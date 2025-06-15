const std = @import("std");
const xml = @import("../xml.zig");
const Config = @import("config.zig");
const CompositeDependency = @import("composite_dependency.zig");
const FileList = @import("file_list.zig");
const StepList = @import("step_list.zig");
const ConditionalFileInstallList = @import("conditional_file_install_list.zig");
const u = @import("../utils.zig");

const Allocator = std.mem.Allocator;

pub fn parseConfig(allocator: Allocator, xml_path: []const u8) !Config {
    const doc = try xml.init(allocator, xml_path);
    defer doc.deinit();

    // if (doc.findElement("config") == null) return error.NoConfigElement;

    var config = Config{ .module_name = undefined };

    if (doc.findElement("moduleName")) |module_name_node| {
        config.module_name = try parseModuleTitle(module_name_node);
    } else {
        return error.NoModuleName;
    }

    if (doc.findElement("moduleImage")) |module_image_node| {
        config.module_image = try parseHeaderImage(module_image_node);
    }

    if (doc.findElement("moduleDependencies")) |deps_node| {
        config.module_dependencies = try parseCompositeDependency(allocator, deps_node);
    }

    if (doc.findElement("requiredInstallFiles")) |files_node| {
        config.required_install_files = try parseFileList(allocator, files_node);
    }

    if (doc.findElement("installSteps")) |steps_node| {
        config.install_steps = try parseStepList(allocator, steps_node);
    }

    if (doc.findElement("conditionalFileInstalls")) |cfi_node| {
        config.conditional_file_installs = try parseConditionalFileInstallList(allocator, cfi_node);
    }

    return config;
}

fn parseModuleTitle(node: xml.Node) !Config.ModuleTitle {
    var title = Config.ModuleTitle{
        .text = "",
    };

    if (node.getText()) |text| {
        title.text = text;
    }

    if (node.getAttribute("position")) |pos_attr| {
        title.position = try u.initEnum(Config.ModuleTitlePosition, pos_attr, .Left);
    }

    if (node.getAttribute("colour")) |colour_attr| {
        title.colour = colour_attr;
    }

    return title;
}

fn parseHeaderImage(node: xml.Node) !Config.HeaderImage {
    var image = Config.HeaderImage{};

    if (node.getAttribute("path")) |path_attr| {
        image.path = path_attr;
    }

    if (node.getAttribute("showImage")) |show_attr| {
        image.show_image = std.mem.eql(u8, show_attr, "true");
    }

    if (node.getAttribute("showFade")) |fade_attr| {
        image.show_fade = std.mem.eql(u8, fade_attr, "true");
    }

    if (node.getAttribute("height")) |height_attr| {
        image.height = std.fmt.parseInt(i32, height_attr, 10) catch -1;
    }

    return image;
}

fn parseCompositeDependency(allocator: Allocator, node: xml.Node) !CompositeDependency {
    var dep = CompositeDependency.init(allocator);

    if (node.getAttribute("operator")) |op_attr| {
        dep.operator = try u.initEnum(CompositeDependency.Operator, op_attr, .And);
    }

    var maybe_child = node.getFirstChild();
    while (maybe_child) |child| {
        if (child.getType() == .element) {
            const element_name = child.getElement() orelse {
                maybe_child = child.getNextSibling();
                continue;
            };

            if (std.mem.eql(u8, element_name, "fileDependency")) {
                try parseFileDependency(&dep, child);
            } else if (std.mem.eql(u8, element_name, "flagDependency")) {
                try parseFlagDependency(&dep, child);
            } else if (std.mem.eql(u8, element_name, "gameDependency")) {
                try parseGameDependency(&dep, child);
            } else if (std.mem.eql(u8, element_name, "fommDependency")) {
                try parseFommDependency(&dep, child);
            } else if (std.mem.eql(u8, element_name, "dependencies")) {
                const nested = try allocator.create(CompositeDependency);
                nested.* = try parseCompositeDependency(allocator, child);
                try dep.addNested(nested);
            }
        }
        maybe_child = child.getNextSibling();
    }

    return dep;
}

fn parseFileDependency(dep: *CompositeDependency, node: xml.Node) !void {
    const file_attr = node.getAttribute("file") orelse return error.MissingFileAttribute;

    const state_attr = node.getAttribute("state") orelse "Active";
    const state = try u.initEnum(CompositeDependency.FileState, state_attr, .Active);

    try dep.addFile(file_attr, state);
}

fn parseFlagDependency(dep: *CompositeDependency, node: xml.Node) !void {
    const flag_attr = node.getAttribute("flag") orelse return error.MissingFlagAttribute;
    const value_attr = node.getAttribute("value") orelse return error.MissingValueAttribute;

    try dep.addFlag(flag_attr, value_attr);
}

