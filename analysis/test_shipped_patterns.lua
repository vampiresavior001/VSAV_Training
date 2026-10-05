-- 配布物に入れるパターンファイル (scripts/patterns/*.json) が、本物の Import で
-- そのまま取り込めること。Short LP と、その対の Long LP > MP ([5])。
--
-- チュートリアルの近道として Short LP (サスカッチのショートダッシュ小P) を
-- 同梱する (本人、2026-10-02)。手で書いたファイルなので、書き間違えると
-- Import が黙って断るか、別の動きとして入る。ここで本物の import と本物の
-- 行の表示を通し、チュートリアルで組む 2 ステップと同じになることを見る:
--   1  Auto (Fastest)  Dash : Forward Cancel
--   2  Auto (8)        Attack : LP
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_shipped_patterns.lua
local NL = string.char(10)
local ram={} memory={readbyte=function(a) return ram[a] or 0 end}
gui={text=function() end, box=function() end}
local FC=0 emu={framecount=function() FC=FC+1 return FC end}
function mark_training_settings_dirty() end
panel_fill_color=0 panel_outline_color=0
text_selected_color=0 text_default_color=0 text_default_border_color=0 text_disabled_color=0
-- The real make_input_sequence and the real runner, as test_editor_rows.lua
-- wires them: the Auto (8) on the second row is the runner's answer.
local _csrc = io.open("controller.lua"):read("*a")
local _cs = _csrc:find("function make_input_sequence", 1, true)
local _ce = _csrc:find(NL .. "end", _csrc:find("return _sequence", _cs, true), true)
assert(_cs and _ce, "make_input_sequence が controller.lua に見つからない")
assert(loadstring(_csrc:sub(_cs, _ce + 4)))()
local P1={input={pressed={},down={}}} player_objects={P1}
function check_input_down_autofire(p,name) return p.input.down[name] == true end
local _R = dofile("actionSequenceRunner.lua")
seq_auto_ticks = _R.auto_ticks_for
seq_auto_needs_number = _R.auto_needs_number
training_settings={action_sequences={}, action_patterns={}}
ram[0xFF8B82]=0x0A                         -- the dummy is Sasquatch
local E=dofile("actionSequenceEditor.lua")
local json = dofile("dkjson.lua")

local fails=0
local function eq(what,got,want)
  if got==want then print("  ok "..what) else
    fails=fails+1
    print("  NG "..what)
    print("     got  ["..tostring(got).."]")
    print("     want ["..tostring(want).."]")
  end
end
local function tap(n)
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
  return false
end
local function squeeze(t)
  return (t:gsub("^[>%s]+",""):gsub("%s*>%s*$",""):gsub("%s+"," "))
end

print("[1] ファイルが読める - 形と中身")
local f = io.open("patterns/Sasquatch_Short_LP.json", "rb")
eq("scripts/patterns にある", f ~= nil, true)
local text = f and f:read("*a") or ""
if f then f:close() end
eq("改行は LF だけ", text:find(string.char(13), 1, true), nil)
local got = json.decode(text)
eq("JSON として読める", type(got), "table")
got = got or {}
eq("版", got.version, 1)
eq("反撃のパターン", got.trigger, "reversal")
eq("サスカッチ (0x0A) のもの", got.character, 0x0A)
eq("1 本だけ", got.items and #got.items, 1)

print("")
print("[2] 本物の Import を通す")
-- The file window and the read are stubbed; the import itself is the real one.
E.transfer_file = function() return "OK", nil end
function read_object_from_json_file() return got end
E.open_patterns("reversal")
eq("Import の行がある", goto_row("Import from a File"), true)
tap("LP") draw() E.registerBefore()
local _, rows = draw()
eq("1 本入ったと出る", table.concat(rows, " "):find("OK  1 added", 1, true) ~= nil, true)
local lib = training_settings.action_patterns.reversal
local items = lib and lib["10"] and lib["10"].items or {}
eq("サスカッチの一覧に入る", #items, 1)
local it = items[1] or {}
eq("名前", it.name, "Short LP")
eq("印は付かない (取り込んだものは付かない)", it.use, false)
eq("2 ステップ", it.steps and #it.steps, 2)

print("")
print("[3] 行の表示がチュートリアルで組むものと同じ")
training_settings.action_sequences.reversal = { ["10"] = { version = 1, steps = it.steps } }
E.open("reversal")
local _, srows = draw()
eq("1 行目", squeeze(srows[1] or ""), "1 Auto (Fastest) Dash : Forward Cancel")
eq("2 行目", squeeze(srows[2] or ""), "2 Auto (8) Attack : LP")

print("")
print("[4] 配布 zip に入る")
-- make_release_zip.py walks scripts/ whole, so a file there ships.
local mk = io.open("../analysis/make_release_zip.py"):read("*a")
eq("scripts を丸ごと歩いている", mk:find('walk("scripts", names)', 1, true) ~= nil, true)
eq("json は除外の対象でない (除外は名前で決まる)",
	mk:find('"Sasquatch_Short_LP.json"', 1, true), nil)
eq("ロング版も除外されない", mk:find('"Sasquatch_Long_LP_MP.json"', 1, true), nil)

-- THE LONG VERSION (user, 2026-10-05). Short LP's partner for the tutorial:
-- a full forward dash, LP, then MP 26 Ticks after the LP - a gap the user
-- built so that jumping out of it is hard. Not Chain: the gap is the point.
-- Imported on top of Short LP, as the tutorial does, so it lands second.
print("")
print("[5] ロング版 (Long LP > MP) も本物の Import で入る")
local lf = io.open("patterns/Sasquatch_Long_LP_MP.json", "rb")
eq("scripts/patterns にある", lf ~= nil, true)
local ltext = lf and lf:read("*a") or ""
if lf then lf:close() end
eq("改行は LF だけ", ltext:find(string.char(13), 1, true), nil)
local lgot = json.decode(ltext) or {}
eq("版", lgot.version, 1)
eq("反撃のパターン", lgot.trigger, "reversal")
eq("サスカッチ (0x0A) のもの", lgot.character, 0x0A)
eq("1 本だけ", lgot.items and #lgot.items, 1)
function read_object_from_json_file() return lgot end
E.open_patterns("reversal")
eq("Import の行がある", goto_row("Import from a File"), true)
tap("LP") draw() E.registerBefore()
local _, lrows = draw()
eq("1 本入ったと出る", table.concat(lrows, " "):find("OK  1 added", 1, true) ~= nil, true)
local litems = lib and lib["10"] and lib["10"].items or {}
eq("Short LP の次に入る", #litems, 2)
local lit = litems[2] or {}
eq("名前", lit.name, "Long LP > MP")
eq("印は付かない", lit.use, false)
eq("3 ステップ", lit.steps and #lit.steps, 3)
training_settings.action_sequences.reversal = { ["10"] = { version = 1, steps = lit.steps } }
E.open("reversal")
local _, lsrows = draw()
eq("1 行目", squeeze(lsrows[1] or ""), "1 Auto (Fastest) Dash : Forward")
eq("2 行目", squeeze(lsrows[2] or ""), "2 Auto (0) Attack : LP")
eq("3 行目 (Chain ではなく 26 Tick)", squeeze(lsrows[3] or ""), "3 +26t Attack : MP")

print("")
if fails == 0 then
  print("test_shipped_patterns ok")
else
  print("test_shipped_patterns: " .. fails .. " NG")
  os.exit(1)
end
