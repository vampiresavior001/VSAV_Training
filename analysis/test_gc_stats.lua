-- Show GC Stats の数え方と表示 (scripts/gcStats.lua)。
--
-- 1 回 = 1 本の連続ガード ($05 が 02 の間)。その中で GC の受付 ($158) が開き、
-- ゲームが GC コマンドを 1 段以上受け取った (ガード前から生きている入力を含む)
-- ものだけを数える。途中のどこかで GC が出れば Pass、出ないまま抜ければ Fail。
-- 途中の Cmd Expired や受付終了では確定しない。測るのは P1 だけで、1P / 2P は
-- P1 のキャラクターが左右どちらにいたか ($120)。平均は Pass の回だけ
-- (本人、2026-10-01)。表記は PB Stats に合わせる: Total / Pass / Fail /
-- Success、小数 2 桁、まだ無いものは - (本人、2026-10-01: 表記がPBとぶれてる)。
--
-- 窓の状態は guardCancel.lua の gc_next_state と gc_tick_count をそのまま
-- 取り出して回す。フックは 0x0221CC に来たときしか走らないので、ここでは
-- 同じ順で 1 ティックずつ叩く。最後に GC Command Trace の gct_tick と同じ
-- ティックを食わせ、Input t がトレースの行と食い違わないことも見る。
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_gc_stats.lua
local NL = string.char(10)
local src = io.open("guardCancel.lua"):read("*a")

local fails = 0
local function want(what, got, w)
	if got ~= w then
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(w) .. "]")
	else
		print("  ok " .. what)
	end
end

local function lift(name)
	local a = src:find("local function " .. name .. "(", 1, true)
	local b = src:find(NL .. "end", a or 1, true)
	assert(a and b, name .. " が guardCancel.lua に見つからない")
	return assert(loadstring(src:sub(a, b + 3) .. NL .. "return " .. name))()
end
local gc_next_state = lift("gc_next_state")
local gc_tick_count = lift("gc_tick_count")

local RUN = true
globals = { controlling_p1 = true, match_running = function() return RUN end,
            options = { display_gc_stats = true } }
local M = dofile("gcStats.lua")

-- ---------------------------------------------------------------- the game
-- One tick as the hook sees it. Fields stay as set until changed; the block
-- clock runs down by itself, one a tick, the way 0x022492 takes it.
--   s05   P1 $05 (02 in the stun)      clock  $158      act  $06
--   prog  the GC command's +0          step   its +1    side $120 (1 = left)
local S, tick
local function fresh(seq0)
	M.clear()
	RUN = true
	globals.controlling_p1, globals.macroLua = true, nil
	globals.options.display_gc_stats = true
	S = { seq = seq0 or 1000, state = "p1_gc_none", open = nil,
	      clock = 0, act = 0, s05 = 0, prog = 0, step = 0, side = 1 }
	-- The first tick after a clear only learns what the next one compares
	-- against, as it does after a load: nothing on it can start a string.
	tick()
end
function tick(ch)
	for k, v in pairs(ch or {}) do S[k] = v end
	S.seq = S.seq + 1
	local gc = gc_next_state(S.state, S.clock, S.act)
	local n
	n, S.open = gc_tick_count(gc, S.open, S.seq)
	M.on_tick(S.seq, gc, n, S.prog, S.step, S.s05, S.side)
	S.state = gc
	if S.clock > 0 then S.clock = S.clock - 1 end
	return S.seq, gc
end
local function idle(k) for _ = 1, k do tick() end end
-- The contact: $05 to 02 with the clock still 0 - the guard handler loads it
-- further down the same update - then the window opens on the next tick.
local function block()
	tick({ s05 = 2 })
	local seq, gc = tick({ clock = 14 })
	assert(gc == "p1_gc_begin", "the window did not open: " .. tostring(gc))
	return seq
end
-- Another hit inside the stun: $05 never left 02, the clock loads again.
local function hit_again() return tick({ clock = 14 }) end
-- The cancel: the clock cleared, $06 on the special, $05 out of the stun and
-- +0 back to 0, all on one tick (see gcStats.lua on the order).
local function cancel()
	local seq, gc = tick({ clock = 0, act = 0x0E, s05 = 0, prog = 0, step = 6 })
	assert(gc == "p1_gc_success", "no success: " .. tostring(gc))
	tick({ act = 0 })
	return seq
end
local function run_out() while S.clock > 0 do tick() end tick() end
-- 6 2 3: +0 0->2 / +1 ->02, then +1 ->04, then +0 ->4 / +1 ->06.
local function d1() return tick({ prog = 2, step = 2 }) end
local function d2() return tick({ prog = 2, step = 4 }) end
local function d3() return tick({ prog = 4, step = 6 }) end
local function expire() return tick({ prog = 0 }) end

