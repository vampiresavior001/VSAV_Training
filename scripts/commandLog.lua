-- DIAGNOSTIC: WHAT DARKNESS ILLUSION'S COMMAND RECOGNIZER DID (2026-10-11).
--
-- The read-only probe of analysis/COMMAND_TRAINER_DESIGN.ja.md (section 4),
-- for one command: Morrigan's Darkness Illusion, LP LP forward LK HP. It logs
-- what the game's own recognizer did with the inputs, not what the inputs
-- looked like, from four places in Morrigan's move check:
--   0x039802  JSR $29E7A: the shared recognizer 0x02A0C8 with the table at
--             0x02A6CE and the block player+$330 in A4. Read before the call:
--             the block (+0 phase, +1 step offset, +4 timer) and $1AC, the
--             press edges the recognizer compares with the step.
--   0x039808  the instruction after the call: D0 (1 = command complete) and
--             the block again.
--   0x03997E  reached only when D0 was 1; the meter test ($109) is next.
--   0x0399A2  the RTS after the move id (8) and the state were written: the
--             move started.
-- What it is for (design section 7): the timer each accepted step sets at +4
-- (14-19 by the table at 0x02A55A as the listing reads it - this confirms it
-- or not), how many calls go by before it runs out, and telling a completed
-- command from a started move (no meter).
--
-- A row is one call that changed something: a step accepted, the command
-- complete, the timer run out, a press edge that was not the step waited for,
-- or the block found cleared between two calls by something else. Calls that
-- only counted the timer down make no row; "calls" on the next row says how
-- many calls there were since the last row, that one included.
--
-- Knockdown Logger only. Gathered in the exec hooks, written from the frame
-- callback - io.open cannot write from inside an exec hook.
-- reversal_logs/command_log.jsonl: one JSON object per line, the first one the
-- header. A start of FBNeo begins a new file. analysis/archive_logs.py
-- archives it; analysis/command_log_summary.py reads it.

local M = {}

local LOG = "reversal_logs/command_log.jsonl"
local PLAYERS = { [0xFF8400] = 1, [0xFF8800] = 2 }
local BLOCK = 0x330
M.CALL, M.RETURN, M.MET, M.STARTED = 0x039802, 0x039808, 0x03997E, 0x0399A2
-- Rows held while the file cannot be written; the oldest go first.
local MAX_PENDING = 20000
local pending_rows = {}
local seq = 0
local started = false
local last_write = 0
-- Per player: what the call read, how the last call left the block, and the
-- calls since the last row.
local at_call = { nil, nil }
local after = { nil, nil }
local calls = { 0, 0 }

local function logging()
	return globals ~= nil and globals.options ~= nil
	   and globals.options.knockdown_logger_enable == true
end
-- guardCancel's 0x0221CC hook adds one each time it runs for P1: one clock for
-- both players (design section 4). -1 before that hook has run.
local function tick()
	return (globals ~= nil and globals.p1_tick_seq) or -1
end

local function player()
	local a6 = memory.getregister("m68000.a6")
	return PLAYERS[a6], a6
end
local function block(base)
	local b = base + BLOCK
	return memory.readbyte(b), memory.readbyte(b + 1), memory.readbyte(b + 4)
end

-- c: the block and edges as the call read them; ph2..tm2: as it left them.
local function push(p, base, kind, c, ph2, st2, tm2, d0)
	seq = seq + 1
	local step = -1
	if kind == "complete" then step = 5
	elseif kind == "step" then step = st2 / 2
	elseif c ~= nil then step = (c.ph ~= 0) and (c.st / 2 + 1) or 1 end
	pending_rows[#pending_rows + 1] = {
		seq = seq, tick = tick(), frame = emu.framecount(), p = p, kind = kind, step = step,
		edge = c and c.edge or memory.readword(base + 0x1AC),
		held = c and c.held or memory.readword(base + 0x12A),
		ph = c and c.ph or -1, st = c and c.st or -1, tm = c and c.tm or -1,
		ph2 = ph2 or -1, st2 = st2 or -1, tm2 = tm2 or -1, d0 = d0 or -1,
		calls = calls[p],
		meter = memory.readbyte(base + 0x109),
		state = memory.readdword(base + 0x04),
		move = memory.readbyte(base + 0x106),
		face = memory.readbyte(base + 0x0B),
		char = memory.readbyte(base + 0x382),
	}
	if #pending_rows > MAX_PENDING then table.remove(pending_rows, 1) end
	calls[p] = 0
