const std = @import("std");
const u = @import("utils.zig");
const State = @import("state.zig");

const Allocator = std.mem.Allocator;

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var state = try State.init(allocator);
    defer state.deinit() catch |err| std.debug.print("Error: {}\n", .{err});

    if (state.isMissingConfig()) return;

    switch (state.step) {
        .help => State.showUsage(state.args),
        .set => try state.updateConfig(),
        .install => try state.installMods(),
        .mount => try state.writeMountScripts(),
    }
}
