//! The mylisp interpreter as a library. The executable in main.zig is a thin front end.
//!
//! A name is exposed here only when another module needs it, since anything
//! exposed becomes an API that is hard to take back.

pub const runRepl = @import("repl.zig").runRepl;
pub const runFile = @import("repl.zig").runFile;

// Nothing references the files themselves, so each file must be listed here
// or its test blocks silently never run.
test {
    _ = @import("heap.zig");
    _ = @import("lexer.zig");
    _ = @import("memory.zig");
    _ = @import("object.zig");
    _ = @import("reader.zig");
    _ = @import("repl.zig");
    _ = @import("value.zig");
}
