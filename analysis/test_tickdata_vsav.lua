-- THE RAM ADAPTER: WHICH BOX IS OUT THIS TICK.
--
-- The attack box is animation data and can be read (cel + 0x0A, 0 = none).
-- The throw box cannot: its id is a literal in the character's own script, so
-- the only thing that knows is the check at 0x029406 - which the ROM shows runs
-- every tick the throw is out (see the note in tickDataVsav.lua).
--
-- What this pins is the hook, the P1 filter, and that the flag is LATCHED
-- rather than time-stamped. The first attempt compared tick counters and the
-- hook and the capture do not run at the same point in a tick, so a 29 tick
-- throw reported one.
--
-- Run from the package root.
--   cd C:/fightcaVSAV-Debug/emulator/fbneo && lua5.1 analysis/test_tickdata_vsav.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local fails = 0
local function want(what, got, w)
	if got ~= w then
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(w) .. "]")
	else
		print("  ok " .. what)
	end
end

local ram = {}
local hooks = {}
local regs = {}
memory = {
	readbyte = function(a) return ram[a] or 0 end,
	readword = function(a) return ram[a] or 0 end,
	readdword = function(a) return ram[a] or 0 end,
	registerexec = function(pc, fn) hooks[pc] = fn end,
	getregister = function(n) return regs[n] or 0 end,
}

local P1, P2 = 0xFF8400, 0xFF8800
local vsav = dofile("scripts/tickDataVsav.lua")

want("投げ判定にフックした", type(hooks[0x029406]), "function")

ram[P1 + 0x1C] = 0x900000
ram[0x900000 + 0x0A] = 0
want("判定が無ければ false", vsav.capture(1).p1.attack_box, false)
ram[0x900000 + 0x0A] = 7
local s = vsav.capture(2)
want("攻撃判定は出る", s.p1.attack_box, true)
want("その id", s.p1.attack_box_id, 7)

-- 投げ。攻撃判定は無いが、検査が走っていれば出ている扱い。
ram[0x900000 + 0x0A] = 0
regs["m68000.a6"] = P1
hooks[0x029406]()
s = vsav.capture(3)
want("投げ判定も箱として出る", s.p1.attack_box, true)
want("投げ専用の id", s.p1.attack_box_id, 0x100)

-- 読んだら消える。次のティックに検査が無ければ消えている。
want("検査が無いティックでは消える", vsav.capture(4).p1.attack_box, false)

-- 持続のあいだ毎ティック検査が走る = 毎ティック出ている。
local out = 0
for _ = 1, 29 do
	hooks[0x029406]()
	if vsav.capture(0).p1.attack_box then out = out + 1 end
end
want("毎ティック検査があれば毎ティック出る", out, 29)

-- 相手 (P2) の投げは拾わない。
regs["m68000.a6"] = P2
hooks[0x029406]()
want("P2 の投げは拾わない", vsav.capture(5).p1.attack_box, false)

-- 攻撃判定があるときは、そちらの id が優先される。
ram[0x900000 + 0x0A] = 3
regs["m68000.a6"] = P1
hooks[0x029406]()
want("攻撃判定が優先", vsav.capture(6).p1.attack_box_id, 3)


-- 飛び道具は別オブジェクト。本体のセルには判定が無いので、そちらを見ないと
-- 技が丸ごと測れない (デミトリのデモンビリオン)。
local PROJ = 0xFF9400
local function spawn(slot, owner, box_id)
	local b = PROJ + slot * 0x100
	ram[b] = 0x0200            -- 有効
	ram[b + 0x04] = 0x02
	ram[b + 0x30] = owner % 0x10000
	ram[b + 0x1C] = 0x910000 + slot
	ram[0x910000 + slot + 0x0A] = box_id
	return b
end
local function despawn(slot) ram[PROJ + slot * 0x100] = 0 end

ram[0x900000 + 0x0A] = 0                      -- 本体には判定なし
spawn(3, P1, 5)
local s2 = vsav.capture(7)
want("飛び道具の判定を拾う", s2.p1.attack_box, true)
want("本体の id と混ざらない", s2.p1.attack_box_id, 0x205)

-- 相手の飛び道具は自分の技ではない。
despawn(3)
spawn(4, P2, 5)
want("相手の飛び道具は拾わない", vsav.capture(8).p1.attack_box, false)
despawn(4)

-- 本体に判定があるときは本体が優先。振っている技の最中に前の飛び道具が
-- 残っていても、測るのは振っているほう。
spawn(5, P1, 9)
ram[0x900000 + 0x0A] = 4
want("本体が優先", vsav.capture(9).p1.attack_box_id, 4)
despawn(5)
ram[0x900000 + 0x0A] = 0

