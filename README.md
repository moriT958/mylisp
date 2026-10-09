# mylisp

Scheme subset.

## Build

| Command | Description |
|---|---|
| `make` / `make debug` | Debug build (`-O0 -g`, with ASan and UBSan). Output: `build/debug/mylisp` |
| `make release` | `-O2 -DNDEBUG`. Output: `build/release/mylisp` |
| `make run` | Build and start the REPL |
| `make test` | Run `tests/run.sh` with the built binary |
| `make clean` | Remove `build/` |

```bash
# Debug features are toggled with macros:
#   DEBUG_STRESS_GC, DEBUG_LOG_GC, DEBUG_TRACE_EXECUTION
# Run make clean first when changing macros, since stale object files are not rebuilt.
make clean && make EXTRA_CFLAGS="-DDEBUG_TRACE_EXECUTION"
```
