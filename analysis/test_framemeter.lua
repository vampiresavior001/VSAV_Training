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
local texts = {}
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
		texts[#texts + 1] = t
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
-- Both have a hurtbox, as a character normally does: with $94-$96 all 0 the
-- meter takes them for invulnerable (see [4j]).
ram[0xFF8400 + 0x94] = 1
ram[0xFF8800 + 0x94] = 1

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
	texts = {}
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
	local dots = {}
	for _, d in ipairs(boxes) do
		if d.w == 1 and d.h == 1 then dots[#dots + 1] = d end
	end
	boxes = dots
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
-- Invulnerability is drawn on the lower half now (see [4j]), so an idle P2
-- that is invulnerable is still an idle tile: no dots on its row.
ram[0xFF8800 + 0x147] = 1
fm = fresh(true)
feed(TURBO)
n, good = dotted(fm)
eq("何もしていない無敵の P2 には点を打たない (P1 の 6 つ)", good .. "/" .. n, "6/6")
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
--   close LP   startup 3 tiles, 3 red, 7 blue    (Startup 4 / Active 3 / Recovery 7)
--   crouch HK  startup 9 tiles, 4 red, 25 blue   (Startup 10 / Active 4 / Recovery 25)
-- The last blue tile is the tick $105 drops, the last of the table's 硬直
-- (THE MOVE'S LAST TICK IS BLUE, 2026-10-10); `rec` below is the ticks before it.
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
eq("近距離 LP 空振り: 緑 3 / 赤 3 / 青 7 (表の 3 | 3 | 7)", read(3, 3, 6, 0, 0), "3/3/7")
eq("近距離 LP ガード (11 Tick 止まる): 同じ", read(3, 3, 6, 11, 0), "3/3/7")
eq("しゃがみ大 K 空振り: 緑 9 / 赤 4 / 青 25", read(9, 4, 24, 0, 0), "9/4/25")
eq("しゃがみ大 K ガード (止まる間に 4 Tick 動く): 同じ", read(9, 4, 24, 11, 4), "9/4/25")

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
eq("緑 4・赤 3・青 4: 数字なし", numbers_for(4, 3, 3), "")
eq("緑 5・赤 3・青 4: 緑の 5 だけ", numbers_for(5, 3, 3), "5")
eq("緑 5・赤 3・青 6: 5 と 6", numbers_for(5, 3, 5), "5,6")
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
-- The off-screen credits text went too (user, 2026-10-08): scrolling the meter
-- brought it onto the screen. The origin stays credited in the README.
eq("画面外の謝辞の文は無い", fsrc:find("VSAV_FrameMeter by @tirsod.com", 1, true), nil)
eq("README には出典が残る", slurp("../README.md"):find("tirsod/VSAV_FrameMeter", 1, true) ~= nil, true)
globals.options.fm_input_p1 = false

-- ---------------------------------------------------------------------------
print("[4e] リバーサルフレーム: シグネチャの次の Tick の上 2 行をマゼンタに")
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
		if b.w == 3 and b.h == 2 and b.fill == "#FF40FFFF" then
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
print("[4i] 投げ: 判定の出た Tick を攻撃判定に、投げられている間をやられに (2026-10-08)")
-- A throw has no attack box. The game checks it on every tick its window is
-- out (0x029406, the hook Tick Data already has); tickDataVsav counts those
-- per player and the meter reads the count. The count is driven here.
local throw_count = { [A1] = 0, [A2] = 0 }
package.loaded["./scripts/tickDataVsav"] = { throw_checks = function(base) return throw_count[base] end }
local function throw_case(window, thrown_from)
	fm = fresh(true)
	local frames = {}
	for i = 1, 40 do frames[i] = 5000 + i end
	local in_window = {}
	for _, t in ipairs(window) do in_window[t] = true end
	feed(frames, function(i)
		ram[A1 + 0x105] = (i <= 24) and 1 or 0     -- the throw, start to end
		ram[A1 + 0x20] = 300 - i                    -- it plays every tick
		box(false) ; stop(0)
		if in_window[i] then throw_count[A1] = throw_count[A1] + 1 end
		ram[A2 + 0x05] = (thrown_from ~= nil and i >= thrown_from and i <= 22) and 6 or 0
	end)
	ram[A1 + 0x105] = 0 ; ram[A2 + 0x05] = 0 ; ram[A1 + 0x20] = 0
	draw_once(fm)
	local hurt = 0
	for _, img in pairs(tiles) do
		if img == "images/framemeter/FM_hurt.png" then hurt = hurt + 1 end
	end
	return startup_tiles, active_tiles, hurt, p1_numbers()
end
-- A grab that connects writes the opponent's thrown state on the tick it is
-- tried (0x029482), so the attempt and the thrown edge are the same tick.
local su, act, hurt, nums = throw_case({ 5 }, 5)
eq("掴んだ投げ: 試した 1 Tick が攻撃判定", act, 1)
eq("その前は発生", su, 4)
eq("発生は判定の Tick まで (4 + 1)", nums:match("^Startup (%d+)"), "5")
eq("投げられている 18 Tick はやられ", hurt, 18)
-- A grab made by a path that is not hooked: the thrown edge alone.
su, act = throw_case({}, 7)
eq("入口を通らない掴みも、投げられた Tick が攻撃判定", act, 1)
eq("その前は発生", su, 6)
su, act, hurt = throw_case({ 5, 6, 7, 8 }, nil)
eq("判定が 4 Tick 出る投げ (空振り): 4 マス", act, 4)
eq("投げられていなければやられは無い", hurt, 0)
su, act = throw_case({}, nil)
eq("判定が出なければ攻撃判定は無い (全部発生)", act, 0)
package.loaded["./scripts/tickDataVsav"] = nil
ram[A1 + 0x105] = 1

-- ---------------------------------------------------------------------------
print("[4j] 無敵は下半分の白。マスの色と数値はそのまま (2026-10-08)")
-- Invulnerability used to be a white tile of its own, which hid the startup,
-- active or recovery under it and restarted the Startup count where it ended.
-- Now it is the solid white lower half, for any of the hitbox display's
-- tests: $134, $147, $11E, $145 with $1A4 = 0, or no hurtbox ($94-$96 all 0).
local WHITE = "#F2F2F2FF"
local function invul_case(set, clear, shown)
	fm = fresh(true)
	globals.options.fm_no_throw = shown == true
	local frames = {}
	for i = 1, 30 do frames[i] = 6000 + i end
	feed(frames, function(i)
		ram[A1 + 0x105] = (i <= 12) and 1 or 0
		box(i >= 4 and i <= 6)
		ram[A1 + 0x20] = 100 - i
		if i <= 2 then set() else clear() end
		ram[A1 + 0x143] = (shown and i <= 2) and 1 or 0
	end)
	clear() ; box(false) ; ram[A1 + 0x20] = 0 ; ram[A1 + 0x143] = 0
	draw_once(fm)
	local white, stripes = 0, 0
	for _, b in ipairs(boxes) do
		if b.w == 3 and b.h == 3 and b.fill == WHITE then white = white + 1 end
		if b.w == 3 and b.h == 1 and b.fill == "#CA275FFF" then stripes = stripes + 1 end
	end
	globals.options.fm_no_throw = false
	return p1_numbers(), startup_tiles, white, stripes
end
local function byte(off, v) return function() ram[A1 + off] = v end end
local plain = invul_case(function() end, function() end)
eq("無敵なし", plain, "Startup 4 / Total 13 / Recovery 7")
local cases = {
	{ "やられ判定なし ($94-$96 = 0)", byte(0x94, 0), byte(0x94, 1) },
	{ "$147", byte(0x147, 9), byte(0x147, 0) },
	{ "$11E", byte(0x11E, 1), byte(0x11E, 0) },
	{ "$134", byte(0x134, 1), byte(0x134, 0) },
	{ "$145 ($1A4 = 0)", byte(0x145, 1), byte(0x145, 0) },
}
for _, c in ipairs(cases) do
	local nums, su, white = invul_case(c[2], c[3])
	eq(c[1] .. ": 数値は無敵なしと同じ", nums, plain)
	eq(c[1] .. ": 発生の緑は 3 マスのまま", su, 3)
	eq(c[1] .. ": 下半分の白は 2 マス", white, 2)
end
do
	local _, _, white = invul_case(function() ram[A1 + 0x145] = 1 ; ram[A1 + 0x1A4] = 20 end,
		function() ram[A1 + 0x145] = 0 ; ram[A1 + 0x1A4] = 0 end)
	eq("$145 でも $1A4 が残っていれば無敵ではない", white, 0)
end
do
	local _, _, white, stripes = invul_case(byte(0x147, 9), byte(0x147, 0), true)
	eq("無敵と投げ無敵が重なれば白 (縞は描かない)", white .. "/" .. stripes, "2/0")
end
-- Down is not invulnerable (user, 2026-10-08): "invulnerable shows not being
-- hit where you would be hit". A knockdown or wake-up cel has +$0B = $FE, and
-- while it does the white is left off, even with no hurtbox. Except Q-Bee's
-- head shake: still $FE once she is free ($05 = 0), and from the tick after she
-- becomes free (Actionable +0t) she can act - white from there.
do
	local function cel_flag(v) ram[CEL + 0x0B] = v ; ram[CEL + 0x100 + 0x0B] = v end
	-- ticks 1-6 down ($05 = 2), no hurtbox, $FE; 7 free (T); 8-9 still $FE
	-- (the head shake, +0t and +1t); 10- an ordinary cel. shake = false: the
	-- cel changes on T, as every other character's does on its reversal tick.
	-- $143 is set on T (7) and counts down to 0 on 12, as Q-Bee's does.
	local function wakeup(shake)
		fm = fresh(true)
		globals.options.fm_no_throw = true
		local frames = {}
		for i = 1, 20 do frames[i] = 6500 + i end
		feed(frames, function(i)
			ram[A1 + 0x105] = 0
			ram[A1 + 0x05] = (i <= 6) and 2 or 0
			ram[A1 + 0x94] = (i <= 6) and 0 or 1
			cel_flag(((i <= 6) or (shake and i <= 9)) and 0xFE or 0)
			ram[A1 + 0x143] = (i >= 7 and i <= 11) and (12 - i) or 0
			ram[A1 + 0x20] = 100 - i
		end)
		cel_flag(0) ; ram[A1 + 0x05] = 0 ; ram[A1 + 0x94] = 1 ; ram[A1 + 0x20] = 0 ; ram[A1 + 0x143] = 0
		draw_once(fm)
		local white, stripes = 0, 0
		for _, b in ipairs(boxes) do
			if b.w == 3 and b.h == 3 and b.fill == WHITE then white = white + 1 end
			if b.w == 3 and b.h == 1 and b.fill == "#CA275FFF" then stripes = stripes + 1 end
		end
		globals.options.fm_no_throw = false
		return white, stripes
	end
	local w, st = wakeup(false)
	eq("起き上がり ($FE、やられ判定なし) は白にしない", w, 0)
	eq("ほかのキャラの形 (T でセルが替わる): 投げ無敵は T から縞 5 マス", st, 5)
	w, st = wakeup(true)
	eq("Q-Bee の首振り: 動ける状態になった次の Tick (+0t) から白、2 マス", w, 2)
	eq("Q-Bee: T は縞も出さない (結果的にダウンと同じ)。白の後の残り 2 マスだけ縞", st, 2)
	local _, _, white = invul_case(function() cel_flag(0xFF) end, function() cel_flag(0) end)
	eq("+$0B = $FF は無敵ではない", white, 0)
	_, _, white = invul_case(function() cel_flag(0xFE) ; ram[A1 + 0x05] = 2 ; ram[A1 + 0x147] = 9 end,
		function() cel_flag(0) ; ram[A1 + 0x05] = 0 ; ram[A1 + 0x147] = 0 end)
	eq("ダウン中 ($05 = 2、$FE) は $147 があっても白にしない", white, 0)
	-- Morrigan's last wake-up ticks: an ordinary cel, no hurtbox, $145 with
	-- $1A4 = 0, on the ground (user's screenshot, 2026-10-08).
	local function morrigan(air)
		return function()
			ram[A1 + 0x05] = 2 ; ram[A1 + 0x94] = 0 ; ram[A1 + 0x145] = 1 ; ram[A1 + 0x1A4] = 0
			ram[A1 + 0x38] = air and 0xFF or 0
		end
	end
	local function back()
		ram[A1 + 0x05] = 0 ; ram[A1 + 0x94] = 1 ; ram[A1 + 0x145] = 0 ; ram[A1 + 0x38] = 0
	end
	_, _, white = invul_case(morrigan(false), back)
	eq("地上のやられ中 ($05 = 2): $FE でなくても、$145・やられ判定なしでも白にしない", white, 0)
	-- (user, 2026-10-08) In the air too: being knocked down or juggled is
	-- recovery, and the protection is a given.
	_, _, white = invul_case(morrigan(true), back)
	eq("空中のやられ中 (浮かされ・受け身) も白にしない", white, 0)
	local _, _, _, stripes = invul_case(function() ram[A1 + 0x05] = 2 end, function() ram[A1 + 0x05] = 0 end, true)
	eq("やられ中 ($05 = 2) の投げ無敵は縞にしない", stripes, 0)
	_, _, _, stripes = invul_case(function() end, function() end, true)
	eq("(対照) 動ける状態の投げ無敵は縞 2 マス", stripes, 2)
	ram[A1 + 0x105] = 1
end
-- Juggle invulnerability in the air is not $FE: still white ($145 above).
-- Dark Force activation ($06 = 0x16) is an animation with no attack flag. With
-- the white tile gone it read as doing nothing; it is startup (2026-10-08).
do
	fm = fresh(true)
	local frames = {}
	for i = 1, 60 do frames[i] = 7000 + i end
	feed(frames, function(i)
		ram[A1 + 0x105] = 0
		ram[A1 + 0x006] = (i <= 43) and 0x16 or 0
		ram[A1 + 0x147] = (i <= 43) and (44 - i) or 0
		ram[A1 + 0x20] = 300 - i
	end)
	ram[A1 + 0x006] = 0 ; ram[A1 + 0x147] = 0 ; ram[A1 + 0x20] = 0
	draw_once(fm)
	local white = 0
	for _, b in ipairs(boxes) do
		if b.w == 3 and b.h == 3 and b.fill == WHITE then white = white + 1 end
	end
	eq("DF 発動は発生 (緑 43 マス)", startup_tiles, 43)
	eq("下半分の白も 43 マス", white, 43)
	eq("数値は前の白いマスのときと同じ", p1_numbers(), "Startup 43 / Total 43 / Recovery 0")
end
ram[A1 + 0x105] = 1

-- ---------------------------------------------------------------------------
print("[4k] 持続からすぐ動ける技も、動ける Tick を硬直に数える (2026-10-08)")
-- Midnight Pleasure whiffed: startup, 29 active ticks, then free on the next
-- tick with no recovery tile. The tables and Tick Data read 2 / 29 / 1, total
-- 31; the meter read Recovery 0 / Total 30.
local function no_recovery_tiles(running)
	fm = fresh(true)
	local frames = {}
	local last = running and 25 or 40
	for i = 1, last do frames[i] = 8000 + i end
	feed(frames, function(i)
		ram[A1 + 0x105] = (i <= 30) and 1 or 0
		box(i >= 2 and i <= 30)
		ram[A1 + 0x20] = 300 - i
	end)
	box(false) ; ram[A1 + 0x20] = 0
	draw_once(fm)
	return p1_numbers()
end
eq("持続 29 のあとすぐ動ける: Recovery 1 / Total 31", no_recovery_tiles(false),
	"Startup 2 / Total 31 / Recovery 1")
eq("技の途中では足さない", no_recovery_tiles(true):match("Recovery (%d+)"), "0")
ram[A1 + 0x105] = 1

-- ---------------------------------------------------------------------------
print("[4l] ステートを読み込んだら、前の Tick と比べない。記録もつなげない (2026-10-08)")
-- Ten ticks, a load (fm.registerLoad, as the master script calls it), ten more.
-- `before` sets the RAM for each tick; `after` is the same for the ticks after
-- the load.
local function across_load(before, after)
	fm = fresh(true)
	local frames = {}
	for i = 1, 10 do frames[i] = 9000 + i end
	feed(frames, before)
	fm.registerLoad()
	for i = 1, 10 do frames[i] = 9100 + i end
	feed(frames, after)
	draw_once(fm)
end
ram[A1 + 0x105] = 1
across_load(nil, nil)
eq("動き続けていても、ロードの後から記録し直す (発生 10 マス、20 ではない)", startup_tiles, 10)
across_load(nil, function() ram[A1 + 0x105] = 0 end)
eq("ロードの後に誰も動かなければ、前の記録は残る (発生 10 マス)", startup_tiles, 10)
ram[A1 + 0x105] = 1
-- The reversal marker on the last tick before the load, gone after it: not a
-- reversal tick - the two ticks are not one after the other in the game.
across_load(function(i)
	ram[A2 + 0x05] = 2
	ram[A2 + 0x04] = (i == 10) and SIG or 0x02000000
end, function() ram[A2 + 0x05] = 0 ; ram[A2 + 0x04] = 0 end)
eq("ロード前のシグネチャで、ロード後に印を付けない", #marks(), 0)
ram[A2 + 0x05] = 0 ; ram[A2 + 0x04] = 0
-- Not thrown before the load, thrown in the loaded state: not a grab.
across_load(function() ram[A2 + 0x05] = 0 end, function() ram[A2 + 0x05] = 6 end)
eq("ロードをまたいで投げられた状態になっても、掴みのマスにしない", active_tiles, 0)
ram[A2 + 0x05] = 0
-- Control: without a load the same marker does mark the next tick.
fm = fresh(true)
recovery(A2, 1)
draw_once(fm)
eq("(対照) ロードが無ければ印は付く", #marks(), 1)

-- ---------------------------------------------------------------------------
print("[4m] ジャンプ通常技は着地で終わる。着地モーションは何もしていないマス (2026-10-10)")
-- A jump normal: 3 startup ticks in the air, 2 box ticks, 3 recovery ticks in
-- the air, then touchdown with $105 still 1 for 4 ticks (the landing motion,
-- cancellable into a grounded normal), then $105 = 0. Tick Data reads this as
-- Startup 4 / Active 2 / Recovery 4 / Total 9: the touchdown tick is the last.
-- `state` is $06 in the air (0x06 jump, 0x0E a special); `cancel_at` starts a
-- new attack ($1B8 + 1) on that tick of the landing motion.
local function jump_attack(state, cancel_at, movement)
	fm = fresh(true)
	globals.options.fm_movement_data = movement or false
	local frames = {}
	for i = 1, 30 do frames[i] = 9500 + i end
	feed(frames, function(i)
		local air = i <= 8
		ram[A1 + 0x38] = air and 0xFF or 0
		ram[A1 + 0x06] = (i <= 12) and (air and state or 0x06) or 0
		ram[A1 + 0x105] = (i <= 12) and 1 or 0
		ram[A1 + 0x1B8] = (cancel_at and i >= cancel_at) and 1 or 0
		box(i >= 4 and i <= 5)
		ram[A1 + 0x20] = 300 - i
	end)
	box(false) ; ram[A1 + 0x20] = 0 ; ram[A1 + 0x38] = 0 ; ram[A1 + 0x06] = 0 ; ram[A1 + 0x1B8] = 0
	draw_once(fm)
	return p1_numbers()
end
eq("着地のティックまで: Tick Data と同じ", jump_attack(0x06), "Startup 4 / Total 9 / Recovery 4")
eq("着地の Tick まで青、着地モーションは青にしない", recovery_tiles, 4)
eq("空中の $06 が 0x0A でも同じ", jump_attack(0x0A), "Startup 4 / Total 9 / Recovery 4")
eq("Include Jumps / Dashes が ON でも同じ", jump_attack(0x06, nil, true), "Startup 4 / Total 9 / Recovery 4")
eq("空中必殺技の着地硬直は硬直のまま", jump_attack(0x0E), "Startup 4 / Total 13 / Recovery 8")
-- Cancelled into a grounded normal on the third landing tick: that is a new
-- move, so it starts over with green tiles and is measured as itself.
jump_attack(0x06, 11)
eq("地上の通常技でキャンセルしたら、そこから新しい技 (発生のマス)", startup_tiles, 3 + 2)
ram[A1 + 0x105] = 1

-- ---------------------------------------------------------------------------
print("[4n] 技の最後の Tick を青に。数値と Advantage は変わらない (2026-10-10)")
-- The table's time chart draws 硬直 up to and including that tick (Midnight
-- Pleasure 1 | 29 | 1). The numbers stay as they were: Recovery is the blue
-- count now instead of the blue count + 1, and Advantage is measured from the
-- tile before it.
eq("持続の直後に動ける技 (ミッドナイトプレジャー): 青 1", read(1, 29, 0, 0, 0), "1/29/1")
eq("その数値", p1_numbers(), "Startup 2 / Total 31 / Recovery 1")
-- P1's close LP whiffs into a P2 in stun ($05 = 2) on ticks 4-16: P1's move
-- ends on tick 13 (its 13th tick, $105 0), P2 can act on 17.
local function advantage_case()
	fm = fresh(true)
	local frames = {}
	for i = 1, 40 do frames[i] = 9700 + i end
	feed(frames, function(i)
		ram[A1 + 0x105] = (i <= 12) and 1 or 0
		box(i >= 4 and i <= 6)
		ram[A1 + 0x20] = 300 - i
		ram[A2 + 0x05] = (i >= 4 and i <= 16) and 2 or 0
	end)
	box(false) ; ram[A1 + 0x20] = 0 ; ram[A2 + 0x05] = 0
	draw_once(fm)
	for k, t in ipairs(texts) do
		if t == measures[1] then return p1_numbers(), texts[k + 2], recovery_tiles end
	end
end
local nums, adv, blue = advantage_case()
eq("数値はこれまでどおり", nums, "Startup 4 / Total 13 / Recovery 7")
eq("Advantage もこれまでどおり (17 - 13)", adv, "4")
eq("青は 7 (最後が技の終わりの Tick)", blue, 7)
-- A jump attack whose $105 drops in the air, Include Jumps / Dashes on: the
-- tick it drops is blue, the fall after it light blue, and Recovery is the
-- same as Tick Data's (4: three recovery ticks and that one).
fm = fresh(true)
globals.options.fm_movement_data = true
local frames = {}
for i = 1, 30 do frames[i] = 9800 + i end
feed(frames, function(i)
	ram[A1 + 0x38] = (i <= 14) and 0xFF or 0
	ram[A1 + 0x06] = (i <= 14) and 0x06 or 0
	ram[A1 + 0x105] = (i <= 8) and 1 or 0
	box(i >= 4 and i <= 5)
	ram[A1 + 0x20] = 300 - i
end)
box(false) ; ram[A1 + 0x20] = 0 ; ram[A1 + 0x38] = 0 ; ram[A1 + 0x06] = 0
draw_once(fm)
eq("空中で技が終わったジャンプ攻撃: 数値は Tick Data と同じ", p1_numbers(), "Startup 4 / Total 9 / Recovery 4")
eq("その青は 4 (技の終わりの Tick まで)", recovery_tiles, 4)
globals.options.fm_movement_data = false
ram[A1 + 0x105] = 1
-- A move made on the tick after another ends: a jump held through a knockdown
-- move (Demitri's heavy Demon Cradle, then a jumping LP; user's screenshot
-- 2026-10-10). The first move ends on tick 21, drawn blue; the jump starts on
-- it. The jumping LP starts on 30, its box is out on 33-34, it lands on 36
-- (the landing motion runs to 39). Measured alone: Startup 4 / Total 7 /
-- Recovery 2. It read the two moves together once the first one's last tick
-- was no longer idle.
fm = fresh(true)
globals.options.fm_movement_data = true
frames = {}
for i = 1, 50 do frames[i] = 9900 + i end
feed(frames, function(i)
	local air = i >= 21 and i <= 35
	ram[A1 + 0x38] = air and 0xFF or 0
	ram[A1 + 0x06] = (i >= 21 and i <= 39) and 0x06 or 0
	ram[A1 + 0x105] = (i <= 20 or (i >= 30 and i <= 39)) and 1 or 0
	box((i >= 4 and i <= 6) or (i >= 33 and i <= 34))
	ram[A1 + 0x20] = 300 - i
end)
box(false) ; ram[A1 + 0x20] = 0 ; ram[A1 + 0x38] = 0 ; ram[A1 + 0x06] = 0
draw_once(fm)
eq("前の技の直後に跳んだジャンプ攻撃は、それだけを数える", p1_numbers(), "Startup 4 / Total 7 / Recovery 2")
globals.options.fm_movement_data = false
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
local load_hook = master:find("savestate.registerload(function(slot)", 1, true)
local load_end = load_hook and master:find("\n\tend)", load_hook, true)
local fm_load = master:find("frameMeterModule.registerLoad()", 1, true)
eq("ステートの読み込みで registerLoad を呼ぶ", load_hook ~= nil and fm_load ~= nil
	and fm_load > load_hook and load_end ~= nil and fm_load < load_end, true)

print(fails == 0 and "\n全て通った" or ("\n" .. fails .. " 件 NG"))
os.exit(fails == 0 and 0 or 1)
