-- タブごとのリセットが、聞いてから、そのタブだけを戻すか。
--
-- WHY THE SELF-LOOKUP NEEDS A TEST. The row finds its own tab by looking
-- itself up in menu when it is used, because the alternative is naming the
-- rows - a second list to keep in step with the tab, and that is exactly how
-- the test list drifted and left four tests unrun. Self-location is only safe
-- if it really finds the right tab, and the failure is silent: resetting
-- nothing, or resetting somebody else's tab, both look like an ordinary press.
--
-- WHY THE CONFIRMATION NEEDS ONE TOO. MP resets the row under the cursor
-- everywhere else in this menu, so the habit that costs a tab is already
-- trained. All three ways in have to ask, and the box has to land on Cancel -
-- a box that lands on OK is a slower way of doing the same damage.
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_menu_reset_tab.lua
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
local ram = {}
memory = { readbyte = function(a) return ram[a] or 0 end }
gui = { text = function() end, box = function() end }
-- 押し込みの門が emu.framecount() を見るので、時間はこちらで進める。
local FRAME = 1000
emu = { framecount = function() return FRAME end }
-- A FRAME REBUILDS THE WHOLE MENU.
--
-- menu = get_menu() sits inside guiRegister, so every row object is thrown
-- away and remade each drawn frame. The popup is answered on a later frame
-- than the one that opened it, and a test that never rebuilt could not see
-- that - which is how a reset that did nothing at all shipped (user,
-- 2026-09-23). Time only passes here by way of a rebuild.
local function wait_frames(n)
	for _ = 1, n do
		FRAME = FRAME + 1
		menuModule.guiRegister()
	end
end
dofile("menu.lua")
menuModule.guiRegister()

local fails = 0
local function want(what, got, expected)
	if got == expected then
		print("  ok " .. what)
	else
		fails = fails + 1
		print("  NG " .. what)
		print("     got  [" .. tostring(got) .. "]")
		print("     want [" .. tostring(expected) .. "]")
	end
end

local RESET_NAME = "Reset This Tab"
local WANTED = { Display = true, Trainer = true, Analysis = true }
local SENTINEL = "moved"

local function tab_named(name)
	for _, t in ipairs(menu) do
		if t.name == name then return t end
	end
	return nil
