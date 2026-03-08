-- =============================================================================
-- freevoice.lua — FreeVoice Hammerspoon integration
-- =============================================================================
-- HOLD hotkey → push-to-talk (records while held, stops on release)
-- TAP  hotkey → toggle       (first tap starts, second tap stops)
-- Esc  / indicator ×         → cancel without transcribing
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Configuration
-- ---------------------------------------------------------------------------

local HOLD_THRESHOLD      = 0.4    -- seconds before a keydown becomes PTT
local MAX_RECORD_SECONDS  = 660    -- auto-stop at 11 minutes
local WARN_RECORD_SECONDS = 600    -- amber warning at 10 minutes

-- Keyboard shortcut. Change via "Change Hotkey" in the menu.
local HOTKEY_MODS = {"alt"}
local HOTKEY_KEY  = "/"   -- Option+/ = ÷

local SHOW_INDICATOR = true
local MAX_HISTORY    = 5

-- ---------------------------------------------------------------------------
-- Audio config (keep in sync with config.sh / config.local.sh)
-- ---------------------------------------------------------------------------

local FFMPEG_BIN     = "/opt/homebrew/bin/ffmpeg"
local MIC_DEVICE     = ":default"
local SAMPLE_RATE    = "16000"
local RECORDING_FILE = "/tmp/freevoice_recording.wav"

-- ---------------------------------------------------------------------------
-- Auto-detect repo directory from this file's path
-- ---------------------------------------------------------------------------

local _src = debug.getinfo(1, "S").source:match("^@?(.+)$") or ""
local FREEVOICE_DIR = _src:match("(.+)/hammerspoon/[^/]+$")
    or (os.getenv("HOME") .. "/Desktop/freevoice")

local freevoiceSh        = FREEVOICE_DIR .. "/freevoice.sh"
local lastTranscriptFile = os.getenv("HOME") .. "/.freevoice/last_transcript.txt"
local transcriptLogFile  = os.getenv("HOME") .. "/.freevoice/transcripts.log"

-- ---------------------------------------------------------------------------
-- State machine
-- ---------------------------------------------------------------------------

local STATE = {
    IDLE         = "idle",
    TAP_PENDING  = "tap_pending",
    PTT          = "ptt",
    TOGGLE       = "toggle",
    TRANSCRIBING = "transcribing",
}
local state     = STATE.IDLE
local holdTimer = nil

-- Forward declarations
local _hotkey
local _escHotkey
local cancelRecording
local onKeyDown
local onKeyUp

-- ffmpeg task kept alive in Lua so Hammerspoon is the OS-level parent,
-- preserving the TCC mic permission throughout the recording.
local _recordTask   = nil
local _onFfmpegDone = nil
local _warnTimer    = nil
local _maxTimer     = nil

-- ---------------------------------------------------------------------------
-- Menu bar icon — speech bubble drawn via hs.canvas
-- ---------------------------------------------------------------------------

local function _makeBubbleIcon(sz)
    local c   = hs.canvas.new({x=0, y=0, w=sz, h=sz})
    local col = {red=0, green=0, blue=0, alpha=1}
    local pad = math.max(1, sz * 0.06)
    local bH  = sz * 0.65
    local bW  = sz - pad * 2
    local r   = sz * 0.20

    c:appendElements({
        type="rectangle", action="fill", fillColor=col,
        roundedRectRadii={xRadius=r, yRadius=r},
        frame={x=pad, y=pad, w=bW, h=bH},
    })
    local bBase = pad + bH
    c:appendElements({
        type="segments", action="fill", fillColor=col, closed=true,
        coordinates={
            {x=sz*0.21, y=bBase-1},
            {x=sz*0.12, y=sz-pad },
            {x=sz*0.37, y=bBase-1},
        },
    })

    local img = c:imageFromCanvas()
    c:delete()
    return img
end

local menuBar = hs.menubar.new()
local _mbIcon = _makeBubbleIcon(18)

local function setMenuBarIcon(_) end   -- icon is static; indicator shows state

