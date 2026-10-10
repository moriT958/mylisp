//! The object heap: allocates objects, chains them, and frees them all at once.

const std = @import("std");
const CountingAllocator = @import("memory.zig").CountingAllocator;
const object = @import("object.zig");
const Obj = object.Obj;
const ObjPair = object.ObjPair;
const ObjString = object.ObjString;
const Value = @import("value.zig").Value;

pub const Heap = struct {
    counting: CountingAllocator,
    // Most recently created first.
    objects: ?*Obj = null,

    pub fn init(backing: std.mem.Allocator) Heap {
        return .{ .counting = CountingAllocator.init(backing) };
    }

    pub fn deinit(self: *Heap) void {
        var current = self.objects;
        while (current) |obj| {
            // Read next first: freeing the object invalidates it.
            current = obj.next;
            self.freeObject(obj);
        }
        self.objects = null;
    }

    pub fn bytesAllocated(self: *const Heap) usize {
        return self.counting.bytesAllocated();
    }

    pub fn newPair(self: *Heap, car: Value, cdr: Value) !*ObjPair {
        const pair = try self.allocator().create(ObjPair);
        pair.* = .{ .obj = .{ .kind = .pair, .next = self.objects }, .car = car, .cdr = cdr };
        self.objects = &pair.obj;
        return pair;
    }

    pub fn newString(self: *Heap, chars: []const u8) !*ObjString {
        const a = self.allocator();
        const string = try a.create(ObjString);
        errdefer a.destroy(string);
        const copy = try a.dupe(u8, chars);
        string.* = .{ .obj = .{ .kind = .string, .next = self.objects }, .chars = copy };
        self.objects = &string.obj;
        return string;
    }

    // Built per call, not stored: the interface points at self.counting, so it
    // would dangle if the heap moved.
    fn allocator(self: *Heap) std.mem.Allocator {
        return self.counting.allocator();
    }

    fn freeObject(self: *Heap, obj: *Obj) void {
        const a = self.allocator();
        switch (obj.kind) {
            .pair => a.destroy(ObjPair.fromObj(obj)),
            .string => {
                const string = ObjString.fromObj(obj);
                a.free(string.chars);
                a.destroy(string);
            },
        }
    }
};

const testing = std.testing;

test "a pair holds its car and cdr" {
    var heap = Heap.init(testing.allocator);
    defer heap.deinit();

    const pair = try heap.newPair(.{ .int = 1 }, .{ .boolean = true });
    try testing.expectEqual(Value{ .int = 1 }, pair.car);
    try testing.expectEqual(Value{ .boolean = true }, pair.cdr);
    try testing.expectEqual(pair, pair.value().asPair().?);
}

test "a list is a chain of pairs ending in nil" {
    var heap = Heap.init(testing.allocator);
    defer heap.deinit();

    var list: Value = .nil;
    var i: i64 = 3;
    while (i >= 1) : (i -= 1) list = (try heap.newPair(.{ .int = i }, list)).value();

    var expected: i64 = 1;
    var current = list;
    while (current.asPair()) |pair| : (current = pair.cdr) {
        try testing.expectEqual(Value{ .int = expected }, pair.car);
        expected += 1;
    }
    try testing.expectEqual(4, expected);
    try testing.expect(current == .nil);
}

test "a string copies its bytes" {
    var heap = Heap.init(testing.allocator);
    defer heap.deinit();

    var source = [_]u8{ 'a', 'b', 'c' };
    const string = try heap.newString(&source);
    source[0] = 'z';
    try testing.expectEqualStrings("abc", string.chars);
}

test "a string may be empty or contain a NUL byte" {
    var heap = Heap.init(testing.allocator);
    defer heap.deinit();

    const empty = try heap.newString("");
    try testing.expectEqual(0, empty.chars.len);
    const with_nul = try heap.newString("a\x00b");
    try testing.expectEqualStrings("a\x00b", with_nul.chars);
}

test "strings with equal text are different objects" {
    var heap = Heap.init(testing.allocator);
    defer heap.deinit();

    const a = try heap.newString("same");
    const b = try heap.newString("same");
    try testing.expect(!Value.eql(a.value(), b.value()));
    try testing.expect(Value.eql(a.value(), a.value()));
}

test "asPair and asString tell the kinds apart" {
    var heap = Heap.init(testing.allocator);
    defer heap.deinit();

    const pair = (try heap.newPair(.nil, .nil)).value();
    const string = (try heap.newString("s")).value();
    try testing.expect(pair.asPair() != null);
    try testing.expect(pair.asString() == null);
    try testing.expect(string.asString() != null);
    try testing.expect(string.asPair() == null);
    const nil: Value = .nil;
    try testing.expect(nil.asPair() == null);
    try testing.expect((Value{ .int = 5 }).asString() == null);
}

test "bytes are counted per object and the count returns to zero" {
    var heap = Heap.init(testing.allocator);

    _ = try heap.newPair(.nil, .nil);
    try testing.expectEqual(@sizeOf(ObjPair), heap.bytesAllocated());
    _ = try heap.newString("hello");
    try testing.expectEqual(@sizeOf(ObjPair) + @sizeOf(ObjString) + 5, heap.bytesAllocated());

    heap.deinit();
    try testing.expectEqual(0, heap.bytesAllocated());
}

test "new objects go to the front of the chain" {
    var heap = Heap.init(testing.allocator);
    defer heap.deinit();

    const first = try heap.newPair(.nil, .nil);
    const second = try heap.newString("x");
    try testing.expectEqual(&second.obj, heap.objects.?);
    try testing.expectEqual(&first.obj, heap.objects.?.next.?);
    try testing.expect(first.obj.next == null);
}

test "deinit frees many objects and may be repeated" {
    var heap = Heap.init(testing.allocator);

    for (0..10_000) |i| {
        _ = try heap.newPair(.{ .int = @intCast(i) }, .nil);
        _ = try heap.newString("some text");
    }
    heap.deinit();
    try testing.expectEqual(0, heap.bytesAllocated());
    try testing.expect(heap.objects == null);
    heap.deinit();
    try testing.expectEqual(0, heap.bytesAllocated());
}

test "a pair that cannot be allocated leaves the heap unchanged" {
    var failing = testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 0 });
    var heap = Heap.init(failing.allocator());
    defer heap.deinit();

    try testing.expectError(error.OutOfMemory, heap.newPair(.nil, .nil));
    try testing.expect(heap.objects == null);
    try testing.expectEqual(0, heap.bytesAllocated());
}

test "a string whose bytes cannot be allocated releases its header" {
    // First allocation (the header) succeeds, the second (the bytes) fails.
    var failing = testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 1 });
    var heap = Heap.init(failing.allocator());
    defer heap.deinit();

    try testing.expectError(error.OutOfMemory, heap.newString("hello"));
    try testing.expect(heap.objects == null);
    try testing.expectEqual(0, heap.bytesAllocated());
}
