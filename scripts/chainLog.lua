-- WHAT THE GAME'S CHAIN AND RAPID CANCEL CHECK DID (2026-10-14).
--
-- The read-only probe for the Chain Trainer (handoff 2026-10-14, section 10 A,
-- and CHAIN_WINDOW_ROM_ANALYSIS): the body contact that opens the input timer,
-- the timer itself, the presses, the presses held through hit stop, and every
-- call of the normal-attack cancel check with how far it got. Nothing is
-- written to the game. The rows are for finding the window's real edges
-- before anything is drawn from them.
--
-- The ROM path (vsavj, analysis/mame_code; checked by test_chain_log.lua):
--   018262  move.b #$e, ($169,A6)     body contact: the attacker's timer = 14
--   02250A  after 022500-022506        $169 already counted down this update,
--                                      $126 is this update's press edges
--   027E7C  hit stop, $169 != 0        $12E |= $126 next - a press held
--   028E42  the cancel check           A5+$10E/$10D/$8A/$15D, $3B4, then:
--   028E5E    bsr 028FB0               rapid first; 028FF0 = rapid accepted
--   028E66    rapid refused            then $39 (contact) ...
--   028E6E    $39 set                  ... also entered directly by other
--                                      handlers (air, Jedah DF, Sasquatch DF)
--   028E76    $1B2 clear               $12E, plus $126 while $169 != 0
--   028E8C    some button              D0 = (held | edge) & $7700
--   028E94    exactly one              (028F78)
--   028E98    and.w D1, D0             D0 the button, D1 the next-move mask
--   028E9E    allowed                  the next move is in the mask
--   028ED0    st ($119,A6)             chain accepted
--   028EDC    after $102/$101          the commit both kinds share
--   029000    $3B4 != 0                another path; not read as a chain
--   028F34    rts                      the end of the call
--
-- A row is one of:
--   contact  the timer was set (p = the attacker, opp = the one it hit;
--            opp05 / opp140 are that one's $05 and $140 before the hit -
--            018262 runs ahead of 0182D8, which rewrites its state. $05 2 is
--            in stun, and $140 0x02 / 0x12 a block, as guardCancel.lua reads)
--   tick     an update where $169, $126's buttons or $12E was not 0, or
--            where $06, $105 or $1B8 changed (a normal, a dash attack, a
--            landing starting or ending - the Chain Trainer counts a link from
--            the first free tick after any of them, and a move's start tells it
--            which press was the move's own)
--   react    in stun, $06 went 0x00 -> 0x02: the impact freeze is over and
--            the hurt reaction runs (s59 = $59, the stun class the reversal
--            timing keys its 14 / 19 / 23 Tick leads on; s140, s54)
--   hit      the impact freeze began ($05 2, $06 0x00, from anything else):
--            this player was hit, by a body or a projectile - the contact row
--            sees only a body. The update after the hit; prev05 / prev140 are
--            this player's $05 / $140 on the update before (in stun or not,
--            already blocking or not), s140 the reaction now (0x02 / 0x12 a
--            block)
--   sig      the state is 0x02020400, the game's mark one tick before the
--            character can act (024F0A; VSAV_MEMORY_NOTES section 5) - seen
--            here at the update after it was written, so this tick is the
--            reversal tick: the first one a guard can come out on
--   hold     a press held into $12E during hit stop
--   check    a call of the check that saw a button, or accepted
-- Calls that saw nothing make no row; "calls" on the next check row counts
-- them, that one included.
--
-- Two readers: the file (below), and chainTrainer.lua, which draws the Chain
-- Trainer from the same rows plus the quiet calls (M.set_listener). The hooks
-- do nothing while neither is on.
--
-- The file: Knockdown Logger only. Gathered in the exec hooks, written from
-- the frame callback - io.open cannot write from inside an exec hook.
-- reversal_logs/chain_log.jsonl: one JSON object per line, the first one the
-- header. A start of FBNeo begins a new file. analysis/archive_logs.py
-- archives it; analysis/chain_log_summary.py reads it.