local function row(i) return M.text()[i + 1] end
local function n(i, k) return M.state()[i][k] end

print("[1] ガードだけでは数えない")
do
	fresh()
	idle(3)
	block()
	run_out()
	tick({ s05 = 0 })
	idle(3)
	want("Total 0", n(1, "total") + n(2, "total"), 0)
	-- 食らい: 受付が開かないので、コマンドが進んでも連続ガードではない
	tick({ s05 = 2 })
	d1() d2() expire()
	idle(20)
	tick({ s05 = 0 })
	want("食らいは数えない", n(1, "total"), 0)
end

print("")
print("[1b] 前進してからガード - 1 段目が生きていれば試行 (TRIAL_MIN_STEPS = 1 のとおり)")
do
	-- 前を入れ続けると 1 段目が失効のたびに取り直される (v11.7.11 の gc trace
	-- ログ seq 592-650)。その直後のガードは試行に入り、GC しなければ Fail。
	want("段数のしきい値は 1", M.TRIAL_MIN_STEPS, 1)
	fresh()
	d1()                 -- 前
	idle(4)
	block()              -- 後ろでガード。前は 1 段目のまま生きている
	expire()
	run_out()
	tick({ s05 = 0 })
	want("Total 1 / Fail 1", n(1, "total") .. "/" .. n(1, "fail"), "1/1")
end

print("")
print("[2] コマンドが進んで、GC しないまま連続ガードが終わる -> Fail")
do
	fresh()
	block()
	d1() d2()
	expire()
	run_out()
	want("受付が切れただけでは確定しない", n(1, "total"), 0)
	tick({ s05 = 0 })
	want("抜けたら Fail", n(1, "total") .. "/" .. n(1, "pass") .. "/" .. n(1, "fail"), "1/0/1")
end

print("")
print("[3] 2 発の連続ガードは 1 回")
do
	fresh()
	block()
	d1()
	expire()
	run_out()
	hit_again()
	d1() d2() expire()
	run_out()
	tick({ s05 = 0 })
	want("Total 1 (2 回に数えない)", n(1, "total"), 1)
	want("Fail 1", n(1, "fail"), 1)
end

print("")
print("[4] 途中で失効、次のヒットで入れ直して GC -> Pass 1 回だけ")
do
	fresh()
	block()
	d1() d2()
	expire()             -- Cmd Expired
	run_out()            -- GC Expired
	hit_again()
	local first = d1()
	d2() d3()
	local ok = cancel()
	idle(5)
	want("Total 1 / Pass 1 / Fail 0", n(1, "total") .. "/" .. n(1, "pass") .. "/" .. n(1, "fail"), "1/1/0")
	-- 入れ直した方の 1 個目から
	want("Input t は最後のコマンドから", n(1, "sum_in"), ok - first)
end

print("")
print("[5] 平均 - ガード前からの入力、GC t は受付開始から")
do
	fresh()
	idle(2)
	local first = d1()   -- ガードの 3 ティック前に 6
	idle(2)
	local open = block()
	local second = d2()
	idle(1)
	local third = d3()
	local ok = cancel()
	want("Input t = 最初の方向から成立まで", n(1, "sum_in"), ok - first)
	-- 方向ごと: 1 個目 -> 2 個目、2 個目 -> 3 個目、3 個目 -> ボタン。トレースの
	-- 各行の数字と同じ数え方で、足すと Input t (本人、2026-10-01)
	local sp = M.steps()[1]
	want("方向ごとの平均", table.concat(sp, " "), string.format("%.2f %.2f %.2f",
		second - first, third - second, ok - third))
	want("足すと Input t", (second - first) + (third - second) + (ok - third), ok - first)
	want("2P 側はまだ -", table.concat(M.steps()[2], " "), "- - -")
	want("GC t = 受付開始から (SUCCESS Nt と同じ)", n(1, "sum_gc"), ok - open)
	want("表示は小数 2 桁 (PB Stats と同じ)", row(1), "1P          1     1     0 100.00% "
		.. string.format("%5.2f", ok - open) .. " " .. string.format("%7.2f", ok - first))
	-- 2 回目: 最後の方向とボタンが同じティック (+0 が 0 に落ち、+1 だけ上がる)
	block()
	local f2 = d1()
	d2()
	local ok2 = tick({ clock = 0, act = 0x0E, s05 = 0, prog = 0, step = 6 })
	tick({ act = 0 })
	want("2 回とも Pass", n(1, "pass"), 2)
	want("Input t の合計", n(1, "sum_in"), (ok - first) + (ok2 - f2))
	want("平均は Pass の回だけ", n(1, "n_in"), 2)
	-- 最後の方向とボタンが同じティックなら、ボタンまでの間隔は 0
	want("方向ごとも同じ 2 回ぶん (n_in を共有)", n(1, "n_in"), 2)
	want("ボタンまでの合計 (1 回目 + 0)", M.state()[1].sum_st[3], ok - third)
	-- Fail を足しても平均は動かない
	local before = row(1):sub(-14)
	block() d1() expire() run_out() tick({ s05 = 0 })
	want("Fail は平均に入らない", row(1):sub(-14), before)
	want("Success 66.67%", row(1):match("(%d+%.%d%d)%%"), "66.67")
