-- FRAME METER, AS TAKEN IN FROM tirsod/VSAV_FrameMeter (2026-10-04).
--
-- framemeter.lua is his file; the local changes are marked "VSAV_Training:".
-- This checks those changes and the hook, not his meter logic:
--
--   [1]  every image the module loads is in scripts/images/framemeter
--   [2]  it logs while globals.match_running() says so, not on match_begun
--   [3]  the hook: config defaults, rows at the end of Display, start-up require
--
-- 120Hz Ticks were marked on the meter for a while and taken out again before
-- release (user, 2026-10-04); see the commit that added this file.
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_framemeter.lua
local fails = 0
local function eq(what, got, want)
	if got == want then print("  ok " .. what .. " = " .. tostring(got))
	else
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(want) .. "]")
	end
end
local function slurp(path)
	local fh = io.open(path)
	assert(fh, path .. " が読めない")
	local s = fh:read("*a")
	fh:close()
	return s
end

-- ---------------------------------------------------------------------------
-- Stand-ins for FBNeo. gd checks that each image exists, relative to scripts/
-- as in the game.
local loaded_images = {}
gd = {
	createFromPng = function(path)
		local fh = io.open(path, "rb")
		loaded_images[#loaded_images + 1] = { path = path, ok = fh ~= nil }
		if fh then fh:close() end
		return { gdStr = function() return path end }
	end,
}
package.preload["gd"] = function() return gd end

local fc = 0
emu = {
	romname = function() return "vsavj" end,
	parentname = function() return "vsav" end,
	sourcename = function() return "CPS2" end,
	framecount = function() return fc end,
	screenwidth = function() return 384 end,
	registerafter = function() end,
}
local ram = {}
memory = {
	readbyte = function(a) return ram[a] or 0 end,
	readword = function(a) return ram[a] or 0 end,
	readdword = function(a) return ram[a] or 0 end,
}
-- Each tile is one gui.image of its state's PNG; gd above hands back the path.
local startup_tiles = 0
gui = {
	image = function(_, _, img)
		if img == "images/framemeter/FM_startup.png" then startup_tiles = startup_tiles + 1 end
	end,
	text = function() end,
	box = function() end,
}

local tick_cb
local running = true
local function fresh(match_begun)
	globals = {
		truth = { ticker = { subscribe = function(_, f) tick_cb = f end } },
		options = { display_frame_meter = true, fm_no_throw = false, fm_movement_data = false,
		            fm_input_p1 = false, fm_hitstop = true },
		game_state = { match_begun = match_begun },
		match_running = function() return running end,
		controllerModule = { enable_both_players = function() end },
	}
	local fm = dofile("framemeter.lua")
	fm.registerStart()
	return fm
end
-- P1 attacking, not walking: the meter logs every Tick.
ram[0xFF8400 + 0x105] = 1

-- One call per Tick.
local function feed(n)
	for i = 1, n do
		fc = fc + 1
		tick_cb(i)
	end
end
-- The meter grows in over ~96 draws; count only once it is fully out.
local function startup_drawn(fm)
	for _ = 1, 120 do fm.guiRegister() end
	startup_tiles = 0
	fm.guiRegister()
	return startup_tiles
end

-- ---------------------------------------------------------------------------
print("[1] 画像")
local fm = fresh(true)
local missing = 0
for _, im in ipairs(loaded_images) do if not im.ok then missing = missing + 1 ; print("    missing " .. im.path) end end
eq("読み込む画像がすべてある", missing, 0)
eq("読み込む画像の数", #loaded_images > 30, true)

-- ---------------------------------------------------------------------------
print("[2] 試合中かどうかは match_running で見る")
running = true
fm = fresh(false)                 -- match_begun false, as during a transformation
feed(4)
eq("match_begun が false でも記録する (P1 の発生 4 マス)", startup_drawn(fm), 4)
running = false
fm = fresh(true)
feed(4)
eq("match_running が false なら記録しない", startup_drawn(fm), 0)
running = true

-- ---------------------------------------------------------------------------
print("[3] つなぎ込み")
local cfg = dofile("config.lua").default_training_settings
for _, k in ipairs({ "display_frame_meter", "fm_no_throw", "fm_movement_data", "fm_input_p1", "fm_hitstop" }) do
	eq(k .. " の初期値は OFF", cfg[k], false)
end
local msrc = slurp("menu.lua")
local a = msrc:find('name = "Display"', 1, true)
local b = a and msrc:find('name = ', a + 20, true)
local tab = a and msrc:sub(a, b or #msrc) or ""
local row = tab:find('"Frame Meter", training_settings, "display_frame_meter", false,', 1, true)
eq("Display タブに Frame Meter の行", row ~= nil, true)
-- Last before Reset Tab, so the four rows open right under it.
local reset = tab:find('reset_tab_item("Display")', 1, true)
eq("Reset Tab の直前 (間に別の行が無い)", row ~= nil and reset ~= nil and row < reset
	and tab:sub(row, reset):find('child_of%("display_[^f]') == nil, true)
local kids = 0
for _ in tab:gmatch('child_of%("display_frame_meter"') do kids = kids + 1 end
eq("その子の行が 4 つ", kids, 4)
local master = slurp("vsav_training_master_script.lua")
eq("起動時に require", master:find('= require "./scripts/framemeter"', 1, true) ~= nil, true)
eq("registerStart を呼ぶ", master:find("frameMeterModule.registerStart()", 1, true) ~= nil, true)
eq("guiRegister を呼ぶ", master:find("frameMeterModule.guiRegister()", 1, true) ~= nil, true)

print(fails == 0 and "\n全て通った" or ("\n" .. fails .. " 件 NG"))
os.exit(fails == 0 and 0 or 1)
