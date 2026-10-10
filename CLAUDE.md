# mylisp

A Scheme-subset interpreter in Zig (0.16): stack-based bytecode VM with a self-made mark-and-sweep GC.

## Design decisions

- No separate AST. The Reader's S-expression (heap cons cells) is compiled directly in one pass.
- Closures use upvalues (open/close). Tail calls use a `TAILCALL` instruction.
- Every heap allocation goes through one allocator that counts bytes, so the GC can decide when to collect.
- The temporary user memo about plan is in `docs/devmemo/TASK.md` (gitignored, Japanese). Follow its stage order and confirm each stage's check before moving on.

## Language

- Code, comments, README, and commit messages are in English.
- Conversation with the user is in Japanese.

## Build

- `zig build`: debug build (`zig-out/bin/mylisp`). Add `-Doptimize=ReleaseSafe` or `-Doptimize=ReleaseFast` for the others.
- `zig build run -- [file]`: start the REPL, or run a file.
- `zig build test`: run the unit tests and the end-to-end tests.
- `zig build fmt`: format the sources. `zig fmt --check build.zig src` must pass.
- Debug features (GC stress, GC log, execution trace) are `comptime` build options, not macros.
- Zig's standard library changes between versions. Check an API against the std source (`zig env` prints `std_dir`) instead of relying on memory.

## Code style

### Roles

- Code says HOW, tests say WHAT (expected behavior), comments say WHY.

### Comments

- Write WHY: the reason, constraint, or trade-off. Do not restate what the code does.
- Use `//` for comments. Use `///` and `//!` only to document public API or describe a file, not for WHY notes.
- Do not leave commented-out code; delete it.

### Idioms

Follow the Zig standard library's conventions:

- Errors are error unions (`!T`) with `try` and `errdefer`. Absence is an optional (`?T`), not a sentinel value.
- Use slices (`[]const u8`), not a pointer plus a length.
- Use tagged unions and exhaustive `switch`. Do not add `else` to a `switch` just to silence a missing case.
- Compile-time configuration is `comptime` and build options, not preprocessor tricks.
- Pass `std.mem.Allocator` explicitly. A type that owns memory has `init` and `deinit`, used with `defer`.
- Prefer `std.ArrayList` and `std.HashMap` over hand-written containers.
- Mark `pub` only what another file uses. `src/root.zig` is the library's public API.
- Standard streams use `writerStreaming` and `readerStreaming`; the positional `writer` overwrites redirected output.

### Naming

Follow the Zig style guide: types are `PascalCase`, functions are `camelCase`, variables, fields, and file names are `snake_case`.

## Testing

- Unit tests are `test` blocks next to the code they check, run by `zig build test`. Use `std.testing.allocator` so leaks fail the test. Cover the components that can be tested in isolation: lexer, reader, symbol table, allocator accounting, VM instructions.
- End-to-end tests are `.scm` input plus expected output under `tests/`, run by `tests/run.sh` against the built binary (`zig build test` runs it). They pin what a user sees through the REPL and file runner.
- A behavior bug found through an end-to-end test gets a unit test at the component where it lives.
