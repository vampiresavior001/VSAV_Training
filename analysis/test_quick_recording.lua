-- QUICK RECORDING (scripts/quickRecording.lua, scripts/macro.lua, v11.7.28).
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_quick_recording.lua
--
--   [1] Coin, Coin: the dummy's plans go, P2 is yours, a take; then P1 again,
--       the take written to the dummy's quick_recording.mis and playing
--   [2] Auto Trim: the frames before the first input and after the last go,
--       the header's place is the one the first input was made from; Coin and
--       Start are never part of a take. Off: everything kept
--   [3] a take with no input: the old file stays, nothing plays
--   [4] Coin while the quick take plays: it stops and a new take begins
--   [5] off: Coin is not taken (controller.lua swaps sides). On while P2 is
--       yours: P1 back, no take. The wizard and outside a match: not taken
--   [6] a take goes when the setting turns off, the dummy changes, the wizard
--       comes up, the match ends or a state loads - the file stays
--   [7] Volume Down stops the quick take; copying it into the menu's slot
--   [8] a stop drops the quick file: the next start is the menu's slot again
--   [9] the hook-up: menu, config, master script, controller, zip, .gitignore
--  [10] Coin Saves To = Playback Slot: Coin to finish writes the take over the
--       menu's slot as well, without asking. Own Slot (the default): not
--  [11] what the player started last (the slot or the quick take) starts
--       again from its first frame (Play After Restore); the dummy's own
--       Reversal - Recording start is not remembered
--  [12] a message said through hold_message (a state saved, a take saved)
--       stays on the line while a playback writes its progress; named states
--       hand no macro data to the save
--  [13] a playback of the player's own (user_play, play_quick, replay_last)
--       owns P2 until it stops, the gaps between loops included: the dummy's
--       Guard Action reads 'none' and its plans go when it starts. A
--       Reversal - Recording start (playcontrol) is not one
--  [14] a Reversal / Counter Attack / Push Block - Recording playback stops the
--       frame P2 goes into hit or block stun, and the dummy's own settings
--       run from there: the take starts over on the next trigger
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

