-- FRAME METER, AS TAKEN IN FROM tirsod/VSAV_FrameMeter (2026-10-04).
--
-- framemeter.lua is his file; the local changes are marked "VSAV_Training:".
-- This checks those changes and the hook, not his meter logic:
--
--   [1]  every image the module loads is in scripts/images/framemeter
--   [2]  second_of_pair - the 120Hz pair test, wrap included
--   [3]  turbo: each pair gets a black dot each side of the border the two
--        tiles share, on the fill's third row - only on a tile that is not idle
--   [4]  normal speed: one Tick per frame, no dots
--   [5]  it logs while globals.match_running() says so, not on match_begun
--   [6]  the hook: config defaults, rows at the end of Display, start-up require
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
-- A 120Hz dot is a 1x1 gui.box. The tiles start at x = 8 and step 4, so the
-- border a pair shares is at x = 8 + 4k and its dots at 8 + 4k - 1 (the left
-- tile's last fill column) and 8 + 4k + 1 (the right tile's first).
local BLACK = "#000000FF"
local startup_tiles, tiles, boxes = 0, {}, {}
gui = {
	image = function(x, y, img)
		if img == "images/framemeter/FM_startup.png" then startup_tiles = startup_tiles + 1 end
		tiles[x .. "," .. y] = img
	end,
	text = function() end,
	box = function(x1, y1, x2, y2, fill)
		boxes[#boxes + 1] = { x = x1, y = y1, w = x2 - x1 + 1, h = y2 - y1 + 1, fill = fill }
	end,
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

-- One call per Tick, with the displayed frame the Tick ran in. `before`, if
-- given, runs ahead of each Tick (to change a state mid-run).
local function feed(frames, before)
	for i, f in ipairs(frames) do
		if before then before(i) end
		fc = f
		tick_cb(i)
	end
end
-- The meter grows in over ~96 draws; look only once it is fully out.
local function draw_once(fm)
	for _ = 1, 120 do fm.guiRegister() end
	startup_tiles, tiles, boxes = 0, {}, {}
	fm.guiRegister()
end
local function startup_drawn(fm)
	draw_once(fm)
	return startup_tiles
end
-- The dots drawn. Each is checked against the tile it sits in: a left dot
-- (x = 8 + 4k - 1) is in the tile drawn 3px to its left, a right one
-- (8 + 4k + 1) in the tile 1px to its left; either way 3 rows below that
-- tile's top - the third of its six fill rows, one above the lower middle,
-- which read as low (user, 2026-10-04) - and that tile is not an idle one.
-- Returns the count, how many pass all that, and lefts, rights, P1-row dots.
local function dotted(fm)
	draw_once(fm)
	local top
	for _, d in ipairs(boxes) do if top == nil or d.y < top then top = d.y end end
	local good, left, right, p1 = 0, 0, 0, 0
	for _, d in ipairs(boxes) do
		local side = (d.x - 8) % 4
		local host = nil
		if side == 3 then left = left + 1; host = tiles[(d.x - 3) .. "," .. (d.y - 3)] end
		if side == 1 then right = right + 1; host = tiles[(d.x - 1) .. "," .. (d.y - 3)] end
		if d.w == 1 and d.h == 1 and d.fill == BLACK and host ~= nil
		   and not host:find("inactive", 1, true) then
			good = good + 1
		end
		if d.y == top then p1 = p1 + 1 end
	end
	return #boxes, good, left, right, p1
end

-- ---------------------------------------------------------------------------
print("[1] 画像")
local fm = fresh(true)
local missing = 0
for _, im in ipairs(loaded_images) do if not im.ok then missing = missing + 1 ; print("    missing " .. im.path) end end
eq("読み込む画像がすべてある", missing, 0)
eq("読み込む画像の数", #loaded_images > 30, true)

-- ---------------------------------------------------------------------------
print("[2] second_of_pair")
local sf = fm.second_of_pair
local fr = { [0] = 10, [1] = 11, [2] = 11, [3] = 12 }
eq("2 は 1 と同じ表示フレームの 2 つ目", sf(fr, 2, 4), true)
eq("1 は組の 1 つ目 (つなぐのは 2 つ目の側だけ)", sf(fr, 1, 4), false)
eq("0 は 1 Tick だけ", sf(fr, 0, 4), false)
eq("3 は 1 Tick だけ", sf(fr, 3, 4), false)
eq("記録の無い所には付けない", sf(fr, 7, 4), false)
eq("一周の境目も隣どうし", sf({ [0] = 5, [3] = 5 }, 0, 4), true)

-- ---------------------------------------------------------------------------
print("[3] ターボ: 2 Tick 進む表示フレームの 2 マスに、境目の左右へ黒 1 ドットずつ")
-- 4 Ticks in 3 frames: frames 2, 5 and 8 each carry two Ticks.
local TURBO = { 1, 2, 2, 3, 4, 5, 5, 6, 7, 8, 8, 9 }
ram[0xFF8800 + 0x05] = 2          -- P2 in hit / block stun: yellow tiles
fm = fresh(true)
feed(TURBO)
local n, good, left, right, p1 = dotted(fm)
eq("ドットの数 (3 組 x 2 人 x 左右)", n, 12)
eq("どれも黒 1x1、動いているマスの上から 3 行目", good, 12)
eq("左右 6 ずつ", left .. "+" .. right, "6+6")
eq("P1 の段に 6", p1, 6)
ram[0xFF8800 + 0x05] = 0
-- P2 idle throughout: nothing on its row.
fm = fresh(true)
feed(TURBO)
n = dotted(fm)
eq("P2 が何もしていなければ P1 の 6 つだけ", n, 6)
-- One tile idle, the other not: the dot on the idle side is left out.
-- Hurt on Ticks 1-2 only: the pair at Ticks 2-3 is hurt, then idle.
fm = fresh(true)
feed({ 1, 2, 2, 3 }, function(i) ram[0xFF8800 + 0x05] = (i <= 2) and 2 or 0 end)
n, good, left, right, p1 = dotted(fm)
eq("やられ → 何もしない: P2 は左 (やられのマス) だけ", (n - p1) .. ":" .. left .. "+" .. right, "1:2+1")  -- P1: 1 + 1
-- Hurt from Tick 3 on: the pair at Ticks 2-3 is idle, then hurt.
fm = fresh(true)
feed({ 1, 2, 2, 3 }, function(i) ram[0xFF8800 + 0x05] = (i >= 3) and 2 or 0 end)
n, good, left, right, p1 = dotted(fm)
eq("何もしない → やられ: P2 は右 (やられのマス) だけ", (n - p1) .. ":" .. left .. "+" .. right, "1:1+2")  -- P1: 1 + 1
eq("どれも動いているマスの上", good, n)
ram[0xFF8800 + 0x05] = 0
-- Striped and light tiles get the same black dots: invulnerable white.
ram[0xFF8800 + 0x147] = 1
fm = fresh(true)
feed(TURBO)
n, good = dotted(fm)
eq("無敵の白のマスにも黒 (P1 6 + P2 6)", good .. "/" .. n, "12/12")
ram[0xFF8800 + 0x147] = 0

-- ---------------------------------------------------------------------------
print("[4] ノーマル: 1 フレーム 1 Tick なら付けない")
fm = fresh(true)
feed({ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 })
eq("ドットの数", (dotted(fm)), 0)

-- ---------------------------------------------------------------------------
print("[5] 試合中かどうかは match_running で見る")
running = true
fm = fresh(false)                 -- match_begun false, as during a transformation
feed({ 1, 2, 3, 4 })
eq("match_begun が false でも記録する (P1 の発生 4 マス)", startup_drawn(fm), 4)
running = false
fm = fresh(true)
feed({ 1, 2, 3, 4 })
eq("match_running が false なら記録しない", startup_drawn(fm), 0)
running = true

-- ---------------------------------------------------------------------------
print("[6] つなぎ込み")
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
