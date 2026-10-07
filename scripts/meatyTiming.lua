-- MEATY TIMING: WHEN YOUR ATTACK MET THE OPPONENT'S REVERSAL TICK.
--
-- One row under Tick Data (user, 2026-10-07):
--
--   Wake-up  Reversal +0t  Active 3t
--
-- Reversal: the contact tick minus the opponent's reversal tick - the first
-- tick they can act again, on which only a guard or a special can start
-- (guardCancel.lua "WHAT IS ALLOWED ON THE FREE TICK": a special pressed on
-- free-1 comes out on free+0 in 336 of 336 spans; a normal is a tick later).
-- Active: which advancing tick of the attacker's active run touched them,
-- counted the way Tick Data counts its Active (tickData.currentRun). A move
-- whose box goes out more than once reads "Active 2:3t" from its second run
-- on - the third tick of the second run, the runs being the ones Tick Data
-- lists. "Active -" when the contact came from a projectile or a throw, whose
-- tick inside the move cannot be told.
--
-- NOT a verdict. Nothing here says a setup worked or a jump was stopped.
--
-- THE REVERSAL TICK IS THE GAME'S OWN, NOT AN INPUT TIMING. On the last tick
-- of a recovery 0x024F0A writes $04..$07 = 02 02 04 00 (the "marker" here,
-- VSAV_MEMORY_NOTES.md 5); the tick it is gone is the reversal tick - the
-- same tick Frame Meter marks in magenta. It is never the tick the dummy's
-- input went in, nor the first tick a normal could come out. Q-Bee's wake-up
-- has no marker, so it is not measured.
--
-- In the archived per-tick logs the marker lasted exactly one tick on every
-- one of 4358 recoveries (knockdown 554, guard 195, hit the rest). If it ever
-- lasts longer and a contact lands on the tick it goes, that tick cannot be
-- told from one still inside the recovery, so the recovery is left unmeasured
-- rather than called +0t.
--
-- CONTACT is the defender's hitstop ($5C) going up - the signal measured as
-- contact for jump attacks (VSAV_MEMORY_NOTES.md) - or a throw. Not $05
-- turning to 0x02: the marker tick itself carries $05 = 0x02, so a hit on the
-- reversal tick would show no edge there. Guard when the block clock ($158)
-- rose on the same tick.
--
-- WHAT IS RECORDED. For each recovery, the first contact from +0 to +30
-- ticks after its reversal tick, hit or guard. A contact outside that, a whiff,
-- or a later hit of the same string leaves the shown result alone. A new
-- recovery drops whatever was still waiting. 30 is how far to look, not how
-- long the row stays: it stays until the next result.
--
-- THE SITUATION is what was last done to the defender before the recovery: a
-- knockdown (Wake-up), a guard (After Guard), a hit (After Hit, or Air
-- Recovery when the reversal tick is in the air). A recovery that began before
-- measuring did is not measured - nothing is guessed.
--
-- Pure: no memory, no GUI, no globals. framedata.lua feeds it the same
-- snapshot Tick Data gets, after Tick Data has taken it.

local M = {}

local WINDOW = 30

local LABEL = {
	down = "Wake-up",
	guard = "After Guard",
	hit = "After Hit",
	air = "Air Recovery",
}

local prev = nil
local last_tick = nil
-- What was last done to the defender: "down" / "guard" / "hit", or nil when
-- that is not known (measuring started in the middle of something).
local latch = nil
local marker_ticks = 0
local pending = nil      -- { rev = tick, kind = latch value }
local result = nil       -- { kind, delta, active, contact }

function M.reset(reason, clear_result)
	prev = nil
	last_tick = nil
	latch = nil
	marker_ticks = 0
	pending = nil
	if clear_result then result = nil end
end

-- "3t", "2:3t", "-", or false when the contact cannot be put on the attacker.
local function active_label(s, run, contact)
	if contact == "throw" then return "-" end
	if s.p1.body_box then
		if run == nil or run.adv == nil or run.adv < 1 then return "-" end
		if (run.index or 1) >= 2 then return run.index .. ":" .. run.adv .. "t" end
		return run.adv .. "t"
	end
	-- Tick Data's box covers the attacker's projectiles when its own is not out.
	if s.p1.attack_box then return "-" end
	return false
end

-- s: the Tick Data snapshot (p1 = the measured side, p2 = the other).
-- run: tickData.currentRun() for the same tick, or nil.
function M.update(s, run)
	if type(s) ~= "table" or type(s.tick) ~= "number"
	   or type(s.p1) ~= "table" or type(s.p2) ~= "table" then
		M.reset("invalid_snapshot", false)
		return
	end
	local cur = {
		marker = s.p2.marker == true,
		hitstop = s.p2.hitstop or 0,
		block_clock = s.p2.block_clock or 0,
		status = s.p2.status or 0,
	}
	if prev ~= nil and s.tick == last_tick then return end
	if prev == nil or s.tick ~= last_tick + 1 then
		-- The first tick, or ticks were missed: nothing is carried over them.
		prev = cur
		last_tick = s.tick
		latch = nil
		pending = nil
		marker_ticks = cur.marker and 1 or 0
		return
	end
	local p = prev

	local contact = nil
	if p.status ~= 0x06 and cur.status == 0x06 then contact = "throw"
	elseif cur.block_clock > p.block_clock then contact = "block"
	elseif cur.hitstop > p.hitstop then contact = "hit" end

	-- THE REVERSAL TICK: the marker was there on the tick before and is not now.
	if p.marker and not cur.marker then
		local kind = latch
		if kind == "hit" and s.p2.airborne == true then kind = "air" end
		if kind ~= nil and not (marker_ticks >= 2 and contact ~= nil) then
			pending = { rev = s.tick, kind = kind }
		else
			pending = nil
		end
		latch = nil
	end
	if cur.marker then
		marker_ticks = (p.marker and marker_ticks or 0) + 1
	else
		marker_ticks = 0
	end

	if contact ~= nil then
		if pending ~= nil then
			local d = s.tick - pending.rev
			if d >= 0 and d <= WINDOW then
				local active = active_label(s, run, contact)
				if active ~= false then
					result = { kind = LABEL[pending.kind], delta = d, active = active,
						contact = contact }
				end
			end
			-- One contact per recovery: whatever it was, the next ones are not it.
			pending = nil
		end
		latch = (contact == "block") and "guard" or "hit"
	end
	-- Down only on top of a contact this module saw: a knockdown already
	-- running when measuring began is a recovery it did not see start.
	if s.p2.knockdown == true and latch ~= nil then latch = "down" end
	if pending ~= nil and s.tick - pending.rev > WINDOW then pending = nil end

	prev = cur
	last_tick = s.tick
end

function M.getResult() return result end
function M.isWaiting() return pending ~= nil end

function M.formatResult()
	local r = result
	if r == nil then return "" end
	return r.kind .. "  Reversal +" .. r.delta .. "t  Active " .. r.active
end

return M
