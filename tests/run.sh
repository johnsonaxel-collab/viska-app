#!/bin/bash
# Unit tests for the core logic. Add "bench <modell.bin> <fil.wav>…" to also
# time real transcriptions through whisper-server.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d)"
export VISKA_PROJECT="$HERE"
export VISKA_SUPPORT="$OUT/support"   # never touch the real app's files

swiftc -O "$HERE"/app/core/*.swift "$HERE"/tests/unit/main.swift -o "$OUT/viska-tests"
"$OUT/viska-tests"

if [ "${1:-}" = "bench" ]; then
  shift
  swiftc -O "$HERE"/app/core/*.swift "$HERE"/tests/bench/main.swift -o "$OUT/viska-bench"
  "$OUT/viska-bench" "$@"
fi
