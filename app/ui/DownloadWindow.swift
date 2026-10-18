// Small window that shows progress while a speech model downloads.
import Cocoa

final class DownloadWindow: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let bar = NSProgressIndicator()
    private let button = NSButton(title: "Avbryt", target: nil, action: nil)
    private let downloader = ModelDownloader()
    private var model: WhisperModel?
    private var finished = false

    /// Called once: true when the model is on disk, false if cancelled.
    var onFinish: ((Bool) -> Void)?

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 150),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = "Viska"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.level = .floating

        title.font = .systemFont(ofSize: 14, weight: .semibold)
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byWordWrapping
        detail.maximumNumberOfLines = 2
        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = 1
        bar.style = .bar
        button.bezelStyle = .rounded
        button.target = self
        button.action = #selector(buttonPressed)

        let content = NSView(frame: window.contentRect(forFrameRect: window.frame))
        title.frame = NSRect(x: 20, y: 110, width: 380, height: 20)
        bar.frame = NSRect(x: 20, y: 82, width: 380, height: 20)
        detail.frame = NSRect(x: 20, y: 44, width: 380, height: 32)
        button.frame = NSRect(x: 290, y: 10, width: 112, height: 30)
        [title, bar, detail, button].forEach(content.addSubview)
        window.contentView = content

        downloader.onProgress = { [weak self] done, total in self?.progress(done, total) }
        downloader.onDone = { [weak self] result in self?.done(result) }
    }

    func download(_ model: WhisperModel) {
        self.model = model
        finished = false
        title.stringValue = "Laddar ner talmodell: \(model.title)"
        detail.stringValue = "KB-Whisper från KBLab, cirka \(model.approxMB) MB. Görs bara en gång."
        bar.doubleValue = 0
        button.title = "Avbryt"
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        downloader.start(model)
    }

    private func progress(_ done: Int64, _ total: Int64) {
        bar.doubleValue = total > 0 ? Double(done) / Double(total) : 0
        detail.stringValue = "\(done / 1_000_000) av \(total / 1_000_000) MB"
    }

    private func done(_ result: Result<Void, Error>) {
        switch result {
        case .success:
            finished = true
            window.orderOut(nil)
            onFinish?(true)
        case .failure(let e):
            if (e as NSError).code == NSURLErrorCancelled { return }
            title.stringValue = "Nedladdningen misslyckades"
            detail.stringValue = e.localizedDescription
            button.title = "Försök igen"
        }
    }

    @objc private func buttonPressed() {
        if button.title == "Försök igen", let m = model {
            download(m)
        } else {
            cancel()
        }
    }

    private func cancel() {
        downloader.cancel()
        window.orderOut(nil)
        if !finished { finished = true; onFinish?(false) }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        cancel()
        return false
    }
}
