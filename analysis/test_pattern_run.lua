-- WHICH LIST THE DUMMY ACTUALLY RUNS.
--
-- Guard Action Type picks the SOURCE: 0xB is the one Action Steps list, 0xC is
-- one out of the Action Pattern Library. Everything downstream is the same
-- either way, so what this pins is the choosing.
--
-- THE ROLL HAPPENS ONCE PER ARMING. schedule is asked many times while a single
-- reversal runs - by the arm, by the loop, by the menu - and a fresh roll on
-- each of them would splice two patterns together one step at a time. That is
-- the failure this file exists to catch, and it is invisible in a single call.
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_pattern_run.lua
local ram={} memory={readbyte=function(a) return ram[a] or 0 end,
                     readdword=function() return 0 end}
gui={text=function() end,box=function() end}
emu={framecount=function() return 1 end}
globals={dummy={}} training_settings={action_sequences={}, action_patterns={}}
function mark_training_settings_dirty() end
function dash_attack_ticks_for(m) return (m=="forward dash" or m=="forward dash cancel") and 6 or nil end
seq_dash_cancel_reverse = { ["forward dash cancel"] = "back", ["back dash cancel"] = "forward" }
function air_dash_ticks_for() return nil end
function air_dash_attack_ticks_for() return nil end
local src=io.open("controller.lua"):read("*a")
local _NL=string.char(10)
local s=src:find("function make_input_sequence",1,true)
local e=src:find(_NL.."end",src:find("return _sequence",s,true),true)
assert(s and e,"make_input_sequence が controller.lua で見つからない")
assert(loadstring(src:sub(s,e+4)))()

local R = dofile("actionSequenceRunner.lua")

local fails=0
local function eq(what,got,want)
  if got==want then print("  ok "..what)
  else
    fails=fails+1
    print("  NG "..what)
    print("     got  ["..tostring(got).."]")
    print("     want ["..tostring(want).."]")
  end
end

-- $382 のキャラ id。ランナーは dummy_cid() でこれを読む。
local CID = 0xFF8B82
ram[CID] = 0x05

local function step(btn, wait)
  return { action="atk", lever="none", button=btn, wait=wait or -1 }
end
local function patterns(list)
  training_settings.action_patterns = { reversal = { ["5"] = { version=1, items=list } } }
end
-- 走る列の 1 歩目が押すボタン。どのパターンが選ばれたかを 1 文字で見る。
local function ran()
  local sched = R.schedule("reversal")
  if sched == nil then return nil end
  local p = R.picked_pattern()
  return p and p.name or "?"
end

print("[1] 0xB のままなら今までどおり Action Steps の列")
training_settings.guard_action = 0xB
training_settings.action_sequences = { reversal = { ["5"] = { version=1, steps={ step("MP") } } } }
patterns({ { name="lib", use=true, steps={ step("HK") } } })
local sched = R.schedule("reversal")
eq("列がある", sched ~= nil, true)
eq("ライブラリは使われない", R.picked_pattern(), nil)

