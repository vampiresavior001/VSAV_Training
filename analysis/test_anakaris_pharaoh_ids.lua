-- ANAKARIS: 0x14 IS PHARAOH SALVATION, 0x1C IS PHARAOH DECORATION.
--
-- The move list had the two the wrong way round (fixed 2026-10-07, from
-- darkstalkers.web.fc2.com's Anakaris EX move page checked against the ROM).
-- Picking "P. Salvation" as a Character Specific Reversal poked 0x1C, which is
-- Decoration, and Tick Data named each one as the other.
--
-- What must NOT change with it, and is pinned here too:
--   - the names, which Action Steps save and look the command up by;
--   - the commands themselves, which were right all along;
--   - the order of the list, because p2_reversal_list saves a position in it.
--
-- Run from scripts/ - the dofile below is relative.
--   cd scripts && lua5.1 ../analysis/test_anakaris_pharaoh_ids.lua

local ram = {}
memory = {
	readbyte = function(a) return ram[a] or 0 end,
	readword = function(a) return ram[a] or 0 end,
}
globals = { options = {} }
local M = dofile("charMoves.lua")

local fails = 0
local function want(what, got, w)
	if got ~= w then
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(w) .. "]")
	else
		print("  ok " .. what)
	end
end

-- Both players Anakaris ($382 = 0x06), through the module as the script uses it.
ram[0xFF8400 + 0x382] = 0x06
ram[0xFF8800 + 0x382] = 0x06
local moves = M.registerBefore()
globals.char_moves = moves

local function by_name(list, name)
	local hit
	for _, m in ipairs(list) do
		if m.name == name then hit = m end     -- the last one, as the lookups do
	end
	return hit
end
local function by_value(list, v)
	for _, m in ipairs(list) do
		if m.value == v then return m end
	end
	return nil
end

print("-- 技 ID と名前")
local all = moves.P2.all
want("0x14 は P. Salvation", (by_value(all, 0x14) or {}).name, "P. Salvation")
want("0x1C は Pharoah Decoration", (by_value(all, 0x1C) or {}).name, "Pharoah Decoration")
want("P. Salvation は 0x14", (by_name(all, "P. Salvation") or {}).value, 0x14)
want("Pharoah Decoration は 0x1C", (by_name(all, "Pharoah Decoration") or {}).value, 0x1C)

print("-- 入力列は変えない")
local function seq(name)
	local m = by_name(all, name)
	local c = m and m.command
	if c == nil or c.sequence == nil then return nil end
	local out = {}
	for _, step in ipairs(c.sequence) do out[#out + 1] = table.concat(step, "+") end
	return table.concat(out, " ")
end
want("Salvation: HK MP 2 MK HP", seq("P. Salvation"), "HK MP down MK HP")
want("Decoration: HK MP LK 2 LP MK HP", seq("Pharoah Decoration"), "HK MP LK down LP MK HP")
want("Salvation の表示名", (by_name(all, "P. Salvation") or {}).command.display_name, "Pharaoh Salvation")
want("Decoration の表示名", (by_name(all, "Pharoah Decoration") or {}).command.display_name, "Pharaoh Decoration")

print("-- 一覧の並び (p2_reversal_list は位置で保存される)")
local names = {}
for _, m in ipairs(get_moves_Anakaris()) do names[#names + 1] = m.name end
want("並びは前と同じ", table.concat(names, " | "), table.concat({
	"Coffin", "Spell of Turn - IN", "Spell of Turn - OUT", "Curse", "Cobra Blow",
	"Hands", "Float", "Pit to Underworld", "Pharoah Magic", "Pharoah Magic",
	"P. Salvation", "Pharoah Decoration", "Pursuit", "Pit of Blame",
	"Guard Cancel", "Taunt" }, " | "))

print("-- Character Specific Reversal が書き込む値")
-- The lookup itself, lifted out of dummyState.lua rather than copied.
local src = io.open("dummyState.lua"):read("*a")
local s = src:find("local function get_p2_char_specific_reversal()", 1, true)
local e = s and src:find("\nend\n", s, true)
assert(s and e, "get_p2_char_specific_reversal が dummyState.lua に見つからない")
local lookup = assert(loadstring(src:sub(s, e + 4) .. "\nreturn get_p2_char_specific_reversal"))()
globals.char_moves = moves
globals.p2_current_move_list = moves.P2.reversal_names
local function poked(name)
	for i, n in ipairs(moves.P2.reversal_names) do
		if n == name then
			globals.options.p2_reversal_list = i
			local m = lookup()
			return m and m.value
		end
	end
	return nil
end
want("P. Salvation を選ぶと 0x14", poked("P. Salvation"), 0x14)
want("Pharoah Decoration を選ぶと 0x1C", poked("Pharoah Decoration"), 0x1C)
want("Pit of Blame は 0x16 のまま", poked("Pit of Blame"), 0x16)

if fails == 0 then
	print("test_anakaris_pharaoh_ids ok")
else
	print(fails .. " 件 NG")
	os.exit(1)
end
