-- THE PLAYBACK SLOT (was Recording Slot), v11.7.28.
--
-- User, 2026-10-16: "そうなるとレコーディングスロットは無意味になるのでは？" ->
-- "推奨の整理で": renamed Playback Slot, Last Recording taken out of its list
-- (nothing writes last_recording.mis once Volume Up stops recording), so the
-- stored index is the slot's number, 1..5.
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_playback_slot.lua
--
--   [1] the row: Playback Slot, Slot 1..5, no Last Recording
--   [2] an old settings file: 1 (Last Recording) -> Slot 1, 2..6 -> 1..5;
--       a version 6 file is left alone
--   [3] who reads the index: the file name, the HUD, a random pick
local fails = 0
local function want(what, got, w)
	if got == w then print("  ok " .. what .. " = " .. tostring(got))
	else
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(w) .. "]")
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
print("[1] 行: Playback Slot、Slot 1〜5、Last Recording は無い")
local menu = slurp("menu.lua")
want("Playback Slot の行", menu:find('list_menu_item("Playback Slot", training_settings, "recording_slot", recording_slot,1,', 1, true) ~= nil, true)
want("Recording Slot の行は無い", menu:find('list_menu_item("Recording Slot"', 1, true), nil)
local list = menu:match("\nrecording_slot = (%b{})")
local names = {}
for n in (list or ""):gmatch('"([^"]+)"') do names[#names + 1] = n end
want("一覧は Slot 1〜5", table.concat(names, ","), "Slot 1,Slot 2,Slot 3,Slot 4,Slot 5")
local cfg = dofile("config.lua").default_training_settings
want("既定は 1 (Slot 1)", cfg.recording_slot, 1)
want("設定の版は 6 以上", cfg.settings_version >= 6, true)

-- ---------------------------------------------------------------------------
print("[2] 古い設定ファイル: Last Recording (1) は Slot 1、2〜6 は 1〜5")
package.preload["./scripts/dkjson"] = function() return {} end
memory = { readbyte = function() return 0 end, writebyte = function() end }
dofile("utilities.lua")
local saved = {}
training_settings_store = { load = function() return saved end, save = function() return true end }
local function migrated(file_table)
	saved = file_table
	training_settings = { recording_slot = 1, settings_version = 6 }
	load_training_data()
	return training_settings.recording_slot, training_settings.settings_version
end
local v, ver = migrated({ recording_slot = 1, settings_version = 5 })
want("1 (Last Recording) -> 1 (Slot 1)", v, 1)
want("  版は 6", ver, 6)
want("2 (Slot 1) -> 1", (migrated({ recording_slot = 2, settings_version = 5 })), 1)
want("4 (Slot 3) -> 3", (migrated({ recording_slot = 4, settings_version = 5 })), 3)
want("6 (Slot 5) -> 5", (migrated({ recording_slot = 6, settings_version = 5 })), 5)
want("版の無い古いファイルも移す (3 -> 2)", (migrated({ recording_slot = 3 })), 2)
want("版 6 のファイルはそのまま (3 は Slot 3)", (migrated({ recording_slot = 3, settings_version = 6 })), 3)

-- ---------------------------------------------------------------------------
print("[3] 番号を読むところ")
local ds = slurp("dummyState.lua")
local body = ds:match("local function get_recording_slot%(%)(.-)\nend")
local map = {}
for n, f in (body or ""):gmatch("pb_type == 0x(%d) then%s+slot = '([^']+)'") do map[#map + 1] = n .. "=" .. f end
want("1〜5 が slot_1〜5.mis", table.concat(map, " "),
     "1=slot_1.mis 2=slot_2.mis 3=slot_3.mis 4=slot_4.mis 5=slot_5.mis")
want("  last_recording.mis はもう無い", (body or ""):find("last_recording", 1, true), nil)
want("HUD は番号そのまま", slurp("hud.lua"):find("\tlocal slot = globals.options.recording_slot\n", 1, true) ~= nil, true)
want("ランダムで選んだスロットの番号をそのまま書く",
     slurp("macro.lua"):find("globals.options.recording_slot = slot.num\n", 1, true) ~= nil, true)

if fails == 0 then print("\n全て通った") else print("\n" .. fails .. " 件 NG") os.exit(1) end
