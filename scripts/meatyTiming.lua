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
-- input went in, nor the first tick a normal could come out.
--
-- Q-BEE'S WAKE-UP HAS NO MARKER (user, 2026-10-08: "Wake-up  Actionable +Nt").
-- Her last wake-up cel (the head shake) puts her straight back to 0x02000002
-- while the cel still turns ordinary strikes away (+$0B = $FE), and every
-- action - specials, normals, Dark Force, jumps, dashes - starts on the tick
-- after (40 of 40 measured, QBEE_WAKEUP_HEADSHAKE_SURVEY.ja.md 9). So her base
-- is that next tick: the first tick she can start anything, which is what the
-- reversal tick is for a special. Read here as a knockdown recovery ending
-- ($05 0x02 -> 0x00) without the marker, in a cel with that +$0B. A
-- character that goes through the marker never matches: on its reversal tick
-- the cel no longer has it (measured, Demitri).
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
-- WHOSE CONTACT (2026-10-08). $5C also rises when the DEFENDER's attack hits:
-- an invulnerable reversal that struck you while your box was out read as your
-- meaty, with your active tick. Where the game's own strike confirmations are
-- there (tickDataVsav.lua, STRIKES THE GAME CONFIRMED), a rise on which they
-- struck you and you struck nothing ends the wait and reads "P2 Hit First"
-- (the side that struck; user, 2026-10-08) - their answer landed first, and
-- the row says so rather than keeping the last meaty, which read as this
-- exchange's. The active tick is given for a strike by your
-- body; a strike by a projectile is "-", even with your own box out. A guard
-- ($158) needs no confirmation: they can only be guarding yours.
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
-- LANDED (user, 2026-11-21). After a wake-up only: the tick your jump landed,
-- counted from the opponent's reversal tick, so a safe jump can be read
-- against their reversal's startup ("Landed Rev+2t"). Asked for because in
-- VSAV a jump-in has no landing recovery to speak of: on the landing tick of
-- a jump and of a jump attack the game runs its guard check (0x022ABA,
-- 0x022C54 call 0x027694 right after $38 is cleared).
--
--   Wake-up  Reversal +0t  Active 3t  Landed Rev+2t   touched them, landed +2
--   Wake-up  Landed Rev-3t  No Contact               landed before they woke
--   Wake-up  Landed Rev+1t  No Contact               landed after, untouched
--
-- WITHOUT THE HITSTOP. A jump attack that touches them freezes you for its
-- hitstop and lands that much later; against an invulnerable reversal it
-- touches nothing and lands on time, which is the landing that matters. So
-- after a contact the landing is the contact tick plus the ticks the game's
-- own physics had left at that tick (tickDataVsav.lua, land_in) - exact for
-- jumps that hit nothing (design_landing_prediction.md, 2026-09-18). Without
-- a contact it is the tick $38 went to 0.
--
-- Not for air specials (0x0E / 0x10 / 0x12 seen in the air): their landing
-- has recovery. A landing before the reversal tick counts only for a jump
-- that took off after the knockdown, within 30 ticks of the reversal tick;
-- one after it, within the same 30. A later contact keeps the landing.
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
local pending = nil      -- { rev = tick, kind = latch value, landed = ticks or nil }
local result = nil       -- { kind, delta, active, contact, landed, no_contact }
-- The attacker's jump in progress: { after_down, special, land = tick or nil }.
local jump = nil
-- A landing of a jump that took off after the knockdown, before the reversal
-- tick came: the tick it landed.
local early_land = nil

function M.reset(reason, clear_result)
	prev = nil
	last_tick = nil
	latch = nil
	marker_ticks = 0
	pending = nil
	jump = nil
	early_land = nil
	if clear_result then result = nil end
end

