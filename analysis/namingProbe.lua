-- CAN AN ACTION PATTERN BE NAMED FROM A SEPARATE WINDOW - AND THEN SHOWN?
--
-- Naming a pattern with a stick and a character wheel is miserable. A real
-- text field with a real keyboard is the obvious fix, and the file dialog work
-- on 2026-09-16 already proved the transport: io.popen -> PowerShell -> Windows
-- Forms, with the answer handed back through a UTF-8 file.
--
-- BUT A NAME IS NOT A PATH. A path only has to be handed to the OS; a name has
-- to be DRAWN, every frame, by gui.text. Nothing in this entire tool passes a
-- non-ASCII byte to gui.text - measured, not assumed - so whether FBNeo's font
-- can draw one at all is unknown, and it decides the whole feature:
--
--   * if it can, names can be Japanese and the window is the way to type them
--   * if it cannot, names are ASCII-only, and then the question becomes
--     whether a window is worth a freeze when a character wheel or the PC
--     keyboard would do
--
-- ANSWERED 2026-09-16: gui.text draws NOTHING for kana and kanji. Not garbage,
-- not a placeholder box - the samples came back as empty lines while the ASCII
-- one read fine. So NAMES ARE ASCII-ONLY, and the separate window is how they
-- get typed (decided over reading the PC keyboard, and over baking names into
-- PNGs to get Japanese back).
--
-- The samples are still drawn every frame. They are the evidence, and they
-- cost nothing to keep.
--
-- MEASURED 2026-09-16 (analysis/naming_probe_20260916_typing.log):
--   * The window comes up in front and typing works. Nine names went in and
--     came back byte for byte, ASCII and Japanese alike.
--   * Japanese survives the trip and then draws as an EMPTY ROW, confirmed on
--     screen. The name is still stored and still sorted on, so the real thing
--     has to reject it, strip it, or knowingly let it through. The probe counts
--     the non-ASCII bytes so that choice has a basis.
--   * Cancel is clean: status CANCELLED, the previous name untouched.
--   * A single press opened the box TWICE - see the guard below.
--
-- WHAT IS LEFT TO SETTLE:
--   * Does pre-filling work, for renaming rather than retyping? Hotkey 3 has
--     not been pressed yet.
--
-- Run INSTEAD of the training script:
--   analysis/run_naming_probe.bat        (double click)
--
-- What to do:
--   Lua Hotkey 1   Type an ASCII name, press Enter. The normal case.
--   Lua Hotkey 2   Type a JAPANESE name with the IME, press Enter. Expected:
--                  it comes back fine and then draws as an empty row. Seeing
--                  that is the point - it is what a user would hit by accident.
--   Lua Hotkey 3   Rename - the box comes up pre-filled. Edit it, press Enter.
--   Lua Hotkey 4   Open it and press ESCAPE. Expected: "cancelled", no change.
--
-- After each one the result is drawn back on screen through gui.text, which is
-- the same path a real pattern name would take. Say what you see there, not
-- only what you typed - the two disagreeing IS the finding.
--
-- Everything also goes to analysis/naming_probe.log.

local LOG = "naming_probe.log"
local PATH_OUT = "naming_probe_out.txt"

local lines = {}
local busy_note = nil
local last_name = ""
local last_status = "(nothing yet)"

