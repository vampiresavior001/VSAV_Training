-- A CHILD ROW IS OFFERED ONLY WHILE ITS PARENT IS ON.
--
-- Five settings cannot do anything unless another setting is on: the three
-- that live inside the scrolling input bar, the pushbox axis inside the hitbox
-- display, and the dummy's input column inside the HUD. They used to sit in
-- the list next to everything else, so the Display tab offered switches that
-- silently did nothing, and the dependency was invisible unless you read the
-- drawing code.
--
-- is_disabled IS the visibility switch - the draw loop skips those rows and
-- _sub_menu_up / _sub_menu_down recurse past them (menu.lua) - so what this
-- pins is the predicate itself, under each state a parent can be in.
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_menu_children.lua
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
globals = {}
memory = { readbyte = function() return 0 end }
gui = { text = function() end, box = function() end }
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

local function find_row(_name)
	for _, tab in ipairs(menu) do
		for _, e in ipairs(tab.entries) do
			if e.name == _name then return e, tab.name end
		end
	end
	return nil, nil
end

-- The property each parent writes, and the row that writes it.
local PARENTS = {
	display_hitbox_default = "Display Hitboxes",
	show_scrolling_input   = "Show Scrolling Input",
}

local CHILDREN = {
	{ "Display Pushbox X Center",  "display_hitbox_default" },
	{ "Scrolling Input History",    "show_scrolling_input" },
	{ "Show Button Releases",       "show_scrolling_input" },
	{ "Hide Negative Edge Inputs", "show_scrolling_input"   },
	{ "Show GC Trainer",           "show_scrolling_input"   },
}

-- SHOW P2 INPUTS IS NOT ONE OF THEM, AND HAS TO STAY THAT WAY.
--
-- It was hung under the HUD for one frame of this work, because vsavscriptv2
-- drew the column inside the display_hud branch. That pairing had no reason
-- behind it beyond where the code sat, and no way to guess it from the menu
-- (user, 2026-09-13) - so the drawing moved out of the branch and the row
-- stands alone. Pinned here because the gate is easy to put back by accident.
do
	local row, tab = find_row("Show P2 Inputs")
	want("Show P2 Inputs の行がある (" .. tostring(tab) .. ")", row ~= nil, true)
	want("Show P2 Inputs は何にもぶら下がっていない",
		row ~= nil and row.is_disabled == nil, true)
	local v2 = io.open("vsavscriptv2.lua"):read("*a")
	-- The column's own switch, and NOT inside the branch that draws the HUD.
	local at_col = v2:find("globals.options.display_p2_inputs", 1, true)
	-- WHAT IS INSIDE THE HUD BRANCH, AND WHAT IS NOT.
	--
	-- charaspecfic is the only thing the HUD branch draws, and it now sits
	-- behind a switch of its own inside it (Show Character Specific, 2026-09-23)
	-- so the two lines are no longer adjacent. What this pins is unchanged:
	-- charaspecfic is in the branch, and P2's column is not.
	-- 呼び出し側から探す。display_hud の枝はこのファイルに 2 つあり、
	-- 先頭から探すと hud() のほうに当たる。
	local at_spec = v2:find(string.rep(string.char(9), 4) .. "charaspecfic()", 1, true)
	local at_hud = nil
	do
		local i = 1
		while true do
			local j = v2:find("if globals.options.display_hud == true then", i, true)
			if j == nil or (at_spec ~= nil and j > at_spec) then break end
			at_hud = j
			i = j + 1
		end
	end
	want("HUD の枝が charaspecfic を呼ぶ",
		(at_hud ~= nil and at_spec ~= nil) and (at_spec - at_hud) < 500, true)
	want("描く側が同じキーを読む", at_col ~= nil, true)
	want("P2 の列は HUD の枝の中に無い",
		(at_col ~= nil and at_spec ~= nil) and at_col > at_spec, true)
	-- 自前のスイッチの内側にあること。ここが外れると、HUD を出した人には
	-- また説明の無い表示が出る。
	want("charaspecfic は自分のスイッチの内側",
		v2:find("if globals.options.display_char_specific == true then", 1, true) ~= nil, true)
end

-- A parent gated on a property no row writes would take its children off the
-- menu for good, so the names are checked before the children are.
for _key, _name in pairs(PARENTS) do
	local row, tab = find_row(_name)
	want(_name .. " の行がある (" .. tostring(tab) .. ")", row ~= nil, true)
	want(_name .. " が書く先", row ~= nil and row.property_name or "", _key)
	want(_name .. " 自身は隠れない", row ~= nil and row.is_disabled == nil, true)
end

for _, c in ipairs(CHILDREN) do
	local _name, _parent = c[1], c[2]
	local row, tab = find_row(_name)
	want(_name .. " の行がある (" .. tostring(tab) .. ")", row ~= nil, true)
	if row ~= nil then
		want(_name .. " に is_disabled がある", type(row.is_disabled), "function")
		training_settings[_parent] = true
		want(_name .. ": 親が ON なら出る", row.is_disabled(), false)
		training_settings[_parent] = false
		want(_name .. ": 親が OFF なら消える", row.is_disabled(), true)
		training_settings[_parent] = nil
		want(_name .. ": 親が未設定でも消える", row.is_disabled(), true)
		-- A settings file written by an older build can hold 1 here. Every
		-- parent's own drawing code asks for == true, so a 1 is a parent that
		-- is NOT running - and a child offered under it would be exactly the
		-- dead switch this change exists to remove.
		training_settings[_parent] = 1
		want(_name .. ": 親が 1 でも消える", row.is_disabled(), true)
		training_settings[_parent] = true
	end
end

-- A child on a different tab from its parent would vanish from one screen when
-- something on another screen was switched, which is worse than leaving it on.
for _, c in ipairs(CHILDREN) do
	local _, ctab = find_row(c[1])
	local _, ptab = find_row(PARENTS[c[2]])
	want(c[1] .. " は親と同じタブ", ctab, ptab)
end

if fails == 0 then
	print("test_menu_children ok")
else
	print(fails .. " 件 NG")
	os.exit(1)
end
