-- CAN THE TOOL OPEN A REAL WINDOWS FILE DIALOG, AND SURVIVE IT?
--
-- Action Patterns needs import/export. A fixed folder plus a name typed into
-- the menu would work, but a native Save/Open dialog is what anyone sharing a
-- pattern file actually expects. FBNeo's Lua has no such call, so the only way
-- is to run something outside: io.popen -> PowerShell -> System.Windows.Forms.
--
-- WHAT IS ALREADY KNOWN. macro.lua:15 calls io.popen("dir ...") at load time,
-- which proves the function EXISTS and does not throw. It never reads the
-- handle, so it proves nothing about the output coming back.
--
-- WHAT THIS HAS TO SETTLE, because every one of them can kill the idea:
--
--   1. Is io.popen's output readable? f:read("*a") may return nil or "".
--   2. Does the dialog come to the FRONT? FBNeo draws through DirectX; a
--      dialog opening behind it is indistinguishable from a hang, because the
--      emulator is blocked on a click nobody can see. dialog_probe.ps1 owns
--      the dialog with an invisible top-most form to force the issue.
--   3. How long is the emulator frozen? io.popen is synchronous and this runs
--      on the emulator thread, so EVERYTHING stops until the dialog closes.
--      Acceptable for an explicit menu action, fatal if it also hangs audio
--      or leaves the game desynced afterwards.
--   4. Do non-ASCII paths survive? A path through the Desktop is already
--      "C:\Users\...\デスクトップ\...".
--   5. Is Cancel distinguishable from failure? Both look like "no path".
--
-- WHAT IS SETTLED SO FAR (2026-09-16):
--
--   1. YES. io.popen's stdout is readable. Spawning costs about 0.38s even
--      for "cmd /c echo", which is the floor for any of this.
--   2. YES. The owned top-most form brings the dialog in front.
--   3. The emulator is frozen for exactly as long as the dialog is open -
--      measured at 39s on a slow pick - and came back fine afterwards.
--      Fine for an explicit menu action, unusable for anything repeated.
--   4. NOT through a returned path. Lua 5.1 on Windows opens files through
--      the ANSI API: the same file handed over as a UTF-8 path returned nil
--      from io.open and as cp932 opened fine. So Lua no longer sees the
--      chosen path at all - it stages bytes at an ASCII path of its own and
--      PowerShell copies to or from the chosen file. Still to confirm on
--      real hardware, which is what the Japanese-folder run below is for.
--   5. Still open - a Cancel has not been pressed yet. The status word on
--      line 1 of the output file now says CANCELLED outright.
--
-- Run INSTEAD of the training script:
--   analysis/run_dialog_probe.bat        (double click)
--
-- What to do, once the game is up:
--   Lua Hotkey 1   plain io.popen, no dialog. Settles (1) on its own, so a
--                  failure later can be blamed on the right half.
--   Lua Hotkey 2   Export. A Save dialog opens; pick any name and save.
--                  Do it a SECOND time into a folder with Japanese in the
--                  path (the Desktop) - that is the case (4) is about.
--                  Do it a THIRD time and press Cancel.
--   Lua Hotkey 3   Import. An Open dialog; pick the file hotkey 2 wrote.
--
-- After each one, keep playing for a few seconds. The question is not only
-- whether the dialog worked but whether the emulator came back.
--
-- Everything also goes to analysis/dialog_probe.log - FBNeo resolves a relative
-- io.open against the LUA SCRIPT'S folder, not the launching .bat's cd target.

local LOG = "dialog_probe.log"
local PATH_OUT = "dialog_probe_out.txt"
-- Where Lua stages the bytes. Deliberately ASCII and deliberately beside the
-- script: this is the one path io.open has to cope with, so it must never
-- inherit whatever the user picked in the dialog.
local PAYLOAD = "dialog_probe_payload.json"

local lines = {}
local busy_note = nil

