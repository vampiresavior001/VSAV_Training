-- RUNS AN ACTION SEQUENCE.
--
-- A WAIT NAMES THE TICK THE STEP COMES OUT ON.
--
--     1  Jump forward          on free+0, the first tick the dummy can act
--     2  Air dash        +5    the dash HAPPENS five ticks after the jump
--     3  Attack MP       +5    the press LANDS five ticks after the dash
--
-- Not when the step starts wiggling the stick. A forward dash is F N F, so a
-- wait of five puts its last F on tick five and the two before it earlier -
-- the list is laid backwards from the tick that was asked for. That is the
-- same shape as the arm, which places a reversal's press on free+0 and puts
-- the motion in ahead of it, and it is the only way to name the tick a move
-- actually appears on.
--
-- Step one is placed by guardCancel's arm; its wait is the press offset in
-- kd_delay_ticks, which already works this way. Everything after it is placed
-- here, on the tick clock.
--
-- ONE STEP IS ONE INPUT LIST, NEVER CONCATENATED.
--
-- The waits could in principle be blank entries inside one long list, since
-- that is how make_input_sequence's delay_before already expresses a delay.
-- That was tried and it does not work, for a reason worth keeping written
-- down:
--
--     IT DID NOT COME OUT AT ALL. queue_input_sequence refuses to hold a
--     sequence that presses a button before its last entry (controller.lua,
--     "Pre-buffering"), and a joined list does exactly that as soon as step two
--     is an attack. Without the hold there is no kd_tick and no blk_hold, the
--     free-1 signature hook skips anything that is not held, and the whole
--     reversal silently produced nothing.
--
-- Kept apart, every list is one motion with at most one button on its last
-- entry, which is the shape the hold was written for.
local M = {}

