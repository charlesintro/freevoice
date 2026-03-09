// =============================================================================
// PreferencesWindowController.swift — SwiftUI preferences window
// =============================================================================

import Cocoa
import SwiftUI

// MARK: - Window controller

final class PreferencesWindowController: NSWindowController {

    convenience init() {
        let view   = PreferencesView(store: PreferencesStore.shared)
        let hosting = NSHostingController(rootView: view)
        let window  = NSWindow(contentViewController: hosting)
        window.title      = "FreeVoice Preferences"
        window.styleMask  = [.titled, .closable]
        window.isReleasedWhenClosed = false   // keep alive for re-open
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
        Form {
            Section {
                Picker("Language", selection: $store.language) {
                    Text("English").tag("en")
                    Text("Auto-detect").tag("auto")
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 220)

                Toggle("Auto-paste after transcription", isOn: $store.autoPaste)
            } header: {
                Text("Transcription")
            }

            Divider()

            Section {
                Toggle("Launch FreeVoice at login", isOn: $store.launchAtLogin)
                    .help("Adds FreeVoice to System Settings → General → Login Items")
            } header: {
                Text("General")
            }

            Divider()

            Section {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "keyboard")
                        .foregroundColor(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hotkey: **Option+/**")
                        Text("Tap → toggle mode  |  Hold 0.4 s → push-to-talk")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Esc or ✕ → cancel recording")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Hotkey")
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 380)
    }
}
