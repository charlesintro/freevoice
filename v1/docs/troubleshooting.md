# Troubleshooting

---

## Quick Diagnostics

Run this first — it checks all dependencies in one go:

```bash
cd ~/Desktop/freevoice
./freevoice.sh check
```

---

## Hotkey Does Nothing

**Hammerspoon doesn't have Input Monitoring permission.**

1. Open System Settings → Privacy & Security → **Input Monitoring**
2. Ensure **Hammerspoon** is listed and toggled **on**.
3. Reload Hammerspoon config (menu bar icon → **Reload Config**).

**Hammerspoon config error.**

1. Click the Hammerspoon menu bar icon → **Open Console**.
2. Look for red error lines.
3. Common mistake: wrong path in `require(...)`. Double-check by running `echo ~/Desktop/freevoice` in Terminal.

**Hotkey conflicts with another app.**

Another app may have claimed the same shortcut. Try a different key combination in `hammerspoon/freevoice.lua`.

---

## Recording Starts But Nothing Gets Pasted

**Accessibility permission is missing.**

1. Open System Settings → Privacy & Security → **Accessibility**
2. Add **Hammerspoon** AND your **terminal app** (if running from Terminal).
3. Ensure both are toggled **on**.
4. Reload Hammerspoon config.

**Whisper hasn't finished yet.**

For longer recordings (30+ seconds), the `medium.en` model can take 10–20 seconds to transcribe. The "Transcribing…" banner will be visible. Wait for it to disappear.

**Nothing was detected in the audio.**

If you recorded in a very noisy environment or spoke very quietly, Whisper may return empty output. Check the clipboard — if it's empty too, nothing was detected. Try speaking more clearly close to the mic.

---

## Error: "whisper-cli not found"

Whisper.cpp isn't installed or isn't on PATH.

```bash
# Re-run the installer:
./install.sh

# Or install manually:
brew install whisper-cpp

# Verify:
which whisper-cli
```

If you built whisper.cpp from source, set the path in `config.local.sh`:
```bash
WHISPER_BIN="/path/to/whisper.cpp/build/bin/whisper-cli"
```

---

## Error: "Model not found"

The model file is missing or at a different path.

```bash
# Re-run the installer to download the model:
./install.sh

# Check where it downloaded to:
ls ~/.freevoice/models/
```

If the model is in a custom location, set it in `config.local.sh`:
```bash
WHISPER_MODEL="/path/to/your/ggml-small.en.bin"
```

---

## Error: "ffmpeg not found"

```bash
brew install ffmpeg
```

---

## Microphone Not Working / No Audio Captured

**Wrong device selected.**

List available devices and find your mic's index:

```bash
./freevoice.sh list-devices
```

Then set it in `config.local.sh`:
```bash
MIC_DEVICE=":1"   # replace with your mic's index
```

**macOS microphone permission denied.**

1. Open System Settings → Privacy & Security → **Microphone**
2. Ensure your terminal app (Terminal or iTerm2) is listed and toggled on.
3. Try recording again — macOS may also prompt automatically.

**ffmpeg can't open the device.**

Run a test recording directly:

```bash
ffmpeg -f avfoundation -i ":default" -ar 16000 -ac 1 -t 3 /tmp/test.wav && echo "Success"
```

If you see an error like `Device or resource busy`, another app may have exclusive access to the mic. Quit other audio apps and try again.

Play back the test to check it captured audio:
```bash
afplay /tmp/test.wav
```

---

## Transcription Is Slow

**Normal for `medium.en` model.** It takes 8–15 s for a 30-second clip on Apple Silicon. Switch to `small.en` for faster results.

**Metal GPU acceleration may not be active.**

Whisper.cpp uses Metal automatically on Apple Silicon when installed via Homebrew. If you built from source, ensure you compiled with Metal support:

```bash
cmake -B build -DGGML_METAL=ON
cmake --build build --config Release
```

**Check that no other heavy process is competing for the GPU.** Close other GPU-intensive apps while dictating.

---

## Transcription Quality Is Poor

**Try the `medium.en` model** for significantly better accuracy, especially for technical vocabulary:

```bash
./install.sh --model medium
```

Then update `config.local.sh`:
```bash
WHISPER_MODEL="$HOME/.freevoice/models/ggml-medium.en.bin"
```

**Speak closer to the mic and reduce background noise.** Whisper is robust but still affected by noisy environments.

**Avoid very short recordings** (under ~1 second). Whisper needs enough audio context to work well.

---

## Pasted Text Has Extra Spaces / Punctuation

Whisper sometimes adds punctuation or capitalises words unexpectedly. This is model behaviour and generally improves with larger models. If it's disruptive, you can post-process the text in `freevoice.sh` by extending the `_run_whisper` cleanup `sed` pipeline.

---

## Mac Mini USB Mic Isn't Being Detected

1. Make sure the mic is plugged in **before** running `list-devices`:

   ```bash
   ./freevoice.sh list-devices
   ```

2. If it still doesn't appear, check System Settings → Sound → Input to confirm macOS sees it.

3. Set the device index in `config.local.sh` and test:

   ```bash
   MIC_DEVICE=":1"
   ```

   ```bash
   ffmpeg -f avfoundation -i ":1" -ar 16000 -ac 1 -t 3 /tmp/test.wav && afplay /tmp/test.wav
   ```

---

## Hammerspoon Alerts Don't Appear

This is cosmetic only — FreeVoice still works. The alerts require macOS notification permission for Hammerspoon:

System Settings → Notifications → **Hammerspoon** → Allow notifications.

---

## Log Files

FreeVoice writes ffmpeg errors to `/tmp/freevoice.log`:

```bash
cat /tmp/freevoice.log
```

Hammerspoon logs are visible in its console:
- Hammerspoon menu bar icon → **Open Console**

---

## Still Stuck?

Open an issue at [github.com/YOUR_USERNAME/freevoice/issues](https://github.com/YOUR_USERNAME/freevoice/issues) with:
- Output of `./freevoice.sh check`
- Output of `cat /tmp/freevoice.log`
- macOS version (`sw_vers`)
- Hammerspoon console output
