// Where Viska keeps its files and finds its engine binaries.
import Foundation

enum Paths {
    /// ~/Library/Application Support/Viska — models, logs, settings, prompts.
    static var support: URL {
        if let override = ProcessInfo.processInfo.environment["VISKA_SUPPORT"] {
            return ensure(URL(fileURLWithPath: override, isDirectory: true))
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ensure(base.appendingPathComponent("Viska", isDirectory: true))
    }

    static var models: URL { ensure(support.appendingPathComponent("models", isDirectory: true)) }
    static var logs: URL { ensure(support.appendingPathComponent("loggar", isDirectory: true)) }

    /// The source checkout (whisper.cpp lives there during development).
    /// .../Viska.app/Contents/MacOS/Viska -> up 4 = project root.
    static var projectDir: URL {
        if let override = ProcessInfo.processInfo.environment["VISKA_PROJECT"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        var up4 = exe
        for _ in 0..<4 { up4 = up4.deletingLastPathComponent() }
        if FileManager.default.fileExists(atPath: up4.appendingPathComponent("whisper.cpp").path) {
            return up4
        }
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("code/viska-app")
    }

    /// An engine binary: bundled inside the .app (distribution) first,
    /// then the local whisper.cpp build (development).
    static func binary(_ name: String) -> String? {
        var candidates: [String] = []
        if let r = Bundle.main.resourceURL {
            candidates.append(r.appendingPathComponent("bin/\(name)").path)
        }
        candidates.append(projectDir.appendingPathComponent("whisper.cpp/build/bin/\(name)").path)
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    @discardableResult
    static func ensure(_ dir: URL) -> URL {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
