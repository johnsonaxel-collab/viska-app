// Measures the time from releasing the key until the text is pasted.
import Foundation

final class Stopwatch {
    private let start = DispatchTime.now().uptimeNanoseconds
    private var last = DispatchTime.now().uptimeNanoseconds
    private(set) var stages: [(name: String, seconds: Double)] = []

    func mark(_ name: String) {
        let now = DispatchTime.now().uptimeNanoseconds
        stages.append((name, Double(now - last) / 1e9))
        last = now
    }

    var total: Double { Double(last - start) / 1e9 }
}

enum LatencyLog {
    static var url: URL { Paths.logs.appendingPathComponent("tider.tsv") }

    /// One TSV row per dictation: when, model, each stage, total, characters.
    static func append(_ sw: Stopwatch, model: String, chars: Int) {
        let header = "tid\tmodell\tsteg\ttotal_s\ttecken\n"
        if !FileManager.default.fileExists(atPath: url.path) {
            try? header.write(to: url, atomically: true, encoding: .utf8)
        }
        let stages = sw.stages.map { "\($0.name)=\(String(format: "%.3f", $0.seconds))" }
            .joined(separator: " ")
        let row = "\(ISO8601DateFormatter().string(from: Date()))\t\(model)\t\(stages)\t"
            + "\(String(format: "%.3f", sw.total))\t\(chars)\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(row.data(using: .utf8)!)
            h.closeFile()
        }
    }
}

/// "1,23 s" — Swedish decimal comma.
func formatSeconds(_ s: Double) -> String {
    String(format: "%.2f s", s).replacingOccurrences(of: ".", with: ",")
}
