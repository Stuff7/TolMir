const std = @import("std");
const c = @cImport({
    @cInclude("mxml.h");
});

const Self = @This();

root: *c.mxml_node_t,

pub fn init(path: []const u8) !Self {
    const options = c.mxmlOptionsNew() orelse return error.MxmlInit;
    defer c.mxmlOptionsDelete(options);
    c.mxmlOptionsSetTypeValue(options, c.MXML_TYPE_OPAQUE);
    const doc = c.mxmlLoadFilename(null, options, path.ptr);
    if (doc == null) return error.InvalidXml;
    return Self{ .root = doc.? };
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
