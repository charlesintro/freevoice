// =============================================================================
// IndicatorWindowController.swift — Floating recording/transcribing indicator
// =============================================================================
//
// Shows a small translucent rounded-rectangle in the lower-center of the screen:
//   • Recording    → 6 braille chars driven by RMS audio level.
//                    Silence: ⠒⠒⠒⠒⠒⠒ (slow staggered breath).
//                    Talking: ⠶/⠿/⣿ per bar.
//   • Transcribing → same label, rolling braille wave (⠂⠒⠶⠿⣿⠿⠶⠒ cycling).
//   • × button     → top-left corner, cancels recording.
// =============================================================================

import Cocoa

final class IndicatorWindowController {

    private var panel: NSPanel?
    private var waveLabel: NSTextField?

    private let panelW: CGFloat = 74
    private let panelH: CGFloat = 38

    private let recordingColor = NSColor.white
    private let warningColor   = NSColor(calibratedHue: 0.08, saturation: 0.95,
                                         brightness: 1.0, alpha: 1.0)

    // MARK: - Recording audio level state

    private var barLevels:  [Float] = [0, 0, 0, 0, 0, 0]
    private var breathPhase: Float  = 0
    private var levelTimer: Timer?

    private let barAttacks: [Float] = [0.78, 0.85, 0.92, 0.95, 0.88, 0.72]
    private let barDecays:  [Float] = [0.50, 0.55, 0.62, 0.65, 0.58, 0.48]

    // MARK: - Transcribing animation state

    // Rolling wave of braille density — scrolls left on each tick
    private let transcribingRing: [Character] = ["⠂", "⠒", "⠶", "⠿", "⣿", "⠿", "⠶", "⠒"]
    private var transcribingPhase = 0
    private var transcribingTimer: Timer?

    // MARK: - Init

    init() { observeNotifications() }
    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: - Notifications

