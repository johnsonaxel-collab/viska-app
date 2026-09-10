// wfrecord — minimal mic recorder for WhisperFlow.
// Records 16 kHz mono 16-bit PCM WAV until it receives SIGTERM/SIGINT,
// then finalizes the file and exits. No third-party dependencies.
//
// Usage: wfrecord /path/to/out.wav
import Foundation
import AVFoundation

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/wf.wav"
var recorder: AVAudioRecorder?

func log(_ s: String) {
    FileHandle.standardError.write((s + "\n").data(using: .utf8)!)
}

func startRecording() {
    let url = URL(fileURLWithPath: outPath)
    let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: 16000.0,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
    ]
    do {
        recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder?.record()
        log("recording -> \(outPath)")
    } catch {
        log("record error: \(error)")
        exit(1)
    }
}

// Handle termination signals on the main queue so we can finalize the WAV.
signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)
let stop: () -> Void = {
    recorder?.stop()
    exit(0)
}
let sTerm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
let sInt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
sTerm.setEventHandler(handler: stop)
sInt.setEventHandler(handler: stop)
sTerm.resume()
sInt.resume()

// macOS mic permission prompt (attributed to the launching app, e.g. Terminal).
AVCaptureDevice.requestAccess(for: .audio) { granted in
    if granted {
        DispatchQueue.main.async { startRecording() }
    } else {
        log("microphone permission denied")
        exit(1)
    }
}

RunLoop.main.run()
