#!/bin/bash
# One-time setup for WhisperFlow. No Homebrew required.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

echo "==> pip deps (cmake, pynput) into user site"
python3 -m pip install --user --quiet --upgrade pip >/dev/null 2>&1 || true
python3 -m pip install --user --quiet cmake pynput

# Make the pip-installed cmake available on PATH for this script.
PYUSERBIN="$(python3 -c 'import site, os; print(os.path.join(site.USER_BASE, "bin"))')"
export PATH="$PYUSERBIN:$PATH"
echo "    cmake: $(command -v cmake)"

echo "==> clone whisper.cpp"
if [ ! -d whisper.cpp ]; then
  git clone --depth 1 https://github.com/ggml-org/whisper.cpp.git
fi

echo "==> build whisper.cpp (Metal, Release)"
cd whisper.cpp
cmake -B build -DCMAKE_BUILD_TYPE=Release >/dev/null
cmake --build build --config Release -j"$(sysctl -n hw.ncpu)"
cd "$HERE"

# Talmodellen (KB-Whisper) laddas ner av appen första gången den startar.

echo "==> compile Swift recorder"
mkdir -p bin
swiftc -O record.swift -o bin/wfrecord

echo ""
echo "==> KLART. Bygg appen med:  ./build_app.sh"
echo "    (första körningen ber om Mikrofon + Tillgänglighet i Systeminställningar)"
