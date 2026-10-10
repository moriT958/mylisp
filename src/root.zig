//! The mylisp interpreter as a library. The executable in main.zig is a thin front end.
//!
//! A name is exposed here only when another module needs it, since anything
//! exposed becomes an API that is hard to take back.

// Nothing references the files themselves, so each file must be listed here
// or its test blocks silently never run.
test {
    _ = @import("heap.zig");
    _ = @import("lexer.zig");
    _ = @import("memory.zig");
    _ = @import("object.zig");
    _ = @import("reader.zig");
    _ = @import("value.zig");
}