local M = {}

local LOG = "reversal_logs/chain_log.jsonl"
local PLAYERS = { [0xFF8400] = 1, [0xFF8800] = 2 }
local MAX_PENDING = 20000
local pending_rows = {}
local seq = 0
local started = false
local last_write = 0
local listener, listener_wants = nil, nil

-- The cancel check's steps, in the order a call passes them.
M.STAGE = {
	entry = 1, inhibit_ok = 2, rapid_check = 3, rapid_no = 4, contact_ok = 5,
	c1b2_ok = 6, buttons = 7, one_button = 8, mask = 9, allowed = 10,
	chain_accept = 11, rapid_accept = 12, commit = 13,
}
M.PC = {
	contact = 0x018262, tick = 0x02250A, hold = 0x027E7C,
	entry = 0x028E42, inhibit_ok = 0x028E56, rapid_check = 0x028E5E,
	rapid_no = 0x028E66, contact_ok = 0x028E6E, c1b2_ok = 0x028E76,
	buttons = 0x028E8C, one_button = 0x028E94, mask = 0x028E98,
	allowed = 0x028E9E, chain_accept = 0x028ED0, commit = 0x028EDC,
	rapid_accept = 0x028FF0, special = 0x029000, done = 0x028F34,
}

-- The six attack buttons of a press word ($7700: bits 8-10 and 12-14). Lua 5.1
-- here has no bit library.
local BUTTON_BITS = { 0x0100, 0x0200, 0x0400, 0x1000, 0x2000, 0x4000 }
function M.buttons(w)
	w = w or 0
	local out = 0
	for _, b in ipairs(BUTTON_BITS) do
		if math.floor(w / b) % 2 == 1 then out = out + b end
	end
	return out
end

local function logging()
	return globals ~= nil and globals.options ~= nil
	   and globals.options.knockdown_logger_enable == true
end
local function trainer()
	return listener ~= nil and listener_wants ~= nil and listener_wants() == true
end
local function active()
	return logging() or trainer()
end

-- chainTrainer.lua's way in: every row goes to fn as it is made, while wants()
-- says the trainer is on - and every quiet call of the check too (quiet =
-- true), which the file leaves out: the trainer needs to know the check ran on
-- a tick to call that tick judged.
function M.set_listener(fn, wants)
	listener, listener_wants = fn, wants
end
-- THE GAME'S OWN TICK COUNTER, 0xFF8081, CARRIED PAST ITS WRAP.
--
-- Not globals.p1_tick_seq (one per run of guardCancel's 0x0221CC hook for P1,
-- which commandLog uses). Measured 2026-10-15 on the first chain_log with both
-- players' rows (reversal_logs_archive/v11.7.25.2_13): between consecutive
-- rows it stepped one more or one less than 0xFF8081 212 times in 3244, so a
-- P1 contact and P2's reversal tick came out 25 or 26 apart for the same hit,
-- while 0xFF8081 said 26 every time (37 of 37, and 31 / 35 for the other two
-- strengths). Every hook of one tick reads the same value of it, for either
-- player. A step back (the emulator running a tick again) is followed, so a
-- tick run twice is numbered the same both times.
local clock, last_lg = 0, nil
local function tick()
	local lg = memory.readbyte(0xFF8081)
	if last_lg ~= nil then
		local d = (lg - last_lg) % 256
		if d >= 128 then d = d - 256 end
		clock = clock + d
	end
	last_lg = lg
	return clock
end
-- For chainTrainer.lua: the same clock, read outside the hooks.
function M.clock() return tick() end

local function player()
	local a6 = memory.getregister("m68000.a6")
	return PLAYERS[a6], a6
end
local function reg(name) return memory.getregister("m68000." .. name) end

