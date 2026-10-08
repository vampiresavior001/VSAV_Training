-- DIAGNOSTIC: WHAT MAKES A PLAYER UNTOUCHABLE, AND Q-BEE'S WAKE-UP (2026-10-08).
--
-- Bishamon's Kirisute Gomen is invulnerable from its 1st to 13th frame (the
-- frame data tables, where its hurtboxes are not drawn), but neither Frame
-- Meter's white tile nor Show Invuln Timer showed it - both read $147 only.
-- cps2-hitboxes.lua hides a hurtbox when any of $134, $147, $11E, or $145 with
-- $1A4 = 0 is set, and draws none when the box ids $94-$96 are 0. This records
-- all of them per tick, so the one a move uses can be read off rather than
-- guessed.
--
-- Q-BEE'S HEAD SHAKE. Her wake-up ends in a 3-tick cel whose +$0B is $FE,
-- which the strike test turns away (analysis/QBEE_WAKEUP_HEADSHAKE_SURVEY.ja.md,
-- 0x018040). Read from ROM only; how it lines up with her first action, the
-- Meaty Timing base tick and Dark Force is what this log is for. Each row also
-- carries the cel pointer ($1C), its counter ($20), $23, the cel's +$08 (the
-- hurtbox map) and +$0B, hitstop ($5C), the block clock ($158), $38 (in the
-- air), $3B4, the buttons ($122) and lever ($125), the strikes the game
-- confirmed (tickDataVsav.lua, 0x018230) and the reversal tick Meaty Timing
-- is waiting on.
--
-- Knockdown Logger only, in a match. Read on the tick clock
-- (globals.truth.ticker): once per game tick, mid-tick at the frameskip read -
-- not from a registerexec, so the file can be written. BEFORE framedata (Tick
-- Data and Meaty Timing) handles the same tick: Rx calls the subscriber added
-- last first (rx.lua Subject:onNext), so mt_rev is Meaty Timing as it stood
-- after the previous tick (measured 2026-10-08: it shows one tick late).
-- A row is one player on one tick where something listed changed. The cel
-- counter alone makes a row only for Q-Bee (0x0C); for the others it counts
-- down every tick and would bury the rest.
--
-- reversal_logs/invuln_log.jsonl: one JSON object per line, the first one the
-- header. New rows are appended at most once a second from the frame callback;
-- a start of FBNeo begins a new file. analysis/archive_logs.py archives it.

local M = {}

local LOG = "reversal_logs/invuln_log.jsonl"
local PLAYERS = { 0xFF8400, 0xFF8800 }
local QBEE = 0x0C
-- Rows held while the file cannot be written; the oldest go first.
local MAX_PENDING = 20000
local pending_rows = {}
local last = { nil, nil }
local seq = 0
local started = false
local last_write = 0

local function logging()
	return globals ~= nil and globals.options ~= nil
	   and globals.options.knockdown_logger_enable == true
end
local function in_match()
	if globals == nil then return false end
	if globals.match_running ~= nil then return globals.match_running() == true end
	return globals.game_state ~= nil and globals.game_state.match_begun == true
end

-- Modules already loaded by the master script; nothing is required here.
local function loaded(name)
	return package ~= nil and package.loaded ~= nil and package.loaded[name] or nil
end
local function strike_totals(base)
	local tdv = loaded("./scripts/tickDataVsav")
	local t = type(tdv) == "table" and tdv.strike_totals and tdv.strike_totals() or nil
	t = t and t[base]
	if t == nil then return -1, -1 end
	return t.body, t.proj
end
local function meaty_waiting()
	local mt = loaded("./scripts/meatyTiming")
	local rev = type(mt) == "table" and mt.waitingSince and mt.waitingSince() or nil
	return rev or -1
end