-- "3t", "2:3t", "-", or false when the contact cannot be put on the attacker.
local function active_label(s, run, contact)
	if contact == "throw" then return "-" end
	if s.strikes_known == true then
		-- The game said which object struck: the body's tick only for the body.
		if s.p1.struck_body == true then
			if not s.p1.body_box or run == nil or run.adv == nil or run.adv < 1 then return "-" end
			if (run.index or 1) >= 2 then return run.index .. ":" .. run.adv .. "t" end
			return run.adv .. "t"
		end
		if s.p1.struck_proj == true then return "-" end
		-- Neither (a guard, which needs no confirmation): read the boxes below.
	end
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
		cel_flag = s.p2.cel_flag or 0,
		air = s.p1.airborne == true,
	}
	if prev ~= nil and s.tick == last_tick then return end
	if prev == nil or s.tick ~= last_tick + 1 then
		-- The first tick, or ticks were missed: nothing is carried over them.
		prev = cur
		last_tick = s.tick
		latch = nil
		pending = nil
		jump = nil
		early_land = nil
		marker_ticks = cur.marker and 1 or 0
		return
	end
	local p = prev

	local contact = nil
	if p.status ~= 0x06 and cur.status == 0x06 then contact = "throw"
	elseif cur.block_clock > p.block_clock then contact = "block"
	elseif cur.hitstop > p.hitstop then contact = "hit" end
	-- WHOSE CONTACT (see the top): theirs only when the game says they struck
	-- you and you did not strike them. A rise with neither confirmed (a path
	-- the hook does not see) is taken as before.
	local theirs = false
	if s.strikes_known == true and contact == "hit" then
		local mine = s.p1.struck_body == true or s.p1.struck_proj == true
		theirs = not mine and s.p1.was_struck == true
	end

	-- THE REVERSAL TICK: the marker was there on the tick before and is not now.
	if p.marker and not cur.marker then
		local kind = latch
		if kind == "hit" and s.p2.airborne == true then kind = "air" end
		if kind ~= nil and not (marker_ticks >= 2 and contact ~= nil) then
			pending = { rev = s.tick, kind = kind, base = "Reversal" }
		else
			pending = nil
		end
		latch = nil
	-- Q-Bee's wake-up (see the top): based on the tick after this one.
	elseif not p.marker and latch == "down" and p.status == 0x02 and cur.status == 0x00
	       and cur.cel_flag >= 0x80 and cur.cel_flag ~= 0xFF then
		pending = { rev = s.tick + 1, kind = "down", base = "Actionable" }
		latch = nil
	end
	if cur.marker then
		marker_ticks = (p.marker and marker_ticks or 0) + 1
	else
		marker_ticks = 0
	end
	-- A landing that came before the reversal tick (LANDED, at the top).
	if pending ~= nil and not pending.seen then
		pending.seen = true
		if pending.kind == "down" and early_land ~= nil and pending.rev - early_land <= WINDOW then
			pending.landed = early_land - pending.rev
			result = { kind = LABEL.down, landed = pending.landed, no_contact = true }
		end
		early_land = nil
	end

	-- THE JUMP: takeoff, an air special in it, and the landing.
	-- AFTER THE KNOCKDOWN HIT, NOT AFTER $1A7 (user, 2026-11-21: an early
	-- landing showed nothing). All 33 jump-ins of the first play test took off
	-- 9 to 28 ticks before the knockdown flag came on - it rises well after the
	-- hit that knocks down - so a jump that took off after the last contact
	-- counts, the flag or not.
	if cur.air and not p.air then
		jump = { after_down = latch ~= nil, special = false }
	end
	if jump ~= nil and cur.air and s.p1.special == true then jump.special = true end
	if jump ~= nil and p.air and not cur.air then
		local L = jump.land or s.tick
		if not jump.special then
			if pending ~= nil then
				local d = L - pending.rev
				if pending.kind == "down" and d <= WINDOW then
					pending.landed = d
					result = { kind = LABEL.down, landed = d, no_contact = true }
				end
			elseif latch ~= nil and jump.after_down then
				-- Kept for the reversal tick, which uses it for a wake-up only.
				early_land = L
			end
		end
		jump = nil
	end

	if contact ~= nil then
		-- Where this jump would have landed had it touched nothing: the first
		-- contact's tick plus the physics left at it (LANDED, at the top).
		local landed = pending and pending.landed or nil
		local in_recovery = pending ~= nil
		if jump ~= nil and cur.air and contact ~= "throw" and not theirs
		   and not jump.special and s.p1.special ~= true and type(s.p1.land_in) == "number" then
			jump.land = jump.land or (s.tick + s.p1.land_in)
			if pending ~= nil and pending.kind == "down" then landed = jump.land - pending.rev end
		end
		if pending ~= nil then
			local d = s.tick - pending.rev
			if d >= 0 and d <= WINDOW then
				if theirs then
					-- Their attack struck you first: no meaty, and the row says so.
					result = { kind = LABEL[pending.kind], base = pending.base, delta = d,
						first = true, contact = contact, landed = pending.landed }
				else
					local active = active_label(s, run, contact)
					if active ~= false then
						result = { kind = LABEL[pending.kind], base = pending.base, delta = d,
							active = active, contact = contact, landed = landed }
					end
				end
			end
			-- One contact per recovery: whatever it was, the next ones are not it.
			pending = nil
		end
		latch = (contact == "block") and "guard" or "hit"
		early_land = nil
		-- A contact outside a recovery (the hit that knocks down, say) comes
		-- after the takeoff of any jump still in the air: that jump does not
		-- count before the reversal tick.
		if jump ~= nil and not in_recovery then jump.after_down = false end
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
-- The reversal tick being waited on (in the ticks update was given), or nil.
-- For the diagnostic log (invulnLog.lua).
function M.waitingSince() return pending and pending.rev or nil end

-- opponent: the side the defender is on ("P1" / "P2"), for "P2 Hit First".
function M.formatResult(opponent)
	local r = result
	if r == nil then return "" end
	local landed = ""
	if r.landed ~= nil then
		landed = "Landed Rev" .. (r.landed < 0 and "-" or "+") .. math.abs(r.landed) .. "t"
	end
	if r.no_contact then return r.kind .. "  " .. landed .. "  No Contact" end
	local head = r.kind .. "  " .. (r.base or "Reversal") .. " +" .. r.delta .. "t  "
	if landed ~= "" then landed = "  " .. landed end
	if r.first then return head .. (opponent or "P2") .. " Hit First" .. landed end
	return head .. "Active " .. r.active .. landed
end

return M
