-- SUCCESS の隣に出る数字が、ティックであってフレームでないこと。
--
-- WHY IT CANNOT BE COUNTED WHERE IT IS DRAWN. $158 takes 14 on a guard and
-- 0x022492 removes one EVERY TICK (VSAV_MEMORY_NOTES.md), so the label is a
-- tick count or it is nothing. inputHistory's own gc handling runs from
-- registerBefore, which is displayed frames - at turbo 3 that is 3 frames to
-- 4 ticks, so counting there would print frames under a "t".
--
-- WHY IT IS NOT READ OUT OF $158. A cancel clears the clock early, and by the
-- time anything knows the cancel succeeded the value it had is gone. Counting
-- from the tick the window opened needs no such reading.
--
-- WHAT THIS DRIVES. gc_tick_count is lifted out of guardCancel.lua and run
-- tick by tick, because the hook it lives in only runs when the game reaches
-- 0x0221CC. The other half - the number reaching the column - is pinned in
-- test_input_tick_columns.lua.
--
-- Run from scripts/ - the read below is relative.
--   cd scripts && lua5.1 ../analysis/test_gc_success_ticks.lua
local NL = string.char(10)
local src = io.open("guardCancel.lua"):read("*a")
local a = src:find("local function gc_tick_count(", 1, true)
local b = src:find(NL .. "end", a or 1, true)
assert(a, "gc_tick_count が guardCancel.lua に見つからない")
assert(b, "gc_tick_count の終わりが見つからない")
local gc_tick_count = assert(loadstring(
	src:sub(a, b + 3) .. NL .. "return gc_tick_count"))()
local sa = src:find("local function gc_next_state(", 1, true)
local sb = src:find(NL .. "end", sa or 1, true)
assert(sa and sb, "gc_next_state が guardCancel.lua に見つからない")
local gc_next_state = assert(loadstring(
	src:sub(sa, sb + 3) .. NL .. "return gc_next_state"))()

local fails = 0
local function want(what, got, expected)
	if got == expected then
		print("  ok " .. what)
	else
		fails = fails + 1
		print("  NG " .. what)
		print("     got  [" .. tostring(got) .. "]")
		print("     want [" .. tostring(expected) .. "]")
	end
end

-- 窓を 1 ティックずつ回す。guardCancel の状態機械と同じ順で状態を渡し、
-- 返ってきた数と持ち越しを引き継ぐ。cancel_at は「窓が開いてから何ティック
-- 目にキャンセルが出たか」で、ここが答えになるはずの値。
local function run_window(cancel_at, succeed)
	local open_seq, got = nil, nil
	local seq = 500                     -- 任意の開始位置。差だけが意味を持つ。
	local state = "p1_gc_none"
	for t = 0, 20 do
		seq = seq + 1
		local gc
		if t == 0 then
			gc = "p1_gc_begin"
		elseif t < cancel_at then
			gc = "p1_gc_in_progress"
		elseif t == cancel_at then
			gc = succeed and "p1_gc_success" or "p1_gc_ended"
		else
			gc = "p1_gc_none"
		end
		state = gc
		local n
		n, open_seq = gc_tick_count(gc, open_seq, seq)
		if n ~= nil then got = n end
	end
	return got, open_seq
end

print("[1] 窓が開いてから何ティック目か")
-- 窓は 14 ティック。早いほど小さい。
for _, at in ipairs({ 2, 5, 9, 13, 14 }) do
	local n = run_window(at, true)
	want(at .. " ティック目に出たら " .. at, n, at)
end

print("")
print("[2] 成立しなかった窓は数えない")
-- 時間切れ (p1_gc_ended) には数字を付けない。SUCCESS の隣にしか出ない。
want("14 で時間切れ", run_window(14, false), nil)
want("途中で終わっても", run_window(6, false), nil)

