-- RECORDING P1 GUARD (scripts/autoguard.lua, v11.7.31).
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_p1_guard_recording.lua
--
--   [1] on, through a take: P1's two Auto Guard bytes (+$3B2 / +$3E2) are 1,
--       P2's are left alone, and no key is pressed for anybody
--   [2] the take ends: what was there before comes back. Off (the default)
--       or no take: nothing is written
--   [3] a state load or the match ending forgets what was saved: nothing is
--       written over the game that is there now
--   [4] the hook-up: master (Quick or the wizard, every frame; the load
--       handler), menu, config, and the offsets the ROM sets per player
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

local ram, writes = {}, 0
memory = {
	readbyte = function(a) return ram[a] or 0 end,
	readword = function(a) return ram[a] or 0 end,
	writebyte = function(a, v) ram[a] = v ; writes = writes + 1 end,
}
emu = { framecount = function() return 0 end }
local in_match = true
globals = { options = { p1_guard_while_recording = 2 }, match_running = function() return in_match end }
package.loaded["./scripts/debugKnockdown"] = {}
dofile("autoguard.lua")
local A = autoguardModule
local P1_1, P1_2 = 0xFF87B2, 0xFF87E2
local P2_1, P2_2 = 0xFF8BB2, 0xFF8BE2

-- ---------------------------------------------------------------------------
print("[1] 記録中: P1 の Auto Guard の 2 バイトを 1 に。P2 は触らない")
do
	ram[P1_1], ram[P1_2], ram[P2_1], ram[P2_2] = 0, 7, 0, 0
	A.p1_guard_while_recording(true)
	A.p1_guard_while_recording(true)
	eq("P1 +$3B2", ram[P1_1], 1)
	eq("P1 +$3E2", ram[P1_2], 1)
	eq("P2 は触らない", ram[P2_1] .. "/" .. ram[P2_2], "0/0")
end

-- ---------------------------------------------------------------------------
print("[2] 記録が終わったら元の値に戻す。Off や記録していないときは書かない")
do
	A.p1_guard_while_recording(false)
	eq("元の値に戻す", ram[P1_1] .. "/" .. ram[P1_2], "0/7")
	writes = 0
	A.p1_guard_while_recording(false)
	eq("その後は書かない", writes, 0)
	globals.options.p1_guard_while_recording = 1
	A.p1_guard_while_recording(true)
	eq("Off (既定): 記録中でも書かない", writes, 0)
	globals.options.p1_guard_while_recording = nil
	A.p1_guard_while_recording(true)
	eq("設定の無いファイル: Off と同じ", writes, 0)
	globals.options.p1_guard_while_recording = 2
end

-- ---------------------------------------------------------------------------
print("[3] ステートの読み込みや試合の終わりでは、覚えた値を書き戻さない")
do
	ram[P1_1], ram[P1_2] = 0, 0
	A.p1_guard_while_recording(true)
	A.after_load()
	ram[P1_1], ram[P1_2] = 5, 5             -- the loaded game's own
	writes = 0
	A.p1_guard_while_recording(false)
	eq("ステートを読んだ後: 書かない", writes, 0)
	A.p1_guard_while_recording(true)
	in_match = false
	writes = 0
	A.p1_guard_while_recording(false)
	eq("試合が終わった後: 書かない", writes, 0)
	in_match = true
	writes = 0
	A.p1_guard_while_recording(false)
	eq("  忘れたので、その後も書かない", writes, 0)
end

-- ---------------------------------------------------------------------------
print("[4] 組み込み")
do
	local ms = slurp("vsav_training_master_script.lua")
	eq("master: Quick か Wizard の記録中を毎フレーム渡す",
	   ms:find("autoguardModule.p1_guard_while_recording(quickRecordingModule.recording()\n\t\tor (globals.recordingWizard ~= nil and globals.recordingWizard.is_active()))", 1, true) ~= nil, true)
	local load = ms:match("savestate%.registerload%(function%(slot%)(.-)\nend%)")
	eq("  ステートの読み込みで忘れる", load ~= nil and load:find("autoguardModule.after_load()", 1, true) ~= nil, true)
	local menu = slurp("menu.lua")
	eq("Recording タブに Recording P1 Guard (Off / Auto Guard、既定 Off)",
	   menu:find('list_menu_item("Recording P1 Guard", training_settings, "p1_guard_while_recording", { "Off", "Auto Guard" }, 1,', 1, true) ~= nil, true)
	eq("config の既定 p1_guard_while_recording = 1", slurp("config.lua"):find("\n  p1_guard_while_recording = 1,\n", 1, true) ~= nil, true)
	-- The game sets both bytes for each player at the same offsets: the loop
	-- at 0x925E runs with A0 = $400 and then $800 off A5.
	local rom = slurp("../analysis/mame_code/c00.txt")
	eq("ROM: プレイヤーごとの同じ位置 (0x925E、$400 と $800)",
	   rom:find("009254: 41ED 0400                lea     ($400,A5), A0", 1, true) ~= nil
	   and rom:find("00925A: 41ED 0800                lea     ($800,A5), A0", 1, true) ~= nil
	   and rom:find("009278: 1140 03B2                move.b  D0, ($3b2,A0)", 1, true) ~= nil, true)
	eq("  P2 の Auto Guard と同じ 2 つ (+$3B2 / +$3E2)", slurp("autoguard.lua"):find("local auto_guard_addr_1 = 0xFF8BB2", 1, true) ~= nil, true)
end

print(fails == 0 and "\n全て通った" or ("\n" .. fails .. " 件 NG"))
os.exit(fails == 0 and 0 or 1)
