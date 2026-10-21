-- THE GAME STANDS STILL WHILE THE MENU IS OPEN (v11.7.28; survey
-- MENU_GAME_FREEZE_ROM_SURVEY, user 2026-10-16: "２をやってから公開したい").
--
-- Until now opening the menu only took both players' inputs away: the game ran
-- on under it - the round timer, the dummy's recovery, projectiles. Pausing
-- FBNeo itself would stop the Lua frame callbacks and the pad the menu is read
-- from. So the game is stopped from inside instead, at its own task manager,
-- and FBNeo keeps running: the menu reads the pad (joypad.get) as before, the
-- screen keeps the last picture, and the music plays on.
--
-- THE TASK MANAGER (ROM, analysis/mame_code c00.txt):
--   0011A4  a pass: clear the vblank flag (-$7B9C,A5); A0 = the 16 task
--           records (-$7DA4,A5 = 0xFF025C, 0x20 bytes each), D0 = 15
--   0011BA  each record's state byte: 4 or more runs the task (0011D6), less
--           skips it (0011C2). Then jsr 001520 (constants) and the next pass
--   001350  in the vblank interrupt: each record in state 1 counts its wait
--           down (+1) and goes to 4 at 0. Skipped too, or the waits would run
--           out while the game stands and every task wake at once after
--   008E10  the match's own task adds 1 to the Tick (0xFF8081) - so a Tick
--           that does not move is the proof that it holds
-- Neither is changed in RAM: A0 is pointed elsewhere for the pass, at
-- 0011AC (after the lea, once a pass) and 001354 (once a frame). EMPTY is 0x400
-- zero bytes of the ROM, so all 16 records read state 0: no task runs, no wait
-- counts, and nothing is written (a state 0 is never written to; ROM would not
-- take it anyway). A savestate taken while it stands is the game as it was -
-- no frozen record is saved into it. Only registers, written from exec hooks
-- as stage-select.lua and idleSound.lua already do.
--
-- WHEN: the menu open, in a match, and no position move in progress (it
-- needs the game to run to land; it stands again once it has). Lua's frame
-- callbacks keep running: the game's RAM does not change under them.
--
-- THE CHECK: frozen, the Tick must not move after the first frame (that one
-- may finish the pass that was running), and neither may either character -
-- its state ($04-$07), X ($10), Y ($14), cel ($1C) and what is left of the
-- cel ($20), none of which the Lua side writes while it stands. If any moves,
-- the hooks do not hold on this build: it is switched off for the session,
-- with a message. The Tick alone was not proof enough (review of 7643e09).
--
-- WHAT DID CHANGE (Knockdown Logger only, reversal_logs/freeze_log.jsonl):
-- the whole work RAM (0xFF0000, 64 KB) read once the first frame has passed
-- and again on the frame the menu closes, before the game runs it, and the
-- addresses that differ written as ranges. The vblank interrupt is not
-- stopped - its frame counter (0xFF8080) and input reads go on - and the
-- tool's own writes show here too; the log says which they are, rather than
-- the code assuming it. A check that fails writes its row at once, with why
-- (review of 328c706: that is the row worth having most).

local M = {}

M.PC = { tasks = 0x0011AC, waits = 0x001354 }
M.EMPTY = 0x0B8540
M.EMPTY_LEN = 0x200          -- 16 records of 0x20

local frozen = false
local broken = nil           -- why it was switched off, if it was
local frozen_frames, tick_at = 0, nil
local checked = nil          -- EMPTY read back as zeros (once)
local chars_at = nil         -- the two characters once the first frame has passed
local ram_at = nil           -- the work RAM then (logging only)
local tick_first = nil       -- the Tick the freeze held at

