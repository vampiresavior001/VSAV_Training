-- SAVE AND RESTORE A STATE BY HAND (scripts/trainingState.lua, v11.7.28).
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_training_state.lua
--
--   [1] Volume Up once: the state comes back once the window has passed -
--       nothing saved: a message, nothing loaded
--   [2] twice inside the window: saved, nothing restored; then nothing until
--       the key is let go. Held: one press
--   [3] restored: what runs stops first (playback, steps, queued inputs)
--   [4] not restored: another session (a character select), another pair,
--       another game speed
--   [5] not saved while anything runs a state does not carry; neither while
--       recording, in the wizard or the editor, during a position move or
--       outside a match. A failed save keeps the old one
--   [6] the hook-up, and nothing saving or loading a state on its own
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

local ram = {}
memory = { readbyte = function(a) return ram[a] or 0 end }
local messages = {}
emu = { message = function(m) messages[#messages + 1] = m end }
local saves, loads, save_fails = 0, 0, false
savestate = {
	create = function(name) return { name = name } end,
	save = function(st) if save_fails then error("refused") end ; saves = saves + 1 end,
	load = function(name) loads = loads + 1 end,
}
local pending, cancels = 0, 0
package.loaded["./scripts/actionSequenceRunner"] = {
	pending_count = function() return pending end,
	cancel = function() cancels = cancels + 1 ; pending = 0 end,
}
local stops = 0
local status = {}
local qr_rec, wz_on, ed_on, cam_busy, in_match = false, false, false, false, true
globals = {
	options = { game_speed = 3 },
	match_running = function() return in_match end,
	macroLua = { playing = false, starting = false,
	             get_recording_status = function() return status end,
	             stop_all_playback = function() stops = stops + 1 ; globals.macroLua.playing = false end },
	quickRecording = { recording = function() return qr_rec end },
	recordingWizard = { is_active = function() return wz_on end },
}
package.loaded["./scripts/actionSequenceEditor"] = { is_active = function() return ed_on end }
positionModule = { camera_restore_busy = function() return cam_busy end }
guard_action_input = {}
player_objects = { {}, {} }
local gm_run = nil
package.loaded["./scripts/grabMashing"] = { _run = function() return gm_run end }

local T = dofile("trainingState.lua")
local P1C, P2C = 0xFF8400 + 0x382, 0xFF8800 + 0x382
ram[P1C], ram[P2C] = 1, 5

-- The key over frames: true held, false up.
local held = false
local function frame(down)
	local edge = down and not held
	T.volume_up(edge, not down)
	held = down
	T.registerAfter()
end
local function frames(n, down) for _ = 1, n do frame(down) end end
local function last_msg() return messages[#messages] end
local function fresh()
	saves, loads, stops, cancels, pending, messages = 0, 0, 0, 0, 0, {}
	globals.macroLua.playing, globals.macroLua.starting, status = false, false, {}
	qr_rec, wz_on, ed_on, cam_busy, in_match, save_fails, gm_run = false, false, false, false, true, false, nil
	guard_action_input.csp_due = nil
	player_objects[2].pending_input_sequence = nil
	frames(T.WINDOW + 3, false)
end

-- ---------------------------------------------------------------------------
print("[1] 1 回押し: 判定時間が過ぎてから復元。保存が無ければ何もしない")
do
	fresh()
	frame(true) ; frame(false)
	frames(T.WINDOW - 2, false)
	eq("判定時間のうちは何もしない", loads, 0)
	frames(3, false)
	eq("保存が無い: 読み込まない", loads, 0)
	eq("  知らせる", last_msg(), "State not restored: no state saved")
end

-- ---------------------------------------------------------------------------
print("[2] 2 回押し: 保存だけ。離すまで次を受けない。押し続けは 1 回")
do
	fresh()
	frame(true) ; frame(false) ; frame(true)
	eq("2 回目で保存", saves, 1)
	eq("  先に復元しない", loads, 0)
	eq("  知らせる", last_msg(), "State saved")
	frames(T.WINDOW + 3, true)            -- still held: nothing more
	eq("押し続けても何もしない", saves + loads, 1)
	frames(2, false)
	-- A long hold is one press: once, then the window passes - a restore.
	fresh()
	frames(T.WINDOW + 5, true)
	frames(2, false)
	eq("長押しは 1 回押し (復元)", loads, 1)
	eq("  保存はしない", saves, 0)
end

-- ---------------------------------------------------------------------------
print("[3] 復元: 動いているものを先に止める")
do
	fresh()
	frame(true) ; frame(false) ; frame(true) ; frame(false)       -- save
	globals.macroLua.playing = true
	pending = 2
	player_objects[2].pending_input_sequence = { 1 }
	guard_action_input.csp_due = 9
	frame(true) ; frame(false) ; frames(T.WINDOW + 2, false)       -- restore
	eq("読み込んだ", loads, 1)
	eq("  再生を止めた", stops >= 1, true)
	eq("  Action Steps の残りを消した", cancels >= 1, true)
	eq("  送る前の入力を消した", player_objects[2].pending_input_sequence, nil)
	eq("  Character Specific の待ちを消した", guard_action_input.csp_due, nil)
	eq("  知らせる", last_msg(), "State restored")
end

-- ---------------------------------------------------------------------------
print("[4] 別のセッション・別のキャラ・別のゲーム速度の保存は読まない")
do
	local function restore_after(change)
		fresh()
		frame(true) ; frame(false) ; frame(true) ; frame(false)
		change()
		frame(true) ; frame(false) ; frames(T.WINDOW + 2, false)
		return loads, last_msg()
	end
	local n, m = restore_after(function() T.new_session() end)
	eq("キャラ選択の後 (同じ組を選び直しても): 読まない", n, 0)
	eq("  知らせる", m, "State not restored: saved in another session")
	n = restore_after(function() ram[P2C] = 6 end)
	eq("キャラが違う: 読まない", n, 0)
	ram[P2C] = 5
	n, m = restore_after(function() globals.options.game_speed = 2 end)
	eq("ゲーム速度が違う: 読まない", n, 0)
	eq("  知らせる", m, "State not restored: saved at another game speed")
	globals.options.game_speed = 3
	n = restore_after(function() end)
	eq("同じなら読む", n, 1)
end

-- ---------------------------------------------------------------------------
print("[5] 保存しないとき")
do
	local function save_with(set)
		fresh()
		set()
		frame(true) ; frame(false) ; frame(true) ; frame(false)
		return saves, last_msg()
	end
	local cases = {
		{ "再生中", function() globals.macroLua.playing = true end, "playback" },
		{ "再生の開始待ち", function() globals.macroLua.starting = true end, "playback" },
		{ "ループの合間", function() status = { loop_pending = true } end, "playback" },
		{ "Action Steps の残り", function() pending = 1 end, "Action Steps" },
		{ "送る前の入力", function() player_objects[2].pending_input_sequence = { 1 } end, "queued input" },
		{ "Character Specific の待ち", function() guard_action_input.csp_due = 3 end, "reversal waiting" },
		{ "Grab Mashing のつかみ中", function() gm_run = {} end, "Grab Mashing" },
		{ "Quick Recording の記録中", function() qr_rec = true end, "recording" },
		{ "Recording Wizard", function() wz_on = true end, "Recording Wizard" },
		{ "Action Steps のエディタ", function() ed_on = true end, "Action Steps editor" },
		{ "位置の移動中", function() cam_busy = true end, "position move" },
		{ "試合外", function() in_match = false end, "no match" },
	}
	for _, c in ipairs(cases) do
		local n, m = save_with(c[2])
		eq(c[1] .. ": 保存しない", n, 0)
		eq("  理由", m, "State not saved: " .. c[3])
	end
	-- Restoring under a recording: refused too.
	fresh()
	frame(true) ; frame(false) ; frame(true) ; frame(false)
	qr_rec = true
	frame(true) ; frame(false) ; frames(T.WINDOW + 2, false)
	eq("記録中は復元しない", loads, 0)
	eq("  理由", last_msg(), "State not restored: recording")
	-- With the menu open: it closes first, then the state loads (user,
	-- 2026-10-16: "ステートロードはメニューを閉じてロード、ボタンでもそれでいい").
	local closes = 0
	togglemenu = function() closes = closes + 1 ; globals.show_menu = not globals.show_menu end
	fresh()
	frame(true) ; frame(false) ; frame(true) ; frame(false)
	globals.show_menu = true
	frame(true) ; frame(false) ; frames(T.WINDOW + 2, false)
	eq("メニュー中の 1 回押し: メニューを閉じてから復元", closes .. "/" .. loads .. "/" .. tostring(globals.show_menu), "1/1/false")
	-- The editor keeps the menu open: nothing loads.
	fresh()
	frame(true) ; frame(false) ; frame(true) ; frame(false)
	globals.show_menu = true
	togglemenu = function() closes = closes + 1 end
	frame(true) ; frame(false) ; frames(T.WINDOW + 2, false)
	eq("メニューが閉じなければ (エディタの確認など) 復元しない", loads, 0)
	eq("  理由", last_msg(), "State not restored: close the menu first")
	-- Nothing saved: the menu is not closed for nothing.
	fresh()
	closes = 0
	togglemenu = function() closes = closes + 1 ; globals.show_menu = not globals.show_menu end
	T._forget()
	globals.show_menu = true
	frame(true) ; frame(false) ; frames(T.WINDOW + 2, false)
	eq("保存が無ければメニューは閉じない", closes .. "/" .. tostring(globals.show_menu), "0/true")
	eq("  理由", last_msg(), "State not restored: no state saved")
	globals.show_menu = false
	-- The menu's Restore State row: asked during the draw, loaded at the
	-- frame's end, the menu closed first.
	fresh()
	frame(true) ; frame(false) ; frame(true) ; frame(false)
	globals.show_menu = true
	closes = 0
	T.request_restore()
	eq("Restore State の行: 頼んだその場では読まない", loads, 0)
	T.registerAfter()
	eq("  フレームの終わりにメニューを閉じて復元", closes .. "/" .. loads, "1/1")
	globals.show_menu = false
	togglemenu = nil
	-- A save the emulator refuses keeps the one before.
	fresh()
	frame(true) ; frame(false) ; frame(true) ; frame(false)
	local before = T._saved()
	save_fails = true
	ram[P2C] = 7
	frame(true) ; frame(false) ; frame(true) ; frame(false)
	eq("保存に失敗したら前の保存のまま", T._saved(), before)
	ram[P2C] = 5
end

-- ---------------------------------------------------------------------------
print("[6] 組み込み、勝手に保存・読み込みをしない")
do
	local ms = slurp("vsav_training_master_script.lua")
	eq("起動時に require", ms:find('\nlocal trainingStateModule = require "./scripts/trainingState"', 1, true) ~= nil, true)
	eq("globals.trainingState", ms:find("\tglobals.trainingState = trainingStateModule\n", 1, true) ~= nil, true)
	eq("registerAfter", ms:find("\ttrainingStateModule.registerAfter()\n", 1, true) ~= nil, true)
	local sel = ms:match("if not globals%._select_cleared then(.-)end")
	eq("キャラ選択で新しいセッション", sel ~= nil and sel:find("trainingStateModule.new_session()", 1, true) ~= nil, true)
	local ctl = slurp("controller.lua")
	eq("controller: Volume Up は trainingState へ (押した瞬間と離れているか)",
	   ctl:find('_ts.volume_up(_inputs["Volume Up"] == nil and last_inputs["Volume Up"] == false,', 1, true) ~= nil, true)
	eq("controller: Volume Up で記録しない", ctl:find("reccontrol()", 1, true), nil)
	for _, f in ipairs({ "controller.lua", "macro.lua" }) do
		local src = slurp(f)
		eq(f .. ": current_recording を読み込まない", src:find('savestate.load("current_recording")', 1, true), nil)
		eq(f .. ": current_recording を作らない", src:find('savestate.create("current_recording")', 1, true), nil)
		eq(f .. ": Use Savestate Upon Recording を見ない", src:find("use_recording_savestate", 1, true), nil)
	end
	local menu = slurp("menu.lua")
	eq("メニューから Use Savestate Upon Recording を外した", menu:find('"Use Savestate Upon Recording"', 1, true), nil)
	eq("Save State", menu:find('{ name = "Save State",', 1, true) ~= nil, true)
	eq("Restore State の行がある (メニューを閉じてから)", menu:find('{ name = "Restore State",', 1, true) ~= nil
	   and menu:find("globals.trainingState.request_restore()", 1, true) ~= nil, true)
	eq("  Save State は確認してから (Yes / No、Yes から)", menu:find("validate = function(_self) save_state_ask() end,", 1, true) ~= nil
	   and menu:find('make_popup(112, 84, 272, 144, { _yes, _no }, "Save the state here?")', 1, true) ~= nil
	   and menu:find("current_popup.selected_index = 1\n", 1, true) ~= nil, true)
	eq("  Yes は同じ窓口 (trainingState.save)", menu:find("globals.trainingState.save()", 1, true) ~= nil, true)
	eq("  確認の左は戻る (Yes でも)", menu:find("function _yes:left() current_popup = nil end", 1, true) ~= nil
	   and menu:find("function _no:left() current_popup = nil end", 1, true) ~= nil, true)
end

print(fails == 0 and "\n全て通った" or ("\n" .. fails .. " 件 NG"))
os.exit(fails == 0 and 0 or 1)