-- ダッシュ状態と技 id。ダッシュ攻撃はダッシュ状態の中の技なので $06 は 0x14 の
-- まま変わらず、技が変わったことは技 id でしか分からない。
ram[P1 + 0x006] = 0x14
want("ダッシュ状態を見ている", vsav.capture(40).p1.dash, true)
ram[P1 + 0x006] = 0x0A
want("通常技はダッシュではない", vsav.capture(42).p1.dash, false)
-- どの技を描いているかはセルポインタそのもの。技の開始はこれが自分のスクリプト
-- を離れたティックで、判定 id はその中の 1 バイト。
ram[P1 + 0x1C] = 0x900000
want("セルポインタを生で持つ", vsav.capture(43).p1.cel, 0x900000)
ram[P1 + 0x1C] = 0x900018
want("動いたら追う", vsav.capture(44).p1.cel, 0x900018)

-- 空中の通常技。着地モーションをキャンセルできるのはこれだけで、有利はその
-- 着地の瞬間で測る。実測した 9 回の空中接触のうち 8 回が $06=0x06 (ジャンプ)、
-- 1 回が 0x0A (通常技)。0x0A だけを見ると 9 回中 1 回しか拾えない。
ram[P1 + 0x038] = 0x01
ram[P1 + 0x006] = 0x06
want("ジャンプ中の攻撃も空中通常技", vsav.capture(60).p1.air_normal, true)
ram[P1 + 0x006] = 0x0A
want("通常技の状態も空中通常技", vsav.capture(61).p1.air_normal, true)
-- 必殺技 / ES / EX の着地硬直は本物なのでキャンセルできない。
ram[P1 + 0x006] = 0x0E
want("必殺技は違う", vsav.capture(62).p1.air_normal, false)
ram[P1 + 0x006] = 0x10
want("ES も違う", vsav.capture(63).p1.air_normal, false)
ram[P1 + 0x006] = 0x12
want("EX も違う", vsav.capture(64).p1.air_normal, false)
-- 地上ならそもそも空中ではない。
ram[P1 + 0x038] = 0x00 ram[P1 + 0x006] = 0x0A
want("地上の通常技は違う", vsav.capture(65).p1.air_normal, false)

-- 技の名前と、それを見分ける鍵。$102 が強度 (0/2/4 = 弱中強)、$101 が 0 なら P、
-- そうでなければ K。連打キャンセルの解析で判っていた組で、実測でも 6 通りすべて
-- 出ている。
ram[P1 + 0x038] = 0x00
ram[P1 + 0x006] = 0x0A ram[P1 + 0x102] = 0x02 ram[P1 + 0x101] = 0x00
do
  local s = vsav.capture(70)
  want("中 P と名づける", s.p1.move_name, "MP")
  want("鍵も立つ", s.p1.move_key ~= 0, true)
end
ram[P1 + 0x102] = 0x04 ram[P1 + 0x101] = 0x02
want("大 K と名づける", vsav.capture(71).p1.move_name, "HK")
ram[P1 + 0x102] = 0x00 ram[P1 + 0x101] = 0x00
want("小 P と名づける", vsav.capture(72).p1.move_name, "LP")
-- 空中では $06 が 0x06 のままなので、技が出ているかは攻撃フラグで分ける。
ram[P1 + 0x006] = 0x06 ram[P1 + 0x038] = 0x01 ram[P1 + 0x105] = 0x00
do
  local s = vsav.capture(73)
  want("ただのジャンプは技ではない", s.p1.move_key, 0)
  want("名前も出ない", s.p1.move_name, nil)
end
ram[P1 + 0x105] = 0x01
want("ジャンプ攻撃は名づける", vsav.capture(74).p1.move_name, "LP")
-- ダッシュは攻撃フラグを自分で立てるが技ではない。ボタン名だけは持っておく
-- (ダッシュ攻撃はアニメで拾い、名前をここから取るため)。
ram[P1 + 0x006] = 0x14
do
  local s = vsav.capture(75)
  want("ダッシュは技ではない", s.p1.move_key, 0)
  want("ボタン名は持っている", s.p1.button_name, "LP")
end
-- 必殺技は $106 から名前を引く。charMoves が無いところでは種別だけ返す。
ram[P1 + 0x006] = 0x0E ram[P1 + 0x106] = 0x04
do
  local s = vsav.capture(76)
  want("必殺技の種別", s.p1.move_name, "SP")
  want("鍵は通常技と別", s.p1.move_key ~= 0, true)
