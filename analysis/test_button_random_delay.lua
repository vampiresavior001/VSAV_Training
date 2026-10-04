-- RANDOM DELAY ON THE BUTTON, AND THE BUTTON WAIT IT SITS UNDER (v11.7.21.2).
--
-- Reversal / Counter Attack - Specified. The motion goes in at once; the button
-- waits Button Wait (was Guard Action Delay) plus a fresh draw
-- of 0..Random Delay, so a dash or jump attack is pressed at a different point
-- each time (user, 2026-10-03). The wait's ceiling is 60, menu and runtime.
--
--   [1]  randomStartWait.lua - the clamp and the draw
--   [2]  guardCancel's kd_delay_ticks, sliced out - ceiling, Auto, who adds it
--   [3]  GA.btn_rd_roll - Specified only
--   [4]  the runner's deferred start (Random Start Wait above 0): the draw
--        survives the Auto swap
--   [5]  GA.rsw_defer -> runner, end to end, with the real kd_delay_ticks
--   [6]  the menu rows: name, value, ceiling
--   [7]  the wiring that is only visible in the source
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_button_random_delay.lua
local ram = {}
memory = {
	readbyte  = function(a) return ram[a] or 0 end,
	readdword = function(a) return ram[a] or 0 end,
}
gui = { text = function() end, box = function() end }
emu = { framecount = function() return 1 end }
globals = { dummy = { guard_action = "reversal" }, options = {} }
training_settings = { action_sequences = {}, random_start_wait = 0, button_random_delay = 0 }
function mark_training_settings_dirty() end
function dash_attack_ticks_for() return nil end
seq_dash_cancel_reverse = { ["forward dash cancel"] = "back", ["back dash cancel"] = "forward" }

local function slurp(path)
	local fh = io.open(path)
	assert(fh, path .. " が読めない")
	local s = fh:read("*a")
	fh:close()
	return s
end

-- The real make_input_sequence, lifted out of controller.lua.
local csrc = slurp("controller.lua")
local cs = csrc:find("function make_input_sequence", 1, true)
local ce = csrc:find("\nend", csrc:find("return _sequence", cs, true), true)
assert(cs and ce, "make_input_sequence が controller.lua に見つからない")
assert(loadstring(csrc:sub(cs, ce + 4)))()

function queue_input_sequence(_d, _seq)
	_d.pending_input_sequence = { sequence = _seq, current_frame = 1 }
end

local RSW = dofile("randomStartWait.lua")
package.loaded["./scripts/randomStartWait"] = RSW
local R = dofile("actionSequenceRunner.lua")

local fails = 0
local function fail(what, got, want)
	fails = fails + 1
	print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(want) .. "]")
end
local function eq(what, got, want)
	if got == want then print("  ok " .. what .. " = " .. tostring(got))
	else fail(what, got, want) end
end
local function show(e)
	if e == nil then return "nil" end
	return "{" .. table.concat(e, ",") .. "}"
end
local real_random = math.random

local P2 = 0xFF8800
local CLOCK = 0xFF8081
local CID = 0xFF8B82

-- ---------------------------------------------------------------------------
print("[1] 設定の読み方と抽選")
training_settings.button_random_delay = nil
eq("未設定は 0", RSW.button_limit(), 0)
eq("未設定の抽選", RSW.roll_button(), 0)
training_settings.button_random_delay = -3
eq("負は 0", RSW.button_limit(), 0)
training_settings.button_random_delay = 90
eq("上限 60 で止まる", RSW.button_limit(), 60)
training_settings.button_random_delay = "x"
eq("数でないものは 0", RSW.button_limit(), 0)
training_settings.button_random_delay = 5.9
eq("端数は切り捨て", RSW.button_limit(), 5)
-- Its own setting: the start wait neither feeds nor blocks it.
training_settings.random_start_wait = 40
training_settings.button_random_delay = 0
eq("Random Start Wait を読まない", RSW.roll_button(), 0)
training_settings.random_start_wait = 0
training_settings.button_random_delay = 60
math.randomseed(4242)
local seen, lo, hi = {}, 99, -1
for _ = 1, 20000 do
	local v = RSW.roll_button()
	seen[v] = true
	if v < lo then lo = v end
	if v > hi then hi = v end
