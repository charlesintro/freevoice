// =============================================================================
// KeyRecorderView.swift — Click-to-record hotkey capture widget
// =============================================================================
//
// Usage (SwiftUI):
//   KeyRecorderView(keyCode:     $store.customKeyCode,
//                  flags:       $store.customFlags,
//                  displayName: $store.customDisplayName)
//
// UX:
//   • Shows the currently recorded combo (e.g. "⌃⌥A") or "Click to record…"
//   • Click → border turns accent-coloured, label says "Press shortcut…"
//   • Press any non-modifier key → combo is recorded, widget returns to normal
//   • Press Esc → cancel, no change
// =============================================================================

import Cocoa
import SwiftUI
import CoreGraphics

// MARK: - NSViewRepresentable bridge

struct KeyRecorderView: NSViewRepresentable {

    @Binding var keyCode:     CGKeyCode
    @Binding var flags:       CGEventFlags
    @Binding var displayName: String

    // Coordinator forwards recorded values back to the SwiftUI bindings.
    final class Coordinator {
        var parent: KeyRecorderView
        init(_ parent: KeyRecorderView) { self.parent = parent }

        func recorded(code: CGKeyCode, flags: CGEventFlags, name: String) {
            parent.keyCode     = code
            parent.flags       = flags
            parent.displayName = name
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> KeyRecorderNSView {
        let view = KeyRecorderNSView()
        let coordinator = context.coordinator
        view.onRecorded = { code, flags, name in
            coordinator.recorded(code: code, flags: flags, name: name)
        }
        return view
    }

    func updateNSView(_ nsView: KeyRecorderNSView, context: Context) {
        // Keep coordinator's parent reference fresh so bindings stay live.
        context.coordinator.parent = self
        nsView.displayLabel = displayName
    }
}

// MARK: - Native NSView implementation

final class KeyRecorderNSView: NSView {

    /// Called when the user successfully records a new shortcut.
    var onRecorded: ((CGKeyCode, CGEventFlags, String) -> Void)?

    /// Reflects the currently saved combo string (set by KeyRecorderView.updateNSView).
    var displayLabel: String = "" {
        didSet { needsDisplay = true }
    }

    private(set) var isRecording = false

    // MARK: - First-responder behaviour

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        isRecording = true
        needsDisplay = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        if isRecording {
            isRecording = false
            needsDisplay = true
        }
        return super.resignFirstResponder()
    }

    // MARK: - Key capture

    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }

        // Esc → cancel, no change
        if event.keyCode == 53 {
            isRecording = false
            needsDisplay = true
            window?.makeFirstResponder(nil)
            return
        }

        // Skip bare modifier key presses (no printable character yet)
        let chars = event.charactersIgnoringModifiers ?? ""
        if chars.isEmpty { return }

        let cgKeyCode = CGKeyCode(event.keyCode)
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])

        // Convert NSEvent flags → CGEventFlags
        var cgFlags = CGEventFlags()
        if mods.contains(.control) { cgFlags.insert(.maskControl) }
        if mods.contains(.option)  { cgFlags.insert(.maskAlternate) }
        if mods.contains(.shift)   { cgFlags.insert(.maskShift) }
        if mods.contains(.command) { cgFlags.insert(.maskCommand) }

        // Build the human-readable combo string (⌃⌥⇧⌘ order)
        var name = ""
        if mods.contains(.control) { name += "⌃" }
        if mods.contains(.option)  { name += "⌥" }
        if mods.contains(.shift)   { name += "⇧" }
        if mods.contains(.command) { name += "⌘" }
        name += chars.uppercased()

        onRecorded?(cgKeyCode, cgFlags, name)
        isRecording = false
        needsDisplay = true
        window?.makeFirstResponder(nil)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: 5, yRadius: 5)

        if isRecording {
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
            path.fill()
            NSColor.controlAccentColor.setStroke()
        } else {
            NSColor.controlBackgroundColor.setFill()
            path.fill()
            NSColor.separatorColor.setStroke()
        }
        path.lineWidth = 1
        path.stroke()

        let label: String
        let labelColor: NSColor
        if isRecording {
            label = "Press shortcut…"
            labelColor = .controlAccentColor
        } else if displayLabel.isEmpty {
            label = "Click to record…"
            labelColor = .placeholderTextColor
        } else {
            label = displayLabel
            labelColor = .labelColor
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font:            NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: labelColor,
        ]
        let str = NSAttributedString(string: label, attributes: attrs)
        let size = str.size()
        let origin = NSPoint(x: (bounds.width - size.width) / 2,
                             y: (bounds.height - size.height) / 2)
        str.draw(at: origin)
    }
}
