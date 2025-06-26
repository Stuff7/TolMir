const std = @import("std");
const u = @import("../utils.zig");
const Config = @import("config.zig");
const parser = @import("parser.zig");
const CompositeDependency = @import("composite_dependency.zig");
const FileList = @import("file_list.zig");
const StepList = @import("step_list.zig");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const print = std.debug.print;

const Walker = @This();

allocator: Allocator,
in_dir: []const u8,
out_dir: []const u8,
config: Config,
flags: std.StringHashMap([]const u8),
selected_files: ArrayList(FileInstallation),

const FileInstallation = struct {
    source: []const u8,
    destination: ?[]const u8 = null,
    is_folder: bool,
    priority: i32 = 0,
};

pub fn init(allocator: Allocator, config_path: []const u8, in_dir: []const u8, out_dir: []const u8) !Walker {
    const config = try parser.parseConfig(allocator, config_path);

    return Walker{
        .allocator = allocator,
        .in_dir = in_dir,
        .out_dir = out_dir,
        .config = config,
        .flags = std.StringHashMap([]const u8).init(allocator),
        .selected_files = ArrayList(FileInstallation).init(allocator),
    };
}

pub fn deinit(self: *Walker) void {
    self.config.deinit();
    self.flags.deinit();
    self.selected_files.deinit();
}

pub fn runInstaller(self: *Walker) !void {
    print(u.ansi("=== FOMOD Installer ===", "1;36") ++ "\n", .{});
    print(u.ansi("Module: ", "1;33") ++ u.ansi("{s}", "1;37") ++ "\n", .{self.config.module_name.text});

    if (self.config.module_image) |img| {
        if (img.path) |path| {
            const p = try std.fs.path.join(self.allocator, &[_][]const u8{ self.in_dir, path });
            defer self.allocator.free(p);
            print("\n", .{});
            try u.renderImage1337(self.allocator, p, "100");
            print("\n", .{});
        }
    }

    print("\n", .{});

    if (self.config.module_dependencies) |deps| {
        print(u.ansi("Checking module dependencies...", "1;34") ++ "\n", .{});
        if (!self.checkDependencies(deps)) {
            print(u.ansi("❌ Module dependencies not satisfied. Installation cannot proceed.", "1;31") ++ "\n", .{});
            return;
        }
        print(u.ansi("✅ Module dependencies satisfied.", "1;32") ++ "\n\n", .{});
    }

    if (self.config.required_install_files) |required_files| {
        try self.processFileList(required_files, "Required Files");
    }

    if (self.config.install_steps) |steps| {
        try self.processInstallSteps(steps);
    }

    if (self.config.conditional_file_installs) |cfi| {
        try self.processConditionalFileInstalls(cfi);
    }

    if (self.confirmInstall()) try self.install();
}

fn checkDependencies(self: Walker, deps: CompositeDependency) bool {
    switch (deps.operator) {
        .And => {
            for (deps.dependencies.items) |dep| {
                if (!self.checkSingleDependency(dep)) {
                    return false;
                }
            }
            return true;
        },
        .Or => {
            for (deps.dependencies.items) |dep| {
                if (self.checkSingleDependency(dep)) {
                    return true;
                }
            }
            return false;
        },
    }
}

fn checkSingleDependency(self: Walker, dep: CompositeDependency.DependencyType) bool {
    switch (dep) {
        .File => |file_dep| {
            print("  " ++ u.ansi("File dependency: ", "36") ++ u.ansi("{s}", "37") ++ u.ansi(" (needs: ", "36") ++ u.ansi("{s}", "33") ++ u.ansi(")", "36") ++ "\n", .{ file_dep.file, @tagName(file_dep.state) });
            // TODO: check if the file exists and is active/inactive
            return true;
        },
        .Flag => |flag_dep| {
            if (self.flags.get(flag_dep.flag)) |value| {
                return std.mem.eql(u8, value, flag_dep.value);
            }
            return false;
        },
        .Game, .Fomm => return true, // TODO: get game version somehow
        .Nested => |nested| return self.checkDependencies(nested),
    }
}

