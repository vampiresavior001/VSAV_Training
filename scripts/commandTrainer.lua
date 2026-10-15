-- COMMAND TRAINER (Trainer tab, 2026-10-11).
--
-- One command at a time, picked on the Trainer tab's Command Trainer row: what
-- the game's own recognizer took, step by step (analysis/
-- COMMAND_TRAINER_DESIGN.ja.md, sections 5 and 7). P1 only. The rows come from
-- commandLog.lua's exec hooks; nothing here reads the inputs itself or guesses
-- what the game would accept.
--
-- What the panel says, from the recognizer measured on the machine
-- (VSAV_MEMORY_NOTES, section 9):
--   * A press counts only when it is exactly the step waited for: anything
--     else starting the same tick and the step is not taken (LK+F is not F).
--     The waiting goes on, so a right press later still counts. The last press
--     that was not taken is written beside the step.
--   * Each accepted step loads a timer T of 14 to 19 (half of them 14). The
--     next step is taken up to the (T-1)th call after it, so 13 calls always
--     get through and 14 or more only on the roll: those are drawn orange.
--     The number shown is ticks; the warning counts calls, which is what the
--     timer counts. While a command is waiting the two were the same in every
--     row measured.
--   * Expired: the timer ran out, counted from the last accepted step. The
--     step it was waiting for gets a red x; the ticks are on the result line.
--   * Not started: the command was complete but the move was not written -
--     the meter or the state test said no. The meter is always 99 in this
--     tool (vsavscriptv2.lua timer()), so it is the state.
--   * Interrupted: the block was cleared from outside (a hit, another state).
--
-- GC Command Trace's box, columns and colours, at the right: x 260-346 of
-- the box, under the PB Count line. At 210, where that trace sits, it lay over
-- Tick Data's lines (user's screenshots, 2026-10-11: Recovery 26t under it).
-- Here only Tick Data's longest lines reach it - a multi-hit move's Active
-- list, a long Action Timeline - and the P2 input column starts at 353
-- (vsavscriptv2.lua: screen width minus three icons). GC Command Trace stays
-- off while this panel is displayed (hud.lua): the two boxes would overlap. The result
-- stays until the next attempt's first step is taken.

local M = {}
local commandLog = require "./scripts/commandLog"

local P1 = 0xFF8400
local WARN_AT = 14            -- calls; 13 or fewer always get through
local ROW_H, CH = 11, 4.2     -- GC Command Trace's row height and glyph width
local NUM_R = 78              -- its right edge for the numbers
local BOX_W = NUM_R + CH + 2
local WHITE, GOLD, BAD, WARN = "#FFFFFF", "#FFD700", "#FF0000", "#FF7F00"

local trace = nil

function M.selected()
	local i = globals ~= nil and globals.options ~= nil and globals.options.command_trainer
	if type(i) ~= "number" then return nil end
	return commandLog.PROFILES[i - 1]
end

function M.reset() trace = nil end

-- Whether character id cid can do prof's command (Moment Slice: Gallon and
-- Dark Gallon, commandLog.lua).
function M.fits(prof, cid)
	if cid == prof.char then return true end
	for _, id in ipairs(prof.chars or {}) do
		if id == cid then return true end
	end
	return false
end

-- Share the visibility condition with GC Command Trace, so unsupported
-- characters do not hide both trainers.
function M.is_visible()
	local prof = M.selected()
	return prof ~= nil and M.fits(prof, memory.readbyte(P1 + 0x382))
end

