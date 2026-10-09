#!/bin/sh
# Usage: tests/run.sh <path to binary>
set -eu

bin="$1"
fail=0

# TODO:
# This is temporary.
# mylisp has no Reader, so the binary dumps a hand-built chunk.
expected="== 1 + 2 * 3 ==
0000 OP_CONST     0 '1'
0002 OP_CONST     1 '2'
0004 OP_CONST     2 '3'
0006 OP_MUL
0007 OP_ADD
0008 OP_RETURN"

actual=$("$bin")
if [ "$actual" = "$expected" ]; then
  echo "ok"
else
  echo "failed: disassembly mismatch"
  echo "--- expected"
  echo "$expected"
  echo "--- actual"
  echo "$actual"
  fail=1
fi

exit "$fail"