-- ---------------------------------------------------------------------------
-- Floating animated indicator
-- ---------------------------------------------------------------------------
-- Recording  → 5 white waveform bars (animated)
-- Warning    → 5 amber bars (approaching time limit)
-- Transcribing → 3 pulsing gray dots (iMessage-style "thinking")
-- Top-left × cancels recording.

local IND = {
    W        = 80,    H        = 34,
    -- Waveform bars
    BARS     = 5,     BAR_W    = 3,    BAR_GAP  = 7,
    BAR_X0   = 19,   -- (80 - (5*3 + 4*7)) / 2
    MAX_H    = 22,    MIN_H    = 3,
    -- Dot positions for transcribing (centered in canvas)
    DOT_R    = 3.5,   DOT_Y    = 17,  -- H/2
    DOT_XS   = {26, 40, 54},          -- 3 dots, 14 px apart
    -- Animation
    FPS      = 25,
    -- Colors
    BG       = {red=0.06, green=0.06, blue=0.06, alpha=0.72},
    BAR_REC  = {red=1.00, green=1.00, blue=1.00, alpha=1.0},   -- white
    BAR_WARN = {red=1.00, green=0.62, blue=0.10, alpha=1.0},   -- amber
    CLOSE    = {w=18, h=18},   -- × hit-target (top-left corner)
}

local _canvas    = nil
local _animTimer = nil
local _animPhase = 0.0
local _indMode   = nil   -- "recording" | "warning" | "transcribing"

local _dragWatcher = nil
local _dragOrigin  = nil
local _dragStart   = nil

local function _stopAnimation()
    if _animTimer then _animTimer:stop(); _animTimer = nil end
end

local function _destroyCanvas()
    _stopAnimation()
    if _dragWatcher then _dragWatcher:stop(); _dragWatcher = nil end
    if _canvas then _canvas:hide(); _canvas:delete(); _canvas = nil end
    _indMode = nil
end

local function _buildCanvas()
    local screen = hs.screen.mainScreen():frame()
    local x = screen.x + screen.w - IND.W - 60
    local y = screen.y + screen.h - IND.H - 60
    local c = hs.canvas.new({x=x, y=y, w=IND.W, h=IND.H})

    c:appendElements({   -- background
        id="bg", type="rectangle", action="fill", fillColor=IND.BG,
        roundedRectRadii={xRadius=10, yRadius=10},
        frame={x=0, y=0, w=IND.W, h=IND.H},
    })
    c:appendElements({   -- × close button (top-left)
        id="closeX", type="text", text="×",
        textColor={red=0.55, green=0.55, blue=0.55, alpha=0.90},
        textSize=11, frame={x=3, y=1, w=13, h=15}, textAlignment="center",
    })
    for i = 1, IND.BARS do   -- waveform bars
        local bx = IND.BAR_X0 + (i-1) * (IND.BAR_W + IND.BAR_GAP)
        c:appendElements({
            id="bar"..i, type="rectangle", action="fill", fillColor=IND.BAR_REC,
            frame={x=bx, y=(IND.H-IND.MIN_H)/2, w=IND.BAR_W, h=IND.MIN_H},
            roundedRectRadii={xRadius=1, yRadius=1},
        })
    end
    for i = 1, 3 do   -- transcribing dots (start invisible)
        c:appendElements({
            id="dot"..i, type="circle", action="fill",
            fillColor={red=0.65, green=0.65, blue=0.65, alpha=0},
            center={x=IND.DOT_XS[i], y=IND.DOT_Y}, radius=IND.DOT_R,
        })
    end

    c:level(hs.canvas.windowLevels.floating)
    c:show()
    return c
end

local _TRANSPARENT = {red=0, green=0, blue=0, alpha=0}

