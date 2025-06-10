const std = @import("std");

const Allocator = std.mem.Allocator;

pub fn ansi(comptime txt: []const u8, comptime styles: []const u8) []const u8 {
    return "\x1b[" ++ styles ++ "m" ++ txt ++ "\x1b[0m";
}

/// Caller needs to check if a free is necessary on their end.
pub fn utf16ToUtf8(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    if (input.len < 2 or input[0] != 0xFF or input[1] != 0xFE) {
        return input;
    }

    var i: usize = 2;
    var out = std.ArrayList(u8).init(allocator);
    defer out.deinit();

    while (i + 1 < input.len) {
        const lo = input[i];
        const hi = input[i + 1];
        const code_unit: u16 = (@as(u16, hi) << 8) | lo;
        i += 2;

        if (code_unit >= 0xD800 and code_unit <= 0xDBFF) {
            if (i + 1 >= input.len) return error.InvalidSurrogatePair;
            const lo_lo = input[i];
            const lo_hi = input[i + 1];
            const low_unit: u16 = (@as(u16, lo_hi) << 8) | lo_lo;
            i += 2;

            if (low_unit < 0xDC00 or low_unit > 0xDFFF) return error.InvalidSurrogatePair;

            const high = code_unit - 0xD800;
            const low = low_unit - 0xDC00;
            const codepoint: u21 = @intCast(0x10000 + (@as(u32, high) << 10 | low));

            var cbuf: [4]u8 = undefined;
            try out.appendSlice(cbuf[0..try std.unicode.utf8Encode(codepoint, &cbuf)]);
        } else if (code_unit >= 0xDC00 and code_unit <= 0xDFFF) {
            return error.UnexpectedLowSurrogate;
        } else {
            var cbuf: [4]u8 = undefined;
            try out.appendSlice(cbuf[0..try std.unicode.utf8Encode(code_unit, &cbuf)]);
        }
    }

    return try out.toOwnedSlice();
}

pub fn stripInitialXmlComments(xml: []const u8) []const u8 {
    var pos: usize = 0;

    while (pos < xml.len) {
        while (pos < xml.len and std.ascii.isWhitespace(xml[pos])) {
            pos += 1;
        }

        if (pos + 4 <= xml.len and std.mem.eql(u8, xml[pos .. pos + 4], "<!--")) {
            pos += 4;

            while (pos + 3 <= xml.len) {
                if (std.mem.eql(u8, xml[pos .. pos + 3], "-->")) {
                    pos += 3;
                    break;
                }
                pos += 1;
            } else {
                break;
            }
        } else {
            break;
        }
    }

    return xml[pos..];
}
