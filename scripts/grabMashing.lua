-- GRAB MASHING (Dummy tab, user 2026-10-15; handoff VSAV_Claude_Handoff_Remaining
-- 20261015, START_HERE_GRAB_MASHING / GRAB_MASH_ROM_ANALYSIS).
--
-- While the dummy grabs or is grabbed by a move that takes mashing, it mashes
-- directions and buttons: Off / Normal / Fast / Fastest. The dummy only (P2,
-- and only while you control P1), and only inside a grab the game is reading
-- the mash for - not a throw in general, not a stun.
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
-- Ticks of the grab are replaced. Not at all while a recording plays or is
-- made, in the Recording Wizard, in the menu, or with P2 under your control.
-- Random Throw Tech % (throwTech.lua) holds away + MP the whole time the
-- dummy is thrown; inside a grab that reads the mash this replaces it too.
-- v11.7.26_2: Demitri's grab with that hold ended after 13 calls, $15C at
-- 105, where one without it ran all 121 - whether the mash's own presses tech
-- the same grab is not measured yet.
--
-- THE THREE SETTINGS (handoff, section 1 and 3). Normal and Fast are 3rd
-- Strike training's grab branches (Normal, Serious), in Ticks here where 3rd
-- counts displayed frames - the same numbers, not the same speed. Each
-- combination is held for its whole period, counted from the first Tick:
--   Normal   lever  dr d dl l ul u ur r  every 4    buttons LP, LK every 6
--   Fast     lever  dl d ur u dl ur      every 3    buttons LP, LK every 4
--   Fastest  a new lever press and a new button press every Tick: forward or
--            back, LP or LK, whichever the last Tick did not hold - the most
--            presses the game counts. Not the fastest escape: the amounts are
--            random.
-- (r is towards the other side.)
--
-- LIGHT BUTTONS ONLY (user, 2026-10-15: "投げぬけを避けるなら弱攻撃を使うのがいい
-- でしょう。ノーマルとファステストは投げぬけしてしまった"). 3rd's rhythms press
-- medium and heavy buttons too, and with a direction those tech the throw:
-- v11.7.26_3, every Fastest grab (then LP / MP) on Morrigan ended 10 to 13
-- calls in with $15C at 47 to 83, as the Random Throw Tech hold did. The
-- game counts one button press per call whichever it is (02991C reads $126 &
-- 0x77 once), so light ones lose nothing.

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
}

-- Lever bits as the game reads them after the facing swap: 0x01 back, 0x02
-- forward (guardCancel.lua, "CORRECTED bit1 (forward)"), 0x04 down, 0x08 up.
local B, F, D, U = 0x01, 0x02, 0x04, 0x08
local LP, LK = 0x01, 0x10
M.PATTERN = {
	Normal = { lever = { D + F, D, D + B, B, U + B, U, U + F, F }, lever_every = 4,
	           button = { LP, LK }, button_every = 6 },
	Fast = { lever = { D + B, D, U + F, U, D + B, U + F }, lever_every = 3,
	         button = { LP, LK }, button_every = 4 },
}
local BUTTON_ORDER = { LP, LK }

local function has(v, b) return math.floor(v / b) % 2 == 1 end

-- The raw lever for the corrected one: 022194 swaps bits 0 and 1 when $b is set.
local function raw_lever(corrected, facing)
	if facing == 0 then return corrected end
	local b0, b1 = corrected % 2, math.floor(corrected / 2) % 2
	return corrected - b0 - 2 * b1 + 2 * b0 + b1
end
M.raw_lever = raw_lever

-- Fastest: one bit not held on the last Tick, from the list; 0 (a release, so
-- the next Tick can press) when every one was held.
local function fresh_bit(prev, list)
	for _, b in ipairs(list) do if not has(prev, b) then return b end end
	return 0
end

-- The word for the n-th Tick of a mash (n from 0), given last Tick's corrected
-- $124: buttons, corrected lever.
function M.word(mode, n, prev_buttons, prev_lever)
	if mode == "Fastest" then
		return fresh_bit(prev_buttons, BUTTON_ORDER), fresh_bit(prev_lever, { F, B })
	end
	local p = M.PATTERN[mode]
	if p == nil then return 0, 0 end
	local btn = p.button[math.floor(n / p.button_every) % #p.button + 1]
	local lev = p.lever[math.floor(n / p.lever_every) % #p.lever + 1]
	return btn, lev
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
local HEADER = '{"log": "grab_log", "version": 1, '
	.. '"hooks": "02991C the held side\'s mash (A6 grabber), 02997A / 0299B4 still held, 02997E let go, '
	.. '0299B8 the grabber\'s own mash, 022120 the dummy\'s input (scripts/grabMashing.lua)", '
	.. '"kind": "call = 02991C entered; end = how it returned; own = 0299B8; inject = the word put in the dummy\'s $122; '
	.. 'run = a mash began or ended; skip = a call held the dummy and nothing went in (why)", '
	.. '"fields": "grabber / held 1 or 2; ret the return address (which move); t15c the grabber\'s $15C; '
	.. 'cpu the held side\'s $3B4; e126 / e127 the held side\'s press edges; s_grabber / s_held $04-$07; '
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
	call = { lg = memory.readbyte(0xFF8081), grabber = SIDE[a6], held = SIDE[held],
	         grabber_base = a6, held_base = held, ret = memory.readdword(a7) }
	push({ kind = "call", grabber = SIDE[a6] or 0, held = SIDE[held] or 0, ret = hex(call.ret, 6),
	       t15c = memory.readword(a6 + 0x15C), cpu = memory.readbyte(held + 0x3B4),
	       e126 = hex(memory.readbyte(held + 0x126), 2), e127 = hex(memory.readbyte(held + 0x127), 2),
	       s_grabber = hex(memory.readdword(a6 + 0x04), 8), s_held = hex(memory.readdword(held + 0x04), 8),
	       c_grabber = memory.readbyte(a6 + 0x382), c_held = memory.readbyte(held + 0x382) })
end

local function finish(still)
	local c = call
	call = nil
	if c == nil then return end
	local dummy = (c.held == 2) and c.held_base or ((c.grabber == 2) and c.grabber_base or nil)
	c.still = still
	c.st05 = dummy and memory.readbyte(dummy + 0x05) or nil
	last = c
	if dummy ~= nil then unread = c end
	push({ kind = "end", still = still, t15c = memory.readword(c.grabber_base + 0x15C) })
	if not still and run ~= nil then
		push({ kind = "run", what = "end", why = "let go" })
		run = nil
	end
end
function M.on_held() finish(true) end
function M.on_let_go() finish(false) end

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
	local role = (c.held == 2) and "grabbed" or "grabbing"
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
	memory.registerexec(M.PC.enter, M.on_enter)
	memory.registerexec(M.PC.held, M.on_held)
	memory.registerexec(M.PC.held_cpu, M.on_held)
	memory.registerexec(M.PC.let_go, M.on_let_go)
	memory.registerexec(M.PC.own, M.on_own)
	memory.registerexec(M.PC.input, M.on_input)
end

function M.registerAfter()
	if M.mode() == "Off" and run ~= nil then M.reset("off") end
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