fn processFileList(self: *Walker, file_list: FileList, description: []const u8) !void {
    print(u.ansi("Processing ", "1;34") ++ u.ansi("{s}", "1;37") ++ u.ansi(":", "1;34") ++ "\n", .{description});

    for (file_list.items.items) |item| {
        switch (item) {
            .File => |file| {
                print("  " ++ u.ansi("📄 File: ", "32") ++ u.ansi("{s}", "37"), .{file.source});
                if (file.system.destination) |dest| {
                    print(" " ++ u.ansi("->", "33") ++ " " ++ u.ansi("{s}", "37"), .{dest});
                }
                print("\n", .{});

                try self.selected_files.append(.{
                    .source = file.source,
                    .destination = file.system.destination,
                    .is_folder = false,
                    .priority = file.system.priority,
                });
            },
            .Folder => |folder| {
                print("  " ++ u.ansi("📁 Folder: ", "34") ++ u.ansi("{s}", "37"), .{folder.source});
                if (folder.system.destination) |dest| {
                    print(" " ++ u.ansi("->", "33") ++ " " ++ u.ansi("{s}", "37"), .{dest});
                }
                print("\n", .{});

                try self.selected_files.append(.{
                    .source = folder.source,
                    .destination = folder.system.destination,
                    .is_folder = true,
                    .priority = folder.system.priority,
                });
            },
        }
    }
    print("\n", .{});
}

fn processInstallSteps(self: *Walker, steps: StepList) !void {
    print(u.ansi("=== Installation Steps ===", "1;36") ++ "\n", .{});

    for (steps.steps.items, 0..) |step, step_idx| {
        if (step.visible) |visibility| {
            if (!self.checkDependencies(visibility)) {
                print(u.ansi("Step '", "33") ++ u.ansi("{s}", "37") ++ u.ansi("' is not visible, skipping...", "33") ++ "\n", .{step.name});
                continue;
            }
        }

        print("\n" ++ u.ansi("--- Step {d}: ", "1;93") ++ u.ansi("{s}", "1;37") ++ u.ansi(" ---", "1;93") ++ "\n", .{ step_idx + 1, step.name });

        try self.processGroups(step.optional_file_groups);
    }
}

fn processGroups(self: *Walker, groups: StepList.GroupList) !void {
    for (groups.groups.items) |group| {
        const selections = try self.getUserSelection(group);
        defer selections.deinit();

        for (selections.items) |selection| {
            const plugin = &group.plugins.plugins.items[selection];
            print(u.ansi("\nSelected: ", "1;32") ++ u.ansi("{s}", "1;37") ++ "\n", .{plugin.name});

            if (plugin.condition_flags) |flags| {
                for (flags.flags.items) |flag| {
                    try self.flags.put(flag.name, flag.value);
                    print("  " ++ u.ansi("Set flag: ", "93") ++ u.ansi("{s}", "33") ++ u.ansi(" = ", "93") ++ u.ansi("{s}", "33") ++ "\n", .{ flag.name, flag.value });
                }
            }

            if (plugin.files) |files| {
                try self.processFileList(files, plugin.name);
            }
        }
    }
}

fn printOptions(self: Walker, group: StepList.Group, selections: []usize) !void {
    for (group.plugins.plugins.items, 0..) |plugin, idx| {
        const type_info = self.getPluginTypeInfo(plugin);
        print(
            u.ansi("  [{d}] ", "1;36") ++ u.ansi("{s} ", "32"),
            .{ idx, type_info.plugin_type.marker() },
        );

        if (std.mem.indexOfScalar(usize, selections, idx)) |_| {
            print(u.ansi("{s}", "1;93;4") ++ "\n", .{plugin.name});
        } else {
            print(u.ansi("{s}\n", "1;37"), .{plugin.name});
        }
    }
    print(u.ansi("Selected:", "1;32") ++ " {any}\n", .{selections});
}

fn getPluginTypeInfo(self: Walker, plugin: StepList.Plugin) struct { plugin_type: StepList.PluginTypeEnum, selectable: bool } {
    switch (plugin.type_descriptor) {
        .simple_type => |simple| {
            return .{
                .plugin_type = simple.name,
                .selectable = simple.name != .Required and simple.name != .NotUsable,
            };
        },
        .dependency_type => |dep_type| {
            for (dep_type.patterns.patterns.items) |pattern| {
                if (self.checkDependencies(pattern.dependencies)) {
                    return .{
                        .plugin_type = pattern.plugin_type.name,
                        .selectable = pattern.plugin_type.name != .Required and pattern.plugin_type.name != .NotUsable,
                    };
                }
            }
            return .{
                .plugin_type = dep_type.default_type.name,
                .selectable = dep_type.default_type.name != .Required and dep_type.default_type.name != .NotUsable,
            };
        },
    }
}

