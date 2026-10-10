//! Splits source text into tokens.

const std = @import("std");

pub const Kind = enum {
    left_paren,
    right_paren,
    quote,
    int,
    string,
    symbol,
    true_literal,
    false_literal,
    eof,
    // The lexeme of an invalid token is the error message, not source text.
    invalid,
};

// The lexeme points into the source, so a token is only valid while the source is alive.
// A multi-line string token reports the line where it starts, which is where an error belongs.
pub const Token = struct {
    kind: Kind,
    lexeme: []const u8,
    line: u32,
};

pub const Lexer = struct {
    source: []const u8,
    pos: usize = 0,
    line: u32 = 1,

    pub fn init(source: []const u8) Lexer {
        return .{ .source = source };
    }

    // Returns eof forever once the input is used up.
    pub fn next(self: *Lexer) Token {
        self.skipWhitespaceAndComments();
        const start = self.pos;
        const line = self.line;
        if (self.pos >= self.source.len) return self.token(.eof, start, line);

        switch (self.source[self.pos]) {
            '(' => return self.single(.left_paren, line),
            ')' => return self.single(.right_paren, line),
            '\'' => return self.single(.quote, line),
            '"' => return self.string(line),
            '#' => return self.hashLiteral(line),
            else => return self.atom(line),
        }
    }

    fn token(self: *const Lexer, kind: Kind, start: usize, line: u32) Token {
        return .{ .kind = kind, .lexeme = self.source[start..self.pos], .line = line };
    }

    fn single(self: *Lexer, kind: Kind, line: u32) Token {
        const start = self.pos;
        self.pos += 1;
        return self.token(kind, start, line);
    }

    fn invalid(message: []const u8, line: u32) Token {
        return .{ .kind = .invalid, .lexeme = message, .line = line };
    }

    fn skipWhitespaceAndComments(self: *Lexer) void {
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c == '\n') {
                self.line += 1;
                self.pos += 1;
            } else if (std.ascii.isWhitespace(c)) {
                self.pos += 1;
            } else if (c == ';') {
                while (self.pos < self.source.len and self.source[self.pos] != '\n') self.pos += 1;
            } else {
                return;
            }
        }
    }

    fn skipToDelimiter(self: *Lexer) void {
        while (self.pos < self.source.len and !isDelimiter(self.source[self.pos])) self.pos += 1;
    }

    // Integers and symbols share a character set ("-", "1+", "+5"), so the whole
    // run is read first and classified afterwards.
    fn atom(self: *Lexer, line: u32) Token {
        const start = self.pos;
        self.skipToDelimiter();
        const text = self.source[start..self.pos];
        return self.token(if (isInteger(text)) .int else .symbol, start, line);
    }

    fn hashLiteral(self: *Lexer, line: u32) Token {
        const start = self.pos;
        self.skipToDelimiter();
        const text = self.source[start..self.pos];
        if (std.mem.eql(u8, text, "#t")) return self.token(.true_literal, start, line);
        if (std.mem.eql(u8, text, "#f")) return self.token(.false_literal, start, line);
        return invalid("invalid # syntax", line);
    }

    // The token includes both quotes and the raw escapes; decoding is the reader's job.
    fn string(self: *Lexer, line: u32) Token {
        const start = self.pos;
        self.pos += 1;
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            self.pos += 1;
            if (c == '\n') self.line += 1;
            if (c == '"') return self.token(.string, start, line);
            if (c == '\\' and self.pos < self.source.len) {
                if (self.source[self.pos] == '\n') self.line += 1;
                self.pos += 1;
            }
        }
        return invalid("unterminated string", line);
    }
};

fn isDelimiter(c: u8) bool {
    return std.ascii.isWhitespace(c) or c == '(' or c == ')' or c == ';' or c == '"' or c == '\'';
}

fn isInteger(text: []const u8) bool {
    var digits = text;
    if (digits.len > 0 and (digits[0] == '+' or digits[0] == '-')) digits = digits[1..];
    if (digits.len == 0) return false;
    for (digits) |c| {
        if (!std.ascii.isDigit(c)) return false;
    }
    return true;
}

const testing = std.testing;

const Expected = struct { Kind, []const u8, u32 };

fn expectTokens(source: []const u8, expected: []const Expected) !void {
    var lexer = Lexer.init(source);
    for (expected, 0..) |want, i| {
        const got = lexer.next();
        testing.expectEqual(want[0], got.kind) catch |err| {
            std.debug.print("token {d} of {s}: kind\n", .{ i, source });
            return err;
        };
        testing.expectEqualStrings(want[1], got.lexeme) catch |err| {
            std.debug.print("token {d} of {s}: lexeme\n", .{ i, source });
            return err;
        };
        testing.expectEqual(want[2], got.line) catch |err| {
            std.debug.print("token {d} of {s}: line\n", .{ i, source });
            return err;
        };
    }
}

test "empty and blank input is just eof" {
    try expectTokens("", &.{.{ .eof, "", 1 }});
    try expectTokens("   \t\r\n  ", &.{.{ .eof, "", 2 }});
    try expectTokens("; only a comment", &.{.{ .eof, "", 1 }});
    try expectTokens("; comment\n", &.{.{ .eof, "", 2 }});
}

test "a call splits into parens, symbols, and integers" {
    try expectTokens("(+ 1 2)", &.{
        .{ .left_paren, "(", 1 },
        .{ .symbol, "+", 1 },
        .{ .int, "1", 1 },
        .{ .int, "2", 1 },
        .{ .right_paren, ")", 1 },
        .{ .eof, "", 1 },
    });
}

