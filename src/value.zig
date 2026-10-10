//! Runtime values: nil, booleans, integers, and references to heap objects.

const std = @import("std");
const Obj = @import("object.zig").Obj;

pub const Value = union(enum) {
    nil,
    boolean: bool,
    int: i64,
    obj: *Obj,

    // Only #f is false: nil and 0 are true, in Scheme.
    pub fn isTruthy(self: Value) bool {
        return switch (self) {
            .boolean => |b| b,
            .nil, .int, .obj => true,
        };
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

const testing = std.testing;

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
