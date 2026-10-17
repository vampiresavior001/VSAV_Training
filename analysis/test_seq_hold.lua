-- HOLD: THE DIRECTION STAYS DOWN AFTER THE ATTACK.
--
-- A charge move is a direction held and then let go. A step's input otherwise
-- exists for the one tick it is written - the walker frees the delivery slot
-- and nothing writes 0xFF8B94 again until the next step - so nothing charges.
--
-- The Hold row on an attack marks the step, the compiler turns it into the
-- LEVER of the last entry with the buttons stripped, and the walker keeps
-- asserting that until the next step takes over.
--
-- This drives the real compiler and a stand-in for the walker built to the same
-- rules, recording what lands on the input word each tick.
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_seq_hold.lua
local ram = {}
memory = {
	readbyte  = function(a) return ram[a] or 0 end,
	readdword = function(a) return ram[a] or 0 end,
}
gui = { text = function() end, box = function() end }
emu = { framecount = function() return 1 end }
globals = { dummy = { guard_action = "sequence" }, options = {} }
training_settings = { action_sequences = {} }
function mark_training_settings_dirty() end
function dash_attack_ticks_for() return nil end
-- キャンセル方向の地図 (guardCancel が公開する seq_dash_cancel_reverse の代役)。
seq_dash_cancel_reverse = { ["forward dash cancel"] = "back", ["back dash cancel"] = "forward" }

local csrc = io.open("controller.lua"):read("*a")
local cs = csrc:find("function make_input_sequence", 1, true)
local ce = csrc:find("\nend", csrc:find("return _sequence", cs, true), true)
assert(cs and ce, "make_input_sequence が controller.lua に見つからない")
assert(loadstring(csrc:sub(cs, ce + 4)))()

-- The record queue_input_sequence builds, reduced to what the walker uses.
local queued = nil
function queue_input_sequence(_d, _seq)
	queued = { sequence = _seq, current_frame = 1 }
	_d.pending_input_sequence = queued
end

local R = dofile("actionSequenceRunner.lua")

local fails = 0
local function fail(what, got, want)
	fails = fails + 1
	print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(want) .. "]")
end

-- Names to bits, the same mapping entry_to_bits uses (facing 0 = forward is
-- 0x02). Buttons are only distinguished from zero here.
local BITS = { forward = 0x02, back = 0x01, down = 0x04, up = 0x08 }
local function to_bits(entry)
	local lev, btn = 0, 0
	for _, k in ipairs(entry or {}) do
		if BITS[k] then lev = lev + BITS[k] else btn = 1 end
	end
	return lev, btn
