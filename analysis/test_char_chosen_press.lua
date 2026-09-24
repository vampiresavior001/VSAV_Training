-- 「このプレイヤーはキャラを選んだか」— 選択画面の $04 で答える。
--
-- 実測 (2026-09-24、選択画面 6 回分、両プレイヤーの $04/$05 を変化のたびに記録):
--
--     $04 $05
--     00  00   受付前 (画面が出てくる途中)
--     00  02   選択中。カーソルが動く
--     02  06   決定の押しが通った (1 フレーム)
--     04  00   決定済み
--
-- これで 3 つが同時に片付いた。
--
--   * バレッタを LP で決定しても $04 は 04 になる。$3BD と $3E1 はどちらも 0 の
--     ままで、ここがずっと答えられなかった穴。
--   * 受付前にボタンを押しても $04 は 00 のまま (早押し 3 回を記録)。押下 latch は
--     まさにそこで立ち、1 本のスティックで両方のカーソルが動いた。
--   * $3BD は古い値が残る。選択画面に戻った直後、前の試合の選択を持ったまま
--     $04 だけ 00 に戻っていた。$3BD は最初から「今回選んだか」ではなかった。
--
-- ログは scripts/reversal_logs_archive/2026-09-24-css-confirm/ に退避してある。
--
-- Run from scripts/ - the dofile below is relative.
--   cd scripts && lua5.1 ../analysis/test_char_chosen_press.lua
local P1, P2 = 0xFF8400, 0xFF8800
local CSS = 0xFF8009
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

-- 1 プレイヤーぶんの状態を置く。
local function state(base, s04, s05)
	ram[base + 0x04], ram[base + 0x05] = s04, s05
end

print("[1] 局面ごとの答え")
do
	ram = {}
	ram[CSS] = 2
	state(P1, 0x00, 0x00)
	want("受付前は false", util.char_chosen(P1), false)
	state(P1, 0x00, 0x02)
	want("選択中は false", util.char_chosen(P1), false)
	state(P1, 0x02, 0x06)
	want("決定の押しが通った 1 フレームも true", util.char_chosen(P1), true)
	state(P1, 0x04, 0x00)
	want("決定済みは true", util.char_chosen(P1), true)
end

print("")
print("[2] バレッタを LP で決定 - 元の不具合")
do
	-- キャラ id 0、ボタン番号 0。値では見えないが $04 は 04 になる (frame 2824)。
	ram = {}
	ram[CSS] = 2
	ram[P1 + 0x3BD], ram[P1 + 0x3E1] = 0, 0
	state(P1, 0x04, 0x00)
	want("選んだと答える", util.char_chosen(P1), true)
end

print("")
print("[3] 受付前の押しでは立たない - 両カーソル同時の不具合")
do
	-- 早押し 3 回とも $04 は 00 のまま (frame 1743 / 1751 / 1760)。
	ram = {}
	ram[CSS] = 2
	state(P1, 0x00, 0x00)
	ram[P1 + 0x394] = 0x01
	want("押しても false", util.char_chosen(P1), false)
	ram[P1 + 0x396] = 0x01
	want("押しっぱなしでも false", util.char_chosen(P1), false)
end

print("")
print("[4] 戻った直後の古い $3BD では立たない")
do
	-- 選択画面に戻った瞬間、$3BD は前の試合の値のまま $04 だけ 00
	-- (frame 2573: P1 01 / P2 04、frame 2279: P1 01 / P2 0A)。
	ram = {}
	ram[CSS] = 2
	ram[P1 + 0x3BD], ram[P2 + 0x3BD] = 0x01, 0x0A
	state(P1, 0x00, 0x00)
	state(P2, 0x00, 0x00)
	want("1P は選んでいない", util.char_chosen(P1), false)
	want("2P も選んでいない", util.char_chosen(P2), false)
end

print("")
print("[5] 2P も同じ規則")
do
	-- 2P が決定したときも 02/06 -> 04/00 (frame 2287 / 1993)。
	ram = {}
	ram[CSS] = 2
	state(P2, 0x00, 0x02)
	want("選択中は false", util.char_chosen(P2), false)
	state(P2, 0x04, 0x00)
	want("決定済みは true", util.char_chosen(P2), true)
	-- 1P の決定は 2P の答えに影響しない。
	state(P1, 0x04, 0x00)
	state(P2, 0x00, 0x02)
	want("1P だけ決定なら 2P は false", util.char_chosen(P2), false)
end

print("")
print("[6] 読むのは $04 だけ - 状態も押下も持たない")
do
	local src = io.open("utilities.lua"):read("*a")
	local a = src:find("local function char_chosen(base_addr)", 1, true)
	local b = src:find(string.char(10) .. "end", a or 1, true)
	local body = src:sub(a or 1, (b or 1) + 4)
	want("$04 を読む", body:find("base_addr + 0x04", 1, true) ~= nil, true)
	want("$3BD を読まない (古い値が残る)", body:find("0x3BD", 1, true), nil)
	want("押下を読まない", body:find("0x394", 1, true), nil)
	want("latch を持たない", body:find("css_picked", 1, true), nil)
end

if fails == 0 then print("") print("全て通った") else print(fails .. " 件 NG") os.exit(1) end
