-- "HAS THIS PLAYER CHOSEN A CHARACTER YET", INCLUDING WHEN THEY CHOSE BULLETA.
--
-- The arcade-stick mirror and the stage cursor both ask this. They used to ask
-- it of $3BD alone, which is the character id - and Bulleta is 0x00, so she
-- answered the same as an empty slot. Control never passed to P2 for her, and
-- for nobody else, because she is the only character numbered zero.
--
-- SUPERSEDED MODEL (2026-09-12): $3BD or $3E1, from analysis/select_probe.log.
-- It could not see Bulleta picked with LP (both bytes 0), and $3BD turned out to
-- keep the LAST match's pick when the select screen comes back.
--
-- CURRENT (2026-09-24): $04 on the select screen - 00 before picks are taken,
-- 00 while picking, 02 for the one frame the confirm is taken, 04 once
-- confirmed. See analysis/test_char_chosen_press.lua for the full table and the
-- logs it came from. This file keeps the shapes the mirror depends on.
--
--   cd C:/fightcaVSAV-Debug/emulator/fbneo && lua5.1 analysis/test_char_chosen.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local ram = {}
memory = {
	readbyte = function(a) return ram[a] or 0 end,
	readword = function(a) return ram[a] or 0 end,
	readdword = function(a) return ram[a] or 0 end,
	writebyte = function(a, v) ram[a] = v end,
}
emu = { framecount = function() return 0 end }
gui = { text = function() end }

local util = dofile("scripts/utilities.lua")
local P1, P2 = 0xFF8400, 0xFF8800

local fails = 0
local function want(what, got, w)
	if got ~= w then
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(w) .. "]")
	else
		print("  ok " .. what)
	end
end

local function clear()
	for _, b in ipairs({ P1, P2 }) do
		ram[b + 0x3BD], ram[b + 0x3E1] = 0, 0
		ram[b + 0x04], ram[b + 0x05] = 0x00, 0x02   -- 選択中
	end
end
local function confirm(b) ram[b + 0x04], ram[b + 0x05] = 0x04, 0x00 end

clear()
want("誰も選んでいない", util.char_chosen(P1), false)

-- デミトリを選んだ P1。$04 が 04 になる。
confirm(P1)
ram[P1 + 0x3BD], ram[P1 + 0x3E1] = 0x01, 0x01
want("デミトリを選んだ", util.char_chosen(P1), true)
want("相手はまだ選んでいない", util.char_chosen(P2), false)

-- ビシャモンを選んだ P2。
confirm(P2)
ram[P2 + 0x3BD], ram[P2 + 0x3E1] = 0x08, 0x03
want("ビシャモンを選んだ", util.char_chosen(P2), true)

-- これが直したかったもの。バレッタを LP で選ぶと $3BD も $3E1 も 0 のまま。
clear()
confirm(P1)
want("バレッタ + LP でも選択済みと分かる", util.char_chosen(P1), true)

-- 逆に、$3BD が立っていても $04 が 00 なら選んでいない - 選択画面に戻った
-- 直後は前の試合の値が残っている。
clear()
ram[P1 + 0x3BD] = 0x0A
want("古い $3BD だけでは選択済みにしない", util.char_chosen(P1), false)

-- 片側だけ選んでいる状態。ミラーはこの形のときだけ働く。
clear()
confirm(P1)
want("バレッタの P1 は選択済み", util.char_chosen(P1), true)
want("P2 は未選択のまま", util.char_chosen(P2), false)

if fails == 0 then print("全て通った") else print(fails .. " 件 NG") os.exit(1) end
