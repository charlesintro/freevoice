# FreeVoice

**Local, offline push-to-talk dictation for macOS.**

Hold a keyboard shortcut → speak → release → your words appear in whatever app is active.

No internet connection. No API keys. No subscription. Everything runs on your Mac.

---

## How It Works

Press a keyboard shortcut (default: **Ctrl + Shift + Space**) to start dictating. Two modes, chosen automatically:

| Mode | How to use | When to use |
|---|---|---|
| **Push-to-talk** | Hold the key while speaking, release when done | Short bursts |
| **Toggle** | Tap once to start, tap again to stop | Longer dictation |

After you stop, FreeVoice transcribes locally using [Whisper](https://github.com/ggerganov/whisper.cpp) and pastes the text into whatever app is active.

A small **🎙 FV** icon in your menu bar gives you one-click access to recent transcripts, settings, and quit.

Works in any app: browsers, notes apps, editors, messaging apps, terminals — anywhere you can type.

---

## Requirements

- **macOS 13 (Ventura) or later**
- **Apple Silicon Mac** (M1, M2, M3, M4 — Metal GPU acceleration is used automatically)
- Internet connection for the one-time install only

> **Intel Macs**: Should work but will be significantly slower since Metal acceleration isn't available. Not officially tested.

---

## Installation

### Step 1 — Clone the repo

Open Terminal and run:

```bash
git clone https://github.com/YOUR_USERNAME/freevoice.git ~/Desktop/freevoice
cd ~/Desktop/freevoice
```

### Step 2 — Run the installer

```bash
./install.sh
```

This will:
- Install [ffmpeg](https://ffmpeg.org/) (audio recording)
- Install [whisper.cpp](https://github.com/ggerganov/whisper.cpp) (local transcription)
- Install [Hammerspoon](https://www.hammerspoon.org/) (system-wide hotkey)
- Download the `small.en` Whisper model (~150 MB, saved to `~/.freevoice/models/`)

To use the larger, more accurate `medium.en` model instead:

```bash
./install.sh --model medium
```

---

## Grant macOS Permissions

macOS will ask for these the first time. You can also grant them in advance:

| Permission | Where to grant | What it's for |
|---|---|---|
| **Microphone** | System Settings → Privacy & Security → Microphone | Recording your voice |
| **Accessibility** | System Settings → Privacy & Security → Accessibility | Pasting text into apps |
| **Input Monitoring** | System Settings → Privacy & Security → Input Monitoring | Global hotkey detection |

For **Accessibility** and **Input Monitoring**: add both your **terminal app** (Terminal or iTerm2) and **Hammerspoon**.

---

## Set Up the Hotkey

See **[docs/setup-hotkey.md](docs/setup-hotkey.md)** for step-by-step screenshots.

**Quick version:**

1. Open Hammerspoon (it appears in your menu bar after install).
2. Click the Hammerspoon icon → **Open Config**.
3. Add this line to `~/.hammerspoon/init.lua`:

   ```lua
   require("/Users/YOUR_NAME/Desktop/freevoice/hammerspoon/freevoice")
   ```

   Replace `YOUR_NAME` with your macOS username (run `whoami` in Terminal if unsure).

4. Save the file, then click the Hammerspoon icon → **Reload Config**.

That's it. Hold **Ctrl + Shift + Space** and speak.

---

## External USB Mic

If you plug in a USB microphone and set it as the default in **System Settings → Sound → Input**, FreeVoice picks it up automatically — no config change needed.

If you want to target a specific mic *without* changing the system default, click **🎙 FV** in the menu bar → **List Audio Devices**, find the index number of your mic, then set `MIC_DEVICE=":1"` (or whichever index) in `config.local.sh`.

---

## Configuration

Copy `config.local.sh.example` → `config.local.sh` to customise settings. This file is gitignored and won't be overwritten by updates.

| Setting | Default | Description |
|---|---|---|
| `MIC_DEVICE` | `:default` | Audio input device. Use `list-devices` to find index |
| `WHISPER_MODEL` | `~/.freevoice/models/ggml-small.en.bin` | Path to the Whisper model |
| `WHISPER_LANGUAGE` | `en` | Transcription language |
| `AUTO_PASTE` | `true` | Paste automatically, or clipboard only |
| `APPEND_TRAILING_SPACE` | `true` | Add a space after pasted text |
| `SHOW_NOTIFICATIONS` | `true` | macOS banner notifications |

---

## Changing the Hotkey

Edit `hammerspoon/freevoice.lua` and change these two lines:

```lua
local HOTKEY_MODS = {"ctrl", "shift"}
local HOTKEY_KEY  = "space"
```

Common alternatives:

```lua
-- Caps Lock remapped to F13 (requires Karabiner-Elements)
local HOTKEY_MODS = {}
local HOTKEY_KEY  = "f13"

-- Command + Shift + Space
local HOTKEY_MODS = {"cmd", "shift"}
local HOTKEY_KEY  = "space"
```

After editing, reload Hammerspoon (menu bar icon → **Reload Config**).

---

## Model Comparison

| Model | Size | Latency (Apple Silicon) | Accuracy |
|---|---|---|---|
| `base.en` | ~75 MB | ~1–2 s | Lower |
| **`small.en`** | **~150 MB** | **~2–5 s** | **Good** ← default |
| `medium.en` | ~470 MB | ~8–15 s | Higher |

To switch models, edit `WHISPER_MODEL` in `config.local.sh` and re-run `install.sh --model medium` (or `base`) to download the model file.

---

## Verify Your Setup

```bash
./freevoice.sh check
```

---

## Manual Usage

You can also run FreeVoice directly from Terminal without a hotkey:

```bash
# Start recording (runs until you call stop)
./freevoice.sh start

# Stop, transcribe, and paste
./freevoice.sh stop

# Transcribe the last recording again (without pasting)
./freevoice.sh transcribe

# Check if recording is in progress
./freevoice.sh status
```

---

## Troubleshooting

See **[docs/troubleshooting.md](docs/troubleshooting.md)** for common issues and fixes.

---

## Project Structure

```
freevoice/
├── README.md                     This file
├── install.sh                    One-shot installer
├── freevoice.sh                  Core script: record → transcribe → paste
├── config.sh                     Default settings (tracked by git)
├── config.local.sh.example       Template for personal overrides
├── config.local.sh               Your personal settings (gitignored)
├── hammerspoon/
│   └── freevoice.lua             Hammerspoon push-to-talk hotkey config
├── docs/
│   ├── setup-hotkey.md           Detailed hotkey setup guide
│   └── troubleshooting.md        Common issues and fixes
└── .gitignore
```

---

## Privacy

- All processing happens on your Mac. No audio ever leaves your device.
- No telemetry, no analytics, no network calls during use.
- Temporary audio files are saved to `/tmp/` and overwritten on the next recording.

---

## License

MIT — see [LICENSE](LICENSE) for details.