-- The two characters' fields the game moves and the tool does not write.
local FIELDS = { { 0x04, 4 }, { 0x10, 2 }, { 0x14, 2 }, { 0x1C, 4 }, { 0x20, 1 } }
local function chars()
	local out = {}
	for _, base in ipairs({ 0xFF8400, 0xFF8800 }) do
		for _, f in ipairs(FIELDS) do
			local v = 0
			for i = 0, f[2] - 1 do v = v * 256 + memory.readbyte(base + f[1] + i) end
			out[#out + 1] = v
		end
	end
	return table.concat(out, ",")
end

local LOG = "reversal_logs/freeze_log.jsonl"
local started_log = false
local function logging()
	return globals ~= nil and globals.options ~= nil and globals.options.knockdown_logger_enable == true
end
local function read_ram()
	local t = {}
	for i = 0, 0xFFFF do t[i + 1] = string.char(memory.readbyte(0xFF0000 + i) % 256) end
	return table.concat(t)
end
-- The addresses that differ, as "FFxxxx" or "FFxxxx-FFyyyy", runs closer than
-- 4 bytes joined; at most 200.
local function ranges(a, b)
	local out, i, n = {}, 1, #a
	while i <= n and #out < 200 do
		if a:byte(i) ~= b:byte(i) then
			local j, last = i, i
			while j <= n and j - last <= 4 do
				if a:byte(j) ~= b:byte(j) then last = j end
				j = j + 1
			end
			local lo, hi = 0xFF0000 + i - 1, 0xFF0000 + last - 1
			out[#out + 1] = lo == hi and string.format("%06X", lo) or string.format("%06X-%06X", lo, hi)
			i = last + 1
		else
			i = i + 1
		end
	end
	return out
end
local function write_row(text)
	local f = io.open(LOG, started_log and "a" or "w")
	if f == nil then return end
	if not started_log then
		f:write('{"log": "freeze_log", "version": 2, "what": "the work RAM (0xFF0000-0xFFFFFF) read once a menu freeze had held one frame and again on the frame it ended, before the game ran it, or after the frame a check failed on (scripts/gameFreeze.lua)", '
			.. '"fields": "frames: frames frozen; tick: the Tick it held at; gave_up: why the check failed (only on such a row); changed: the addresses that differ (runs within 4 bytes joined, at most 200)"}\n')
		started_log = true
	end
	f:write(text)
	f:close()
end
-- One row: what differs from the RAM read after the first frame.
local function write_diff(why)
	local q = {}
	for _, r in ipairs(ranges(ram_at, read_ram())) do q[#q + 1] = '"' .. r .. '"' end
	write_row(string.format('{"frames": %d, "tick": %d, %s"changed": [%s]}\n', frozen_frames, tick_first or -1,
		why and ('"gave_up": "' .. why .. '", ') or "", table.concat(q, ", ")))
end

local function say(text)
	if emu ~= nil and emu.message ~= nil then emu.message(text) end
	print(text)
end

-- THE NOTICE AGAIN, UNDER RECORDING GUI (user, 2026-10-21). The emulator's
-- message line does not show in Fightcade's FBNeo, so the give-up notice is
-- handed to macro.lua's hold_message as well - once the menu has closed: it is
-- said with the menu open, and the box it is drawn under (Display > Recording
-- GUI, hud.lua) is behind the menu until then.
local notice = nil

function M.on_tasks()
	if frozen then memory.setregister("m68000.a0", M.EMPTY) end
end
function M.on_waits()
	if frozen then memory.setregister("m68000.a0", M.EMPTY) end
end

function M.registerStart()
	memory.registerexec(M.PC.tasks, M.on_tasks)
	memory.registerexec(M.PC.waits, M.on_waits)
end

-- EMPTY is what the build's ROM says it is: every record's state byte 0.
local function empty_ok()
	if checked == nil then
		checked = true
		for k = 0, 15 do
			if memory.readbyte(M.EMPTY + 0x20 * k) ~= 0 or memory.readbyte(M.EMPTY + 0x20 * k + 1) ~= 0 then
				checked = false
			end
		end
	end
	return checked
end

function M.wanted()
	if broken ~= nil then return false end
	if globals == nil or globals.show_menu ~= true then return false end
	if globals.match_running ~= nil and not globals.match_running() then return false end
	if positionModule ~= nil and positionModule.busy ~= nil and positionModule.busy() then return false end
	return empty_ok()
end

-- Before each frame: whether this frame stands. On the frame it stops
-- standing, before the game runs it, what changed under it goes to the log.
function M.registerBefore()
	if notice ~= nil and (globals == nil or globals.show_menu ~= true) then
		local mac = globals ~= nil and globals.macroLua or nil
		if mac ~= nil and mac.hold_message ~= nil then mac.hold_message(notice) end
		notice = nil
	end
	local want = M.wanted()
	if want and not frozen then
		frozen_frames, tick_at, chars_at, ram_at, tick_first = 0, memory.readbyte(0xFF8081), nil, nil, nil
	end
	if frozen and not want and ram_at ~= nil then
		write_diff(nil)
		ram_at = nil
	end
	frozen = want
end

local function give_up(why)
	frozen = false
	broken = why
	if ram_at ~= nil then write_diff(why) end
	ram_at = nil
	say("Menu: the game could not be stopped (" .. broken .. ") - it runs under the menu this session")
	notice = "Menu: the game could not be stopped - it runs under the menu this session"
end

-- After it: the checks. Not on a frame that ended the freeze from the Lua
-- side - the menu closed, or a position move started from it - since that
-- frame's own writes are the tool's, not the game's.
function M.registerAfter()
	if not frozen then return end
	if not M.wanted() then return end
	frozen_frames = frozen_frames + 1
	local tick = memory.readbyte(0xFF8081)
	if frozen_frames == 1 then
		tick_at, tick_first, chars_at = tick, tick, chars()
		if logging() then ram_at = read_ram() end
		return
	end
	if tick ~= tick_at then give_up("the Tick moved") return end
	if chars() ~= chars_at then give_up("a character moved") end
end

-- A state was loaded (master's savestate.registerload; Restore State closes
-- the menu and loads). The game is another one now: nothing to check against,
-- and no row - what changed is the state, not the freeze.
function M.after_load()
	frozen, frozen_frames, tick_at, chars_at, ram_at, tick_first = false, 0, nil, nil, nil, nil
end

function M.frozen() return frozen end
function M.broken() return broken end

-- For analysis/test_game_freeze.lua.
function M._reset()
	frozen, broken, frozen_frames, tick_at, checked = false, nil, 0, nil, nil
	chars_at, ram_at, tick_first, notice = nil, nil, nil, nil
end
M._ranges = ranges

return M