end

local function on_call()
	if not logging() then return end
	local p, base = player()
	if p == nil then return end
	local ph, st, tm = block(base)
	local prev = after[p]
	-- Cleared since the last call by something other than the recognizer (a
	-- hit, another state, a state load). Not an expiry (design section 4).
	if prev ~= nil and prev.ph ~= 0 and ph == 0 then
		push(p, base, "cleared", prev, ph, st, tm, nil)
	end
	calls[p] = calls[p] + 1
	at_call[p] = { ph = ph, st = st, tm = tm,
	               edge = memory.readword(base + 0x1AC), held = memory.readword(base + 0x12A) }
end

local function on_return()
	if not logging() then return end
	local p, base = player()
	if p == nil then return end
	local c = at_call[p]
	at_call[p] = nil
	local ph, st, tm = block(base)
	after[p] = { ph = ph, st = st, tm = tm }
	if c == nil then return end
	-- moveq #1 / #0 just before the RTS (0x02A580 / 0x02A57A, 0x02A57C).
	local d0 = memory.getregister("m68000.d0") % 0x100
	local kind
	if d0 == 1 then
		kind = "complete"
	elseif ph ~= 0 and (c.ph == 0 or st ~= c.st) then
		kind = "step"
	elseif c.ph ~= 0 and ph == 0 then
		kind = "expired"
	elseif c.edge ~= 0 then
		kind = "miss"
	end
	if kind ~= nil then push(p, base, kind, c, ph, st, tm, d0) end
end

local function on_met()
	if not logging() then return end
	local p, base = player()
	if p ~= nil then push(p, base, "met", nil, nil, nil, nil, nil) end
end

local function on_started()
	if not logging() then return end
	local p, base = player()
	if p ~= nil then push(p, base, "started", nil, nil, nil, nil, nil) end
end

function M.registerStart()
	-- registerexec holds one callback per address; registering again on a
	-- reload replaces these rather than adding more. No other script hooks
	-- these four (analysis/test_command_log.lua).
	memory.registerexec(M.CALL, on_call)
	memory.registerexec(M.RETURN, on_return)
	memory.registerexec(M.MET, on_met)
	memory.registerexec(M.STARTED, on_started)
end

local function hex(n, w) return string.format("0x%0" .. w .. "X", n) end

local HEADER = '{"log": "command_log", "version": 1, "command": "Darkness Illusion (Morrigan): LP LP forward LK HP", '
	.. '"hooks": "0x039802 call, 0x039808 return, 0x03997E command complete (meter test next), 0x0399A2 move started", '
	.. '"block": "player+$330: ph +0 phase (0 = waiting for step 1), st +1 step offset (2 per accepted step), tm +4 timer; '
	.. 'ph/st/tm as the call read them, ph2/st2/tm2 as it left them", '
	.. '"kind": "step = a step accepted (step = its number), complete = D0 1 (step 5), expired = the timer ran out waiting for step, '
	.. 'miss = a press edge that was not step, cleared = the block was 0 at a call after the last call left it waiting, '
	.. 'met = 0x03997E reached, started = 0x0399A2 reached (step -1 on these two)", '
	.. '"edge": "$1AC, the press edges the recognizer compares; held: $12A", '
	.. '"calls": "recognizer calls by this player since its last row, this one included", '
	.. '"tick": "globals.p1_tick_seq (one per run of the 0x0221CC hook for P1), -1 before it runs", '
	.. '"face": "+$0B, the facing byte per the design (unverified)", "meter": "$109", "move": "$106", "state": "$04-$07"}\n'

local function row_text(r)
	return string.format(
		'{"seq": %d, "tick": %d, "frame": %d, "p": %d, "kind": "%s", "step": %d, '
		.. '"edge": "%s", "held": "%s", "ph": %d, "st": %d, "tm": %d, "ph2": %d, "st2": %d, "tm2": %d, '
		.. '"d0": %d, "calls": %d, "meter": %d, "state": "%s", "move": "%s", "face": "%s", "char": "%s"}\n',
		r.seq, r.tick, r.frame, r.p, r.kind, r.step,
		hex(r.edge, 4), hex(r.held, 4), r.ph, r.st, r.tm, r.ph2, r.st2, r.tm2,
		r.d0, r.calls, r.meter, hex(r.state, 8), hex(r.move, 2), hex(r.face, 2), hex(r.char, 2))
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

-- For analysis/test_command_log.lua.
function M._rows() return pending_rows end

return M
