-- A CHECKBOX ROW HOLDS A BOOLEAN, WHATEVER IT WAS BUILT WITH.
--
-- 0 is true in Lua and every consumer of these settings asks for == true, so a
-- row holding 1 or 0 draws as "yes" or "no" while the feature does the
-- opposite. The rows were built with 1 / 0 / true / false at different times
-- and reset() wrote that literal straight back, so MP was a way to get one:
-- resetting Show Scrolling Input left it holding 1, which read "yes" while the
-- input bar stopped drawing and the three rows under it vanished (user,
-- 2026-09-14).
--
-- One row was built with its arguments in the wrong order on top of that -
-- checkbox_menu_item(name, table, 1, "use_character_specific_slots", help) -
-- so it wrote to training_settings[1] and the setting it names was never
-- touched. It read "no" for years while the feature was on. That shape is
-- checked here too, because nothing else would notice.
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_menu_switches.lua
package.preload["./scripts/charMoves"] = function()
	return { get_player_movelists = function()
		return { P1 = { reversal_names = { "Stub" } }, P2 = { reversal_names = { "Stub" } } }
	end }
end
package.preload["./scripts/actionSequenceEditor"] = function()
	return dofile("actionSequenceEditor.lua")
end
package.preload["./scripts/actionSequenceRunner"] = function()
	return dofile("actionSequenceRunner.lua")
	end
package.preload["./scripts/position"] = function()
	return dofile("position.lua")
end

training_settings = {}
globals = { getCharacter = function() return "Demitri" end }
memory = { readbyte = function() return 0 end }
gui = { text = function() end, box = function() end, rect = function() end }
dofile("menu.lua")
menuModule.guiRegister()

local fails = 0
local function want(what, got, w)
	if got ~= w then
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(w) .. "]")
	else
		print("  ok " .. what)
	end
end

