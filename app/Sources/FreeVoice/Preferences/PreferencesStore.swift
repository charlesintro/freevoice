// =============================================================================
// PreferencesStore.swift — UserDefaults wrapper + launch-at-login
// =============================================================================

import Foundation
import CoreGraphics
import ServiceManagement

// MARK: - Hotkey options

/// All supported global hotkeys, mirroring v1 config.sh options.
enum HotkeyOption: String, CaseIterable {
    case optionSlash     = "option_slash"       // Option+/   (default)
    case optionSpace     = "option_space"       // Option+Space
    case ctrlSpace       = "ctrl_space"         // Ctrl+Space
    case ctrlOptionSlash = "ctrl_option_slash"  // Ctrl+Option+/
    case custom          = "custom"             // User-recorded combination

    var displayName: String {
        switch self {
        case .optionSlash:     return "Option+/"
        case .optionSpace:     return "Option+Space"
        case .ctrlSpace:       return "Ctrl+Space"
        case .ctrlOptionSlash: return "Ctrl+Option+/"
        case .custom:          return "Custom"
        }
    }

    /// Carbon key code for the trigger key.
    /// For .custom, HotkeyController reads PreferencesStore.shared.customKeyCode directly.
    var keyCode: CGKeyCode {
        switch self {
        case .optionSlash, .ctrlOptionSlash: return 44  // kVK_Slash
        case .optionSpace, .ctrlSpace:       return 49  // kVK_Space
        case .custom:                        return 0   // unused — see HotkeyController
        }
    }

    /// The exact modifier combination required.
    /// For .custom, HotkeyController reads PreferencesStore.shared.customFlags directly.
    var requiredFlags: CGEventFlags {
        switch self {
        case .optionSlash:     return [.maskAlternate]
        case .optionSpace:     return [.maskAlternate]
        case .ctrlSpace:       return [.maskControl]
        case .ctrlOptionSlash: return [.maskAlternate, .maskControl]
        case .custom:          return []  // unused — see HotkeyController
        }
    }
}

// MARK: - Store

final class PreferencesStore: ObservableObject {

    static let shared = PreferencesStore()

    // MARK: - Preferences

    /// Whisper language code passed to whisper-cli --language.
    @Published var language: String {
        didSet { UserDefaults.standard.set(language, forKey: Keys.language) }
    }

    /// When true, transcribed text is pasted automatically via Cmd+V.
    @Published var autoPaste: Bool {
        didSet { UserDefaults.standard.set(autoPaste, forKey: Keys.autoPaste) }
    }

    /// Active global hotkey — takes effect immediately, no restart needed.
    @Published var hotkey: HotkeyOption {
        didSet { UserDefaults.standard.set(hotkey.rawValue, forKey: Keys.hotkey) }
    }

    /// Whether FreeVoice is registered as a login item (macOS 13+).
    @Published var launchAtLogin: Bool {
        didSet { applyLaunchAtLogin(launchAtLogin) }
    }

    // MARK: - Custom hotkey

    /// Carbon key code for the user-recorded custom hotkey.
    @Published var customKeyCode: CGKeyCode {
        didSet { UserDefaults.standard.set(Int(customKeyCode), forKey: Keys.customKeyCode) }
    }

    /// Modifier flags for the user-recorded custom hotkey.
    @Published var customFlags: CGEventFlags {
        didSet {
            UserDefaults.standard.set(Int(customFlags.rawValue), forKey: Keys.customFlags)
        }
    }

    /// Human-readable display string for the custom hotkey (e.g. "⌃⌥A").
    /// Empty means no custom hotkey has been recorded yet.
    @Published var customDisplayName: String {
        didSet { UserDefaults.standard.set(customDisplayName, forKey: Keys.customDisplayName) }
    }

    // MARK: - Init

    private init() {
        UserDefaults.standard.register(defaults: [
            Keys.language:          "en",
            Keys.autoPaste:         true,
            Keys.hotkey:            HotkeyOption.optionSlash.rawValue,
            Keys.customKeyCode:     0,
            Keys.customFlags:       0,
            Keys.customDisplayName: "",
        ])
        language          = UserDefaults.standard.string(forKey: Keys.language) ?? "en"
        autoPaste         = UserDefaults.standard.bool(forKey: Keys.autoPaste)
        hotkey            = HotkeyOption(rawValue: UserDefaults.standard.string(forKey: Keys.hotkey) ?? "") ?? .optionSlash
        launchAtLogin     = (SMAppService.mainApp.status == .enabled)
        customKeyCode     = CGKeyCode(max(0, UserDefaults.standard.integer(forKey: Keys.customKeyCode)))
        customFlags       = CGEventFlags(rawValue: UInt64(max(0, UserDefaults.standard.integer(forKey: Keys.customFlags))))
        customDisplayName = UserDefaults.standard.string(forKey: Keys.customDisplayName) ?? ""
    }

    // MARK: - Launch at login

    private func applyLaunchAtLogin(_ enable: Bool) {
        do {
            if enable { try SMAppService.mainApp.register() }
            else       { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("[FreeVoice] Launch-at-login toggle failed: %@", error.localizedDescription)
            DispatchQueue.main.async { self.launchAtLogin = (SMAppService.mainApp.status == .enabled) }
        }
    }

    // MARK: - Keys

    private enum Keys {
        static let language          = "language"
        static let autoPaste         = "autoPaste"
        static let hotkey            = "hotkey"
        static let customKeyCode     = "customKeyCode"
        static let customFlags       = "customFlags"
        static let customDisplayName = "customDisplayName"
    }
}
