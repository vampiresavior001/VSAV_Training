-- GALLON'S BEAST CANNON TURNS AFTER A GUARD CANCEL (scripts/guardCancel.lua
-- GA.bc_turn_tick, scripts/menu.lua bc_turn_items), 2026-11-08.
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_gallon_bc_turn.lua
--
-- The game, as the turns done by hand showed it (invuln_log): a fresh P press
-- while the cannon flies ($07 = 0x04) on a Tick $23 is 0 stops Gallon ($07 =
-- 0x08, 18 Ticks), and the lever when the stop ends picks the next cannon. The
-- stand-in below does the same with a short stop.
--
--   [1] turn 1: its delay after the cannon came out, LP + direction for one
--       Tick on a Tick the game takes it, pressed afresh until it stops, then
--       the direction alone through the stop; forward / back by $0B
--   [2] one turn for Punch, four for Three Punch (ES); each later delay counts
--       from the Tick the turn before came out; None ends the list
--   [3] only while the cannon is out ($06 0x0E / 0x10, $106 a Beast Cannon),
--       only for Gallon, only with Guard Cancel; a turn the game does not take
--       is tried until the cannon ends, and no longer
--   [4] the hook-up: the Tick hook calls it after GA.ag_reaim
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

local src = slurp("guardCancel.lua")
local f0 = assert(src:find("GA.BC_IDS = {", 1, true))
local f1 = assert(src:find("function GA.bc_turn_tick()", f0, true))
local e0 = assert(src:find("\nend\n", f1, true))
local ram, wrote = {}, nil
memory = { readbyte = function(a) return ram[a] or 0 end }
debugKnockdownModule = { mark_write = function() end }
GA = {}
local function assert_input_bits(lev, btn) wrote = { lev = lev, btn = btn } end
assert(loadstring("local GA, assert_input_bits = ...\n" .. src:sub(f0, e0 + 4)))(GA, assert_input_bits)

local ST, PH, ID, CH, LG, FACE, F23 = 0xFF8806, 0xFF8807, 0xFF8906, 0xFF8B82, 0xFF8081, 0xFF880B, 0xFF8823
local function opts(t)
	local o = { guard_action = 2, gc_button = 2,
		bc_turn1 = 1, bc_turn2 = 1, bc_turn3 = 1, bc_turn4 = 1,
		bc_turn1_delay = 10, bc_turn2_delay = 10, bc_turn3_delay = 10, bc_turn4_delay = 10 }
	for k, v in pairs(t or {}) do o[k] = v end
	globals = { options = o }
end

