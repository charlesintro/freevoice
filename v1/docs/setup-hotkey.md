# Hotkey Setup Guide

FreeVoice uses **Hammerspoon** to register a system-wide keyboard shortcut that works in any app. This guide walks you through the complete setup.

---

## Why Hammerspoon?

Push-to-talk requires detecting both when a key is **pressed** (start recording) and when it's **released** (stop and transcribe). Most macOS hotkey methods only detect key presses, not releases. Hammerspoon handles both, making it the right tool for the job.

Hammerspoon is free, open-source, and widely used by macOS power users. It runs in the background and uses very little CPU/memory.

---

## Step 1 — Open Hammerspoon

After running `install.sh`, Hammerspoon is installed. Open it:

- Press **Cmd + Space**, type `Hammerspoon`, press Enter.

You'll see a small icon appear in your **menu bar** (top-right of the screen).

If macOS asks for permissions, click **Open System Settings** and grant them (more details in Step 3).

---

## Step 2 — Edit the Hammerspoon Config

1. Click the **Hammerspoon icon** in the menu bar.
2. Click **Open Config**.

   This opens the file `~/.hammerspoon/init.lua` in your default text editor.

3. Add this line to the file (replace `YOUR_NAME` with your username — run `whoami` in Terminal if unsure):

   ```lua
   require("/Users/YOUR_NAME/Desktop/freevoice/hammerspoon/freevoice")
   ```

   **Example** (if your username is `charlie`):
   ```lua
   require("/Users/charlie/Desktop/freevoice/hammerspoon/freevoice")
   ```

4. Save the file.

---

## Step 3 — Reload Hammerspoon

1. Click the **Hammerspoon icon** in the menu bar.
2. Click **Reload Config**.

   The console may briefly flash open. This is normal.

If you see a notification saying FreeVoice loaded successfully, you're done. If you see an error, check Step 4.

---

## Step 4 — Grant macOS Permissions

macOS requires explicit permission for Hammerspoon to:
- Monitor global keypresses (**Input Monitoring**)
- Control other apps for pasting (**Accessibility**)

### Input Monitoring (required for the hotkey to work)

1. Open **System Settings** → **Privacy & Security** → **Input Monitoring**
2. Click the **+** button (you may need to unlock with your password).
3. Add **Hammerspoon** (usually in `/Applications/Hammerspoon.app`).
4. Make sure the toggle next to Hammerspoon is **on**.

### Accessibility (required for auto-paste)

1. Open **System Settings** → **Privacy & Security** → **Accessibility**
2. Add both:
   - **Hammerspoon** (`/Applications/Hammerspoon.app`)
   - Your **terminal app** (Terminal or iTerm2) — needed if you use FreeVoice from the command line

After granting permissions, reload Hammerspoon config again (menu bar icon → **Reload Config**).

---

## Step 5 — Test It

1. Click somewhere in a text field (Notes app, browser search bar, etc.).
2. Hold **Ctrl + Shift + Space** and say something.
3. Release the keys.
4. After 2–5 seconds, your words should appear in the text field.

You should also see a small on-screen banner:
- **"Recording…"** while you hold the key
- **"Transcribing…"** while Whisper processes the audio
- **"Done"** when the text is pasted

---

## Changing the Hotkey

The default hotkey is **Ctrl + Shift + Space**. To change it:

1. Open `hammerspoon/freevoice.lua` in a text editor.
2. Find these lines near the top:

   ```lua
   local HOTKEY_MODS = {"ctrl", "shift"}
   local HOTKEY_KEY  = "space"
   ```

3. Change them to your preferred shortcut. Examples:

   ```lua
   -- F13 key (if you remap Caps Lock with Karabiner-Elements)
   local HOTKEY_MODS = {}
   local HOTKEY_KEY  = "f13"

   -- Right Option key (if remapped with Karabiner)
   local HOTKEY_MODS = {}
   local HOTKEY_KEY  = "rightalt"

   -- Command + Shift + D
   local HOTKEY_MODS = {"cmd", "shift"}
   local HOTKEY_KEY  = "d"
   ```

4. Save, then reload Hammerspoon (menu bar → **Reload Config**).

### Tip: Remap Caps Lock to Push-to-Talk

Many users remap Caps Lock to a dedicated push-to-talk key using [Karabiner-Elements](https://karabiner-elements.pqrs.org/) (free):

- Remap Caps Lock → F13 (a key that no app uses)
- Set `HOTKEY_KEY = "f13"` in `freevoice.lua`
- Now Caps Lock becomes your dictation key

---

## How to Disable FreeVoice Temporarily

- Click the **Hammerspoon menu bar icon** → **Reload Config** → the hotkey is re-registered.
- To fully disable: right-click the Hammerspoon menu bar icon → **Quit** (or `killall Hammerspoon` in Terminal).
- To disable just the FreeVoice hotkey: comment out the `require(...)` line in `~/.hammerspoon/init.lua` and reload config.

---

## Hammerspoon Doesn't Start on Login?

1. Open Hammerspoon.
2. Click the menu bar icon → **Preferences**.
3. Check **Launch Hammerspoon at login**.
