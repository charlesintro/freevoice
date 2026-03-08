// =============================================================================
// AppDelegate.swift — FreeVoice application delegate
// =============================================================================

import Cocoa

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
    private var statusBarController: StatusBarController?
    private var hotkeyController: HotkeyController?

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController()
        hotkeyController    = HotkeyController()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyController?.stop()
    }
}
