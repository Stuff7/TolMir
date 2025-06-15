const std = @import("std");
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

pub fn deinit(self: *FileList) void {
    self.items.deinit();
}

pub fn addFile(self: *FileList, source: []const u8, system: SystemItemAttributes) !void {
    try self.items.append(.{ .File = FileType{ .source = source, .system = system } });
}

pub fn addFolder(self: *FileList, source: []const u8, system: SystemItemAttributes) !void {
    try self.items.append(.{ .Folder = FolderType{ .source = source, .system = system } });
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
};
