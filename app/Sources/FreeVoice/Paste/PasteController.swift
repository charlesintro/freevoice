// =============================================================================
// PasteController.swift — Clipboard write + Cmd+V via CGEventPost
// =============================================================================
//
// Step 1: Write text to NSPasteboard.
// Step 2: Synthesize Cmd+V keystrokes via CGEvent so the focused app receives it.
//
// Reuses the Accessibility permission already granted for the CGEventTap.
// If CGEvent posting fails for any reason, the text is still on the clipboard
// so the user can paste manually.
//
// Call from the main queue.
// =============================================================================

import Cocoa
import ApplicationServices

private let kVK_V: CGKeyCode = 0x09

final class PasteController {

    func paste(_ text: String) {
        // 1. Write to clipboard.
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        // 2. Post Cmd+V to whatever app currently has focus.
        //    We use cghidEventTap so the event goes through the normal HID path.
        guard let src = CGEventSource(stateID: .hidSystemState) else {
            NSLog("[FreeVoice] PasteController: CGEventSource unavailable — text is on clipboard.")
            return
        }

        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: kVK_V, keyDown: true)
        let keyUp   = CGEvent(keyboardEventSource: src, virtualKey: kVK_V, keyDown: false)

        keyDown?.flags = .maskCommand
        keyUp?.flags   = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        NSLog("[FreeVoice] Pasted %d characters.", text.count)
    }
}
