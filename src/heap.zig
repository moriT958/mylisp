//! The object heap: allocates objects, chains them, and frees them all at once.

const std = @import("std");
const CountingAllocator = @import("memory.zig").CountingAllocator;
const object = @import("object.zig");
const Obj = object.Obj;
const ObjPair = object.ObjPair;
const ObjString = object.ObjString;
const ObjSymbol = object.ObjSymbol;
const Value = @import("value.zig").Value;

pub const Heap = struct {
    counting: CountingAllocator,
    // Most recently created first.
    objects: ?*Obj = null,
    // Keys are the symbols' own name bytes, so lookup by content needs no extra copy.
    symbols: std.StringHashMapUnmanaged(*ObjSymbol) = .empty,

    pub fn init(backing: std.mem.Allocator) Heap {
        return .{ .counting = CountingAllocator.init(backing) };
    }

    pub fn deinit(self: *Heap) void {
        self.symbols.deinit(self.allocator());
        self.symbols = .empty;
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

    pub fn intern(self: *Heap, name: []const u8) !*ObjSymbol {
        if (self.symbols.get(name)) |existing| return existing;

        const a = self.allocator();
        const symbol = try a.create(ObjSymbol);
        errdefer a.destroy(symbol);
        const copy = try a.dupe(u8, name);
        errdefer a.free(copy);
        // Last fallible step: once the table has the symbol, nothing below can fail.
        try self.symbols.put(a, copy, symbol);
        symbol.* = .{ .obj = .{ .kind = .symbol, .next = self.objects }, .chars = copy };
        self.objects = &symbol.obj;
        return symbol;
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
            .symbol => {
                const symbol = ObjSymbol.fromObj(obj);
                a.free(symbol.chars);
                a.destroy(symbol);
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

test "the same name interns to the same symbol" {
    var heap = Heap.init(testing.allocator);
    defer heap.deinit();

    const first = try heap.intern("foo");
    const second = try heap.intern("foo");
    try testing.expectEqual(first, second);
    try testing.expectEqualStrings("foo", first.chars);
}

test "different names are different symbols" {
    var heap = Heap.init(testing.allocator);
    defer heap.deinit();

    const foo = try heap.intern("foo");
    try testing.expect(foo != try heap.intern("bar"));
    try testing.expect(foo != try heap.intern("fo"));
    try testing.expect(foo != try heap.intern("fooo"));
    try testing.expect(foo != try heap.intern("Foo"));
}

test "the empty name is a valid symbol" {
    var heap = Heap.init(testing.allocator);
    defer heap.deinit();

    const empty = try heap.intern("");
    try testing.expectEqual(0, empty.chars.len);
    try testing.expectEqual(empty, try heap.intern(""));
}

test "a symbol copies its name" {
    var heap = Heap.init(testing.allocator);
    defer heap.deinit();

    var source = [_]u8{ 'a', 'b' };
    const symbol = try heap.intern(&source);
    source[0] = 'z';
    try testing.expectEqualStrings("ab", symbol.chars);
    try testing.expectEqual(symbol, try heap.intern("ab"));
}

test "a symbol and a string with the same text are different values" {
    var heap = Heap.init(testing.allocator);
    defer heap.deinit();

    const symbol = (try heap.intern("foo")).value();
    const string = (try heap.newString("foo")).value();
    try testing.expect(!Value.eql(symbol, string));
    try testing.expect(symbol.asSymbol() != null and symbol.asString() == null);
    try testing.expect(string.asString() != null and string.asSymbol() == null);
    try testing.expect(symbol.asPair() == null);
}

test "many symbols stay findable and pointer-stable while the table grows" {
    var heap = Heap.init(testing.allocator);
    defer heap.deinit();

    var symbols: [2000]*ObjSymbol = undefined;
    var buffer: [16]u8 = undefined;
    for (&symbols, 0..) |*slot, i| {
        slot.* = try heap.intern(try std.fmt.bufPrint(&buffer, "sym-{d}", .{i}));
    }
    for (symbols, 0..) |expected, i| {
        const name = try std.fmt.bufPrint(&buffer, "sym-{d}", .{i});
        try testing.expectEqual(expected, try heap.intern(name));
    }
    try testing.expectEqual(2000, heap.symbols.count());
}

test "heaps have independent symbol tables" {
    var first = Heap.init(testing.allocator);
    defer first.deinit();
    var second = Heap.init(testing.allocator);
    defer second.deinit();

    const a = try first.intern("foo");
    const b = try second.intern("foo");
    try testing.expect(a != b);
}

test "interning counts its table and releases everything on deinit" {
    var heap = Heap.init(testing.allocator);

    _ = try heap.intern("one");
    _ = try heap.intern("two");
    try testing.expect(heap.bytesAllocated() > 2 * @sizeOf(ObjSymbol));
    heap.deinit();
    try testing.expectEqual(0, heap.bytesAllocated());
    try testing.expectEqual(0, heap.symbols.count());
}

test "a failed intern leaves the heap unchanged at every allocation step" {
    // The steps are the object header, the name bytes, and the table storage.
    for (0..3) |fail_index| {
        var failing = testing.FailingAllocator.init(testing.allocator, .{ .fail_index = fail_index });
        var heap = Heap.init(failing.allocator());
        defer heap.deinit();

        try testing.expectError(error.OutOfMemory, heap.intern("foo"));
        try testing.expect(heap.objects == null);
        try testing.expectEqual(0, heap.symbols.count());
        try testing.expectEqual(0, heap.bytesAllocated());
    }
}
