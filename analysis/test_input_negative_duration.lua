-- NO NEGATIVE COUNT UNDER A COLUMN OF THE SCROLLING INPUT BAR.
--
-- The bar showed -25593 under its oldest IDLE column (user's screenshots,
-- 2026-10-07). The count under a column is the next column's stamp minus its
-- own, and the stamps came from two clocks: until guardCancel.lua's tick hook
-- has run once, globals.p1_tick_seq is nil and registerBefore stamps with
-- emu.framecount() - large once a savestate is loaded - and from then on with
-- the tick sequence, which starts from 1. The column stamped before the switch
-- then reads "first tick stamp - framecount".
--
-- The fix starts the history over when the clock changes (the two cannot be
-- compared), and the bar draws "-" rather than a negative count whatever the
-- stamps are.
--
-- Run from scripts/ - inputHistory.lua loads its images by relative path.
--   cd scripts && lua5.1 ../analysis/test_input_negative_duration.lua

gd = { createFromPng = function() return { gdStr = function() return "" end } end }
package.preload["gd"] = function() return gd end

local ram = {}
memory = {
	readbyte = function(a) return ram[a] or 0 end,
	readword = function(a) return ram[a] or 0 end,
	readdword = function(a) return ram[a] or 0 end,
	writebyte = function(a, v) ram[a] = v end,
}
local texts = {}
gui = { text = function(x, y, t) texts[#texts + 1] = tostring(t) end,
        box = function() end, image = function() end }
local frame = 25600
emu = { framecount = function() return frame end, screenwidth = function() return 384 end,
        screenheight = function() return 224 end }
joypad = { get = function() return {} end, set = function() end }
globals = {
	options = { show_button_releases = true, show_gc_trainer = false,
	            inp_history_scroll = 0 },
	gc_event = "p1_gc_none",
	pb_event = "p1_pb_none",
	show_menu = false,
}
Rx = dofile("rx-lua/rx.lua")

local inp = dofile("inputHistory.lua")

local fails = 0
local function want(what, got, w)
	if got ~= w then
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(w) .. "]")
	else
		print("  ok " .. what)
	end
end

local function hold(dir, btn)
	ram[0xFF8400 + 0x122] = btn
	ram[0xFF8400 + 0x125] = dir
end

-- One displayed frame. With ticks == nil the tick hook has not run yet
-- (p1_tick_seq stays nil); otherwise it ran once per tick, queuing the ticks
-- on which the pair changed, as in test_input_tick_columns.lua.
local function a_frame(ticks)
	frame = frame + 1
	if ticks ~= nil then
		local q = {}
		for _, t in ipairs(ticks) do
			globals.p1_tick_seq = (globals.p1_tick_seq or 0) + 1
			if t.dir ~= nil then
				q[#q + 1] = { dir = t.dir, btn = t.btn, seq = globals.p1_tick_seq }
				hold(t.dir, t.btn)
			end
		end
		globals.p1_tick_inputs = q
	end
	inp.registerBefore({})
end

-- The counts the bar draws under its columns, from the real draw path.
local function drawn_counts()
	texts = {}
	inp.guiRegister({})
	local out = {}
	for _, t in ipairs(texts) do
		if t:match("^%-?%d+$") or t == "-" then out[#out + 1] = t end
	end
	return out
end
local function negatives(counts)
	local n = {}
	for _, t in ipairs(counts) do
		if t:match("^%-%d+$") then n[#n + 1] = t end
	end
	return table.concat(n, ",")
end
local function largest_stamp()
	local m = 0
	for _, e in ipairs(input_history[1]) do
		if e.frame ~= nil and e.frame > m then m = e.frame end
	end
	return m
end

-- ---------------------------------------------------------------------------
print("-- 起動直後: フックが走る前の列 (framecount) と、走った後の列 (Tick)")
hold(0, 0)
a_frame(nil)                     -- before the hook: stamped with emu.framecount()
want("フック前に IDLE の列ができる", #input_history[1] >= 1, true)
local before = largest_stamp()
want("その列は framecount で刻まれる", before, 25601)
-- The hook starts counting: ticks 1-6 neutral, a forward press on tick 7.
a_frame({ {}, {}, {} })
a_frame({ {}, {}, {} })
a_frame({ { dir = 6, btn = 0 }, {} })
local counts = drawn_counts()
want("負の数を描かない", negatives(counts), "")
want("framecount で刻んだ列は残らない", largest_stamp() <= globals.p1_tick_seq, true)
want("Tick で刻んだ列は残る (前の押し)", #input_history[1] >= 1, true)

-- ---------------------------------------------------------------------------
print("-- Tick の時計が続く間は消さない")
local n = #input_history[1]
a_frame({ { dir = 0, btn = 0 }, {}, {} })
a_frame({ { dir = 2, btn = 0 }, {} })
want("列が積み増される", #input_history[1] > n, true)
want("やはり負の数を描かない", negatives(drawn_counts()), "")

-- ---------------------------------------------------------------------------
print("-- フックが無い (オフラインとロード順) なら framecount のまま積む")
inp.clear()
globals.p1_tick_seq = nil
globals.p1_tick_inputs = nil
hold(0, 0) ; a_frame(nil)        -- the switch back to framecount starts over
hold(6, 0) ; a_frame(nil)
hold(0, 0) ; a_frame(nil)
local m = #input_history[1]
want("framecount の列が積まれる", m >= 2, true)
hold(4, 0) ; a_frame(nil)
want("時計が変わらなければ消さない", #input_history[1] > m, true)
want("framecount だけなら負の数は無い", negatives(drawn_counts()), "")

-- ---------------------------------------------------------------------------
print("-- 刻みが逆順の列が残っていても、表示は「-」")
-- Whatever made it, a later column stamped before an earlier one says nothing
-- about how long an input was held.
local h = input_history[1]
want("前提: 列が 2 本以上", #h >= 2, true)
h[1].frame = h[2].frame + 25593
local c = drawn_counts()
want("負の数を描かない", negatives(c), "")
-- Drawn newest first, so the oldest column's count comes last.
want("数は列の数だけ", #c, #h)
want("いちばん古い列は「-」", c[#c], "-")
local dashes = 0
for _, t in ipairs(c) do if t == "-" then dashes = dashes + 1 end end
want("「-」はその 1 本だけ", dashes, 1)

if fails == 0 then
	print("test_input_negative_duration ok")
else
	print(fails .. " 件 NG")
	os.exit(1)
end
