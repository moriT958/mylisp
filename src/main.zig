const std = @import("std");
const mylisp = @import("mylisp");

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;
    const gpa = init.gpa;

    // Streaming, not positional: a positional writer overwrites redirected output from offset 0.
    var out_buffer: [4096]u8 = undefined;
    var out_writer = std.Io.File.stdout().writerStreaming(io, &out_buffer);
    const out = &out_writer.interface;
    var err_buffer: [1024]u8 = undefined;
    var err_writer = std.Io.File.stderr().writerStreaming(io, &err_buffer);
    const err = &err_writer.interface;

    var args = init.minimal.args.iterate();
    _ = args.skip();
    const path = args.next();
    if (args.next() != null) {
        try err.writeAll("usage: mylisp [file]\n");
        try err.flush();
        return 2;
    }

    if (path) |file_path| {
        const source = std.Io.Dir.cwd().readFileAlloc(io, file_path, gpa, .limited(64 * 1024 * 1024)) catch |e| {
            try err.print("cannot open '{s}': {t}\n", .{ file_path, e });
            try err.flush();
            return 1;
        };
        defer gpa.free(source);
        return mylisp.runFile(gpa, source, out, err);
    }

    var in_buffer: [4096]u8 = undefined;
    var in_reader = std.Io.File.stdin().readerStreaming(io, &in_buffer);
    const interactive = try std.Io.File.stdin().isTty(io);
    return mylisp.runRepl(gpa, &in_reader.interface, out, err, interactive);
}