-- THE ROW'S LEFT AND RIGHT STOP AT OFF AND P1'S OWN COMMANDS ONLY (user,
-- 2026-10-11): with ten commands, going round all of them to reach your
-- character's was the chore. The value is still the index into the whole
-- list (1 Off, then PROFILES), so a saved setting keeps its meaning (and
-- M.follow_p1 below moves it to the new character's command). v: the value
-- now, d: -1 or 1, cid: P1's character id. Off always fits, so this always
-- ends.
function M.step(v, d, cid)
	local n = #commandLog.PROFILES + 1
	if type(v) ~= "number" or v < 1 or v > n then v = 1 end
	for _ = 1, n do
		v = v + d
		if v < 1 then v = n elseif v > n then v = 1 end
		if v == 1 or M.fits(commandLog.PROFILES[v - 1], cid) then return v end
	end
	return 1
end

-- A CHANGE OF CHARACTER TAKES THE COMMAND WITH IT (user, 2026-10-11): on
-- Demitri the row turns to Midnight Pleasure. To the command last used for
-- that character since FBNeo started, else its first. A character with none
-- leaves the value alone and draws nothing, so going back brings it back.
-- Off stays Off. Called in a match only: on the select screen $382 can hold
-- a passing value.
local last_for_char = {}
function M.follow_p1(cid)
	local v = globals.options.command_trainer
	if type(v) ~= "number" or v <= 1 then return end
	local prof = commandLog.PROFILES[v - 1]
	if prof == nil then return end
	if M.fits(prof, cid) then
		last_for_char[cid] = v
		return
	end
	local want = last_for_char[cid]
	if want == nil then
		for i, p in ipairs(commandLog.PROFILES) do
			if M.fits(p, cid) then want = i + 1 break end
		end
	end
	if want ~= nil then
		globals.options.command_trainer = want
		trace = nil
	end
end

-- One row from commandLog.lua.
function M.on_row(r)
	local prof = M.selected()
	if prof == nil or r.p ~= 1 or r.cmd ~= prof.key then return end
	local n = #prof.steps
	if r.kind == "step" and r.step == 1 then
		trace = { cmd = prof.key, rows = { { t = r.tick, face = r.face } }, miss = {}, acc = 0 }
		return
	end
	local a = trace
	if a == nil or a.cmd ~= prof.key then return end
	if r.kind == "started" then
		if a.done == "pending" then a.done = "Success" end
		return
	end
	if a.done ~= nil then return end
	-- A row for a step whose step before it was never seen: the attempt began
	-- before the trainer was on. Not guessed at (design section 4).
	local prev = (r.kind == "step" or r.kind == "complete") and a.rows[r.step - 1] or nil
	if r.kind == "step" or r.kind == "complete" then
		if prev == nil then return end
		a.rows[r.step] = { t = r.tick, gap = r.tick - prev.t, calls = a.acc + r.calls, face = r.face }
		a.acc = 0
		if r.kind == "complete" or r.step == n then a.done, a.at = "pending", r.tick end
	elseif r.kind == "miss" then
		if r.step >= 2 then a.miss[r.step] = r.edge end
		a.acc = a.acc + r.calls
	elseif r.kind == "expired" then
		a.done, a.at, a.waiting = "Expired", r.tick, r.step
	elseif r.kind == "cleared" then
		a.done, a.at, a.waiting = "Interrupted", r.tick, r.step
	end
end

-- After the frame: both hooks of a completed command have run by now, so a
-- command still waiting for its start did not start.
function M.registerAfter()
	if trace ~= nil and trace.done == "pending" then trace.done = "Not started" end
	if globals ~= nil and globals.options ~= nil and globals.match_running ~= nil
	   and globals.match_running() == true then
		M.follow_p1(memory.readbyte(P1 + 0x382))
	end
	local prof = M.selected()
	if trace ~= nil and (prof == nil or trace.cmd ~= prof.key) then trace = nil end
end

function M.registerStart()
	commandLog.set_listener(M.on_row, function() return M.selected() ~= nil end)
end

-- For analysis/test_command_trainer.lua.
function M._trace() return trace end

-- ---------------------------------------------------------------------------
-- Drawing. The input viewer's images (inputHistory.lua's globals) and the
-- orange ones GC Command Trace uses for a late input - loaded on the first
-- draw, since gd comes from inputHistory.lua's require and this file may load
-- first. A missing file costs the orange and nothing else.
local warn_img = nil
local function load_warn_images()
	warn_img = {}
	if gd == nil then return end
	for _, d in ipairs({ 2, 4, 6, 8 }) do
		local im = gd.createFromPng("images/" .. d .. "_dir_warn.png")
		if im ~= nil then warn_img[d] = im:gdStr() end
	end
	local im = gd.createFromPng("images/no_button_warn.png")
	if im ~= nil then warn_img.no_button = im:gdStr() end
end

local BUTTONS = { 0x0100, 0x0200, 0x0400, 0x1000, 0x2000, 0x4000 }
local KEYS = { { 0x0100, "LP" }, { 0x0200, "MP" }, { 0x0400, "HP" }, { 0x1000, "LK" },
               { 0x2000, "MK" }, { 0x4000, "HK" }, { 0x0002, "F" }, { 0x0001, "B" },
               { 0x0008, "U" }, { 0x0004, "D" } }

