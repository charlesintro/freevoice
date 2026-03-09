// =============================================================================
// StatusBarController.swift — Menu bar icon and dynamic menu
// =============================================================================

import Cocoa

/// Owns the `NSStatusItem` that lives in the macOS menu bar.
///
/// Phase 2: Dynamic menu rebuilt on open — shows "Copy Last Transcript" and
///          a "Recent Transcripts" submenu (up to 5 items from TranscriptStore).
final class StatusBarController: NSObject, NSMenuDelegate {

    private let statusItem: NSStatusItem
    private let store = TranscriptStore()
    var onOpenPreferences: (() -> Void)?   // set by AppDelegate

    // MARK: - Init

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureButton()
        configureMenu()
        observeTranscripts()
    }

    // MARK: - Private setup

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = makeBubbleIcon(size: 18)
        button.image?.isTemplate = true
        button.toolTip = "FreeVoice"
    }

    private func configureMenu() {
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        // buildMenu() is called by NSMenuDelegate.menuWillOpen(_:) so it's
        // always fresh when the user clicks the icon.
    }

    private func observeTranscripts() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTranscriptReady(_:)),
            name: HotkeyController.transcriptReadyNotification,
            object: nil
        )
    }

    @objc private func handleTranscriptReady(_ note: Notification) {
        // Nothing visible needed here for now — menu rebuilds on next open.
        // Phase 3 will flash the indicator window.
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        buildMenu(menu)
    }

    // MARK: - Menu construction

    private func buildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        // --- Header ---
        let header = NSMenuItem(title: "FreeVoice", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        menu.addItem(.separator())

        // --- Copy Last Transcript ---
        let recent = store.loadRecent(limit: 1)
        let copyItem = NSMenuItem(
            title: "Copy Last Transcript",
            action: recent.isEmpty ? nil : #selector(copyLastTranscript),
            keyEquivalent: "c"
        )
        copyItem.target  = self
        copyItem.isEnabled = !recent.isEmpty
        menu.addItem(copyItem)

        // --- Recent Transcripts submenu ---
        let recentItems = store.loadRecent(limit: 5)
        if !recentItems.isEmpty {
            let submenuParent = NSMenuItem(title: "Recent Transcripts", action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: "Recent Transcripts")
            for (idx, text) in recentItems.reversed().enumerated() {
                let truncated = text.count > 60 ? String(text.prefix(57)) + "…" : text
                let item = NSMenuItem(
                    title: "\(idx + 1). \(truncated)",
                    action: #selector(copyRecentTranscript(_:)),
                    keyEquivalent: ""
                )
                item.target          = self
                item.representedObject = text
                submenu.addItem(item)
            }
            submenuParent.submenu = submenu
            menu.addItem(submenuParent)
        }

        menu.addItem(.separator())

        // --- Preferences ---
        let prefsItem = NSMenuItem(title: "Preferences…", action: #selector(openPreferences),
                                   keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        // --- Quit ---
        menu.addItem(
            NSMenuItem(
                title: "Quit FreeVoice",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )
    }

    // MARK: - Actions

    @objc private func openPreferences() { onOpenPreferences?() }

    @objc private func copyLastTranscript() {
        guard let text = store.loadRecent(limit: 1).first else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func copyRecentTranscript(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Icon

    /// Draws a filled speech-bubble icon at the requested point size.
    private func makeBubbleIcon(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            let margin: CGFloat = 1.0
            let tailH:  CGFloat = size * 0.22
            let radius: CGFloat = size * 0.18

            let bodyRect = CGRect(
                x:      margin,
                y:      tailH + margin * 0.5,
                width:  rect.width  - margin * 2,
                height: rect.height - tailH - margin * 1.5
            )
            let bubblePath = CGMutablePath()
            bubblePath.addRoundedRect(in: bodyRect, cornerWidth: radius, cornerHeight: radius)
            ctx.addPath(bubblePath)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillPath()

            let tailX: CGFloat = size * 0.22
            let tailPath = CGMutablePath()
            tailPath.move(to:    CGPoint(x: tailX,               y: tailH + margin * 0.5))
            tailPath.addLine(to: CGPoint(x: tailX + size * 0.18, y: tailH + margin * 0.5))
            tailPath.addLine(to: CGPoint(x: tailX,               y: margin))
            tailPath.closeSubpath()
            ctx.addPath(tailPath)
            ctx.fillPath()

            return true
        }
    }
}
