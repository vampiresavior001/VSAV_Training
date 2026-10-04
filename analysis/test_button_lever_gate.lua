-- A HIDDEN ROW MUST NOT ACT (v11.7.21.3).
--
-- Two settings were read while their rows were hidden, and both were found the
-- same afternoon (user, 2026-10-04):
--
-- THE BUTTON LEVER ROW IS SPECIFIED'S ALONE.
--
-- Reversal/Counter Button Lever is shown only for Reversal / Counter Attack -
-- Specified. It was read for every guard action anyway, so a Neutral left over
-- from a Specified session turned an Action Patterns dash step's second tap
-- into nothing: the tutorial's Short LP walked forward instead of dashing
-- (user, 2026-10-04; kd_c0A press_defer with lever 0).
--
-- THE PIT OF BLAME ROW IS ANAKARIS'S ALONE. Left on Random from an Anakaris
-- session, it put his DPF+K on Sasquatch 22 Ticks after every launch.
--
--   [1]  button_lever_bits, sliced out of guardCancel.lua
--   [2]  GA.rsw_defer - the lever handed to the runner
--   [3]  ga_sequence - a sequence with nothing to run runs nothing
--   [4]  the Pit of Blame trigger arms for Anakaris only, the id the row uses
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_button_lever_gate.lua
local function slurp(path)
	local fh = io.open(path)
	assert(fh, path .. " が読めない")
	local s = fh:read("*a")
	fh:close()
	return s
end

local fails = 0
local function eq(what, got, want)
	if got == want then print("  ok " .. what .. " = " .. tostring(got))
	else
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(want) .. "]")
	end
end

