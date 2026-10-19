-- TECH HIT MUST STAY ON THE ROW THE PUSH BLOCK WAS GRANTED ON.
--
-- Confirmed bug: with PB Stats' button history, a push block granted on the
-- third press moved its TECH HIT down to rows 4, 5 and 6 as the player kept
-- pressing, because the display searched for the LAST mark while ok was true
-- and marks keeps recording after the grant (user, 2026-10-19).
--
-- This drives the real timers.lua hooks (0x0275E0 and 0x027632) and the real
-- tech-hit-inputs.lua drawing with memory, exec hooks and gui mocked. The
-- game itself is not running; see the report for the separate in-game check.
--
-- Run from scripts/ - the dofile paths and the icon path are relative.
--   cd scripts && lua5.1 ../analysis/test_tech_hit_position.lua
local P1, P2 = 0xFF8400, 0xFF8800

local ram = {}
local execs = {}
local a6 = P1

memory = {
	readbyte = function(x) return ram[x] or 0 end,
	readbytesigned = function(x) return ram[x] or 0 end,
	readword = function(x) return ram[x] or 0 end,
	readwordsigned = function(x) return ram[x] or 0 end,
	readdword = function(x) return ram[x] or 0 end,
	readdwordsigned = function(x) return ram[x] or 0 end,
	writebyte = function(x, v) ram[x] = v end,
	writeword = function(x, v) ram[x] = v end,
	writedword = function(x, v) ram[x] = v end,
	registerexec = function(addr, f) execs[addr] = f end,
	getregister = function() return a6 end,
}

local draws = {}
gui = {
	text = function(x, y, s) draws[#draws + 1] = { x = x, y = y, s = tostring(s) } end,
	box = function() end,
	gdoverlay = function() end,
}
local _img = { gdStr = function() return "" end }
gd = {
	createFromPng = function() return _img end,
	createFromPngStr = function() return _img end,
	copyResampled = function() end,
}

globals = { options = {}, dummy = {}, controlling_p1 = true }
package.preload["./scripts/debugKnockdown"] = function()
	return { mark_write = function() end }
end

local timersModule = dofile("timers.lua")
local timers = timersModule.registerBefore()
globals.timers = timers
local tech_hit_inputs = dofile("tech-hit-inputs.lua")

local fails = 0
local function want(what, got, w)
	if got ~= w then
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(w) .. "]")
	else
		print("  ok " .. what)
	end
end