local function _animateBars()
    if not _canvas then return end

    if _indMode == "transcribing" then
        -- Hide bars
        for i = 1, IND.BARS do _canvas["bar"..i].fillColor = _TRANSPARENT end
        -- Animate 3 dots: staggered sine wave (120° apart) — "thinking" effect
        _animPhase = _animPhase + 0.10
        for i = 1, 3 do
            local phase = _animPhase + (i-1) * (2 * math.pi / 3)
            local a     = 0.12 + ((math.sin(phase) + 1) / 2) * 0.88
            _canvas["dot"..i].fillColor =
                {red=0.65, green=0.65, blue=0.65, alpha=a}
        end

    else
        -- Hide dots
        for i = 1, 3 do _canvas["dot"..i].fillColor = _TRANSPARENT end
        -- Animate bars (white when recording, amber when warning)
        local barColor = (_indMode == "warning") and IND.BAR_WARN or IND.BAR_REC
        local speed    = (_indMode == "warning") and 0.28 or 0.18
        _animPhase = _animPhase + speed
        for i = 1, IND.BARS do
            local phase = _animPhase + (i-1) * 0.55
            local frac  = (math.sin(phase) + 1) / 2
            local bh    = IND.MIN_H + frac * (IND.MAX_H - IND.MIN_H)
            local bx    = IND.BAR_X0 + (i-1) * (IND.BAR_W + IND.BAR_GAP)
            _canvas["bar"..i].frame     = {x=bx, y=(IND.H-bh)/2, w=IND.BAR_W, h=bh}
            _canvas["bar"..i].fillColor = barColor
        end
    end
end

local function showIndicator(mode)
    if not SHOW_INDICATOR then return end
    _indMode = mode
    if not _canvas then
        _canvas = _buildCanvas()
        _dragWatcher = hs.eventtap.new(
            { hs.eventtap.event.types.leftMouseDown,
              hs.eventtap.event.types.leftMouseDragged,
              hs.eventtap.event.types.leftMouseUp },
            function(evt)
                if not _canvas then return false end
                local eType  = evt:getType()
                local mPos   = hs.mouse.absolutePosition()
                local cFrame = _canvas:frame()
                local Types  = hs.eventtap.event.types

                if eType == Types.leftMouseDown then
                    local rx = mPos.x - cFrame.x
                    local ry = mPos.y - cFrame.y
                    if rx < 0 or rx > cFrame.w or ry < 0 or ry > cFrame.h then
                        _dragStart = nil; return false
                    end
                    -- × hit-test
                    if rx <= IND.CLOSE.w and ry <= IND.CLOSE.h then
                        if cancelRecording then cancelRecording() end
                        _dragStart = nil; return false
                    end
                    _dragStart  = {x=mPos.x,   y=mPos.y  }
                    _dragOrigin = {x=cFrame.x,  y=cFrame.y}

                elseif eType == Types.leftMouseDragged then
                    if _dragStart then
                        _canvas:topLeft({
                            x = _dragOrigin.x + (mPos.x - _dragStart.x),
                            y = _dragOrigin.y + (mPos.y - _dragStart.y),
                        })
                    end

                elseif eType == Types.leftMouseUp then
                    _dragStart = nil
                end
                return false
            end
        )
        _dragWatcher:start()
    else
        _indMode = mode
    end
    _stopAnimation()
    _animTimer = hs.timer.doEvery(1/IND.FPS, _animateBars)
end

local function hideIndicator() _destroyCanvas() end

-- ---------------------------------------------------------------------------
-- Recording timers
-- ---------------------------------------------------------------------------

local function _clearRecordTimers()
    if _warnTimer then _warnTimer:stop(); _warnTimer = nil end
    if _maxTimer  then _maxTimer:stop();  _maxTimer  = nil end
end

