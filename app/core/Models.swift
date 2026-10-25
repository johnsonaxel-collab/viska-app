// KB-Whisper models (KBLab, trained on Swedish) and their download.
import CryptoKit
import Foundation

struct WhisperModel: Equatable {
    let id: String          // stored in UserDefaults
    let title: String       // shown in the menu
    let repo: String        // Hugging Face repo under KBLab
    let approxMB: Int
    let revision: String    // pinned Hugging Face commit, so the file cannot change under us
    let sha256: String      // expected checksum of the downloaded file

    var fileName: String { "\(repo)-q5_0.bin" }
    var localURL: URL { Paths.models.appendingPathComponent(fileName) }
    var isDownloaded: Bool {
        let size = (try? FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? Int) ?? 0
        return size > 10_000_000
    }
    var downloadURL: URL {
        URL(string: "https://huggingface.co/KBLab/\(repo)/resolve/\(revision)/ggml-model-q5_0.bin")!
    }
}

enum ModelCatalog {
    static let fast = WhisperModel(
        id: "snabb", title: "Snabb", repo: "kb-whisper-small", approxMB: 175,
        revision: "3564d61a42fc210ceaa55a22a96dd64478959c78",
        sha256: "6768836a51abc902e420c613153e6d418c90ea2774e913274d02ab23170225b7")
    static let accurate = WhisperModel(
        id: "noggrann", title: "Noggrann", repo: "kb-whisper-medium", approxMB: 540,
        revision: "0abe10b9d7f75d0902656e5c06c5c4d549604dc5",
        sha256: "7f8762e0ade9e0073674c0d5acae942a0b1ea98add9baa008ee89c94eaba43d0")
    static let all = [fast, accurate]

    static func byId(_ id: String?) -> WhisperModel {
        all.first { $0.id == id } ?? fast
    }
}

enum DownloadError: LocalizedError {
    case badStatus(Int)
    case tooSmall
    case wrongChecksum

    var errorDescription: String? {
        switch self {
        case .badStatus(let code): return "Servern svarade med fel \(code)."
        case .tooSmall: return "Filen blev för liten. Nedladdningen avbröts troligen."
        case .wrongChecksum: return "Filen stämmer inte med den väntade modellen och användes inte."
        }
    }
}

enum Checksum {
    /// SHA-256 of a file as lowercase hex, read in chunks so large models fit in memory.
    static func sha256(of url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        var hasher = SHA256()
        while let chunk = try? h.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Downloads one model with progress callbacks (delivered on the main queue).
final class ModelDownloader: NSObject, URLSessionDownloadDelegate {
    var onProgress: ((Int64, Int64) -> Void)?
    var onDone: ((Result<Void, Error>) -> Void)?

    private var session: URLSession?
    private var model: WhisperModel?
    private var moveError: Error?

    func start(_ model: WhisperModel) {
        self.model = model
        moveError = nil
        let s = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        session = s
        s.downloadTask(with: model.downloadURL).resume()
    }

    func cancel() {
        session?.invalidateAndCancel()
        session = nil
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let expected = totalBytesExpectedToWrite > 0
            ? totalBytesExpectedToWrite : Int64((model?.approxMB ?? 0) * 1_000_000)
        DispatchQueue.main.async { self.onProgress?(totalBytesWritten, expected) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // The temp file vanishes when this returns, so move it now.
        guard let model = model else { return }
        if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
            moveError = DownloadError.badStatus(http.statusCode)
            return
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: location.path)[.size] as? Int) ?? 0
        if size < 10_000_000 { moveError = DownloadError.tooSmall; return }
        if Checksum.sha256(of: location) != model.sha256 { moveError = DownloadError.wrongChecksum; return }
        do {
            try? FileManager.default.removeItem(at: model.localURL)
            try FileManager.default.moveItem(at: location, to: model.localURL)
        } catch {
            moveError = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let result: Result<Void, Error>
        if let e = error ?? moveError { result = .failure(e) } else { result = .success(()) }
        session.finishTasksAndInvalidate()
        DispatchQueue.main.async { self.onDone?(result) }
    }
}
