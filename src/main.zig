const std = @import("std");

pub fn main(init: std.process.Init) !void {
    // Streaming, not positional: a positional writer overwrites redirected output from offset 0.
    var buffer: [64]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &buffer);
    try stdout.interface.writeAll("mylisp\n");
    try stdout.interface.flush();
}
