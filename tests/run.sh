#!/bin/sh
# Usage: tests/run.sh <path to binary>
set -eu

bin="$1"
fail=0

actual=$("$bin")
if [ "$actual" = "mylisp" ]; then
  echo "ok"
else
  echo "failed: expected 'mylisp', got '$actual'"
  fail=1
fi

exit "$fail"
