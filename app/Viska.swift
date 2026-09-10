// Viska — a self-contained macOS menu bar app for local push-to-talk
// dictation. Hold the PTT key (default: Right Command), speak, release.
// The mic is recorded, transcribed locally with whisper.cpp, and pasted at
// the cursor. No Python, no third-party frameworks.
import Cocoa
import AVFoundation
import ApplicationServices

// MARK: - Locate the project directory (models, whisper.cpp) relative to the app

func findProjectDir() -> URL {
    let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    // .../Viska.app/Contents/MacOS/Viska  -> up 4 = project root
    let up4 = exe.deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    if FileManager.default.fileExists(
        atPath: up4.appendingPathComponent("whisper.cpp/build/bin/whisper-cli").path) {
        return up4
    }
    return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("whisperflow")
}

// MARK: - App state

enum FlowState { case idle, recording, transcribing }

// Map a modifier keycode to the CGEventFlags bit it toggles.
func flagFor(keycode: Int64) -> CGEventFlags {
    switch keycode {
    case 54, 55: return .maskCommand      // right / left Command
    case 61, 58: return .maskAlternate    // right / left Option
    case 62, 59: return .maskControl      // right / left Control
    case 60, 56: return .maskShift        // right / left Shift
    default: return .maskCommand
    }
}

// MARK: - Global event-tap callback (C function pointer, no captures)

func tapCallback(proxy: CGEventTapProxy, type: CGEventType,
                 event: CGEvent, userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let userInfo = userInfo {
            let app = Unmanaged<AppDelegate>.fromOpaque(userInfo).takeUnretainedValue()
            if let tap = app.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
        }
        return Unmanaged.passUnretained(event)
    }
    if type == .flagsChanged, let userInfo = userInfo {
        let app = Unmanaged<AppDelegate>.fromOpaque(userInfo).takeUnretainedValue()
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        if keycode == app.pttKeycode {
            let pressed = event.flags.contains(flagFor(keycode: keycode))
            app.handlePTT(pressed: pressed)
        }
    }
    return Unmanaged.passUnretained(event)
}

// MARK: - Floating recording HUD

/// A row of rounded bars that scroll left as new mic levels arrive, so the
/// waveform visibly "moves" while you speak.
class WaveView: NSView {
    var heights: [CGFloat] = Array(repeating: 0.08, count: 13)
    var barColor: NSColor = .systemGreen

    func push(_ level: CGFloat) {
        heights.removeFirst()
        heights.append(max(0.06, min(1.0, level)))
        needsDisplay = true
    }

    func reset() {
        heights = Array(repeating: 0.08, count: heights.count)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let n = heights.count
        let gap: CGFloat = 3
        let barW = max(2, (bounds.width - CGFloat(n - 1) * gap) / CGFloat(n))
        let midY = bounds.height / 2
        let maxH = bounds.height
        barColor.setFill()
        var x: CGFloat = 0
        for h in heights {
            let bh = max(barW, h * maxH)
            let rect = NSRect(x: x, y: midY - bh / 2, width: barW, height: bh)
            NSBezierPath(roundedRect: rect, xRadius: barW / 2, yRadius: barW / 2).fill()
            x += barW + gap
        }
    }
}

/// Small blurred pill that floats near the bottom-center of the screen.
class RecordingHUD {
    let panel: NSPanel
    let wave = WaveView()
    let label = NSTextField(labelWithString: "Spelar in…")

    init() {
        let w: CGFloat = 200, h: CGFloat = 64
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let bg = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        bg.material = .hudWindow
        bg.state = .active
        bg.blendingMode = .behindWindow
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 16
        bg.layer?.masksToBounds = true
        bg.autoresizingMask = [.width, .height]

        wave.frame = NSRect(x: 16, y: 26, width: w - 32, height: 26)
        wave.autoresizingMask = [.width]

        label.frame = NSRect(x: 0, y: 7, width: w, height: 15)
        label.alignment = .center
        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = NSColor.white.withAlphaComponent(0.9)
        label.drawsBackground = false
        label.isBezeled = false
        label.isEditable = false

        bg.addSubview(wave)
        bg.addSubview(label)
        panel.contentView = bg
    }

