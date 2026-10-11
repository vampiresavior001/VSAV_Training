-- WHAT THE GAME'S SEQUENCE COMMAND RECOGNIZER DID (2026-10-11).
--
-- The observation side of analysis/COMMAND_TRAINER_DESIGN.ja.md (section 4):
-- the exec hooks on the commands' own calls into the shared recognizer
-- 0x02A0C8, and the rows built from them. Two readers: Knockdown Logger's file
-- (below), and commandTrainer.lua, which draws the Command Trainer from the
-- same rows. registerexec keeps one callback per address, so the hooks live
-- here only.
--
-- The ten commands that call the recognizer from a move check (M.PROFILES).
-- Each is called from its character's move check with the block (player +
-- block) in A4 and the table's wrapper as the JSR target
-- (analysis/sequence_command_evidence.json):
--   call   the JSR. Read before it: the block (+0 phase, +1 step offset, +4
--          timer) and $1AC, the press edges the recognizer compares with the
--          step (an exact match - nothing else may start that tick).
--   ret    the instruction after it: D0 (1 = command complete), the block again.
--   start  the RTS after the move id and the state were written: the move
--          started. Reached only when the meter and state tests passed.
-- Darkness Illusion, Luminous Illusion and Midnight Pleasure were checked on
-- the machine (VSAV_MEMORY_NOTES, section 9: every timer 14-19, expiry on the
-- T-th call, the next step within T-1); the other seven were read from the
-- ROM only, and their start paths test more than the meter and the state
-- ($38 on the ground, $149, $14C, the opponent's $1A0 and the like).
--
-- A row is one call that changed something: a step accepted, the command
-- complete, the timer run out, a press edge that was not the step waited for,
-- or the block found cleared between two calls by something else. Calls that
-- only counted the timer down make no row; "calls" on the next row says how
-- many calls there were since the last row, that one included.
--
-- The file: Knockdown Logger only. Gathered in the exec hooks, written from
-- the frame callback - io.open cannot write from inside an exec hook.
-- reversal_logs/command_log.jsonl: one JSON object per line, the first one the
-- header. A start of FBNeo begins a new file. analysis/archive_logs.py
-- archives it; analysis/command_log_summary.py reads it.

local M = {}

-- In the Command Trainer row's order (menu.lua): index 2 is the first one.
-- Grouped by character. The settings file keeps the index, so the order is
-- fixed once released.
-- The ten calls into the recognizer found in the ROM (analysis/
-- SEQUENCE_COMMAND_ROM_SURVEY.ja.md, sequence_command_evidence.json): the
-- block, the JSR, the RTS after the move id, checked against the disassembly
-- by analysis/test_command_log.lua. Steps: the table words & $770F; 1 back,
-- 2 forward, 4 down, 8 up, relative to facing.
local LP, MP, HP, LK, MK, HK = 0x0100, 0x0200, 0x0400, 0x1000, 0x2000, 0x4000
local BACK, FWD, DOWN, UP = 0x0001, 0x0002, 0x0004, 0x0008
M.PROFILES = {
	{ key = "di", name = "Darkness Illusion", char = 0x05, char_name = "Morrigan",
	  block = 0x330, call = 0x039802, ret = 0x039808, start = 0x0399A2, move = 0x08,
	  steps = { LP, LP, FWD, LK, HP } },
	{ key = "fs", name = "Finishing Shower", char = 0x05, char_name = "Morrigan",
	  block = 0x300, call = 0x0397F4, ret = 0x0397FA, start = 0x0398EC, move = 0x00,
	  steps = { MP, LP, BACK, LK, MK } },
	{ key = "cn", name = "Cryptic Needle", char = 0x05, char_name = "Morrigan",
	  block = 0x340, call = 0x0397D8, ret = 0x0397DE, start = 0x0399D0, move = 0x0A,
	  steps = { FWD, HP, MP, LP, FWD } },
	{ key = "li", name = "Luminous Illusion", char = 0x0E, char_name = "Lilith",
	  block = 0x348, call = 0x04DCFA, ret = 0x04DD00, start = 0x04DDA4, move = 0x18,
	  steps = { LP, LP, FWD, LK, HP } },
	{ key = "mp", name = "Midnight Pleasure", char = 0x01, char_name = "Demitri",
	  block = 0x330, call = 0x02FF9C, ret = 0x02FFA2, start = 0x030134, move = 0x14,
	  steps = { LP, MP, FWD, MK, MK } },
	-- Dark Gallon (0x12) shares Gallon's animations (idleSound.lua); taken to
	-- share this code too. If it did not, the hooks would simply stay quiet.
	{ key = "ms", name = "Moment Slice", char = 0x02, chars = { 0x02, 0x12 }, char_name = "Gallon",
	  block = 0x340, call = 0x031D36, ret = 0x031D3C, start = 0x031EC0, move = 0x06,
	  steps = { LP, MP, FWD, LK, MK } },
	{ key = "pm", name = "Pharaoh Magic", char = 0x06, char_name = "Anakaris",
	  block = 0x340, call = 0x03B88A, ret = 0x03B890, start = 0x03BA98, move = 0x10,
	  steps = { MK, LP, DOWN, LK, MP } },
	{ key = "ps", name = "Pharaoh Salvation", char = 0x06, char_name = "Anakaris",
	  block = 0x348, call = 0x03B86E, ret = 0x03B874, start = 0x03BAD4, move = 0x14,
	  steps = { HK, MP, DOWN, MK, HP } },
	{ key = "pd", name = "Pharaoh Decoration", char = 0x06, char_name = "Anakaris",
	  block = 0x358, call = 0x03B87C, ret = 0x03B882, start = 0x03BB10, move = 0x1C,
	  steps = { HK, MP, LK, DOWN, LP, MK, HP } },
	{ key = "tr", name = "Tenraiha", char = 0x0D, char_name = "Lei-Lei",
	  block = 0x330, call = 0x04B364, ret = 0x04B36A, start = 0x04B4EA, move = 0x0C,
	  steps = { LK, HK, MP, MP, UP } },
}

local LOG = "reversal_logs/command_log.jsonl"
local PLAYERS = { [0xFF8400] = 1, [0xFF8800] = 2 }
-- Rows held while the file cannot be written; the oldest go first.
local MAX_PENDING = 20000
local pending_rows = {}
local seq = 0
local started = false
local last_write = 0
local listener, listener_wants = nil, nil

local function logging()
	return globals ~= nil and globals.options ~= nil
	   and globals.options.knockdown_logger_enable == true
end
local function active()
	return logging() or (listener_wants ~= nil and listener_wants() == true)
end
-- guardCancel's 0x0221CC hook adds one each time it runs for P1: one clock for
-- both players (design section 4). -1 before that hook has run.
local function tick()
	return (globals ~= nil and globals.p1_tick_seq) or -1
end

-- commandTrainer.lua's way in: every row goes to fn as it is made, while
-- wants() says the trainer is on.
function M.set_listener(fn, wants)
	listener, listener_wants = fn, wants
end

local function player()
	local a6 = memory.getregister("m68000.a6")
	return PLAYERS[a6], a6
end

local function hooks_for(prof)
	local n = #prof.steps
	-- Per player: what the call read, how the last call left the block, and
	-- the calls since the last row.
	local S = { { calls = 0 }, { calls = 0 } }
	local function block(base)
		local b = base + prof.block
		return memory.readbyte(b), memory.readbyte(b + 1), memory.readbyte(b + 4)
	end
	-- c: the block and edges as the call read them; ph2..tm2: as it left them.
	local function push(p, base, kind, c, ph2, st2, tm2, d0)
		local s = S[p]
		local step = -1
		if kind == "complete" then step = n
		elseif kind == "step" then step = st2 / 2
		elseif c ~= nil then step = (c.ph ~= 0) and (c.st / 2 + 1) or 1 end
		seq = seq + 1
		local r = {
			seq = seq, tick = tick(), frame = emu.framecount(), p = p, cmd = prof.key,
			kind = kind, step = step,
			edge = c and c.edge or memory.readword(base + 0x1AC),
			held = c and c.held or memory.readword(base + 0x12A),
			ph = c and c.ph or -1, st = c and c.st or -1, tm = c and c.tm or -1,
			ph2 = ph2 or -1, st2 = st2 or -1, tm2 = tm2 or -1, d0 = d0 or -1,
			calls = s.calls,
			meter = memory.readbyte(base + 0x109),
			state = memory.readdword(base + 0x04),
			move = memory.readbyte(base + 0x106),
			face = memory.readbyte(base + 0x0B),
			char = memory.readbyte(base + 0x382),
		}
		s.calls = 0
		if listener ~= nil then listener(r) end
		if logging() then
			pending_rows[#pending_rows + 1] = r
			if #pending_rows > MAX_PENDING then table.remove(pending_rows, 1) end
		end
	end

	local function on_call()
		if not active() then return end
		local p, base = player()
		if p == nil then return end
		local s = S[p]
		local ph, st, tm = block(base)
		-- Cleared since the last call by something other than the recognizer
		-- (a hit, another state, a state load). Not an expiry (design section 4).
		if s.after ~= nil and s.after.ph ~= 0 and ph == 0 then
			push(p, base, "cleared", s.after, ph, st, tm, nil)
		end
		s.calls = s.calls + 1
		s.at_call = { ph = ph, st = st, tm = tm,
		              edge = memory.readword(base + 0x1AC), held = memory.readword(base + 0x12A) }
	end

	local function on_return()
		if not active() then return end
		local p, base = player()
		if p == nil then return end
		local s = S[p]
		local c = s.at_call
		s.at_call = nil
		local ph, st, tm = block(base)
		s.after = { ph = ph, st = st, tm = tm }
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

	local function on_started()
		if not active() then return end
		local p, base = player()
		if p ~= nil then push(p, base, "started", nil, nil, nil, nil, nil) end
	end

	return on_call, on_return, on_started
end

function M.registerStart()
	-- registerexec holds one callback per address; registering again on a
	-- reload replaces these rather than adding more. No other script hooks
	-- these addresses (analysis/test_command_log.lua).
	for _, prof in ipairs(M.PROFILES) do
		local on_call, on_return, on_started = hooks_for(prof)
		memory.registerexec(prof.call, on_call)
		memory.registerexec(prof.ret, on_return)
		memory.registerexec(prof.start, on_started)
	end
end

local function hex(n, w) return string.format("0x%0" .. w .. "X", n) end

local HEADER = '{"log": "command_log", "version": 2, '
	.. '"cmd": "commandLog.lua PROFILES: di fs cn (Morrigan), li (Lilith), mp (Demitri), ms (Gallon), '
	.. 'pm ps pd (Anakaris), tr (Lei-Lei)", '
	.. '"hooks": "per command: the JSR into the recognizer, the instruction after it, the RTS after the move was written", '
	.. '"block": "player+block: ph +0 phase (0 = waiting for step 1), st +1 step offset (2 per accepted step), tm +4 timer; '
	.. 'ph/st/tm as the call read them, ph2/st2/tm2 as it left them", '
	.. '"kind": "step = a step accepted (step = its number), complete = D0 1 (the last step), expired = the timer ran out waiting for step, '
	.. 'miss = a press edge that was not step, cleared = the block was 0 at a call after the last call left it waiting, '
	.. 'started = the move was written (step -1)", '
	.. '"edge": "$1AC, the press edges the recognizer compares; held: $12A", '
	.. '"calls": "recognizer calls by this player for this command since its last row, this one included", '
	.. '"tick": "globals.p1_tick_seq (one per run of the 0x0221CC hook for P1), -1 before it runs", '
	.. '"face": "+$0B, 1 facing right", "meter": "$109", "move": "$106", "state": "$04-$07"}\n'

local function row_text(r)
	return string.format(
		'{"seq": %d, "tick": %d, "frame": %d, "p": %d, "cmd": "%s", "kind": "%s", "step": %d, '
		.. '"edge": "%s", "held": "%s", "ph": %d, "st": %d, "tm": %d, "ph2": %d, "st2": %d, "tm2": %d, '
		.. '"d0": %d, "calls": %d, "meter": %d, "state": "%s", "move": "%s", "face": "%s", "char": "%s"}\n',
		r.seq, r.tick, r.frame, r.p, r.cmd, r.kind, r.step,
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
