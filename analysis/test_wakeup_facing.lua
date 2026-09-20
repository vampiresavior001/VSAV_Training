-- Run from scripts/: lua5.1 ../analysis/test_wakeup_facing.lua
-- A wake-up can turn the dummy between the defer and the delivery of the
-- deferred press. The press must keep the corrected direction it was asked
-- for, which means its raw bits follow the facing byte.
local src = assert(io.open("guardCancel.lua")):read("*a")

local fails = 0
local function want(label, actual, expected)
	if actual ~= expected then
		fails = fails + 1
		print("NG " .. label .. ": " .. tostring(actual) .. " / " .. tostring(expected))
	end
end

-- The helper under test, lifted out of the source.
local first = assert(src:find("local function swap_facing_bits", 1, true))
local last = assert(src:find("\nend", first, true))
local swap = assert(loadstring(src:sub(first, last + 3)
	.. "\nreturn swap_facing_bits"))()

-- THE GAME'S OWN RULES, AS THE CODE STATES THEM.
--
-- 0x022194 exchanges raw lever bits 0 and 1 when the facing byte $b is set;
-- corrected space keeps forward on bit1 and back on bit0 for every facing
-- (guardCancel.lua, the block above LEVER_DOWN). entry_to_bits() implements
-- exactly that: forward is raw bit1 when $b == 0 and raw bit0 when it is not.
local function raw_for(_dir, _b)
	if _dir == "forward" then return (_b == 0) and 2 or 1 end
	return (_b == 0) and 1 or 2
end
local function corrected(_raw, _b)
	if _b == 1 then return swap(_raw) end
	return _raw
end

-- A press resolved against one facing and delivered under another must still
-- read as the same corrected direction once the game applies its swap.
for _, dir in ipairs({ "forward", "back" }) do
	for _, at_defer in ipairs({ 0, 1 }) do
		for _, at_press in ipairs({ 0, 1 }) do
			local raw = raw_for(dir, at_defer)
			local label = dir .. " defer $" .. at_defer .. " press $" .. at_press
			if at_press ~= at_defer then raw = swap(raw) end
			want(label .. " corrected bit1", corrected(raw, at_press),
				(dir == "forward") and 2 or 1)
		end
	end
end

-- Bits that are not facing-relative must never move, alone or combined.
want("neutral stays", swap(0), 0)
want("down stays", swap(4), 4)
want("up stays", swap(8), 8)
want("down+forward follows the facing", swap(6), 5)
want("down+back follows the facing", swap(5), 6)
want("up+down stays", swap(12), 12)
want("both sides stays", swap(3), 3)

-- SOURCE CONTRACTS.
--
-- Both defer sites capture the reference; a third site appearing without one
-- would deliver unswapped bits across the turn.
want("two defer sites capture the facing",
	select(2, src:gsub("fast_press_fref = facing_for_input%(%)", "")), 2)
want("the delivery compares the reference",
	src:find("facing_for_input() ~= fast_press_fref", 1, true) ~= nil, true)
-- The mark must show what was actually asserted, not what was captured.
local at = assert(src:find('mark_write("press_now"', 1, true))
want("press_now marks the re-aimed bits",
	src:find("_pl * 256", at, true) ~= nil, true)

print(fails == 0 and "REP_OK" or (fails .. " REP_NG"))
os.exit(fails == 0 and 0 or 1)
