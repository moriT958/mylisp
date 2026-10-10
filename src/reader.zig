//! Reads S-expressions from source text, one datum at a time.

const std = @import("std");
const Heap = @import("heap.zig").Heap;
const lexer_mod = @import("lexer.zig");
const Lexer = lexer_mod.Lexer;
const Token = lexer_mod.Token;
const ObjPair = @import("object.zig").ObjPair;
const Value = @import("value.zig").Value;

// Recursion depth is bounded so hostile input cannot overflow the stack.
const max_nesting = 1000;

pub const Diagnostic = struct {
    line: u32,
    // A static string, never a slice of the source.
    message: []const u8,
};

pub const Result = union(enum) {
    datum: Value,
    // The input is used up and no datum was started.
    eof,
    // The input ended inside a datum, e.g. "(1 2". A REPL can ask for more lines.
    incomplete,
    invalid: Diagnostic,
};

// Anything but memory exhaustion is a normal Result, not an error: bad input is expected.
pub const Error = std.mem.Allocator.Error;

pub const Reader = struct {
    heap: *Heap,
    lexer: Lexer,

    pub fn init(heap: *Heap, source: []const u8) Reader {
        return .{ .heap = heap, .lexer = Lexer.init(source) };
    }

    // Bytes of the source consumed so far. After a complete datum this is where
    // the next one starts; after `incomplete` it is the end, so a caller that
    // wants to resume must remember the position from before the call.
    pub fn position(self: *const Reader) usize {
        return self.lexer.pos;
    }

    pub fn read(self: *Reader) Error!Result {
        return self.readToken(self.lexer.next(), 0);
    }

    // depth counts the open lists and quotes around the datum being read.
    fn readToken(self: *Reader, token: Token, depth: u32) Error!Result {
        switch (token.kind) {
            .eof => return if (depth == 0) .eof else .incomplete,
            .invalid => return invalid(token.line, token.lexeme),
            .right_paren => return invalid(token.line, "unexpected ')'"),
            .left_paren => {
                if (depth >= max_nesting) return invalid(token.line, "nesting too deep");
                return self.readList(depth + 1);
            },
            .quote => {
                if (depth >= max_nesting) return invalid(token.line, "nesting too deep");
                return self.readQuote(depth + 1);
            },
            .int => {
                const n = std.fmt.parseInt(i64, token.lexeme, 10) catch |err| switch (err) {
                    error.Overflow => return invalid(token.line, "integer out of range"),
                    // The lexer only hands over a sign and digits.
                    error.InvalidCharacter => unreachable,
                };
                return .{ .datum = .{ .int = n } };
            },
            .string => return self.readString(token),
            .symbol => return .{ .datum = (try self.heap.intern(token.lexeme)).value() },
            .true_literal => return .{ .datum = .{ .boolean = true } },
            .false_literal => return .{ .datum = .{ .boolean = false } },
        }
    }

    // Appends in a loop, not by recursing on the tail, so a long list uses no extra stack.
    fn readList(self: *Reader, depth: u32) Error!Result {
        var head: Value = .nil;
        var tail: ?*ObjPair = null;
        while (true) {
            const token = self.lexer.next();
            if (token.kind == .right_paren) return .{ .datum = head };
            if (token.kind == .eof) return .incomplete;

            const result = try self.readToken(token, depth);
            const element = switch (result) {
                .datum => |value| value,
                .eof, .incomplete, .invalid => return result,
            };

            const pair = try self.heap.newPair(element, .nil);
            if (tail) |last| {
                last.cdr = pair.value();
            } else {
                head = pair.value();
            }
            tail = pair;
        }
    }

    fn readQuote(self: *Reader, depth: u32) Error!Result {
        const result = try self.readToken(self.lexer.next(), depth);
        const datum = switch (result) {
            .datum => |value| value,
            .eof, .incomplete => return .incomplete,
            .invalid => return result,
        };

        const quote = (try self.heap.intern("quote")).value();
        const rest = (try self.heap.newPair(datum, .nil)).value();
        return .{ .datum = (try self.heap.newPair(quote, rest)).value() };
    }

    // Decodes the escapes inside a string token, which includes its quotes.
    fn readString(self: *Reader, token: Token) Error!Result {
        const a = self.heap.allocator();
        var decoded: std.ArrayList(u8) = .empty;
        defer decoded.deinit(a);
        // Decoding only shrinks the text, and the two quotes are not copied.
        try decoded.ensureTotalCapacity(a, token.lexeme.len - 2);

        var i: usize = 1;
        while (i < token.lexeme.len - 1) : (i += 1) {
            var c = token.lexeme[i];
            if (c == '\\') {
                i += 1;
                c = switch (token.lexeme[i]) {
                    '"' => '"',
                    '\\' => '\\',
                    'n' => '\n',
                    't' => '\t',
                    else => return invalid(token.line, "invalid escape sequence"),
                };
            }
            decoded.appendAssumeCapacity(c);
        }

        return .{ .datum = (try self.heap.newString(decoded.items)).value() };
    }
};

