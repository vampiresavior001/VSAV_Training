-- DOES THE GUARD CANCEL LAND ON THE TICK OF A PRESS OR A RELEASE?
--
-- The input bar draws SUCCESS on the column the GC window closes on, and the
-- comment in inputHistory.lua claims the qualifying input - a press, a release
-- or the final direction - lands on that same frame. The bar is drawn from
-- emu.registerbefore, which only runs on DISPLAYED frames: at turbo 3 that is
-- 3 frames to 4 game ticks, so roughly one tick in four is never sampled and a
-- one-tick input can fall in the gap. v133 fixed this with a tick-side capture
-- and v135 removed it again as collateral while withdrawing something else.
--
-- So the on-screen position cannot answer the question. This logs the same
-- decision per TICK instead, and reports the gap in ticks between the last
-- button edge and the tick the cancel came out on.
--
-- WHERE THE EDGES COME FROM. guardCancel.lua already documents the per-object
-- input routine, which runs once per player per game tick:
--
--     022114: move.w ($122,A6), ($124,A6)   ; $124 := previous input
--     02211A: move.w ($394,A6), ($122,A6)   ; $122 := current input
--     0221B4: move.w D0, ($126,A6)          ; $126 := PRESS edge, this tick
--     0221C2: move.w D0, ($128,A6)          ; $128 := RELEASE edge, this tick
--     0221CC: move.b ($b,A6), D0            <- hooked here
--
-- Hooking at 0x0221CC means both edges already hold this tick's values.
--
-- THE SUCCESS TEST IS THE TOOL'S OWN, moved from frames to ticks. inputHistory
-- calls it a success when the block clock $158 reaches 0 while $06 is a
-- special (0x0E), an ES (0x10) or an EX (0x12).
--
-- Run INSTEAD of the training script:
--   analysis/run_gc_success_probe.bat        (double click)
--
-- What to do, once a round is up:
--   1. Set the dummy to attack so you have something to block.
--   2. Block, then input the guard cancel: DPF (6 2 3) + the button.
--   3. Do it eight or ten times. Include attempts you know were too late.
--   4. Deliberately complete one or two by RELEASING the button rather than
--      pressing it - the claim is that a release qualifies too.
--
-- What to look for on screen:
--   "last:" is the most recent attempt. The number after the arrow is the gap
--   in ticks between the last button edge and the cancel coming out. 0 means
--   the same tick. A run of 0s says the bar could draw SUCCESS on the right
--   column if it sampled every tick.
local LOG = "gc_success_probe.log"
local file = nil
local lines = 0

local P1 = 0xFF8400
local TICK = 0xFF8081

local BTN = { [0] = "LP", [1] = "MP", [2] = "HP", [4] = "LK", [5] = "MK", [6] = "HK" }
local BTN_ORDER = { 0, 1, 2, 4, 5, 6 }

-- $06 values inputHistory treats as "the cancel came out".
local CANCEL_STATE = { [0x0E] = "Special", [0x10] = "ES", [0x12] = "EX" }

local function bit(v, n)
	return (math.floor(v / 2 ^ n) % 2) >= 1
end

local function btn_names(mask)
	local out = ""
	for _, n in ipairs(BTN_ORDER) do
		if bit(mask, n) then out = out .. BTN[n] .. " " end
	end
	if out == "" then return "---" end
	return (out:gsub("%s+$", ""))
end

-- $125: bit0 forward, bit1 back, bit2 down, bit3 up. Written as the numpad
-- direction so a DPF reads as 6 2 3.
local function lever_name(v)
	local f, b, d, u = bit(v, 0), bit(v, 1), bit(v, 2), bit(v, 3)
	if d then
		if b then return "1" elseif f then return "3" else return "2" end
	elseif u then
		if b then return "7" elseif f then return "9" else return "8" end
	else
		if b then return "4" elseif f then return "6" else return "5" end
	end
end

local function write(s)
	if file == nil then file = io.open(LOG, "a") end
	if file then
		file:write(s .. "\n")
		file:flush()
		lines = lines + 1
	end
end

-- Per-attempt state. An attempt starts when the block clock becomes non-zero
-- and ends on the tick it reaches zero again.
local open_tick = nil
local last_edge_tick = nil
local last_edge_what = nil
local prev_timer = 0
local prev_lever = nil
local attempts, successes = 0, 0
local last_summary = "(まだ 1 回も出ていない)"
local gaps = {}

