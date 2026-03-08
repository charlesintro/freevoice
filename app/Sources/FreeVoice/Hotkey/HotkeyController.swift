// =============================================================================
// HotkeyController.swift — Global hotkey listener via CGEventTap
// =============================================================================
//
// Phase 1: Validates that CGEventTap works and fires an NSAlert on Option+/.
// Phase 2: Replace `onHotkey()` with the full PTT/toggle recording state machine.
//
// Requires Accessibility permission:
//   System Settings → Privacy & Security → Accessibility → FreeVoice ✓
// macOS will NOT prompt automatically — we guide the user via an alert if
// CGEventTapCreate fails.
// =============================================================================

import Cocoa
import ApplicationServices

// Carbon key code for the forward-slash key (/). This value is stable across
// all macOS versions and keyboard layouts.
private let kVK_Slash: CGKeyCode = 44

/// Registers a CGEventTap session-level listener for the global Option+/ hotkey.
///
/// - Important: The tap runs on the calling thread's run loop.  Dispatch any
///   UI work to `DispatchQueue.main`.
final class HotkeyController {

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // MARK: - Lifecycle

    init() {
        start()
    }

    deinit {
        stop()
    }

    /// Installs the CGEventTap and adds it to the current run loop.
    func start() {
        guard eventTap == nil else { return }

        // Listen for both keyDown (to act on the hotkey) and keyUp (needed in
        // Phase 2 for PTT mode, where we release on key-up).  Listening for
        // tapDisabledByTimeout lets us re-enable the tap if macOS disables it.
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)   |
            (1 << CGEventType.tapDisabledByTimeout.rawValue)

        // Use a C closure as the tap callback.  We pass `self` as the `userInfo`
        // pointer so the closure can forward events to `handleEvent`.
        eventTap = CGEventTapCreate(
            .cgSessionEventTap,   // intercepts events across the entire login session
            .headInsertEventTap,  // insert before other taps
            .defaultTap,
            mask,
            { (_, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passRetained(event) }
                let controller = Unmanaged<HotkeyController>
                    .fromOpaque(refcon)
                    .takeUnretainedValue()
                return controller.handleEvent(type: type, event: event)
            },
            Unmanaged.passUnretained(self).toOpaque()
        )

        guard let tap = eventTap else {
            NSLog("[FreeVoice] CGEventTapCreate failed — Accessibility permission not granted.")
            requestAccessibilityPermission()
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEventTapEnable(tap, true)
        NSLog("[FreeVoice] Hotkey listener active (Option+/)")
    }

    /// Removes the CGEventTap from the run loop and releases resources.
    func stop() {
        if let tap = eventTap {
            CGEventTapEnable(tap, false)
        }
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .commonModes)
        }
        eventTap      = nil
        runLoopSource = nil
    }

    // MARK: - Event handling

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {

        // Re-enable the tap if macOS automatically disabled it (happens when the
        // tap blocks events for too long — unlikely here but defensive).
        if type == .tapDisabledByTimeout, let tap = eventTap {
            CGEventTapEnable(tap, true)
            return nil
        }

        // Only care about keyDown for now (keyUp used in Phase 2 PTT).
        guard type == .keyDown else { return Unmanaged.passRetained(event) }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        // Normalise modifier flags to only the four meaningful ones so extra
        // bits (e.g. NumLock) don't prevent matching.
        let flags = event.flags.intersection([
            .maskAlternate,  // Option
            .maskCommand,    // Cmd
            .maskControl,    // Ctrl
            .maskShift       // Shift
        ])

        // Hotkey: Option+/ with no other modifiers.
        guard keyCode == kVK_Slash, flags == .maskAlternate else {
            return Unmanaged.passRetained(event)   // pass through unchanged
        }

        DispatchQueue.main.async { self.onHotkey() }
        return nil   // consume — don't pass "/" to the focused app
    }

    // MARK: - Hotkey action

    /// Called on the main queue whenever the user presses Option+/.
    ///
    /// Phase 1: Shows a confirmation alert so we can validate the whole path
    /// (CGEventTap → main queue → window) without any recording logic.
    ///
    /// Phase 2: This becomes the entry point for the PTT/toggle state machine.
    private func onHotkey() {
        let alert = NSAlert()
        alert.messageText     = "FreeVoice — hotkey works!"
        alert.informativeText = "Option+/ received. Recording will start here in Phase 2."
        alert.alertStyle      = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - Accessibility guidance

    /// Asks macOS to show the Accessibility permission sheet.
    ///
    /// `kAXTrustedCheckOptionPrompt: true` causes the system to open
    /// System Settings → Privacy & Security → Accessibility automatically,
    /// which is friendlier than asking the user to navigate there manually.
    private func requestAccessibilityPermission() {
        DispatchQueue.main.async {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            let trusted = AXIsProcessTrustedWithOptions(opts as CFDictionary)
            if trusted {
                // Shouldn't reach here (we only call this when the tap failed),
                // but if we somehow already have permission, just restart.
                self.start()
            }
            // If not trusted, the system has shown the Settings sheet.
            // The user needs to enable FreeVoice there and relaunch the app.
        }
    }
}
