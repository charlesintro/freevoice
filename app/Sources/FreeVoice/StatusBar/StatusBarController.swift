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

        // --- Model download state (first-run only) ---
        if case .downloading = TranscriptionController.shared.modelState {
            let dlItem = NSMenuItem(title: "Downloading model…", action: nil, keyEquivalent: "")
            dlItem.isEnabled = false
            menu.addItem(dlItem)
        }

        menu.addItem(.separator())

        // --- Copy Last Transcript ---
        let recent = store.loadRecent(limit: 1)
        let copyItem = NSMenuItem(
            title: "Copy Last Transcript",
            action: recent.isEmpty ? nil : #selector(copyLastTranscript),
            keyEquivalent: ""
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

        // --- Microphone picker ---
        let micParent  = NSMenuItem(title: "Microphone", action: nil, keyEquivalent: "")
        let micSubmenu = NSMenu(title: "Microphone")
        let currentUID = PreferencesStore.shared.inputDeviceUID

        let defaultItem = NSMenuItem(title: "System Default",
                                     action: #selector(changeMicrophone(_:)),
                                     keyEquivalent: "")
        defaultItem.target            = self
        defaultItem.representedObject = ""
        defaultItem.state             = currentUID.isEmpty ? .on : .off
        micSubmenu.addItem(defaultItem)

        let devices = AudioDeviceHelper.listInputDevices()
        if !devices.isEmpty {
            micSubmenu.addItem(.separator())
            for device in devices {
                let item = NSMenuItem(title: device.name,
                                      action: #selector(changeMicrophone(_:)),
                                      keyEquivalent: "")
                item.target            = self
                item.representedObject = device.uid
                item.state             = (device.uid == currentUID) ? .on : .off
                micSubmenu.addItem(item)
            }
        }
        micParent.submenu = micSubmenu
        menu.addItem(micParent)

        // --- Hotkey picker ---
        let hotkeyParent  = NSMenuItem(title: "Hotkey", action: nil, keyEquivalent: "")
        let hotkeySubmenu = NSMenu(title: "Hotkey")
        let store         = PreferencesStore.shared
        let currentHotkey = store.hotkey
        for option in HotkeyOption.allCases {
            // For the Custom option, show the recorded combo or "(not set)"
            let title: String
            if option == .custom {
                let name = store.customDisplayName
                title = name.isEmpty ? "Custom (not set)" : "Custom: \(name)"
            } else {
                title = option.displayName
            }
            let item = NSMenuItem(
                title:          title,
                action:         #selector(changeHotkey(_:)),
                keyEquivalent:  ""
            )
            item.target            = self
            item.representedObject = option.rawValue
            item.state             = (option == currentHotkey) ? .on : .off
            hotkeySubmenu.addItem(item)
        }
        hotkeyParent.submenu = hotkeySubmenu
        menu.addItem(hotkeyParent)

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

    @objc private func changeHotkey(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let option = HotkeyOption(rawValue: raw) else { return }
        PreferencesStore.shared.hotkey = option
        NSLog("[FreeVoice] Hotkey changed to %@", option.displayName)
        // If custom isn't recorded yet, open Preferences so user can set it up
        if option == .custom && PreferencesStore.shared.customDisplayName.isEmpty {
            onOpenPreferences?()
        }
    }

    @objc private func changeMicrophone(_ sender: NSMenuItem) {
        guard let uid = sender.representedObject as? String else { return }
        PreferencesStore.shared.inputDeviceUID = uid
        NSLog("[FreeVoice] Microphone changed to: %@", uid.isEmpty ? "System Default" : uid)
    }

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

    // MARK: - Icon drawing

    /// Idle state: filled speech-bubble.
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
