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
                    MicrophonePickerRow(store: store)
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

            // --- Hotkey ---
            GroupBox(label: Label("Hotkey", systemImage: "keyboard")) {
                VStack(alignment: .leading, spacing: 10) {

                    // Hotkey picker
                    HStack {
                        Text("Hotkey")
                        Spacer()
                        Picker("", selection: $store.hotkey) {
                            ForEach(HotkeyOption.allCases, id: \.self) { option in
                                Text(option.displayName).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 180)
                    }

                    // Key recorder — only shown when Custom is selected
                    if store.hotkey == .custom {
                        HStack {
                            Text("Shortcut")
                            Spacer()
                            KeyRecorderView(
                                keyCode:     $store.customKeyCode,
                                flags:       $store.customFlags,
                                displayName: $store.customDisplayName
                            )
                            .frame(width: 160, height: 26)
                        }
                        Text("Click the field above, then press your key combination.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    // Reference guide (no longer hardcodes the hotkey name)
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

// MARK: - Microphone picker row

private struct MicrophonePickerRow: View {

    @ObservedObject var store: PreferencesStore

    // Populated once on appear; refreshed if the user clicks the picker.
    @State private var devices: [AudioDeviceHelper.InputDevice] = []

    var body: some View {
        HStack {
            Text("Microphone")
            Spacer()
            Picker("", selection: $store.inputDeviceUID) {
                Text("System Default").tag("")
                if !devices.isEmpty {
                    Divider()
                    ForEach(devices, id: \.uid) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 180)
            .onAppear { devices = AudioDeviceHelper.listInputDevices() }
        }
    }
}
