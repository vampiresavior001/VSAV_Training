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
	-- The guard pose's own state outlives a trace on purpose (it follows the
	-- character, not the attempt), so a test has to clear it itself.
	gct_state.pers_start, gct_state.pers_n, gct_state.pose_prev = nil, nil, nil
	gct_state.contact, gct_state.pre_prev, gct_state.bar_mark = nil, nil, nil
	globals.gc_trace = nil
	mem = {}
	mem[BASE + 0x382] = 0x09
	-- The last lever the guard pose tested (facing-corrected): back, as it is
	-- while a guard is held. A test that lets go sets it itself.
	mem[BASE + 0x12D] = 0x01
end

-- ガードポーズの状態を置く。$06 = 0C がポーズ、$07 = 02 が離した後の持続。
local function pose(s06, s07, s05)
	mem[BASE + 0x06], mem[BASE + 0x07], mem[BASE + 0x05] = s06, s07, s05 or 0
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
print("[4d] 連続ガード - 前の受付が切れた後も生きているコマンドは、次のガードへ持ち越す")
do
	-- 実機 2026-09-25。オルバスの 5 段チェーンをガード中、1 段目の受付
	-- (14t) がコマンドの途中で切れ、2 段目のガードでそのまま成立した。
	-- トレースは Guard -> 最後の 1 方向 -> ボタン だけになり、方向 1 つで
	-- GC が出たように見えた。入力履歴には → ↓ ↘+P が全部あった。
	--
	-- 受付切れの結果を表示している間 (done ~= nil) に入った方向を拾って
	-- おらず、次のガードで白紙から始めていたため。
	fresh()
	tick(1,  0, 0, "p1_gc_begin")         -- 1 段目のガード
	tick(5,  2, 2, "p1_gc_in_progress")   -- →
	tick(15, 2, 2, "p1_gc_ended")         -- 1 段目の受付が切れた。コマンドは生きている
	want("受付切れ", gct_state.done, "GC Expired")
	tick(18, 2, 4, nil)                   -- ↓ (受付切れの表示中)
	tick(20, 2, 4, "p1_gc_begin")         -- 2 段目のガード
	tick(21, 4, 6, "p1_gc_in_progress")   -- ↘
	tick(22, 0, 6, "p1_gc_success")
	want("→ ↓ を持ち越してから Guard", kinds(), "dir,dir,guard,dir,btn")
	want("成立", gct_state.done, "Success")
	want("ガードは 2 段目", gct_state.guard, 20)
	want("→ は 1 段目の受付中の時刻", gct_state.rows[1].t, 5)
	want("↓ は受付切れの表示中の時刻", gct_state.rows[2].t, 18)

	-- 2 段目のガードと同じティックに方向が入っても、1 回しか記録しない。
	fresh()
	tick(1,  0, 0, "p1_gc_begin")
	tick(5,  2, 2, "p1_gc_in_progress")
	tick(15, 2, 2, "p1_gc_ended")
	tick(20, 2, 4, "p1_gc_begin")         -- ガードと ↓ が同時
	want("→ を持ち越し、↓ は 1 回", kinds(), "dir,dir,guard")
end

print("")
print("[4e] 持ち越すのは生きているコマンドだけ")
do
	-- 受付切れの表示中にコマンドも死んだら、次のガードには何も持ち越さない。
	fresh()
	tick(1,  0, 0, "p1_gc_begin")
	tick(5,  2, 2, "p1_gc_in_progress")
	tick(15, 2, 2, "p1_gc_ended")
	tick(18, 0, 2, nil)                   -- コマンドも切れた
	tick(30, 0, 2, "p1_gc_begin")         -- 次のガード
	want("Guard から始まる", kinds(), "guard")

	-- 次のガードと同じティックに入れ直した場合は、新しいコマンドだけ。
	fresh()
	tick(1,  0, 0, "p1_gc_begin")
	tick(5,  2, 2, "p1_gc_in_progress")
	tick(15, 2, 2, "p1_gc_ended")
	tick(18, 0, 2, nil)
	tick(30, 2, 2, "p1_gc_begin")         -- ガードと 1 個目の方向が同時
	want("新しい 1 個目とガード", kinds(), "dir,guard")

	-- 次のガードと同じティックにコマンドが切れたら、持ち越さない。
	fresh()
	tick(1,  0, 0, "p1_gc_begin")
	tick(5,  2, 2, "p1_gc_in_progress")
	tick(15, 2, 2, "p1_gc_ended")
	tick(20, 0, 2, "p1_gc_begin")         -- ガードの瞬間にコマンドが切れた
	want("切れたコマンドは持ち越さない", kinds(), "guard")