local WAIT_AUTO = -1
local TIMING_CHAIN = "chain"
-- LATE CHAIN IS GONE, AND THE REASON IS WORTH KEEPING.
--
-- It asked for the terminal animation cel while the gate above it required
-- contact, and those are never true together - so it never fired once. Rebuilt
-- on measurement it still could not be made honest: the window is the contact
-- flag $39, nothing on either side counts that window down (the first
-- candidate, $5C, counts ONE hit's stop and the window spans several), and
-- without a countdown "the last tick of the window" cannot be known before it
-- has passed.
--
-- The row is not offered any more. A saved step that used it is migrated to
-- Chain by the editor - see the note there. Finding the last tick is what a
-- numeric Wait is for, and it is how the value was found while investigating
-- this (user, 2026-09-05).
local TIMING_CANCEL = "cancel"
local TIMING_LATE_CANCEL = "late_cancel"
local TIMING_LANDING = "landing"
-- RAPID FIRE - 連打キャンセル - IS NOT A CHAIN, AND THE ROM SAYS SO OUTRIGHT.
--
-- The normal-attack handler at 0x028E42 calls 0x028FB0 BEFORE it tests contact
-- ($39) or the chain inhibit ($1B2), and on success branches past both. So a
-- light attack repeating into itself needs neither a hit nor a clear inhibit -
-- it comes out on whiff, which is what mashing a jab does.
--
-- 0x028FB0, condition for condition:
--
--   tst.b  ($38,A6)   bne fail      airborne - ground only
--   move.b ($111,A6) / cmp.b ($110,A6) / bne fail
--   btst   #0, ($21,A6)  beq fail   this animation cel accepts it
--   move.w ($126,A6), andi #$7700   a button edge is present
--   bit = ($102>>1)+8, +4 if $101   ... and it is THE SAME BUTTON
--   btst   bit, D0     beq fail
--   st     ($11a,A6)                 flagged, D2/D3 keep strength and family
--
-- The bit numbers are the six attack buttons: 8 LP, 9 MP, 10 HP, 12 LK, 13 MK,
-- 14 HK. Same strength ($102 = 0/2/4) and same family ($101 = 0 punch,
-- 2 kick) as the move already out, which is why this only ever repeats the
-- button that started it.
--
-- $126 is the PRESS EDGE, computed at 0x0221B4 from $122 AND NOT $124 - after
-- the tool's own hook at 0x02211A and before the state dispatch. A press put in
-- at the hook is therefore seen by the same tick's test, and $21 read there is
-- the value that tick's test uses (VSAV_MEMORY_NOTES, "ティック内の順序").
--
-- Which cels carry bit 0 is animation data, not a rule about strength: the ROM
-- never looks at $102 to decide whether rapid fire is allowed, only to work out
-- which button counts. So the gate below asks the cel, not the strength.
local TIMING_RAPID = "rapid"

-- The three that are timed off a HIT. Landing is not one of them: it is timed
-- off the floor, takes no contact, and must not eat the one a mode behind it
-- is waiting for.
local HIT_TIMED = {
	[TIMING_CHAIN] = true,
	[TIMING_CANCEL] = true, [TIMING_LATE_CANCEL] = true,
}

-- The modes that wait to CONNECT to the move in front of them, and so can be
-- missed. Landing is not one: the floor always arrives. Rapid fire is, even
-- though it needs no hit - its cel window belongs to a move that ends.
local CONNECT_TIMED = {
	[TIMING_CHAIN] = true, [TIMING_RAPID] = true,
	[TIMING_CANCEL] = true, [TIMING_LATE_CANCEL] = true,
}

-- The four motions a dash attack can come out of.
local DASH_MOTION = {
	["forward dash"] = true, ["back dash"] = true,
	["forward dash cancel"] = true, ["back dash cancel"] = true,
}

-- The action ids that are a dash ON THE GROUND, and so have a measured
-- dash-attack offset. air.f and air.b are deliberately absent: they send the
-- same input, but the number does not apply to them.
--
-- "dash" is the pre-split id. The editor rewrites it on open, but a settings
-- file that has not been opened since still runs, and it was always a ground
-- dash.
local GROUND_DASH = {
	["dash.f"] = true, ["dash.b"] = true,
	["dashc.f"] = true, ["dashc.b"] = true,
	["dash"] = true,
}

local AIR_DASH_ID = { ["air.f"] = true, ["air.b"] = true }

-- A plain jump only. A super jump goes higher and takes longer to leave the
-- ground, so its floor is a different measurement and there is not one yet.
local JUMP_ID = { ["jump.n"] = true, ["jump.f"] = true, ["jump.b"] = true }

-- MEASURED STEP FLOORS. THE WHOLE CAST, ALL FOUR DASHES.
--
-- DASH_AUTO_TICKS (guardCancel) are ARM-path press offsets. The step path is
-- not always the same distance from the move, so these were measured on their
-- own: step two's Wait walked down in the game until the move stopped coming
-- out. Same unit and same meaning as the number the menu takes.
--
-- WHY THIS IS DATA AND NOT A FORMULA.
--
-- The plain dashes very nearly are one - the arm value minus one on 25 of the
-- 28 cells - and that is the exact shape that has already cost this project
-- four wrong generalisations (see AIR_DASH_TICKS). The three cells that break
-- it are measured like the rest:
--
--   Jedah        f and b level with the arm, not one under
--   Sasquatch    f two under
--
-- The cancels have no shape at all. Against the arm table they run from
-- Aulbath's fc four under to Gallon's nine over, with Morrigan two under and
-- Anakaris level in between. The fallback in auto_ticks_for adds two for a
-- cancel, which matches no character in this table.
--
-- Every character with an arm row has a row here, so that fallback no longer
-- fires for anyone who can dash at all. It is left in place for a character
-- who has neither row.
--
-- Keyed by $382, then the same four fields DASH_AUTO_TICKS uses, so the two
-- tables can be read side by side. A hit here overrides the fallback, and a
-- 0 is a value - Zabel's whole row is zeros.
local STEP_FLOOR_FIELD = {
	["forward dash"]        = "f",
	["back dash"]           = "b",
	["forward dash cancel"] = "fc",
	["back dash cancel"]    = "bc",
}

local MEASURED_STEP_FLOORS = {
	--                      f    b    fc   bc
	[0x00] = { name = "Bulleta",   f =  4, b =  4, fc =  4, bc =  4 },
	-- Demitri, at the user's instruction. He has no row in DASH_AUTO_TICKS -
	-- both his dashes are uninterruptible, so there is no dash attack to time -
	-- and a character with no row there falls back to 0 on the arm path. Zero
	-- here keeps the two paths saying the same thing about him instead of the
	-- step path answering "Not Measured" to a question the arm path answers.
	[0x01] = { name = "Demitri",   f =  0, b =  0, fc =  0, bc =  0 },
	[0x02] = { name = "Gallon",    f =  7, b =  2, fc = 15, bc = 10 },
	[0x03] = { name = "Victor",    f =  4, b =  4, fc =  4, bc =  4 },
	[0x04] = { name = "Zabel",     f =  0, b =  0, fc =  0, bc =  0 },
	[0x05] = { name = "Morrigan",  f = 11, b = 11, fc = 11, bc = 11 },
	[0x06] = { name = "Anakaris",  f =  4, b =  4, fc =  3, bc =  3 },
	[0x07] = { name = "Felicia",   f =  7, b =  7, fc =  7, bc =  7 },
	[0x08] = { name = "Bishamon",  f =  5, b =  2, fc =  4, bc =  2 },
	[0x09] = { name = "Aulbath",   f =  5, b =  0, fc =  0, bc =  0 },
	[0x0A] = { name = "Sasquatch", f =  0, b =  0, fc =  8, bc =  8 },
	[0x0C] = { name = "Q-Bee",     f =  5, b =  5, fc =  6, bc =  6 },
	[0x0D] = { name = "Lei-Lei",   f =  0, b =  4, fc =  0, bc =  0 },
	[0x0E] = { name = "Lilith",    f =  4, b =  4, fc =  4, bc =  4 },
	[0x0F] = { name = "Jedah",     f = 10, b = 10, fc = 10, bc = 10 },
}

-- AUTO AFTER A GROUND DASH IS THE MEASURED VALUE, AS IS.
--
-- The ground Auto is "the dummy is doing nothing", and a dash is something, so
-- Auto after a dash would wait for the dash to END - not a dash attack.
--
-- The table's number and this wait share an origin, once the arm's own +1 is
-- accounted for:
--
--     arm      press at free-1 + kd_press_base() + DASH_AUTO_TICKS
--              (a dash is not in SPECIAL_MOTION, so the base is 1)
--              -> the button lands on free + DASH_AUTO_TICKS
--     here     the anchor is the tick the dash's own last tap went in, and
--              that tap IS step one's press: free-1 + kd_press_base() + 0
--              -> step two lands on anchor + WAIT = free + WAIT
--
-- The same moment therefore asks WAIT = DASH_AUTO_TICKS, with nothing
-- subtracted. An earlier reading subtracted one, on the grounds that the two
-- origins were a tick apart - but the tick it named is the one
-- kd_press_base() already adds, and subtracting it again put the attack a
-- tick early: Jedah's forward dash showed Auto (9) while Delay Auto on the
-- same dash measured 10. The table's own contract ("a value here and the
-- same number typed into the menu behave identically") is what this follows
-- now. Nothing new is estimated: DASH_AUTO_TICKS is already measured for
-- every character and all four dashes.
--
-- Folding the pair into the arm's own delay instead was tried and does not
-- produce the move, even though the logs show that machinery doing exactly
-- what it is supposed to.
local P2_BASE = 0xFF8800
-- The game's own tick counter for P2, incremented once per tick. Deltas are
-- taken mod 256 the same way the rest of guardCancel.lua does it.
local P2_TICKS = 0xFF8081

-- The action ids the editor writes, and what each one is made of. Kept here
-- rather than in the editor because this is the side that has to produce
-- input; the editor only has to name things.
local ACTIONS = {
	["neutral"]  = { motion = "none" },
	["walk.f"]   = { motion = "forward" },
	["walk.b"]   = { motion = "back" },
	["crouch.d"] = { motion = "down" },
	["crouch.f"] = { motion = "down-forward" },
	["crouch.b"] = { motion = "down-back" },
	["dash.f"]   = { motion = "forward dash" },
	["dash.b"]   = { motion = "back dash" },
	["dashc.f"]  = { motion = "forward dash cancel" },
	["dashc.b"]  = { motion = "back dash cancel" },
	-- Same input as a ground dash. The id is what keeps the ground dash-attack
	-- table off the Auto that follows it - see GROUND_DASH below.
	["air.f"]    = { motion = "forward dash" },
	["air.b"]    = { motion = "back dash" },
	["jump.n"]   = { motion = "up" },
	["jump.f"]   = { motion = "up-forward" },
	["jump.b"]   = { motion = "up-back" },
	["sj.n"]     = { motion = "super jump" },
	["sj.f"]     = { motion = "super jump forward" },
	["sj.b"]     = { motion = "super jump back" },
}
for _, b in ipairs({ "LP", "MP", "HP", "LK", "MK", "HK" }) do
	ACTIONS["n." .. b] = { motion = "none", button = b }
	ACTIONS["c." .. b] = { motion = "down", button = b }
end

-- The two strings a step is made of. Kept beside the compiled input list
-- because guardCancel does not only need the list: it asks what the motion IS
-- to decide the press tick, and which button to press when an entry carries
-- none. Those questions used to be answered by the Reversal Input rows, which
-- in sequence mode describe something else entirely.
-- A NAMED SPECIAL, AND THE TWO SHAPES ITS COMMAND COMES IN.
--
-- The registry in charMoves is the source (seq_special_command). A `motion`
-- move is an ordinary motion plus a button and goes through the same path a
-- Custom step does. A `sequence` move is a list of input steps - MP LP 4 LK MK -
-- which make_input_sequence has no name for, and which is the whole reason this
-- action exists: Custom cannot express it.
--
-- Read live rather than resolved at edit time. A saved step keeps the NAME, so
-- correcting a command in the registry corrects every list that uses it, and a
-- list saved under one dummy still names its move under another.
local SPECIAL_PREFIX = "sp."

local function special_command(step)
	local id = tostring(step.action or "")
	if id:sub(1, #SPECIAL_PREFIX) ~= SPECIAL_PREFIX then return nil end
	if seq_special_command == nil then return nil end
	return seq_special_command(id:sub(#SPECIAL_PREFIX + 1))
end

-- ELECTRIC BUTTONS ARE ORDINARY BUTTONS THAT STAY DOWN.
--
-- Victor's medium and heavy normals gain the electric property when the button
-- is kept down (Mizuumi writes them 5[MP] and 2[MP]). "Elec.MP" is that MP:
-- the input is the same, and what is different is that it is held for
-- ELEC_HOLD_TICKS afterwards. Everything below therefore sees a plain button
-- name, and compile is the only place that knows about the hold.
-- HOW LONG THE BUTTON STAYS DOWN.
--
-- Not a duration anyone measured: it is an upper bound. guardCancel drops the
-- hold the moment the next step starts delivering, so in a list this reads as
-- "until the next step", and the number only decides the LAST step - and the
-- one case with nothing after it.
--
-- Eight was tried first and was wrong for a chain. Measured, all three links of
-- a chain held for the same nine ticks and only the first came out electric
-- (user, 2026-09-05): a chained move starts inside the previous one's hit stop,
-- where the attacker's script does not advance, so nine ticks of real time
-- moved the move's own frames barely at all and the game never reached the
-- frame where it looks at the button.
--
-- Thirty ticks is about twenty-two displayed frames at turbo 3, which clears an
-- ordinary hit stop with room to spare, and every electric normal's own
-- animation is longer than that - so the bound cannot outlast the move it
-- belongs to, whatever comes after it (user, 2026-09-05).
--
-- The two cases are not the same length of hold and never were: whiffed, the
-- move runs at once and eight ticks were enough; out of a chain the hold has to
-- outlast a hit stop first. One bound covers both because the next step takes
-- the hold away as it starts.
local ELEC_HOLD_TICKS = 30
local function elec_button(b)
	if type(b) ~= "string" then return nil end
	return b:match("^Elec%.(%u%u)$")
end

local function step_parts(step)
	-- Assembled from parts: an attack is a direction and a button, a custom
	-- step the same with motions allowed in place of the direction.
	if step.action == "custom" or step.action == "atk"
	   or step.action == "dash" then
		local b = step.button or "none"
		return step.lever or "none", elec_button(b) or b
	end
	local sp = special_command(step)
	if sp ~= nil then
		-- A repeat names no motion either, but it DOES take a button - the
		-- strength is the player's. Same shape as a sequence for every other
		-- caller: not nil, so the step reads as compilable.
		if sp.type == "repeat" then return step.action, step.button or "none" end
		-- A sequence carries its own buttons, so there is no button to name and
		-- the motion is not one make_input_sequence knows. step_inputs takes it
		-- from here; what matters to every OTHER caller of step_parts is that
		-- this is not nil, which would read as "this step cannot be compiled".
		if sp.type == "sequence" then return step.action, "none" end
		return sp.motion, step.button or "none"
	end
	local a = ACTIONS[step.action]
	if a == nil then return nil end
	return a.motion, a.button or "none"
end

local function step_inputs(step, mis)
	local sp = special_command(step)
	if sp ~= nil and sp.type == "repeat" then
		-- One press, built by make_input_sequence so PPP/KKK expand the same way
		-- they do everywhere else, then repeated with a neutral between. The
		-- gap is what gives each press after the first an edge.
		local _b = step.button
		if _b == nil or _b == "none" then return nil end
		local one = mis("none", _b, "", 0)
		if one == nil or one[1] == nil then return nil end
		local out = {}
		for i = 1, (sp.count or 4) do
			local e = {}
			for j, k in ipairs(one[1]) do e[j] = k end
			out[#out + 1] = e
			if i < (sp.count or 4) then out[#out + 1] = {} end
		end
		return out
	end
	if sp ~= nil and sp.type == "sequence" then
		-- ALREADY IN THE WALKER'S OWN SHAPE. One inner table is one tick and its
		-- members are simultaneous, which is exactly what an entry is - so the
		-- list is copied, not converted. Copied because the registry is shared
		-- and a compiled schedule must not be able to write back into it.
		local out = {}
		for i, e in ipairs(sp.sequence) do
			local entry = {}
			for j, k in ipairs(e) do entry[j] = k end
			out[i] = entry
		end
		return out
	end
	local motion, button = step_parts(step)
	if motion == nil then return nil end
	return mis(motion, button, "", 0)
end
-- COMMON GROUND-NORMAL CONNECTION WINDOWS (VSAV ROM).
-- 0x028E42 handles chains.  A contact ($39), no chain inhibit ($1B2), and a
-- later button in LP,LK,MP,MK,HP,HK are required.  The final chain check is
-- made while the terminal cell has $21 bit 6 and $20 == 1.
local CHAIN_RANK = { LP = 1, LK = 2, MP = 3, MK = 4, HP = 5, HK = 6 }
-- THE RECORD THE WALKER HOLDS, NOT THE EDITOR'S STEP.
--
-- service_body walks compiled entries, and a compiled entry has no `action`:
-- compile already resolved the motion and the button through step_parts, which
-- is also where the legacy n.MP / c.HP ids are turned into a button. Reading
-- step.action here therefore always found nil, next_rank was always nil, and
-- no chain ever armed - measured by driving a two-step list with every ROM
-- condition set to its passing value and seeing step two never delivered.
local function normal_button(step)
	if step == nil then return nil end
	local b = step.button
	if b == nil or b == "none" then return nil end
	return b
end

-- ONE CONNECTION PER CONTACT.
--
-- $39 stays non-zero for the whole of a hit stop, so a mode that only asks
-- "is there contact" arms again on the very next tick - and the step after it
-- goes in during the SAME hit stop as the one before. Measured in game:
-- light -> medium chains, medium -> heavy does not, because the heavy is
-- pressed inside the medium's hit stop before the medium has connected and
-- produced a stop of its own.
--
-- The attacker's own script is frozen for that whole stop ($164 does not
-- advance during hit stop - see VSAV_MEMORY_NOTES "$158 を硬直の基準に使っては
-- いけない理由"), so nothing about the character changes to tell the two
-- moments apart. What does change is the contact itself: it ends.
--
-- So a timing-gated step consumes the contact it fired on, and the next one
-- waits for a fresh one. No count of frames anywhere - the game says when the
-- stop is over by clearing $39.
local contact_used = false
-- THE DIRECTION THE LAST TIMING STEP PRESSED, STILL DOWN.
--
-- A step in the middle of the list keeps its direction after the press without
-- anyone arranging it: the NEXT step is already waiting with the same lever.
-- The last step has nothing behind it, so the direction came off on the tick
-- after the press - and a press the game did not take as a chain is read later
-- as a fresh normal, by which time the crouch is gone. That is the standing
-- heavy at the end of a list that was crouching all the way to it.
--
-- Held to the end of the contact and no further. The schedule-empty drop that
-- guards seq_held_lever exists so the dummy is not left leaning on a direction
-- once the list is done; clearing this when $39 goes back to 0 keeps that
-- promise without needing to count anything.
local held_after = nil

-- ONE CONNECTION PER CEL WINDOW, FOR THE SAME REASON.
--
-- Rapid fire takes no contact, so contact_used cannot guard it. What it does
-- take is a cel whose flags carry bit 0, and that is equally a window with an
-- end: the animation moves on. So a rapid step consumes the window it fired
-- on, and the next one waits for the flag to drop and come back.
--
-- Without this the gate stays open for the rest of the cel and the whole list
-- goes out one tick apart - the same failure contact_used was written for.
local rapid_used = false
-- Seen busy since this step reached the head of the queue. See timing_missed.
local gate_busy_seen = false

-- Bit 0 of the cel flags. Lua 5.1 here has no bit library, and $21 is one byte.
local function rapid_cel_open()
	return (memory.readbyte(P2_BASE + 0x21) % 2) == 1
end

-- Called every tick from service_body, before the gates are asked.
local function refresh_contact()
	if memory.readbyte(P2_BASE + 0x39) == 0 then
		contact_used = false
		held_after = nil
	end
	if not rapid_cel_open() then rapid_used = false end
end

-- True while this hit stop has already sent a step out.
local function contact_spent()
	return contact_used
end
local function chain_ready(step)
	if contact_spent() then return false end
	local next_rank = CHAIN_RANK[normal_button(step)]
	if next_rank == nil then return false end
	if memory.readbyte(P2_BASE + 0x06) ~= 0x0A then return false end
	if memory.readbyte(P2_BASE + 0x39) == 0 then return false end
	if memory.readbyte(P2_BASE + 0x1B2) ~= 0 then return false end
	local strength = memory.readbyte(P2_BASE + 0x102)
	local family = memory.readbyte(P2_BASE + 0x101)
	if strength ~= 0 and strength ~= 2 and strength ~= 4 then return false end
	local current_rank = strength + ((family == 0) and 1 or 2)
	if next_rank <= current_rank then return false end
	return true
end

-- WHICH BUTTON THE ROM WOULD COUNT AS A REPEAT, RIGHT NOW.
--
-- 0x028FD8 builds the bit from the move already out - ($102>>1)+8, plus 4 for
-- a kick - so the only press rapid fire accepts is the same strength and the
-- same family. Named here instead of compared as a bit so the refusal is
-- readable: LP repeats LP, nothing else does.
local RAPID_STRENGTH = { [0] = "L", [2] = "M", [4] = "H" }
local function rapid_button_now()
	local s = RAPID_STRENGTH[memory.readbyte(P2_BASE + 0x102)]
	if s == nil then return nil end
	local family = memory.readbyte(P2_BASE + 0x101)
	if family == 0 then return s .. "P" end
	if family == 2 then return s .. "K" end
	return nil
end

-- Every condition 0x028FB0 tests, and none it does not.
--
-- No contact test and no $1B2: the caller branches past both on success. No
-- test on strength either - whether this cel allows a repeat is the cel's own
-- flag, and asking "is it a light attack" here would be a second, invented
-- rule that disagrees with the game wherever the animation data does.
local function rapid_ready(step)
	if rapid_used then return false end
	local b = normal_button(step)
	if b == nil then return false end
	if memory.readbyte(P2_BASE + 0x06) ~= 0x0A then return false end
	-- $38: rapid fire is ground only. An air chain is the other routine.
	if memory.readbyte(P2_BASE + 0x38) ~= 0 then return false end
	-- The ROM wants these two equal. They are the Dark Force pair - 0x027008
	-- sets both when it starts, 0x022526 clears $110 alone when its timer runs
	-- out - so they are equal until Dark Force has been used and has ended.
	if memory.readbyte(P2_BASE + 0x110) ~= memory.readbyte(P2_BASE + 0x111) then
		return false
	end
	if b ~= rapid_button_now() then return false end
	-- NOT DURING HIT STOP, AND THIS IS WHY RAPID FIRE AND CHAIN DIFFER.
	--
	-- 0x022552 tests $5C first: non-zero decrements it and branches to
	-- 0x0225D0, jumping over the $06 dispatch at 0x0225C4. So for the whole hit
	-- stop the normal-attack handler - and 0x028FB0 with it - never runs.
	--
	-- Chain survives that because 0x028E76 reads $12E, the LATCHED button word,
	-- which keeps a press until the handler next looks. Rapid fire reads $126
	-- alone, and $126 is one tick's press edge (0x0221B4, $122 AND NOT $124).
	-- A press made during hit stop is therefore thrown away.
	--
	-- Measured by the user on Zabel's crouching LP: on whiff the repeat came
	-- out, on hit it never did. The gate had opened inside the stop, because
	-- the animation is frozen there and $21 keeps whatever flags it had.
	if memory.readbyte(P2_BASE + 0x5C) ~= 0 then return false end
	return rapid_cel_open()
end

-- Ordinary special cancels use countdown $167 (standard specials) or $168
-- (the second, mostly non-sequence EX, permission path).  Sequence-command
-- supers use another gate and are deliberately left to the game.  Auto Cancel
-- starts on contact so hit-stop receives the whole command.  Late Cancel uses
-- the last window guaranteed by both ordinary paths because a Custom action
-- does not identify a move ID before the game recognizes it.
local function ordinary_cancel_window()
	local a = memory.readbyte(P2_BASE + 0x167)
	local b = memory.readbyte(P2_BASE + 0x168)
	if a == 0 then return b end
	if b == 0 then return a end
	return math.min(a, b)
end
local function cancel_ready(step, late)
	if contact_spent() then return false end
	if memory.readbyte(P2_BASE + 0x06) ~= 0x0A then return false end
	if not late then
		-- Do not reject $119 here: sequence-command supers are allowed after a
		-- chain and the game, not the runner, owns that distinction.
		return memory.readbyte(P2_BASE + 0x39) ~= 0
	end
	-- The $167/$168 ordinary gates reject chain-started normals themselves.
	if memory.readbyte(P2_BASE + 0x119) ~= 0 then return false end
	local window = ordinary_cancel_window()
	return window > 0 and window <= (step.lead + 1)
end

-- WHAT AN Auto RESOLVES TO, IN ONE PLACE.
--
-- The editor prints this number on the row and the compiler schedules from it,
-- and they have already drifted apart once: the editor asked which MOTION came
-- before, which cannot tell an air dash from a ground one, so the row said
-- Auto (0) while the schedule used the state test. Both call this now.
--
-- nil means "no number" - Auto stays the state test, which is a real answer and
-- not a missing one.
-- prev2 is the step before prev - needed only for the attack after an air
-- dash, whose floor depends on which JUMP the dash came out of.
-- WHERE "Recovered" WOULD BE A LIE.
--
-- Auto's state test is "the dummy has finished what it was doing", and after an
-- ATTACK that is exactly the earliest - measured on Jedah's air chain at 25 and
-- 24, and confirmed again on his air dash into two attacks.
--
-- After a jump, a ground dash or an air dash it is not. The dummy is mid-arc or
-- mid-dash, and "finished" comes much later than the tick the next thing can be
-- put in. The number for those comes from a measured table, and where the table
-- has no entry the honest answer is that nobody has measured it - not a word
-- that promises the earliest.
function M.auto_needs_number(prev)
	if prev == nil then return false end
	return GROUND_DASH[prev.action] == true
	    or AIR_DASH_ID[prev.action] == true
	    or JUMP_ID[prev.action] == true
end

function M.auto_ticks_for(prev, step, prev2)
	if prev == nil or step == nil then return nil end

	-- After a ground dash, the Auto resolves to a number: how many ticks after
	-- the dash's own last tap (the anchor) the attack's press lands.
	--
	-- MEASURED STEP FLOORS COME FIRST. Walking step two's Wait down in the
	-- game until the move stops coming out is the only measurement that
	-- describes this exact path; where the character has been measured, that
	-- number is the answer and the arm-derived fallback below is not consulted
	-- (see MEASURED_STEP_FLOORS above).
	--
	-- Fallback derivation, for characters nobody has measured yet: the arm's
	-- press lands at free-1 + kd_press_base() + DASH_AUTO_TICKS, and
	-- kd_press_base() already covers the tick between the free-1 signature
	-- and the dash's own last tap - so the wait asks for DASH_AUTO_TICKS with
	-- nothing subtracted. A dash cancel adds two more: its reverse direction
	-- cannot go in before the dash exists (v207).
	if GROUND_DASH[prev.action] then
		local pm = step_parts(prev)
		if pm == nil or not DASH_MOTION[pm] then return nil end
		local _row = MEASURED_STEP_FLOORS[memory.readbyte(0xFF8B82)]
		if _row ~= nil then
			-- Long-hand because these values can be 0 - Zabel's row is all
			-- zeros - and `a and b or c` on a zero field is the shape that
			-- went wrong in v194.
			local _v = _row[STEP_FLOOR_FIELD[pm]]
			if _v ~= nil then return _v end
		end
		if dash_attack_ticks_for == nil then return nil end
		local n = dash_attack_ticks_for(pm)
		if n == nil then return nil end
		if seq_dash_cancel_reverse ~= nil and seq_dash_cancel_reverse[pm] ~= nil then
			return n + 2
		end
		return n
	end

	-- After an air dash: measured, per character.
	--
	-- This was a flat 0, argued from the ground offset only existing because the
	-- press has to land INSIDE the dash. Zabel and Q-Bee both measure 0 so the
	-- argument held up, and then Lei-Lei measured 5 - at 4 the LP does not come
	-- out. A number nobody measured is a number that happens to be right.
	if AIR_DASH_ID[prev.action] then
		if air_dash_attack_ticks_for == nil then return nil end
		if prev2 == nil or not JUMP_ID[prev2.action] then return nil end
		return air_dash_attack_ticks_for(prev2.action, prev.action)
	end

	-- Jump into air dash: measured per character AND per pair of directions.
	-- Zabel is 8 forward-into-forward and as-soon-as-possible back-into-forward,
	-- so the jump's direction is part of the question.
	if JUMP_ID[prev.action] and AIR_DASH_ID[step.action] then
		if air_dash_ticks_for == nil then return nil end
		return air_dash_ticks_for(prev.action, step.action)
	end

	return nil
end

-- HOW MANY TICKS THE WALKER SPENDS ON ONE ENTRY.
--
-- Mirrors the pacing in guardCancel's seq_tick walker, which is v158's rule: a
-- buttonless press has to exist for two ticks or the game does not take it -
-- the second tap of a dash is exactly that case - while an entry that presses
-- a button goes in for one tick, so a chain-cancellable normal is not swung
-- twice.
local function entry_cost(e)
	if #e == 0 then return 1 end
	for _, k in ipairs(e) do
		if k ~= "forward" and k ~= "back" and k ~= "up" and k ~= "down"
		   and k ~= "h_charge" and k ~= "v_charge" then
			return 1
		end
	end
	return 2
end

-- A HELD DIRECTION HAS NO PRESS EDGE.
--
-- A forward jump ends holding forward, Pose can hold a direction on its own,
-- and a block holds back. If the next step opens with a direction that is
-- already down, the game sees no new press and the step's first tap simply
-- does not exist - which is why the air dash came out only sometimes. It is
-- the same reason the back dash and the super jump from crouch carry a leading
-- neutral in controller.lua.
--
-- So a step that opens with a direction gets one, and under a NUMBERED wait it
-- costs nothing in timing: the wait names the tick the step comes out on, lead
-- grows by one, and the list starts one tick earlier to land in the same place.
--
-- NOT WHEN THE DIRECTION ARRIVES WITH A BUTTON.
--
-- Under Auto there is nothing to start early from - the tick is a state test,
-- not a count, and the future is not visible - so every entry in front of the
-- last one pushes the press that many ticks past free+0. Measured on the case
-- that found this: dash MP, then Auto crouching LP, is a link the dummy has to
-- take on the frame it recovers, and the leading neutral made it free+1.
--
-- It also bought nothing there. The neutral exists to give a DIRECTION a press
-- edge; when the direction arrives together with a button, the edge is the
-- button's and the direction only has to be held at that instant - a level the
-- game reads from $122, not an edge from $126. A dash, a jump, a walk and a
-- command motion all open on a bare direction and still get theirs.
--
-- Step one is left alone. It is the reversal itself, placed by machinery that
-- has been measured against the trigger in a way nothing here has.
local function opens_with_direction(list)
	local e = list[1]
	if e == nil then return false end
	local dir = false
	for _, k in ipairs(e) do
		if k == "forward" or k == "back" or k == "up" or k == "down"
		   or k == "h_charge" or k == "v_charge" then
			dir = true
		else
			return false      -- a button rides along: it carries the edge
		end
	end
	return dir
end

-- The directions in a list's LAST entry, buttons stripped. This is what a Hold
-- keeps asserting once the step has been delivered.
--
-- Returned as an entry (a list of names) rather than as bits, because the bits
-- depend on which way the dummy is facing and that is only known at the tick it
-- is written - entry_to_bits in guardCancel reads the facing each time.
local DIRECTION_NAME = {
	["forward"] = true, ["back"] = true, ["up"] = true, ["down"] = true,
}

local function hold_lever(list)
	local last = list[#list]
	if last == nil then return nil end
	local out = {}
	for _, k in ipairs(last) do
		if DIRECTION_NAME[k] then out[#out + 1] = k end
	end
	if #out == 0 then return nil end
	return out
end
-- THE LEVER GOES IN WHILE THE BUTTON IS STILL WAITING.
--
-- A chain step sits at the head of the queue for the whole of the previous
-- move's hit stop, and its lever used to arrive on the same tick as its button.
-- Auto (After) is fine that way - the dummy is free and the crouch registers -
-- but inside a hit stop the attacker's script is frozen ($164 does not advance,
-- see VSAV_MEMORY_NOTES) and the one tick is not enough: the button came out
-- standing.
--
-- So the direction is asserted for the whole wait, which is how the chain is
-- played by hand. Nothing is added to the input list, so `lead` stays 0 and the
-- button still lands on the tick the gate opens - the reason a leading entry
-- was NOT used here.
--
-- ONLY A PLAIN DIRECTIONAL ATTACK. One entry carrying a direction and a button
-- is the case that needs it. A command motion is a sequence of taps whose own
-- first entry is the start of the motion, and holding a direction in front of
-- that would corrupt it.
local function waiting_step_lever(step)
	if step == nil or step.timing == nil then return nil end
	local list = step.sequence
	if list == nil or #list ~= 1 then return nil end
	local has_button = false
	-- The LAST entry, because that is the one hold_lever reads and the one that
	-- carries the press. Asking the first entry instead made this test and the
	-- entry-count guard below overlap: every command motion opens with a
	-- neutral or a bare direction, so the count guard never did any work.
	for _, k in ipairs(list[#list]) do
		if not DIRECTION_NAME[k] then has_button = true end
	end
	if not has_button then return nil end
	return hold_lever(list)
end

-- Ticks the whole list occupies, final entry included. What the Wait is NOT:
-- a wait is the gap in front of the step, this is the step's own operation.
local function list_ticks(list)
	local n = 0
	for i = 1, #list do n = n + entry_cost(list[i]) end
	return n
end

-- Ticks spent before the FINAL entry is reached. A wait names the tick the
-- step comes out on, and the step comes out on its final entry, so this is how
-- far ahead of that tick the list has to be started.
local function lead_ticks(list)
	local n = 0
	for i = 1, #list - 1 do n = n + entry_cost(list[i]) end
	return n
end

-- Steps in, a schedule out. Each entry is
--   { sequence = <input list>,
--     wait = <ticks after the previous step, naming the tick this one lands>,
--     lead = <ticks the list needs before its final entry>,
--     auto = <true when it waits for the dummy to be able to act instead> }
--
-- mis is passed in rather than read from the global so this can be exercised
-- without the emulator.
function M.compile(seq, mis)
	mis = mis or make_input_sequence
	if type(seq) ~= "table" or type(seq.steps) ~= "table" then return nil end

	local out = {}
	for i, step in ipairs(seq.steps) do
		local inputs = step_inputs(step, mis)
		if inputs == nil then return nil end
		-- A HOLD ON A ONE-ENTRY MOTION IS A POSTURE, AND A POSTURE NEEDS NO EDGE.
		--
		-- The leading neutral exists to give a DIRECTION a press edge, because a
		-- tap that is already down is not a tap. A step that says Hold is not
		-- asking for a tap: it is asking for the lever to sit somewhere, which
		-- the game reads as a level out of $122 and not as an edge out of $126.
		--
		-- The neutral actively worked against it, twice over. It released the
		-- previous step's hold for a tick - so a charge built across several
		-- steps was broken between every one of them - and under Auto the lead
		-- it adds is never subtracted, so the direction landed on free+1.
		--
		-- Only for a ONE entry motion. A dash or a super jump is a sequence of
		-- taps, and its first one needs its edge whatever the step says about
		-- holding afterwards.
		local _posture = (step.hold == true) and (#inputs == 1)
		if i > 1 and not _posture and opens_with_direction(inputs) then
			table.insert(inputs, 1, {})
		end
		local motion, button = step_parts(step)
		local _sp_cmd = special_command(step)

		-- THE HOLD IS NOT IN THE INPUT LIST.
		--
		-- Copies of the pressed entry, appended here, cannot reach the game on
		-- step one: the arm path presses the button itself on the tick it
		-- wants and then DROPS the sequence, so that nothing is left for the
		-- frame side to swing a second time. Measured - a plain MP came out
		-- (user, 2026-09-05). An earlier attempt aimed at the last copy also
		-- broke the pre-buffer and produced two presses.
		--
		-- So the button names ride the record instead, and guardCancel keeps
		-- them down for ELEC_HOLD_TICKS after the press, the same way it keeps
		-- a held direction down. entry_to_bits already knows the buttons.
		local _hb = nil
		if elec_button(step.button) ~= nil and #inputs > 0 then
			for _, k in ipairs(inputs[#inputs]) do
				if not DIRECTION_NAME[k] then
					_hb = _hb or {}
					_hb[#_hb + 1] = k
				end
			end
		end

		-- A DASH CANCEL STEP HOLDS ITS REVERSE DIRECTION ON ITS OWN.
		--
		-- "Forward Dash Cancel" compiles to the plain dash - the reverse is not
		-- in the list, and the arm's press machinery that injects it for a
		-- single-motion reversal has nothing to ride on here (a sequence step
		-- carries no deferred button). So the runner parks it: two ticks after
		-- this step's last tap, hold the reverse direction, and merge it into
		-- the next step's button press. That is the arm's own arrangement for a
		-- dash cancel ("the reverse cannot go in before that or there is no
		-- dash to cancel"), and holding it through the gap is what makes the
		-- game's one-frame cancel window unmissable.
		--
		-- Only when a next step exists. A cancel with nothing after it has no
		-- button to press - holding back into nothing would just walk the
		-- dummy backwards.
		local _rev = nil
		if seq.steps[i + 1] ~= nil and seq_dash_cancel_reverse ~= nil then
			_rev = seq_dash_cancel_reverse[motion]
		end

		local wait = tonumber(step.wait) or 0
		-- A TYPED ZERO CANNOT STAND AFTER STEP ONE.
		--
		-- It put this step on the same tick as the one before, and the two went
		-- out as a single input (user, 2026-09-05). The editor no longer offers
		-- it; this catches sequences saved before that, one tick later rather
		-- than refused.
		--
		-- BEFORE the Auto resolution below, deliberately. Auto is WAIT_AUTO
		-- here, not zero, and the number it resolves to IS allowed to be zero -
		-- Demitri's measured dash floor is exactly that, and clamping it would
		-- overwrite a measurement with a rule.
		if i > 1 and wait == 0 then wait = 1 end

		-- AUTO AFTER A DASH RESOLVES TO A NUMBER, HERE AND NOWHERE ELSE.
		--
		-- Scope first, because it matters: this touches the sequence path only.
		-- DASH_AUTO_TICKS is read, never written; dash_attack_ticks(),
		-- kd_delay_ticks() and kd_press_offset() in guardCancel are untouched;
		-- Reversal - Specified with Delay = Auto still gets 12, and so does a
		-- sequence's FIRST step, which goes through kd_delay_ticks as before.
		-- Only "step two or later, previous step is a dash, this Wait is Auto"
		-- lands here.
		--
		-- The two origins share the arm's own +1: the arm's press lands at
		-- free-1 + kd_press_base() + DASH_AUTO_TICKS, and the wait is counted
		-- from the tick the dash's own last tap went in - which IS that press
		-- for step one, at free-1 + kd_press_base(). The same moment therefore
		-- asks for DASH_AUTO_TICKS with nothing subtracted. Subtracting one
		-- double-counted kd_press_base() and landed the attack a tick early
		-- (Jedah: Auto (9) against Delay Auto's measured 10).
		--
		-- Nothing new is estimated: the table is already measured for every
		-- character and all four dashes. Where it has no entry, Auto is left
		-- alone rather than given an invented number.
		-- One place decides this, and the editor's row reads the same one.
		if i > 1 and wait == WAIT_AUTO then
			local n = M.auto_ticks_for(seq.steps[i - 1], step, seq.steps[i - 2])
			if n ~= nil then wait = math.max(0, n) end
		end

		local timing = (i > 1) and step.timing or nil
		out[#out + 1] = {
			sequence = inputs,
			motion = motion,
			button = button,
			timing = timing,
			-- Which row this was on screen. The queue is consumed from the
			-- front, so by the time a step fires its position in `pending` no
			-- longer says which one it is.
			index = i,
			-- A NAMED SPECIAL, FOR THE PRESS OFFSET.
			--
			-- guardCancel presses a special on free-1 and everything else on
			-- free+0 (kd_press_base, keyed on SPECIAL_MOTION). It reads the
			-- motion name, and a button-order super has none - its "motion" is
			-- the move's own id, which no table of motions can carry. So the
			-- record says it outright.
			-- press_free0 opts a move out of the early press. It is still a
			-- special in every other way; what it is not is a tick early.
			special = (_sp_cmd ~= nil and _sp_cmd.press_free0 ~= true) or nil,
			-- Carried on the record so the answer survives compilation; the
			-- step itself is gone by the time guardCancel asks.
			press_free0 = (_sp_cmd ~= nil and _sp_cmd.press_free0 == true) or nil,
			-- STEP ONE'S WAIT IS NOT COUNTED HERE.
			--
			-- It is the press offset the arm already applies - kd_delay_ticks
			-- in guardCancel, the same one Guard Action Delay feeds. "Dragon
			-- punch on the fifth tick after the guard" is precisely what that
			-- does: the motion goes in at once and only the press waits, which
			-- is the only way to put a press on a named tick. Scheduling it
			-- here instead would delay the whole motion and miss the window.
			-- Auto agrees by construction: -1 in the editor, negative in
			-- kd_delay_ticks, both meaning the per-character dash value.
			wait = (i == 1) and 0 or math.max(0, wait),
			auto = (i > 1) and (wait == WAIT_AUTO) and timing == nil or false,
			-- STEP ONE NEVER SENDS A NEGATIVE.
			--
			-- kd_delay_ticks reads a negative as "use the dash-attack table".
			-- Step one no longer offers Auto, so a -1 there can only be left
			-- over from a sequence saved before that, and it would silently
			-- behave as a dash delay while the screen reads Fastest. Clamped
			-- so the two agree.
			raw_wait = (i == 1) and math.max(0, wait) or wait,
			lead = lead_ticks(inputs),
			-- For the readout: how many ticks this step spends putting its own
			-- inputs in. A bare button is 1, a command motion is several.
			op_ticks = list_ticks(inputs),
			-- Which buttons stay down after the press, and for how long.
			hold_btn = _hb,
			hold_btn_ticks = (_hb ~= nil) and ELEC_HOLD_TICKS or nil,
			-- KEEP THE DIRECTION DOWN AFTER THIS STEP.
			--
			-- A charge move is a direction held and then let go, and a step's
			-- input otherwise exists for the one tick it is written: the walker
			-- frees the slot and nothing writes 0xFF8B94 again until the next
			-- step. Nothing charges in one tick.
			--
			-- Carried as the LEVER of the last entry, with the buttons dropped -
			-- a held button gives the next attack no press edge, and the release
			-- of a charge is a direction change, not a button one.
			--
			-- NOT ON A DASH CANCEL STEP. Its own auto-held reverse (rev below)
			-- is the holding that matters; the Hold row would keep the dash's
			-- own forward down instead, which releases the cancel.
			hold = (step.hold and _rev == nil) and hold_lever(inputs) or nil,
			-- THE REVERSE DIRECTION THIS STEP HOLDS AFTER ITS TAPS, UNTIL THE
			-- NEXT STEP'S BUTTON. A direction NAME, not bits - which way the
			-- dummy is facing is only known at the tick it is written, the same
			-- reason hold_lever above returns names.
			rev = _rev,
		}
	end

	if #out == 0 then return nil end
	return out
end

-- COMPILE ONCE, NOT ONCE PER ASK.
--
-- seq_len asks for the first step's length from five places in guardCancel,
-- several of which run every frame, and compiling builds tables. Applying in
-- the editor stores a fresh copy of the draft, so the saved table's identity is
-- all that is needed to know a cached compile is stale - no invalidate call to
-- remember, and nothing to forget.
local cache_src, cache_which, cache_cid, cache_out

-- ONE SEQUENCE PER CHARACTER.
--
-- A sequence is built for a particular dummy - its moves, its heights, its
-- animation lengths - and building one is enough work that having it replaced
-- by switching character would make the feature not worth using. Stored under
-- the dummy's id ($382), as a string key so the settings file stays a plain
-- object rather than a sparse array.
local CID = 0xFF8B82          -- P2's $382

local function dummy_cid()
	return tostring(memory.readbyte(CID))
end

-- The editor's saved sequence for this trigger AND this character, compiled.
-- nil when there is nothing usable there, which every caller treats as
-- "behave as before".
function M.schedule(which)
	local store = training_settings and training_settings.action_sequences
	local per = store and store[which]
	if type(per) ~= "table" then return nil end
	-- An entry from before sequences were per character. The editor copies
	-- it into the draft on open, but migrates it only on Save - until that
	-- Save it belongs to no one and runs for no one.
	if per.steps ~= nil then return nil end

	local cid = dummy_cid()
	local seq = per[cid]
	-- No enable flag of its own. Guard Action Type = Reversal - Sequence is
	-- what turns this on, and a second switch would only give the two a way to
	-- disagree.
	if seq == nil then return nil end
	if seq ~= cache_src or which ~= cache_which or cid ~= cache_cid then
		local ok, out = pcall(M.compile, seq)
		cache_src, cache_which, cache_cid = seq, which, cid
		cache_out = (ok and out) or nil
	end
	return cache_out
end

-- NO TIMEOUT ANYWHERE HERE.
--
-- A count of frames would be a lie about what is being waited for. The
-- schedule is dropped by the events that actually end it - a new arm replaces
-- it, and loading a state clears it - never by a number.
local pending = nil     -- steps still to fire, in order
local anchor = nil      -- P2 tick counter when the previous step started
-- STEP ONE'S Hold HAS TO BE HANDED OVER SEPARATELY.
--
-- Every later step is queued by service_body, which tags the delivery record
-- with the hold. Step one is not: the arm places it, through machinery in
-- guardCancel that predates all of this and only takes an input list. So a Hold
-- on step one was silently dropped - "walk twenty ticks, then throw" stood
-- still and threw at nothing.
--
-- Parked here for the tick walker to collect once step one's record is gone,
-- rather than pushed at the arm: the arm is not the tick the holding starts on,
-- and asserting a direction while the reversal itself is still being delivered
-- would fight the free-1 machinery for the input word.
local arm_hold = nil
-- ONE SHOT, LIKE arm_hold BESIDE IT.
--
-- The button hold has to be handed over once and forgotten. Asked of the
-- schedule instead, the answer is the same on every tick - so the moment the
-- deadline let go, the next tick armed it again and the attack came out over
-- and over (user, 2026-09-05). The lever hold was never exposed to that,
-- because take_arm_hold clears it as it answers.
local arm_hold_btn = nil
local arm_hold_btn_ticks = nil

-- THE DASH CANCEL'S REVERSE DIRECTION, HELD BETWEEN STEPS.
--
-- A dash-cancel step's compiled list is the plain dash; the reverse direction
-- that makes the move is parked here instead of being an entry, because the
-- tick it starts on is NOT the tick the step comes out on: it is two ticks
-- after the step's last tap (the arm's own v207 rule - the reverse cannot go
-- in before that or there is no dash to cancel), and it has to survive until
-- the next step's button presses on top of it.
--
-- Lifecycle: the walker parks it when a step carrying `rev` runs off its end
-- (park_rev, with the tick that just ended - so `at` lands two ticks past the
-- last tap); rev_lever_now answers it once that tick arrives; the walker
-- merges it into a delivered entry and clears it on the entry that carries a
-- button or its own direction. arm_rev is the same thing for STEP ONE, which
-- the arm places and the walker can only collect afterwards - the same
-- arrangement arm_hold above uses.
--
-- Cleared by a merge, by cancel(), and by the walker when the schedule is
-- spent with nothing merged - a dash cancel whose button never came leaves
-- nothing held.
local rev = nil        -- { lever = <direction name>, at = <tick to start> }
local arm_rev = nil    -- step one's reverse, waiting for its record to end

-- THE WHOLE SCHEDULE, KEPT SO THE LOOP CAN PUT IT BACK.
--
-- pending holds only what is still to come, and the last step takes itself out
-- of it, so by the time the loop needs the list again there is nothing left to
-- read it from. This is the compile's own output and is never mutated - the
-- loop copies step one before changing its wait, because M.schedule caches on
-- the settings table's identity and a mutated entry would be served again.
local loop_sched = nil
-- Which trigger the loop belongs to, so a restart can ask for the list again
-- rather than replay the one compiled at the arm.
local loop_which = nil

-- Called by the walker when a step carrying rev runs off its end. `now` is
-- the tick that just ended - the step's last tap - so the holding starts two
-- ticks past it.
function M.park_rev(lever, now)
	if lever == nil then return end
	rev = { lever = lever, at = (now + 2) % 256 }
end

-- The lever to assert this tick, or nil. The mod-256 half-window is the same
-- clock convention the anchor uses: a delta past 127 reads as "not yet".
function M.rev_lever_now(now)
	if rev == nil then return nil end
	if (now - rev.at) % 256 > 127 then return nil end
	return rev.lever
end

-- The merge is spent: the button pressed (or the entry's own direction took
-- the lever), so nothing is held any more.
function M.rev_clear()
	rev = nil
end

-- Step one's reverse, collected once its record is gone - the same one-shot
-- contract take_arm_hold above uses.
function M.arm_rev_due(now)
	if arm_rev == nil then return nil end
	local _l = arm_rev
	arm_rev = nil
	M.park_rev(_l, now)
	return _l
end


-- HOW MANY LATER STEPS HAVE GONE OUT, AND HOW MANY WERE DROPPED UNFIRED.
--
-- Steps two and later live here rather than in the game, and nothing in the
-- game can end them - see "NO TIMEOUT ANYWHERE HERE" above. That makes it easy
-- for a schedule to outlive the opportunity that created it, and impossible to
-- see from the screen: what comes out looks exactly like a fresh guard action.
-- Counted so it can be read instead of argued about.
M.steps_fired = 0
M.steps_dropped = 0

-- WHAT EACH STEP ACTUALLY WAITED, IN TICKS.
--
-- A row can say Auto (After) or Auto (Chain) without ever saying how long that
-- turned out to be, and the number is the interesting part: it is the answer
-- the tool was used to find in the first place, and by hand it costs a run per
-- guess. Recorded where the step fires, so it is measured and not predicted.
--
-- Counted the way the Wait row is defined - from the previous step's last
-- input to this step's press - so a numbered step reads back the number that
-- was typed, and an Auto reads what the number would have been.
--
-- MEASURED ONLY. What the row was set to is not carried: it is on the row, and
-- the user asked for the readout to be the half they cannot already see.
--
-- ticks is absent where there is no gap to report. Step one on the first pass
-- is the case: its wait is counted from the TRIGGER, by the arm in
-- guardCancel, not from a step before it - so it carries its Act alone.
--
-- { { index = <step number>, mode = <short name>, ticks = <measured or nil>,
--     op = <ticks this step spends on its own inputs> }, ... }
M.wait_log = {}
-- One pass of the longest list the editor allows (16), plus the Loop item in
-- front of it. The log is cleared at each restart, so it never holds more.
local WAIT_LOG_MAX = 17
local TIMING_LABEL = {
	[TIMING_CHAIN] = "Chain",
	[TIMING_RAPID] = "Rapid",
	[TIMING_CANCEL] = "Cancel",
	[TIMING_LATE_CANCEL] = "Late",
	[TIMING_LANDING] = "Land",
}
local function log_entry(e)
	M.wait_log[#M.wait_log + 1] = e
	while #M.wait_log > WAIT_LOG_MAX do table.remove(M.wait_log, 1) end
end

local function log_wait(step, ticks)
	-- A LOOP RESTART IS NOT STEP ONE'S WAIT, SO IT IS NOT ON STEP ONE'S ITEM.
	--
	-- Round two onwards, loop_refill fires step one with the Loop Wait in
	-- place of its own. Putting that number beside Step.1 would read as step
	-- one's setting, and printing both would read as two gaps added together.
	-- So the gap is its own item and step one keeps only what is still true of
	-- it on this pass: how long its input takes.
	if step.is_loop then
		-- ONE PASS AT A TIME, AND THE LOOP ITEM AT THE FRONT OF IT.
		--
		-- Kept whole, the line grew past the right edge of the screen and the
		-- Loop item - the newest, and the one being looked for - was the part
		-- that fell off. Reported: the readout "starts at Step.1" and the loop
		-- wait cannot be read (user, 2026-09-06).
		--
		-- Cleared here instead of trimming the oldest, because trimming drops
		-- the Loop item first: it is the oldest of the pass it belongs to.
		M.wait_log = {}
		log_entry({ mode = "Loop", ticks = ticks })
		log_entry({ index = step.index, op = step.op_ticks })
		return
	end
	local mode = TIMING_LABEL[step.timing]
	if mode == nil then mode = step.auto and "Auto" or "Set" end
	log_entry({
		index = step.index,
		mode  = mode,
		ticks = ticks,
		op    = step.op_ticks,
	})
end

-- THE LINE THE HUD PRINTS, BUILT HERE SO IT CAN BE TESTED.
--
--   Step.1 Act:3 / Step.2 Wait:13 Act:1 / Loop Wait:11 / Step.1 Act:3
--
-- Wait is measured, in ticks, from the previous step's last input to this
-- step's press - the same thing the Wait row names. Act is what this step then
-- spends entering its own inputs: 1 for a bare button, more for a motion.
--
-- An item carries whichever of the two it has. Step one has no Wait: on the
-- first pass its gap is counted from the trigger, and on a loop pass the gap
-- belongs to the Loop item in front of it.
--
-- The setting is not repeated. It is on the row already, and a number that is
-- sometimes the setting and sometimes the result cannot be read at a glance.
local function wait_log_items()
	local out = {}
	for _, e in ipairs(M.wait_log) do
		-- "Step.2", not "Step#2". A hash next to a digit is hard to pick out
		-- at this font size (user, 2026-09-06).
		local t = (e.mode == "Loop") and "Loop"
			or ("Step." .. tostring(e.index or "?"))
		if e.ticks ~= nil then t = t .. " Wait:" .. e.ticks end
		if e.op ~= nil then t = t .. " Act:" .. e.op end
		out[#out + 1] = t
	end
	return out
end

function M.wait_log_text()
	local items = wait_log_items()
	if #items == 0 then return nil end
	return table.concat(items, " / ")
end

-- THE SAME LINE, BROKEN TO FIT.
--
-- One line ran off the right edge and took the newest items with it. Wrapped
-- on the separator, never inside an item: half of "Wait:25" at the end of a
-- line is worse than a shorter line.
--
-- A line that continues keeps its trailing "/" so the break is visibly a break
-- and not the end of the pass.
function M.wait_log_lines(cols)
	local items = wait_log_items()
	if #items == 0 then return nil end
	local lines, cur = {}, nil
	for _, it in ipairs(items) do
		if cur == nil then
			cur = it
		elseif #cur + 3 + #it <= cols then
			cur = cur .. " / " .. it
		else
			lines[#lines + 1] = cur .. " /"
			cur = it
		end
	end
	lines[#lines + 1] = cur
	return lines
end

function M.cancel()
	if pending ~= nil then
		M.steps_dropped = M.steps_dropped + #pending
	end
	pending = nil
	anchor = nil
	arm_hold = nil
	arm_hold_btn = nil
	arm_hold_btn_ticks = nil
	rev = nil
	arm_rev = nil
	loop_sched = nil
	loop_which = nil
	air_seen = false
	contact_used = false
	rapid_used = false
	gate_busy_seen = false
	-- AND THE DIRECTION THE LAST TIMING STEP LEFT DOWN.
	--
	-- Every other piece of per-run state is dropped here; this one was missed.
	-- It is only cleared where $39 goes back to zero, and that test lives in
	-- refresh_contact, which is reached from M.service - which is not called at
	-- all once Guard Action Type is something other than Action Steps. So a run
	-- cancelled while the contact was still live left a direction latched, and
	-- the next time the mode was selected the walker asserted it before
	-- anything had been armed.
	held_after = nil
end

-- Steps still waiting. Zero and nil read the same to the caller.
function M.pending_count()
	return (pending ~= nil) and #pending or 0
end

-- Compiles the trigger's sequence, keeps steps 2..n, and returns the first so
-- the caller can queue it exactly where it queues a motion today.
function M.arm(which)
	local sched = M.schedule(which)
	if sched == nil then return nil end
	pending = {}
	for i = 2, #sched do pending[#pending + 1] = sched[i] end
	if #pending == 0 then pending = nil end
	anchor = nil
	arm_hold = sched[1].hold
	arm_hold_btn = sched[1].hold_btn
	arm_hold_btn_ticks = sched[1].hold_btn_ticks
	arm_rev = sched[1].rev
	loop_sched = sched
	loop_which = which
	contact_used = false
	rapid_used = false
	gate_busy_seen = false
	-- Same reason as in M.cancel: a new run must not inherit the direction the
	-- previous one was still holding.
	held_after = nil
	-- A fresh run, so the readout is this run's numbers and not the last one's.
	--
	-- Step one goes in on the arm path, not through service_body, and its wait
	-- is measured from the trigger by guardCancel - a different question from
	-- the one this readout answers. Its Act is not a measurement though: it is
	-- how long its input list is, known here, so the row starts with it.
	M.wait_log = {}
	log_entry({ index = 1, op = sched[1].op_ticks })
	return sched[1].sequence
end

-- Returns step one's hold once, then forgets it. One-shot because the walker
-- asks on every tick where nothing is being delivered, and only the first of
-- those is the moment step one finished.
function M.take_arm_hold()
	local h = arm_hold
	arm_hold = nil
	return h
end

-- Same contract for the button hold: answered once, then gone.
function M.take_arm_hold_button()
	local h, n = arm_hold_btn, arm_hold_btn_ticks
	arm_hold_btn, arm_hold_btn_ticks = nil, nil
	return h, n
end

-- Step one's wait, in the encoding kd_delay_ticks already understands:
-- a count of ticks, or negative for Auto.
function M.first_wait(which)
	local sched = M.schedule(which)
	if sched == nil then return nil end
	return sched[1].raw_wait
end

-- What step one IS, for the parts of the arm that ask about the motion rather
-- than about the list: whether it is a special (which moves the press by a
-- tick), which dash it is (which is what Auto reads), and which button to put
-- in when an entry carries none.
function M.first_motion(which)
	local sched = M.schedule(which)
	if sched == nil then return nil end
	return sched[1].motion
end

function M.first_button(which)
	local sched = M.schedule(which)
	if sched == nil then return nil end
	return sched[1].button
end


-- Whether step one is a named special move. Asked by guardCancel to decide the
-- press offset: a special goes in on free-1, a normal on free+0, and a
-- button-order super is a special whose motion is a name.
function M.first_is_special(which)
	local sched = M.schedule(which)
	if sched == nil then return false end
	return sched[1].special == true
end
-- DOES THE FIRST STEP ASK NOT TO BE PRESSED EARLY?
--
-- Separate from first_is_special on purpose. "Not a special" and "a special
-- that presses like a normal" are different answers, and guardCancel falls back
-- to the motion table when the first is false - which would put DPF back on
-- free-1 and undo the whole point for Kienzan.
function M.first_press_free0(which)
	local sched = M.schedule(which)
	if sched == nil then return false end
	return sched[1].press_free0 == true
end

-- How long the first step is. guardCancel sizes its arm window from the
-- motion's length, so it has to be asked about the compiled list, not about the
-- stick name - they are no longer the same thing.
function M.first_len(which)
	local sched = M.schedule(which)
	if sched == nil then return nil end
	return #sched[1].sequence
end

-- What the first step would hold, for tests. NOT what guardCancel uses -
-- that has to be the one-shot above, or the hold re-arms every tick.
function M.first_hold_button(which)
	local sched = M.schedule(which)
	if sched == nil or sched[1].hold_btn == nil then return nil end
	return sched[1].hold_btn, sched[1].hold_btn_ticks
end

-- WHAT "CAN ACT" MEANS ON THE GROUND, AND WHAT IT MEANS IN THE AIR.
--
-- On the ground: neither in stun nor mid-action, the same pair of bytes the
-- recording wizard waits on before it re-offers Play again. Unchanged.
--
-- In the air neither byte ever reaches zero, so that test can never pass and
-- Auto never fired there at all. This is what the GAME tests, read out of the
-- ROM rather than guessed at - 0x052996, in the handler for falling after a
-- dash, and the same shape in the other airborne handlers:
--
--     movea.l ($1c,A6), A0     ; the current animation frame
--     btst    #$1, ($1,A0)     ; does this frame allow another attack?
--     beq     ...              ; no - nothing can come out
--     jsr     $277f8           ; pressed, and not already used this trip
--
-- and $277f8 is
--
--     bsr $274ba               ; $126 & $77 - an attack button's press edge
--     bsr $2759a               ; which button: 0..2 punches, 4..6 kicks
--     btst D1, ($1a6,A6)       ; already used during this air trip?
--     bne ...                  ; yes, refuse
--
-- So there are two conditions and neither is a chain window: the animation
-- frame has to permit it, and that button must not have been spent yet on this
-- trip. $1a6 uses the button byte's own bit numbering - measured on the same
-- recordings, HK leaves 0x40, then LK 0x50, then LP 0x51.
--
-- THREE EARLIER ATTEMPTS READ $21 INSTEAD, AND $21 IS ONLY A COPY.
--
-- Keying on bit 1 of $21 fitted both measured floors (25 and 24) by
-- coincidence - $21 carries the same flag byte, but the copy is a tick out of
-- step with the frame, so every attempt to line it up properly made it worse.
-- $21's own bit 1 is tested at 0x022BD6 and leads to $27122, which is the
-- DIRECTION check: it gates movement, not attacks.
--
-- Reading ($1c) directly needs no latch. It is the same value, on the same
-- tick, that the game is about to test.
local BUTTON_BIT = {
	LP = 0, MP = 1, HP = 2,
	LK = 4, MK = 5, HK = 6,
}

local function air_ready(button)
	-- Same validity guard autoguard.lua's cel_ptr uses.
	local p = memory.readdword(P2_BASE + 0x1C)
	if p == nil or p < 0x1000 or p >= 0x1000000 then return false end
	if math.floor(memory.readbyte(p + 1) / 2) % 2 == 0 then return false end

	local b = BUTTON_BIT[button]
	-- A step with no single button - a motion, a bare direction - has nothing
	-- in the used mask to check against.
	if b == nil then return true end
	return math.floor(memory.readbyte(P2_BASE + 0x1A6) / 2 ^ b) % 2 == 0
end

local function dummy_free(step)
	if memory.readbyte(P2_BASE + 0x05) ~= 0 then return false end
	if memory.readbyte(P2_BASE + 0x38) == 0 then
		return memory.readbyte(P2_BASE + 0x06) == 0
	end
	return air_ready(step and step.button)
end


-- TOUCHDOWN, FROM THE CLOCK THE REVERSAL ARM ALREADY USES.
--
-- Auto (After) asks the wrong question while the dummy is airborne: $38 sends
-- dummy_free down the air_ready branch, which is "may this button come out in
-- the AIR". A grounded follow-up - a crouching normal after a dash attack that
-- ends in the air - is not asking that, and waiting for the whole landing to
-- finish is later than the frame the game will take.
--
-- guardCancel already predicts the touchdown for wake-up and air-recovery
-- reversals (ticks_to_landing replays the ROM physics; kd_land_arm is how far
-- ahead to fire so the press lands ON the actionable tick, not after it). This
-- asks the same clock rather than building a second answer out of $38 edges.
--
-- The direction is already down by then: a landing step is a timing step, so
-- waiting_step_lever holds its lever for the whole descent. That is the input
-- being present at touchdown, which is what a landing cancel is.
-- Seen airborne since this landing step reached the head of the queue. The
-- touchdown is an EDGE, and an edge needs the other side of it remembered.
local air_seen = false

-- HOW LONG THE NEUTRAL IN THE MIDDLE OF A DASH MAY LAST.
--
-- A dash is N, forward, neutral, forward. The game gives the first forward ten
-- frames to be held, then TEN FRAMES OF NEUTRAL, then takes the second forward.
-- Unlike a special move - where the grace between inputs is one of six random
-- values, 10F at 16/32 down to 15F at 2/32 - the dash grace is FIXED. 10F at
-- Normal speed, 8F at the game's own Turbo setting (NOT the emulator's turbo,
-- which is a different thing and was confused for it here once).
--
-- The tool runs on ticks and one frame is one tick at Normal, so this is ten
-- ticks. Source and the probability table are in VSAV_MEMORY_NOTES.md under
-- "コマンド受付の猶予" - reference material, not something measured here.
--
-- The list spends one tick on that neutral already, so a hold may add nine
-- before the motion expires. Hit stop is eleven ticks ($5C is slammed to 0x0B),
-- which is longer than the whole grace - so a freeze landing on the neutral
-- kills the dash outright, and holding the last press into it presses into a
-- window that has already closed. That is why exceeding this restarts the
-- motion from the top rather than waiting longer.
M.DASH_GRACE_TICKS = 10

local function landing_ready(step)
	local _air = memory.readbyte(P2_BASE + 0x38) ~= 0
	if _air then
		air_seen = true
		-- ONLY A STEP THAT NEEDS RUN-UP STARTS IN THE AIR.
		--
		-- The press has to land ON the touchdown, and a step's last entry
		-- arrives `lead` ticks after it fires - the same arithmetic
		-- `wait - lead` does for a numbered wait. A one-entry normal has lead 0
		-- and therefore starts on the floor, not above it: firing two ticks
		-- early put the button in the air, which is the press that went in and
		-- produced nothing.
		--
		-- A command motion has entries to get through, so it starts early and
		-- uses the prediction to know how early.
		local _lead = step.lead or 0
		-- NOT WHILE THE PHYSICS IS FROZEN.
		--
		-- ticks_to_landing() answers in PHYSICS ticks and the delivery runs on
		-- the CLOCK, and hitstop separates the two: position stops updating
		-- while the tick counter keeps going (measured 2026-09-18 - y, vy and ay
		-- identical across ticks while the hook kept firing). Committing in
		-- there sends the run-up into a window that is still counting down, so
		-- the motion expires mid-flight: the command acceptance counter does NOT
		-- freeze with the physics.
		--
		-- $5C is the remaining hitstop, already read by tickDataVsav.lua. Zero
		-- means the two clocks agree and the prediction can be acted on.
		--
		-- Nothing is lost by waiting. If the moment goes past, the branch below
		-- fires this step on the touchdown instead - late, but out. A dummy that
		-- stays silent teaches nothing, which is the whole reason the deadline
		-- on this gate exists at all.
		if memory.readbyte(P2_BASE + 0x5C) ~= 0 then return false end
		if _lead > 0 and seq_ticks_to_landing ~= nil then
			local _ld = seq_ticks_to_landing()
			if _ld ~= nil and _ld <= _lead then return true end
		end
		return false
	end
	-- THE TOUCHDOWN ITSELF.
	--
	-- $38 back to zero is the fact, and it needs no prediction -
	-- ticks_to_landing "Returns nil when the object is not on a descending
	-- path", so a scripted descent is invisible to it anyway.
	--
	-- Only after the dummy has actually been airborne: a step that reaches the
	-- head on the ground has no landing to wait for, and firing there would be
	-- "now" under another name.
	return air_seen
end
-- HAS THE CHANCE GONE?
--
-- "Auto (After)" is the dummy having finished what it was doing, and that is
-- exactly the point past which a chain, a cancel or a repeat can no longer
-- happen: they all live inside the move in front of them.
--
-- AN EDGE, NOT A LEVEL. dummy_free is true for a tick or two immediately after
-- the previous step's press, before the game has started the move - reading the
-- level alone would call every connection missed before it had a chance. So the
-- dummy has to be seen BUSY first; only then does becoming free again count as
-- the chance having passed.
--
-- Reset when a step fires, so each waiting step judges its own window.
-- gate_busy_seen is declared beside contact_used, above M.cancel: declared here
-- it would be a DIFFERENT variable from the one cancel() and arm() clear, and
-- those two would silently write a global instead. Nothing in Lua says so - it
-- showed up as a latch that leaked from one run into the next.
local function timing_missed(step)
	if not dummy_free(step) then
		gate_busy_seen = true
		return false
	end
	return gate_busy_seen
end

local function service_body(defender)
	local now = memory.readbyte(P2_TICKS)

	-- A WAIT NAMES THE TICK THE STEP COMES OUT ON.
	--
	-- Not the tick its first direction goes in. If a forward dash is F N F and
	-- the wait is five, the dash happens five ticks after the step before it -
	-- so the list has to START early enough for its LAST entry to land there,
	-- exactly as the arm places a reversal's press on free+0 and puts the
	-- motion in ahead of it. lead is how far ahead that is.
	--
	-- The clock does not run while anything is still being delivered, which is
	-- also what keeps the schedule out of the block: the arm holds step one in
	-- this slot for the whole of it.
	if defender.pending_input_sequence ~= nil then
		anchor = nil
		return
	end
	if anchor == nil then
		-- The slot is freed on the tick AFTER the last entry went in - the
		-- walker only notices it has run off the end on its next pass, and the
		-- arm drops step one at the press for the same reason. So the tick
		-- being named here is the one before this.
		anchor = (now - 1) % 256
	end

	local step = pending[1]
	if CONNECT_TIMED[step.timing] then
		local _ok
		if step.timing == TIMING_CHAIN then _ok = chain_ready(step)
		elseif step.timing == TIMING_RAPID then _ok = rapid_ready(step)
		elseif step.timing == TIMING_CANCEL then _ok = cancel_ready(step, false)
		else _ok = cancel_ready(step, true) end
		-- MISSING THE CONNECTION IS NOT A REASON TO STOP.
		--
		-- A chain that did not connect, a cancel window that never opened - the
		-- step used to sit at the head of the queue for ever, holding its
		-- direction, and the rest of the list never came out. Whiffing one link
		-- of a string therefore ended the whole run, which is not what a drill
		-- should do.
		--
		-- So the connection has a deadline, and it is the one the row next to
		-- it already names: Auto (After). Past that point the move it was
		-- supposed to connect to is over and no gate can open, so the step goes
		-- out on its own instead of waiting for something that cannot happen.
		if not _ok and not timing_missed(step) then return end
	elseif step.timing == TIMING_LANDING then
		-- A LANDING THAT CANNOT HAPPEN IS NOT A REASON TO STOP EITHER.
		--
		-- The connect-timed gate above already carries this deadline. Landing
		-- did not, and it is the same mistake: if the step before it never left
		-- the ground - a dash that did not come out, a jump that was swapped
		-- away - there is no landing to wait for and the list stopped there for
		-- good.
		--
		-- Reported 2026-09-17 on a three step list: Dash Forward Cancel, then
		-- Attack LP, then Attack Down on Auto (Landing). The dash did not come
		-- out, the standing LP did, and the run ended.
		--
		-- Same deadline as the others: once the dummy has been busy and is free
		-- again, the moment being waited for is over and the step goes out on
		-- its own. That is Auto (After) - which is what every Auto should fall
		-- back to when its condition is missed (user, same report).
		if not landing_ready(step) and not timing_missed(step) then return end
	elseif step.auto then
		if not dummy_free(step) then return end
	else
		-- Negative means the motion is longer than the wait: there is no way to
		-- land it on the named tick, so it goes as early as it can.
		local _start = step.wait - step.lead
		if _start < 0 then _start = 0 end
		if ((now - anchor) % 256) < _start then return end
	end

	-- Fired on this contact, so the next timing-gated step waits for a fresh
	-- one. Only the four modes consume it: a numbered or Auto step is not timed
	-- off the hit and must not eat the contact a mode behind it is waiting for.
	if step.timing == TIMING_LANDING then air_seen = false end
	if step.timing == TIMING_RAPID then rapid_used = true end
	if HIT_TIMED[step.timing] then
		contact_used = true
		-- Its direction stays down for the rest of this contact, so the last
		-- step gets what every earlier one got from the step behind it.
		held_after = waiting_step_lever(step)
	end

	-- The gap this step really waited. `anchor` names the tick the step before
	-- it finished delivering, and `lead` is how far ahead of its own press this
	-- step had to start - so adding it back gives press-to-press, which is what
	-- the Wait row means.
	log_wait(step, ((now - anchor) % 256) + (step.lead or 0))

	table.remove(pending, 1)
	if #pending == 0 then pending = nil end
	anchor = nil
	gate_busy_seen = false

	M.steps_fired = M.steps_fired + 1
	queue_input_sequence(defender, step.sequence)
	-- Hand it to the tick hook rather than the frame path. Tagged after
	-- queueing because queue_input_sequence builds the record; without this the
	-- step would be walked at one entry per displayed frame, about 1.6 ticks
	-- each, which is what a scheduled step is not allowed to be.
	local q = defender.pending_input_sequence
	if q ~= nil then
		q.seq_tick = true
		q.tick_held = 0
		-- AIMED AT A TOUCHDOWN THAT HAS NOT HAPPENED YET.
		--
		-- lead is the cost of every entry BUT THE LAST (lead_ticks), so the
		-- whole schedule exists to put the final press on one named tick. For a
		-- landing step that tick is a prediction, and the walker needs to know
		-- which segments are living on one.
		q.seq_land = (step.timing == TIMING_LANDING
		               and (step.lead or 0) > 0) or nil
		-- Rides on the record so the walker picks it up when it runs off the
		-- end of this segment - that is the tick the holding has to start, and
		-- the walker is the only thing that knows it has arrived.
		q.seq_hold = step.hold
		-- The button hold rides the same way, with its tick count beside it.
		q.seq_hold_btn = step.hold_btn
		q.seq_hold_btn_ticks = step.hold_btn_ticks
		-- Same ride for the dash cancel's reverse direction.
		q.seq_rev = step.rev
	end
end

-- THE LOOP'S WAIT IS STEP ONE'S WAIT, ON EVERY PASS AFTER THE FIRST.
--
-- Step one's own Wait is the ARM's press delay - kd_delay_ticks reads it - and
-- the arm only places the pass it was triggered for. From pass two on, step one
-- is delivered by the tick walker like any other step, so it takes an ordinary
-- step wait and the machinery below it needs nothing new.
--
-- On and off is its own switch, so this field only ever answers "when" - the
-- same two answers a step's Wait gives:
--
--   -1   Auto - service_body waits for dummy_free, the After of the editor
--   0+   ticks from the previous step, and service_body starts the input list
--        `lead` early so the LAST entry lands on that tick
--
-- THE TWO ARE NOT THE SAME EARLIEST, WHICH IS WHY BOTH ARE OFFERED.
--
-- Auto begins the input when the dummy is free, so the press falls `lead` ticks
-- after that - three or four for a dash. Good enough to keep a blocking drill
-- going round; not the fastest dash. A number gets the lead subtraction and can
-- be walked down until the move stops coming out, which is what a loop tight
-- enough to be an infinite needs.
local LOOP_AUTO = -1
-- A loop boundary can also be "when the dummy lands", which is what a hop into
-- an air normal wants: the next lap's first step is a dash, and a dash has to
-- START before the touchdown for its last input to arrive on the first tick the
-- dummy can act. Auto (After) is too late by that run-up; a number cannot know
-- how long the hop took. -2 because -1 is already Auto and zero has no meaning
-- here (see M.loop_wait).
local LOOP_LANDING = -2

-- Whether the list repeats at all. Read live rather than latched at arm time:
-- switching it off should stop the loop that is running, which reads better
-- than a setting that only takes effect next time.
function M.loop_on()
	return training_settings ~= nil and training_settings.action_steps_loop == true
end

-- When the next pass starts. Auto unless a number was typed.
function M.loop_wait()
	local _v = training_settings and training_settings.action_steps_loop_wait
	-- -1 is Auto. Zero was briefly accepted by the menu, but a loop boundary
	-- has no supported zero-tick meaning. Treat old or manually edited zero
	-- values as Auto as a second line of defence behind settings migration.
	if _v == LOOP_LANDING then return LOOP_LANDING end
	if type(_v) ~= "number" or _v <= 0 then return LOOP_AUTO end
	return _v
end

-- The raw steps, for the two questions the menu asks about the loop. Same
-- reads M.schedule does, without the compile.
local function loop_steps(which)
	local store = training_settings and training_settings.action_sequences
	local per = store and store[which]
	if type(per) ~= "table" or per.steps ~= nil then return nil end
	local seq = per[dummy_cid()]
	local steps = seq and seq.steps
	if type(steps) ~= "table" or #steps == 0 then return nil end
	return steps
end

-- WHAT Auto RESOLVES TO FOR THE LOOP, OR nil.
--
-- The step before the loop's first step is the LAST step of the list - looping
-- is what makes them neighbours - so this is the editor's own Wait question
-- with the editor's own answer function. The menu prints a number where there
-- is one and After where there is not, exactly as a step's row does: naming
-- After where the table has a number promises something the row does not do.
--
-- A one-step list is its own predecessor, which is the right answer rather than
-- a special case.
function M.loop_auto_ticks(which)
	local steps = loop_steps(which)
	if steps == nil then return nil end
	return M.auto_ticks_for(steps[#steps], steps[1], steps[#steps - 1])
end

-- Not while the training menu is up. The dummy is frozen behind it, so a
-- restart armed in there would fire the instant it closes - macro.lua holds its
-- own playback off for the same reason (LOOP_MENU_CLOSE_HOLD). No count is
-- needed here: the state that matters is whether the menu is open.
local function loop_blocked()
	return globals ~= nil and globals.show_menu == true
end

-- Puts the whole list back, with step one carrying the loop's wait instead of
-- the arm's. The copy is one level deep and only step one needs it - the other
-- entries are handed on untouched, and loop_sched must survive intact because
-- M.schedule caches it.
local function loop_refill()
	if loop_sched == nil or #loop_sched == 0 then return end
	if not M.loop_on() then return end
	-- EDITS TAKE EFFECT ON THE NEXT LAP.
	--
	-- loop_sched is what M.arm compiled, and replaying it meant the loop kept
	-- running the list as it was when the guard action armed - so changing a
	-- step with the loop on appeared to do nothing until the next arm, which
	-- with a loop running may never come (user, 2026-09-06).
	--
	-- Asked again here instead. M.schedule caches on the stored table's
	-- identity and save_draft writes a fresh copy, so an unchanged list hands
	-- back the very same compiled schedule and this costs nothing.
	--
	-- A missing or invalid newly saved list stops the loop. Replaying the old
	-- compiled list would hide the failure and execute inputs no longer shown
	-- by the Editor.
	if loop_which ~= nil then
		local _fresh = M.schedule(loop_which)
		if _fresh == nil or #_fresh == 0 then
			loop_sched = nil
			loop_which = nil
			return
		end
		loop_sched = _fresh
	end
	local _w = M.loop_wait()
	local _first = {}
	for k, v in pairs(loop_sched[1]) do _first[k] = v end
	-- LANDING IS A TIMING, NOT A NUMBER.
	--
	-- service_body branches on step.timing before it looks at auto or wait, so
	-- handing the restart the landing gate is all it takes: the prediction, the
	-- run-up and the deadline all come with it. Safe to set here because
	-- M.compile only ever puts a timing on steps 2 and later - step one's is
	-- always nil, so nothing is being overwritten.
	if _w == LOOP_LANDING then
		_first.timing = TIMING_LANDING
		_first.auto = false
		_first.wait = 0
	else
		_first.auto = (_w == LOOP_AUTO)
		_first.wait = (_w == LOOP_AUTO) and 0 or _w
	end
	-- Marked so the readout can say Loop rather than repeating step one's own
	-- mode, which is not what this pass waited for.
	_first.is_loop = true
	pending = { _first }
	for i = 2, #loop_sched do pending[#pending + 1] = loop_sched[i] end
	-- Left for service_body to name on the first tick with the slot free, the
	-- same tick every other step's wait is counted from.
	anchor = nil
end



-- The direction to hold this tick, or nil. Asked by the walker on ticks where
-- nothing is being delivered, the same place the dash cancel's reverse is
-- asked. nil once the step has fired - it is off the queue by then.
-- NOT WHILE THE MENU IS UP.
--
-- The hold exists so the direction is already down on the tick a gate opens,
-- and no gate can open behind the menu: the dummy is not fighting, the step
-- being waited for cannot fire, and loop_blocked already refuses to restart
-- there for the same reason.
--
-- Left running it is asserted on every tick the menu is open, which is as long
-- as it takes to toggle Loop Steps or walk a Wait row - so the direction goes
-- in for seconds, and comes back out of the menu already down, with no press
-- edge left for whatever was supposed to tap it next. Reported as the last
-- input of an action step staying in, when toggling the loop or changing a
-- timing (user, 2026-09-06).
function M.waiting_lever()
	if loop_blocked() then return nil end
	local _w = (pending ~= nil) and waiting_step_lever(pending[1]) or nil
	if _w ~= nil then return _w end
	return held_after
end
-- Called once per tick from the walker in guardCancel. No latch: the air test
-- reads what the game is about to read, on the same tick.
--
-- The spent schedule used to end the story here. With a loop set it is asked
-- every tick instead, so the restart waits for the menu to close on its own
-- without anyone counting frames at it.
function M.service(defender)
	if defender == nil then return end
	-- Every tick, before anything can return early. The gates below ask it, and
	-- so does the direction the last step is still holding - that has to come
	-- off when the contact ends, and by then the schedule is empty and
	-- service_body is never reached again.
	refresh_contact()
	-- THE MENU ENDS THE RUN. IT DOES NOT PAUSE IT.
	--
	-- Opening the menu only calls disable_both_players; the game keeps running
	-- and the tick clock keeps counting. So a schedule left in flight behind
	-- the menu is not waiting, it is elapsing: a numbered wait runs out while a
	-- Wait row is being walked, and Auto asks whether a dummy that is standing
	-- still can act, which it can. Both are answered against a fight that is
	-- not happening, and there is no way to resume in the middle from that.
	--
	-- So the pass is dropped rather than frozen - the same call the refusal
	-- path in guardCancel makes, for the same reason: an opportunity is one
	-- unit, and this one is over.
	--
	-- THE LOOP DOES NOT COME BACK ON ITS OWN EITHER.
	--
	-- Restarting from the top on close means the dummy is already moving before
	-- the menu has finished closing, which is not what closing a menu should
	-- do - and after an edit it is worse, because the first thing seen is a lap
	-- nobody asked for. loop_sched goes with the pass, so the next lap needs a
	-- fresh arm: hit the dummy once and it picks up again from the edited list
	-- (user, 2026-09-06).
	if loop_blocked() then
		if pending ~= nil then
			M.steps_dropped = M.steps_dropped + #pending
			pending = nil
		end
		-- AND THE SEGMENT ALREADY BEING DELIVERED.
		--
		-- Dropping the queue alone left the step in the delivery slot to finish
		-- walking its entries, so closing the editor was followed by the tail
		-- of the input that was in flight when it opened - a leftover from a
		-- run that has been abandoned. Nothing of the old pass comes out.
		--
		-- The same pair the savestate clean-up in the master script does, for
		-- the same reason: the schedule lives on the Lua side and clearing one
		-- half does not reach the other.
		defender.pending_input_sequence = nil
		loop_sched = nil
		loop_which = nil
		anchor = nil
		held_after = nil
		return
	end
	if pending == nil then
		loop_refill()
		if pending == nil then return end
	end
	service_body(defender)
end

return M
