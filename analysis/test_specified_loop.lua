-- REVERSAL / COUNTER ATTACK - SPECIFIED, LOOP (handoff 2026-10-14, 14).
--
-- With the Loop row on, the Specified action runs again after it ends: an
-- airborne one on the landing, one on the ground once the dummy has been busy
-- and is free again (the landing gate and its deadline). With the row off,
-- nothing changes. This drives the real runner with the delivery slot and the
-- dummy's state moved tick by tick, and reads the guardCancel / menu / config
-- side from source.
--
--   [1]  off: nothing is kept, the guard action goes back to the arm
--   [2]  on: the first run in the slot, then a lap per busy -> free
--   [3]  an edit takes effect on the next lap
--   [4]  a setting that builds nothing ends the loop
--   [5]  switching the row off stops it at the next lap
--   [6]  the menu drops the loop; closing it does not restart it
--   [7]  a Random Start Wait start (arm_oneshot) loops only with the row on
--   [8]  specified_lap: the first-run fields are taken off, Button Wait and
--        the dash cancel's reverse are kept
--   [9]  guardCancel / menu / config
--   [10] GA.pose_release: a Pose holding the dash's first direction gets a
--        neutral in front of it (user, 2026-10-14), nothing else changes
--   [11] the lap built from it: one more Tick of run-up, the button unchanged
--   [12] the hit-stun arm and the lap call it; the block arm does not
--   [13] with the game standing behind the menu (no tick), M.menu_open ends the
--        run on every open; the master calls it each frame the menu is open
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_specified_loop.lua
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
training_settings = { action_sequences = {}, specified_loop = true }
function mark_training_settings_dirty() end
function dash_attack_ticks_for() return nil end

