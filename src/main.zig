const std = @import("std");
const Archive = @import("archive.zig");
const Xml = @import("xml.zig");

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try Args.init(allocator);
    defer args.deinit();

    var xml = try Xml.init(args.file);
    defer xml.deinit();

    if (xml.findElement("description")) |desc| {
        if (Xml.getText(desc)) |text| {
            std.debug.print("Description: {s}\n", .{text});
        } else {
            std.debug.print("No text: {?}\n", .{desc});
        }
    }

    // var reader = try Archive.init();
    // defer reader.deinit();
    //
    // try reader.open(args.file);
    //
    // while (reader.nextEntry()) |entry| {
    //     try reader.extractToFile(allocator, entry);
    // }
    //
    // try reader.close();
}

const Args = struct {
    allocator: std.mem.Allocator,
    args: [][:0]u8,
    file: []const u8,

    pub fn init(allocator: std.mem.Allocator) !Args {
        const args = try std.process.argsAlloc(allocator);

        if (args.len < 2) {
            std.debug.print("Usage: {s} <tsx_file>\n", .{args[0]});
            return error.MissingArgs;
        }

        return Args{
            .allocator = allocator,
            .args = args,
            .file = args[1],
        };
    }

    pub fn deinit(self: Args) void {
        defer std.process.argsFree(self.allocator, self.args);
    }
};
