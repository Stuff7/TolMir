const std = @import("std");
const u = @import("utils.zig");
const Archive = @import("archive.zig");

const Allocator = std.mem.Allocator;

const Self = @This();

allocator: Allocator,
step: Step,
cwd_name: []const u8,
cwd: std.fs.Dir,

pub fn init(allocator: Allocator) !Self {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        showUsage(args);
        return error.MissingArgs;
    }

    const cwd_name = try allocator.dupe(u8, findOption(args, "dir") orelse "");
    return Self{
        .allocator = allocator,
        .step = try Step.init(args),
        .cwd_name = cwd_name,
        .cwd = if (cwd_name.len == 0) std.fs.cwd() else try std.fs.cwd().openDir(cwd_name, .{}),
    };
}

pub fn installMods(self: Self) !void {
    const mods_dir = try self.cwd.openDir(u.mods_dir, .{ .iterate = true });
    var mods = mods_dir.iterate();

    while (try mods.next()) |mod| {
        if (mod.kind != .file) continue;

        const path = try std.fs.path.join(self.allocator, &[_][]const u8{
            self.cwd_name,
            u.mods_dir,
            mod.name,
        });
        defer self.allocator.free(path);

        var reader = try Archive.init();
        defer reader.deinit();

        try reader.open(path);

        while (reader.nextEntry()) |entry| {
            try reader.extractToFile(self, entry);
        }

        try reader.close();
    }
}

pub fn deinit(self: Self) void {
    self.allocator.free(self.cwd_name);
}

fn findOption(args: [][:0]u8, comptime name: []const u8) ?[]const u8 {
    for (args, 0..) |arg, i| {
        if (!std.mem.eql(u8, arg, "--" ++ name)) continue;
        if (i + 1 < args.len) return args[i + 1];
        return null;
    }
    return null;
}

fn showUsage(args: [][:0]u8) void {
    std.debug.print(u.ansi("Usage: ", "1") ++ "{s} " ++ u.ansi("[steps] ", "92") ++ u.ansi("[options]\n", "93") ++
        "\n" ++
        u.ansi("Steps:\n  ", "92") ++
        u.ansi("install     Install all enabled mods\n  ", "92") ++
        u.ansi("mount       Make Skyrim actually 'see' the mods\n", "92") ++
        "\n" ++
        u.ansi("Options:\n  ", "93") ++
        u.ansi("--dir       Working directory, everything TolMir does will be handled here (default: .)\n", "93") ++
        "\n", .{
        args[0],
    });
}

const Step = enum {
    install,
    mount,

    pub fn init(args: [][:0]u8) !Step {
        inline for (@typeInfo(Step).@"enum".fields) |f| {
            if (std.mem.eql(u8, args[1], f.name)) return @field(Step, f.name);
        }
        std.debug.print(u.ansi("Unknown step: ", "1") ++ "{s}\n", .{args[1]});
        showUsage(args);
        return error.UnknownStep;
    }
};