fn invalid(line: u32, message: []const u8) Result {
    return .{ .invalid = .{ .line = line, .message = message } };
}

const testing = std.testing;

// Reads every datum in the source and renders the outcomes as text, e.g.
// "OK:1 | OK:(a b) | EOF", so a whole run can be compared in one assertion.
fn render(heap: *Heap, source: []const u8) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();

    var reader = Reader.init(heap, source);
    var first = true;
    while (true) {
        if (!first) try out.writer.writeAll(" | ");
        first = false;
        switch (try reader.read()) {
            .datum => |value| try out.writer.print("OK:{f}", .{value}),
            .eof => {
                try out.writer.writeAll("EOF");
                break;
            },
            .incomplete => {
                try out.writer.writeAll("INCOMPLETE");
                break;
            },
            .invalid => |d| {
                try out.writer.print("ERR:{s}@{d}", .{ d.message, d.line });
                break;
            },
        }
    }
    return testing.allocator.dupe(u8, out.written());
}

fn expectReads(source: []const u8, expected: []const u8) !void {
    var heap = Heap.init(testing.allocator);
    defer heap.deinit();
    const text = try render(&heap, source);
    defer testing.allocator.free(text);
    try testing.expectEqualStrings(expected, text);
}

test "nothing to read is eof" {
    try expectReads("", "EOF");
    try expectReads("  ; nothing\n", "EOF");
}

test "atoms" {
    try expectReads("42", "OK:42 | EOF");
    try expectReads("-7 +5 0", "OK:-7 | OK:5 | OK:0 | EOF");
    try expectReads("foo", "OK:foo | EOF");
    try expectReads("#t #f", "OK:#t | OK:#f | EOF");
    try expectReads("()", "OK:() | EOF");
}

test "lists" {
    try expectReads("(+ 1 2)", "OK:(+ 1 2) | EOF");
    try expectReads("(1 (2 3) \"s\" #t #f ())", "OK:(1 (2 3) \"s\" #t #f ()) | EOF");
    try expectReads("((a) ((b)))", "OK:((a) ((b))) | EOF");
    try expectReads("(a ; comment\n b)", "OK:(a b) | EOF");
}

test "quote expands to a two-element list" {
    try expectReads("'x", "OK:(quote x) | EOF");
    try expectReads("'(1 2)", "OK:(quote (1 2)) | EOF");
    try expectReads("''x", "OK:(quote (quote x)) | EOF");
    try expectReads("(a 'b c)", "OK:(a (quote b) c) | EOF");
    try expectReads("'()", "OK:(quote ()) | EOF");
}

test "several data in one source are read in order" {
    try expectReads("1 2 (3)", "OK:1 | OK:2 | OK:(3) | EOF");
    try expectReads("(a b)\n(c d)", "OK:(a b) | OK:(c d) | EOF");
}

test "string escapes are decoded" {
    try expectReads("\"hi\"", "OK:\"hi\" | EOF");
    try expectReads("\"\"", "OK:\"\" | EOF");
    try expectReads("\"a\\\"b\"", "OK:\"a\\\"b\" | EOF");
    try expectReads("\"a\\\\b\"", "OK:\"a\\\\b\" | EOF");
    try expectReads("\"a\\nb\"", "OK:\"a\nb\" | EOF");
    try expectReads("\"a\\tb\"", "OK:\"a\tb\" | EOF");
}

test "decoded string bytes are what the escapes mean" {
    var heap = Heap.init(testing.allocator);
    defer heap.deinit();

    var reader = Reader.init(&heap, "\"a\\\"b\\\\c\\nd\\te\"");
    const value = (try reader.read()).datum;
    try testing.expectEqualStrings("a\"b\\c\nd\te", value.asString().?.chars);
}

test "a bad escape is an error" {
    try expectReads("\"a\\qb\"", "ERR:invalid escape sequence@1");
}

test "integers are checked against the i64 range" {
    try expectReads("9223372036854775807", "OK:9223372036854775807 | EOF");
    try expectReads("-9223372036854775808", "OK:-9223372036854775808 | EOF");
    try expectReads("9223372036854775808", "ERR:integer out of range@1");
    try expectReads("-9223372036854775809", "ERR:integer out of range@1");
    try expectReads("99999999999999999999999", "ERR:integer out of range@1");
    try expectReads("1\n9223372036854775808", "OK:1 | ERR:integer out of range@2");
}