local function push(r)
	seq = seq + 1
	r.seq = seq
	r.tick = tick()
	r.lg = memory.readbyte(0xFF8081)
	r.frame = emu.framecount()
	if trainer() then listener(r) end
	if logging() then
		pending_rows[#pending_rows + 1] = r
		if #pending_rows > MAX_PENDING then table.remove(pending_rows, 1) end
	end
end

-- What every row carries about the player, read at the hook.
local function snap(r, base)
	r.t169 = memory.readbyte(base + 0x169)
	r.edge = memory.readword(base + 0x126)
	r.held = memory.readword(base + 0x12E)
	r.c39 = memory.readbyte(base + 0x39)
	r.hs = memory.readbyte(base + 0x5C)
	r.cel = memory.readbyte(base + 0x21)
	r.air = memory.readbyte(base + 0x38)
	r.state = memory.readdword(base + 0x04)
	r.str = memory.readbyte(base + 0x102)
	r.typ = memory.readbyte(base + 0x101)
	r.r110 = memory.readbyte(base + 0x110)
	r.r111 = memory.readbyte(base + 0x111)
	r.char = memory.readbyte(base + 0x382)
	-- The attack flag and the game's count of attacks started: with $102 /
	-- $101 they say when a move began (airGuardGap.lua move_start).
	r.f105 = memory.readbyte(base + 0x105)
	r.s1b8 = memory.readword(base + 0x1B8)
	-- The lever this update ($122's low byte; bit 0x04 down - the bits
	-- guardCancel.lua's entry_to_bits injects): standing or crouching normal.
	r.lever = memory.readbyte(base + 0x123)
	return r
end

-- The call in progress, per player, and the calls that made no row.
local cur = {}
local quiet = { 0, 0 }

-- The call is over (its RTS, or a new call found it still open). A row only
-- when it saw a button or accepted - every other update of every normal
-- attack calls this, and those say nothing.
local function finish(p, how)
	local c = cur[p]
	cur[p] = nil
	if c == nil then return end
	if c.accept == nil and c.stage < M.STAGE.buttons
	   and M.buttons(c.edge) == 0 and M.buttons(c.held) == 0 then
		quiet[p] = quiet[p] + 1
		if trainer() then
			c.quiet = true
			c.tick = tick()
			c.ends = how
			listener(c)
		end
		return
	end
	c.calls = quiet[p] + 1
	quiet[p] = 0
	c.ends = how
	push(c)
end

local function stage(name)
	return function()
		if not active() then return end
		local p = player()
		if p == nil or cur[p] == nil then return end
		local s = M.STAGE[name]
		if s > cur[p].stage then cur[p].stage = s end
	end
end

local function on_contact()
	if not active() then return end
	local p, base = player()
	if p == nil then return end
	local r = snap({ kind = "contact", p = p }, base)
	local a1 = reg("a1")
	r.opp = PLAYERS[a1] or 0
	if r.opp ~= 0 then
		r.opp05 = memory.readbyte(a1 + 0x05)
		r.opp140 = memory.readbyte(a1 + 0x140)
	end
	push(r)
end

-- $06 as the last update read it, per player: any change makes a row even
-- when nothing else would, so the first tick the player can act again is on
-- the record (the Chain Trainer counts a link from it). Not only 0x0A: a dash
-- attack stays 0x14 and then lands (user, 2026-10-15: "ダッシュ中Pから小Pの目押
-- しも猶予を出したい").
local last06 = {}
-- $105 and $1B8 likewise: a move starting inside a dash changes neither $06
-- nor anything else these rows are made for, and the trainer has to see it.
local last105, last1b8 = {}, {}
-- $04-$07 as the last update read it, per player, for react / sig.
local last_state = {}
local last140 = {}
local function b06(st) return math.floor(st / 0x100) % 0x100 end
local function b05(st) return math.floor(st / 0x10000) % 0x100 end
local function on_tick()
	if not active() then return end
	local p, base = player()
	if p == nil then return end
	local s06 = memory.readbyte(base + 0x06)
	local moved = last06[p] ~= nil and last06[p] ~= s06
	last06[p] = s06
	local f105, s1b8 = memory.readbyte(base + 0x105), memory.readword(base + 0x1B8)
	if last105[p] ~= nil and (last105[p] ~= f105 or last1b8[p] ~= s1b8) then moved = true end
	last105[p], last1b8[p] = f105, s1b8
	-- THE OTHER SIDE'S RECOVERY, FOR THE LINK WINDOW (user, 2026-10-15:
	-- "リバーサルフレームのtickはわかる？ リバーサルフレームからガードが可能に
	-- なる"). Whoever is in stun - the trainer picks the one it needs.
	local st = memory.readdword(base + 0x04)
	local prev = last_state[p]
	last_state[p] = st
	local prev140 = last140[p]
	last140[p] = memory.readbyte(base + 0x140)
	if prev ~= nil then
		local kind = nil
		if b05(st) == 0x02 and b05(prev) == 0x02 and b06(prev) == 0x00 and b06(st) == 0x02 then
			kind = "react"
		elseif st == 0x02020400 and prev ~= 0x02020400 then
			kind = "sig"
		elseif b05(st) == 0x02 and b06(st) == 0x00 and not (b05(prev) == 0x02 and b06(prev) == 0x00) then
			kind = "hit"
		end
		if kind ~= nil then
			local r = snap({ kind = kind, p = p }, base)
			r.s59 = memory.readbyte(base + 0x59)
			r.s140 = memory.readbyte(base + 0x140)
			r.s54 = memory.readbyte(base + 0x54)
			r.prev05 = b05(prev)
			r.prev140 = prev140 or 0
			push(r)
		end
	end
	local t = memory.readbyte(base + 0x169)
	if t == 0 and M.buttons(memory.readword(base + 0x126)) == 0
	   and memory.readword(base + 0x12E) == 0 and not moved then
		return
	end
	push(snap({ kind = "tick", p = p }, base))
end

local function on_hold()
	if not active() then return end
	local p, base = player()
	if p == nil then return end
	if M.buttons(memory.readword(base + 0x126)) == 0 then return end
	push(snap({ kind = "hold", p = p }, base))
end

local function open_call(p, base, path)
	local c = snap({ kind = "check", p = p, path = path, stage = M.STAGE.entry }, base)
	local a5 = reg("a5")
	c.inhibit = memory.readbyte(a5 + 0x10E) * 0x1000000 + memory.readbyte(a5 + 0x10D) * 0x10000
	            + memory.readbyte(a5 + 0x8A) * 0x100 + memory.readbyte(a5 + 0x15D)
	c.c1b2 = memory.readbyte(base + 0x1B2)
	c.c3b4 = memory.readbyte(base + 0x3B4)
	cur[p] = c
	return c
end

local function on_entry()
	if not active() then return end
	local p, base = player()
	if p == nil then return end
	if cur[p] ~= nil then finish(p, "open") end
	open_call(p, base, "normal")
end

-- Reached by the normal path once $39 is set, and entered directly by other
-- handlers - a call that is not open here is one of those.
local function on_contact_ok()
	if not active() then return end
	local p, base = player()
	if p == nil then return end
	if cur[p] == nil then open_call(p, base, "direct") end
	if M.STAGE.contact_ok > cur[p].stage then cur[p].stage = M.STAGE.contact_ok end
end

local function on_buttons()
	if not active() then return end
	local p = player()
	if p == nil or cur[p] == nil then return end
	cur[p].stage = math.max(cur[p].stage, M.STAGE.buttons)
	cur[p].btn = reg("d0") % 0x10000
end

local function on_mask()
	if not active() then return end
	local p = player()
	if p == nil or cur[p] == nil then return end
	cur[p].stage = math.max(cur[p].stage, M.STAGE.mask)
	cur[p].d0 = reg("d0") % 0x10000
	cur[p].d1 = reg("d1") % 0x10000
end

local function on_chain_accept()
	if not active() then return end
	local p = player()
	if p == nil or cur[p] == nil then return end
	cur[p].stage = math.max(cur[p].stage, M.STAGE.chain_accept)
	cur[p].accept = "chain"
	cur[p].d0 = reg("d0") % 0x10000
	cur[p].d2 = reg("d2") % 0x100
	cur[p].d3 = reg("d3") % 0x100
end

local function on_rapid_accept()
	if not active() then return end
	local p = player()
	if p == nil or cur[p] == nil then return end
	cur[p].stage = math.max(cur[p].stage, M.STAGE.rapid_accept)
	cur[p].accept = "rapid"
	cur[p].d0 = reg("d0") % 0x10000
	cur[p].d1 = reg("d1") % 0x10000
end

local function on_commit()
	if not active() then return end
	local p, base = player()
	if p == nil or cur[p] == nil then return end
	cur[p].stage = math.max(cur[p].stage, M.STAGE.commit)
	-- Written at 028ED4 / 028ED8 just before: the next move.
	cur[p].next_str = memory.readbyte(base + 0x102)
	cur[p].next_typ = memory.readbyte(base + 0x101)
end

local function on_special()
	if not active() then return end
	local p = player()
	if p == nil or cur[p] == nil then return end
	cur[p].path = "special"
end

local function on_done()
	if not active() then return end
	local p = player()
	if p == nil then return end
	finish(p, "rts")
end

function M.registerStart()
	-- registerexec holds one callback per address; registering again on a
	-- reload replaces these rather than adding more. No other script hooks
	-- these addresses (analysis/test_chain_log.lua).
	memory.registerexec(M.PC.contact, on_contact)
	memory.registerexec(M.PC.tick, on_tick)
	memory.registerexec(M.PC.hold, on_hold)
	memory.registerexec(M.PC.entry, on_entry)
	memory.registerexec(M.PC.inhibit_ok, stage("inhibit_ok"))
	memory.registerexec(M.PC.rapid_check, stage("rapid_check"))
	memory.registerexec(M.PC.rapid_no, stage("rapid_no"))
	memory.registerexec(M.PC.contact_ok, on_contact_ok)
	memory.registerexec(M.PC.c1b2_ok, stage("c1b2_ok"))
	memory.registerexec(M.PC.buttons, on_buttons)
	memory.registerexec(M.PC.one_button, stage("one_button"))
	memory.registerexec(M.PC.mask, on_mask)
	memory.registerexec(M.PC.allowed, stage("allowed"))
	memory.registerexec(M.PC.chain_accept, on_chain_accept)
	memory.registerexec(M.PC.commit, on_commit)
	memory.registerexec(M.PC.rapid_accept, on_rapid_accept)
	memory.registerexec(M.PC.special, on_special)
	memory.registerexec(M.PC.done, on_done)
end

local function hex(n, w) return string.format("0x%0" .. w .. "X", n or 0) end
local STAGE_NAME = {}
for k, v in pairs(M.STAGE) do STAGE_NAME[v] = k end

local HEADER = '{"log": "chain_log", "version": 1, '
	.. '"hooks": "018262 contact ($169 = 14), 02250A the update after $169 counted down, 027E7C hit stop hold, '
	.. '028E42..028F34 the normal-attack cancel check (scripts/chainLog.lua)", '
	.. '"kind": "contact = the attacker p set its timer, opp = the player hit, opp05/opp140 its $05/$140 before the hit; '
	.. 'tick = an update with $169, a button in $126 or $12E, or $06 / $105 / $1B8 changing; '
	.. 'react = in stun, $06 went 0x00 -> 0x02 (s59/s140/s54 = $59/$140/$54); sig = the state 0x02020400 seen, the reversal tick; '
	.. 'hit = the impact freeze began (hit by a body or a projectile; prev05/prev140 = $05/$140 the update before); '
	.. 'hold = a press held into $12E during hit stop; check = a call of the cancel check that saw a button or accepted", '
	.. '"stage": "how far the call got: entry, inhibit_ok, rapid_check, rapid_no, contact_ok, c1b2_ok, buttons, one_button, mask, allowed, '
	.. 'chain_accept, rapid_accept, commit", '
	.. '"path": "normal = from 028E42, direct = entered at 028E6E, special = $3B4 != 0 (029000)", '
	.. '"fields": "t169 $169, edge $126, held $12E, c39 $39, hs $5C, cel $21, air $38, state $04-$07, str/typ $102/$101 (the move), '
	.. 'r110/r111, char $382, f105 $105 (attack flag), s1b8 $1B8 (attacks started), lever $123 (0x04 down); check: inhibit A5+$10E,$10D,$8A,$15D, c1b2 $1B2, c3b4 $3B4, btn D0 at 028E8C, d0/d1 at 028E98 '
	.. '(the button, the next-move mask) or at the accept, d2/d3 the next strength/type, next_str/next_typ after the commit, '
	.. 'calls = calls of the check by this player since its last check row, this one included", '
	.. '"tick": "0xFF8081 carried past its wrap (the game tick, the same for both players); lg = 0xFF8081"}\n'

local function row_text(r)
	local s = string.format(
		'{"seq": %d, "tick": %d, "lg": %d, "frame": %d, "p": %d, "kind": "%s", '
		.. '"t169": %d, "edge": "%s", "held": "%s", "c39": %d, "hs": %d, "cel": "%s", "air": %d, '
		.. '"state": "%s", "str": %d, "typ": %d, "r110": %d, "r111": %d, "char": "%s", "f105": %d, "s1b8": %d, '
		.. '"lever": "%s"',
		r.seq, r.tick, r.lg, r.frame, r.p, r.kind,
		r.t169, hex(r.edge, 4), hex(r.held, 4), r.c39, r.hs, hex(r.cel, 2), r.air,
		hex(r.state, 8), r.str, r.typ, r.r110, r.r111, hex(r.char, 2), r.f105 or 0, r.s1b8 or 0,
		hex(r.lever, 2))
	if r.kind == "contact" then
		s = s .. string.format(', "opp": %d, "opp05": %d, "opp140": %d', r.opp or 0, r.opp05 or -1, r.opp140 or -1)
	elseif r.kind == "react" or r.kind == "sig" or r.kind == "hit" then
		s = s .. string.format(', "s59": %d, "s140": %d, "s54": %d, "prev05": %d, "prev140": %d',
			r.s59 or -1, r.s140 or -1, r.s54 or -1, r.prev05 or -1, r.prev140 or -1)
	elseif r.kind == "check" then
		s = s .. string.format(
			', "path": "%s", "stage": "%s", "accept": "%s", "ends": "%s", "calls": %d, '
			.. '"inhibit": "%s", "c1b2": %d, "c3b4": %d, "btn": "%s", "d0": "%s", "d1": "%s", '
			.. '"d2": %d, "d3": %d, "next_str": %d, "next_typ": %d',
			r.path, STAGE_NAME[r.stage] or "?", r.accept or "", r.ends or "", r.calls or 0,
			hex(r.inhibit, 8), r.c1b2 or 0, r.c3b4 or 0, hex(r.btn, 4), hex(r.d0, 4), hex(r.d1, 4),
			r.d2 or -1, r.d3 or -1, r.next_str or -1, r.next_typ or -1)
	end
	return s .. "}\n"
end

-- Once a second at most, and only when something new came in.
function M.registerAfter()
	-- THE CLOCK SEES 0xFF8081 EVERY FRAME. tick() carries it past its wrap from
	-- the value it last saw, so 128 Ticks or more without a row read as going
	-- back: v11.7.25.2_14, rows 88 and 92 were 156 frames apart and the tick
	-- went from 208 to 159, and three link lines joined an HK from before that
	-- pause to an LP after it. At most 2 Ticks pass in a frame (turbo 3: 4 in 3).
	tick()
	if #pending_rows == 0 or not logging() then return end
	local now = emu.framecount()
	if now - last_write < 60 then return end
	last_write = now
	local f = io.open(LOG, started and "a" or "w")
	if f == nil then return end
	if not started then
		f:write(HEADER)
		started = true
	end
	for _, r in ipairs(pending_rows) do f:write(row_text(r)) end
	f:close()
	pending_rows = {}
end

-- For analysis/test_chain_log.lua.
function M._rows() return pending_rows end
function M._row_text(r) return row_text(r) end

return M