-- ---------------------------------------------------------------------------
-- The emulator, enough for macro.lua.
local frame_no = 0
local messages = {}
emu = { framecount = function() return frame_no end, romname = function() return "vsavj" end,
        parentname = function() return "vsav" end, sourcename = function() return "cps2.cpp" end,
        message = function(m) messages[#messages + 1] = m end, registerstart = function() end }
savestate = { registersave = function() end, registerload = function() end }
input = { registerhotkey = function() end }
local pad = { {}, {} }
joypad = { get = function(p) return p and pad[p] or {} end, set = function() end, getup = function() return {} end }
local ram = {}
memory = {
	readbyte = function(a) return ram[a] or 0 end,
	readword = function(a) return (ram[a] or 0) end,
	writeword = function(a, v) ram[a] = v end,
}
gui = { text = function() end }
fba = true

-- The macro folder, in memory: nothing here touches scripts/macro.
local FAKE = "QR_FAKE/"
local files = {}
local real_open, real_input, real_output = io.open, io.input, io.output
local function fake_handle(name, mode)
	local buf = {}
	return {
		read = function(_, _fmt) return files[name] end,
		write = function(_, s) buf[#buf + 1] = s end,
		close = function() if mode == "w" then files[name] = table.concat(buf) end end,
	}
end
io.open = function(name, mode)
	if type(name) == "string" and name:sub(1, #FAKE) == FAKE then
		if (mode or "r"):find("r") and files[name] == nil then return nil end
		return fake_handle(name, (mode or "r"):find("w") and "w" or "r")
	end
	return real_open(name, mode)
end
io.input = function(name)
	if type(name) == "string" and name:sub(1, #FAKE) == FAKE then return fake_handle(name, "r") end
	return real_input(name)
end
io.output = function(name)
	if type(name) == "string" and name:sub(1, #FAKE) == FAKE then return fake_handle(name, "w") end
	return real_output(name)
end

local cancels = 0
package.loaded["./scripts/actionSequenceRunner"] = { cancel = function() cancels = cancels + 1 end }
guard_action_input = { csp_due = 5 }
player_objects = { {}, { pending_input_sequence = { 1 }, counter = { sequence = { 1 }, attack_frame = 3, ref_time = 4 } } }
local side = "P1"
local wizard_on, in_match = false, true
globals = {
	options = { quick_recording = true, quick_auto_trim = true, looped_playback = false,
	            use_character_specific_slots = true, random_playback = false },
	dummy = { p2_char = "Felicia", recording_slot = "slot_1.mis" },
	controlling_p1 = true,
	match_running = function() return in_match end,
	recordingWizard = { is_active = function() return wizard_on end },
	controllerModule = { set_controlling_target = function(s) side = s ; globals.controlling_p1 = (s == "P1") end },
}

dofile("macro-options.lua")
dofile("macro-modules.lua")
dofile("macro.lua")
path = FAKE   -- after macro-options.lua: where macro.lua reads and writes
macroLuaModule.registerStart()
local function api() globals.macroLua = macroLuaModule.registerBefore() ; return globals.macroLua end
api()
local Q = dofile("quickRecording.lua")
local QFILE = FAKE .. "Felicia/quick_recording.mis"

-- One recorded frame: what the pad holds, where the two stand.
local P2_FACING, P1X, P2X = 0xFF880B, 0xFF8410, 0xFF8810
local function frame(p1, p2, x1, x2)
	frame_no = frame_no + 1
	pad[1], pad[2] = p1 or {}, p2 or {}
	if x1 then ram[P1X] = x1 end
	if x2 then ram[P2X] = x2 end
	macroLuaModule.registerAfter()
	api()
	Q.registerAfter()
end
local function take_text() return files[QFILE] end
local function body(text)
	-- The take without the header lines.
	return (text or ""):gsub("#[^\n]*\n", ""):gsub("^%s+", ""):gsub("%s+$", "")
end
local function fresh()
	Q.reset("test")
	api().stop_all_playback()
	globals.options.quick_recording, globals.options.quick_auto_trim = true, true
	globals.controllerModule.set_controlling_target("P1")
	wizard_on, in_match = false, true
	globals.dummy.p2_char = "Felicia"
	cancels = 0
	messages = {}
end

-- ---------------------------------------------------------------------------
print("[1] Coin で始めて、Coin で終える")
do
	fresh()
	guard_action_input.csp_due = 5
	player_objects[2].pending_input_sequence = { 1 }
	eq("Coin を受け取る", Q.on_coin(), true)
	eq("  記録中", Q.recording(), true)
	eq("  P2 を操作", side, "P2")
	eq("  反撃の予定を消す (runner.cancel)", cancels, 1)
	eq("  Character Specific の待ちも", guard_action_input.csp_due, nil)
	eq("  送る前の入力も", player_objects[2].pending_input_sequence, nil)
	frame({ ["P1 Coin"] = true }, {}, 100, 200)      -- the Coin that began it
	frame({}, {}, 101, 201)
	frame({}, {}, 102, 202)
	frame({}, { ["P2 Right"] = true }, 103, 203)      -- the first input
	frame({}, { ["P2 Right"] = true }, 104, 204)
	frame({}, {}, 105, 205)
	frame({}, { ["P2 Weak Punch"] = true }, 106, 206) -- the last input
	frame({}, {}, 107, 207)
	frame({ ["P1 Coin"] = true }, {}, 108, 208)      -- the Coin that ends it
	eq("Coin で終える", Q.on_coin(), true)
	eq("  記録は終わり", Q.recording(), false)
	eq("  P1 に戻る", side, "P1")
	eq("  ダミーの quick_recording.mis に書いた", take_text() ~= nil, true)
	eq("  そのまま再生", api().quick_playing(), true)
end

-- ---------------------------------------------------------------------------
print("[2] Auto Trim: 最初の入力の前と最後の入力の後を切る。Coin と Start は入れない")
do
	-- A .mis line per player; every frame ends with "." (W<n> waits n frames).
	local function player(t, n)
		return ((t or ""):match("# Player " .. n .. "\n([^\n]*)") or "")
	end
	local t = take_text() or ""
	eq("P2: 右、右、無し、弱P の 4 フレーム", player(t, 2), "R.R..1.")
	eq("P1: 押していない 4 フレーム (Coin は入れない)", player(t, 1), "W4")
	eq("開始位置は最初の入力の前のフレーム (102 / 202)", t:match("# startpos ([%d ]+)"), "102 0 202 0")
	-- Off: every frame kept, Coin and Start still not.
	fresh()
	globals.options.quick_auto_trim = false
	ram[P1X], ram[P2X] = 299, 399
	Q.on_coin()
	frame({ ["P1 Coin"] = true, ["P1 Start"] = true }, {}, 300, 400)
	frame({}, {}, 301, 401)
	frame({}, { ["P2 Left"] = true }, 302, 402)
	frame({}, {}, 303, 403)
	frame({ ["P1 Coin"] = true }, {}, 304, 404)
	Q.on_coin()
	t = take_text() or ""
	eq("Auto Trim Off: P2 は最初から最後まで 5 フレーム", player(t, 2), "..L...")
	eq("  P1 は 5 フレーム (Coin と Start は除く)", player(t, 1), "W5")
	eq("  開始位置は Coin を押した時", t:match("# startpos ([%d ]+)"), "299 0 399 0")
end

-- ---------------------------------------------------------------------------
print("[3] 入力の無い記録は保存しない。前のファイルはそのまま、再生もしない")
do
	fresh()
	local before = take_text()
	Q.on_coin()
	frame({ ["P1 Coin"] = true }, {}, 500, 600)
	frame({}, {}, 501, 601)
	frame({ ["P1 Coin"] = true }, {}, 502, 602)
	eq("終えたが保存しない", Q.on_coin(), true)
	eq("  ファイルは前のまま", take_text(), before)
	eq("  再生しない", api().quick_playing(), false)
	eq("  P1 に戻る", side, "P1")
	eq("  知らせる", messages[#messages], "Quick Recording: no input, not saved")
end

-- ---------------------------------------------------------------------------
print("[4] 再生中の Coin: 止めて、新しい記録を始める")
do
	fresh()
	eq("前の記録を再生", api().play_quick(), true)
	eq("  再生中", api().quick_playing(), true)
	Q.on_coin()
	eq("Coin で再生は止まる", api().quick_playing(), false)
	eq("  記録が始まる", Q.recording(), true)
	Q.cancel("test")
end

-- ---------------------------------------------------------------------------
print("[5] Off、P2 を操作中、ウィザード、試合外")
do
	fresh()
	globals.options.quick_recording = false
	eq("Off: Coin を受け取らない (左右の切替は controller.lua)", Q.on_coin(), false)
	eq("  記録しない", Q.recording(), false)
	fresh()
	globals.controllerModule.set_controlling_target("P2")
	eq("On で P2 を操作中: 受け取る", Q.on_coin(), true)
	eq("  P1 に戻すだけ", side, "P1")
	eq("  記録は始めない", Q.recording(), false)
	fresh()
	wizard_on = true
	eq("ウィザード中は受け取らない", Q.on_coin(), false)
	fresh()
	in_match = false
	eq("試合外では受け取らない", Q.on_coin(), false)
end

-- ---------------------------------------------------------------------------
print("[6] 記録中に理由が無くなったら捨てる。ファイルはそのまま、P1 に戻る")
do
	local function abandoned(change)
		fresh()
		local before = take_text()
		Q.on_coin()
		frame({}, { ["P2 Right"] = true }, 700, 800)
		change()
		frame({}, { ["P2 Right"] = true }, 701, 801)
		return Q.recording(), take_text() == before, side, api().quick_playing()
	end
	local r, same, s, p = abandoned(function() globals.options.quick_recording = false end)
	eq("Off にした: 捨てる", r, false) ; eq("  ファイルはそのまま", same, true) ; eq("  P1", s, "P1") ; eq("  再生しない", p, false)
	r, same = abandoned(function() globals.dummy.p2_char = "Morrigan" end)
	eq("ダミーが変わった: 捨てる", r, false) ; eq("  ファイルはそのまま", same, true)
	r = abandoned(function() wizard_on = true end)
	eq("ウィザードが始まった: 捨てる", r, false)
	r = abandoned(function() in_match = false end)
	eq("試合が終わった: 捨てる", r, false)
	fresh()
	Q.on_coin()
	Q.reset("load")
	eq("ステートのロード: 捨てる", Q.recording(), false)
end

-- ---------------------------------------------------------------------------
print("[7] Volume Down は Quick の再生を止める。スロットへのコピー")
do
	fresh()
	api().play_quick()
	eq("再生中の Volume Down: 止める", Q.volume_down(), true)
	eq("  止まった", api().quick_playing(), false)
	eq("止まっているときは受け取らない (メニューのスロットを再生)", Q.volume_down(), false)
	Q.on_coin()
	eq("記録中の Volume Down は受け取って何もしない", Q.volume_down(), true)
	eq("  記録は続く", Q.recording(), true)
	Q.cancel("test")
	local ok, name = api().copy_quick_to_slot()
	eq("コピーした", ok, true)
	eq("  メニューのスロット (Felicia/slot_1.mis)", name, "Felicia/slot_1.mis")
	eq("  中身は Quick の記録", files[FAKE .. "Felicia/slot_1.mis"], take_text())
	local ok3, name3 = api().copy_quick_to_slot(3)
	eq("メニューの行で選んだスロット (3) へ", name3, "Felicia/slot_3.mis")
	eq("  中身は Quick の記録", files[FAKE .. "Felicia/slot_3.mis"], take_text())
	globals.dummy.p2_char = "Morrigan"
	local ok2 = api().copy_quick_to_slot()
	eq("記録の無いダミーではコピーしない", ok2, false)
end

-- ---------------------------------------------------------------------------
print("[8] 止めたら Quick のファイルは外れる。次の再生はメニューのスロット")
do
	fresh()
	files[FAKE .. "Felicia/slot_1.mis"] = "# p2facing 0\n# startpos 1 1 1 1\n\nL,L,L\n"
	local read = {}
	local inp = io.input
	io.input = function(name) read[#read + 1] = name ; return inp(name) end
	api().play_quick()
	api().playcontrol(true)          -- stop
	api().playcontrol(true)          -- start again: the menu's slot
	io.input = inp
	eq("最初は Quick のファイル", read[1], QFILE)
	eq("  止めた後はメニューのスロット", read[#read], FAKE .. "Felicia/slot_1.mis")
	api().stop_all_playback()
end

-- ---------------------------------------------------------------------------
print("[10] Coin Saves To: Playback Slot なら Coin で終えたときスロットにも書く")
do
	local function take_with(mode, slot)
		fresh()
		globals.options.coin_saves_to = mode
		globals.options.recording_slot = slot
		files[FAKE .. "Felicia/slot_3.mis"] = "OLD"
		Q.on_coin()
		frame({}, { ["P2 Left"] = true }, 900, 950)
		frame({ ["P1 Coin"] = true }, {}, 901, 951)
		Q.on_coin()
		return files[FAKE .. "Felicia/slot_3.mis"], messages[#messages]
	end
	local s, m = take_with(1, 3)
	eq("Own Slot (既定): スロットは書かない", s, "OLD")
	eq("  知らせる", m:find("saved to", 1, true), nil)
	s, m = take_with(2, 3)
	eq("Playback Slot: メニューのスロット (3) に確認なしで書く", s, take_text())
	eq("  知らせる", m:find("saved to Felicia/slot_3.mis, playing", 1, true) ~= nil, true)
	eq("  再生するのは記録そのもの", api().quick_playing(), true)
	globals.options.coin_saves_to = nil
	s = take_with(nil, 3)
	eq("設定の無いファイル: Own Slot と同じ", s, "OLD")
	globals.options.coin_saves_to, globals.options.recording_slot = nil, nil
	api().stop_all_playback()
end

-- ---------------------------------------------------------------------------
print("[11] 最後に自分で再生したものを覚えて、最初から再生し直す (Play After Restore)")
do
	fresh()
	api().forget_user_play()
	eq("何も再生していない: 再生し直さない", api().replay_last(), false)
	files[FAKE .. "Felicia/slot_1.mis"] = take_text()      -- a take that parses
	api().user_play()                         -- Volume Down: the slot
	eq("Volume Down の再生はスロット", api().quick_playing(), false)
	api().user_play()                         -- stop
	eq("止めても覚えている", api().replay_last(), true)
	eq("  スロットを最初から", api().quick_playing() == false and api().get_recording_status().playing == true, true)
	api().stop_all_playback()
	api().play_quick()                        -- Play Quick Recording / the take after Coin
	api().stop_all_playback()
	eq("Quick の再生の後は Quick", api().replay_last() and api().quick_playing(), true)
	api().stop_all_playback()
	-- The dummy's own start (Reversal - Recording, guardCancel.lua) goes
	-- through playcontrol, not user_play: it is not remembered.
	api().playcontrol(true) ; api().playcontrol(true)
	eq("ダミーの反撃の再生は覚えない (Quick のまま)", api().replay_last() and api().quick_playing(), true)
	api().stop_all_playback()
	Q.on_coin()
	eq("記録中は再生し直さない", api().replay_last(), false)
	Q.cancel("test")
	api().forget_user_play()
	eq("忘れたら再生し直さない", api().replay_last(), false)
end

-- ---------------------------------------------------------------------------
print("[12] 再生中も、残す知らせは進み具合で上書きしない (約 2 秒)")
do
	-- A take writes "macro recording: n" every frame, the way a playback
	-- writes its own: the line the two share. The take's own start message
	-- is held as well, so it runs out first.
	fresh()
	Q.on_coin()
	eq("記録を始めた知らせは残る", messages[#messages], "Quick Recording: recording - Coin to finish")
	for _ = 1, 121 do frame({}, {}, 1, 1) end
	eq("その後は毎フレーム進み具合を書く", (messages[#messages] or ""):find("macro recording", 1, true) ~= nil, true)
	api().hold_message("State saved")
	local kept = 0
	for _ = 1, 119 do
		frame({}, {}, 1, 1)
		if messages[#messages] == "State saved" then kept = kept + 1 end
	end
	eq("  hold_message の知らせは 119 フレーム残る", kept, 119)
	eq("  その間は held_message が文を返す (Recording GUI が描く)", api().held_message(), "State saved")
	frame({}, {}, 1, 1)
	frame({}, {}, 1, 1)
	eq("  その後は進み具合に戻る", (messages[#messages] or ""):find("macro recording", 1, true) ~= nil, true)
	eq("  held_message も nil", api().held_message(), nil)
	Q.cancel("test")
	-- Drawn by Display > Recording GUI only (user, 2026-10-21: "Recoding Gui
	-- と一緒にして、慣れたらメッセージは不要なはず"): the emulator's own line did
	-- not show in play.
	local hud = slurp("hud.lua")
	local dr = hud:match("local function draw_rec%(%)(.-)\nend\n")
	eq("Recording GUI の枠の下に held_message を描く", dr ~= nil and dr:find("globals.macroLua.held_message()", 1, true) ~= nil
	   and dr:find("gui.text(mid_width, mid_height + 10, _held)", 1, true) ~= nil, true)
	eq("  描くのは Recording GUI が on のときだけ", hud:find("if globals.options.display_recording_gui == true then\n\t\t\tdraw_rec()", 1, true) ~= nil, true)
	local qr = slurp("quickRecording.lua")
	local ts = slurp("trainingState.lua")
	eq("Quick Recording と状態の保存の知らせは hold_message 経由",
	   qr:find("mac.hold_message(text)", 1, true) ~= nil and ts:find("mac.hold_message(text)", 1, true) ~= nil, true)
	local ms = slurp("macro.lua")
	eq("名前付きの状態の保存には再生の位置を渡さない (registerSave)",
	   ms:find('["registerSave"] = function(slot)', 1, true) ~= nil
	   and ms:find('if type(slot) ~= "number" then return end\n\t\tif mame then return emu.framecount() end', 1, true) ~= nil, true)
end

-- ---------------------------------------------------------------------------
print("[13] 自分で始めた再生のあいだは、ダミーの Guard Action を止める (user_playback)")
do
	fresh()
	files[FAKE .. "Felicia/slot_1.mis"] = take_text()
	eq("何も再生していない: false", api().user_playback(), false)
	api().user_play()                                  -- Volume Down / Play Recording
	eq("Volume Down の再生: true", api().user_playback(), true)
	api().user_play()                                  -- stop
	eq("  止めたら false", api().user_playback(), false)
	api().play_quick()
	eq("Quick の再生: true", api().user_playback(), true)
	api().stop_all_playback()
	eq("  止めたら false", api().user_playback(), false)
	api().replay_last()
	eq("状態の復元の後の再生 (replay_last): true", api().user_playback(), true)
	api().stop_all_playback()
	-- The dummy's own start (Reversal / Counter Attack - Recording) comes in
	-- through the table's playcontrol.
	api().playcontrol(true)
	eq("ダミーの反撃の再生 (playcontrol): false", api().get_recording_status().playing == true
	   and api().user_playback() == false, true)
	api().stop_all_playback()
	-- Between loops, and waiting to start: still the player's.
	-- In a match (a pending loop is dropped outside one), with the gap long
	-- enough to be seen.
	globals.options.looped_playback = true
	globals.options.loop_interval_after_frames = 5
	globals.hotkeys_armed = true
	api().setloop()
	api().user_play()
	local gaps, all_true = 0, true
	for _ = 1, 30 do
		frame({}, {}, 1, 1)
		macroLuaModule.registerBefore()
		if api().get_recording_status().loop_pending == true then gaps = gaps + 1 end
		if api().user_playback() ~= true then all_true = false end
	end
	eq("ループの合間を通った", gaps > 0, true)
	eq("  合間も含めてずっと true", all_true, true)
	api().stop_all_playback()
	globals.hotkeys_armed, globals.options.loop_interval_after_frames = nil, nil
	eq("  止めたら false", api().user_playback(), false)
	globals.options.looped_playback = false
	api().setloop()
	-- The hook-up: Guard Action reads 'none' while it holds, and what the
	-- dummy had planned goes the moment it starts.
	local ds = slurp("dummyState.lua")
	local ga = ds:match("local function get_guard_action%(%)(.-)\nend\n")
	eq("dummyState: その間の Guard Action は 'none'", ga ~= nil
	   and ga:find("if mac ~= nil and mac.user_playback ~= nil and mac.user_playback() then\n        return 'none'", 1, true) ~= nil
	   and ga:find("if mac ~= nil", 1, true) < ga:find("globals.options.guard_action == 0x2", 1, true), true)
	local ms = slurp("vsav_training_master_script.lua")
	-- Called, not only looked for: defined before its local, it was a nil
	-- global and stopped the script on the first playback (v11.7.31 test).
	cancels = 0
	guard_action_input.csp_due = 4
	player_objects[2].pending_input_sequence = { 1 }
	local ok = pcall(Q.drop_automation)
	eq("Q.drop_automation を呼べる", ok, true)
	eq("  ダミーの予定を消す (runner.cancel、待ち、送る前の入力)",
	   cancels .. "/" .. tostring(guard_action_input.csp_due) .. "/" .. tostring(player_objects[2].pending_input_sequence), "1/nil/nil")
	eq("master: 始まった瞬間にダミーの予定を消す (Quick の記録と同じ)",
	   ms:find("if _up and not globals.user_playback_was then quickRecordingModule.drop_automation() end", 1, true) ~= nil, true)
	eq("  ダミーの状態を作った直後", ms:find('globals["dummy"]   \t\t = dummyStateModule.registerBefore().get_dummy_state()\n\t-- A PLAYBACK OF THE PLAYER', 1, true) ~= nil, true)
end

-- ---------------------------------------------------------------------------
print("[14] Recording 系の反撃は、やられ・ガード硬直に入ったら止めて、次のきっかけで最初から")
do
	local ms = slurp("vsav_training_master_script.lua")
	local blk = ms:match("\tglobals%.rec_counter_cut = false\n(.-)\n\tif globals%.recordingWizard ~= nil and globals%.recordingWizard%.is_active%(%) then")
	eq("master: その判定がある (Wizard の分岐の直前)", blk ~= nil, true)
	blk = blk or ""
	eq("  $05 が 0 から 0 以外になったフレーム", blk:find("globals.rec_counter_st == 0 and _st ~= 0", 1, true) ~= nil
	   and blk:find("local _st = memory.readbyte(0xFF8805)", 1, true) ~= nil
	   and blk:find("globals.rec_counter_st = _st", 1, true) ~= nil, true)
	eq("  対象は Recording 系の 3 つだけ (自分の再生は Guard Action が 'none')",
	   blk:find("_ga == 'recording on reversal' or _ga == 'recording on counter'", 1, true) ~= nil
	   and blk:find("or _ga == 'recording on pushblock'", 1, true) ~= nil, true)
	eq("  再生を止める", blk:find("globals.macroLua.stop_all_playback()", 1, true) ~= nil, true)
	eq("  そのフレームは再生のキーを送らず、ダミーの設定の処理へ",
	   ms:find("\telseif globals.macroLua.playing == true and not globals.rec_counter_cut then\n", 1, true) ~= nil, true)
	-- The take starts again from its first frame: the stop leaves nothing to
	-- resume, and the next start is a fresh one.
	fresh()
	files[FAKE .. "Felicia/slot_1.mis"] = take_text()
	api().playcontrol(true)
	for _ = 1, 3 do macroLuaModule.registerBefore() end
	api().stop_all_playback()
	api().playcontrol(true)
	eq("止めた後の次の再生は 1 フレーム目から", api().get_recording_status().playing == true, true)
	api().stop_all_playback()
end

-- ---------------------------------------------------------------------------
print("[9] 組み込み")
do
	io.open, io.input, io.output = real_open, real_input, real_output
	local menu = slurp("menu.lua")
	eq("Recording タブに Quick Recording (既定 ON)",
	   menu:find('checkbox_menu_item("Quick Recording", training_settings, "quick_recording", true,', 1, true) ~= nil, true)
	eq("  その子に Auto Trim (既定 ON)",
	   menu:find('child_of("quick_recording", checkbox_menu_item("Auto Trim", training_settings, "quick_auto_trim", true,', 1, true) ~= nil, true)
	eq("  その子に Play Quick Recording", menu:find('child_of("quick_recording", { name = "Play Quick Recording",', 1, true) ~= nil, true)
	eq("  その子に Copy to Slot", menu:find('child_of("quick_recording", copy_quick_item()),', 1, true) ~= nil, true)
	-- The copy picks its slot in a window (user, 2026-10-16): Slot 1 to 5 and
	-- Cancel, landing on Cancel; a slot's row copies there, Left goes back.
	local cq = menu:match("function copy_quick_item%(%)(.-)\nend\n")
	eq("  窓: Slot 1〜5 と Cancel", cq ~= nil and cq:find("for _i = 1, 5 do _list[_i] = slot_row(_i) end", 1, true) ~= nil
	   and cq:find('local _no = { name = "Cancel" }', 1, true) ~= nil, true)
	eq("  開くと Cancel の上", cq ~= nil and cq:find("current_popup.selected_index = 6", 1, true) ~= nil, true)
	eq("  スロットの行でそこへコピー", cq ~= nil and cq:find("_m.copy_quick_to_slot(_i)", 1, true) ~= nil, true)
	eq("  左で戻る", cq ~= nil and cq:find("function _r:left() current_popup = nil end", 1, true) ~= nil, true)
	eq("  開いた押しの続きでは決めない (15 フレーム)", cq ~= nil and cq:find("emu.framecount() - opened_at < 15", 1, true) ~= nil, true)
	eq("  その子に Coin Saves To (Own Slot / Playback Slot、既定 Own Slot)",
	   menu:find('child_of("quick_recording", list_menu_item("Coin Saves To", training_settings, "coin_saves_to", { "Own Slot", "Playback Slot" }, 1,', 1, true) ~= nil, true)
	eq("Play Recording の行は user_play (Play After Restore が覚える)", menu:find("globals.macroLua.user_play()", 1, true) ~= nil
	   and menu:find("globals.macroLua.playcontrol()", 1, true) == nil, true)
	local cfg = slurp("config.lua")
	eq("config の既定 coin_saves_to = 1", cfg:find("\n  coin_saves_to = 1,\n", 1, true) ~= nil, true)
	eq("config の既定 quick_recording = true", cfg:find("\n  quick_recording = true,\n", 1, true) ~= nil, true)
	eq("config の既定 quick_auto_trim = true", cfg:find("\n  quick_auto_trim = true,\n", 1, true) ~= nil, true)
	local ms = slurp("vsav_training_master_script.lua")
	eq("起動時に require", ms:find('\nlocal quickRecordingModule = require "./scripts/quickRecording"', 1, true) ~= nil, true)
	eq("globals.quickRecording", ms:find("\tglobals.quickRecording = quickRecordingModule\n", 1, true) ~= nil, true)
	eq("registerAfter", ms:find("\tquickRecordingModule.registerAfter()\n", 1, true) ~= nil, true)
	local load = ms:match("savestate%.registerload%(function%(slot%)(.-)\nend%)")
	eq("ステートのロードで止める", load ~= nil and load:find('quickRecordingModule.reset("load")', 1, true) ~= nil, true)
	eq("記録中はダミーの自動操作を回さない", ms:find("\telseif quickRecordingModule.recording() then\n", 1, true) ~= nil, true)
	local ctl = slurp("controller.lua")
	eq("controller: Coin はまず Quick Recording に", ctl:find("local _handled = _qr ~= nil and _qr.on_coin ~= nil and _qr.on_coin()", 1, true) ~= nil, true)
	eq("controller: 記録中は Volume Down を受けない", ctl:find('not _wizard_busy and not _qr_busy and _inputs["Volume Down"] == nil', 1, true) ~= nil, true)
	eq("controller: Volume Up は記録せず trainingState へ (記録中は向こうが断る)", ctl:find("_ts.volume_up(", 1, true) ~= nil
	   and ctl:find("reccontrol()", 1, true) == nil, true)
	eq("controller: Volume Down はまず Quick の再生を止める", ctl:find("_qr.volume_down()", 1, true) ~= nil, true)
	eq("zip に入れない", slurp("../analysis/make_release_zip.py"):find('"quick_recording.mis",', 1, true) ~= nil, true)
	eq(".gitignore", slurp("../.gitignore"):find("\nquick_recording.mis\n", 1, true) ~= nil, true)
end

print(fails == 0 and "\n全て通った" or ("\n" .. fails .. " 件 NG"))
os.exit(fails == 0 and 0 or 1)
