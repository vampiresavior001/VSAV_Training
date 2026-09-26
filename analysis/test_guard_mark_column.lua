-- THE GUARD TICK GETS A COLUMN OF ITS OWN IN THE BAR ALONG THE BOTTOM.
--
-- The GC label sits on the tick the window opened, one tick after the block
-- was decided, and the block's own tick was often the last tick of a longer
-- column (IDLE 6). Reading the label's column as the guard tick was the
-- natural mistake (user, 2026-09-26). guardCancel.lua hands the contact tick
-- over with the window's column, and mark_guard_column splits it off one tick
-- back and marks it: G, or GP and the persistence tick.
--
-- Run from scripts/ - inputHistory.lua loads its images by relative path.
--   cd scripts && lua5.1 ../analysis/test_guard_mark_column.lua

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
gui = {
	text = function(x, y, s, c) texts[#texts + 1] = { x = x, y = y, s = s, c = c } end,
	box = function() end, image = function() end,
}
local frame = 1000
emu = { framecount = function() return frame end, screenwidth = function() return 384 end,
        screenheight = function() return 224 end }
joypad = { get = function() return {} end, set = function() end }
globals = {
	options = { show_button_releases = true, show_gc_trainer = true,
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

-- One displayed frame. ticks: { dir, btn, gc, mark }, one per tick; only the
-- ticks the hook would have queued (input or window changed) are given.
local seq = 100
local function a_frame(ticks)
	frame = frame + 1
	local q = {}
	for _, t in ipairs(ticks) do
		seq = t.seq or (seq + 1)
		q[#q + 1] = { dir = t.dir, btn = t.btn or 0, seq = seq, gc = t.gc, mark = t.mark }
	end
	globals.p1_tick_seq = seq
	globals.p1_tick_inputs = q
	local last = ticks[#ticks]
	ram[0xFF8400 + 0x122] = last.btn or 0
	ram[0xFF8400 + 0x125] = last.dir
	inp.registerBefore({})
end

local function hist() return input_history[1] end
local function find_frame(f)
	for i, e in ipairs(hist()) do if e.frame == f then return e, i end end
end

print("-- IDLE の途中で当たった: 当たったティックで列が分かれる")
-- 1 枚目 (2026-09-25): ← 6 / IDLE 6 (最後のティックで当たった) / → (受付が開く)
a_frame({ { dir = 0x02, seq = 200 } })                    -- ← (後ろ)
a_frame({ { dir = 0x00, seq = 206, gc = "p1_gc_none" } }) -- 離した
local before = #hist()
a_frame({ { dir = 0x01, seq = 212, gc = "p1_gc_begin", mark = { seq = 211, pers = 6 } } })
local split = find_frame(211)
want("当たったティックの列ができた", split ~= nil, true)
want("その列は印を持つ", split and split.gc_guard and split.gc_guard.pers, 6)
want("その列は IDLE のまま", split and split.direction, 5)
want("受付の列は別", find_frame(212) and find_frame(212).gc_event, "p1_gc_begin")
want("列は 2 本増えた (分けた列と受付の列)", #hist() - before >= 2, true)
local idle = find_frame(206)
want("元の IDLE は印を持たない", idle and idle.gc_guard, nil)

print("-- 当たったティックがもともと列の始まりなら、分けずに印だけ")
a_frame({ { dir = 0x00, seq = 300, gc = "p1_gc_none" } })
before = #hist()
a_frame({ { dir = 0x00, seq = 301, gc = "p1_gc_begin", mark = { seq = 300 } } })
local own = find_frame(300)
want("印が付いた", own and own.gc_guard ~= nil, true)
want("入れたままなら持続なし", own and own.gc_guard and own.gc_guard.pers, nil)
want("分けた列は増えていない", find_frame(300) == own and #hist() - before <= 2, true)

print("-- 分けた列の中身")
-- ボタンを押したまま当たった: 押した瞬間ではないので pressed は持ち越さない。
a_frame({ { dir = 0x00, btn = 0x04, seq = 400, gc = "p1_gc_none" } })
local held = find_frame(400)
a_frame({ { dir = 0x00, btn = 0x04, seq = 405, gc = "p1_gc_begin", mark = { seq = 404, pers = 1 } } })
local c = find_frame(404)
want("持続 1 ティック目も印になる", c and c.gc_guard and c.gc_guard.pers, 1)
want("押した印は持ち越さない", c and c.pressed, nil)
want("ボタンは押したまま", c and c.buttons[3], held and held.buttons[3])
want("受付の状態は持ち越さない", c and c.gc_event, "p1_gc_none")

print("-- 帯を出していなければ何もしない")
globals.options.show_gc_trainer = false
a_frame({ { dir = 0x00, seq = 500, gc = "p1_gc_none" } })
a_frame({ { dir = 0x01, seq = 506, gc = "p1_gc_begin", mark = { seq = 505, pers = 2 } } })
want("列は分けない", find_frame(505), nil)
globals.options.show_gc_trainer = true

print("-- 印が無ければ (被弾、当たりが見えなかった受付) 何もしない")
a_frame({ { dir = 0x00, seq = 600, gc = "p1_gc_none" } })
a_frame({ { dir = 0x01, seq = 606, gc = "p1_gc_begin" } })
want("列は分けない", find_frame(605), nil)

print("-- 描く")
-- GP と数字、なければ G。トレースのガードの行と同じ緑で、帯の高さに出す。
local function draw_one(e)
	texts = {}
	draw_input_history_entry(e, 100, 200, "black", 18)
	for _, t in ipairs(texts) do
		if t.s == "G" or (type(t.s) == "string" and t.s:sub(1, 2) == "GP") then return t end
	end
end
local t5 = draw_one(split)
want("GP6 と出る", t5 and t5.s, "GP6")
want("色はトレースのガードの行と同じ", t5 and t5.c, "#99EE99")
want("帯の高さ", t5 and t5.y, 200 - 9)
want("入れたままは G", draw_one(own) and draw_one(own).s, "G")
want("持続 1 ティック目は GP1", draw_one(c) and draw_one(c).s, "GP1")
-- いちばん細い列 (方向だけ、18px) に収まり、隣の列の GC に掛からない。
want("4 文字まで (GP12)", #("GP12") * 4.2 + 1 < 18, true)
globals.options.show_gc_trainer = false
want("帯を出していなければ描かない", draw_one(split), nil)
globals.options.show_gc_trainer = true

print("-- Hide Negative Edge Inputs (既定で ON) を通しても残る")
-- 描く前に、前と同じレバーで新しい押しの無い列を消すフィルタが掛かる。分けた列は
-- まさにその形なので、ここで消えて実機では印が一度も出なかった (2026-09-26)。
do
	local shown = remove_nedge_events(hist())
	local kept_split, kept_own = false, false
	for _, e in ipairs(shown) do
		if e == split then kept_split = true end
		if e == own then kept_own = true end
	end
	want("分けた列は残る", kept_split, true)
	want("もともとの列に付けた印も残る", kept_own, true)
	-- 印の無い、同じレバーの列は今までどおり消える (フィルタそのものは変えない)。
	local plain = { frame = 1, direction = 5, buttons = { false, false, false, false, false, false },
		gc_event = "p1_gc_none", pb_event = "p1_pb_none" }
	local plain2 = { frame = 2, direction = 5, buttons = { false, false, false, false, false, false },
		gc_event = "p1_gc_none", pb_event = "p1_pb_none" }
	want("印の無い同じ列は今までどおり消える", #remove_nedge_events({ plain, plain2 }), 1)
end

print("-- 供給側 (guardCancel の tick フック) が印を列に添えている")
do
	local gc = io.open("guardCancel.lua"):read("*a")
	want("受付のティックで印を作る", gc:find("gct.bar_mark = gct.contact ~= nil", 1, true) ~= nil, true)
	want("列に添える", gc:find("mark = gct.bar_mark", 1, true) ~= nil, true)
	want("毎ティック捨てる", gc:find("gct.bar_mark = nil", 1, true) ~= nil, true)
	local ih = io.open("inputHistory.lua"):read("*a")
	local d = ih:find("mark_guard_column(input_history[1], _raw.mark)", 1, true)
	local u = ih:find('update_input_history(input_history[1], "P1", _input, false, nil, _raw)', 1, true)
	want("受付の列を積む前に分ける", d ~= nil and u ~= nil and d < u, true)
end

if fails == 0 then
	print("test_guard_mark_column ok")
else
	print(fails .. " 件 NG")
	os.exit(1)
end
