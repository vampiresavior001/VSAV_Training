-- DOES ticks_to_landing() ACTUALLY PREDICT THE TOUCHDOWN?
--
-- Goal behind the question: Sasquatch repeating forward-dash-cancel light
-- attacks, landing, and putting the NEXT dash attack out as early as the game
-- allows. A dash is a motion - F N F - so its last entry has to arrive on the
-- first actionable tick, which means the list must START several ticks before
-- that. A gate that only reacts to the landing is already too late by exactly
-- that many ticks. Prediction is not a convenience here; it is the requirement.
--
-- guardCancel.lua:1064 already carries one. It reads y, vy, ay and the floor
-- and steps the same arithmetic the ROM does (0x027402 tst.w / bpl - a rising
-- object is never "about to land"), returning ticks until y drops below the
-- floor. Auto (Landing) uses it to fire `lead` ticks early. What has never been
-- measured is whether the number it returns is RIGHT.
--
-- WHAT THIS RECORDS, per side:
--   * every tick the object is airborne and descending, the prediction made
--     that tick and the tick it was made on
--   * the tick $38 actually goes 1 -> 0
-- and then, for each prediction, the error: (tick_made + predicted) - actual.
-- Zero means exact. A constant offset means the arithmetic is right but the
-- reference point is off by that much. Scatter means it cannot be trusted.
--
-- NO FILE WRITING INSIDE THE EXEC HOOK. That is the mistake that cost a whole
-- day on 2026-09-17: io.open inside a memory.registerexec callback writes
-- nothing, silently, and the empty log was read as "the hook never ran". The
-- hook here only fills a table; the frame callback and the exit hook write it.
--
-- Run INSTEAD of the training script:
--   analysis/run_landing_predict_probe.bat        (double click)
--
-- What to do:
--   Play Sasquatch on 1P. Forward dash (a hop for her), cancel into a light
--   attack, land. Do it ten or fifteen times. Ordinary jumps count too - more
--   shapes of descent is better. The dummy's jumps are measured as well, so
--   anything it does adds samples for free.
--
-- What to look for on screen:
--   "err" is the spread of the error across every prediction. All zeros means
--   the prediction can be trusted as far ahead as it is made.

local LOG = "landing_predict_probe.log"

local P = {
	{ name = "P1", base = 0xFF8400 },
	{ name = "P2", base = 0xFF8800 },
}

-- Signed reads, matching ticks_to_landing() in guardCancel.lua.
local function sdw(a)
	local v = memory.readdword(a)
	if v >= 2147483648 then v = v - 4294967296 end
	return v
end

local function sw(a)
	local v = memory.readword(a)
	if v >= 32768 then v = v - 65536 end
	return v
end

-- The same routine, byte for byte in behaviour, so this measures the thing the
-- tool actually uses rather than a second opinion about it.
local function ticks_to_landing(base)
	local _y  = sdw(base + 0x14)
	local _vy = sdw(base + 0x44)
	local _ay = sdw(base + 0x4C)
	local _g  = sw(base + 0x3A)
	if math.floor(_y / 65536) < _g then return nil end
	for _t = 1, 60 do
		_vy = _vy + _ay
		_y  = _y + _vy
		if _vy < 0 and math.floor(_y / 65536) < _g then return _t end
	end
	return nil
end


-- Character id lives at $382 (actionSequenceEditor.lua carries the same table).
-- Results are bucketed by it so a session of ordinary play accumulates evidence
-- for every character that gets used, instead of proving it for one and leaving
-- the rest to be taken on trust.
local CHARS = {
	[0x00] = "Bulleta",  [0x01] = "Demitri",  [0x02] = "Gallon",
	[0x03] = "Victor",   [0x04] = "Zabel",    [0x05] = "Morrigan",
	[0x06] = "Anakaris", [0x07] = "Felicia",  [0x08] = "Bishamon",
	[0x09] = "Aulbath",  [0x0A] = "Sasquatch",[0x0B] = "Zabel 2",
	[0x0C] = "Q-Bee",    [0x0D] = "Lei-Lei",  [0x0E] = "Lilith",
	[0x0F] = "Jedah",    [0x12] = "Dark Gallon", [0x18] = "Oboro",
}
local by_char = {}
local function char_bucket(cid)
	if by_char[cid] == nil then
		by_char[cid] = { lands = 0, stl = {} }
	end
	return by_char[cid]
