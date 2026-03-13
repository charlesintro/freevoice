// =============================================================================
// WelcomeController.swift — First-run "How to use" onboarding
// =============================================================================
//
// Shows a brief tutorial alert on first launch. Uses NSAlert's built-in
// suppression checkbox so the user can opt out of future showings.
// The suppression state is stored in UserDefaults under "hasSeenWelcome".
// =============================================================================

import Cocoa

enum WelcomeController {

    private static let suppressionKey = "hasSeenWelcome"

    /// Shows the welcome alert if the user hasn't dismissed it permanently.
    /// Call from `applicationDidFinishLaunching` after all controllers are set up.
    static func showIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: suppressionKey) else { return }

        let alert = NSAlert()
        alert.messageText     = "Welcome to FreeVoice"
        alert.informativeText = """
            Press Option+/ anywhere to start dictating.

            • Tap quickly → toggle mode (press again to stop)
            • Hold → push-to-talk (release to stop)
            • Press Esc to cancel without transcribing

            Your words are typed automatically wherever your cursor is.
            Change the hotkey or microphone from the  menu bar icon.
            """
        alert.addButton(withTitle: "Got it")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't show this again"

        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()

        if alert.suppressionButton?.state == .on {
            UserDefaults.standard.set(true, forKey: suppressionKey)
        }
    }
}
