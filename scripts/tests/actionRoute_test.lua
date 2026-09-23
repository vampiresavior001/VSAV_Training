-- 道筋の状態機械。合成スナップショットを流して、出来事とその時刻を照合する。
--
-- 数字は作り話ではなく、2026-09-08 と 09 の routeProbe のトレースから起こして
-- いる。ログの 1 本を 1 テストにしてあるので、実測が変われば期待値も変わる。
--
--   lua5.1 scripts/tests/actionRoute_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
local ar = require "scripts/actionRoute"
local passed = 0
local function eq(a, b, n)
  if a ~= b then error(n .. ": expected " .. tostring(b) .. ", got " .. tostring(a)) end
end

-- 省略した項目は「前のティックのまま」。変えたいものだけ書く。
-- key は「今どの技が出ているか」の鍵で、0 は何も出ていない。name はその表示。
local function snap(t, o)
  return { tick = t,
    p1 = { free = o.free or false, stunned = o.stunned or false,
           jump_state = o.jump or false, airborne = o.air or false,
           dash = o.dash or false, attack = o.atk or 0,
           attack_box = o.box or false, cel = o.cel or 0,
           -- ジャンプもダッシュも必殺技も「行動」。個別に書かなくても立つ。
           action = (o.action or o.special or o.jump or o.dash) or false,
           move_key = o.key or 0, move_name = o.name,
           -- $1B8: how many attacks the game has started. Same button twice
           -- keeps one key, so this is what says a second one began.
           attack_seq = o.seq or 0,
           -- Lua の pairs は nil の項目を飛ばすので、消したいときは false を書く。
           button_name = o.button or "LP", stance = o.stance or nil },
    p2 = { status = o.p2 or 0, block_clock = o.bc or 0, hitstop = o.hs or 0,
           guarding = o.guard or false } }
end

-- events は {ティック, 変わったもの} の並び。間のティックは前の状態が続く。
local function feed(events, last)
  ar.reset("test", true)
  local by_tick = {}
  for _, e in ipairs(events) do by_tick[e[1]] = e[2] end
  local st = {}
  for t = 0, last do
    local ch = by_tick[t]
    if ch then for k, v in pairs(ch) do st[k] = v end end
    ar.update(snap(t, st))
  end
  return ar.getResult()
end

local function test(name, fn) fn() passed = passed + 1 print("ok " .. name) end

-- 実測 (ログの 2 本目のジャンプ攻撃): 離陸 +4 中 P +29 ヒット +34 着地 +52。
-- 1 起点なので画面では 5t / 30t / 35t / 53t。
test("ジャンプ攻撃は時刻で並ぶ", function()
  local r = feed({
    { 0,   { free = true } },
    { 10,  { free = false, jump = true } },
    { 14,  { air = true } },
    { 39,  { atk = 1, key = 0x10200, name = "MP" } },
    { 43,  { box = true } },
    { 44,  { p2 = 2, hs = 11 } },
    { 49,  { box = false } },
    { 62,  { air = false } },
    { 90,  { free = true, jump = false, atk = 0, key = 0 } },
  }, 110)
  eq(ar.formatResult(),
    "1t PreJump >  5t Air >  30t MP >  35t Hit >  53t Landing >  81t Free", "1 行")
  eq(r.contact_at, 35, "接触の時刻")
  eq(r.total, 81, "全長")
end)

-- 実測 (ザベルの空中ダッシュ攻撃): 離陸 +3 空中ダッシュ +29 技 +43 着地 +59。
test("空中ダッシュは上昇とダッシュの両方が出る", function()
  local r = feed({
    { 0,  { free = true } },
    { 10, { free = false, jump = true } },
    { 13, { air = true } },
    { 39, { dash = true, atk = 1 } },
    { 53, { key = 0x10400, name = "HP" } },
    { 57, { box = true } },
    { 69, { air = false, box = false } },
    { 77, { free = true, jump = false, dash = false, atk = 0, key = 0 } },
  }, 100)
  eq(ar.formatResult(),
    "1t PreJump >  4t Air >  30t Dash >  44t HP >  60t Landing >  68t Free", "1 行")
end)

-- ダッシュ攻撃は $06 が 0x14 のままで、強度のバイトも動かない。名前が変わらない
-- ので、アニメが自分のスクリプトを離れた瞬間を技の始まりとし、名前はボタンから
-- 取る。実測 (空振りのダッシュ小 P): 技 +7 判定 +9 終点 +19。
test("ダッシュ攻撃はアニメの飛びで拾い、ボタンで名づける", function()
  local r = feed({
    { 0,  { free = true, cel = 0x1000 } },
    { 10, { free = false, dash = true, atk = 1, cel = 0x1000, button = "LP" } },
    { 13, { cel = 0x1018 } },
    { 15, { cel = 0x1030 } },
    { 17, { cel = 0x9000 } },
    { 19, { box = true, cel = 0x9018 } },
    { 22, { box = false, cel = 0x9030 } },
    { 29, { free = true, dash = false, atk = 0 } },
  }, 50)
  eq(ar.formatResult(), "1t Dash >  8t LP >  20t Free", "1 行")
end)

-- ダッシュのアニメはループもする。デミトリのダッシュがそれで、表では 攻撃前 が
-- "-" つまりダッシュから技が出せないのに 13t HK と出ていた。判定が一度も出て
-- いなければ、それは技ではない。
test("判定の出ないダッシュの飛びは技ではない", function()
  local r = feed({
    { 0,  { free = true, cel = 0x1000 } },
    { 10, { free = false, dash = true, atk = 1, cel = 0x1000, button = "HK" } },
    { 13, { cel = 0x1018 } },
    { 22, { cel = 0x1000 } },                  -- アニメが先頭へ戻る (ループ)
    { 25, { cel = 0x1018 } },
    { 49, { free = true, dash = false, atk = 0 } },
  }, 70)
  eq(ar.formatResult(), "1t Dash >  40t Free", "技は出ていない")
end)

