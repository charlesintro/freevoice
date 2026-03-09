// =============================================================================
// HotkeyController.swift — Global hotkey + PTT/Toggle state machine
// =============================================================================
//
// Listens for Option+/ via CGEventTap (session-level, works in any focused app).
//
// State machine (mirrors v1 Lua exactly):
//
//   IDLE
//    ↓ keyDown
//   TAP_PENDING ── (0.4 s timer fires, no keyUp yet) ──→ PTT   (start recording)
//               ── keyUp before 0.4 s ─────────────────→ TOGGLE (start recording)
//
//   PTT    ── keyUp ─────────────────────────────────→ TRANSCRIBING
//          ── Esc ──────────────────────────────────→ IDLE (discard)
//          ── 11-min timer ─────────────────────────→ TRANSCRIBING
//          (10-min timer → amber warning, handled by IndicatorWindowController in Phase 3)
//
//   TOGGLE ── keyDown ────────────────────────────────→ TRANSCRIBING
//          ── Esc ────────────────────────────────────→ IDLE (discard)
//          ── 11-min timer ───────────────────────────→ TRANSCRIBING
//
//   TRANSCRIBING ── whisper done ────────────────────→ IDLE
//
// Requires Accessibility permission (same as Phase 1).
// =============================================================================

import Cocoa
import ApplicationServices

// Carbon key code for forward-slash. Stable across all layouts.
private let kVK_Slash:  CGKeyCode = 44
private let kVK_Escape: CGKeyCode = 53

private let holdThreshold    = 0.4    // seconds: tap vs PTT decision
private let warnSeconds      = 600.0  // 10 min: trigger amber (Phase 3)
private let maxSeconds       = 660.0  // 11 min: auto-stop

// MARK: - State

private enum RecordingState {
    case idle
    case tapPending     // keyDown received, waiting for tap vs PTT decision
    case ptt            // push-to-talk: recording until key released
    case toggle         // toggle mode: recording until second keyDown
    case transcribing
}

// MARK: - Controller

final class HotkeyController {

    // Injected controllers
    private let recording    = RecordingController()
    private let transcription = TranscriptionController()
    private let paste        = PasteController()
    private let store        = TranscriptStore()

    // CGEventTap
    private var eventTap:     CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // State machine
    private var state: RecordingState = .idle

    // Timers (all fire on main queue)
    private var holdTimer: DispatchWorkItem?   // 0.4 s tap-vs-PTT
    private var warnTimer: DispatchWorkItem?   // 10 min amber warning
    private var maxTimer:  DispatchWorkItem?   // 11 min auto-stop

    // Notification to StatusBarController that a transcript is ready.
    // Posted on main queue with userInfo["text"]: String.
    static let transcriptReadyNotification = Notification.Name("FreeVoiceTranscriptReady")

    // MARK: - Lifecycle

    init() { start() }
    deinit { stop() }

    func start() {
        guard eventTap == nil else { return }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)   |
            (1 << CGEventType.tapDisabledByTimeout.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { (_, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passRetained(event) }
                let ctrl = Unmanaged<HotkeyController>.fromOpaque(refcon).takeUnretainedValue()
                return ctrl.handleEvent(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let tap = eventTap else {
            NSLog("[FreeVoice] CGEventTap failed — Accessibility permission not granted.")
            requestAccessibilityPermission()
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("[FreeVoice] Hotkey listener active (Option+/).")
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .commonModes) }
        eventTap      = nil
        runLoopSource = nil
    }

    // MARK: - CGEventTap callback

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout, let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
            return nil
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags   = event.flags.intersection([.maskAlternate, .maskCommand, .maskControl, .maskShift])

        // --- Esc cancels recording (any state, no modifier required) ---
        if keyCode == kVK_Escape, type == .keyDown {
            if state == .ptt || state == .toggle {
                DispatchQueue.main.async { self.cancelRecording() }
                return nil   // consume Esc
            }
            return Unmanaged.passRetained(event)
        }

        // --- Option+/ only ---
        guard keyCode == kVK_Slash, flags == .maskAlternate else {
            return Unmanaged.passRetained(event)
        }

        switch (state, type) {

        case (.idle, .keyDown):
            DispatchQueue.main.async { self.beginTapPending() }
            return nil

        case (.tapPending, .keyUp):
            // Released before hold threshold → Toggle mode
            DispatchQueue.main.async { self.transitionToToggle() }
            return nil

        case (.toggle, .keyDown):
            // Second press → stop toggle recording
            DispatchQueue.main.async { self.stopAndTranscribe() }
            return nil

        case (.ptt, .keyUp):
            DispatchQueue.main.async { self.stopAndTranscribe() }
            return nil

        default:
            break
        }

        return Unmanaged.passRetained(event)
    }

