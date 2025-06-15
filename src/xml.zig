const std = @import("std");
const u = @import("utils.zig");
const c = @cImport({
    @cInclude("mxml.h");
});

const Self = @This();

root: Node,

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

    if (node) |root| return Self{ .root = Node{ .node = root } };

    return error.NoRootElement;
}

pub fn findElement(self: Self, name: [*:0]const u8) ?Node {
    if (c.mxmlFindElement(self.root.node, self.root.node, name, null, null, c.MXML_DESCEND_ALL)) |node| {
        return Node{ .node = node };
    }
    return null;
}

pub fn deinit(self: Self) void {
    c.mxmlDelete(self.root.node);
}

pub const Node = struct {
    node: *c.mxml_node_t,

    pub fn getText(self: @This()) ?[:0]const u8 {
        const text = c.mxmlGetOpaque(self.node);
        if (text == null) return null;
        return std.mem.span(text);
    }

    pub fn getAttribute(self: @This(), attribute: []const u8) ?[]const u8 {
        if (c.mxmlElementGetAttr(self.node, attribute.ptr)) |attr| {
            return std.mem.span(attr);
        }
        return null;
    }

    pub fn getFirstChild(self: @This()) ?@This() {
        if (c.mxmlGetFirstChild(self.node)) |node| {
            return @This(){ .node = node };
        }
        return null;
    }

    pub fn getType(self: @This()) Type {
        return Type.init(c.mxmlGetType(self.node));
    }

    pub fn getElement(self: @This()) ?[]const u8 {
        if (c.mxmlGetElement(self.node)) |name| {
            return std.mem.span(name);
        }
        return null;
    }

    pub fn getNextSibling(self: @This()) ?@This() {
        if (c.mxmlGetNextSibling(self.node)) |node| {
            return @This(){ .node = node };
        }
        return null;
    }

    pub const Type = enum {
        cdata,
        comment,
        custom,
        declaration,
        directive,
        element,
        ignore,
        integer,
        @"opaque",
        real,
        text,
        unknown,

        fn init(n: c_int) @This() {
            return switch (n) {
                c.MXML_TYPE_CDATA => .cdata,
                c.MXML_TYPE_COMMENT => .comment,
                c.MXML_TYPE_CUSTOM => .custom,
                c.MXML_TYPE_DECLARATION => .declaration,
                c.MXML_TYPE_DIRECTIVE => .directive,
                c.MXML_TYPE_ELEMENT => .element,
                c.MXML_TYPE_IGNORE => .ignore,
                c.MXML_TYPE_INTEGER => .integer,
                c.MXML_TYPE_OPAQUE => .@"opaque",
                c.MXML_TYPE_REAL => .real,
                c.MXML_TYPE_TEXT => .text,
                else => .unknown,
            };
        }
    };
};
