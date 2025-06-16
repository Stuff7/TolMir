const std = @import("std");
const Allocator = std.mem.Allocator;

const CompositeDependency = @This();

operator: Operator = .And,
dependencies: std.ArrayList(DependencyType),
allocator: Allocator,

pub fn init(allocator: Allocator) CompositeDependency {
    return CompositeDependency{
        .operator = .And,
        .dependencies = std.ArrayList(DependencyType).init(allocator),
        .allocator = allocator,
    };
}

pub fn deinit(self: *CompositeDependency) void {
    for (self.dependencies.items) |dep| {
        if (dep == .Nested) {
            dep.Nested.deinit();
            self.allocator.destroy(dep.Nested);
        }
    }
    self.dependencies.deinit();
}

pub fn addFile(self: *CompositeDependency, file: []const u8, state: FileState) !void {
    try self.dependencies.append(.{ .File = FileDependency{ .file = file, .state = state } });
}

pub fn addFlag(self: *CompositeDependency, flag: []const u8, value: []const u8) !void {
    try self.dependencies.append(.{ .Flag = FlagDependency{ .flag = flag, .value = value } });
}

pub fn addGameVersion(self: *CompositeDependency, version: []const u8) !void {
    try self.dependencies.append(.{ .Game = VersionDependency{ .version = version } });
}

pub fn addFommVersion(self: *CompositeDependency, version: []const u8) !void {
    try self.dependencies.append(.{ .Fomm = VersionDependency{ .version = version } });
}

pub fn addNested(self: *CompositeDependency, nested: *CompositeDependency) !void {
    try self.dependencies.append(.{ .Nested = nested });
}

pub const Operator = enum {
    And,
    Or,
};

pub const FileState = enum {
    Missing,
    Inactive,
    Active,
};

const FileDependency = struct {
    file: []const u8,
    state: FileState,
};

const FlagDependency = struct {
    flag: []const u8,
    value: []const u8,
};

const VersionDependency = struct {
    version: []const u8,
};

pub const DependencyType = union(enum) {
    File: FileDependency,
    Flag: FlagDependency,
    Game: VersionDependency,
    Fomm: VersionDependency,
    Nested: *CompositeDependency,
};