end
ram[P1 + 0x006] = 0x12
want("EX の種別", vsav.capture(77).p1.move_name, "EX")

-- 登録簿があるときは名前を引く。表示名が付いていればそちらが勝つ。
-- ダッシュデモンクレイドルはゲームデータ上 "Dash DP" という別 id だが、
-- アクションステップには "Demon Cradle" しか無い (user, 2026-09-10)。
globals = globals or {}
globals.char_moves = { P1 = { all = {
  { value = 0x04, name = "Demon Cradle" },
  { value = 0x06, name = "Dash DP", display_name = "Demon Cradle" },
} } }
ram[P1 + 0x006] = 0x0E ram[P1 + 0x106] = 0x04
want("登録簿の名前を使う", vsav.capture(81).p1.move_name, "Demon Cradle")
ram[P1 + 0x106] = 0x06
want("表示名があればそちらを使う", vsav.capture(82).p1.move_name, "Demon Cradle")
ram[P1 + 0x106] = 0x08
want("登録簿に無ければ種別に落ちる", vsav.capture(83).p1.move_name, "SP")
-- アクションステップが別の名前を出す技は、行もそちらに合わせる。128 件中 32 件が
-- 食い違っていた (実測 2026-09-11)。seq_special_list がエディタの一覧そのもの。
seq_special_list = function(cid)
  if cid ~= 0x08 then return nil end
  return { { name = "Bricks", label = "Enma Seki" },
           { name = "Kienzan", label = "Kienzen" } }
end
ram[P1 + 0x382] = 0x08
globals.char_moves = { P1 = { all = {
  { value = 0x02, name = "Bricks" },
  { value = 0x04, name = "Oni Kubi" },
} } }
ram[P1 + 0x106] = 0x02
want("ステップの名前に合わせる", vsav.capture(84).p1.move_name, "Enma Seki")
ram[P1 + 0x106] = 0x04
want("ステップに無ければ登録簿の名前", vsav.capture(85).p1.move_name, "Oni Kubi")
-- キャラクターが変わったら引き直すこと。
ram[P1 + 0x382] = 0x01
ram[P1 + 0x106] = 0x02
want("別キャラなら登録簿の名前", vsav.capture(86).p1.move_name, "Bricks")
seq_special_list = nil
ram[P1 + 0x382] = 0x00
globals.char_moves = nil
ram[P1 + 0x106] = 0x04
-- 必殺技は単体で道筋を始められる。ジャンプやダッシュを経由しなくてよい。
want("必殺技だと分かる", vsav.capture(78).p1.special, true)
ram[P1 + 0x006] = 0x0A
want("通常技は違う", vsav.capture(79).p1.special, false)
ram[P1 + 0x006] = 0x14
want("ダッシュも違う", vsav.capture(80).p1.special, false)

-- どの状態が「行動」か。歩きは 0x00 のままなので入らない。
for _, st in ipairs({ 0x06, 0x0A, 0x0E, 0x10, 0x12, 0x14, 0x16 }) do
  ram[P1 + 0x006] = st
  want(string.format("$06=%02X は行動", st), vsav.capture(81).p1.action, true)
end
for _, st in ipairs({ 0x00, 0x02, 0x04, 0x08, 0x0C }) do
  ram[P1 + 0x006] = st
  want(string.format("$06=%02X は行動ではない", st), vsav.capture(82).p1.action, false)
end

-- ヒットとガードの見分けは相手の復帰の種別。ブロッククロックはどのトレースでも
-- 一度も動かなかった。
ram[P2 + 0x140] = 0x02
want("地上ガード", vsav.capture(83).p2.guarding, true)
ram[P2 + 0x140] = 0x12
want("もう一つのガード", vsav.capture(84).p2.guarding, true)
ram[P2 + 0x140] = 0x00
want("ヒット硬直はガードではない", vsav.capture(85).p2.guarding, false)
ram[P2 + 0x140] = 0x04
want("こちらもヒット硬直", vsav.capture(86).p2.guarding, false)