-- A checkbox is the row with no list and no min/max, the same way
-- test_release_defaults recognises one.
local boxes = {}
for _, tab in ipairs(menu) do
	for _, e in ipairs(tab.entries) do
		if e.property_name ~= nil and e.list == nil and e.min == nil then
			boxes[#boxes + 1] = { tab = tab.name, row = e }
		end
	end
end
print(("  -- チェックボックスの行 %d 件"):format(#boxes))
want("ひととおり拾えた", #boxes >= 40, true)

local bad_default, bad_name, bad_reset, bad_toggle = {}, {}, {}, {}
for _, b in ipairs(boxes) do
	local e = b.row
	local where = b.tab .. " / " .. tostring(e.name)

	-- The property name is a key, so it is a string. Anything else means the
	-- arguments went in the wrong order.
	if type(e.property_name) ~= "string" then
		bad_name[#bad_name + 1] = where .. " -> " .. tostring(e.property_name)
	end
	-- ...and the default is a switch, so it is a boolean. A string there is the
	-- other half of the same mistake: the help text landing in the value.
	if type(e.default_value) ~= "boolean" then
		bad_default[#bad_default + 1] = where .. " -> " .. tostring(e.default_value)
	end

	if type(e.property_name) == "string" then
		e:reset()
		if type(training_settings[e.property_name]) ~= "boolean" then
			bad_reset[#bad_reset + 1] = where
		end
		-- Left and right both toggle; neither may leave anything else behind.
		e:left()
		local a = training_settings[e.property_name]
		e:right()
		local c = training_settings[e.property_name]
		if type(a) ~= "boolean" or type(c) ~= "boolean" then
			bad_toggle[#bad_toggle + 1] = where
		end
	end
end

local function report(what, list)
	want(what, #list, 0)
	for _, m in ipairs(list) do print("       " .. m) end
end
report("property_name は全部文字列", bad_name)
report("既定値は全部 boolean", bad_default)
report("MP でリセットしても boolean", bad_reset)
report("左右で切り替えても boolean", bad_toggle)

-- A SETTINGS FILE WRITTEN BEFORE ANY OF THAT STILL CARRIES 1 AND 0.
--
-- Drawing is where it gets healed, so the row is asked to draw with each of
-- the shapes one of those files can hold.
for _, held in ipairs({ 1, 0, "yes", "" }) do
	local e = boxes[1].row
	training_settings[e.property_name] = held
	e:draw(0, 0, false)
	want(("保存値 %s は boolean に直る"):format(tostring(held)),
		type(training_settings[e.property_name]), "boolean")
end
-- ...and to the value the consumers would have read, not the other one.
local e1 = boxes[1].row
training_settings[e1.property_name] = 1
e1:draw(0, 0, false)
want("1 は ON になる", training_settings[e1.property_name], true)
training_settings[e1.property_name] = 0
e1:draw(0, 0, false)
want("0 は OFF になる", training_settings[e1.property_name], false)

-- "RESET TO DEFAULT" HAS TO MEAN THE DEFAULT THE TOOL SHIPS WITH.
--
-- Every row carries its own literal default, written by hand, and twelve of
-- them disagreed with config.lua: MP on Guard Action Frequency reset it to
-- 100% against a shipped None, MP on Movelist turned a row on that ships off,
-- and three Gauge rows shipped ON while MP switched them off. The legend on
-- every one of those rows says "MP: Reset to default" (2026-09-14).
--
-- Every row is checked, not only the checkboxes, because the lists and the
-- integers drifted the same way.
do
	local shipped = dofile("config.lua").default_training_settings
	local function as_switch(v) return v ~= nil and v ~= false and v ~= 0 end
	local off = {}
	for _, tab in ipairs(menu) do
		for _, e in ipairs(tab.entries) do
			if e.property_name ~= nil and type(e.property_name) == "string" then
				local mine, ships = e.default_value, shipped[e.property_name]
				local agree
				if e.list == nil and e.min == nil then
					agree = (as_switch(mine) == as_switch(ships))
				else
					agree = (mine == ships)
				end
				if not agree then
					off[#off + 1] = ("%s / %s: 出荷 %s, MP %s")
						:format(tab.name, tostring(e.name), tostring(ships), tostring(mine))
				end
			end
		end
	end
	want("MP のリセット先は出荷値と一致する", #off, 0)
	for _, m in ipairs(off) do print("       " .. m) end
end

-- TWO ROWS THAT SHIPPED ON AND COULD NOT BOTH WORK.
--
-- healthAndMeter.lua held the two Infinite Dark Force switches in one
-- if/elseif, so P2's did nothing while P1's was on - and both shipped on.
do
	local hm = io.open("healthAndMeter.lua"):read("*a")
	want("Dark Force が elseif で繋がっていない",
		hm:find("elseif globals.options.p2_infinite_df", 1, true), nil)
	want("P2 側も独立した if を持つ",
		hm:find("if globals.options.p2_infinite_df then", 1, true) ~= nil, true)
end

-- THE EMERGENCY REFILL STAYS AT ONE BAT.
--
-- vsavscriptv2 refills P1 to 0x0090 - 144, one bat - when red life drops to 28,
-- and the obvious-looking correction is to use Max Life instead. That was made
-- and withdrawn: restoring 288 does not bring the second bat back on the gauge,
-- so the character ends up holding life nothing shows (user, 2026-09-14).
--
-- Pinned here so the same correction is not made a third time without reading
-- the note above the code.
do
	local v2 = io.open("vsavscriptv2.lua"):read("*a")
	want("補充値は 1 バット", v2:find("local ONE_BAT = 0x0090", 1, true) ~= nil, true)
	want("Max Life を使っていない",
		v2:find("globals.options.p1_max_life", 1, true), nil)
	want("理由が書いてある",
		v2:find("DOES NOT BRING THE SECOND BAT BACK", 1, true) ~= nil, true)
	local shipped = dofile("config.lua").default_training_settings
	-- 288 is the standard VITALITY entry and what Gauge / Max Life ships at.
	want("Max Life の出荷値は 288", shipped.p1_max_life, 288)
	want("P2 も 288", shipped.p2_max_life, 288)
end

-- THE ROW THAT WAS WIRED TO NOTHING.
do
	local row
	for _, b in ipairs(boxes) do
		if b.row.name == "Use Character Specific Slots" then row = b.row end
	end
	want("Use Character Specific Slots がある", row ~= nil, true)
	want("書く先", row ~= nil and row.property_name or "", "use_character_specific_slots")
	local shipped = dofile("config.lua").default_training_settings
	want("出荷値がある", type(shipped.use_character_specific_slots), "boolean")
	local macro = io.open("macro.lua"):read("*a")
	want("読む側が同じキーを見ている",
		macro:find("globals.options.use_character_specific_slots", 1, true) ~= nil, true)
end

if fails == 0 then
	print("test_menu_switches ok")
else
	print(fails .. " 件 NG")
	os.exit(1)
end
