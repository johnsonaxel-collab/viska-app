#!/usr/bin/env python3
"""
WhisperFlow — hold-to-talk local dictation for macOS.

Hold the push-to-talk key, speak, release. The mic recording is transcribed
locally with whisper.cpp and pasted at your cursor (clipboard + Cmd+V).

Config via env vars:
  WF_LANG   language code for whisper, or "auto" (default: auto). e.g. WF_LANG=sv
  WF_MODEL  model filename in ./models (default: ggml-small.bin)
  WF_KEY    push-to-talk key: cmd_r | alt_r | ctrl_r | f5 ... (default: cmd_r)
"""
import os
import sys
import time
import signal
import threading
import subprocess
from pathlib import Path

from pynput import keyboard

HERE = Path(__file__).resolve().parent
MODEL = HERE / "models" / os.environ.get("WF_MODEL", "ggml-small.bin")
WHISPER = HERE / "whisper.cpp" / "build" / "bin" / "whisper-cli"
RECORDER = HERE / "bin" / "wfrecord"
WAV = "/tmp/wf.wav"
LANG = os.environ.get("WF_LANG", "auto")

_KEY_MAP = {
    "cmd_r": keyboard.Key.cmd_r,
    "alt_r": keyboard.Key.alt_r,
    "ctrl_r": keyboard.Key.ctrl_r,
    "f5": keyboard.Key.f5,
    "f6": keyboard.Key.f6,
}
PTT_KEY = _KEY_MAP.get(os.environ.get("WF_KEY", "cmd_r"), keyboard.Key.cmd_r)

kb = keyboard.Controller()
_rec_proc = None
_recording = False
_lock = threading.Lock()


def start_rec():
    global _rec_proc, _recording
    with _lock:
        if _recording:
            return
        _recording = True
        try:
            os.remove(WAV)
        except OSError:
            pass
        _rec_proc = subprocess.Popen(
            [str(RECORDER), WAV],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    print("● spelar in…", flush=True)


def stop_and_transcribe():
    global _rec_proc, _recording
    with _lock:
        if not _recording:
            return
        _recording = False
        proc = _rec_proc
        _rec_proc = None
    if proc:
        proc.send_signal(signal.SIGTERM)
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()

    if not os.path.exists(WAV) or os.path.getsize(WAV) < 2000:
        print("… för kort, hoppar över", flush=True)
        return

    print("… transkriberar", flush=True)
    try:
        res = subprocess.run(
            [str(WHISPER), "-m", str(MODEL), "-f", WAV,
             "-l", LANG, "-nt", "-np", "-t", str(os.cpu_count() or 4)],
            capture_output=True, text=True, timeout=120,
        )
    except subprocess.TimeoutExpired:
        print("! whisper timeout", flush=True)
        return

    text = res.stdout.strip()
    if not text:
        print("… (inget hördes)", flush=True)
        return
    paste(text)
    print("✎ " + text, flush=True)


def paste(text):
    subprocess.run(["pbcopy"], input=text, text=True)
    time.sleep(0.15)  # let the PTT key fully release before we send Cmd+V
    with kb.pressed(keyboard.Key.cmd):
        kb.press("v")
        kb.release("v")


def on_press(key):
    if key == PTT_KEY:
        start_rec()


def on_release(key):
    if key == PTT_KEY:
        threading.Thread(target=stop_and_transcribe, daemon=True).start()


def main():
    for path, name in [(RECORDER, "wfrecord"), (WHISPER, "whisper-cli"), (MODEL, "model")]:
        if not Path(path).exists():
            print(f"Saknar {name}: {path}\nKör ./setup.sh först.")
            sys.exit(1)

    key_name = os.environ.get("WF_KEY", "cmd_r").upper()
    print(f"WhisperFlow redo — håll {key_name}, prata, släpp. "
          f"Språk={LANG}, modell={MODEL.name}. Ctrl+C avslutar.")
    with keyboard.Listener(on_press=on_press, on_release=on_release) as listener:
        listener.join()


if __name__ == "__main__":
    main()
