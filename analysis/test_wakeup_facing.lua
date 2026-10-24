-- Run from scripts/: lua5.1 ../analysis/test_wakeup_facing.lua
-- A wake-up can turn the dummy between the defer and the delivery of the
-- deferred press. The press must keep the corrected direction it was asked
-- for, which means its raw bits follow the facing byte.
local src = assert(io.open("guardCancel.lua")):read("*a")

local fails = 0
local function want(label, actual, expected)
	if actual ~= expected then
		fails = fails + 1
		print("NG " .. label .. ": " .. tostring(actual) .. " / " .. tostring(expected))
	end
end

-- The helper under test, lifted out of the source.
local first = assert(src:find("local function swap_facing_bits", 1, true))
local last = assert(src:find("\nend", first, true))
local swap = assert(loadstring(src:sub(first, last + 3)
	.. "\nreturn swap_facing_bits"))()

-- THE GAME'S OWN RULES, AS THE CODE STATES THEM.
--
-- 0x022194 exchanges raw lever bits 0 and 1 when the facing byte $b is set;
-- corrected space keeps forward on bit1 and back on bit0 for every facing
-- (guardCancel.lua, the block above LEVER_DOWN). entry_to_bits() implements
-- exactly that: forward is raw bit1 when $b == 0 and raw bit0 when it is not.
local function raw_for(_dir, _b)
	if _dir == "forward" then return (_b == 0) and 2 or 1 end
	return (_b == 0) and 1 or 2
end
local function corrected(_raw, _b)
	if _b == 1 then return swap(_raw) end
	return _raw
end

-- A press resolved against one facing and delivered under another must still
-- read as the same corrected direction once the game applies its swap.
for _, dir in ipairs({ "forward", "back" }) do
	for _, at_defer in ipairs({ 0, 1 }) do
		for _, at_press in ipairs({ 0, 1 }) do
			local raw = raw_for(dir, at_defer)
			local label = dir .. " defer $" .. at_defer .. " press $" .. at_press
			if at_press ~= at_defer then raw = swap(raw) end
			want(label .. " corrected bit1", corrected(raw, at_press),
				(dir == "forward") and 2 or 1)
		end
	end
end

-- Bits that are not facing-relative must never move, alone or combined.
want("neutral stays", swap(0), 0)
want("down stays", swap(4), 4)
want("up stays", swap(8), 8)
want("down+forward follows the facing", swap(6), 5)
want("down+back follows the facing", swap(5), 6)
want("up+down stays", swap(12), 12)
want("both sides stays", swap(3), 3)

-- SOURCE CONTRACTS.
--
-- Both defer sites capture the reference; a third site appearing without one
-- would deliver unswapped bits across the turn.
want("two defer sites capture the facing",
	select(2, src:gsub("fast_press_fref = facing_for_input%(%)", "")), 2)
want("the delivery compares the reference",
	src:find("fast_press_fref ~= nil and GA.fast_press_face_now() ~= fast_press_fref", 1, true) ~= nil, true)
-- The mark must show what was actually asserted, not what was captured.
local at = assert(src:find('mark_write("press_now"', 1, true))
want("press_now marks the re-aimed bits",
	src:find("_pl * 256", at, true) ~= nil, true)

-- ---------------------------------------------------------------------------
-- A SPECIFIED DASH, AND ALL OF ITS DEFERRED DELIVERY (v11.7.28.4).
--
-- User 2026-10-17: a wake-up forward dash cancel + MP came out as a standing
-- MP. Measured (kd_c0A, v11.7.28.3): 9 of 9 wake-ups that turned failed, 2 of 2
-- that did not dashed. The record carried its button in the last entry, so it
-- was not raw and every direction went in on the side the opponent is on;
-- $b, which the game swaps $122 with, kept the way the dummy lay until the
-- free tick. And only the press was re-aimed: the second tap and the
-- cancel's reverse were not.

-- Every defer site records whether it resolved raw, right after the facing.
want("both defer sites remember raw-ness",
	select(2, src:gsub("fast_press_fref = facing_for_input%(%)\n%s*GA%.fast_press_raw = GA%.pending_raw%(%)", "")), 2)
want("the second tap is re-aimed",
	src:find("local _ml = GA.fast_press_aim(fast_press_mlev)", 1, true) ~= nil, true)
want("the cancel's reverse is re-aimed",
	src:find("local _rv = GA.fast_press_aim(fast_press_rev)", 1, true) ~= nil, true)
want("the press is re-aimed",
	src:find("local _pl = GA.fast_press_aim(fast_press_lev)", 1, true) ~= nil, true)
want("Specified and Action Steps / Patterns dashes are queued raw",
	src:find("if (_ga0 == 'reversal' or _ga0 == 'counter' or _ga0 == 'sequence')\n\t\t   and GA.RAW_DASH_STICK[GA.stick()] then\n\t\t\t_q.raw_dir = true", 1, true) ~= nil, true)
