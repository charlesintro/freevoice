// =============================================================================
// main.swift — FreeVoice application entry point
// =============================================================================
// Using an explicit main.swift (instead of @main on AppDelegate) gives us
// direct control over the NSApplication lifecycle before run() is called.
// =============================================================================

import Cocoa

// Initialise the shared application singleton.
// NSApp is nil until this call; accessing .shared creates it.
let app = NSApplication.shared

// Belt-and-suspenders: LSUIElement=YES in Info.plist already suppresses the
// Dock icon, but explicitly setting .accessory here prevents any brief flash
// and makes the policy clear to future readers.
app.setActivationPolicy(.accessory)

let delegate = AppDelegate()
app.delegate = delegate

app.run()