memory.registerexec(0x0221CC, function()
	local a6 = memory.getregister("m68000.a6")
	if a6 ~= P1 then return end

	local t       = memory.readbyte(TICK)
	local press   = memory.readbyte(P1 + 0x126)
	local release = memory.readbyte(P1 + 0x128)
	local lever   = memory.readbyte(P1 + 0x125)
	local timer   = memory.readbyte(P1 + 0x158)
	local state   = memory.readbyte(P1 + 0x006)

	-- THE WINDOW OPENED.
	if timer > 0 and prev_timer == 0 then
		open_tick = t
		last_edge_tick, last_edge_what = nil, nil
		attempts = attempts + 1
		write(string.format("--- attempt %d  OPEN t=%d  $158=%02X", attempts, t, timer))
	end

	-- Inside the window, every edge and every lever change is worth a line.
	-- Outside it, nothing is logged: this is about one attempt at a time.
	if timer > 0 or open_tick ~= nil then
		local note = nil
		if press ~= 0 then
			last_edge_tick, last_edge_what = t, "press " .. btn_names(press)
			note = "PRESS   " .. btn_names(press)
		elseif release ~= 0 then
			last_edge_tick, last_edge_what = t, "release " .. btn_names(release)
			note = "RELEASE " .. btn_names(release)
		elseif lever ~= prev_lever then
			note = "lever   " .. lever_name(lever)
		end
		if note ~= nil then
			write(string.format("    t=%3d  %-16s $125=%s $158=%02X $06=%02X",
				t, note, lever_name(lever), timer, state))
		end
	end

	-- THE WINDOW CLOSED. Same test inputHistory makes, one tick at a time.
	if timer == 0 and prev_timer > 0 and open_tick ~= nil then
		local how = CANCEL_STATE[state]
		local gap = "n/a"
		if last_edge_tick ~= nil then
			-- The tick counter is a byte and wraps, so the difference is taken
			-- modulo 256 rather than subtracted straight.
			gap = tostring((t - last_edge_tick) % 256)
		end
		if how ~= nil then
			successes = successes + 1
			if last_edge_tick ~= nil then gaps[#gaps + 1] = (t - last_edge_tick) % 256 end
			last_summary = string.format("SUCCESS (%s)  %s -> +%s tick", how,
				last_edge_what or "エッジ無し", gap)
			write(string.format("    t=%3d  CLOSE  SUCCESS %-7s $06=%02X   last edge: %s (+%s tick)",
				t, how, state, last_edge_what or "none", gap))
		else
			last_summary = string.format("出なかった ($06=%02X)  %s -> +%s tick",
				state, last_edge_what or "エッジ無し", gap)
			write(string.format("    t=%3d  CLOSE  no cancel      $06=%02X   last edge: %s (+%s tick)",
				t, state, last_edge_what or "none", gap))
		end
		open_tick = nil
	end

	prev_timer = timer
	prev_lever = lever
end)

-- AND WHAT THE DISPLAY SIDE SEES, ON THE SAME LINES.
--
-- The tick stream above settles what the GAME does. It cannot say how far the
-- input bar is off, because the bar is built in emu.registerbefore - displayed
-- frames only - and computes its own press/release edges by comparing against
-- the PREVIOUS FRAME rather than the previous tick.
--
-- So the same three things are sampled again here, the way inputHistory.lua
-- samples them, and written into the same log with an "F" marker. Reading the
-- two streams side by side gives the answer the fix depends on: how many
-- COLUMNS lie between the edge the player made and the column SUCCESS lands
-- on. One column is a different repair from three.
local f_prev_btn = nil
local f_prev_timer = 0
local f_gc_state = "none"
emu.registerbefore(function()
	local fr    = emu.framecount()
	local t     = memory.readbyte(TICK)
	local btn   = memory.readbyte(P1 + 0x122)
	local timer = memory.readbyte(P1 + 0x158)
	local state = memory.readbyte(P1 + 0x006)

	-- The edges the frame sampler would compute: this frame's buttons against
	-- the last frame's, with everything in between invisible to it.
	local f_press, f_release = 0, 0
	if f_prev_btn ~= nil then
		for _, n in ipairs(BTN_ORDER) do
			if bit(btn, n) and not bit(f_prev_btn, n) then f_press = f_press + 2 ^ n end
			if bit(f_prev_btn, n) and not bit(btn, n) then f_release = f_release + 2 ^ n end
		end
	end

	-- handle_gc_event()'s own transitions, unchanged.
	local note = nil
	if timer == 0 and f_gc_state == "in_progress" then
		if CANCEL_STATE[state] ~= nil then
			note = "F CLOSE SUCCESS " .. CANCEL_STATE[state]
			f_gc_state = "success"
		else
			note = "F CLOSE no cancel"
			f_gc_state = "ended"
		end
	elseif f_gc_state == "none" and timer > 0 then
		note = "F OPEN"
		f_gc_state = "in_progress"
	elseif timer > 0 then
		f_gc_state = "in_progress"
	elseif f_gc_state == "ended" or f_gc_state == "success" then
		f_gc_state = "none"
	end
	if note == nil and (f_press ~= 0 or f_release ~= 0) and timer > 0 then
		if f_press ~= 0 then note = "F PRESS   " .. btn_names(f_press)
		else note = "F RELEASE " .. btn_names(f_release) end
	end

	if note ~= nil then
		write(string.format("  [f=%d t=%3d] %-22s $158=%02X $06=%02X",
			fr, t, note, timer, state))
	end

	f_prev_btn = btn
	f_prev_timer = timer
end)

gui.register(function()
	gui.text(8, 8, string.format("gc success probe   %d 回中 %d 成立   %d 行記録",
		attempts, successes, lines))
	gui.text(8, 18, "last:  " .. last_summary)

	-- The whole question in one line: if every gap is 0, the qualifying input
	-- and the cancel are on the same tick and only the sampling rate is losing
	-- it. Anything else says the claim in inputHistory.lua needs revisiting.
	local spread = {}
	local seen = {}
	for _, g in ipairs(gaps) do
		if not seen[g] then seen[g] = 0 end
		seen[g] = seen[g] + 1
	end
	for g, n in pairs(seen) do spread[#spread + 1] = g .. "t x" .. n end
	gui.text(8, 28, "成立したときの間隔: " ..
		((#spread > 0) and table.concat(spread, "  ") or "まだ無い"))
	gui.text(8, 42, "ガードして DPF (6 2 3) + ボタン。8〜10 回。F 行が表示側")
	gui.text(8, 52, "うち 1〜2 回は「押し」ではなく「離し」で成立させる。")
end)

emu.registerexit(function()
	if file then file:close() file = nil end
end)
