// Starts the real whisper-server with a KB-Whisper model and times each file.
// Usage: viska-bench <model.bin> <a.wav> [b.wav ...]
import Foundation

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 2, let bin = Paths.binary("whisper-server") else {
    print("Användning: viska-bench <modell.bin> <fil.wav>…  (VISKA_PROJECT pekar på repot)")
    exit(2)
}
let server = WhisperServer(binary: bin)
let t0 = Date()
try server.start(modelPath: args[0], language: "sv")
guard server.waitUntilReady(timeout: 60) else { print("Talmotorn startade inte"); exit(1) }
print(String(format: "Modell laddad på %.2f s (port %d)", Date().timeIntervalSince(t0), server.port))

var times: [Double] = []
for wav in args.dropFirst() {
    let sw = Stopwatch()
    let text = try server.transcribe(wav: URL(fileURLWithPath: wav), language: "sv")
    sw.mark("tal_till_text")
    times.append(sw.total)
    print(String(format: "%.2f s  %@", sw.total, text))
}
server.stop()
let sorted = times.sorted()
print(String(format: "Median %.2f s, max %.2f s", sorted[sorted.count / 2], sorted.last!))
