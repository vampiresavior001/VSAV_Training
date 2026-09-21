-- ACTION PATTERN LIBRARY - EVERYTHING IS REACHABLE WITH THE LEVER AND LP.
--
-- MP and HP are shortcuts and nothing else. A feature that can only be reached
-- with one is a feature half the players will never find - the ported
-- implementation put Random on MP and the options on HP, which is what this
-- exists to stop coming back (design_action_pattern_library.md).
--
-- tap() REFUSES MP AND HP, so the whole file is the proof: if a walk below
-- needed one, it could not have been written.
--
-- LEFT IS ALWAYS BACK. A value that moves on Left is a row the stick cannot
-- leave, so two-way switches are LP or Right and never Left.
--
-- Run from scripts/ - the dofile below is relative.
--   cd scripts && lua5.1 ../analysis/test_pattern_library_reach.lua
local ram={} memory={readbyte=function(a) return ram[a] or 0 end}
gui={text=function() end, box=function() end}
local FC=0 emu={framecount=function() FC=FC+1 return FC end}
function mark_training_settings_dirty() end
panel_fill_color=0 panel_outline_color=0
text_selected_color=0 text_default_color=0 text_default_border_color=0 text_disabled_color=0
local _csrc = io.open("controller.lua"):read("*a")
local _NL = string.char(10)
local _cs = _csrc:find("function make_input_sequence", 1, true)
local _ce = _csrc:find(_NL .. "end", _csrc:find("return _sequence", _cs, true), true)
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
-- 本物を呼ぶとテストが 39 秒止まる。名前は上から与える。
local answer = nil
E.prompt_name = function() return answer end

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

-- ここが主張そのもの。近道キーは受け付けない。
local ALLOWED = { up=true, down=true, left=true, right=true, LP=true }
local function tap(n)
  assert(ALLOWED[n], "レバーと LP 以外を使った: " .. tostring(n))
  P1.input.pressed={} P1.input.down={} E.registerBefore()
  P1.input.pressed={[n]=true} P1.input.down={[n]=true} E.registerBefore()
  P1.input.pressed={} P1.input.down={}
end

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
  for _=1,20 do
    if selected():find(text,1,true) then return true end
    tap("down")
  end
  fail("行が見つからない ["..text.."]", selected(), text)
  return false
end
local function title_of() local t=draw() return t end
-- 名前の箱は「描いてから次のフレーム」で開く。歩くときの 1 手として畳んでおく。
local function answer_name(name)
  answer = name
  draw()
  E.registerBefore()
end

-- The library key follows the harness's ram, so [22] can open another
-- character's library. lib_key may be defined later; fall back to Morrigan.
local function items()
  local key = (type(lib_key) == "function") and lib_key() or "5"
  local per = training_settings.action_patterns.reversal[key]
  if per == nil then return {} end
  return per.items
end
local function one_step() return { { action="atk", lever="none", button="LP", wait=-1 } } end
local function open(list)
  training_settings.action_patterns.reversal = { ["5"] = { version=1, items=list } }
  E.open_patterns("reversal")
end

print("[1] 一覧 - 下と LP だけで、どの行にも入れる")
open({
  { name="one", use=true,  steps=one_step() },
  { name="two", use=false, steps=one_step() },
})
for _, row in ipairs({ "[x] 01", "[ ] 02", "New", "Add from current Steps",
                       "Export to a File", "Import from a File", "Back" }) do
  E.open_patterns("reversal")
  eq("届く: " .. row, goto_row(row), true)
end

print("")
print("[2] 項目 - 下と LP だけで、どの行にも入れる")
for _, row in ipairs({ "Edit", "Use in Random", "Rename", "Copy", "Move",
                       "Delete", "Export this Pattern", "Back" }) do
  E.open_patterns("reversal")
  tap("LP")
  eq("届く: " .. row, goto_row(row), true)
end