fn parseGameDependency(dep: *CompositeDependency, node: xml.Node) !void {
    const version_attr = node.getAttribute("version") orelse return error.MissingVersionAttribute;
    try dep.addGameVersion(version_attr);
}

fn parseFommDependency(dep: *CompositeDependency, node: xml.Node) !void {
    const version_attr = node.getAttribute("version") orelse return error.MissingVersionAttribute;
    try dep.addFommVersion(version_attr);
}

fn parseFileList(allocator: Allocator, node: xml.Node) !FileList {
    var file_list = FileList.init(allocator);

    var maybe_child = node.getFirstChild();
    while (maybe_child) |child| {
        if (child.getType() == .element) {
            const element_name = child.getElement() orelse {
                maybe_child = child.getNextSibling();
                continue;
            };

            if (std.mem.eql(u8, element_name, "file")) {
                try parseFileItem(&file_list, child, true);
            } else if (std.mem.eql(u8, element_name, "folder")) {
                try parseFileItem(&file_list, child, false);
            }
        }
        maybe_child = child.getNextSibling();
    }

    return file_list;
}

fn parseFileItem(file_list: *FileList, node: xml.Node, is_file: bool) !void {
    const source_attr = node.getAttribute("source") orelse return error.MissingSourceAttribute;

    var system = FileList.SystemItemAttributes{};

    if (node.getAttribute("destination")) |dest_attr| {
        system.destination = dest_attr;
    }

    if (node.getAttribute("alwaysInstall")) |always_attr| {
        system.always_install = std.mem.eql(u8, always_attr, "true");
    }

    if (node.getAttribute("installIfUsable")) |usable_attr| {
        system.install_if_usable = std.mem.eql(u8, usable_attr, "true");
    }

    if (node.getAttribute("priority")) |priority_attr| {
        system.priority = std.fmt.parseInt(i32, priority_attr, 10) catch 0;
    }

    if (is_file) {
        try file_list.addFile(source_attr, system);
    } else {
        try file_list.addFolder(source_attr, system);
    }
}

fn parseStepList(allocator: Allocator, node: xml.Node) !StepList {
    var step_list = StepList.init(allocator);

    if (node.getAttribute("order")) |order_attr| {
        step_list.order = try u.initEnum(StepList.OrderEnum, order_attr, .Ascending);
    }

    var maybe_child = node.getFirstChild();
    while (maybe_child) |child| {
        if (child.getType() == .element) {
            const element_name = child.getElement() orelse {
                maybe_child = child.getNextSibling();
                continue;
            };

            if (std.mem.eql(u8, element_name, "installStep")) {
                const step = try parseInstallStep(allocator, child);
                try step_list.steps.append(step);
            }
        }
        maybe_child = child.getNextSibling();
    }

    return step_list;
}

fn parseInstallStep(allocator: Allocator, node: xml.Node) !StepList.InstallStep {
    const name_attr = node.getAttribute("name") orelse return error.MissingNameAttribute;

    var step = StepList.InstallStep{
        .name = name_attr,
        .visible = null,
        .optional_file_groups = StepList.GroupList.init(allocator),
    };

    var maybe_child = node.getFirstChild();
    while (maybe_child) |child| {
        if (child.getType() == .element) {
            const element_name = child.getElement() orelse {
                maybe_child = child.getNextSibling();
                continue;
            };

            if (std.mem.eql(u8, element_name, "visible")) {
                const visible_dep = try allocator.create(CompositeDependency);
                visible_dep.* = try parseCompositeDependency(allocator, child);
                step.visible = visible_dep.*;
            } else if (std.mem.eql(u8, element_name, "optionalFileGroups")) {
                step.optional_file_groups = try parseGroupList(allocator, child);
            }
        }
        maybe_child = child.getNextSibling();
    }

    return step;
}

fn parseGroupList(allocator: Allocator, node: xml.Node) !StepList.GroupList {
    var group_list = StepList.GroupList.init(allocator);

    if (node.getAttribute("order")) |order_attr| {
        group_list.order = try u.initEnum(StepList.OrderEnum, order_attr, .Ascending);
    }

    var maybe_child = node.getFirstChild();
    while (maybe_child) |child| {
        if (child.getType() == .element) {
            const element_name = child.getElement() orelse {
                maybe_child = child.getNextSibling();
                continue;
            };

            if (std.mem.eql(u8, element_name, "group")) {
                const group = try parseGroup(allocator, child);
                try group_list.groups.append(group);
            }
        }
        maybe_child = child.getNextSibling();
    }

    return group_list;
}