const UserCmd = union(enum) {
    empty,
    info: usize,
    selection: usize,
    clear,
    err: []const u8,

    pub fn parse(group: StepList.Group) UserCmd {
        var input_buffer: [256]u8 = undefined;
        const input_str = std.io.getStdIn().reader().readUntilDelimiterOrEof(input_buffer[0..], '\n') catch |err| {
            return if (err == error.EndOfStream) .empty else .{ .err = "Error reading input, try again." };
        } orelse return .empty;

        const trimmed_input = std.mem.trim(u8, input_str, " \t\r\n");
        if (trimmed_input.len == 0) return .empty;

        if (trimmed_input.len > 1 and trimmed_input[trimmed_input.len - 1] == 'i') {
            const index_str = trimmed_input[0 .. trimmed_input.len - 1];
            const index = std.fmt.parseInt(usize, index_str, 10) catch {
                return .{ .err = "Invalid index format, try again." };
            };

            if (index >= group.plugins.plugins.items.len) {
                return .{ .err = "Index out of range." };
            }

            return .{ .info = index };
        }

        if (std.mem.eql(u8, trimmed_input, "clear")) return .clear;

        const input = std.fmt.parseInt(usize, trimmed_input, 10) catch {
            return .{ .err = "Invalid input, try again." };
        };

        return .{ .selection = input };
    }
};

const InputConfig = struct {
    prompt: []const u8,
    allow_empty: bool,
    min_selections: usize,
    max_selections: ?usize, // null means unlimited

    fn printInfo(self: @This(), group: StepList.Group) void {
        print(u.ansi("Commands", "1") ++ ":\n  " ++
            u.ansi("{{idx}}", "1;4;92") ++ u.ansi("i", "1;92") ++ ": Print option details\n  " ++
            u.ansi("clear", "1;92") ++ ": Clear the terminal and print this message\n\n", .{});
        print(u.ansi("Step: ", "1") ++ u.ansi("{s}\n", "38;5;226"), .{group.name});
        print(u.ansi("{s}", "1;34") ++ "\n", .{self.prompt});
    }
};

fn printModuleInfo(self: Walker) void {
    print(u.ansi("Module: ", "1;33") ++ u.ansi("{s}", "1;37") ++ "\n", .{self.config.module_name.text});
}

fn getInputWithValidation(
    self: Walker,
    group: StepList.Group,
    selections: *std.ArrayList(usize),
    config: InputConfig,
) !void {
    config.printInfo(group);
    try self.printOptions(group, selections.items);

    while (true) {
        print(u.ansi("> ", "1;32"), .{});

        switch (UserCmd.parse(group)) {
            .clear => {
                u.clearTerminal();
                self.printModuleInfo();
                config.printInfo(group);
                try self.printOptions(group, selections.items);
            },
            .empty => {
                if (config.allow_empty and selections.items.len >= config.min_selections) {
                    return;
                } else if (selections.items.len < config.min_selections) {
                    print(u.ansi("You must select at least {} plugin(s).", "1;31") ++ "\n", .{config.min_selections});
                } else {
                    print(u.ansi("Invalid input, try again.", "1;31") ++ "\n", .{});
                }
            },
            .info => |index| {
                try self.showPluginInfo(group.plugins.plugins.items[index]);
            },
            .selection => |input| {
                if (try self.validateAndAddSelection(group, selections, input)) {
                    if (config.max_selections) |max| {
                        if (selections.items.len >= max) {
                            return;
                        }
                    }
                }
                print(u.ansi("Selected:", "1;32") ++ " {any}\n", .{selections.items});
            },
            .err => |msg| {
                print(u.ansi("{s}", "1;31") ++ "\n", .{msg});
            },
        }

        if (config.max_selections) |max| {
            if (selections.items.len >= max) {
                return;
            }
        }
    }
}

