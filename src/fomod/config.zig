const std = @import("std");
const Xml = @import("../xml.zig");
const CompositeDependency = @import("composite_dependency.zig");
const FileList = @import("file_list.zig");
const StepList = @import("step_list.zig");
const ConditionalFileInstallList = @import("conditional_file_install_list.zig");
const Allocator = std.mem.Allocator;

const Config = @This();

doc: Xml,
module_name: ModuleTitle,
module_image: ?HeaderImage = null,
module_dependencies: ?CompositeDependency = null,
required_install_files: ?FileList = null,
install_steps: ?StepList = null,
conditional_file_installs: ?ConditionalFileInstallList = null,

pub fn deinit(self: Config) void {
    if (self.module_image) |img| {
        img.deinit();
    }
    if (self.module_dependencies) |dep| {
        dep.deinit();
    }
    if (self.required_install_files) |fl| {
        fl.deinit();
    }
    if (self.install_steps) |steps| {
        steps.deinit();
    }
    if (self.conditional_file_installs) |cfi| {
        cfi.deinit();
    }
    self.doc.deinit();
}

pub const ModuleTitlePosition = enum {
    Left,
    Right,
    RightOfImage,
};

pub const ModuleTitle = struct {
    text: []const u8,
    position: ModuleTitlePosition = .Left,
    colour: []const u8 = "000000",
};

pub const HeaderImage = struct {
    allocator: Allocator,
    path: ?[]const u8 = null,
    show_image: bool = true,
    show_fade: bool = true,
    height: i32 = -1,

    fn deinit(self: HeaderImage) void {
        if (self.path) |path|
            self.allocator.free(path);
    }
};
