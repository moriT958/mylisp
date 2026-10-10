//! The heap's allocator. Every allocation goes through it so the GC can see how many bytes are live.

const std = @import("std");
const Alignment = std.mem.Alignment;

pub const CountingAllocator = struct {
    backing: std.mem.Allocator,
    // Live bytes, not a running total: the GC compares this against a threshold.
    bytes_allocated: usize = 0,

    pub fn init(backing: std.mem.Allocator) CountingAllocator {
        return .{ .backing = backing };
    }

    // The interface points at self, so self must not move while it is in use.
    pub fn allocator(self: *CountingAllocator) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &vtable };
    }

    pub fn bytesAllocated(self: *const CountingAllocator) usize {
        return self.bytes_allocated;
    }

    const vtable: std.mem.Allocator.VTable = .{
        .alloc = alloc,
        .resize = resize,
        .remap = remap,
        .free = free,
    };

    fn from(ctx: *anyopaque) *CountingAllocator {
        return @ptrCast(@alignCast(ctx));
    }

    // Counting happens only after the backing call succeeds: a failed
    // allocation must not make the GC think memory is in use.
    fn alloc(ctx: *anyopaque, len: usize, alignment: Alignment, ret_addr: usize) ?[*]u8 {
        const self = from(ctx);
        const ptr = self.backing.rawAlloc(len, alignment, ret_addr) orelse return null;
        self.bytes_allocated += len;
        return ptr;
    }

    fn resize(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) bool {
        const self = from(ctx);
        if (!self.backing.rawResize(memory, alignment, new_len, ret_addr)) return false;
        self.bytes_allocated = self.bytes_allocated + new_len - memory.len;
        return true;
    }

    fn remap(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self = from(ctx);
        const ptr = self.backing.rawRemap(memory, alignment, new_len, ret_addr) orelse return null;
        self.bytes_allocated = self.bytes_allocated + new_len - memory.len;
        return ptr;
    }

    fn free(ctx: *anyopaque, memory: []u8, alignment: Alignment, ret_addr: usize) void {
        const self = from(ctx);
        self.backing.rawFree(memory, alignment, ret_addr);
        self.bytes_allocated -= memory.len;
    }
};

const testing = std.testing;

test "allocation and free return the count to zero" {
    var counting = CountingAllocator.init(testing.allocator);
    const a = counting.allocator();

    const bytes = try a.alloc(u8, 100);
    try testing.expectEqual(100, counting.bytesAllocated());
    a.free(bytes);
    try testing.expectEqual(0, counting.bytesAllocated());
}

test "the count uses bytes, not elements" {
    var counting = CountingAllocator.init(testing.allocator);
    const a = counting.allocator();

    const words = try a.alloc(u64, 10);
    try testing.expectEqual(80, counting.bytesAllocated());
    a.free(words);
}

test "a failed allocation is not counted" {
    var failing = testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 0 });
    var counting = CountingAllocator.init(failing.allocator());
    const a = counting.allocator();

    try testing.expectError(error.OutOfMemory, a.alloc(u8, 100));
    try testing.expectEqual(0, counting.bytesAllocated());
}

test "growing and shrinking keep the count equal to the live size" {
    var counting = CountingAllocator.init(testing.allocator);
    const a = counting.allocator();

    var bytes = try a.alloc(u8, 10);
    try testing.expectEqual(10, counting.bytesAllocated());
    bytes = try a.realloc(bytes, 1000);
    try testing.expectEqual(1000, counting.bytesAllocated());
    bytes = try a.realloc(bytes, 4);
    try testing.expectEqual(4, counting.bytesAllocated());
    a.free(bytes);
    try testing.expectEqual(0, counting.bytesAllocated());
}

test "resizing in place keeps the count equal to the live size" {
    var buffer: [256]u8 = undefined;
    var fixed = std.heap.FixedBufferAllocator.init(&buffer);
    var counting = CountingAllocator.init(fixed.allocator());
    const a = counting.allocator();

    var bytes = try a.alloc(u8, 64);
    try testing.expect(a.resize(bytes, 32));
    bytes.len = 32;
    try testing.expectEqual(32, counting.bytesAllocated());
    try testing.expect(a.resize(bytes, 48));
    bytes.len = 48;
    try testing.expectEqual(48, counting.bytesAllocated());
    a.free(bytes);
    try testing.expectEqual(0, counting.bytesAllocated());
}

test "a zero-length allocation is not counted" {
    var counting = CountingAllocator.init(testing.allocator);
    const a = counting.allocator();

    const empty = try a.alloc(u8, 0);
    try testing.expectEqual(0, counting.bytesAllocated());
    a.free(empty);
    try testing.expectEqual(0, counting.bytesAllocated());
}

test "standard containers are counted through it" {
    var counting = CountingAllocator.init(testing.allocator);
    const a = counting.allocator();

    var list: std.ArrayList(u32) = .empty;
    for (0..1000) |i| try list.append(a, @intCast(i));
    try testing.expectEqual(list.capacity * @sizeOf(u32), counting.bytesAllocated());
    list.deinit(a);
    try testing.expectEqual(0, counting.bytesAllocated());
}

test "an interface from one allocator does not touch another's count" {
    var first = CountingAllocator.init(testing.allocator);
    var second = CountingAllocator.init(testing.allocator);

    const bytes = try first.allocator().alloc(u8, 7);
    try testing.expectEqual(7, first.bytesAllocated());
    try testing.expectEqual(0, second.bytesAllocated());
    first.allocator().free(bytes);
}