test "quote is its own token and may repeat" {
    try expectTokens("'x", &.{ .{ .quote, "'", 1 }, .{ .symbol, "x", 1 }, .{ .eof, "", 1 } });
    try expectTokens("''x", &.{ .{ .quote, "'", 1 }, .{ .quote, "'", 1 }, .{ .symbol, "x", 1 } });
}

test "signed digits are integers" {
    try expectTokens("42 -7 +5 0", &.{
        .{ .int, "42", 1 },
        .{ .int, "-7", 1 },
        .{ .int, "+5", 1 },
        .{ .int, "0", 1 },
    });
}

test "anything else that looks almost like a number is a symbol" {
    try expectTokens("- + -a 1+ a1 12abc 1-2 +-1", &.{
        .{ .symbol, "-", 1 },
        .{ .symbol, "+", 1 },
        .{ .symbol, "-a", 1 },
        .{ .symbol, "1+", 1 },
        .{ .symbol, "a1", 1 },
        .{ .symbol, "12abc", 1 },
        .{ .symbol, "1-2", 1 },
        .{ .symbol, "+-1", 1 },
    });
}

test "punctuation is allowed inside symbols" {
    try expectTokens("null? set! list->vector <= *x* a.b", &.{
        .{ .symbol, "null?", 1 },
        .{ .symbol, "set!", 1 },
        .{ .symbol, "list->vector", 1 },
        .{ .symbol, "<=", 1 },
        .{ .symbol, "*x*", 1 },
        .{ .symbol, "a.b", 1 },
    });
}

test "non-ASCII bytes are symbol characters" {
    try expectTokens("λ x", &.{ .{ .symbol, "λ", 1 }, .{ .symbol, "x", 1 } });
}

test "delimiters need no surrounding whitespace" {
    try expectTokens("(a(b)c)", &.{
        .{ .left_paren, "(", 1 },
        .{ .symbol, "a", 1 },
        .{ .left_paren, "(", 1 },
        .{ .symbol, "b", 1 },
        .{ .right_paren, ")", 1 },
        .{ .symbol, "c", 1 },
        .{ .right_paren, ")", 1 },
    });
    try expectTokens("a'b", &.{ .{ .symbol, "a", 1 }, .{ .quote, "'", 1 }, .{ .symbol, "b", 1 } });
    try expectTokens("a;c\nb", &.{ .{ .symbol, "a", 1 }, .{ .symbol, "b", 2 } });
    try expectTokens("1\"s\"", &.{ .{ .int, "1", 1 }, .{ .string, "\"s\"", 1 } });
}

test "booleans" {
    try expectTokens("#t #f (#t)", &.{
        .{ .true_literal, "#t", 1 },
        .{ .false_literal, "#f", 1 },
        .{ .left_paren, "(", 1 },
        .{ .true_literal, "#t", 1 },
        .{ .right_paren, ")", 1 },
    });
}

test "other # syntax is invalid" {
    for ([_][]const u8{ "#x", "#true", "#", "#t1", "#fx" }) |source| {
        var lexer = Lexer.init(source);
        const token = lexer.next();
        try testing.expectEqual(Kind.invalid, token.kind);
        try testing.expectEqualStrings("invalid # syntax", token.lexeme);
    }
}

test "a string token keeps its quotes and raw escapes" {
    try expectTokens("\"hi\"", &.{ .{ .string, "\"hi\"", 1 }, .{ .eof, "", 1 } });
    try expectTokens("\"\"", &.{.{ .string, "\"\"", 1 }});
    try expectTokens("\"a\\\"b\"", &.{.{ .string, "\"a\\\"b\"", 1 }});
    try expectTokens("\"a\\\\\" x", &.{ .{ .string, "\"a\\\\\"", 1 }, .{ .symbol, "x", 1 } });
}

test "delimiters inside a string are ordinary characters" {
    try expectTokens("\"a b ( ) ; '\"", &.{.{ .string, "\"a b ( ) ; '\"", 1 }});
}

test "a multi-line string reports the line it starts on" {
    try expectTokens("\"a\nb\" c", &.{ .{ .string, "\"a\nb\"", 1 }, .{ .symbol, "c", 2 }, .{ .eof, "", 2 } });
    try expectTokens("\"a\\\nb\" c", &.{ .{ .string, "\"a\\\nb\"", 1 }, .{ .symbol, "c", 2 } });
}

test "an unterminated string is invalid and reports where it started" {
    for ([_][]const u8{ "\"abc", "\"abc\\", "\"abc\\\"", "\"" }) |source| {
        var lexer = Lexer.init(source);
        const token = lexer.next();
        try testing.expectEqual(Kind.invalid, token.kind);
        try testing.expectEqualStrings("unterminated string", token.lexeme);
        try testing.expectEqual(1, token.line);
    }
    try expectTokens("x\n\"ab\ncd", &.{ .{ .symbol, "x", 1 }, .{ .invalid, "unterminated string", 2 } });
}

test "lines are counted across comments and blank lines" {
    try expectTokens("(a\n  ; c\n\n  b)", &.{
        .{ .left_paren, "(", 1 },
        .{ .symbol, "a", 1 },
        .{ .symbol, "b", 4 },
        .{ .right_paren, ")", 4 },
        .{ .eof, "", 4 },
    });
}

test "eof repeats" {
    var lexer = Lexer.init("x");
    _ = lexer.next();
    for (0..3) |_| try testing.expectEqual(Kind.eof, lexer.next().kind);
}

test "a NUL byte is an ordinary character" {
    try expectTokens("a\x00b", &.{.{ .symbol, "a\x00b", 1 }});
}
