-- 空中の Auto (After) - いつ押してよいか。出るかどうかはゲームが決める。
--
-- WHY THIS EXISTS. 空中の Auto (After) は、ROM の空中攻撃の判定 2 つを写して
-- いた - セルの許可ビットと、$1a6 (この滞空で使ったボタン)。どちらかが拒めば
-- 押さなかった。
--
-- 同じボタンを Lua 側で止めるのはやめる (本人、2026-09-25)。バレッタでも
-- ジャンプ中 P -> 中 K (空振り) -> 中 K が 1 回のジャンプで出るし、アナカリスは
-- 浮遊中に MP を 4 回・5 回出す間ずっと $1a6 に MP のビットが立ったままだった
-- (実測、手で 2 回)。出ない判定はゲームに任せる。
--
-- 残るのはタイミングで、次のどちらかで押してよい。
--   * $07 が 02 に戻った (空中の待機 = 前の攻撃が終わった)。アナカリスの浮遊は
--     これしか無い - セルの許可ビットが一度も立たず、連発はすべて 02 に戻って
--     から 2〜5 フレーム後だった
--   * セルの許可ビット (($1c)+1 の bit 1)。攻撃が終わる前に繋がる最速。ジェダで
--     実測 (25 と 24)
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_air_ready.lua
local NL = string.char(10)
local src = io.open("actionSequenceRunner.lua"):read("*a")

local fails = 0
local function want(what, got, expected)
	if got == expected then
		print("  ok " .. what)
	else
		fails = fails + 1
		print("  NG " .. what)
		print("     got  [" .. tostring(got) .. "]  want [" .. tostring(expected) .. "]")
	end
end

-- air_ready から dummy_free の end まで。
local s = src:find("local function air_ready()", 1, true)
local d = src:find("local function dummy_free(step)", s or 1, true)
local e = src:find(NL .. "end", d or 1, true)
assert(s ~= nil and d ~= nil and e ~= nil, "air_ready / dummy_free の区間が見つからない")

local P2 = 0xFF8800
local CEL = 0x123456
local ram = {}
memory = {
	readbyte = function(a) return ram[a] or 0 end,
	readdword = function(a) return (a == P2 + 0x1C) and CEL or 0 end,
}
P2_BASE = P2
assert(loadstring(src:sub(s, e + 4) .. NL .. "_G.dummy_free = dummy_free"))()

-- 空中、やられでもない、が土台。
local function air(s07, cel1, s1a6)
	ram = {}
	ram[P2 + 0x38] = 1
	ram[P2 + 0x05] = 0
	ram[P2 + 0x06] = 0x06
	ram[P2 + 0x07] = s07
	ram[CEL + 1] = cel1
	ram[P2 + 0x1A6] = s1a6 or 0
end
local MP = { button = "MP" }

print("[1] アナカリスの浮遊 - 待機に戻れば押す")
do
	-- 実測の形: セルの許可ビットは立たず、$1a6 には MP が残っている。
	air(0x02, 0x00, 0x02)
	want("待機 (02) なら押す", dummy_free(MP), true)
	air(0x06, 0x00, 0x02)
	want("攻撃中 (06) は待つ", dummy_free(MP), false)
	air(0x04, 0x40, 0x02)
	want("着地 (04) は待つ", dummy_free(MP), false)
end

print("")
print("[2] 使ったボタンでは止めない - 全キャラ")
do
	-- バレッタ: 中 K を空振りした後にもう一度中 K。$1a6 に MK (bit 5) がある。
	air(0x02, 0x00, 0x20)
	want("待機に戻っていれば同じボタンも押す", dummy_free({ button = "MK" }), true)
	air(0x06, 0x02, 0xFF)
	want("許可ビットが立てば $1a6 が全部立っていても押す", dummy_free(MP), true)
end

print("")
print("[3] セルの許可ビットは今までどおり - 繋がる最速")
do
	-- ジェダの空中チェーン: 攻撃中 (06) でも、次を許すセルに入れば押す。
	air(0x06, 0x02, 0x00)
	want("攻撃中でも許可ビットで押す", dummy_free(MP), true)
	air(0x06, 0x01, 0x00)
	want("bit 1 でなければ押さない", dummy_free(MP), false)
end

print("")
print("[4] 地上とやられは変わらない")
do
	air(0x02, 0x02, 0x00)
	ram[P2 + 0x05] = 0x0E
	want("やられ中は押さない", dummy_free(MP), false)
	ram = {}
	ram[P2 + 0x38] = 0
	ram[P2 + 0x06] = 0x00
	want("地上で動作が無ければ押す", dummy_free(MP), true)
	ram[P2 + 0x06] = 0x0A
	want("地上で技の途中は待つ", dummy_free(MP), false)
end

print("")
print("[5] $1a6 を読まない")
do
	local a = src:find("local function air_ready()", 1, true)
	local b = src:find(NL .. "end", a or 1, true)
	local body = src:sub(a or 1, (b or 1) + 4)
	want("air_ready は $1a6 を読まない", body:find("0x1A6", 1, true), nil)
	want("ボタンを受け取らない", src:find("air_ready(step", 1, true), nil)
end

print("")
if fails == 0 then
	print("ALL OK")
else
	print(fails .. " NG")
	os.exit(1)
end
