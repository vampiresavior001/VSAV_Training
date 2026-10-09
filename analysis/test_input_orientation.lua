-- AUTO-FLIP INPUTS ON SIDE SWITCH (scripts/inputOrientation.lua, 2026-10-09).
--
-- On, the dummy's automated inputs follow a side switch, as before. Off, one
-- run - a recording playback, an Action Steps / Patterns / Specified input
-- from its arm, a Loop Steps lap - keeps the left / right of its first input
-- through any number of switches, so the game reads the same input against
-- its own new facing (option selects on a cross-up). A new run takes the
-- facing again; the setting is read when a run starts.
--
--   [1] recordings: the swap per frame (inputOrientation.rec_flip)
--   [2] Action Steps: the facing per input (inputOrientation.steps_face)
--   [3] guardCancel's real conversion (entry_to_bits) across a cross-up
--   [4] wiring: master, macro, runner, guardCancel, controller, menu, config
--
-- Run from scripts/ - guardCancel.lua is read and sliced from here.
--   cd scripts && lua5.1 ../analysis/test_input_orientation.lua
local fails = 0
local function eq(what, got, want)
	if got == want then print("  ok " .. what .. " = " .. tostring(got))
	else
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(want) .. "]")
	end
end
local function slurp(path)
	local fh = assert(io.open(path, "rb"), path)
	local s = fh:read("*a")
	fh:close()
	return s
end

training_settings = { auto_flip_inputs = true }
local O = dofile("inputOrientation.lua")

-- ---------------------------------------------------------------------------
print("[1] 記録の再生: 左右を入れ替えるか")
-- live: what the old rule says this frame (P2 faces the other way from the
-- take). pressing: the frame presses a P2 key.
local function play(serial, frames)
	local out = {}
	for i, f in ipairs(frames) do out[i] = O.rec_flip(serial, f[1], f[2]) and "F" or "-" end
	return table.concat(out)
end
O.reset()
training_settings.auto_flip_inputs = true
-- presses from frame 1; the sides switch at frame 3 and back at frame 5.
local CROSS = { { false, true }, { false, true }, { true, true }, { true, true }, { false, true }, { false, true } }
eq("ON: 毎フレーム追従 (従来どおり)", play(1, CROSS), "--FF--")
training_settings.auto_flip_inputs = false
eq("OFF: 最初に押したフレームの向きのまま (2 回入れ替わっても)", play(2, CROSS), "------")
eq("OFF: 入れ替わった後に始めた再生は、その向きで固定", play(3, { { true, true }, { false, true }, { true, true } }), "FFF")
-- the take opens on three neutral frames; the switch comes during them.
eq("OFF: 先頭のニュートラル中の入れ替わりは、最初の入力に反映", play(4,
	{ { false, false }, { true, false }, { true, false }, { true, true }, { false, true } }), "-FFFF")
eq("OFF: 同じ再生の続き (番号が同じ) は固定のまま", play(4, { { false, true } }), "F")
eq("OFF: 次の再生 (番号が変わる) で取り直す", play(5, { { false, true }, { true, true } }), "--")
-- the setting is read when a playback starts
training_settings.auto_flip_inputs = true
eq("途中で ON にしても、その再生は OFF のまま", play(5, { { true, true } }), "-")
eq("次の再生から ON", play(6, { { true, true } }), "F")
training_settings.auto_flip_inputs = false
eq("途中で OFF にしても、その再生は ON のまま", play(6, { { false, true } }), "-")
O.reset()
training_settings.auto_flip_inputs = true

-- ---------------------------------------------------------------------------
print("[2] Action Steps: 前・後を直す向き")
local function face_seq(id, list)
	local out = {}
	for i, f in ipairs(list) do out[i] = tostring(O.steps_face(f[1], id, f[2])) end
	return table.concat(out)
end
training_settings.auto_flip_inputs = true
local r1 = O.steps_begin()
eq("ON: 毎回いまの向き", face_seq(r1, { { 0, true }, { 1, true }, { 1, true }, { 0, true } }), "0110")
training_settings.auto_flip_inputs = false
local r2 = O.steps_begin()
eq("OFF: 押さない入力 (ニュートラル) では決めない", face_seq(r2, { { 0, false }, { 1, false } }), "01")
eq("OFF: 最初に押した入力の向きで固定、2 回入れ替わっても", face_seq(r2, { { 1, true }, { 0, true }, { 1, true }, { 0, false } }), "1111")
eq("その回の入力でないもの (id なし) はいまの向き", face_seq(nil, { { 0, true } }), "0")
local r3 = O.steps_begin()
eq("新しい回 (次の反撃・ループの周回) で取り直す", face_seq(r3, { { 0, true }, { 1, true } }), "00")
eq("前の回の入力は、もう固定を読まない", face_seq(r2, { { 0, true } }), "0")
O.steps_end()
eq("中断 (runner の cancel) の後は固定を読まない", face_seq(r3, { { 1, true } }), "1")
training_settings.auto_flip_inputs = true
local r4 = O.steps_begin()
training_settings.auto_flip_inputs = false
eq("始めたときの設定 (ON) のまま", face_seq(r4, { { 0, true }, { 1, true } }), "01")
O.reset()
eq("ロード・キャラクター選択の後は何も残らない", O.steps_run(), nil)
training_settings.auto_flip_inputs = true

