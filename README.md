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
# GC debug features are toggled with macros.
# Run make clean first when changing macros, since stale object files are not rebuilt.
make clean && make EXTRA_CFLAGS="-DDEBUG_STRESS_GC -DDEBUG_LOG_GC"
```