local function log(s)
	lines[#lines + 1] = s
	if #lines > 8 then table.remove(lines, 1) end
	local f = io.open(LOG, "a")
	if f ~= nil then
		f:write(s .. "\n")
		f:close()
	end
end

local function bytes_of(s, limit)
	if s == nil then return "nil" end
	local out = {}
	for i = 1, math.min(#s, limit or 24) do
		out[#out + 1] = string.format("%02X", s:byte(i))
	end
	return table.concat(out, " ")
end

local function trim(s)
	if s == nil then return nil end
	s = s:gsub("^\239\187\191", "")
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function read_file(path)
	local f = io.open(path, "r")
	if f == nil then return nil end
	local s = f:read("*a")
	f:close()
	return s
end

-- Found rather than assumed: FBNeo resolves a relative path against the Lua
-- script's own folder, not the launching .bat's cd target.
local PS1 = nil
local function find_ps1()
	if PS1 ~= nil then return PS1 end
	for _, cand in ipairs({ "naming_probe.ps1", "analysis/naming_probe.ps1",
	                        "../analysis/naming_probe.ps1" }) do
		local f = io.open(cand, "r")
		if f ~= nil then
			f:close()
			PS1 = cand
			log("   using " .. cand)
			return PS1
		end
	end
	return nil
end

local function run(cmd)
	if io.popen == nil then return nil, "io.popen does not exist in this build" end
	local t0 = os.clock()
	local f = io.popen(cmd, "r")
	if f == nil then return nil, "io.popen returned nil" end
	local ok, out = pcall(function() return f:read("*a") end)
	f:close()
	log(string.format("   stalled %.2fs", os.clock() - t0))
	if not ok then return nil, "read failed: " .. tostring(out) end
	return out, nil
end

-- mode is "new" or "rename"; initial pre-fills the box.
local function ask_for_name(mode, initial)
	local ps1 = find_ps1()
	if ps1 == nil then
		log("   NG naming_probe.ps1 not found from the working directory")
		return "ERROR: no script"
	end
	os.remove(PATH_OUT)
	-- 2>&1 so a PowerShell failure reaches stdout instead of dying on stderr
	-- where io.popen cannot see it.
	local cmd = 'powershell -NoProfile -STA -ExecutionPolicy Bypass -File "'
		.. ps1 .. '" ' .. mode .. ' "' .. PATH_OUT .. '" "' .. (initial or "") .. '" 2>&1'
	local out, err = run(cmd)
	if err ~= nil then
		log("   NG " .. err)
		return "ERROR: " .. err
	end

	local body = read_file(PATH_OUT)
	if body == nil then
		log("   NG PowerShell wrote nothing")
		log("   stdout [" .. tostring(trim(out)) .. "]")
		return "ERROR: no output file"
	end

	local status, text, nbytes = body:match("^([^\n]*)\n([^\n]*)\n([^\n]*)")
	status = trim(status) or ""
	text = text or ""
	log("   status [" .. status .. "]")
	log("   text   [" .. text .. "]")
	-- The bytes are the finding. An ASCII name is one byte per character; a
	-- Japanese one is three, and gui.text is about to be handed all of them.
	log("   bytes  " .. bytes_of(text))
	log("   len    " .. #text .. " bytes, ps says " .. tostring(nbytes))

	-- NAMES ARE ASCII-ONLY, decided 2026-09-16 once gui.text was measured
	-- drawing nothing at all for kana and kanji. Nothing stops a person typing
	-- Japanese into the box anyway, and the result would be a name that is
	-- stored, sorted and matched on but shows up as an empty row. So the count
	-- is reported here: it decides whether the real thing rejects the name,
	-- strips it, or lets it through.
	--
	-- ONLY WHEN THERE IS A NAME TO CHECK. A cancel carries an empty string, and
	-- running the check on it printed "ASCII only - this one can be drawn"
	-- under every cancelled attempt in the first two logs. Harmless there, but
	-- the real thing must not validate a name the user just declined to give.
	if status == "OK" then
		local bad = 0
		for i = 1, #text do
			if text:byte(i) > 127 then bad = bad + 1 end
		end
		if bad == 0 then
			log("   ASCII only - this one can be drawn")
		else
			log("   " .. bad .. " non-ASCII bytes - WILL DRAW AS BLANK")
		end
	end
	return status, text
end

local function name_it(mode, initial, label)
	log("[" .. label .. "]")
	local status, text = ask_for_name(mode, initial)
	last_status = status
	if status == "OK" then
		last_name = text
		log("   OK name is now [" .. text .. "]")
	elseif status == "CANCELLED" then
		log("   cancelled (not a fault) - name left as [" .. last_name .. "]")
	else
		log("   NG " .. tostring(status))
	end
end

-- ONE PRESS MUST NOT OPEN TWO WINDOWS.
--
-- A Lua hotkey is called for every frame the key is HELD - about 38 times for
-- one press, which CLAUDE.md has warned about since v11.5 and which this probe
-- ignored. The first run opened the box twice from a single press: the job
-- blocks inside the frame callback, FBNeo delivers the still-held key again
-- when it returns, and a second window comes up on top of a name that was just
-- set (analysis/naming_probe_20260916_typing.log, two "stalled" blocks under
-- one header).
--
-- Same 15-frame guard the menu rows use (menu.lua:1335). Frames do not advance
-- while the window is open, so on return the counter is still within the
-- window and the repeat is swallowed - which is exactly what is wanted.
local pending = nil
local last_fired = nil
local function arm(job)
	if last_fired ~= nil and emu.framecount() - last_fired < 15 then return end
	last_fired = emu.framecount()
	pending = job
end

input.registerhotkey(1, function() arm(function() name_it("new", "", "1 ASCII name") end) end)
input.registerhotkey(2, function() arm(function() name_it("new", "", "2 Japanese name") end) end)
input.registerhotkey(3, function()
	arm(function()
		name_it("rename", last_name ~= "" and last_name or "pattern_1", "3 rename, pre-filled")
	end)
end)
input.registerhotkey(4, function() arm(function() name_it("new", "", "4 cancel test") end) end)

-- Published so test_probe_smoke.lua can see an error this pcall swallowed.
probe_error = nil

emu.registerbefore(function()
	if pending ~= nil then
		local job = pending
		pending = nil
		busy_note = "window is open - the emulator is stopped"
		local ok, e = pcall(job)
		if not ok then
			probe_error = tostring(e)
			log("   NG lua error: " .. tostring(e))
		end
		busy_note = nil
	end
end)

-- THE FONT TEST, drawn from frame one and needing no input at all. If the
-- Japanese lines come out blank or as garbage then gui.text is ASCII-only and
-- no amount of clever input changes that.
local SAMPLES = {
	"ASCII    : Bishamon UBK setup 01",
	"Hiragana : \227\129\130\227\129\132\227\129\134",
	"Katakana : \227\130\162\227\130\164\227\130\166",
	"Kanji    : \230\162\133\230\154\151\229\133\165\229\138\155",
}

gui.register(function()
	gui.text(4, 4, "NAMING PROBE  1=ascii 2=jp 3=rename 4=cancel", 0xFFFFFFFF, 0x000000FF)
	gui.text(4, 14, "-- can gui.text draw these? --", 0xFFFF80FF, 0x000000FF)
	local y = 24
	for _, s in ipairs(SAMPLES) do
		gui.text(4, y, s, 0xFFFFFFFF, 0x000000FF)
		y = y + 8
	end
	y = y + 4
	-- The returned name through the same drawing path a real one would take.
	gui.text(4, y, "status: " .. last_status, 0x80C0FFFF, 0x000000FF)
	gui.text(4, y + 8, "name  : [" .. last_name .. "]", 0x80FF80FF, 0x000000FF)
	y = y + 20
	if busy_note ~= nil then
		gui.text(4, y, busy_note, 0xFFFF00FF, 0x000000FF)
		y = y + 8
	end
	for i = 1, #lines do
		gui.text(4, y, lines[i], 0xC0FFC0FF, 0x000000FF)
		y = y + 8
	end
end)

log("--- naming probe start ---")
log("io.popen " .. (io.popen ~= nil and "present" or "MISSING"))