    private func observeNotifications() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(onRecordingStarted),
                       name: HotkeyController.recordingStartedNotification, object: nil)
        nc.addObserver(self, selector: #selector(onTranscribingStarted),
                       name: HotkeyController.transcribingStartedNotification, object: nil)
        nc.addObserver(self, selector: #selector(onWarning),
                       name: HotkeyController.recordingWarningNotification, object: nil)
        nc.addObserver(self, selector: #selector(onDone),
                       name: HotkeyController.transcriptReadyNotification, object: nil)
        nc.addObserver(self, selector: #selector(onDone),
                       name: HotkeyController.recordingCancelledNotification, object: nil)
        nc.addObserver(self, selector: #selector(onDone),
                       name: HotkeyController.transcriptionFailedNotification, object: nil)
        nc.addObserver(self, selector: #selector(onAudioLevel(_:)),
                       name: RecordingController.audioLevelNotification, object: nil)
    }

    @objc private func onRecordingStarted() {
        ensurePanel()
        stopTranscribingTimer()
        setWaveColor(recordingColor)
        waveLabel?.isHidden = false
        panel?.orderFrontRegardless()
        startLevelTimer()
    }

    @objc private func onTranscribingStarted() {
        stopLevelTimer()
        startTranscribingTimer()
    }

    @objc private func onWarning() { setWaveColor(warningColor) }

    @objc private func onDone() {
        stopLevelTimer()
        stopTranscribingTimer()
        panel?.orderOut(nil)
        waveLabel?.isHidden = true
        setWaveColor(recordingColor)
    }

    @objc private func onAudioLevel(_ note: Notification) {
        guard let level = note.userInfo?["level"] as? Float else { return }
        for i in 0..<barLevels.count {
            let target = level * Float.random(in: 0.40...1.0)
            let alpha  = target > barLevels[i] ? barAttacks[i] : barDecays[i]
            barLevels[i] = alpha * target + (1 - alpha) * barLevels[i]
        }
    }

    // MARK: - Recording: level-driven braille

    private func startLevelTimer() {
        barLevels   = [0, 0, 0, 0, 0, 0]
        breathPhase = 0
        levelTimer?.invalidate()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 1 / 20, repeats: true) { [weak self] _ in
            self?.updateRecordingBraille()
        }
    }

    private func stopLevelTimer() {
        levelTimer?.invalidate()
        levelTimer = nil
        barLevels  = [0, 0, 0, 0, 0, 0]
    }

    private func updateRecordingBraille() {
        breathPhase += 0.04

        var chars = ""
        for i in 0..<barLevels.count {
            let level = max(0, min(1.0, (barLevels[i] - 0.006) / 0.040))
            if level < 0.06 {
                let breath = sin(breathPhase + Float(i) * 0.8)
                chars += breath > 0 ? "⠒" : "⠂"
            } else if level < 0.35 {
                chars += "⠶"
            } else if level < 0.68 {
                chars += "⠿"
            } else {
                chars += "⣿"
            }
        }
        waveLabel?.stringValue = chars
    }

    // MARK: - Transcribing: rolling braille wave

    private func startTranscribingTimer() {
        transcribingPhase = 0
        transcribingTimer?.invalidate()
        transcribingTimer = Timer.scheduledTimer(withTimeInterval: 1 / 8, repeats: true) { [weak self] _ in
            self?.updateTranscribingBraille()
        }
    }

    private func stopTranscribingTimer() {
        transcribingTimer?.invalidate()
        transcribingTimer = nil
    }

    private func updateTranscribingBraille() {
        var chars = ""
        for i in 0..<6 {
            chars += String(transcribingRing[(transcribingPhase + i) % transcribingRing.count])
        }
        transcribingPhase = (transcribingPhase + 1) % transcribingRing.count
        waveLabel?.stringValue = chars
    }

    // MARK: - Helpers

    private func setWaveColor(_ color: NSColor) { waveLabel?.textColor = color }

    // MARK: - Panel construction

    private func ensurePanel() {
        guard panel == nil else { return }

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let sf     = screen.visibleFrame
        let origin = CGPoint(x: sf.midX - panelW / 2, y: sf.minY + 80)

        let p = NSPanel(
            contentRect: NSRect(origin: origin, size: CGSize(width: panelW, height: panelH)),
            styleMask:   [.nonactivatingPanel, .borderless],
            backing:     .buffered,
            defer:       false
        )
        p.level                       = .floating
        p.backgroundColor             = .clear
        p.isOpaque                    = false
        p.hasShadow                   = true
        p.isMovableByWindowBackground = true
        p.collectionBehavior          = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let content = DraggableView(frame: NSRect(x: 0, y: 0, width: panelW, height: panelH))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.clear.cgColor

        let bg = CALayer()
        bg.frame           = content.bounds
        bg.backgroundColor = NSColor(white: 0.06, alpha: 0.72).cgColor
        bg.cornerRadius    = 10
        bg.masksToBounds   = true
        content.layer?.addSublayer(bg)

        // Braille label — centered, nudged right of cancel button
        let lbl = NSTextField(labelWithString: "⠒⠒⠒⠒⠒⠒")
        lbl.font            = NSFont(name: "Menlo", size: 12)
                              ?? .monospacedSystemFont(ofSize: 12, weight: .regular)
        lbl.textColor       = .white
        lbl.backgroundColor = .clear
        lbl.isBezeled       = false
        lbl.isEditable      = false
        lbl.sizeToFit()
        lbl.frame = NSRect(
            x: (panelW - lbl.frame.width) / 2,
            y: (panelH - lbl.frame.height) / 2,
            width: lbl.frame.width,
            height: lbl.frame.height
        )
        lbl.isHidden = true
        content.addSubview(lbl)
        waveLabel = lbl

        // Cancel button added after label so it renders on top
        buildCancelButton(in: content)

        p.contentView = content
        panel = p
    }

    // MARK: - Cancel button (top-left, floats over content)

    private func buildCancelButton(in view: NSView) {
        let size: CGFloat = 12
        let btn = HoverButton(frame: NSRect(
            x: 4,
            y: panelH - size - 4,
            width: size, height: size
        ))
        btn.bezelStyle       = .circular
        btn.isBordered       = false
        btn.title            = "✕"
        btn.font             = .systemFont(ofSize: 8, weight: .semibold)
        btn.contentTintColor = NSColor(white: 0.45, alpha: 1)
        btn.target           = self
        btn.action           = #selector(cancelTapped)
        view.addSubview(btn)
    }

    @objc private func cancelTapped() {
        NotificationCenter.default.post(name: HotkeyController.cancelRequestedNotification, object: nil)
    }
}

// MARK: - Draggable content view

private final class DraggableView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}

// MARK: - Cancel button with hover highlight

private final class HoverButton: NSButton {
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self, userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        contentTintColor = NSColor(white: 0.95, alpha: 1)
    }

    override func mouseExited(with event: NSEvent) {
        contentTintColor = NSColor(white: 0.45, alpha: 1)
    }
}
