const std = @import("std");
const u = @import("utils.zig");
const Fomod = @import("fomod/walker.zig");
const LoadOrder = @import("loadorder.zig");
const Archive = @import("archive.zig");

const fs = std.fs;
const Allocator = std.mem.Allocator;
const print = std.debug.print;

const Self = @This();

allocator: Allocator,
step: Step,
cfg: Config,
args: [][:0]u8,
loadorder: LoadOrder,

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
        .loadorder = try LoadOrder.init(allocator, cfg.cwdir),
    };
}

pub fn updateConfig(self: *Self) !void {
    const args = self.args[2..];
    if (args.len < 2) {
        print(
            u.ansi("cwd:       ", "1") ++ u.ansi("{s}\n", "93") ++
                u.ansi("gamedir:   ", "1") ++ u.ansi("{s}\n", "93") ++
                u.ansi("gamedata:  ", "1") ++ u.ansi("{s}\n", "93"),
            .{ self.cfg.cwd, self.cfg.gamedir, self.cfg.gamedata },
        );
        return;
    }

    var i: usize = 0;
    while (i < args.len) : (i += 2) {
        const key = args[i];
        const val = args[i + 1];
        const v = std.mem.trimEnd(u8, val, "/");
        print(u.ansi("{s}: ", "1") ++ u.ansi("{s}\n", "93"), .{ key, v });

        if (std.mem.eql(u8, key, "cwd")) {
            self.cfg.cwd = v;
            self.cfg.cwdir = if (v.len == 0) fs.cwd() else try fs.cwd().openDir(v, .{});
        } else if (std.mem.eql(u8, key, "gamedir")) {
            self.cfg.gamedir = v;
        } else if (std.mem.eql(u8, key, "gamedata")) {
            self.cfg.gamedata = v;
        }
    }
}

pub fn isMissingConfig(self: Self) bool {
    if (self.step != .set and self.cfg.gamedata.len == 0 and self.cfg.gamedir.len == 0) {
        print(u.ansi("You need to set the gamedata and gamedir directories first\n", "1"), .{});
        showUsage(self.args);
        return true;
    }
    return false;
}

