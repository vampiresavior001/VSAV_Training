-- RANDOM START WAIT (user, 2026-10-02).
--
-- One setting, 0-60 game Ticks. Every time the dummy starts an action of its
-- own, it first waits a fresh draw of 0..N; defence never waits, and neither
-- does the Recording Wizard's check playback.
--
--   [1]      randomStartWait.lua - the clamp and the draw
--   [2]-[8]  the runner's delayed step one (start_steps, arm_oneshot,
--            arm_deferred) on a stand-in for guardCancel's tick walker
--   [9]      a loop lap's draw
--   [10]     guardCancel's GA.rsw_defer, sliced out of the file
--   [11]     macro.lua's countdown, sliced out, and where it sits
--   [12]     the wiring that is only visible in the source
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_random_start_wait.lua
local ram = {}
memory = {
	readbyte  = function(a) return ram[a] or 0 end,
	readdword = function(a) return ram[a] or 0 end,
}
gui = { text = function() end, box = function() end }
emu = { framecount = function() return 1 end }
globals = { dummy = { guard_action = "reversal" }, options = {} }
training_settings = { action_sequences = {}, random_start_wait = 0 }
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
-- The runner looks the module up by the path the game uses.
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

local P2 = 0xFF8800
local CLOCK = 0xFF8081
local CID = 0xFF8B82

-- ---------------------------------------------------------------------------
print("[1] 設定の読み方と抽選")
training_settings.random_start_wait = nil
eq("未設定は 0", RSW.limit(), 0)
eq("未設定の抽選", RSW.roll(), 0)
training_settings.random_start_wait = -5
eq("負は 0", RSW.limit(), 0)
training_settings.random_start_wait = 75
eq("上限 60 で止まる", RSW.limit(), 60)
training_settings.random_start_wait = "x"
eq("数でないものは 0", RSW.limit(), 0)
training_settings.random_start_wait = 20.7
eq("端数は切り捨て", RSW.limit(), 20)
training_settings.random_start_wait = 60
math.randomseed(12345)
local seen, lo, hi = {}, 99, -1
for _ = 1, 20000 do
	local v = RSW.roll()
	seen[v] = true
	if v < lo then lo = v end
	if v > hi then hi = v end
end
eq("最小", lo, 0)
eq("最大", hi, 60)
local all = true
for v = 0, 60 do if not seen[v] then all = false end end
eq("0..60 の全部が出る", all, true)
training_settings.random_start_wait = 0

-- ---------------------------------------------------------------------------
-- A stand-in for guardCancel's walker: the same two passes per tick, the same
-- v158 pacing (a bare direction two ticks, anything else one), the same gate
-- on owns(). Each entry is logged on the first tick it is asserted.
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

local function stun()  ram[P2 + 0x05] = 2 ; ram[P2 + 0x06] = 0x0A ; ram[P2 + 0x38] = 0 end
local function free()  ram[P2 + 0x05] = 0 ; ram[P2 + 0x06] = 0    ; ram[P2 + 0x38] = 0 end
local function air()   ram[P2 + 0x05] = 0 ; ram[P2 + 0x06] = 0    ; ram[P2 + 0x38] = 1 end

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

-- ---------------------------------------------------------------------------
print("[2] 必殺技 (DPF+LP)、待ち 10 - 押しは最速 (free-1) の 10 Tick 後")
reset("reversal")
local dp = make_input_sequence("DPF", "LP", "", 0)
eq("arm_oneshot", R.arm_oneshot("reversal", dp,
	{ wait = 10, adj = -1, delay = 0, hold_dir = false }), true)