    // MARK: - State transitions (always on main queue)

    private func beginTapPending() {
        state = .tapPending
        NSLog("[FreeVoice] State → TAP_PENDING")

        let item = DispatchWorkItem { [weak self] in
            guard let self, self.state == .tapPending else { return }
            self.transitionToPTT()
        }
        holdTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + holdThreshold, execute: item)
    }

    private func transitionToPTT() {
        cancelTimers()
        state = .ptt
        NSLog("[FreeVoice] State → PTT (push-to-talk)")
        startRecordingWithTimers()
    }

    private func transitionToToggle() {
        cancelTimers()
        state = .toggle
        NSLog("[FreeVoice] State → TOGGLE")
        startRecordingWithTimers()
    }

    private func stopAndTranscribe() {
        cancelTimers()
        state = .transcribing
        NSLog("[FreeVoice] State → TRANSCRIBING")

        guard let fileURL = recording.stopRecording() else {
            NSLog("[FreeVoice] No recording to transcribe.")
            state = .idle
            return
        }

        transcription.transcribe(url: fileURL) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let text):
                NSLog("[FreeVoice] Transcript: %@", text)
                self.store.save(text)
                self.paste.paste(text)
                NotificationCenter.default.post(
                    name: HotkeyController.transcriptReadyNotification,
                    object: nil,
                    userInfo: ["text": text]
                )
            case .failure(let msg):
                NSLog("[FreeVoice] Transcription failed: %@", msg)
                self.showError(msg)
            }
            self.state = .idle
            NSLog("[FreeVoice] State → IDLE")
        }
    }

    private func cancelRecording() {
        cancelTimers()
        recording.discardRecording()
        state = .idle
        NSLog("[FreeVoice] Recording cancelled → IDLE")
    }

    // MARK: - Recording helpers

    private func startRecordingWithTimers() {
        recording.startRecording { [weak self] started in
            guard let self else { return }
            guard started else {
                self.state = .idle
                self.showError("Microphone access denied. Grant in System Settings → Privacy → Microphone.")
                return
            }
            self.armWarnTimer()
            self.armMaxTimer()
        }
    }

    private func armWarnTimer() {
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.recording.isRecording else { return }
            NSLog("[FreeVoice] 10-min warning (Phase 3 will show amber indicator).")
            // Phase 3: notify IndicatorWindowController to turn amber.
        }
        warnTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + warnSeconds, execute: item)
    }

    private func armMaxTimer() {
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.recording.isRecording else { return }
            NSLog("[FreeVoice] 11-min limit reached — auto-stopping.")
            self.stopAndTranscribe()
        }
        maxTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + maxSeconds, execute: item)
    }

    private func cancelTimers() {
        holdTimer?.cancel(); holdTimer = nil
        warnTimer?.cancel(); warnTimer = nil
        maxTimer?.cancel();  maxTimer  = nil
    }

    // MARK: - Error display

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle      = .warning
        alert.messageText     = "FreeVoice"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - Accessibility guidance

    private func requestAccessibilityPermission() {
        DispatchQueue.main.async {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            let trusted = AXIsProcessTrustedWithOptions(opts as CFDictionary)
            if trusted { self.start() }
        }
    }
}