end

local want_dump = false
local state = {}
for i = 1, #P do
	state[i] = { air_last = 0, open = {}, errs = {}, lands = 0, no_pred = 0,
	             raw = {}, last_raw = nil, last_land_tick = nil,
	             near = {}, far = {},
	             frozen = 0, near_hs = {}, near_seen = {},
	             still = 0, near_still = {}, ly = nil, lvy = nil,
	             win = {} }
end

local lines = {}
local function say(s)
	lines[#lines + 1] = s
	if #lines > 12 then table.remove(lines, 1) end
end

-- Per tick, per object. Fills tables only.
memory.registerexec(0x0221CC, function()
	local a6 = memory.getregister("m68000.a6")
	for i, p in ipairs(P) do
		if a6 == p.base then
			local st = state[i]
			local tick = memory.readbyte(0xFF8081)
			local air = memory.readbyte(p.base + 0x38)

			-- HITSTOP, WHICH THE TOOL ALREADY READS ELSEWHERE.
			--
			-- tickDataVsav.lua:364 has it: $5C counts down every tick and is
			-- slammed back to 0x0B by a hit. So it is not a flag, it is the
			-- REMAINING frozen time - which is exactly what the prediction is
			-- missing. ticks_to_landing() answers in physics ticks; the wait is
			-- measured on a clock that keeps running while the physics does not.
			local hs = memory.readbyte(p.base + 0x5C)
			if hs ~= 0 then st.frozen = st.frozen + 1 end

			-- DID THE PHYSICS ACTUALLY ADVANCE?
			--
			-- $5C is the reason to expect a freeze, not proof of one. It is set
			-- on the ATTACKER too, and the +11 / +16 buckets that survived both
			-- corrections look like over-counting - ticks charged as frozen
			-- where the object in fact kept moving. Position not changing is the
			-- observation itself, so it is the yardstick the other two are
			-- measured against.
			local cy, cvy = sdw(p.base + 0x14), sdw(p.base + 0x44)
			if st.ly ~= nil and cy == st.ly and cvy == st.lvy then
				st.still = st.still + 1
			end
			st.ly, st.lvy = cy, cvy

			if air ~= 0 then
				local pred = ticks_to_landing(p.base)
				if pred ~= nil then
					st.open[#st.open + 1] = { at = tick, pred = pred,
					                          hs = hs, frozen_at = st.frozen,
					                          still_at = st.still,
					                          cid = memory.readbyte(p.base + 0x382) }
					if #st.open > 120 then table.remove(st.open, 1) end
				else
					st.no_pred = st.no_pred + 1
				end
				-- RAW SAMPLES FOR ONE DESCENT.
				--
				-- The first run came back with errors around -45 to -70, stepping
				-- by 2 with exactly two samples per value. Two samples per value
				-- says this hook fires twice per tick for one object; a step of 2
				-- per tick says the predicted time falls about three times faster
				-- than the clock it is measured against. Systematic, not scatter -
				-- so the raw pairs will name it.
				if #st.raw < 40 then
					st.raw[#st.raw + 1] = { t = tick, p = pred or -1, hs = hs,
					                        y = math.floor(sdw(p.base + 0x14) / 65536),
					                        vy = sdw(p.base + 0x44),
					                        ay = sdw(p.base + 0x4C) }
				end
			elseif st.air_last ~= 0 then
				-- TOUCHDOWN. Score every prediction made during this descent.
				st.lands = st.lands + 1
				char_bucket(memory.readbyte(p.base + 0x382)).lands =
					char_bucket(memory.readbyte(p.base + 0x382)).lands + 1
				for _, o in ipairs(st.open) do
					-- The tick counter is a byte and wraps; the descent is far
					-- shorter than 256 ticks, so the difference is unambiguous.
					local landed_in = (tick - o.at) % 256
					local err = o.pred - landed_in
					st.errs[err] = (st.errs[err] or 0) + 1
					-- BUCKET BY HOW LONG BEFORE THE LANDING, NOT BY THE ANSWER.
					--
					-- Cutting on the predicted value was wrong, and the data said
					-- so: the far bucket came back +0 four hundred times while the
					-- near one was full of -45s. A small prediction that misses by
					-- forty ticks is not a bad prediction - it is a prediction
					-- that was made and THEN invalidated, because the character
					-- went back up. Sasquatch's dash is a hop, so that happens
					-- constantly.
					--
					-- What matters is the final approach: a prediction made in the
					-- last handful of ticks can no longer be overtaken by another
					-- air action, and that is the one Auto (Landing) commits on.
					if landed_in <= 20 then
						st.near[err] = (st.near[err] or 0) + 1
						-- WHAT AN IMPLEMENTATION COULD ACTUALLY DO: add the
						-- freeze it can see right now. It cannot know about a
						-- freeze that has not started yet.
						local e_hs = (o.pred + o.hs) - landed_in
						st.near_hs[e_hs] = (st.near_hs[e_hs] or 0) + 1
						-- THE CEILING: every tick actually spent frozen between
						-- the prediction and the touchdown. If this one is +0
						-- and the other is not, freeze explains all of it and
						-- the gap is only what could not be foreseen.
						local e_seen = (o.pred + (st.frozen - o.frozen_at)) - landed_in
						st.near_seen[e_seen] = (st.near_seen[e_seen] or 0) + 1
						-- The yardstick: ticks the object provably did not move.
						local e_still = (o.pred + (st.still - o.still_at)) - landed_in
						st.near_still[e_still] = (st.near_still[e_still] or 0) + 1
						local cb = char_bucket(o.cid)
						cb.stl[e_still] = (cb.stl[e_still] or 0) + 1
						-- HOW LATE MUST THE COMMIT BE TO BE SAFE?
						--
						-- This is the question the implementation turns on. A
						-- prediction is exact for the ballistic state it was made
						-- in; what breaks it is the character changing that state
						-- afterwards - Sasquatch's hop, Q-Bee's flight. The later
						-- it is made, the less room there is for that to happen.
						--
						-- Auto (Landing) commits when the answer comes down to
						-- `lead`, so what matters is whether the window at that
						-- distance is clean. Bucketed fine near the touchdown and
						-- coarse further out.
						local w
						if landed_in <= 2 then w = "1-2"
						elseif landed_in <= 5 then w = "3-5"
						elseif landed_in <= 10 then w = "6-10"
						else w = "11-20" end
						st.win[w] = st.win[w] or {}
						st.win[w][e_still] = (st.win[w][e_still] or 0) + 1
					else
						st.far[err] = (st.far[err] or 0) + 1
					end
				end
				st.last_n = #st.open
				st.open = {}
				st.last_raw = st.raw
				st.last_land_tick = tick
				st.raw = {}
				-- The frame callback does the writing; this only asks for it.
				-- Waiting for every twentieth landing meant a sixteen landing
				-- session produced no file at all.
				want_dump = true
			end
			st.air_last = air
		end
	end
end)

local function spread(errs)
	local ks = {}
	for k in pairs(errs) do ks[#ks + 1] = k end
	table.sort(ks)
	if #ks == 0 then return "-" end
	local out = {}
	for _, k in ipairs(ks) do out[#out + 1] = string.format("%+d:%d", k, errs[k]) end
	return table.concat(out, " ")
end

-- Writing happens HERE, not in the hook.
local dumped = false
local function dump()
	if dumped then return end
	dumped = true
	local f = io.open(LOG, "a")
	if f == nil then return end
	f:write("---- landing prediction ----" .. string.char(10))
	for i, p in ipairs(P) do
		local st = state[i]
		f:write(string.format("%s  landings=%d  no_prediction_ticks=%d", p.name, st.lands, st.no_pred)
			.. string.char(10))
		f:write("   err all : " .. spread(st.errs) .. string.char(10))
		f:write("   err NEAR (made within 20 ticks of the landing): " .. spread(st.near)
			.. string.char(10))
		f:write("   err far  (made earlier, can still be invalidated): " .. spread(st.far) .. string.char(10))
		f:write("   NEAR + $5C seen at the time : " .. spread(st.near_hs) .. string.char(10))
		f:write("   NEAR + every frozen tick    : " .. spread(st.near_seen) .. string.char(10))
		f:write("   NEAR + every STILL tick     : " .. spread(st.near_still) .. string.char(10))
		f:write("   by how late the prediction was made (still-corrected):" .. string.char(10))
		for _, w in ipairs({ "1-2", "3-5", "6-10", "11-20" }) do
			f:write(string.format("     %-6s ticks before landing : %s", w,
				spread(st.win[w] or {})) .. string.char(10))
		end
		if st.last_raw ~= nil and st.last_land_tick ~= nil then
			f:write(string.format("   last descent, landed on tick %d:", st.last_land_tick)
				.. string.char(10))
			for _, r in ipairs(st.last_raw) do
				f:write(string.format("     t=%3d pred=%3d left=%3d  y=%6d vy=%8d ay=%8d",
					r.t, r.p, (st.last_land_tick - r.t) % 256, r.y, r.vy, r.ay) .. string.char(10))
			end
		end
	end
	-- PER CHARACTER, corrected the way the implementation would.
	--
	-- One character proving out says nothing about the rest: the physics values
	-- are read per object, so it SHOULD carry over, but "should" is not a
	-- measurement.
	f:write("---- per character (corrected by still ticks) ----" .. string.char(10))
	local ids = {}
	for cid in pairs(by_char) do ids[#ids + 1] = cid end
	table.sort(ids)
	for _, cid in ipairs(ids) do
		local cb = by_char[cid]
		f:write(string.format("  %-12s (%02X) landings=%-4d %s",
			CHARS[cid] or "?", cid, cb.lands, spread(cb.stl)) .. string.char(10))
	end
	f:close()
end

emu.registerbefore(function()
	-- Ten seconds of no new landing and the session is over in practice; the
	-- exit hook is the real trigger but FBNeo does not always reach it.
	if want_dump then
		want_dump = false
		dumped = false
		dump()
	end
end)

emu.registerexit(function() dumped = false dump() end)

gui.register(function()
	gui.text(4, 4, "LANDING PREDICT PROBE", 0xFFFFFFFF, 0x000000FF)
	local y = 14
	for i, p in ipairs(P) do
		local st = state[i]
		gui.text(4, y, string.format("%s  lands %d  no-pred %d", p.name, st.lands, st.no_pred),
			0xFFFF80FF, 0x000000FF)
		gui.text(4, y + 8, "  NEAR " .. spread(st.near), 0x80FF80FF, 0x000000FF)
		gui.text(4, y + 16, "  +hs  " .. spread(st.near_hs), 0x80FFFFFF, 0x000000FF)
		gui.text(4, y + 24, "  +all " .. spread(st.near_seen), 0xFFC080FF, 0x000000FF)
		gui.text(4, y + 32, "  1-2t " .. spread(st.win["1-2"] or {}), 0x80FF80FF, 0x000000FF)
		gui.text(4, y + 40, "  3-5t " .. spread(st.win["3-5"] or {}), 0xC0FF80FF, 0x000000FF)
		gui.text(4, y + 48, " 6-10t " .. spread(st.win["6-10"] or {}), 0xFFC080FF, 0x000000FF)
		y = y + 60
	end
	gui.text(4, y, "how late must the commit be? 1-2t clean = safe", 0x80C0FFFF, 0x000000FF)
	for i = 1, #lines do
		gui.text(4, y + 10 + (i - 1) * 8, lines[i], 0xC0C0C0FF, 0x000000FF)
	end
end)

say("play 1P Sasquatch: dash, cancel into a light, land. repeat.")