-- 歩きとしゃがみはレバー $125 から読む。$122 はボタンなので何も出なかった
-- (実測 859 行すべて 00)。$125 のビットは向きに対する相対なので、向きを見る
-- 必要がない: bit0 が前、bit1 が後ろ、bit2 が下。
ram[P1 + 0x005] = 0x00 ram[P1 + 0x006] = 0x00 ram[P1 + 0x038] = 0x00
ram[P1 + 0x125] = 0x01
want("bit0 は前歩き", vsav.capture(90).p1.stance, "Walk")
-- 前後は画面上で逆に出たので区別をやめた (user, 2026-09-10)。どちらも Walk。
ram[P1 + 0x125] = 0x02
want("bit1 も歩き", vsav.capture(91).p1.stance, "Walk")
ram[P1 + 0x00B] = 0x01
want("向きを変えても同じ", vsav.capture(92).p1.stance, "Walk")
ram[P1 + 0x125] = 0x04
want("bit2 はしゃがみ", vsav.capture(93).p1.stance, "Crouch")
ram[P1 + 0x125] = 0x05
want("しゃがみ前もしゃがみ", vsav.capture(94).p1.stance, "Crouch")
ram[P1 + 0x125] = 0x00
want("中立なら何も無い", vsav.capture(95).p1.stance, nil)
-- ボタンの側を読んでいないこと。
ram[P1 + 0x122] = 0x07
want("ボタンでは歩かない", vsav.capture(96).p1.stance, nil)
ram[P1 + 0x122] = 0x00
-- 技の最中に前を握っていても歩きではない。
ram[P1 + 0x125] = 0x01 ram[P1 + 0x006] = 0x0A
want("技の最中は歩きではない", vsav.capture(97).p1.stance, nil)
ram[P1 + 0x006] = 0x00 ram[P1 + 0x038] = 0x01
want("空中でも歩きではない", vsav.capture(98).p1.stance, nil)

-- 歩きの $06 は 0x00 ではなく 0x04 (2026-09-10 実測)。0x04 の 580 ティック中
-- 569 でレバーが倒れていて、残る 11 は前の行動の尻尾。レバーを条件に残すこと
-- でその 11 を落とす。
ram[P1 + 0x038] = 0x00 ram[P1 + 0x006] = 0x04
ram[P1 + 0x125] = 0x01
want("歩きは $06=0x04", vsav.capture(99).p1.stance, "Walk")
ram[P1 + 0x125] = 0x02
want("後ろ歩きも $06=0x04", vsav.capture(100).p1.stance, "Walk")
ram[P1 + 0x125] = 0x00
want("0x04 でもレバー中立なら歩きではない", vsav.capture(101).p1.stance, nil)
ram[P1 + 0x125] = 0x01 ram[P1 + 0x038] = 0x01
want("0x04 でも空中なら歩きではない", vsav.capture(102).p1.stance, nil)
ram[P1 + 0x038] = 0x00 ram[P1 + 0x005] = 0x02
want("やられ中は 0x04 でも歩きではない", vsav.capture(103).p1.stance, nil)
ram[P1 + 0x005] = 0x00
-- 0x04 は「自由」ではない。道筋の終わりは $06 == 0x00 のまま。
want("歩きは free ではない", vsav.capture(104).p1.free, false)
ram[P1 + 0x006] = 0x00 ram[P1 + 0x125] = 0x00

-- $1B8 は「攻撃を始めた回数」。連打キャンセルで同じ小 P が始め直されたときも
-- ROM (0x028F18) がここを 1 増やすので、鍵が変わらなくても 2 本目だと分かる。
ram[P1 + 0x1B8] = 0x0007
want("$1B8 をそのまま渡す", vsav.capture(110).p1.attack_seq, 0x0007)
ram[P1 + 0x1B8] = 0x0008
want("増えれば増える", vsav.capture(111).p1.attack_seq, 0x0008)
ram[P1 + 0x1B8] = 0

-- 道筋の節目。$06 と $38 と $05 から、actionRoute が読む真偽値を作る。
ram[P1 + 0x005] = 0x00 ram[P1 + 0x006] = 0x06 ram[P1 + 0x038] = 0x00
do
  local s = vsav.capture(50)
  want("ジャンプ状態", s.p1.jump_state, true)
  want("まだ地上", s.p1.airborne, false)
  want("自由ではない", s.p1.free, false)
end
ram[P1 + 0x038] = 0x01
want("離陸を拾う", vsav.capture(51).p1.airborne, true)
ram[P1 + 0x005] = 0x00 ram[P1 + 0x006] = 0x00 ram[P1 + 0x038] = 0x00
do
  local s = vsav.capture(52)
  want("両方 0 で自由", s.p1.free, true)
  want("ジャンプ状態ではない", s.p1.jump_state, false)