local function _startRecordTimers()
    if not MAX_RECORD_SECONDS then return end
    _warnTimer = hs.timer.doAfter(WARN_RECORD_SECONDS, function()
        if _indMode == "recording" then
            _indMode = "warning"
            hs.alert.show(
                string.format("⚠ Recording will stop in %ds",
                    MAX_RECORD_SECONDS - WARN_RECORD_SECONDS), 4)
        end
    end)
    _maxTimer = hs.timer.doAfter(MAX_RECORD_SECONDS, function()
        if state == STATE.PTT or state == STATE.TOGGLE then
            hs.alert.show("Recording limit reached — transcribing now", 2)
            -- stopAndTranscribe is defined below; call via a timer to avoid
            -- forward-reference issues at load time.
            hs.timer.doAfter(0, function()
                if state == STATE.PTT or state == STATE.TOGGLE then
                    -- Inline the stop sequence to avoid forward-ref:
                    local _stopAndTranscribe = _G and _G.fv_stopAndTranscribe
                    if _stopAndTranscribe then _stopAndTranscribe() end
                end
            end)
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Esc cancel
-- ---------------------------------------------------------------------------

local function enableEscCancel()
    if _escHotkey then _escHotkey:enable() end
end
local function disableEscCancel()
    if _escHotkey then _escHotkey:disable() end
end

-- ---------------------------------------------------------------------------
-- State transitions
-- ---------------------------------------------------------------------------

local function transitionTo(s) state = s; setMenuBarIcon(s) end

-- ---------------------------------------------------------------------------
-- Async task runner
-- ---------------------------------------------------------------------------

local function runAsync(subcommand, onDone)
    return hs.task.new(freevoiceSh, onDone or function() end, {subcommand}):start()
end

-- ---------------------------------------------------------------------------
-- Recording actions
-- ---------------------------------------------------------------------------

local function _interruptRecord(cb)
    _onFfmpegDone = cb
    if _recordTask and _recordTask:isRunning() then
        _recordTask:interrupt()
    else
        local c = _onFfmpegDone; _onFfmpegDone = nil; _recordTask = nil
        if c then c(0, "", "") end
    end
end

local function startRecording()
    os.remove(RECORDING_FILE)
    showIndicator("recording")
    _startRecordTimers()

    _recordTask = hs.task.new(FFMPEG_BIN, function(code, _, err)
        local cb = _onFfmpegDone; _onFfmpegDone = nil; _recordTask = nil
        if cb then
            cb(code, _, err)
        else
            hideIndicator(); disableEscCancel(); transitionTo(STATE.IDLE)
            if code ~= 0 then
                hs.alert.show("⚠ FreeVoice: recording stopped unexpectedly\n" ..
                    (err ~= "" and err or "ffmpeg exit "..tostring(code)), 5)
            end
        end
    end, {"-loglevel","error","-f","avfoundation","-i",MIC_DEVICE,
          "-ar",SAMPLE_RATE,"-ac","1","-y",RECORDING_FILE})

    if not _recordTask:start() then
        _clearRecordTimers(); hideIndicator(); disableEscCancel(); _recordTask = nil
        hs.alert.show("⚠ FreeVoice: could not start ffmpeg.\nRun: brew install ffmpeg", 5)
        transitionTo(STATE.IDLE)
    end
end

local stopAndTranscribe   -- forward declare so cancelRecording can see it

stopAndTranscribe = function()
    _clearRecordTimers()
    disableEscCancel()
    showIndicator("transcribing")
    transitionTo(STATE.TRANSCRIBING)
    _interruptRecord(function(_, _, _)
        runAsync("transcribe-paste", function(code, _, err)
            hideIndicator()
            if code == 0 then
                hs.alert.show("✓", 1.2)
            else
                hs.alert.show("⚠ FreeVoice: " ..
                    (err ~= "" and err or "transcription failed"), 4)
            end
            transitionTo(STATE.IDLE)
        end)
    end)
end

-- Expose for the max-timer callback above
if _G then _G.fv_stopAndTranscribe = stopAndTranscribe end

cancelRecording = function()
    if state == STATE.IDLE or state == STATE.TRANSCRIBING then return end
    _clearRecordTimers(); disableEscCancel()
    if holdTimer then holdTimer:stop(); holdTimer = nil end
    hideIndicator(); transitionTo(STATE.IDLE)
    _interruptRecord(function(_, _, _) os.remove(RECORDING_FILE) end)
end

_escHotkey = hs.hotkey.new({}, "escape", cancelRecording)

-- ---------------------------------------------------------------------------
-- State machine handlers
-- ---------------------------------------------------------------------------

onKeyDown = function()
    if state == STATE.IDLE then
        transitionTo(STATE.TAP_PENDING)
        holdTimer = hs.timer.doAfter(HOLD_THRESHOLD, function()
            if state == STATE.TAP_PENDING then
                transitionTo(STATE.PTT); enableEscCancel(); startRecording()
            end
        end)
    elseif state == STATE.TOGGLE then
        if holdTimer then holdTimer:stop(); holdTimer = nil end
        stopAndTranscribe()
    end
end

onKeyUp = function()
    if state == STATE.TAP_PENDING then
        if holdTimer then holdTimer:stop(); holdTimer = nil end
        transitionTo(STATE.TOGGLE); enableEscCancel(); startRecording()
    elseif state == STATE.PTT then
        stopAndTranscribe()
    end
end

-- ---------------------------------------------------------------------------
-- Hotkey helpers
-- ---------------------------------------------------------------------------

local function _hotkeyLabel(mods, key)
    local sym = {alt="⌥", cmd="⌘", shift="⇧", ctrl="⌃"}
    local parts = {}
    for _, m in ipairs(mods or {}) do table.insert(parts, sym[m] or m) end
    table.insert(parts, key:upper())
    return table.concat(parts, "")
end

-- Modifier key names to ignore when capturing a hotkey combo
local _MOD_KEYS = {
    lalt=true, ralt=true, alt=true,
    lshift=true, rshift=true, shift=true,
    lctrl=true, rctrl=true, ctrl=true,
    lcmd=true, rcmd=true, cmd=true, fn=true,
}

local function captureCustomHotkey()
    if _hotkey then _hotkey:disable() end
    hs.alert.show("Press your new hotkey combination\n(Esc to cancel)", 15)

    local capTap
    capTap = hs.eventtap.new({hs.eventtap.event.types.keyDown}, function(evt)
        local keyName = hs.keycodes.map[evt:getKeyCode()]
        if _MOD_KEYS[keyName or ""] then return false end   -- skip bare modifiers

        capTap:stop()
        hs.alert.closeAll()

        if keyName == "escape" then
            if _hotkey then _hotkey:enable() end
            return true
        end

        local flags = evt:getFlags()
        local mods  = {}
        if flags.cmd   then table.insert(mods, "cmd")   end
        if flags.alt   then table.insert(mods, "alt")   end
        if flags.shift then table.insert(mods, "shift") end
        if flags.ctrl  then table.insert(mods, "ctrl")  end

        if _hotkey then _hotkey:delete() end
        HOTKEY_MODS = mods; HOTKEY_KEY = keyName
        _hotkey = hs.hotkey.bind(HOTKEY_MODS, HOTKEY_KEY, onKeyDown, onKeyUp)

        if _hotkey then
            hs.alert.show("Hotkey → " .. _hotkeyLabel(mods, keyName), 2)
        else
            hs.alert.show("⚠ That combination didn't work — try another.", 3)
            HOTKEY_MODS = {"alt"}; HOTKEY_KEY = "/"
            _hotkey = hs.hotkey.bind(HOTKEY_MODS, HOTKEY_KEY, onKeyDown, onKeyUp)
            if _hotkey then _hotkey:enable() end
        end
        return true   -- consume the captured keypress
    end)
    capTap:start()
end

-- ---------------------------------------------------------------------------
-- Setup check (friendly webview window)
-- ---------------------------------------------------------------------------

local function showSetupCheck()
    local ffmpegOk  = (hs.fs.attributes(FFMPEG_BIN) ~= nil)
    local whisperOk = (hs.fs.attributes("/opt/homebrew/bin/whisper-cli") ~= nil
                    or hs.fs.attributes("/usr/local/bin/whisper-cli")    ~= nil)
    local modelPath = os.getenv("HOME") .. "/.freevoice/models/ggml-small.en.bin"
    local modelOk   = (hs.fs.attributes(modelPath) ~= nil)
    local micOk     = (hs.audiodevice.defaultInputDevice() ~= nil)
    local hotkeyOk  = (_hotkey ~= nil)
    local allGood   = ffmpegOk and whisperOk and modelOk and micOk and hotkeyOk

    local function row(ok, title, fix)
        local note = (not ok and fix)
            and ('<p style="margin:5px 0 0;font-size:12px;color:#888;">'..fix.."</p>")
            or  ""
        return string.format(
            '<div style="display:flex;gap:12px;padding:13px 0;'
            ..'border-bottom:1px solid #f0f0f0;align-items:flex-start;">'
            ..'<span style="font-size:20px;line-height:1.2;">%s</span>'
            ..'<div><p style="margin:0;font-size:14px;font-weight:500;color:%s;">%s</p>%s</div>'
            .."</div>",
            ok and "✅" or "❌",
            ok and "#1a1a1a" or "#b00020",
            title, note)
    end

    local summary = allGood
        and '<p style="color:#2a7d2a;font-size:13px;margin-bottom:18px;">Everything is set up — FreeVoice is ready.</p>'
        or  '<p style="color:#b00020;font-size:13px;margin-bottom:18px;">A few things need attention. See below.</p>'

    local html = [[<!DOCTYPE html><html><head><meta charset="UTF-8"><style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;background:#fff;
     color:#1a1a1a;padding:28px}
h1{font-size:19px;font-weight:600;margin-bottom:8px}
.list div:last-child{border-bottom:none!important}
button{margin-top:22px;background:#007AFF;color:#fff;border:none;
       padding:9px 26px;border-radius:9px;font-size:14px;font-weight:500;cursor:pointer}
button:hover{background:#0062cc}
</style></head><body><h1>FreeVoice — Setup</h1>]] .. summary
    .. '<div class="list">'
    .. row(ffmpegOk,  "Audio recorder (ffmpeg)",
           "Open Terminal and run:  brew install ffmpeg")
    .. row(whisperOk, "Speech-to-text engine (whisper-cli)",
           "Open Terminal and run:  brew install whisper-cpp")
    .. row(modelOk,   "Speech model downloaded (~150 MB)",
           "Run install.sh — it downloads the model file automatically")
    .. row(micOk,     "Microphone found",
           "System Settings → Privacy & Security → Microphone → enable Hammerspoon")
    .. row(hotkeyOk,  "Keyboard shortcut active",
           "System Settings → Privacy & Security → Input Monitoring → enable Hammerspoon")
    .. [[</div>
<button onclick="window.location='fv://close'">Done</button>
</body></html>]]

    local sw, sh = 430, 415
    local sf = hs.screen.mainScreen():frame()
    local wv = hs.webview.new({
        x=sf.x+(sf.w-sw)/2, y=sf.y+(sf.h-sh)/2, w=sw, h=sh,
    })
    wv:windowStyle({"titled","closable"})
    wv:windowTitle("FreeVoice")
    wv:deleteOnClose(true)
    wv:navigationCallback(function(action, wv2)
        if action=="didNavigate" and (wv2:url() or ""):find("^fv://close") then
            wv2:delete()
        end
    end)
    wv:html(html)
    wv:show()
    wv:bringToFront()
end

-- ---------------------------------------------------------------------------
-- Transcript helpers
-- ---------------------------------------------------------------------------

local function readLastTranscript()
    local f = io.open(lastTranscriptFile, "r")
    if not f then return nil end
    local t = f:read("*all"):match("^%s*(.-)%s*$"); f:close()
    return (t and t ~= "") and t or nil
end

local function readRecentTranscripts(n)
    local f = io.open(transcriptLogFile, "r")
    if not f then return {} end
    local entries = {}
    for line in f:lines() do
        local ts, text = line:match("^%[([^%]]+)%] (.+)$")
        if ts and text then table.insert(entries, {timestamp=ts, text=text}) end
    end
    f:close()
    local result = {}
    for i = #entries, math.max(1, #entries - n + 1), -1 do
        table.insert(result, entries[i])
    end
    return result
end

-- ---------------------------------------------------------------------------
-- Menu
-- ---------------------------------------------------------------------------

local function buildMenu()
    local lastText = readLastTranscript()
    local items    = {}

    -- Copy last transcript
    table.insert(items, {
        title    = "Copy Last Transcript",
        disabled = (lastText == nil),
        fn       = function()
            local text = readLastTranscript()
            if text then
                hs.pasteboard.setContents(text)
                local preview = #text > 60 and (text:sub(1,60).."…") or text
                hs.alert.show("Copied: "..preview, 2.5)
            else
                hs.alert.show("No transcript yet.", 2)
            end
        end,
    })

    -- Recent transcripts submenu
    local history = readRecentTranscripts(MAX_HISTORY)
    if #history > 0 then
        local sub = {}
        for _, e in ipairs(history) do
            local cap = e
            local t   = e.timestamp:sub(12,16)
            local pre = #e.text > 55 and (e.text:sub(1,55).."…") or e.text
            table.insert(sub, {
                title = string.format("[%s]  %s", t, pre),
                fn    = function()
                    hs.pasteboard.setContents(cap.text)
                    hs.alert.show("Copied", 1.2)
                end,
            })
        end
        table.insert(items, {title="Recent Transcripts", menu=sub})
    end

    table.insert(items, {title="-"})

    -- Change Hotkey submenu (presets + Custom…)
    local presets = {
        {label="÷  (Option + /)",     mods={"alt"}, key="/"},
        {label="⌥ Space",             mods={"alt"}, key="space"},
        {label="F13",                 mods={},      key="f13"},
    }
    -- Determine if the active hotkey matches any preset
    local isPresetActive = false
    for _, p in ipairs(presets) do
        if p.key == HOTKEY_KEY and table.concat(p.mods) == table.concat(HOTKEY_MODS) then
            isPresetActive = true; break
        end
    end

    local hotkeySub = {}
    for _, p in ipairs(presets) do
        local active = (p.key == HOTKEY_KEY
            and table.concat(p.mods) == table.concat(HOTKEY_MODS))
        local cap = p
        table.insert(hotkeySub, {
            title = active and ("✓  "..p.label) or ("   "..p.label),
            fn    = function()
                if _hotkey then _hotkey:delete() end
                HOTKEY_MODS = cap.mods; HOTKEY_KEY = cap.key
                _hotkey = hs.hotkey.bind(HOTKEY_MODS, HOTKEY_KEY, onKeyDown, onKeyUp)
                hs.alert.show("Hotkey → ".._hotkeyLabel(cap.mods, cap.key), 1.5)
            end,
        })
    end
    table.insert(hotkeySub, {title="-"})
    -- Show ✓ + current combo when a custom key is active
    local customLabel = isPresetActive
        and "   Custom…"
        or  ("✓  Custom  ".._hotkeyLabel(HOTKEY_MODS, HOTKEY_KEY))
    table.insert(hotkeySub, {title=customLabel, fn=captureCustomHotkey})
    table.insert(items, {title="Change Hotkey", menu=hotkeySub})

    -- Check Setup
    table.insert(items, {title="Check Setup", fn=showSetupCheck})

    table.insert(items, {title="-"})

    -- Quit
    table.insert(items, {
        title = "Quit FreeVoice",
        fn    = function()
            _clearRecordTimers()
            if state ~= STATE.IDLE then
                _interruptRecord(function() os.remove(RECORDING_FILE) end)
            end
            hideIndicator(); disableEscCancel()
            if _escHotkey then _escHotkey:delete() end
            if _hotkey    then _hotkey:delete()    end
            menuBar:delete()
            if _G then _G.fv_stopAndTranscribe = nil end
            print("[FreeVoice] Quit.")
        end,
    })

    return items
end

if menuBar then
    menuBar:setIcon(_mbIcon, true)
    menuBar:setMenu(buildMenu)
    menuBar:setTooltip("FreeVoice")
end

-- ---------------------------------------------------------------------------
-- Hotkey registration
-- ---------------------------------------------------------------------------

_hotkey = hs.hotkey.bind(HOTKEY_MODS, HOTKEY_KEY, onKeyDown, onKeyUp)

if _hotkey then
    print(string.format("[FreeVoice] Loaded. Hotkey: %s+%s | Repo: %s",
        (#HOTKEY_MODS > 0 and table.concat(HOTKEY_MODS,"+") or "none"),
        HOTKEY_KEY, FREEVOICE_DIR))
else
    hs.alert.show("⚠ FreeVoice: hotkey failed to register.\n"
        .."Check Input Monitoring in System Settings → Privacy & Security.", 6)
end

return _hotkey
