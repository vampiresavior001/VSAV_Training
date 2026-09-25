-- EDITOR OPERATIONS: ADD, REORDER, DELETE, MIGRATE.
--
-- Drives the editor with real input and checks the draft that comes out of
-- Save. Everything here used to print and never assert, which meant a step that
-- silently stopped moving still read as a pass - and that is exactly what
-- happened when the Order screen changed shape.
--
-- Rows are found BY NAME, not by counting. Adding a row to the detail screen
-- (Hold did) must not turn these into arithmetic puzzles that quietly break.
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_editor_ops.lua
local ram={} memory={readbyte=function(a) return ram[a] or 0 end}
gui={text=function() end, box=function() end}
local FC=0
emu={framecount=function() FC=FC+1 return FC end}
function mark_training_settings_dirty() end
panel_fill_color=0 panel_outline_color=0
text_selected_color=0 text_default_color=0 text_default_border_color=0 text_disabled_color=0
-- The real one: the Hold row is offered from what a motion actually compiles
-- to, so a stub would decide which rows exist.
local _csrc = io.open("controller.lua"):read("*a")
local _cs = _csrc:find("function make_input_sequence", 1, true)
local _ce = _csrc:find("\nend", _csrc:find("return _sequence", _cs, true), true)
assert(_cs and _ce, "make_input_sequence が controller.lua に見つからない")
assert(loadstring(_csrc:sub(_cs, _ce + 4)))()
local P1={input={pressed={},down={}}}
player_objects={P1}
-- rate も控える。Wait 行だけ数字の上を速く歩くので、その速さがどこで
-- 切り替わるかを見るために要る。
local autofire_rate_seen = {}
function check_input_down_autofire(p,name,rate)
  autofire_rate_seen[name] = rate
  return p.input.down[name] == true
end
training_settings={action_sequences={}}
ram[0xFF8B82]=0x05
local E=dofile("actionSequenceEditor.lua")

local function trim(x) return (x:gsub("^%s+", ""):gsub("%s+$", "")) end
local fails=0
local function want(what, got, w)
  if got ~= w then
    fails = fails + 1
    print("  NG "..what.."   got ["..tostring(got).."]  want ["..tostring(w).."]")
  end
end

local function tap(name)
  -- armed ゲート: 押していない回で arm され、次の回で押しが読まれる
  P1.input.pressed={}; P1.input.down={}
  E.registerBefore()
  P1.input.pressed={[name]=true}; P1.input.down={[name]=true}
  E.registerBefore()
  P1.input.pressed={}; P1.input.down={}
end

-- The row the cursor is on, read off what the editor actually draws.
local function selected()
  local sel=nil
  gui.text=function(x,y,t)
    if x==33 and y>=37 and y<=160 and t:sub(1,1)==">" then sel=t end
  end
  E.guiRegister()
  gui.text=function() end
  return sel or ""
end

-- Walk down to the row whose label contains `text`. Names, not row numbers:
-- the detail screen gained a Hold row and every count in here would have been
-- wrong by one, silently.
local function goto_row(text)
  -- 上端まで戻ってから下る。Wait 画面はカーソルが現在の設定の行に乗った状態で
  -- 開くので、下るだけでは自分より上の行へ行けない。上下とも端で止まるので、
  -- 余分に上を押しても 1 行目に着くだけ。
  for _=1,24 do tap("up") end
  for _=1,24 do
    if selected():find(text, 1, true) then return true end
    tap("down")
  end
  fails = fails + 1
  print("  NG 行が見つからない ["..text.."]   いま ["..selected().."]")
  return false
end

local function steps()
  local per=(training_settings.action_sequences.reversal or {})["5"]
  return per and per.steps or nil
