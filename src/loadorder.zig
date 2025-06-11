const std = @import("std");
const Allocator = std.mem.Allocator;

const Self = @This();

allocator: Allocator,
file: std.fs.File,
file_content: std.ArrayList(u8),
mods: std.StringArrayHashMap(bool),

pub fn init(allocator: Allocator, cwd: std.fs.Dir) !Self {
    const file = try cwd.createFile("loadorder", .{ .truncate = false, .read = true });
    const stat = try file.stat();
    var file_content = try std.ArrayList(u8).initCapacity(allocator, stat.size);
    file_content.expandToCapacity();
    _ = try file.readAll(file_content.items);

    var it = std.mem.splitScalar(u8, file_content.items, '\n');
    var mods = std.StringArrayHashMap(bool).init(allocator);

    while (it.next()) |entry| {
        if (entry.len < 2) continue;
        const enabled = entry[0] == '*';
        const name = try allocator.dupe(u8, entry[if (enabled) 1 else 0..]);
        try mods.put(name, enabled);
    }

    return Self{
        .allocator = allocator,
        .file = file,
        .file_content = file_content,
        .mods = mods,
    };
}

pub fn appendMod(self: *Self, name: []const u8, enabled: bool) !void {
    if (self.mods.contains(name)) return;
    try self.mods.put(try self.allocator.dupe(u8, name), enabled);
}

pub fn serialize(self: *Self) !void {
    self.file_content.shrinkRetainingCapacity(0);
    var it = self.mods.iterator();

    while (it.next()) |mod| {
        if (mod.value_ptr.*) try self.file_content.append('*');
        try self.file_content.appendSlice(mod.key_ptr.*);
        try self.file_content.append('\n');
    }

    try self.file.seekTo(0);
    try self.file.writeAll(self.file_content.items);
}

pub fn deinit(self: *Self) void {
    self.file.close();
    self.file_content.deinit();

    for (self.mods.keys()) |k| self.allocator.free(k);
    self.mods.deinit();
}
