//! The mylisp interpreter as a library. The executable in main.zig is a thin front end.

const std = @import("std");

// Without this, test blocks in files that root.zig imports would never run.
test {
    std.testing.refAllDecls(@This());
}
