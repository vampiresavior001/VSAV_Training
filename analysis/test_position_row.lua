-- THE POSITION ROW'S SHORTCUTS (user, 2026-09-21).
--
-- Position 行の近道: LP = 現在の設定で再配置、HP = 再配置してメニューを閉じる。
-- 従来は値が変わらないと再配置されなかったので、同じ位置に戻すには
-- 別の項目を挟んで 2 回変える必要があった。
--
-- ここで固定するもの:
--   [1] Off は何もしない (Off は「触らない」の意味)
--   [2] 壁の配置ならスタブでもスライドが立つ。駆動して P1 が動くこと、
--       そして走行中の 2 回目の reapply は撥ねられること
--   [3] メニュー側の配線 (menu.lua のソース契約)
--   [4] タブ名 (Dummy) と行の所在
-- 成功経路の実機確認はユーザが 1 回普通に使うだけでよい (CLAUDE.md)。
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_position_row.lua
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

local ram = {}
local function sw(v)
	if v >= 32768 then return v - 65536 end
	return v
end
memory = {
	readbyte   = function(a) return ram[a] or 0 end,
	readword   = function(a) return ram[a] or 0 end,
	readdword  = function(a) return ram[a] or 0 end,
	writeword  = function(a, v) ram[a] = v end,
	writebyte  = function(a, v) ram[a] = v end,
}
gui = { text = function() end, box = function() end, rect = function() end, image = function() end }
emu = { framecount = function() return 1 end }
training_settings = {}
globals = { options = {} }
function mark_training_settings_dirty() end
function save_training_data_if_dirty() end

local fails = 0
local function want(what, got, w)
	if got ~= w then
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(w) .. "]")
	else
		print("  ok " .. what)
	end
end

positionModule = dofile("position.lua")
local M = positionModule

-- reapply はメニューの Position 行から呼ばれる。ゲートの順序をここで固定する。
print("[1] reapply - Off は何もしない")
globals.options.stage_position = 1
want("Off では撥ねられる", M.reapply(), false)
want("mask_input は素通りする", (function()
	local t = { ["P1 Left"] = true }
	M.mask_input(t)
	return t["P1 Left"]
end)(), true)

print("")
print("[2] 壁の配置は stub でも駆動できる (左壁, stage_position=2)")
-- hotkeys_armed を立てないと slide_allowed が撥ねる。have_start は
-- 位置が読めるようになった時点で真 (position.lua で初期値 true)。
globals.hotkeys_armed = true
globals.options.stage_position = 2
-- P1/P2 を中央から離したところに置いておく (X は 16.16 の整数半分)。
ram[0xFF8410] = 640; ram[0xFF8810] = 640
want("スライドが始まる", M.reapply(), true)
want("mask_input が方向を飲む (スライド走行中)", (function()
	local t = { ["P1 Left"] = true }
	M.mask_input(t)
	return t["P1 Left"]
end)(), false)
-- スライドが走行中の 2 回目は撥ねられる: 画面の並びはいま出したばかり。
want("走行中は 2 回目を撥ねる", M.reapply(), false)
-- 駆動: registerBefore が毎フレーム run() を回す。左壁 280 へ向かう。
local x0 = sw(ram[0xFF8410])
for _ = 1, 12 do M.registerBefore() end
want("P1 が動いた", ram[0xFF8410] ~= x0, true)
want("左へ向かっている", ram[0xFF8410] < x0, true)
-- スライド完了を待つ (guard_frames の上限は 180)。完了したら mask_input は
-- 素通りに戻る = steps が空になった。
for _ = 1, 200 do M.registerBefore() end
want("スライドが終わる", (function()
	local t = { ["P1 Left"] = true }
	M.mask_input(t)
	return t["P1 Left"]
end)(), true)
want("終わったあとも reapply は通る", M.reapply(), true)
for _ = 1, 200 do M.registerBefore() end

print("")
print("[3] メニュー側の配線 (menu.lua のソース契約)")
local msrc = io.open("menu.lua"):read("*a")
want("Position 行に validate (LP = 再配置) がある",
	msrc:find("function position_menu_item:validate() positionModule.reapply() end", 1, true) ~= nil, true)
want("Position 行に hp がある",
	msrc:find("function position_menu_item:hp()", 1, true) ~= nil, true)
want("hp は reapply が成功したときだけ閉じる",
	msrc:find("if positionModule.reapply() then togglemenu() end", 1, true) ~= nil, true)
want("凡例に 3 つのキーを出す",
	msrc:find("LP: Place again   MP: Reset   HP: Place + close", 1, true) ~= nil, true)
want("説明文に LP と HP の近道を書く",
	msrc:find("LP places the pair at this setting again", 1, true) ~= nil and
	msrc:find("HP also closes the menu", 1, true) ~= nil, true)
want("メニュー入力に HP の門がある",
	msrc:find("if P1.input.pressed.HP or P2.input.pressed.HP then", 1, true) ~= nil, true)
want("HP の門は hp を呼ぶ",
	msrc:find("_current_entry:hp()", 1, true) ~= nil, true)

print("")
print("[4] タブ名と行の所在")
package.preload["./scripts/position"] = function() return M end
dofile("menu.lua")
menuModule.guiRegister()   -- menu テーブルはここで組み立てられる (get_menu)
local dummy_tab = nil
for _, t in ipairs(menu) do
	if t.name == "Dummy" then dummy_tab = t end
end
want("タブは Dummy", dummy_tab ~= nil, true)
local row = nil
for _, e in ipairs(dummy_tab.entries) do
	if e.name == "Position" then row = e end
end
want("Position 行は Dummy タブにある", row ~= nil, true)
want("行の legend が更新されている", row:legend():find("HP: Place + close", 1, true) ~= nil, true)
want("行は validate と hp を持つ", row.validate ~= nil and row.hp ~= nil, true)

print(fails == 0 and "REP_OK" or (fails .. " REP_NG"))
os.exit(fails == 0 and 0 or 1)