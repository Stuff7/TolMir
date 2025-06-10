const std = @import("std");
const u = @import("utils.zig");
const c = @cImport({
    @cInclude("mxml.h");
});

const Self = @This();

root: *c.mxml_node_t,

pub fn init(allocator: std.mem.Allocator, path: []const u8) !Self {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const initial_contents = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    const contents = try u.utf16ToUtf8(allocator, initial_contents);
    defer allocator.free(contents);
    if (initial_contents.ptr != contents.ptr) allocator.free(initial_contents);

    const sanitized = u.stripInitialXmlComments(contents);

    const options = c.mxmlOptionsNew() orelse return error.MxmlInit;
    defer c.mxmlOptionsDelete(options);

    c.mxmlOptionsSetTypeValue(options, c.MXML_TYPE_OPAQUE);
    const doc = c.mxmlLoadString(null, options, sanitized.ptr);
    if (doc == null) return error.InvalidXml;

    var node = doc;
    while (node != null and c.mxmlGetType(node) != c.MXML_TYPE_ELEMENT) {
        node = c.mxmlGetNextSibling(node);
    }

    if (node) |root| return Self{ .root = root };

    return error.NoRootElement;
}

pub fn findElement(self: Self, name: [*:0]const u8) ?*c.mxml_node_t {
    return c.mxmlFindElement(self.root, self.root, name, null, null, c.MXML_DESCEND_ALL);
}

pub fn getText(node: *c.mxml_node_t) ?[:0]const u8 {
    const text = c.mxmlGetOpaque(node);
    if (text == null) return null;
    return std.mem.span(text);
}

pub fn deinit(self: Self) void {
    c.mxmlDelete(self.root);
}