end
local function reset_row(tab_name)
	local t = tab_named(tab_name)
	return t.entries[#t.entries]
end
-- 全タブの設定を「既定ではない値」にする。他のタブを巻き込んでいないかを
-- 見るには、他のタブも動かしておく必要がある。
local function scatter()
	local props = {}
	for _, t in ipairs(menu) do
		for _, e in ipairs(t.entries) do
			if e.property_name ~= nil and e.default_value ~= nil then
				training_settings[e.property_name] = SENTINEL
				props[#props + 1] = { tab = t.name, prop = e.property_name,
				                      name = e.name, def = e.default_value }
			end
		end
	end
	return props
end
local function survey(props, tab_name)
	local back, stuck, moved_elsewhere = 0, {}, {}
	for _, p in ipairs(props) do
		if p.tab == tab_name then
			if training_settings[p.prop] == p.def then
				back = back + 1
			else
				stuck[#stuck + 1] = p.name
			end
		elseif training_settings[p.prop] ~= SENTINEL then
			moved_elsewhere[#moved_elsewhere + 1] = p.prop
		end
	end
	return back, table.concat(stuck, ", "), table.concat(moved_elsewhere, ", ")
end

print("[1] 置き場所 - 対象 3 タブの末尾にだけある")
do
	local seen = {}
	for _, t in ipairs(menu) do
		local has = false
		for _, e in ipairs(t.entries) do
			if e.name == RESET_NAME then has = true end
		end
		if has then
			seen[t.name] = true
			-- 末尾であること。途中にあると、下へ流している最中に踏む。
			want(t.name .. " では最後の行", t.entries[#t.entries].name, RESET_NAME)
		-- 行は自分の居るタブの名前を持っている。持ち歩けるのは名前だけで、
		-- 行そのものは毎フレーム作り直される。タブ名を変えてここを直し忘れる
		-- と、リセットが黙って何もしない状態に戻る。
		want(t.name .. " の行が名乗るタブ", t.entries[#t.entries].tab_name, t.name)
		end
	end
	for name in pairs(WANTED) do
		want(name .. " にある", seen[name] == true, true)
	end
	for _, t in ipairs(menu) do
		if not WANTED[t.name] then
			want(t.name .. " には無い", seen[t.name], nil)
		end
	end
end

print("")
print("[2] 入口は 3 つあり、どれも聞くだけで何も変えない")
-- Right / LP / MP。MP をここに含めるのが肝で、他の行では MP がその場で
-- リセットなので、そのつもりで押すと 1 タブ消える。
for _, how in ipairs({ "right", "validate", "reset" }) do
	local row = reset_row("Display")
	local props = scatter()
	current_popup = nil
	wait_frames(20)
	row[how](row)
	local back, stuck = survey(props, "Display")
	want(how .. " は箱を開く", current_popup ~= nil, true)
	want(how .. " ではまだ何も戻っていない", back, 0)
end

print("")
print("[3] 箱は Cancel に乗って開く")
do
	local row = reset_row("Trainer")
	current_popup = nil
	wait_frames(20)
	row:right()
	-- 人が選んで押すまでの間隔。15 フレームの門より後ろでないと、
	-- 門に守られて通ってしまう判定がある (箱が開き直さないこと)。
	wait_frames(20)
	want("2 行ある", #current_popup.entries, 2)
	want("1 行目は OK", current_popup.entries[1].name, "OK")
	want("2 行目は Cancel", current_popup.entries[2].name, "Cancel")
	want("乗っているのは Cancel", current_popup.selected_index, 2)
	want("題に対象タブの名前が出る",
		current_popup.title:find("Trainer", 1, true) ~= nil, true)
end

print("")
print("[4] Cancel は何も変えずに閉じる")
do
	local row = reset_row("Display")
	local props = scatter()
	current_popup = nil
	wait_frames(20)
	row:right()
	-- 人が選んで押すまでの間隔。15 フレームの門より後ろでないと、
	-- 門に守られて通ってしまう判定がある (箱が開き直さないこと)。
	wait_frames(20)
	local no = current_popup.entries[2]
	no:validate()
	want("閉じた", current_popup, nil)
	local back = survey(props, "Display")
	want("何も戻っていない", back, 0)
	-- レバーだけでも帰れること。左は常に戻るに空けてある。
	wait_frames(20)
	row:right()
	-- 人が選んで押すまでの間隔。15 フレームの門より後ろでないと、
	-- 門に守られて通ってしまう判定がある (箱が開き直さないこと)。
	wait_frames(20)
	current_popup.entries[2]:left()
	want("左でも閉じる", current_popup, nil)
end

print("")
print("[5] OK はそのタブだけ戻す")
for name in pairs(WANTED) do
	local row = reset_row(name)
	local props = scatter()
	current_popup = nil
	wait_frames(20)
	row:right()
	-- 人が選んで押すまでの間隔。15 フレームの門より後ろでないと、
	-- 門に守られて通ってしまう判定がある (箱が開き直さないこと)。
	wait_frames(20)
	local touched = 0
	for _, p in ipairs(props) do if p.tab == name then touched = touched + 1 end end
	want(name .. ": 動かせた行が十分ある", touched >= 8, true)
	current_popup.entries[1]:validate()
	want(name .. ": 箱は閉じる", current_popup, nil)
	local back, stuck, elsewhere = survey(props, name)
	want(name .. ": 戻らなかった行が無い", stuck, "")
	want(name .. ": 戻った行数", back, touched)
	want(name .. ": 他タブを巻き込んでいない", elsewhere, "")
end

print("")
print("[6] 開いた直後の Right では決まらない")
-- Right は押しっぱなしで連射される。開けた押しがそのまま箱の中まで走ると、
-- 聞いた意味が無くなる。Play Recording と Loop Interval の箱と同じ 15
-- フレームの門。
do
	local row = reset_row("Analysis")
	local props = scatter()
	current_popup = nil
	wait_frames(20)
	row:right()
	-- 門のテストなのでここだけ詰める。
	wait_frames(1)
	local ok = current_popup.entries[1]
	ok:right()
	want("開いた直後は効かない", current_popup ~= nil, true)
	local back = survey(props, "Analysis")
	want("まだ戻っていない", back, 0)
	-- 門が明けたら、レバーだけで決められる。
	wait_frames(20)
	ok:right()
	want("門が明ければ効く", current_popup, nil)
	local after = survey(props, "Analysis")
	want("戻った", after > 0, true)
end

print("")
print("[7] 隠れている行も戻す")
-- 親のスイッチで隠れている子は、値を持ったまま画面から消えているだけ。
-- 親を戻したら一緒に出てくるので、見えていた行だけ戻すと結果が
-- 「押したときに何が表示されていたか」で変わる。
do
	local tab = tab_named("Display")
	local row = reset_row("Display")
	local hidden = nil
	for _, e in ipairs(tab.entries) do
		if e.is_disabled ~= nil and e.property_name ~= nil
		   and e.default_value ~= nil then
			hidden = e
		end
	end
	want("隠れうる行が Display にある", hidden ~= nil, true)
	if hidden ~= nil then
		training_settings.display_hud = false
		training_settings.display_hitbox_default = false
		training_settings.show_scrolling_input = false
		want("実際に隠れている", hidden.is_disabled(), true)
		training_settings[hidden.property_name] = SENTINEL
		current_popup = nil
		wait_frames(20)
		row:right()
	-- 人が選んで押すまでの間隔。15 フレームの門より後ろでないと、
	-- 門に守られて通ってしまう判定がある (箱が開き直さないこと)。
	wait_frames(20)
		current_popup.entries[1]:validate()
		want("隠れていても戻った",
			training_settings[hidden.property_name], hidden.default_value)
	end
end

if fails == 0 then print("") print("全て通った") else print(fails .. " 件 NG") os.exit(1) end
