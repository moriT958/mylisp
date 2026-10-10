//! The read-print loop and the file runner.
//! Evaluation does not exist yet, so each datum is only echoed back.

const std = @import("std");
const Heap = @import("heap.zig").Heap;
const Reader = @import("reader.zig").Reader;

const Allocator = std.mem.Allocator;

pub const Error = Allocator.Error || std.Io.Writer.Error || std.Io.Reader.Error || std.Io.Reader.StreamRemainingError;

const Run = struct {
    status: enum { ok, incomplete, failed },
    // Where the unfinished datum starts when the status is incomplete, so the
    // REPL can keep just that tail and read the rest on the next line.
    consumed: usize,
};

// TODO: compile and execute each datum; for now it is only echoed.
fn runSource(heap: *Heap, source: []const u8, out: *std.Io.Writer, err: *std.Io.Writer) Error!Run {
    var reader = Reader.init(heap, source);
    var consumed: usize = 0;
    while (true) {
        switch (try reader.read()) {
            .datum => |datum| {
                try out.print("{f}\n", .{datum});
                consumed = reader.position();
            },
            .eof => return .{ .status = .ok, .consumed = source.len },
            .incomplete => return .{ .status = .incomplete, .consumed = consumed },
            .invalid => |diagnostic| {
                // Flush first so stdout and stderr stay in order when they share a pipe.
                try out.flush();
                try err.print("error: {s} (line {d})\n", .{ diagnostic.message, diagnostic.line });
                try err.flush();
                return .{ .status = .failed, .consumed = reader.position() };
            },
        }
    }
}

// Unlike a file run, a REPL keeps going after an error.
pub fn runRepl(
    gpa: Allocator,
    in: *std.Io.Reader,
    out: *std.Io.Writer,
    err: *std.Io.Writer,
    interactive: bool,
) Error!u8 {
    var heap = Heap.init(gpa);
    defer heap.deinit();

    // Input that does not yet form a complete datum, carried over to the next line.
    var pending: std.ArrayList(u8) = .empty;
    defer pending.deinit(gpa);
    var line: std.Io.Writer.Allocating = .init(gpa);
    defer line.deinit();

    while (true) {
        // No prompt when piped, so the output stays comparable in tests.
        if (interactive) {
            try out.writeAll(if (pending.items.len == 0) "> " else "... ");
            try out.flush();
        }

        // Streams into a growing buffer because a line may be longer than any fixed one.
        line.clearRetainingCapacity();
        _ = in.streamDelimiterEnding(&line.writer, '\n') catch |e| switch (e) {
            // An allocating writer can only fail by running out of memory.
            error.WriteFailed => return error.OutOfMemory,
            error.ReadFailed => return e,
        };
        const had_newline = if (in.takeByte()) |_| true else |e| switch (e) {
            error.EndOfStream => false,
            error.ReadFailed => return e,
        };
        if (line.written().len == 0 and !had_newline) break;

        try pending.appendSlice(gpa, line.written());
        if (had_newline) try pending.append(gpa, '\n');

        const run = try runSource(&heap, pending.items, out, err);
        switch (run.status) {
            .incomplete => try pending.replaceRange(gpa, 0, run.consumed, &.{}),
            .ok, .failed => pending.clearRetainingCapacity(),
        }
        try out.flush();
    }

    if (interactive) {
        try out.writeByte('\n');
        try out.flush();
    }
    if (pending.items.len > 0 and !interactive) {
        try err.writeAll("error: unexpected end of input\n");
        try err.flush();
        return 1;
    }
    return 0;
}

// Stops at the first error: the rest of a broken file is not worth running.
pub fn runFile(
    gpa: Allocator,
    source: []const u8,
    out: *std.Io.Writer,
    err: *std.Io.Writer,
) Error!u8 {
    var heap = Heap.init(gpa);
    defer heap.deinit();

    const run = try runSource(&heap, source, out, err);
    try out.flush();
    if (run.status == .incomplete) {
        try err.writeAll("error: unexpected end of input\n");
        try err.flush();
    }
    return if (run.status == .ok) 0 else 1;
}

const testing = std.testing;

const Session = struct {
    out: []u8,
    err: []u8,
    status: u8,

    fn deinit(self: Session) void {
        testing.allocator.free(self.out);
        testing.allocator.free(self.err);
    }
};

fn sessionOf(input: []const u8, interactive: bool, file_mode: bool) !Session {
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    var err: std.Io.Writer.Allocating = .init(testing.allocator);
    defer err.deinit();

    const status = if (file_mode)
        try runFile(testing.allocator, input, &out.writer, &err.writer)
    else blk: {
        var in: std.Io.Reader = .fixed(input);
        break :blk try runRepl(testing.allocator, &in, &out.writer, &err.writer, interactive);
    };

    return .{
        .out = try testing.allocator.dupe(u8, out.written()),
        .err = try testing.allocator.dupe(u8, err.written()),
        .status = status,
    };
}

