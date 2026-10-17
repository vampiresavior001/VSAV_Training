-- THE HUD'S "Bubble" READOUT (scripts/vsavscriptv2.lua, v11.7.28.3).
--
-- Reported 2026-10-17: "殴った時にまれに足元にBUBBLE". The line was asked as
-- P2 $46 == 0x4000, which also turned up on ordinary hits. It now asks what the
-- game says about Aulbath's Water Jail: P2 in a hit reaction ($05 2), hit type
-- ($54) 0x2D, some of its count ($15C) left.
--
-- The HUD is sliced out of the file and run against a stand-in for the memory
-- (vsavscriptv2.lua itself loads gd and image files).
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_hud_bubble.lua
local fails = 0
local function eq(what, got, want)
	if got == want then print("  ok " .. what .. " = " .. tostring(got))
	else
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(want) .. "]")
	end
end
local function slurp(p)
	local fh = io.open(p)
	assert(fh, p .. " が読めない")
	local s = fh:read("*a")
	fh:close()
	return s
end

local src = slurp("vsavscriptv2.lua")
local s = src:find("local function hud()", 1, true)
local e = s and src:find("\nend\n", s, true)
assert(s and e, "hud() が見つからない")
local ram, drawn = {}, {}
memory = {
	readbyte = function(a) return ram[a] or 0 end,
	readword = function(a) return ram[a] or 0 end,
	readdword = function(a) return ram[a] or 0 end,
}
gui = { text = function(_, _, t) drawn[#drawn + 1] = t end, box = function() end }
globals = { show_life = false, show_meter = false, show_position = false, options = {} }
local hud = assert(loadstring(src:sub(s, e + 4) .. "\nreturn hud"))()

local P2 = 0xFF8800
local function bubble()
	drawn = {}
	hud()
	for _, t in ipairs(drawn) do if t:find("^Bubble ") then return t end end
	return nil
end
local function set(st05, hit54, count, w46)
	ram = {}
	ram[P2 + 0x05] = st05
	ram[P2 + 0x54] = hit54
	ram[P2 + 0x15C] = count
	ram[P2 + 0x46] = w46
end

print("[1] ウォータージェイルのときだけ出す")
set(0x02, 0x2D, 300)
eq("やられ中・0x2D・残りあり", bubble(), "Bubble 300")
set(0x02, 0x2D, 0)
eq("残りが 0 (抜けた)", bubble(), nil)
set(0x00, 0x2D, 300)
eq("やられ中でない", bubble(), nil)
set(0x02, 0x24, 300)
eq("別のやられ (ビッグブランチ 0x24)", bubble(), nil)

print("[2] 以前の条件 ($46 == 0x4000) だけでは出さない")
set(0x02, 0x00, 0, 0x4000)
eq("$46 が 0x4000 の普通の当たり", bubble(), nil)
eq("ソースに $46 の判定が残っていない", src:find("readword(0xff8846) == 0x4000", 1, true), nil)

print("[3] 呪いの表示はそのまま")
set(0x02, 0x2D, 300)
ram[P2 + 0x14E] = 0x0808
ram[P2 + 0x156] = 5
drawn = {}
hud()
eq("呪われている間は CURSED (Bubble より先)", drawn[1], "CURSED 5")

print(fails == 0 and "\n全て通った" or ("\n" .. fails .. " 件 NG"))
os.exit(fails == 0 and 0 or 1)
