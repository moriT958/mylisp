# mylisp

A Scheme-subset interpreter in C: stack-based bytecode VM with a self-made mark-and-sweep GC.

## Design decisions

- No separate AST. The Reader's S-expression (heap cons cells) is compiled directly in one pass.
- Closures use upvalues (open/close). Tail calls use a `TAILCALL` instruction.
- The temporary user memo about plan is in `docs/devmemo/TASK.md` (gitignored, Japanese). Follow its stage order and confirm each stage's check before moving on.

## Language

- Code, comments, README, and commit messages are in English.
- Conversation with the user is in Japanese.

## Build

- `make` / `make debug`: `-O0 -g` with ASan and UBSan (`build/debug/mylisp`).
- `make release`: `-O2 -DNDEBUG` (`build/release/mylisp`).
- `make test`: runs `tests/run.sh` against the built binary.
- GC debug features are macros: `make clean && make EXTRA_CFLAGS="-DDEBUG_STRESS_GC -DDEBUG_LOG_GC"`. Run `make clean` first when changing macros.
- Code must build without warnings under `-std=c11 -Wall -Wextra -Wpedantic`.

## Code style

### Roles

- Code says HOW, tests say WHAT (expected behavior), comments say WHY.

### Comments

- Write WHY: the reason, constraint, or trade-off. Do not restate what the code does.
- Use `//` for every comment, never `/* */` (block comments do not nest).
- Disable code with `#if 0`, not comments.

### Functions and macros

- Prefer `static inline` functions (snake_case) and `enum` constants over macros. Functions give type checking, single evaluation of arguments, and debuggability.
- Use macros only where a function cannot do the job:
  - conditional compilation (`DEBUG_STRESS_GC`, `DEBUG_LOG_GC`, include guards)
  - taking a type or operator token as an argument (`ALLOCATE(type, n)`, `BINARY_OP(op)`)
  - X-macros that generate several things from one list (opcode enum, names, disassembler)
  - `__FILE__` / `__LINE__` capture
  - helpers local to one function, such as `READ_BYTE()` in the VM loop, with `#undef` afterwards
- When writing a macro: UPPER_CASE name, parenthesize each argument and the whole body, wrap multi-statement bodies in `do { ... } while (0)`, and evaluate each argument once.

### Naming

- Functions and variables: `snake_case`, prefixed by module where it avoids ambiguity (`value_print`, `value_array_write`).
- Types and enum values: `CamelCase` types (`Value`, `ValueArray`), `PREFIX_UPPER` enum values (`VAL_INT`).
- Include guards: `MYLISP_<NAME>_H`.

## Testing

- No C unit tests. Only integration/E2E tests: `.scm` input plus expected output under `tests/`, run by `tests/run.sh`.
- Until the Reader exists (stage 2), use a temporary hand-built-chunk driver in `main.c` and replace it with `.scm` tests afterwards.
