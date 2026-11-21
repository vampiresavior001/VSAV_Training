-- A RESTORE DOES NOT OVERWRITE THE ROUND'S START (scripts/position.lua), 2026-11-21.
--
-- The centre arrangements slide the pair to where the round began, caught when
-- both X jump in one frame. A recording's start-position restore (macro.lua
-- restore_playback_pos, before each pass; the wizard's restore) moves both in
-- one frame too, and replaced the centre with a spot part-way through the
-- restore (user: the slide to the centre sometimes went somewhere else).
--
--   lua5.1 analysis/test_position_restore_start.lua
--
--   [1] a restore leaves the start alone, and puts the pair where it was asked
--   [2] a round that really starts after it is still caught
local P1, P2 = 0xFF8400, 0xFF8800
local fails = 0
local function eq(what, got, want)
	if got == want then print("  ok " .. what .. " = " .. tostring(got))
	else
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(want) .. "]")
	end
end

local ram = {}
memory = {
	readbyte = function(a) return ram[a] or 0 end,
	readword = function(a) return ram[a] or 0 end,
	readdword = function(a) return ram[a] or 0 end,
	writebyte = function(a, v) ram[a] = v end,
	writeword = function(a, v) ram[a] = v % 0x10000 end,
}
local frame = 0
emu = { framecount = function() return frame end }
gui = { text = function() end }
input = { registerhotkey = function() end }
joypad = { get = function() return {} end, set = function() end }
globals = { hotkeys_armed = true, options = { stage_position = 4 }, _input = {} }
-- position.lua's trace must not write the emulator's log (test_position_hotkey.lua).
local real_open = io.open
io.open = function(name, mode)
	if mode == "a" or mode == "w" then return nil end
	return real_open(name, mode)
end
local pos = dofile("scripts/position.lua")
local function tick(n) for _ = 1, n do frame = frame + 1 pos.registerBefore() end end

ram[P1 + 0x10], ram[P2 + 0x10], ram[0xFF8290] = 300, 900, 408
tick(20)
local l0, r0 = pos._start()

print("[1] 記録の開始位置への復元")
pos.camera_restore_start(pos.camera_for(450, 620), 450, 0, 620, 0)
tick(40)
local l, r = pos._start()
eq("中央の左は変わらない", l, l0)
eq("中央の右は変わらない", r, r0)
eq("P1 は記録の位置", ram[P1 + 0x10], 450)
eq("P2 は記録の位置", ram[P2 + 0x10], 620)
eq("復元は終わった", pos.camera_restore_busy(), false)

print("[2] その後の本当のラウンド開始は採る")
ram[P1 + 0x10], ram[P2 + 0x10] = 0, 0
tick(2)
ram[P1 + 0x10], ram[P2 + 0x10] = 560, 720
tick(12)
l, r = pos._start()
eq("左", l, 560)
eq("右", r, 720)

print(fails == 0 and "\n全て通った" or ("\n" .. fails .. " 件 NG"))
os.exit(fails == 0 and 0 or 1)
