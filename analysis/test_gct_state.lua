-- GC Command Trace - 試行の切れ目をどのバイトで見るか。
--
-- WHY THIS TEST EXISTS. コマンドブロックの +1 (段番号) は、試行が死んでも
-- 0 に戻らない。次の試行が上書きするまで最後の値のまま座っている。だから
-- 「+1 が 0 になったら終わり」と読むと、
--   * 途中で時間切れになった試行を取りこぼす (2026-09-23 のログで 41 回)
--   * うち 25 回は +1 が 02 のまま入れ直されており、2 回の試行が 1 本に
--     繋がって、1 入力では出せない間隔として描かれる
-- 状態を持っているのは +0 (どのハンドラで待っているか) のほう。
--   0 = 1 個目の方向待ち / 2 = 途中の方向待ち / 4 = ボタン待ち
--
-- 成立した tick では +0 が 4 -> 0 へ同じ tick に落ちる (ログ seq=5373)。
-- 終わり判定をイベントより先に書くと成功が潰れるので、順序も固定する。
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_gct_state.lua
local NL = string.char(10)
local src = io.open("guardCancel.lua"):read("*a")

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

-- 区間で挟んで取り出す。狙いの外の同じ文字列に当たらないように。
local s = src:find("-- ------------------------------------------------------- GC COMMAND TRACE", 1, true)
local e = src:find("-- --------------------------------------------------- END GC COMMAND TRACE", 1, true)
assert(s ~= nil and e ~= nil and e > s, "GC COMMAND TRACE の区間が見つからない")
local region = src:sub(s, e - 1)

local BASE = 0xFF8400
local BLK = 0x348          -- cid 0x09 のブロック
local mem = {}
memory = {
	readbyte = function(a) return mem[a] or 0 end,
	readword = function(a) return mem[a] or 0 end,
}
globals = { p1_tick_seq = 0 }

assert(loadstring(region .. NL
	.. "_G.gct_tick = gct_tick" .. NL
	.. "_G.gct_state = gct" .. NL
	.. "_G.gct_reset_fn = gct_reset" .. NL))()

local function fresh()
	gct_reset_fn()
	globals.gc_trace = nil
	mem = {}
	mem[BASE + 0x382] = 0x09
end

-- 1 tick 進める。prog = +0、step = +1、ev = その tick の GC イベント。
local function tick(seq, prog, step, ev)
	globals.p1_tick_seq = seq
	mem[BASE + 0x382] = 0x09
	mem[BASE + BLK] = prog
	mem[BASE + BLK + 1] = step
	gct_tick(ev)
end