fn validateAndAddSelection(
    self: Walker,
    group: StepList.Group,
    selections: *std.ArrayList(usize),
    input: usize,
) !bool {
    if (input >= group.plugins.plugins.items.len) {
        print(u.ansi("Index out of range.", "1;31") ++ "\n", .{});
        return false;
    }

    const plugin = group.plugins.plugins.items[input];
    const type_info = self.getPluginTypeInfo(plugin);
    if (!type_info.selectable) {
        print(u.ansi("Plugin not selectable.", "1;31") ++ "\n", .{});
        return false;
    }

    for (selections.items, 0..) |sel, idx| {
        if (sel == input) {
            print(u.ansi("Removed idx {}", "1;33") ++ "\n", .{sel});
            _ = selections.orderedRemove(idx);
            return false;
        }
    }

    try selections.append(input);
    return true;
}

fn getUserSelection(self: Walker, group: StepList.Group) !std.ArrayList(usize) {
    var selections = std.ArrayList(usize).init(self.allocator);

    // Auto-select required and recommended plugins
    for (group.plugins.plugins.items, 0..) |plugin, idx| {
        const type_info = self.getPluginTypeInfo(plugin);
        if (type_info.plugin_type == .Required) {
            try selections.append(idx);
            print(u.ansi("Auto-selected (Required): ", "1;31") ++ u.ansi("{s}", "1;37") ++ "\n", .{plugin.name});
        } else if (type_info.plugin_type == .Recommended and
            (group.group_type == .SelectAll or group.group_type == .SelectAny))
        {
            try selections.append(idx);
            print(u.ansi("Auto-selected (Recommended): ", "1;33") ++ u.ansi("{s}", "1;37") ++ "\n", .{plugin.name});
        }
    }

    switch (group.group_type) {
        .SelectAll => {
            // Auto-select all selectable plugins that aren't already selected
            for (group.plugins.plugins.items, 0..) |plugin, idx| {
                const type_info = self.getPluginTypeInfo(plugin);
                if (type_info.selectable and type_info.plugin_type != .Required) {
                    var already_selected = false;
                    for (selections.items) |sel| {
                        if (sel == idx) {
                            already_selected = true;
                            break;
                        }
                    }
                    if (!already_selected) {
                        try selections.append(idx);
                    }
                }
            }
        },
        .SelectExactlyOne => {
            try self.getInputWithValidation(group, &selections, InputConfig{
                .prompt = "Choose exactly one plugin by index:",
                .allow_empty = false,
                .min_selections = 1,
                .max_selections = 1,
            });
        },
        .SelectAtMostOne => {
            try self.getInputWithValidation(group, &selections, InputConfig{
                .prompt = "Choose zero or one plugin by index (empty input to skip):",
                .allow_empty = true,
                .min_selections = 0,
                .max_selections = 1,
            });
        },
        .SelectAtLeastOne => {
            try self.getInputWithValidation(group, &selections, InputConfig{
                .prompt = "Choose at least one plugin by index (empty input to finish):",
                .allow_empty = true,
                .min_selections = 1,
                .max_selections = null,
            });
        },
        .SelectAny => {
            try self.getInputWithValidation(group, &selections, InputConfig{
                .prompt = "Choose any plugins by index (empty input to finish):",
                .allow_empty = true,
                .min_selections = 0,
                .max_selections = null,
            });
        },
    }

    return selections;
}

fn showPluginInfo(self: Walker, plugin: StepList.Plugin) !void {
    print("\n" ++ u.ansi("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", "2;37") ++ "\n", .{});

    if (plugin.image) |img| {
        const path = try std.fs.path.join(self.allocator, &[_][]const u8{ self.in_dir, img.path });
        defer self.allocator.free(path);
        try u.renderImage1337(self.allocator, path, "110");
        print("\n", .{});
    }

    print(u.ansi("📦 ", "1;36") ++ u.ansi("{s}", "1;37;4") ++ "\n", .{plugin.name});

    if (plugin.description.len > 0) {
        print(u.ansi("{s}", "37") ++ "\n", .{plugin.description});
    }

    print(u.ansi("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", "2;37") ++ "\n\n", .{});
}

fn processConditionalFileInstalls(self: *Walker, cfi: @import("conditional_file_install_list.zig")) !void {
    print(u.ansi("=== Processing Conditional File Installs ===", "1;36") ++ "\n", .{});

    for (cfi.patterns.patterns.items) |pattern| {
        if (self.checkDependencies(pattern.dependencies)) {
            print(u.ansi("Conditional pattern matched, adding files:", "1;32") ++ "\n", .{});
            try self.processFileList(pattern.files, "Conditional Files");
        }
    }
}

