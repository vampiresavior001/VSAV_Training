-- AUTO MASH (Dummy tab, user 2026-10-15; handoff VSAV_Claude_Handoff_Remaining
-- 20261015, START_HERE_GRAB_MASHING / GRAB_MASH_ROM_ANALYSIS). The Mash Meter
-- observation added 2026-10-19 shares these routines' callbacks.
--
-- While the dummy grabs or is grabbed by a move that takes mashing, or is in a
-- hit it can mash out of, it mashes directions and buttons: Off / Normal /
-- Fast / Fastest. The dummy only (P2, and only while you control P1), and only
-- where the game is reading the mash - not a throw in general, not ordinary
-- hit stun.
--
-- HITS TOO (user, 2026-10-16: "短縮できるものはすべてグラブマッシングで" and
-- "オルバスの毒ガスも"; survey EXTENDED_MASHING_ROM_SURVEY, checked against
-- analysis/mame_code c20.txt). Besides the grab, two routines read the one
-- hit's own input, A6 that one:
--   0260AC  called from 02497A, 024A0A, 025426 and 025800. If its $3B4 is 0,
--           a new lever press ($127 & 0x0F) takes a random amount off its own
--           $15C (table 0283C4: 1 x24, 8 x3, 12 x2, 16 x2, 32), a new button
--           press ($126 & 0x77) another (028404: 1 x23, 12, 16 x5, 32 x2, 48),
--           then 1 more. Under 0: 02610A clears it and returns D0 1, out.
--           Otherwise 026106 returns D0 0. The CPU path still ends at 026140.
--   025F22  each Tick of the $140 0x34 reaction (025E9C, $07 2) until its
--           motion ends (025EE6): any new press, lever or button ($126 as a
--           word), plays the motion one more step (027F70).
-- Which moves end there is the hit type ($54) the attack sets (survey: Chaos
-- Flare 40, Karame Dama 1D, Big Branch 24, Water Jail 2D, Q-Bee's QJ 3C) -
-- not checked here move by move; whatever reaches the routine is mashed for.
-- The log names the hit type and the attacker.
--
-- WHAT THE GAME READS (ROM, analysis/mame_code c28.txt; the handoff's reading
-- checked against it):
--   02991C  called by the grabber's move, A6 the grabber. A4 = ($32,A6), the
--           one held. If A4's $3B4 is 0 (a player, not the CPU), a new lever
--           press (A4's $127 & 0x0F) takes a random amount off the grabber's
--           $15C (table 029CC2), a new button press (A4's $126 & 0x77) another
--           (029D02), then 1 more. Under 0: 02997E clears it and returns D0 1,
--           let go. Otherwise 02997A returns D0 0, still held. ($10D,A5) set
--           lets go at once; the CPU path ends at 0299B4 / 02997E.
--   0299B8  called just before it, A6 the grabber again: a new button press
--           of its own and a new lever press each advance its move (027F70).
-- So each side's mash is one new press per category per call: more buttons at
-- once do not count twice, and a held button counts once.
--
-- WHEN THE INPUT GOES IN: AFTER A GRAB CALL, BEFORE THE NEXT. The input
-- routine (02207E: both players, in an order it picks at random, 014E8A bit 0)
-- makes the press edges ($126 = ~$124 & $122 at 0221AA) the next grab call
-- reads. So the dummy is mashed for when the latest grab call since its last
-- input held it, with its $05 as it was then; that call is then used up. A
-- grab let go, a dummy whose state changed, or no call since (a freeze, or a
-- grab over) gets nothing - so no normal or jump out of the release. The
-- grab's first call reads input made before it began, so it is never mashed for.
--
-- NOT "THE CALL OF THIS TICK" OR "OF THE TICK BEFORE": which it is depends on
-- who grabs. The first version took the Tick before and mashed only after the
-- grab's last call (v11.7.26_2, Demitri on Morrigan: P1's calls came before
-- the dummy's input of the same Tick). The second took the same Tick: the
-- dummy held on P1 got 704 inputs, but the dummy grabbing (Demitri on Demitri,
-- 0x02FE54, 758 calls) got none (v11.7.26_3) - its call of a Tick does not come
-- before that Tick's input, presumably the dummy's own update running after
-- the input routine. "Since the last input" holds either way.
--
-- WHERE. 022120, the instruction after 02211A copies $394 into $122: the
-- dummy's whole $122 is replaced for that Tick. Whatever else wrote $394
-- before the copy (guardCancel's injection, a playback through the pad) is
-- not merged in - this owns the input for the Tick. $12A (the special-move
-- reader, copied from $394 at 022126) is left as it was, so mashing builds no
-- command. The facing swap at 022194 runs after, so the lever is written raw.
--
-- WHAT IT STOPS. Grabbed, the dummy's reversal plans made before the grab
-- (Action Steps / Specified, a Character Specific wait, a queued input) are
-- dropped when mashing starts, as a savestate load drops them: they were for
-- something that is over, and must not go off when the dummy is let go. When
-- the dummy is the one grabbing, its own action is left running; only the
-- Ticks of the grab are replaced. In a hit, nothing is dropped: a reversal set
-- for the hit is still wanted when the dummy gets out (guardCancel arms its
-- long reaction off this same $15C), so while one is queued (a queued input,
-- Action Steps still to come) the Tick is left to it and not mashed. Not at
-- all while a recording plays or is made, in the Recording Wizard, in the
-- menu, or with P2 under your control.
-- Random Throw Tech % (throwTech.lua) holds away + MP the whole time the
-- dummy is thrown; inside a grab that reads the mash this replaces it too.
-- v11.7.26_2: Demitri's grab with that hold ended after 13 calls, $15C at
-- 105, where one without it ran all 121 - whether the mash's own presses tech
-- the same grab is not measured yet.
--
-- PPP + UP, THEN KKK + DOWN, AND AGAIN (user, 2026-10-16: "グラブマッシングは３ボタン
-- と上下連打で投げぬけしないように。PPP上＞KKK下＞PPP上にして"). The two halves
-- share no bit, so each change is a new lever press and a new button press.
-- No forward or back: a throw tech wants one (v11.7.26_3, every Fastest grab
-- with LP / MP and forward / back on Morrigan ended 10 to 13 calls in with
-- $15C at 47 to 83, as the Random Throw Tech hold did; v11.7.27 went to LP and
-- LK alone for that). Three buttons count as one: 02991C only asks whether
-- $126 & 0x77 is non-zero, and $127 & 0x0F, each once a call.
--   Normal   a change every 7 Ticks
--   Fast     a change every 4 Ticks
--   Fastest  a change every Tick: the half the last Tick did not hold - the
--            most presses the game counts. Not the fastest escape: the
--            amounts are random.
-- Counted from the first Tick; Normal and Fast start on PPP + up.
-- 7 and 4 keep v11.7.27's pace. A call takes 1, and on average 1.66 more for
-- a new lever press and as much for a new button press (029CC2 and 029D02
-- are the same 32 words: 29 ones, 4, 8, 12). v11.7.27's Normal made a new
-- lever press every 8 Ticks (half its changes added no bit) and a button one
-- every 6, 1.48 a Tick; Fast 4 lever presses in 18 Ticks and a button one
-- every 4, 1.78. A change every N Ticks is 1 + 3.31 / N: 1.47 for 7, 1.83 for
-- 4. Worked out, not measured.

local M = {}
local actionSequenceRunner = require "./scripts/actionSequenceRunner"

local P1, P2 = 0xFF8400, 0xFF8800
local SIDE = { [P1] = 1, [P2] = 2 }
M.MODES = { "Off", "Normal", "Fast", "Fastest" }

M.PC = {
	enter = 0x02991C,     -- the held side's mash, A6 the grabber
	held = 0x02997A,      -- still held (a player)
	held_cpu = 0x0299B4,  -- still held (the CPU path)
	let_go = 0x02997E,    -- let go
	own = 0x0299B8,       -- the grabber's own mash
	input = 0x022120,     -- after $394 -> $122, before the edges
	hit_enter = 0x0260AC, -- a hit's own timer, A6 the one hit
	hit_held = 0x026106,  -- still in it
	hit_held_cpu = 0x026140, -- still in it (the CPU path)
	hit_end = 0x02610A,   -- out
	motion = 0x025F22,    -- the 0x34 reaction's motion, A6 the one hit
	motion_end = 0x025EE6, -- its motion over
}

-- THE MASH METER (user, 2026-10-19).
--
-- This is observation, not input: it has to keep working with Auto Mash Off,
-- with P2 in your hands, during playback/recording, and while the menu is
-- open. The routines below are the same ones the auto input uses, so the
-- observation is added to those callbacks rather than a second registerexec.
--
-- A grab reads the GRABBER's $15C and draws over the HELD side. The two hits
-- read their own $15C. The 0x34 reaction reads its motion pointer/count; the
-- section table is the one at 0x028444. The lengths are the first byte of each
-- 24-byte record, and 0x0285AC is the end record: its 6 is not part of the
-- 120 updates before the end.
M.MOTION_BASE = 0x028444
M.MOTION_END = 0x0285AC
M.MOTION_STRIDE = 0x18
M.MOTION_LENGTHS = { 16, 10, 10, 3, 10, 10, 3, 10, 10, 3, 10, 10, 3, 8, 4 }
M.MOTION_TOTAL = 120

local motion_record, motion_after = {}, {}
do
	local after = 0
	for i = #M.MOTION_LENGTHS, 1, -1 do
		motion_record[M.MOTION_BASE + (i - 1) * M.MOTION_STRIDE] =
			{ index = i, len = M.MOTION_LENGTHS[i] }
		motion_after[i] = after
		after = after + M.MOTION_LENGTHS[i]
	end
end

-- nil means "cannot be known from this pointer/count"; no value is guessed.
local function motion_remaining(ptr, count)
	if ptr == M.MOTION_END then return 0 end
	local rec = motion_record[ptr]
	if rec == nil then return nil end
	if type(count) ~= "number" or count < 1 or count > rec.len then return nil end
	return count + motion_after[rec.index]
end
M.motion_remaining = motion_remaining

local meter = {
	[P1] = { active = false },
	[P2] = { active = false },
}
local meter_serial = 0

local function meter_clear(side)
	local m = meter[side]
	if m == nil then return end
	m.active, m.kind, m.owner, m.target = false, nil, nil, nil
	m.remaining, m.baseline, m.unknown = nil, nil, false
	m.s05, m.s54, m.s140, m.ptr, m.count, m.stale = nil, nil, nil, nil, nil, 0
end

local function meter_start(side, kind, owner, remaining, baseline, s05, s54, s140)
	local m = meter[side]
	if m == nil then return end
	meter_serial = meter_serial + 1
	m.active, m.kind, m.owner, m.target = true, kind, owner, side
	m.remaining, m.baseline = remaining, baseline
	m.unknown = (remaining == nil)
	m.s05, m.s54, m.s140, m.ptr, m.count, m.stale = s05, s54, s140, nil, nil, 0
	m.id = meter_serial
end

local function meter_end(side, kind)
	local m = meter[side]
	if m ~= nil and m.kind == kind then meter_clear(side) end
end

-- The timer is a signed word and may reach -1 before the routine's own end
-- branch clears it. The meter never shows a negative count.
local function timer_value(base)
	local v = memory.readword(base + 0x15C)
	if v >= 0x8000 then v = v - 0x10000 end
	if v < 0 then v = 0 end
	return v
end

local function meter_timer(side, owner, kind, value, s05, s54)
	local m = meter[side]
	if m == nil then return end
	if kind == "grab" and meter[owner] == nil then return end
	local v = value or 0
	if v < 0 then v = 0 end
	-- A rise is a refreshed timer (another grab or hit); s54 changing is a
	-- different hit. Anything else is the same interval and keeps its base.
	local new = (not m.active) or m.kind ~= kind or m.owner ~= owner
		or (m.s54 ~= nil and s54 ~= nil and s54 ~= m.s54)
		or (m.remaining ~= nil and v > m.remaining)
	if new then
		meter_start(side, kind, owner, v, v, s05, s54)
	else
		m.remaining, m.unknown, m.s05, m.s54, m.stale = v, false, s05, s54, 0
	end
end

local function meter_motion(side, ptr, count, s05, s140)
	local m = meter[side]
	if m == nil then return end
	local rem = motion_remaining(ptr, count)
	-- A pointer back to the first record, or moving backwards, is a new
	-- reaction. An unknown pointer is still observed: the label is drawn with
	-- no bar, never with a made-up number.
	local new = (not m.active) or m.kind ~= "recovery_motion"
		or (m.s140 ~= nil and s140 ~= nil and s140 ~= m.s140)
		or (m.ptr ~= nil and ptr < m.ptr)
		or (ptr == M.MOTION_BASE and m.ptr ~= nil and m.ptr ~= M.MOTION_BASE)
	if new then
		meter_start(side, "recovery_motion", side, rem, M.MOTION_TOTAL, s05, nil, s140)
	else
		m.remaining, m.unknown, m.s05, m.s140, m.stale = rem, (rem == nil), s05, s140, 0
	end
	m.ptr, m.count = ptr, count
end

-- The hooks run BEFORE their routines subtract or advance. The frame end is
-- after the game has done so, which is when the meter is drawn: take the
-- current value there, still only for a state the ROM routine has confirmed.
local function meter_refresh(side, m)
	if m.kind == "grab" or m.kind == "recovery_timer" then
		m.remaining, m.unknown = timer_value(m.owner), false
	elseif m.kind == "recovery_motion" then
		local ptr = memory.readdword(side + 0x1C)
		local count = memory.readbyte(side + 0x20)
		local rem = motion_remaining(ptr, count)
		m.remaining, m.unknown = rem, (rem == nil)
		m.ptr, m.count = ptr, count
	end
end

-- One missed hook is not an end. The game's own state is checked at the end
-- of a displayed frame, but only outside the menu/freeze; two consecutive
-- mismatches are needed so a transitional frame does not erase the meter.
local function meter_validate()
	if globals == nil then return end
	if globals.show_menu == true or globals.game_frozen == true then return end
	if globals.match_running ~= nil and not globals.match_running() then
		M.reset_meter()
		return
	end
	for side, m in pairs(meter) do
		if m.active then
			local s05 = memory.readbyte(side + 0x05)
			local ok = true
			if m.kind == "grab" then
				ok = (m.s05 == nil or s05 == m.s05)
			elseif m.kind == "recovery_timer" then
				ok = (s05 == 0x02)
			elseif m.kind == "recovery_motion" then
				ok = (s05 == 0x02)
					and (m.s140 == nil or memory.readbyte(side + 0x140) == m.s140)
			end
			if ok then
				m.stale = 0
				meter_refresh(side, m)
			else
				m.stale = (m.stale or 0) + 1
				if m.stale >= 2 then meter_clear(side) end
			end
		end
	end
end

function M.meter_state(side) return meter[side] end
function M.reset_meter()
	for side in pairs(meter) do meter_clear(side) end
end
M._meter = meter
M._meter_validate = meter_validate

-- Lever bits as the game reads them after the facing swap: 0x01 back, 0x02
-- forward (guardCancel.lua, "CORRECTED bit1 (forward)"), 0x04 down, 0x08 up.
local D, U = 0x04, 0x08
local PPP, KKK = 0x07, 0x70            -- LP MP HP, LK MK HK
M.HALVES = { { PPP, U }, { KKK, D } }
M.EVERY = { Normal = 7, Fast = 4, Fastest = 1 }

local function has(v, b) return math.floor(v / b) % 2 == 1 end

-- The raw lever for the corrected one: 022194 swaps bits 0 and 1 when $b is set.
local function raw_lever(corrected, facing)
	if facing == 0 then return corrected end
	local b0, b1 = corrected % 2, math.floor(corrected / 2) % 2
	return corrected - b0 - 2 * b1 + 2 * b0 + b1
end
M.raw_lever = raw_lever

-- The word for the n-th Tick of a mash (n from 0), given last Tick's corrected
-- $124: buttons, corrected lever. Fastest takes the half the last Tick did not
-- hold (KKK + down after any punch or up, else PPP + up).
function M.word(mode, n, prev_buttons, prev_lever)
	local every = M.EVERY[mode]
	if every == nil then return 0, 0 end
	local k
	if mode == "Fastest" then
		k = (prev_buttons % 8 ~= 0 or has(prev_lever, U)) and 2 or 1
	else
		k = math.floor(n / every) % 2 + 1
	end
	return M.HALVES[k][1], M.HALVES[k][2]
end

function M.mode()
	local v = globals ~= nil and globals.options ~= nil and globals.options.grab_mashing
	return M.MODES[v or 1] or "Off"
end

-- ---------------------------------------------------------------------------
-- The log (Knockdown Logger only), as chainLog.lua: gathered in the hooks,
-- written from the frame callback - io.open cannot write from an exec hook.
local LOG = "reversal_logs/grab_log.jsonl"
local MAX_PENDING = 20000
local pending_rows = {}
local started_file = false
local last_write = 0
local function logging()
	return globals ~= nil and globals.options ~= nil and globals.options.knockdown_logger_enable == true
end
local function hex(n, w) return string.format("0x%0" .. w .. "X", n or 0) end
local function push(r)
	if not logging() then return end
	r.lg = memory.readbyte(0xFF8081)
	r.frame = emu.framecount()
	pending_rows[#pending_rows + 1] = r
	if #pending_rows > MAX_PENDING then table.remove(pending_rows, 1) end
end
local function row_text(r)
	local keys = {}
	for k in pairs(r) do keys[#keys + 1] = k end
	table.sort(keys)
	local out = {}
	for _, k in ipairs(keys) do
		local v = r[k]
		if type(v) == "number" then out[#out + 1] = string.format('"%s": %d', k, v)
		elseif type(v) == "boolean" then out[#out + 1] = string.format('"%s": %s', k, tostring(v))
		else out[#out + 1] = string.format('"%s": "%s"', k, tostring(v)) end
	end
	return "{" .. table.concat(out, ", ") .. "}\n"
end
local HEADER = '{"log": "grab_log", "version": 2, '
	.. '"hooks": "02991C the held side\'s mash (A6 grabber), 02997A / 0299B4 still held, 02997E let go, '
	.. '0299B8 the grabber\'s own mash, 0260AC a hit\'s own timer (A6 the one hit), 026106 / 026140 still in it, '
	.. '02610A out, 025F22 the 0x34 reaction\'s motion, 025EE6 its end, 022120 the dummy\'s input (scripts/grabMashing.lua)", '
	.. '"kind": "call = a routine entered (what: grab / hit / motion); end = how it returned; own = 0299B8; '
	.. 'inject = the word put in the dummy\'s $122; run = a mash began or ended; dummy = its $54 / $140 / $05 changed; '
	.. 'skip = a call had the dummy in it and nothing went in (why)", '
	.. '"fields": "grabber / held 1 or 2 (held: the one in it); ret the return address (which move); t15c the timer '
	.. '(the grabber\'s, or a hit\'s own); cpu the held side\'s $3B4; e126 / e127 the held side\'s press edges; '
	.. 's_grabber / s_held $04-$07; h54 the hit type, h140 $140 of the one hit; c_held / c_other the characters; '
	.. 'btn / lever what was written (lever raw), p124 the dummy\'s $124 before; lg = 0xFF8081"}\n'

-- ---------------------------------------------------------------------------
-- The grab calls, newest first: the one in progress and the last finished.
local call = nil
local last = nil
-- The mash in progress: { role = "grabbed" / "grabbing", st05, n, grabber_char }.
local run = nil
-- The latest grab call with the dummy in it since the dummy's last input.
local unread = nil

local function base_of(word) return 0xFF0000 + (word % 0x10000) end

function M.reset(why)
	if run ~= nil then push({ kind = "run", what = "end", why = why or "reset" }) end
	call, last, run, unread = nil, nil, nil, nil
end

-- Grabbed: what was planned before the grab goes, as a savestate load drops it.
local function drop_reservations()
	actionSequenceRunner.cancel()
	if guard_action_input ~= nil then guard_action_input.csp_due = nil end
	local p = player_objects ~= nil and player_objects[2] or nil
	if p ~= nil then
		p.pending_input_sequence = nil
		if p.counter ~= nil then
			p.counter.sequence = nil
			p.counter.attack_frame = -1
			p.counter.ref_time = -1
		end
	end
end

-- Nothing of this while P2 is yours, a recording plays or is made, the wizard
-- is up, the menu is open or there is no match.
local function allowed()
	if globals == nil or globals.options == nil then return false, "no options" end
	if M.mode() == "Off" then return false, "off" end
	if globals.controlling_p1 ~= true then return false, "P2 is yours" end
	if globals.playing == true then return false, "playing" end
	if globals.recording == true then return false, "recording" end
	if globals.show_menu == true then return false, "menu" end
	local wz = globals.recordingWizard
	if wz ~= nil and wz.is_active ~= nil and wz.is_active() then return false, "wizard" end
	if globals.match_running ~= nil and not globals.match_running() then return false, "no match" end
	return true
end
M.allowed = allowed

function M.on_enter()
	local a6 = memory.getregister("m68000.a6")
	local held = base_of(memory.readword(a6 + 0x32))
	local a7 = memory.getregister("m68000.a7")
	meter_timer(held, a6, "grab", timer_value(a6), memory.readbyte(held + 0x05), nil)
	call = { what = "grab", lg = memory.readbyte(0xFF8081), grabber = SIDE[a6], held = SIDE[held],
	         grabber_base = a6, held_base = held, timer_base = a6, ret = memory.readdword(a7) }
	push({ kind = "call", what = "grab", grabber = SIDE[a6] or 0, held = SIDE[held] or 0, ret = hex(call.ret, 6),
	       t15c = memory.readword(a6 + 0x15C), cpu = memory.readbyte(held + 0x3B4),
	       e126 = hex(memory.readbyte(held + 0x126), 2), e127 = hex(memory.readbyte(held + 0x127), 2),
	       s_grabber = hex(memory.readdword(a6 + 0x04), 8), s_held = hex(memory.readdword(held + 0x04), 8),
	       c_grabber = memory.readbyte(a6 + 0x382), c_held = memory.readbyte(held + 0x382) })
end

local function finish(still)
	local c = call
	call = nil
	if c == nil then return end
	if not still then
		if c.what == "grab" then
			meter_end(c.held_base, "grab")
		elseif c.what == "hit" then
			meter_end(c.held_base, "recovery_timer")
		elseif c.what == "motion" then
			meter_end(c.held_base, "recovery_motion")
		end
	end
	local dummy = (c.held == 2) and c.held_base or ((c.grabber == 2) and c.grabber_base or nil)
	c.still = still
	c.st05 = dummy and memory.readbyte(dummy + 0x05) or nil
	last = c
	if dummy ~= nil then unread = c end
	if c.timer_base ~= nil then
		push({ kind = "end", what = c.what, still = still, t15c = memory.readword(c.timer_base + 0x15C) })
	end
	if not still and run ~= nil and dummy ~= nil then
		push({ kind = "run", what = "end", why = (c.what == "grab") and "let go" or "out" })
		run = nil
	end
end
function M.on_held() finish(true) end
function M.on_let_go() finish(false) end

-- The routines of a hit (0260AC, 025F22): A6 the one hit, reading its own input.
local function hit_row(what, a6)
	local other = (a6 == P1) and P2 or P1
	return { kind = "call", what = what, held = SIDE[a6] or 0, cpu = memory.readbyte(a6 + 0x3B4),
	         e126 = hex(memory.readbyte(a6 + 0x126), 2), e127 = hex(memory.readbyte(a6 + 0x127), 2),
	         s_held = hex(memory.readdword(a6 + 0x04), 8), h54 = hex(memory.readbyte(a6 + 0x54), 2),
	         h140 = hex(memory.readbyte(a6 + 0x140), 2),
	         c_held = memory.readbyte(a6 + 0x382), c_other = memory.readbyte(other + 0x382) }
end
function M.on_hit_enter()
	local a6 = memory.getregister("m68000.a6")
	local a7 = memory.getregister("m68000.a7")
	meter_timer(a6, a6, "recovery_timer", timer_value(a6),
		memory.readbyte(a6 + 0x05), memory.readbyte(a6 + 0x54))
	call = { what = "hit", lg = memory.readbyte(0xFF8081), held = SIDE[a6], held_base = a6,
	         timer_base = a6, ret = memory.readdword(a7) }
	local r = hit_row("hit", a6)
	r.ret, r.t15c = hex(call.ret, 6), memory.readword(a6 + 0x15C)
	push(r)
end
-- The motion has no return of its own: each call is still in it, its end is out.
local function motion(still)
	local a6 = memory.getregister("m68000.a6")
	meter_motion(a6, memory.readdword(a6 + 0x1C), memory.readbyte(a6 + 0x20),
		memory.readbyte(a6 + 0x05), memory.readbyte(a6 + 0x140))
	call = { what = "motion", lg = memory.readbyte(0xFF8081), held = SIDE[a6], held_base = a6, ret = 0 }
	local r = hit_row("motion", a6)
	r.still = still
	push(r)
	finish(still)
end
function M.on_motion() motion(true) end
function M.on_motion_end() motion(false) end

-- In a hit, a reversal queued for when the dummy gets out has the Tick.
local function reversal_queued()
	local p = player_objects ~= nil and player_objects[2] or nil
	if p ~= nil and p.pending_input_sequence ~= nil then return true end
	return actionSequenceRunner.pending_count ~= nil and actionSequenceRunner.pending_count() > 0
end

function M.on_own()
	local a6 = memory.getregister("m68000.a6")
	push({ kind = "own", side = SIDE[a6] or 0, e126 = hex(memory.readbyte(a6 + 0x126), 2),
	       e127 = hex(memory.readbyte(a6 + 0x127), 2) })
end

-- The dummy's input for this Tick (A6 = P2 at 022120).
function M.on_input()
	if memory.getregister("m68000.a6") ~= P2 then return end
	local c = unread
	unread = nil
	local ok, why = allowed()
	if not ok then
		if c ~= nil and c.still then push({ kind = "skip", why = why }) end
		if run ~= nil then M.reset("not allowed: " .. why) end
		return
	end
	local lg = memory.readbyte(0xFF8081)
	local st05 = memory.readbyte(P2 + 0x05)
	local in_it = c ~= nil and c.still and (lg - c.lg) % 256 <= 1 and st05 == c.st05 and st05 ~= 0
	if not in_it then
		-- No call since the last input (a freeze) keeps the run while the dummy
		-- is in the same state; a state change ends it (a let-go already did).
		if run ~= nil and (c ~= nil or st05 ~= run.st05) then M.reset("state") end
		if c ~= nil and c.still then push({ kind = "skip", why = "state" }) end
		return
	end
	local role = "hit"
	if c.what == "grab" then role = (c.held == 2) and "grabbed" or "grabbing" end
	if role == "hit" and reversal_queued() then
		push({ kind = "skip", why = "reversal queued" })
		return
	end
	if run == nil or run.role ~= role then
		run = { role = role, st05 = c.st05, n = 0 }
		push({ kind = "run", what = "start", role = role, mode = M.mode(), ret = hex(c.ret, 6) })
		if role == "grabbed" then drop_reservations() end
	end
	local prev_btn = memory.readbyte(P2 + 0x124)
	local prev_lev = memory.readbyte(P2 + 0x125)
	local btn, lev = M.word(M.mode(), run.n, prev_btn, prev_lev)
	local raw = raw_lever(lev, memory.readbyte(P2 + 0x0B))
	memory.writeword(P2 + 0x122, btn * 256 + raw)
	push({ kind = "inject", role = role, n = run.n, btn = hex(btn, 2), lever = hex(raw, 2),
	       p124 = hex(prev_btn * 256 + prev_lev, 4) })
	run.n = run.n + 1
end

function M.registerStart()
	if globals ~= nil then globals.mash_meter = M.meter_state end
	memory.registerexec(M.PC.enter, M.on_enter)
	memory.registerexec(M.PC.held, M.on_held)
	memory.registerexec(M.PC.held_cpu, M.on_held)
	memory.registerexec(M.PC.let_go, M.on_let_go)
	memory.registerexec(M.PC.own, M.on_own)
	memory.registerexec(M.PC.input, M.on_input)
	memory.registerexec(M.PC.hit_enter, M.on_hit_enter)
	memory.registerexec(M.PC.hit_held, M.on_held)
	memory.registerexec(M.PC.hit_held_cpu, M.on_held)
	memory.registerexec(M.PC.hit_end, M.on_let_go)
	memory.registerexec(M.PC.motion, M.on_motion)
	memory.registerexec(M.PC.motion_end, M.on_motion_end)
end

-- The dummy's reaction when it changes (the log only): a hit that reaches
-- neither routine still shows its hit type ($54) and $140 here, which is how
-- a move that is not mashed for gets found.
local seen = nil
local function watch_dummy()
	if not logging() or M.mode() == "Off" then seen = nil return end
	local h54, h140, s05 = memory.readbyte(P2 + 0x54), memory.readbyte(P2 + 0x140), memory.readbyte(P2 + 0x05)
	local key = h54 * 65536 + h140 * 256 + s05
	if key == seen then return end
	seen = key
	push({ kind = "dummy", h54 = hex(h54, 2), h140 = hex(h140, 2), s05 = hex(s05, 2),
	       c_other = memory.readbyte(P1 + 0x382) })
end

function M.registerAfter()
	meter_validate()
	if M.mode() == "Off" and run ~= nil then M.reset("off") end
	watch_dummy()
	if #pending_rows == 0 or not logging() then return end
	local now = emu.framecount()
	if now - last_write < 60 then return end
	last_write = now
	local f = io.open(LOG, started_file and "a" or "w")
	if f == nil then return end
	if not started_file then
		f:write(HEADER)
		started_file = true
	end
	for _, r in ipairs(pending_rows) do f:write(row_text(r)) end
	f:close()
	pending_rows = {}
end

-- For analysis/test_grab_mashing.lua.
function M._rows() return pending_rows end
function M._run() return run end
function M._last() return last end
function M._row_text(r) return row_text(r) end

return M