print("")
print("[3] Use in Random - LP と 右で切り替わり、左では切り替わらない")
open({ { name="one", use=true, steps=one_step() } })
tap("LP") goto_row("Use in Random")
tap("LP")
eq("LP で外れる", items()[1].use, false)
tap("LP")
eq("LP で戻る", items()[1].use, true)
tap("right")
eq("右でも外れる", items()[1].use, false)
-- 左は値に触らない。触ると、その行から出る手段が無くなる。
tap("left")
eq("左では変わらない", items()[1].use, false)
eq("左は戻る", title_of(), "REVERSAL ACTION PATTERNS: Morrigan")

print("")
print("[4] Move - 左右で並び替わり、下と LP で出られる")
open({
  { name="one", use=false, steps=one_step() },
  { name="two", use=false, steps=one_step() },
  { name="three", use=false, steps=one_step() },
})
goto_row("[ ] 03") tap("LP") goto_row("Move") tap("LP")
tap("left")
eq("左で 1 つ前へ", items()[2].name, "three")
tap("left")
eq("もう 1 つ前へ", items()[1].name, "three")
tap("right")
eq("右で戻る", items()[2].name, "three")
-- 値の行から出るのは下。左は値を動かすので、出口は行として置いてある。
tap("down")
eq("Back の行に立つ", selected():find("Back", 1, true) ~= nil, true)
tap("LP")
eq("項目の画面へ戻った", title_of(), "REVERSAL ACTION PATTERNS: Morrigan  >  02  three")

print("")
print("[5] Delete - 確認を挟み、既定は消さない側")
open({ { name="one", use=false, steps=one_step() },
       { name="two", use=false, steps=one_step() } })