end
eq("最小", lo, 0)
eq("最大", hi, 60)
local all = true
for v = 0, 60 do if not seen[v] then all = false end end
eq("0..60 の全部が出る", all, true)
eq("Random Start Wait の抽選には影響しない", RSW.roll(), 0)
training_settings.button_random_delay = 0

-- ---------------------------------------------------------------------------
print("[2] kd_delay_ticks - 上限 60、Auto、足すのは Specified だけ")
local gsrc = slurp("guardCancel.lua")
local k1 = gsrc:find("local function kd_delay_ticks()", 1, true)
local k2 = k1 and gsrc:find("\nend\n", k1, true)
assert(k1 and k2, "kd_delay_ticks が guardCancel.lua に見つからない")
-- Sliced as a global so this file can call it; it reads GA, dash_attack_ticks
-- and actionSequenceRunnerModule as globals here, upvalues in the game.
local kd_src = gsrc:sub(k1, k2 + 4):gsub("^local function kd_delay_ticks", "function kd_delay_ticks")
GA = {}
local arm_dash = 13
function dash_attack_ticks() return arm_dash end
local first_wait = nil
actionSequenceRunnerModule = { first_wait = function() return first_wait end }
assert(loadstring(kd_src))()

local function kd(ga, gd, rd)
	globals.dummy.guard_action = ga
	globals.options.gc_delay = gd
	GA.btn_rd = rd
	return kd_delay_ticks()
end
eq("Reversal 14", kd("reversal", 14, 0), 14)
eq("31-50 が 30 で止まらない (45)", kd("reversal", 45, 0), 45)
eq("上限 60 (75 -> 60)", kd("reversal", 75, 0), 60)
eq("Random Delay を足す (14 + 7)", kd("reversal", 14, 7), 21)
eq("足した分は上限の外 (60 + 60)", kd("reversal", 60, 60), 120)
eq("Auto はダッシュの値に足す (13 + 5)", kd("reversal", -1, 5), 18)
arm_dash = nil
eq("ダッシュでない Auto は 0 + 5", kd("reversal", -1, 5), 5)
arm_dash = 13
eq("Counter も同じ (10 + 3)", kd("counter", 10, 3), 13)
eq("btn_rd が無ければ 0 として扱う", kd("counter", 10, nil), 10)
first_wait = 10
eq("Action Steps は 1 歩目の Wait だけ (足さない)", kd("sequence", 0, 7), 10)
first_wait = 45
eq("1 歩目の Wait の上限は 30 のまま", kd("sequence", 0, 0), 30)
first_wait = nil
eq("Character Specific には足さない", kd("Character Specific Reversal", 10, 7), 10)
eq("Push Block には足さない", kd("pb", 10, 7), 10)
eq("数でない設定は 0", kd("reversal", nil, 7), 0)

-- ---------------------------------------------------------------------------
print("[3] GA.btn_rd_roll - Specified の反撃とカウンタだけ引く")
local r1 = gsrc:find("function GA.btn_rd_roll()", 1, true)
local r2 = r1 and gsrc:find("\nend\n", r1, true)
assert(r1 and r2, "GA.btn_rd_roll が guardCancel.lua に見つからない")
assert(loadstring(gsrc:sub(r1, r2 + 4)))()
training_settings.button_random_delay = 20
math.random = function(a, b) return b - 3 end
globals.dummy.guard_action = "reversal"
eq("reversal は引く (0..20)", GA.btn_rd_roll(), 17)
globals.dummy.guard_action = "counter"
eq("counter は引く", GA.btn_rd_roll(), 17)
for _, ga in ipairs({ "sequence", "pb", "gc", "none", "Character Specific Reversal",
                      "recording on reversal" }) do
	globals.dummy.guard_action = ga
	eq(ga .. " は 0", GA.btn_rd_roll(), 0)
end
math.random = real_random
training_settings.button_random_delay = 0
globals.dummy.guard_action = "reversal"
eq("設定 0 なら 0", GA.btn_rd_roll(), 0)

