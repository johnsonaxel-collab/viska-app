// Turns a raw transcript into finished text with a local model in Ollama.
// Only text is sent, and only to 127.0.0.1.
import Foundation

enum RewriteError: LocalizedError {
    case unavailable
    case http(Int, String)
    case rejected(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Ollama är inte igång."
        case .http(let code, let body): return "Ollama svarade \(code): \(body)"
        case .rejected(let why): return "Omskrivningen förkastades: \(why)"
        }
    }
}

final class OllamaClient {
    let base: URL
    init(base: URL = URL(string: "http://127.0.0.1:11434")!) { self.base = base }

    /// Installed model names, or nil when Ollama is not running.
    func models() -> [String]? {
        var req = URLRequest(url: base.appendingPathComponent("api/tags"))
        req.timeoutInterval = 2
        guard let (data, status) = try? WhisperServer.send(req), status == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["models"] as? [[String: Any]] else { return nil }
        return list.compactMap { $0["name"] as? String }.sorted()
    }

    func chat(model: String, system: String, user: String, timeout: TimeInterval = 60) throws -> String {
        let payload: [String: Any] = [
            "model": model,
            "stream": false,
            "keep_alive": "60m",   // keep the model in memory between dictations
            "think": false,        // skip "thinking" on models that support it: slower, no gain here
            "options": ["temperature": 0.2, "num_ctx": 4096],
            "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
        ]
        var req = URLRequest(url: base.appendingPathComponent("api/chat"))
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, status): (Data, Int)
        do { (data, status) = try WhisperServer.send(req) } catch { throw RewriteError.unavailable }
        guard status == 200 else {
            throw RewriteError.http(status, String(decoding: data, as: UTF8.self))
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let msg = json?["message"] as? [String: Any]
        return (msg?["content"] as? String) ?? ""
    }
}

final class Rewriter {
    let client: OllamaClient
    var model: String

    init(client: OllamaClient = OllamaClient(), model: String) {
        self.client = client
        self.model = model
    }

    /// Returns the rewritten text. Throws if Ollama fails or the result looks invented.
    func rewrite(_ raw: String) throws -> String {
        let system = Prompts.load(Prompts.rewriteFile)
        let user = "Tal: \(raw)\nText:"
        let out = RewriteGuard.tidy(try client.chat(model: model, system: system, user: user))
        if let why = RewriteGuard.problem(raw: raw, rewritten: out) { throw RewriteError.rejected(why) }
        return out
    }

    /// Loads the model and processes the real prompt once, so Ollama can reuse
    /// that work and the first dictation is as fast as the rest.
    func warmUp() {
        _ = try? client.chat(model: model, system: Prompts.load(Prompts.rewriteFile),
                             user: "Tal: eh hej\nText:", timeout: 120)
    }
}

/// Catches answers a small model sometimes gives instead of a rewrite.
enum RewriteGuard {
    /// Removes wrapping quotes and a leading "Text:" the model may echo.
    static func tidy(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["Text:", "text:"] where t.hasPrefix(prefix) {
            t = String(t.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        let quotes: [(Character, Character)] = [("\"", "\""), ("”", "”"), ("“", "”"), ("«", "»")]
        for (open, close) in quotes where t.count >= 2 && t.first == open && t.last == close {
            t = String(t.dropFirst().dropLast())
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// nil when the rewrite looks safe, otherwise the reason it was rejected.
    static func problem(raw: String, rewritten: String) -> String? {
        if rewritten.isEmpty { return "tomt svar" }
        // Cleaning only removes words, so a much longer text means something was added.
        let limit = Double(raw.count) * 1.3 + 15
        if Double(rewritten.count) > limit { return "längre än det som sades" }
        let lower = rewritten.lowercased()
        for opener in ["här är", "självklart", "visst,", "absolut,", "som en ai", "jag kan inte"]
            where lower.hasPrefix(opener) && !raw.lowercased().contains(opener) {
            return "modellen svarade i stället för att skriva om"
        }
        return nil
    }
}

/// Notes rewrites that failed or were rejected, so the prompt can be improved.
/// The lines hold dictated text, so only the latest ones are kept.
enum RewriteLog {
    static var url: URL { Paths.logs.appendingPathComponent("omskrivning-fel.log") }
    static let maxLines = 50

    static func append(raw: String, error: String) {
        let flat = raw.replacingOccurrences(of: "\n", with: " ")
        let line = "\(ISO8601DateFormatter().string(from: Date()))\t\(error)\t\(flat)"
        let old = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let lines = old.split(separator: "\n").map(String.init) + [line]
        let kept = lines.suffix(maxLines).joined(separator: "\n") + "\n"
        try? kept.write(to: url, atomically: true, encoding: .utf8)
    }
}
