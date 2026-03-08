#!/usr/bin/env bash
# =============================================================================
# freevoice.sh — Local, offline push-to-talk dictation for macOS
# =============================================================================
# Records microphone audio, transcribes it via whisper.cpp, and pastes
# the result into whatever app is currently active.
#
# 100% offline — no API calls, no cloud services.
# Requires: ffmpeg, whisper-cli (whisper.cpp), macOS 13+, Apple Silicon.
#
# Usage:
#   freevoice.sh start          Begin recording
#   freevoice.sh stop           Stop recording, transcribe, and paste
#   freevoice.sh transcribe     (Re-)transcribe last recording without pasting
#   freevoice.sh status         Print whether recording is in progress
#   freevoice.sh list-devices   List available audio input devices
#   freevoice.sh check          Verify all dependencies are present
#
# Typically invoked by the Hammerspoon hotkey (hammerspoon/freevoice.lua),
# not called manually. See README.md for setup instructions.
# =============================================================================

set -euo pipefail

# Ensure Homebrew binaries are on PATH when called from Hammerspoon,
# which launches scripts outside of a login shell environment.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# ---------------------------------------------------------------------------
# Resolve script directory and load config
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=config.sh
source "$SCRIPT_DIR/config.sh"

# Load user overrides if they exist (gitignored, never overwrites on update)
if [[ -f "$SCRIPT_DIR/config.local.sh" ]]; then
  # shellcheck source=config.local.sh.example
  source "$SCRIPT_DIR/config.local.sh"
fi

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

RECORDING_FILE="$FREEVOICE_TMPDIR/freevoice_recording.wav"
PID_FILE="$FREEVOICE_TMPDIR/freevoice.pid"
LOG_FILE="$FREEVOICE_TMPDIR/freevoice.log"

# Transcript persistence — used by the menu bar to offer "Copy Last Transcript".
FREEVOICE_DATA_DIR="$HOME/.freevoice"
LAST_TRANSCRIPT_FILE="$FREEVOICE_DATA_DIR/last_transcript.txt"
TRANSCRIPT_LOG="$FREEVOICE_DATA_DIR/transcripts.log"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log() {
  echo "[freevoice] $*" >&2
}

notify() {
  # Show a macOS banner notification (non-blocking, best-effort).
  local message="$1"
  local title="${2:-FreeVoice}"
  if [[ "$SHOW_NOTIFICATIONS" == "true" ]]; then
    osascript -e "display notification \"$message\" with title \"$title\"" 2>/dev/null || true
  fi
}

die() {
  log "ERROR: $*"
  notify "Error: $*" "FreeVoice"
  exit 1
}

# Persist a transcript so the menu bar can offer "Copy Last Transcript".
# Appends a timestamped line to the running log and overwrites the "last" file.
save_transcript() {
  local text="$1"
  mkdir -p "$FREEVOICE_DATA_DIR"
  printf '%s' "$text" > "$LAST_TRANSCRIPT_FILE"
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$text" >> "$TRANSCRIPT_LOG"
}

# ---------------------------------------------------------------------------
# Dependency checks
# ---------------------------------------------------------------------------