pub fn installMods(self: *Self) !void {
    var arena = std.heap.ArenaAllocator.init(self.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var mods_dir = try self.cfg.cwdir.openDir(u.mods_dir, .{ .iterate = true });
    defer mods_dir.close();
    var mods = mods_dir.iterate();

    while (try mods.next()) |mod| {
        const stem = fs.path.stem(mod.name);
        if (mod.kind != .file) continue;

        const in_path = try self.join(allocator, .{ u.mods_dir, mod.name });

        const inflated_path = try self.join(allocator, .{ u.inflated_dir, stem });
        const is_inflated = u.dirExists(inflated_path);

        if (!is_inflated) {
            print(u.ansi("Processing mod: ", "1") ++ u.ansi("{s}\n", "92"), .{inflated_path});
            var root = try Archive.getRootDir(allocator, in_path, stem);
            if (root) |r| {
                if (u.isGameDir(r)) root = null;
            }

            var reader = try Archive.open(in_path, stem);
            try self.loadorder.appendMod(stem, true);
            while (reader.nextEntry()) |entry| {
                if (entry.fileType() != .regular) continue;
                var out_path = entry.pathName();
                if (root) |r| out_path = out_path[r.len + 1 ..];

                const maybe_data = out_path[0 .. "Data".len + 1];

                if (std.ascii.eqlIgnoreCase(out_path, "fomod/moduleconfig.xml")) {
                    out_path = try std.ascii.allocLowerString(allocator, out_path);
                } else if (std.ascii.eqlIgnoreCase(maybe_data, "data/") and !std.mem.eql(u8, maybe_data, "Data/")) {
                    out_path = try std.fmt.allocPrintZ(allocator, "Data/{s}", .{out_path[maybe_data.len..]});
                }

                if (!is_inflated) try reader.extractToFile(self.*, 2, out_path, inflated_path);
            }
            try reader.close();
        }

        const fomod_file = try fs.path.join(allocator, &[_][]const u8{ inflated_path, "fomod", "moduleconfig.xml" });
        const data_dir = try fs.path.join(allocator, &[_][]const u8{ inflated_path, "Data" });

        const has_fomod = u.fileExists(fomod_file);

        const install_path = if (u.fileExists(fomod_file) or u.dirExists(data_dir))
            try self.join(allocator, .{ u.installs_dir, stem })
        else
            try self.join(allocator, .{ u.installs_dir, stem, "Data" });

        if (u.dirExists(install_path)) continue;

        print(u.ansi("Installing mod: ", "1") ++ u.ansi("{s}\n", "92"), .{install_path});
        if (has_fomod) {
            var fomod = try Fomod.init(allocator, fomod_file, inflated_path, install_path);
            try fomod.runInstaller();
        } else {
            try u.symlinkRecursive(self.allocator, 2, install_path, inflated_path, install_path);
            const skse_path = try fs.path.join(allocator, &[_][]const u8{ install_path, "skse64_loader.exe" });
            if (u.fileExists(skse_path)) {
                const launcher_path = try fs.path.join(allocator, &[_][]const u8{ install_path, "SkyrimSELauncher.exe" });
                try u.symlinkFile(2, skse_path, launcher_path);
            }
        }
    }

    try self.loadorder.serialize();
    try self.writePluginsTxt();
}

pub fn writePluginsTxt(self: Self) !void {
    const path = try fs.path.join(self.allocator, &[_][]const u8{ self.cfg.gamedata, "Plugins.txt" });
    defer self.allocator.free(path);
    var plugins = try fs.createFileAbsolute(path, .{});
    defer plugins.close();
    const w = plugins.writer();

    var it = self.loadorder.mods.iterator();
    while (it.next()) |entry| {
        if (!entry.value_ptr.*) continue;
        const dirpath = try self.join(null, .{ u.installs_dir, entry.key_ptr.*, "Data" });
        defer self.allocator.free(dirpath);

        var dir = fs.openDirAbsolute(dirpath, .{ .iterate = true }) catch continue;
        defer dir.close();
        var dit = dir.iterate();
        while (try dit.next()) |e| {
            if ((e.kind != .sym_link and e.kind != .file) or !std.mem.endsWith(u8, e.name, ".esp")) continue;
            try std.fmt.format(w, "*{s}\n", .{fs.path.basename(e.name)});
        }
    }
}

pub fn writeMountScripts(self: @This()) !void {
    var arena = std.heap.ArenaAllocator.init(self.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const orig_path = try u.escapeShellArg(allocator, try std.fmt.allocPrint(allocator, "{s}.orig", .{self.cfg.gamedir}));

    const stg_dir = try u.escapeShellArg(allocator, try self.join(allocator, .{"staging"}));
    const lower_dir = try u.escapeShellArg(allocator, try self.join(allocator, .{"merged"}));
    const upper_path = try u.escapeShellArg(allocator, try self.join(allocator, .{ "overlay", "upper" }));
    const work_path = try u.escapeShellArg(allocator, try self.join(allocator, .{ "overlay", "work" }));
    const merged_path = try u.escapeShellArg(allocator, self.cfg.gamedir);

    var mount_buf = std.ArrayList(u8).init(allocator);
    const mount_w = mount_buf.writer();

    var unmount_buf = std.ArrayList(u8).init(allocator);
    const unmount_w = unmount_buf.writer();

    try mount_w.writeAll("#!/bin/bash\n\nset -e\n\n");
    try mount_w.print("mv \\\n{s} \\\n{s}\n\n", .{ merged_path, orig_path });
    try mount_w.print("rm -rf {s}\n", .{lower_dir});
    try mount_w.print("mkdir -p \\\n{s} \\\n{s} \\\n{s} \\\n{s} \\\n{s}\n\n", .{
        upper_path, work_path, merged_path, stg_dir, lower_dir,
    });

    try mount_w.writeAll("cp -a \\\n");
    const keys = self.loadorder.mods.keys();
    const vals = self.loadorder.mods.values();
    for (keys, vals) |k, v| {
        if (!v) continue;
        try mount_w.print("{s}/* \\\n", .{
            try u.escapeShellArg(allocator, try self.join(allocator, .{ u.installs_dir, k })),
        });
    }
    try mount_w.print("{s}/* \\\n", .{stg_dir});
    try mount_w.print("{s}\n\n", .{lower_dir});

    try mount_w.print(
        "sudo mount -t overlay overlay -o \\\nlowerdir+={s},\\\nlowerdir+={s},\\\n",
        .{ lower_dir, orig_path },
    );
    try mount_w.print("upperdir={s},\\\n", .{upper_path});
    try mount_w.print("workdir={s} \\\n", .{work_path});
    try mount_w.print("{s}\n", .{merged_path});

    try unmount_w.writeAll("#!/bin/bash\n\nset -e\n\n");
    try unmount_w.print("sudo umount {s}\n", .{merged_path});
    try unmount_w.print("sudo rm -rf {s}\n", .{merged_path});
    try unmount_w.print("mv \\\n{s} \\\n{s}\n", .{ orig_path, merged_path });

    const overlay_path = try u.escapeShellArg(allocator, try self.join(allocator, .{"overlay"}));
    try unmount_w.print("cp -a {s}/* {s}\n", .{ upper_path, stg_dir });
    try unmount_w.print("rm -rf {s}\n", .{lower_dir});
    try unmount_w.print("sudo rm -rf {s}\n", .{overlay_path});

    const mount_sh = try self.join(allocator, .{"mount.sh"});
    try writeFile(mount_sh, mount_buf.items);
    const unmount_sh = try self.join(allocator, .{"unmount.sh"});
    try writeFile(unmount_sh, unmount_buf.items);

    try self.writePluginsTxt();

    print("Mount/unmount scripts created.\n" ++
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

pub fn showUsage(args: [][:0]u8) void {
    print(u.ansi("Usage: ", "1") ++ "{s} " ++ u.ansi("[steps] ", "92") ++
        "\n" ++
        u.ansi("Steps:\n  ", "92") ++
        u.ansi("help               Show this message\n  ", "92") ++
        u.ansi("set ", "92") ++ u.ansi("[Key] [Value]  ", "93") ++ u.ansi("Sets config key to value\n  ", "92") ++
        u.ansi("install            Install all enabled mods\n  ", "92") ++
        u.ansi("mount              Generate shell scripts to mount overlay over Skyrim directory\n  ", "92") ++
        "\n" ++
        u.ansi("Key:\n  ", "93") ++
        u.ansi("cwd [dir]         Working directory where mods will be managed\n  ", "93") ++
        u.ansi("gamedir [dir]     Game root directory\n  ", "93") ++
        u.ansi("gamedata [dir]    Game data directory (normally in AppData)\n  ", "93") ++
        "\n", .{
        args[0],
    });
}

fn join(self: Self, allocator: ?Allocator, paths: anytype) ![:0]const u8 {
    const alloc = allocator orelse self.allocator;
    var ps: [paths.len + 1][]const u8 = undefined;
    ps[0] = try fs.cwd().realpathAlloc(alloc, self.cfg.cwd);
    defer alloc.free(ps[0]);
    inline for (paths, 1..) |p, i| {
        ps[i] = p;
    }

    return fs.path.joinZ(alloc, &ps);
}

const Step = enum {
    help,
    set,
    install,
    mount,

    pub fn init(args: [][:0]u8) !Step {
        inline for (@typeInfo(Step).@"enum".fields) |f| {
            if (std.mem.eql(u8, args[1], f.name)) return @field(Step, f.name);
        }
        print(u.ansi("Unknown step: ", "1") ++ "{s}\n", .{args[1]});
        showUsage(args);
        return error.UnknownStep;
    }
};

const Config = struct {
    allocator: Allocator,
    contents: []const u8 = "",
    cwdir: fs.Dir = fs.cwd(),
    cwd: []const u8 = "",
    gamedir: []const u8 = "",
    gamedata: []const u8 = "",

    pub fn init(allocator: Allocator, cwd_path: []const u8, game_dir: []const u8, gamedata: []const u8, contents: []const u8) !@This() {
        const cwd = if (cwd_path.len == 0) fs.cwd() else try fs.cwd().openDir(cwd_path, .{});

        return @This(){
            .allocator = allocator,
            .contents = contents,
            .cwdir = cwd,
            .cwd = cwd_path,
            .gamedir = game_dir,
            .gamedata = gamedata,
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
        var gamedata: ?[]const u8 = null;

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
                } else if (std.mem.eql(u8, key, "gamedata")) {
                    gamedata = value;
                }
            }
        }

        return try @This().init(
            allocator,
            cwd orelse return error.MissingCwdField,
            game_dir orelse return error.MissingGameDirField,
            gamedata orelse return error.MissingGameDataField,
            contents,
        );
    }

    pub fn serialize(self: @This()) !void {
        const file = try std.fs.cwd().createFile("tolmir.ini", .{});
        defer file.close();

        const writer = file.writer();
        try writer.print(
            \\cwd={s}
            \\gamedir={s}
            \\gamedata={s}
        , .{ self.cwd, self.gamedir, self.gamedata });
    }
};
