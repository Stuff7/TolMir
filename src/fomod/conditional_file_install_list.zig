const std = @import("std");
const CompositeDependency = @import("composite_dependency.zig");
const FileList = @import("file_list.zig");
const Allocator = std.mem.Allocator;

const ConditionalFileInstallList = @This();

patterns: ConditionalInstallPatternList,

pub fn init(allocator: Allocator) ConditionalFileInstallList {
    return .{
        .patterns = ConditionalInstallPatternList.init(allocator),
    };
}

pub fn deinit(self: ConditionalFileInstallList) void {
    self.patterns.deinit();
}

pub const ConditionalInstallPattern = struct {
    dependencies: CompositeDependency,
    files: FileList,
};

pub const ConditionalInstallPatternList = struct {
    patterns: std.ArrayList(ConditionalInstallPattern),
    allocator: Allocator,

    pub fn init(allocator: Allocator) ConditionalInstallPatternList {
        return .{
            .patterns = std.ArrayList(ConditionalInstallPattern).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: ConditionalInstallPatternList) void {
        for (self.patterns.items) |pattern| {
            pattern.dependencies.deinit();
            pattern.files.deinit();
        }
        self.patterns.deinit();
    }
};