eq("owns reversal", R.owns("reversal"), true)
eq("owns counter (別の行動)", R.owns("counter"), false)
eq("owns sequence (常に)", R.owns("sequence"), true)
stun()
run(6)
eq("硬直中に出た入力", #log, 0)
free()
local F = now
run(20)
local press = first_with("LP")
eq("押しの Tick - 自由になった Tick", press and (press.tick - F), 9)
eq("入力の数 (そのまま)", #log, #dp)
eq("出し終わったら行動はアームに戻る", R.owns("reversal"), false)

-- ---------------------------------------------------------------------------
print("[3] 待ちが入力より短いとき - 動けるようになってから入れる分より早くはならない")
reset("reversal")
local fd = make_input_sequence("forward dash", "none", "", 0)
R.arm_oneshot("reversal", fd, { wait = 1, adj = 0, delay = 0, hold_dir = true })
free()
F = now
run(12)
local lead = 0
for i = 1, #fd - 1 do lead = lead + cost(fd[i]) end
eq("最初の入力は自由になった Tick", log[1] and (log[1].tick - F), 0)
eq("最後のタップ - 自由になった Tick (= lead)", log[#log] and (log[#log].tick - F), lead)

-- ---------------------------------------------------------------------------
print("[4] 地上で動けるまで待つ / 途中でまたガードしたら数え直す")
reset("reversal")
R.arm_oneshot("reversal", dp, { wait = 20, adj = -1, delay = 0, hold_dir = false })
air()
run(10)
eq("空中では出ない", #log, 0)
free()
run(3)
stun()          -- 3 Tick 目でまたガード
run(5)
eq("数えている途中のガードで出ない", #log, 0)
free()
F = now
run(30)
press = first_with("LP")
eq("押しは 2 度目に自由になった Tick から数える", press and (press.tick - F), 19)

print("[4b] 出している途中で cancel (拒否された機会・試合終了) - 残りの入力は出し切って、枠を空ける")
reset("reversal")
R.arm_oneshot("reversal", dp, { wait = 10, adj = -1, delay = 0, hold_dir = false })
free()
run(7)                                  -- 最初の入力 (F+5) が出たところ
eq("途中まで出ている", #log >= 1 and #log < #dp, true)
R.cancel()
run(20)
eq("残りも出た", #log, #dp)
eq("配信枠は空いた", defender.pending_input_sequence, nil)
eq("行動はアームに戻った", R.owns("reversal"), false)

print("[4c] 待っている間の cancel - 何も出ず、行動はアームに戻る")
reset("reversal")
R.arm_oneshot("reversal", dp, { wait = 30, adj = -1, delay = 0, hold_dir = false })
free()
run(3)
R.cancel()
run(40)
eq("出た入力", #log, 0)
eq("行動はアームに戻った", R.owns("reversal"), false)

-- ---------------------------------------------------------------------------
print("[5] 遅らせ (Guard Action Delay) あり - 動作と押しを分ける")
reset("reversal")
local fdhp = make_input_sequence("forward dash", "HP", "", 0)
R.arm_oneshot("reversal", fdhp, { wait = 5, adj = 0, delay = 12, hold_dir = true })
free()
F = now
run(40)
-- 動作側: 最後のタップから HP が外れ、方向は押すまで押しっぱなし。
local taps = {}
for _, l in ipairs(log) do if l.rec.sequence == log[1].rec.sequence then taps[#taps + 1] = l end end
eq("動作の入力数", #taps, #fdhp)
eq("動作の最後に HP が無い", has(taps[#taps].entry, "HP"), false)
eq("動作の最後は 前", show(taps[#taps].entry), "{forward}")
eq("動作の最後の Tick - F (= 待ち 5)", taps[#taps].tick - F, 5)
eq("動作の後は前を押し続ける", show(taps[1].rec.seq_hold), "{forward}")
press = first_with("HP")
eq("押しは 前+HP", press and show(press.entry), "{forward,HP}")
-- 押しは動作の終わり (2 Tick 押す最後のタップの 2 Tick 目) から 12 Tick。
eq("押し - 動作の最後のタップ", press and (press.tick - (taps[#taps].tick + 1)), 12)

-- ---------------------------------------------------------------------------
print("[6] ダッシュキャンセル - 押しは 2 Tick 後ろ、押しにレバーを付けない (逆方向は後から乗る)")
reset("reversal")
local fdc = make_input_sequence("forward dash cancel", "HP", "", 0)
R.arm_oneshot("reversal", fdc, { wait = 5, adj = 0, delay = 0, hold_dir = true, rev = "back" })
free()
F = now
run(40)
taps = {}
for _, l in ipairs(log) do if l.rec.sequence == log[1].rec.sequence then taps[#taps + 1] = l end end
eq("動作の記録に逆方向", taps[1] and taps[1].rec.seq_rev, "back")
eq("動作の後に方向を押し続けない (逆方向が持つ)", taps[1] and taps[1].rec.seq_hold, nil)
press = first_with("HP")
eq("押しは HP だけ", press and show(press.entry), "{HP}")
eq("押し - 動作の最後のタップ (= 0 + 2)", press and (press.tick - (taps[#taps].tick + 1)), 2)

print("[6b] Auto のダッシュ攻撃は、ステップの実測値を使う")
reset("reversal")
ram[CID] = 0x02                       -- Gallon: f = 7, fc = 15 (MEASURED_STEP_FLOORS)
R.arm_oneshot("reversal", fdc, { wait = 5, adj = 0, delay = 6, hold_dir = true,
	rev = "back", auto_dash = "forward dash cancel" })
free()
run(60)
taps = {}
for _, l in ipairs(log) do if l.rec.sequence == log[1].rec.sequence then taps[#taps + 1] = l end end
press = first_with("HP")
eq("押し - 動作の最後のタップ (= fc 15)", press and (press.tick - (taps[#taps].tick + 1)), 15)
ram[CID] = 0

-- ---------------------------------------------------------------------------
print("[7] Button Lever の行")
reset("reversal")
local fwhp = make_input_sequence("forward", "HP", "", 0)
R.arm_oneshot("reversal", fwhp, { wait = 3, adj = 0, delay = 0, hold_dir = true, lever = {} })
free()
run(10)
eq("Neutral は押しの方向を外す", log[1] and show(log[1].entry), "{HP}")
reset("reversal")
R.arm_oneshot("reversal", fwhp, { wait = 3, adj = 0, delay = 0, hold_dir = true, lever = { "down" } })
free()
run(10)
eq("方向を選べばその方向", log[1] and show(log[1].entry), "{down,HP}")
reset("reversal")
R.arm_oneshot("reversal", dp, { wait = 12, adj = -1, delay = 0, hold_dir = false, lever = {} })
free()
run(20)
press = first_with("LP")
eq("必殺技の free-1 押しには掛けない (アームと同じ)", press and show(press.entry), show(dp[#dp]))

-- ---------------------------------------------------------------------------
print("[8] Action Steps - 1 歩目が待ち、残りはその後に普段どおり")
reset("sequence")
ram[CID] = 0x0F                       -- Jedah
training_settings.action_sequences = { reversal = { ["15"] = { version = 1, steps = {
	{ action = "custom", lever = "DPF", button = "LP", wait = 0 },
	{ action = "atk", lever = "none", button = "HK", wait = 6 },
} } } }
training_settings.action_steps_loop = false
eq("arm_deferred", R.arm_deferred("reversal",
	{ wait = 10, adj = -1, delay = 0, hold_dir = false }), true)
eq("積まれた数 (1 歩目 + 2 歩目)", R.pending_count(), 2)
free()
F = now
run(40)
press = first_with("LP")
eq("1 歩目の押し - F", press and (press.tick - F), 9)
local hk = first_with("HK")
eq("2 歩目は 1 歩目の 6 Tick 後 (待ちの数え方は普段どおり)", hk and press and (hk.tick - press.tick), 6)
eq("Wait の表示は 1 歩目の Act から", R.wait_log[1] and R.wait_log[1].index, 1)
eq("Wait の表示に 1 歩目の待ちは載せない (トリガから数えるため)",
	R.wait_log[1] and R.wait_log[1].ticks, nil)

-- ---------------------------------------------------------------------------
print("[9] ループの各周 - Loop Wait の後に、周ごとに新しく抽選して足す")
local function lap_gap(limit)
	reset("sequence")
	training_settings.action_steps_loop = true
	training_settings.action_steps_loop_wait = 10
	training_settings.random_start_wait = limit
	R.arm_deferred("reversal", { wait = 0, adj = -1, delay = 0, hold_dir = false })
	free()
	run(120)
	-- HK (2 歩目) の次の LP (次の周の 1 歩目) までの間。
	local hk1, lp2
	for _, l in ipairs(log) do
		if hk1 == nil and has(l.entry, "HK") then hk1 = l
		elseif hk1 ~= nil and lp2 == nil and has(l.entry, "LP") then lp2 = l end
	end
	return hk1 and lp2 and (lp2.tick - hk1.tick)
end
local real_random = math.random
math.random = function(a, b) return b end          -- いつも上限を引く
local base = lap_gap(0)
local with = lap_gap(25)
math.random = real_random
eq("0 のときは今までどおり (差 0)", base ~= nil, true)
eq("25 を引いた周は 25 Tick 遅れる", with and base and (with - base), 25)
training_settings.random_start_wait = 0
training_settings.action_steps_loop = false
eq("Loop の表示に待ちが含まれる", (function()
	for _, e in ipairs(R.wait_log) do if e.mode == "Loop" then return e.ticks ~= nil end end
	return false
end)(), true)
ram[CID] = 0

-- ---------------------------------------------------------------------------
print("[10] guardCancel の GA.rsw_defer")
local gsrc = slurp("guardCancel.lua")
local s1 = gsrc:find("function GA.rsw_draw()", 1, true)
local s2 = gsrc:find("function GA.rsw_defer()", 1, true)
local e2 = s2 and gsrc:find("\nend", s2, true)
assert(s1 and s2 and e2, "GA.rsw_draw / GA.rsw_defer が guardCancel.lua に見つからない")
GA = {}
DASH_CANCEL_REVERSE = { ["forward dash cancel"] = "back", ["back dash cancel"] = "forward" }
BUTTON_LEVER_DIR = { [5] = { "forward" } }
local special = true
function kd_press_base() return special and 0 or 1 end
function kd_delay_ticks() return 0 end
function kd_holds_direction() return not special end
debugKnockdownModule = { mark_write = function() end }
actionSequenceRunnerModule = R
local stick, button = "DPF", "LP"
function GA.stick() return stick end
function GA.button() return button end
assert(loadstring(gsrc:sub(s1, e2 + 4)))()

reset("reversal")
globals.options = { counter_attack_lever = 1, gc_delay = 0 }
training_settings.random_start_wait = 0
eq("0 のときは渡さない (アームがそのまま動く)", GA.rsw_defer(), false)
eq("0 のときは runner に何も積まない", R.owns("reversal"), false)
training_settings.random_start_wait = 30
math.random = function(a, b) return 17 end
eq("1 以上なら runner に渡す", GA.rsw_defer(), true)
math.random = real_random
eq("Specified は oneshot として持つ", R.owns("reversal"), true)
free()
F = now
run(40)
press = first_with("LP")
eq("必殺技の押し = F - 1 + 17", press and (press.tick - F), 16)

reset("counter")
stick, button, special = "forward dash cancel", "HP", false
globals.options = { counter_attack_lever = 5, gc_delay = 0 }
math.random = function(a, b) return 8 end
eq("カウンタも渡す", GA.rsw_defer(), true)
math.random = real_random
eq("owns counter", R.owns("counter"), true)
free()
run(40)
press = first_with("HP")
-- Lever の行が逆方向より優先 (アームの _ov と同じ)。
eq("Button Lever = Forward が押しに乗る", press and show(press.entry), "{forward,HP}")
training_settings.random_start_wait = 0

-- ---------------------------------------------------------------------------
print("[11] macro.lua - 再生の開始を Tick で待つ")
local msrc = slurp("macro.lua")
local ms = msrc:find("local function start_wait_tick", 1, true)
local me = ms and msrc:find("\nend", ms, true)
assert(ms and me, "start_wait_tick が macro.lua に見つからない")
local tick_fn = assert(loadstring(msrc:sub(ms, me + 4) .. "\nreturn start_wait_tick"))()
local sw = { left = 5, last = 250 }
eq("1 Tick", tick_fn(sw, 251), false)
eq("2 Tick 進んだフレーム (Turbo)", tick_fn(sw, 253), false)
eq("周回をまたぐ", tick_fn(sw, 255), true)
sw = { left = 5, last = 10 }
eq("ステートロードの飛びは数えない", tick_fn(sw, 200), false)
eq("残りはそのまま", sw.left, 5)
eq("止まったまま", tick_fn(sw, 200), false)

local function body_of(src, head)
	local s = src:find(head, 1, true)
	if s == nil then return "" end
	local e = src:find("\nend", s, true)
	return src:sub(s, e)
end
local pc = body_of(msrc, "local function playcontrol(silent)")
local w_at = pc:find("rsw_roll()", 1, true)
local d_at = pc:find("dostate(frame)", 1, true)
eq("playcontrol は再生前に抽選する", w_at ~= nil and d_at ~= nil and w_at < d_at, true)
eq("待っている間に呼ばれたら止める", pc:find("if start_wait ~= nil then", 1, true) ~= nil, true)
local tmp = body_of(msrc, "function play_temporary_recording()")
eq("ウィザードの確認再生は待たない", tmp:find("rsw_roll", 1, true), nil)
eq("stop_macro_playback が待ちも捨てる",
	body_of(msrc, "function stop_macro_playback()"):find("start_wait = nil", 1, true) ~= nil, true)
local cd = msrc:find("start_wait_tick(start_wait,", 1, true)
local pb = msrc:find("if playing and loop_menu_hold_active() then", 1, true)
eq("カウントダウンは再生ブロックの前 (同じコールバックで 1 フレーム目)",
	cd ~= nil and pb ~= nil and cd < pb, true)

-- ---------------------------------------------------------------------------
print("[12] 配線")
local function count(src, pat)
	local n, at = 0, 1
	while true do
		local f = src:find(pat, at, true)
		if f == nil then return n end
		n = n + 1
		at = f + 1
	end
end
eq("記録のガード行動 3 つが starting を見る",
	count(gsrc, "if not globals.macroLua.playing and not globals.macroLua.starting then"), 3)
eq("Character Specific は 2 つとも依頼時に抽選", count(gsrc, "GA.csp_wait = GA.rsw_draw()"), 2)
eq("アームの前で rsw_defer", gsrc:find("and GA.rsw_defer() then", 1, true) ~= nil, true)
eq("tick walker の門は owns", gsrc:find("or not actionSequenceRunnerModule.owns(globals.dummy.guard_action) then\n\t\t\t\tbreak", 1, true) ~= nil, true)
eq("guard_action ~= 'sequence' の門が残っていない",
	count(gsrc, "guard_action ~= 'sequence'"), 0)
local menu = slurp("menu.lua")
-- Dummy's is indented under Guard Action Type: indent(1, ..._item),
eq("行は 2 つ (Dummy と Recording)",
	count(menu, "random_start_wait_item,") + count(menu, "random_start_wait_item),"), 2)
eq("上限 60", menu:find('"random_start_wait", 0, 60,', 1, true) ~= nil, true)
local cfg = slurp("config.lua")
eq("既定は 0 (オフ)", cfg:find("random_start_wait = 0,", 1, true) ~= nil, true)
-- Looked up mid-run with pcall(require, ...) in three files. The master has to
-- load it at start-up, as it does gcStats, or a look-up that fails mid-run
-- reads as 0 everywhere and nothing ever waits.
local master = slurp("vsav_training_master_script.lua")
eq("master が起動時に読み込む",
	master:find('= require "./scripts/randomStartWait"', 1, true) ~= nil, true)
eq("コンソールに引いた値を出す",
	msrc:find('" after a Random Start Wait of "', 1, true) ~= nil, true)
local ctl = slurp("controller.lua")
eq("再生ホットキーは待ち中も止める",
	ctl:find("if globals.macroLua.playing or globals.macroLua.starting then", 1, true) ~= nil, true)

print(fails == 0 and "\n全て通った" or ("\n" .. fails .. " 件 NG"))
os.exit(fails == 0 and 0 or 1)