print("")
print("[2] 0xC なら印の付いたパターン")
training_settings.guard_action = 0xC
patterns({ { name="only", use=true, steps={ step("HK"), step("LK") } } })
R.pick_pattern("reversal")
eq("選ばれた", R.picked_pattern().name, "only")
eq("2 歩ある", #R.schedule("reversal"), 2)

print("")
print("[3] 印が 1 つだけなら毎回それ")
patterns({
  { name="on",  use=true,  steps={ step("LP") } },
  { name="off", use=false, steps={ step("HP") } },
})
local seen = {}
for _=1,30 do R.pick_pattern("reversal") seen[R.picked_pattern().name]=true end
local n=0 for _ in pairs(seen) do n=n+1 end
eq("1 種類しか出ない", n, 1)
eq("それは印の付いたほう", seen["on"], true)

print("")
print("[4] 印が複数なら、その中からだけ選ばれる")
patterns({
  { name="a", use=true,  steps={ step("LP") } },
  { name="b", use=false, steps={ step("MP") } },
  { name="c", use=true,  steps={ step("HP") } },
})
math.randomseed(12345)
local got = {}
for _=1,200 do R.pick_pattern("reversal") got[R.picked_pattern().name]=true end
eq("a は出る", got["a"], true)
eq("c は出る", got["c"], true)
eq("b は出ない", got["b"], nil)

print("")
print("[5] 1 回の選択の中では、何度聞いても同じ 1 本")
-- ここが本題。schedule を何度呼んでも同じ 1 本が返ること。
math.randomseed(7)
R.pick_pattern("reversal")
local first = R.picked_pattern().name
local stable = true
for _=1,200 do
  if ran() ~= first then stable = false break end
end
eq("何度聞いても同じ 1 本", stable, true)
-- 引き直せば散る。200 回で 2 種類とも出れば、固定ではない。
local kinds = {}
for _=1,200 do R.pick_pattern("reversal") kinds[R.picked_pattern().name]=true end
local k=0 for _ in pairs(kinds) do k=k+1 end
eq("選び直せば散る", k, 2)

print("")
print("[6] 印が 1 つも無ければ何も走らない")
patterns({
  { name="a", use=false, steps={ step("LP") } },
  { name="b", use=false, steps={ step("MP") } },
})
eq("選ばれない", R.pick_pattern("reversal"), nil)
eq("列も出ない", R.schedule("reversal"), nil)

print("")
print("[7] 空のパターンは印が付いていても走らない")
patterns({ { name="empty", use=true, steps={} } })
eq("中身が無いものは選ばない", R.pick_pattern("reversal"), nil)

print("")
print("[8] キャラが違えばそのキャラのパターン")
patterns({ { name="morrigan", use=true, steps={ step("LP") } } })
ram[CID] = 0x0A
eq("別キャラには何も無い", R.pick_pattern("reversal"), nil)
ram[CID] = 0x05
eq("戻せば出る", R.pick_pattern("reversal").name, "morrigan")

print("")
print("[9] 編集したら、走る列も新しくなる")
-- ここは移植版が落ちた形そのもの。compile の結果は seq の表の同一性で憶えて
-- いるので、steps だけ差し替えると古い列が返り続ける。
patterns({ { name="one", use=true, steps={ step("LP") } } })
R.pick_pattern("reversal")
eq("まず 1 歩", #R.schedule("reversal"), 1)
-- エディタの保存と同じことをする: 表ごと差し替え、ランナーに手放させる。
local row = training_settings.action_patterns.reversal["5"]
row.items[1] = { name="one", use=true, steps={ step("LP"), step("MP"), step("HP") } }
R.forget_pick()
R.pick_pattern("reversal")
eq("3 歩になっている", #R.schedule("reversal"), 3)
-- 表を差し替えずに中身だけ書き換えると古いままになる、という裏取り。
row.items[1].steps = { step("LP") }
eq("同じ表のままなら憶えたまま", #R.schedule("reversal"), 3)

print("")
print("[10] 周回ごとに引き直す - 引くのは loop_refill の中、schedule を聞く前")
-- loop_refill はローカル関数なので、ここは呼び出しではなくソースを読む。
-- 確かめたいのは「どこで引くか」そのもの。pending は最終ステップが発火した
-- ティックに空になるので、この位置なら着地の予測にはまだ十分間に合う - 1 段
-- でも後ろへ動かすと、新しい周回の 1 歩目が決まらないまま助走が始まる。
--
-- 区間で挟んでから探す。同じ文字列はこのファイルの他の場所にもある。
local rsrc = io.open("actionSequenceRunner.lua"):read("*a")
local lr_s = rsrc:find("local function loop_refill()", 1, true)
local lr_e = rsrc:find("-- Left for service_body to name on the first tick", lr_s, true)
eq("loop_refill が見つかる", lr_s ~= nil, true)
eq("終わりの目印も見つかる", lr_e ~= nil, true)
local body = rsrc:sub(lr_s, lr_e)
local at_pick = body:find("M.pick_pattern(loop_which)", 1, true)
local at_sched = body:find("M.schedule(loop_which)", 1, true)
local at_on = body:find("M.loop_on()", 1, true)
eq("周回ごとに引いている", at_pick ~= nil, true)
eq("schedule を聞く前に引いている", (at_pick or 0) < (at_sched or 0), true)
-- ループが止まっているときに引いてはいけない。引くと、走ってもいないのに
-- 次のパターンが変わる。
eq("ループが生きている判定より後ろ", (at_on or 0) < (at_pick or 0), true)
-- パターン以外のときは触らない。Action Steps は 1 本しか無い。
eq("patterns_mode の中にある",
   body:find("if patterns_mode() then M.pick_pattern(loop_which) end", 1, true) ~= nil, true)

print("")
print("[11] キャラ選択に戻るとループは止まる - refill も走行中の周も")
-- match_running はマスタースクリプトが公開する「本当に試合中」の定義。
-- それが false を返すあいだは、refill も pending の残り周も出してはいけない。
do
  local sgate = body:find("if not match_live() then return end", 1, true)
  eq("refill の先頭で試合中を見る", sgate ~= nil, true)
  local after_on = body:find("if not M.loop_on() then return end", 1, true)
  eq("loop_on の判定より後ろにある", (after_on or 0) < (sgate or 0), true)
  -- service 側: menu の後片付けと同じ形で、走行中の周ごと落ちる。
  local at_menu = rsrc:find("if loop_blocked() then", 1, true)
  local at_live = rsrc:find("if not match_live() then", at_menu or 1, true)
  eq("service も試合外で落とす", at_live ~= nil, true)
  eq("menu の後片付けの後に置いてある",
     (at_menu or 0) < (at_live or 0), true)
  -- 定義: match_running が無い環境では「生きている」扱い (テスト互換)。
  local def_s = rsrc:find("local function match_live()", 1, true)
  local def_e = rsrc:find("\nend", def_s or 1, true)
  local dbody = rsrc:sub(def_s or 1, (def_e or 1) + 3)
  eq("無ければ生きている扱い", dbody:find("if f == nil then return true end", 1, true) ~= nil, true)
end

if fails == 0 then print("") print("全て通った") else print(fails .. " 件 NG") os.exit(1) end
