const std = @import("std");

const Allocator = std.mem.Allocator;

const Self = @This();

allocator: Allocator,
cwd: std.fs.Dir,
content: std.ArrayList(u8),
map: Map,

const Map = std.StringHashMap(std.ArrayList([]const u8));

pub fn init(allocator: Allocator, cwd: std.fs.Dir) !Self {
    const map = Map.init(allocator);
    var file = cwd.openFile("espmap", .{}) catch return Self{
        .allocator = allocator,
        .cwd = cwd,
        .map = map,
        .content = std.ArrayList(u8).init(allocator),
    };

    defer file.close();
    const stat = try file.stat();
    var content = try std.ArrayList(u8).initCapacity(allocator, stat.size);
    content.expandToCapacity();
    _ = try file.readAll(content.items);

    var self = Self{
        .allocator = allocator,
        .cwd = cwd,
        .map = map,
        .content = content,
    };

    try self.deserialize();

    return self;
}

pub fn appendEsp(self: *Self, stem: []const u8, esp_path: []const u8) !void {
    const result = try self.map.getOrPut(stem);
    const map = result.value_ptr;
    if (!result.found_existing) {
        result.key_ptr.* = try self.allocator.dupe(u8, stem);
        result.value_ptr.* = try std.ArrayList([]const u8).initCapacity(self.allocator, 5);
    }

    if (!std.mem.endsWith(u8, esp_path, ".esp")) return;

    const esp = std.fs.path.basename(esp_path);
    var added = false;
    for (map.items) |v| {
        if (std.mem.eql(u8, v, esp)) {
            added = true;
            break;
        }
    }

    if (!added) try map.append(try self.allocator.dupe(u8, esp));
}

pub fn serialize(self: *Self) !void {
    self.content.shrinkRetainingCapacity(0);
    var it = self.map.iterator();

    while (it.next()) |entry| {
        try self.content.appendSlice(&[_]u8{ @intCast(entry.value_ptr.items.len), @intCast(entry.key_ptr.len) });
        try self.content.appendSlice(entry.key_ptr.*);
        for (entry.value_ptr.*.items) |esp| {
            try self.content.append(@intCast(esp.len));
            try self.content.appendSlice(esp);
        }
    }

    var file = try self.cwd.createFile("espmap", .{});
    defer file.close();
    try file.writeAll(self.content.items);
}

pub fn deserialize(self: *Self) !void {
    const Step = enum {
        get_mod_name,
        build_esp_list,
    };

    var step = Step.get_mod_name;
    var num_esps: usize = 0;
    var i: usize = 0;
    var esp_list: *std.ArrayList([]const u8) = undefined;
    while (i < self.content.items.len) {
        switch (step) {
            .get_mod_name => {
                num_esps = self.content.items[i];
                i += 1;
                const len = self.content.items[i];
                i += 1;
                const start = i;
                i += len;
                const end = i;
                const key = try self.allocator.dupe(u8, self.content.items[start..end]);
                const entry = try self.map.getOrPutValue(key, try std.ArrayList([]const u8).initCapacity(self.allocator, 5));
                esp_list = entry.value_ptr;
                if (num_esps != 0) step = .build_esp_list;
            },
            .build_esp_list => {
                const len = self.content.items[i];
                i += 1;
                const start = i;
                i += len;
                const end = i;
                const name = try self.allocator.dupe(u8, self.content.items[start..end]);
                try esp_list.append(name);
                if (esp_list.items.len == num_esps) step = .get_mod_name;
            },
        }
    }
}

pub fn deinit(self: *Self) void {
    self.content.deinit();

    var it = self.map.iterator();
    while (it.next()) |entry| {
        self.allocator.free(entry.key_ptr.*);
        for (entry.value_ptr.items) |name| self.allocator.free(name);
        entry.value_ptr.deinit();
    }
    self.map.deinit();
}
