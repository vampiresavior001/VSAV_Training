-- CHAIN TRAINER (scripts/chainTrainer.lua, 2026-10-14).
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_chain_trainer.lua
--
--   [1] off: nothing kept, nothing drawn
--   [2] a press held through hit stop, taken when it ends: CHAIN 6t (1t is
--       C+1, as AirGap's 1t is the first tick)
--   [3] a press on a judged tick: CHAIN 12t
--   [4] after the window: LATE Nt, counted from the window's last tick
--   [5] two buttons pending: MULTI.  [6] not a chain from that move: NO CHAIN
--   [7] a press before the hit, in the move before it: EARLY. The move's own
--       press is not one
--   [8] rapid, after a hit and out of a whiff.  [9] no press: no row
--   [10] got hit, six lines at most, the other side, a change of character
--   [11] the lines (one glyph per tick, one line a link, as AirGap) and
--        drawing at AirGap's height, right of the game's hit count - under
--        AirGap's lines when both are on
--   [12] the hook-up: chainLog's listener, menu, config, master script; the
--        GC / Seq. Command Trainers hidden while it is on
--   [13] a link: LINK / GAP / GUARD from the other side's state before the
--        hit, counted from the first tick out of the first normal
--   [14] the link window: the last press that lands before the other side's
--        reversal tick (its react + 13 / 18 / 22, or its sig)
--   [15] a link out of a dash attack (D.MP), from the free tick after landing
--        (the landing $06 0x06 / $07 0x04 is free, the dash's own 0x14 / 0x08
--        is not)
--   [16] a hit 10 or more Ticks after the other side could act: a new combo,
--        written from the top
--   [17] the press that started the move is not early - a dash attack's too
--   [18] specials, ES, EX and DF by name: a cancel ends the line, a link into
--        one, and one that hit heads the next line
--   [19] a pursuit (a hit on the other side while it is down) makes no line
--   [20] a special cancel that hit: did it combo, and the last press that would
--   [21] a move in a special's state right after it hit is kept as a line
--   [22] no chain line to the same button (RAPID and LINK stay)
--   [23] a normal's startup: from a press on a free tick to its first
--        contact, the fewest seen, standing and crouching apart - not a chain's
--   [24] a press past the chain window, still in the move, that could have
--        linked: a link line, EARLY Nt/Mt
--   [25] and when it could not, or it is not known: the chain's LATE
--   [26] a hit on or after their reversal Tick (seen, not hit since) is not a
--        combo, though $05 reads 2 there: GAP
--
-- The rows fed in are the ones chainLog.lua makes (test_chain_log.lua); the
-- window is the one measured (VSAV_MEMORY_NOTES, section 14): $169 13..1 over
-- C+1..C+13, hit stop 11 over C+1..C+11.
--
local fails = 0
local function eq(what, got, want)
	if got == want then print("  ok " .. what .. " = " .. tostring(got))
	else
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(want) .. "]")
	end
end
local function slurp(path)
	local fh = io.open(path)
	assert(fh, path .. " が読めない")
	local s = fh:read("*a")
	fh:close()
	return s
end

local ram, regs = {}, {}
memory = {
	readbyte = function(a) return ram[a] or 0 end,
	readword = function(a) return 0 end,
	readdword = function(a) return 0 end,
	getregister = function(name) return regs[name:gsub("^m68000%.", "")] or 0 end,
	registerexec = function() end,
}
emu = { framecount = function() return 0 end }
globals = { options = { chain_trainer = 2 } }
package.loaded["./scripts/chainLog"] = dofile("chainLog.lua")
-- The rows' clock, as the trainer reads it outside the hooks.
local now_tick = 0
package.loaded["./scripts/chainLog"].clock = function() return now_tick end
local T = dofile("chainTrainer.lua")

-- Rows as chainLog makes them. state: $04-$07; 0x00000A00 is $06 = 0x0A.
local NORMAL, IDLE, HIT = 0x02000A02, 0x02000000, 0x02020202
local function contact(tick, str, typ, p, opp05, opp140)
	T.on_row({ kind = "contact", p = p or 1, tick = tick, str = str or 0, typ = typ or 0, air = 0,
	           t169 = 0, hs = 0, edge = 0, held = 0, state = NORMAL, char = 1,
	           opp05 = opp05 or 2, opp140 = opp140 or 0 })
end
local function tick(tick, t169, hs, edge, state, p)
	T.on_row({ kind = "tick", p = p or 1, tick = tick, t169 = t169, hs = hs, edge = edge or 0,
	           held = 0, state = state or NORMAL, air = 0, char = 1, str = 0, typ = 0 })
end
local function check(tick, t169, stage, accept, d0, d1, quiet)
	T.on_row({ kind = "check", p = 1, tick = tick, t169 = t169, hs = 0, edge = 0, held = 0,
	           stage = stage or "rapid_no", accept = accept, d0 = d0, d1 = d1, quiet = quiet,
	           state = NORMAL, air = 0, char = 1, str = 0, typ = 0 })
end
-- The hit at C and its hit stop: C+1..C+11 held, $169 13..3.
local function hit(C, press_at, btn)
	contact(C)
	for n = 1, 11 do
		tick(C + n, 14 - n, 12 - n, (press_at == C + n) and btn or 0)
	end
