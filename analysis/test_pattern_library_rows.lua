-- ACTION PATTERN LIBRARY - THE ROWS, AND WHETHER THEY FIT.
--
-- Written BEFORE the screens, on purpose. The ported implementation was built
-- the other way round and four things were broken the moment anyone walked it
-- (design_action_pattern_library.md), so the order is reversed here: pin what
-- the screens say, then make them say it.
--
-- WIDTH IS THE POINT OF THIS FILE. The panel is 360px, the glyphs are 4px and
-- rows start at x=33, so a row has 81 characters before it runs off the edge.
-- A name long enough to overflow is what this catches, and it catches it here
-- rather than in front of the user after a full FBNeo restart.
--
-- Run from scripts/ - the dofile below is relative.
--   cd scripts && lua5.1 ../analysis/test_pattern_library_rows.lua
local ram={} memory={readbyte=function(a) return ram[a] or 0 end}
gui={text=function() end, box=function() end}
local FC=0 emu={framecount=function() FC=FC+1 return FC end}
function mark_training_settings_dirty() end
panel_fill_color=0 panel_outline_color=0
text_selected_color=0 text_default_color=0 text_default_border_color=0 text_disabled_color=0
local _csrc = io.open("controller.lua"):read("*a")
local _cs = _csrc:find("function make_input_sequence", 1, true)
local _ce = _csrc:find("\nend", _csrc:find("return _sequence", _cs, true), true)
assert(_cs and _ce, "make_input_sequence が controller.lua に見つからない")
assert(loadstring(_csrc:sub(_cs, _ce + 4)))()
local P1={input={pressed={},down={}}} player_objects={P1}
function check_input_down_autofire(p,name) return p.input.down[name] == true end
local _R = dofile("actionSequenceRunner.lua")
seq_auto_ticks = _R.auto_ticks_for
seq_auto_needs_number = _R.auto_needs_number
training_settings={action_sequences={}, action_patterns={}}
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
  P1.input.pressed={} P1.input.down={} E.registerBefore()
  P1.input.pressed={[n]=true} P1.input.down={[n]=true} E.registerBefore()
  P1.input.pressed={} P1.input.down={}
end
local function taps(n,k) for _=1,k do tap(n) end end

-- Rows are read exactly where the editor draws them: x=33, y from 37 in tens,
-- and the panel's help text below 160 is not part of the list.
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
local function selected()
  local _,rows=draw()
  for _,r in ipairs(rows) do if r:sub(1,1)==">" then return r end end
  return ""
end
local function goto_row(text)
  for _=1,16 do
    if selected():find(text,1,true) then return end
    tap("down")
  end
  fail("行が見つからない ["..text.."]", selected(), text)
end

-- Padding inside a row comes from the longest label in the SAME list, so one
-- extra pattern would rewrite every expected string. Content is compared here;
-- the column alignment is checked on its own in [6].
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

local function one_step()
  return { { action="atk", lever="none", button="LP", wait=-1 } }
end
local function open(cid, items)
  ram[0xFF8B82]=cid
  training_settings.action_patterns.reversal =
    { [tostring(cid)] = { version=1, items=items } }
  E.open_patterns("reversal")
end

print("[1] 一覧 - チェック、通し番号、名前、扉。下に New / Add / Back")
open(0x05, {
  { name="anti-Bishamon rushdown", use=true,  steps=one_step() },
  { name="vs long range poke",     use=false, steps=one_step() },
  { name="wakeup DP bait",         use=true,  steps=one_step() },
})
title_eq("見出しは ACTION PATTERNS", "REVERSAL ACTION PATTERNS: Morrigan")
rows_eq("一覧の行", {
  ">  [x] 01  anti-Bishamon rushdown  >",
  "   [ ] 02  vs long range poke  >",
  "   [x] 03  wakeup DP bait  >",
  "   New  >",
  "   Add from current Steps  >",
  "   Export to a File  >",
  "   Import from a File  >",
  "   Back",
})

print("")
print("[2] 1 件も無いとき - New / Add / Back だけが残る")
open(0x05, {})
rows_eq("空の一覧", {
  ">  New  >",
  "   Add from current Steps  >",
  "   Export to a File  >",
  "   Import from a File  >",
  "   Back",
})

