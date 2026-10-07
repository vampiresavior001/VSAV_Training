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
local startup_tiles, active_tiles, recovery_tiles, tiles, boxes, numbers = 0, 0, 0, {}, {}, {}
local measures, ag_window, ag_success = {}, 0, 0
gui = {
	image = function(x, y, img)
		-- The AG overlays are drawn over a tile; counted, not recorded as one.
		if img == "images/framemeter/FM_pushblock.png" then ag_window = ag_window + 1 ; return end
		if img == "images/framemeter/FM_pushblock_OK.png" then ag_success = ag_success + 1 ; return end
		if img == "images/framemeter/FM_startup.png" then startup_tiles = startup_tiles + 1 end
		if img == "images/framemeter/FM_active.png" then active_tiles = active_tiles + 1 end
		if img == "images/framemeter/FM_recovery.png" then recovery_tiles = recovery_tiles + 1 end
		tiles[x .. "," .. y] = img
	end,
	text = function(x, y, t)
		if type(t) == "string" and t:match("^%d+$") then numbers[#numbers + 1] = t end
		if type(t) == "string" and t:match("^Startup") then measures[#measures + 1] = t end
	end,
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
		            fm_input_p1 = false },
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
	startup_tiles, active_tiles, recovery_tiles, tiles, boxes, numbers = 0, 0, 0, {}, {}, {}
	measures, ag_window, ag_success = {}, 0, 0
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
print("[4b] ヒットストップは「動かなかった Tick」だけ飛ばす (Show P1 Inputs = no)")
-- Demitri, measured on the real thing (2026-10-05): the close LP stands still
-- through hitstop, the crouching HK keeps animating through it. Whiff and
-- block have to read the same, as Tick Data does:
--   close LP   startup 3 tiles, 3 red, 6 blue    (Startup 4 / Active 3 / Recovery 7)
--   crouch HK  startup 9 tiles, 4 red, 24 blue   (Startup 10 / Active 4 / Recovery 25)
-- The HK's box ticks and its first recovery tick all play while $5C is set:
-- the contact tick, then 3 box ticks and 1 recovery tick inside the freeze.
-- A tick where the animation advanced changes $20 (the cel's remaining
-- ticks); here $20 simply counts down while the move plays.
local CEL = 0x500000
local A1, A2 = 0xFF8400, 0xFF8800
local function box(on) ram[A1 + 0x1C] = on and CEL or CEL + 0x100 ; ram[CEL + 0x0A] = on and 1 or 0 end
local function stop(n) ram[A1 + 0x5C] = n ; ram[A2 + 0x5C] = n end
-- One move. `plays` says which of the frozen ticks still animate.
--   su / act / rec  startup, box and recovery ticks the move plays
--   freeze          ticks of hitstop after contact (0 = whiff)
--   anime           how many ticks the move keeps playing inside the freeze
local function move(su, act, rec, freeze, anime)
	local script = {}                 -- one entry per tick: kind, plays
	for _ = 1, su do script[#script + 1] = { "su", true } end
	local played_in_freeze = 0
	for k = 1, act do
		script[#script + 1] = { "act", true }
		if k == 1 and freeze > 0 then
			-- contact: freeze ticks follow, the first `anime` of them playing on
			for f = 1, freeze do
				if played_in_freeze < anime then
					played_in_freeze = played_in_freeze + 1
					script[#script + 1] = { "frz_play", true }
				else
					script[#script + 1] = { "frz_still", false }
				end
			end
		end
	end
	for _ = 1, rec do script[#script + 1] = { "rec", true } end
	-- the ticks played inside the freeze came off what follows it
	local trimmed, drop = {}, played_in_freeze
	for i, e in ipairs(script) do
		if drop > 0 and i > su + 1 + freeze and (e[1] == "act" or e[1] == "rec") then
			drop = drop - 1
		else
			trimmed[#trimmed + 1] = e
		end
	end
	-- what each tick shows: box out for the act ticks and for the first act-1
	-- of the ticks played in the freeze; recovery for the rest
	local frames, n = {}, #trimmed + 12
	for i = 1, n do frames[i] = i end
	local anim, box_left, frz = 200, act, 0
	ram[A2 + 0x1C] = 0 ; ram[A2 + 0x20] = 0   -- the swap below has to be a change
	feed(frames, function(i)
		local e = trimmed[i]
		ram[A1 + 0x105] = e and 1 or 0
		ram[A2 + 0x05] = 0
		if e == nil then box(false) ; stop(0) ; return end
		if e[2] then anim = anim - 1 end
		ram[A1 + 0x20] = anim
		if e[1] == "su" then box(false) ; stop(0)
		elseif e[1] == "act" then
			box(true) ; box_left = box_left - 1
			if box_left == act - 1 and freeze > 0 then frz = freeze ; stop(frz) else stop(0) end
		elseif e[1] == "frz_play" or e[1] == "frz_still" then
			-- $5C stays set on every frozen tick and reads 0 on the first one
			-- that moves again (measured: the v1 trial read the LP right). The
			-- attacker's own $5C runs out a tick before the defender's, and on
			-- that tick it has not moved yet (user's screenshots, 2026-10-07).
			stop(frz) ; ram[A1 + 0x5C] = frz - 1 ; frz = frz - 1
			if e[1] == "frz_play" then
				box(box_left > 0) ; if box_left > 0 then box_left = box_left - 1 end
			end
			-- the defender enters guard on the first frozen tick: a new cel,
			-- nothing played. Must not make a tile of its own.
			if frz == freeze - 1 then ram[A2 + 0x1C] = 0x600000 ; ram[A2 + 0x20] = 9 end -- first frozen tick
		else box(false) ; stop(0) end
	end)
end
local function read(su, act, rec, freeze, anime, inputs)
	fm = fresh(true)
	globals.options.fm_input_p1 = inputs == true
	move(su, act, rec, freeze, anime)
	draw_once(fm)
	return startup_tiles .. "/" .. active_tiles .. "/" .. recovery_tiles
end
-- P1's numbers as drawn, and the gray "still in hitstop" marks.
local function p1_numbers() return ((measures[1] or ""):gsub(" / Advantage.*$", "")) end
local function still_marks()
	local n = 0
	for _, b in ipairs(boxes) do
		if b.w == 3 and b.h == 2 and b.fill == "#B0B0B0FF" then n = n + 1 end
	end
	return n
end
eq("近距離 LP 空振り: 緑 3 / 赤 3 / 青 6", read(3, 3, 6, 0, 0), "3/3/6")
eq("近距離 LP ガード (11 Tick 止まる): 同じ", read(3, 3, 6, 11, 0), "3/3/6")
eq("しゃがみ大 K 空振り: 緑 9 / 赤 4 / 青 24", read(9, 4, 24, 0, 0), "9/4/24")
eq("しゃがみ大 K ガード (止まる間に 4 Tick 動く): 同じ", read(9, 4, 24, 11, 4), "9/4/24")

-- ---------------------------------------------------------------------------
print("[4f] Show P1 Inputs でヒットストップも並べるが、数値は変わらない (2026-10-07)")
-- Inputs on: every hitstop tick is logged, so the input icons can be read
-- against it. A tick a character spent still - in hitstop, not moving - gets a
-- gray top and is left out of its numbers, so they read the same either way.
-- LP blocked: P1 still on the 11 frozen ticks, P2 on those and the contact
-- tick (12). Inputs off, only the contact tick is logged of those: P2's 1.
-- Crouching HK: P1 plays 4 of the 11 and is still on 7; P2 the same 12. Inputs
-- off, the 4 played ticks and the contact tick are logged: P2's 5.
local cases = {
	{ "近距離 LP ガード", { 3, 3, 6, 11, 0 }, "Startup 4 / Total 13 / Recovery 7", 1, 23 },
	{ "しゃがみ大 K ガード", { 9, 4, 24, 11, 4 }, "Startup 10 / Total 38 / Recovery 25", 5, 19 },
}
for _, c in ipairs(cases) do
	local a = c[2]
	read(a[1], a[2], a[3], a[4], a[5], false)
	eq(c[1] .. ": 入力 OFF の数値", p1_numbers(), c[3])
	eq(c[1] .. ": 入力 OFF の灰色の印", still_marks(), c[4])
	read(a[1], a[2], a[3], a[4], a[5], true)
	eq(c[1] .. ": 入力 ON でも同じ数値", p1_numbers(), c[3])
	eq(c[1] .. ": 入力 ON の灰色の印 (止まった Tick 全部)", still_marks(), c[5])
end
read(3, 3, 6, 0, 0, false)
eq("空振りの数値も同じ", p1_numbers(), "Startup 4 / Total 13 / Recovery 7")
globals.options.fm_input_p1 = false

-- ---------------------------------------------------------------------------
print("[4c] 同じ色が 5 マス以上続いたら数字 (6 から変更、2026-10-06)")
-- Up to four can be seen at a glance; from five the count is written.
local function numbers_for(su, act, rec)
	read(su, act, rec, 0, 0)
	table.sort(numbers)
	return table.concat(numbers, ",")
end
eq("緑 4・赤 3・青 4: 数字なし", numbers_for(4, 3, 4), "")
eq("緑 5・赤 3・青 4: 緑の 5 だけ", numbers_for(5, 3, 4), "5")
eq("緑 5・赤 3・青 6: 5 と 6", numbers_for(5, 3, 6), "5,6")
box(false) ; stop(0) ; ram[A1 + 0x105] = 1 ; ram[A1 + 0x20] = 0 ; ram[A2 + 0x1C] = 0 ; ram[A2 + 0x20] = 0

-- ---------------------------------------------------------------------------
print("[4d] 隠し要素は消した (2026-10-06)")
-- It used to shake the meter each time Include Hitstop was toggled, and after
-- 60 shakes blow it apart, close the menu and hand both players back.
local fsrc = slurp("framemeter.lua")
for _, gone in ipairs({ "explode_meter", "make_particle", "fightcade_txt", "enable_both_players",
                        "show_menu", "meter_anchor.shake" }) do
	eq(gone .. " が無い", fsrc:find(gone, 1, true), nil)
end
fm = fresh(true)
globals.show_menu = true
local handed_back = 0
globals.controllerModule = { enable_both_players = function() handed_back = handed_back + 1 end }
for i = 1, 200 do
	globals.options.fm_input_p1 = (i % 2 == 0)
	fc = 1000 + i
	tick_cb(1000 + i)
	fm.guiRegister()
end
eq("200 回切り替えてもメニューは開いたまま", globals.show_menu, true)
eq("操作も渡さない", handed_back, 0)
eq("謝辞の文は残す", fsrc:find("VSAV_FrameMeter by @tirsod.com", 1, true) ~= nil, true)
globals.options.fm_input_p1 = false

-- ---------------------------------------------------------------------------
print("[4e] リバーサルフレーム: シグネチャの次の Tick の上 2 行を黄色に")
-- The game writes $04..$07 = 02 02 04 00 on the last recovery tick (free-1);
-- the tick after it is the one where only a special (or guard) can start.
-- Here: stun on ticks 1..10, the signature on the last one or two of them,
-- free from tick 11.
local SIG = 0x02020400
local function recovery(addr, sig_ticks)
	local frames = {}
	for i = 1, 20 do frames[i] = 2000 + i end
	feed(frames, function(i)
		ram[addr + 0x05] = (i <= 10) and 2 or 0
		ram[addr + 0x04] = (i > 10 - sig_ticks and i <= 10) and SIG or 0x02000000
	end)
	ram[addr + 0x05] = 0 ; ram[addr + 0x04] = 0
end
-- The marks drawn, and for each the tile under it and the tile before it.
local function marks()
	local out = {}
	for _, b in ipairs(boxes) do
		if b.w == 3 and b.h == 2 and b.fill == "#FFF730FF" then
			out[#out + 1] = { here = tiles[(b.x - 1) .. "," .. (b.y - 1)],
			                  before = tiles[(b.x - 5) .. "," .. (b.y - 1)] }
		end
	end
	return out
end
for _, case in ipairs({ { "P2", 0xFF8800, 1 }, { "P2 (2 Tick 続くシグネチャ)", 0xFF8800, 2 },
                        { "P1", 0xFF8400, 1 } }) do
	fm = fresh(true)
	globals.options.fm_input_p1 = false
	ram[0xFF8400 + 0x105] = 0
	recovery(case[2], case[3])
	draw_once(fm)
	local m = marks()
	eq(case[1] .. ": 印は 1 つ", #m, 1)
	eq(case[1] .. ": 黄 (やられ) の直後のマス", m[1] and m[1].before, "images/framemeter/FM_hurt.png")
	eq(case[1] .. ": 印のマスはまだ何もしていない色", m[1] and m[1].here, "images/framemeter/FM_inactive.png")
end
fm = fresh(true)
recovery(0xFF8800, 0)
draw_once(fm)
eq("シグネチャが無ければ印も無い (自分の技の硬直明けなど)", #marks(), 0)
ram[0xFF8400 + 0x105] = 1

-- ---------------------------------------------------------------------------
print("[4g] 投げ無敵は下半分に描くだけ。数値も記録の続き方も変えない")
-- Throw invulnerability used to be a state of its own, which replaced the
-- startup / active / recovery under it while shown. Now it is a flag beside
-- the state, drawn as stripes on rows 4-6 of the tile.
local function lp_nothrow(nothrow_until, shown, shown_while_recording)
	fm = fresh(true)
	globals.options.fm_no_throw = shown_while_recording == true
	local frames = {}
	for i = 1, 40 do frames[i] = 3000 + i end
	feed(frames, function(i)
		ram[A1 + 0x105] = (i <= 12) and 1 or 0
		box(i >= 4 and i <= 6)
		ram[A1 + 0x20] = 100 - i                 -- the move plays every tick
		ram[A1 + 0x143] = (i <= nothrow_until) and 1 or 0
	end)
	ram[A1 + 0x143] = 0 ; box(false) ; ram[A1 + 0x20] = 0
	-- Switched on only now: what is drawn must come from what was recorded
	-- while it was off.
	globals.options.fm_no_throw = shown
	draw_once(fm)
	local half = 0
	for _, b in ipairs(boxes) do
		if b.w == 3 and b.h == 1 and b.fill == "#CA275FFF" then half = half + 1 end
	end
	return p1_numbers(), half
end
local plain = lp_nothrow(0, false)
eq("投げ無敵なしの近距離 LP", plain, "Startup 4 / Total 13 / Recovery 7")
local n_off, h_off = lp_nothrow(8, false)
local n_on, h_on = lp_nothrow(8, true)
eq("発生と持続に投げ無敵が重なっても、表示 OFF の数値は同じ", n_off, plain)
eq("表示 ON でも数値は同じ", n_on, plain)
local n_rec = lp_nothrow(8, true, true)
eq("記録中から表示 ON でも数値は同じ", n_rec, plain)
eq("表示 OFF なら下半分は描かない", h_off, 0)
eq("表示 ON なら 8 マスの下半分", h_on, 8)
local _, h_long = lp_nothrow(25, true)
eq("技が終わっても投げ無敵の間は記録が続く (25 マス、記録時は表示 OFF)", h_long, 25)
globals.options.fm_no_throw = false
ram[A1 + 0x105] = 1

-- ---------------------------------------------------------------------------
print("[4h] AG: 受付は Show P1 Inputs のときだけ、成立は常に")
local function guard_with_pb(inputs, success_tick)
	fm = fresh(true)
	globals.options.fm_input_p1 = inputs
	local frames = {}
	for i = 1, 30 do frames[i] = 4000 + i end
	feed(frames, function(i)
		ram[A1 + 0x105] = (i <= 20) and 1 or 0
		-- P1 plays except on ticks 6-10, which are hitstop where nobody moves.
		if i < 6 or i > 10 then ram[A1 + 0x20] = 200 - i end
		stop((i >= 6 and i <= 10) and (11 - i) or 0)
		ram[A2 + 0x05] = (i >= 6 and i <= 18) and 2 or 0
		ram[A2 + 0x1AB] = (i >= 6 and i <= 19) and (20 - i) or 0      -- P2's AG window
		ram[A1 + 0x1B0] = (i == success_tick) and 2 or 0               -- P1 pushed back
	end)
	stop(0) ; ram[A2 + 0x05] = 0 ; ram[A2 + 0x1AB] = 0 ; ram[A1 + 0x1B0] = 0 ; ram[A1 + 0x20] = 0
	draw_once(fm)
	return ag_window, ag_success
end
local w_off, s_off = guard_with_pb(false, 15)
local w_on, s_on = guard_with_pb(true, 15)
eq("入力 OFF: 受付は描かない", w_off, 0)
eq("入力 ON: 受付を描く", w_on > 0, true)
eq("成立は入力 OFF でも描く", s_off, 1)
eq("成立は入力 ON でも描く", s_on, 1)
local _, s_skip = guard_with_pb(false, 8)
eq("飛ばしたヒットストップの中の成立も、次のマスに描く", s_skip, 1)
globals.options.fm_input_p1 = false
ram[A1 + 0x105] = 1

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
-- Include Jumps / Dashes (fm_movement_data) is on for a new install since
-- 2026-10-06 and Show Throw Invulnerability (fm_no_throw) since 2026-10-07;
-- the rest stay off.
eq("fm_movement_data の初期値は ON", cfg.fm_movement_data, true)
eq("fm_no_throw の初期値は ON", cfg.fm_no_throw, true)
eq("Include Hitstop (fm_hitstop) は無い", cfg.fm_hitstop, nil)
for _, k in ipairs({ "display_frame_meter", "fm_input_p1" }) do
	eq(k .. " の初期値は OFF", cfg[k], false)
end
local msrc = slurp("menu.lua")
local a = msrc:find('name = "Display"', 1, true)
local b = a and msrc:find('name = ', a + 20, true)
local tab = a and msrc:sub(a, b or #msrc) or ""
local row = tab:find('"Frame Meter", training_settings, "display_frame_meter", false,', 1, true)
eq("Display タブに Frame Meter の行", row ~= nil, true)
-- Last before Reset Tab, so its rows open right under it.
local reset = tab:find('reset_tab_item("Display")', 1, true)
eq("Reset Tab の直前 (間に別の行が無い)", row ~= nil and reset ~= nil and row < reset
	and tab:sub(row, reset):find('child_of%("display_[^f]') == nil, true)
local kids = 0
for _ in tab:gmatch('child_of%("display_frame_meter"') do kids = kids + 1 end
eq("その子の行が 3 つ (Include Hitstop は 2026-10-07 に外した)", kids, 3)
-- What Reset This Tab and MP restore must be the same as a new install.
for _, k in ipairs({ "fm_no_throw", "fm_movement_data", "fm_input_p1" }) do
	local d = tab:match('"' .. k .. '", (%a+),')
	eq(k .. " のメニューの初期値が config と同じ", d, tostring(cfg[k]))
end
local master = slurp("vsav_training_master_script.lua")
eq("起動時に require", master:find('= require "./scripts/framemeter"', 1, true) ~= nil, true)
eq("registerStart を呼ぶ", master:find("frameMeterModule.registerStart()", 1, true) ~= nil, true)
eq("guiRegister を呼ぶ", master:find("frameMeterModule.guiRegister()", 1, true) ~= nil, true)

print(fails == 0 and "\n全て通った" or ("\n" .. fails .. " 件 NG"))
os.exit(fails == 0 and 0 or 1)
