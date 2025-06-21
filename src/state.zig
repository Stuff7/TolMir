const std = @import("std");
const u = @import("utils.zig");
const Fomod = @import("fomod/walker.zig");
const LoadOrder = @import("loadorder.zig");
const EspMap = @import("espmap.zig");
const Archive = @import("archive.zig");

const fs = std.fs;
const Allocator = std.mem.Allocator;

const Self = @This();

allocator: Allocator,
step: Step,
cfg: Config,
args: [][:0]u8,
loadorder: LoadOrder,
espmap: EspMap,

pub fn init(allocator: Allocator) !Self {
    const args = try std.process.argsAlloc(allocator);
    errdefer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        showUsage(args);
        return error.MissingArgs;
    }

    const cfg = Config.deserialize(allocator) catch Config{ .allocator = allocator };
    return Self{
        .allocator = allocator,
        .step = try Step.init(args),
        .cfg = cfg,
        .args = args,
        .loadorder = try LoadOrder.init(allocator, cfg.cwd),
        .espmap = try EspMap.init(allocator, cfg.cwd),
    };
}

pub fn updateConfig(self: *Self) !void {
    const args = self.args[2..];
    if (args.len < 2) {
        std.debug.print(
            u.ansi("cwd:     ", "1") ++ u.ansi("{s}\n", "93") ++
                u.ansi("gamedir: ", "1") ++ u.ansi("{s}\n", "93"),
            .{ self.cfg.cwd_path, self.cfg.game_dir },
        );
        return;
    }

    var i: usize = 0;
    while (i < args.len) : (i += 2) {
        const key = args[i];
        const val = args[i + 1];
        const v = std.mem.trimEnd(u8, val, "/");
        std.debug.print(u.ansi("{s}: ", "1") ++ u.ansi("{s}\n", "93"), .{ key, v });

        if (std.mem.eql(u8, key, "cwd")) {
            self.cfg.cwd_path = v;
            self.cfg.cwd = if (v.len == 0) fs.cwd() else try fs.cwd().openDir(v, .{});
        } else if (std.mem.eql(u8, key, "gamedir")) {
            self.cfg.game_dir = v;
        }
    }
}

