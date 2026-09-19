-- MENU SURFACE TEST.
--
-- Drives the editor with real input and reads what it actually draws, by
-- intercepting gui.text. Every heading and every row is compared character for
-- character, so a layout change that was not intended fails here rather than in
-- front of the user after a full FBNeo restart.
--
-- Run from scripts/ - the dofile below is relative.
--   cd scripts && lua5.1 ../analysis/test_editor_rows.lua
local ram={} memory={readbyte=function(a) return ram[a] or 0 end}
gui={text=function() end, box=function() end}
local FC=0 emu={framecount=function() FC=FC+1 return FC end}
function mark_training_settings_dirty() end
panel_fill_color=0 panel_outline_color=0
text_selected_color=0 text_default_color=0 text_default_border_color=0 text_disabled_color=0
-- THE REAL make_input_sequence, NOT A STUB.
--
-- A stub that returned {{button}} for every motion used to be enough, because
-- nothing here read the entries. The Hold row does - it is offered when a
-- step's input list ends on a direction - so a stub would decide that question
-- for the test instead of the code. Lifted out of controller.lua.
local _csrc = io.open("controller.lua"):read("*a")
local _cs = _csrc:find("function make_input_sequence", 1, true)
local _ce = _csrc:find("\nend", _csrc:find("return _sequence", _cs, true), true)
assert(_cs and _ce, "make_input_sequence が controller.lua に見つからない")
assert(loadstring(_csrc:sub(_cs, _ce + 4)))()
local P1={input={pressed={},down={}}} player_objects={P1}
function check_input_down_autofire(p,name) return p.input.down[name] == true end
-- 行の無いキャラ用の導出スタブ。MEASURED_STEP_FLOORS が全キャラ埋まったので、
-- 行のあるキャラではこの表は引かれない - モリガンもザベルも実測値が出る。
local TBL={[0x05]={f=12,b=12,fc=13,bc=13}, [0x04]={f=1,b=1,fc=1,bc=1}}
local FIELD={["forward dash"]="f",["back dash"]="b",["forward dash cancel"]="fc",["back dash cancel"]="bc"}
function dash_attack_ticks_for(m) local f=FIELD[m] if not f then return nil end local r=TBL[ram[0xFF8B82]] if not r then return nil end return r[f] end
-- AIR_DASH_TICKS は guardCancel.lua からソースごと読む。書き写すと、表に
-- キャラを足したときにここだけ古くなって、テストが古い答えを守ってしまう。
local _gsrc = io.open("guardCancel.lua"):read("*a")
local _ts = _gsrc:find("local AIR_DASH_TICKS = {", 1, true)
local _te = _gsrc:find("\n}", _ts, true)
assert(_ts and _te, "AIR_DASH_TICKS が guardCancel.lua に見つからない")
local AIR = assert(loadstring("return " .. _gsrc:sub(_ts + #"local AIR_DASH_TICKS = ", _te + 2)))()
local function air_row(jump,dash) local r=AIR[ram[0xFF8B82]] if not r then return nil end
  return r[tostring(jump)..">"..tostring(dash)] end
function air_dash_ticks_for(j,d) local p=air_row(j,d) return p and p.dash end
function air_dash_attack_ticks_for(j,d) local p=air_row(j,d) return p and p.atk end
-- Auto の解決は runner が一手に持つ。エディタはそれを表示するだけなので、
-- テストでも本物を配線する - スタブを置くとテストが答えを決めてしまう。
local _R = dofile("actionSequenceRunner.lua")
seq_auto_ticks = _R.auto_ticks_for
-- 「Recovered が嘘になる場所か」も runner が決める。エディタは従うだけ。
seq_auto_needs_number = _R.auto_needs_number
training_settings={action_sequences={}}
ram[0xFF8B82]=0x05
local E=dofile("actionSequenceEditor.lua")

local fails=0
local function fail(what,got,want)
  fails=fails+1
  print("  NG "..what)
  print("     got  ["..tostring(got).."]")
  print("     want ["..tostring(want).."]")
end
local function eq(what,got,want)
  if got==want then print("  ok "..what) else fail(what,got,want) end
end

local function tap(n)
  -- The armed gate wants a release before it reads a press.
  P1.input.pressed={} P1.input.down={} E.registerBefore()
  P1.input.pressed={[n]=true} P1.input.down={[n]=true} E.registerBefore()
  P1.input.pressed={} P1.input.down={}
end
local function taps(n,k) for _=1,k do tap(n) end end

-- 選択中の行。分類はキャラによって増減するので、数ではなく名前で歩く。
local function selected()
  local sel=nil
  gui.text=function(x,y,t)
    if x==33 and y>=37 and y<=160 and t:sub(1,1)==">" then sel=t end
  end
  E.guiRegister()
  gui.text=function() end
  return sel or ""
end
local function goto_row(text)
  for _=1,16 do
    if selected():find(text,1,true) then return end
    tap("down")
  end
  fail("行が見つからない ["..text.."]", selected(), text)
end

-- The panel is gui.box(23,15,360,207); the heading sits at y=21 and rows run
-- from y=37 in tens. Everything below 160 is help text and is not part of this.
local function draw()
  local title,rows=nil,{}
  gui.text=function(x,y,t)
    if x==33 and y==21 then title=t
    elseif x==33 and y>=37 and y<=160 then rows[#rows+1]=t end
  end
  E.guiRegister()
  gui.text=function() end
  return title,rows
end
-- 行内の詰め物は「そのリストで一番長い行」から決まるので、ステップを 1 つ
-- 足しただけで全部の期待値が書き換わってしまう。ここでは中身を見て、列が
-- 揃っていることは [9] で別に見る。行頭の字下げは階層を表すので残す。
local function norm(t)
  local lead, rest = t:match("^(%s*)(.-)%s*$")
  return lead .. rest:gsub("%s%s+", "  ")
end
local function rows_eq(what,want)
  local _,raw=draw()
  local got,w2={},{}
  for i,l in ipairs(raw)  do got[i]=norm(l) end
  for i,l in ipairs(want) do w2[i]=norm(l) end
  local g,w=table.concat(got,"\n"),table.concat(w2,"\n")
  if g==w then print("  ok "..what) else
    fails=fails+1
    print("  NG "..what)
    for i=1,math.max(#got,#w2) do
      local a,b=got[i] or "(nothing)",w2[i] or "(nothing)"
      print((a==b and "     = [" or "     X [")..a.."]  want ["..b.."]")
    end
  end
end
local function title_eq(what,want)
  local t=draw()
  eq(what,norm(t),norm(want))
end
local function open(cid,steps)
  ram[0xFF8B82]=cid
  training_settings.action_sequences.reversal={[tostring(cid)]={version=1,steps=steps}}
  E.open("reversal")
end

local HEAD="REVERSAL ACTION STEPS: Morrigan"

print("[1] detail の行 - Action / parts / Wait の順、Start はどこにも出ない")
open(0x05,{{action="atk",lever="none",button="LP",wait=-1}})
tap("LP")
rows_eq("Attack Neutral + LP",{
  ">  Action : Attack  >",
  "     Direction : Neutral  >",
  "     Button : LP  >",
  "   Wait : Auto (Fastest)  >",
  "   Back"})

open(0x05,{{action="custom",lever="DPF",button="HP",wait=-1}})
tap("LP")
rows_eq("Custom DPF + HP",{
  ">  Action : Custom  >",
  "     Motion : DPF  >",
  "     Button : HP  >",
  "     Hold : No",
  "   Wait : Auto (Fastest)  >",
  "   Back"})

open(0x05,{{action="dash.f",wait=-1}})
tap("LP")
rows_eq("Dash Forward",{
  ">  Action : Dash Forward  >",
  "     Hold : No",
  "   Wait : Auto (Fastest)  >",
  "   Back"})

open(0x05,{{action="dashc.f",wait=-1},{action="atk",lever="none",button="HP",wait=-1}})
tap("LP")
rows_eq("Dash Forward Cancel - Hold 行は出ない",{
  ">  Action : Dash Forward Cancel  >",
  "   Wait : Auto (Fastest)  >",
  "   Move Step : 1 / 2  >",
  "   Remove This Step  >",
  "   Back"})

open(0x05,{{action="crouch.d",wait=-1}})
tap("LP")
rows_eq("Crouch Neutral",{
  ">  Action : Crouch Neutral  >",
  "     Hold : No",
  "   Wait : Auto (Fastest)  >",
  "   Back"})

print("[2] 2 歩目の Wait - ダッシュの次は数値に解決する")
open(0x05,{{action="dash.f",wait=-1},{action="atk",lever="none",button="LK",wait=-1}})
tap("down") tap("LP")
rows_eq("Dash の次の Attack",{
  ">  Action : Attack  >",
  "     Direction : Neutral  >",
     "     Button : LK  >",
     "   Wait : Auto (11)  >",
     "   Move Step : 2 / 2  >",
  "   Remove This Step  >",
  "   Back"})

print("[2b] Wait の選択画面 - 選ぶ前に、選んだ結果が読める")
-- 行は Auto (11) と出るのに、選択肢は After としか出ていなかった。ダッシュの
-- 後の攻撃はダッシュの「最中」に出る技で、終わってから出るのではないので、
-- After という語が場面と合っていない (本人、2026-09-19)。
--
-- 実測値が出る場面だけ Fastest (N) に差し替える。攻撃の後は After のままで
-- 正しい - そこは本当に「ダミーが終わるまで待つ」だから。
open(0x05,{{action="dash.f",wait=-1},{action="atk",lever="none",button="LK",wait=-1}})
tap("down") tap("LP")            -- STEP 2 へ
goto_row("Wait") tap("LP")       -- Wait 画面
rows_eq("ダッシュの後は解決値が出る",{
  ">  Fastest (11)",
  "   Landing",
  "   Chain",
  "   Cancel",
  "   Late Cancel",
  "   Fixed Ticks",
  "   Back"})
tap("left")

-- 攻撃の後は After のまま。ここを巻き込むと、正しい語まで失われる。
open(0x05,{{action="atk",lever="none",button="LP",wait=-1},{action="atk",lever="none",button="LK",wait=-1}})
tap("down") tap("LP")
goto_row("Wait") tap("LP")
rows_eq("攻撃の後は After のまま",{
  ">  After",
  "   Landing",
  "   Rapid",
  "   Chain",
  "   Cancel",
  "   Late Cancel",
  "   Fixed Ticks",
  "   Back"})
tap("left")

print("[3] 見出しは経路 - 押した行の名前がそのまま伸びる")
open(0x05,{{action="atk",lever="none",button="LP",wait=-1},{action="neutral",wait=-1}})
title_eq("root",     HEAD)
tap("LP")
title_eq("detail",   HEAD.."  >  STEP 1")
tap("LP")
title_eq("groups",   HEAD.."  >  STEP 1  >  Action")
goto_row("Crouch") tap("LP")
title_eq("actions",  HEAD.."  >  STEP 1  >  Action  >  Crouch")
tap("left") tap("left")
tap("down") tap("LP")
title_eq("pick 方向", HEAD.."  >  STEP 1  >  Direction")
tap("left") tap("down") tap("LP")
title_eq("pick ボタン", HEAD.."  >  STEP 1  >  Button")
tap("left") tap("down") tap("LP")
title_eq("wait",     HEAD.."  >  STEP 1  >  Wait")
-- Wait 画面の Left は「値を減らす」なので、抜けるのは下の Back 行から。
tap("down") tap("LP")
tap("down") tap("LP")
title_eq("order",    HEAD.."  >  STEP 1  >  Move Step")
print("  (Order は Wait と同じ形。左右で動かし、抜けるのは Back 行から)")
tap("right")
title_eq("order 移動後", HEAD.."  >  STEP 2  >  Move Step")
tap("down") tap("LP")
tap("down") tap("LP")
title_eq("confirm",  HEAD.."  >  STEP 2  >  Remove")

print("[4] Custom の lever 行は Motion - 見出しも同じ語")
open(0x05,{{action="custom",lever="DPF",button="HP",wait=-1}})
tap("LP") tap("down") tap("LP")
title_eq("pick モーション", HEAD.."  >  STEP 1  >  Motion")

print("[5] 分類の並び")
open(0x05,{{action="neutral",wait=-1}})
tap("LP") tap("LP")
rows_eq("groups - モリガンに空中ダッシュは無い",{
  "   Attack  >",
  "   Dash  >",
  "   Jump  >",
  "   Super Jump  >",
  ">  Stand  >",
  "   Crouch  >",
  "   Custom  >"})

print("[6] 最長の見出しがパネルに収まる")
-- 決め打ちはやめた。分類がキャラで増減するので、名前が最長のキャラと分類名が
-- 最長の分類が同じ画面に出るとは限らない(Dark Gallon に Super Jump は無い)。
-- 全キャラ x 到達できる全分類を歩いて、いちばん長い見出しを実際に見つける。
local worst, worst_cid = "", nil
for cid = 0x00, 0x18 do
  open(cid,{{action="atk",lever="none",button="LP",wait=-1}})
  tap("LP") tap("LP")                        -- detail → Action(分類一覧)
  local _,grows = draw()
  for row = 1, #grows do
    -- 分類一覧の row 番目へ移動して入る。list を持たない分類は即戻るので、
    -- 見出しは伸びない - それも含めて測る。
    open(cid,{{action="atk",lever="none",button="LP",wait=-1}})
    tap("LP") tap("LP")
    taps("down", row - 1)
    tap("LP")
    local t = draw()
    if t ~= nil and #t > #worst then worst, worst_cid = t, cid end
  end
end
-- ステップ番号だけは 2 桁になりうるので置換して測る。
local widest = worst:gsub("STEP 1", "STEP 16")
local right = 33 + #widest * 4                -- get_text_width は #text*4
print(string.format("     [%s]  %d 文字  右端 %d px", widest, #widest, right))
if right<=360 then print("  ok パネル右端 360 に収まる")
else fail("パネルからはみ出す", right, "<= 360") end

print("[6b] Hold 行は「保持できる方向がある」ときだけ出る")
-- タメ技は方向を溜めて離すもの。保持する方向が無いステップに行を出しても
-- 意味がないので、素の方向で終わるときだけ出す。
open(0x05,{{action="atk",lever="down-back",button="LP",wait=-1}})
tap("LP")
rows_eq("Attack Down Back + LP",{
  ">  Action : Attack  >",
  "     Direction : Down Back  >",
  "     Button : LP  >",
  "     Hold : No",
  "   Wait : Auto (Fastest)  >",
  "   Back"})

open(0x05,{{action="atk",lever="none",button="LP",wait=-1}})
tap("LP")
rows_eq("Attack Neutral + LP - 保持するものが無い",{
  ">  Action : Attack  >",
  "     Direction : Neutral  >",
  "     Button : LP  >",
  "   Wait : Auto (Fastest)  >",
  "   Back"})

-- DPF の最後のエントリは {down,forward,HP} なので、方向で終わっている。
-- 規則は「最後が方向なら保持できる」の一本槍で、コマンドかどうかは見ない。
-- 昇龍拳のあと下前を握り続けるのは無害だし、例外を作ると「なぜここだけ」を
-- 説明し続けることになる。
open(0x05,{{action="custom",lever="DPF",button="HP",wait=-1}})
tap("LP")
rows_eq("Custom DPF - 最後が方向なので付く",{
  ">  Action : Custom  >",
  "     Motion : DPF  >",
  "     Button : HP  >",
  "     Hold : No",
  "   Wait : Auto (Fastest)  >",
  "   Back"})

open(0x05,{{action="custom",lever="down-back",button="HP",wait=-1}})
tap("LP")
rows_eq("Custom Down Back - 素の方向なので出る",{
  ">  Action : Custom  >",
  "     Motion : Down Back  >",
  "     Button : HP  >",
  "     Hold : No",
  "   Wait : Auto (Fastest)  >",
  "   Back"})

open(0x05,{{action="atk",lever="down-back",button="LP",hold=true,wait=-1}})
tap("LP")
rows_eq("Hold : Yes",{
  ">  Action : Attack  >",
  "     Direction : Down Back  >",
  "     Button : LP  >",
  "     Hold : Yes",
  "   Wait : Auto (Fastest)  >",
  "   Back"})

-- 移動系にも付く。「Stand Forward を Hold して、次のステップの Wait を 15 に
-- すれば 15 ティック歩いて投げ」が組めるのはこれのおかげ。
open(0x05,{{action="dash.f",wait=-1}})
tap("LP")
rows_eq("Dash Forward - 名前付きアクションにも付く",{
  ">  Action : Dash Forward  >",
  "     Hold : No",
  "   Wait : Auto (Fastest)  >",
  "   Back"})

open(0x05,{{action="walk.f",hold=true,wait=-1}})
tap("LP")
rows_eq("Stand Forward - 15 ティック歩く指定の土台",{
  ">  Action : Stand Forward  >",
  "     Hold : Yes",
  "   Wait : Auto (Fastest)  >",
  "   Back"})

open(0x05,{{action="neutral",wait=-1}})
tap("LP")
rows_eq("Stand Neutral - 保持するものが無い",{
  ">  Action : Stand Neutral  >",
  "   Wait : Auto (Fastest)  >",
  "   Back"})

print("[7] 一覧の行 - 1 歩目にも Auto (Fastest) が出て、詳細と同じ語を使う")
open(0x05,{{action="dash.f",wait=-1},
           {action="atk",lever="none",button="MP",wait=-1},
           {action="atk",lever="down-back",button="LP",wait=-1},
           {action="atk",lever="down-back",button="LP",wait=3}})
rows_eq("一覧",{
  ">  1  Auto (Fastest)  Dash : Forward  >",
   "   2  Auto (11)  Attack : MP  >",
  "   3  Auto (After)  Attack : Down Back + LP  >",
  "   4  3 Ticks  Attack : Down Back + LP  >",
  "   + Add Step  >",
  "   Save",
  "   Back Without Saving",
  "   Clear All Steps"})

print("[6c] 空中ダッシュはメニューに載り、地上ダッシュと見分けが付く")
-- 入力は同じでも Auto の解決先が違うので、名前を分ける必要がある。
open(0x04,{{action="jump.f",wait=-1},
           {action="air.f",wait=-1},
           {action="atk",lever="down",button="HP",wait=-1}})
rows_eq("ザベルの最低空ダッシュ → 下 HP",{
  ">  1  Auto (Fastest)  Jump : Forward  >",
  "   2  Auto (8)  Air Dash : Forward  >",
  "   3  Auto (0)  Attack : Down + HP  >",
  "   + Add Step  >",
  "   Save",
  "   Back Without Saving",
  "   Clear All Steps"})
-- 地上ダッシュなら 2 歩目は表から数値に解決する(ザベルの実測 f=0)。
open(0x04,{{action="dash.f",wait=-1},
           {action="atk",lever="down",button="HP",wait=-1}})
rows_eq("地上ダッシュの次は数値",{
  ">  1  Auto (Fastest)  Dash : Forward  >",
  "   2  Auto (0)  Attack : Down + HP  >",
  "   + Add Step  >",
  "   Save",
  "   Back Without Saving",
  "   Clear All Steps"})

print("[6d] 空中ダッシュを持たないキャラには出さない")
-- 出せない行を並べるのは、無い行より悪い。組んだシーケンスは正しく見えて
-- 走って何も起きず、タイミングの間違いと区別が付かない。
local function group_rows(cid)
  open(cid,{{action="atk",lever="none",button="LP",wait=-1}})
  tap("LP") tap("LP")
  local _,rows=draw()
  local out={}
  for _,l in ipairs(rows) do out[#out+1]=l:gsub("^[>%s]+",""):gsub("%s*>*%s*$","") end
  return table.concat(out," / ")
end
local function action_rows(cid)
  open(cid,{{action="atk",lever="none",button="LP",wait=-1}})
  tap("LP") tap("LP")
  goto_row("Air Dash") tap("LP")
  local _,rows=draw()
  local out={}
  for _,l in ipairs(rows) do out[#out+1]=l:gsub("^[>%s]+",""):gsub("%s*>*%s*$","") end
  return table.concat(out," / ")
end
-- 表に入っている実測値がそのまま行に出ること。表はソースから読んでいるので、
-- キャラを足せばここも自動で追随する。
local function dash_row(cid, jump, dash)
  open(cid,{{action=jump,wait=-1},{action=dash,wait=-1}})
  local _,rows=draw()
  return (rows[2] or ""):gsub("^%s+",""):gsub("%s*>%s*$","")
end
-- ジャンプの向きとダッシュの向きの組で決まる。ザベルは前→前が 8 なのに
-- 後ろ→前は 4 - 同じキャラ・同じ踏切でも答えが違う。
eq("ザベル 前→前 8",   dash_row(0x04,"jump.f","air.f"), "2  Auto (8)        Air Dash : Forward")
eq("ザベル 後→後 8",   dash_row(0x04,"jump.b","air.b"), "2  Auto (8)        Air Dash : Back")
eq("ザベル 後→前 4",   dash_row(0x04,"jump.b","air.f"), "2  Auto (4)        Air Dash : Forward")
eq("ザベル 垂直→前 4", dash_row(0x04,"jump.n","air.f"), "2  Auto (4)        Air Dash : Forward")
eq("ザベル 前→後 4",   dash_row(0x04,"jump.f","air.b"), "2  Auto (4)        Air Dash : Back")
eq("ザベル 垂直→後 4", dash_row(0x04,"jump.n","air.b"), "2  Auto (4)        Air Dash : Back")
-- Q-Bee はザベルと形が違う。前も後ろも 6 で、垂直だけが 4。
eq("Q-Bee 前→前 6",   dash_row(0x0C,"jump.f","air.f"), "2  Auto (6)        Air Dash : Forward")
eq("Q-Bee 後→前 6",   dash_row(0x0C,"jump.b","air.f"), "2  Auto (6)        Air Dash : Forward")
eq("Q-Bee 垂直→前 4", dash_row(0x0C,"jump.n","air.f"), "2  Auto (4)        Air Dash : Forward")
eq("レイレイ 前→前 9", dash_row(0x0D,"jump.f","air.f"), "2  Auto (9)        Air Dash : Forward")
eq("レイレイ 後→後 9", dash_row(0x0D,"jump.b","air.b"), "2  Auto (9)        Air Dash : Back")
eq("レイレイ 垂直→前 6", dash_row(0x0D,"jump.n","air.f"), "2  Auto (6)        Air Dash : Forward")
eq("レイレイ 後→前 6",   dash_row(0x0D,"jump.b","air.f"), "2  Auto (6)        Air Dash : Forward")
eq("レイレイ 前→後 6",   dash_row(0x0D,"jump.f","air.b"), "2  Auto (6)        Air Dash : Back")
eq("レイレイ 垂直→後 6", dash_row(0x0D,"jump.n","air.b"), "2  Auto (6)        Air Dash : Back")
-- 未実測の組は数字を出さない。

-- 空中ダッシュの次の攻撃もキャラ別。0 は「測ってある 0」であって既定値ではない。
local function atk_row(cid, dash, jump)
  open(cid,{{action=jump or "jump.f",wait=-1},{action=dash,wait=-1},
            {action="atk",lever="none",button="LP",wait=-1}})
  local _,rows=draw()
  return (rows[3] or ""):gsub("^%s+",""):gsub("%s*>%s*$","")
end
-- 攻撃の下限も組ごと。レイレイが同方向 5 / それ以外 8 で、それを証明した。
eq("ザベル 前→前 攻撃 0",   atk_row(0x04,"air.f","jump.f"), "3  Auto (0)        Attack : LP")
eq("Q-Bee 前→前 攻撃 0",   atk_row(0x0C,"air.f","jump.f"), "3  Auto (0)        Attack : LP")
eq("Q-Bee 垂直→前 攻撃 0", atk_row(0x0C,"air.f","jump.n"), "3  Auto (0)        Attack : LP")
eq("レイレイ 前→前 攻撃 5", atk_row(0x0D,"air.f","jump.f"), "3  Auto (5)        Attack : LP")
eq("レイレイ 垂直→前 攻撃 8", atk_row(0x0D,"air.f","jump.n"), "3  Auto (8)        Attack : LP")
eq("レイレイ 前→後 攻撃 8", atk_row(0x0D,"air.b","jump.f"), "3  Auto (8)        Attack : LP")
eq("ジェダ 前→前 攻撃 6",  atk_row(0x0F,"air.f","jump.f"), "3  Auto (6)        Attack : LP")
-- 未実測の組は数字を出さない。ザベルの交差はダッシュだけ測ってある。
-- 未実測の組では Recovered と言わない。ジャンプ・ダッシュ・空中ダッシュの
-- あとの「硬直明け」は最速ではないので、その語を出すのは嘘になる。
eq("ザベル 後→前 攻撃 4",   atk_row(0x04,"air.f","jump.b"), "3  Auto (4)        Attack : LP")
eq("ザベル 垂直→後 攻撃 4", atk_row(0x04,"air.b","jump.n"), "3  Auto (4)        Attack : LP")
eq("ザベル 後→後 攻撃 0",  atk_row(0x04,"air.b","jump.b"), "3  Auto (0)        Attack : LP")
-- どちらの表にも行が無いキャラで Not Measured が出ること。ザベル 2 は別形態で
-- 未確認のため、MEASURED_STEP_FLOORS にも DASH_AUTO_TICKS にも
-- 行が無い。デミトリは利用者の指示で 0 の行を持つ。
eq("表に行が無いキャラ",   atk_row(0x0B,"dash.f","jump.f"), "3  Auto (Not Measured)  Attack : LP")
-- 表に行が無いキャラは数字を出さない。ダミーがビシャモンなら空中ダッシュ
-- そのものが無いので、この経路は Custom で組んだときにだけ通る。
eq("ジェダ 前→前 7",   dash_row(0x0F,"jump.f","air.f"), "2  Auto (7)        Air Dash : Forward")
eq("ジェダ 後→前 4",   dash_row(0x0F,"jump.b","air.f"), "2  Auto (4)        Air Dash : Forward")
eq("ジェダ 垂直→前 4", dash_row(0x0F,"jump.n","air.f"), "2  Auto (4)        Air Dash : Forward")
eq("ジェダ 後→前 攻撃 9", atk_row(0x0F,"air.f","jump.b"), "3  Auto (9)        Attack : LP")

-- スーパージャンプはモリガンとリリスだけ。空中ダッシュとは重ならないので、
-- 「スーパージャンプから空中ダッシュ」という並びはどのキャラでも作れない。
for _, c in ipairs({ {0x05,"モリガン",true}, {0x0E,"リリス",true},
                     {0x04,"ザベル",false}, {0x0D,"レイレイ",false},
                     {0x08,"ビシャモン",false} }) do
  local g = group_rows(c[1])
  local has_sj  = g:find("Super Jump", 1, true) ~= nil
  local has_air = g:find("Air Dash", 1, true) ~= nil
  if has_sj ~= c[3] then
    fail(c[2].." の Super Jump", tostring(has_sj), tostring(c[3]))
  elseif has_sj and has_air then
    fail(c[2].." が両方持っている", g, "重ならない")
  else
    print(string.format("  ok %-8s SJ=%-5s AirDash=%s", c[2], tostring(has_sj), tostring(has_air)))
  end
end

eq("ザベル(前後とも)",  action_rows(0x04), "Forward / Back")
eq("レイレイ(前後とも)", action_rows(0x0D), "Forward / Back")
eq("Q-Bee(前だけ)",     action_rows(0x0C), "Forward")
eq("ジェダ(前だけ)",     action_rows(0x0F), "Forward")
for _, c in ipairs({ {0x05,"モリガン"}, {0x08,"ビシャモン"}, {0x00,"ブレッタ"} }) do
  local g = group_rows(c[1])
  if g:find("Air Dash", 1, true) then
    fail(c[2].." に Air Dash が出ている", g, "出ない")
  else
    print("  ok "..c[2].." には分類ごと出ない")
  end
end

print("[7b] 一覧では方向の後ろに (Hold) が出る")
-- タメが繋がっているかはリスト全体の性質で、1 歩ずつ詳細を開いて確かめるのは
-- 途中の抜けを見落とす読み方になる。だから一覧に出す。
open(0x05,{{action="dash.f",wait=-1},
           {action="atk",lever="down-back",button="LP",hold=true,wait=-1},
           {action="atk",lever="down-back",button="LP",wait=-1},
           {action="walk.f",hold=true,wait=3},
           {action="atk",lever="forward",button="EXP",wait=2}})
rows_eq("(Hold) 付きの一覧",{
  ">  1  Auto (Fastest)  Dash : Forward  >",
   "   2  Auto (11)  Attack : Down Back (Hold) + LP  >",
  "   3  Auto (After)  Attack : Down Back + LP  >",
  "   4  3 Ticks  Stand : Forward (Hold)  >",
  "   5  2 Ticks  Attack : Forward + PPP  >",
  "   + Add Step  >",
  "   Save",
  "   Back Without Saving",
  "   Clear All Steps"})

-- 詳細画面には Hold 行があるので、そちらには (Hold) を出さない。
tap("down") tap("LP")
rows_eq("詳細では二重に言わない",{
  ">  Action : Attack  >",
  "     Direction : Down Back  >",
  "     Button : LP  >",
  "     Hold : Yes",
  "   Wait : Auto (11)  >",
  "   Move Step : 2 / 5  >",
  "   Remove This Step  >",
  "   Back"})

print("[8] 一覧の最長行がパネルに収まる")
-- 16 歩目 + Auto (Recovered) + 最長のアクション名(Custom の最長モーションと
-- 最長ボタン)。カーソル行なので < > と末尾の > も付く。
local many={}
for k=1,16 do many[k]={action="custom",lever="HCharge",button="LP+LK",hold=true,wait=-1} end
open(0x05,many)
taps("down",15)
local _,listrows=draw()
local longest=""
for _,l in ipairs(listrows) do if #l>#longest then longest=l end end
local listright=33+#longest*4
print(string.format("     [%s]  %d 文字  右端 %d px", longest, #longest, listright))
if listright<=360 then print("  ok パネル右端 360 に収まる")
else fail("一覧がパネルからはみ出す", listright, "<= 360") end

print("[9] 列が揃っているか - 中身の照合は空白を潰しているので、ここで見る")
-- 番号 / いつ / 何を の 3 列と、行末の > が、それぞれ同じ桁から始まること。
local function all_same(name, t)
  if #t == 0 then fail(name, "行が無い", "1 行以上") return end
  for i = 2, #t do
    if t[i] ~= t[1] then fail(name, table.concat(t, ","), "全部 "..t[1]) return end
  end
  print(string.format("  ok %-16s 全 %d 行が %d 桁目", name, #t, t[1]))
end
open(0x04,{{action="jump.f",wait=-1},
           {action="air.f",wait=-1},
           {action="atk",lever="down",button="HP",wait=-1},
           {action="atk",lever="down-back",button="LP",hold=true,wait=12},
           {action="custom",lever="HCharge",button="LP+LK",wait=-1}})
do
  local _, rows = draw()
  local when, what, door = {}, {}, {}
  for _, l in ipairs(rows) do
    -- 「>  1  Auto (8)   Air Dash : Forward   >」から各列の開始桁を取る。
    local w = l:match("^[>%s]%s%s%d+%s+()")
    if w ~= nil then
      when[#when + 1] = w
      local a = l:match("^[>%s]%s%s%d+%s+%S[^%s]*[^\n]-%s%s+()")
      what[#what + 1] = a or -1
    end
    if l:sub(-1) == ">" then door[#door + 1] = #l end
  end
  all_same("いつ の列", when)
  all_same("何を の列", what)
  all_same("行末の >",  door)
  for _, l in ipairs(rows) do print("     |"..l.."|") end
end


-- SPECIAL: THE GROUP APPEARS ONLY FOR CHARACTERS THAT HAVE ONE.
--
-- Built as the union of every character's moves, each row carrying the ids that
-- have it, so shown() does the filtering the Air Dash list already relies on -
-- and a group whose rows all go, goes. What is pinned is that a character with
-- no entries loses the GROUP, not that it opens an empty screen.
print("\n[9c] 電撃ボタンはビクトルにだけ出る")
-- 他のキャラでは何も起きない選択肢になるので出さない。Air Dash の一覧と同じ規則。
local function button_rows(cid)
  open(cid, {{action="atk", lever="none", button="LP", wait=-1}})
  tap("LP")
  goto_row("Button") tap("LP")
  local out = {}
  local function take()
    local _, rows = draw()
    for _, l in ipairs(rows) do
      local t = l:gsub("^[>%s]+",""):gsub("%s*>*%s*$","")
      if t ~= "" then out[#out+1] = t end
    end
  end
  take()
  -- 12 行までしか描かれないので、下まで送ってもう一度読む。
  for _ = 1, 14 do tap("down") end
  take()
  return table.concat(out, " / ")
end
do
  local vic = button_rows(0x03)
  eq("ビクトルには Elec.MP が出る", vic:find("Elec.MP", 1, true) ~= nil, true)
  eq("弱には電撃版が無い",           vic:find("Elec.LP", 1, true) ~= nil, false)
  eq("4 つとも出る",
     (vic:find("Elec.HP",1,true) and vic:find("Elec.MK",1,true)
      and vic:find("Elec.HK",1,true)) ~= nil, true)
  local mor = button_rows(0x05)
  eq("モリガンには出ない", mor:find("Elec.", 1, true) ~= nil, false)
  eq("普通のボタンは出る", mor:find("MP", 1, true) ~= nil, true)
end
-- 保存済みのステップは、別のキャラを操作していても名前で出る。絞るのは
-- 選ばせるときだけで、名前を引くときではない。
do
  open(0x05, {{action="atk", lever="none", button="Elec.MP", wait=-1}})
  local _, rows = draw()
  eq("別キャラでも Elec.MP と読める",
     rows[1]:find("Elec.MP", 1, true) ~= nil, true)
end

print("\n[10] Special Move")
seq_special_list = function(cid)
  if cid == 0x05 then return {
    { name = "Shadow Blade",     command = { type = "motion", motion = "DPF", button_group = "P" } },
    { name = "Finishing Shower", command = { type = "sequence",
                                             sequence = {{"MP"},{"LP"},{"back"},{"LK"},{"MK"}} } } }
  elseif cid == 0x02 then return {
    { name = "Climb Razor", command = { type = "motion", motion = "DPF", button_group = "K" } } }
  elseif cid == 0x08 then return {
    -- 表示名だけ違う技。id は "sp.K.D." のままで、行に出るのは Karame Dama。
    { name = "K.D.", label = "Karame Dama",
      command = { type = "motion", motion = "HCF", button_group = "P" } } }
  elseif cid == 0x09 then return {
    -- 分類は is_ex で割れる。ボタンの形とは一致しないので、両方を組み合わせる。
    { name = "Plain",     command = { type="motion", motion="QCF", button_group="P" } },
    { name = "ES Plain",  command = { type="motion", motion="QCF",
                                      allowed_buttons={"EXP"} } },   -- EX 分類ではない
    { name = "EX One",    is_ex = true,
      command = { type="motion", motion="QCB", allowed_buttons={"EXK"} } },
    { name = "EX Two",    is_ex = true,
      command = { type="motion", motion="QCB", allowed_buttons={"EXP","EXK"} } },
    { name = "EX Pair",   is_ex = true,
      command = { type="motion", motion="HCF", allowed_buttons={"LK+MK"} } },
    { name = "EX Single", is_ex = true,
      command = { type="motion", motion="DPF", button_group="K" } } }
  end
  return nil
end

eq("モリガンには Special が出る",
   group_rows(0x05):find("Special", 1, true) ~= nil, true)
eq("ガロンにも出る",
   group_rows(0x02):find("Special", 1, true) ~= nil, true)
eq("収録の無いキャラには分類ごと出ない",
   group_rows(0x0A):find("Special", 1, true) ~= nil, false)

-- 保存済みステップは、別のキャラを操作していても名前で出る。groups(all) が
-- 和集合を返すのが効いている場所で、ここが崩れると行が生の id になる。
open(0x0A,{{action="sp.Shadow Blade",button="HP",wait=-1}})
do
  local _,rows = draw()
  eq("別キャラでも名前が出る",
     rows[1]:find("Shadow Blade", 1, true) ~= nil, true)
end
-- 親分類は 2 つ。割るのはゲームデータの isEX で、ボタンの形ではない。
-- ES Plain は PPP で入れる通常必殺技なので Special 側に残る。
do
  local g = group_rows(0x09)
  eq("Special が出る",     g:find("Special", 1, true) ~= nil, true)
  eq("EX Special も出る",  g:find("EX Special", 1, true) ~= nil, true)
end
local function side(cid, group)
  open(cid, {{action="atk", lever="none", button="LP", wait=-1}})
  tap("LP") tap("LP")
  goto_row(group) tap("LP")
  local _, rows = draw()
  local out = {}
  for _, l in ipairs(rows) do
    local t = l:gsub("^[>%s]+",""):gsub("%s*>*%s*$","")
    if t ~= "Back" and t ~= "" then out[#out+1] = t end
  end
  return table.concat(out, " / ")
end
-- 追い打ちは別の一覧から来る。Special のスタブに何も足していないのに
-- 分類が増えることで、混ざっていないことが分かる。
seq_pursuit_list = function(cid)
  if cid == 0x09 then return {
    { name = "Pursuit", command = { type="motion", motion="up",
                                    allowed_buttons={"LP","MP","HP","LK","MK","HK"} } },
    { name = "OTG Slap Chop", label = "Togakubi Sarashi",
      command = { type="motion", motion="22", allowed_buttons={"EXP"} } } }
  end
  return nil
end
eq("Special 側",    side(0x09, "Special"),    "Plain / ES Plain")
eq("EX Special 側", side(0x09, "EX Special"), "EX One / EX Two / EX Pair / EX Single")
eq("Pursuit 側",    side(0x09, "Pursuit"),    "Pursuit / Togakubi Sarashi")
-- 追い打ちの無いキャラでは分類ごと消える。
eq("追い打ちが無ければ分類ごと出ない",
   group_rows(0x05):find("Pursuit", 1, true) ~= nil, false)
do
  -- 見出しと技名が同じときは 1 回だけ書く。"Pursuit : Pursuit" は同じことを
  -- 二度言っている。
  open(0x09, {{action="sp.Pursuit", button="LP", wait=-1}})
  local _, rows = draw()
  eq("見出しと同名なら 1 回だけ",
     rows[1]:find("Pursuit : Pursuit", 1, true) ~= nil, false)
  eq("行には出る", rows[1]:find("Pursuit", 1, true) ~= nil, true)
end

-- ボタン行は選ぶ余地があるときだけ。PPP か KKK が 1 つきりなら行は出ないが、
-- ステップにはそのボタンが入っていないと、押されない入力になる。
local function pick(cid, group, move)
  open(cid, {{action="atk", lever="none", button="LP", wait=-1}})
  tap("LP") tap("LP")
  goto_row(group) tap("LP")
  goto_row(move) tap("LP")
  local _, rows = draw()
  local shown = table.concat(rows, " | ")
  goto_row("Back") tap("LP")
  goto_row("Save") tap("LP")
  local sv = training_settings.action_sequences.reversal[tostring(cid)]
  return shown, sv.steps[1].button
end
do
  local rows, btn = pick(0x09, "EX Special", "EX One")
  eq("EX 1 つきりはボタン行を出さない", rows:find("Button", 1, true) ~= nil, false)
  eq("それでもボタンは入っている",       btn, "EXK")
end
do
  local rows, btn = pick(0x09, "EX Special", "EX Two")
  eq("PPP か KKK を選べる技は行が出る", rows:find("Button", 1, true) ~= nil, true)
  eq("既定は先頭",                       btn, "EXP")
end
do
  local rows, btn = pick(0x09, "EX Special", "EX Pair")
  eq("LK+MK は行が出る", rows:find("Button : LK+MK", 1, true) ~= nil, true)
  eq("保存も LK+MK",     btn, "LK+MK")
end
do
  local rows = pick(0x09, "EX Special", "EX Single")
  eq("強度を選ぶ EX は行が出る", rows:find("Button", 1, true) ~= nil, true)
end

-- 行に出るのは label。id はゲームデータの名前のままなので、保存済みの
-- ステップは表示を変えても引き続き解決する。
open(0x08, {{action="sp.K.D.", button="HP", wait=-1}})
do
  local _, rows = draw()
  eq("行には Mizuumi 表記が出る",   rows[1]:find("Karame Dama", 1, true) ~= nil, true)
  eq("行にゲームデータ名は出ない",  rows[1]:find("K.D.", 1, true) ~= nil, false)
end

seq_special_list = nil
seq_pursuit_list = nil

-- 本物の charMoves が is_ex を渡していること。
--
-- 上のスタブはエディタ側だけを見ている。分類を割る値そのものが来ていなければ
-- EX Special は空のまま消え、全部が Special に入る - スタブでは見えない。
do
  local M = dofile("charMoves.lua")
  local pairs_seen, bad = 0, 0
  for cid = 0x00, 0x18 do
    ram[0xFF8400 + 0x382] = cid
    ram[0xFF8800 + 0x382] = cid
    local list = seq_special_list(cid)
    if list ~= nil then
      local flag = {}
      for _, m in ipairs(M.get_player_movelists().P2.all) do flag[m.name] = (m.isEX == true) end
      for _, m in ipairs(list) do
        pairs_seen = pairs_seen + 1
        if (m.is_ex == true) ~= flag[m.name] then bad = bad + 1 end
      end
    end
  end
  eq("is_ex を照合した技があること", pairs_seen > 50, true)
  eq("is_ex はゲームデータの isEX と一致", bad, 0)
  -- 分類が両側とも空でないこと。片側に寄っていたら割る意味が無い。
  ram[0xFF8400 + 0x382] = 0x05
  ram[0xFF8800 + 0x382] = 0x05
  local ex, plain = 0, 0
  for _, m in ipairs(seq_special_list(0x05)) do
    if m.is_ex then ex = ex + 1 else plain = plain + 1 end
  end
  eq("モリガンの EX 側が空でない",    ex > 0, true)
  eq("モリガンの Special 側が空でない", plain > 0, true)
  -- 追い打ちは Special と排他。両方に出たら、どちらかの分類が嘘になる。
  local both = 0
  for cid = 0x00, 0x18 do
    ram[0xFF8400 + 0x382] = cid
    ram[0xFF8800 + 0x382] = cid
    local sp = seq_special_list(cid) or {}
    local pu = seq_pursuit_list(cid) or {}
    for _, a in ipairs(sp) do
      for _, b in ipairs(pu) do if a.name == b.name then both = both + 1 end end
    end
  end
  eq("Special と追い打ちに同じ技は出ない", both, 0)

  -- ゲームデータが空中版しか名乗っていない技。ザベルのデスハリケーンは
  -- 0x02 "Air Death Hurricane" だけがあり、isReversalMove が false だったので
  -- どの一覧にも出ていなかった。QCB + K は地上でも同じコマンドなので、
  -- 空中専用ではない = "(Air)" は付かない。
  ram[0xFF8400 + 0x382] = 0x04
  ram[0xFF8800 + 0x382] = 0x04
  local dh = nil
  for _, m in ipairs(seq_special_list(0x04) or {}) do
    if m.name == "Air Death Hurricane" then dh = m end
  end
  eq("デスハリケーンが出る", dh ~= nil, true)
  eq("行は Death Hurricane", dh and dh.label, "Death Hurricane")
  eq("(Air) は付かない", dh and dh.label:find("(Air)", 1, true) ~= nil, false)
  eq("コマンドは QCB", dh and dh.command.motion, "QCB")
  -- 値を書き込む経路には出さない。0x02 は空中版の値で、地上で書くと
  -- 「進行中の行動を上書きする」危険な形になる。他の "Air ..." が全て
  -- isReversalMove = false なのはそのため。
  local rev = M.get_player_movelists().P2.reversal_names
  local in_cs = false
  for _, n in ipairs(rev) do if n == "Air Death Hurricane" then in_cs = true end end
  eq("Character Specific には出さない", in_cs, false)
  -- 旗そのもの。isReversalMove を立てて直すのは間違い。
  local cm = io.open("charMoves.lua"):read("*a")
  eq("値の行は isReversalMove = false のまま",
     cm:find('name = "Air Death Hurricane",    conditions = {}, isReversalMove = false', 1, true) ~= nil,
     true)
  eq("代わりに isActionStepOnly で拾う",
     cm:find("isActionStepOnly = true", 1, true) ~= nil, true)

  -- 空中専用の技は、同じコマンドの地上技と 1 行にまとめない。まとめると
  -- 片方が一覧から消える。行の名前で見分けが付くことも要る。
  ram[0xFF8400 + 0x382] = 0x06
  ram[0xFF8800 + 0x382] = 0x06
  local has_ground, has_air = false, false
  for _, m in ipairs(seq_special_list(0x06)) do
    if m.label == "Mummy Drop" then has_ground = true end
    if m.label == "Royal Judgement (Air)" then has_air = true end
  end
  eq("地上のミイラドロップが出る", has_ground, true)
  eq("空中の王家の裁きも別行で出る", has_air, true)
  -- 空中と書かれるのは air_only の技だけ。全部に付いたら意味が無い。
  local air_n, all_n = 0, 0
  for cid = 0x00, 0x18 do
    ram[0xFF8400 + 0x382] = cid
    ram[0xFF8800 + 0x382] = cid
    for _, m in ipairs(seq_special_list(cid) or {}) do
      all_n = all_n + 1
      if m.label:find("(Air)", 1, true) then air_n = air_n + 1 end
    end
  end
  eq("(Air) が付く技はある",   air_n > 0, true)
  eq("(Air) が全部には付かない", air_n < all_n / 4, true)
  ram[0xFF8400 + 0x382] = 0x08
  ram[0xFF8800 + 0x382] = 0x08
  local bi = seq_pursuit_list(0x08) or {}
  eq("ビシャモンの追い打ちは 2 つ", #bi, 2)
  -- 同名の技はいまのダミーの表から引くこと。"Pursuit" は 15 の表すべてに
  -- 実在するので、pairs() で最初に見つけた表を返すと別キャラのものになる。
  -- 中身が同じでもテーブルは別物なので、同一性で見分けられる。
  local seen = {}
  local wrong = 0
  for cid = 0x00, 0x18 do
    ram[0xFF8400 + 0x382] = cid
    ram[0xFF8800 + 0x382] = cid
    local l = seq_pursuit_list(cid)
    if l ~= nil then
      local got = seq_special_command("Pursuit")
      if got ~= l[1].command then wrong = wrong + 1 end
      seen[tostring(l[1].command)] = true
    end
  end
  eq("追い打ちはいまのダミーの表から引く", wrong, 0)
  -- 表が 1 つしかないなら上の照合は素通りしてしまう。
  local n_tables = 0
  for _ in pairs(seen) do n_tables = n_tables + 1 end
  eq("表はキャラごとに別物", n_tables > 10, true)
  seq_special_list = nil
  seq_special_command = nil
end

print(fails==0 and "\n全て通った" or ("\n"..fails.." 件 NG"))
os.exit(fails==0 and 0 or 1)