print("")
print("[3] 次の窓は 0 から数え直す")
-- 持ち越しが残ると、2 回目が前の窓ぶんまで足した値になる。
do
	local open_seq, seq = nil, 900
	local results = {}
	for _, w in ipairs({ 4, 7, 11 }) do
		for t = 0, w do
			seq = seq + 1
			local gc
			if t == 0 then gc = "p1_gc_begin"
			elseif t < w then gc = "p1_gc_in_progress"
			else gc = "p1_gc_success" end
			local n
			n, open_seq = gc_tick_count(gc, open_seq, seq)
			if n ~= nil then results[#results + 1] = n end
		end
		-- 窓と窓のあいだ。何ティックあいても次の値は変わらないこと。
		for _ = 1, 37 do
			seq = seq + 1
			local n
			n, open_seq = gc_tick_count("p1_gc_none", open_seq, seq)
			want("窓の外では数えない", n, nil)
		end
	end
	want("1 回目", results[1], 4)
	want("2 回目", results[2], 7)
	want("3 回目", results[3], 11)
	want("成立した数だけ返っている", #results, 3)
end

print("")
print("[4] 開始を見ていない窓には数字を付けない")
-- メニューを閉じた直後など、途中から拾った窓。適当な数を出すくらいなら
-- 何も出さないほうがよい。
do
	local n, carry = gc_tick_count("p1_gc_success", nil, 1234)
	want("数字は出ない", n, nil)
	want("持ち越しも残さない", carry, nil)
end

print("")
print("[5] 開いた窓は、閉じるまで持ち越す")
do
	local n, carry = gc_tick_count("p1_gc_begin", nil, 700)
	want("開始では数えない", n, nil)
	want("開始ティックを憶える", carry, 700)
	local n2, carry2 = gc_tick_count("p1_gc_in_progress", carry, 705)
	want("途中でも数えない", n2, nil)
	want("憶えたまま", carry2, 700)
	local n3, carry3 = gc_tick_count("p1_gc_success", carry2, 709)
	want("成立で差が出る", n3, 9)
	want("使ったら手放す", carry3, nil)
end

print("")
print("[6] ガードした瞬間に出したキャンセルも成立として拾う")
-- 本件の不具合。窓が開いた次のティックにキャンセルが出ると、状態はまだ
-- begin で、成立の判定が in_progress を要求していたためどの枝にも当たらず、
-- begin のまま固まっていた。次のガードまでそのままなので、キャンセルは
-- 出ているのに SUCCESS が一度も描かれない (本人、2026-09-23)。
do
	want("begin から直接 成立", gc_next_state("p1_gc_begin", 0, 0x0E), "p1_gc_success")
	want("begin から ES", gc_next_state("p1_gc_begin", 0, 0x10), "p1_gc_success")
	want("begin から EX", gc_next_state("p1_gc_begin", 0, 0x12), "p1_gc_success")
	want("begin で技が出ていなければ時間切れ",
		gc_next_state("p1_gc_begin", 0, 0x00), "p1_gc_ended")
	-- 従来どおりの経路も壊していないこと。
	want("in_progress から 成立",
		gc_next_state("p1_gc_in_progress", 0, 0x0E), "p1_gc_success")
	want("in_progress から 時間切れ",
		gc_next_state("p1_gc_in_progress", 0, 0x00), "p1_gc_ended")
	want("窓が開けば begin", gc_next_state("p1_gc_none", 14, 0x00), "p1_gc_begin")
	want("開いたままなら in_progress",
		gc_next_state("p1_gc_begin", 13, 0x00), "p1_gc_in_progress")
	want("成立の次は none", gc_next_state("p1_gc_success", 0, 0x0E), "p1_gc_none")
	want("時間切れの次も none", gc_next_state("p1_gc_ended", 0, 0x00), "p1_gc_none")
end

print("")
print("[7] 状態機械と数えるほうを繋いで、1 ティック目の成立を通す")
-- 2 つとも直っていないと SUCCESS 1t にならない。状態機械だけ直しても
-- 数が出ず、数だけ直しても SUCCESS が出ない。
do
	local state, open_seq, seq, got = "p1_gc_none", nil, 300, nil
	-- 1 ティック目: ガード成立で窓が開く。
	local clocks = { 14, 0, 0, 0 }
	local acts   = {  0, 0x0E, 0x0E, 0x00 }
	for i = 1, #clocks do
		seq = seq + 1
		state = gc_next_state(state, clocks[i], acts[i])
		local n
		n, open_seq = gc_tick_count(state, open_seq, seq)
		if n ~= nil then got = n end
	end
	want("成立として拾えた", got ~= nil, true)
	want("1 ティック目と出る", got, 1)
end
if fails == 0 then print("") print("全て通った") else print(fails .. " 件 NG") os.exit(1) end