fn parseGroup(allocator: Allocator, node: xml.Node) !StepList.Group {
    const name_attr = node.getAttribute("name") orelse return error.MissingNameAttribute;

    const type_attr = node.getAttribute("type") orelse "SelectExactlyOne";
    const group_type = try u.initEnum(StepList.GroupType, type_attr, .SelectExactlyOne);

    var group = StepList.Group{
        .name = name_attr,
        .group_type = group_type,
        .plugins = StepList.PluginList.init(allocator),
    };

    var maybe_child = node.getFirstChild();
    while (maybe_child) |child| {
        if (child.getType() == .element) {
            const element_name = child.getElement() orelse {
                maybe_child = child.getNextSibling();
                continue;
            };

            if (std.mem.eql(u8, element_name, "plugins")) {
                group.plugins = try parsePluginList(allocator, child);
            }
        }
        maybe_child = child.getNextSibling();
    }

    return group;
}

fn parsePluginList(allocator: Allocator, node: xml.Node) !StepList.PluginList {
    var plugin_list = StepList.PluginList.init(allocator);

    if (node.getAttribute("order")) |order_attr| {
        plugin_list.order = try u.initEnum(StepList.OrderEnum, order_attr, .Ascending);
    }

    var maybe_child = node.getFirstChild();
    while (maybe_child) |child| {
        if (child.getType() == .element) {
            const element_name = child.getElement() orelse {
                maybe_child = child.getNextSibling();
                continue;
            };

            if (std.mem.eql(u8, element_name, "plugin")) {
                const plugin = try parsePlugin(allocator, child);
                try plugin_list.plugins.append(plugin);
            }
        }
        maybe_child = child.getNextSibling();
    }

    return plugin_list;
}

fn parsePlugin(allocator: Allocator, node: xml.Node) !StepList.Plugin {
    const name_attr = node.getAttribute("name") orelse return error.MissingNameAttribute;

    var plugin = StepList.Plugin{
        .name = name_attr,
        .description = "",
        .type_descriptor = .{ .simple_type = .{ .name = .Optional } },
    };

    var maybe_child = node.getFirstChild();
    while (maybe_child) |child| {
        if (child.getType() == .element) {
            const element_name = child.getElement() orelse {
                maybe_child = child.getNextSibling();
                continue;
            };

            if (std.mem.eql(u8, element_name, "description")) {
                if (child.getText()) |desc| {
                    plugin.description = desc;
                }
            } else if (std.mem.eql(u8, element_name, "image")) {
                if (child.getAttribute("path")) |path_attr| {
                    plugin.image = .{ .path = path_attr };
                }
            } else if (std.mem.eql(u8, element_name, "files")) {
                plugin.files = try parseFileList(allocator, child);
            } else if (std.mem.eql(u8, element_name, "conditionFlags")) {
                plugin.condition_flags = try parseConditionFlagList(allocator, child);
            } else if (std.mem.eql(u8, element_name, "typeDescriptor")) {
                plugin.type_descriptor = try parsePluginTypeDescriptor(allocator, child);
            }
        }
        maybe_child = child.getNextSibling();
    }

    return plugin;
}

fn parseConditionFlagList(allocator: Allocator, node: xml.Node) !StepList.ConditionFlagList {
    var flag_list = StepList.ConditionFlagList.init(allocator);

    var maybe_child = node.getFirstChild();
    while (maybe_child) |child| {
        if (child.getType() == .element) {
            const element_name = child.getElement() orelse {
                maybe_child = child.getNextSibling();
                continue;
            };

            if (std.mem.eql(u8, element_name, "flag")) {
                const name_attr = child.getAttribute("name") orelse return error.MissingNameAttribute;
                const value_attr = child.getAttribute("value") orelse return error.MissingValueAttribute;

                const flag = StepList.SetConditionFlag{
                    .name = name_attr,
                    .value = value_attr,
                };

                try flag_list.flags.append(flag);
            }
        }
        maybe_child = child.getNextSibling();
    }

    return flag_list;
}

fn parsePluginTypeDescriptor(allocator: Allocator, node: xml.Node) !StepList.PluginTypeDescriptor {
    var maybe_child = node.getFirstChild();
    while (maybe_child) |child| {
        if (child.getType() == .element) {
            const element_name = child.getElement() orelse {
                maybe_child = child.getNextSibling();
                continue;
            };

            if (std.mem.eql(u8, element_name, "dependencyType")) {
                return .{ .dependency_type = try parseDependencyPluginType(allocator, child) };
            } else if (std.mem.eql(u8, element_name, "type")) {
                const type_attr = child.getAttribute("name") orelse "Optional";
                const plugin_type = try u.initEnum(StepList.PluginTypeEnum, type_attr, .Optional);
                return .{ .simple_type = .{ .name = plugin_type } };
            }
        }
        maybe_child = child.getNextSibling();
    }

    return .{ .simple_type = .{ .name = .Optional } };
}

