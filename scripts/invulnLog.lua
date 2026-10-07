-- DIAGNOSTIC: WHICH BYTE MAKES A MOVE INVULNERABLE (2026-10-08).
--
-- Bishamon's Kirisute Gomen is invulnerable from its 1st to 13th frame (the
-- frame data tables, where its hurtboxes are not drawn), but neither Frame
-- Meter's white tile nor Show Invuln Timer shows it - both read $147 only.
-- cps2-hitboxes.lua hides a hurtbox when any of $134, $147, $11E, or $145 with
-- $1A4 = 0 is set, and draws none when the box ids $94-$96 are 0. This records
-- all of them per tick, so the one the move uses can be read off rather than
-- guessed.
--
-- Knockdown Logger only, in a match. Recorded from the tick clock
-- (globals.truth.ticker) - not from a registerexec, so the file can be
-- written - and only the ticks on which a player's values changed, to
-- reversal_logs/invuln_log.json, at most once a second.

local M = {}

local PLAYERS = { 0xFF8400, 0xFF8800 }
local MAX_ROWS = 3000
local rows = {}
local last = { nil, nil }
local seq = 0
local dirty = false
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

local function read(base)
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
	}
end

local FIELDS = { "char", "state", "atk", "move", "hurt", "f11e", "f134", "f145", "f1a4", "f147", "f143" }

local function same(a, b)
	if a == nil or b == nil then return false end
	for _, k in ipairs(FIELDS) do
		if a[k] ~= b[k] then return false end
	end
	return true
end

function M.on_tick()
	seq = seq + 1
	if not logging() or not in_match() then
		last = { nil, nil }
		return
	end
	for p = 1, 2 do
		local v = read(PLAYERS[p])
		if not same(v, last[p]) then
			v.seq, v.p = seq, p
			rows[#rows + 1] = v
			if #rows > MAX_ROWS then table.remove(rows, 1) end
			dirty = true
		end
		last[p] = v
	end
end

function M.registerStart()
	if globals ~= nil and globals.truth ~= nil and globals.truth.ticker ~= nil then
		globals.truth.ticker:subscribe(function() M.on_tick() end)
	end
end

local function hex(n, w) return string.format("0x%0" .. w .. "X", n) end

-- Once a second at most, and only when something new came in.
function M.registerAfter()
	if not dirty or not logging() then return end
	local now = emu.framecount()
	if now - last_write < 60 then return end
	last_write = now
	dirty = false
	local f = io.open("reversal_logs/invuln_log.json", "w")
	if f == nil then return end
	f:write("{\n  \"note\": \"per-tick values that can make a player invulnerable; a row only when one changed\",\n")
	f:write("  \"rows\": [\n")
	for i, r in ipairs(rows) do
		f:write(string.format(
			"    {\"seq\": %d, \"p\": %d, \"char\": \"%s\", \"state\": \"%s\", \"atk\": %d, \"move\": \"%s\", \"hurt\": \"%s\", \"f11e\": %d, \"f134\": %d, \"f145\": %d, \"f1a4\": %d, \"f147\": %d, \"f143\": %d}%s\n",
			r.seq, r.p, hex(r.char, 2), hex(r.state, 8), r.atk, hex(r.move, 2), hex(r.hurt, 6),
			r.f11e, r.f134, r.f145, r.f1a4, r.f147, r.f143, i < #rows and "," or ""))
	end
	f:write("  ]\n}\n")
	f:close()
end

return M
