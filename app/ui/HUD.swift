// Floating recording HUD shown near the bottom of the screen.
import Cocoa

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
        setStatus("Transkriberar…", color: .systemOrange)
    }

    func setStatus(_ text: String, color: NSColor) {
        wave.barColor = color
        wave.needsDisplay = true
        label.stringValue = text
    }

    func update(level: CGFloat) { wave.push(level) }

    func hide() {
        NSAnimationContext.runAnimationGroup({ c in
            c.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: { self.panel.orderOut(nil) })
    }
}
