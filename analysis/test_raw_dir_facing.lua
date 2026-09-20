-- WHICH FACING A COMMAND IS RESOLVED AGAINST.
--
-- The engine corrects one injected word TWICE, into two fields, using two
-- different bytes:
--
--     02218E: tst.b ($b,A6)      -> $122 is swapped on $b ALONE
--     0221DC: move.b ($120,A6)   -> $12a is swapped on $120 when grounded
--
-- While those two disagree - which is what crossing over does - no single
-- injection can be right for both, so the command has to say which field it
-- will be read out of. A sequence of nothing but horizontals and neutrals is a
-- dash or a walk, read raw out of $122; anything with a button, an up or a
-- down is a command motion, read out of $12a.
--
-- WHAT THIS CATCHES. Measured 2026-09-20 over three crossovers: the tool's own
-- answer flipped one tick before $b did, so the two taps of ONE dash went out
-- as opposite screen directions while the game's reference had not moved -
-- "the same direction twice" failing to be twice, and no second dash.
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_raw_dir_facing.lua
local fails = 0
local function eq(what, got, want)
	if got == want then print("  ok " .. what)
	else
		fails = fails + 1
		print("  NG " .. what)
		print("     got  [" .. tostring(got) .. "]")
		print("     want [" .. tostring(want) .. "]")
	end
end

function copytable(t)
	local o = {}
	for k, v in pairs(t) do
		if type(v) == "table" then o[k] = copytable(v) else o[k] = v end
	end
	return o
end
globals = { options = {} }
debugKnockdownModule = nil

-- The real queue_input_sequence, lifted out of controller.lua. Taking the real
-- one is the point: the classification changing there has to show up here.
local src = io.open("controller.lua"):read("*a")
local NL = string.char(10)
local s = src:find("function queue_input_sequence", 1, true)
local e = src:find(NL .. "end" .. NL, s, true)
assert(s and e, "queue_input_sequence が controller.lua に見つからない")
assert(loadstring(src:sub(s, e + 4)))()

local function classify(seq)
	local p = {}
	queue_input_sequence(p, seq, false)
	assert(p.pending_input_sequence ~= nil, "積まれなかった")
	return p.pending_input_sequence.raw_dir
end

print("[1] 生の方向だけの列は $b で解決する側")
eq("前ダッシュ", classify({ { "forward" }, {}, { "forward" } }), true)
eq("後ろダッシュ", classify({ { "back" }, {}, { "back" } }), true)
eq("先頭にニュートラルがあっても", classify({ {}, { "back" }, {}, { "back" } }), true)
eq("歩き (1 エントリ)", classify({ { "forward" } }), true)
eq("ダッシュキャンセル", classify({ { "forward" }, {}, { "forward" }, { "back" } }), true)

print("")
print("[2] コマンド技は今までどおり $120 側のまま")
-- 下や上が混ざれば必殺技のコマンド。$12a から読まれる。
eq("波動系", classify({ { "down" }, { "down", "forward" }, { "forward", "LP" } }), false)
eq("昇龍系", classify({ { "forward" }, { "down" }, { "down", "forward" }, { "LP" } }), false)
eq("スーパージャンプ", classify({ {}, { "down" }, { "up" } }), false)
-- ボタンが混ざるだけでもコマンド側。方向とボタンが同じティックに来る。
eq("方向つきの通常技", classify({ { "forward", "HP" } }), false)

print("")
print("[3] 方向を持たない列はそもそも関係ない")
eq("プッシュブロック", classify({ { "LP" }, {}, { "LP" } }), false)
eq("素の通常技", classify({ { "LP" } }), false)
eq("しゃがみ", classify({ { "down" } }), false)

print("")
print("[4] 印が付いた列だけ facing_for_input が $b を読む")
-- guardCancel 側は 20 箇所以上から entry_to_bits を呼ぶので、フラグは
-- 引き回さず「いま配っている列」に訊いている。その形を固定する。
local gsrc = io.open("guardCancel.lua"):read("*a")
local fs = gsrc:find("local function facing_for_input()", 1, true)
local fe = gsrc:find(NL .. "end", fs, true)
eq("facing_for_input がある", fs ~= nil, true)
local body = gsrc:sub(fs, fe)
eq("配送中の列に訊いている",
   body:find("pending_input_sequence", 1, true) ~= nil, true)
eq("raw_dir を見ている", body:find("_s.raw_dir == true", 1, true) ~= nil, true)
-- 印が無ければ従来の計算に落ちること。ここが消えると必殺技側が壊れる。
eq("それ以外は side_flag_now のまま",
   body:find("return side_flag_now()", 1, true) ~= nil, true)
-- 空中は従来どおり $b。もともとそうなっている。
eq("空中の判定は残っている", body:find("0xFF8838", 1, true) ~= nil, true)

print("")
print("[5] 振り向くまでダッシュを出さない - 場所とガードを固定する")
-- guardCancel には入力列を配る歩進が 2 つあり、2 行目まで同じ文字列なので
-- 区間で挟んでから探す (CLAUDE.md)。Action Steps 側にしかない目印で閉じる。
local ws = gsrc:find("A DASH CANNOT BE AIMED WHILE THE CHARACTER IS STILL TURNING", 1, true)
local we = gsrc:find("THE PARKED REVERSE RIDES THE FIRST ENTRY THAT HAS ROOM", 1, true)
eq("待ちが入っている", ws ~= nil, true)
eq("Action Steps の歩進の中にある", ws ~= nil and we ~= nil and ws < we, true)
local hold = gsrc:sub(ws, we)
-- 生の方向の列だけ。必殺技のコマンドを待たせると発生が変わる。
eq("raw_dir のときだけ", hold:find("_s0.raw_dir == true", 1, true) ~= nil, true)
eq("向きが食い違っているときだけ",
   hold:find("facing_unsettled()", 1, true) ~= nil, true)
-- 固定フレーム数を書かない。ダッシュ自身の受付窓で頭打ちにする。
eq("窓の長さで頭打ちにしている",
   hold:find("DASH_GRACE_TICKS", 1, true) ~= nil, true)
eq("そうでなければ数えを戻す", hold:find("_s0.face_hold = 0", 1, true) ~= nil, true)

-- facing_unsettled は $b と相手の側を突き合わせるだけ。
local us = gsrc:find("local function facing_unsettled()", 1, true)
local ue = gsrc:find(NL .. "end", us, true)
eq("facing_unsettled がある", us ~= nil, true)
local ub = gsrc:sub(us, ue)
eq("$b を読んでいる", ub:find("0xFF880B", 1, true) ~= nil, true)
eq("相手の側と比べている", ub:find("side_flag_now()", 1, true) ~= nil, true)

if fails == 0 then print("") print("全て通った") else print(fails .. " 件 NG") os.exit(1) end
