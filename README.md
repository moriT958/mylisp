# mylisp

Scheme subset.

Requires [Zig](https://ziglang.org/) 0.16.

## Build

| Command | Description |
|---|---|
| `zig build` | Debug build. Output: `zig-out/bin/mylisp` |
| `zig build -Doptimize=ReleaseSafe` | Optimized build that keeps safety checks |
| `zig build -Doptimize=ReleaseFast` | Optimized build without safety checks |
| `zig build run -- [file]` | Start the REPL, or run a file |
| `zig build test` | Run the unit and end-to-end tests |
| `zig build fmt` | Format the sources |
