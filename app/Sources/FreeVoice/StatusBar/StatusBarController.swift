// =============================================================================
// StatusBarController.swift — Menu bar icon and menu
// =============================================================================

import Cocoa

/// Owns the `NSStatusItem` that lives in the macOS menu bar.
///
/// Phase 1: Static menu with only a Quit item.
/// Phase 2+: Menu becomes dynamic — shows recording state, recent transcripts,
///           hotkey picker, and preferences.
final class StatusBarController {

    private let statusItem: NSStatusItem

    // MARK: - Init

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureButton()
        configureMenu()
    }

    // MARK: - Private setup

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = makeBubbleIcon(size: 18)
        // isTemplate = true makes AppKit automatically invert the icon for
        // dark/light menu bars and the highlighted (pressed) state.
        button.image?.isTemplate = true
        button.toolTip = "FreeVoice"
    }

    private func configureMenu() {
        let menu = NSMenu()

        let header = NSMenuItem(title: "FreeVoice", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        menu.addItem(.separator())

        menu.addItem(
            NSMenuItem(
                title: "Quit FreeVoice",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )

        statusItem.menu = menu
    }

    // MARK: - Icon

    /// Draws a filled speech-bubble icon at the requested point size.
    ///
    /// The shape mirrors the Lua canvas icon from v1 (body = rounded rect,
    /// tail = small triangle at the lower-left corner of the body).
    /// Using `isTemplate = true` on the resulting image lets AppKit handle
    /// tint / inversion for dark-mode and highlight states automatically.
    private func makeBubbleIcon(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            let margin: CGFloat = 1.0
            let tailH:  CGFloat = size * 0.22      // height reserved for the tail
            let radius: CGFloat = size * 0.18      // corner radius of the bubble body

            // --- Bubble body (filled rounded rect) ---
            let bodyRect = CGRect(
                x:      margin,
                y:      tailH + margin * 0.5,
                width:  rect.width  - margin * 2,
                height: rect.height - tailH - margin * 1.5
            )
            let bubblePath = CGMutablePath()
            bubblePath.addRoundedRect(
                in: bodyRect,
                cornerWidth:  radius,
                cornerHeight: radius
            )
            ctx.addPath(bubblePath)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillPath()

            // --- Tail (small triangle at bottom-left of body) ---
            let tailX: CGFloat = size * 0.22
            let tailPath = CGMutablePath()
            tailPath.move(to:    CGPoint(x: tailX,              y: tailH + margin * 0.5))
            tailPath.addLine(to: CGPoint(x: tailX + size * 0.18, y: tailH + margin * 0.5))
            tailPath.addLine(to: CGPoint(x: tailX,              y: margin))
            tailPath.closeSubpath()
            ctx.addPath(tailPath)
            ctx.fillPath()

            return true
        }
    }
}
