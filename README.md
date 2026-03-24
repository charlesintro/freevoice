# FreeVoice

**Local, offline push-to-talk dictation for macOS.**

Press a hotkey, speak, press again — your words appear in whatever app is active. No internet. No API keys. No subscription. Runs entirely on your Mac using Apple's Neural Engine.

---

## Download

**[FreeVoice for macOS →](https://github.com/charlesintro/freevoice/releases/latest)**

Requires macOS 13 (Ventura) or later, Apple Silicon.

---

## How It Works

Press **Option + /** to start recording. Two modes, chosen automatically:

| Mode | How | When |
|---|---|---|
| **Toggle** | Tap once to start, tap again to stop | Longer dictation |
| **Push-to-talk** | Hold the key, release when done | Quick bursts |

FreeVoice transcribes locally using [WhisperKit](https://github.com/argmaxinc/WhisperKit) (tiny.en model, bundled in the app) and pastes the text into whatever app is active.

---

## Permissions

macOS will prompt for these on first launch:

| Permission | What it's for |
|---|---|
| **Microphone** | Recording your voice |
| **Accessibility** | Pasting text into the active app |
| **Input Monitoring** | Detecting the global hotkey |

---

## Features

- Works in any app — browsers, notes, editors, terminals, anywhere you can type
- Floating braille-wave indicator shows recording and transcribing state
- Microphone picker in the menu bar (pick a specific mic without changing system default)
- Customisable hotkey (Option+/, Fn, or a custom combo)
- Auto-paste or clipboard-only mode
- Recent transcripts in the menu bar
- Seamless audio device switching (AirPods, USB mics)
- Auto-updates via Sparkle

---

## Building from Source

### Requirements

- macOS 13+
- Xcode 15+
- [xcodegen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

### Steps

```bash
git clone https://github.com/charlesintro/freevoice.git
cd freevoice/app
xcodegen generate
open FreeVoice.xcodeproj
```

Then in Xcode: set your Development Team under **FreeVoice target → Signing & Capabilities → Team**, and hit **▶**.

> The WhisperKit tiny.en model (75MB) is bundled in `app/Models/`. No download needed at runtime.

---

## Project Structure

```
freevoice/
├── app/                          Swift app (current, v1.2+)
│   ├── project.yml               xcodegen project spec
│   ├── Models/                   Bundled WhisperKit model (tiny.en)
│   └── Sources/FreeVoice/
│       ├── AppDelegate.swift
│       ├── Hotkey/               CGEventTap state machine
│       ├── Recording/            AVAudioEngine recorder
│       ├── Transcription/        WhisperKit actor
│       ├── Indicator/            Floating braille indicator
│       ├── StatusBar/            Menu bar icon + menu
│       └── Preferences/          Settings store + window
├── v1/                           Legacy shell script version (archived)
│   ├── freevoice.sh
│   ├── hammerspoon/
│   └── docs/
└── RELEASING.md                  Release process and Sparkle setup
```

---

## Privacy

- All processing happens on your Mac. No audio leaves your device.
- No telemetry, analytics, or network calls during use.
- Temporary audio files are saved to `/tmp/` and overwritten each recording.
- Network permission is present only for Sparkle update checks (optional).

---

## License

MIT — see [LICENSE](LICENSE) for details.