-- An edge word as text: LK+F. F and B are toward and away from the opponent.
function M.keys(w)
	local out = {}
	for _, k in ipairs(KEYS) do
		if w % (k[1] * 2) >= k[1] then out[#out + 1] = k[2] end
	end
	return table.concat(out, "+")
end

local function bit(w, b) return w % (b * 2) >= b end

-- The step's input: the button dots, or the arrow on the side it points to.
-- face: +$0B, 1 facing right.
local function draw_step(x, y, w, face, warn)
	if w % 0x10 ~= 0 then
		if img_dir == nil then return end
		local d = 5
		if bit(w, 0x0002) then d = (face == 1) and 6 or 4
		elseif bit(w, 0x0001) then d = (face == 1) and 4 or 6
		elseif bit(w, 0x0008) then d = 8
		elseif bit(w, 0x0004) then d = 2 end
		gui.image(x, y, (warn and warn_img[d]) or img_dir[d])
		return
	end
	if img_no_button == nil then return end
	local img = { img_L_button, img_M_button, img_H_button }
	local empty = (warn and warn_img.no_button) or img_no_button
	for i = 1, 3 do
		gui.image(x + (i - 1) * 5, y, bit(w, BUTTONS[i]) and img[i] or empty)
		gui.image(x + (i - 1) * 5, y + 5, bit(w, BUTTONS[i + 3]) and img[i] or empty)
	end
end

local function right(x, y, s, c)
	gui.text(math.floor(x + NUM_R - #s * CH + 0.5), y, s, c or WHITE)
end

function M.draw()
	local prof = M.selected()
	if prof == nil then return end
	-- NOTHING FOR A CHARACTER WITHOUT IT (user, 2026-10-11). It used to say "P1
	-- Morrigan only"; a character with a command of its own is switched to it
	-- by M.follow_p1, so what is left here is one with none, and a box saying
	-- so is clutter. The selection stays for when that character comes back.
	if not M.is_visible() then return end
	-- Not while Chain Trainer is on: its lines reach this box. The command is
	-- still followed, and the panel comes back when that is turned off.
	local _cht = package.loaded["./scripts/chainTrainer"]
	if type(_cht) == "table" and _cht.is_visible ~= nil and _cht.is_visible() then return end
	if warn_img == nil then load_warn_images() end
	-- hud.lua's blocks_top(): under the PB Count line, lower with the Guard
	-- Action Frequency Check on. x: see the note at the top.
	local x = 262
	local y = (globals.options.display_gc_freq_counter == true) and 50 or 38
	local n = #prof.steps
	local a = (trace ~= nil and trace.cmd == prof.key) and trace or nil
	local result = a ~= nil and a.done ~= nil and a.done ~= "pending"
	local lines = 1 + n + (result and 1 or 0)
	gui.box(x - 2, y - 1, x + BOX_W, y + lines * ROW_H + 1, "#00000099", "#00000055")
	gui.text(x + 2, y + 2, prof.name, WHITE)
	local face = memory.readbyte(P1 + 0x0B)
	-- The step being waited for, or the one the attempt ended on.
	local next_k = nil
	if a ~= nil then
		next_k = a.waiting
		if next_k == nil then
			for k = 1, n do if a.rows[k] == nil then next_k = k break end end
		end
	end
	for k = 1, n do
		local ry = y + k * ROW_H
		local row = a and a.rows[k]
		local warn = row ~= nil and row.calls ~= nil and row.calls >= WARN_AT
		draw_step(x + 2, ry, prof.steps[k], (row and row.face) or (a and a.rows[1] and a.rows[1].face) or face, warn)
		if row ~= nil and row.gap ~= nil then
			right(x, ry + 2, row.gap .. "t", warn and WARN or nil)
		end
		-- THE STEP THE ATTEMPT DIED ON GETS A RED x, NOT A NUMBER (user,
		-- 2026-10-11). A row's number is always the time to an input that was
		-- taken; how long the dead step was waited for is the result line's.
		-- Without the mark, one LP and an expiry drew rows 1 and 2 alike.
		local tx = x + 18
		if a ~= nil and k == a.waiting and (a.done == "Expired" or a.done == "Interrupted") then
			gui.text(tx, ry + 2, "x", BAD)
			tx = tx + 2 * CH
		end
		local miss = a and a.miss[k]
		if miss ~= nil then
			gui.text(tx, ry + 2, M.keys(miss), (row ~= nil) and WARN or BAD)
		end
		-- Past the step waited for: dimmed, not yet in play.
		if a ~= nil and row == nil and next_k ~= nil and k > next_k then
			gui.box(x + 1, ry, x + 16, ry + 10, "#000000BB", "#000000BB")
		end
	end
	if result then
		local ry = y + (n + 1) * ROW_H + 2
		if a.done == "Success" then
			gui.text(x + 2, ry, "Success", GOLD)
			right(x, ry, (a.rows[n].t - a.rows[1].t) .. "t", GOLD)
		elseif a.done == "Expired" then
			gui.text(x + 2, ry, "Expired", BAD)
			local last = a.rows[(a.waiting or 2) - 1]
			if last ~= nil then right(x, ry, (a.at - last.t) .. "t", BAD) end
		elseif a.done == "Not started" then
			gui.text(x + 2, ry, "Not started", WARN)
		else
			gui.text(x + 2, ry, a.done, BAD)
		end
	end
end

return M