print("")
print("[3] 項目の画面 - Edit が先頭、Use in Random は行の上で切り替わる")
open(0x05, {
  { name="anti-Bishamon rushdown", use=true, steps=one_step() },
})
tap("LP")
title_eq("見出しに通し番号が付く", "REVERSAL ACTION PATTERNS: Morrigan  >  01  anti-Bishamon rushdown")
rows_eq("項目の行", {
  ">  Edit  >",
  "   Use in Random : Yes",
  "   Rename  >",
  "   Copy",
  "   Move  >",
  "   Delete  >",
  "   Export this Pattern  >",
  "   Back",
})

print("")
print("[4] Edit に入ったら見出しはエディタのものへ切り替わる")
-- パンくずを継ぎ足すと 105 字 = 453px で溢れる (設計メモの実測)。継ぎ足さず、
-- 「いまステップ列を編集している」と名乗らせる。
tap("LP")
title_eq("エディタの見出し", "REVERSAL ACTION STEPS: Morrigan  >  01  anti-Bishamon rushdown")

print("")
print("[5] Edit から左で戻るのは一覧であって、メニューではない")
tap("left")
title_eq("項目の画面へ戻る", "REVERSAL ACTION PATTERNS: Morrigan  >  01  anti-Bishamon rushdown")
tap("left")
title_eq("一覧へ戻る", "REVERSAL ACTION PATTERNS: Morrigan")
eq("まだ開いている", E.is_active(), true)

print("")
print("[6] 幅 - どの行も 81 字を超えない")
-- 名前に使えるのは 66 字。"[x] 256  " の 9 字と行頭の 3 字、扉の 3 字を引いた残り。
local LONG = string.rep("W", 66)
open(0x05, {
  { name=LONG, use=true, steps=one_step() },
  { name="short", use=false, steps=one_step() },
})
local _,rows = draw()
local widest, worst = 0, ""
for _,r in ipairs(rows) do
  if #r > widest then widest, worst = #r, r end
