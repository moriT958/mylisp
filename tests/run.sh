#!/bin/sh
# Usage: tests/run.sh <path to binary>
set -u

bin="$1"
dir=$(dirname "$0")
failed=0

check() {
  if [ "$2" = "$3" ]; then
    echo "ok   $1"
  else
    echo "FAIL $1"
    echo "--- expected"
    echo "$2"
    echo "--- actual"
    echo "$3"
    failed=1
  fi
}

# The same source must give the same output as a file and through stdin, which
# exercises the REPL's handling of forms that span several lines.
for scm in "$dir"/cases/*.scm; do
  name=$(basename "$scm" .scm)
  expected=$(cat "${scm%.scm}.out")
  check "$name (file)" "$expected" "$("$bin" "$scm" 2>&1)"
  check "$name (stdin)" "$expected" "$("$bin" <"$scm" 2>&1)"
done

# File mode only: the REPL keeps going after an error, a file run stops.
for scm in "$dir"/errors/*.scm; do
  name=$(basename "$scm" .scm)
  expected=$(cat "${scm%.scm}.out")
  actual=$("$bin" "$scm" 2>&1)
  status=$?
  check "$name" "$expected" "$actual"
  if [ "$status" -eq 0 ]; then
    echo "FAIL $name: expected a non-zero exit status"
    failed=1
  fi
done

exit "$failed"