check_dependencies() {
  local ok=true

  echo "Checking FreeVoice dependencies..."
  echo

  # ffmpeg
  if command -v ffmpeg &>/dev/null; then
    echo "  [OK] ffmpeg: $(ffmpeg -version 2>&1 | head -1)"
  else
    echo "  [MISSING] ffmpeg — run: brew install ffmpeg"
    ok=false
  fi

  # whisper-cli
  if [[ -n "$WHISPER_BIN" ]] && command -v "$WHISPER_BIN" &>/dev/null; then
    echo "  [OK] whisper-cli: $WHISPER_BIN"
  else
    echo "  [MISSING] whisper-cli — run: brew install whisper-cpp"
    echo "            (or set WHISPER_BIN in config.local.sh if built from source)"
    ok=false
  fi

  # model file
  if [[ -f "$WHISPER_MODEL" ]]; then
    local size
    size=$(du -sh "$WHISPER_MODEL" | cut -f1)
    echo "  [OK] model: $WHISPER_MODEL ($size)"
  else
    echo "  [MISSING] model: $WHISPER_MODEL"
    echo "            Run install.sh to download a model."
    ok=false
  fi

  # Accessibility permission (needed for auto-paste via System Events)
  echo
  echo "  Note: Auto-paste requires Accessibility access for your terminal."
  echo "        System Settings → Privacy & Security → Accessibility"
  echo

  if [[ "$ok" == "true" ]]; then
    echo "All dependencies satisfied. FreeVoice is ready."
    return 0
  else
    echo "Some dependencies are missing. See install.sh or README.md."
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Device listing
# ---------------------------------------------------------------------------

list_devices() {
  echo "Available audio input devices:"
  echo "(Use the index number in MIC_DEVICE, e.g. MIC_DEVICE=\":1\")"
  echo
  ffmpeg -f avfoundation -list_devices true -i "" 2>&1 \
    | grep -A 100 "AVFoundation audio devices" \
    | grep -E "^\[AVFoundation" \
    | sed 's/\[AVFoundation.*\] /  /' \
    || die "ffmpeg not found. Install it with: brew install ffmpeg"
}

# ---------------------------------------------------------------------------
# Recording
# ---------------------------------------------------------------------------

cmd_start() {
  # Guard: don't start a second recording on top of an existing one.
  if [[ -f "$PID_FILE" ]]; then
    local existing_pid
    existing_pid=$(cat "$PID_FILE")
    if kill -0 "$existing_pid" 2>/dev/null; then
      log "Already recording (PID $existing_pid). Use 'stop' first."
      return 1
    else
      # Stale PID file — clean up.
      rm -f "$PID_FILE"
    fi
  fi

  # Verify dependencies before attempting to record.
  if [[ -z "$WHISPER_BIN" ]] || ! command -v "$WHISPER_BIN" &>/dev/null; then
    die "whisper-cli not found. Run install.sh or set WHISPER_BIN in config.local.sh."
  fi
  if [[ ! -f "$WHISPER_MODEL" ]]; then
    die "Model not found at $WHISPER_MODEL. Run install.sh to download one."
  fi

  # Remove any stale recording from a previous session.
  rm -f "$RECORDING_FILE"

  log "Starting recording (device: $MIC_DEVICE, ${RECORD_SAMPLE_RATE} Hz mono)..."
  notify "Recording..." "FreeVoice"

  # Start ffmpeg in the background.
  # -f avfoundation   : macOS Core Audio input driver
  # -i "$MIC_DEVICE"  : audio device (":default", ":0", ":1", etc.)
  # -ar 16000         : 16 kHz sample rate (Whisper's native rate)
  # -ac 1             : mono (Whisper doesn't use stereo)
  # -y                : overwrite output without prompting
  ffmpeg \
    -loglevel error \
    -f avfoundation \
    -i "$MIC_DEVICE" \
    -ar "$RECORD_SAMPLE_RATE" \
    -ac "$RECORD_CHANNELS" \
    -y \
    "$RECORDING_FILE" \
    >> "$LOG_FILE" 2>&1 &

  local ffmpeg_pid=$!
  echo "$ffmpeg_pid" > "$PID_FILE"
  log "Recording started (PID $ffmpeg_pid). Call 'stop' to finish."
}

# ---------------------------------------------------------------------------
# Stop + transcribe + paste (the complete pipeline)
# ---------------------------------------------------------------------------

cmd_stop() {
  if [[ ! -f "$PID_FILE" ]]; then
    log "Not recording (no PID file found)."
    return 1
  fi

  local pid
  pid=$(cat "$PID_FILE")
  rm -f "$PID_FILE"

  if kill -0 "$pid" 2>/dev/null; then
    log "Stopping recording (PID $pid)..."
    # SIGTERM causes ffmpeg to flush buffers and write a valid WAV footer.
    kill -SIGTERM "$pid" 2>/dev/null || true
    # Wait for ffmpeg to finish flushing (usually < 0.5 s).
    wait "$pid" 2>/dev/null || true
    log "Recording saved to $RECORDING_FILE"
  else
    log "Warning: recording process (PID $pid) was already gone."
  fi

  # Guard: make sure there's actually something to transcribe.
  if [[ ! -f "$RECORDING_FILE" ]] || [[ ! -s "$RECORDING_FILE" ]]; then
    die "Recording file is missing or empty. Was the mic accessible?"
  fi

  _transcribe_and_paste
}

# ---------------------------------------------------------------------------
# Transcribe only (re-runs on the last saved recording, no paste)
# ---------------------------------------------------------------------------

cmd_transcribe() {
  if [[ ! -f "$RECORDING_FILE" ]] || [[ ! -s "$RECORDING_FILE" ]]; then
    die "No recording found at $RECORDING_FILE. Record something first."
  fi

  local text
  text=$(_run_whisper)

  if [[ -z "$text" ]]; then
    log "Whisper returned no text (silence or unintelligible audio)."
    notify "Nothing transcribed." "FreeVoice"
    return 0
  fi

  save_transcript "$text"
  echo "$text"
  echo -n "$text" | pbcopy
  log "Copied to clipboard."
}

# ---------------------------------------------------------------------------
# Cancel (discard recording without transcribing)
# ---------------------------------------------------------------------------

cmd_cancel() {
  if [[ ! -f "$PID_FILE" ]]; then
    log "Not recording — nothing to cancel."
    return 0
  fi

  local pid
  pid=$(cat "$PID_FILE")
  rm -f "$PID_FILE"

  if kill -0 "$pid" 2>/dev/null; then
    log "Cancelling recording (PID $pid)..."
    kill -SIGTERM "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi

  # Discard the recording — do not transcribe.
  rm -f "$RECORDING_FILE"
  notify "Recording cancelled." "FreeVoice"
  log "Recording cancelled and discarded."
}

# ---------------------------------------------------------------------------
# Status
# ---------------------------------------------------------------------------

cmd_status() {
  if [[ -f "$PID_FILE" ]]; then
    local pid
    pid=$(cat "$PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
      echo "Recording (PID $pid)"
      return 0
    fi
  fi
  echo "Idle"
}

# ---------------------------------------------------------------------------
# Internal: run whisper.cpp and return cleaned text on stdout
# ---------------------------------------------------------------------------

_run_whisper() {
  notify "Transcribing..." "FreeVoice"
  log "Transcribing with $(basename "$WHISPER_BIN") (model: $(basename "$WHISPER_MODEL"))..."

  local raw_output
  # --no-timestamps (-nt) : omit [HH:MM:SS.mmm --> HH:MM:SS.mmm] prefixes
  # --language            : skip language-detection overhead for .en models
  # 2>/dev/null           : discard init/progress logs (they go to stderr)
  raw_output=$(
    "$WHISPER_BIN" \
      --model "$WHISPER_MODEL" \
      --file  "$RECORDING_FILE" \
      --language "$WHISPER_LANGUAGE" \
      --no-timestamps \
      2>/dev/null
  ) || {
    die "whisper-cli exited with an error. Check $LOG_FILE for details."
  }

  # Clean up the output:
  #   1. Remove any residual timestamp brackets whisper might emit
  #   2. Collapse multiple blank lines
  #   3. Strip leading/trailing whitespace
  local text
  text=$(
    echo "$raw_output" \
      | sed 's/^\[.*\][[:space:]]*//' \
      | sed '/^[[:space:]]*$/d' \
      | sed 's/^[[:space:]]*//' \
      | sed 's/[[:space:]]*$//' \
      | tr '\n' ' ' \
      | sed 's/[[:space:]]\{2,\}/ /g' \
      | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
  )

  echo "$text"
}

# ---------------------------------------------------------------------------
# Internal: transcribe and paste into the active app
# ---------------------------------------------------------------------------

_transcribe_and_paste() {
  local text
  text=$(_run_whisper)

  if [[ -z "$text" ]]; then
    log "Nothing transcribed (silence or unintelligible audio)."
    notify "Nothing transcribed." "FreeVoice"
    return 0
  fi

  # Optionally append a trailing space so the cursor lands after the text.
  if [[ "$APPEND_TRAILING_SPACE" == "true" ]]; then
    text="$text "
  fi

  log "Transcribed: $text"

  # Persist for menu bar "Copy Last Transcript".
  save_transcript "$text"

  # Copy to clipboard — always, regardless of AUTO_PASTE setting.
  printf '%s' "$text" | pbcopy

  if [[ "$AUTO_PASTE" == "true" ]]; then
    # Paste into whatever app currently has focus.
    # System Events requires Accessibility permission for the calling app
    # (Terminal, iTerm2, Hammerspoon — whichever triggered this script).
    osascript -e \
      'tell application "System Events" to keystroke "v" using command down' \
      2>/dev/null || {
        log "Auto-paste failed — Accessibility permission may be missing."
        log "The text is still on the clipboard; paste manually with Cmd+V."
        notify "Paste failed — check Accessibility permission." "FreeVoice"
        return 1
      }
    notify "Pasted." "FreeVoice"
    log "Pasted into active app."
  else
    notify "Copied to clipboard." "FreeVoice"
    log "Copied to clipboard (AUTO_PASTE is off)."
  fi

  # Delete the WAV immediately after transcription — audio is never kept.
  # Only the text transcript is persisted (in ~/.freevoice/).
  rm -f "$RECORDING_FILE"
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

COMMAND="${1:-}"

case "$COMMAND" in
  start)          cmd_start ;;
  stop)           cmd_stop ;;
  cancel)         cmd_cancel ;;
  transcribe)       cmd_transcribe ;;
  transcribe-paste) _transcribe_and_paste ;;
  status)         cmd_status ;;
  list-devices)   list_devices ;;
  check)          check_dependencies ;;
  *)
    echo "Usage: $(basename "$0") {start|stop|cancel|transcribe|transcribe-paste|status|list-devices|check}"
    echo
    echo "  start              Begin recording from the microphone"
    echo "  stop               Stop recording, transcribe, and paste into active app"
    echo "  cancel             Stop recording and discard (no transcription)"
    echo "  transcribe         Transcribe the last recording (no paste)"
    echo "  transcribe-paste   Transcribe the last recording and paste (called by Lua hotkey)"
    echo "  status        Show whether a recording is in progress"
    echo "  list-devices  Print available audio input devices with index numbers"
    echo "  check         Verify all dependencies are installed"
    exit 1
    ;;
esac
