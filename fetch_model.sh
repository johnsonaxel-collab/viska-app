#!/bin/bash
# Resilient model fetcher: retries HF until the model downloads fully or we give up.
# Resumes partial downloads with curl -C -.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
MODEL_NAME="${WF_MODEL:-ggml-small.bin}"
OUT="$HERE/models/$MODEL_NAME"
URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$MODEL_NAME"
mkdir -p "$HERE/models"

for i in $(seq 1 60); do
  echo "[attempt $i] $(date '+%H:%M:%S') downloading $MODEL_NAME…"
  if curl -L --fail --connect-timeout 20 -C - -o "$OUT" "$URL"; then
    # Sanity check: real models are tens/hundreds of MB, not an error page.
    SIZE=$(stat -f%z "$OUT" 2>/dev/null || echo 0)
    if [ "$SIZE" -gt 10000000 ]; then
      echo "OK: $OUT ($SIZE bytes)"
      exit 0
    fi
    echo "downloaded file too small ($SIZE bytes) — retrying"
  fi
  sleep 45
done
echo "gave up after many attempts — Hugging Face still unreachable"
exit 1