-- n Ticks of a cannon from lg = from. The stand-in game: a fresh LP press while
-- flying, on a Tick $23 is 0, stops it for STOP Ticks; when the stop ends $106
-- becomes the turned cannon.
-- each(i) may override ram before the Tick. Returns the writes as a string:
-- "i:LL" for a press (LP + lever LL), "i:-LL" for a lever alone.
local STOP = 3
local function run(from, n, each, opt)
	opt = opt or {}
	GA.bc = nil
	ram[CH] = opt.char or 0x02
	ram[ST] = opt.st or 0x0E
	ram[ID] = opt.id or 0x0A
	ram[PH] = 0x04
	ram[F23] = 0
	local stop_left, out, held = 0, {}, false
	for i = 0, n do
		ram[LG] = (from + i) % 256
		if each then each(i) end
		wrote = nil
		GA.bc_turn_tick()
		if wrote then
			out[#out + 1] = i .. ":" .. (wrote.btn == 0x01 and "" or "-") .. string.format("%02X", wrote.lev)
		end
		-- the game's answer, seen from the next Tick
		if not opt.deaf then
			if ram[PH] == 0x08 then
				stop_left = stop_left - 1
				if stop_left == 0 then ram[PH] = 0x04 ; ram[ID] = 0x10 end
			elseif wrote and wrote.btn == 0x01 and not held and ram[PH] == 0x04 and ram[F23] == 0 then
				ram[PH], stop_left = 0x08, STOP
			end
		end
		held = (wrote ~= nil and wrote.btn == 0x01)
	end
	return table.concat(out, " ")
end

print("[1] 1 回目: Delay 後に LP + 方向を 1 Tick、止まったら方向だけ")
do
	ram[FACE] = 0
	opts({ bc_turn1 = 2, bc_turn1_delay = 3 })
	eq("Up, Delay 3: 3 で押し、4-6 は止まっている間の上", run(10, 9), "3:08 4:-08 5:-08 6:-08")
	opts({ bc_turn1 = 2, bc_turn1_delay = 3 })
	eq("止まるまで押し直す (放す Tick を挟む)", run(10, 6, nil, { deaf = true }), "3:08 4:-08 5:08 6:-08")
	opts({ bc_turn1 = 2, bc_turn1_delay = 3 })
	eq("$23 が 1 の間は方向だけ、0 になった Tick に押す",
		run(10, 9, function(i) ram[F23] = (i <= 5) and 1 or 0 end), "3:-08 4:-08 5:-08 6:08 7:-08 8:-08 9:-08")
	opts({ bc_turn1 = 2, bc_turn1_delay = 3 })
	eq("飛んでいない ($07 = 0x06) 間は方向だけ",
		run(10, 6, function(i) if i <= 4 then ram[PH] = 0x06 elseif i == 5 then ram[PH] = 0x04 end end),
		"3:-08 4:-08 5:08 6:-08")
	local dirs = { [3] = "0A", [4] = "02", [5] = "06", [6] = "04", [7] = "05", [8] = "01", [9] = "09" }
	for d = 3, 9 do
		opts({ bc_turn1 = d, bc_turn1_delay = 1 })
		eq("  $0B = 0 で方向 " .. d, (run(10, 1)), "1:" .. dirs[d])
	end
	ram[FACE] = 1
	opts({ bc_turn1 = 4, bc_turn1_delay = 1 })
	eq("$0B = 1 の前は bit0", run(10, 1), "1:01")
	opts({ bc_turn1 = 8, bc_turn1_delay = 1 })
	eq("$0B = 1 の後ろは bit1", run(10, 1), "1:02")
	ram[FACE] = 0
end

print("[2] 回数と、2 回目以降の Delay")
do
	local four = { bc_turn1 = 2, bc_turn2 = 6, bc_turn3 = 4, bc_turn4 = 8,
		bc_turn1_delay = 2, bc_turn2_delay = 1, bc_turn3_delay = 2, bc_turn4_delay = 1 }
	opts(four)
	eq("Punch: 1 回だけ", run(10, 20), "2:08 3:-08 4:-08 5:-08")
	four.gc_button = 4
	opts(four)
	-- turn 1 pressed 2, stop 3-5, out on 6; turn 2 at 6+1 = 7, stop 8-10, out 11;
	-- turn 3 at 11+2 = 13, stop 14-16, out 17; turn 4 at 18, stop 19-21.
	eq("Three Punch (ES): 4 回、前の回が出た Tick から数える", run(10, 24, nil, { st = 0x10 }),
		"2:08 3:-08 4:-08 5:-08 7:04 8:-04 9:-04 10:-04 13:02 14:-02 15:-02 16:-02 18:01 19:-01 20:-01 21:-01")
	four.bc_turn3 = 1
	opts(four)
	eq("3 回目が None: そこで終わる", run(10, 24, nil, { st = 0x10 }),
		"2:08 3:-08 4:-08 5:-08 7:04 8:-04 9:-04 10:-04")
	opts({ gc_button = 4 })
	eq("1 回目が None: 何もしない", run(10, 20), "")
	opts({ gc_button = 3, bc_turn1 = 2, bc_turn1_delay = 1 })
	eq("Kick: 何もしない", run(10, 5), "")
end

print("[3] キャノン中だけ (ブロック)")
do
	opts({ bc_turn1 = 2, bc_turn1_delay = 3 })
	eq("押す Tick に必殺技でない ($06 = 0): 入れない",
		run(10, 5, function(i) ram[ST] = (i == 3) and 0x00 or 0x0E end, { deaf = true }), "")
	opts({ bc_turn1 = 2, bc_turn1_delay = 3 })
	eq("押す Tick の技 id がビーストキャノンでない: 入れない",
		run(10, 3, function(i) ram[ID] = (i == 3) and 0x02 or 0x0A end), "")
	opts({ bc_turn1 = 2, bc_turn1_delay = 1 })
	eq("ほかの必殺技 (Million Flicker 0x02): 始まらない", run(10, 5, nil, { id = 0x02 }), "")
	opts({ bc_turn1 = 2, bc_turn1_delay = 1 })
	eq("通常技 ($06 = 0x0A): 始まらない", run(10, 5, nil, { st = 0x0A }), "")
	opts({ bc_turn1 = 2, bc_turn1_delay = 1 })
	eq("ガロン以外: 入れない", run(10, 5, nil, { char = 0x05 }), "")
	opts({ bc_turn1 = 2, bc_turn1_delay = 1 })
	eq("ダークガロン: 入れる", run(10, 1, nil, { char = 0x12 }), "1:08")
	opts({ guard_action = 6, bc_turn1 = 2, bc_turn1_delay = 1 })
	eq("Guard Cancel 以外: 入れない", run(10, 5), "")
	opts({ bc_turn1 = 2, bc_turn1_delay = 2 })
	eq("取られない回は、キャノンが終わったらやめる",
		run(10, 6, function(i) ram[ST] = (i >= 4) and 0x00 or 0x0E end, { deaf = true }), "2:08 3:-08")
	opts({ bc_turn1 = 2, bc_turn1_delay = 2 })
	eq("終わって次のキャノン: 数え直す",
		run(10, 8, function(i) ram[ST] = (i == 4) and 0x00 or 0x0E end, { deaf = true }), "2:08 3:-08 7:08 8:-08")
	opts({ bc_turn1 = 2, bc_turn1_delay = 3 })
	eq("lg が 255 から 0 へ回っても", run(254, 3), "3:08")
end

print("[4] 組み込み")
do
	local hook = src:match("memory%.registerexec%(0x02211A, function%(%)(.-)\nend%)") or ""
	local a = hook:find("GA.ag_reaim()", 1, true)
	local b = hook:find("GA.bc_turn_tick()", 1, true)
	eq("Tick のフックで GA.ag_reaim の後に呼ぶ", a ~= nil and b ~= nil and a < b, true)
	eq("assert_input_bits はそれより前に定義されている",
		src:find("local function assert_input_bits(", 1, true) < f0, true)
	local menu = slurp("menu.lua")
	eq("menu: bc_turn の行", menu:find('"bc_turn" .. _n', 1, true) ~= nil, true)
	local cfg = slurp("config.lua")
	eq("config: 既定は None と 10", cfg:find("bc_turn1 = 1, bc_turn2 = 1, bc_turn3 = 1, bc_turn4 = 1,", 1, true) ~= nil
		and cfg:find("bc_turn1_delay = 10,", 1, true) ~= nil, true)
end

print(fails == 0 and "\n全て通った" or ("\n" .. fails .. " 件 NG"))
os.exit(fails == 0 and 0 or 1)
