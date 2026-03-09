// =============================================================================
// PreferencesWindowController.swift — SwiftUI preferences window
// =============================================================================

import Cocoa
import SwiftUI

// MARK: - Window controller

final class PreferencesWindowController: NSWindowController {

    convenience init() {
        let view    = PreferencesView(store: PreferencesStore.shared)
        let hosting = NSHostingController(rootView: view)
        let window  = NSWindow(contentViewController: hosting)
        window.title                = "FreeVoice Preferences"
        window.styleMask            = [.titled, .closable]
        window.isReleasedWhenClosed = false
        self.init(window: window)
    }

    func show() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - SwiftUI view

private struct PreferencesView: View {

    @ObservedObject var store: PreferencesStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // --- Transcription ---
            GroupBox(label: Label("Transcription", systemImage: "waveform")) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Language")
                        Spacer()
                        Picker("", selection: $store.language) {
                            Text("English").tag("en")
                            Text("Auto-detect").tag("auto")
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 140)
                    }
                    Divider()
                    Toggle("Auto-paste after transcription", isOn: $store.autoPaste)
                    Text("When off, text is placed on the clipboard — paste manually with ⌘V.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(10)
            }

            // --- General ---
            GroupBox(label: Label("General", systemImage: "gearshape")) {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Launch FreeVoice at login", isOn: $store.launchAtLogin)
                    Text("Requires the app to be installed in /Applications.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(10)
            }

            // --- Hotkey reference ---
            GroupBox(label: Label("Hotkey", systemImage: "keyboard")) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Option+/").fontWeight(.medium)
                        Spacer()
                        Text("Activate")
                            .foregroundColor(.secondary)
                    }
                    Divider()
                    HStack {
                        Text("Tap").fontWeight(.medium)
                        Spacer()
                        Text("Toggle mode — press again to stop")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Hold 0.4 s").fontWeight(.medium)
                        Spacer()
                        Text("Push-to-talk — release to stop")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Esc  /  ✕").fontWeight(.medium)
                        Spacer()
                        Text("Cancel without transcribing")
                            .foregroundColor(.secondary)
                    }
                }
                .font(.callout)
                .padding(10)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