pub fn installMods(self: *Self) !void {
    var arena = std.heap.ArenaAllocator.init(self.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var mods_dir = try self.cfg.cwd.openDir(u.mods_dir, .{ .iterate = true });
    defer mods_dir.close();
    var mods = mods_dir.iterate();

    while (try mods.next()) |mod| {
        const stem = fs.path.stem(mod.name);
        if (mod.kind != .file) continue;

        const esp_cached = self.espmap.map.contains(stem);

        const in_path = try self.join(allocator, .{ u.mods_dir, mod.name });

        const inflated_path = try self.join(allocator, .{ u.inflated_dir, stem });
        const is_inflated = u.dirExists(inflated_path);

        if (!is_inflated or !esp_cached) {
            std.debug.print(u.ansi("Processing mod: ", "1") ++ u.ansi("{s}\n", "92"), .{inflated_path});
            var reader = try Archive.open(in_path, stem);
            try self.loadorder.appendMod(stem, true);
            while (reader.nextEntry()) |entry| {
                const name = entry.pathName();

                if (!is_inflated) try reader.extractToFile(self.*, 2, entry, inflated_path);
                if (esp_cached) continue;
                try self.espmap.appendEsp(stem, name);
            }
            try reader.close();
        }

        const fomod_file = try fs.path.join(allocator, &[_][]const u8{ inflated_path, "fomod", "ModuleConfig.xml" });
        const data_dir = try fs.path.join(allocator, &[_][]const u8{ inflated_path, "Data" });

        const has_fomod = if (fs.cwd().statFile(fomod_file)) |_| true else |_| false;
        const has_data = u.dirExists(data_dir);

        const install_path = if (has_fomod or has_data)
            try self.join(allocator, .{ u.installs_dir, stem })
        else
            try self.join(allocator, .{ u.installs_dir, stem, "Data" });

        if (u.dirExists(install_path)) continue;

        std.debug.print(u.ansi("Installing mod: ", "1") ++ u.ansi("{s}\n", "92"), .{install_path});
        if (has_fomod) {
            var fomod = try Fomod.init(allocator, fomod_file, inflated_path, install_path);
            try fomod.runInstaller();
        } else {
            try u.symlinkRecursive(self.allocator, 2, inflated_path, install_path);
        }
    }

    try self.loadorder.serialize();
    try self.espmap.serialize();
    try self.writePluginsTxt();
}

pub fn writePluginsTxt(self: Self) !void {
    var plugins = try self.cfg.cwd.createFile("Plugins.txt", .{});
    defer plugins.close();
    const w = plugins.writer();

    var it = self.loadorder.mods.iterator();
    while (it.next()) |entry| {
        if (!entry.value_ptr.*) continue;
        try std.fmt.format(w, "*{s}\n", .{entry.key_ptr.*});
    }
}

pub fn writeMountScripts(self: @This()) !void {
    var arena = std.heap.ArenaAllocator.init(self.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const orig_path = try u.escapeShellArg(allocator, try std.fmt.allocPrint(allocator, "{s}.orig", .{self.cfg.game_dir}));

    if (u.makeRelativeToCwd(allocator, try self.join(allocator, .{"overlay"}))) |p|
        try u.nukeDir(p);

    const upper_path = try u.escapeShellArg(allocator, try self.join(allocator, .{ "overlay", "upper" }));
    const work_path = try u.escapeShellArg(allocator, try self.join(allocator, .{ "overlay", "work" }));
    const merged_path = try u.escapeShellArg(allocator, self.cfg.game_dir);

    var mount_buf = std.ArrayList(u8).init(allocator);
    const mount_w = mount_buf.writer();

    var unmount_buf = std.ArrayList(u8).init(allocator);
    const unmount_w = unmount_buf.writer();

    try mount_w.writeAll("#!/bin/bash\n\nset -e\n\n");
    try mount_w.print("mv \\\n{s} \\\n{s}\n\n", .{ merged_path, orig_path });
    try mount_w.print("mkdir -p \\\n{s} \\\n{s} \\\n{s}\n\n", .{
        upper_path, work_path, merged_path,
    });

    try mount_w.writeAll("sudo mount -t overlay overlay -o \\\n");

    const keys = self.loadorder.mods.keys();
    const vals = self.loadorder.mods.values();
    var i = keys.len;
    while (i > 0) {
        i -= 1;
        if (!vals[i]) continue;

        const path = try u.escapeShellArg(
            allocator,
            try self.join(allocator, .{ u.installs_dir, keys[i] }),
        );

        try mount_w.print("lowerdir+={s},\\\n", .{path});
    }

    try mount_w.print("lowerdir+={s},\\\n", .{orig_path});
    try mount_w.print("upperdir={s},\\\n", .{upper_path});
    try mount_w.print("workdir={s} \\\n", .{work_path});
    try mount_w.print("{s}\n", .{merged_path});

    try unmount_w.writeAll("#!/bin/bash\n\nset -e\n\n");
    try unmount_w.print("sudo umount {s}\n", .{merged_path});
    try unmount_w.print("sudo rm -rf {s}\n", .{merged_path});
    try unmount_w.print("mv \\\n{s} \\\n{s}\n", .{ orig_path, merged_path });

    const mount_sh = try self.join(allocator, .{"mount.sh"});
    try writeFile(mount_sh, mount_buf.items);
    const unmount_sh = try self.join(allocator, .{"unmount.sh"});
    try writeFile(unmount_sh, unmount_buf.items);

    std.debug.print("Mount/unmount scripts created.\n" ++
        "  Mount with " ++ u.ansi("{s}\n", "1;93") ++
        "  Unmount with " ++ u.ansi("{s}\n", "1;93"), .{ mount_sh, unmount_sh });
}

fn writeFile(path: []const u8, contents: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{
        .read = true,
        .truncate = true,
        .mode = 0o755,
    });
    defer file.close();
    try file.writeAll(contents);
}

pub fn deinit(self: *Self) !void {
    try self.cfg.serialize();
    self.cfg.deinit();
    std.process.argsFree(self.allocator, self.args);
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
    std.debug.print(u.ansi("Usage: ", "1") ++ "{s} " ++ u.ansi("[steps] ", "92") ++
        "\n" ++
        u.ansi("Steps:\n  ", "92") ++
        u.ansi("install            Install all enabled mods\n  ", "92") ++
        u.ansi("mount              Generate shell scripts to mount overlay over Skyrim directory\n  ", "92") ++
        u.ansi("set ", "92") ++ u.ansi("[Key] [Value]  ", "93") ++ u.ansi("Sets config key to value\n", "92") ++
        "\n" ++
        u.ansi("Key:\n  ", "93") ++
        u.ansi("cwd [dir]          Working directory where mods will be managed\n  ", "93") ++
        u.ansi("gamedir [path]     Game root directory\n  ", "93") ++
        "\n", .{
        args[0],
    });
}

fn join(self: Self, allocator: ?Allocator, paths: anytype) ![]const u8 {
    const alloc = allocator orelse self.allocator;
    var ps: [paths.len + 1][]const u8 = undefined;
    ps[0] = try fs.cwd().realpathAlloc(alloc, self.cfg.cwd_path);
    inline for (paths, 1..) |p, i| {
        ps[i] = p;
    }

    return fs.path.joinZ(alloc, &ps);
}

const Step = enum {
    install,
    mount,
    set,

    pub fn init(args: [][:0]u8) !Step {
        inline for (@typeInfo(Step).@"enum".fields) |f| {
            if (std.mem.eql(u8, args[1], f.name)) return @field(Step, f.name);
        }
        std.debug.print(u.ansi("Unknown step: ", "1") ++ "{s}\n", .{args[1]});
        showUsage(args);
        return error.UnknownStep;
    }
};

const Config = struct {
    allocator: Allocator,
    cwd_path: []const u8 = "",
    cwd: fs.Dir = fs.cwd(),
    game_dir: []const u8 = "",
    contents: []const u8 = "",

    pub fn init(allocator: Allocator, cwd_path: []const u8, game_dir: []const u8, contents: []const u8) !@This() {
        const cwd = if (cwd_path.len == 0) fs.cwd() else try fs.cwd().openDir(cwd_path, .{});
        return @This(){
            .allocator = allocator,
            .cwd_path = cwd_path,
            .cwd = cwd,
            .game_dir = game_dir,
            .contents = contents,
        };
    }

    pub fn deinit(self: @This()) void {
        defer self.allocator.free(self.contents);
    }

    pub fn deserialize(allocator: Allocator) !@This() {
        const file = try std.fs.cwd().openFile("tolmir.ini", .{});
        defer file.close();

        const file_size = try file.getEndPos();
        const contents = try allocator.alloc(u8, file_size);

        _ = try file.readAll(contents);

        var cwd: ?[]const u8 = null;
        var game_dir: ?[]const u8 = null;

        var lines = std.mem.splitScalar(u8, contents, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r\n");
            if (trimmed.len == 0) continue;

            if (std.mem.indexOf(u8, trimmed, "=")) |eq_pos| {
                const key = std.mem.trim(u8, trimmed[0..eq_pos], " \t");
                const value = std.mem.trim(u8, trimmed[eq_pos + 1 ..], " \t");

                if (std.mem.eql(u8, key, "cwd")) {
                    cwd = value;
                } else if (std.mem.eql(u8, key, "gamedir")) {
                    game_dir = value;
                }
            }
        }

        const final_cwd = cwd orelse return error.MissingCwdField;
        const final_game_dir = game_dir orelse return error.MissingGameDirField;

        return try @This().init(allocator, final_cwd, final_game_dir, contents);
    }

    pub fn serialize(self: @This()) !void {
        const file = try std.fs.cwd().createFile("tolmir.ini", .{});
        defer file.close();

        const writer = file.writer();
        try writer.print("cwd={s}\n", .{self.cwd_path});
        try writer.print("gamedir={s}\n", .{self.game_dir});
    }
};