fn expectRepl(input: []const u8, out: []const u8, err: []const u8, status: u8) !void {
    const session = try sessionOf(input, false, false);
    defer session.deinit();
    try testing.expectEqualStrings(out, session.out);
    try testing.expectEqualStrings(err, session.err);
    try testing.expectEqual(status, session.status);
}

fn expectFile(input: []const u8, out: []const u8, err: []const u8, status: u8) !void {
    const session = try sessionOf(input, false, true);
    defer session.deinit();
    try testing.expectEqualStrings(out, session.out);
    try testing.expectEqualStrings(err, session.err);
    try testing.expectEqual(status, session.status);
}

test "each datum is echoed on its own line" {
    try expectRepl("42 foo \"hi\" #t ()\n(+ 1 2)\n'x\n", "42\nfoo\n\"hi\"\n#t\n()\n(+ 1 2)\n(quote x)\n", "", 0);
    try expectFile("42 foo \"hi\" #t ()\n(+ 1 2)\n'x\n", "42\nfoo\n\"hi\"\n#t\n()\n(+ 1 2)\n(quote x)\n", "", 0);
}

test "a datum may span several lines" {
    const source = "(a\n  b\n  (c))\n";
    try expectRepl(source, "(a b (c))\n", "", 0);
    try expectFile(source, "(a b (c))\n", "", 0);
}

test "a last line without a newline is still read" {
    try expectRepl("1\n2", "1\n2\n", "", 0);
    try expectFile("1\n2", "1\n2\n", "", 0);
}

test "empty input, blank lines, and comments print nothing" {
    try expectRepl("", "", "", 0);
    try expectRepl("\n\n; comment\n   \n", "", "", 0);
    try expectFile("", "", "", 0);
}

test "two data on one line, and one split across lines after another" {
    try expectRepl("(a) (b\nc)\n", "(a)\n(b c)\n", "", 0);
}

test "the REPL reports an error and keeps going" {
    try expectRepl("(1 2))\n(ok)\n", "(1 2)\n(ok)\n", "error: unexpected ')' (line 1)\n", 0);
}

test "a file run stops at the first error" {
    try expectFile("(a)\n)\n(b)\n", "(a)\n", "error: unexpected ')' (line 2)\n", 1);
}

test "input that ends inside a datum is an error at the end" {
    try expectRepl("(1 2\n", "", "error: unexpected end of input\n", 1);
    try expectFile("(1 2\n", "", "error: unexpected end of input\n", 1);
    try expectRepl("(1 2", "", "error: unexpected end of input\n", 1);
}

test "output before an unfinished datum is kept" {
    try expectRepl("1\n(2\n", "1\n", "error: unexpected end of input\n", 1);
    try expectFile("1\n(2\n", "1\n", "error: unexpected end of input\n", 1);
}

test "a datum carried over a line does not echo the data before it again" {
    try expectRepl("1 (2\n3)\n", "1\n(2 3)\n", "", 0);
}

test "an error discards the rest of its line only" {
    try expectRepl("#x (lost)\n(kept)\n", "(kept)\n", "error: invalid # syntax (line 1)\n", 0);
}

test "a very long line is read whole" {
    const long = try testing.allocator.alloc(u8, 1 << 20);
    defer testing.allocator.free(long);
    @memset(long, 'a');
    const input = try std.fmt.allocPrint(testing.allocator, "{s}\n", .{long});
    defer testing.allocator.free(input);
    const expected = try std.fmt.allocPrint(testing.allocator, "{s}\n", .{long});
    defer testing.allocator.free(expected);

    try expectRepl(input, expected, "", 0);
}

test "an interactive session prompts, and continues with a different prompt" {
    const session = try sessionOf("1\n(2\n3)\n", true, false);
    defer session.deinit();
    try testing.expectEqualStrings("> 1\n> ... (2 3)\n> \n", session.out);
    try testing.expectEqualStrings("", session.err);
    try testing.expectEqual(0, session.status);
}

test "an interactive session ending mid-datum is not an error" {
    const session = try sessionOf("(1\n", true, false);
    defer session.deinit();
    try testing.expectEqual(0, session.status);
    try testing.expectEqualStrings("", session.err);
}

test "windows line endings are whitespace" {
    try expectRepl("(a\r\nb)\r\n", "(a b)\n", "", 0);
}

// The output writers discard, so the only allocations are the REPL's own and
// any WriteFailed that comes back would be a REPL bug, not the harness's.
fn runForLeaks(gpa: Allocator, input: []const u8) !void {
    var no_buffer: [0]u8 = .{};
    var out: std.Io.Writer.Discarding = .init(&no_buffer);
    var err: std.Io.Writer.Discarding = .init(&no_buffer);
    var in: std.Io.Reader = .fixed(input);
    _ = try runRepl(gpa, &in, &out.writer, &err.writer, false);
}

test "running out of memory at any step leaks nothing" {
    try testing.checkAllAllocationFailures(testing.allocator, runForLeaks, .{"(a \"s\" 'b)\n(c\nd) )\n"});
}