fn parseDependencyPluginType(allocator: Allocator, node: xml.Node) !StepList.DependencyPluginType {
    var dep_type = StepList.DependencyPluginType{
        .default_type = .{ .name = .Optional },
        .patterns = StepList.DependencyPatternList.init(allocator),
    };

    var maybe_child = node.getFirstChild();
    while (maybe_child) |child| {
        if (child.getType() == .element) {
            const element_name = child.getElement() orelse {
                maybe_child = child.getNextSibling();
                continue;
            };

            if (std.mem.eql(u8, element_name, "defaultType")) {
                const type_attr = child.getAttribute("name") orelse "Optional";
                const plugin_type = try u.initEnum(StepList.PluginTypeEnum, type_attr, .Optional);
                dep_type.default_type = .{ .name = plugin_type };
            } else if (std.mem.eql(u8, element_name, "patterns")) {
                dep_type.patterns = try parseDependencyPatternList(allocator, child);
            }
        }
        maybe_child = child.getNextSibling();
    }

    return dep_type;
}

fn parseDependencyPatternList(allocator: Allocator, node: xml.Node) !StepList.DependencyPatternList {
    var pattern_list = StepList.DependencyPatternList.init(allocator);

    var maybe_child = node.getFirstChild();
    while (maybe_child) |child| {
        if (child.getType() == .element) {
            const element_name = child.getElement() orelse {
                maybe_child = child.getNextSibling();
                continue;
            };

            if (std.mem.eql(u8, element_name, "pattern")) {
                const pattern = try parseDependencyPattern(allocator, child);
                try pattern_list.patterns.append(pattern);
            }
        }
        maybe_child = child.getNextSibling();
    }

    return pattern_list;
}

fn parseDependencyPattern(allocator: Allocator, node: xml.Node) !StepList.DependencyPattern {
    var pattern = StepList.DependencyPattern{
        .dependencies = CompositeDependency.init(allocator),
        .plugin_type = .{ .name = .Optional },
    };

    var maybe_child = node.getFirstChild();
    while (maybe_child) |child| {
        if (child.getType() == .element) {
            const element_name = child.getElement() orelse {
                maybe_child = child.getNextSibling();
                continue;
            };

            if (std.mem.eql(u8, element_name, "dependencies")) {
                pattern.dependencies = try parseCompositeDependency(allocator, child);
            } else if (std.mem.eql(u8, element_name, "type")) {
                const type_attr = child.getAttribute("name") orelse "Optional";
                const plugin_type = try u.initEnum(StepList.PluginTypeEnum, type_attr, .Optional);
                pattern.plugin_type = .{ .name = plugin_type };
            }
        }
        maybe_child = child.getNextSibling();
    }

    return pattern;
}

fn parseConditionalFileInstallList(allocator: Allocator, node: xml.Node) !ConditionalFileInstallList {
    var cfi_list = ConditionalFileInstallList.init(allocator);

    var maybe_child = node.getFirstChild();
    while (maybe_child) |child| {
        if (child.getType() == .element) {
            const element_name = child.getElement() orelse {
                maybe_child = child.getNextSibling();
                continue;
            };

            if (std.mem.eql(u8, element_name, "patterns")) {
                cfi_list.patterns = try parseConditionalInstallPatternList(allocator, child);
            }
        }
        maybe_child = child.getNextSibling();
    }

    return cfi_list;
}

fn parseConditionalInstallPatternList(allocator: Allocator, node: xml.Node) !ConditionalFileInstallList.ConditionalInstallPatternList {
    var pattern_list = ConditionalFileInstallList.ConditionalInstallPatternList.init(allocator);

    var maybe_child = node.getFirstChild();
    while (maybe_child) |child| {
        if (child.getType() == .element) {
            const element_name = child.getElement() orelse {
                maybe_child = child.getNextSibling();
                continue;
            };

            if (std.mem.eql(u8, element_name, "pattern")) {
                const pattern = try parseConditionalInstallPattern(allocator, child);
                try pattern_list.patterns.append(pattern);
            }
        }
        maybe_child = child.getNextSibling();
    }

    return pattern_list;
}

fn parseConditionalInstallPattern(allocator: Allocator, node: xml.Node) !ConditionalFileInstallList.ConditionalInstallPattern {
    var pattern = ConditionalFileInstallList.ConditionalInstallPattern{
        .dependencies = CompositeDependency.init(allocator),
        .files = FileList.init(allocator),
    };

    var maybe_child = node.getFirstChild();
    while (maybe_child) |child| {
        if (child.getType() == .element) {
            const element_name = child.getElement() orelse {
                maybe_child = child.getNextSibling();
                continue;
            };

            if (std.mem.eql(u8, element_name, "dependencies")) {
                pattern.dependencies = try parseCompositeDependency(allocator, child);
            } else if (std.mem.eql(u8, element_name, "files")) {
                pattern.files = try parseFileList(allocator, child);
            }
        }
        maybe_child = child.getNextSibling();
    }

    return pattern;
}
