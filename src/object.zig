//! Heap objects. Every object struct starts with an `Obj` header so a `*Obj` can stand for any of them.

const std = @import("std");
const Value = @import("value.zig").Value;

pub const ObjKind = enum {
    pair,
    string,
};

pub const Obj = struct {
    kind: ObjKind,
    // Chains every object so the GC can visit them all.
    next: ?*Obj = null,
};

pub const ObjPair = struct {
    obj: Obj,
    car: Value,
    cdr: Value,

    pub fn fromObj(obj: *Obj) *ObjPair {
        std.debug.assert(obj.kind == .pair);
        return @fieldParentPtr("obj", obj);
    }

    pub fn value(self: *ObjPair) Value {
        return .{ .obj = &self.obj };
    }
};

pub const ObjString = struct {
    obj: Obj,
    // Owned by the heap and freed with the object.
    chars: []u8,

    pub fn fromObj(obj: *Obj) *ObjString {
        std.debug.assert(obj.kind == .string);
        return @fieldParentPtr("obj", obj);
    }

    pub fn value(self: *ObjString) Value {
        return .{ .obj = &self.obj };
    }
};
