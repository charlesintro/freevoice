// =============================================================================
// IndicatorWindowController.swift — Floating recording/transcribing indicator
// =============================================================================
//
// Shows a small translucent pill in the lower-center of the screen:
//   • Recording    → 5 waveform bars, each oscillating at its own frequency so
//                    they react organically to audio (flat at silence, chaotic
//                    spikes when talking). White → amber at 10-min warning.
//   • Transcribing → 3 pulsing dots
//   • × button     → top-left, cancels via HotkeyController.cancelRequestedNotification
//
// The panel is non-activating, floats above all windows, and is draggable.
// =============================================================================

import Cocoa

final class IndicatorWindowController {

    private var panel: NSPanel?
    private var barLayers: [CALayer] = []
    private var dotsLayer: CAReplicatorLayer?

    private let panelW: CGFloat = 130
    private let panelH: CGFloat = 50

    private let recordingColor = NSColor.white
    private let warningColor   = NSColor(calibratedHue: 0.08, saturation: 0.95,
                                         brightness: 1.0, alpha: 1.0)

    // MARK: - Audio level state

    private var barLevels:  [Float] = [0, 0, 0, 0, 0]
    private var breathPhase: Float = 0
    private var levelTimer: Timer?

    // Fast attack so bars spike immediately; fast decay so they snap back to
    // flat within ~200 ms of silence (alpha 0.55 → ×0.45 per callback ≈ 3
    // callbacks to near-zero at the ~10 Hz audio tap rate).
    private let barAttacks: [Float] = [0.78, 0.90, 0.95, 0.85, 0.72]
    private let barDecays:  [Float] = [0.52, 0.58, 0.64, 0.56, 0.48]

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
        nc.addObserver(self, selector: #selector(onAudioLevel(_:)),
                       name: RecordingController.audioLevelNotification, object: nil)
    }

    @objc private func onRecordingStarted() {
        ensurePanel()
        setDotsVisible(false)
        setBarColor(recordingColor)
        setBarsVisible(true)
        panel?.orderFrontRegardless()
        startLevelTimer()
    }

    @objc private func onTranscribingStarted() {
        stopLevelTimer()
        setBarsVisible(false)
        setDotsVisible(true)
    }

    @objc private func onWarning() { setBarColor(warningColor) }

    @objc private func onDone() {
        stopLevelTimer()
        panel?.orderOut(nil)
        setBarsVisible(false)
        setDotsVisible(false)
        setBarColor(recordingColor)
    }

    @objc private func onAudioLevel(_ note: Notification) {
        guard let level = note.userInfo?["level"] as? Float else { return }
        for i in 0..<barLevels.count {
            // Each bar sees a randomly scaled version of the incoming level so
            // they respond to different virtual "amounts" of audio each callback.
            // At silence level=0 so scaling is irrelevant — bars stay flat.
            let target = level * Float.random(in: 0.40...1.0)
            let alpha  = target > barLevels[i] ? barAttacks[i] : barDecays[i]
            barLevels[i] = alpha * target + (1 - alpha) * barLevels[i]
        }
    }

    // MARK: - Level-driven bar animation

    private func startLevelTimer() {
        barLevels   = [0, 0, 0, 0, 0]
        breathPhase = 0
        levelTimer?.invalidate()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 1 / 20, repeats: true) { [weak self] _ in
            self?.updateBarHeights()
        }
    }

    private func stopLevelTimer() {
        levelTimer?.invalidate()
        levelTimer = nil
        barLevels  = [0, 0, 0, 0, 0]
    }

    private func updateBarHeights() {
        // Slow breath: full cycle ~8 s, each bar staggered by 0.5 rad → gentle wave
        breathPhase += 0.04

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.04)
        for (i, bar) in barLayers.enumerated() {
            // Tighter ramp → bars reach full height at ~0.046 RMS (normal speech)
            let level = max(0, min(1.0, (barLevels[i] - 0.006) / 0.040))

            // Subtle idle breath that fades away as audio arrives
            let breath = Float(0.11) * (1 - level)
                         * (0.5 + 0.5 * sin(breathPhase + Float(i) * 0.5))

            let scaleY = CGFloat(0.07 + breath + level * 0.93)
            bar.setValue(scaleY, forKeyPath: "transform.scale.y")
        }
        CATransaction.commit()
    }

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
        bg.cornerRadius    = panelH / 2
        bg.masksToBounds   = true

        content.layer?.addSublayer(bg)
        buildBars(in: bg)
        buildDots(in: bg)
        buildCancelButton(in: content)

        p.contentView = content
        panel = p
    }

    // MARK: - Waveform bars

    private func buildBars(in parent: CALayer) {
        let count  = 5
        let barW:  CGFloat = 4
        let barH:  CGFloat = panelH * 0.52
        let gap:   CGFloat = 5
        let totalW = CGFloat(count) * barW + CGFloat(count - 1) * gap
        let startX = (panelW - totalW) / 2 + 8

        for i in 0..<count {
            let bar = CALayer()
            let x   = startX + CGFloat(i) * (barW + gap)
            bar.frame           = CGRect(x: x, y: (panelH - barH) / 2, width: barW, height: barH)
            bar.anchorPoint     = CGPoint(x: 0.5, y: 0.5)
            bar.backgroundColor = recordingColor.cgColor
            bar.cornerRadius    = barW / 2
            bar.isHidden        = true
            bar.transform       = CATransform3DMakeScale(1.0, 0.10, 1.0)

            parent.addSublayer(bar)
            barLayers.append(bar)
        }
    }

    private func setBarsVisible(_ visible: Bool) { barLayers.forEach { $0.isHidden = !visible } }
    private func setBarColor(_ color: NSColor)   { barLayers.forEach { $0.backgroundColor = color.cgColor } }

    // MARK: - Pulsing dots (transcribing)

    private func buildDots(in parent: CALayer) {
        let dotD:  CGFloat = 7
        let rep    = CAReplicatorLayer()
        rep.instanceCount     = 3
        rep.instanceDelay     = 0.25
        rep.instanceTransform = CATransform3DMakeTranslation(dotD + 6, 0, 0)

        let groupW = 3 * dotD + 2 * 6
        let dot    = CALayer()
        dot.frame           = CGRect(x: (panelW - groupW) / 2 + 8,
                                     y: (panelH - dotD) / 2,
                                     width: dotD, height: dotD)
        dot.backgroundColor = NSColor.white.cgColor
        dot.cornerRadius    = dotD / 2

        let pulse         = CAKeyframeAnimation(keyPath: "transform.scale")
        pulse.values      = [1.0, 1.5, 1.0]
        pulse.keyTimes    = [0, 0.5, 1.0]
        pulse.duration    = 1.0
        pulse.repeatCount = .infinity
        dot.add(pulse, forKey: "pulse")

        rep.addSublayer(dot)
        rep.isHidden = true
        parent.addSublayer(rep)
        dotsLayer = rep
    }

    private func setDotsVisible(_ visible: Bool) { dotsLayer?.isHidden = !visible }

    // MARK: - Cancel button

    private func buildCancelButton(in view: NSView) {
        let size: CGFloat = 20
        let btn = NSButton(frame: NSRect(
            x: 8,
            y: (panelH - size) / 2,
            width: size, height: size
        ))
        btn.bezelStyle       = .circular
        btn.isBordered       = false
        btn.title            = "✕"
        btn.font             = .systemFont(ofSize: 10, weight: .semibold)
        btn.contentTintColor = NSColor(white: 0.65, alpha: 1)
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
