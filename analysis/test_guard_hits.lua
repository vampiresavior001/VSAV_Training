-- GUARD = AFTER HIT GUARD / FIRST GUARD ONLY (scripts/autoguard.lua) AND
-- SHOW BLOCKING DIRECTION (scripts/timers.lua), v11.7.32. The two as the 3rd Strike
-- training mode 3rd_training_lua has them ("after first hit" / "first hit").
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_guard_hits.lua
--
--   [1] After Hit Guard: no guard until an attack connects, then guard; First
--       Guard Only: the first attack is guarded, and that guard counts - then none
--   [2] the count starts over 12 Ticks after the dummy can act again - the
--       attacker walking up counted, the attacker mid-attack waited for; a
--       new contact or the dummy's own attack starts the Ticks over; turbo
--       and the Tick counter wrapping are counted
--   [3] another Guard: the Random Guard % roll decides (nil)
--   [4] Show Blocking Direction: on the frame a guard lands on either player,
--       the lever sent the frame before, as a numpad direction; added only
--       when it differs; a new guard in a string ($158 up) counts; a hit or
--       nothing held (Auto Guard) is not kept; 120 frames
--   [5] the hook-up: menu (Guard values appended, Random Guard % hidden for
--       them and back to its five), hud, config, timers
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
local frame_no = 1000
memory = { readbyte = function(a) return ram[a] or 0 end, readword = function(a) return ram[a] or 0 end,
           writebyte = function(a, v) ram[a] = v end }
emu = { framecount = function() return frame_no end }
globals = { options = { guard = 8 }, controlling_p1 = true }
package.loaded["./scripts/debugKnockdown"] = {}
dofile("autoguard.lua")
local A = autoguardModule
local ME, FOE, TICK = 0xFF8800, 0xFF8400, 0xFF8081

local function stand(base) ram[base + 0x05], ram[base + 0x06], ram[base + 0x105] = 0, 0, 0 end
local function walk(base) ram[base + 0x05], ram[base + 0x06], ram[base + 0x105] = 0, 0x02, 0 end
local function hurt(base) ram[base + 0x05], ram[base + 0x06], ram[base + 0x54], ram[base + 0x105] = 2, 0, 0, 0 end
local function guard(base) ram[base + 0x05], ram[base + 0x06], ram[base + 0x54], ram[base + 0x105] = 2, 0, 0xFF, 0 end
local function attack(base) ram[base + 0x05], ram[base + 0x06], ram[base + 0x105] = 0, 0x0A, 1 end
-- One frame: the Tick moves by step (2 at turbo 3 on some frames).
local function frame(step)
	ram[TICK] = ((ram[TICK] or 0) + (step or 1)) % 256
	frame_no = frame_no + 1
	A._gh_update(ME, FOE)
end
local function idle_for(ticks) stand(ME) ; stand(FOE) ; for _ = 1, ticks do frame(1) end end

-- ---------------------------------------------------------------------------
print("[1] After Hit Guard / First Guard Only: 数えるのは接触 (ガードを含む。3rd の received_connection)")
do
	globals.options.guard = 8
	idle_for(20)
	eq("After Hit Guard: まだ接触していない - ガードしない", A._gh_allow(), false)
	attack(FOE) ; hurt(ME) ; frame()
	eq("  当たった後 - ガードする", A._gh_allow(), true)
	stand(ME) ; frame()                     -- the dummy recovers, the attacker still moves
	eq("  相手が動いている間は続く", A._gh_allow(), true)
	-- First Guard Only: the first attack is guarded, and that guard is the connection.
	globals.options.guard = 9
	idle_for(12)
	eq("First Guard Only: 数え直した後 - ガードする", A._gh_allow(), true)
	attack(FOE) ; guard(ME) ; frame()
	eq("  1 発目をガードしたら、その後はガードしない (ずっとガードしない)", A._gh_allow(), false)
	stand(ME) ; frame()
	eq("  相手が動いている間はガードしないまま", A._gh_allow(), false)
	idle_for(12)
	eq("  12 Tick 何もしなければ、また 1 発目をガードする", A._gh_allow(), true)
end