end
local function shape()
  local st=steps()
  if st==nil then return "(保存なし)" end
  local out={}
  for _,s in ipairs(st) do out[#out+1]=string.format("%s(wait=%s)", s.action, tostring(s.wait)) end
  return #st.." 歩  "..table.concat(out,"  ")
end
local function save_and_close()
  goto_row("Save")
  tap("LP")
end

print("[1] 旧形式 3 種を開く → 移行されるか")
training_settings.action_sequences.reversal = { version=1, steps={
  {action="n.MP", wait=0},
  {action="dash", lever="forward dash", button="LP", wait=5},
  {action="c.HK", wait=-1} } }
E.open("reversal")
save_and_close()
do
  local st=steps()
  want("歩数", st and #st, 3)
  if st and #st==3 then
    want("n.MP → atk",  st[1].action, "atk")
    want("n.MP の方向", st[1].lever,  "none")
    want("n.MP のボタン", st[1].button, "MP")
    want("dash → dash.f", st[2].action, "dash.f")
    want("dash のボタンは落ちる", st[2].button, nil)
    want("c.HK → atk",  st[3].action, "atk")
    want("c.HK の方向", st[3].lever,  "down")
  end
  print("  "..shape())
end

print("[2] ステップ追加")
E.open("reversal")
goto_row("+ Add Step")
tap("LP")                      -- 追加して詳細画面へ
tap("left")                    -- 一覧へ戻る
save_and_close()
want("追加後の歩数", steps() and #steps(), 4)
print("  "..shape())

print("[3] 並べ替え - 1 歩目を 2 番目へ")
E.open("reversal")
local before1 = steps()[1].action
local before2 = steps()[2].action
tap("LP")                      -- 1 歩目の詳細へ
goto_row("Move Step")
tap("LP")                      -- Order 画面
tap("right")                   -- Wait と同じで、左右が値を動かす
goto_row("Back") tap("LP")     -- Order 画面を抜ける
tap("left")                    -- 一覧へ
save_and_close()
do
  local st=steps()
  want("1 番目に来たもの", st and st[1].action, before2)
  want("2 番目に来たもの", st and st[2].action, before1)
  print("  "..shape())
end

print("[4] 削除 - 2 歩目")
E.open("reversal")
local n_before = #steps()
local third = steps()[3].action
tap("down") tap("LP")          -- 2 歩目の詳細へ
goto_row("Remove This Step")
tap("LP")                      -- 確認画面
goto_row("Yes, remove it")
tap("LP")
save_and_close()
do
  local st=steps()
  want("削除後の歩数", st and #st, n_before-1)
  want("3 歩目が 2 歩目に繰り上がる", st and st[2].action, third)
  print("  "..shape())
end

print("[5] Add Step は最終行の複製か - LP を並べる作業を短くするため")
-- 以前の「1 行目のコピーが出続けている」とは別物。あれはどのステップも既定が
-- Dash Forward だったせいでそう見えていただけで、何も複製していなかった。
training_settings.action_sequences.reversal = { ["5"] = { version=1, steps={
  {action="atk", lever="down-back", button="HK", hold=true, wait=7} } } }
E.open("reversal")
goto_row("+ Add Step")
tap("LP")
tap("left")
save_and_close()
do
  local st=steps()
  want("歩数", st and #st, 2)
  if st and #st == 2 then
    local a, b = st[1], st[2]
    want("action", b.action, a.action)
    want("lever",  b.lever,  a.lever)
    want("button", b.button, a.button)
    want("hold",   b.hold,   a.hold)
    want("wait",   b.wait,   a.wait)
  end
end
-- 空リストの 1 歩目だけは複製元が無いので、まっさらな Neutral。
training_settings.action_sequences.reversal = { ["5"] = { version=1, steps={} } }
E.open("reversal")
save_and_close()
want("空リストの 1 歩目", steps() and steps()[1].action, "neutral")

print("[6] Hold は保持できない形に変えたら消える")
training_settings.action_sequences.reversal = { ["5"] = { version=1, steps={
  {action="walk.f", hold=true, wait=0} } } }
E.open("reversal")
tap("LP")                      -- 詳細へ
goto_row("Action") tap("LP")   -- 分類へ
goto_row("Stand") tap("LP")    -- Stand の中身へ
goto_row("Neutral") tap("LP")  -- Stand Neutral: 保持するものが無い
tap("left")
save_and_close()
do
  local st=steps()
  want("action", st and st[1].action, "neutral")
  want("hold は捨てられる", st and st[1].hold, nil)
end


-- MENU BUTTON WHILE EDITING: THE THREE ROWS, AND WHAT EACH ONE LEAVES BEHIND.
--
-- The draft only reaches training_settings on Save, so this button used to
-- take an edit with it silently. What is checked here is the DRAFT after each
-- of the three answers, not the screen: a row that reads right and saves
-- nothing is the failure this is for.
local function all_rows()
  local out={}
  gui.text=function(x,y,t)
    if x==33 and y>=37 and y<=160 then out[#out+1]=t:gsub("^[>%s]+",""):gsub("%s*>%s*$","") end
  end
  E.guiRegister()
  gui.text=function() end
  return out
end

print("\n[7] メニューボタンで閉じようとしたとき")
training_settings.action_sequences.reversal = { ["5"] = { version=1, steps={
  {action="dash.f", wait=0} } } }
E.open("reversal")
-- 2 歩目を足して、保存していない差分を作る。
goto_row("Add Step") tap("LP")
goto_row("Back") tap("LP")
want("下書きは 2 歩", #all_rows()>=2, true)
want("まだ保存されていない", #(steps() or {}), 1)

want("request_close が引き取る", E.request_close(), true)
E.registerBefore()
do
  local r=all_rows()
  want("行 1", r[1], "Cancel")
  want("行 2", r[2], "Save and Close")
  want("行 3", r[3], "Close Without Saving")
  want("行はこの 3 つだけ", #r, 3)
end

-- Cancel: 何も起きない。エディタは開いたまま、保存もされない。
tap("LP")
want("Cancel でエディタは開いたまま", E.is_active(), true)
want("Cancel で保存されない", #(steps() or {}), 1)

-- 保存せず閉じる: エディタは閉じ、保存済みは 1 歩のまま。
E.request_close() E.registerBefore()
goto_row("Close Without Saving") tap("LP")
want("保存せず閉じた", E.is_active(), false)
want("保存済みは元のまま", #(steps() or {}), 1)
want("閉じていれば引き取らない", E.request_close(), false)

-- 保存して閉じる: 2 歩目が書かれる。
E.open("reversal")
goto_row("Add Step") tap("LP")
goto_row("Back") tap("LP")
E.request_close() E.registerBefore()
goto_row("Save and Close") tap("LP")
want("保存して閉じた", E.is_active(), false)
want("2 歩目が保存された", #(steps() or {}), 2)

-- MP RESET: THE VALUE AND THE MODE, BOTH.
--
-- Wait carries two pieces of state on one line - the number in st.wait and the
-- connection mode in st.timing - and MP is the only key that touches both. The
-- screen cannot show the second one: from Auto (Late Cancel), an MP that
-- cleared the number but left the mode would read "0 Ticks" and still compile
-- as a cancel the next time it ran. So what is pinned here is the SAVED draft,
-- not the row.
print("\n[8] Wait 画面 - 縦のリストと Fixed Ticks")
-- 値をスクロールする 1 行から、モードを選ぶ縦のリストへ変わった。数値は
-- Fixed Ticks の下の画面に移り、そこだけが左右で動く。
training_settings.action_sequences.reversal = { ["5"] = { version=1, steps={
  {action="atk", lever="none", button="LP", wait=0},
  {action="atk", lever="none", button="MP", wait=15} } } }
E.open("reversal")
goto_row("2 ") tap("LP")
goto_row("Wait") tap("LP")
-- 開いたときのカーソルは、いま選ばれている行に乗る。
want("いまの設定の行に乗って開く",
     selected():find("Fixed Ticks : 15", 1, true) ~= nil, true)
goto_row("Fixed Ticks") tap("LP")
want("数値画面は 15 Ticks", selected():find("15 Ticks", 1, true) ~= nil, true)
tap("MP")
want("MP で下限の 1 Ticks", selected():find("1 Ticks", 1, true) ~= nil, true)
want("MP で 0 Ticks にはならない", selected():find("0 Ticks", 1, true) ~= nil, false)
goto_row("Back") tap("LP")     -- 数値 -> Wait
goto_row("Back") tap("LP")     -- Wait -> ステップ詳細
goto_row("Back") tap("LP")     -- 詳細 -> 一覧
save_and_close()
do
  local st = steps()
  want("保存された wait は 1", st and st[2].wait, 1)
  want("timing は付かない", st and st[2].timing, nil)
end

-- モードは行を選ぶ。選んだ時点で wait は Auto に戻る。
training_settings.action_sequences.reversal = { ["5"] = { version=1, steps={
  {action="atk", lever="none", button="LP", wait=0},
  {action="atk", lever="none", button="MP", wait=15} } } }
E.open("reversal")
goto_row("2 ") tap("LP")
goto_row("Wait") tap("LP")
goto_row("Late Cancel") tap("LP")
want("選ぶと詳細へ戻り、行に出る",
     selected():find("Auto (Late Cancel)", 1, true) ~= nil, true)
goto_row("Back") tap("LP")
save_and_close()
do
  local st = steps()
  want("保存された timing", st and st[2].timing, "late_cancel")
  want("wait は Auto に戻る", st and st[2].wait, -1)
end

print("\n[9] 未保存チェックと全ステップ削除")
-- 変更していないのに確認が出る / 左で抜けると黙って捨てる、の両方を直した。
training_settings.action_sequences.reversal = { ["5"] = { version=1, steps={
  {action="atk", lever="none", button="LP", wait=0},
  {action="atk", lever="none", button="MP", wait=5} } } }

-- 何も触らずに左 -> そのまま閉じる
E.open("reversal")
tap("left")
want("触っていなければ左で閉じる", E.is_active(), false)

-- 触ってから左 -> 確認画面が出る
E.open("reversal")
goto_row("2 ") tap("LP")
goto_row("Wait") tap("LP")
-- 数値は Fixed Ticks の下。Wait 画面そのものは選ぶだけで値は動かない。
goto_row("Fixed Ticks") tap("LP")
tap("right")                       -- wait を動かす
goto_row("Back") tap("LP")         -- 数値 -> Wait
goto_row("Back") tap("LP")         -- Wait -> 詳細
goto_row("Back") tap("LP")         -- 詳細 -> 一覧
tap("left")
want("触ったあとの左は閉じない", E.is_active(), true)
want("確認画面が出る", selected():find("Cancel", 1, true) ~= nil, true)
-- 保存せず閉じるを選ぶと、保存済みは元のまま
goto_row("Close Without Saving") tap("LP")
want("閉じた", E.is_active(), false)
want("保存済みは変わっていない", steps()[2].wait, 5)

-- Back Without Saving も同じ確認を通る
E.open("reversal")
goto_row("2 ") tap("LP")
goto_row("Wait") tap("LP")
goto_row("Fixed Ticks") tap("LP")
tap("right")
goto_row("Back") tap("LP")
goto_row("Back") tap("LP")
goto_row("Back") tap("LP")
goto_row("Back Without Saving") tap("LP")
want("Back Without Saving も確認する", E.is_active(), true)
goto_row("Cancel") tap("LP")
want("Cancel で編集に戻る", E.is_active(), true)
-- Cancel は確認画面だけを閉じるので、いるのは一覧。もう一度左で出し直す。
tap("left")
goto_row("Save and Close") tap("LP")
want("保存して閉じた", E.is_active(), false)
want("こんどは保存されている", steps()[2].wait, 6)

-- 全ステップ削除
E.open("reversal")
goto_row("Clear All Steps") tap("LP")
want("いきなり消さない", #steps(), 2)
goto_row("No, keep them") tap("LP")
want("No で戻る", E.is_active(), true)
goto_row("Clear All Steps") tap("LP")
goto_row("Yes, clear all steps") tap("LP")
save_and_close()
want("1 歩だけ残る", #steps(), 1)
print("\n[10] Wait 画面に並ぶもの")
-- 窓の終わりを事前に知る手段が無いので行ごと外した。旧実装は最終セルと接触を
-- 同時に要求していて一度も発火していない。
training_settings.action_sequences.reversal = { ["5"] = { version=1, steps={
  {action="atk", lever="none", button="LP", wait=0},
  {action="atk", lever="none", button="MP", wait=1} } } }
E.open("reversal")
goto_row("2 ") tap("LP")
goto_row("Wait") tap("LP")
want("Wait 画面に並ぶもの", table.concat(all_rows(), " | "),
     "After | Landing | Rapid | Chain | Cancel | Late Cancel | Fixed Ticks : 1 | Back")
want("Late Chain は無い",
     table.concat(all_rows(), " | "):find("Late Chain", 1, true) ~= nil, false)

-- 連打キャンセル。ROM 0x028FB0 は同じボタンしか受け付けないので、行を出すのは
-- 前ステップが小攻撃のときだけ。強攻撃の後ろに出ると、押しても何も起きない
-- モードがメニューに並ぶことになる。
training_settings.action_sequences.reversal = { ["5"] = { version=1, steps={
  {action="atk", lever="none", button="HP", wait=0},
  {action="atk", lever="none", button="HP", wait=1} } } }
E.open("reversal")
goto_row("2 ") tap("LP")
goto_row("Wait") tap("LP")
want("大攻撃の後ろに Rapid は出ない",
     table.concat(all_rows(), " | "):find("Rapid", 1, true) ~= nil, false)
want("ほかのモードは残る", table.concat(all_rows(), " | "),
     "After | Landing | Chain | Cancel | Late Cancel | Fixed Ticks : 1 | Back")

-- 保存済みの rapid は、前ステップを大攻撃に変えても行に残る。消すと矢印で
-- 戻れない設定を抱えたリストになる。
training_settings.action_sequences.reversal = { ["5"] = { version=1, steps={
  {action="atk", lever="none", button="HP", wait=0},
  {action="atk", lever="none", button="LP", wait=-1, timing="rapid"} } } }
E.open("reversal")
do
  local r = all_rows()
  want("保存済みの Rapid Fire は残る",
       r[2]:find("Auto (Rapid Fire)", 1, true) ~= nil, true)
end
goto_row("2 ") tap("LP")
goto_row("Wait") tap("LP")
want("行は残り、カーソルもそこに乗る", trim(selected():gsub("^>%s*", "")), "Rapid")
want("Rapid の行がある", table.concat(all_rows(), " | "):find("Rapid", 1, true) ~= nil, true)

-- 保存済みは Chain へ移行する。放置すると、そのステップで止まったままの
-- リストが、棒でも降りられない行を抱えることになる。
training_settings.action_sequences.reversal = { ["5"] = { version=1, steps={
  {action="atk", lever="none", button="LP", wait=0},
  {action="atk", lever="none", button="MP", wait=-1, timing="late_chain"} } } }
E.open("reversal")
do
  local r = all_rows()
  want("保存済みの Late Chain は Chain になる",
       r[2]:find("Auto (Chain)", 1, true) ~= nil, true)
  want("Late Chain とは出ない",
       r[2]:find("Late Chain", 1, true) ~= nil, false)
end
goto_row("Save") tap("LP")
want("保存も chain で書かれる", steps()[2].timing, "chain")


-- Wait 行は 0..120 の数字と、その左端に並ぶ 5 つのモードが 1 本の列になって
-- いる。数字は速く、モードは今までの速さ。モードを速くすると、指を離す前に
-- 5 つ全部を通り過ぎる。
print("\n[11] 押しっぱなしの速さ")
-- Wait がリストになったので、速さの置き場所も変わった。数字は Fixed Ticks の
-- 下の画面だけになり、そこには行き過ぎて困るモードが並んでいない - だから
-- 条件なしで速い。モードの一覧は上下で選ぶ普通のメニューなので従来の速さ。
training_settings.action_sequences.reversal = { ["5"] = { version=1, steps={
  {action="atk", lever="none", button="LP", wait=0},
  {action="atk", lever="none", button="MP", wait=60} } } }
E.open("reversal")
goto_row("2 ") tap("LP")
goto_row("Wait") tap("LP")
do
  autofire_rate_seen = {}
  tap("down")
  want("モードの一覧は今までの速さ", autofire_rate_seen["down"], 4)
end
goto_row("Fixed Ticks") tap("LP")
do
  autofire_rate_seen = {}
  tap("left")
  want("数字は速い", autofire_rate_seen["left"], 1)
  want("1 減った", selected():find("59 Ticks", 1, true) ~= nil, true)
end

print("\n[12] 開いただけでは設定を書き換えない")
-- 旧形式 (キャラ別になる前の、steps が上にあるもの) を開くと、以前は open が
-- その場で「いま出ているダミー」の下へ移し替えていた。見るために開いただけ、
-- 保存せず閉じた、でも中身は動いている - 保存していないのに設定が変わるのは、
-- どのキャラのものだったか分からない旧形式では特に良くない。移行は Save だけ。
local function legacy()
  local per = training_settings.action_sequences.reversal
  return (per and per.steps) and #per.steps or 0
end
training_settings.action_sequences.reversal = { version=1, steps={
  {action="dash.f", wait=0} } }
E.open("reversal")
want("下書きには読み込まれる", #all_rows()>=1, true)
want("開いただけでは移行しない", legacy(), 1)
want("キャラの下にはまだ無い", steps(), nil)
-- 捨てる差分を作ってから閉じる。何も触っていなければ閉じるかは聞かれない。
goto_row("Add Step") tap("LP")
goto_row("Back") tap("LP")
E.request_close() E.registerBefore()
goto_row("Close Without Saving") tap("LP")
want("保存せず閉じた", E.is_active(), false)
want("保存せず閉じても旧形式のまま", legacy(), 1)
want("保存せず閉じてもキャラの下は空", steps(), nil)
-- Save で初めて、開いたときのキャラの下へ移る。
E.open("reversal")
save_and_close()
want("Save で移行する", legacy(), 0)
want("開いたときのキャラの下に入る", #(steps() or {}), 1)

print("\n[13] 編集中にキャラが変わったら保存せず閉じる")
-- 保存先は open したときのキャラに決まる。途中で相手が変わったら、下書きは
-- もう別のキャラのものなので、書かずに閉じる。
training_settings.action_sequences.reversal = { ["5"] = { version=1, steps={
  {action="dash.f", wait=0} } } }
E.open("reversal")
goto_row("Add Step") tap("LP")
goto_row("Back") tap("LP")
want("下書きは 2 歩", #all_rows()>=2, true)
-- 閉じるか聞かれている最中にキャラが変わる、という一番きわどいところで見る。
want("request_close が引き取る", E.request_close(), true)
ram[0xFF8B82]=0x08
E.registerBefore()
want("閉じた", E.is_active(), false)
want("保存されていない", #(steps() or {}), 1)
want("別のキャラにも書かれていない", (training_settings.action_sequences.reversal or {})["8"], nil)
-- 閉じるかどうかの問いも一緒に降ろす。残っていると、次に開いた瞬間その画面が
-- 出てくる。
ram[0xFF8B82]=0x05
E.open("reversal")
E.registerBefore()
-- 降ろし忘れていると、ここで問いが立ち上がる。触っていない下書きは捨てるものが
-- 無いので、画面も出さずにその場で閉じてしまう。
want("次に開いてすぐ閉じない", E.is_active(), true)
do
  local r=all_rows()
  want("次に開くのは普通の画面", r[1]~="Cancel", true)
end
E.request_close() E.registerBefore()
want("後片付け - 閉じた", E.is_active(), false)

print("\n[14] 長いリストのスクロール")
-- 4096 歩まで積めるのに、1 行 4 フレームでは端まで 4 分半かかる。積めるが歩けない
-- リストになっていた。押しっぱなしの長さで 1 回の移動量が増える。
local function long(n)
  local st={ {action="atk", lever="down-forward", button="LP", wait=0} }
  for i=2,n do st[i]={action="atk", lever="down-forward", button="LP", timing="rapid", wait=-1} end
  return { version=1, steps=st }
end
-- 今カーソルが乗っている行の番号。ステップ行は先頭が番号なのでそれを読む。
local function cur()
  return tonumber((selected():match("^>%s*(%d+)")))
end
-- 最終行はギャップぶん下がって all_rows の帯から外れる。端の話をするので、
-- ここだけパネルの底まで見る。
local function selected_wide()
  local sel=nil
  gui.text=function(x,y,t)
    if x==33 and y>=37 and y<=190 and t:sub(1,1)==">" then sel=t end
  end
  E.guiRegister()
  gui.text=function() end
  return sel or ""
end
-- 押しっぱなしを frames 分続けた状態で reps 回ぶん読ませる。
local function hold_walk(name, frames, reps)
  P1.input.pressed={}; P1.input.down={[name]=true}
  P1.input.state_time={[name]=frames}
  for _=1,reps do E.registerBefore() end
  P1.input.pressed={}; P1.input.down={}; P1.input.state_time={}
end

training_settings.action_sequences.reversal = { ["5"] = long(400) }
E.open("reversal")
want("1 歩目から始まる", cur(), 1)
hold_walk("down", 0, 5)
want("押した直後は 1 行ずつ", cur(), 6)
-- 狙うのはタップの方。1 回押せば必ず 1 行で、掴んだままなら旅に出る。
hold_walk("down", 29, 5)
want("29 フレームまでは 1 行ずつ", cur(), 11)
hold_walk("down", 30, 5)
want("30 フレームで 2 行ずつ", cur(), 21)
hold_walk("down", 60, 5)
want("60 フレームで 8 行ずつ", cur(), 61)
-- 400 歩 + Add Step + Save + Back + Clear = 404 行。404 / 50 は 8 なので、
-- 最上段は下限の 16 が効く。
hold_walk("down", 100, 5)
want("100 フレームで 16 行ずつ", cur(), 141)

-- 走っている最中に端へ着いたら止まる。反対の端から出てくるのは、そこへ
-- 連れて行かれたのと同じで、行きたかったところではない。
hold_walk("down", 100, 100)
want("端で止まる", selected_wide():find("Clear All Steps", 1, true) ~= nil, true)
-- 一押しの折り返しはそのまま。1 行目から上で最終行に出るのは、長いリストで
-- Save に届く唯一の近道でもある。
E.open("reversal")
tap("up")
want("一押しは折り返す", selected_wide():find("Clear All Steps", 1, true) ~= nil, true)

-- 触っていない側のプレイヤーの時計を読まないこと。state_time は「今の状態が
-- 何フレーム続いているか」で、押していない状態も数える。誰も触っていない方向は
-- 起動からずっと同じ状態なので何万フレームにもなり、それを掴んだ時間として
-- 読むと、開いた瞬間から最上段のギアに入る。
do
  local P2={input={pressed={},down={},state_time={}}}
  player_objects={P1,P2}
  P2.input.down["down"]=false
  P2.input.state_time["down"]=99999
  training_settings.action_sequences.reversal = { ["5"] = long(400) }
  E.open("reversal")
  hold_walk("down", 0, 5)
  want("触っていない側の時計は数えない", cur(), 6)
  -- 実際に両方掴んでいれば長い方を採る。
  P2.input.down["down"]=true
  P2.input.state_time["down"]=100
  P1.input.pressed={}; P1.input.down={}; P1.input.state_time={}
  for _=1,5 do E.registerBefore() end
  want("両方掴んでいれば長い方", cur(), 6 + 16*5)
  player_objects={P1}
end

-- 一画面に収まるリストにはギアを付けない。押しっぱなしの折り返しを取り上げる
-- だけになる。
training_settings.action_sequences.reversal = { ["5"] = long(4) }
E.open("reversal")
hold_walk("down", 100, 3)
want("短いリストは今までどおり", cur(), 4)

print("[MP] 一覧から MP でステップを外す - 確認は残す")
-- 本人の依頼 (2026-09-25)。ステップの画面の Remove This Step と同じ確認画面を、
-- 一覧から直接開く近道。確認を残すので、うっかり押しても LP を押すまで消えない。
local function help_line()
  local h = ""
  gui.text=function(x,y,t) if y==181 then h=t end end
  E.guiRegister()
  gui.text=function() end
  return h
end
ram[0xFF8B82]=0x05
training_settings.action_sequences.reversal = { ["5"] = { version=1, steps={
  {action="atk", lever="none", button="LP", wait=0},
  {action="atk", lever="none", button="MP", wait=-1},
  {action="atk", lever="none", button="HP", wait=-1} } } }
E.open("reversal")
goto_row("Attack : MP")
want("操作説明に MP: Remove", help_line():find("MP: Remove", 1, true) ~= nil, true)
tap("MP")
want("確認画面が開く", selected():find("No, keep it", 1, true) ~= nil, true)
tap("LP")                              -- No
want("No なら一覧に戻る", selected():find("Attack : MP", 1, true) ~= nil, true)
tap("MP")
tap("down")                            -- Yes
tap("LP")
want("消した後も一覧 (エディタは閉じない)", selected():find("Attack : HP", 1, true) ~= nil, true)
save_and_close()
want("2 歩になる", steps() and #steps(), 2)
want("残ったのは LP と HP",
  steps() and (tostring(steps()[1].button) .. "," .. tostring(steps()[2].button)), "LP,HP")

-- ステップの画面から消す道は今までどおり 2 段戻る (その画面も閉じる)。
E.open("reversal")
goto_row("Attack : HP")
tap("LP")                              -- ステップの画面へ
goto_row("Remove This Step")
tap("LP")
tap("down")                            -- Yes
tap("LP")
-- 2 歩中の 2 歩目を消したので、カーソルは同じ位置の + Add Step に乗る。
want("画面からの削除も一覧へ戻る", selected():find("Add Step", 1, true) ~= nil, true)
save_and_close()
want("1 歩になる", steps() and #steps(), 1)

-- 最後の 1 歩は消せない。Remove This Step が無いのと同じ。
E.open("reversal")
goto_row("Attack : LP")
want("1 歩だけのときは説明に出さない", help_line():find("MP: Remove", 1, true), nil)
tap("MP")
want("1 歩だけなら何も起きない", selected():find("Attack : LP", 1, true) ~= nil, true)
save_and_close()
want("1 歩のまま", steps() and #steps(), 1)

print(fails==0 and "\n全て通った" or ("\n"..fails.." 件 NG"))
os.exit(fails==0 and 0 or 1)