end
eq("最長 66 字の名前でも 81 字以内", widest <= 81, true)
if widest > 81 then print("     " .. widest .. " 字: [" .. worst .. "]") end
-- 扉は列で揃う。揃っていないと目が滑る。
local cols = {}
for _,r in ipairs(rows) do
  if r:sub(-1) == ">" then cols[#r] = true end
end
local n = 0
for _ in pairs(cols) do n = n + 1 end
eq("扉が 1 つの列に揃っている", n, 1)

-- 見出しも溢れないこと。最長は Dark Gallon。
ram[0xFF8B82]=0x12
E.open_patterns("reversal")
local t = draw()
eq("見出しが 81 字以内 (Dark Gallon)", #t <= 81, true)
tap("LP")
local t2 = draw()
eq("項目の見出しも 81 字以内", #t2 <= 81, true)

print("")
print("[7] Rename - 画面が先、箱はその次のフレーム")
-- 実際に PowerShell を起動させない。ここが本物だとテストが 39 秒止まる。
local asked, answer = nil, nil
local calls = 0
E.prompt_name = function(cur) calls = calls + 1 ; asked = cur ; return answer end

open(0x05, { { name="old name", use=true, steps=one_step() } })
tap("LP")
goto_row("Rename")
tap("LP")
eq("押しただけでは箱は開かない", calls, 0)
-- 空行も行として描かれる (印の 3 字だけ)。縦の間が知らせの読みやすさそのもの。
rows_eq("知らせの行", {
  "   USE YOUR KEYBOARD.",
  "   ",
  "   A window has opened for the name of this pattern.",
  "   The game is stopped until you close it.",
  "   ",
  "   If it is hiding behind this one, Alt+Tab to it.",
  "   Cancel there changes nothing.",
})
eq("カーソルは出ない", selected(), "")
-- ここまでで画面は描かれた。次のフレームで箱が開く。
answer = "vs Kai meaty"
E.registerBefore()
eq("箱が開いた", calls, 1)
eq("いまの名前が渡る", asked, "old name")
title_eq("項目の画面へ戻っている", "REVERSAL ACTION PATTERNS: Morrigan  >  01  vs Kai meaty")
tap("left")
rows_eq("名前が変わった", {
  ">  [x] 01  vs Kai meaty  >",
  "   New  >",
  "   Add from current Steps  >",
  "   Export to a File  >",
  "   Import from a File  >",
  "   Back",
})

print("")
print("[8] Rename のキャンセルは何も変えない")
calls = 0 answer = nil
tap("LP")
goto_row("Rename")
tap("LP")
draw()
E.registerBefore()
eq("箱は開いた", calls, 1)
tap("left")
rows_eq("名前はそのまま", {
  ">  [x] 01  vs Kai meaty  >",
  "   New  >",
  "   Add from current Steps  >",
  "   Export to a File  >",
  "   Import from a File  >",
  "   Back",
})

print("")
print("[9] New - 名前が付くまで何も作らない")
open(0x05, {})
calls = 0 answer = nil
goto_row("New")
tap("LP")
draw()
E.registerBefore()
eq("箱は開いた", calls, 1)
rows_eq("キャンセルなら増えない", {
  ">  New  >",
  "   Add from current Steps  >",
  "   Export to a File  >",
  "   Import from a File  >",
  "   Back",
})
answer = "anti-Zabel"
goto_row("New")
tap("LP")
draw()
E.registerBefore()
title_eq("そのままエディタへ入る", "REVERSAL ACTION STEPS: Morrigan  >  01  anti-Zabel")
tap("left")
title_eq("戻ると新しい項目の画面", "REVERSAL ACTION PATTERNS: Morrigan  >  01  anti-Zabel")
tap("left")
rows_eq("作られていて、印も付いている", {
  ">  [x] 01  anti-Zabel  >",
  "   New  >",
  "   Add from current Steps  >",
  "   Export to a File  >",
  "   Import from a File  >",
  "   Back",
})

print("")
print("[10] 描けない文字は落とし、66 字で切る")
open(0x05, { { name="keep", use=false, steps=one_step() } })
tap("LP")
goto_row("Rename")
tap("LP")
draw()
-- gui.text は ASCII しか描けない。混ざった名前は読める部分だけ残す。
answer = "ab" .. string.char(0xE3, 0x81, 0x82) .. "cd"
E.registerBefore()
tap("left")
rows_eq("非 ASCII を落とす", {
  ">  [ ] 01  abcd  >",
  "   New  >",
  "   Add from current Steps  >",
  "   Export to a File  >",
  "   Import from a File  >",
  "   Back",
})
tap("LP")
goto_row("Rename")
tap("LP")
draw()
answer = string.rep("Z", 200)
E.registerBefore()
tap("left")
local _,rows = draw()
eq("66 字で切れている", #(rows[1]:match("%d%d%s+(Z+)") or ""), 66)
eq("行は 81 字に収まる", #rows[1] <= 81, true)

print("")
print("[11] 深いところまで降りても見出しが溢れない - 削られるのは名前")
-- 設計メモの実測: パンくずを全部並べると 105 字 = 453px で溢れる。名前を
-- パンくずの「前」に置き、足りなければ名前のほうを削る。パンくずは「いま
-- どこにいるか」なので、そちらを削ると何も分からなくなる。
open(0x12, { { name=string.rep("W", 66), use=true, steps=one_step() } })
local deepest = ""
local function step_in(what)
  local t = draw()
  eq(what .. " で 81 字以内 (" .. #t .. ")", #t <= 81, true)
  deepest = t
end
step_in("一覧")
tap("LP") step_in("項目")
tap("LP") step_in("エディタ")
tap("LP") step_in("ステップ")
goto_row("Action") tap("LP") step_in("Action")
tap("LP") step_in("その下")
-- いちばん深いところでも、末尾はパンくずのままであること。
eq("末尾はパンくず", deepest:find("  >  ", 1, true) ~= nil, true)
eq("名前は削られている", deepest:find(string.rep("W", 66), 1, true), nil)
eq("通し番号は残っている", deepest:find("  >  01", 1, true) ~= nil, true)

if fails == 0 then print("") print("全て通った") else print(fails .. " 件 NG") os.exit(1) end
