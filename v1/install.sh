#!/usr/bin/env bash
# =============================================================================
# install.sh — FreeVoice one-shot installer
# =============================================================================
# Installs all dependencies and downloads a Whisper model.
# Run this once after cloning the repo.
#
# Usage:
#   ./install.sh                  Install with defaults (small.en model)
#   ./install.sh --model medium   Download the medium.en model instead
#   ./install.sh --model base     Download the base.en model (fastest)
#   ./install.sh --help           Show all options
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------

MODEL_CHOICE="small"       # base | small | medium
MODEL_LANG="en"            # en (English-only, faster) or "" (multilingual)
MODELS_DIR="$HOME/.freevoice/models"
HF_BASE="https://huggingface.co/ggerganov/whisper.cpp/resolve/main"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

print_help() {
  cat <<EOF
install.sh — FreeVoice installer

Usage:
  ./install.sh [OPTIONS]

Options:
  --model <name>   Model to download: base | small | medium  (default: small)
  --multilingual   Download the multilingual model instead of English-only
  --help           Show this message

Model comparison (Apple Silicon — approximate):
  base    ~75 MB   ~1-2 s latency   Lower accuracy
  small   ~150 MB  ~2-5 s latency   Good balance  ← recommended
  medium  ~470 MB  ~8-15 s latency  Higher accuracy

The model is saved to ~/.freevoice/models/ and gitignored.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model)        MODEL_CHOICE="$2"; shift 2 ;;
    --multilingual) MODEL_LANG="";     shift ;;
    --help|-h)      print_help; exit 0 ;;
    *)
      echo "Unknown option: $1"
      print_help
      exit 1
      ;;
  esac
done

# Derive the full model filename from the chosen size + language suffix.
if [[ -n "$MODEL_LANG" ]]; then
  MODEL_FILENAME="ggml-${MODEL_CHOICE}.${MODEL_LANG}.bin"
else
  MODEL_FILENAME="ggml-${MODEL_CHOICE}.bin"
fi
MODEL_URL="${HF_BASE}/${MODEL_FILENAME}"
MODEL_PATH="${MODELS_DIR}/${MODEL_FILENAME}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

step() { echo; echo "==> $*"; }
info() { echo "    $*"; }
ok()   { echo "    [OK] $*"; }
warn() { echo "    [WARN] $*"; }

require_macos() {
  if [[ "$(uname)" != "Darwin" ]]; then
    echo "ERROR: FreeVoice only supports macOS."
    exit 1
  fi
}

require_apple_silicon() {
  if [[ "$(uname -m)" != "arm64" ]]; then
    warn "Non-Apple Silicon Mac detected. Performance will be lower without Metal GPU acceleration."
    warn "Whisper will still work — just slower."
  fi
}

# ---------------------------------------------------------------------------
# 1. Pre-flight
# ---------------------------------------------------------------------------

require_macos
require_apple_silicon

echo "======================================================"
echo " FreeVoice Installer"
echo " Model: $MODEL_FILENAME"
echo "======================================================"

# ---------------------------------------------------------------------------
# 2. Homebrew
# ---------------------------------------------------------------------------

step "Checking Homebrew..."
if command -v brew &>/dev/null; then
  ok "Homebrew is already installed."
else
  info "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Ensure brew is on PATH (common for Apple Silicon fresh installs)
  eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"
  ok "Homebrew installed."
fi

# ---------------------------------------------------------------------------
# 3. ffmpeg
# ---------------------------------------------------------------------------

step "Checking ffmpeg..."
if command -v ffmpeg &>/dev/null; then
  ok "ffmpeg already installed: $(ffmpeg -version 2>&1 | head -1 | awk '{print $3}')"
else
  info "Installing ffmpeg via Homebrew..."
  brew install ffmpeg
  ok "ffmpeg installed."
fi

# ---------------------------------------------------------------------------
# 4. whisper.cpp
# ---------------------------------------------------------------------------

step "Checking whisper-cli (whisper.cpp)..."
if command -v whisper-cli &>/dev/null; then
  ok "whisper-cli already installed: $(whisper-cli --version 2>&1 | head -1 || echo 'version unknown')"
else
  info "Installing whisper-cpp via Homebrew..."
  info "(This includes Metal GPU acceleration for Apple Silicon.)"
  brew install whisper-cpp
  ok "whisper-cli installed."
fi

# ---------------------------------------------------------------------------
# 5. Hammerspoon (hotkey engine)
# ---------------------------------------------------------------------------

step "Checking Hammerspoon..."
if [[ -d "/Applications/Hammerspoon.app" ]]; then
  ok "Hammerspoon already installed."
