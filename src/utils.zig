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

pub fn clearTerminal() void {
    print("\x1b[3J\x1b[H\x1b[2J", .{});
}

pub fn replacePathSep(allocator: Allocator, source: []const u8) ![]const u8 {
    return try std.mem.replaceOwned(u8, allocator, source, "\\", "/");
}

pub fn escapeShellArg(allocator: Allocator, path: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    try result.append('"');

    for (path) |c| {
        if (c == '"') {
            try result.appendSlice("\\\"");
        } else {
            try result.append(c);
        }
    }

    try result.append('"');

    return result.toOwnedSlice();
}

pub fn renderImage1337(allocator: Allocator, path: []const u8, width: []const u8) !void {
    var file = std.fs.cwd().openFile(path, .{}) catch {
        print(ansi("image: ", "2") ++ ansi("{s} ", "1") ++ ansi("NOT FOUND\n", "1;93"), .{path});
        return;
    };
    defer file.close();

    const file_size = try file.getEndPos();
    const file_data = try allocator.alloc(u8, file_size);
    defer allocator.free(file_data);

    _ = try file.readAll(file_data);

    const base64_len = std.base64.standard.Encoder.calcSize(file_size);
    const base64_data = try allocator.alloc(u8, base64_len);
    defer allocator.free(base64_data);

    const data = std.base64.standard.Encoder.encode(base64_data, file_data);

    const ESC = "\x1b";
    const BEL = "\x07";

    const stdout = std.io.getStdOut().writer();

    try stdout.print(
        "{s}]1337;File=name={s};width={s};preserveAspectRatio=0;inline=1:{s}{s}",
        .{ ESC, path, width, data, BEL },
    );
}

pub fn trimWhitespace(s: []const u8) []const u8 {
    var start: usize = 0;
    var end: usize = s.len;

    while (start < end and std.ascii.isWhitespace(s[start])) : (start += 1) {}
    while (end > start and std.ascii.isWhitespace(s[end - 1])) : (end -= 1) {}

    return s[start..end];
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

pub fn replaceXmlEntities(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = input;

    const entities = [_]struct {
        entity: []const u8,
        replacement: []const u8,
    }{
        .{ .entity = "&apos;", .replacement = "'" },
        .{ .entity = "&quot;", .replacement = "\"" },
        .{ .entity = "&lt;", .replacement = "<" },
        .{ .entity = "&gt;", .replacement = ">" },
    };

    for (entities) |e| {
        const temp = try std.mem.replaceOwned(u8, allocator, result, e.entity, e.replacement);
        if (result.ptr != input.ptr) allocator.free(result); // only free if it's not the original input
        result = temp;
    }

    return result;
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

pub fn makeRelativeToCwd(allocator: std.mem.Allocator, abs: []const u8) ?[]const u8 {
    const cwd = std.fs.cwd().realpathAlloc(allocator, ".") catch return null;

    if (std.mem.startsWith(u8, abs, cwd)) {
        const base_with_slash = if (std.mem.endsWith(u8, cwd, "/"))
            cwd
        else
            std.fmt.allocPrint(allocator, "{s}/", .{cwd}) catch return null;
        defer allocator.free(base_with_slash);

        if (std.mem.startsWith(u8, abs, base_with_slash)) {
            return abs[base_with_slash.len..];
        }
    }
    return null;
}

pub fn symlinkRecursive(
    allocator: Allocator,
    indent: ?comptime_int,
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
                if (indent) |ind| {
                    print(" " ** ind ++ ansi("Symlink:\n", "1") ++
                        " " ** (ind + 2) ++ ansi("{s}\n", "96") ++
                        " " ** (ind + 2) ++ ansi("{s}\n", "92"), .{ source_full_path, dest_full_path });
                }

                fs.cwd().symLink(source_full_path, dest_full_path, .{}) catch |err| switch (err) {
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
    indent: comptime_int,
    src_path: []const u8,
    dst_path: []const u8,
) !void {
    try fs.cwd().makePath(fs.path.dirname(dst_path) orelse ".");

    print(" " ** indent ++ ansi("Symlink:\n", "1") ++
        " " ** (indent + 2) ++ ansi("{s}\n", "96") ++
        " " ** (indent + 2) ++ ansi("{s}\n", "92"), .{ src_path, dst_path });

    fs.cwd().symLink(src_path, dst_path, .{}) catch |err| switch (err) {
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

pub fn fileExists(path: []const u8) bool {
    return if (fs.cwd().statFile(path)) |_| true else |_| false;
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

pub fn isGameDir(path: []const u8) bool {
    const dirs = [_][]const u8{
        "data", "skse", "textures", "meshes", "interface", "scripts", "plugins",
    };

    inline for (dirs) |dir| {
        if (std.ascii.eqlIgnoreCase(path, dir)) return true;
    }

    return false;
}