end
local function last() local r = T._rows() ; return r[#r] end
-- The startups are kept across T.reset() (facts about the moves): each test
-- starts without any.
local function fresh() T.reset() ; T.startup = {} ; globals.options.chain_trainer = 2 ; T.registerAfter() end

-- ---------------------------------------------------------------------------
print("[1] Off")
do
	globals.options.chain_trainer = 1
	T.reset()
	hit(100, 106, 0x0200)
	check(112, 2, "commit", "chain", 0x0200)
	eq("行を持たない", #T._rows(), 0)
	eq("表示しない", T.is_visible(), false)
	eq("P1 は 2", (function() globals.options.chain_trainer = 2 return T.side() end)(), 1)
	eq("P2 は 3", (function() globals.options.chain_trainer = 3 return T.side() end)(), 2)
end

print("[2] ヒットストップ中の押しは溜められ、明けた Tick で成立: CHAIN 6t")
do
	fresh()
	hit(100, 106, 0x0200)
	tick(112, 2, 0)
	check(112, 2, "commit", "chain", 0x0200)
	local r = last()
	eq("1 行", #T._rows(), 1)
	eq("  結果 (1t = C+1、押したのは C+6)", r and r.result, "CHAIN 6t")
	eq("  ラベル", r and (r.src .. " > " .. r.tgt), "LP > MP")
	eq("  0t-10t は held", r and r.band[0] == "held" and r.band[10] == "held", true)
	eq("  11t は judged", r and r.band[11], "judged")
	eq("  -1t (接触の Tick) は帯の外", r and r.band[-1], nil)
	eq("  成立の印は 11t", r and r.accept.t, 11)
end

print("[3] 判定される Tick の押し: CHAIN 12t")
do
	fresh()
	hit(100)
	tick(112, 2, 0, 0x0400)
	check(112, 2, "commit", "chain", 0x0400)
	eq("結果", last() and last().result, "CHAIN 12t")
	eq("ラベル", last() and last().tgt, "HP")
end

print("[4] 窓の後: LATE 2t")
do
	fresh()
	hit(200)
	check(212, 2, "rapid_no", nil, nil, nil, true)
	check(213, 1, "rapid_no", nil, nil, nil, true)
	check(214, 0, "rapid_no", nil, nil, nil, true)
	tick(215, 0, 0, 0x2000)
	check(215, 0, "c1b2_ok")
	eq("まだ閉じない", #T._rows(), 0)
	now_tick = 200 + T.SPAN + 1
	T.registerAfter()
	eq("期限で閉じる", #T._rows(), 1)
	eq("結果 (窓の最後 C+13 から C+15)", last() and last().result, "LATE 2t")
	eq("窓は C+13 まで (0 始まりで 12)", last() and last().window_last, 12)
	now_tick = 0
end

print("[5] 2 種類のボタン: MULTI")
do
	fresh()
	contact(300)
	for n = 1, 11 do
		local e = (n == 5) and 0x2000 or ((n == 7) and 0x4000 or 0)
		tick(300 + n, 14 - n, 12 - n, e)
	end
	check(312, 2, "buttons")
	check(313, 1, "buttons")
	contact(340)              -- the next hit closes it
	eq("結果", T._rows()[1] and T._rows()[1].result, "MULTI")
	eq("ラベルは両方", T._rows()[1] and T._rows()[1].tgt, "MK+HK")
end

print("[6] その技からはつながらない: NO CHAIN")
do
	fresh()
	-- HK into MK: not a chain the mask allows (HK > HK is not shown at all, [22]).
	contact(400, 4, 2)
	for n = 1, 11 do tick(400 + n, 14 - n, 12 - n, (n == 3) and 0x2000 or 0) end
	check(412, 2, "mask")
	contact(450)
	eq("結果", T._rows()[1] and T._rows()[1].result, "NO CHAIN")
	eq("ラベル", T._rows()[1] and (T._rows()[1].src .. " > " .. T._rows()[1].tgt), "HK > MK")
end

print("[7] 当たる前の押し: EARLY。技を出した押しは数えない")
do
	fresh()
	tick(495, 0, 0, 0x0100, IDLE)      -- the LP that starts the move
	tick(499, 0, 0, 0x0200, NORMAL)    -- MP during its startup
	hit(500)
	contact(560)
	eq("結果 (C-1 は 1t の 2 Tick 前)", T._rows()[1] and T._rows()[1].result, "EARLY 2t")
	eq("技を出した LP は入らない", T._rows()[1] and #T._rows()[1].early, 1)
end

print("[8] 連打キャンセル")
do
	fresh()
	hit(600)
	tick(613, 1, 0, 0x0100)
	check(613, 1, "commit", "rapid", 0x0100, 8)
	eq("当たった後: RAPID", last() and last().result, "RAPID")
	eq("  ボタンは D1 のビット (8 = LP)", last() and last().tgt, "LP")
	check(640, 0, "commit", "rapid", 0x0100, 8)
	eq("空振りから: RAPID の行", last() and last().result, "RAPID")
	eq("  メーターは描かない", last() and last().nometer, true)
end

print("[9] 押さなければ行は残らない")
do
	fresh()
	hit(700)
	check(712, 2, "rapid_no", nil, nil, nil, true)
	contact(760)
	eq("行なし", #T._rows(), 0)
	eq("今の接触は測っている", T._cur() ~= nil, true)
end

print("[10] 被弾、6 本まで、相手側、キャラ交代")
do
	fresh()
	hit(800, 805, 0x0200)
	tick(812, 2, 0, 0, HIT)
	eq("被弾: HIT", last() and last().result, "HIT")
	fresh()
	for k = 1, 8 do
		local C = 1000 + k * 50
		hit(C, C + 3, 0x0200)
		check(C + 12, 2, "commit", "chain", 0x0200)
	end
	eq("6 本まで (表示の広さ)", #T._rows(), T.MAX_ROWS)
	local before = #T._rows()
	contact(2000, 0, 0, 2)
	tick(2001, 13, 11, 0x0200, NORMAL, 2)
	eq("P1 を測っているとき P2 の行は入らない", #T._rows(), before)
	T.on_row({ kind = "contact", p = 1, tick = 2100, str = 0, typ = 0, air = 0, t169 = 0, hs = 0,
	           edge = 0, held = 0, state = NORMAL, char = 5 })
	eq("キャラが変わったら消す", #T._rows(), 0)
	fresh()
	hit(2200, 2203, 0x0200)
	check(2212, 2, "commit", "chain", 0x0200)
	globals.options.chain_trainer = 3
	T.registerAfter()
	eq("測る側を変えたら消す", #T._rows(), 0)
	globals.options.chain_trainer = 1
	T.registerAfter()
	globals.options.chain_trainer = 2
end

-- ---------------------------------------------------------------------------
print("[11] 行の文字 (1 Tick 1 文字、1 本 1 行) と描画")
do
	local function text(cells) local o = {} for _, c in ipairs(cells) do o[#o + 1] = c[1] end return table.concat(o) end
	local boxes, texts = {}, {}
	gui = {
		box = function(x1, y1, x2, y2) boxes[#boxes + 1] = { x1, y1, x2, y2 } end,
		text = function(x, y, s, c) texts[#texts + 1] = { x, y, s, c } end,
	}
	fresh()
	hit(3000, 3006, 0x0200)
	check(3012, 2, "commit", "chain", 0x0200)
	hit(3050)
	check(3062, 2, "rapid_no", nil, nil, nil, true)
	check(3063, 1, "rapid_no", nil, nil, nil, true)
	tick(3065, 0, 0, 0x2000)
	check(3065, 0, "c1b2_ok")
	contact(3100)
	local L = T.lines()
	eq("見出し", L[1] and L[1][1][1], "Chain P1")
	-- label, a space, the ticks from one column, then the result: as AirGap
	eq("1 本目: - が溜める Tick、押した P、成立の |", L[2] and text(L[2]), "LP > MP -----P-----|    CHAIN 6t")
	eq("2 本目: = が判定の Tick、. が窓の外、K", L[3] and text(L[3]), "LP > MK -----------==.K LATE 2t")
	local function cell(l, ch) for _, c in ipairs(l) do if c[1] == ch then return c end end end
	eq("  P は中の色", L[2] and cell(L[2], "P")[2], "#FFFF00")
	eq("  成立は緑", L[2] and L[2][#L[2]][2], "#00FF00")
	eq("  遅れは赤", L[3] and L[3][#L[3]][2], "#FF0000")
	T.draw()
	local minx, maxx, miny, maxy = 999, 0, 999, 0
	for _, b in ipairs(boxes) do
		minx = math.min(minx, b[1]); maxx = math.max(maxx, b[3]); miny = math.min(miny, b[2]); maxy = math.max(maxy, b[4])
	end
	for _, t in ipairs(texts) do
		minx = math.min(minx, t[1]); maxx = math.max(maxx, t[1] + math.ceil(#t[3] * 4.2))
	end
	eq("AirGap と同じ高さで、コンボ数の右 (x 104, y 37)", minx == 102 and miny == 36, true)
	eq("右は P2 の入力列 (353) より左", maxx <= 352, true)
	eq("高さは見出し + 行の数 x 8", maxy, 37 + #L * 8)
	-- The widest a line gets: an air label, the whole bar, the longest result.
	local wide = { src = "J.MP", tgt = "J.HP", band = {}, presses = { { t = 30, b = 0x0400 } }, early = {}, result = "CHAIN 22t" }
	eq("いちばん長い行でも P2 の入力列 (353) より左", T.X + (#"J.MP > J.HP" + 1 + T.MAX_BAR + 1 + #"CHAIN 22t") * 4.2 + 2 <= 352, true)
	eq("目盛りより先は > で止める", #T.bar_cells(wide) == T.MAX_BAR and T.bar_cells(wide)[T.MAX_BAR][1], ">")
	-- Under AirGap's lines when both are on.
	boxes, texts = {}, {}
	globals.options.display_air_guard_gap = true
	package.loaded["./scripts/airGuardGap"] = { lines = function() return { {}, {}, {} } end }
	T.draw()
	local my = 999
	for _, b in ipairs(boxes) do my = math.min(my, b[2]) end
	eq("AirGap も ON なら、その 3 行の下 (y 37 + 24 + 3)", my, 37 + 3 * 8 + 3 - 1)
	globals.options.display_air_guard_gap = nil
	package.loaded["./scripts/airGuardGap"] = nil
	boxes, texts = {}, {}
	globals.options.chain_trainer = 1
	T.draw()
	eq("Off では何も描かない", #boxes + #texts, 0)
	globals.options.chain_trainer = 2
end

-- ---------------------------------------------------------------------------
print("[12] 組み込み")
do
	local L = package.loaded["./scripts/chainLog"]
	globals.options.knockdown_logger_enable = false
	local got = 0
	L.set_listener(function() got = got + 1 end, function() return true end)
	regs.a6 = 0xFF8400
	ram[0xFF8400 + 0x169] = 13
	local hooks = {}
	memory.registerexec = function(pc, fn) hooks[pc] = fn end
	L.registerStart()
	hooks[L.PC.tick]()
	hooks[L.PC.entry]() ; hooks[L.PC.done]()
	eq("Knockdown Logger OFF でもトレーナーには渡す (tick + 静かな呼び出し)", got, 2)
	eq("ファイル用には積まない", #L._rows(), 0)
	L.set_listener(nil, nil)

	local ms = slurp("vsav_training_master_script.lua")
	eq("起動時に require", ms:find('\nlocal chainTrainerModule = require "./scripts/chainTrainer"', 1, true) ~= nil, true)
	eq("registerStart は chainLog の後", (ms:find("\tchainTrainerModule.registerStart()\n", 1, true) or 0)
	   > (ms:find("\tchainLogModule.registerStart()\n", 1, true) or 1e9), true)
	eq("registerAfter", ms:find("\tchainTrainerModule.registerAfter()\n", 1, true) ~= nil, true)
	eq("ステートロードで消す", ms:find("\t\tchainTrainerModule.reset()\n", 1, true) ~= nil, true)
	eq("描画は pcall", ms:find("pcall(chainTrainerModule.draw)", 1, true) ~= nil, true)

	local menu = slurp("menu.lua")
	local row = 'list_menu_item("Chain Trainer", training_settings, "chain_trainer", { "Off", "P1", "P2" }, 1, "'
	local at = menu:find(row, 1, true)
	eq("Trainer タブの行", at ~= nil, true)
	local agg = menu:find('checkbox_menu_item("Show Air Guard Gaps"', 1, true)
	eq("Show Air Guard Gaps のすぐ上", at ~= nil and agg ~= nil and at < agg
	   and not menu:sub(at, agg):find("_menu_item(", #row, true), true)
	local hs = at and (at + #row)
	local he = hs and menu:find('"),', hs, true)
	local help = hs and he and menu:sub(hs, he - 1) or ""
	local n, widest = 0, 0
	for line in (help:gsub("\\n", "\n") .. "\n"):gmatch("(.-)\n") do
		n = n + 1
		if #line > widest then widest = #line end
	end
	eq("説明は 6 行", n, 6)
	eq("説明の行は 79 文字以内", widest > 0 and widest <= 79, true)
	eq("既定は Off (1)", dofile("config.lua").default_training_settings.chain_trainer, 1)
	-- From x 104 its lines reach their boxes: hidden while it is on.
	local hud = slurp("hud.lua")
	local gct = hud:find("local function draw_gc_command_trace()", 1, true)
	eq("ON の間 GC Command Trainer を描かない", gct ~= nil
	   and hud:find('package.loaded["./scripts/chainTrainer"]', gct, true) ~= nil, true)
	local ct = slurp("commandTrainer.lua")
	local cd = ct:find("function M.draw()", 1, true)
	eq("ON の間 Seq. Command Trainer を描かない", cd ~= nil
	   and ct:find('package.loaded["./scripts/chainTrainer"]', cd, true) ~= nil, true)
end

-- ---------------------------------------------------------------------------
print("[13] 目押し: 2 発目の直前の相手の状態で LINK / GAP / GUARD")
do
	local IDLE_ = 0x02000000
	local function link_case(opp05, opp140)
		fresh()
		hit(4000)                              -- LP hits; its chain line has no press
		tick(4020, 0, 0, 0, IDLE_)             -- the LP is over: 1t
		tick(4022, 0, 0, 0x0100, IDLE_)        -- LP pressed on 3t
		tick(4023, 0, 0, 0, NORMAL)            -- the second LP starts
		contact(4027, 0, 0, 1, opp05, opp140)  -- and hits
		return last()
	end
	local r = link_case(2, 0)
	eq("やられ中に当たった: LINK 3t", r and r.result, "LINK 3t")
	eq("  ラベル", r and (r.src .. " > " .. r.tgt), "LP > LP")
	eq("  緑", r and T.lines()[2][#T.lines()[2]][2], "#00FF00")
	local function text(cells) local o = {} for _, c in ipairs(cells) do o[#o + 1] = c[1] end return table.concat(o) end
	eq("  目盛り: 1t から押した Tick まで", text(T.bar_cells(r)), "..P")
	eq("動けるようになってから当たった: GAP 3t", link_case(0, 0).result, "GAP 3t")
	eq("ガード中に当たった: GUARD 3t", link_case(2, 0x02).result, "GUARD 3t")
	eq("ガード (0x12) も GUARD", link_case(2, 0x12).result, "GUARD 3t")
	-- A cancel is not a link.
	fresh()
	hit(4100, 4105, 0x0200)
	check(4112, 2, "commit", "chain", 0x0200)
	tick(4113, 1, 0, 0, NORMAL)
	contact(4118, 2, 0)
	eq("キャンセルの次の当たりは目押しではない", last() and last().link, nil)
	-- Too long after: not a link.
	fresh()
	hit(4200)
	tick(4220, 0, 0, 0, IDLE_)
	tick(4300, 0, 0, 0x0100, IDLE_)
	tick(4301, 0, 0, 0, NORMAL)
	contact(4305)
	eq("60 Tick より後は目押しにしない", last() and last().link, nil)
end

print("[14] 目押しの猶予: 相手のリバーサル Tick までに当たる最後の押し (/Mt)")
do
	local IDLE_ = 0x02000000
	local function react(tick, s59, s140)
		T.on_row({ kind = "react", p = 2, tick = tick, s59 = s59, s140 = s140 or 0, char = 5, state = 0x02020200 })
	end
	local function sig(tick) T.on_row({ kind = "sig", p = 2, tick = tick, char = 5, state = 0x02020400 }) end
	-- LP hits at 5000; its stun's freeze ends at 5013, so R = 5013 + 13 = 5026.
	-- The LP is over at 5020 (1t). The next press, 2 Ticks to its hit.
	local function case(press, opp05, with_sig)
		fresh()
		hit(5000)
		react(5013, 0)
		tick(5020, 0, 0, 0, IDLE_)
		tick(press, 0, 0, 0x0100, IDLE_)
		tick(press + 1, 0, 0, 0, NORMAL)
		if with_sig then sig(5026) end
		contact(press + 2, 0, 0, 1, opp05, 0)
		return last()
	end
	local function text(cells) local o = {} for _, c in ipairs(cells) do o[#o + 1] = c[1] end return table.concat(o) end
	local r = case(5022, 2)
	eq("3t に押して当たった: LINK 3t/4t (R 5026 - 2 - 5020)", r and r.result, "LINK 3t/4t")
	eq("  目盛り: 4t まで = 、押したのは 3t", text(T.bar_cells(r)), "==P=")
	r = case(5025, 0)
	eq("6t は遅い: GAP 6t/4t", r and r.result, "GAP 6t/4t")
	eq("  目盛り: 4t まで = 、. のあと 6t", text(T.bar_cells(r)), "====.P")
	r = case(5025, 0, true)
	eq("相手が実際に復帰した Tick (sig) でも同じ", r and r.result, "GAP 6t/4t")
	-- Medium: 18 from the react.
	fresh()
	hit(5100)
	react(5113, 1)
	tick(5120, 0, 0, 0, IDLE_)
	tick(5125, 0, 0, 0x0200, IDLE_)
	tick(5126, 0, 0, 0, NORMAL)
	contact(5128, 2, 0, 1, 2, 0)
	eq("中 (+18): LINK 6t/8t (5131 - 3 - 5120)", last() and last().result, "LINK 6t/8t")
	-- The game and the window disagree: the window is not shown.
	r = case(5025, 2)
	eq("当たったのに窓の外: /Mt を出さない", r and r.result, "LINK 6t")
	eq("  食い違いの印", r and r.mismatch, true)
	-- No react from a ground hit stun (a knockdown, say): no window.
	fresh()
	hit(5200)
	react(5213, 0, 0x0A)
	tick(5220, 0, 0, 0, IDLE_)
	tick(5222, 0, 0, 0x0100, IDLE_)
	tick(5223, 0, 0, 0, NORMAL)
	contact(5224, 0, 0, 1, 2, 0)
	eq("地上のやられ以外は窓を出さない", last() and last().result, "LINK 3t")
	-- Far past the window: the next attack, not a missed link.
	r = case(5020 + 3 + T.LINK_LATE_MAX, 0)
	eq("最後の押しより 10 Tick 以上遅いのは目押しの行にしない", r and r.link, nil)
	r = case(5020 + 2 + T.LINK_LATE_MAX, 0)
	eq("  9 Tick 遅れまでは GAP の行 (13t は 4t の 9 Tick 後)", r and r.result, "GAP " .. (3 + T.LINK_LATE_MAX) .. "t/4t")
end

print("[15] ダッシュ中の技からの目押し: 着地して動けるようになった Tick が 1t")
do
	-- LAND: the dash's own landing ($06 0x14 / $07 0x08) - still in the move
	-- (v11.7.25.2_26: 23 of 23 presses there started nothing).
	local DASH, LAND, IDLE_ = 0x02001404, 0x02001408, 0x02000000
	local function react(tick, s59) T.on_row({ kind = "react", p = 2, tick = tick, s59 = s59, s140 = 0, char = 5, state = 0x02020200 }) end
	fresh()
	-- D.MP hits at 6000 inside the dash ($06 0x14), in the air.
	T.on_row({ kind = "contact", p = 1, tick = 6000, str = 2, typ = 0, air = 1, t169 = 0, hs = 0, edge = 0,
	           held = 0, state = DASH, char = 1, opp05 = 2, opp140 = 0 })
	react(6013, 1)                           -- medium: R = 6013 + 18 = 6031
	T.on_row({ kind = "tick", p = 1, tick = 6014, t169 = 0, hs = 0, edge = 0, held = 0, state = DASH, air = 1, char = 1 })
	T.on_row({ kind = "tick", p = 1, tick = 6018, t169 = 0, hs = 0, edge = 0, held = 0, state = LAND, air = 0, char = 1 })
	T.on_row({ kind = "tick", p = 1, tick = 6022, t169 = 0, hs = 0, edge = 0, held = 0, state = IDLE_, air = 0, char = 1 })
	T.on_row({ kind = "tick", p = 1, tick = 6024, t169 = 0, hs = 0, edge = 0x0100, held = 0, state = IDLE_, air = 0, char = 1 })
	T.on_row({ kind = "tick", p = 1, tick = 6025, t169 = 0, hs = 0, edge = 0, held = 0, state = NORMAL, air = 0, char = 1 })
	contact(6027, 0, 0, 1, 2, 0)
	local r = last()
	eq("ラベルは D.MP > LP", r and (r.src .. " > " .. r.tgt), "D.MP > LP")
	-- 1t = 6022 (the landing is still in the move); 3t; d = 3; 6031 - 3 - 6022 = 6.
	eq("着地のあと動ける Tick から数える: LINK 3t/6t", r and r.result, "LINK 3t/6t")
	-- The landing after it, $06 0x06 / $07 0x04, is free from its first tick:
	-- Felicia's D.MP > crouching LP (v11.7.25.2_26, 13 of 13 presses there
	-- started a move; user: "ダッシュMPからしゃがみ小Pがつながったケース").
	fresh()
	T.on_row({ kind = "contact", p = 1, tick = 6000, str = 2, typ = 0, air = 1, t169 = 0, hs = 0, edge = 0,
	           held = 0, state = DASH, char = 1, opp05 = 2, opp140 = 0 })
	react(6013, 1)                           -- R = 6031
	T.on_row({ kind = "tick", p = 1, tick = 6014, t169 = 0, hs = 0, edge = 0, held = 0, state = DASH, air = 1, char = 1 })
	T.on_row({ kind = "tick", p = 1, tick = 6018, t169 = 0, hs = 0, edge = 0, held = 0, state = LAND, air = 0, char = 1 })
	T.on_row({ kind = "tick", p = 1, tick = 6022, t169 = 0, hs = 0, edge = 0x0100, held = 0, state = 0x02000604, air = 0, char = 1 })
	T.on_row({ kind = "tick", p = 1, tick = 6023, t169 = 0, hs = 0, edge = 0, held = 0, state = NORMAL, air = 0, char = 1 })
	contact(6026, 0, 0, 1, 2, 0)
	local lt = false
	for _, x in ipairs(T._rows()) do if (x.result or ""):sub(1, 4) == "LATE" then lt = true end end
	eq("着地 (0x06 / 0x04) の最初の Tick の押しは D.MP の LATE にしない", lt, false)
	-- 1t = 6022, pressed on it; d = 4; 6031 - 4 - 6022 = 5.
	eq("  D.MP > LP LINK 1t/5t", last() and (last().src .. " > " .. last().tgt .. " " .. last().result), "D.MP > LP LINK 1t/5t")
	-- Before the jump leaves the ground ($07 0x02) it is not free.
	eq("  跳ぶ前の 0x06 / 0x02 は動ける Tick ではない", (function()
		fresh()
		hit(6050)
		T.on_row({ kind = "tick", p = 1, tick = 6070, t169 = 0, hs = 0, edge = 0, held = 0, state = 0x02000602, air = 0, char = 1 })
		T.on_row({ kind = "tick", p = 1, tick = 6072, t169 = 0, hs = 0, edge = 0x0100, held = 0, state = 0x02000602, air = 0, char = 1 })
		T.on_row({ kind = "tick", p = 1, tick = 6073, t169 = 0, hs = 0, edge = 0, held = 0, state = NORMAL, air = 0, char = 1 })
		contact(6076, 0, 0, 1, 2, 0)
		return last() and last().link
	end)(), nil)
	-- Walking counts as free too.
	fresh()
	hit(6100)
	T.on_row({ kind = "tick", p = 1, tick = 6120, t169 = 0, hs = 0, edge = 0, held = 0, state = 0x02000402, air = 0, char = 1 })
	tick(6122, 0, 0, 0x0100, 0x02000402)
	tick(6123, 0, 0, 0, NORMAL)
	contact(6125, 0, 0, 1, 2, 0)
	eq("歩いていても動ける Tick ($06 0x04)", last() and last().result, "LINK 3t")
	-- Crouching counts as free too ($06 0x02 with $05 0): not the move's late press.
	fresh()
	hit(6200)
	tick(6220, 0, 0, 0, 0x02000000)
	tick(6223, 0, 0, 0, 0x02000202)            -- crouching
	tick(6224, 0, 0, 0x2000, 0x02000202)       -- MK pressed from the crouch
	tick(6225, 0, 0, 0, NORMAL)
	contact(6229, 2, 2, 1, 2, 0)
	local lt = false
	for _, x in ipairs(T._rows()) do if (x.result or ""):sub(1, 4) == "LATE" then lt = true end end
	eq("しゃがみ ($06 0x02) からの押しは前の技の LATE にしない", lt, false)
	eq("  目押しの行: LP > MK LINK 5t", last() and (last().src .. " > " .. last().tgt .. " " .. last().result), "LP > MK LINK 5t")
	-- The move over, a jump and a J.MK: not the move's late press.
	fresh()
	hit(6300)
	tick(6320, 0, 0, 0, 0x02000000)            -- free: the LP is over
	T.on_row({ kind = "tick", p = 1, tick = 6321, t169 = 0, hs = 0, edge = 0, held = 0, state = 0x02000600, air = 0, char = 1 })
	T.on_row({ kind = "tick", p = 1, tick = 6326, t169 = 0, hs = 0, edge = 0x2000, held = 0, state = 0x02000602, air = 1, char = 1 })
	contact(6400)
	local late = false
	for _, x in ipairs(T._rows()) do if (x.result or ""):sub(1, 4) == "LATE" then late = true end end
	eq("技が終わってからの空中の押し (J.MK) は LATE にしない", late, false)
end

print("[16] 相手が動けるようになって 10 Tick 以上あいた当たりは、1 行目から")
do
	local function sig(tick) T.on_row({ kind = "sig", p = 2, tick = tick, char = 5, state = 0x02020400 }) end
	fresh()
	hit(7000, 7006, 0x0200)
	check(7012, 2, "commit", "chain", 0x0200)
	eq("1 本ある", #T._rows(), 1)
	sig(7040)
	contact(7049)                            -- 9 Ticks after: the same combo
	eq("9 Tick 後の当たりでは消さない", #T._rows(), 1)
	fresh()
	hit(7100, 7106, 0x0200)
	check(7112, 2, "commit", "chain", 0x0200)
	sig(7140)
	contact(7150)                            -- 10 Ticks after: a new combo
	eq("10 Tick 後の当たりで消して 1 行目から", #T._rows(), 0)
	-- Inside a combo the other side never recovers: never cleared.
	fresh()
	hit(7200, 7206, 0x0200)
	check(7212, 2, "commit", "chain", 0x0200)
	contact(7300)
	eq("相手が復帰していなければ消さない", #T._rows(), 1)
end

print("[17] 技を出した押しは「早すぎた押し」にしない (ダッシュ攻撃も)")
do
	local DASH = 0x02001400
	local function row(t) t.p = 1 ; t.char = 1 ; t.held = 0 ; t.t169 = t.t169 or 0 ; t.hs = 0 ; t.air = t.air or 0
		t.edge = t.edge or 0 ; t.str = t.str or 0 ; t.typ = t.typ or 0 ; T.on_row(t) end
	-- Bishamon: in the dash, LK pressed; the dash attack starts the next tick
	-- ($105 rises inside the dash); it hits; nothing else is pressed.
	fresh()
	row({ kind = "tick", tick = 8180, state = 0x02000000 })
	row({ kind = "tick", tick = 8190, state = DASH, f105 = 0 })
	row({ kind = "tick", tick = 8195, state = DASH, f105 = 0, edge = 0x1000 })
	row({ kind = "tick", tick = 8196, state = DASH, f105 = 1, typ = 2 })
	T.on_row({ kind = "contact", p = 1, tick = 8200, str = 0, typ = 2, air = 0, t169 = 0, hs = 0, edge = 0,
	           held = 0, state = DASH, char = 1, opp05 = 2, opp140 = 0, f105 = 1 })
	contact(8260)
	eq("D.LK を出した LK は EARLY にならない (行が残らない)", #T._rows(), 0)
	-- A press after the move began is early, as before.
	fresh()
	row({ kind = "tick", tick = 8290, state = DASH, f105 = 0 })
	row({ kind = "tick", tick = 8295, state = DASH, f105 = 0, edge = 0x1000 })
	row({ kind = "tick", tick = 8296, state = DASH, f105 = 1, typ = 2 })
	row({ kind = "tick", tick = 8298, state = DASH, f105 = 1, typ = 2, edge = 0x0100 })
	T.on_row({ kind = "contact", p = 1, tick = 8300, str = 0, typ = 2, air = 0, t169 = 0, hs = 0, edge = 0,
	           held = 0, state = DASH, char = 1, opp05 = 2, opp140 = 0, f105 = 1 })
	contact(8360)
	eq("技が始まったあとの LP は EARLY (C-2 は 1t の 3 Tick 前)", T._rows()[1] and T._rows()[1].result, "EARLY 3t")
	eq("  ラベルは D.LK > LP", T._rows()[1] and (T._rows()[1].src .. " > " .. T._rows()[1].tgt), "D.LK > LP")
	-- $1B8 moving is a start too (Zabel's dash raises $105 by itself).
	fresh()
	row({ kind = "tick", tick = 8390, state = DASH, f105 = 1, s1b8 = 4 })
	row({ kind = "tick", tick = 8395, state = DASH, f105 = 1, s1b8 = 4, edge = 0x1000 })
	row({ kind = "tick", tick = 8396, state = DASH, f105 = 1, s1b8 = 5, typ = 2 })
	T.on_row({ kind = "contact", p = 1, tick = 8400, str = 0, typ = 2, air = 0, t169 = 0, hs = 0, edge = 0,
	           held = 0, state = DASH, char = 1, opp05 = 2, opp140 = 0, f105 = 1, s1b8 = 5 })
	contact(8460)
	eq("$1B8 が動いた開始でも、その前の押しは数えない", #T._rows(), 0)
end

print("[18] 必殺技 (SP)・ES・EX・DF を名前で")
do
	local function text(cells) local o = {} for _, c in ipairs(cells) do o[#o + 1] = c[1] end return table.concat(o) end
	local SPS, ESS, IDLE_ = 0x02000E00, 0x02001000, 0x02000000
	-- LP hits at 9000; a special's button on 9008 (in the stop), and the
	-- special out once the stop is over, on 9012 ($06 0x0E).
	fresh()
	hit(9000, 9008, 0x0400)
	tick(9012, 2, 0, 0, SPS)
	local r = last()
	eq("通常技からのキャンセル: LP > SP", r and (r.src .. " > " .. r.tgt), "LP > SP")
	eq("  結果は SP と押した Tick (C+8 は 8t)", r and r.result, "SP 8t")
	eq("  帯は描かない。押した P と出た |", text(T.bar_cells(r)), ".......P...|")
	eq("  緑", T.lines()[2][#T.lines()[2]][2], "#00FF00")
	-- ES.
	fresh()
	hit(9100, 9105, 0x0300)
	tick(9112, 2, 0, 0, ESS)
	eq("ES: MP+LP の ES", last() and last().src .. " > " .. last().tgt .. " " .. last().result, "LP > ES ES 5t")
	-- After the normal ended: a link into a special.
	fresh()
	hit(9200)
	tick(9220, 0, 0, 0, IDLE_)
	tick(9222, 0, 0, 0x0400, IDLE_)
	tick(9223, 0, 0, 0, SPS)
	T.on_row({ kind = "contact", p = 1, tick = 9226, str = 4, typ = 0, air = 0, t169 = 0, hs = 0, edge = 0,
	           held = 0, state = SPS, char = 1, opp05 = 2, opp140 = 0 })
	eq("終わってからの必殺技は目押しの行: LP > SP LINK 3t", last() and (last().src .. " > " .. last().tgt .. " " .. last().result), "LP > SP LINK 3t")
	-- A special that hit names the next line.
	-- A special's hit opens no chain line: a press during it is nothing's early.
	eq("必殺技の当たりではチェーンの行を開かない", T._cur(), nil)
	tick(9240, 0, 0, 0x0100, SPS)
	T.on_row({ kind = "contact", p = 1, tick = 9245, str = 4, typ = 0, air = 0, t169 = 0, hs = 0, edge = 0,
	           held = 0, state = SPS, char = 1, opp05 = 2, opp140 = 0 })
	contact(9300)
	local early = false
	for _, x in ipairs(T._rows()) do if (x.result or ""):sub(1, 5) == "EARLY" then early = true end end
	eq("  必殺技の途中の押しは EARLY にならない", early, false)
	-- It is still a link's start.
	fresh()
	T.on_row({ kind = "contact", p = 1, tick = 9400, str = 4, typ = 0, air = 0, t169 = 0, hs = 0, edge = 0,
	           held = 0, state = SPS, char = 1, opp05 = 2, opp140 = 0 })
	tick(9401, 0, 0, 0, SPS)                -- still in the special
	tick(9420, 0, 0, 0, IDLE_)
	tick(9421, 0, 0, 0x0100, IDLE_)
	tick(9422, 0, 0, 0, NORMAL)
	contact(9424, 0, 0, 1, 2, 0)
	eq("必殺技のあとの目押し: SP > LP LINK 2t", last() and (last().src .. " > " .. last().tgt .. " " .. last().result), "SP > LP LINK 2t")
end

print("[19] 追い打ち (ダウン中の相手への当たり) は行にしない")
do
	local ESS, PURSUIT = 0x02001000, 0x02000E00
	fresh()
	hit(9500, 9505, 0x0300)
	tick(9510, 2, 0, 0, ESS)                 -- MK > ES
	local n = #T._rows()
	-- the ES hits and knocks down; the pursuit's button, then the pursuit
	T.on_row({ kind = "contact", p = 1, tick = 9512, str = 0, typ = 0, air = 0, t169 = 0, hs = 0, edge = 0,
	           held = 0, state = ESS, char = 1, opp05 = 2, opp140 = 0 })
	tick(9560, 0, 0, 0x0100, ESS)
	T.on_row({ kind = "tick", p = 1, tick = 9561, t169 = 0, hs = 0, edge = 0, held = 0, state = PURSUIT, air = 1, char = 1 })
	T.on_row({ kind = "contact", p = 1, tick = 9575, str = 0, typ = 0, air = 1, t169 = 0, hs = 0, edge = 0,
	           held = 0, state = PURSUIT, air = 1, char = 1, opp05 = 2, opp140 = 0x0A })
	contact(9640)
	local found = false
	for _, r in ipairs(T._rows()) do if r.src == "SP" or (r.result or ""):sub(1, 5) == "EARLY" then found = true end end
	eq("追い打ちの行 (SP > LP EARLY) は出ない", found, false)
	eq("ES の行は残る", T._rows()[n] and T._rows()[n].result, "ES 5t")
	eq("追い打ちのあとは測っていない", T._cur() ~= nil and T._cur().C == 9640, true)
end

print("[20] 必殺技キャンセルがつながったか: コンボになる最後の押し (/Mt)")
do
	local SPS = 0x02000E00
	local function text(cells) local o = {} for _, c in ipairs(cells) do o[#o + 1] = c[1] end return table.concat(o) end
	local function react(tick, s59) T.on_row({ kind = "react", p = 2, tick = tick, s59 = s59, s140 = 0, char = 5, state = 0x02020200 }) end
	local function sig(tick) T.on_row({ kind = "sig", p = 2, tick = tick, char = 5, state = 0x02020400 }) end
	-- The other side's freeze beginning: the update after the hit (H = tick - 1).
	local function opp_hit(tick, prev05, prev140, s140)
		T.on_row({ kind = "hit", p = 2, tick = tick, prev05 = prev05, prev140 = prev140 or 0, s140 = s140 or 0,
		           char = 5, state = 0x02020000 })
	end
	-- LP hits at 9700; its freeze ends at 9713, so R = 9726.
	fresh()
	hit(9700, 9708, 0x0400)
	tick(9712, 2, 0, 0, SPS)                 -- the special comes out (cancel)
	react(9713, 0)
	opp_hit(9716, 2)                         -- it hits on 9715, while they are in stun
	local r = T._rows()[1]
	-- M = 8 + (9726 - 1 - 9715) = 18
	eq("コンボになった: SP 8t/18t", r and r.result, "SP 8t/18t")
	eq("  緑", T.lines()[2][#T.lines()[2]][2], "#00FF00")
	eq("  目盛り: = がコンボになる範囲 (18t まで)、押した P と出た |", text(T.bar_cells(r)), "=======P===|======")
	-- Late: pressed on 22t; they could act on 9826, and it hit on 9830.
	fresh()
	hit(9800)
	react(9813, 0)
	tick(9822, 0, 0, 0x0400, NORMAL)
	tick(9823, 0, 0, 0, SPS)
	sig(9826)
	opp_hit(9831, 0)
	r = T._rows()[1]
	-- M = 22 + (9826 - 1 - 9830) = 17
	eq("間に合わなかった: SP 22t/17t", r and r.result, "SP 22t/17t")
	eq("  赤", T.lines()[2][#T.lines()[2]][2], "#FF0000")
	-- Guarded: they had recovered and blocked it.
	fresh()
	hit(9850)
	react(9863, 0)
	tick(9872, 0, 0, 0x0400, NORMAL)
	tick(9873, 0, 0, 0, SPS)
	sig(9876)
	opp_hit(9881, 0, 0, 0x02)
	eq("ガードされた: SP 22t/17t (赤)", T._rows()[1] and T._rows()[1].result, "SP 22t/17t")
	-- Hit on their reversal tick: the update before reads the mark 0x02020400,
	-- $05 2 - still not a combo (v11.7.25.2_20: LK > SP, sig C+26, hit C+26).
	fresh()
	hit(9950)
	react(9963, 0)                           -- R = 9976
	tick(9960, 0, 0, 0x0400, NORMAL)
	tick(9961, 0, 0, 0, SPS)
	sig(9976)
	opp_hit(9977, 2)                         -- H = 9976 = R; prev05 2 from the mark
	-- M = 10 + (9976 - 1 - 9976) = 9
	eq("リバーサル Tick に当たった: SP 10t/9t (1 Tick 遅い、赤)", T._rows()[1] and T._rows()[1].result, "SP 10t/9t")
	eq("  赤", T.lines()[2][#T.lines()[2]][2], "#FF0000")
	-- One tick earlier, before the mark: a combo, on the last tick.
	fresh()
	hit(9950)
	react(9963, 0)
	tick(9960, 0, 0, 0x0400, NORMAL)
	tick(9961, 0, 0, 0, SPS)
	opp_hit(9976, 2)                         -- H = 9975 = R - 1
	eq("リバーサル Tick の 1 つ前: SP 10t/10t (緑)", T._rows()[1] and T._rows()[1].result, "SP 10t/10t")
	-- The game and the window disagree: no /Mt.
	fresh()
	hit(9900, 9908, 0x0400)
	tick(9912, 2, 0, 0, SPS)
	react(9913, 0)
	opp_hit(9916, 0)                         -- "not in stun" although well inside
	eq("食い違いは /Mt を出さない", T._rows()[1] and T._rows()[1].result, "SP 8t")
	-- A special that never hits: no /Mt. A body contact alone does not decide it.
	fresh()
	hit(10000, 10008, 0x0400)
	tick(10012, 2, 0, 0, SPS)
	react(10013, 0)
	T.on_row({ kind = "contact", p = 1, tick = 10040, str = 4, typ = 0, air = 0, t169 = 0, hs = 0, edge = 0,
	           held = 0, state = SPS, char = 1, opp05 = 2, opp140 = 0 })
	eq("当たりが相手側に無ければ /Mt なし", T._rows()[1] and T._rows()[1].result, "SP 8t")
end

print("[21] 当たってすぐ必殺技の状態になった回も、行として残す")
do
	local SPS = 0x02000E00
	-- Bishamon's crouching MP: hit at 11329, in 0x0E on the next update with
	-- its hit stop at 11 and nothing pressed (v11.7.25.2_24). The user wants
	-- the line: it says whether the special combo'd (MP > SP SP 1t/0t).
	fresh()
	tick(11325, 0, 0, 0, NORMAL)               -- the MP under way
	contact(11329, 2, 0, 1, 0, 0)
	tick(11330, 13, 11, 0, SPS)
	eq("MP > SP の行になる (押しが無いので技の出た 1t)", T._rows()[1] and (T._rows()[1].src .. " > " .. T._rows()[1].tgt .. " " .. T._rows()[1].result), "MP > SP SP 1t")
	-- A cancel pressed after the hit is the same as before.
	fresh()
	hit(11500, 11508, 0x0400)
	tick(11512, 2, 0, 0, SPS)
	eq("押してからの必殺技はキャンセル (SP 8t)", T._rows()[1] and T._rows()[1].result, "SP 8t")
end

print("[22] 同じボタンへのチェーンの行は書かない (RAPID と LINK は残す)")
do
	-- HK hits; an HK pressed in its startup: HK > HK EARLY - not a chain.
	fresh()
	tick(12095, 0, 0, 0x4000, 0x02000000)       -- the HK that starts the move
	tick(12096, 0, 0, 0, NORMAL)
	tick(12098, 0, 0, 0x4000, NORMAL)           -- HK again, in its startup
	contact(12100, 4, 2)
	contact(12160)
	eq("HK > HK EARLY は出ない", #T._rows(), 0)
	-- In the window, refused by the mask: HK > HK NO CHAIN is not shown either.
	fresh()
	contact(12200, 4, 2)
	for n = 1, 11 do tick(12200 + n, 14 - n, 12 - n, (n == 3) and 0x4000 or 0) end
	check(12212, 2, "mask")
	contact(12260)
	eq("HK > HK NO CHAIN も出ない", #T._rows(), 0)
	-- Another button still shows.
	fresh()
	contact(12300, 4, 2)
	for n = 1, 11 do tick(12300 + n, 14 - n, 12 - n, (n == 3) and 0x0400 or 0) end
	check(12312, 2, "mask")
	contact(12360)
	eq("HK > HP NO CHAIN は出る", T._rows()[1] and (T._rows()[1].src .. " > " .. T._rows()[1].tgt .. " " .. T._rows()[1].result), "HK > HP NO CHAIN")
	-- RAPID LP > LP stays.
	fresh()
	hit(12400)
	tick(12413, 1, 0, 0x0100)
	check(12413, 1, "commit", "rapid", 0x0100, 8)
	eq("LP > LP RAPID は残す", T._rows()[1] and T._rows()[1].result, "RAPID")
end

-- Rows with the lever, as chainLog makes them now. The other side is char 5.
local function lrow(kind, tick, edge, state, lever, str, typ, s1b8, t169, hs)
	T.on_row({ kind = kind, p = 1, tick = tick, t169 = t169 or 0, hs = hs or 0, edge = edge or 0, held = 0,
	           state = state, air = 0, char = 1, str = str or 0, typ = typ or 0, lever = lever,
	           s1b8 = s1b8 or 0, f105 = (s1b8 or 0) > 0 and 1 or 0 })
end
local function other_side() T.on_row({ kind = "tick", p = 2, tick = 0, char = 5, state = 0x02000000, air = 0, edge = 0 }) end
local STAND_N, CROUCH_N = 0x02000A00, 0x02000A02

print("[23] 技の出の速さ: 出る前の Tick (押し / 受付) から最初の接触まで、立ちとしゃがみは別")
do
	fresh()
	other_side()
	lrow("tick", 8000, 0, IDLE, 0x00)
	lrow("tick", 8001, 0x0200, IDLE, 0x00)                  -- MP, lever neutral
	lrow("tick", 8002, 0, STAND_N, 0x00, 2, 0, 1)           -- the standing MP appears
	contact(8006, 2, 0)
	eq("立ち MP: 8006 - 8001 = 5", T.startup[T.startup_key(1, 5, 2, 0, false)], 5)
	lrow("tick", 8100, 0, IDLE, 0x04, 2, 0, 1)
	lrow("tick", 8101, 0x0200, IDLE, 0x04, 2, 0, 1)         -- MP with the lever down
	lrow("tick", 8102, 0, CROUCH_N, 0x04, 2, 0, 2)
	contact(8105, 2, 0)
	eq("しゃがみ MP は別: 4", T.startup[T.startup_key(1, 5, 2, 0, true)], 4)
	eq("  立ち MP は 5 のまま", T.startup[T.startup_key(1, 5, 2, 0, false)], 5)
	lrow("tick", 8200, 0, IDLE, 0x00, 2, 0, 2)
	lrow("tick", 8201, 0x0200, IDLE, 0x00, 2, 0, 2)
	lrow("tick", 8202, 0, STAND_N, 0x00, 2, 0, 3)
	contact(8209, 2, 0)                                     -- further away: 8
	eq("遠くて遅く当たった回では増やさない (少ない方)", T.startup[T.startup_key(1, 5, 2, 0, false)], 5)
	-- A chain's move is not counted: from its accept the same move hits a Tick
	-- off a press's (v11.7.25.2_27), and a link is a press.
	fresh()
	other_side()
	contact(8300)
	for n = 1, 11 do lrow("tick", 8300 + n, 0, NORMAL, 0x00, 0, 0, 1, 14 - n, 12 - n) end
	check(8312, 2, "commit", "chain", 0x2000)
	lrow("tick", 8312, 0, NORMAL, 0x00, 0, 0, 1, 2, 0)
	lrow("tick", 8313, 0, STAND_N, 0x00, 2, 2, 2, 1, 0)     -- the MK appears
	contact(8318, 2, 2)
	eq("チェーンの受付から出た技では覚えない", T.startup[T.startup_key(1, 5, 2, 2, false)], nil)
	-- A pursuit is not counted.
	lrow("tick", 8400, 0, IDLE, 0x00, 2, 2, 2)
	lrow("tick", 8401, 0x1000, IDLE, 0x00, 2, 2, 2)
	lrow("tick", 8402, 0, STAND_N, 0x00, 0, 2, 3)
	contact(8404, 0, 2, 1, 0, 0x0A)
	eq("追い打ちの当たりでは数えない", T.startup[T.startup_key(1, 5, 0, 2, false)], nil)
end

-- crouching LP hits at 9000 (its hit stop to 9011, judged 9012 / 9013), their
-- react at 9013 so R = 9026; the LP is over at 9020 (1t). A press on 9017:
-- past the window, 3 Ticks before 1t.
local function late_press(lever, with_react, startups)
	fresh()
	other_side()
	for k, v in pairs(startups or {}) do T.startup[k] = v end
	contact(9000, 0, 0)
	for n = 1, 11 do lrow("tick", 9000 + n, 0, CROUCH_N, 0x04, 0, 0, 1, 14 - n, 12 - n) end
	check(9012, 2, "rapid_no", nil, nil, nil, true)
	check(9013, 1, "rapid_no", nil, nil, nil, true)
	if with_react ~= false then
		T.on_row({ kind = "react", p = 2, tick = 9013, s59 = 0, s140 = 0, char = 5, state = 0x02020200 })
	end
	lrow("tick", 9017, 0x0200, CROUCH_N, lever, 0, 0, 1)
	lrow("tick", 9020, 0, 0x02000004, lever, 0, 0, 1)
	return T._rows()[#T._rows()]
end
local function text(cells) local o = {} for _, c in ipairs(cells) do o[#o + 1] = c[1] end return table.concat(o) end

print("[24] チェーンの窓の後、技の中の押しで、目押しなら間に合った: EARLY Nt/Mt の目押しの行")
do
	-- Standing MP: 5 to its contact. 9026 - 5 - 9020 = 1.
	local r = late_press(0x00, true, { [T.startup_key(1, 5, 2, 0, false)] = 5 })
	eq("目押しの行", r and r.link, true)
	eq("  LP > MP EARLY 3t/1t", r and (r.src .. " > " .. r.tgt .. " " .. r.result), "LP > MP EARLY 3t/1t")
	eq("  目盛り: 押し、技の中の 2 Tick、1t まで =", r and text(T.bar_cells(r)), "P..=")
	local L = T.lines()
	eq("  赤", L[#L] and L[#L][#L[#L]][2], "#FF0000")
	eq("  LATE の行は出ない", #T._rows(), 1)
	-- The lever down on the press: the crouching MP's startup.
	r = late_press(0x04, true, { [T.startup_key(1, 5, 2, 0, false)] = 7, [T.startup_key(1, 5, 2, 0, true)] = 4 })
	eq("レバー下ならしゃがみ MP の 4 で: EARLY 3t/2t", r and r.result, "EARLY 3t/2t")
end

print("[25] 目押しでも間に合わない、または分からないときは、チェーンの LATE のまま")
do
	local r = late_press(0x00, true, {})
	eq("出の速さを見ていない: LATE 4t", r and (r.link and "link" or r.result), "LATE 4t")
	r = late_press(0x00, true, { [T.startup_key(1, 5, 2, 0, false)] = 6 })
	eq("間に合わない (9026 - 6 - 9020 = 0): LATE 4t", r and (r.link and "link" or r.result), "LATE 4t")
	r = late_press(0x00, false, { [T.startup_key(1, 5, 2, 0, false)] = 5 })
	eq("相手の復帰が分からない: LATE 4t", r and (r.link and "link" or r.result), "LATE 4t")
	r = late_press(0x04, true, { [T.startup_key(1, 5, 2, 0, false)] = 5 })
	eq("レバー下で、しゃがみの方を見ていない: LATE 4t", r and (r.link and "link" or r.result), "LATE 4t")
end

print("[26] 相手のリバーサル Tick 以降の当たりは、$05 が 2 でもコンボにしない")
do
	local IDLE_ = 0x02000000
	local function react(t, s59) T.on_row({ kind = "react", p = 2, tick = t, s59 = s59, s140 = 0, char = 5, state = 0x02020200 }) end
	local function sig(t) T.on_row({ kind = "sig", p = 2, tick = t, char = 5, state = 0x02020400 }) end
	-- LP hits at 9500, react 9513 (R = 9526), the LP over at 9520; the next
	-- LP pressed on 9524 hits on 9526 - the reversal Tick itself.
	local function case(opp05, extra_react)
		fresh()
		hit(9500)
		react(9513, 0)
		tick(9520, 0, 0, 0, IDLE_)
		tick(9524, 0, 0, 0x0100, IDLE_)
		tick(9525, 0, 0, 0, NORMAL)
		sig(9526)
		if extra_react then react(9527, 0) end
		contact(extra_react and 9530 or 9526, 0, 0, 1, opp05, 0)
		return last()
	end
	local r = case(2)
	eq("リバーサル Tick ちょうどの当たり ($05 2): GAP 5t/4t", r and r.result, "GAP 5t/4t")
	eq("  赤", r and T.lines()[2][#T.lines()[2]][2], "#FF0000")
	r = case(2, true)
	eq("  その後に当たり直していれば (飛び道具など) LINK のまま", r and r.result:sub(1, 4), "LINK")
	-- Before it: unchanged.
	fresh()
	hit(9600)
	react(9613, 0)
	tick(9620, 0, 0, 0, IDLE_)
	tick(9622, 0, 0, 0x0100, IDLE_)
	tick(9623, 0, 0, 0, NORMAL)
	contact(9625, 0, 0, 1, 2, 0)
	eq("リバーサル Tick より前は LINK 3t/3t のまま (9626 - 3 - 9620)", last() and last().result, "LINK 3t/3t")
end

print(fails == 0 and "\n全て通った" or ("\n" .. fails .. " 件 NG"))
os.exit(fails == 0 and 0 or 1)
