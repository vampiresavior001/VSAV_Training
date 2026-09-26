-- GC Command Trace - 表と時計。
--
-- WHY THE TABLE IS PINNED. Which command block a guard cancel uses is per
-- character, and there is no way to work it out at runtime before the first
-- success - a forward input advances several commands' first steps at once, so
-- "whichever is moving" does not narrow it down. The values came from the ROM
-- (the branch whose success target tests $158) and were then confirmed against
-- 87 measured guard cancels across all 16 characters: the block that clears on
-- the success tick agreed every time (2026-09-23).
--
-- A wrong entry does not crash. It draws somebody else's command as if it were
-- the guard cancel, which reads as a working feature.
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_gc_command_trace.lua
local NL = string.char(10)
local src = io.open("guardCancel.lua"):read("*a")
local hud = io.open("hud.lua"):read("*a")

local fails = 0
local function want(what, got, expected)
	if got == expected then
		print("  ok " .. what)
	else
		fails = fails + 1
		print("  NG " .. what)
		print("     got  [" .. tostring(got) .. "]")
		print("     want [" .. tostring(expected) .. "]")
	end
end

print("[1] 16 キャラぶんのブロックが、測定した値で入っている")
do
	local a = src:find("local GC_BLOCK = {", 1, true)
	local b = src:find("}", a or 1, true)
	want("表がある", a ~= nil and b ~= nil, true)
	local body = src:sub(a or 1, b or 1)
	local got = {}
	for cid, blk in body:gmatch("%[(0x%x%x)%]%s*=%s*(0x%x+)") do
		got[tonumber(cid)] = tonumber(blk)
	end
	-- 実測 (成立したティックで消えたブロック) と ROM 抽出の一致したもの。
	local measured = {
		[0x00] = 0x340, [0x01] = 0x308, [0x02] = 0x328, [0x03] = 0x308,
		[0x04] = 0x338, [0x05] = 0x318, [0x06] = 0x330, [0x07] = 0x310,
		[0x08] = 0x300, [0x09] = 0x348, [0x0A] = 0x308, [0x0B] = 0x338,
		[0x0C] = 0x330, [0x0D] = 0x310, [0x0E] = 0x310, [0x0F] = 0x308,
	}
	local n, bad = 0, {}
	for cid = 0, 15 do
		n = n + 1
		if got[cid] ~= measured[cid] then
			bad[#bad + 1] = string.format("0x%02X(%s)", cid, tostring(got[cid]))
		end
	end
	want("16 キャラ揃っている", n, 16)
	want("値が実測と一致", table.concat(bad, " "), "")
	-- ブロックは 8 バイト刻みで $300..$358 の中。外れていたら別の何かを読む。
	local out = {}
	for cid, blk in pairs(got) do
		if blk < 0x300 or blk > 0x358 or blk % 8 ~= 0 then
			out[#out + 1] = string.format("0x%02X", cid)
		end
	end
	want("どれも $300..$358 の 8 バイト刻み", table.concat(out, " "), "")
end

print("")
print("[2] 段は +1、試行の切れ目は +0。どちらも他方では読めない")
-- +0 は「どの処理で待っているか」で、方向が 1 つ受け付けられても 2 のまま
-- 動かない。+0 を段として読むと昇龍拳が方向 2 つに見える。
--
-- 逆に +1 は試行が死んでも 0 に戻らないので、始まりと終わりは +0 でしか
-- 読めない。切れ目を +1 に持たせると 2 回の試行が 1 本に繋がる
-- (2026-09-24、analysis/test_gct_state.lua が実際に動かして確かめる)。
do
	local a = src:find("local function gct_tick(_gc)", 1, true)
	local b = src:find(NL .. "end", a or 1, true)
	local body = src:sub(a or 1, (b or 1) + 3)
	want("gct_tick がある", a ~= nil, true)
	want("段は +1 を読む", body:find("_blk + 1", 1, true) ~= nil, true)
	want("段が増えたら方向が通った", body:find("_step > _was_step", 1, true) ~= nil, true)
	want("始まりは +0 が 0 を出たところ",
		body:find("_was_prog == 0 and _prog ~= 0", 1, true) ~= nil, true)
	want("終わりは +0 が 0 へ戻ったところ",
		body:find("_was_prog ~= 0 and _prog == 0", 1, true) ~= nil, true)
	-- 方向はその場のレバーから。押したものではなく通ったものを出す。
	want("方向は gct_numpad から取る",
		body:find("gct_numpad()", 1, true) ~= nil, true)
end

print("")
print("[2b] 方向は入力ビューアと同じ読み方で出す")
-- 下のバーと見比べるための readout なので、矢印が両方で同じ意味でないと
-- 用を成さない。自前で規則を決めて 2 回間違えている - 生のまま描いて
-- 1P の昇龍拳が 2P のものとして出た、$120 で入れ替えて今度は左下を向いた
-- (本人、2026-09-23)。決めるのをやめ、read_game_input の規則を借りる。
do
	local a = src:find("local function gct_numpad()", 1, true)
	local b = src:find(NL .. "end", a or 1, true)
	local body = src:sub(a or 1, (b or 1) + 3)
	want("gct_numpad がある", a ~= nil, true)
	-- 入力ビューアと同じ読み方であること。この readout は下のバーと
	-- 見比べるためのものなので、矢印が両方で同じ意味でないと用を成さない。
	-- 自前で規則を決めて 2 回間違えた (生のまま描く / $120 で入れ替える)
	-- ので、決めるのをやめて借りている (本人、2026-09-23)。
	want("レバーは $125", body:find("0x125", 1, true) ~= nil, true)
	want("向きは $b", body:find("0x00B", 1, true) ~= nil, true)
	want("$12B は読まない", body:find("0x12B", 1, true), nil)
	want("$120 は読まない", body:find("0x120", 1, true), nil)
	-- 入れ替えの向きは分岐ごと挟んで見る。2 つの代入が在ることだけを
	-- 見ると、両方を同じに書き換えても通ってしまう。
	local _if = "if memory.readbyte(P1_BASE + 0x00B) == 0 then" .. NL
		.. string.rep(string.char(9), 2) .. "_left, _right = _b1, _b0"
	want("facing 0 の枝で bit1 が左", body:find(_if, 1, true) ~= nil, true)
	local _el = "else" .. NL .. string.rep(string.char(9), 2)
		.. "_left, _right = _b0, _b1"
	want("それ以外の枝で bit0 が左", body:find(_el, 1, true) ~= nil, true)
	-- ビューア側の読みと 1 文字ずつ同じこと。片方だけ直されると、また
	-- 2 か所が食い違う。
	local h = io.open("inputHistory.lua"):read("*a")
	local ha = h:find("local function read_game_input", 1, true)
	local hb = h:find("local function pressed(bit_index)", ha or 1, true)
	local hbody = h:sub(ha or 1, hb or 1)
	want("ビューアも $125", hbody:find("0x125", 1, true) ~= nil, true)
	want("ビューアも $00B", hbody:find("0x00B", 1, true) ~= nil, true)
	-- テンキーへの落とし方も同じ形。
	for _, needle in ipairs({
		"if _left then _direction = 1", "elseif _right then _direction = 3" }) do
		want("ビューアの落とし方 [" .. needle .. "]",
			hbody:find(needle, 1, true) ~= nil, true)
	end
	
	want("こちらも 下+左 が 1、下+右 が 3",
		body:find("if _left then return 1 elseif _right then return 3", 1, true) ~= nil, true)
	local h = io.open("inputHistory.lua"):read("*a")
	want("ビューアも同じ規則 (変数名は違う)",
		h:find("_left, _right = bit1, bit0", 1, true) ~= nil, true)
end

print("")
print("[3] 時計は 2 本 - Success だけ Guard から")
do
	local src2 = hud
	local a = hud:find("local function draw_gc_command_trace()", 1, true)
	local b = hud:find(NL .. "end" .. NL, a or 1, true)
	local body = hud:sub(a or 1, (b or 1) + 4)
	want("描画がある", a ~= nil, true)
	-- 左の列は「直前の入力から」。最速なら各方向が 1t、最後のレバーと
	-- ボタンが同じティックなら 0t になる (本人、2026-09-23)。通算だと
	-- 読む側が引き算することになる。中身は [7] で実際に描かせて見る。
	want("直前の入力からの差", body:find("_r.t - _last_in", 1, true) ~= nil, true)
	-- ガードは入力ではないので起点にならない。
	want("入力のときだけ起点を進める",
		body:find('if _r.k == "dir" or _r.k == "btn" then', 1, true) ~= nil, true)
	-- 最初の入力より前には数字が無い。
	want("起点が無ければ出さない", body:find("if _last_in ~= nil then", 1, true) ~= nil, true)
	want("通算の引き算は残っていない", body:find("_r.t - _t0", 1, true), nil)
	-- 数字は 1 つの列に右揃え。ラベルの直後に書くと、長い終端行だけ
	-- 数字が遠くへ飛んで間違いに見える (本人、2026-09-23)。
	want("数字は gct_num を通す", body:find("gct_num(", 1, true) ~= nil, true)
	want("ラベル長に合わせた置き方は残っていない",
		body:find("#_t.done * 5", 1, true), nil)
	-- 失敗の色は入力ビューアが死んだ GC に使っている赤と同じ。2 つの
	-- readout が同じことを違う色で言わないように。
	local h = io.open("inputHistory.lua"):read("*a")
	want("ビューアの失敗色", h:find('"GC", "#FF0000"', 1, true) ~= nil, true)
	want("こちらも同じ赤", src2:find('GCT_BAD = "#FF0000"', 1, true) ~= nil, true)
	want("中間色は使っていない", src2:find("#FF6666", 1, true), nil)
	-- 起点の規則は [7] で実際に描かせて見る。ここはソースなので、
	-- 「攻撃の先頭から数える」古い形が残っていないことだけ見る。
	want("先頭からの通算は残っていない", body:find("_t.at - _t0", 1, true), nil)
	-- ガードが無いうちは何も描かない。描くとただのレバー履歴になる。
	want("ガードが無ければ描かない",
		body:find("_t.guard == nil", 1, true) ~= nil, true)
end

print("")
print("[4] メニュー / config / 描画が同じキーを指している")
do
	local menu = io.open("menu.lua"):read("*a")
	local cfg = dofile("config.lua").default_training_settings
	want("メニューに行がある",
		menu:find('"Show GC Command Trace", training_settings, "display_gc_command_trace"',
			1, true) ~= nil, true)
	want("出荷値は OFF", cfg.display_gc_command_trace, false)
	want("描く側が同じキーを読む",
		hud:find("globals.options.display_gc_command_trace", 1, true) ~= nil, true)
end

print("")
print("[5] 終端の語")
-- 本人が決めた語。画面に出る文字なので、勝手に変わっていたら気付きたい。
for _, word in ipairs({ "Success", "GC Expired", "Cmd Expired" }) do
	want(word .. " を使っている", src:find('"' .. word .. '"', 1, true) ~= nil, true)
end
-- 入り直しも Command Expired にまとめる判断 (本人、2026-09-23)。別の語が
-- 増えていたら、その判断が覆っている。
want("Command Reset は無い", src:find("Command Reset", 1, true), nil)
-- 長い語に戻すと数字の列が右へ追い出され、矢印との間が 60px 空く。
want("Command Expired は使っていない", src:find("Command Expired", 1, true), nil)

print("")
print("[6] 終わった trace は、次のガードが来るまで消えない")
-- 成立したあともレバーは動いているので、「次のモーションが始まったら
-- 捨てる」だと 1〜2 ティックで消える。実際、成功した瞬間に消えることが
-- あると報告された (本人、2026-09-23)。集めるほうと見せるほうを分けて、
-- ガードを持った trace だけが前のものと入れ替わる。
do
	local a = src:find("local function gct_publish()", 1, true)
	local b = src:find(NL .. "end", a or 1, true)
	local body = src:sub(a or 1, (b or 1) + 3)
	want("gct_publish がある", a ~= nil, true)
	-- 入れ替えの条件はガードがあること。ここが無いと、ガードの無い
	-- 集めかけが表示を上書きして、また消える。
	want("ガードがあるときだけ差し替える",
		body:find("if gct.guard ~= nil then", 1, true) ~= nil, true)
	want("見せるのは控えのほう",
		body:find("globals.gc_trace = gct_shown", 1, true) ~= nil, true)
	-- 控えを nil にする代入が、宣言の 1 つだけであること。2 つ目が
	-- できると、そこから表示が消える経路になる。
	local _n = 0
	for _ in src:gmatch("gct_shown = nil") do _n = _n + 1 end
	want("控えを消す代入は宣言だけ", _n, 1)
	want("宣言は local", src:find("local gct_shown = nil", 1, true) ~= nil, true)
	want("gc_trace に nil を書く経路が無い",
		src:find("globals.gc_trace = nil", 1, true), nil)
	-- 控えが古い rows を指し続けられること。reset が同じ表を空にすると、
	-- 見せているほうまで一緒に空になる。
	local ra = src:find("local function gct_reset()", 1, true)
	local rb = src:find(NL .. "end", ra or 1, true)
	want("reset は新しい表を作る",
		src:sub(ra or 1, (rb or 1) + 3):find("gct.rows, gct.guard", 1, true) ~= nil, true)
end

print("")
print("[7] 実際に描かせる - gui.text に nil の色を渡さない")
-- ここまでの判定はソースを読むだけで、描画を一度も走らせていなかった。
-- その隙間から nil の色が gui.text へ渡り、"invalid colour" で HUD ごと
-- 落ちた (本人、2026-09-23)。読むだけでは見えない類なので、叩く。
do
	-- [8] からも触るので、この do の外に出す。
	calls = {}
	bad = {}
	images = {}
	gui = {
		text = function(_x, _y, _s, _c)
			calls[#calls + 1] = { x = _x, y = _y, s = _s, c = _c }
			-- FBNeo の gui.text は色が nil だと落ちる。省略は許されるが、
			-- nil を渡すのは別物。
			if _c ~= nil and type(_c) ~= "string" and type(_c) ~= "number" then
				bad[#bad + 1] = tostring(_s)
			end
			if _c == nil then bad[#bad + 1] = "nil:" .. tostring(_s) end
		end,
		image = function(_x, _y, _img)
			images[#images + 1] = { x = _x, y = _y, img = _img }
		end,
		box = function() end, line = function() end, rect = function() end,
	}
	memory = { readbyte = function() return 0 end, readword = function() return 0 end,
	           readdword = function() return 0 end, writebyte = function() end,
	           registerexec = function() end, registerwrite = function() end,
	           getregister = function() return 0 end }
	emu = { framecount = function() return 1 end, screenwidth = function() return 384 end,
	        screenheight = function() return 224 end }
	joypad = { get = function() return {} end }
	-- hud.lua は tech-hit-inputs を require し、そちらが gd の別の口も叩く。
	local _img = { gdStr = function() return "" end }
	gd = {
		-- どのファイルを読んだかを gdStr に残す。オレンジの矢印を見分けるため。
		createFromPng = function(_path)
			return { gdStr = function() return "png:" .. tostring(_path) end }
		end,
		createFromPngStr = function() return _img end,
		copyResampled = function() end,
	}
	package.preload["gd"] = function() return gd end
	-- hud.lua が読む 2 つ。どちらもこのテストでは使われない。
	package.preload["./scripts/actionSequenceRunner"] = function()
		return { gc_freq = function() return nil end }
	end
	package.preload["./scripts/debugKnockdown"] = function()
		return { mark_write = function() end }
	end
	img_dir = {}
	for i = 1, 9 do img_dir[i] = "dir" .. i end
	img_no_button, img_L_button, img_M_button, img_H_button = "n", "l", "m", "h"
	globals = { options = { display_gc_command_trace = true } }
	hud_mod = dofile("hud.lua")
	want("描画が外に出ている", type(hud_mod.draw_gc_command_trace), "function")

	-- 成立した trace。方向 3 つ、ガード、ボタン。
	globals.gc_trace = {
		guard = 110,
		done = "Success",
		at = 202,
		rows = {
			{ k = "dir",   t = 100, v = 6 },
			{ k = "dir",   t = 101, v = 2 },
			{ k = "dir",   t = 102, v = 3 },
			{ k = "guard", t = 110 },
			{ k = "btn",   t = 202, v = { true, true, true, false, false, false } },
		},
	}
	hud_mod.draw_gc_command_trace()
	want("色が nil のまま渡された描画は無い", table.concat(bad, ", "), "")
	want("何か描いている", #calls > 0, true)

	-- 左の列 (Cmd) は「直前の入力から」。ガードは入力ではないので起点に
	-- ならないが、動きのどこで起きたかを見るために数字は持ち、括弧で囲む
	-- (本人、2026-09-23)。右の列 (GC) は Guard からで、窓の行だけ。
	local nums = {}
	for _, c in ipairs(calls) do
		if type(c.s) == "string" and c.s:find("t%)?$") and c.s ~= "GC Command Trace" then
			nums[#nums + 1] = c
		end
	end
	want("数字の数", #nums, 5)
	want("2 行目は 1t", nums[1].s, "1t")
	want("3 行目も 1t", nums[2].s, "1t")
	want("ガードは括弧付きで ↘ から 8t", nums[3].s, "(8t)")
	-- ボタンは直前の入力 (↘) から。ガードを飛ばすので 20t。
	want("ボタンは入力どうしの間隔", nums[4].s, "100t")
	want("Success は Guard から 92t", nums[5].s, "92t")
	-- 列は 1 つ。括弧がガードの行を区別するので、分ける必要が無くなった
	-- (本人、2026-09-23)。
	-- 1 文字は 4.2px。5 で測ると長い文字列ほど右端が左へずれる - 実際に
	-- そう見えた (本人、2026-09-23)。ここは本当の字送りで測るので、
	-- 描く側が 5 のままなら落ちる。
	local CH = 4.2
	local ends = {}
	for i = 1, 5 do ends[i] = nums[i].x + #nums[i].s * CH end
	local worst = 0
	for i = 1, 5 do
		if nums[i].s:sub(-1) ~= ")" then
			local d = math.abs(ends[i] - ends[1])
			if d > worst then worst = d end
		end
	end
	-- 丸めのぶん 1px までは許す。
	want("数字の右端が揃っている (ずれ " .. worst .. "px)",
		worst <= 1, true)
	-- 括弧は列の外へはみ出す。中の数字が上下と揃うように、閉じ括弧 1 文字ぶん
	-- だけ右へ出す。全体を右揃えにすると中の数字が 1 文字ぶん左へずれる。
	-- 括弧の寄せは 1 文字ぶんちょうど。丸めのぶん測定では 1px 未満の差に
	-- 埋もれるので、値そのものをソースで縛る。
	local _hs = io.open("hud.lua"):read("*a")
	want("寄せは字送り 1 文字ぶん",
		_hs:find("local GCT_BRACKET = GCT_CH", 1, true) ~= nil, true)
	want("字送りは 4.2",
		_hs:find("local GCT_CH = 4.2", 1, true) ~= nil, true)
	-- 括弧は 1 文字ぶん外へ。中の数字の右端が、ほかの数字と揃う。
	want("括弧の中身が揃っている",
		math.abs((ends[3] - CH) - ends[1]) <= 1, true)
	-- 失敗は赤。
	calls, bad = {}, {}
	globals.gc_trace.done, globals.gc_trace.at = "Cmd Expired", 211
	hud_mod.draw_gc_command_trace()
	local red = false
	for _, c in ipairs(calls) do
		if c.s == "Cmd Expired" and c.c == "#FF0000" then red = true end
	end
	want("失敗は #FF0000", red, true)
	-- 列が必要以上に右へ行っていないこと。右揃えなだけでは足りない -
	-- 長いラベルに合わせて広げると、矢印と数字が 60px 離れる (本人、
	-- 2026-09-23 に 2 度)。いちばん長いラベルの右端と数字の左端の差で見る。
	local _lab_r, _num_l
	for _, c in ipairs(calls) do
		if c.s == "Cmd Expired" then _lab_r = c.x + #c.s * 5 end
		if type(c.s) == "string" and c.s:find("t$") and c.s ~= "GC Command Trace" then
			_num_l = c.x
		end
	end
	want("ラベルと数字が離れていない", (_num_l or 999) - (_lab_r or 0) <= 20, true)
	-- ブロックの左端。画面右の P2 入力列と Fastest に重なっていた。
	local hud_src = io.open("hud.lua"):read("*a")
	want("左へ寄せてある", hud_src:find("local _x, _y = 226, 50", 1, true) ~= nil, true)
	-- 失敗は最後に通った入力から数える。段のタイマーはそこから始まる。
	-- 上の trace ではボタン行が 122 にあるので 131 - 122 = 9t。
	local n2 = {}
	for _, c in ipairs(calls) do
		if type(c.s) == "string" and c.s:find("t$") and c.s ~= "GC Command Trace" then
			n2[#n2 + 1] = c.s
		end
	end
	want("失敗は最後の入力から", n2[#n2], "9t")
	-- ボタンが無い失敗なら、最後の方向から。ガードは操作ではないので飛ばす。
	calls, bad = {}, {}
	globals.gc_trace.rows[5] = nil
	hud_mod.draw_gc_command_trace()
	local n3 = {}
	for _, c in ipairs(calls) do
		if type(c.s) == "string" and c.s:find("t$") and c.s ~= "GC Command Trace" then
			n3[#n3 + 1] = c.s
		end
	end
	want("ボタンが無ければ最後の方向から", n3[#n3], "109t")
	want("ガードからではない", n3[#n3] ~= "101t", true)
	want("色が nil のまま渡された描画は無い (失敗側)", table.concat(bad, ", "), "")

	-- スイッチが OFF なら何も描かない。
	calls = {}
	globals.options.display_gc_command_trace = false
	hud_mod.draw_gc_command_trace()
	want("OFF なら描かない", #calls, 0)
end

print("")
print("[8] ガード先行なら、最初の方向はガードからの数字を持つ")
-- ガードしてからコマンドを入れ始めると、最初の方向には「直前の入力」が
-- 無いので無印だった。だがそこで知りたいのは「ガードから何ティックで
-- 入れ始めたか」で、まさにその数字 (本人、2026-09-23)。
--
-- 括弧は付けない。ガードがそのまま鎖の起点になるので、この数字は鎖の一部
-- (本人、2026-09-24)。括弧が残るのは Guard の行自身だけ。
do
	calls, bad = {}, {}
	globals.options.display_gc_command_trace = true
	globals.gc_trace = {
		guard = 100, done = "Success", at = 112,
		rows = {
			{ k = "guard", t = 100 },
			{ k = "dir",   t = 103, v = 6 },
			{ k = "dir",   t = 104, v = 2 },
			{ k = "dir",   t = 105, v = 3 },
			{ k = "btn",   t = 112,
				v = { true, false, false, false, false, false } },
		},
	}
	hud_mod.draw_gc_command_trace()
	local n = {}
	for _, c in ipairs(calls) do
		if type(c.s) == "string" and c.s:find("t%)?$")
			and c.s ~= "GC Command Trace" then
			n[#n + 1] = c
		end
	end
	want("色が nil のまま渡された描画は無い", table.concat(bad, ", "), "")
	want("数字の数", #n, 5)
	want("1 つ目の方向はガードから 3t", n[1].s, "3t")
	want("2 つ目からは直前の入力から", n[2].s, "1t")
	want("3 つ目も", n[3].s, "1t")
	want("ボタンは直前の入力から 7t", n[4].s, "7t")
	want("Success は Guard から 12t", n[5].s, "12t")
	-- ガードが先頭なら、ガード自身には数字が付かない。上に何も無い。
	local g = false
	for _, c in ipairs(calls) do if c.s == "Guard" then g = true end end
	want("Guard は描かれている", g, true)
end
print("")
print("[9] 乱数に救われた間隔は警告色。死んだコマンドの後のガードは繋ぐ")
-- 猶予は乱数で、プレイヤーが体感するのは 11〜15 ティック。11 までは普通に
-- 来る値で、それを超えて通ったものは引きが良かっただけ (本人、2026-09-24)。
--
-- 0x02A55A の表 (14 が 16/32、以降 19 まで) は段タイマーに積まれる値で、
-- プレイヤーが得る窓とは別物 (本人)。表は VSAV_MEMORY_NOTES に書いてある。
do
	calls, bad = {}, {}
	globals.options.display_gc_command_trace = true
	globals.gc_trace = {
		guard = 100, done = "Success", at = 145,
		rows = {
			{ k = "guard", t = 100 },
			{ k = "dir",   t = 115, v = 6 },   -- ガードから 15t
			{ k = "dir",   t = 126, v = 2 },   -- 11t 猶予の内
			{ k = "dir",   t = 138, v = 3 },   -- 12t 引きに救われた
			{ k = "btn",   t = 145,
				v = { true, false, false, false, false, false } },
		},
	}
	hud_mod.draw_gc_command_trace()
	local by = {}
	for _, c in ipairs(calls) do
		if type(c.s) == "string" and c.s:find("t%)?$")
			and c.s ~= "GC Command Trace" then by[c.s] = c.c end
	end
	want("11t は警告色ではない", by["11t"], "#FFFFFF")
	want("12t は警告色 (引き次第)", by["12t"], "#FF7F00")
	want("ボタンの 7t は普通", by["7t"], "#FFFFFF")
	-- 括弧付きはガードを端点に持つ数字で、受付の猶予ではない。引きに救われた
	-- という読みが成立しないので、12 以上でも警告にしない (本人、2026-09-24)。
	want("ガードからの数字は 12 以上でも警告しない", by["15t"], "#FFFFFF")
	want("そこに括弧は付けない", by["(15t)"], nil)
	want("色が nil のまま渡された描画は無い", table.concat(bad, ", "), "")

	-- 死んだコマンドの後に近いガードが来たら、行を捨てずに繋ぐ。そこで
	-- 数え直す。実機 2026-09-24 の 2 枚目と同じ形。
	--
	-- 死んだ試行の入力から数え続けると、-> が「前の入力 -> 期限切れ ->
	-- ガード -> ここ」の 3 区間を足した数字になり、1 つの待ちに見える
	-- (本人、2026-09-24)。
	calls, bad = {}, {}
	globals.gc_trace = {
		guard = 129, done = "Success", at = 155,
		rows = {
			{ k = "dir",  t = 100, v = 6 },
			{ k = "dir",  t = 108, v = 2 },    -- 8t
			{ k = "dead", t = 127, v = "Cmd Expired" },   -- 最後の入力から 19t
			{ k = "guard", t = 129 },          -- 期限切れから 2t
			{ k = "dir",  t = 132, v = 6 },    -- ガードから 3t
			{ k = "dir",  t = 136, v = 2 },    -- 4t
			{ k = "dir",  t = 142, v = 3 },    -- 6t
			{ k = "btn",  t = 142,
				v = { true, false, false, false, false, false } },   -- 0t
		},
	}
	hud_mod.draw_gc_command_trace()
	local seen = {}
	local dead_c = nil
	for _, c in ipairs(calls) do
		if type(c.s) == "string" then
			if c.s == "Cmd Expired" then dead_c = c.c end
			if c.s:find("t%)?$") and c.s ~= "GC Command Trace" then
				seen[c.s] = c.c
			end
		end
	end
	want("死んだ印が行として出る", dead_c, "#FF0000")
	-- 死んだ行の数字は「通った猶予」ではなく「殺した待ち」なので、琥珀では
	-- なく行と同じ赤。
	want("死んだ行は最後の入力から", seen["19t"] ~= nil, true)
	want("死んだ行の数字は赤", seen["19t"], "#FF0000")
	want("ガードは死んだ行から", seen["(2t)"] ~= nil, true)
	want("ガードは最後の入力から数えない", seen["(29t)"], nil)
	-- 切った後のガードは数え直しの起点そのものなので、括弧は付けない
	-- (本人、2026-09-24)。受付の猶予ではないので琥珀にもしない。
	want("ガードの後の 1 つ目はガードから", seen["3t"], "#FFFFFF")
	want("そこに括弧は付けない", seen["(3t)"], nil)
	want("その次からは入力どうし", seen["4t"], "#FFFFFF")
	want("レバーとボタンが同時なら 0t", seen["0t"], "#FFFFFF")
	want("Success はガードから", seen["26t"] ~= nil, true)
	want("色が nil のまま渡された描画は無い", table.concat(bad, ", "), "")

	-- 失敗の終端も同じ。死んだ行を跨いで数えない。1 枚目がこれで、
	-- ガードから 14t = 受付がそのまま切れた、と読める。
	calls, bad = {}, {}
	globals.gc_trace = {
		guard = 26, done = "GC Expired", at = 40,
		rows = {
			{ k = "dir",  t = 0,  v = 6 },
			{ k = "dir",  t = 10, v = 4 },
			{ k = "dead", t = 24, v = "Cmd Expired" },
			{ k = "guard", t = 26 },
		},
	}
	hud_mod.draw_gc_command_trace()
	seen = {}
	for _, c in ipairs(calls) do
		if type(c.s) == "string" and c.s:find("t%)?$") then seen[c.s] = c.c end
	end
	want("終端はガードから", seen["14t"] ~= nil, true)
	want("終端は死んだ試行の入力から数えない", seen["30t"], nil)
	want("色が nil のまま渡された描画は無い", table.concat(bad, ", "), "")

	-- ガードが先、コマンド切れが後 (実機 2026-09-24)。受付が開いている間に
	-- 入れ直したので、死んだ行の下は「切れてから何ティックで入れ直したか」。
	calls, bad = {}, {}
	globals.gc_trace = {
		guard = 21, done = "Success", at = 40,
		rows = {
			{ k = "dir",  t = 0,  v = 6 },
			{ k = "dir",  t = 9,  v = 4 },   -- 9t
			{ k = "guard", t = 21 },         -- 最後の入力から (12t)
			{ k = "dead", t = 24, v = "Cmd Expired" },   -- 最後の入力から 15t
			{ k = "dir",  t = 26, v = 6 },   -- 切れてから 2t
			{ k = "dir",  t = 31, v = 4 },   -- 5t
			{ k = "dir",  t = 37, v = 3 },   -- 6t
			{ k = "btn",  t = 40,
				v = { false, false, false, true, false, false } },   -- 3t
		},
	}
	hud_mod.draw_gc_command_trace()
	seen = {}
	for _, c in ipairs(calls) do
		if type(c.s) == "string" and c.s:find("t%)?$") then seen[c.s] = c.c end
	end
	want("ガードは最後の入力から", seen["(12t)"] ~= nil, true)
	-- 括弧は 1 文字ぶん外へ出す。中身が下の行と揃う。
	local g_call, d_call
	for _, c in ipairs(calls) do
		if c.s == "(12t)" then g_call = c elseif c.s == "15t" then d_call = c end
	end
	want("括弧の中身が下の行と揃っている",
		math.abs((g_call.x + #g_call.s * 4.2 - 4.2)
			- (d_call.x + #d_call.s * 4.2)) <= 1, true)
	want("死んだ行も最後の入力から", seen["15t"], "#FF0000")
	want("入れ直しは切れてから", seen["2t"], "#FFFFFF")
	want("切った後に括弧は付けない", seen["(2t)"], nil)
	want("その次からは入力どうし", seen["6t"], "#FFFFFF")
	want("Success はガードから", seen["19t"] ~= nil, true)
	want("色が nil のまま渡された描画は無い", table.concat(bad, ", "), "")

	-- 切った後の数字も受付の猶予ではない。12 以上でも琥珀にしない。
	calls, bad = {}, {}
	globals.gc_trace = {
		guard = 34, done = nil, at = nil,
		rows = {
			{ k = "dir",  t = 0,  v = 6 },
			{ k = "dead", t = 20, v = "Cmd Expired" },
			{ k = "guard", t = 34 },
			{ k = "dir",  t = 47, v = 4 },
		},
	}
	hud_mod.draw_gc_command_trace()
	seen = {}
	for _, c in ipairs(calls) do
		if type(c.s) == "string" and c.s:find("t%)?$") then seen[c.s] = c.c end
	end
	want("切った後の数字は 12 以上でも警告しない", seen["13t"], "#FFFFFF")
	want("色が nil のまま渡された描画は無い", table.concat(bad, ", "), "")

	-- ガード行自身の括弧も同じ。入力から 12 以上離れていても警告しない。
	calls, bad = {}, {}
	globals.gc_trace = {
		guard = 20, done = nil, at = nil,
		rows = {
			{ k = "dir", t = 0, v = 6 },
			{ k = "dir", t = 5, v = 4 },
			{ k = "guard", t = 20 },
		},
	}
	hud_mod.draw_gc_command_trace()
	seen = {}
	for _, c in ipairs(calls) do
		if type(c.s) == "string" and c.s:find("t%)?$") then seen[c.s] = c.c end
	end
	want("ガード行の括弧は 12 以上でも警告しない", seen["(15t)"], "#FFFFFF")
	want("色が nil のまま渡された描画は無い", table.concat(bad, ", "), "")

	-- 繋ぐ条件は 16 ティック。体感の猶予 15 の 1 つ外側。
	local gsrc = io.open("guardCancel.lua"):read("*a")
	want("16 ティックで判定している",
		gsrc:find("local REATTACH_TICKS = 16", 1, true) ~= nil, true)
	want("Cmd Expired のときだけ繋ぐ",
		gsrc:find('gct.done == \"Cmd Expired\" and _gc ==', 1, true) ~= nil, true)
	want("期限切れを行として残す",
		gsrc:find('gct_add(\"dead\", gct.at, gct.done)', 1, true) ~= nil, true)
end
print("")
print("[10] 警告色はオレンジ。その行の矢印も白い塗りだけオレンジ")
do
	-- 琥珀 (#FFA000) は Success の金 (#FFD700) と見分けにくかった (本人、
	-- 2026-09-25)。gui.image に色の引数は無いので、矢印は色違いの画像
	-- (analysis/make_warn_arrows.py が作る) に差し替える。
	calls, bad, images = {}, {}, {}
	globals.gc_trace = {
		guard = 30, done = "Success", at = 60,
		rows = {
			{ k = "dir", t = 0,  v = 6 },   -- 先頭。数字なし、白
			{ k = "dir", t = 12, v = 2 },   -- 12t: 数字も矢印もオレンジ
			{ k = "dir", t = 13, v = 3 },   -- 1t: 白
			{ k = "guard", t = 30 },        -- (17t): ガードは警告しない
			{ k = "dir", t = 45, v = 5 },   -- 32t だが 5 に白い塗りは無い
			{ k = "btn", t = 60,
				v = { true, false, false, false, false, false } },   -- 15t
		},
	}
	hud_mod.draw_gc_command_trace()
	local arrows = {}
	for _, im in ipairs(images) do
		local s0 = tostring(im.img)
		if s0:find("^dir") or s0:find("_dir_warn") then arrows[#arrows + 1] = s0 end
	end
	want("矢印の並び", table.concat(arrows, " "),
		"dir6 png:images/2_dir_warn.png dir3 dir5")
	local by = {}
	for _, c in ipairs(calls) do
		if type(c.s) == "string" then by[c.s] = c.c end
	end
	want("12t はオレンジ", by["12t"], "#FF7F00")
	want("1t は白", by["1t"], "#FFFFFF")
	want("ガードの括弧はオレンジにしない", by["(17t)"], "#FFFFFF")
	want("中立の 32t も数字はオレンジ", by["32t"], "#FF7F00")
	want("ボタンの 15t もオレンジ", by["15t"], "#FF7F00")
	-- 既存の色は変えない。
	want("Success は金のまま", by["Success"], "#FFD700")
	want("Success の数字も金のまま", by["30t"], "#FFD700")
	want("色が nil のまま渡された描画は無い", table.concat(bad, ", "), "")

	-- ガード先行の 1 つ目 (ガードから測る) は、大きくてもオレンジにしない。
	calls, bad, images = {}, {}, {}
	globals.gc_trace = {
		guard = 0, done = nil, at = nil,
		rows = {
			{ k = "guard", t = 0 },
			{ k = "dir", t = 20, v = 4 },
		},
	}
	hud_mod.draw_gc_command_trace()
	arrows = {}
	for _, im in ipairs(images) do
		local s0 = tostring(im.img)
		if s0:find("^dir") or s0:find("_dir_warn") then arrows[#arrows + 1] = s0 end
	end
	want("ガードから測った矢印は白", table.concat(arrows, " "), "dir4")

	-- 切れた後の最初の矢印も同じ。
	calls, bad, images = {}, {}, {}
	globals.gc_trace = {
		guard = 34, done = nil, at = nil,
		rows = {
			{ k = "dir",  t = 0,  v = 6 },
			{ k = "dead", t = 20, v = "Cmd Expired" },
			{ k = "guard", t = 34 },
			{ k = "dir",  t = 47, v = 8 },
		},
	}
	hud_mod.draw_gc_command_trace()
	arrows = {}
	for _, im in ipairs(images) do
		local s0 = tostring(im.img)
		if s0:find("^dir") or s0:find("_dir_warn") then arrows[#arrows + 1] = s0 end
	end
	want("切れた後の矢印は白", table.concat(arrows, " "), "dir6 dir8")

	-- 数字の色と矢印の色は同じでなければならない。矢印は生成物なので、
	-- 生成スクリプトの色と GCT_WARN がずれていないかを見る。
	local gen = io.open("../analysis/make_warn_arrows.py"):read("*a")
	local r, g, b = gen:match("WARN = %(0x(%x%x), 0x(%x%x), 0x(%x%x)%)")
	local hex = hud:match('local GCT_WARN = "#(%x%x%x%x%x%x)"')
	want("矢印の色と数字の色が一致",
		r and hex and (r .. g .. b):upper() == hex:upper(), true)
end

print("")
print("[11] 持続中のガードは G-Persist と何ティック目かを描く")
do
	-- ガード方向を離した後、ポーズの持続中に当たったガード (本人、2026-09-25)。
	-- 行の値に持続のティックが入っている。入れたままのガードは値なしで Guard。
	calls, bad, images = {}, {}, {}
	globals.gc_trace = {
		guard = 20, done = nil, at = nil,
		rows = {
			{ k = "dir",   t = 8,  v = 6 },
			{ k = "guard", t = 20, v = 3 },
		},
	}
	hud_mod.draw_gc_command_trace()
	local labels, nums = {}, {}
	for _, c in ipairs(calls) do
		if type(c.s) == "string" then
			labels[c.s] = c
			if c.s:find("t%)?$") then nums[c.s] = c end
		end
	end
	want("G-Persist 3 と描く", labels["G-Persist 3"] ~= nil, true)
	want("Guard とは描かない", labels["Guard"], nil)
	want("括弧の数字は今までどおり", nums["(12t)"] ~= nil, true)
	-- ラベルと括弧の数字が重ならない (1 文字 4.2px)。
	local g, n = labels["G-Persist 3"], nums["(12t)"]
	want("ラベルと数字が重ならない",
		g ~= nil and n ~= nil and (g.x + #g.s * 4.2) < n.x, true)
	want("色が nil のまま渡された描画は無い", table.concat(bad, ", "), "")

	calls, bad, images = {}, {}, {}
	globals.gc_trace.rows[2].v = nil
	hud_mod.draw_gc_command_trace()
	labels = {}
	for _, c in ipairs(calls) do if type(c.s) == "string" then labels[c.s] = c end end
	want("値が無ければ Guard", labels["Guard"] ~= nil, true)

	-- 2 桁と 3 桁の最悪でも重ならない。
	calls, bad, images = {}, {}, {}
	globals.gc_trace = {
		guard = 130, done = nil, at = nil,
		rows = {
			{ k = "dir",   t = 10,  v = 6 },
			{ k = "guard", t = 130, v = 12 },
		},
	}
	hud_mod.draw_gc_command_trace()
	labels, nums = {}, {}
	for _, c in ipairs(calls) do
		if type(c.s) == "string" then
			labels[c.s] = c
			if c.s:find("t%)$") then nums[c.s] = c end
		end
	end
	g, n = labels["G-Persist 12"], nums["(120t)"]
	want("G-Persist 12 と (120t) も重ならない",
		g ~= nil and n ~= nil and (g.x + #g.s * 4.2) < n.x, true)
end

print("")
print("[12] ガード行が当たったティックにあるとき - 数字は各行の前から、Success は受付から")
do
	-- 2026-09-25 の実機の形。当たりは 9、受付と → は 10。ガード行を当たりに
	-- 置くので → が下に来て 1t。Success は入力履歴の SUCCESS と同じく受付から。
	calls, bad, images = {}, {}, {}
	globals.gc_trace = {
		guard = 10, done = "Success", at = 23,
		rows = {
			{ k = "guard", t = 9,  v = 6 },
			{ k = "dir",   t = 10, v = 6 },
			{ k = "dir",   t = 15, v = 2 },
			{ k = "dir",   t = 20, v = 3 },
			{ k = "btn",   t = 23, v = { true } },
		},
	}
	hud_mod.draw_gc_command_trace()
	local seq = {}
	for _, c in ipairs(calls) do
		if type(c.s) == "string" and c.s ~= "GC Command Trace" then seq[#seq + 1] = c.s end
	end
	want("描かれる文字列の順", table.concat(seq, " / "),
		"G-Persist 6 / 1t / 5t / 5t / 3t / Success / 13t")
	want("色が nil のまま渡された描画は無い", table.concat(bad, ", "), "")

	-- 当たりと受付の間にコマンドが切れた形。ガードが死んだ印より上なので、
	-- どちらも前の入力から数え、255t に回り込まない。
	calls, bad, images = {}, {}, {}
	globals.gc_trace = {
		guard = 36, done = nil, at = nil,
		rows = {
			{ k = "dir",   t = 10, v = 6 },
			{ k = "guard", t = 34 },
			{ k = "dead",  t = 35, v = "Cmd Expired" },
			{ k = "dir",   t = 36, v = 6 },
		},
	}
	hud_mod.draw_gc_command_trace()
	seq = {}
	for _, c in ipairs(calls) do
		if type(c.s) == "string" and c.s ~= "GC Command Trace" then seq[#seq + 1] = c.s end
	end
	want("死んだ印の上のガード", table.concat(seq, " / "),
		"Guard / (24t) / Cmd Expired / 25t / 1t")
end

print("")
print("[13] 遅れたボタンは、押していない点をオレンジにする。押した点の色はそのまま")
do
	-- 矢印は白い塗りをオレンジにして警告する。ボタンでそれに当たるのは空きの点で、
	-- 押した点は強さの色なので残す。先に試したオレンジの枠は、トレースの中で
	-- ひとつだけの四角になり、選択中のカーソルに見えた (本人、2026-09-26)。
	local warn_dot = "png:images/no_button_warn.png"
	local boxes = {}
	local was_box = gui.box
	gui.box = function(x1, y1, x2, y2, fill, line) boxes[#boxes + 1] = line end
	local function dots()
		local out = {}
		for _, im in ipairs(images) do
			local s0 = tostring(im.img)
			if s0 == warn_dot then s0 = "W" end
			if s0 == "n" or s0 == "l" or s0 == "m" or s0 == "h" or s0 == "W" then
				out[#out + 1] = s0
			end
		end
		return table.concat(out, "")
	end
	local function draw(rows)
		calls, bad, images, boxes = {}, {}, {}, {}
		globals.gc_trace = { guard = rows[1].t, done = nil, at = nil, rows = rows }
		hud_mod.draw_gc_command_trace()
	end

	-- 右下から 12t 遅れた LP + HP。点は列ごとに上・下 (上L 下L 上M 下M 上H 下H) の順に描く。
	draw({
		{ k = "guard", t = 5 },
		{ k = "dir",   t = 10, v = 3 },
		{ k = "btn",   t = 22, v = { true, false, true, false, false, false } },
	})
	want("空きの点はオレンジ、押した点はそのまま", dots(), "lWWWhW")
	local num
	for _, c in ipairs(calls) do if c.s == "12t" then num = c end end
	want("数字もオレンジ (同じ判定)", num and num.c, "#FF7F00")
	local framed = 0
	for _, l in ipairs(boxes) do if l == "#FF7F00" then framed = framed + 1 end end
	want("枠は描かない", framed, 0)

	-- 中ボタンを押しても中の色のまま (空きだけがオレンジ)。
	draw({
		{ k = "guard", t = 5 },
		{ k = "dir",   t = 10, v = 3 },
		{ k = "btn",   t = 30, v = { false, true, false, false, true, false } },
	})
	want("中ボタンは中の色", dots(), "WWmmWW")

	-- 11t なら空きの点はいつもの灰色。
	draw({
		{ k = "guard", t = 5 },
		{ k = "dir",   t = 10, v = 3 },
		{ k = "btn",   t = 21, v = { false, false, true, false, false, false } },
	})
	want("11t はいつもの点", dots(), "nnnnhn")

	-- ガードから数えたボタン (前に入力が無い) は警告しない。数字と同じ。
	draw({
		{ k = "guard", t = 5 },
		{ k = "btn",   t = 30, v = { true } },
	})
	want("ガードから数えたボタンはいつもの点", dots(), "lnnnnn")

	-- 絵は生成物。矢印と同じスクリプトが同じ色で作る。
	local gen = io.open("../analysis/make_warn_arrows.py"):read("*a")
	want("生成スクリプトが空きの点も作る",
		gen:find('recolour("no_button.png", "no_button_warn.png"', 1, true) ~= nil, true)
	local f = io.open("images/no_button_warn.png", "rb")
	want("絵が配布物の中にある", f ~= nil, true)
	if f then f:close() end
	gui.box = was_box
end

if fails == 0 then print("") print("全て通った") else print(fails .. " 件 NG") os.exit(1) end
