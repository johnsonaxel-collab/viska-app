#!/bin/bash
# Launch WhisperFlow. Env overrides: WF_LANG, WF_MODEL, WF_KEY
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"
exec python3 flow.py