-- 判定が出れば技。空振りでも箱は出るので、当たったかどうかとは関係ない。
test("判定が出れば飛びは技", function()
  local r = feed({
    { 0,  { free = true, cel = 0x1000 } },
    { 10, { free = false, dash = true, atk = 1, cel = 0x1000, button = "LP" } },
    { 17, { cel = 0x9000 } },
    { 19, { box = true, cel = 0x9018 } },
    { 22, { box = false, cel = 0x9030 } },
    { 29, { free = true, dash = false, atk = 0 } },
  }, 50)
  eq(ar.formatResult(), "1t Dash >  8t LP >  20t Free", "1 行")
end)

-- 0x18 ちょうどの前進は同じアニメの続き。これを飛びと読むと、ダッシュのアニメが
-- 1 コマ進んだだけで技が出たことになる。
test("0x18 ちょうどは技ではない", function()
  local r = feed({
    { 0,  { free = true, cel = 0x1000 } },
    { 10, { free = false, dash = true, atk = 1, cel = 0x1000 } },
    { 13, { cel = 0x1018 } },
    { 15, { cel = 0x1030 } },
    { 25, { free = true, dash = false, atk = 0 } },
  }, 45)
  eq(ar.formatResult(), "1t Dash >  16t Free", "技は出ていない")
end)

-- 空中で 2 つ出したら 2 つ並ぶ。区間で書いていたころは 1 つしか選べなかった。
test("1 回のジャンプで 2 つ出したら 2 つ並ぶ", function()
  local r = feed({
    { 0,  { free = true } },
    { 10, { free = false, jump = true } },
    { 13, { air = true } },
    { 25, { atk = 1, key = 0x10200, name = "MP" } },
    { 29, { box = true } },
    { 30, { p2 = 2, hs = 11 } },
    { 40, { box = false, key = 0x20E04, name = "Soul Fist" } },
    { 43, { hs = 0 } },                        -- 前のヒットストップが切れる
    { 45, { box = true } },
    { 46, { hs = 11 } },
    { 55, { air = false, box = false } },
    { 65, { free = true, jump = false, atk = 0, key = 0 } },
  }, 85)
  eq(ar.formatResult(),
    "1t PreJump >  4t Air >  16t MP >  21t Hit >  31t Soul Fist >  37t Hit >  46t Landing >  56t Free",
    "1 行")
end)

-- 多段技でも接触は 1 回だけ。欲しいのは「何を何ティックで当てたか」で、当たり
-- 続けた回数ではない (ES デモンクレイドルが 9 回の Hit で行を埋めた)。回数は
-- 1 行目の Active の並びに出ている。
test("多段でも接触は 1 回だけ", function()
  local r = feed({
    { 0,  { free = true } },
    { 10, { free = false, jump = true } },
    { 13, { air = true } },
    { 25, { atk = 1, key = 0x10402, name = "HK" } },
    { 30, { box = true } },
    { 31, { p2 = 2, hs = 11 } },
    { 40, { hs = 0 } },
    { 41, { hs = 11 } },
    { 55, { air = false, box = false } },
    { 65, { free = true, jump = false, atk = 0, key = 0 } },
  }, 85)
  eq(ar.formatResult(),
    "1t PreJump >  4t Air >  16t HK >  22t Hit >  46t Landing >  56t Free",
    "1 行")
end)

-- 技が変われば接触もまた 1 回出る。「1 技に 1 回」であって「1 道筋に 1 回」では
-- ない。
test("技が変われば接触もまた出る", function()
  local r = feed({
    { 0,  { free = true } },
    { 10, { free = false, jump = true } },
    { 13, { air = true } },
    { 25, { atk = 1, key = 0x10200, name = "MP" } },
    { 29, { box = true } },
    { 30, { p2 = 2, hs = 11 } },
    { 33, { hs = 0 } },
    { 34, { hs = 11 } },                       -- 同じ技の 2 発目。出ない
    { 40, { box = false, key = 0x10402, name = "HK" } },
    { 43, { hs = 0 } },
    { 45, { box = true } },
    { 46, { hs = 11 } },                       -- 別の技なので出る
    { 55, { air = false, box = false } },
    { 65, { free = true, jump = false, atk = 0, key = 0 } },
  }, 85)
  eq(ar.formatResult(),
    "1t PreJump >  4t Air >  16t MP >  21t Hit >  31t HK >  37t Hit >  46t Landing >  56t Free",
    "1 行")
end)

-- 判定はその技のものでなければならない。ダッシュの序盤に出た幽霊が、40 ティック
-- 後の本物の判定で生き延びていた。
test("あとの技の判定では生き延びない", function()
  local r = feed({
    { 0,  { free = true, cel = 0x1000 } },
    { 10, { free = false, dash = true, atk = 1, cel = 0x1000, button = "HK" } },
    { 17, { cel = 0x5000 } },                  -- ループ。幽霊
    { 20, { cel = 0x5018 } },
    { 50, { dash = false, key = 0x20E04, name = "Demon Cradle" } },
    { 54, { box = true } },                    -- 判定は必殺技のもの
    { 60, { box = false } },
    { 80, { free = true, atk = 0, key = 0 } },
  }, 100)
  eq(ar.formatResult(), "1t Dash >  41t Demon Cradle >  71t Free", "1 行")
end)

-- 立ち通常技も 1 つの行動。ジャンプやダッシュを経由しなくても道筋になる。
test("立ち通常技だけでも道筋になる", function()
  local r = feed({
    { 0,  { free = true } },
    { 10, { free = false, action = true, atk = 1, key = 0x10200, name = "MP" } },
    { 15, { box = true } },
    { 16, { p2 = 2, hs = 11 } },
    { 20, { box = false } },
    { 40, { free = true, action = false, atk = 0, key = 0 } },
  }, 60)
  eq(ar.formatResult(), "1t MP >  7t Hit >  31t Free", "1 行")
end)

-- チェーンは 1 本の道筋に並ぶ。隙間を許すので、繋いだぶんが 1 行になる。
test("チェーンは 1 本に並ぶ", function()
  local r = feed({
    { 0,  { free = true } },
    { 10, { free = false, action = true, atk = 1, key = 0x10000, name = "LP" } },
    { 14, { box = true } },
    { 15, { p2 = 2, hs = 11 } },
    { 20, { box = false, key = 0x10002, name = "LK" } },
    { 23, { hs = 0 } },
    { 24, { box = true } },
    { 25, { hs = 11 } },
    { 30, { box = false } },
    { 50, { free = true, action = false, atk = 0, key = 0 } },
  }, 70)
  eq(ar.formatResult(),
    "1t LP >  6t Hit >  11t LK >  16t Hit >  41t Free", "1 行")
end)