-- ---------------------------------------------------------------------------
-- A stand-in for guardCancel's walker, as in test_random_start_wait.lua: two
-- passes per tick, v158 pacing, the owns() gate. Each entry is logged on the
-- first tick it is asserted.
local now = 0
local defender = {}
local log = {}
local function cost(e)
	if #e == 0 then return 1 end
	for _, k in ipairs(e) do
		if k ~= "forward" and k ~= "back" and k ~= "up" and k ~= "down" then return 1 end
	end
	return 2
end
local function walk_tick()
	ram[CLOCK] = now % 256
	for _ = 1, 2 do
		if not R.owns(globals.dummy.guard_action) then break end
		R.service(defender)
		local s = defender.pending_input_sequence
		if s == nil or not s.seq_tick then break end
		local i = s.current_frame or 1
		if i <= #s.sequence then
			local e = s.sequence[i]
			if (s.tick_held or 0) == 0 then
				log[#log + 1] = { tick = now, entry = e, rec = s, index = i }
			end
			s.tick_held = (s.tick_held or 0) + 1
			if s.tick_held >= cost(e) then
				s.current_frame = i + 1
				s.tick_held = 0
			end
			break
		end
		defender.pending_input_sequence = nil
	end
	now = now + 1
end
local function run(n) for _ = 1, n do walk_tick() end end
local function free() ram[P2 + 0x05] = 0 ; ram[P2 + 0x06] = 0 ; ram[P2 + 0x38] = 0 end
local function reset(ga)
	R.cancel()
	defender = {}
	log = {}
	now = 0
	globals.dummy.guard_action = ga or "reversal"
end
local function has(e, k)
	for _, v in ipairs(e or {}) do if v == k then return true end end
	return false
end
local function first_with(k)
	for _, l in ipairs(log) do if has(l.entry, k) then return l end end
	return nil
end
-- Ticks from the motion's last tap (its second tick) to the press.
local function gap(btn)
	local taps = {}
	for _, l in ipairs(log) do
		if l.rec.sequence == log[1].rec.sequence then taps[#taps + 1] = l end
	end
	local press = first_with(btn)
	if press == nil or #taps == 0 then return nil end
	return press.tick - (taps[#taps].tick + 1)
end

-- ---------------------------------------------------------------------------
print("[4] runner - Auto の差し替えで乱数が消えない")
reset("reversal")
ram[CID] = 0x02                       -- Gallon: f = 7, fc = 15 (MEASURED_STEP_FLOORS)
local fdhp = make_input_sequence("forward dash", "HP", "", 0)
R.arm_oneshot("reversal", fdhp, { wait = 5, adj = 0, delay = 13 + 4, hold_dir = true,
	auto_dash = "forward dash", delay_extra = 4 })
free()
run(60)
eq("押し - 動作の最後 (= 実測 7 + 4)", gap("HP"), 11)
reset("reversal")
R.arm_oneshot("reversal", fdhp, { wait = 5, adj = 0, delay = 13, hold_dir = true,
	auto_dash = "forward dash" })
free()
run(60)
eq("delay_extra が無ければ実測 7 のまま", gap("HP"), 7)
reset("reversal")
R.arm_oneshot("reversal", fdhp, { wait = 5, adj = 0, delay = 10 + 6, hold_dir = true })
free()
run(60)
eq("数値の Wait は delay に入った分だけ (10 + 6)", gap("HP"), 16)
ram[CID] = 0

-- ---------------------------------------------------------------------------
print("[5] GA.rsw_defer -> runner (本物の kd_delay_ticks で)")
local s1 = gsrc:find("function GA.rsw_draw()", 1, true)
local s2 = gsrc:find("function GA.rsw_defer()", 1, true)
local e2 = s2 and gsrc:find("\nend", s2, true)
assert(s1 and s2 and e2, "GA.rsw_draw / GA.rsw_defer が guardCancel.lua に見つからない")
DASH_CANCEL_REVERSE = { ["forward dash cancel"] = "back", ["back dash cancel"] = "forward" }
BUTTON_LEVER_DIR = {}
function kd_press_base() return 1 end
function kd_holds_direction() return true end
debugKnockdownModule = { mark_write = function() end }
local stick, button = "forward dash", "HP"
function GA.stick() return stick end
function GA.button() return button end
assert(loadstring(gsrc:sub(s1, e2 + 4)))()
-- The real runner from here on: rsw_defer hands it the arm's numbers.
actionSequenceRunnerModule = R

reset("reversal")
ram[CID] = 0x02
globals.options = { counter_attack_lever = 1, gc_delay = -1 }
training_settings.random_start_wait = 10
training_settings.button_random_delay = 8
math.random = function(a, b) return 6 end   -- start wait 6, button 6
GA.btn_rd = GA.btn_rd_roll()
eq("待つので runner に渡す", GA.rsw_defer(), true)
math.random = real_random
free()
run(80)
eq("Auto: 押し - 動作の最後 (= 実測 7 + 乱数 6)", gap("HP"), 13)

reset("counter")
globals.options = { counter_attack_lever = 1, gc_delay = 9 }
math.random = function(a, b) return 3 end
GA.btn_rd = GA.btn_rd_roll()
eq("カウンタも渡す", GA.rsw_defer(), true)
math.random = real_random
free()
run(80)
eq("数値: 押し - 動作の最後 (= 9 + 3)", gap("HP"), 12)
training_settings.random_start_wait = 0
training_settings.button_random_delay = 0
ram[CID] = 0

-- ---------------------------------------------------------------------------
print("[6] メニューの行")
package.preload["./scripts/charMoves"] = function()
	return { get_player_movelists = function()
		return { P1 = { reversal_names = { "Stub" } }, P2 = { reversal_names = { "Stub" } } }
	end }
end
package.preload["./scripts/actionSequenceEditor"] = function() return dofile("actionSequenceEditor.lua") end
package.preload["./scripts/actionSequenceRunner"] = function() return R end
package.preload["./scripts/position"] = function() return dofile("position.lua") end
dofile("menu.lua")
local shipped = dofile("config.lua").default_training_settings
for k, v in pairs(shipped) do
	if training_settings[k] == nil then training_settings[k] = v end
end
eq("既定は 0 (オフ)", shipped.button_random_delay, 0)
globals.getCharacter = function() return "Sasquatch" end
menuModule.guiRegister()
local dummy
for _, tab in ipairs(menu) do if tab.name == "Dummy" then dummy = tab end end
local bw, brd
for _, e in ipairs(dummy.entries) do
	if e.property_name == "gc_delay" then bw = e end
	if e.property_name == "button_random_delay" then brd = e end
end
assert(bw and brd, "Button Wait / Random Delay の行が無い")
local function drawn(e, sel)
	local got, gx
	local real = gui.text
	gui.text = function(_x, _y, _t) if got == nil then got, gx = tostring(_t), _x end end
	e:draw(0, 0, sel)
	gui.text = real
	return got, gx
end
-- The motion list is local to menu.lua, so its order is read from the source:
-- the setting is an index into it.
local stick_list = {}
do
	local msrc0 = slurp("menu.lua")
	local b = msrc0:find("local counter_attack_stick = {", 1, true)
	local e = b and msrc0:find("\n}", b, true)
	assert(b and e, "counter_attack_stick が menu.lua に見つからない")
	for line in msrc0:sub(b, e):gmatch("[^\n]+") do
		if not line:match("^%s*%-%-") then
			local v = line:match('^%s*"([^"]+)"')
			if v then stick_list[#stick_list + 1] = v end
		end
	end
end
local function stick_index(name)
	for i, v in ipairs(stick_list) do if v == name then return i end end
end
training_settings.guard_action = 6
training_settings.counter_attack_stick = stick_index("Forward Dash")
training_settings.gc_delay = -1
eq("Specified の名前と Auto", drawn(bw), "Button Wait : Auto")
training_settings.gc_delay = 14
eq("数値", drawn(bw, true), "< Button Wait : 14 >")
training_settings.guard_action = 8
eq("Counter も同じ名前", drawn(bw), "Button Wait : 14")
training_settings.guard_action = 3
eq("Push Block も同じ名前", drawn(bw), "Button Wait : 14")
training_settings.guard_action = 10
eq("PB Recording も同じ名前", drawn(bw), "Button Wait : 14")
training_settings.guard_action = 6
training_settings.counter_attack_stick = stick_index("QCF")
training_settings.gc_delay = -1
eq("ダッシュでない Auto は 0 と出す", drawn(bw), "Button Wait : 0")
training_settings.gc_delay = 59
bw:right() ; bw:right()
eq("上限 60", training_settings.gc_delay, 60)
training_settings.gc_delay = -1

training_settings.button_random_delay = 0
local t, x = drawn(brd)
eq("0 は 0", t, "Random Delay : 0")
-- The indent is the draw loop's now (menu_row_x, 2026-10-04): the row draws
-- where it is told, and sits one level (8px, 2 文字) deeper than Button Wait.
eq("自分では字下げしない", x, 0)
eq("Button Wait より 8px (2 文字) 深い", menu_row_x(brd, 0) - menu_row_x(bw, 0), 8)
training_settings.button_random_delay = 5
eq("0-N で出す", drawn(brd, true), "< Random Delay : 0-5 >")
training_settings.button_random_delay = 59
brd:right() ; brd:right()
eq("上限 60", training_settings.button_random_delay, 60)
training_settings.button_random_delay = 0
brd:left()
eq("下限 0", training_settings.button_random_delay, 0)

-- ---------------------------------------------------------------------------
print("[7] 配線")
local function count(src, pat)
	local n, at = 0, 1
	while true do
		local f = src:find(pat, at, true)
		if f == nil then return n end
		n = n + 1
		at = f + 1
	end
end
-- The arm: drawn after _armed is known and before rsw_defer, which reads it.
local a_armed = gsrc:find("_armed = (arm_edge or hs_arm_edge or BLK.edge)", 1, true)
local a_defer = gsrc:find("and GA.rsw_defer() then", 1, true)
local a_draw = a_armed and gsrc:find("GA.btn_rd = GA.btn_rd_roll()", a_armed, true)
eq("アームで rsw_defer の前に引く", a_draw ~= nil and a_defer ~= nil and a_draw < a_defer, true)
-- The reactive fallback: drawn right in front of the queue it makes.
local q = "GA.btn_rd = GA.btn_rd_roll()\n\t\t\t\t_defender.counter.sequence = ga_sequence(_stick, _button, delay_type, 0)"
eq("反応経路でも積む直前に引く", gsrc:find(q, 1, true) ~= nil, true)
eq("引くのはこの 2 か所だけ", count(gsrc, "GA.btn_rd = GA.btn_rd_roll()"), 2)
eq("Auto のときは runner に乱数を別に渡す",
	gsrc:find("_o.auto_dash = GA.stick()\n\t\t\t-- The Random Delay", 1, true) ~= nil
	and gsrc:find("_o.delay_extra = GA.btn_rd or 0", 1, true) ~= nil, true)
-- The eight-frame cleanup in service_held_reversal must wait while the hook
-- still owes a deferred press: it released the held last entry first and the
-- dummy swung twice (kd_c0A_s02..s08, every press later than ~12 Ticks after
-- free). Bounded to that function's tick_owned branch.
local sh = gsrc:find("local function service_held_reversal()", 1, true)
local to = sh and gsrc:find("_seq.tick_owned = true", sh, true)
local gate = to and gsrc:find("if memory.readbyte(0xFF8805) == 0x00 and fast_press_lg == nil then", to, true)
local rel = gate and gsrc:find("release_input_sequence(_d)", gate, true)
eq("8 フレーム後の片付けは、押しが残っている間は放さない",
	gate ~= nil and gate - to < 1200 and rel ~= nil and rel - gate < 3000, true)
local rsrc = slurp("actionSequenceRunner.lua")
eq("runner は実測値に足す", rsrc:find("bwait = n + (o.delay_extra or 0)", 1, true) ~= nil, true)
local msrc = slurp("menu.lua")
eq("Button Wait の上限 60", msrc:find('GAD_NAME, training_settings, "gc_delay", -1, 60,', 1, true) ~= nil, true)
eq("Random Delay の上限 60", msrc:find('"button_random_delay", 0, 60,', 1, true) ~= nil, true)
eq("旧名が説明文に残っていない", count(msrc, "replaces Guard Action Delay"), 0)
local master = slurp("vsav_training_master_script.lua")
eq("乱数のモジュールは起動時に読み込み済み",
	master:find('= require "./scripts/randomStartWait"', 1, true) ~= nil, true)

print(fails == 0 and "\n全て通った" or ("\n" .. fails .. " 件 NG"))
os.exit(fails == 0 and 0 or 1)