end
local function lev_name(lev)
	if lev == 0 then return "-" end
	local out = {}
	for _, k in ipairs({ "up", "down", "back", "forward" }) do
		if lev % (BITS[k] * 2) >= BITS[k] then out[#out + 1] = k end
	end
	return table.concat(out, "+")
end

local P2 = 0xFF8800
local function set_free() ram[P2 + 0x05] = 0 ; ram[P2 + 0x06] = 0 ; ram[P2 + 0x38] = 0 end
local function set_stun() ram[P2 + 0x05] = 2 ; ram[P2 + 0x06] = 0x0A ; ram[P2 + 0x38] = 0 end

-- THE WALKER, TO THE SAME RULES AS guardCancel's seq_tick BLOCK.
--
-- Two passes so one tick can end a segment and start the next; the v158 hold
-- (buttonless entries take two ticks); the hold picked up when a segment runs
-- off its end; and dropped once the schedule is empty.
local held_lever = nil
local reentered = false
local defender = {}
local log = {}
local function tick()
	local wrote = nil
	for _pass = 1, 2 do
		R.service(defender)
		local s = defender.pending_input_sequence
		if s == nil or s.sequence == nil then break end
		held_lever = nil
		local i = s.current_frame or 1
		-- 窓が切れたら、凍結明けに頭から入れ直す (実装と同じ規則)
		if s.restart_pending then
			if (ram[P2 + 0x5C] or 0) ~= 0 then
				wrote = { lev = 0, btn = 0, src = "wait" }
				break
			end
			s.restart_pending = nil
			s.current_frame = 1 ; s.tick_held = 0 ; s.entry_ticks = 0
			i = 1
			reentered = true
		end
		if i <= #s.sequence then
			local lev, btn = to_bits(s.sequence[i])
			s.entry_ticks = (s.entry_ticks or 0) + 1
			if (lev ~= 0 or btn ~= 0) and (ram[P2 + 0x5C] or 0) ~= 0
			   and not s.seq_through_freeze
			   and s.entry_ticks > (R.DASH_GRACE_TICKS or 10) then
				s.restart_pending = true
				wrote = { lev = 0, btn = 0, src = "wait" }
				break
			end
			wrote = { lev = lev, btn = btn,
			          src = (reentered and "reenter" or "step") }
			reentered = false
			local hold = (btn == 0 and lev ~= 0) and 2 or 1
			-- 凍結中のティックはゲームが処理しないので数えない。
			-- 何かを押しているエントリだけ。ニュートラルは登録される押しが無いので
			-- 待っても得が無く、猶予だけ食う。
			-- 必殺技の歩 (seq_through_freeze) は例外で、凍結中も数える。
			if (lev ~= 0 or btn ~= 0) and (ram[P2 + 0x5C] or 0) ~= 0
			   and not s.seq_through_freeze then
				-- 出してはいるが、ゲームは見ていない
			else
				s.tick_held = (s.tick_held or 0) + 1
			end
			if s.tick_held >= hold then
				s.current_frame = i + 1
				s.tick_held = 0
				s.entry_ticks = 0
			end
			break
		end
		held_lever = s.seq_hold
		defender.pending_input_sequence = nil
	end
	if wrote == nil and held_lever ~= nil then
		if R.pending_count() == 0 then
			held_lever = nil
		else
			local lev = to_bits(held_lever)
			wrote = { lev = lev, btn = 0, src = "hold" }
		end
	end
	log[#log + 1] = wrote or { lev = 0, btn = 0, src = "none" }
	return log[#log]
end
local function run(n) for _ = 1, n do tick() end end
local function trace()
	local out = {}
	for _, e in ipairs(log) do
		out[#out + 1] = e.src .. ":" .. lev_name(e.lev) .. (e.btn ~= 0 and "+B" or "")
	end
	return table.concat(out, " ")
end

local function install(steps)
	ram[0xFF8B82] = 0x08                       -- Bishamon
	training_settings.action_sequences = { reversal = { ["8"] = { version = 1, steps = steps } } }
end
local function start()
	log = {} ; held_lever = nil ; queued = nil
	defender = {}
	R.cancel()
	R.arm("reversal")                          -- 1 歩目は呼び出し側が出す
end

print("[1] Hold なし - ステップを出したら方向は離れる")
install({
	{ action = "atk", lever = "none",      button = "LP", wait = 0 },
	{ action = "atk", lever = "down-back", button = "LP", wait = -1 },
})
start()
set_free()
run(6)
do
	local held = 0
	for _, e in ipairs(log) do if e.src == "hold" then held = held + 1 end end
	if held ~= 0 then fail("保持したティック数", held, 0)
	else print("  ok 保持は 0 ティック   " .. trace()) end
end

print("[2] Hold あり - 次のステップまで方向が残り、ボタンは落ちる")
install({
	{ action = "atk", lever = "none",      button = "LP", wait = 0 },
	{ action = "atk", lever = "down-back", button = "LP", hold = true, wait = -1 },
	{ action = "atk", lever = "forward",   button = "HP", wait = -1 },
})
start()
set_free()
run(1)          -- 2 歩目を出させる
-- ここで硬直に入れる。自由なままだと 3 歩目が使い切りと同じティックで
-- キューされてしまい、保持が始まる前に上書きされる。
set_stun()
run(12)
do
	local held, btn_leak = 0, 0
	for _, e in ipairs(log) do
		if e.src == "hold" then
			held = held + 1
			if e.lev ~= (0x04 + 0x01) then fail("保持しているレバー", lev_name(e.lev), "down+back") end
			if e.btn ~= 0 then btn_leak = btn_leak + 1 end
		end
	end
	if held < 10 then fail("硬直中に保持したティック数", held, ">= 10") end
	if btn_leak ~= 0 then fail("保持にボタンが混ざったティック数", btn_leak, 0) end
	if fails == 0 then
		print(string.format("  ok 硬直 12 ティックのうち %d ティック down+back を保持、ボタンは 0", held))
	end
end

print("[3] 硬直が明けたら次のステップが上書きする")
set_free()
local before = #log
run(6)
do
	local switched = false
	for i = before + 1, #log do
		if log[i].src == "step" then switched = true break end
	end
	if not switched then fail("3 歩目が出たか", "出ていない", "出る")
	else print("  ok 保持 → 3 歩目へ切り替わった") end
end

print("[4] 最後のステップのあとは何も残さない")
do
	run(8)
	local tail_hold = 0
	for i = #log - 5, #log do
		if log[i] and log[i].src == "hold" then tail_hold = tail_hold + 1 end
	end
	if tail_hold ~= 0 then fail("シーケンス終了後に保持していたティック数", tail_hold, 0)
	else print("  ok ダミーは方向にもたれたままにならない") end
end

print("[5] 保持していても、次が裸の方向なら先頭ニュートラルで一度離す")
-- opens_with_direction が入れるニュートラルは、押しっぱなしの方向に押しエッジが
-- 立たない問題への対処。Hold と噛み合っていないと歩き出しやダッシュが死ぬ。
install({
	{ action = "atk",    lever = "none",      button = "LP", wait = 0 },
	{ action = "atk",    lever = "down-back", button = "LP", hold = true, wait = -1 },
	{ action = "dash.f", wait = -1 },
})
local sched = R.compile(training_settings.action_sequences.reversal["8"])
do
	local third = sched[3].sequence
	local first_is_neutral = (#third[1] == 0)
	if not first_is_neutral then
		local names = {}
		for _, k in ipairs(third[1]) do names[#names + 1] = k end
		fail("ダッシュの先頭エントリ", table.concat(names, "+"), "ニュートラル")
	else
		print("  ok ダッシュは先頭ニュートラルから始まる(保持が解ける)")
	end
end

print("[6] Hold は最後のエントリの方向だけを取る")
do
	local one = R.compile({ version = 1, steps = {
		{ action = "atk", lever = "none",         button = "LP", wait = 0 },
		{ action = "atk", lever = "down-forward", button = "HK", hold = true, wait = -1 },
	} })
	local h = one[2].hold
	local names = {}
	for _, k in ipairs(h or {}) do names[#names + 1] = k end
	table.sort(names)
	local got = table.concat(names, "+")
	if got ~= "down+forward" then fail("hold の中身", got, "down+forward")
	else print("  ok hold = down+forward   ボタン HK は入っていない") end
end

print("[6b] 1 歩目の Hold も効くこと - 20 ティック歩いて投げ")
-- 1 歩目はアームが出すので、runner のキュー地点(seq_hold を付ける場所)を
-- 通らない。取りこぼすと歩かないまま投げに行って、届かず何も出ない。
install({
	{ action = "walk.f", hold = true,  wait = 0 },
	{ action = "atk", lever = "forward", button = "HK", hold = true, wait = 20 },
})
do
	local sched = R.compile(training_settings.action_sequences.reversal["8"])
	local h = sched[1].hold
	local names = {}
	for _, k in ipairs(h or {}) do names[#names + 1] = k end
	if table.concat(names, "+") ~= "forward" then
		fail("1 歩目の hold", table.concat(names, "+"), "forward")
	end
	-- アームは 1 歩目の入力リストしか返さないので、hold は別に預けられる。
	R.cancel()
	R.arm("reversal")
	local taken = R.take_arm_hold()
	local tn = {}
	for _, k in ipairs(taken or {}) do tn[#tn + 1] = k end
	if table.concat(tn, "+") ~= "forward" then
		fail("預けた 1 歩目の hold", table.concat(tn, "+"), "forward")
	end
	-- 一度きり。ウォーカーは毎ティック聞きに来るので、2 回返すと
	-- 2 歩目の保持を上書きしてしまう。
	if R.take_arm_hold() ~= nil then fail("2 回目", "値が返った", "nil") end
	-- cancel で捨てられること。
	R.cancel()
	R.arm("reversal")
	R.cancel()
	if R.take_arm_hold() ~= nil then fail("cancel 後", "値が残っている", "nil") end
	if fails == 0 then print("  ok 1 歩目の hold は預けられ、一度だけ取り出せ、cancel で消える") end
end

print("[7] Hold を付けていないステップの hold は nil")
do
	local two = R.compile({ version = 1, steps = {
		{ action = "atk", lever = "none",      button = "LP", wait = 0 },
		{ action = "atk", lever = "down-back", button = "LP", wait = -1 },
	} })
	if two[2].hold ~= nil then fail("hold", tostring(two[2].hold), "nil")
	else print("  ok nil") end
end

print("[8] ダッシュキャンセルの rev - タップの 2 ティック後から保持し、合流で消える")
do
	-- 状態機械を直接叩く。park はセグメント終端 (= 最後のタップ) で呼ばれ、
	-- 保持はその 2 ティック後から始まる (v207: 先に置くとダッシュが消える)。
	-- 256 の半周期を過ぎると黙る - 保持が 2 秒も続くことはなく、いつかは
	-- 合流か cancel で終わるというこの機構の性質の 保険。
	R.cancel()
	R.park_rev("back", 100)
	if R.rev_lever_now(100) ~= nil then fail("park したティック", "既に立った", "nil") end
	if R.rev_lever_now(101) ~= nil then fail("1 ティック後", "既に立った", "nil") end
	if R.rev_lever_now(102) ~= "back" then fail("2 ティック後", tostring(R.rev_lever_now(102)), "back") end
	if R.rev_lever_now(150) ~= "back" then fail("48 ティック後も", tostring(R.rev_lever_now(150)), "back") end
	if R.rev_lever_now(230) ~= nil then fail("半周期を超えたら", "立った", "nil") end
	-- 合流で消える。ウォーカーはエントリを書いた後に rev_clear を呼ぶ。
	R.rev_clear()
	if R.rev_lever_now(102) ~= nil then fail("clear 後", "残っている", "nil") end
	if fails == 0 then print("  ok park → 2 ティック後に立ち、clear で消える") end
end

print("[8b] 1 歩目が cancel ステップ - arm が rev を預け、キャンセルで消える")
do
	install({
		{ action = "dashc.f", wait = -1 },
		{ action = "atk", lever = "none", button = "HP", wait = -1 },
	})
	local sched = R.compile(training_settings.action_sequences.reversal["8"])
	if sched[1].rev ~= "back" then fail("compile の rev", tostring(sched[1].rev), "back") end
	if sched[1].hold ~= nil then fail("compile の hold", tostring(sched[1].hold), "nil") end
	R.cancel()
	R.arm("reversal")
	-- hold は握りつぶされているので、take_arm_hold は何も返さない。
	if R.take_arm_hold() ~= nil then fail("cancel ステップの hold", "値が返った", "nil") end
	-- 記録が終わる前は立たない。_due は一度だけ返り、park する。
	if R.rev_lever_now(50) ~= nil then fail("記録が終わる前", "立った", "nil") end
	if R.arm_rev_due(50) ~= "back" then fail("arm_rev_due", tostring(R.arm_rev_due(50)), "back") end
	if R.rev_lever_now(51) ~= nil then fail("park 直後", "立った", "nil") end
	if R.rev_lever_now(52) ~= "back" then fail("2 ティック後", tostring(R.rev_lever_now(52)), "back") end
	R.cancel()
	if R.rev_lever_now(52) ~= nil then fail("cancel 後", "残っている", "nil") end
	if fails == 0 then print("  ok 1 歩目の rev は預けられ、一度だけ受け取り、cancel で消える") end
end

print("[8c] メニューで終わった run は、ダッシュキャンセルの後ろも 1 歩目の hold も残さない。始まっていない run には触らない (v11.7.28.2 / .4)")
do
	-- 本人 2026-10-17: ダッシュキャンセルの直後にメニューを開くと、閉じた後に
	-- 後ろへ歩き続けた。drop_for_menu が rev / arm_rev を残していたため。
	-- A segment of the run (seq_tick) in the slot: the run is in progress.
	local defender = { pending_input_sequence = { sequence = { { "back" } }, seq_tick = true } }
	local before = fails
	install({
		{ action = "dashc.f", wait = -1 },
		{ action = "atk", lever = "none", button = "HP", wait = -1 },
	})
	R.cancel()
	R.arm("reversal")
	R.park_rev("back", 100)
	globals.show_menu = true
	R.menu_open(defender)
	globals.show_menu = false
	if R.rev_lever_now(150) ~= nil then fail("2 歩目以降の rev", tostring(R.rev_lever_now(150)), "nil") end
	if R.arm_rev_due(150) ~= nil then fail("1 歩目の arm_rev", "残っている", "nil") end
	if R.rev_lever_now(155) ~= nil then fail("arm_rev から park されたもの", "立った", "nil") end
	if defender.pending_input_sequence ~= nil then fail("送っている途中の入力", "残っている", "nil") end
	-- 1 歩目の Hold も。
	install({
		{ action = "atk", lever = "forward", hold = true, button = "LP", wait = 0 },
		{ action = "atk", lever = "none", button = "HP", wait = -1 },
	})
	R.cancel()
	R.arm("reversal")
	defender.pending_input_sequence = { sequence = { { "back" } }, seq_tick = true }
	globals.show_menu = true
	R.menu_open(defender)
	globals.show_menu = false
	if R.take_arm_hold() ~= nil then fail("1 歩目の hold", "残っている", "nil") end
	-- STEP ONE STILL WITH THE ARM (v11.7.28.4): its record in the slot, not a
	-- segment. The run has not begun, so the menu leaves all of it - it comes
	-- out on close (user, 2026-10-17: "ダウン中にメニューをおしても次の技はでたほうがいい").
	install({
		{ action = "dashc.f", wait = -1 },
		{ action = "atk", lever = "none", button = "HP", wait = -1 },
	})
	R.cancel()
	R.arm("reversal")
	local waiting = { sequence = { { "forward" }, {}, { "forward" } }, kd_tick = true }
	defender.pending_input_sequence = waiting
	local n_before = R.pending_count()
	globals.show_menu = true
	R.menu_open(defender)
	globals.show_menu = false
	if defender.pending_input_sequence ~= waiting then fail("待っている 1 歩目の記録", "消えた", "残る") end
	if R.pending_count() ~= n_before or n_before == 0 then fail("待っている run の 2 歩目以降", tostring(R.pending_count()), tostring(n_before)) end
	if R.arm_rev_due(60) ~= "back" then fail("待っている 1 歩目の arm_rev", "消えた", "back") end
	-- メニューを閉じているときは何も消さない。
	R.cancel()
	R.park_rev("back", 100)
	R.menu_open(defender)
	if R.rev_lever_now(102) ~= "back" then fail("閉じているとき", tostring(R.rev_lever_now(102)), "back") end
	R.cancel()
	if fails == before then print("  ok rev・arm_rev・1 歩目の hold はメニューで消え、待っている 1 歩目と閉じているときは触らない") end
end

print("[9] 凍結中のティックは配送に数えない")
-- ボタンを伴わない入力は 2 ティック必要 (v158)。ところがヒットストップ中の押しは
-- ゲームが捨てる ($126 は 1 ティックの押しエッジ)。凍結中のティックも数えていた
-- ため、ゲームが一度も見ていない入力を「出した」ことにして次へ進んでいた。
--
-- 実機トレース 2026-09-19、ジェダ 10 回。成功した 5 回は凍結ティックゼロ、
-- 失敗した 5 回はちょうど 1 つ、いずれも 1 回目の前入力の 2 ティック目。
-- そのタップが成立せず、2 回目の前だけが入ってダッシュにならなかった
-- ($06 は 5 回とも 0x14 に届かない)。
do
	local function dash_ticks(freeze_at)
		install({
			{ action = "atk",    lever = "none", button = "LP", wait = 0 },
			{ action = "dash.f", wait = -1 },
		})
		start()
		set_free()
		local n = 0
		for i = 1, 20 do
			ram[P2 + 0x5C] = (i == freeze_at) and 5 or 0
			local e = tick()
			if e.src == "step" then n = n + 1 end
		end
		ram[P2 + 0x5C] = 0
		return n
	end
	local plain = dash_ticks(nil)
	-- 方向を出しているティックで凍らせる。ニュートラルで凍らせても
	-- 伸びないのが正しい挙動なので、試したことにならない。
	local dir_at = nil
	for k, e in ipairs(log) do
		if e.src == "step" and e.lev ~= 0 then dir_at = k break end
	end
	if dir_at == nil then fail("方向を出すティックが見つからない", "nil", "数値") end
	local frozen = dash_ticks(dir_at)
	if plain < 5 then fail("凍結なしの配送ティック", plain, ">= 5") end
	-- 凍った 1 ティックは数に入らないので、その分だけ出し続ける。
	if frozen ~= plain + 1 then fail("凍結 1 ティック分だけ伸びる", frozen, plain + 1) end
	-- 上は代役の歩進を見ている。実装そのものは読んで固定する。
	-- (これが無いと、実装から条件を外しても上は通ってしまう)
	local gsrc = io.open("guardCancel.lua"):read("*a")
	-- 必殺技は例外 (本人、2026-10-11: 必殺技はヒットストップ中の入力を受け付け、
	-- ダッシュは受け付けない)。凍結中のティックも配送に数える (seq_through_freeze)。
	-- ダッシュと通常技はこれまでどおり数えない。
	local g = gsrc:find("and memory.readbyte(0xFF885C) ~= 0\n\t\t\t\t   and not _s0.seq_through_freeze then", 1, true)
	local i = g and gsrc:find("_s0.tick_held = (_s0.tick_held or 0) + 1", g, true)
	if g == nil or i == nil or (i - g) > 1200 then
		fail("実装が凍結中のティックを数えない", "守られていない", "$5C の分岐の内側")
	end
	-- 例外の範囲は runner の through_freeze が決める。歩の種類ごとに確かめる。
	local keep_lookup = seq_special_command
	seq_special_command = function(name)
		local t = { ["Tenraiha"] = { type = "sequence" }, ["Shadow Blade"] = { type = "motion" },
		            ["Mash"] = { type = "repeat" }, ["Dedicated"] = { type = "dedicated" } }
		return t[name]
	end
	local cases = {
		{ "順押しの必殺技 (sequence)", { action = "sp.Tenraiha" }, true },
		{ "方向入力の必殺技 (motion)", { action = "sp.Shadow Blade" }, true },
		{ "連打の必殺技 (repeat) はこれまでどおり", { action = "sp.Mash" }, false },
		{ "dedicated はこれまでどおり", { action = "sp.Dedicated" }, false },
		{ "Custom の QCF", { action = "custom", lever = "QCF", button = "LP" }, true },
		{ "Custom の溜め (HCharge)", { action = "custom", lever = "HCharge", button = "LP" }, true },
		{ "Custom の前+中K (通常技)", { action = "custom", lever = "forward", button = "MK" }, false },
		{ "Custom のニュートラル+強P", { action = "custom", lever = "none", button = "HP" }, false },
		{ "Attack (通常技)", { action = "atk", lever = "down", button = "MK" }, false },
		{ "Dash", { action = "dash", lever = "forward" }, false },
	}
	for _, c in ipairs(cases) do
		local got = R.through_freeze(c[2]) == true
		if got ~= c[3] then fail("ヒットストップを跨ぐか: " .. c[1], tostring(got), tostring(c[3])) end
	end
	seq_special_command = keep_lookup
	if gsrc:find("if (_pl ~= 0 or _pb ~= 0)", 1, true) == nil then
		fail("ニュートラルは待たない", "限定が無い", "_pl/_pb のどちらかが非ゼロのときだけ")
	end
	if fails == 0 then print("  ok 凍った 1 ティックは配送に数えず、その分だけ出し続ける") end
end

print("[9b] 必殺技の歩は凍結中も配送に数え、入れ直さない (本物の runner を通す)")
-- 実機 2026-10-11 (reversal_logs_archive/v11.7.25、51 回): 中足払い Cancel 天雷破で、
-- 弱K の後はヒットストップの間ずっと進まず、明けてから入れ直して 6 Tick 後に出た。
-- 例外を入れたのに効いていなかった。runner が例外を「コンパイル済みの記録」に
-- 尋ねていて、記録には action も lever も無いので常に偽だった。上の [9] は
-- エディタの歩を直接渡していたので通っていた。ここは R.service が積んだ記録を見る。
do
	local keep_lookup = seq_special_command
	seq_special_command = function(name)
		if name == "Tenraiha" then
			return { type = "sequence", sequence = { { "LK" }, { "HK" }, { "MP" }, {}, { "MP" }, { "up" } } }
		end
		return nil
	end
	local sched = R.compile({ version = 1, steps = {
		{ action = "atk", lever = "none", button = "LP", wait = 0 },
		{ action = "sp.Tenraiha", wait = -1 },
		{ action = "custom", lever = "QCF", button = "LP", wait = -1 },
		{ action = "atk", lever = "down", button = "MK", wait = -1 },
		{ action = "dash.f", wait = -1 },
	} })
	local want = { false, true, true, false, false }
	for k = 1, #want do
		local got = sched ~= nil and sched[k] ~= nil and sched[k].through_freeze == true
		if got ~= want[k] then fail("compile の through_freeze (" .. k .. " 歩目)", tostring(got), tostring(want[k])) end
	end
	-- 2 歩目の天雷破。1 エントリ目を出した次のティックから凍らせる
	-- (Cancel では弱K が当たったティックに出て、残りがヒットストップに入る)。
	local function walk(freeze)
		install({
			{ action = "atk", lever = "none", button = "LP", wait = 0 },
			{ action = "sp.Tenraiha", wait = -1 },
		})
		start()
		set_free()
		local sent, other = 0, 0
		for _ = 1, 30 do
			ram[P2 + 0x5C] = (freeze and queued ~= nil) and 11 or 0
			local e = tick()
			if e.src == "step" then sent = sent + 1
			elseif e.src == "wait" or e.src == "reenter" then other = other + 1 end
		end
		ram[P2 + 0x5C] = 0
		return sent, other
	end
	local plain = walk(false)
	local tagged = queued ~= nil and queued.seq_through_freeze == true
	if not tagged then fail("runner が積んだ記録の seq_through_freeze", tostring(queued and queued.seq_through_freeze), "true") end
	local frozen, other = walk(true)
	if plain < 6 then fail("凍結なしで出したティック", plain, ">= 6") end
	if frozen ~= plain then fail("凍結中も同じティック数で出し切る", frozen, plain) end
	if other ~= 0 then fail("待ち・入れ直しのティック", other, 0) end
	seq_special_command = keep_lookup
	if fails == 0 then
		print(string.format("  ok 天雷破は凍結中も %d ティックで出し切り、入れ直さない", frozen))
	end
end

print("[10] 窓が切れるほど長い凍結なら、待たずに頭から入れ直す")
-- 凍結中のティックを数えないのは、短い凍結を跨ぐため。長い凍結は救えない。
--
-- 実機トレース 2026-09-19:
--   ジェダ      凍結 3   前入力を 5 ティック保持  → ダッシュ出る
--   サスカッチ  凍結 11  前入力を 13 ティック保持 → 出ない
-- ダッシュの 1 回目のレバー方向は 10 フレームしか継続できない (資料)。
-- 超えた先は死んだモーションに餌をやっているだけなので、凍結が明けてから
-- 窓ごと作り直す。
do
	local function run_with_freeze(freeze_len)
		install({
			{ action = "atk",    lever = "none", button = "LP", wait = 0 },
			{ action = "dash.f", wait = -1 },
		})
		start()
		set_free()
		local dir_at, reenter = nil, 0
		for i = 1, 40 do
			local hs = 0
			if dir_at ~= nil and i > dir_at and i <= dir_at + freeze_len then hs = 1 end
			ram[P2 + 0x5C] = hs
			local e = tick()
			if e.src == "step" and e.lev ~= 0 and dir_at == nil then dir_at = i end
			if e.src == "reenter" then reenter = reenter + 1 end
		end
		ram[P2 + 0x5C] = 0
		return reenter
	end
	-- 短い凍結は跨げるので入れ直さない。
	if run_with_freeze(2) ~= 0 then fail("短い凍結で入れ直した", "した", "しない") end
	-- 猶予を超える凍結は入れ直す。
	if run_with_freeze(20) == 0 then fail("長い凍結で入れ直さない", "しない", "する") end
	-- 実装そのものを固定する (上は代役の歩進を見ているため)。
	local gsrc = io.open("guardCancel.lua"):read("*a")
	if gsrc:find("_s0.restart_pending = true", 1, true) == nil then
		fail("窓切れの印", "無い", "restart_pending")
	end
	if gsrc:find("> (actionSequenceRunnerModule.DASH_GRACE_TICKS or 10) then", 1, true) == nil then
		fail("判定に使う猶予", "資料値でない", "DASH_GRACE_TICKS")
	end
	if gsrc:find("if memory.readbyte(0xFF885C) ~= 0 then return end", 1, true) == nil then
		fail("凍結が明けてから入れ直す", "明ける前に入れ直す", "$5C が 0 になるまで待つ")
	end
	if fails == 0 then print("  ok 短い凍結は跨ぎ、長い凍結は凍結明けに入れ直す") end
end

print("")
print("[12] メニューが開いているあいだは 1 ビットも書かない")
-- 2026-09-20 報告: メニュー中もダミーの入力だけが届き続ける。ダミー自身は
-- 止まっているので、入力を書いているのは注入側。28 箇所ある assert_input_bits
-- のうちメニューを見ていたのは Hold の 2 箇所だけで、アームの配送経路には
-- ゲートが無かった。Action Patterns より前からある穴 (0xB でも再現)。
do
	local gsrc = io.open("guardCancel.lua"):read("*a")
	local a = gsrc:find("local function assert_input_bits", 1, true)
	local b = gsrc:find("inject_guard = true", a or 1, true)
	local before = fails
	if a == nil then fail("assert_input_bits", "無い", "ある") end
	local head = (a ~= nil and b ~= nil) and gsrc:sub(a, b) or ""
	-- 書き込みの手前で返すこと。
	if head:find("globals.show_menu == true then return end", 1, true) == nil then
		fail("メニューのゲート", "無い", "書き込みの前にある")
	end
	-- フックの入口ではないこと。そこで返すと M.service が呼ばれず、
	-- 「メニューは走行を終了させる」処理まで止まる。
	local hook = gsrc:find("This hook fires once per TICK, at 0x014E7A", 1, true)
	local svc = gsrc:find("actionSequenceRunnerModule.service(_d0)", 1, true)
	if hook ~= nil and svc ~= nil then
		local body = gsrc:sub(hook, svc)
		if body:find("if globals.show_menu == true then return end", 1, true) ~= nil then
			fail("ゲートの位置", "service より手前", "assert_input_bits の中だけ")
		end
	end
	if fails == before then
		print("  ok 注入の直前で止め、列を捨てる処理は残している")
	end
end

print(fails == 0 and "\n全て通った" or ("\n" .. fails .. " 件 NG"))
os.exit(fails == 0 and 0 or 1)
