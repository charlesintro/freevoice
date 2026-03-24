// =============================================================================
// AppDelegate.swift — FreeVoice application delegate
// =============================================================================

import Cocoa
import Sparkle

/// Top-level application lifecycle handler.
///
/// Owns the two long-lived controllers:
///   - `StatusBarController`  — the menu bar icon + menu
///   - `HotkeyController`     — the global Option+/ keyboard listener
///
/// No window is ever shown at launch; FreeVoice is entirely menu-bar based
/// (LSUIElement = YES in Info.plist).
final class AppDelegate: NSObject, NSApplicationDelegate {

    // Strong references — must live for the app's lifetime.
    private var statusBarController:   StatusBarController?
    private var hotkeyController:      HotkeyController?
    private var indicatorController:   IndicatorWindowController?
    private var preferencesController: PreferencesWindowController?

    // Sparkle auto-updater
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = PreferencesStore.shared   // warm up singleton + register UserDefaults defaults

        // Start downloading / loading the WhisperKit model in the background
        // so it's ready by the time the user first presses the hotkey.
        TranscriptionController.shared.prepare()

        let sb = StatusBarController()
        sb.onOpenPreferences = { [weak self] in self?.openPreferences() }
        sb.updater = updaterController.updater
        statusBarController  = sb
        indicatorController  = IndicatorWindowController()
        hotkeyController     = HotkeyController()

        WelcomeController.showIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyController?.stop()
    }

    private func openPreferences() {
        if preferencesController == nil {
            preferencesController = PreferencesWindowController()
        }
        preferencesController?.show()
    }
}