local function kinds()
	local out = {}
	for _, r in ipairs(gct_state.rows) do out[#out + 1] = r.k end
	return table.concat(out, ",")
end

print("[1] ガード先行 - 方向 3 つ、成立した tick に +0 が 0 へ落ちても Success")
do
	fresh()
	tick(1, 0, 0, nil)
	tick(2, 0, 0, "p1_gc_begin")
	tick(3, 2, 2, "p1_gc_in_progress")
	tick(4, 2, 4, "p1_gc_in_progress")
	tick(5, 4, 6, "p1_gc_in_progress")
	tick(6, 0, 6, "p1_gc_success")        -- +0 は成功と同じ tick に 0 へ
	want("行の並び", kinds(), "guard,dir,dir,dir,btn")
	want("終端", gct_state.done, "Success")
	want("公開されている", globals.gc_trace ~= nil, true)
end

print("")
print("[1b] 最後の方向とボタンが同じ tick でも、方向を落とさない")
do
	-- ログ seq=5576。02.04 -> 00.06 と success が同じ tick に来る。段の増加を
	-- 「+0 が 0 でないとき」に限ると、3 個目の方向がまるごと消える。
	fresh()
	tick(1, 0, 0, "p1_gc_begin")
	tick(2, 2, 2, "p1_gc_in_progress")
	tick(3, 2, 4, "p1_gc_in_progress")
	tick(4, 0, 6, "p1_gc_success")
	want("方向 3 つとボタン", kinds(), "guard,dir,dir,dir,btn")
	want("終端", gct_state.done, "Success")
end

print("")
print("[2] コマンドの途中で時間切れ -> その後のガードが 16 tick 以内なら繋ぐ")
do
	fresh()
	tick(10, 2, 2, nil)                   -- 1 個目が入った。ガードはまだ無い
	-- gct_shown は前の試行を持ったままなので、「nil か」ではなく
	-- 「書き換えていないか」を見る。
	local before = globals.gc_trace
	tick(11, 2, 2, nil)
	tick(20, 0, 2, nil)                   -- 時間切れ。+1 は 02 のまま
	want("ガード前でも時間切れを覚えている", gct_state.done, "Cmd Expired")
	want("行を捨てていない", kinds(), "dir")
	want("ガードが無い間は画面を書き換えない", globals.gc_trace, before)
	tick(36, 0, 2, "p1_gc_begin")         -- ちょうど 16 tick 後のガード
	want("死んだ行 + ガード", kinds(), "dir,dead,guard")
	want("繋いだので終端は消える", gct_state.done, nil)
	-- ここが取りこぼしていた遷移。+1 は 02 のままで +0 だけが 0 -> 2。
	tick(37, 2, 2, "p1_gc_in_progress")
	want("段が動かない入れ直しも 1 個目として拾う", kinds(), "dir,dead,guard,dir")
	tick(38, 2, 4, "p1_gc_in_progress")
	tick(39, 4, 6, "p1_gc_in_progress")
	tick(40, 0, 6, "p1_gc_success")
	want("そのまま成立まで通る", kinds(), "dir,dead,guard,dir,dir,dir,btn")
	want("終端", gct_state.done, "Success")
end

print("")
print("[3] 17 tick 後のガードは繋がない")
do
	fresh()
	tick(10, 2, 2, nil)
	tick(20, 0, 2, nil)
	want("時間切れ", gct_state.done, "Cmd Expired")
	tick(37, 0, 2, "p1_gc_begin")         -- 20 から 17 tick
	want("新しい trace になる", kinds(), "guard")
	want("終端は無い", gct_state.done, nil)
end

print("")
print("[4] 受付が開いている間の入れ直しは、同じガードの続きにする")
do
	-- 実機 2026-09-24。ガードの 3t 後にコマンドが切れ、受付が開いたまま
	-- 入れ直して成立した。ここで畳むとガードごと消えるので、成立した試行は
	-- 自分のガードを持たず、画面に一度も出ない。
	fresh()
	tick(0,  2, 2, nil)                   -- 1 個目
	tick(9,  2, 4, nil)                   -- 2 個目
	tick(21, 2, 4, "p1_gc_begin")         -- ガード
	tick(24, 0, 4, "p1_gc_in_progress")   -- コマンド切れ
	want("時間切れ", gct_state.done, "Cmd Expired")
	tick(26, 2, 2, "p1_gc_in_progress")   -- 受付が開いたまま入れ直し
	want("ガードを捨てない", gct_state.guard, 21)
	want("死んだ印を挟んで続ける", kinds(), "dir,dir,guard,dead,dir")
	tick(28, 2, 4, "p1_gc_in_progress")
	tick(31, 4, 6, "p1_gc_in_progress")
	tick(33, 0, 6, "p1_gc_success")
	want("成立まで通る", kinds(), "dir,dir,guard,dead,dir,dir,dir,btn")
	want("終端", gct_state.done, "Success")
	want("成立が画面に出る", globals.gc_trace ~= nil
		and globals.gc_trace.done, "Success")
end

print("")
print("[4b] 受付が閉じた後の入れ直しは畳む")
do
	fresh()
	tick(1, 0, 0, "p1_gc_begin")
	tick(2, 2, 2, "p1_gc_in_progress")
	tick(9, 2, 2, "p1_gc_ended")          -- 受付が切れた
	want("終端", gct_state.done, "GC Expired")
	tick(20, 0, 2, nil)
	tick(21, 2, 2, nil)                   -- 受付の外なので新しい試行
	want("集めなおしている", kinds(), "dir")
	-- gct_publish は毎回新しいテーブルを作るので、同一性ではなく中身で見る。
	want("画面は終わった試行のまま", globals.gc_trace.done, "GC Expired")
	want("集め直しの行は出ていない", #globals.gc_trace.rows, 2)
end

print("[4c] 受付が閉じた後に入れ直したら、そのガードには繋がない")
do
	-- コマンドが先に切れて done が Cmd Expired のまま受付が閉じた場合。
	-- ここで続きにすると、とっくに終わったガードへ何十ティックも後の入力を
	-- 繋いでしまう。繋ぐのは受付が開いている間だけ。
	fresh()
	tick(1,  0, 0, "p1_gc_begin")
	tick(2,  2, 2, "p1_gc_in_progress")
	tick(5,  0, 2, "p1_gc_in_progress")   -- コマンド切れ
	want("時間切れ", gct_state.done, "Cmd Expired")
	tick(15, 0, 2, "p1_gc_ended")         -- 受付が閉じた
	tick(30, 2, 2, nil)                   -- ずっと後の入れ直し
	want("新しい試行になる", kinds(), "dir")
	want("古いガードを引きずらない", gct_state.guard, nil)
end

print("")
print("[5] GC の受付が先に切れたら GC Expired")
do
	fresh()
	tick(1, 0, 0, "p1_gc_begin")
	tick(2, 2, 2, "p1_gc_in_progress")
	tick(9, 2, 2, "p1_gc_ended")          -- コマンドはまだ生きている
	want("終端", gct_state.done, "GC Expired")
	want("行", kinds(), "guard,dir")
end

print("")
print("[6] 終わり判定はイベントの後 - 並び順を固定する")
do
	local f = src:find("local function gct_tick", 1, true)
	local g = src:find("-- --------------------------------------------------- END GC COMMAND TRACE", f or 1, true)
	local body = src:sub(f or 1, (g or 1) - 1)
	local i_succ = body:find('"p1_gc_success"', 1, true)
	local i_drop = body:find("_dropped", body:find("if gct.done == nil then", 1, true) or 1, true)
	want("success を先に見ている", i_succ ~= nil and i_drop ~= nil and i_succ < i_drop, true)
	want("終わりは +0 で見る", body:find("_dropped = _was_prog ~= 0 and _prog == 0", 1, true) ~= nil, true)
	want("段 == 0 を終わりの条件に使っていない", body:find("_step == 0 and _prog == 0", 1, true), nil)
end

print("")
if fails == 0 then
	print("ALL OK")
else
	print(fails .. " NG")
	os.exit(1)
end