-- 相手の復帰の種別 ($140) は、やられに入るのと同じティックに書かれるとは
-- 限らない。チェーンの初段だけ Hit と出ていたのはこれ。1 ティックだけ待って
-- 直す。本当に当たっていたなら、そのあとガードに変わることはない。
test("ガードの判定は 1 ティック遅れても拾う", function()
  local r = feed({
    { 0,  { free = true } },
    { 10, { free = false, action = true, atk = 1, key = 0x10000, name = "LP" } },
    { 14, { box = true } },
    { 15, { p2 = 2, hs = 11 } },              -- 接触。$140 はまだ 0
    { 16, { guard = true } },                 -- 1 ティック遅れてガードと分かる
    { 40, { free = true, action = false, atk = 0, key = 0 } },
  }, 60)
  local found = nil
  for _, e in ipairs(r.events) do if e.kind == "contact" then found = e.text end end
  eq(found, "Guard", "接触の種別")
end)

-- 本当に当たったなら、そのあとガードに変わることはない。
test("当たったものは 1 ティック後も Hit のまま", function()
  local r = feed({
    { 0,  { free = true } },
    { 10, { free = false, action = true, atk = 1, key = 0x10000, name = "LP" } },
    { 14, { box = true } },
    { 15, { p2 = 2, hs = 11 } },
    { 40, { free = true, action = false, atk = 0, key = 0 } },
  }, 60)
  local found = nil
  for _, e in ipairs(r.events) do if e.kind == "contact" then found = e.text end end
  eq(found, "Hit", "接触の種別")
end)

-- 小技をガードさせてからの投げ。1 技 1 回の規則と、投げの最中は技を出さない
-- 規則がぶつかって、投げが消えていた。掴みは「同じ技がまた当たった」ではない。
test("ガードさせてからの投げも出る", function()
  local r = feed({
    { 0,  { free = true } },
    { 10, { free = false, action = true, atk = 1, key = 0x10000, name = "LP" } },
    { 14, { box = true } },
    { 15, { p2 = 2, hs = 11, guard = true } },
    { 20, { box = false } },
    { 30, { p2 = 6 } },                        -- 掴んだ
    { 60, { p2 = 0 } },
    { 70, { free = true, action = false, atk = 0, key = 0 } },
  }, 90)
  eq(ar.formatResult(),
    "1t LP >  6t Guard >  21t Throw >  61t Free", "1 行")
end)

-- 立ちからの投げ。掴みは相手側で見えるので、投げ手の状態が行動になるのを
-- 待たずに道筋を開ける。
test("投げだけでも道筋が始まる", function()
  local r = feed({
    { 0,  { free = true } },
    { 10, { p2 = 6 } },                        -- 掴んだ。こちらの状態はまだ中立
    { 11, { free = false } },                  -- 1 ティック遅れて投げの動作へ
    { 40, { p2 = 0 } },
    { 50, { free = true } },
  }, 80)
  eq(ar.formatResult(), "1t Throw >  41t Free", "1 行")
end)

-- 投げのアニメは投げ。投げはボタンで入るので、そのアニメを技として名づけると
-- 「空ジャンプして投げただけ」が 47t Throw > 51t HP > 104t HP と出る。掴んだ
-- ことは行に出ているし、離すまで他は始められない。
test("投げの最中は技を出さない", function()
  local r = feed({
    { 0,  { free = true } },
    { 10, { free = false, jump = true } },
    { 13, { air = true } },
    { 55, { air = false } },                   -- 着地
    { 56, { p2 = 6 } },                        -- 掴んだ
    { 60, { key = 0x10400, name = "HP" } },    -- 投げのアニメ。技ではない
    -- 蹴り投げは掴んだ相手を先に離す。離したあとのアニメも投げの続きで、
    -- そこを技と読むと 158t Throw > 293t MK > 293t Hit になっていた。
    { 100,{ p2 = 0 } },
    { 113,{ key = 0x10402, name = "HK" } },
    { 115,{ p2 = 2, hs = 11 } },
    { 120,{ key = 0 } },
    { 130,{ free = true, jump = false } },
  }, 150)
  eq(ar.formatResult(),
    "1t PreJump >  4t Air >  46t Landing >  47t Throw >  121t Free", "1 行")
end)

-- 攻撃しないジャンプも道筋を出す。実測: 離陸 +4 着地 +41 終点 +49。
test("攻撃しないジャンプも出る", function()
  local r = feed({
    { 0,  { free = true } },
    { 10, { free = false, jump = true } },
    { 14, { air = true } },
    { 51, { air = false } },
    { 59, { free = true, jump = false } },
  }, 80)
  eq(ar.formatResult(), "1t PreJump >  5t Air >  42t Landing >  50t Free", "1 行")
  eq(r.contact_at, nil, "接触なし")
end)

-- やられ中の相手に当てても $05 のエッジは立たない。ヒットストップの跳ね上がりが
-- 唯一の合図で、これが無いとコンボ中の飛び込みで接触が出ない。
test("やられ中の相手への接触はヒットストップで拾う", function()
  local r = feed({
    { 0,  { free = true, p2 = 2 } },
    { 10, { free = false, jump = true } },
    { 12, { air = true } },
    { 34, { atk = 1, key = 0x10200, name = "MP" } },
    { 39, { box = true } },
    { 40, { hs = 11 } },
    { 84, { air = false } },
    { 180,{ free = true, jump = false, atk = 0, key = 0 } },
  }, 200)
  eq(r.contact_at, 31, "接触の時刻")
end)

-- ブロッククロックはどのトレースでも一度も動かなかったので、ガードがヒット
-- ストップ側に落ちて Hit と出ていた。種別は相手の復帰の種別 ($140) で決める。
test("ガードは Guard と出る", function()
  local r = feed({
    { 0,  { free = true } },
    { 10, { free = false, jump = true } },
    { 12, { air = true } },
    { 34, { atk = 1, key = 0x10200, name = "MP" } },
    { 39, { box = true } },
    { 40, { hs = 11, guard = true } },      -- ブロッククロックは動かない
    { 84, { air = false } },
    { 180,{ free = true, jump = false, atk = 0, key = 0 } },
  }, 200)
  local found = nil
  for _, e in ipairs(r.events) do if e.kind == "contact" then found = e.text end end
  eq(found, "Guard", "接触の種別")
end)

