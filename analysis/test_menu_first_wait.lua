-- A FIRST RUN WAITING OUT ITS START IS KEPT BY THE MENU (v11.7.29.1; review of
-- bbe8bfe).
--
-- Random Start Wait (and step one's Random Delay) park the first run in the
-- runner's pending list rather than in the delivery slot. M.menu_open read an
-- empty slot as a run in progress and dropped it: open the menu while the
-- dummy was still in stun and the counter never came. The real runner is driven
-- tick by tick; the menu frames run no tick (the game stands), as in play.
--
--   [1] Specified (arm_oneshot), wait 20: menu or not, the same input at the
--       same tick; opened several times, still the same
--   [2] Action Steps (arm_deferred): the same, step two included
--   [3] a run whose first segment is out still ends at the menu
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_menu_first_wait.lua
local ram = {}
memory = {
	readbyte  = function(a) return ram[a] or 0 end,
	readword  = function(a) return ram[a] or 0 end,
	readdword = function(a) return ram[a] or 0 end,
}
gui = { text = function() end, box = function() end }
emu = { framecount = function() return 1 end }
globals = { dummy = { guard_action = "reversal" }, options = {}, show_menu = false,
            match_running = function() return true end }
training_settings = { action_sequences = {}, specified_loop = false }
function mark_training_settings_dirty() end
function dash_attack_ticks_for() return nil end
-- The real make_input_sequence, lifted out of controller.lua (the step lists
-- compile through it).
do
	local csrc = io.open("controller.lua"):read("*a")
	local cs = csrc:find("function make_input_sequence", 1, true)
	local ce = csrc:find("\nend", csrc:find("return _sequence", cs, true), true)
	assert(loadstring(csrc:sub(cs, ce + 4)))()
end
local sent = {}
local now = 0
function queue_input_sequence(d, seq)
	if d.pending_input_sequence ~= nil then return end
	d.pending_input_sequence = { sequence = seq, current_frame = 1 }
	local parts = {}
	for _, e in ipairs(seq) do parts[#parts + 1] = table.concat(e, "+") end
	sent[#sent + 1] = now .. ":" .. table.concat(parts, ",")
end
local R = dofile("actionSequenceRunner.lua")

local fails = 0
local function eq(what, got, want)
	if got == want then print("  ok " .. what .. " = " .. tostring(got))
	else
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(want) .. "]")
	end
end

local P2, TICKS = 0xFF8800, 0xFF8081
local function free() ram[P2 + 0x05] = 0 ; ram[P2 + 0x06] = 0 ; ram[P2 + 0x38] = 0 end
local function stun() ram[P2 + 0x05] = 2 ; ram[P2 + 0x06] = 0 ; ram[P2 + 0x38] = 0 end
local defender = {}
local function tick()
	now = now + 1
	ram[TICKS] = now % 256
	R.service(defender)
	local s = defender.pending_input_sequence
	if s ~= nil then
		s.current_frame = (s.current_frame or 1) + 1
		if s.current_frame > #s.sequence then defender.pending_input_sequence = nil end
	end
end
-- The master's frame call while the menu is up: no tick runs.
local function menu(frames)
	globals.show_menu = true
	for _ = 1, frames do
		if R.owns(globals.dummy.guard_action) then R.menu_open(defender) end
	end
	globals.show_menu = false
end

local A = { { "forward" }, {}, { "forward", "LP" } }
local function specified(opens)
	R.cancel()
	defender, sent, now = {}, {}, 0
	globals.dummy.guard_action = "reversal"
	R.arm_oneshot("reversal", A, { wait = 20, adj = 0, delay = 0, hold_dir = true }, nil)
	stun()
	for i = 1, 3 do tick() ; if opens[i] then menu(opens[i]) end end
	free()
	for _ = 1, 60 do tick() end
	return table.concat(sent, " | ")
end

print("[1] Specified の Random Start Wait (arm_oneshot, wait 20)")
local base = specified({})
eq("メニューを開かない: 1 回出る", base ~= "", true)
eq("やられ中に開いて閉じる: 同じ Tick に同じ入力", specified({ [2] = 5 }), base)
eq("何度も開閉: 同じ", specified({ [1] = 3, [2] = 40, [3] = 1 }), base)

print("[2] Action Steps (arm_deferred)")
ram[0xFF8B82] = 0x08
training_settings.action_sequences = { reversal = { ["8"] = { version = 1, steps = {
	{ action = "atk", lever = "none", button = "LP", wait = 0 },
	{ action = "atk", lever = "down", button = "MK", wait = -1 },
} } } }
local function steps(opens)
	R.cancel()
	defender, sent, now = {}, {}, 0
	globals.dummy.guard_action = "sequence"
	local ok = R.arm_deferred("reversal", { wait = 20, adj = 0, delay = 0, hold_dir = false })
	stun()
	for i = 1, 3 do tick() ; if opens[i] then menu(opens[i]) end end
	free()
	for _ = 1, 80 do tick() end
	return (ok and "armed " or "not armed ") .. table.concat(sent, " | ")
end
local sbase = steps({})
eq("メニューを開かない: 1 歩目と 2 歩目が出る", select(2, sbase:gsub("|", "")) >= 1, true)
eq("やられ中に開閉: 同じ", steps({ [2] = 5 }), sbase)
eq("何度も開閉: 同じ", steps({ [1] = 2, [3] = 9 }), sbase)

print("[3] 始まった run はこれまでどおり終わる")
do
	R.cancel()
	defender, sent, now = {}, {}, 0
	globals.dummy.guard_action = "sequence"
	R.arm_deferred("reversal", { wait = 2, adj = 0, delay = 0, hold_dir = false })
	free()
	local guard = 0
	while #sent == 0 and guard < 40 do tick() ; guard = guard + 1 end
	eq("1 歩目が出た", #sent, 1)
	eq("  始まったので first_waiting は下りる", R.first_waiting, false)
	menu(3)
	eq("メニューで残りは落ちる", R.pending_count(), 0)
	for _ = 1, 40 do tick() end
	eq("  閉じても 2 歩目は出ない", #sent, 1)
end

print(fails == 0 and "\n全て通った" or ("\n" .. fails .. " 件 NG"))
os.exit(fails == 0 and 0 or 1)
