-- WHAT WAITS WHILE THE GAME STANDS UNDER THE MENU (v11.7.28.1; review of
-- 7643e09). gameFreeze.lua stops the game, but the Lua side counted emulator
-- frames on through it. With globals.game_frozen set (the master, right after
-- gameFreezeModule.registerBefore):
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_freeze_holds.lua
--
--   [1] a take (macro.lua's recording) leaves the frames out
--   [2] a playback holds its place: the next frame is the one after, not
--       one the frozen frames ran past
--   [3] a loop's wait between passes is not spent
--   [4] the life refill (healthAndMeter.lua) does not fire, and keeps what was
--       left of its wait
--   [5] Looped Playback, the menu closed: a pass the game stood under goes
--       straight on (no 30-frame hold - a dash's neutral grew past the game's
--       window, user 2026-10-17). A menu the game ran under keeps the hold
--   [6] the Knockdown Logger counts no frame of it either: a recording is not
--       cut into new ones while the menu stands over a hit stun
local fails = 0
local function eq(what, got, want)
	if got == want then print("  ok " .. what .. " = " .. tostring(got))
	else
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(want) .. "]")
	end
end

-- ---------------------------------------------------------------------------
-- The emulator, enough for macro.lua (as analysis/test_quick_recording.lua).
local frame_no = 0
emu = { framecount = function() return frame_no end, romname = function() return "vsavj" end,
        parentname = function() return "vsav" end, sourcename = function() return "cps2.cpp" end,
        message = function() end, registerstart = function() end }