-- ---------------------------------------------------------------------------
print("[2] ダミーが動けるようになってから 12 Tick で数え直す (相手が攻撃中なら待つ)")
do
	globals.options.guard = 8
	hurt(ME) ; attack(FOE) ; frame()
	eq("当たった", A._gh_allow(), true)
	stand(ME) ; stand(FOE)
	for _ = 1, 11 do frame(1) end
	eq("動けるようになって 11 Tick ではまだ", A._gh_allow(), true)
	frame(1)
	eq("12 Tick で数え直す", A._gh_allow(), false)
	-- The attacker walks up: counted (user, 2026-10-24).
	hurt(ME) ; frame()
	stand(ME) ; walk(FOE)
	for _ = 1, 12 do frame(1) end
	eq("相手が歩いて近寄っても 12 Tick で数え直す", A._gh_allow(), false)
	-- The attacker in an attack at the 12th Tick: still the same string.
	hurt(ME) ; frame()
	stand(ME) ; attack(FOE)
	for _ = 1, 15 do frame(1) end
	eq("相手が攻撃中のあいだは数え直さない (15 Tick でも)", A._gh_allow(), true)
	stand(FOE) ; frame(1)
	eq("  攻撃が終われば (もう 12 Tick を過ぎているので) 数え直す", A._gh_allow(), false)
	-- Hit or guarded again inside the 12: the count starts from that stun's end.
	hurt(ME) ; frame()
	stand(ME) ; stand(FOE)
	for _ = 1, 8 do frame(1) end
	guard(ME) ; frame(1)
	stand(ME)
	for _ = 1, 11 do frame(1) end
	eq("途中でまた接触したら、その硬直明けから数え直す (8 + 11 ではまだ)", A._gh_allow(), true)
	frame(1)
	eq("  12 Tick で数え直す", A._gh_allow(), false)
	-- The dummy's own attack (a reversal) holds the count too.
	hurt(ME) ; frame()
	attack(ME) ; stand(FOE)
	for _ = 1, 15 do frame(1) end
	eq("ダミー自身が攻撃中は数えない", A._gh_allow(), true)
	-- Two Ticks a frame (turbo), and the counter wrapping at 256.
	hurt(ME)
	ram[TICK] = 250
	A._gh_update(ME, FOE)                   -- hit, on Tick 250
	stand(ME) ; stand(FOE)
	for _ = 1, 5 do frame(2) end            -- 250 -> 4: 10 Ticks
	eq("2 Tick ずつ、256 で一周しても数える (10 Tick)", A._gh_allow(), true)
	frame(2)
	eq("  12 Tick で数え直す", A._gh_allow(), false)
end

-- ---------------------------------------------------------------------------
print("[3] ほかの Guard のときは Random Guard % のロールが決める")
do
	for _, v in ipairs({ 2, 3, 4, 5, 6, 7 }) do
		globals.options.guard = v
		eq("Guard " .. v .. ": nil", A._gh_allow(), nil)
	end
	globals.options.guard = 8
end

