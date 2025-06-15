const std = @import("std");
const u = @import("utils.zig");
const LoadOrder = @import("loadorder.zig");
const EspMap = @import("espmap.zig");
const Archive = @import("archive.zig");

const fs = std.fs;
const Allocator = std.mem.Allocator;

const Self = @This();

allocator: Allocator,
step: Step,
cwd_name: []const u8,
cwd: fs.Dir,
loadorder: LoadOrder,
espmap: EspMap,

pub fn init(allocator: Allocator) !Self {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        showUsage(args);
        return error.MissingArgs;
    }

    const cwd_name = try allocator.dupe(u8, findOption(args, "dir") orelse "");
    const cwd = if (cwd_name.len == 0) fs.cwd() else try fs.cwd().openDir(cwd_name, .{});
    return Self{
        .allocator = allocator,
        .step = try Step.init(args),
        .cwd_name = cwd_name,
        .cwd = cwd,
        .loadorder = try LoadOrder.init(allocator, cwd),
        .espmap = try EspMap.init(allocator, cwd),
    };
}

pub fn installMods(self: *Self) !void {
    var mods_dir = try self.cwd.openDir(u.mods_dir, .{ .iterate = true });
    defer mods_dir.close();
    var mods = mods_dir.iterate();

    while (try mods.next()) |mod| {
        const stem = fs.path.stem(mod.name);
        if (mod.kind != .file) continue;

        const esp_cached = self.espmap.map.contains(stem);

        const in_path = try self.join(.{ u.mods_dir, mod.name });
        defer self.allocator.free(in_path);

        const out_path = try self.join(.{ u.inflated_dir, stem });
        defer self.allocator.free(out_path);
        const is_inflated = u.dirExists(out_path);

        var has_fomod = false;
        var has_data = false;

        if (!is_inflated or !esp_cached) {
            std.debug.print(u.ansi("Processing mod: ", "1") ++ u.ansi("{s}\n", "92"), .{out_path});
            var reader = try Archive.open(in_path, stem);
            try self.loadorder.appendMod(stem, true);
            while (reader.nextEntry()) |entry| {
                const name = entry.pathName();

                if (std.mem.eql(u8, name, "fomod/ModConfig.xml")) {
                    has_fomod = true;
                } else if (std.mem.eql(u8, name, "Data")) {
                    has_data = true;
                }

                if (!is_inflated) try reader.extractToFile(self.*, 2, entry, out_path);
                if (esp_cached) continue;
                try self.espmap.appendEsp(stem, name);
            }
            try reader.close();
        }

        const install_path = if (has_fomod or has_data)
            try self.join(.{ u.installs_dir, stem })
        else
            try self.join(.{ u.installs_dir, stem, "Data" });
        defer self.allocator.free(install_path);

        if (u.dirExists(install_path)) return;

        std.debug.print(u.ansi("Installing mod: ", "1") ++ u.ansi("{s}\n", "92"), .{install_path});
        if (has_fomod) {
            // TODO: interactive mod install
        } else {
            try u.symlinkRecursive(self.allocator, 2, out_path, install_path);
        }
    }

    try self.loadorder.serialize();
    try self.espmap.serialize();
    try self.writePluginsTxt();
}

pub fn writePluginsTxt(self: Self) !void {
    var plugins = try self.cwd.createFile("Plugins.txt", .{});
    defer plugins.close();
    const w = plugins.writer();

    var it = self.loadorder.mods.iterator();
    while (it.next()) |entry| {
        if (!entry.value_ptr.*) continue;
        try std.fmt.format(w, "*{s}\n", .{entry.key_ptr.*});
    }
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.cwd_name);
    self.espmap.deinit();
    self.loadorder.deinit();
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

fn join(self: Self, paths: anytype) ![]const u8 {
    var ps: [paths.len + 1][]const u8 = undefined;
    ps[0] = self.cwd_name;
    inline for (paths, 1..) |p, i| {
        ps[i] = p;
    }
    return fs.path.join(self.allocator, &ps);
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
