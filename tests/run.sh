#!/bin/bash
# Unit tests for the core logic. Optional extra modes:
#   bench <modell.bin> <fil.wav>…   time real transcriptions via whisper-server
#   rewrite <ollama-modell> <rader.txt>   time rewrites via Ollama
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

if [ "${1:-}" = "rewrite" ]; then
  shift
  swiftc -O "$HERE"/app/core/*.swift "$HERE"/tests/rewrite/main.swift -o "$OUT/viska-rewrite"
  "$OUT/viska-rewrite" "$@"
fi