fn confirmInstall(self: Walker) bool {
    print("\n" ++ u.ansi("=== Installation Summary ===", "1;36") ++ "\n", .{});
    print(u.ansi("Module: ", "1;33") ++ u.ansi("{s}", "1;37") ++ "\n", .{self.config.module_name.text});
    print(u.ansi("Files to install: ", "1;33") ++ u.ansi("{d}", "1;37") ++ "\n", .{self.selected_files.items.len});

    if (self.selected_files.items.len > 0) {
        print("\n" ++ u.ansi("Files and folders to install:", "1;34") ++ "\n", .{});

        std.sort.insertion(FileInstallation, self.selected_files.items, {}, compareFileInstallations);

        for (self.selected_files.items) |file| {
            const icon = if (file.is_folder) u.ansi("📁", "34") else u.ansi("📄", "32");
            print("  {s} " ++ u.ansi("{s}", "37"), .{ icon, file.source });
            if (file.destination) |dest| {
                print(" " ++ u.ansi("->", "33") ++ " " ++ u.ansi("{s}", "37"), .{dest});
            }
            if (file.priority != 0) {
                print(" " ++ u.ansi("(priority: {d})", "90"), .{file.priority});
            }
            print("\n", .{});
        }
    }

    if (self.flags.count() > 0) {
        print("\n" ++ u.ansi("Flags set during installation:", "1;34") ++ "\n", .{});
        var iterator = self.flags.iterator();
        while (iterator.next()) |entry| {
            print("  " ++ u.ansi("{s}", "33") ++ u.ansi(" = ", "93") ++ u.ansi("{s}", "33") ++ "\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }
    }

    while (true) {
        print("\n" ++ u.ansi("Proceed with installation? [Y/n]: ", "1;36"), .{});
        var buf: [8]u8 = undefined;
        const line = std.io.getStdIn().reader().readUntilDelimiterOrEof(&buf, '\n') catch return false;
        if (line) |s| {
            const trimmed = std.mem.trim(u8, s, " \t\r\n");
            if (trimmed.len == 0 or std.ascii.eqlIgnoreCase(trimmed, "y") or std.ascii.eqlIgnoreCase(trimmed, "yes")) {
                return true;
            } else if (std.ascii.eqlIgnoreCase(trimmed, "n") or std.ascii.eqlIgnoreCase(trimmed, "no")) {
                return false;
            }
        }
    }
}

fn install(self: Walker) !void {
    print("\n" ++ u.ansi("=== Installation Process ===", "1;36") ++ "\n", .{});
    if (self.selected_files.items.len > 0) {
        for (self.selected_files.items) |file| {
            const src = try std.fs.path.join(
                self.allocator,
                &[_][]const u8{ self.in_dir, file.source },
            );
            defer self.allocator.free(src);

            if (file.is_folder) {
                print(u.ansi("📁 Installing folder: ", "1;34") ++ u.ansi("{s}", "1;37"), .{file.source});
                if (file.destination) |dest| {
                    const dst = try std.fs.path.join(self.allocator, &[_][]const u8{ self.out_dir, dest });
                    defer self.allocator.free(dst);
                    print(" " ++ u.ansi("to ", "36") ++ u.ansi("{s}\n", "37"), .{dest});
                    try u.symlinkRecursive(self.allocator, 2, self.out_dir, src, dst);
                }
            } else {
                print(u.ansi("📄 Installing file: ", "1;32") ++ u.ansi("{s}", "1;37"), .{file.source});
                if (file.destination) |dest| {
                    const dst_full = try std.fs.path.join(self.allocator, &[_][]const u8{ self.out_dir, dest });
                    defer self.allocator.free(dst_full);
                    const dst = try u.normalizeModDir(self.allocator, self.out_dir, dst_full);
                    defer self.allocator.free(dst);
                    print(" " ++ u.ansi("to ", "36") ++ u.ansi("{s}\n", "37"), .{dest});
                    try u.symlinkFile(2, src, dst);
                }
            }
        }
        print("\n" ++ u.ansi("✅ Installation completed successfully!", "1;32") ++ "\n", .{});
    } else {
        print(u.ansi("ℹ️  No files selected for installation.", "1;33") ++ "\n", .{});
    }
}

fn compareFileInstallations(context: void, a: FileInstallation, b: FileInstallation) bool {
    _ = context;
    return a.priority > b.priority;
}