local gsrc = slurp("guardCancel.lua")
local function slice(head, tail)
	local a = gsrc:find(head, 1, true)
	local b = a and gsrc:find(tail, a, true)
	assert(a and b, head .. " が guardCancel.lua に見つからない")
	return gsrc:sub(a, b + #tail - 1)
end

-- The real tables, as globals here (locals in the game).
LEVER_DOWN = 0x04
assert(loadstring((slice("local BUTTON_LEVER_DIR = {", "\n}\n"):gsub("^local ", ""))))()
local function index_of(dirs)
	for i, t in pairs(BUTTON_LEVER_DIR) do
		if #t == #dirs then
			local same = true
			for k = 1, #dirs do if t[k] ~= dirs[k] then same = false end end
			if same then return i end
		end
	end
end
function facing_for_input() return 0 end   -- facing right: forward is 0x02

-- ---------------------------------------------------------------------------
print("[1] button_lever_bits - Specified のときだけ効く")
assert(loadstring((slice("local function button_lever_bits()", "\nend\n"):gsub("^local ", ""))))()
globals = { dummy = {}, options = {} }
local FWD = index_of({ "forward" })
assert(FWD, "BUTTON_LEVER_DIR に forward が無い")
local function lever(ga, li)
	globals.dummy.guard_action = ga
	globals.options.counter_attack_lever = li
	return button_lever_bits()
end
eq("Specified の反撃、As Is は上書きしない", lever("reversal", 1), nil)
eq("Specified の反撃、Neutral は 0", lever("reversal", 2), 0)
eq("Specified の反撃、Forward は前", lever("reversal", FWD), 0x02)
eq("Specified のカウンタ、Neutral は 0", lever("counter", 2), 0)
eq("Action Steps / Patterns では Neutral が残っていても効かない", lever("sequence", 2), nil)
eq("Action Steps / Patterns では Forward も効かない", lever("sequence", FWD), nil)
eq("Character Specific でも効かない", lever("Character Specific Reversal", 2), nil)
eq("Push Block でも効かない", lever("pb", 2), nil)

-- ---------------------------------------------------------------------------
print("[2] GA.rsw_defer - runner に渡すレバー")
GA = {}
DASH_CANCEL_REVERSE = { ["forward dash cancel"] = "back" }
function kd_press_base() return 1 end
function kd_delay_ticks() return 0 end
function kd_holds_direction() return true end
function make_input_sequence() return { { "forward" }, {}, { "forward", "LP" } } end
debugKnockdownModule = { mark_write = function() end }
function GA.stick() return "forward dash" end
function GA.button() return "LP" end
package.loaded["./scripts/randomStartWait"] = { roll = function() return 5 end }
local got
actionSequenceRunnerModule = {
	prepick = function() end,
	draw_first_delay = function() return 0 end,
	arm_deferred = function(_, o) got = o ; return true end,
	arm_oneshot = function(_, _, o) got = o ; return true end,
}
assert(loadstring(slice("function GA.rsw_draw()", "\nend\n")))()
assert(loadstring(slice("function GA.rsw_defer()", "\nend\n")))()
local function defer(ga, li)
	globals.dummy.guard_action = ga
	globals.options = { counter_attack_lever = li, gc_delay = 0 }
	got = nil
	GA.rsw_defer()
	return got
end
local o = defer("sequence", 2)
eq("Action Steps / Patterns には Neutral を渡さない", o and o.lever, nil)
o = defer("sequence", FWD)
eq("Action Steps / Patterns には Forward も渡さない", o and o.lever, nil)
o = defer("reversal", 2)
eq("Specified の Neutral は空のレバー", o and o.lever and #o.lever, 0)
o = defer("counter", FWD)
eq("Specified の Forward は前", o and o.lever and o.lever[1], "forward")

-- With nothing to run (no list, no pattern ticked) a sequence used to fall back
-- to the Specified motion and button - two more hidden rows.
local oneshot_called = false
actionSequenceRunnerModule.arm_deferred = function() return false end
actionSequenceRunnerModule.arm_oneshot = function() oneshot_called = true ; return true end
globals.dummy.guard_action = "sequence"
globals.options = { counter_attack_lever = 1, gc_delay = 0 }
eq("空のシーケンスは runner に何も渡さない", GA.rsw_defer(), false)
eq("Specified の動きで代わりに出さない", oneshot_called, false)
globals.dummy.guard_action = "reversal"
eq("Specified はこれまでどおり渡す", GA.rsw_defer(), true)
eq("Specified は oneshot で", oneshot_called, true)

-- ---------------------------------------------------------------------------
print("[3] ga_sequence - 空のシーケンスは何も出さない")
local runner_list = nil
actionSequenceRunnerModule.arm = function() return runner_list end
make_input_sequence = function(stick, button) return { { stick, button } } end
assert(loadstring((slice("local function ga_sequence(", "\nend\n"):gsub("^local ", ""))))()
globals.dummy.guard_action = "sequence"
runner_list = nil
eq("リストが無ければ nil (Specified の動きではない)", ga_sequence("up-forward", "HK", "", 0), nil)
runner_list = { { "forward" } }
eq("リストがあればそのリスト", ga_sequence("up-forward", "HK", "", 0), runner_list)
globals.dummy.guard_action = "reversal"
local spec = ga_sequence("up-forward", "HK", "", 0)
eq("Specified は設定の動き", spec and spec[1] and spec[1][1], "up-forward")

-- ---------------------------------------------------------------------------
print("[4] 咎めの穴はアナカリスのときだけ")
-- Inside service_held_reversal, so read in place: the arming line, between the
-- trigger's state read and the queue it leads to.
local t1 = gsrc:find("local _hurt_or_block = memory.readbyte(0xFF8805) == 0x02", 1, true)
local t2 = t1 and gsrc:find("make_input_sequence(PIT_OF_BLAME_STICK", t1, true)
local arm = t1 and gsrc:find("if memory.readbyte(0xFF8009) == 4 and _hurt_or_block and not pit_of_blame_armed\n"
	.. "\t   and memory.readbyte(0xFF8B82) == 0x06 then", t1, true)
eq("発動の準備はアナカリス (0x06) のときだけ", arm ~= nil and t2 ~= nil and arm < t2, true)
eq("準備はこの 1 か所だけ", select(2, gsrc:gsub("pit_of_blame_armed = true", "")), 1)
local msrc = slurp("menu.lua")
eq("メニューの行も同じ id で出し分ける",
	msrc:find("return memory.readbyte(0xFF8B82) ~= 0x06", 1, true) ~= nil, true)

print(fails == 0 and "\n全て通った" or ("\n" .. fails .. " 件 NG"))
os.exit(fails == 0 and 0 or 1)
