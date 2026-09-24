-- 「このプレイヤーはキャラを選んだか」— ゲームが書く値では答えられない。
--
-- $3BD と $3E0 はキャラ ID で、バレッタは 0x00。$3AE とその写し $3E1 は
-- 決定に使ったボタンの番号で、実測では MP が 1、LK が 3、MK が 4 -
-- 並びは LP MP HP LK MK HK なので LP は 0 (2026-09-23)。
--
-- つまり「バレッタを LP で決定」すると 4 バイトとも 0 のまま。キャラは
-- 選ばれているのに、読める値が無い。アーケードスティックのミラーが 2P へ
-- 渡らない不具合はこれで、バレッタ「かつ」弱パンチのときだけ起きる。
-- 本人が実機でその組み合わせに切り分けた。
--
-- $380..$3FF を 4 セッション毎フレーム走査して、この決定で動く別のバイトは
-- 無いことを確認済み。$3BC と $3E3 は逆アセンブル上それらしく見えるが
-- 終始 0。
--
-- なので決定そのものを見る。選択画面では攻撃ボタンが決定で、$394 が入力の
-- ボタン側。
--
-- Run from scripts/ - the dofile below is relative.
--   cd scripts && lua5.1 ../analysis/test_char_chosen_press.lua
local P1, P2 = 0xFF8400, 0xFF8800
local ram = {}
memory = {
	readbyte = function(a) return ram[a] or 0 end,
	readword = function(a) return ram[a] or 0 end,
	readdword = function(a) return ram[a] or 0 end,
	writebyte = function(a, v) ram[a] = v end,
}
gui = { text = function() end, box = function() end }
emu = { framecount = function() return 1 end }
globals = { options = {} }
-- utilities.lua は json を require する。ここでは使わないので差し替える。
package.preload["./scripts/dkjson"] = function()
	return { encode = function() return "{}" end, decode = function() return nil end }
end
package.preload["dkjson"] = package.preload["./scripts/dkjson"]
local util = dofile("utilities.lua")

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

local CSS = 0xFF8009
local function css(on) ram[CSS] = on and 2 or 0 end
-- 値を消すだけでは足りない。latch は選択画面を離れたときに落ちるので、
-- 新しい試行を始めるには画面を一度出る。
local function clear(base)
	ram[base + 0x3BD], ram[base + 0x3E1] = 0, 0
	ram[base + 0x394] = 0
	ram[0xFF8009] = 0
	util.char_chosen(base)
	ram[0xFF8009] = 2
	util.char_chosen(base)
end
-- 1 フレーム進める。char_chosen は毎フレーム呼ばれる想定。
local function frame(base) return util.char_chosen(base) end

print("[1] バレッタを LP で決定 - ゲームは何も書かない")
-- ID 0 かつボタン番号 0 なので $3BD も $3E1 も 0 のまま。
do
	css(true)
	clear(P1)
	want("押す前は false", frame(P1), false)
	ram[P1 + 0x394] = 0x01                 -- LP
	want("押した瞬間に true", frame(P1), true)
	ram[P1 + 0x394] = 0x00                 -- 離す
	want("離しても true のまま", frame(P1), true)
	want("ゲームが書いた値は 0 のまま", ram[P1 + 0x3BD], 0)
end

print("")
print("[2] 従来どおりの経路も残っている")
do
	css(true)
	clear(P2)
	want("押す前は false", frame(P2), false)
	ram[P2 + 0x3BD] = 0x05                 -- モリガン
	want("ID が入れば true", frame(P2), true)
	clear(P2)
	frame(P2)
	ram[P2 + 0x3E1] = 0x04                 -- ボタン番号だけ入る場合
	want("$3E1 でも true", frame(P2), true)
end

print("")
print("[3] 攻撃ボタン以外では立たない")
-- Start や Coin で立つと、キャラを選ぶ前に「選んだ」ことになる。
do
	css(true)
	clear(P1)
	frame(P1)
	for _, bit in ipairs({ 0x08, 0x80 }) do
		ram[P1 + 0x394] = bit
		want(string.format("0x%02X では立たない", bit), frame(P1), false)
		ram[P1 + 0x394] = 0
		frame(P1)
	end
	-- 6 つの攻撃ボタンはどれでも立つ。LP が 0 番なのが今回の件。
	for _, bit in ipairs({ 0x01, 0x02, 0x04, 0x10, 0x20, 0x40 }) do
		clear(P1)
		frame(P1)
		ram[P1 + 0x394] = bit
		want(string.format("0x%02X で立つ", bit), frame(P1), true)
		ram[P1 + 0x394] = 0
	end
end

print("")
print("[4] 選択画面を離れたら落ちる")
-- 残ると、次に選択画面へ来たとき最初から「選んでいる」ことになり、
-- ミラーが自分のキャラを選ぶ前から動く。
do
	css(true)
	clear(P1)
	frame(P1)
	ram[P1 + 0x394] = 0x01
	want("立っている", frame(P1), true)
	ram[P1 + 0x394] = 0
	css(false)
	want("選択画面を出たら false", frame(P1), false)
	css(true)
	want("戻ってきても false のまま", frame(P1), false)
end

print("")
print("[5] 片方だけが立つ")
-- 1P が選んで 2P がまだ、がミラーの動く条件そのもの。
do
	css(true)
	clear(P1) clear(P2)
	frame(P1) frame(P2)
	ram[P1 + 0x394] = 0x01
	want("P1 は true", frame(P1), true)
	want("P2 は false のまま", frame(P2), false)
end

print("")
print("[6] 押しっぱなしで選択画面へ入っても立たない")
-- 前の画面で押したボタンを持ったまま選択画面へ入るのは普通に起きる。
-- 水準で見ると、キャラを選ぶ前に「選んだ」ことになり、ミラーが自分の
-- カーソルを動かせなくなる。押し始め (端) で見ること。
do
	css(false)
	ram[P1 + 0x3BD], ram[P1 + 0x3E1] = 0, 0
	ram[P1 + 0x394] = 0x01            -- 前の画面から押しっぱなし
	frame(P1)
	css(true)
	want("入った直後は false", frame(P1), false)
	want("押したままなら立たない", frame(P1), false)
	ram[P1 + 0x394] = 0x00            -- 一度離す
	want("離しても false", frame(P1), false)
	ram[P1 + 0x394] = 0x01            -- 押し直す
	want("押し直せば立つ", frame(P1), true)
end
if fails == 0 then print("") print("全て通った") else print(fails .. " 件 NG") os.exit(1) end
