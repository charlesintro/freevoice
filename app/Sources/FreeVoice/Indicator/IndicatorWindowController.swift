// =============================================================================
// IndicatorWindowController.swift — Floating recording/transcribing indicator
// =============================================================================
//
// Shows a small dark pill in the lower-center of the screen:
//   • Recording  → 5 animated waveform bars (white → amber at 10-min warning)
//   • Transcribing → 3 pulsing dots
//   • × button   → cancels via HotkeyController.cancelRequestedNotification
//
// The panel is non-activating (never steals focus), floats above all windows,
// and is draggable by clicking anywhere on its background.
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
                                         brightness: 1.0, alpha: 1.0) // amber

    // MARK: - Init

    init() {
        observeNotifications()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Notification wiring

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
    }

    @objc private func onRecordingStarted() {
        ensurePanel()
        setDotsVisible(false)
        setBarColor(recordingColor)
        setBarsVisible(true)
        panel?.orderFrontRegardless()
    }

    @objc private func onTranscribingStarted() {
        setBarsVisible(false)
        setDotsVisible(true)
    }

    @objc private func onWarning() {
        setBarColor(warningColor)
    }

    @objc private func onDone() {
        panel?.orderOut(nil)
        setBarsVisible(false)
        setDotsVisible(false)
        // Reset bar color for next use
        setBarColor(recordingColor)
    }

    // MARK: - Panel construction

    private func ensurePanel() {
        guard panel == nil else { return }

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let sf = screen.visibleFrame
        let origin = CGPoint(x: sf.midX - panelW / 2, y: sf.minY + 80)

        let p = NSPanel(
            contentRect: NSRect(origin: origin, size: CGSize(width: panelW, height: panelH)),
            styleMask:   [.nonactivatingPanel, .borderless],
            backing:     .buffered,
            defer:       false
        )
        p.level                = .floating
        p.backgroundColor      = .clear
        p.isOpaque             = false
        p.hasShadow            = true
        p.isMovableByWindowBackground = true
        p.collectionBehavior   = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let content = DraggableView(frame: NSRect(x: 0, y: 0, width: panelW, height: panelH))
        content.wantsLayer = true

        // Dark pill background
        let bg = CALayer()
        bg.frame           = content.bounds
        bg.backgroundColor = NSColor(white: 0.10, alpha: 0.90).cgColor
        bg.cornerRadius    = panelH / 2
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
        let startX = (panelW - totalW) / 2 - 8   // shift left to leave room for × button

        for i in 0..<count {
            let bar = CALayer()
            let x   = startX + CGFloat(i) * (barW + gap)
            bar.frame         = CGRect(x: x, y: (panelH - barH) / 2, width: barW, height: barH)
            bar.anchorPoint   = CGPoint(x: 0.5, y: 0.5)
            bar.backgroundColor = recordingColor.cgColor
            bar.cornerRadius  = barW / 2
            bar.isHidden      = true

            let anim              = CAKeyframeAnimation(keyPath: "transform.scale.y")
            anim.values           = [0.2, 1.0, 0.5, 0.85, 0.2]
            anim.keyTimes         = [0, 0.25, 0.5, 0.75, 1.0]
            anim.duration         = 0.75
            anim.repeatCount      = .infinity
            anim.timeOffset       = Double(i) * 0.14
            anim.calculationMode  = .cubic
            bar.add(anim, forKey: "bounce")

            parent.addSublayer(bar)
            barLayers.append(bar)
        }
    }

    private func setBarsVisible(_ visible: Bool) {
        barLayers.forEach { $0.isHidden = !visible }
    }

    private func setBarColor(_ color: NSColor) {
        barLayers.forEach { $0.backgroundColor = color.cgColor }
    }

    // MARK: - Pulsing dots (transcribing)

    private func buildDots(in parent: CALayer) {
        let dotD:  CGFloat = 7
        let rep    = CAReplicatorLayer()
        rep.instanceCount     = 3
        rep.instanceDelay     = 0.22
        rep.instanceTransform = CATransform3DMakeTranslation(dotD + 6, 0, 0)

        let dot = CALayer()
        // Position the first dot so the 3-dot group is centered (accounting for × button)
        let groupW = 3 * dotD + 2 * 6
        dot.frame           = CGRect(x: (panelW - groupW) / 2 - 8,
                                     y: (panelH - dotD) / 2,
                                     width: dotD, height: dotD)
        dot.backgroundColor = NSColor.white.cgColor
        dot.cornerRadius    = dotD / 2

        let pulse            = CAKeyframeAnimation(keyPath: "transform.scale")
        pulse.values         = [1.0, 1.5, 1.0]
        pulse.keyTimes       = [0, 0.5, 1.0]
        pulse.duration       = 0.85
        pulse.repeatCount    = .infinity
        dot.add(pulse, forKey: "pulse")

        rep.addSublayer(dot)
        rep.isHidden = true
        parent.addSublayer(rep)
        dotsLayer = rep
    }

    private func setDotsVisible(_ visible: Bool) {
        dotsLayer?.isHidden = !visible
    }

    // MARK: - Cancel button

    private func buildCancelButton(in view: NSView) {
        let size: CGFloat = 20
        let btn = NSButton(frame: NSRect(
            x: panelW - size - 10,
            y: (panelH - size) / 2,
            width: size, height: size
        ))
        btn.bezelStyle        = .circular
        btn.isBordered        = false
        btn.title             = "✕"
        btn.font              = .systemFont(ofSize: 10, weight: .semibold)
        btn.contentTintColor  = NSColor(white: 0.55, alpha: 1)
        btn.target            = self
        btn.action            = #selector(cancelTapped)
        view.addSubview(btn)
    }

    @objc private func cancelTapped() {
        NotificationCenter.default.post(
            name: HotkeyController.cancelRequestedNotification,
            object: nil
        )
    }
}

// MARK: - Draggable content view

/// Plain NSView with mouseDownCanMoveWindow = true so the panel
/// can be repositioned by dragging anywhere on its background.
private final class DraggableView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}
