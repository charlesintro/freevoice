// =============================================================================
// PreferencesStore.swift — UserDefaults wrapper + launch-at-login
// =============================================================================

import Foundation
import ServiceManagement

final class PreferencesStore: ObservableObject {

    static let shared = PreferencesStore()

    // MARK: - Preferences

    /// Whisper language code passed to whisper-cli --language. "en" or "auto".
    @Published var language: String {
        didSet { UserDefaults.standard.set(language, forKey: Keys.language) }
    }

    /// When true, transcribed text is pasted automatically via Cmd+V.
    /// When false, text is placed on the clipboard only.
    @Published var autoPaste: Bool {
        didSet { UserDefaults.standard.set(autoPaste, forKey: Keys.autoPaste) }
    }

    /// Whether FreeVoice is registered as a login item (macOS 13+).
    @Published var launchAtLogin: Bool {
        didSet { applyLaunchAtLogin(launchAtLogin) }
    }

    // MARK: - Init

    private init() {
        UserDefaults.standard.register(defaults: [
            Keys.language:  "en",
            Keys.autoPaste: true,
        ])
        language     = UserDefaults.standard.string(forKey: Keys.language) ?? "en"
        autoPaste    = UserDefaults.standard.bool(forKey: Keys.autoPaste)
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }

    // MARK: - Launch at login

    private func applyLaunchAtLogin(_ enable: Bool) {
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Falls back to false during dev (app must be in /Applications)
            NSLog("[FreeVoice] Launch-at-login toggle failed: %@", error.localizedDescription)
            // Revert the published value without re-triggering didSet
            DispatchQueue.main.async { self.launchAtLogin = (SMAppService.mainApp.status == .enabled) }
        }
    }

    // MARK: - Keys

    private enum Keys {
        static let language  = "language"
        static let autoPaste = "autoPaste"
    }
}
