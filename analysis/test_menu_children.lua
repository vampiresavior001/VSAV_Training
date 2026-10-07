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

-- A ROW THAT BELONGS TO ANOTHER IS INDENTED UNDER IT (user, 2026-10-04).
--
-- The Frame Meter's four rows opened under it and read as four more switches.
-- Every row that appears because of the row above it is now indented, on every
-- tab, and Show Character Specific moved up under the HUD - it sat below Show
-- P2 Inputs, where an indent would have pointed at the wrong row.
--
-- What is pinned: which rows are indented and how deep, nothing else is, and
-- each one's parent is the nearest row above it that is one level out. The
-- last is what an indent SAYS on screen, so a child moved away from its parent
-- fails here even though its gate still works.
print("[indent]")
local TREE = {
	Recording = {
		{ "Use Random Recording Slot", { "Enable Slot 1", "Enable Slot 2", "Enable Slot 3",
		                                 "Enable Slot 4", "Enable Slot 5" } },
	},
	Dummy = {
		{ "Guard", { "Random Guard %" } },
		{ "Guard Action Type", { "Random Guard Action %", "Random Start Wait",
			"Input Motion", "Button", "Button Lever",
			 "Guard Cancel Button", "Push Block Type",
			"Push Block Type (PB Recording)", "Button Wait", "GC Input Delay (Ticks)",
			"P2 Reversal List", "Reversal Strength", "Reversal Action Patterns",
			"Reversal Action Steps", "Loop Steps" } },
		{ "Button Wait", { "Random Delay" } },
		{ "Loop Steps", { "Loop Wait" } },
	},
	Display = {
		{ "HUD (Life / Meter)", { "Show Tech Hit Mash", "Show Character Specific" } },
		{ "Display Hitboxes", { "Display Pushbox X Center" } },
		{ "Show Scrolling Input", { "Scrolling Input History", "Show Button Releases",
			"Hide Negative Edge Inputs", "Show GC Trainer" } },
		{ "Frame Meter", { "Show Throw Invulnerability", "Include Jumps / Dashes",
			"Show P1 Inputs" } },
	},
	Trainer = {
		{ "Tick Data", { "Tick Data Side", "Show Meaty Timing", "Show Action Timeline" } },
		{ "Show Action Timeline", { "Timeline Cut (Free Ticks)" } },
	},
}
-- name -> parent, per tab; a parent's level decides its children's.
local parent_of, level_of = {}, {}
for tab, list in pairs(TREE) do
	parent_of[tab], level_of[tab] = {}, {}
	for _, pc in ipairs(list) do
		for _, c in ipairs(pc[2]) do parent_of[tab][c] = pc[1] end
	end
	local function level(n)
		if parent_of[tab][n] == nil then return 0 end
		return level(parent_of[tab][n]) + 1
	end
	for n in pairs(parent_of[tab]) do level_of[tab][n] = level(n) end
end

local seen = 0
for _, tab in ipairs(menu) do
	local want_level = level_of[tab.name] or {}
	for i, e in ipairs(tab.entries) do
		local lv = want_level[e.name] or 0
		want(tab.name .. " > " .. tostring(e.name) .. " の字下げ", e.indent or 0, lv)
		if lv > 0 then
			seen = seen + 1
			-- The row the indent points at: the nearest one above, one level out.
			local up = nil
			for j = i - 1, 1, -1 do
				if (tab.entries[j].indent or 0) < (e.indent or 0) then up = tab.entries[j]; break end
			end
			want(tab.name .. " > " .. e.name .. " の親", up ~= nil and up.name or "-", parent_of[tab.name][e.name])
			want(tab.name .. " > " .. e.name .. " は親より 1 段だけ深い",
				(e.indent or 0) - (up ~= nil and (up.indent or 0) or 0), 1)
		end
	end
end
local listed = 0
for _, lv in pairs(level_of) do for _ in pairs(lv) do listed = listed + 1 end end
want("字下げした行を全部見た", seen, listed)

-- The draw loop is what puts the indent on screen; the row's own draw() is
-- not told. 8px a level, the step editor's two spaces.
want("menu_row_x: 字下げなし", menu_row_x({}, 100), 100)
want("menu_row_x: 1 段", menu_row_x({ indent = 1 }, 100), 108)
want("menu_row_x: 2 段", menu_row_x({ indent = 2 }, 100), 116)
do
	local src = io.open("menu.lua"):read("*a")
	local n = 0
	for _ in src:gmatch(":draw%(_row_x, ") do n = n + 1 end
	want("描画ループの 2 列とも menu_row_x の x で描く", n, 2)
	want("描画ループが menu_row_x を通す",
		src:find("local _row_x = menu_row_x(menu[main_menu_selected_index].entries[i], _menu_x + _menu_x_interval)", 1, true) ~= nil, true)
	-- Random Delay used to shift itself 8px. With the loop adding its level
	-- too it would sit 8px deeper than the indent says.
	want("自分で字下げする行が無い", src:find("gui.text(_x + 8,", 1, true), nil)
end

-- TIMELINE CUT GOES WITH THE ACTION TIMELINE (2026-10-05). It cuts the green
-- row, so with the row hidden it has nothing to do - and with Tick Data off
-- neither of them does.
do
	local row = find_row("Timeline Cut (Free Ticks)")
	want("Timeline Cut の行がある", row ~= nil, true)
	if row ~= nil then
		training_settings.mo_enable_frame_data = true
		training_settings.display_action_timeline = true
		want("Timeline Cut: 両方 ON なら出る", row.is_disabled(), false)
		training_settings.display_action_timeline = false
		want("Timeline Cut: Action Timeline が OFF なら消える", row.is_disabled(), true)
		training_settings.display_action_timeline = true
		training_settings.mo_enable_frame_data = false
		want("Timeline Cut: Tick Data が OFF なら消える", row.is_disabled(), true)
		training_settings.mo_enable_frame_data = nil
		training_settings.display_action_timeline = nil
	end
	local sw = find_row("Show Action Timeline")
	want("Show Action Timeline の既定は ON", sw ~= nil and sw.default_value, true)
	want("Show Action Timeline が書く先", sw ~= nil and sw.property_name, "display_action_timeline")
	-- MEATY TIMING (2026-10-07): on by default, between the Tick Data rows and
	-- the Action Timeline - the order the rows have on screen.
	local mt = find_row("Show Meaty Timing")
	want("Show Meaty Timing の既定は ON", mt ~= nil and mt.default_value, true)
	want("Show Meaty Timing が書く先", mt ~= nil and mt.property_name, "display_meaty_timing")
end

if fails == 0 then
	print("test_menu_children ok")
else
	print(fails .. " 件 NG")
	os.exit(1)
end