-- For Action Steps / Patterns GA.stick() is step one's motion (2026-10-25,
-- Gallon's wake-up dash on a turn).
want("  for 'sequence' GA.stick() is step one's motion",
	src:find("function GA.stick()\n\tif globals.dummy.guard_action == 'sequence' then\n\t\tlocal _m = actionSequenceRunnerModule.first_motion(\"reversal\")", 1, true) ~= nil, true)
for _, st in ipairs({ "forward dash", "back dash", "forward dash cancel", "back dash cancel" }) do
	want("  " .. st .. " is one of them", src:find('["' .. st .. '"] = true', 1, true) ~= nil, true)
end

-- The re-aim itself, lifted out and run: fref, $b and the facing standing in.
local s0 = assert(src:find("GA.fast_press_raw = false\n", 1, true))
local e0 = assert(src:find("function GA.pending_raw()", s0, true))
local e1 = assert(src:find("\nend\n", e0, true))
GA = {}
local b_now, side_now = 1, 0
memory = { readbyte = function(a) if a == 0xFF880B then return b_now end return 0 end }
actionSequenceRunnerModule = { orientation = { steps_face = function(live) return live end } }
GA.af_run_now = function() return nil end
facing_for_input = function() return side_now end
swap_facing_bits = swap
assert(loadstring(src:sub(s0, e1 + 4)))()

-- The measured wake-up (kd_c0A_s03): $b is 1 through free-1 and 0 from the
-- free tick; the opponent's side is 0 throughout. Tap one on free-3, the
-- neutral, the second tap held on free-1 and free, the reverse from free+1,
-- the press with the Button Lever forward on free+7.
local B = { [-3] = 1, [-2] = 1, [-1] = 1, [0] = 0, [1] = 0, [7] = 0 }
local function run(raw)
	local seen = {}
	local function face(t) if raw then return B[t] end return side_now end
	local function deliver(t, lev) seen[#seen + 1] = corrected(lev, B[t]) end
	deliver(-3, raw_for("forward", face(-3)))                 -- tap one, resolved live
	-- The defer, on free-2: what the motion, reverse and press were captured as.
	b_now = B[-2]
	GA.fast_press_raw = raw
	fast_press_fref = face(-2)
	local mlev, rev, lev = raw_for("forward", face(-2)), raw_for("back", face(-2)), raw_for("forward", face(-2))
	for _, t in ipairs({ -1, 0 }) do b_now = B[t] ; deliver(t, GA.fast_press_aim(mlev)) end
	b_now = B[1] ; deliver(1, GA.fast_press_aim(rev))
	b_now = B[7] ; deliver(7, GA.fast_press_aim(lev))
	local names = {}
	for _, v in ipairs(seen) do names[#names + 1] = (v == 2) and "F" or (v == 1) and "B" or tostring(v) end
	return table.concat(names, " ")
end
want("before: resolved on the side - the taps disagree (as measured)", run(false), "B B F B F")
want("now: raw - forward, forward twice, back, forward", run(true), "F F F B F")
-- Without the turn nothing moves either way.
B = { [-3] = 0, [-2] = 0, [-1] = 0, [0] = 0, [1] = 0, [7] = 0 }
want("no turn, before", run(false), "F F F B F")
want("no turn, now", run(true), "F F F B F")

-- AUTO-FLIP OFF DOES NOT FIX A RUN'S FACING WHILE THE DUMMY IS STILL TURNING
-- (2026-10-25, Gallon's wake-up dash after Demitri's punch throw: 11 of 11
-- turning wake-ups gave no dash with Auto-Flip off, 9 of 9 that did not turn
-- dashed). The side switch came before the run; only one inside it is held.
want("facing_for_input fixes the facing only once $b agrees with the side",
	src:find("_press ~= false and not facing_unsettled())", 1, true) ~= nil
	and src:find("local function facing_unsettled()", 1, true) < src:find("local function facing_for_input(_press)", 1, true), true)
do
	local IO = dofile("inputOrientation.lua")
	local keep = training_settings
	training_settings = { auto_flip_inputs = false }
	-- Wake-up turn: the first tap while turning (not fixed), the second after.
	local id = IO.steps_begin()
	local f1 = IO.steps_face(0, id, false)     -- tap 1: $b 0 still, turning: press passed as false
	local f2 = IO.steps_face(1, id, true)      -- tap 2: turned, $b 1: fixed now
	local f3 = IO.steps_face(0, id, true)      -- later: held at 1
	want("Auto-Flip off, wake-up turn: tap 1 by the old facing, tap 2 by the new", f1 .. "," .. f2, "0,1")
	want("  fixed from tap 2 on", f3, 1)
	-- A switch inside the run: the first press is fixed and held.
	id = IO.steps_begin()
	local g1 = IO.steps_face(0, id, true)
	local g2 = IO.steps_face(1, id, true)
	want("Auto-Flip off, switch inside the run: held at the first press", g1 .. "," .. g2, "0,0")
	IO.steps_end()
	training_settings = keep
end

print(fails == 0 and "REP_OK" or (fails .. " REP_NG"))
os.exit(fails == 0 and 0 or 1)