tap("LP") goto_row("Delete") tap("LP")
eq("消さない側が選ばれている", selected():find("No, keep it", 1, true) ~= nil, true)
tap("LP")
eq("消えていない", #items(), 2)
eq("項目の画面に戻る", title_of(), "REVERSAL ACTION PATTERNS: Morrigan  >  01  one")
goto_row("Delete") tap("LP") goto_row("Yes, delete") tap("LP")
eq("消えた", #items(), 1)
eq("残ったのは two", items()[1].name, "two")
eq("一覧へ戻っている", title_of(), "REVERSAL ACTION PATTERNS: Morrigan")

print("")
print("[6] Copy - 隣に増えて、カーソルがその行に乗る")
open({ { name="one", use=true, steps=one_step() },
       { name="two", use=false, steps=one_step() } })
tap("LP") goto_row("Copy") tap("LP")
eq("1 本増えた", #items(), 3)
eq("隣に入った", items()[2].name, "one")
eq("一覧に戻っている", title_of(), "REVERSAL ACTION PATTERNS: Morrigan")
eq("カーソルは複製の行", selected():find("02  one", 1, true) ~= nil, true)
-- 別の表であること。片方を直してもう片方が動いては困る。
items()[1].steps[1].button = "HK"
eq("複製は別物", items()[2].steps[1].button, "LP")

print("")
print("[7] Add from current Steps - いまの Action Steps が丸ごと入る")
training_settings.action_sequences.reversal = { ["5"] = { version=1, steps={
  { action="atk", lever="none", button="MP", wait=-1 },
  { action="atk", lever="down", button="HK", wait=5 },
} } }
open({})
goto_row("Add from current Steps") tap("LP")
answer_name("imported")
eq("1 本できた", #items(), 1)
eq("名前が付いている", items()[1].name, "imported")
eq("ステップ数が同じ", #items()[1].steps, 2)
eq("中身も同じ", items()[1].steps[2].button, "HK")
eq("項目の画面にいる", title_of(), "REVERSAL ACTION PATTERNS: Morrigan  >  01  imported")
-- 取り込みは写し。パターンを直しても元の Action Steps は動かない。
items()[1].steps[1].button = "LK"
eq("元は動かない", training_settings.action_sequences.reversal["5"].steps[1].button, "MP")

print("")
print("[8] 直したあと左 - 黙って捨てない")
open({ { name="one", use=false, steps=one_step() } })
tap("LP") tap("LP")
eq("エディタに入った", title_of(), "REVERSAL ACTION STEPS: Morrigan  >  01  one")
-- ステップを 1 つ足して汚す。
goto_row("Add Step") tap("LP")
tap("left")
tap("left")
eq("問われる", selected():find("Cancel", 1, true) ~= nil, true)
local _, rows8 = draw()
eq("戻る先はメニューではない",
   table.concat(rows8, " "):find("go back", 1, true) ~= nil, true)
goto_row("Save and go back") tap("LP")
eq("保存された", #items()[1].steps, 2)
eq("項目の画面へ戻った", title_of(), "REVERSAL ACTION PATTERNS: Morrigan  >  01  one")

print("")
print("[9] 左だけでメニューまで戻れる")
tap("left")
eq("一覧", title_of(), "REVERSAL ACTION PATTERNS: Morrigan")
tap("left")
eq("閉じた", E.is_active(), false)

print("")
print("[10] New - 名前を付けてそのままエディタ、左で戻れる")
open({})
goto_row("New") tap("LP")
answer_name("fresh")
eq("エディタにいる", title_of(), "REVERSAL ACTION STEPS: Morrigan  >  01  fresh")
eq("できている", items()[1].name, "fresh")
eq("使う印が付いている", items()[1].use, true)
tap("left")
eq("項目へ", title_of(), "REVERSAL ACTION PATTERNS: Morrigan  >  01  fresh")
tap("left")
eq("一覧へ", title_of(), "REVERSAL ACTION PATTERNS: Morrigan")

print("")
print("[11] Save はメニューまで戻らない - 親のパターンへ戻る")
-- Action Steps を直接編集しているときは、開いたのがメニューの行なので
-- メニューへ戻るのが正しい。ライブラリ経由では上にパターンがある。
open({ { name="one", use=false, steps=one_step() } })
tap("LP") tap("LP")
goto_row("Add Step") tap("LP") tap("left")
goto_row("Save") tap("LP")
eq("親のパターンへ戻る", title_of(), "REVERSAL ACTION PATTERNS: Morrigan  >  01  one")
eq("メニューは開いたまま", E.is_active(), true)
eq("保存されている", #items()[1].steps, 2)

print("")
print("[12] Back Without Saving も親へ戻る")
tap("LP")
goto_row("Add Step") tap("LP") tap("left")
goto_row("Back Without Saving") tap("LP")
-- 汚れているので一度問われる。
eq("問われる", selected():find("Cancel", 1, true) ~= nil, true)
goto_row("Go back without saving") tap("LP")
eq("親のパターンへ戻る", title_of(), "REVERSAL ACTION PATTERNS: Morrigan  >  01  one")
eq("捨てられている", #items()[1].steps, 2)
-- 汚れていなければ問わずに戻る。
tap("LP")
goto_row("Back Without Saving") tap("LP")
eq("そのまま親へ", title_of(), "REVERSAL ACTION PATTERNS: Morrigan  >  01  one")

print("")
print("[13] MP は近道 - 一覧の行を直接チェックできる")
-- ここだけ tap の制限を外す。近道が「あること」を見るので、制限のある tap では
-- そもそも書けない。近道でしか届かない機能が無いことは [1]-[12] が証明済み。
local function tap_any(n)
  P1.input.pressed={} P1.input.down={} E.registerBefore()
  P1.input.pressed={[n]=true} P1.input.down={[n]=true} E.registerBefore()
  P1.input.pressed={} P1.input.down={}
end
local function help_of()
  local h=nil
  gui.text=function(x,y,t) if x==33 and y==181 then h=t end end
  E.guiRegister()
  gui.text=function() end
  return h or ""
end
open({ { name="one", use=false, steps=one_step() },
       { name="two", use=true,  steps=one_step() } })
eq("行に立っている", selected():find("[ ] 01", 1, true) ~= nil, true)
tap_any("MP")
eq("入った", items()[1].use, true)
tap_any("MP")
eq("外れた", items()[1].use, false)
-- 画面はそのまま。入って戻ってくる必要が無いのが近道の意味。
eq("一覧のまま", title_of(), "REVERSAL ACTION PATTERNS: Morrigan")
tap("down")
tap_any("MP")
eq("隣の行も切り替わる", items()[2].use, false)
eq("こちらは触っていない", items()[1].use, false)
-- 行の説明にも出ていること。出ていない近道は無いのと同じ。
eq("凡例に出ている", help_of():find("MP: Tick", 1, true) ~= nil, true)
eq("凡例が 81 字以内", #help_of() <= 81, true)
-- パターンでない行では何も起きず、凡例にも出ない。
goto_row("New")
tap_any("MP")
eq("New では何も起きない", #items(), 2)
eq("凡例にも出ない", help_of():find("MP", 1, true), nil)

print("")
print("[14] Export - 画面が先、ファイル窓はその次のフレーム")
-- 本物を呼ぶとダイアログが開いてテストが止まる。中継の JSON も書かせない。
local jstore, jpath = nil, nil
function write_object_to_json_file(obj, path) jstore, jpath = obj, path return true end
function read_object_from_json_file(path) return jstore end
local xfer_calls, xfer_mode, xfer_who, xfer_suggest, xfer_answer = 0, nil, nil, nil, "OK"
local xfer_dir, xfer_remember = nil, nil
E.transfer_file = function(mode, who, suggest, remember)
  xfer_calls = xfer_calls + 1 xfer_mode = mode xfer_who = who
  xfer_suggest = suggest xfer_remember = remember
  return xfer_answer, xfer_dir
end

open({ { name="one", use=true,  steps=one_step() },
       { name="two", use=false, steps=one_step() } })
goto_row("Export to a File") tap("LP")
eq("押しただけでは開かない", xfer_calls, 0)
local _, rows14 = draw()
eq("知らせが出ている",
   table.concat(rows14, " "):find("A FILE WINDOW HAS OPENED", 1, true) ~= nil, true)
eq("カーソルは出ない", selected(), "")
E.registerBefore()
eq("開いた", xfer_calls, 1)
eq("保存で開いた", xfer_mode, "save")
eq("中継は ASCII のパス", jpath, "action_patterns_transfer.json")
-- ファイル名にキャラ名が入る。1 つのフォルダに同じ名前が並ぶと選べない。
eq("キャラ名を渡している", xfer_who, "Morrigan")
eq("2 本とも入っている", #jstore.items, 2)
eq("名前が入っている", jstore.items[1].name, "one")
eq("印も入っている", jstore.items[1].use, true)
eq("キャラも入っている", jstore.character, 0x05)
local _, rows14b = draw()
eq("結果が出ている", table.concat(rows14b, " "):find("OK", 1, true) ~= nil, true)
tap("LP")
eq("一覧へ戻る", title_of(), "REVERSAL ACTION PATTERNS: Morrigan")

print("")
print("[15] Export - 空なら窓を開かない、キャンセルはそう出る")
open({})
xfer_calls = 0
goto_row("Export to a File") tap("LP") draw() E.registerBefore()
eq("窓は開かない", xfer_calls, 0)
local _, rows15 = draw()
eq("理由が出ている",
   table.concat(rows15, " "):find("nothing saved to send", 1, true) ~= nil, true)
tap("LP")
open({ { name="one", use=true, steps=one_step() } })
xfer_answer = "CANCELLED"
goto_row("Export to a File") tap("LP") draw() E.registerBefore()
local _, rows15b = draw()
eq("キャンセルと出る",
   table.concat(rows15b, " "):find("CANCELLED", 1, true) ~= nil, true)
tap("LP")

print("")
print("[16] Import - 足すのであって置き換えない。届いたものに印は付かない")
xfer_answer = "OK"
open({ { name="mine", use=true, steps=one_step() } })
jstore = { version=1, items={
  { name="theirs A", use=true, steps={ { action="atk", lever="none", button="MP", wait=-1 } } },
  { name="theirs B", use=true, steps={ { action="atk", lever="down", button="HK", wait=5 } } },
} }
xfer_calls = 0
goto_row("Import from a File") tap("LP") draw() E.registerBefore()
eq("読み込みで開いた", xfer_mode, "open")
eq("3 本になった", #items(), 3)
eq("元のものは残っている", items()[1].name, "mine")
eq("元の印も残っている", items()[1].use, true)
eq("足された", items()[2].name, "theirs A")
-- 送られてきたファイルを開いただけで、ダミーの動きが変わってはいけない。
eq("届いたものに印は付かない", items()[2].use, false)
eq("もう 1 本も", items()[3].use, false)
eq("中身も来ている", items()[3].steps[1].button, "HK")
local _, rows16 = draw()
eq("何本入ったか出る",
   table.concat(rows16, " "):find("2 added", 1, true) ~= nil, true)
tap("LP")

print("")
print("[17] Import - 外から来たものは一切信用しない")
open({ { name="mine", use=false, steps=one_step() } })
jstore = { items={
  { name="", use=true, steps={ { action="atk" } } },              -- 名前が無い
  { name="no steps", use=true, steps={} },                        -- 中身が無い
  { name="bad steps", use=true, steps={ "not a table" } },         -- 表ですらない
  { name=string.char(0xE3,0x81,0x82), use=true,
    steps={ { action="atk" } } },                                  -- 描けない名前だけ
  { name="good", use=true, extra="ignored",
    steps={ { action="atk", lever="none", button="LP", wait=3, junk="x" } } },
} }
goto_row("Import from a File") tap("LP") draw() E.registerBefore()
eq("通ったのは 1 本だけ", #items(), 2)
eq("それは good", items()[2].name, "good")
eq("余計なフィールドは持ち込まれない", items()[2].extra, nil)
eq("ステップの余計なフィールドも", items()[2].steps[1].junk, nil)
eq("必要なところは来ている", items()[2].steps[1].button, "LP")
eq("wait も来ている", items()[2].steps[1].wait, 3)
local _, rows17 = draw()
eq("弾いた数も出る",
   table.concat(rows17, " "):find("4 skipped", 1, true) ~= nil, true)
tap("LP")
-- パターンの形をしていないファイル。
open({})
jstore = { hello = "world" }
goto_row("Import from a File") tap("LP") draw() E.registerBefore()
local _, rows17b = draw()
eq("形が違えば断る",
   table.concat(rows17b, " "):find("not a pattern file", 1, true) ~= nil, true)
eq("何も増えていない", #items(), 0)
tap("LP")

print("")
print("[18] Export this Pattern - 1 本だけ、提案名に名前が乗る")
-- 一覧の Export はライブラリ全部。項目の画面のこれは 1 本だけ。
open({ { name="one", use=true,  steps=one_step() },
       { name="two", use=false, steps=one_step() } })
tap("LP")
xfer_calls = 0
goto_row("Export this Pattern") tap("LP")
eq("押しただけでは開かない", xfer_calls, 0)
local _, rows18 = draw()
eq("知らせは保存の言葉",
   table.concat(rows18, " "):find("save the pattern file", 1, true) ~= nil, true)
E.registerBefore()
eq("開いた", xfer_calls, 1)
eq("保存で開いた", xfer_mode, "save")
eq("提案名はキャラとパターン", xfer_suggest,
   "vsav_action_pattern(Morrigan-one).json")
eq("1 本だけ入っている", #jstore.items, 1)
eq("その名前", jstore.items[1].name, "one")
eq("印も一緒に", jstore.items[1].use, true)
eq("ステップも一緒に", jstore.items[1].steps[1].button, "LP")
eq("キャラも入っている", jstore.character, 0x05)
local _, rows18b = draw()
eq("結果が出ている", table.concat(rows18b, " "):find("OK", 1, true) ~= nil, true)
tap("LP")
eq("項目の画面へ戻る",
   title_of(), "REVERSAL ACTION PATTERNS: Morrigan  >  01  one")

print("")
print("[19] Export this Pattern - 名前は提案にだけ乗る。使えない文字は落ちる")
xfer_answer = "CANCELLED"
open({ { name="vs Kai (DP)!", use=true, steps=one_step() } })
tap("LP")
xfer_calls = 0
goto_row("Export this Pattern") tap("LP") draw() E.registerBefore()
eq("使えない文字が落ちた",
   xfer_suggest, "vsav_action_pattern(Morrigan-vs Kai DP).json")
-- クラムは生の名前のまま。提案名に落とされた文字は画面の名前ではない。
eq("画面の名前はそのまま",
   title_of():find("vs Kai (DP)!", 1, true) ~= nil, true)
local _, rows19 = draw()
eq("キャンセルと出る",
   table.concat(rows19, " "):find("CANCELLED", 1, true) ~= nil, true)
eq("1 本とも増えていない", #items(), 1)
tap("LP")
eq("項目の画面へ戻る",
   title_of(), "REVERSAL ACTION PATTERNS: Morrigan  >  01  vs Kai (DP)!")

print("")
print("[20] Export this Pattern - 読めなかった理由が出る")
-- read_object が理由を返すようになった。届かない理由がそのまま画面に出る。
local saved_tf = E.transfer_file
E.transfer_file = function() return "OK", nil end
local reads_answer = nil
function read_object_from_json_file(path) return unpack(reads_answer) end
open({ { name="one", use=true, steps=one_step() } })
-- まず形が違う表: 「not a pattern file」のまま。
reads_answer = { { hello = "world" } }
goto_row("Import from a File") tap("LP") draw() E.registerBefore()
local _, rows20 = draw()
eq("形が違えば断る",
   table.concat(rows20, " "):find("not a pattern file", 1, true) ~= nil, true)
tap("LP")
-- 次に読みが nil と理由: 理由が画面に出る。
reads_answer = { nil, "the file could not be opened" }
goto_row("Import from a File") tap("LP") draw() E.registerBefore()
local _, rows20b = draw()
eq("読めない理由が出る",
   table.concat(rows20b, " "):find("the file could not be opened", 1, true) ~= nil, true)
eq("1 本とも増えていない", #items(), 1)
tap("LP")
-- 本物に戻す。
E.transfer_file = saved_tf
function read_object_from_json_file(path) return jstore end

print("")
print("[21] 前回のフォルダを覚える - OK だけが書き、CANCELLED は書かない")
-- remember は transfer_file の中で settings から読まれる (呼び出し側は渡さ
-- ない)。ここでは remember_dir() の読み先そのものを差し替えて、渡る値と
-- settings に残った値を両方見る。
local remember_dir_value = nil
function remember_dir() return remember_dir_value or "" end
open({ { name="one", use=true, steps=one_step() } })
xfer_calls = 0
xfer_answer = "OK"
xfer_dir = [[C:\Users\me\Downloads]]
goto_row("Export to a File") tap("LP") draw() E.registerBefore()
eq("最初は記憶が空", remember_dir_value, nil)
eq("OK でフォルダが載る", training_settings.pattern_dir,
   [[C:\Users\me\Downloads]])
-- 次の窓は覚えたフォルダから開く。remember_dir の値は editor の本物が
-- settings から読むので、ここは settings を見る。
open({ { name="one", use=true, steps=one_step() } })
xfer_calls = 0
goto_row("Export to a File") tap("LP") draw() E.registerBefore()
eq("次の窓の初期位置は settings のもの", training_settings.pattern_dir,
   [[C:\Users\me\Downloads]])
tap("LP")
-- キャンセルは書かない。
xfer_answer = "CANCELLED"
xfer_dir = [[C:\Users\me\Desktop]]
open({ { name="one", use=true, steps=one_step() } })
goto_row("Export to a File") tap("LP") draw() E.registerBefore()
eq("CANCELLED では変わらない", training_settings.pattern_dir,
   [[C:\Users\me\Downloads]])
tap("LP")
-- import の OK も書く。
xfer_answer = "OK"
open({ { name="mine", use=true, steps=one_step() } })
jstore = { version=1, items={
  { name="theirs", use=true, steps=one_step() } } }
goto_row("Import from a File") tap("LP") draw() E.registerBefore()
eq("Import の OK でも載る", training_settings.pattern_dir,
   [[C:\Users\me\Desktop]])
eq("2 本になった", #items(), 2)
tap("LP")

print("")
print("[22] Import - キャラ違いは拒む。理由に両方の名前を出す")
-- cid_num はエディタ内のローカルで RAM を読む。ハーネスの ram を書き換えて
-- 「別キャラのライブラリを開いた」を作る。エディタは cid 変化で閉じるので、
-- 書き換えたあとに開き直す。
jstore = { version=1, character=0x05, items={
  { name="from Sasquatch", use=true, steps=one_step() } } }
ram[0xFF8B82] = 0x0A
training_settings.action_patterns.reversal =
  { [tostring(0x0A)] = { version=1, items={ { name="mine", use=true, steps=one_step() } } } }
E.open_patterns("reversal")
goto_row("Import from a File") tap("LP") draw() E.registerBefore()
-- 拒まれたので何も増えていない。items() は拒否後の鍵を見るが、
-- ここでは数だけを見る (1 本のはずが 0 に見えたら鍵の問題)。
eq("1 本のまま", #(training_settings.action_patterns.reversal[tostring(0x0A)].items), 1)
local _, rows22 = draw()
eq("ファイルのキャラが出る",
   table.concat(rows22, " "):find("for Morrigan", 1, true) ~= nil, true)
eq("開いた側のキャラも出る",
   table.concat(rows22, " "):find("not Sasquatch", 1, true) ~= nil, true)
eq("何も足していないと言う",
   table.concat(rows22, " "):find("Nothing was added", 1, true) ~= nil, true)
tap("LP")
-- 一致していれば入る。
jstore = { version=1, character=0x05, items={
  { name="same char", use=true, steps=one_step() } } }
ram[0xFF8B82] = 0x05
training_settings.action_patterns.reversal =
  { [tostring(0x05)] = { version=1, items={ { name="mine", use=true, steps=one_step() } } } }
E.open_patterns("reversal")
goto_row("Import from a File") tap("LP") draw() E.registerBefore()
eq("2 本になった", #items(), 2)
local _, rows22b = draw()
eq("一致では added と出る",
   table.concat(rows22b, " "):find("added", 1, true) ~= nil, true)
tap("LP")
-- character フィールドが無い古い手作りファイルは、そのまま通す。
open({})
jstore = { items={ { name="fieldless", use=true, steps=one_step() } } }
goto_row("Import from a File") tap("LP") draw() E.registerBefore()
eq("1 本になった", #items(), 1)
local _, rows22c = draw()
eq("不明でも added と出る",
   table.concat(rows22c, " "):find("added", 1, true) ~= nil, true)
tap("LP")
-- 本物に戻す。
ram[0xFF8B82] = 0x05

if fails == 0 then print("") print("全て通った") else print(fails .. " 件 NG") os.exit(1) end
