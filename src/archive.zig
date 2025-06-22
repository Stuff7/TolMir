const std = @import("std");
const State = @import("state.zig");
const u = @import("utils.zig");
const c = @cImport({
    @cInclude("archive.h");
    @cInclude("archive_entry.h");
});

const fs = std.fs;
const Allocator = std.mem.Allocator;
const print = std.debug.print;

const Self = @This();

archive: *c.struct_archive,
stem: []const u8,

pub fn open(path: []const u8, name: []const u8) !Self {
    const a = c.archive_read_new();
    if (a == null) return error.ArchiveReaderInit;

    var self = Self{ .archive = a.?, .stem = name };

    if (c.archive_read_support_format_zip(self.archive) != 0) return error.ZipInit;
    if (c.archive_read_support_format_rar(self.archive) != 0) return error.RarInit;
    if (c.archive_read_support_format_7zip(self.archive) != 0) return error.Init7z;
    if (c.archive_read_support_filter_all(self.archive) != 0) return error.ArchiveFilterInit;

    try self.assert(c.archive_read_open_filename(self.archive, path.ptr, 10240));

    return self;
}

pub fn close(self: *Self) !void {
    try self.assert(c.archive_read_close(self.archive));
    _ = c.archive_read_free(self.archive);
}

pub fn nextEntry(self: *Self) ?Entry {
    var entry: ?*c.struct_archive_entry = null;
    self.assert(c.archive_read_next_header(self.archive, &entry)) catch return null;
    return Entry{ .entry = entry.? };
}

pub fn skipEntryData(self: Self) void {
    _ = c.archive_read_data_skip(self.archive);
}

pub fn extractToFile(self: Self, state: State, indent: comptime_int, out_path: []const u8, base: []const u8) !void {
    const name = try u.sanitizePath(out_path);
    const path = try fs.path.join(state.allocator, &[_][]const u8{ base, name });
    defer state.allocator.free(path);

    if (fs.path.dirname(path)) |dir| try fs.cwd().makePath(dir);

    const out = try fs.cwd().createFile(path, .{ .truncate = true, .read = false });
    defer out.close();

    const writer = out.writer();
    var buffer: [8192]u8 = undefined;

    print(" " ** indent ++ u.ansi("Inflating:\n", "1") ++
        " " ** (indent + 2) ++ u.ansi("{s}\n", "93") ++
        " " ** (indent + 2) ++ u.ansi("{s}\n", "94"), .{ name, path });
    while (true) {
        const size = c.archive_read_data(self.archive, &buffer, buffer.len);
        if (size == 0) break;
        if (size < 0) return error.ArchiveReadError;
        try writer.writeAll(buffer[0..@intCast(size)]);
    }
}

fn assert(self: Self, err: c_int) !void {
    if (err == 0) return;

    const msg = c.archive_error_string(self.archive);
    if (@intFromPtr(msg) != 0) {
        print("[libarchive]: {s}\n", .{std.mem.span(msg)});
    }

    return error.ArchiveError;
}

pub const Entry = struct {
    entry: *c.struct_archive_entry,

    pub fn pathName(self: @This()) []const u8 {
        return std.mem.span(c.archive_entry_pathname(self.entry));
    }

    pub fn fileType(self: @This()) FileType {
        return @enumFromInt(c.archive_entry_filetype(self.entry));
    }

    pub const FileType = enum(u16) {
        unknown = 0,
        socket = 0o140000, // AE_IFSOCK
        symlink = 0o120000, // AE_IFLNK
        regular = 0o100000, // AE_IFREG
        block = 0o060000, // AE_IFBLK
        directory = 0o040000, // AE_IFDIR
        character = 0o020000, // AE_IFCHR
        fifo = 0o010000, // AE_IFIFO,
    };
};
