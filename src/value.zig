//! Runtime values: nil, booleans, integers, and references to heap objects.

const std = @import("std");
const object = @import("object.zig");
const Obj = object.Obj;
const ObjPair = object.ObjPair;
const ObjString = object.ObjString;
const ObjSymbol = object.ObjSymbol;

pub const Value = union(enum) {
    nil,
    boolean: bool,
    int: i64,
    obj: *Obj,

    pub fn asPair(self: Value) ?*ObjPair {
        return switch (self) {
            .obj => |obj| if (obj.kind == .pair) ObjPair.fromObj(obj) else null,
            .nil, .boolean, .int => null,
        };
    }

    pub fn asString(self: Value) ?*ObjString {
        return switch (self) {
            .obj => |obj| if (obj.kind == .string) ObjString.fromObj(obj) else null,
            .nil, .boolean, .int => null,
        };
    }

    pub fn asSymbol(self: Value) ?*ObjSymbol {
        return switch (self) {
            .obj => |obj| if (obj.kind == .symbol) ObjSymbol.fromObj(obj) else null,
            .nil, .boolean, .int => null,
        };
    }

    // Only #f is false: nil and 0 are true, in Scheme.
    pub fn isTruthy(self: Value) bool {
        return switch (self) {
            .boolean => |b| b,
            .nil, .int, .obj => true,
        };
    }

    // Prints like Scheme's `write`: strings stay quoted so the output reads back as the same datum.
    pub fn format(self: Value, w: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (self) {
            .nil => try w.writeAll("()"),
            .boolean => |b| try w.writeAll(if (b) "#t" else "#f"),
            .int => |n| try w.print("{d}", .{n}),
            .obj => |obj| switch (obj.kind) {
                .pair => try writeList(ObjPair.fromObj(obj), w),
                .string => try writeString(ObjString.fromObj(obj).chars, w),
                .symbol => try w.writeAll(ObjSymbol.fromObj(obj).chars),
            },
        }
    }

    // eq? semantics: objects compare by identity.
    pub fn eql(a: Value, b: Value) bool {
        if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
        return switch (a) {
            .nil => true,
            .boolean => |x| x == b.boolean,
            .int => |x| x == b.int,
            .obj => |x| x == b.obj,
        };
    }
};

// Follows the cdr chain in a loop so a long list does not recurse once per element.
fn writeList(first: *ObjPair, w: *std.Io.Writer) std.Io.Writer.Error!void {
    try w.writeByte('(');
    try first.car.format(w);
    var rest = first.cdr;
    while (rest.asPair()) |pair| : (rest = pair.cdr) {
        try w.writeByte(' ');
        try pair.car.format(w);
    }
    if (rest != .nil) {
        try w.writeAll(" . ");
        try rest.format(w);
    }
    try w.writeByte(')');
}

fn writeString(chars: []const u8, w: *std.Io.Writer) std.Io.Writer.Error!void {
    try w.writeByte('"');
    for (chars) |c| {
        if (c == '"' or c == '\\') try w.writeByte('\\');
        try w.writeByte(c);
    }
    try w.writeByte('"');
}

const testing = std.testing;
const Heap = @import("heap.zig").Heap;

fn printed(value: Value) ![]u8 {
    return std.fmt.allocPrint(testing.allocator, "{f}", .{value});
}

fn expectPrinted(expected: []const u8, value: Value) !void {
    const text = try printed(value);
    defer testing.allocator.free(text);
    try testing.expectEqualStrings(expected, text);
}

fn list(heap: *Heap, items: []const Value, tail: Value) !Value {
    var result = tail;
    var i = items.len;
    while (i > 0) {
        i -= 1;
        result = (try heap.newPair(items[i], result)).value();
    }
    return result;
}

test "atoms print as their Scheme syntax" {
    try expectPrinted("()", .nil);
    try expectPrinted("#t", .{ .boolean = true });
    try expectPrinted("#f", .{ .boolean = false });
    try expectPrinted("0", .{ .int = 0 });
    try expectPrinted("-42", .{ .int = -42 });
    try expectPrinted("9223372036854775807", .{ .int = std.math.maxInt(i64) });
    try expectPrinted("-9223372036854775808", .{ .int = std.math.minInt(i64) });
}

test "symbols print as their bare name" {
    var heap = Heap.init(testing.allocator);
    defer heap.deinit();

    try expectPrinted("foo", (try heap.intern("foo")).value());
    try expectPrinted("null?", (try heap.intern("null?")).value());
    try expectPrinted("", (try heap.intern("")).value());
}

