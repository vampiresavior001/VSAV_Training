-- MORE THAN ONE COLUMN PER DISPLAYED FRAME.
--
-- update_input_history() only appends when _last_entry.frame ~= frame_number,
-- and frame_number was emu.framecount(). That is a hard ceiling of ONE column
-- per displayed frame however many inputs the player made, and at turbo 3 a
-- frame covers 4/3 of a game tick - so the press or release that completes a
-- command had nowhere to go.
--
-- Measured over 19 guard cancels: the frame sampler drew the qualifying edge 3
-- times and lost it 16, with 10 of those putting SUCCESS against no input
-- column at all. The cancels themselves were fine every time; only the drawing
-- lost them (analysis/gc_success_probe_20260915b.log).
--
-- frame_number is now the tick sequence guardCancel.lua keeps, and
-- registerBefore drains the queue of ticks this frame did not sample. This
-- pins both halves: the ticks arrive as separate columns, and a held input
-- still collapses into one.
--
-- Run from scripts/ - inputHistory.lua loads its images by relative path.
--   cd scripts && lua5.1 ../analysis/test_input_tick_columns.lua

gd = { createFromPng = function() return { gdStr = function() return "" end } end }
package.preload["gd"] = function() return gd end

local ram = {}
memory = {
	readbyte = function(a) return ram[a] or 0 end,
	readword = function(a) return ram[a] or 0 end,
	readdword = function(a) return ram[a] or 0 end,
	writebyte = function(a, v) ram[a] = v end,
}
gui = { text = function() end, box = function() end, image = function() end }
local frame = 1000
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

local function columns() return #input_history[1] end