local function log(s)
	lines[#lines + 1] = s
	if #lines > 10 then table.remove(lines, 1) end
	local f = io.open(LOG, "a")
	if f ~= nil then
		f:write(s .. "\n")
		f:close()
	end
end

-- Printable form of a string's bytes, for the encoding question. A path that
-- came back mangled looks fine on screen and only shows up here.
local function bytes_of(s, limit)
	if s == nil then return "nil" end
	local out = {}
	for i = 1, math.min(#s, limit or 16) do
		out[#out + 1] = string.format("%02X", s:byte(i))
	end
	return table.concat(out, " ")
end

local function trim(s)
	if s == nil then return nil end
	-- A UTF-8 BOM would ride in front of the path and io.open would then be
	-- handed a name that does not exist.
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

-- WHERE THE .ps1 IS, found rather than assumed.
--
-- This was hardcoded to "analysis/dialog_probe.ps1" on the first run and did
-- not resolve: FBNeo's working directory is the LUA SCRIPT'S OWN FOLDER, not
-- the directory the launching .bat cd'd to. The proof is this very log, which
-- is opened as a bare "dialog_probe.log" and landed in analysis/; the same
-- rule puts autoguard.lua's "reversal_logs/..." under scripts/.
--
-- Forward slashes throughout: the string passes through cmd.exe before
-- PowerShell sees it, and backslashes would need escaping at both layers.
local PS1 = nil
local function find_ps1()
	if PS1 ~= nil then return PS1 end
	for _, cand in ipairs({ "dialog_probe.ps1", "analysis/dialog_probe.ps1",
	                        "../analysis/dialog_probe.ps1" }) do
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

-- os.clock() is CPU time by the C standard but WALL time in the MSVC runtime,
-- which is what this needs: the process is blocked, not spinning. os.time()
-- is logged next to it as a second opinion at 1s resolution, so a surprise
-- here is visible rather than silently wrong.
local function run(cmd)
	if io.popen == nil then
		return nil, "io.popen does not exist in this build", 0
	end
	local t0, s0 = os.clock(), os.time()
	local f = io.popen(cmd, "r")
	if f == nil then
		return nil, "io.popen returned nil", os.clock() - t0
	end
	local ok, out = pcall(function() return f:read("*a") end)
	f:close()
	local elapsed = os.clock() - t0
	log(string.format("   stalled %.2fs (os.time delta %ds)", elapsed, os.time() - s0))
	if not ok then
		return nil, "read failed: " .. tostring(out), elapsed
	end
	return out, nil, elapsed
end

-- (1) No dialog at all, so a failure here is io.popen and nothing else.
local function probe_popen()
	log("[1] io.popen raw")
	local out, err = run('cmd /c echo VSAV_POPEN_OK')
	if err ~= nil then
		log("   NG " .. err)
		return
	end
	log("   got [" .. tostring(trim(out)) .. "]")
	if trim(out) == "VSAV_POPEN_OK" then
		log("   OK stdout is readable")
	else
		log("   NG stdout did not come back")
	end
end

-- Runs the dialog and lets PowerShell do the copy. Returns status, path, size.
--
-- The path comes back for DISPLAY ONLY - never pass it to io.open. Lua 5.1 on
-- Windows opens files through the ANSI API, so a UTF-8 path returns nil and a
-- cp932 one works; measured both ways offline. Staging at an ASCII path and
-- letting PowerShell copy is what makes a Japanese folder a non-event, and it
-- also covers the paths cp932 cannot spell at all.
local function ask(mode)
	local ps1 = find_ps1()
	if ps1 == nil then
		log("   NG dialog_probe.ps1 not found from the working directory")
		return "ERROR: no script"
	end
	os.remove(PATH_OUT)
	-- 2>&1 MATTERS. Without it the first run was unreadable: PowerShell put
	-- "the argument to -File does not exist" on stderr, which io.popen never
	-- sees, and the only thing reaching stdout was its interactive banner.
	-- The banner is not an error message, so the probe reported "it did not
	-- run" without being able to say why.
	local cmd = 'powershell -NoProfile -STA -ExecutionPolicy Bypass -File "'
		.. ps1 .. '" ' .. mode .. ' "' .. PATH_OUT .. '" "' .. PAYLOAD .. '" 2>&1'
	local out, err = run(cmd)
	if err ~= nil then
		log("   NG " .. err)
		return "ERROR: " .. err
	end

	local body = read_file(PATH_OUT)
	if body == nil then
		log("   NG PowerShell never wrote the file - it did not run")
		log("   stdout [" .. tostring(trim(out)) .. "]")
		return "ERROR: no output file"
	end

	local status, path, size = body:match("^([^\n]*)\n([^\n]*)\n([^\n]*)")
	status = trim(status) or ""
	path = trim(path) or ""
	log("   status [" .. status .. "]")
	log("   path   [" .. path .. "]")
	-- The bytes are the encoding question made visible. A Japanese folder
	-- shows up here as 3-byte runs starting E3/E6/etc; if it ever came back
	-- as 2-byte cp932 instead, everything downstream would need rethinking.
	log("   bytes  " .. bytes_of(path, 24))
	log("   size   " .. tostring(size))
	return status, path, tonumber(size) or 0
end

-- (2) Export: stage the bytes at an ASCII path, dialog, PowerShell copies.
local function probe_export()
	log("[2] Export (SaveFileDialog)")
	local body = '{"probe":"dialog","patterns":[{"name":"test","steps":[]}]}'
	local f = io.open(PAYLOAD, "w")
	if f == nil then
		log("   NG cannot stage at " .. PAYLOAD)
		return
	end
	f:write(body)
	f:close()

	local status, path, size = ask("save")
	if status == "CANCELLED" then
		log("   cancelled (not a fault)")
		return
	end
	if status ~= "OK" then
		log("   NG " .. tostring(status))
		return
	end
	-- Size is checked rather than content: reading the destination back would
	-- mean io.open on the very path this design avoids touching.
	if size == #body then
		log("   OK copied " .. size .. " bytes to the chosen file")
	else
		log("   NG size mismatch, wrote " .. #body .. " got " .. tostring(size))
	end
end

-- (3) Import: dialog, PowerShell copies to the staging path, Lua reads that.
local function probe_import()
	log("[3] Import (OpenFileDialog)")
	os.remove(PAYLOAD)

	local status, path, size = ask("open")
	if status == "CANCELLED" then
		log("   cancelled (not a fault)")
		return
	end
	if status ~= "OK" then
		log("   NG " .. tostring(status))
		return
	end

	local body = read_file(PAYLOAD)
	if body == nil then
		log("   NG nothing staged at " .. PAYLOAD)
		return
	end
	log("   OK read " .. #body .. " bytes through the staging file")
	log("   head [" .. body:sub(1, 48) .. "]")
end

-- The hotkeys must not do the work themselves. A callback that blocks for as
-- long as a dialog is open runs inside FBNeo's key handling; the flag defers
-- it to the frame callback, which is where the emulator expects to lose time.
local pending = nil
input.registerhotkey(1, function() pending = probe_popen end)
input.registerhotkey(2, function() pending = probe_export end)
input.registerhotkey(3, function() pending = probe_import end)

-- A broken job must not end the session - the point is to keep pressing keys
-- and comparing what comes back. But the pcall that buys that also HIDES the
-- undefined global test_probe_smoke.lua exists to catch: a mutation that put
-- no_such_function() into probe_export was caught by nothing at all. So the
-- error is published here as well. The smoke test asserts probe_error stays
-- nil after every hotkey; probes that never set it are unaffected.
probe_error = nil

emu.registerbefore(function()
	if pending ~= nil then
		local job = pending
		pending = nil
		busy_note = "working..."
		local ok, e = pcall(job)
		if not ok then
			probe_error = tostring(e)
			log("   NG lua error: " .. tostring(e))
		end
		busy_note = nil
	end
end)

gui.register(function()
	gui.text(4, 4, "DIALOG PROBE   1=popen  2=export  3=import", 0xFFFFFFFF, 0x000000FF)
	if busy_note ~= nil then
		gui.text(4, 12, busy_note, 0xFFFF00FF, 0x000000FF)
	end
	local y = 22
	for i = 1, #lines do
		gui.text(4, y, lines[i], 0xC0FFC0FF, 0x000000FF)
		y = y + 8
	end
end)

log("--- dialog probe start ---")
log("io.popen " .. (io.popen ~= nil and "present" or "MISSING"))