else
  info "Installing Hammerspoon via Homebrew Cask..."
  brew install --cask hammerspoon
  ok "Hammerspoon installed."
fi

# ---------------------------------------------------------------------------
# 6. Download Whisper model
# ---------------------------------------------------------------------------

step "Setting up Whisper model..."

mkdir -p "$MODELS_DIR"

if [[ -f "$MODEL_PATH" ]]; then
  local_size=$(du -sh "$MODEL_PATH" | cut -f1)
  ok "Model already exists: $MODEL_PATH ($local_size)"
  info "Delete the file and re-run to re-download."
else
  info "Downloading $MODEL_FILENAME from Hugging Face..."
  info "URL: $MODEL_URL"
  info "(This may take a few minutes depending on your connection.)"

  if command -v curl &>/dev/null; then
    curl -L --progress-bar -o "$MODEL_PATH" "$MODEL_URL"
  elif command -v wget &>/dev/null; then
    wget -q --show-progress -O "$MODEL_PATH" "$MODEL_URL"
  else
    echo "ERROR: Neither curl nor wget found. Cannot download model."
    exit 1
  fi

  ok "Model saved to $MODEL_PATH"
fi

# ---------------------------------------------------------------------------
# 7. Write config.local.sh if not present
# ---------------------------------------------------------------------------

step "Checking user config..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_CONFIG="$SCRIPT_DIR/config.local.sh"

if [[ -f "$LOCAL_CONFIG" ]]; then
  ok "config.local.sh already exists — leaving it untouched."
else
  info "Creating config.local.sh from the example..."
  cp "$SCRIPT_DIR/config.local.sh.example" "$LOCAL_CONFIG"
  # Pre-fill the model path with whatever was just downloaded.
  sed -i '' "s|# WHISPER_MODEL=.*|WHISPER_MODEL=\"$MODEL_PATH\"|" "$LOCAL_CONFIG" 2>/dev/null || true
  ok "Created config.local.sh — edit it to customise your setup."
fi

# ---------------------------------------------------------------------------
# 8. Make scripts executable
# ---------------------------------------------------------------------------

step "Setting script permissions..."
chmod +x "$SCRIPT_DIR/freevoice.sh"
chmod +x "$SCRIPT_DIR/install.sh"
ok "Scripts are executable."

# ---------------------------------------------------------------------------
# 9. Wire Hammerspoon config
# ---------------------------------------------------------------------------
# Adds a require() line to ~/.hammerspoon/init.lua so Hammerspoon loads
# FreeVoice automatically. Safe to re-run: skipped if the line already exists.

step "Wiring Hammerspoon config..."

HS_CONFIG_DIR="$HOME/.hammerspoon"
HS_INIT="$HS_CONFIG_DIR/init.lua"
DOFILE_LINE="dofile(\"$SCRIPT_DIR/hammerspoon/freevoice.lua\")"

mkdir -p "$HS_CONFIG_DIR"

if grep -qF "$DOFILE_LINE" "$HS_INIT" 2>/dev/null; then
  ok "Hammerspoon config already contains the FreeVoice dofile line."
else
  # Append with a comment so it's easy to find and remove later.
  printf '\n-- FreeVoice dictation (added by install.sh)\n%s\n' "$DOFILE_LINE" >> "$HS_INIT"
  ok "Added FreeVoice to $HS_INIT"
fi

# Open Hammerspoon so it's running and ready to reload.
open -a Hammerspoon 2>/dev/null || true

# ---------------------------------------------------------------------------
# 10. Verify everything
# ---------------------------------------------------------------------------

step "Running dependency check..."
"$SCRIPT_DIR/freevoice.sh" check

# ---------------------------------------------------------------------------
# 11. Post-install instructions
# ---------------------------------------------------------------------------

echo
echo "======================================================"
echo " Installation complete!"
echo "======================================================"
echo
echo "NEXT STEPS  (just 2 things)"
echo "---------------------------"
echo
echo "1. Reload Hammerspoon:"
echo "   Click the Hammerspoon icon in your menu bar → Reload Config"
echo "   You should see '🎙 FV' appear in the menu bar."
echo
echo "2. Grant two permissions when macOS prompts:"
echo "   • Input Monitoring  — for the global hotkey"
echo "   • Accessibility     — for auto-paste into apps"
echo "   Both appear in System Settings → Privacy & Security."
echo "   After granting each one, click Reload Config again."
echo
echo "Then press Option+/ (÷), speak, and press again to finish — or hold to push-to-talk."
echo
echo "Full instructions: README.md"
echo