-- The live draw, read back as the row number TECH HIT landed on. Rows are
-- input numbers 1..n; ticks are positions 1..14, and a tick with no press
-- takes no row. nil means no TECH HIT was drawn.
local function draw_state()
	draws = {}
	tech_hit_inputs(38)
	local labels, tech_ys = {}, {}
	for _, d in ipairs(draws) do
		if d.s == "TECH HIT" then tech_ys[#tech_ys + 1] = d.y end
		local n = d.s:match("^(%d+): $")
		if n then labels[#labels + 1] = { n = tonumber(n), y = d.y } end
	end
	local row
	if #tech_ys == 1 then
		for _, l in ipairs(labels) do
			if l.y == tech_ys[1] then row = l.n end
		end
	end
	return row, #tech_ys, #labels
end

-- The state the ROM routine is entered in: guarding, in the PB window, one
-- button edge on $126. $170 is the game's count, passed in as the value the
-- routine will read at 0x02760A.
local function guarding(who, count, granted, mask)
	a6 = who
	ram[who + 0x170] = count
	ram[who + 0x184] = granted and 1 or 0
	ram[who + 0x04] = 0x0202
	ram[who + 0x140] = 0x02
	ram[who + 0x3B4] = 0
	ram[0xFF815D] = 0
	ram[who + 0x126] = mask or 0
end

-- One tick in the window. $1AB = 14 is the opening tick, position 1 =
-- 15 - $1AB. The game decrements $1AB itself; the harness moves it by hand.
local function tick(who, w, count, granted, mask)
	guarding(who, count, granted, mask)
	ram[who + 0x1AB] = w
	execs[0x0275E0]()
end

local function grant(who)
	a6 = who
	execs[0x027632]()
end

local function marks_string(who)
	local t = (who == P1) and timers.p1_pb_marks or timers.p2_pb_marks
	local out = {}
	for i = 1, 14 do out[i] = t[i] or "-" end
	return table.concat(out)
end

print("-- 3 回目で成立し、6 回まで押しても 3 行目に残る")
tick(P1, 14, 0, false, 0x01)
tick(P1, 13, 1, false, 0x01)
tick(P1, 12, 2, false, 0x01)
grant(P1)
want("成立した", timers.p1_pushblock_ok, true)
want("成立位置は 3", timers.p1_pb_grant_pos, 3)
want("成立時点の数は 3", timers.p1_pushblock_counter, 3)
tick(P1, 11, 3, true, 0x01)
want("成立後の追加入力も数える (4)", timers.p1_pushblock_counter, 4)
tick(P1, 10, 3, true, 0x01)
want("成立後の追加入力も数える (5)", timers.p1_pushblock_counter, 5)
tick(P1, 9, 3, true, 0x01)
want("成立後の追加入力も数える (6)", timers.p1_pushblock_counter, 6)
local row, n_tech, n_rows = draw_state()
want("TECH HIT は 1 つだけ", n_tech, 1)
want("入力行は 6", n_rows, 6)
want("TECH HIT は 3 行目", row, 3)

print("-- 受付終了後も、残っている履歴の成立行に表示する")
ram[P1 + 0x1AB] = 0
row, n_tech, n_rows = draw_state()
want("窓が閉じても 6 行残る", n_rows, 6)
want("窓が閉じても 3 行目", row, 3)

print("-- 入力のない Tick を挟んでも、成立した入力行へ表示する")
tick(P1, 14, 0, false, 0x00)          -- 前の試行を閉じ、新しい窓
tick(P1, 14, 0, false, 0x01)          -- position 1 -> row 1
tick(P1, 13, 1, false, 0x00)          -- position 2 -> no row
tick(P1, 12, 1, false, 0x00)          -- position 3 -> no row
tick(P1, 11, 1, false, 0x00)          -- position 4 -> no row
tick(P1, 10, 1, false, 0x01)          -- position 5 -> row 2
grant(P1)
want("成立位置は 5", timers.p1_pb_grant_pos, 5)
row, n_tech, n_rows = draw_state()
want("入力行は 2", n_rows, 2)
want("TECH HIT は 2 行目", row, 2)
want("成立位置と成立行を混同しない", timers.p1_pb_grant_pos ~= row, true)

print("-- 同時押しでも、その Tick の 1 行に表示する")
tick(P1, 14, 0, false, 0x00)
tick(P1, 14, 0, false, 0x03)          -- LP+MP on the granting tick
grant(P1)
want("成立位置は 1", timers.p1_pb_grant_pos, 1)
want("MultiPush は 1", timers.p1_pb_simul, 1)
want("同時押しでもカウントは 1", timers.p1_pushblock_counter, 1)
row, n_tech, n_rows = draw_state()
want("同じ Tick の 2 ボタンは 1 行", n_rows, 1)
want("TECH HIT は 1 行目", row, 1)

print("-- 不成立の試行には表示しない")
tick(P1, 14, 0, false, 0x00)
tick(P1, 14, 0, false, 0x01)
tick(P1, 13, 1, false, 0x01)
want("成立していない", timers.p1_pushblock_ok, false)
row, n_tech, n_rows = draw_state()
want("TECH HIT は出ない", n_tech, 0)
want("表示行は nil", row, nil)

print("-- 連続ガードで受付区間が切り替わったら、古い成立を混ぜない")
tick(P1, 14, 0, false, 0x00)
tick(P1, 14, 0, false, 0x01)
tick(P1, 13, 1, false, 0x01)
tick(P1, 12, 2, false, 0x01)
grant(P1)
local old_marks = timers.p1_pb_marks
want("旧区間で成立", timers.p1_pb_grant_pos, 3)
tick(P1, 14, 3, true, 0x01)           -- 0x023966 re-arms $1AB: new span
want("新しい区間の marks になった", timers.p1_pb_marks ~= old_marks, true)
want("成立位置は旧区間のまま残らない", timers.p1_pb_grant_pos, nil)
want("成立区間の印も残らない", timers.p1_pb_grant_marks, nil)
want("成功フラグは別の寿命のまま", timers.p1_pushblock_ok, true)
row, n_tech, n_rows = draw_state()
want("新区間に入力行は 1", n_rows, 1)
want("古い TECH HIT は出ない", n_tech, 0)

print("-- 次の試行では、前の成立位置を持ち越さない")
ram[P1 + 0x1AB] = 0
tick(P1, 14, 0, false, 0x01)          -- guard ended; next attempt opens
want("前の成功フラグは消える", timers.p1_pushblock_ok, false)
want("成立位置も消える", timers.p1_pb_grant_pos, nil)
want("成立区間も消える", timers.p1_pb_grant_marks, nil)
row, n_tech, n_rows = draw_state()
want("TECH HIT は出ない", n_tech, 0)

print("-- 成立位置が確認できないときは推測しない")
tick(P1, 14, 0, false, 0x01)          -- この Tick は position 1
ram[P1 + 0x1AB] = 13                  -- grant hook の $1AB だけが動いた
grant(P1)
want("成立フラグは立つ", timers.p1_pushblock_ok, true)
want("位置は保存しない", timers.p1_pb_grant_pos, nil)
row, n_tech, n_rows = draw_state()
want("TECH HIT は出ない", n_tech, 0)

print("-- P1/P2 の成立位置は別々")
timersModule.clear()
tick(P1, 14, 0, false, 0x01)
tick(P1, 13, 1, false, 0x01)
tick(P1, 12, 2, false, 0x01)
grant(P1)
tick(P2, 14, 0, false, 0x01)
tick(P2, 13, 1, false, 0x01)
tick(P2, 12, 2, false, 0x01)
tick(P2, 11, 3, false, 0x01)
tick(P2, 10, 4, false, 0x01)
grant(P2)
want("P1 の成立位置は 3", timers.p1_pb_grant_pos, 3)
want("P2 の成立位置は 5", timers.p2_pb_grant_pos, 5)
want("P1 は P1 の区間を指す", timers.p1_pb_grant_marks == timers.p1_pb_marks, true)
want("P2 は P2 の区間を指す", timers.p2_pb_grant_marks == timers.p2_pb_marks, true)
want("P1 と P2 の区間は別", timers.p1_pb_grant_marks ~= timers.p2_pb_grant_marks, true)
row, n_tech, n_rows = draw_state()
want("P1 の TECH HIT は 3 行目", row, 3)
want("P1 の入力行は 3", n_rows, 3)

print("-- clear は両方の成立位置と履歴を消す")
timersModule.clear()
want("P1 の成立位置が消える", timers.p1_pb_grant_pos, nil)
want("P2 の成立位置が消える", timers.p2_pb_grant_pos, nil)
want("P1 の成立区間が消える", timers.p1_pb_grant_marks, nil)
want("P2 の成立区間が消える", timers.p2_pb_grant_marks, nil)
want("P1 の成功フラグが消える", timers.p1_pushblock_ok, false)
want("P2 の成功フラグが消える", timers.p2_pushblock_ok, false)
row, n_tech, n_rows = draw_state()
want("履歴が消えて入力行は 0", n_rows, 0)
want("TECH HIT も出ない", n_tech, 0)

print("-- 成立後も marks は追加入力を記録する (維持仕様)")
tick(P1, 14, 0, false, 0x01)
tick(P1, 13, 1, false, 0x01)
tick(P1, 12, 2, false, 0x01)
grant(P1)
tick(P1, 11, 3, true, 0x01)
tick(P1, 10, 3, true, 0x01)
tick(P1, 9, 3, true, 0x01)
want("成立後も 6 行ぶん記録される", marks_string(P1):sub(1, 6), "111111")
want("成立位置は 3 のまま", timers.p1_pb_grant_pos, 3)
row, n_tech, n_rows = draw_state()
want("同時に描画しても TECH HIT は 3 行目", row, 3)

if fails == 0 then
	print("test_tech_hit_position ok")
else
	print(fails .. " 件 NG")
	os.exit(1)
end