-- 踏み切りを潰されたら、そこまでの数字は誰もやっていない行動のもの。
test("途中で食らったら捨てる", function()
  feed({
    { 0,  { free = true } },
    { 10, { free = false, jump = true } },
    { 12, { air = true } },
    { 40, { free = true, jump = false } },
  }, 60)
  local old = ar.getResult()
  ar.update(snap(61, { free = true }))
  ar.update(snap(62, { free = false, jump = true }))
  ar.update(snap(63, { jump = true, stunned = true }))
  eq(ar.getResult(), old, "前の読みのまま")
  eq(ar.getAbortReason(), "attacker_hit", "理由")
end)

-- 歩きとしゃがみも道筋に乗る。$06 は 0x00 のままなので、レバーから読む。
test("歩きも道筋になり、技まで繋がる", function()
  local r = feed({
    { 0,  { free = true } },
    { 10, { free = true, stance = "Walk" } },
    { 30, { stance = false, action = true, free = false, atk = 1,
            key = 0x10200, name = "MP" } },
    { 35, { box = true } },
    { 36, { p2 = 2, hs = 11 } },
    { 60, { free = true, action = false, atk = 0, key = 0 } },
  }, 80)
  eq(ar.formatResult(), "1t Walk >  21t MP >  27t Hit >  51t Free", "1 行")
end)

-- 歩いているあいだは道筋が閉じない。$05 と $06 は 0 なので、そのままだと
-- 10 ティックで自分の道筋を締めてしまう。
test("歩いている間は締まらない", function()
  local r = feed({
    { 0,  { free = true } },
    { 10, { free = true, stance = "Walk" } },
    { 60, { stance = false } },
  }, 90)
  eq(ar.formatResult(), "1t Walk >  51t Free", "1 行")
end)

-- しゃがみは下が優先。しゃがみ前でもしゃがみ。
test("しゃがみも出る", function()
  local r = feed({
    { 0,  { free = true } },
    { 10, { free = true, stance = "Crouch" } },
    { 20, { stance = "Walk" } },               -- 立って歩き出す
    { 40, { stance = false } },
  }, 70)
  eq(ar.formatResult(), "1t Crouch >  11t Walk >  31t Free", "1 行")
end)

-- 歩きは道筋を持たない。$06 が 0x00 のまま動かないので、行動として立たない。
test("行動でなければ始まらない", function()
  local r = feed({
    { 0,  { free = true } },
    { 10, { free = false } },
    { 30, { free = true } },
  }, 50)
  eq(r, nil, "読みは出ない")
end)

test("ティックが飛んだら捨てる", function()
  ar.reset("test", true)
  ar.update(snap(0, { free = true }))
  ar.update(snap(1, { free = false, jump = true }))
  eq(ar.update(snap(3, { jump = true })), "aborted", "状態")
  eq(ar.getAbortReason(), "tick_discontinuity", "理由")
end)

-- 隙間は行動の終わりとは限らない。ザベルのダッシュコマ投げはダッシュから抜ける
-- 途中で一度中立を通るので、最初の中立で締めると投げが行から落ちる。
test("短い隙間なら道筋は続く", function()
  local r = feed({
    { 0,  { free = true, cel = 0x1000 } },
    { 10, { free = false, dash = true, atk = 1, cel = 0x1000 } },
    { 20, { free = true, dash = false, atk = 0 } },      -- 一瞬だけ中立
    { 26, { free = false, key = 0x20E0E, name = "Death Voltage" } },
    { 32, { p2 = 6 } },                                   -- 投げが成立
    { 60, { free = true, key = 0 } },
  }, 80)
  eq(ar.formatResult(),
    "1t Dash >  17t Death Voltage >  23t Throw >  51t Free", "1 行")
end)

-- 10 ティック開いたらそこで終わり。終点は「最初に中立になったティック」で、
-- 待ったぶんは足されない。
test("10 ティック空いたら終わる", function()
  local r = feed({
    { 0,  { free = true, cel = 0x1000 } },
    { 10, { free = false, dash = true, atk = 1, cel = 0x1000 } },
    { 20, { free = true, dash = false, atk = 0 } },
    { 40, { free = false, key = 0x20E0E, name = "Death Voltage" } },
    { 70, { free = true, key = 0 } },
  }, 90)
  eq(ar.formatResult(), "1t Dash >  11t Free", "ダッシュだけで終わる")
end)

-- 必殺技は単体でも道筋を持つ。ジャンプやダッシュを経由しなくてよい。
test("必殺技だけでも道筋になる", function()
  local r = feed({
    { 0,  { free = true } },
    { 10, { free = false, special = true, atk = 1, key = 0x20E04,
            name = "Soul Fist" } },
    { 22, { box = true } },
    { 23, { p2 = 2, hs = 11 } },
    { 50, { free = true, special = false, atk = 0, key = 0 } },
  }, 70)
  eq(ar.formatResult(), "1t Soul Fist >  14t Hit >  41t Free", "1 行")
end)

-- 実測 (2026-09-10 のトレース、ザベルの立ち小 P を 3 回連打キャンセル)。ログを
-- そのまま流し直すと 3 本とも 1t LP > 5t Hit > 17t LP > 21t Hit の形になった。
-- $1B8 はセッション中 8 回増え、うち 3 回が $11A=FF (連打として受理された分)。
test("実測の連打キャンセル 1 本", function()
  feed({
    { 0,  { free = true } },
    { 9,  { free = false, action = true, atk = 1, key = 0x10000, name = "LP",
            seq = 3 } },
    { 12, { box = true } },
    { 13, { p2 = 2, hs = 11 } },
    { 17, { box = false, p2 = 0, hs = 0 } },
    { 25, { seq = 4 } },
    { 28, { box = true } },
    { 29, { p2 = 2, hs = 11 } },
    { 33, { box = false, p2 = 0, hs = 0 } },
    { 47, { free = true, action = false, atk = 0, key = 0 } },
  }, 80)
  eq(ar.formatResult(),
    "1t LP >  5t Hit >  17t LP >  21t Hit >  39t Free", "1 行")
end)