end

print("")
print("[P] ガード持続の何ティック目で当たったか")
do
	-- 実測 (デミトリ 65 回、2026-09-25): ポーズ中 ($06 = 0C) は $07 が 00 なら
	-- ガード方向を入れている、02 なら離した後の持続。接触のティックに $06 が
	-- 0C を外れ $05 が立つ。受付 (p1_gc_begin) はその 1 ティック後のこともある。
	fresh()
	pose(0x0C, 0x00) tick(1, 0, 0, nil)      -- 後ろを入れてポーズ
	pose(0x0C, 0x00) tick(2, 0, 0, nil)
	pose(0x0C, 0x02) tick(3, 0, 0, nil)      -- 離した。持続の始まり
	pose(0x0C, 0x02) tick(4, 0, 0, nil)
	pose(0x00, 0x02, 0x02) tick(6, 0, 0, "p1_gc_begin")   -- 3 ティック後に接触
	want("持続中のガードは Guard 行に 4 を持つ (離したティックが 1)", gct_state.rows[1] and gct_state.rows[1].v, 4)

	-- 受付が 1 ティック遅れても同じ値。
	fresh()
	pose(0x0C, 0x00) tick(1, 0, 0, nil)
	pose(0x0C, 0x02) tick(3, 0, 0, nil)
	pose(0x00, 0x02, 0x02) tick(6, 0, 0, nil)             -- 接触
	pose(0x00, 0x02, 0x02) tick(7, 0, 0, "p1_gc_begin")   -- 受付はその次
	want("受付が 1 ティック遅れても 4", gct_state.rows[1] and gct_state.rows[1].v, 4)

	-- 後ろを入れたままなら数字は無い (いつもの Guard)。めくりもこちら。
	fresh()
	pose(0x0C, 0x00) tick(1, 0, 0, nil)
	pose(0x0C, 0x00) tick(2, 0, 0, nil)
	pose(0x00, 0x02, 0x02) tick(3, 0, 0, "p1_gc_begin")
	want("入れたままのガードは数字なし", gct_state.rows[1] and gct_state.rows[1].v, nil)

	-- 離してから入れ直したら、持続は数え直しではなく消える。
	fresh()
	pose(0x0C, 0x02) tick(1, 0, 0, nil)
	pose(0x0C, 0x00) tick(2, 0, 0, nil)      -- 後ろを入れ直した
	pose(0x00, 0x02, 0x02) tick(4, 0, 0, "p1_gc_begin")
	want("入れ直したら持続ではない", gct_state.rows[1] and gct_state.rows[1].v, nil)

	-- 食らって受付が開かなかった接触の値を、後のガードへ渡さない。
	fresh()
	pose(0x0C, 0x02) tick(1, 0, 0, nil)
	pose(0x00, 0x02, 0x02) tick(4, 0, 0, nil)             -- 接触 (食らい)
	pose(0x00, 0x00, 0x00) tick(20, 0, 0, nil)            -- 硬直が明けた
	pose(0x00, 0x02, 0x02) tick(30, 0, 0, "p1_gc_begin")  -- ポーズ無しでガード
	want("古い持続は使わない", gct_state.rows[1] and gct_state.rows[1].v, nil)

	-- ポーズが歩きで消えた (接触なし) なら、後のガードに数字は付かない。
	fresh()
	pose(0x0C, 0x02) tick(1, 0, 0, nil)
	pose(0x04, 0x00, 0x00) tick(3, 0, 0, nil)             -- 前に歩いた
	pose(0x00, 0x02, 0x02) tick(9, 0, 0, "p1_gc_begin")
	want("歩きで消えたポーズは数えない", gct_state.rows[1] and gct_state.rows[1].v, nil)

	-- しゃがみガード。$07 は 04 が入れている、06 が離した後の持続 (ROM 0x022FDA)。
	-- 最初は 02 だけを見ていて、しゃがみの持続が数えられていなかった。
	fresh()
	pose(0x0C, 0x04) tick(1, 0, 0, nil)      -- 下後ろを入れてしゃがみガード
	pose(0x0C, 0x06) tick(3, 0, 0, nil)      -- 離した。しゃがみの持続
	pose(0x0C, 0x06) tick(4, 0, 0, nil)
	pose(0x00, 0x00, 0x02) tick(7, 0, 0, nil)             -- 4 ティック後に接触
	pose(0x00, 0x02, 0x02) tick(8, 0, 0, "p1_gc_begin")
	want("しゃがみの持続も数える", gct_state.rows[1] and gct_state.rows[1].v, 5)

	fresh()
	pose(0x0C, 0x04) tick(1, 0, 0, nil)
	pose(0x0C, 0x04) tick(2, 0, 0, nil)
	pose(0x00, 0x00, 0x02) tick(3, 0, 0, nil)
	pose(0x00, 0x02, 0x02) tick(4, 0, 0, "p1_gc_begin")
	want("しゃがみで入れたままなら数字なし", gct_state.rows[1] and gct_state.rows[1].v, nil)

	-- 立ちとしゃがみを入れ替えても (00 <-> 04) 入れている間は持続ではない。
	fresh()
	pose(0x0C, 0x02) tick(1, 0, 0, nil)
	pose(0x0C, 0x04) tick(2, 0, 0, nil)      -- しゃがみで入れ直した
	pose(0x0C, 0x06) tick(4, 0, 0, nil)      -- また離した
	pose(0x00, 0x00, 0x02) tick(6, 0, 0, nil)
	pose(0x00, 0x02, 0x02) tick(7, 0, 0, "p1_gc_begin")
	want("入れ直した後の持続から数え直す", gct_state.rows[1] and gct_state.rows[1].v, 3)

	-- 離した次の処理で持続に入り、その直後に当たった (持続 1 ティック目。旧 G-Persist 0)。フックは P1 の処理の
	-- 先頭なので $07 = 02 を一度も見ないまま当たりで上書きされる。ポーズが最後に
	-- 見たレバー ($12D、向き補正済み) の bit0 = 後ろ で判定する (ROM 0x027694)。
	-- 実機 2026-09-25: ← 4 のあとニュートラル最初のティックでガード、Guard (6t) と出ていた。
	fresh()
	pose(0x0C, 0x00) tick(1, 0, 0, nil)      -- 後ろを入れている
	mem[BASE + 0x12D] = 0x00                 -- 最後に処理したレバーは後ろではない
	pose(0x00, 0x00, 0x02) tick(2, 0, 0, nil)             -- 当たった
	pose(0x00, 0x02, 0x02) tick(3, 0, 0, "p1_gc_begin")
	want("離した直後の当たりは持続 1 ティック目", gct_state.rows[1] and gct_state.rows[1].v, 1)

	fresh()
	pose(0x0C, 0x00) tick(1, 0, 0, nil)
	mem[BASE + 0x12D] = 0x01                 -- 後ろのまま
	pose(0x00, 0x00, 0x02) tick(2, 0, 0, nil)
	pose(0x00, 0x02, 0x02) tick(3, 0, 0, "p1_gc_begin")
	want("後ろのままなら数字なし", gct_state.rows[1] and gct_state.rows[1].v, nil)

	fresh()
	pose(0x0C, 0x04) tick(1, 0, 0, nil)      -- しゃがみで入れている
	mem[BASE + 0x12D] = 0x05                 -- 下後ろのまま
	pose(0x00, 0x00, 0x02) tick(2, 0, 0, nil)
	pose(0x00, 0x02, 0x02) tick(3, 0, 0, "p1_gc_begin")
	want("下後ろのままでも数字なし", gct_state.rows[1] and gct_state.rows[1].v, nil)

	fresh()
	pose(0x0C, 0x00) tick(1, 0, 0, nil)
	mem[BASE + 0x12D], mem[BASE + 0x3B2] = 0x00, 0x01   -- $3B2: ポーズがレバーを見ない
	pose(0x00, 0x00, 0x02) tick(2, 0, 0, nil)
	pose(0x00, 0x02, 0x02) tick(3, 0, 0, "p1_gc_begin")
	want("$3B2 が立っていたら判定しない", gct_state.rows[1] and gct_state.rows[1].v, nil)

	-- 持続がすでに見えていたら、その始まりから数える (上書きしない)。
	fresh()
	pose(0x0C, 0x02) tick(1, 0, 0, nil)
	mem[BASE + 0x12D] = 0x00
	pose(0x00, 0x00, 0x02) tick(4, 0, 0, nil)
	pose(0x00, 0x02, 0x02) tick(5, 0, 0, "p1_gc_begin")
	want("見えていた持続は始まりから", gct_state.rows[1] and gct_state.rows[1].v, 4)

	-- 一度使った値は次のガード行に付かない (連続ガードの 2 発目は硬直中のガード)。
	fresh()
	pose(0x0C, 0x02) tick(1, 0, 0, nil)
	pose(0x00, 0x02, 0x02) tick(3, 0, 0, "p1_gc_begin")   -- 1 発目: 持続 2
	pose(0x00, 0x02, 0x02) tick(4, 0, 0, "p1_gc_ended")   -- 受付が閉じた
	pose(0x00, 0x02, 0x02) tick(5, 0, 0, "p1_gc_begin")   -- 2 発目 (まだ硬直中)
	want("2 発目は数字なし", gct_state.rows[#gct_state.rows] and gct_state.rows[#gct_state.rows].v, nil)
end

print("")
print("[C] ガード行は当たったティックに置く。受付が開いたティックではない")
do
	-- 当たりは P1 の処理の外から $05 02 / $06 00 / $07 00 として書かれ、受付の
	-- 時計 ($158 = 14) は P1 自身のガード処理 (0x023960) が次に P1 が動いたとき
	-- 入れる。このフックは P1 の処理の先頭なので、当たりは受付の 1 ティック前に
	-- 見える。受付と同じティックに入った → がガードの上に 0t で描かれ、前に
	-- 入れながらガードしたように読めた (本人、2026-09-25: G-Persist 5 (0t))。
	local function contact() pose(0x00, 0x00, 0x02) end   -- 当たった直後
	local function stun() pose(0x00, 0x02, 0x02) end      -- ガード処理が動いた後
	local function guard_row()
		for _, r in ipairs(gct_state.rows) do if r.k == "guard" then return r end end
	end

	-- 実機のスクリーンショットの形。持続 6 ティック目 (旧 G-Persist 5) で当たり、次のティックに → と受付。
	fresh()
	pose(0x0C, 0x00) tick(1, 0, 0, nil)
	pose(0x0C, 0x02) tick(4, 0, 0, nil)                    -- 離した
	pose(0x0C, 0x02) tick(8, 0, 0, nil)
	contact()        tick(9, 0, 0, nil)                    -- 持続 6 ティック目で当たった
	stun()           tick(10, 2, 2, "p1_gc_begin")         -- → と受付が同じティック
	stun()           tick(15, 2, 4, "p1_gc_in_progress")   -- ↓
	stun()           tick(20, 4, 6, "p1_gc_in_progress")   -- ↘
	stun()           tick(23, 0, 6, "p1_gc_success")       -- P
	want("ガードが → より上", kinds(), "guard,dir,dir,dir,btn")
	want("ガード行は当たったティック", gct_state.rows[1].t, 9)
	want("持続は 6 (離したティックが 1)", gct_state.rows[1].v, 6)
	want("→ は受付のティック", gct_state.rows[2].t, 10)
	want("Success は受付から数える (入力履歴の SUCCESS と同じ)",
		gct_state.at - gct_state.guard, 13)

	-- 当たったティックにレバーも入っていたら、同時はレバーが先。
	fresh()
	contact() tick(9, 2, 2, nil)                           -- → と当たりが同時
	stun()    tick(10, 2, 2, "p1_gc_begin")
	want("同時ならレバーが先", kinds(), "dir,guard")
	want("ガード行は 9", gct_state.rows[2].t, 9)

	-- 当たる前の方向はガードの上に残る。
	fresh()
	stun()    tick(5, 2, 2, nil)
	contact() tick(9, 2, 2, nil)
	stun()    tick(10, 2, 4, "p1_gc_begin")
	want("前の方向 / ガード / 後の方向", kinds(), "dir,guard,dir")
	want("硬直中の状態は当たりにしない", gct_state.rows[2].t, 9)

	-- 表示中の試行から持ち越した方向も、当たった後のものだけガードの下へ。
	fresh()
	tick(1,  0, 0, "p1_gc_begin")
	tick(5,  2, 2, "p1_gc_in_progress")
	tick(15, 2, 2, "p1_gc_ended")                          -- 受付切れ。コマンドは生きている
	tick(18, 2, 4, nil)
	contact() tick(19, 2, 4, nil)
	stun()    tick(20, 4, 6, "p1_gc_begin")
	want("持ち越し 2 つ / ガード / 受付のティックの方向", kinds(), "dir,dir,guard,dir")
	want("ガード行は 19", gct_state.rows[3].t, 19)

	-- 死んだコマンドの後のガード。死んだ印より上には行かない。
	fresh()
	tick(10, 2, 2, nil)
	tick(20, 0, 2, nil)                                    -- 時間切れ
	contact() tick(35, 0, 2, nil)
	stun()    tick(36, 2, 2, "p1_gc_begin")                -- 入れ直しと受付が同時
	want("死んだ印 / ガード / 入れ直し", kinds(), "dir,dead,guard,dir")
	want("ガード行は 35", gct_state.rows[3].t, 35)

	-- 当たりと受付の間にコマンドが切れたら、ガードは死んだ印より上。
	-- 下に置くと、ガードの数字が死んだ印から数えて 255t になる。
	fresh()
	tick(10, 2, 2, nil)
	contact() tick(34, 2, 2, nil)
	stun()    tick(35, 0, 2, nil)                          -- 当たった次のティックに切れた
	stun()    tick(36, 2, 2, "p1_gc_begin")
	want("ティック順: 方向 / ガード / 死んだ印 / 入れ直し", kinds(), "dir,guard,dead,dir")

	-- 当たりが見えなかったら受付のティック。同じティックの方向が先
	-- (これまで死んだコマンドの後だけガードが先になっていた)。
	fresh()
	tick(10, 2, 2, nil)
	tick(20, 0, 2, nil)
	stun() tick(36, 2, 2, "p1_gc_begin")
	want("当たりが無ければ同時扱いでレバーが先", kinds(), "dir,dead,dir,guard")
	want("ガード行は受付のティック", gct_state.rows[4].t, 36)

	-- 硬直が明けた当たりは、後のガードに使わない。
	fresh()
	contact()                 tick(4, 0, 0, nil)
	pose(0x00, 0x00, 0x00)    tick(20, 0, 0, nil)          -- 明けた
	stun()                    tick(30, 2, 2, "p1_gc_begin")
	want("古い当たりは使わない", guard_row() and guard_row().t, 30)

	-- 当たった直後の状態が 2 ティック続いても、最初のティック。
	fresh()
	contact() tick(8, 0, 0, nil)
	contact() tick(9, 0, 0, nil)
	stun()    tick(10, 2, 2, "p1_gc_begin")
	want("最初のティック", gct_state.rows[1].t, 8)

	-- 一度使った当たりは次の受付に使わない。
	fresh()
	contact() tick(9, 0, 0, nil)
	stun()    tick(10, 0, 0, "p1_gc_begin")
	stun()    tick(24, 0, 0, "p1_gc_ended")
	stun()    tick(25, 0, 0, nil)
	stun()    tick(26, 2, 2, "p1_gc_begin")
	want("2 回目の受付は自分のティック", guard_row() and guard_row().t, 26)
end

print("")
print("[M] 画面下の帯へ渡す、当たったティックの印")
do
	-- 帯の GC の印は受付が開いたティックで、ガードの判定はその 1 ティック前。
	-- 受付が開いたティックに「当たったティックと持続」を渡し、帯が 1 ティック前で
	-- 列を分けて印を出す (inputHistory の mark_guard_column)。
	fresh()
	pose(0x0C, 0x02) tick(3, 0, 0, nil)
	pose(0x00, 0x00, 0x02) tick(8, 0, 0, nil)             -- 持続 6 ティック目で当たった
	want("当たったティックにはまだ渡さない", gct_state.bar_mark, nil)
	pose(0x00, 0x02, 0x02) tick(9, 0, 0, "p1_gc_begin")
	local m = gct_state.bar_mark
	want("受付のティックに渡す", m ~= nil, true)
	want("当たったティック", m and m.seq, 8)
	want("持続", m and m.pers, 6)

	fresh()
	pose(0x0C, 0x00) tick(1, 0, 0, nil)
	pose(0x00, 0x00, 0x02) tick(2, 0, 0, nil)
	pose(0x00, 0x02, 0x02) tick(3, 0, 0, "p1_gc_begin")
	want("入れたままなら持続なし", gct_state.bar_mark and gct_state.bar_mark.pers, nil)
	want("それでも印は渡す", gct_state.bar_mark and gct_state.bar_mark.seq, 2)

	-- 当たりが見えなければ渡さない (受付の列そのものに印を重ねない)。
	fresh()
	pose(0x00, 0x02, 0x02) tick(3, 0, 0, "p1_gc_begin")
	want("当たりが無ければ nil", gct_state.bar_mark, nil)

	-- トレースがガードの行を足さない受付 (同じ試行の 2 回目) でも、帯には渡す。
	fresh()
	pose(0x00, 0x00, 0x02) tick(1, 0, 0, nil)
	pose(0x00, 0x02, 0x02) tick(2, 0, 0, "p1_gc_begin")
	pose(0x00, 0x02, 0x02) tick(5, 2, 2, "p1_gc_in_progress")
	pose(0x00, 0x02, 0x02) tick(16, 2, 2, "p1_gc_ended")
	pose(0x00, 0x02, 0x02) tick(17, 2, 2, nil)
	pose(0x00, 0x00, 0x02) tick(18, 2, 4, nil)             -- 硬直中の 2 発目
	pose(0x00, 0x02, 0x02) tick(19, 2, 4, "p1_gc_begin")
	want("2 回目の受付にも渡す", gct_state.bar_mark and gct_state.bar_mark.seq, 18)
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
