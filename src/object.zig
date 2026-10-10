//! Heap objects. Every object struct starts with an `Obj` header so a `*Obj` can stand for any of them.

pub const ObjKind = enum {
    pair,
    string,
    symbol,
};

pub const Obj = struct {
    kind: ObjKind,
    // Chains every object so the GC can visit them all.
    next: ?*Obj = null,
};
