// Keeps whisper-server running in the background with the model loaded, so a
// dictation only pays for the actual transcription. Listens on 127.0.0.1 only.
import Foundation

enum WhisperError: LocalizedError {
    case notRunning
    case http(Int, String)
    case noResponse

    var errorDescription: String? {
        switch self {
        case .notRunning: return "Talmotorn är inte igång."
        case .http(let code, let body): return "Talmotorn svarade \(code): \(body)"
        case .noResponse: return "Inget svar från talmotorn."
        }
    }
}

final class WhisperServer {
    let binary: String
    private(set) var modelPath: String?
    private(set) var port: Int = 0
    private var process: Process?
    private let pidFile = Paths.support.appendingPathComponent("whisper-server.pid")

    init(binary: String) { self.binary = binary }

    var isRunning: Bool { process?.isRunning ?? false }

    func start(modelPath: String, language: String) throws {
        stop()
        killOrphan()
        port = WhisperServer.freePort()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: binary)
        p.arguments = ["-m", modelPath, "-l", language, "-fa", "-nt",
                       "-t", String(min(8, ProcessInfo.processInfo.activeProcessorCount)),
                       "--host", "127.0.0.1", "--port", String(port)]
        let logURL = Paths.logs.appendingPathComponent("whisper-server.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let log = try? FileHandle(forWritingTo: logURL)
        p.standardOutput = log ?? FileHandle.nullDevice
        p.standardError = log ?? FileHandle.nullDevice
        try p.run()
        process = p
        self.modelPath = modelPath
        try? String(p.processIdentifier).write(to: pidFile, atomically: true, encoding: .utf8)
    }

    func stop() {
        if let p = process, p.isRunning {
            p.terminate()
            p.waitUntilExit()
        }
        process = nil
        try? FileManager.default.removeItem(at: pidFile)
    }

    /// Polls /health until the model is loaded.
    func waitUntilReady(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            guard isRunning else { return false }
            if healthOK() { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }

    func transcribe(wav: URL, language: String, prompt: String? = nil) throws -> String {
        guard isRunning else { throw WhisperError.notRunning }
        var fields = [("response_format", "text"), ("language", language), ("temperature", "0.0")]
        if let prompt = prompt, !prompt.isEmpty { fields.append(("prompt", prompt)) }
        let boundary = "viska-\(UUID().uuidString)"
        let audio = try Data(contentsOf: wav)
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/inference")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = Multipart.body(boundary: boundary, fields: fields,
                                      fileField: "file", fileName: "ljud.wav", fileData: audio)
        let (data, status) = try WhisperServer.send(req)
        let body = String(data: data, encoding: .utf8) ?? ""
        guard status == 200 else { throw WhisperError.http(status, body) }
        return TranscriptCleaner.clean(body)
    }

    // MARK: Helpers

    private func healthOK() -> Bool {
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/health")!)
        req.timeoutInterval = 1
        return (try? WhisperServer.send(req))?.1 == 200
    }

    /// A server left behind by a crash would hold memory; stop it.
    private func killOrphan() {
        guard let s = try? String(contentsOf: pidFile, encoding: .utf8),
              let pid = Int32(s.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-p", String(pid), "-o", "comm="]
        let pipe = Pipe()
        ps.standardOutput = pipe
        try? ps.run()
        ps.waitUntilExit()
        let name = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if name.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("whisper-server") {
            kill(pid, SIGTERM)
        }
    }

    static func send(_ req: URLRequest) throws -> (Data, Int) {
        let sem = DispatchSemaphore(value: 0)
        var out: (Data, Int)?
        var err: Error?
        URLSession.shared.dataTask(with: req) { data, resp, e in
            if let e = e { err = e }
            else { out = (data ?? Data(), (resp as? HTTPURLResponse)?.statusCode ?? 0) }
            sem.signal()
        }.resume()
        sem.wait()
        if let e = err { throw e }
        guard let o = out else { throw WhisperError.noResponse }
        return o
    }

    /// Ask the OS for an unused local port.
    static func freePort() -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let ok = withUnsafeMutablePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa -> Bool in
                bind(fd, sa, len) == 0 && getsockname(fd, sa, &len) == 0
            }
        }
        return ok ? Int(UInt16(bigEndian: addr.sin_port)) : 8178
    }
}

enum Multipart {
    static func body(boundary: String, fields: [(String, String)],
                     fileField: String, fileName: String, fileData: Data) -> Data {
        var d = Data()
        func add(_ s: String) { d.append(s.data(using: .utf8)!) }
        for (k, v) in fields {
            add("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(k)\"\r\n\r\n\(v)\r\n")
        }
        add("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(fileName)\"\r\n")
        add("Content-Type: audio/wav\r\n\r\n")
        d.append(fileData)
        add("\r\n--\(boundary)--\r\n")
        return d
    }
}

enum TranscriptCleaner {
    /// Drops whisper's non-speech markers like [BLANK_AUDIO] and tidies whitespace.
    static func clean(_ raw: String) -> String {
        let noTags = raw.replacingOccurrences(of: "\\[[^\\]]*\\]", with: " ", options: .regularExpression)
        let lines = noTags.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.joined(separator: " ")
            .replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
