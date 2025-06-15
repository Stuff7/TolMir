const std = @import("std");
const State = @import("state.zig");

const Allocator = std.mem.Allocator;
const print = std.debug.print;
const fs = std.fs;

pub const installs_dir = "installs";
pub const inflated_dir = "inflated";
pub const mods_dir = "mods";

pub fn ansi(comptime txt: []const u8, comptime styles: []const u8) []const u8 {
    return "\x1b[" ++ styles ++ "m" ++ txt ++ "\x1b[0m";
}

/// Caller needs to check if a free is necessary on their end.
pub fn utf16ToUtf8(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    if (input.len < 2 or input[0] != 0xFF or input[1] != 0xFE) {
        return input;
    }

    var i: usize = 2;
    var out = std.ArrayList(u8).init(allocator);
    defer out.deinit();

    while (i + 1 < input.len) {
        const lo = input[i];
        const hi = input[i + 1];
        const code_unit: u16 = (@as(u16, hi) << 8) | lo;
        i += 2;

        if (code_unit >= 0xD800 and code_unit <= 0xDBFF) {
            if (i + 1 >= input.len) return error.InvalidSurrogatePair;
            const lo_lo = input[i];
            const lo_hi = input[i + 1];
            const low_unit: u16 = (@as(u16, lo_hi) << 8) | lo_lo;
            i += 2;

            if (low_unit < 0xDC00 or low_unit > 0xDFFF) return error.InvalidSurrogatePair;

            const high = code_unit - 0xD800;
            const low = low_unit - 0xDC00;
            const codepoint: u21 = @intCast(0x10000 + (@as(u32, high) << 10 | low));

            var cbuf: [4]u8 = undefined;
            try out.appendSlice(cbuf[0..try std.unicode.utf8Encode(codepoint, &cbuf)]);
        } else if (code_unit >= 0xDC00 and code_unit <= 0xDFFF) {
            return error.UnexpectedLowSurrogate;
        } else {
            var cbuf: [4]u8 = undefined;
            try out.appendSlice(cbuf[0..try std.unicode.utf8Encode(code_unit, &cbuf)]);
        }
    }

    return try out.toOwnedSlice();
}

pub fn stripInitialXmlComments(xml: []const u8) []const u8 {
    var pos: usize = 0;

    while (pos < xml.len) {
        while (pos < xml.len and std.ascii.isWhitespace(xml[pos])) {
            pos += 1;
        }

        if (pos + 4 <= xml.len and std.mem.eql(u8, xml[pos .. pos + 4], "<!--")) {
            pos += 4;

            while (pos + 3 <= xml.len) {
                if (std.mem.eql(u8, xml[pos .. pos + 3], "-->")) {
                    pos += 3;
                    break;
                }
                pos += 1;
            } else {
                break;
            }
        } else {
            break;
        }
    }

    return xml[pos..];
}

pub fn symlinkRecursive(
    allocator: Allocator,
    indent: comptime_int,
    src_path: []const u8,
    dst_path: []const u8,
) !void {
    try fs.cwd().makePath(src_path);

    var source_dir = try fs.cwd().openDir(src_path, .{ .iterate = true });
    defer source_dir.close();

    try fs.cwd().makePath(dst_path);

    var dest_dir = try fs.cwd().openDir(dst_path, .{});
    defer dest_dir.close();

    var walker = try source_dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        const source_full_path = try fs.path.join(allocator, &[_][]const u8{ src_path, entry.path });
        defer allocator.free(source_full_path);

        const dest_full_path = try fs.path.join(allocator, &[_][]const u8{ dst_path, entry.path });
        defer allocator.free(dest_full_path);

        switch (entry.kind) {
            .file => {
                print(" " ** indent ++ ansi("Symlink:\n", "1") ++
                    " " ** (indent + 2) ++ ansi("{s}\n", "96") ++
                    " " ** (indent + 2) ++ ansi("{s}\n", "92"), .{ source_full_path, dest_full_path });

                const source_absolute = try fs.cwd().realpathAlloc(allocator, source_full_path);
                defer allocator.free(source_absolute);

                fs.cwd().symLink(source_absolute, dest_full_path, .{}) catch |err| switch (err) {
                    error.PathAlreadyExists => {},
                    else => return err,
                };
            },
            .directory => {
                fs.cwd().makePath(dest_full_path) catch |err| switch (err) {
                    error.PathAlreadyExists => {},
                    else => return err,
                };
            },
            else => {},
        }
    }
}

pub fn symlinkFile(
    allocator: Allocator,
    indent: comptime_int,
    src_path: []const u8,
    dst_path: []const u8,
) !void {
    try fs.cwd().makePath(fs.path.dirname(dst_path) orelse ".");

    const source_absolute = try fs.cwd().realpathAlloc(allocator, src_path);
    defer allocator.free(source_absolute);

    print(" " ** indent ++ ansi("Symlink:\n", "1") ++
        " " ** (indent + 2) ++ ansi("{s}\n", "96") ++
        " " ** (indent + 2) ++ ansi("{s}\n", "92"), .{ source_absolute, dst_path });

    fs.cwd().symLink(source_absolute, dst_path, .{}) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
}

pub fn sanitizePath(raw_path: []const u8) ![]const u8 {
    if (raw_path.len > 0 and raw_path[0] == '/') {
        return error.AbsolutePathNotAllowed;
    }

    if (raw_path.len == 0) {
        return error.EmptyPathNotAllowed;
    }

    var it = std.mem.tokenizeScalar(u8, raw_path, '/');
    while (it.next()) |part| {
        if (std.mem.eql(u8, part, "..")) {
            return error.PathTraversalDetected;
        }
        if (std.mem.eql(u8, part, ".")) {
            return error.RelativePathComponent;
        }
        if (part.len == 0) {
            return error.MalformedPath;
        }
        if (part[0] == '.') {
            return error.HiddenDotfileBlocked;
        }
    }

    return raw_path;
}

pub fn dirExists(path: []const u8) bool {
    const stat = fs.cwd().statFile(path) catch return false;
    return stat.kind == .directory;
}

pub fn initEnum(T: type, input: []const u8, default: anytype) !T {
    const fields = @typeInfo(T).@"enum".fields;
    inline for (fields) |f| {
        if (std.mem.eql(u8, f.name, input)) {
            return @field(T, f.name);
        }
    }

    return default;
}
