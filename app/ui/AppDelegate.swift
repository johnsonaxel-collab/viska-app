// Menu bar app: push-to-talk, transcription via the local whisper-server,
// paste at the cursor.
import Cocoa
import AVFoundation
import ApplicationServices

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

// Global event-tap callback (C function pointer, no captures).
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

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let wavPath = NSTemporaryDirectory() + "viska.wav"

    // Config (persisted in UserDefaults)
    var lang = UserDefaults.standard.string(forKey: "lang") ?? "sv"
    var model = ModelCatalog.byId(UserDefaults.standard.string(forKey: "modelSize"))
    let pttKeycode: Int64 = 54  // Right Command

    var server: WhisperServer?
    var serverReady = false
    var state: FlowState = .idle
    var lastText = "—"
    var lastTime: String?
    var recorder: AVAudioRecorder?
    var statusItem: NSStatusItem!
    var eventTap: CFMachPort?
    var trustTimer: Timer?
    let hud = RecordingHUD()
    let downloadWindow = DownloadWindow()
    var meterTimer: Timer?
    var statusMenuItem: NSMenuItem!
    var lastMenuItem: NSMenuItem!
    var timeMenuItem: NSMenuItem!
    var langItems: [String: NSMenuItem] = [:]
    var modelItems: [String: NSMenuItem] = [:]

    // Rewriting with a local language model (Ollama)
    var rewriteOn = UserDefaults.standard.object(forKey: "rewrite") as? Bool ?? true
    let rewriter = Rewriter(model: UserDefaults.standard.string(forKey: "llmModel") ?? "qwen2.5:7b")
    var ollamaModels: [String]?     // nil = Ollama not running
    var rewriteMenu: NSMenu!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        buildMenu()
        updateUI()

        AVCaptureDevice.requestAccess(for: .audio) { _ in }

        if let bin = Paths.binary("whisper-server") {
            server = WhisperServer(binary: bin)
            useModel(model)
        } else {
            lastText = "saknar whisper-server, kör ./setup.sh"
            updateUI()
        }
        refreshOllama(warm: true)

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

    /// Asks Ollama which models exist; optionally loads the chosen one into memory.
    func refreshOllama(warm: Bool) {
        let rewriter = self.rewriter
        DispatchQueue.global(qos: .utility).async {
            let models = rewriter.client.models()
            DispatchQueue.main.async { self.ollamaModels = models }
            if warm, let m = models, m.contains(rewriter.model) { rewriter.warmUp() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
    }

    // MARK: Model + engine

    /// Downloads the model if needed, then (re)starts the engine with it.
    func useModel(_ m: WhisperModel) {
        guard m.isDownloaded else {
            downloadWindow.onFinish = { [weak self] ok in
                guard let self = self else { return }
                if ok {
                    self.useModel(m)
                } else if !self.model.isDownloaded {
                    self.lastText = "ingen talmodell, välj en i menyn"
                    self.updateUI()
                }
            }
            downloadWindow.download(m)
            return
        }
        model = m
        UserDefaults.standard.set(m.id, forKey: "modelSize")
        for (id, item) in modelItems { item.state = (id == m.id) ? .on : .off }
        startServer()
    }

    func startServer() {
        guard let server = server else { return }
        serverReady = false
        statusMenuItem.title = "Laddar talmodell…"
        let path = model.localURL.path, lang = self.lang
        DispatchQueue.global(qos: .userInitiated).async {
            var ok = false
            do {
                try server.start(modelPath: path, language: lang == "auto" ? "sv" : lang)
                ok = server.waitUntilReady(timeout: 30)
            } catch {}
            DispatchQueue.main.async {
                self.serverReady = ok
                if !ok { self.lastText = "talmotorn startade inte" }
                self.updateUI()
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

        timeMenuItem = NSMenuItem(title: "Tid: —", action: #selector(openTimeLog), keyEquivalent: "")
        timeMenuItem.target = self
        timeMenuItem.toolTip = "Från att du släpper ⌘ tills texten klistras in. Klicka för hela loggen."
        menu.addItem(timeMenuItem)

        menu.addItem(NSMenuItem.separator())

        let modelParent = NSMenuItem(title: "Talmodell", action: nil, keyEquivalent: "")
        let modelMenu = NSMenu()
        for m in ModelCatalog.all {
            let item = NSMenuItem(title: "\(m.title) (\(m.approxMB) MB)",
                                  action: #selector(setModel(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = m.id
            item.state = (model == m) ? .on : .off
            modelItems[m.id] = item
            modelMenu.addItem(item)
        }
        modelParent.submenu = modelMenu
        menu.addItem(modelParent)

        let langParent = NSMenuItem(title: "Språk", action: nil, keyEquivalent: "")
        let langMenu = NSMenu()
        for (code, label) in [("sv", "Svenska"), ("en", "Engelska"), ("auto", "Känn av automatiskt")] {
            let item = NSMenuItem(title: label, action: #selector(setLang(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = code
            item.state = (lang == code) ? .on : .off
            langItems[code] = item
            langMenu.addItem(item)
        }
        langParent.submenu = langMenu
        menu.addItem(langParent)

        let rewriteParent = NSMenuItem(title: "Omskrivning", action: nil, keyEquivalent: "")
        rewriteMenu = NSMenu()
        rewriteMenu.delegate = self   // rebuilt each time it opens, so the model list is fresh
        rewriteParent.submenu = rewriteMenu
        menu.addItem(rewriteParent)

        let ptt = NSMenuItem(title: "Håll in höger ⌘ för att prata", action: nil, keyEquivalent: "")
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

    @objc func setModel(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        let m = ModelCatalog.byId(id)
        if m != model || !serverReady { useModel(m) }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === rewriteMenu else { return }
        menu.removeAllItems()
        let toggle = NSMenuItem(title: "Skriv om till färdig text", action: #selector(toggleRewrite), keyEquivalent: "")
        toggle.target = self
        toggle.state = rewriteOn ? .on : .off
        menu.addItem(toggle)
        menu.addItem(NSMenuItem.separator())

        if let models = ollamaModels, !models.isEmpty {
            let head = NSMenuItem(title: "Språkmodell", action: nil, keyEquivalent: "")
            head.isEnabled = false
            menu.addItem(head)
            for m in models {
                let item = NSMenuItem(title: m, action: #selector(setLLM(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = m
                item.state = (m == rewriter.model) ? .on : .off
                menu.addItem(item)
            }
            if !models.contains(rewriter.model) {
                let warn = NSMenuItem(title: "\(rewriter.model) saknas: kör ollama pull \(rewriter.model)", action: nil, keyEquivalent: "")
                warn.isEnabled = false
                menu.addItem(warn)
            }
        } else {
            let off = NSMenuItem(title: ollamaModels == nil ? "Ollama är inte igång" : "Inga modeller i Ollama",
                                 action: nil, keyEquivalent: "")
            off.isEnabled = false
            menu.addItem(off)
        }
        menu.addItem(NSMenuItem.separator())
        let edit = NSMenuItem(title: "Redigera prompt…", action: #selector(editPrompt), keyEquivalent: "")
        edit.target = self
        menu.addItem(edit)
        refreshOllama(warm: false)
    }

    @objc func toggleRewrite() {
        rewriteOn.toggle()
        UserDefaults.standard.set(rewriteOn, forKey: "rewrite")
    }

    @objc func setLLM(_ sender: NSMenuItem) {
        guard let m = sender.representedObject as? String else { return }
        rewriter.model = m
        UserDefaults.standard.set(m, forKey: "llmModel")
        refreshOllama(warm: true)
    }

    @objc func editPrompt() {
        _ = Prompts.load(Prompts.rewriteFile)   // creates the file on first use
        NSWorkspace.shared.open(Prompts.url(Prompts.rewriteFile))
    }

    @objc func openTimeLog() {
        NSWorkspace.shared.open(LatencyLog.url)
    }

    func setBarV(_ color: NSColor) {
        let font = NSFont.systemFont(ofSize: 15, weight: .bold)
        statusItem.button?.attributedTitle = NSAttributedString(
            string: "V", attributes: [.foregroundColor: color, .font: font])
    }

    func updateUI() {
        let label: String
        switch state {
        case .idle:
            setBarV(serverReady ? .systemGreen : .systemGray)
            label = serverReady ? "Redo · \(model.title)" : "Laddar talmodell…"
        case .recording: setBarV(.systemRed); label = "● Spelar in…"
        case .transcribing: setBarV(.systemOrange); label = "… Transkriberar"
        }
        statusMenuItem.title = label
        let shown = lastText.count > 42 ? String(lastText.prefix(42)) + "…" : lastText
        lastMenuItem.title = "Senaste: \(shown)"
        timeMenuItem.title = "Tid: \(lastTime ?? "—")"
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
        let sw = Stopwatch()
        meterTimer?.invalidate()
        meterTimer = nil
        recorder?.stop()
        recorder = nil
        sw.mark("inspelning")
        state = .transcribing
        updateUI()
        hud.setTranscribing()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var text = self.transcribe()
            sw.mark("tal_till_text")
            var note: String?
            if self.rewriteOn, let raw = text, !raw.isEmpty {
                DispatchQueue.main.async { self.hud.setStatus("Skriver om…", color: .systemPurple) }
                do {
                    text = try self.rewriter.rewrite(raw)
                } catch {
                    note = (error as? RewriteError).map { e -> String in
                        if case .unavailable = e { return "Rå text: Ollama svarar inte" }
                        return "Rå text: omskrivningen stoppades"
                    } ?? "Rå text"
                    RewriteLog.append(raw: raw, error: error.localizedDescription)
                }
                sw.mark("omskrivning")
            }
            DispatchQueue.main.async {
                self.state = .idle
                if let t = text, !t.isEmpty {
                    self.lastText = t
                    self.paste(t)
                    sw.mark("inklistring")
                    self.lastTime = formatSeconds(sw.total)
                    let models = self.rewriteOn ? "\(self.model.repo)+\(self.rewriter.model)" : self.model.repo
                    LatencyLog.append(sw, model: models, chars: t.count)
                    self.playSound("Glass")
                } else {
                    self.lastText = "(inget hördes)"
                }
                self.updateUI()
                if let note = note {
                    // Say why the text was pasted unedited, then fade out.
                    self.hud.setStatus(note, color: .systemYellow)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { self.hud.hide() }
                } else {
                    self.hud.hide()
                }
            }
        }
    }

    /// Runs off the main thread.
    func transcribe() -> String? {
        let url = URL(fileURLWithPath: wavPath)
        let size = (try? FileManager.default.attributesOfItem(atPath: wavPath)[.size] as? Int) ?? 0
        if size < 2000 { return nil }  // too short
        guard let server = server else { return nil }
        // First dictation right after launch may arrive while the model loads.
        if !server.waitUntilReady(timeout: 30) { return nil }
        return try? server.transcribe(wav: url, language: lang == "auto" ? "auto" : lang)
    }

    func paste(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        // The PTT key is released by now, so posting ⌘V is safe.
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
