const std = @import("std");
const Allocator = std.mem.Allocator;
const CompositeDependency = @import("composite_dependency.zig");
const FileList = @import("file_list.zig");

const StepList = @This();

steps: std.ArrayList(InstallStep),
order: OrderEnum = .Ascending,
allocator: Allocator,

pub fn init(allocator: Allocator) StepList {
    return .{
        .steps = std.ArrayList(InstallStep).init(allocator),
        .allocator = allocator,
    };
}

pub fn deinit(self: *StepList) void {
    for (self.steps.items) |*step| {
        if (step.visible) |*dep| {
            dep.deinit();
            step.allocator.destroy(dep);
        }
        step.optional_file_groups.deinit();
    }
    self.steps.deinit();
}

pub const OrderEnum = enum {
    Ascending,
    Descending,
    Explicit,
};

pub const GroupType = enum {
    SelectAtLeastOne,
    SelectAtMostOne,
    SelectExactlyOne,
    SelectAll,
    SelectAny,
};

pub const Group = struct {
    name: []const u8,
    group_type: GroupType,
    plugins: PluginList,
};

pub const GroupList = struct {
    groups: std.ArrayList(Group),
    order: OrderEnum = .Ascending,
    allocator: Allocator,

    pub fn init(allocator: Allocator) GroupList {
        return .{
            .groups = std.ArrayList(Group).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *GroupList) void {
        for (self.groups.items) |*group| {
            group.plugins.deinit();
        }
        self.groups.deinit();
    }
};

pub const InstallStep = struct {
    name: []const u8,
    visible: ?CompositeDependency,
    optional_file_groups: GroupList,
};

pub const PluginTypeEnum = enum {
    Required,
    Optional,
    Recommended,
    NotUsable,
    CouldBeUsable,
};

const PluginType = struct {
    name: PluginTypeEnum,
};

pub const DependencyPattern = struct {
    dependencies: CompositeDependency,
    plugin_type: PluginType,
};

pub const DependencyPatternList = struct {
    patterns: std.ArrayList(DependencyPattern),
    allocator: Allocator,

    pub fn init(allocator: Allocator) DependencyPatternList {
        return .{
            .patterns = std.ArrayList(DependencyPattern).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *DependencyPatternList) void {
        self.patterns.deinit();
    }
};

pub const DependencyPluginType = struct {
    default_type: PluginType,
    patterns: DependencyPatternList,
};

pub const PluginTypeDescriptor = union(enum) {
    dependency_type: DependencyPluginType,
    simple_type: PluginType,
};

pub const SetConditionFlag = struct {
    name: []const u8,
    value: []const u8,
};

pub const ConditionFlagList = struct {
    flags: std.ArrayList(SetConditionFlag),
    allocator: Allocator,

    pub fn init(allocator: Allocator) ConditionFlagList {
        return .{
            .flags = std.ArrayList(SetConditionFlag).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ConditionFlagList) void {
        self.flags.deinit();
    }
};

const PluginImage = struct {
    path: []const u8,
};

pub const Plugin = struct {
    name: []const u8,
    description: []const u8,
    image: ?PluginImage = null,
    files: ?FileList = null,
    condition_flags: ?ConditionFlagList = null,
    type_descriptor: PluginTypeDescriptor,
};

pub const PluginList = struct {
    plugins: std.ArrayList(Plugin),
    order: OrderEnum = .Ascending,
    allocator: Allocator,

    pub fn init(allocator: Allocator) PluginList {
        return .{
            .plugins = std.ArrayList(Plugin).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *PluginList) void {
        for (self.plugins.items) |*plugin| {
            if (plugin.files) |*f| f.deinit();
            if (plugin.condition_flags) |*c| c.deinit();
        }
        self.plugins.deinit();
    }
};