-- One displayed frame's worth of emulation: the tick hook would have run
-- several times, queuing only the ticks on which the pair changed.
local function a_frame(ticks)
	frame = frame + 1
	local q = {}
	for _, t in ipairs(ticks) do
		globals.p1_tick_seq = (globals.p1_tick_seq or 0) + 1
		q[#q + 1] = { dir = t.dir, btn = t.btn, seq = globals.p1_tick_seq }
	end
	-- Ticks on which nothing changed still advance the clock.
	globals.p1_tick_seq = (globals.p1_tick_seq or 0) + 1
	globals.p1_tick_inputs = q
	-- What the frame itself reads at the end.
	local last = ticks[#ticks]
	if last then
		ram[0xFF8400 + 0x122] = last.btn
		ram[0xFF8400 + 0x125] = last.dir
	end
	inp.registerBefore({})
end

print("-- 1 表示フレームに 3 ティック分の入力")
-- 6 -> 2 -> 3 held, then the button: a DPF inside one displayed frame, which
-- is what a fast input looks like at turbo 3.
local before = columns()
a_frame({ { dir = 0x01, btn = 0x00 },   -- forward
          { dir = 0x04, btn = 0x00 },   -- down
          { dir = 0x05, btn = 0x00 } }) -- down-forward
local after = columns()
want("3 ティック分の列が増えた", after - before >= 3, true)
want("キューは空になった", #globals.p1_tick_inputs, 0)

print("-- 押しっぱなしは 1 列のまま")
local held = columns()
a_frame({})            -- nothing changed this frame
a_frame({})
a_frame({})
want("変化が無ければ列は増えない", columns(), held)

print("-- ボタンが 1 ティックだけ入っても列になる")
local b0 = columns()
a_frame({ { dir = 0x05, btn = 0x04 } })   -- HP down for one tick
a_frame({ { dir = 0x05, btn = 0x00 } })   -- and released
want("押しの列と離しの列が増えた", columns() - b0 >= 2, true)

print("-- ティックの通し番号が列に乗る")
local last_two = { input_history[1][#input_history[1] - 1], input_history[1][#input_history[1]] }
want("直前の列と番号が違う", last_two[1].frame ~= last_two[2].frame, true)
want("番号は増える向き", last_two[2].frame > last_two[1].frame, true)

print("-- 排出した列と最後の読みが同じ時計を使う")
-- The drained columns are stamped with the tick they were captured on. If the
-- reading the frame itself takes falls back to emu.framecount() while they do
-- not, the two are in different units and every duration between them is
-- nonsense. framecount is in the thousands here and the tick sequence is not,
-- so the mix shows up as a huge jump.
local newest = input_history[1][#input_history[1]]
want("最後の列もティックの番号", newest.frame < 1000, true)
want("表示フレーム番号ではない", newest.frame ~= emu.framecount(), true)

print("-- SUCCESS が成立したティックの列に載る")
-- The point of the whole change. The queue carries the window state as of each
-- tick, so the label belongs to the tick the cancel came out on - not to the
-- first tick of the displayed frame that noticed, which is where it landed
-- while the state was worked out once per frame.
globals.p1_tick_inputs = nil
local base = columns()
frame = frame + 1
local q = {}
local function tick(dir, btn, gc)
	globals.p1_tick_seq = globals.p1_tick_seq + 1
	q[#q + 1] = { dir = dir, btn = btn, seq = globals.p1_tick_seq, gc = gc }
end
tick(0x01, 0x00, "p1_gc_in_progress")   -- forward, still blocking
tick(0x04, 0x00, "p1_gc_in_progress")   -- down
tick(0x05, 0x04, "p1_gc_success")       -- down-forward + HP: the cancel
tick(0x05, 0x04, "p1_gc_none")          -- and the window is gone
globals.p1_tick_inputs = q
inp.registerBefore({})

local marked = {}
for i = base + 1, #input_history[1] do
	local e = input_history[1][i]
	if e.gc_event == "p1_gc_success" then marked[#marked + 1] = e end
end
want("SUCCESS の列が 1 本だけある", #marked, 1)
want("その列はボタンを持っている", marked[1] and marked[1].buttons[3] or false, true)
want("その列は下前", marked[1] and marked[1].direction or 0, 3)

print("-- 供給側 (guardCancel の tick フック) の作り")
-- The tests above hand the queue over ready-made, so nothing in them reaches
-- the hook that fills it. guardCancel.lua carries a copy of handle_gc_event()'s
-- decision, and a copy is only safe while it stays a copy - checked against 35
-- logged attempts where the two agreed on every one. These pin the parts that
-- would silently drift apart.
do
	local gc = io.open("guardCancel.lua"):read("*a")
	local function has(what, needle)
		want(what, gc:find(needle, 1, true) ~= nil, true)
	end
	has("ブロッククロックを読む", "memory.readbyte(0xFF8558)")
	has("$06 を読む", "memory.readbyte(0xFF8406)")
	has("必殺技 0x0E", "_act == 0x0E")
	has("ES 0x10", "_act == 0x10")
	has("EX 0x12", "_act == 0x12")
	has("成立を success と呼ぶ", 'p1_gc_success')
	has("GC が変わったティックも積む", "_v ~= p1_tick_input_last or _gc_changed")
	has("列に gc を添える", "gc = _gc")
	-- The three values the drawing switches on, so a rename on one side shows up.
	local ih = io.open("inputHistory.lua"):read("*a")
	for _, v in ipairs({ "p1_gc_begin", "p1_gc_in_progress", "p1_gc_success" }) do
		want("両方が " .. v .. " を知っている",
			gc:find(v, 1, true) ~= nil and ih:find(v, 1, true) ~= nil, true)
	end
end

print("-- フックが無くても落ちない (オフラインとロード順)")
globals.p1_tick_seq = nil
globals.p1_tick_inputs = nil
local ok = pcall(function() frame = frame + 1 inp.registerBefore({}) end)
want("p1_tick_seq が nil でも走る", ok, true)

if fails == 0 then
	print("test_input_tick_columns ok")
else
	print(fails .. " 件 NG")
	os.exit(1)
end