-- 連打キャンセル。小 P から同じ小 P へ入ると鍵は変わらないので、$1B8 (ゲームが
-- 攻撃を始めた回数) が 2 本目の始まりを言う。ROM では 0x028F18 で加算される。
test("連打キャンセルは同じ名前で 2 つ並ぶ", function()
  feed({
    { 0,  { free = true } },
    { 9,  { free = false, action = true, atk = 1, key = 0x10000, name = "LP",
            seq = 1 } },
    { 13, { box = true } },
    { 14, { p2 = 2, hs = 11 } },
    { 18, { box = false, p2 = 0, hs = 0 } },
    { 29, { seq = 2 } },
    { 33, { box = true } },
    { 34, { p2 = 2, hs = 11 } },
    { 38, { box = false, p2 = 0, hs = 0 } },
    { 50, { free = true, action = false, atk = 0, key = 0 } },
  }, 80)
  eq(ar.formatResult(),
    "1t LP >  6t Hit >  21t LP >  26t Hit >  42t Free", "1 行")
end)

test("3 回でも同じ形で続く", function()
  feed({
    { 0,  { free = true } },
    { 9,  { free = false, action = true, atk = 1, key = 0x10000, name = "LP",
            seq = 1 } },
    { 14, { p2 = 2, hs = 11 } },
    { 18, { p2 = 0, hs = 0 } },
    { 29, { seq = 2 } },
    { 34, { p2 = 2, hs = 11 } },
    { 38, { p2 = 0, hs = 0 } },
    { 47, { seq = 3 } },
    { 52, { p2 = 2, hs = 11 } },
    { 56, { p2 = 0, hs = 0 } },
    { 70, { free = true, action = false, atk = 0, key = 0 } },
  }, 100)
  eq(ar.formatResult(),
    "1t LP >  6t Hit >  21t LP >  26t Hit >  39t LP >  44t Hit >  62t Free",
    "1 行")
end)

-- 小 K をガードさせた場合。名前もヒットの種別も既存のまま。
test("小 K の連打はガードでも並ぶ", function()
  feed({
    { 0,  { free = true } },
    { 9,  { free = false, action = true, atk = 1, key = 0x10002, name = "LK",
            seq = 1 } },
    { 14, { p2 = 2, hs = 11, guard = true } },
    { 18, { p2 = 0, hs = 0 } },
    { 29, { seq = 2 } },
    { 34, { p2 = 2, hs = 11 } },
    { 38, { p2 = 0, hs = 0 } },
    { 50, { free = true, action = false, atk = 0, key = 0 } },
  }, 80)
  eq(ar.formatResult(),
    "1t LK >  6t Guard >  21t LK >  26t Guard >  42t Free", "1 行")
end)

-- 押しても受理されなければ $1B8 は動かない。何も足さない。
test("受理されなかった連打は増えない", function()
  feed({
    { 0,  { free = true } },
    { 9,  { free = false, action = true, atk = 1, key = 0x10000, name = "LP",
            seq = 1 } },
    { 14, { p2 = 2, hs = 11 } },
    { 18, { p2 = 0, hs = 0 } },
    { 50, { free = true, action = false, atk = 0, key = 0 } },
  }, 80)
  eq(ar.formatResult(), "1t LP >  6t Hit >  42t Free", "1 行")
end)

-- 自然な多段技は始め直していないので $1B8 は動かない。1 本のまま。
test("多段技は連打ではない", function()
  feed({
    { 0,  { free = true } },
    { 9,  { free = false, action = true, atk = 1, key = 0x20E01,
            name = "Soul Fist", seq = 1 } },
    { 14, { p2 = 2, hs = 11 } },
    { 18, { p2 = 0, hs = 0 } },
    { 24, { p2 = 2, hs = 11 } },
    { 28, { p2 = 0, hs = 0 } },
    { 50, { free = true, action = false, atk = 0, key = 0 } },
  }, 80)
  eq(ar.formatResult(), "1t Soul Fist >  6t Hit >  42t Free", "1 行")
end)

-- 別の技へのチェーンは今までどおり鍵の変化で拾う。$1B8 も同時に動くが、
-- 二重に足さないこと。
test("別ボタンへのチェーンは 1 つずつのまま", function()
  feed({
    { 0,  { free = true } },
    { 9,  { free = false, action = true, atk = 1, key = 0x10000, name = "LP",
            seq = 1 } },
    { 14, { p2 = 2, hs = 11 } },
    { 18, { p2 = 0, hs = 0 } },
    { 29, { key = 0x10200, name = "MP", seq = 2 } },
    { 34, { p2 = 2, hs = 11 } },
    { 38, { p2 = 0, hs = 0 } },
    { 50, { free = true, action = false, atk = 0, key = 0 } },
  }, 80)
  eq(ar.formatResult(),
    "1t LP >  6t Hit >  21t MP >  26t Hit >  42t Free", "1 行")
end)

-- 確定した端から出す。締まるのを待たない (user, 2026-09-10)。
test("道筋は進みながら出る", function()
  ar.reset("test", true)
  local st = {}
  local seen = {}
  local script = {
    [0]  = { free = true },
    [10] = { free = false, action = true, atk = 1, key = 0x10000,
             name = "LP" },
    [15] = { p2 = 2, hs = 11 },
    [19] = { p2 = 0, hs = 0 },
    [40] = { free = true, action = false, atk = 0, key = 0 },
  }
  for t = 0, 60 do
    if script[t] then for k, v in pairs(script[t]) do st[k] = v end end
    ar.update(snap(t, st))
    seen[t] = ar.formatResult()
  end
  eq(seen[9], "", "技の前は何も無い")
  eq(seen[10], "1t LP", "技が出たティックにもう出ている")
  eq(seen[14], "1t LP", "まだヒットしていない")
  eq(seen[16], "1t LP >  6t Hit", "ヒットした次のティックには乗っている")
  eq(seen[60], "1t LP >  6t Hit >  31t Free", "締まったら Free まで")
end)