test "input that ends inside a datum is incomplete" {
    try expectReads("(1 2", "INCOMPLETE");
    try expectReads("(1 (2", "INCOMPLETE");
    try expectReads("'", "INCOMPLETE");
    try expectReads("(a '", "INCOMPLETE");
    try expectReads("''", "INCOMPLETE");
}

test "bad syntax is an error with the line it is on" {
    try expectReads(")", "ERR:unexpected ')'@1");
    try expectReads("(1 2))", "OK:(1 2) | ERR:unexpected ')'@1");
    try expectReads("')", "ERR:unexpected ')'@1");
    try expectReads("#x", "ERR:invalid # syntax@1");
    try expectReads("(1\n2\n#x)", "ERR:invalid # syntax@3");
    try expectReads("\"abc", "ERR:unterminated string@1");
}

test "symbols are interned across reads, strings are not" {
    var heap = Heap.init(testing.allocator);
    defer heap.deinit();

    var reader = Reader.init(&heap, "foo foo \"x\" \"x\"");
    const a = (try reader.read()).datum;
    const b = (try reader.read()).datum;
    const c = (try reader.read()).datum;
    const d = (try reader.read()).datum;
    try testing.expect(Value.eql(a, b));
    try testing.expect(!Value.eql(c, d));
}

test "position advances past each datum" {
    var heap = Heap.init(testing.allocator);
    defer heap.deinit();

    const source = "(a b) c";
    var reader = Reader.init(&heap, source);
    try testing.expectEqual(0, reader.position());
    _ = try reader.read();
    try testing.expectEqual(5, reader.position());
    _ = try reader.read();
    try testing.expectEqual(source.len, reader.position());
}

test "nesting beyond the limit is rejected, not a stack overflow" {
    var heap = Heap.init(testing.allocator);
    defer heap.deinit();

    const source = try testing.allocator.alloc(u8, 100_000);
    defer testing.allocator.free(source);

    @memset(source, '(');
    var parens = Reader.init(&heap, source);
    try testing.expectEqualStrings("nesting too deep", (try parens.read()).invalid.message);

    @memset(source, '\'');
    var quotes = Reader.init(&heap, source);
    try testing.expectEqualStrings("nesting too deep", (try quotes.read()).invalid.message);
}

test "nesting exactly at the limit still reads" {
    var heap = Heap.init(testing.allocator);
    defer heap.deinit();

    const source = try testing.allocator.alloc(u8, 2 * max_nesting);
    defer testing.allocator.free(source);
    @memset(source[0..max_nesting], '(');
    @memset(source[max_nesting..], ')');
    var reader = Reader.init(&heap, source);
    try testing.expect((try reader.read()) == .datum);

    const too_deep = try testing.allocator.alloc(u8, 2 * (max_nesting + 1));
    defer testing.allocator.free(too_deep);
    @memset(too_deep[0 .. max_nesting + 1], '(');
    @memset(too_deep[max_nesting + 1 ..], ')');
    var over = Reader.init(&heap, too_deep);
    try testing.expectEqualStrings("nesting too deep", (try over.read()).invalid.message);
}

test "a very long flat list is read without recursion" {
    // An arena, not the testing allocator: that one records a stack trace per
    // allocation, which makes hundreds of thousands of them take seconds.
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var heap = Heap.init(arena.allocator());
    defer heap.deinit();

    const count = 200_000;
    const source = try testing.allocator.alloc(u8, count * 2 + 2);
    defer testing.allocator.free(source);
    source[0] = '(';
    for (0..count) |i| {
        source[1 + 2 * i] = '1';
        source[2 + 2 * i] = ' ';
    }
    source[source.len - 1] = ')';

    var reader = Reader.init(&heap, source);
    var length: usize = 0;
    var current = (try reader.read()).datum;
    while (current.asPair()) |pair| : (current = pair.cdr) length += 1;
    try testing.expectEqual(count, length);
}

fn readEverything(allocator: std.mem.Allocator, source: []const u8) !void {
    var heap = Heap.init(allocator);
    defer heap.deinit();

    var reader = Reader.init(&heap, source);
    while (true) {
        switch (try reader.read()) {
            .datum => {},
            .eof, .incomplete, .invalid => return,
        }
    }
}

test "running out of memory at any step leaks nothing and is reported" {
    try testing.checkAllAllocationFailures(testing.allocator, readEverything, .{"(a \"s\" 'b (c . d) 12) sym \"x\\ty\""});
    try testing.checkAllAllocationFailures(testing.allocator, readEverything, .{"((((x))))"});
}