local queued = {}
function queue_input_sequence(d, seq)
	if d.pending_input_sequence ~= nil then return end
	d.pending_input_sequence = { sequence = seq, current_frame = 1 }
	queued[#queued + 1] = seq
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
local function busy() ram[P2 + 0x05] = 0 ; ram[P2 + 0x06] = 0x0A ; ram[P2 + 0x38] = 0 end
local function free() ram[P2 + 0x05] = 0 ; ram[P2 + 0x06] = 0 ; ram[P2 + 0x38] = 0 end
local function stun() ram[P2 + 0x05] = 2 ; ram[P2 + 0x06] = 0 ; ram[P2 + 0x38] = 0 end

-- One tick: the runner, then the walker's part - a record in the slot is
-- delivered one entry per tick and the slot frees after its last one. The
-- first run (the arm's, not the runner's) is dropped at its press by `press_at`.
local defender, now = {}, 0
local function tick(press_at)
	now = now + 1
	ram[TICKS] = now % 256
	R.service(defender)
	local s = defender.pending_input_sequence
	if s ~= nil then
		if s.arm then
			if press_at ~= nil and now >= press_at then defender.pending_input_sequence = nil end
		else
			s.current_frame = (s.current_frame or 1) + 1
			if s.current_frame > #s.sequence then defender.pending_input_sequence = nil end
		end
	end
end

local A = { { "forward" }, {}, { "forward", "LP" } }      -- a dash LP
local B = { { "down" }, { "down", "MK" } }                -- the edited setting
local function fresh()
	R.cancel()
	defender = { pending_input_sequence = { sequence = A, arm = true } }   -- the first run
	queued = {}
	training_settings.specified_loop = true
	globals.show_menu = false
end

print("[1] OFF: 何も残さず、反撃はアームへ戻る")
do
	fresh()
	training_settings.specified_loop = false
	eq("arm_specified_loop は断る", R.arm_specified_loop("reversal", function() return {} end), false)
	eq("runner は持たない", R.owns("reversal"), false)
end

print("[2] ON: 初回はスロットのまま、そのあと busy -> free ごとに 1 周")
local builds = 0
local function build_A()
	builds = builds + 1
	return R.specified_lap(A, { delay = 0, hold_dir = true })
end
do
	fresh()
	builds = 0
	eq("arm_specified_loop", R.arm_specified_loop("reversal", build_A), true)
	eq("runner が持つ", R.owns("reversal"), true)
	eq("Action Steps ではない", R.owns("sequence"), true)   -- sequence is always owned
	stun()
	for _ = 1, 3 do tick(4) end          -- the first run waits in the slot
	eq("初回が入っている間は積まない", #queued, 0)
	tick(4)                              -- pressed: the slot frees
	busy()
	for _ = 1, 6 do tick() end           -- the first run's attack
	eq("技の途中では積まない", #queued, 0)
	free()
	tick()
	eq("動けるようになった Tick に 1 周目", #queued, 1)
	eq("1 周目は設定のまま", queued[1] == A or (queued[1] and #queued[1] == #A), true)
	for _ = 1, 5 do tick() end           -- lap one delivered; the dummy stays free
	eq("同じ技が出ずに動けるままなら、続けて積まない", #queued, 1)
	busy()
	for _ = 1, 4 do tick() end
	free()
	tick()
	eq("busy -> free でもう 1 周", #queued, 2)
	eq("周ごとに組み立て直す (3 周目の分まで)", builds >= 2, true)
end

print("[3] 設定を変えたら次の周から")
do
	fresh()
	local n = 0
	local function build()
		n = n + 1
		return R.specified_lap((n == 1) and A or B, { delay = 0, hold_dir = true })
	end
	R.arm_specified_loop("reversal", build)
	tick(1)
	busy() ; for _ = 1, 3 do tick() end
	free() ; tick()
	for _ = 1, 4 do tick() end
	busy() ; for _ = 1, 3 do tick() end
	free() ; tick()
	eq("1 周目は変更前", queued[1] and #queued[1], #A)
	eq("2 周目は変更後", queued[2] and queued[2][2] and queued[2][2][2], "MK")
end

print("[4] 何も組めない設定ならループを終える")
do
	fresh()
	R.arm_specified_loop("reversal", function() return nil end)
	tick(1)
	busy() ; for _ = 1, 3 do tick() end
	free() ; for _ = 1, 3 do tick() end
	eq("周を積まない", #queued, 0)
	eq("反撃はアームへ戻る", R.owns("reversal"), false)
end

print("[5] 行を OFF にしたら次の周で止まる")
do
	fresh()
	R.arm_specified_loop("reversal", build_A)
	tick(1)
	busy() ; for _ = 1, 3 do tick() end
	free() ; tick()
	eq("1 周目は出る", #queued, 1)
	for _ = 1, 4 do tick() end
	training_settings.specified_loop = false
	busy() ; for _ = 1, 3 do tick() end
	free() ; for _ = 1, 3 do tick() end
	eq("2 周目は出ない", #queued, 1)
	eq("反撃はアームへ戻る", R.owns("reversal"), false)
end

print("[6] メニューでループを落とす。閉じただけでは始まらない")
do
	fresh()
	R.arm_specified_loop("reversal", build_A)
	tick(1)
	busy() ; tick()
	globals.show_menu = true
	tick()
	eq("メニュー中に積んだ周は落ちる", R.pending_count(), 0)
	globals.show_menu = false
	free() ; for _ = 1, 3 do tick() end
	busy() ; for _ = 1, 3 do tick() end
	free() ; for _ = 1, 3 do tick() end
	eq("閉じた後も新しい反撃までは出ない", #queued, 0)
	eq("loop_alive も落ちている", R.loop_alive(), false)
end

print("[7] Random Start Wait の初回 (arm_oneshot) も、行が ON のときだけループする")
do
	fresh()
	defender.pending_input_sequence = nil
	R.arm_oneshot("counter", A, { wait = 2, adj = 0, delay = 0, hold_dir = true }, build_A)
	free()
	for _ = 1, 8 do tick() end
	eq("初回が出る", #queued >= 1, true)
	local first = #queued
	busy() ; for _ = 1, 3 do tick() end
	free() ; tick()
	eq("ON: 続けて 1 周", #queued, first + 1)

	fresh()
	defender.pending_input_sequence = nil
	training_settings.specified_loop = false
	R.arm_oneshot("counter", A, { wait = 2, adj = 0, delay = 0, hold_dir = true }, build_A)
	free()
	for _ = 1, 8 do tick() end
	local once = #queued
	busy() ; for _ = 1, 3 do tick() end
	free() ; for _ = 1, 3 do tick() end
	eq("OFF: 初回だけ (これまでどおり)", #queued, once)
	eq("OFF: 出し終えたらアームへ戻る", R.owns("counter"), false)
end

print("[8] specified_lap: 初回用の印を外し、Button Wait と逆方向は残す")
do
	local one = R.specified_lap(A, { delay = 0, hold_dir = true })
	eq("ボタン待ちなしは 1 段", one and #one, 1)
	eq("start_free は無い", one[1].start_free, nil)
	eq("start_wait は無い", one[1].start_wait, nil)
	eq("start_part は無い", one[1].start_part, nil)
	eq("助走の長さはある", (one[1].lead or 0) > 0, true)
	local two = R.specified_lap(A, { delay = 5, hold_dir = true })
	eq("Button Wait 5 は 2 段", two and #two, 2)
	eq("ボタンの段は 5 Tick 後", two[2].wait, 5)
	eq("ボタンの段にも start_part は無い", two[2].start_part, nil)
	local rv = R.specified_lap(A, { delay = 0, hold_dir = true, rev = "back" })
	eq("ダッシュキャンセルは 2 段", rv and #rv, 2)
	eq("逆方向を持つ", rv[1].rev, "back")
	eq("ボタンは逆方向の 2 Tick 後 (既定。Random Start Wait の初回と同じ)", rv[2].wait, 2)
	-- A lap asks for one tick (GA.specified_lap): measured, a lap's button was a
	-- tick behind the first run's (v11.7.25.2, Sasquatch dash cancel).
	local rv1 = R.specified_lap(A, { delay = 8, hold_dir = true, rev = "back", rev_ticks = 1 })
	eq("周は Button Wait + 1 (8 なら 9)", rv1 and rv1[2] and rv1[2].wait, 9)
	eq("空の入力は nil", R.specified_lap({}, {}), nil)
end

print("[9] guardCancel / menu / config")
do
	local gsrc = io.open("guardCancel.lua"):read("*a")
	local aq = gsrc:find("function GA.af_queue(", 1, true)
	local aq_e = aq and gsrc:find("\nend\n", aq, true)
	local aqb = gsrc:sub(aq or 1, aq_e or 1)
	eq("初回がスロットに入ったところで登録する",
	   aqb:find("actionSequenceRunnerModule.arm_specified_loop(_ga, GA.specified_lap)", 1, true) ~= nil, true)
	eq("Specified の 2 種類だけ", aqb:find("if _ga == 'reversal' or _ga == 'counter' then", 1, true) ~= nil, true)
	eq("Random Start Wait の初回にも渡す",
	   gsrc:find("actionSequenceRunnerModule.arm_oneshot(_ga, _mk, _o, GA.specified_lap)", 1, true) ~= nil, true)
	local sl = gsrc:find("function GA.specified_lap()", 1, true)
	local sl_e = sl and gsrc:find("\nend\n", sl, true)
	local slb = gsrc:sub(sl or 1, sl_e or 1)
	eq("周の乱数は自分で引き、GA.btn_rd に書かない",
	   slb:find("GA.btn_rd_roll()", 1, true) ~= nil and slb:find("GA.btn_rd =", 1, true) == nil, true)
	eq("周の Random Start Wait は runner が引く (ここでは 0)", slb:find("wait = 0,", 1, true) ~= nil, true)
	eq("Button Lever などは初回と同じ関数", slb:find("GA.specified_extras(_o, _rd)", 1, true) ~= nil, true)
	-- A dash cancel's lap keeps the arm's delay (Auto included) and the
	-- one-tick button: no step-path number, no two-tick gap.
	local dc = slb:find("if _o.rev ~= nil then", 1, true)
	local dcb = dc and slb:sub(dc, (slb:find("\n\tend\n", dc, true) or dc))
	eq("ダッシュキャンセルの周は step の実測値に差し替えない",
	   dcb ~= nil and dcb:find("_o.auto_dash = nil", 1, true) ~= nil, true)
	eq("ダッシュキャンセルの周はボタンを 1 Tick 後に", dcb ~= nil and dcb:find("_o.rev_ticks = 1", 1, true) ~= nil, true)
	-- Auto for Sasquatch's Forward Dash Cancel is the user's 8 (the fastest that
	-- still makes the short dash LP); the back cancel has not been re-measured.
	eq("サスカッチの Forward Dash Cancel の Auto は 8",
	   gsrc:find('[0x0A] = { name = "Sasquatch", f =  2, b =  1, fc =  8, bc =  7 },', 1, true) ~= nil, true)
	local rsrc = io.open("actionSequenceRunner.lua"):read("*a")
	eq("Random Start Wait の初回は 2 Tick のまま (rev_ticks の既定)",
	   rsrc:find("local bwait = delay + ((o.rev ~= nil) and (o.rev_ticks or 2) or 0)", 1, true) ~= nil, true)

	local msrc = io.open("menu.lua"):read("*a")
	local it = msrc:find('checkbox_menu_item("Loop", training_settings, "specified_loop", false,', 1, true)
	eq("メニューの行", it ~= nil, true)
	eq("Specified の 2 種類だけで出る",
	   msrc:find("specified_loop_item.is_disabled = button_random_delay_item.is_disabled", 1, true) ~= nil, true)
	local rd_row = msrc:find("indent(2, button_random_delay_item),", 1, true)
	local lp_row = msrc:find("indent(1, specified_loop_item),", 1, true)
	eq("Random Delay のすぐ下", rd_row ~= nil and lp_row ~= nil and lp_row > rd_row
	   and msrc:sub(rd_row, lp_row):find("\n", 1, true) == #("indent(2, button_random_delay_item),") + 1, true)
	-- The help text: no line wider than the screen allows (79, as elsewhere).
	local hs = it and msrc:find('"', it + #('checkbox_menu_item("Loop", training_settings, "specified_loop", false,'), true)
	local he = hs and msrc:find('")', hs + 1, true)
	local help = hs and he and msrc:sub(hs + 1, he - 1) or ""
	local widest = 0
	for line in (help:gsub("\\n", "\n") .. "\n"):gmatch("(.-)\n") do
		if #line > widest then widest = #line end
	end
	eq("説明の行は 79 文字以内", widest > 0 and widest <= 79, true)

	local cfg = dofile("config.lua").default_training_settings
	eq("既定は OFF", cfg.specified_loop, false)
	eq("Action Steps の行は別のキー", cfg.action_steps_loop, false)
end

-- The pieces of guardCancel.lua GA.pose_release needs, sliced out as globals.
local gsrc = io.open("guardCancel.lua"):read("*a")
local function slice(head, tail)
	local a = gsrc:find(head, 1, true)
	local b = a and gsrc:find(tail, a, true)
	assert(a and b, head .. " が guardCancel.lua に見つからない")
	return gsrc:sub(a, b + #tail - 1)
end
local stick_now = "forward dash cancel"
GA = { stick = function() return stick_now end }
assert(loadstring((slice("local NEEDS_TAP_EDGE = {", "\n}\n"):gsub("^local ", ""))))()
assert(loadstring((slice("local function is_plain_dash()", "\nend\n"):gsub("^local ", ""))))()
assert(loadstring(slice("GA.POSE_DIRS = {", "\n}\n")))()
assert(loadstring(slice("function GA.pose_release(", "\nend\n")))()

local function dash(dir, btn) return { { dir }, {}, { dir, btn } } end
local function released(ga, stick, pose, list, p1)
	globals.dummy.guard_action = ga
	globals.options = { dummy_neutral = pose }
	globals.controlling_p1 = (p1 ~= false)
	stick_now = stick
	local n = #list
	local out = GA.pose_release(list)
	return out, #out - n
end

print("[10] GA.pose_release: Pose がダッシュの 1 回目の方向を押していたら、その前にニュートラル")
do
	local l = dash("forward", "LP")
	local out, added = released("reversal", "forward dash cancel", 4, l)
	eq("しゃがみ前 + 前ダッシュキャンセル: 1 つ足す", added, 1)
	eq("同じ表を書き換える (af_queue が表で照合する)", out == l, true)
	eq("先頭はニュートラル", #l[1], 0)
	eq("その次が 1 回目の前", l[2][1], "forward")
	eq("最後はボタンのまま", l[4][2], "LP")
	eq("Counter Attack も同じ", select(2, released("counter", "forward dash", 6, dash("forward", "LP"))), 1)
	eq("上前も前を含む", select(2, released("reversal", "forward dash", 9, dash("forward", "LP"))), 1)
	eq("しゃがみ後 + 後ダッシュ", select(2, released("reversal", "back dash cancel", 2, dash("back", "LP"))), 1)
	eq("ニュートラル (1) は変えない", select(2, released("reversal", "forward dash cancel", 1, dash("forward", "LP"))), 0)
	eq("しゃがみ後 + 前ダッシュは変えない (前は押していない)",
	   select(2, released("reversal", "forward dash cancel", 2, dash("forward", "LP"))), 0)
	eq("しゃがみ (3) + 前ダッシュは変えない", select(2, released("reversal", "forward dash cancel", 3, dash("forward", "LP"))), 0)
	eq("P1 を操作していない (Pose が掛からない) なら変えない",
	   select(2, released("reversal", "forward dash cancel", 4, dash("forward", "LP"), false)), 0)
	eq("Action Steps の表は変えない (runner の compile 済みの表)",
	   select(2, released("sequence", "forward dash cancel", 4, dash("forward", "LP"))), 0)
	eq("ダッシュ以外 (QCF) は変えない",
	   select(2, released("reversal", "QCF", 3, { { "down" }, { "down", "forward" }, { "forward", "LP" } })), 0)
	eq("1 つだけの入力は変えない", select(2, released("reversal", "forward dash cancel", 4, { { "forward", "LP" } })), 0)
	globals.dummy.guard_action = "reversal"
	globals.options = {}
	globals.controlling_p1 = nil
end

print("[11] その周: 助走が 1 Tick 長く、ボタンの位置は同じ")
do
	local plain = R.specified_lap(dash("forward", "LP"), { delay = 8, hold_dir = true, rev = "back", rev_ticks = 1 })
	local l = dash("forward", "LP")
	released("reversal", "forward dash cancel", 4, l)
	local rel = R.specified_lap(l, { delay = 8, hold_dir = true, rev = "back", rev_ticks = 1 })
	eq("動作の段はニュートラルから", rel and #rel[1].sequence[1], 0)
	eq("助走 (lead) は 1 Tick 長い (着地の門が 1 Tick 早く始める)", rel[1].lead, plain[1].lead + 1)
	eq("最後の前は同じ", rel[1].sequence[#rel[1].sequence][1], "forward")
	eq("ボタンの段は変わらない (Button Wait 8 なら 9)", rel[2].wait, plain[2].wait)
	eq("逆方向も同じ", rel[1].rev, "back")
	globals.dummy.guard_action = "reversal"
	globals.options = {}
	globals.controlling_p1 = nil
end

print("[12] やられ後のアームと周が呼ぶ。ガード後のアームは呼ばない")
do
	local g = gsrc:find("local _mk = ga_sequence(\n\t\t\t\tglobals.dummy.counter_attack_stick,", 1, true)
	local q = g and gsrc:find("GA.af_queue(_defender, _mk, true)", g, true)
	local blk = g and gsrc:sub(g, q or g)
	eq("アームの区間がある", g ~= nil and q ~= nil, true)
	eq("やられ後だけ (ガード後とダウン後は除く)",
	   blk ~= nil and blk:find("if hs_arm_edge and not BLK.edge and not arm_edge then\n\t\t\t\tGA.pose_release(_mk)", 1, true) ~= nil, true)
	local sl = gsrc:find("function GA.specified_lap()", 1, true)
	local sl_e = sl and gsrc:find("\nend\n", sl, true)
	local slb = gsrc:sub(sl or 1, sl_e or 1)
	local pr = slb:find("GA.pose_release(_mk)", 1, true)
	local op = slb:find("local _o = {", 1, true)
	eq("周も、オプションより前に", pr ~= nil and op ~= nil and pr < op, true)
	-- Only one call site each: a second call on the same list would add a
	-- second neutral.
	local n = 0
	for _ in gsrc:gmatch("GA%.pose_release%(_mk%)") do n = n + 1 end
	eq("呼ぶのは 2 か所だけ", n, 2)
end

print("[13] ゲームが止まっていて Tick が来なくても、メニューを開けば毎回終わる (v11.7.28.2)")
do
	-- [6] with no tick behind the menu: the game stands there since v11.7.28,
	-- so the walker never reaches M.service and only the frame call is left.
	fresh()
	R.arm_specified_loop("reversal", build_A)
	tick(1)
	busy() ; tick()
	local before = R.pending_count()
	R.menu_open(defender)
	eq("メニューを閉じているときは何もしない", R.pending_count(), before)
	globals.show_menu = true
	R.menu_open(defender)
	eq("開いたら積んだ周は落ちる (Tick なし)", R.pending_count(), 0)
	eq("  送っている途中の入力も", defender.pending_input_sequence, nil)
	eq("  loop_alive も落ちる", R.loop_alive(), false)
	globals.show_menu = false
	free() ; for _ = 1, 3 do tick() end
	busy() ; for _ = 1, 3 do tick() end
	free() ; for _ = 1, 3 do tick() end
	eq("閉じた後も新しい反撃までは出ない", #queued, 0)
	eq("dummy が nil でも落ちない", pcall(R.menu_open, nil), true)
	-- The master asks every frame the menu is open, under the walker's own
	-- condition, before the game runs the frame.
	local ms = io.open("vsav_training_master_script.lua"):read("*a")
	local call = "\t\tactionSequenceRunnerModule.menu_open(player_objects and player_objects[2])\n"
	local at = ms:find(call, 1, true)
	local head = at and ms:sub(1, at - 1):match("\n(\tif globals%.show_menu == true and globals%.dummy ~= nil\n[^\n]*\n)$")
	eq("master: メニュー中・runner が持っているときだけ呼ぶ",
	   head == "\tif globals.show_menu == true and globals.dummy ~= nil\n\t   and actionSequenceRunnerModule.owns(globals.dummy.guard_action) then\n", true)
	local rb = ms:find("emu.registerbefore(function()", 1, true)
	local first_return = rb and ms:find("\n%s*return\n", rb)
	local frozen_set = ms:find("\tglobals.game_frozen = gameFreezeModule.frozen()\n", 1, true)
	eq("  globals.game_frozen の後、最初の return より前",
	   at ~= nil and frozen_set ~= nil and first_return ~= nil and frozen_set < at and at < first_return, true)
end

print(fails == 0 and "\n全て通った" or ("\n" .. fails .. " 件 NG"))
os.exit(fails == 0 and 0 or 1)
