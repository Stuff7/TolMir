const std = @import("std");

const Allocator = std.mem.Allocator;

pub fn ansi(comptime txt: []const u8, comptime styles: []const u8) []const u8 {
    return "\x1b[" ++ styles ++ "m" ++ txt ++ "\x1b[0m";
}
