// Viska — a macOS menu bar app for local push-to-talk dictation in Swedish.
// Hold Right Command, speak, release. Speech is transcribed on this Mac with
// KB-Whisper (whisper.cpp) and pasted at the cursor. No audio leaves the Mac.
import Cocoa

let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // menu bar only, no Dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