    private func reposition() {
        guard let screen = NSScreen.main else { return }
        let sf = screen.frame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: sf.midX - size.width / 2, y: sf.minY + 120))
    }

    func showRecording() {
        wave.barColor = .systemGreen
        wave.reset()
        label.stringValue = "Spelar in…"
        reposition()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { c in
            c.duration = 0.15
            panel.animator().alphaValue = 1
        }
    }

    func setTranscribing() {
        wave.barColor = .systemOrange
        label.stringValue = "Transkriberar…"
    }

    func update(level: CGFloat) { wave.push(level) }

    func hide() {
        NSAnimationContext.runAnimationGroup({ c in
            c.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: { self.panel.orderOut(nil) })
    }
}

// MARK: - App delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    let projectDir = findProjectDir()
    // Prefer an engine/model bundled inside the .app (for distribution),
    // fall back to the project dir (for local development).
    var whisperCLI: String {
        if let r = Bundle.main.resourceURL {
            let p = r.appendingPathComponent("bin/whisper-cli").path
            if FileManager.default.fileExists(atPath: p) { return p }
        }
        return projectDir.appendingPathComponent("whisper.cpp/build/bin/whisper-cli").path
    }
    var modelPath: String {
        if let r = Bundle.main.resourceURL {
            let p = r.appendingPathComponent("models/\(model)").path
            if FileManager.default.fileExists(atPath: p) { return p }
        }
        return projectDir.appendingPathComponent("models/\(model)").path
    }
    let wavPath = "/tmp/wf.wav"

    // Config (persisted in UserDefaults)
    var lang = UserDefaults.standard.string(forKey: "lang") ?? "auto"
    var model = UserDefaults.standard.string(forKey: "model") ?? "ggml-small.bin"
    let pttKeycode: Int64 = 54  // Right Command

    var state: FlowState = .idle
    var lastText = "—"
    var recorder: AVAudioRecorder?
    var statusItem: NSStatusItem!
    var eventTap: CFMachPort?
    var trustTimer: Timer?
    let hud = RecordingHUD()
    var meterTimer: Timer?
    var statusMenuItem: NSMenuItem!
    var lastMenuItem: NSMenuItem!
    var langItems: [String: NSMenuItem] = [:]

    let icons: [FlowState: String] = [.idle: "🎙", .recording: "🔴", .transcribing: "⏳"]

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        buildMenu()
        updateUI()

        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        checkAssets()

        if AXIsProcessTrusted() {
            setupEventTap()
        } else {
            // Show the system Accessibility prompt, then poll until the user
            // grants it — the hotkey activates automatically, no restart needed.
            _ = ensureAccessibility()
            statusMenuItem.title = "Väntar på Tillgänglighet…"
            setBarV(.systemGray)
            statusItem.button?.toolTip = "Viska väntar på Tillgänglighet-behörighet"
            trustTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] t in
                guard let self = self else { return }
                if AXIsProcessTrusted() {
                    t.invalidate()
                    self.trustTimer = nil
                    self.setupEventTap()
                    self.updateUI()
                }
            }
        }
    }

    // MARK: Menu

    func buildMenu() {
        let menu = NSMenu()
        statusMenuItem = NSMenuItem(title: "Redo", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        lastMenuItem = NSMenuItem(title: "Senaste: —", action: nil, keyEquivalent: "")
        lastMenuItem.isEnabled = false
        menu.addItem(lastMenuItem)

        menu.addItem(NSMenuItem.separator())

        let langParent = NSMenuItem(title: "Språk", action: nil, keyEquivalent: "")
        let langMenu = NSMenu()
        for (code, label) in [("auto", "Auto"), ("sv", "Svenska"), ("en", "English")] {
            let item = NSMenuItem(title: label, action: #selector(setLang(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = code
            item.state = (lang == code) ? .on : .off
            langItems[code] = item
            langMenu.addItem(item)
        }
        langParent.submenu = langMenu
        menu.addItem(langParent)

        let ptt = NSMenuItem(title: "Push-to-talk: Höger ⌘", action: nil, keyEquivalent: "")
        ptt.isEnabled = false
        menu.addItem(ptt)

        menu.addItem(NSMenuItem.separator())
        let quit = NSMenuItem(title: "Avsluta Viska", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc func setLang(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        lang = code
        UserDefaults.standard.set(code, forKey: "lang")
        for (c, item) in langItems { item.state = (c == code) ? .on : .off }
    }

    func setBarV(_ color: NSColor) {
        let font = NSFont.systemFont(ofSize: 15, weight: .bold)
        statusItem.button?.attributedTitle = NSAttributedString(
            string: "V", attributes: [.foregroundColor: color, .font: font])
    }

    func updateUI() {
        let label: String
        switch state {
        case .idle: setBarV(.systemGreen); label = "Redo"
        case .recording: setBarV(.systemRed); label = "● Spelar in…"
        case .transcribing: setBarV(.systemOrange); label = "… Transkriberar"
        }
        statusMenuItem.title = label
        let shown = lastText.count > 42 ? String(lastText.prefix(42)) + "…" : lastText
        lastMenuItem.title = "Senaste: \(shown)"
    }

    // MARK: Accessibility & event tap

    func ensureAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    func setupEventTap() {
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .listenOnly, eventsOfInterest: mask,
            callback: tapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            alert(title: "Kunde inte starta snabbtangenten",
                  text: "Ge Tillgänglighet-behörighet till Viska och starta om appen.")
            return
        }
        eventTap = tap
        let src = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func checkAssets() {
        var missing: [String] = []
        if !FileManager.default.fileExists(atPath: whisperCLI) { missing.append("whisper-cli") }
        if !FileManager.default.fileExists(atPath: modelPath) { missing.append(model) }
        if !missing.isEmpty {
            lastText = "saknar: " + missing.joined(separator: ", ")
            updateUI()
        }
    }

    // MARK: Push-to-talk

    func handlePTT(pressed: Bool) {
        if pressed {
            if state == .idle { startRecording() }
        } else {
            if state == .recording { stopAndTranscribe() }
        }
    }

    func startRecording() {
        let url = URL(fileURLWithPath: wavPath)
        try? FileManager.default.removeItem(at: url)
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
            recorder?.isMeteringEnabled = true
            recorder?.record()
            playSound("Pop")
            state = .recording
            updateUI()
            hud.showRecording()
            meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                self?.tickMeter()
            }
        } catch {
            lastText = "inspelningsfel"
            updateUI()
        }
    }

    func tickMeter() {
        guard let r = recorder, r.isRecording else { return }
        r.updateMeters()
        let db = r.averagePower(forChannel: 0)          // ~ -160 (tyst) .. 0 (max)
        let norm = max(0, min(1, (db + 55) / 55))
        hud.update(level: CGFloat(pow(norm, 0.65)))     // lyft svaga nivåer lite
    }

    func stopAndTranscribe() {
        meterTimer?.invalidate()
        meterTimer = nil
        recorder?.stop()
        recorder = nil
        state = .transcribing
        updateUI()
        hud.setTranscribing()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let text = self.runWhisper()
            DispatchQueue.main.async {
                self.state = .idle
                if let t = text, !t.isEmpty {
                    self.lastText = t
                    self.paste(t)
                    self.playSound("Glass")
                } else {
                    self.lastText = "(inget hördes)"
                }
                self.updateUI()
                self.hud.hide()
            }
        }
    }

    func runWhisper() -> String? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: wavPath)
        let size = (attrs?[.size] as? Int) ?? 0
        if size < 2000 { return nil }  // too short

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: whisperCLI)
        proc.arguments = ["-m", modelPath, "-f", wavPath, "-l", lang, "-nt", "-np", "-fa",
                          "-t", String(ProcessInfo.processInfo.activeProcessorCount)]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            let out = String(data: data, encoding: .utf8) ?? ""
            return out.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    func paste(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        // The PTT (Right ⌘) is long released by now (transcription took seconds),
        // so posting ⌘V is safe.
        let src = CGEventSource(stateID: .combinedSessionState)
        let vDown = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true) // 'v'
        vDown?.flags = .maskCommand
        let vUp = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
        vUp?.flags = .maskCommand
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
    }

    func playSound(_ name: String) {
        NSSound(named: NSSound.Name(name))?.play()
    }

    // MARK: Helpers

    func alert(title: String, text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.alertStyle = .informational
        a.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}

// MARK: - Entry point

let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // menu bar only, no Dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