end

print("")
print("[6] 左右 - P1 が右にいれば 2P。試行が始まった時点の側")
do
	fresh()
	S.side = 0
	block() d1() expire() run_out() tick({ s05 = 0 })
	want("2P 側に Fail", n(2, "total") .. "/" .. n(2, "fail"), "1/1")
	want("1P 側は 0", n(1, "total"), 0)
	-- 試行が始まってから入れ替わっても、始まった側のまま
	S.side = 1
	block()
	d1()
	S.side = 0
	d2() d3()
	cancel()
	want("1P 側に Pass", n(1, "pass"), 1)
	want("1P / 2P の行", row(1):sub(1, 2) .. row(2):sub(1, 2), "1P2P")
end

print("")
print("[7] ダミーと再生は数えない。操作側を切り替えても消さない")
do
	fresh()
	block() d1() expire() run_out() tick({ s05 = 0 })
	want("自分の Fail が 1", n(1, "fail"), 1)
	-- Coin で P1 をダミーに渡す: P1 の GC はダミーのもの。Recording Wizard も
	-- 録るたびに同じ切り替えをするので、切り替えで消してはいけない (本人、
	-- 2026-10-01)。P1 しか数えないので、別のキャラクターの数字は混ざらない。
	-- Every tick that is not counted is forgotten, so the first one counted
	-- again only learns - as after a load. One idle tick stands for the gap
	-- that is always there in play.
	globals.controlling_p1 = false
	idle(1)
	block() d1() d2() d3() cancel()
	want("渡しても消えない", n(1, "total") .. "/" .. n(1, "fail"), "1/1")
	want("ダミーの GC は数えない", n(1, "pass") + n(2, "pass"), 0)
	globals.controlling_p1 = true
	idle(1)
	block() d1() d2() d3() cancel()
	want("戻したら続きから数える", n(1, "total") .. "/" .. n(1, "pass"), "2/1")
	-- 録画が P1 のキーを押している間
	globals.macroLua = { playing = true, get_keytable = function()
		return { ["P1 Right"] = true, ["P2 Left"] = true } end }
	idle(1)
	block() d1() d2() d3() cancel()
	want("P1 を押す再生は数えない", n(1, "pass"), 1)
	-- ダミー (P2) だけの再生は、まさに練習の場面
	globals.macroLua = { playing = true, get_keytable = function()
		return { ["P2 Left"] = true, ["P1 Coin"] = true } end }
	idle(1)
	block() d1() d2() d3() cancel()
	want("P2 だけの再生なら数える", n(1, "pass"), 2)
end

print("")
print("[8] 状態の変化 - 捨てる、数え直す、桁あふれしない")
do
	fresh(65530)          -- p1_tick_seq はただの数。バイトでもワードでもない
	local first = d1()
	block()
	d2() d3()
	local ok = cancel()
	want("16 ビットを跨いでも Input t", n(1, "sum_in"), ok - first)
	-- ロード (discard): 途中の連続ガードは Fail にしない
	block()
	d1()
	M.discard()
	expire() run_out() tick({ s05 = 0 })
	want("ロードで捨てた連続ガードは数えない", n(1, "total"), 1)
	block() d1() expire() run_out() tick({ s05 = 0 })
	want("次の連続ガードは普通に数える", n(1, "fail"), 1)
	-- ロードがコマンドの途中に来ると、そのコマンドの起点は見えない
	d1()
	M.discard()
	idle(1)              -- learns a motion already under way: no origin
	block() d2() d3() cancel()
	want("起点の無い成功も Pass", n(1, "pass"), 2)
	want("Input t の平均には入れない", n(1, "n_in"), 1)
	want("入れなかった数を残す (方向ごとも一緒に外す)", M.state().no_input, 1)
	-- ラウンドが終わる (試合中でなくなる)
	block() d1()
	RUN = false
	idle(3)
	RUN = true
	tick({ s05 = 0 })
	want("ラウンド終了で捨てる", n(1, "total"), 3)
end

print("")
print("[9] キャラ選択 (clear) は途中の試行も捨てる")
do
	fresh()
	block() d1() expire() run_out() tick({ s05 = 0 })
	block() d1()
	M.clear()
	expire() run_out() tick({ s05 = 0 })
	want("両側とも 0", n(1, "total") + n(2, "total"), 0)
	want("表示も 0 と -", row(1), "1P          0     0     0       -     -       -")
