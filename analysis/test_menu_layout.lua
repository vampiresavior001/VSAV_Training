-- DOES EVERY TAB ACTUALLY FIT ON THE SCREEN?
--
-- The menu panel draws in two fixed columns with no scrolling, and nothing
-- checked that a tab stayed inside them. The Display tab had grown to 25 rows
-- against a capacity of 22, so its last three were drawn straight over the
-- description text at the bottom of the panel - which is what "the Display tab
-- has got messy" turned out to mean (user, 2026-09-13). Adding one more row
-- would have done it again silently.
--
-- The tab bar has the same problem from the other side: each name advances the
-- cursor by (#name + 5) * 4 px and nothing stops the last one running past the
-- right edge of the panel.
--
-- WHAT IS COUNTED, AND WHY NOT SIMPLY EVERY ROW. The Dummy tab holds 26
-- entries but only ever draws a handful: it is a state machine, and most of
-- its rows are gated on a guard action or a character being selected, several
-- of them mutually exclusive. Asserting on its raw total would be asserting
-- something that never happens. Two counts that DO mean something are checked
-- instead - the rows no condition can hide, and the rows a fresh install
-- actually draws. Display's 25 were all unconditional, so the first of those
-- is the one that would have caught it.
--
-- The panel numbers are read back out of menu.lua rather than copied here, so
-- moving the panel moves this test with it.
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_menu_layout.lua
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

-- A fresh install, so "what a new user sees" is a real count and not whatever
-- an empty table happens to make every gate say. Copied INTO the table rather
-- than replacing it: menu.lua captured this exact table while it loaded.
local shipped = dofile("config.lua").default_training_settings
for k, v in pairs(shipped) do training_settings[k] = v end
globals.getCharacter = function() return "Demitri" end

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

local src = io.open("menu.lua"):read("*a")
local function num(_pat, _what)
	local v = tonumber(src:match(_pat))
	want("menu.lua から " .. _what .. " が読めた", v ~= nil, true)
	return v
end

local box_left   = num("_menu_box_left = (%d+)",   "パネル左")
local box_right  = num("_menu_box_right = (%d+)",  "パネル右")
local box_top    = num("_menu_box_top = (%d+)",    "パネル上")
local box_bottom = num("_menu_box_bottom = (%d+)", "パネル下")
local menu_y     = box_top + num("local _menu_y = _menu_box_top %+ (%d+)", "1 行目の y")
local interval   = num("local _menu_y_interval = (%d+)", "行間")
local col_break  = num("if _draw_index > (%d+) then _menu_x_interval", "列の折り返し")
local col2_lift  = num("%(_menu_y %- (%d+)%) %+ _menu_y_interval", "2 列目の持ち上げ")
local desc_up    = num("_menu_box_bottom %- (%d+), description", "説明文の位置")
local bar_x      = box_left + num("local _bar_x = _menu_box_left %+ (%d+)", "タブバーの左")
local char_w     = num("%(#menu%[i%].name %+ 5%) %* (%d+)", "1 文字の幅")
local name_pad   = num("%(#menu%[i%].name %+ (%d+)%) %* 4", "タブ 1 つの余白")

-- The y a row lands on, for the index it is drawn at: one column until
-- col_break, then a second one lifted by col2_lift.
local function row_y(_idx)
	if _idx > col_break then return (menu_y - col2_lift) + interval * _idx end
	return menu_y + interval * _idx
end

-- A row has to finish above the description block. Its height is not written
-- down anywhere, so the row interval stands in for it - a row cannot be taller
-- than the spacing between rows without overlapping the row under it as well.
local desc_y = box_bottom - desc_up
local capacity = 0
while row_y(capacity) + interval <= desc_y do capacity = capacity + 1 end
print(("  -- 1 タブの上限は %d 行 (説明文が y=%d から)"):format(capacity, desc_y))
want("上限が 2 列ぶんある", capacity > col_break + 1, true)

for _, tab in ipairs(menu) do
	local always, shown = 0, 0
	for _, e in ipairs(tab.entries) do
		if e.is_disabled == nil then
			always = always + 1
			shown = shown + 1
		elseif not e.is_disabled() then
			shown = shown + 1
		end
	end
	print(("  -- %-10s 全 %2d   隠れない %2d   新規インストールで %2d")
		:format(tab.name, #tab.entries, always, shown))
	want(("%s: 隠れない行が %d で収まる"):format(tab.name, always), always <= capacity, true)
	want(("%s: 新規インストールの %d 行が収まる"):format(tab.name, shown), shown <= capacity, true)
end

-- AND THE ROWS THEMSELVES, WHICH RUN OUT OF ROOM SIDEWAYS.
--
-- Height was only half of it: a row is drawn as one string and nothing stops
-- it reaching past the panel, or past the start of the second column. The
-- second column is only 150px from the first, and a row there has whatever is
-- left before the right edge.
--
-- The string is not modelled here, it is TAKEN: the row is asked to draw
-- itself with gui.text swapped for a capture, selected (which adds "< " and
-- " >") and holding the widest value it can hold. That way a row type nobody
-- thought about is measured the same as a checkbox.
local col_x2 = num("then _menu_x_interval = (%d+) else", "2 列目までの距離")
local col_x1 = box_left + num("local _menu_x = _menu_box_left %+ (%d+)", "1 列目の x")

local real_text = gui.text
local function widest(_e)
	local keep = nil
	if _e.property_name ~= nil then
		keep = training_settings[_e.property_name]
		if _e.list ~= nil then
			local best, bi = -1, 1
			for i, v in ipairs(_e.list) do
				if #tostring(v) > best then best, bi = #tostring(v), i end
			end
			training_settings[_e.property_name] = bi
		elseif _e.max ~= nil then
			training_settings[_e.property_name] = _e.max
		else
			-- "yes" is one character wider than "no".
			training_settings[_e.property_name] = true
		end
	end
	local got = nil
	gui.text = function(_x, _y, _t) if got == nil then got = tostring(_t) end end
	local ok = pcall(function() _e:draw(0, 0, true) end)
	gui.text = real_text
	if _e.property_name ~= nil then training_settings[_e.property_name] = keep end
	if not ok or got == nil then return nil end
	return #got * char_w
end

local measured = 0
for _, tab in ipairs(menu) do
	-- Only the rows that are actually drawn, in the order they are drawn, so
	-- the index is the one the draw loop would use.
	local shown = {}
	for _, e in ipairs(tab.entries) do
		if e.is_disabled == nil or not e.is_disabled() then shown[#shown + 1] = e end
	end
	local wide = {}
	for idx = 0, #shown - 1 do
		local e = shown[idx + 1]
		local w = widest(e)
		if w ~= nil then
			measured = measured + 1
			local x = (idx > col_break) and (col_x1 + col_x2) or col_x1
			if x + w > box_right then
				wide[#wide + 1] = e.name .. " (右端 " .. (x + w) .. ")"
			end
			-- A first-column row shares its line with the second-column row
			-- eleven places later, and only then can the two collide.
			if idx <= col_break and #shown > idx + col_break + 1
			   and x + w > col_x1 + col_x2 then
				wide[#wide + 1] = e.name .. " (2 列目に重なる " .. (x + w) .. ")"
			end
		end
	end
	want(tab.name .. ": 行が横にはみ出さない", #wide, 0)
	for _, m in ipairs(wide) do print("       " .. m) end
end
print(("  -- 幅を測れた行 %d 件"):format(measured))
want("ほとんどの行を測れた", measured >= 60, true)

-- THE DESCRIPTION BLOCK, WHICH IS WHERE MOST OF IT WENT OFF THE SCREEN.
--
-- The selected row's help is drawn at a fixed offset above the bottom edge and
-- the legend sits below it. Nothing clipped either one, so a row documented in
-- more lines than fit simply drew past the panel and over the input bar, and
-- past the right edge if a line was too long. The Tick Data row had twelve
-- lines against room for four, and lines of 82 characters against room for 81
-- (user screenshot, 2026-09-13). None of it was readable and nothing said so.
local desc_top = box_bottom - num("_menu_box_bottom %- (%d+), description", "説明文の位置")
local legend_y = box_bottom - num("_menu_box_bottom %- (%d+), menu%[main_menu", "凡例の位置")
-- gui.text steps 8px per newline, which is the glyph height rather than the
-- 10px the rows are spaced at.
local LINE = 8
local desc_lines = 0
while desc_top + LINE * desc_lines + LINE <= legend_y do desc_lines = desc_lines + 1 end
local desc_cols = math.floor((box_right - col_x1) / char_w)
print(("  -- 説明文は %d 行 x %d 文字 (y=%d..%d, 凡例 y=%d)")
	:format(desc_lines, desc_cols, desc_top, legend_y - LINE, legend_y))
want("説明文に 4 行以上の余地がある", desc_lines >= 4, true)

-- AND IT HAS TO START BELOW THE ROWS.
--
-- Both the description and the legend are measured from the panel's bottom
-- edge, so moving that edge moves them - and shortening the panel walks the
-- description up into the last row of the first column while the line budget
-- above still reads as six. Nothing on screen would say so: the two texts
-- would simply be drawn over each other.
local last_row_y = menu_y + interval * col_break
want(("説明文が最終行 (y=%d) より下から始まる"):format(last_row_y),
	desc_top >= last_row_y + LINE, true)

local checked = 0
for _, tab in ipairs(menu) do
	local bad = {}
	for _, e in ipairs(tab.entries) do
		if e.description ~= nil then
			local okd, d = pcall(function() return e:description() end)
			if okd and type(d) == "string" then
				checked = checked + 1
				local n, w = 0, 0
				for line in (d .. string.char(10)):gmatch("([^" .. string.char(10) .. "]*)" .. string.char(10)) do
					n = n + 1
					if #line > w then w = #line end
				end
				if n > desc_lines or w > desc_cols then
					bad[#bad + 1] = ("%s (%d 行 / %d 文字)"):format(e.name, n, w)
				end
			end
		end
	end
	want(tab.name .. ": 説明文が枠に収まる", #bad, 0)
	for _, m in ipairs(bad) do print("       " .. m) end
end
print(("  -- 説明文を測れた行 %d 件"):format(checked))
want("説明文をひととおり測れた", checked >= 60, true)

-- THE TAB BAR, WHICH RUNS OUT OF ROOM FROM THE OTHER END.
--
-- The selected tab is drawn as "< name >" from the slot's own left edge while
-- an unselected one is indented instead, so the widest thing that ever appears
-- in a slot is the name plus four characters of decoration.
local x = bar_x
local last_end = 0
for _, tab in ipairs(menu) do
	last_end = x + (#tab.name + 4) * char_w
	x = x + (#tab.name + name_pad) * char_w
end
print(("  -- タブバーは x=%d まで (パネル右端 %d)"):format(last_end, box_right))
want("タブバーがパネルに収まる", last_end <= box_right, true)

-- THE ORDER OF THE TABS, WHICH IS A RULE AND NOT A HABIT.
--
-- Split by what a tab acts on, there are two groups: the ones that change
-- what HAPPENS (Recording, Gauge, Dummy, Game) and the ones that change what
-- you SEE (Display, Trainer, Analysis). Game sat between Trainer and
-- Analysis, inside the second group, although not one of its four rows draws
-- anything - so the bar had no rule you could state, and which side a tab
-- was on had to be remembered one tab at a time (user, 2026-09-23).
--
-- Moved to the right of Dummy, there is exactly ONE boundary: everything
-- left of it decides what happens, everything right of it decides what is
-- drawn. That is worth pinning, because the next tab added will be dropped
-- at whichever end is convenient and the rule goes with it.
do
	local order = {}
	for _, tab in ipairs(menu) do order[#order + 1] = tab.name end
	want("並び", table.concat(order, " "),
		"Recording Gauge Dummy Game Display Trainer Analysis")
	-- 境界は 1 本だけ。左群のどれもが右群のどれより先にあること。
	local happens = { Recording = true, Gauge = true, Dummy = true, Game = true }
	local last_happens, first_seen = 0, nil
	for i, name in ipairs(order) do
		if happens[name] then
			last_happens = i
		elseif first_seen == nil then
			first_seen = i
		end
	end
	want("境界が 1 本", last_happens < (first_seen or 99), true)
end
if fails == 0 then
	print("test_menu_layout ok")
else
	print(fails .. " 件 NG")
	os.exit(1)
end
