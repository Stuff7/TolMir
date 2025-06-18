const std = @import("std");
const u = @import("../utils.zig");
const Allocator = std.mem.Allocator;

const FileList = @This();

items: std.ArrayList(FileListItem),
allocator: Allocator,

pub fn init(allocator: Allocator) FileList {
    return FileList{
        .items = std.ArrayList(FileListItem).init(allocator),
        .allocator = allocator,
    };
}

pub fn deinit(self: FileList) void {
    for (self.items.items) |f| f.deinit(self.allocator);
    self.items.deinit();
}

pub fn addFile(self: *FileList, source: []const u8, system: SystemItemAttributes) !void {
    try self.items.append(.{ .File = FileType{
        .source = try u.replacePathSep(self.allocator, source),
        .system = system,
    } });
}

pub fn addFolder(self: *FileList, source: []const u8, system: SystemItemAttributes) !void {
    try self.items.append(.{ .Folder = FolderType{
        .source = try u.replacePathSep(self.allocator, source),
        .system = system,
    } });
}

pub const SystemItemAttributes = struct {
    destination: ?[]const u8 = null,
    always_install: bool = false,
    install_if_usable: bool = false,
    priority: i32 = 0,
};

const FileType = struct {
    source: []const u8,
    system: SystemItemAttributes,
};

const FolderType = struct {
    source: []const u8,
    system: SystemItemAttributes,
};

const FileListItem = union(enum) {
    File: FileType,
    Folder: FolderType,

    fn deinit(self: FileListItem, allocator: Allocator) void {
        switch (self) {
            .File => |f| allocator.free(f.source),
            .Folder => |f| allocator.free(f.source),
        }

        const dest = switch (self) {
            .File => |f| f.system.destination,
            .Folder => |f| f.system.destination,
        };

        if (dest) |destination| {
            allocator.free(destination);
        }
    }
};
