-- A SPECIAL'S BUTTON WAITS OUT THE TURN AFTER A CROSSOVER (scripts/guardCancel.lua,
-- the Action Steps walker), 2026-11-18.
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_crossover_button_hold.lua
--
-- Gallon's Wild Circular on Auto (Landing) after a jump over the opponent: the
-- back + HK went in on the Tick the game turned him round, and the game threw
-- with a normal throw instead (invuln_log v5, archive v11.7.33_5); with the
-- button held past the turn, 14 of 14 threw with Wild Circular (v11.7.33_6).
--
--   [1] on the ground with $0B not yet the opponent's side: the lever goes in,
--       the button waits - one Tick, two at most
--   [2] nothing else waits: in the air, facing settled, no button, not a special
--   [3] it sits in the Action Steps walker (seq_tick), not the push block one
local fails = 0
local function eq(what, got, want)
	if got == want then print("  ok " .. what .. " = " .. tostring(got))
	else
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(want) .. "]")
	end
end
local fh = assert(io.open("guardCancel.lua"))
local src = fh:read("*a")
fh:close()

local a = assert(src:find("-- A SPECIAL'S BUTTON WAITS OUT THE TURN AFTER A CROSSOVER", 1, true))
local b = assert(src:find("-- Every tick this entry has been asserted", a, true))
local body = src:sub(a, b - 1)
local chunk = assert(loadstring("local _s0, _pl, _pb, assert_input_bits, facing_unsettled, memory = ...\n"
	.. body .. "\nreturn 'go'"))

-- One Tick: returns 'go' (the walker carries on) or nil (held), and what went in.
local function tick(s0, pl, pb, air, unsettled)
	local wrote
	local mem = { readbyte = function(addr) if addr == 0xFF8838 then return air end return 0 end }
	local r = chunk(s0, pl, pb, function(l, bt) wrote = string.format("%02X/%02X", l, bt) end,
		function() return unsettled end, mem)
	return (r == "go") and "go" or ("held " .. tostring(wrote))
end

print("[1] 振り向く前の地上: レバーだけ入れて、ボタンは待つ")
do
	local s = { seq_through_freeze = true }
	eq("1 Tick 目: 後ろだけ", tick(s, 0x01, 0x40, 0, true), "held 01/00")
	eq("振り向いた: そのまま押す", tick(s, 0x01, 0x40, 0, false), "go")
	s = { seq_through_freeze = true }
	tick(s, 0x01, 0x40, 0, true)
	eq("2 Tick 目も待つ", tick(s, 0x01, 0x40, 0, true), "held 01/00")
	eq("3 Tick 目は押す (待つのは 2 Tick まで)", tick(s, 0x01, 0x40, 0, true), "go")
end

print("[2] ほかは待たない")
do
	eq("空中", tick({ seq_through_freeze = true }, 0x01, 0x40, 1, true), "go")
	eq("向きが合っている", tick({ seq_through_freeze = true }, 0x01, 0x40, 0, false), "go")
	eq("ボタンのない入力", tick({ seq_through_freeze = true }, 0x04, 0x00, 0, true), "go")
	eq("必殺技でない (通常技・ダッシュ)", tick({}, 0x01, 0x40, 0, true), "go")
end

print("[3] 置き場所")
do
	local seq_walker = src:find("-- THE PARKED REVERSE RIDES THE FIRST ENTRY THAT HAS ROOM.", 1, true)
	local prev_if = nil
	local p = 1
	while true do
		local q = src:find("if _i <= #_s0.sequence then", p, true)
		if q == nil or q > a then break end
		prev_if, p = q, q + 1
	end
	eq("Action Steps の歩進の中 (THE PARKED REVERSE の直前の区間)",
		prev_if ~= nil and prev_if < a and a < seq_walker, true)
	local _, n = src:gsub("A SPECIAL'S BUTTON WAITS OUT THE TURN AFTER A CROSSOVER", "")
	eq("1 か所だけ", n, 1)
	eq("facing_unsettled はそれより前に定義されている",
		src:find("local function facing_unsettled()", 1, true) < a, true)
end

print(fails == 0 and "\n全て通った" or ("\n" .. fails .. " 件 NG"))
os.exit(fails == 0 and 0 or 1)