-- ---------------------------------------------------------------------------
print("[3] guardCancel の変換 (entry_to_bits): めくりの前後で「前」がどのビットになるか")
local gsrc = slurp("guardCancel.lua")
local function slice(head, tail)
	local a = assert(gsrc:find(head, 1, true), head)
	local b = assert(gsrc:find(tail, a, true), tail)
	return gsrc:sub(a, b + #tail - 1)
end
local ram = {}
memory = { readbyte = function(a) return ram[a] or 0 end, readword = function(a) return ram[a] or 0 end }
GA = {}
actionSequenceRunnerModule = { orientation = O, owns = function(ga) return ga == "sequence" end }
globals = { dummy = { guard_action = "sequence" } }
player_objects = { {}, {} }
for _, piece in ipairs({
	slice("local BUTTON_BITS = {", "\n}\n"),
	slice("local function bor8(a, b)", "\nend\n"),
	slice("local function side_flag_now()", "\nend\n"),
	slice("function GA.af_live()", "\nend\n"),
	slice("function GA.af_run_now()", "\nend\n"),
	slice("local function facing_for_input(_press)", "\nend\n"),
	slice("local function entry_to_bits(_entry)", "\nend\n"),
}) do
	assert(loadstring((piece:gsub("^local ", ""))))()
end
-- P2 at X 0x200, P1 at 0x100: P2 on the right, facing 0. Then a cross-up:
-- P2 ends on the left (P1 at 0x300).
local function stand(p2_left)
	ram[0xFF8810] = 0x200
	ram[0xFF8410] = p2_left and 0x300 or 0x100
	ram[0xFF880B] = p2_left and 1 or 0
	ram[0xFF8920] = p2_left and 1 or 0
end
local function forward_bits(rec, p2_left)
	stand(p2_left)
	player_objects[2].pending_input_sequence = rec
	return (entry_to_bits({ "forward" }))
end
training_settings.auto_flip_inputs = true
local id = O.steps_begin()
local rec = { orient_run = id }
eq("ON: めくり前の前は 0x02", forward_bits(rec, false), 0x02)
eq("ON: めくり後は 0x01 (追従)", forward_bits(rec, true), 0x01)
training_settings.auto_flip_inputs = false
id = O.steps_begin()
rec = { orient_run = id }
eq("OFF: めくり前の前は 0x02", forward_bits(rec, false), 0x02)
eq("OFF: めくり後も 0x02 (同じ左右を送る)", forward_bits(rec, true), 0x02)
eq("OFF: 戻っても 0x02", forward_bits(rec, false), 0x02)
eq("OFF: その回の列でない (ガードキャンセルなど) は追従", forward_bits({}, true), 0x01)
-- The slot empty: a Hold left down belongs to the run whose guard action owns the dummy.
eq("OFF: 列が無いとき (Hold) は、持ち主の回の固定", forward_bits(nil, true), 0x02)
globals.dummy.guard_action = "gc"
eq("OFF: 持ち主でない Guard Action の Hold などは追従", forward_bits(nil, true), 0x01)
globals.dummy.guard_action = "sequence"
-- the first input after a switch that came before it
id = O.steps_begin()
rec = { orient_run = id }
stand(true)
eq("OFF: 最初の入力の前の入れ替わりは、開始の向きに反映 (ニュートラルでは決めない)",
	select(1, entry_to_bits({})), 0)
eq("  → 最初に押した入力は、そのときの向き (0x01)", forward_bits(rec, true), 0x01)
eq("  → 戻っても 0x01", forward_bits(rec, false), 0x01)
O.reset()
training_settings.auto_flip_inputs = true

-- ---------------------------------------------------------------------------
print("[4] つなぎ込み")
local master = slurp("vsav_training_master_script.lua")
eq("master: 起動時に require", master:find('= require "./scripts/inputOrientation"', 1, true) ~= nil, true)
eq("master: 通常の再生は rec_flip を通す (再生の番号・従来の判定・押しているか)",
	master:find("inputOrientationModule.rec_flip(globals.macroLua.playback_serial,\n\t\t\t\tmacro_playback_flipped(), p2_keys_down(_keys))", 1, true) ~= nil, true)
eq("master: Wizard の確認用の再生は従来どおり", master:find("globals.recordingWizard.preview_flip()", 1, true) ~= nil, true)
local lh = master:find("savestate.registerload(function(slot)", 1, true)
eq("master: ステートの読み込みで忘れる", lh ~= nil and master:find("inputOrientationModule.reset()", lh, true) ~= nil
	and master:find("inputOrientationModule.reset()", lh, true) < master:find("\n\tend)", lh, true), true)
local css = master:find("local function return_to_character_select", 1, true)
eq("master: キャラクター選択に戻るときも忘れる", css ~= nil and master:find("inputOrientationModule.reset()", css, true) ~= nil
	and master:find("inputOrientationModule.reset()", css, true) < master:find("globals.return_to_css = return_to_character_select", css, true), true)
local macro = slurp("macro.lua")
local _, starts = macro:gsub("playing = true\n%s*playback_serial = playback_serial %+ 1", "")
eq("macro: 再生が始まる 3 か所で番号を進める (Wizard の確認用は除く)", starts, 3)
eq("macro: 番号を外へ出す", macro:find('["playback_serial"] = playback_serial,', 1, true) ~= nil, true)
local runner = slurp("actionSequenceRunner.lua")
local function in_fn(src, head, needle)
	local a = src:find(head, 1, true)
	local b = a and src:find("\nend\n", a, true)
	return a ~= nil and src:sub(a, b):find(needle, 1, true) ~= nil
end
eq("runner: arm で回を始める", in_fn(runner, "function M.arm(which)", "inputOrientation.steps_begin()"), true)
eq("runner: arm_deferred で回を始める", in_fn(runner, "function M.arm_deferred(which, o)", "inputOrientation.steps_begin()"), true)
eq("runner: arm_oneshot で回を始める", in_fn(runner, "function M.arm_oneshot(owner, list, o)", "inputOrientation.steps_begin()"), true)
eq("runner: ループの周回の最初の段を積むとき回を始める",
	runner:find("if step.is_loop then inputOrientation.steps_begin() end\n\tqueue_input_sequence(defender, step.sequence)", 1, true) ~= nil, true)
eq("runner: 積んだ段にその回を付ける", runner:find("q.orient_run = inputOrientation.steps_run()", 1, true) ~= nil, true)
eq("runner: cancel で忘れる", in_fn(runner, "function M.cancel()", "inputOrientation.steps_end()"), true)
eq("runner: guardCancel へ渡す", runner:find("M.orientation = inputOrientation", 1, true) ~= nil, true)
eq("guardCancel: entry_to_bits は押すかどうかを渡す", gsrc:find("local _facing  = facing_for_input(#_entry > 0)", 1, true) ~= nil, true)
local _, q2 = gsrc:gsub("\n%s+GA%.af_queue%(_defender, ", "")   -- the calls, not the definition
eq("guardCancel: Guard Action の列を積む 2 か所で回を付ける", q2, 2)
local ctl = slurp("controller.lua")
eq("controller: フレームの経路も同じ固定を読む (決めるのは Tick の経路)",
	ctl:find("_face = inputOrientation.steps_face(_face, _player_obj.pending_input_sequence.orient_run, false)", 1, true) ~= nil, true)
local cfg = dofile("config.lua").default_training_settings
eq("初期値は ON", cfg.auto_flip_inputs, true)
local menu = slurp("menu.lua")
local _, rows = menu:gsub('checkbox_menu_item%("Auto%-Flip Inputs on Side Switch",\n%s*training_settings, "auto_flip_inputs", true,', "")
eq("メニュー: 同じ設定の行が 2 つ", rows, 2)
local d1 = menu:find('name = "Dummy"', 1, true)
local d2 = d1 and menu:find("dummy_auto_flip_item,", d1, true)
local d3 = d1 and menu:find("pit_of_blame_item,", d1, true)
eq("メニュー: Dummy タブの Guard Action の行の後", d2 ~= nil and d3 ~= nil and d2 < d3, true)
local r1p = menu:find('checkbox_menu_item("Reset Distance Each Loop"', 1, true)
local r2p = r1p and menu:find("recording_auto_flip_item,", r1p, true)
local r3p = r1p and menu:find('checkbox_menu_item("Use Savestate Upon Recording"', r1p, true)
eq("メニュー: Recording タブの Reset Distance Each Loop の下", r2p ~= nil and r3p ~= nil and r2p < r3p, true)
local help = menu:match('local AUTO_FLIP_HELP =\n(.-)\nlocal dummy_auto_flip_item')
local longest = 0
for l in (help or ""):gmatch('"(.-)\\n"') do if #l > longest then longest = #l end end
eq("説明文の行は 80 文字以内", help ~= nil and longest > 0 and longest <= 80, true)
-- Saved settings: missing key -> on (the old behaviour); a saved off stays off.
do
	package.preload["./scripts/dkjson"] = function() return {} end
	local saved
	training_settings_store = { load = function() return saved end, save = function() return true end }
	dofile("utilities.lua")
	saved = { settings_version = 5 }
	training_settings = dofile("config.lua").default_training_settings
	load_training_data()
	eq("旧設定に項目が無ければ ON", training_settings.auto_flip_inputs, true)
	saved = { settings_version = 5, auto_flip_inputs = false }
	training_settings = dofile("config.lua").default_training_settings
	load_training_data()
	eq("保存した OFF は OFF のまま", training_settings.auto_flip_inputs, false)
end

print(fails == 0 and "\n全て通った" or ("\n" .. fails .. " 件 NG"))
os.exit(fails == 0 and 0 or 1)