-- 締まったあと、次の道筋に中身が入るまでは前の行が残る。消えて出直すと
-- 読んでいる途中で行が飛ぶ。
test("次が始まっても中身が入るまでは前の行が残る", function()
  ar.reset("test", true)
  local st = {}
  local script = {
    [0]  = { free = true },
    [10] = { free = false, action = true, atk = 1, key = 0x10000, name = "LP" },
    [15] = { p2 = 2, hs = 11 },
    [40] = { free = true, action = false, atk = 0, key = 0, p2 = 0, hs = 0 },
    -- 出来事がまだ 1 つも無い道筋。ダークフォースのように、行動ではあるが
    -- 技の鍵を持たない状態で開くとこうなる。
    [60] = { free = false, action = true },
    [70] = { key = 0x10200, name = "MP", atk = 1 },
  }
  local before, empty, after = nil, nil, nil
  for t = 0, 71 do
    if script[t] then for k, v in pairs(script[t]) do st[k] = v end end
    ar.update(snap(t, st))
    if t == 59 then before = ar.formatResult() end
    if t == 65 then empty = ar.formatResult() end
    if t == 70 then after = ar.formatResult() end
  end
  eq(before, "1t LP >  6t Hit >  31t Free", "締まった行")
  eq(empty, "1t LP >  6t Hit >  31t Free", "中身が無い間は前の行のまま")
  eq(after, "11t MP", "出来事が入ったら置き換わる")
end)

-- 着地モーション中にもう一度ジャンプすると、以前は 1 回分しか出なかった
-- (user, 2026-09-10。実物は 1t PreJump > 4t Air > 46t Landing > 102t Free)。
-- 着地硬直は自由ではないので、2 回目は同じ道筋の中に入る。
test("着地硬直から跳んだ 2 回目も出る", function()
  feed({
    { 0,  { free = true } },
    { 10, { free = false, jump = true } },
    { 13, { air = true } },
    { 55, { air = false } },
    { 59, { jump = false } },
    { 62, { jump = true } },
    { 65, { air = true } },
    { 100, { air = false } },
    { 111, { free = true, jump = false } },
  }, 140)
  eq(ar.formatResult(),
    "1t PreJump >  4t Air >  46t Landing >  53t PreJump >  56t Air >"
    .. "  91t Landing >  102t Free", "1 行")
end)

-- 空中ダッシュは $06 を 0x14 にしたあと、攻撃が出るとき 0x06 へ戻す (実測)。
-- ジャンプ状態が空中で立ち上がるので、地上にいることを条件にしないと
-- 30t Dash > 44t PreJump > 44t HP のように偽の PreJump が出る。
test("空中ダッシュ攻撃で PreJump は増えない", function()
  feed({
    { 0,  { free = true, cel = 0x1000 } },
    { 10, { free = false, jump = true } },
    { 13, { air = true } },
    { 39, { dash = true, atk = 1, jump = false } },
    { 53, { jump = true, dash = false, key = 0x10400, name = "HP" } },
    { 57, { box = true } },
    { 69, { air = false, box = false } },
    { 77, { free = true, jump = false, atk = 0, key = 0 } },
  }, 100)
  eq(ar.formatResult(),
    "1t PreJump >  4t Air >  30t Dash >  44t HP >  60t Landing >  68t Free",
    "1 行")
end)

-- 着地したティックも地上なので、そこで $06 が 0x06 に戻る空中ダッシュだと
-- 85t PreJump > 85t Landing になっていた。前のティックも地上であること。
test("着地したティックの $06 復帰で PreJump は増えない", function()
  feed({
    { 0,  { free = true, cel = 0x1000 } },
    { 10, { free = false, jump = true } },
    { 13, { air = true } },
    { 40, { dash = true, atk = 1, jump = false } },
    { 94, { air = false, jump = true, dash = false, atk = 0 } },
    { 110, { free = true, jump = false } },
  }, 140)
  eq(ar.formatResult(),
    "1t PreJump >  4t Air >  31t Dash >  85t Landing >  101t Free", "1 行")
end)

-- 1 回だけのジャンプで PreJump が 2 つ出ないこと。道筋を開いたティックの分は
-- 最初の 1 つで足りている。
test("1 回のジャンプでは PreJump は 1 つ", function()
  feed({
    { 0,  { free = true } },
    { 10, { free = false, jump = true } },
    { 13, { air = true } },
    { 55, { air = false } },
    { 70, { free = true, jump = false } },
  }, 100)
  eq(ar.formatResult(),
    "1t PreJump >  4t Air >  46t Landing >  61t Free", "1 行")
end)

-- 上を握りっぱなしで跳び続けると、着地した次のティックにはもう跳んでいるので
-- $06 は 0x06 のまま動かない。PreJump の立ち上がりが無いので、それを起点に
-- していると 2 回目以降が全部消える (user, 2026-09-10。実物は 10 回以上跳んで
-- 1t PreJump > 4t Air > 45t Landing > 52t Air > 961t Free だった)。
test("上を握った連続ジャンプは離着陸ごとに出る", function()
  feed({
    { 0,  { free = true } },
    { 10, { free = false, jump = true } },
    { 13, { air = true } },
    { 54, { air = false } },
    { 61, { air = true } },
    { 100, { air = false } },
    { 107, { air = true } },
    { 146, { air = false } },
    { 160, { free = true, jump = false } },
  }, 200)
  eq(ar.formatResult(),
    "1t PreJump >  4t Air >  45t Landing >  52t Air >  91t Landing >"
    .. "  98t Air >  137t Landing >  151t Free", "1 行")
end)

-- サスカッチのダッシュ小 P から中 P。ダッシュ中は $06 が 0x14 のままなので鍵は
-- 動かず、以前は 1 本目しか出なかった (user, 2026-09-10。実物は
-- 1t Walk > 12t Air > 12t Dash > 20t LP > 24t Guard > 70t Landing > 77t Free)。
-- 2 本目は $1B8 が言う。サスカッチのダッシュは 1 ティック目から空中。
test("ダッシュ中の 2 本目も出る", function()
  feed({
    { 0,  { free = true, cel = 0x1000 } },
    { 10, { free = false, dash = true, air = true, atk = 1, cel = 0x1000,
            button = "LP", seq = 1 } },
    { 13, { cel = 0x1018 } },
    { 19, { cel = 0x2000 } },
    { 23, { box = true } },
    { 24, { p2 = 2, hs = 11, guard = true } },
    { 30, { box = false, p2 = 0, hs = 0 } },
    -- 空中なので $1B8 は増えない (0x028F0E が $38 を見て飛ばす)。ボタンだけが
    -- 変わる。
    { 40, { button = "MP", cel = 0x3000 } },
    { 45, { box = true } },
    { 46, { p2 = 2, hs = 11 } },
    { 52, { box = false, p2 = 0, hs = 0 } },
    { 70, { air = false } },
    { 80, { free = true, dash = false, atk = 0 } },
  }, 110)
  eq(ar.formatResult(),
    "1t Dash >  1t Air >  10t LP >  15t Guard >  31t MP >  37t Guard >"
    .. "  61t Landing >  71t Free", "1 行")
end)

