-- SPECIFIED'S BUTTON LEVER (scripts/guardCancel.lua button_lever_bits).
--
-- User 2026-10-18: Input Motion Up, Button None, Button Lever Neutral did not
-- jump. With no button the row replaces the motion's last direction, so the
-- Neutral took the Up away. Neutral with no button is ignored now; with a
-- button it is still the dash-neutral normal, and the other directions still
-- replace the last direction with no button ("ジャンプ空中ガードとかは表現でき
-- なくなるよね？" - that use stays).
--
-- The function is lifted out of the file with the table it reads, and run
-- against stand-ins for the settings and the facing.
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_button_lever.lua
local fails = 0
local function eq(what, got, want)
	if got == want then print("  ok " .. what .. " = " .. tostring(got))
	else
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(want) .. "]")
	end
end

local src = assert(io.open("guardCancel.lua")):read("*a")
local s0 = assert(src:find("local BUTTON_LEVER_DIR = {", 1, true))
local f0 = assert(src:find("local function button_lever_bits()", s0, true))
local e0 = assert(src:find("\nend\n", f0, true))
local t_end = assert(src:find("\n}\n", s0, true))
LEVER_DOWN = 0x04
local face = 0
facing_for_input = function() return face end
local chunk = src:sub(s0, t_end + 2) .. "\n" .. src:sub(f0, e0 + 4) .. "\nreturn button_lever_bits"
local lever = assert(loadstring(chunk))()

-- Menu indices (menu.lua counter_attack_lever): 1 As Is, 2 Neutral, 3 Up,
-- 4 Up Forward, 5 Forward, 6 Down Forward, 7 Down, 8 Down Back, 9 Back, 10 Up Back.
local function set(ga, button, i)
	globals = { dummy = { guard_action = ga, counter_attack_button = button },
	            options = { counter_attack_lever = i } }
end

print("[1] Neutral")
set("reversal", "none", 2)
eq("Button None + Neutral: 使わない (モーションのまま)", lever(), nil)
set("counter", "none", 2)
eq("  Counter Attack でも", lever(), nil)
set("reversal", "MP", 2)
eq("ボタンあり + Neutral: 方向を離す (ダッシュ・ニュートラル中P)", lever(), 0)

print("[2] ほかの方向はボタンが無くても置き換える")
face = 0
set("reversal", "none", 10)
eq("Button None + Up Back (向き 0): 上 + 後ろ", lever(), 0x08 + 0x01)
set("reversal", "none", 9)
eq("Button None + Back (向き 0)", lever(), 0x01)
face = 1
eq("  向き 1 では左右が入れ替わる", lever(), 0x02)
face = 0
set("reversal", "LP", 7)
eq("ボタンあり + Down", lever(), 0x04)

print("[3] As Is と Specified 以外")
set("reversal", "none", 1)
eq("As Is: 使わない", lever(), nil)
set("sequence", "none", 9)
eq("Action Steps: 使わない (ステップが自分の方向を持つ)", lever(), nil)

print(fails == 0 and "\n全て通った" or ("\n" .. fails .. " 件 NG"))
os.exit(fails == 0 and 0 or 1)