test "strings print quoted with quotes and backslashes escaped" {
    var heap = Heap.init(testing.allocator);
    defer heap.deinit();

    try expectPrinted("\"hi\"", (try heap.newString("hi")).value());
    try expectPrinted("\"\"", (try heap.newString("")).value());
    try expectPrinted("\"a\\\"b\"", (try heap.newString("a\"b")).value());
    try expectPrinted("\"a\\\\b\"", (try heap.newString("a\\b")).value());
}

test "a newline inside a string is printed as is" {
    var heap = Heap.init(testing.allocator);
    defer heap.deinit();

    try expectPrinted("\"a\nb\"", (try heap.newString("a\nb")).value());
}

test "a proper list prints its elements in order" {
    var heap = Heap.init(testing.allocator);
    defer heap.deinit();

    const items = [_]Value{ .{ .int = 1 }, .{ .int = 2 }, .{ .int = 3 } };
    try expectPrinted("(1 2 3)", try list(&heap, &items, .nil));
    try expectPrinted("(1)", try list(&heap, items[0..1], .nil));
}

test "a pair whose cdr is not a list prints with a dot" {
    var heap = Heap.init(testing.allocator);
    defer heap.deinit();

    try expectPrinted("(1 . 2)", (try heap.newPair(.{ .int = 1 }, .{ .int = 2 })).value());
    const items = [_]Value{ .{ .int = 1 }, .{ .int = 2 } };
    try expectPrinted("(1 2 . 3)", try list(&heap, &items, .{ .int = 3 }));
}

test "nested lists and mixed contents print recursively" {
    var heap = Heap.init(testing.allocator);
    defer heap.deinit();

    const inner = try list(&heap, &.{ (try heap.newString("s")).value(), .nil, .{ .boolean = false } }, .nil);
    const outer = try list(&heap, &.{ .{ .int = 1 }, inner, (try heap.intern("x")).value() }, .nil);
    try expectPrinted("(1 (\"s\" () #f) x)", outer);
    try expectPrinted("(())", try list(&heap, &.{.nil}, .nil));
}

test "a very long list prints without recursing per element" {
    var heap = Heap.init(testing.allocator);
    defer heap.deinit();

    var long: Value = .nil;
    for (0..100_000) |_| long = (try heap.newPair(.{ .int = 7 }, long)).value();
    const text = try printed(long);
    defer testing.allocator.free(text);
    try testing.expectEqual(2 + 100_000 * 2 - 1, text.len);
    try testing.expect(std.mem.startsWith(u8, text, "(7 7 7"));
}

test "printing reports a failing writer instead of swallowing it" {
    var heap = Heap.init(testing.allocator);
    defer heap.deinit();

    var buffer: [2]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buffer);
    const items = [_]Value{ .{ .int = 1 }, .{ .int = 2 } };
    const value = try list(&heap, &items, .nil);
    try testing.expectError(error.WriteFailed, value.format(&w));
}

test "only #f is falsy" {
    var obj: Obj = .{ .kind = .pair };
    const nil: Value = .nil;
    try testing.expect(!(Value{ .boolean = false }).isTruthy());
    try testing.expect((Value{ .boolean = true }).isTruthy());
    try testing.expect(nil.isTruthy());
    try testing.expect((Value{ .int = 0 }).isTruthy());
    try testing.expect((Value{ .obj = &obj }).isTruthy());
}

test "eql compares integers and booleans by value" {
    try testing.expect(Value.eql(.{ .int = 3 }, .{ .int = 3 }));
    try testing.expect(!Value.eql(.{ .int = 3 }, .{ .int = 4 }));
    try testing.expect(Value.eql(.{ .int = std.math.minInt(i64) }, .{ .int = std.math.minInt(i64) }));
    try testing.expect(Value.eql(.{ .boolean = true }, .{ .boolean = true }));
    try testing.expect(!Value.eql(.{ .boolean = true }, .{ .boolean = false }));
    try testing.expect(Value.eql(.nil, .nil));
}

test "eql never equates different types" {
    try testing.expect(!Value.eql(.{ .int = 0 }, .{ .boolean = false }));
    try testing.expect(!Value.eql(.nil, .{ .boolean = false }));
    try testing.expect(!Value.eql(.nil, .{ .int = 0 }));
}

test "eql compares objects by identity" {
    var a: Obj = .{ .kind = .pair };
    var b: Obj = .{ .kind = .pair };
    try testing.expect(Value.eql(.{ .obj = &a }, .{ .obj = &a }));
    try testing.expect(!Value.eql(.{ .obj = &a }, .{ .obj = &b }));
}