-- カウンタが動かなければ足さない。アニメーションのループでダッシュ攻撃が
-- 二重に出ていた問題を作り直さないこと。
test("ダッシュ中にアニメだけ飛んでも増えない", function()
  feed({
    { 0,  { free = true, cel = 0x1000 } },
    { 10, { free = false, dash = true, atk = 1, cel = 0x1000, button = "LP",
            seq = 1 } },
    { 19, { cel = 0x2000 } },
    { 23, { box = true } },
    { 30, { box = false } },
    { 40, { cel = 0x3000 } },
    { 60, { free = true, dash = false, atk = 0 } },
  }, 90)
  eq(ar.formatResult(), "1t Dash >  10t LP >  51t Free", "1 行")
end)

-- 同じボタンのダッシュ攻撃を 2 回。ボタンも変わらず、空中なので $1B8 も動かない。
-- 2 回目のダッシュそのものから数え直すしかない (user, 2026-09-10。実物は
-- 1t Walk > 11t Air > 11t Dash > 20t MP > 25t Guard > 42t Landing > 46t Air
-- > 77t Landing > 84t Free で、2 回目のダッシュも技も消えていた)。
test("ダッシュ中 P からダッシュ中 P も 2 本出る", function()
  feed({
    { 0,  { free = true, cel = 0x1000 } },
    { 10, { free = false, dash = true, air = true, atk = 1, cel = 0x1000,
            button = "MP" } },
    { 19, { cel = 0x2000 } },
    { 23, { box = true } },
    { 24, { p2 = 2, hs = 11, guard = true } },
    { 30, { box = false, p2 = 0, hs = 0 } },
    { 41, { air = false, dash = false, atk = 0, cel = 0x4000 } },
    { 45, { dash = true, air = true, atk = 1, cel = 0x1000 } },
    { 54, { cel = 0x2000 } },
    { 58, { box = true } },
    { 59, { p2 = 2, hs = 11 } },
    { 65, { box = false, p2 = 0, hs = 0 } },
    { 76, { air = false } },
    { 86, { free = true, dash = false, atk = 0 } },
  }, 120)
  eq(ar.formatResult(),
    -- ダッシュが先。足を浮かせているのはダッシュのほうで、$38 はその結果。
    "1t Dash >  1t Air >  10t MP >  15t Guard >  32t Landing >  36t Dash >"
    .. "  36t Air >  45t MP >  50t Guard >  67t Landing >  77t Free", "1 行")
end)

-- ビシャモンのダッシュ大 P 投げ。ダッシュ中の技はアニメで拾うので、投げの
-- アニメーションもボタン名で技として出てしまっていた (user, 2026-09-10。実物は
-- 10t Dash > 17t HP > 25t Throw)。大 P は出ていない。
test("ダッシュ投げはボタン名を残さない", function()
  feed({
    { 0,  { free = true, cel = 0x1000 } },
    { 9,  { free = false, dash = true, atk = 1, cel = 0x1000, button = "HP" } },
    { 16, { cel = 0x2000 } },
    { 20, { box = true } },
    { 24, { p2 = 6 } },
    { 60, { free = true, dash = false, atk = 0, p2 = 0, box = false } },
  }, 90)
  eq(ar.formatResult(), "1t Dash >  16t Throw >  52t Free", "1 行")
end)

-- 当ててから投げたときは、当てたほうも残る。両方あったことだから。
test("ダッシュ攻撃を当ててからの投げは両方残る", function()
  feed({
    { 0,  { free = true, cel = 0x1000 } },
    { 9,  { free = false, dash = true, atk = 1, cel = 0x1000, button = "LP" } },
    { 16, { cel = 0x2000 } },
    { 20, { box = true } },
    { 21, { p2 = 2, hs = 11 } },
    { 27, { box = false, p2 = 0, hs = 0 } },
    { 40, { p2 = 6 } },
    { 70, { free = true, dash = false, atk = 0, p2 = 0 } },
  }, 100)
  eq(ar.formatResult(),
    "1t Dash >  8t LP >  13t Hit >  32t Throw >  62t Free", "1 行")
end)

-- 投げたあとの動きは読まない。技だけでなく、跳んだ・浮いた・着地したも同じ
-- (user, 2026-09-09 の「投げはいつ投げたかがわかればよい」)。ダッシュ投げが
-- 40t Throw > 67t PreJump と出ていた (user, 2026-09-10)。
test("投げのあとに跳んでも道筋には出ない", function()
  feed({
    { 0,  { free = true, cel = 0x1000 } },
    { 9,  { free = false, dash = true, atk = 1, cel = 0x1000, button = "HP" } },
    { 16, { cel = 0x2000 } },
    { 24, { p2 = 6 } },
    { 40, { dash = false, atk = 0, p2 = 0 } },
    { 48, { jump = true } },
    { 52, { air = true } },
    { 80, { air = false } },
    { 90, { free = true, jump = false } },
  }, 120)
  eq(ar.formatResult(), "1t Dash >  16t Throw >  82t Free", "1 行")
end)

-- 投げていないときは今までどおり全部出る。
test("投げていなければ跳んだことは出る", function()
  feed({
    { 0,  { free = true, cel = 0x1000 } },
    { 9,  { free = false, dash = true, atk = 1, cel = 0x1000, button = "HP" } },
    { 16, { cel = 0x2000 } },
    { 20, { box = true } },
    { 21, { p2 = 2, hs = 11 } },
    { 27, { box = false, p2 = 0, hs = 0 } },
    { 40, { dash = false, atk = 0 } },
    { 48, { jump = true } },
    { 52, { air = true } },
    { 80, { air = false } },
    { 90, { free = true, jump = false } },
  }, 120)
  eq(ar.formatResult(),
    "1t Dash >  8t HP >  13t Hit >  40t PreJump >  44t Air >  72t Landing >"
    .. "  82t Free", "1 行")
end)