end
ram[P1 + 0x005] = 0x02
want("やられを拾う", vsav.capture(53).p1.stunned, true)
-- ヒットストップは値そのもの。増加を見るために要る。
ram[P2 + 0x05C] = 0x0B
do
  local s = vsav.capture(54)
  want("ヒットストップの値", s.p2.hitstop, 0x0B)
  want("真偽値も残っている", s.p2.hitfreeze, true)
end
ram[P2 + 0x05C] = 0x00
want("0 なら false", vsav.capture(55).p2.hitfreeze, false)

-- === どちらの側を測るか ===
--
-- スナップショットの p1 / p2 は「測る側」と「相手側」であって、プレイヤー 1 と
-- 2 ではない。tickData.lua と actionRoute.lua はアドレス参照がゼロなので、側を
-- 持っているのはこのファイルだけ - ここが通れば道筋も測定も両側で動く。
want("既定は P1", vsav.side(), "P1")
want("同じ側を指しても倒れない", vsav.set_side("P1"), false)

-- 掃除してから見分けのつく値を入れる。片方が漏れたら分かるようにする。
local function clear(b)
	for _, off in ipairs({ 0x005, 0x006, 0x01C, 0x020, 0x038, 0x05C, 0x101,
	                       0x102, 0x105, 0x106, 0x122, 0x125, 0x140, 0x158,
	                       0x1A7, 0x1B8, 0x382 }) do
		ram[b + off] = 0
	end
end
clear(P1) clear(P2)

want("P2 へ倒すと倒れたと答える", vsav.set_side("P2"), true)
want("倒したあとは P2", vsav.side(), "P2")
want("二度目は倒れない", vsav.set_side("P2"), false)

-- 測る側は P2 を読む。P1 に別の値を置いても漏れてこない。
ram[P2 + 0x006] = 0x14
ram[P1 + 0x006] = 0x0A
want("測る側は P2 の $06", vsav.capture(200).p1.dash, true)

-- 相手側は P1 を読む。有利不利は「相手が何をされたか」なので、ここが入れ替わら
-- ないと測定そのものが成り立たない。
ram[P1 + 0x05C] = 0x0B
ram[P2 + 0x05C] = 0x00
do
	local s = vsav.capture(201)
	want("相手側は P1 のヒットストップ", s.p2.hitstop, 0x0B)
	want("測る側は自分のヒットストップを見る", s.p1.hitfreeze, false)
end
ram[P1 + 0x05C] = 0

-- 投げフックは A6 が測る側かどうかで決める。登録はモジュール読み込み時の一度
-- きりなので、側を定数のまま閉じ込めているとここで落ちる。
ram[P2 + 0x01C] = 0x920000
ram[0x920000 + 0x0A] = 0
regs["m68000.a6"] = P1
hooks[0x029406]()
want("測っていない側の投げは拾わない", vsav.capture(202).p1.attack_box, false)
regs["m68000.a6"] = P2
hooks[0x029406]()
want("P2 の投げを拾う", vsav.capture(203).p1.attack_box_id, 0x100)

-- 飛び道具の持ち主も倒れる。$30 が測る側なら自分の技。
spawn(6, P2, 5)
want("P2 の飛び道具を拾う", vsav.capture(204).p1.attack_box_id, 0x205)
despawn(6)
spawn(7, P1, 5)
want("測っていない側の飛び道具は拾わない", vsav.capture(205).p1.attack_box, false)
despawn(7)

-- 技の名前は P2 のキャラクターと P2 の登録簿から引く。両側に別の技を置いて
-- おき、どちらを引いたかで判る形にする。
seq_special_list = function(cid)
	if cid ~= 0x08 then return nil end
	return { { name = "Bricks", label = "Enma Seki" } }
end
globals.char_moves = {
	P1 = { all = { { value = 0x02, name = "Chaos Flare" } } },
	P2 = { all = { { value = 0x02, name = "Bricks" } } },
}
ram[P1 + 0x382] = 0x01
ram[P2 + 0x382] = 0x08
ram[P2 + 0x006] = 0x0E
ram[P2 + 0x106] = 0x02
want("P2 の登録簿とキャラクターから引く", vsav.capture(206).p1.move_name, "Enma Seki")

-- 戻せること。
want("P1 へ戻すと倒れる", vsav.set_side("P1"), true)
want("戻したら P1", vsav.side(), "P1")
ram[P1 + 0x006] = 0x0E
ram[P1 + 0x106] = 0x02
want("戻したら P1 の登録簿", vsav.capture(207).p1.move_name, "Chaos Flare")
seq_special_list = nil
globals.char_moves = nil

if fails == 0 then print("全て通った") else print(fails .. " 件 NG") os.exit(1) end