end

print("")
print("[9b] OFF の間は数えない。OFF -> ON は 0 から (PB Stats と同じ)")
do
	-- 本人、2026-10-01: PB Statsとあわせて。0 に戻すのはメインスクリプトが OFF の
	-- 間に毎フレーム呼ぶ clear (配線は [12])。ここはモジュールが数えないこと。
	fresh()
	block() d1() expire() run_out() tick({ s05 = 0 })
	want("ON で Fail 1", n(1, "fail"), 1)
	globals.options.display_gc_stats = false
	block() d1() d2() d3() cancel()
	block() d1() expire() run_out() tick({ s05 = 0 })
	want("OFF の間は Pass も Fail も増えない", n(1, "pass") .. "/" .. n(1, "fail"), "0/1")
	-- OFF の途中で始まった連続ガードは、ON に戻しても数えない
	block() d1()
	globals.options.display_gc_stats = true
	expire() run_out() tick({ s05 = 0 })
	want("OFF の間に始まった連続ガードは数えない", n(1, "total"), 1)
	idle(1)
	block() d1() d2() d3() cancel()
	want("ON に戻した後は数える", n(1, "pass"), 1)
end

print("")
print("[10] 表示 - 最大桁でも同じ幅")
do
	fresh()
	local st = M.state()
	st[1].total, st[1].pass, st[1].fail = 99999, 99999, 0
	st[1].n_gc, st[1].sum_gc = 3, 42
	st[1].n_in, st[1].sum_in = 1, 999.9
	st[2].total, st[2].pass, st[2].fail = 99999, 0, 99999
	local t = M.text()
	want("見出し (PB Stats の語)", t[1], "GC Side Total  Pass  Fail Success  GC t Input t")
	want("99999 と 100.00%", t[2], "1P      99999 99999     0 100.00% 14.00  999.90")
	want("0 件の平均は -", t[3], "2P      99999     0 99999   0.00%     -       -")
	want("3 行とも同じ幅", #t[1] == #t[2] and #t[2] == #t[3], true)
	-- 99999 で止まる。PB Stats と同じ (本人、2026-10-01: PBにあわせて)
	block() d1() expire() run_out() tick({ s05 = 0 })
	block() d1() d2() d3() cancel()
	want("99999 で止まる (Fail も Pass も増えない)",
		st[1].total .. "/" .. st[1].pass .. "/" .. st[1].fail, "99999/99999/0")
	want("平均も動かない", st[1].n_gc .. "/" .. st[1].n_in, "3/1")
	-- 止まるのはその側だけ
	S.side = 0
	st[2].total, st[2].fail = 5, 5
	block() d1() expire() run_out() tick({ s05 = 0 })
	want("もう片方の側は数える", st[2].total, 6)
	S.side = 1
	-- 色も PB Stats と同じ: Pass と Success は緑、Fail は赤、見出しは灰色
	local l = M.lines()
	local pb = dofile("pbStats.lua").lines()
	want("Pass は PB Stats の Pass の色", l[2][3][2], pb[2][2][2])
	want("Fail は PB Stats の Fail の色", l[2][4][2], pb[2][3][2])
	want("Success は PB Stats の Success の色", l[2][5][2], pb[3][2][2])
	want("見出しは PB Stats のラベルの色", l[1][1][2], pb[1][1][2])
end

print("")
print("[11] 画面 - 入力の帯・SUCCESS・トレースにかからない")
do
	calls, boxes = {}, {}
	gui = {
		text = function(x, y, s, c) calls[#calls + 1] = { x = x, y = y, s = s, c = c } end,
		box = function(x1, y1, x2, y2) boxes[#boxes + 1] = { x1 = x1, y1 = y1, x2 = x2, y2 = y2 } end,
		image = function() end, line = function() end, rect = function() end,
	}
	memory = { readbyte = function() return 0 end, readword = function() return 0 end,
	           readdword = function() return 0 end, writebyte = function() end,
	           registerexec = function() end, registerwrite = function() end,
	           getregister = function() return 0 end }
	emu = { framecount = function() return 1 end, screenwidth = function() return 384 end,
	        screenheight = function() return 224 end }
	joypad = { get = function() return {} end }
	local _img = { gdStr = function() return "" end }
	gd = { createFromPng = function() return _img end,
	       createFromPngStr = function() return _img end, copyResampled = function() end }
	package.preload["gd"] = function() return gd end
	package.preload["./scripts/actionSequenceRunner"] = function()
		return { gc_freq = function() return nil end }
	end
	package.preload["./scripts/debugKnockdown"] = function()
		return { mark_write = function() end }
	end
	package.preload["./scripts/airGuardGap"] = function() return dofile("airGuardGap.lua") end
	package.preload["./scripts/pbStats"] = function() return dofile("pbStats.lua") end
	-- hud.lua と同じ表を見るため、このテストの M を渡す。
	package.preload["./scripts/gcStats"] = function() return M end
	-- hud.lua requires commandTrainer: GC Command Trace makes way for its box.
	package.preload["./scripts/commandLog"] = function() return dofile("commandLog.lua") end
	package.preload["./scripts/commandTrainer"] = function() return dofile("commandTrainer.lua") end
	local saved = globals
	images = {}
	gui.image = function(x, y, img) images[#images + 1] = { x = x, y = y, img = img } end
	img_dir = {}
	for i = 1, 9 do img_dir[i] = "dir" .. i end
	img_no_button = "nb"
	-- 右下: PB Stats を出しているとき (左上の 4 つのどれかが ON)
	globals = { options = { display_gc_stats = true, display_pb_stats = true },
	            controlling_p1 = true, match_running = function() return RUN end }
	local hud = dofile("hud.lua")
	want("描画が外に出ている", type(hud.draw_gc_stats), "function")
	-- 最大桁のまま描く
	hud.draw_gc_stats()
	want("箱は 1 つ", #boxes, 1)
	local b = boxes[1] or { x1 = 0, y1 = 0, x2 = 0, y2 = 0 }
	-- 入力の帯: 箱は screen height - 21、列の上のラベルはその列の y - 9
	local ih = io.open("inputHistory.lua"):read("*a")
	local back = tonumber(ih:match("local input_underlay_y = emu%.screenheight%(%) %- (%d+)"))
	local label_y = (224 - back) + 2 - 9
	want("帯のラベルは y 196 (帯 203 + 2 - 9)", label_y, 196)
	want("箱の下端がラベルより上", b.y2 < label_y, true)
	-- GC Command Trace: blocks_top() は 38、行は TRACE_ROWS + 結果の 1 行。
	-- 診断用の Random Guard Action % Check (配布時 OFF) を出すと 50 から。
	local hsrc = io.open("hud.lua"):read("*a")
	local row_h = tonumber(hsrc:match("local GCT_ROW_H = (%d+)"))
	local rows = tonumber(src:match("local TRACE_ROWS = (%d+)"))
	local trace_bottom = 38 + (rows + 1) * row_h + 1
	want("トレースの最大の下端は 138", trace_bottom, 138)
	want("箱の上端がトレースより下", b.y1 > trace_bottom, true)
	want("方向の行が 2 行ぶん (矢印 6 個 + ボタンの点 12 個)", #images, 18)
	want("1P は → ↓ ↘、2P は ← ↓ ↙ (トレースと同じ絵)",
		images[1].img .. images[2].img .. images[3].img .. images[10].img .. images[11].img .. images[12].img,
		"dir6dir2dir3dir4dir2dir1")
	want("画面の中 (左)", b.x1 >= 0, true)
	want("画面の中 (右)", b.x2 <= 384, true)
	local out, colour_bad = {}, 0
	for _, c in ipairs(calls) do
		if c.x < b.x1 or c.x + #c.s * 4.2 > b.x2 + 0.5 or c.y < b.y1 or c.y + 7 > b.y2 + 1 then
			out[#out + 1] = c.s
		end
		if type(c.c) ~= "string" then colour_bad = colour_bad + 1 end
	end
	want("文字は全部箱の中", table.concat(out, ","), "")
	want("色が nil の文字は無い", colour_bad, 0)
	-- 右揃え: 各列の右端が行をまたいで揃う (Input t の列)
	local last = {}
	for _, c in ipairs(calls) do
		if last[c.y] == nil or c.x > last[c.y].x then last[c.y] = c end
	end
	local ends = {}
	for _, c in pairs(last) do ends[#ends + 1] = c.x + #c.s * 4.2 end
	local spread = 0
	for _, e in ipairs(ends) do spread = math.max(spread, math.abs(e - ends[1])) end
	want("Input t の列と方向の行の最後の数は右で揃う (" .. #ends .. " 行)",
		#ends == 5 and spread <= 1.5, true)
	-- 左上: PB Stats・Tick Data・Air Guard Gaps・Recording GUI がすべて OFF
	-- (本人、2026-10-01: PB Statsを出していない場合は左上に)
	calls, boxes, images = {}, {}, {}
	globals.options.display_pb_stats = false
	hud.draw_gc_stats()
	local t = boxes[1] or { x1 = 0, y1 = 0, x2 = 999, y2 = 0 }
	local trace_x = tonumber(hsrc:match("local _x, _y = (%d+), blocks_top%(%)" .. NL
		.. "\tlocal _t0 = _t.rows%[1%]%.t"))
	want("左上: 画面の左端から", t.x1 >= 0 and t.x1 <= 6, true)
	want("左上: GC Command Trace の箱 (" .. tostring(trace_x and trace_x - 2) .. ") より左で終わる",
		trace_x ~= nil and t.x2 < trace_x - 2, true)
	want("左上: PB Count の行の下 (blocks_top)", t.y1, 37)
	local out2 = {}
	for _, c in ipairs(calls) do
		if c.x < t.x1 or c.x + #c.s * 4.2 > t.x2 + 0.5 or c.y < t.y1 or c.y + 7 > t.y2 + 1 then
			out2[#out2 + 1] = c.s
		end
	end
	want("左上: 文字は全部箱の中", table.concat(out2, ","), "")
	for _, k in ipairs({ "mo_enable_frame_data", "display_air_guard_gap", "display_recording_gui" }) do
		boxes = {}
		globals.options[k] = true
		hud.draw_gc_stats()
		want(k .. " が ON なら右下", boxes[1] ~= nil and boxes[1].x2 == 380, true)
		globals.options[k] = nil
	end
	-- OFF: 描かない。数えるのは続く ([12] で配線を見る)
	calls, boxes = {}, {}
	globals.options.display_gc_stats = false
	hud.draw_gc_stats()
	want("OFF なら何も描かない (ゲージが見える)", #calls + #boxes, 0)
	-- 数え方が止まったら、数字の代わりにそう出す
	globals.options.display_gc_stats = true
	globals.gc_stats_error = "boom"
	hud.draw_gc_stats()
	want("エラーなら止まったと出す", calls[1] and calls[1].s, "GC Stats stopped: error")
	globals = saved
end

print("")
print("[12] 配線 - フック・メインスクリプト・メニュー・既定値")
do
	-- フックの中、gct_tick の後、p1_gc_state を進める前
	local h = src:find("memory.registerexec(0x0221CC, function()", 1, true)
	local a = src:find("gct_tick(_gc)" .. NL, h or 1, true)
	local c = src:find('require("./scripts/gcStats").on_tick', h or 1, true)
	local e = src:find("p1_gc_state = _gc", h or 1, true)
	want("P1 のフックで gct_tick の後、状態を進める前", h ~= nil and a ~= nil and c ~= nil
		and e ~= nil and h < a and a < c and c < e, true)
	local args = src:sub(c or 1, (c or 1) + 260)
	want("引数の順", args:find("globals.p1_tick_seq, _gc, _gct, gct.prog, gct.step,", 1, true) ~= nil, true)
	want("$05 と $120 を読む", args:find("memory.readbyte(0xFF8405), memory.readbyte(0xFF8520)", 1, true) ~= nil, true)
	want("pcall で守る", args:find("pcall(", 1, true) ~= nil or src:sub((c or 1) - 40, c or 1):find("pcall(", 1, true) ~= nil, true)
	-- フックの中からファイルは書けない (CLAUDE.md)
	local g = io.open("gcStats.lua"):read("*a")
	want("gcStats はファイルを開かない", g:find("io%.") == nil, true)

	local m = io.open("vsav_training_master_script.lua"):read("*a")
	local ra = m:find("savestate.registerload(function(slot)", 1, true)
	local rb = m:find(NL .. "\tend)", ra or 1, true)
	want("ロードで捨てる", ra ~= nil and rb ~= nil
		and m:sub(ra, rb):find("gcStatsModule.discard()", 1, true) ~= nil, true)
	want("位置を戻している間は捨てる",
		m:find("if positionModule.busy() then gcStatsModule.discard() end", 1, true) ~= nil, true)
	local p = io.open("position.lua"):read("*a")
	want("position.lua に busy", p:find('["busy"] = function() return steps ~= nil or camera_restore_busy() end', 1, true) ~= nil, true)

	local menu = io.open("menu.lua"):read("*a")
	local sa = menu:find('checkbox_menu_item("Show GC Stats", training_settings, "display_gc_stats", false,', 1, true)
	want("Trainer に Show GC Stats", sa ~= nil, true)
	local tr = menu:find('name = "Trainer"', 1, true)
	local an = menu:find('name = "Analysis"', 1, true)
	want("Trainer タブの中", tr ~= nil and an ~= nil and sa ~= nil and tr < sa and sa < an, true)
	local desc = menu:sub(sa or 1, menu:find(NL, sa or 1, true))
	for _, w in ipairs({ "1P / 2P", "on the left, facing right, is 1P", "Passes only",
	                     "Pass:", "Fail:",
	                     "GC t:", "Input t:", "Smaller is a faster GC.",
	                     "Off and on starts at 0." }) do
		want("説明に: " .. w, desc:find(w, 1, true) ~= nil, true)
	end
	want("説明に: 99999 で止まる (PB Stats と同じ)", desc:find("Counts stop at 99999.", 1, true) ~= nil, true)
	-- キャラ選択に戻れば消えるので、Reset の行は置かない (本人、2026-10-01)
	want("Reset GC Stats の行は無い", menu:find("Reset GC Stats", 1, true), nil)
	want("消すのはキャラ選択と OFF の 2 か所", select(2, m:gsub("gcStatsModule%.clear%(%)", "")), 2)
	want("OFF の間は毎フレーム 0 に戻す (PB Stats と同じ)",
		m:find("if globals.options.display_gc_stats ~= true then gcStatsModule.clear() end", 1, true) ~= nil, true)
	local pbo = m:find("if globals.options.display_pb_stats == false then", 1, true)
	local gco = m:find("if globals.options.display_gc_stats ~= true then", 1, true)
	want("PB Stats の OFF のすぐ後", pbo ~= nil and gco ~= nil and gco > pbo and gco - pbo < 400, true)

	local cfg = io.open("config.lua"):read("*a")
	want("既定は OFF", cfg:find("display_gc_stats = false,", 1, true) ~= nil, true)
	local hsrc = io.open("hud.lua"):read("*a")
	local gr = hsrc:find('["guiRegister"] = function()', 1, true)
	want("毎フレーム描く", gr ~= nil and hsrc:find("draw_gc_stats()", gr, true) ~= nil, true)
end

print("")
print("[12b] Input t と 3 区間は同じ成功から (2026-10-02)")
do
	-- t1 t2 t3 = 3 つの方向を受け付けたティック、ts = 成立。区間は t2-t1、t3-t2、
	-- ts-t3、Input t は ts-t1。4 つとも同じ成功だけから足すので、丸め前の 3 区間
	-- の平均の合計は Input t の平均に一致する。
	local function close(a, b) return math.abs(a - b) < 1e-9 end
	local function raw(i)
		local s = M.state()[i]
		if s.n_in == 0 then return nil end
		return s.sum_st[1] / s.n_in, s.sum_st[2] / s.n_in, s.sum_st[3] / s.n_in,
			s.sum_in / s.n_in
	end
	fresh()
	-- 間隔の違う成功を 3 回
	for _, gaps in ipairs({ { 2, 5, 1 }, { 4, 3, 0 }, { 7, 1, 2 } }) do
		block()
		d1() idle(gaps[1] - 1)
		d2() idle(gaps[2] - 1)
		if gaps[3] == 0 then
			-- 最後の方向とボタンが同じティック
			tick({ clock = 0, act = 0x0E, s05 = 0, prog = 0, step = 6 })
			tick({ act = 0 })
		else
			d3() idle(gaps[3] - 1)
			cancel()
		end
	end
	local a1, a2, a3, ain = raw(1)
	want("3 回とも数える", n(1, "pass") .. "/" .. n(1, "n_in"), "3/3")
	want("区間の平均 (丸め前)", string.format("%.4f %.4f %.4f", a1, a2, a3),
		string.format("%.4f %.4f %.4f", 13 / 3, 9 / 3, 3 / 3))
	want("丸め前の合計 = 平均 Input t", close(a1 + a2 + a3, ain), true)
	want("同じティックの最後の方向+ボタンは区間 3 が 0 (合計 3 = 1+0+2)",
		M.state()[1].sum_st[3], 3)

	-- 計測できない成功を混ぜる: 起点が見えない (ロード直後) と、2 つしか方向を
	-- 受け付けていない (段が一度に 2 つ進んだ形。実ログには無い、作った入力)
	d1()
	M.discard()
	idle(1)
	block() d2() d3() cancel()
	block() d1() tick({ prog = 4, step = 6 }) cancel()
	want("計測できない成功も Pass に残る", n(1, "pass"), 5)
	want("Input t と区間の対象は同じ 3 回のまま", n(1, "n_in"), 3)
	want("外した数", M.state().no_input, 2)
	local b1, b2, b3, bin = raw(1)
	want("混ぜても丸め前の合計 = 平均 Input t", close(b1 + b2 + b3, bin), true)
	want("混ぜても値は変わらない", close(bin, ain), true)

	-- 失敗は時間の平均に入らない
	block() d1() d2() expire() run_out() tick({ s05 = 0 })
	want("Fail は 1、平均の対象は 3 のまま", n(1, "fail") .. "/" .. n(1, "n_in"), "1/3")

	-- 失効して入れ直した成功は、成立したコマンドだけで測る。連続ガードの
	-- 途中の失効では Fail を確定しない
	block()
	d1() d2() expire()
	run_out()
	hit_again()
	local r1 = d1() idle(2)
	local r2 = d2() idle(1)
	local r3 = d3()
	local rs = cancel()
	want("途中の失効は Fail にならず、Pass が 1 増える",
		n(1, "pass") .. "/" .. n(1, "fail"), "6/1")
	want("入れ直した方から: Input t の合計が増えた分",
		M.state()[1].sum_in - (13 + 9 + 3), rs - r1)
	want("区間も入れ直した方から", (M.state()[1].sum_st[1] - 13) .. "/"
		.. (M.state()[1].sum_st[2] - 9) .. "/" .. (M.state()[1].sum_st[3] - 3),
		(r2 - r1) .. "/" .. (r3 - r2) .. "/" .. (rs - r3))
	local c1, c2, c3, cin = raw(1)
	want("4 回でも丸め前の合計 = 平均 Input t", close(c1 + c2 + c3, cin), true)

	-- 1P と 2P は混ざらない
	S.side = 0
	block() d1() idle(9) d2() d3() cancel()
	S.side = 1
	want("2P は 2P だけ", n(2, "n_in") .. "/" .. M.state()[2].sum_in, "1/12")
	want("1P は変わらない", n(1, "n_in"), 4)
	local e1, e2, e3, ein = raw(2)
	want("2P も丸め前の合計 = 平均 Input t", close(e1 + e2 + e3, ein), true)
	-- 表示: 丸めた 3 つの和と Input t の表示は、ずれても 0.01 程度
	local st = M.steps()[1]
	local shown = tonumber(st[1]) + tonumber(st[2]) + tonumber(st[3])
	local itxt = tonumber(row(1):match("(%S+)$"))
	want("表示の差は丸めの範囲", math.abs(shown - itxt) <= 0.015 + 1e-9, true)
end

print("")
print("[13] GC Command Trace と同じティックで、Input t がトレースの行と一致する")
do
	-- トレースの区間を取り出して、同じメモリを両方に食わせる。トレースの行は
	-- 間隔の足し算で読むものだが、ここでは最初の方向とボタンの絶対ティックを比べる。
	local s = src:find("-- ------------------------------------------------------- GC COMMAND TRACE", 1, true)
	local e = src:find("-- --------------------------------------------------- END GC COMMAND TRACE", 1, true)
	assert(s and e, "GC COMMAND TRACE の区間が見つからない")
	local BASE, BLK = 0xFF8400, 0x348          -- cid 0x09
	local mem = {}
	memory = { readbyte = function(a) return mem[a] or 0 end,
	           readword = function(a) return mem[a] or 0 end }
	globals = { p1_tick_seq = 0, controlling_p1 = true,
	            match_running = function() return true end,
	            options = { display_gc_stats = true } }
	assert(loadstring(src:sub(s, e - 1) .. NL
		.. "_G.gct_tick = gct_tick" .. NL .. "_G.gct_state = gct" .. NL))()
	M.clear()
	local state, open = "p1_gc_none", nil
	local seq = 500
	local function t(o)
		seq = seq + 1
		globals.p1_tick_seq = seq
		mem[BASE + 0x382] = 0x09
		mem[BASE + BLK], mem[BASE + BLK + 1] = o.prog, o.step
		mem[BASE + 0x05], mem[BASE + 0x06], mem[BASE + 0x07] = o.s05, o.s06 or 0, 0
		local gc = gc_next_state(state, o.clock, o.s06 or 0)
		local k
		k, open = gc_tick_count(gc, open, seq)
		gct_tick(gc)
		M.on_tick(seq, gc, k, gct_state.prog, gct_state.step, o.s05, 1)
		state = gc
	end
	-- 前もって 6、接触、受付、2、失効、入れ直し 6 2 3、成立 (失効と入れ直しを跨ぐ)
	t({ prog = 2, step = 2, s05 = 0, clock = 0 })
	t({ prog = 2, step = 2, s05 = 2, clock = 0 })
	t({ prog = 2, step = 4, s05 = 2, clock = 14 })
	t({ prog = 0, step = 4, s05 = 2, clock = 13 })
	t({ prog = 2, step = 2, s05 = 2, clock = 12 })
	t({ prog = 2, step = 4, s05 = 2, clock = 11 })
	t({ prog = 2, step = 4, s05 = 2, clock = 10 })
	t({ prog = 4, step = 6, s05 = 2, clock = 9 })
	t({ prog = 0, step = 6, s05 = 0, clock = 0, s06 = 0x0E })
	local rows = gct_state.rows
	local first, btn = nil, nil
	for _, r in ipairs(rows) do
		if r.k == "dead" then first = nil end
		if r.k == "dir" and first == nil then first = r.t end
		if r.k == "btn" then btn = r.t end
	end
	want("トレースは Success", gct_state.done, "Success")
	want("Pass 1", M.state()[1].pass, 1)
	want("Input t = トレースの最後のコマンドの最初の方向からボタンまで",
		M.state()[1].sum_in, (btn or 0) - (first or 0))
	want("失効の前の 6 からではない", M.state()[1].sum_in, 4)
end

print("")
if fails == 0 then
	print("test_gc_stats ok")
else
	print("test_gc_stats: " .. fails .. " NG")
	os.exit(1)
end