-- サスカッチのビッグブランチは投げたあとコンボに行ける。投げの抑止は投げが
-- 終わるまでで、そこから先の技は出さなければならない (user, 2026-09-10)。
test("投げが終わったら次の技は出る", function()
  feed({
    { 0,  { free = true } },
    { 9,  { free = false, action = true, atk = 1, key = 0x20E10,
            name = "Big Branch", seq = 1 } },
    { 20, { p2 = 6 } },
    -- 相手を離し、自分も動けるようになる = 投げの動作が終わった。
    { 55, { p2 = 0, free = true, action = false, atk = 0, key = 0 } },
    { 60, { free = false, action = true, atk = 1, key = 0x10200,
            name = "MP", seq = 2 } },
    { 65, { p2 = 2, hs = 11 } },
    { 90, { free = true, action = false, atk = 0, key = 0, p2 = 0, hs = 0 } },
  }, 120)
  eq(ar.formatResult(),
    "1t Big Branch >  12t Throw >  52t MP >  57t Hit >  82t Free", "1 行")
end)

-- 掴んでいる最中に自分の状態バイトが一瞬 0 を通っても、投げはまだ続いている。
-- 技のほうは相手が掴まれている間ずっと止まるが、離着陸は r.threw しか見ないので、
-- ここで解いてしまうと投げの最中に PreJump が出る。
test("掴んでいる間は自分が動けても投げの続き", function()
  feed({
    { 0,  { free = true } },
    { 9,  { free = false, action = true, atk = 1, key = 0x20E10,
            name = "Big Branch", seq = 1 } },
    { 20, { p2 = 6 } },
    { 30, { free = true, action = false, atk = 0, key = 0 } },
    { 34, { free = false, jump = true } },
    { 38, { air = true } },
    { 60, { air = false, p2 = 0 } },
    { 90, { free = true, jump = false } },
  }, 120)
  eq(ar.formatResult(), "1t Big Branch >  12t Throw >  82t Free", "1 行")
end)

-- 相手を離しただけで自分がまだ動けないうちは、投げの尻尾のまま。蹴り投げが
-- 158t Throw > 293t MK > 293t Hit と出ていたのがこれ (user, 2026-09-09)。
test("相手を離しても自分が動けないうちは投げの続き", function()
  feed({
    { 0,  { free = true } },
    { 9,  { free = false, action = true, atk = 1, key = 0x20E10,
            name = "Big Branch", seq = 1 } },
    { 20, { p2 = 6 } },
    { 40, { p2 = 0 } },
    { 45, { key = 0x10400, name = "HP", seq = 2 } },
    { 90, { free = true, action = false, atk = 0, key = 0 } },
  }, 120)
  eq(ar.formatResult(), "1t Big Branch >  12t Throw >  82t Free", "1 行")
end)

-- ビクトルの一回転投げ / 二回転投げは発生 1 フレーム。技が始まったティックに
-- もう掴んでいる (実測 2026-09-11: $06 が 0x0E か 0x12 になるのと相手の $05=06 が
-- 同じ行)。掴みを今のティックで見ていると、投げた技が自分の投げに消されていた。
test("発生 1 フレームの投げでも技の名前が出る", function()
  feed({
    { 0,  { free = true } },
    { 9,  { free = false, action = true, special = true, atk = 1,
            key = 0x20E0E, name = "Mega Spike", p2 = 6 } },
    { 49, { p2 = 2 } },
    { 80, { free = true, action = false, special = false, atk = 0, key = 0,
            p2 = 0 } },
  }, 110)
  eq(ar.formatResult(), "1t Mega Spike >  1t Throw >  72t Free", "1 行")
end)

-- 二回転は EX ($06 = 0x12)。同じ扱いになること。
test("EX の投げも同じ", function()
  feed({
    { 0,  { free = true } },
    { 9,  { free = false, action = true, special = true, atk = 1,
            key = 0x21200, name = "Gerdenheim 3", p2 = 6 } },
    { 49, { p2 = 2 } },
    { 80, { free = true, action = false, special = false, atk = 0, key = 0,
            p2 = 0 } },
  }, 110)
  eq(ar.formatResult(), "1t Gerdenheim 3 >  1t Throw >  72t Free", "1 行")
end)

-- 掴む瞬間を見逃した場合。ステートロードや道筋の作り直しで、既に掴んでいる
-- ところから始まると Throw の辺が立たず r.threw も付かない。それでも投げの中
-- なので技にはしない。
test("掴む瞬間を見ていなくても投げの中なら技にしない", function()
  feed({
    { 0,  { free = true, p2 = 6 } },
    { 9,  { free = false, action = true, special = true, atk = 1,
            key = 0x20E0E, name = "Mega Spike" } },
    { 20, { key = 0x10400, name = "HP" } },
    { 49, { p2 = 2 } },
    { 80, { free = true, action = false, special = false, atk = 0, key = 0,
            p2 = 0 } },
  }, 110)
  eq(ar.formatResult():find("Mega Spike") ~= nil, false, "技は出ない")
  eq(ar.formatResult():find("HP") ~= nil, false, "あとの技も出ない")
end)

-- 掴んだ次のティックからは、投げの中で状態が動いても技にはしない。ここを
-- 緩めると蹴り投げの尻尾が戻る。
test("掴んだ次のティックからは技にしない", function()
  feed({
    { 0,  { free = true } },
    { 9,  { free = false, action = true, special = true, atk = 1,
            key = 0x20E0E, name = "Mega Spike", p2 = 6 } },
    { 20, { key = 0x10400, name = "HP" } },
    { 49, { p2 = 2 } },
    { 80, { free = true, action = false, special = false, atk = 0, key = 0,
            p2 = 0 } },
  }, 110)
  eq(ar.formatResult(), "1t Mega Spike >  1t Throw >  72t Free", "1 行")
end)

print("PASS " .. passed)