local function read(base, rev)
	local cel = memory.readdword(base + 0x1C) or 0
	local sb, sp = strike_totals(base)
	return {
		char = memory.readbyte(base + 0x382),
		state = memory.readdword(base + 0x04),
		atk = memory.readbyte(base + 0x105),
		move = memory.readbyte(base + 0x106),
		hurt = memory.readbyte(base + 0x94) * 0x10000 + memory.readbyte(base + 0x95) * 0x100
			+ memory.readbyte(base + 0x96),
		f11e = memory.readbyte(base + 0x11E),
		f134 = memory.readbyte(base + 0x134),
		f145 = memory.readbyte(base + 0x145),
		f1a4 = memory.readbyte(base + 0x1A4),
		f147 = memory.readbyte(base + 0x147),
		f143 = memory.readbyte(base + 0x143),
		cel = cel,
		cnt = memory.readbyte(base + 0x20),
		f23 = memory.readbyte(base + 0x23),
		c08 = (cel ~= 0) and memory.readword(cel + 0x08) or 0,
		c0b = (cel ~= 0) and memory.readbyte(cel + 0x0B) or 0,
		hs = memory.readbyte(base + 0x5C),
		blk = memory.readbyte(base + 0x158),
		air = memory.readbyte(base + 0x38),
		f3b4 = memory.readbyte(base + 0x3B4),
		btn = memory.readbyte(base + 0x122),
		dir = memory.readbyte(base + 0x125),
		sb = sb,
		sp = sp,
		mt_rev = rev,
	}
end

local FIELDS = { "char", "state", "atk", "move", "hurt", "f11e", "f134", "f145", "f1a4", "f147", "f143",
	"cel", "f23", "c08", "c0b", "hs", "blk", "air", "f3b4", "btn", "dir", "sb", "sp", "mt_rev" }

local function same(a, b)
	if a == nil or b == nil then return false end
	for _, k in ipairs(FIELDS) do
		if a[k] ~= b[k] then return false end
	end
	if a.char == QBEE and a.cnt ~= b.cnt then return false end
	return true
end

function M.on_tick(tick)
	seq = seq + 1
	if not logging() or not in_match() then
		last = { nil, nil }
		return
	end
	local rev = meaty_waiting()
	for p = 1, 2 do
		local v = read(PLAYERS[p], rev)
		if not same(v, last[p]) then
			v.seq, v.tick, v.p = seq, tonumber(tick) or -1, p
			pending_rows[#pending_rows + 1] = v
			if #pending_rows > MAX_PENDING then table.remove(pending_rows, 1) end
		end
		last[p] = v
	end
end

function M.registerStart()
	if globals ~= nil and globals.truth ~= nil and globals.truth.ticker ~= nil then
		globals.truth.ticker:subscribe(function(tick) M.on_tick(tick) end)
	end
end

local function hex(n, w) return string.format("0x%0" .. w .. "X", n) end

local HEADER = '{"log": "invuln_log", "version": 2, '
	.. '"read_at": "tick clock (rawStateService ticker): once per game tick, mid-tick at the frameskip read, '
	.. 'before framedata (Tick Data, Meaty Timing) handles the same tick", '
	.. '"tick": "the ticker count; mt_rev is in the same ticks but as of the previous tick", '
	.. '"rows": "one player on one tick where a listed value changed; cnt ($20) alone makes a row only for Q-Bee (char 0x0C)", '
	.. '"sb_sp": "running totals of strikes the game confirmed at 0x018230 by this player\'s body / projectiles on the other player", '
	.. '"mt_rev": "the reversal tick Meaty Timing is waiting on (the opponent of Tick Data Side), -1 if none"}\n'

local function row_text(r)
	return string.format(
		'{"seq": %d, "tick": %d, "p": %d, "char": "%s", "state": "%s", "atk": %d, "move": "%s", '
		.. '"hurt": "%s", "f11e": %d, "f134": %d, "f145": %d, "f1a4": %d, "f147": %d, "f143": %d, '
		.. '"cel": "%s", "cnt": %d, "f23": "%s", "c08": %d, "c0b": "%s", "hs": %d, "blk": %d, '
		.. '"air": %d, "f3b4": %d, "btn": "%s", "dir": "%s", "sb": %d, "sp": %d, "mt_rev": %d}\n',
		r.seq, r.tick, r.p, hex(r.char, 2), hex(r.state, 8), r.atk, hex(r.move, 2),
		hex(r.hurt, 6), r.f11e, r.f134, r.f145, r.f1a4, r.f147, r.f143,
		hex(r.cel, 6), r.cnt, hex(r.f23, 2), r.c08, hex(r.c0b, 2), r.hs, r.blk,
		r.air, r.f3b4, hex(r.btn, 2), hex(r.dir, 2), r.sb, r.sp, r.mt_rev)
end

-- Once a second at most, and only when something new came in.
function M.registerAfter()
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

return M