-- ---------------------------------------------------------------------------
print("[4] Show Blocking Direction: P1 も P2 も、ガードしたときのレバー")
do
	-- What timers.lua touches while it loads (as analysis/test_mash_meter.lua).
	package.loaded["./scripts/debugKnockdown"] = { mark_write = function() end }
	memory.registerexec = function() end
	memory.readbytesigned = memory.readbytesigned or memory.readbyte
	memory.readwordsigned = memory.readwordsigned or memory.readword
	memory.readdword = memory.readdword or memory.readword
	memory.getregister = function() return 0 end
	gui = { text = function() end, rect = function() end, box = function() end, gdoverlay = function() end }
	local _img = { gdStr = function() return "" end }
	gd = { createFromPng = function() return _img end, createFromPngStr = function() return _img end }
	emu.screenwidth = function() return 384 end
	emu.screenheight = function() return 224 end
	local T = dofile("timers.lua")
	local P1, P2 = 0xFF8400, 0xFF8800
	local function free(b) ram[b + 0x05], ram[b + 0x54] = 0, 0 end
	local function guard_lands(b, keys, g158)
		globals._input = keys
		ram[b + 0x05], ram[b + 0x54], ram[b + 0x158] = 2, 0xFF, g158 or 14
		T._block_dir_update(b)
	end
	local function dirs(b) local out = {} for _, e in ipairs(T._block_dirs(b)) do out[#out + 1] = e.dir end return table.concat(out, ",") end
	T._block_dir_reset()
	free(P2) ; T._block_dir_update(P2)
	guard_lands(P2, { ["P2 Right"] = true })
	eq("P2 が右でガード: 6", dirs(P2), "6")
	free(P2) ; T._block_dir_update(P2)
	guard_lands(P2, { ["P2 Right"] = true })
	eq("  同じ方向は足さない", dirs(P2), "6")
	free(P2) ; T._block_dir_update(P2)
	guard_lands(P2, { ["P2 Right"] = true, ["P2 Down"] = true })
	eq("  違う方向は足す (右下 3)", dirs(P2), "6,3")
	ram[P2 + 0x158] = 9 ; T._block_dir_update(P2)
	eq("  硬直の途中 ($158 が減るだけ) では足さない", dirs(P2), "6,3")
	guard_lands(P2, { ["P2 Right"] = true }, 14)
	eq("  連続ガードの次の 1 発 ($158 が戻る) は足す", dirs(P2), "6,3,6")
	-- A hit is not a guard.
	free(P2) ; T._block_dir_update(P2)
	globals._input = { ["P2 Left"] = true }
	ram[P2 + 0x05], ram[P2 + 0x54] = 2, 0 ; T._block_dir_update(P2)
	eq("  食らったときは足さない", dirs(P2), "6,3,6")
	free(P2) ; T._block_dir_update(P2)
	guard_lands(P2, {})
	eq("  何も入れていない (Auto Guard) は足さない", dirs(P2), "6,3,6")
	-- P1 too: the player's own guard.
	free(P1) ; T._block_dir_update(P1)
	guard_lands(P1, { ["P1 Left"] = true, ["P1 Down"] = true, ["P2 Right"] = true })
	eq("P1 のガード: P1 のキーを読む (左下 1)", dirs(P1), "1")
	-- 120 frames, then gone (on the draw).
	local tm = slurp("timers.lua")
	eq("出す時間は 120 フレーム (3rd は 90)", tm:find("local BLOCK_DIR_SHOW = 120", 1, true) ~= nil
	   and tm:find("if age < 0 or age > BLOCK_DIR_SHOW then table.remove(b.dirs, i) else i = i + 1 end", 1, true) ~= nil, true)
	eq("設定が on のとき両者の頭上に矢印", tm:find("if globals.options.show_blocking_direction then%s+draw_block_dir%( 0xFF8400, p1_coords%)%s+draw_block_dir%( 0xFF8800, p2_coords%)") ~= nil
	   and tm:find("gui.image(coords.base.x - 5, coords.base.y - 100 - (#b.dirs - k) * 10, img_dir[e.dir])", 1, true) ~= nil, true)
	T._block_dir_reset()
	globals._input = nil
	for _, b in ipairs({ P1, P2 }) do for _, o in ipairs({ 0x05, 0x54, 0x158 }) do ram[b + o] = nil end end
end

-- ---------------------------------------------------------------------------
print("[5] 組み込み")
do
	local menu = slurp("menu.lua")
	local list = menu:match("\nguard = {(.-)\n}")
	eq("Guard の値の末尾に After Hit Guard / First Guard Only (8 / 9)", list ~= nil
	   and list:find('"Push Block (All Heavy)",', 1, true) < list:find('"After Hit Guard",', 1, true)
	   and list:find('"After Hit Guard",', 1, true) < list:find('"First Guard Only"', 1, true), true)
	eq("  ヘルプは値ごと、2 つとも 12 Tick", menu:find('"After Hit Guard takes the first hit, then guards as All Guard does', 1, true) ~= nil
	   and menu:find('"First Guard Only guards the first attack as All Guard does', 1, true) ~= nil
	   and select(2, menu:gsub("It starts over 12 Ticks after the dummy can act", "")) == 2, true)
	local rg = menu:match("\np2_block_chance = {(.-)\n}")
	eq("Random Guard % は 5 つの確率に戻した", rg ~= nil and rg:find("First", 1, true) == nil and rg:find('"100%",', 1, true) ~= nil, true)
	eq("  After Hit Guard / First Guard Only のときは隠す", menu:find("or training_settings.guard >= 8\nend", 1, true) ~= nil, true)
	eq("hud: All Guard の扱いに 8 / 9 も入れる", slurp("hud.lua"):find("globals.options.guard ~= 4 and globals.options.guard < 8 then return end", 1, true) ~= nil, true)
	eq("Display に Show Blocking Direction (既定 no)",
	   menu:find('checkbox_menu_item("Show Blocking Direction", training_settings, "show_blocking_direction", false,', 1, true) ~= nil, true)
	eq("  Show Cross Up の行は無い", menu:find('"Show Cross Up"', 1, true), nil)
	eq("config の既定 show_blocking_direction = false", slurp("config.lua"):find("\n  show_blocking_direction = false,\n", 1, true) ~= nil, true)
	local tm = slurp("timers.lua")
	eq("timers: 毎フレーム両者のガードを見る (設定が on のとき)", tm:find("if globals ~= nil and globals.options ~= nil and globals.options.show_blocking_direction then%s+block_dir_update%(0xFF8400%)%s+block_dir_update%(0xFF8800%)") ~= nil, true)
	local ag = slurp("autoguard.lua")
	eq("autoguard: ガード方向の矢印は無い", ag:find("note_block_direction", 1, true), nil)
	eq("  状態を読み込んだときの関数は v11.7.31 のまま (1 行)", ag:find('["after_load"] = function() p1_guard_saved = nil end,', 1, true) ~= nil, true)
	eq("  12 Tick", ag:find("local GUARD_HITS_IDLE = 12", 1, true) ~= nil, true)
	eq("公開物にハンドル名を書かない", (ag .. tm .. menu):find("effie", 1, true), nil)
end

print(fails == 0 and "\n全て通った" or ("\n" .. fails .. " 件 NG"))
os.exit(fails == 0 and 0 or 1)