savestate = { registersave = function() end, registerload = function() end }
input = { registerhotkey = function() end }
local pad = { {}, {} }
joypad = { get = function(p) return p and pad[p] or {} end, set = function() end, getup = function() return {} end }
local ram, writes = {}, {}
memory = {
	readbyte = function(a) return ram[a] or 0 end,
	readword = function(a) return (ram[a] or 0) end,
	writeword = function(a, v) ram[a] = v ; writes[#writes + 1] = a end,
}
gui = { text = function() end }
fba = true

local FAKE = "FH_FAKE/"
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

package.loaded["./scripts/actionSequenceRunner"] = { cancel = function() end }
guard_action_input = {}
player_objects = { {}, {} }
globals = {
	options = { quick_recording = true, quick_auto_trim = true, looped_playback = false,
	            use_character_specific_slots = true, random_playback = false },
	dummy = { p2_char = "Felicia", recording_slot = "slot_1.mis" },
	controlling_p1 = true,
	match_running = function() return true end,
	recordingWizard = { is_active = function() return false end },
	controllerModule = { set_controlling_target = function(s) globals.controlling_p1 = (s == "P1") end },
	game_frozen = false,
}

dofile("macro-options.lua")
dofile("macro-modules.lua")
dofile("macro.lua")
path = FAKE
macroLuaModule.registerStart()
local function api() globals.macroLua = macroLuaModule.registerBefore() ; return globals.macroLua end
api()
local Q = dofile("quickRecording.lua")
local QFILE = FAKE .. "Felicia/quick_recording.mis"

-- One frame as the master runs it: after the game's frame (the take), then
-- the next frame's before (the playback). frozen is this frame's answer.
local function frame(p2, frozen)
	frame_no = frame_no + 1
	globals.game_frozen = frozen == true
	pad[1], pad[2] = {}, p2 or {}
	macroLuaModule.registerAfter()
	api()
	Q.registerAfter()
end
-- What the playback hands the game this frame, as one letter.
local function played()
	local k = globals.macroLua.get_keytable()
	if k["P2 Right"] then return "R" end
	if k["P2 Weak Punch"] then return "1" end
	if k["P2 Left"] then return "L" end
	return "."
end
local function player2(t) return ((t or ""):match("# Player 2\n([^\n]*)") or "") end
local R, LP, L = { ["P2 Right"] = true }, { ["P2 Weak Punch"] = true }, { ["P2 Left"] = true }

-- ---------------------------------------------------------------------------
print("[1] 記録: 止まっているフレームは入れない")
do
	Q.on_coin()
	frame({ ["P1 Coin"] = true })
	frame({})
	frame(R)
	frame(L, true) ; frame(L, true) ; frame(L, true)   -- the menu open: the game stands
	frame(LP)
	frame(L)
	frame({ ["P1 Coin"] = true })
	Q.on_coin()
	eq("P2: 右、弱P、左 (止まっていた 3 フレームの左は無い)", player2(files[QFILE]), "R.1.L.")
end

-- ---------------------------------------------------------------------------
print("[2] 再生: 止まっている間は同じ場所。再開したら次のフレームから")
do
	-- The take from [1] plays as soon as it is made. (Asked of the table in
	-- hand: api() is a registerBefore, and would play a frame.)
	eq("再生中", globals.macroLua.quick_playing(), true)
	local seen = {}
	local function run(n, frozen) for _ = 1, n do frame({}, frozen) ; seen[#seen + 1] = played() end end
	run(1)
	eq("最初のフレームは右", seen[1], "R")
	run(4, true)
	run(3)
	eq("止まっている 4 フレームは右のまま、その後に弱P、左、終わり", table.concat(seen), "RRRRR1L.")
	api().stop_all_playback()
end

-- ---------------------------------------------------------------------------
print("[3] ループの待ちは止まっている間に減らない")
do
	globals.hotkeys_armed = true      -- in a match: otherwise a loop is dropped
	globals.options.looped_playback = true
	globals.options.loop_interval_after_frames = 5
	globals.options.loop_interval_before_frames = 0
	-- The menu's slot: a loop's next pass is a playcontrol, which plays it.
	files[FAKE .. "Felicia/slot_1.mis"] = files[QFILE]
	-- From the end of one pass to the first input of the next, counted with
	-- the game standing for `frozen` frames right after the pass ends.
	local function gap(frozen)
		globals.macroLua.playcontrol(true)
		local n = 0
		repeat frame({}) ; n = n + 1 until played() == "L" or n > 60
		repeat frame({}) ; n = n + 1 until played() ~= "L" or n > 60
		for _ = 1, frozen do frame({}, true) end
		local m = 0
		repeat frame({}) ; m = m + 1 until played() == "R" or m > 60
		api().stop_all_playback()
		return m
	end
	local plain = gap(0)
	eq("待ちの後に次の回が来る", plain > 0 and plain < 60, true)
	eq("止まっていた 8 フレームは待ちに数えない", gap(8), plain)
	globals.options.looped_playback = false
end

-- ---------------------------------------------------------------------------
print("[4] 体力の回復: 止まっている間は出ない。待ちの残りはそのまま")
do
	local H = dofile("healthAndMeter.lua")
	globals.options.p2_max_life, globals.options.p1_max_life = 144, 144
	globals.options.p1_refill_timer, globals.options.p2_refill_timer = 1, 1   -- 60 frames
	globals.dmg_calc = {}
	local P2_STATE = 0xFF8805
	local function step(frozen)
		frame_no = frame_no + 1
		globals.game_frozen = frozen == true
		writes = {}
		H.registerBefore()
		for _, a in ipairs(writes) do if a == 0xFF8850 or a == 0xFF8852 then return true end end
		return false
	end
	ram[P2_STATE] = 2
	step()
	ram[P2_STATE] = 0
	step()                            -- the hit ends: the wait starts here
	local hit_at = frame_no
	local refills = {}
	for i = 1, 100 do
		local frozen = i >= 30 and i < 50     -- the menu open for 20 frames
		if step(frozen) then refills[#refills + 1] = frame_no - hit_at end
	end
	eq("回復は 1 回", #refills, 1)
	eq("  60 フレームに、止まっていた 20 フレームを足したところ", refills[1], 80)
	globals.game_frozen = false
end

-- ---------------------------------------------------------------------------
print("[5] Looped Playback: ゲームが止まっていたメニューを閉じたら、その場から続ける")
do
	globals.hotkeys_armed = true
	globals.options.looped_playback = true
	globals.options.loop_interval_after_frames = 0
	globals.options.loop_interval_before_frames = 0
	files[FAKE .. "Felicia/slot_1.mis"] = files[QFILE]
	-- A pass of the take (R, LP, L), the menu opened after its first frame.
	-- stood: whether the game stood under it.
	local function pass(stood)
		globals.macroLua.playcontrol(true)
		local seen, n = {}, 0
		repeat frame({}) ; n = n + 1 until played() == "R" or n > 60
		seen[#seen + 1] = played()
		globals.show_menu = true
		for _ = 1, 6 do frame({}, stood) end
		globals.show_menu = false
		for _ = 1, 4 do frame({}) ; seen[#seen + 1] = played() end
		api().stop_all_playback()
		for _ = 1, 40 do frame({}) end      -- past any hold, for the next case
		return table.concat(seen)
	end
	eq("止まっていた: 閉じた次のフレームから弱P、左 (入力を離さない)", pass(true):sub(1, 3), "R1L")
	local ran = pass(false)
	eq("ゲームが動いていた (試合外・位置の移動など): これまでどおり 30 フレーム待つ", ran, "R....")
	globals.options.looped_playback = false
end

-- ---------------------------------------------------------------------------
print("[6] Knockdown Logger: 止まっている間はフレームを数えない (記録を区切らない)")
do
	-- The exported registerBefore, lifted out of debugKnockdown.lua and run with
	-- the three locals it calls standing in.
	local fh = real_open("debugKnockdown.lua")
	local dsrc = fh:read("*a")
	fh:close()
	local s0 = dsrc:find('["registerBefore"] = function()', 1, true)
	local e0 = s0 and dsrc:find("\n  end,\n", s0, true)
	eq("書き出しの registerBefore がある", s0 ~= nil and e0 ~= nil, true)
	local calls = {}
	sync_diag_hooks = function() calls[#calls + 1] = "sync" end
	registerBefore = function() calls[#calls + 1] = "record" end
	p1_watch = function() calls[#calls + 1] = "p1" end
	local fn = assert(loadstring("return {" .. dsrc:sub(s0, e0 + 6) .. "}"))()["registerBefore"]
	globals.game_frozen = true
	fn()
	eq("止まっている: 記録も P1 の監視も進めない", table.concat(calls, ","), "sync")
	calls = {}
	globals.game_frozen = false
	fn()
	eq("動いている: いつもどおり", table.concat(calls, ","), "sync,record,p1")
	sync_diag_hooks, registerBefore, p1_watch = nil, nil, nil
	local ms = real_open("vsav_training_master_script.lua"):read("*a")
	local set = ms:find("\tglobals.game_frozen = gameFreezeModule.frozen()\n", 1, true)
	local call = ms:find("\tdebugKnockdownModule.registerBefore()\n", 1, true)
	eq("master: globals.game_frozen を立てた後に呼ぶ", set ~= nil and call ~= nil and set < call, true)
end

io.open, io.input, io.output = real_open, real_input, real_output
print(fails == 0 and "\n全て通った" or ("\n" .. fails .. " 件 NG"))
os.exit(fails == 0 and 0 or 1)
