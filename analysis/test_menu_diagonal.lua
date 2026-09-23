-- 斜め入力はメニューのカーソルを動かさない。
--
-- WHY. The menu's four direction blocks are independent and they do different
-- jobs: a vertical moves the cursor down the rows, a horizontal changes the
-- value ON the row. On a stick, a cursor passing through down-right fires both
-- on the same frame - the list walks AND a setting changes, with nothing on
-- screen to say the second thing happened (user, 2026-09-23).
--
-- WHAT IS LOADED. The predicate and the autofire helper are lifted straight
-- out of menu.lua rather than reimplemented, the way make_input_sequence is
-- lifted out of controller.lua in the other tests. menu.lua's own requires
-- (charMoves, the editor, the runner, position) are not needed to ask this
-- question, and a copy of the rule living in the test would only prove the
-- copy. The editor IS loaded for real further down, because the thing worth
-- pinning there is that its own pad reads consult the same predicate.
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_menu_diagonal.lua
local NL = string.char(10)

local msrc = io.open("menu.lua"):read("*a")
local ms = msrc:find("local MENU_CROSS_AXIS = {", 1, true)
local tail = NL .. "  return false" .. NL .. "end"
local me = msrc and msrc:find(tail, ms or 1, true)
assert(ms, "MENU_CROSS_AXIS が menu.lua に見つからない")
assert(me, "check_input_down_autofire の終わりが見つからない")
assert(loadstring(msrc:sub(ms, me + #tail - 1)))()

local fails = 0
local function eq(what, got, want)
  if got == want then
    print("  ok " .. what)
  else
    fails = fails + 1
    print("  NG " .. what)
    print("     got  [" .. tostring(got) .. "]")
    print("     want [" .. tostring(want) .. "]")
  end
end

local function pad(down, pressed, times)
  return { input = { pressed = pressed or {}, down = down,
                     state_time = times or {} } }
end

print("[1] 同じパッドで縦と横が同時なら、どちらも斜め扱い")
local dr = { down = true, right = true }
local ul = { up = true, left = true }
-- 4 つの斜めを全部、縦からも横からも聞く。1 つの斜めだけで確かめると、
-- 対の片方を取り違えた表 (up が right を見ていない、など) が素通りする。
for _, d in ipairs({
  { v = "up",   h = "right" },
  { v = "up",   h = "left"  },
  { v = "down", h = "right" },
  { v = "down", h = "left"  },
}) do
  local both = { [d.v] = true, [d.h] = true }
  eq(d.v .. "+" .. d.h .. " の " .. d.v, menu_input_crossed(pad(both), d.v), true)
  eq(d.v .. "+" .. d.h .. " の " .. d.h, menu_input_crossed(pad(both), d.h), true)
end
for _, one in ipairs({ "up", "down", "left", "right" }) do
  eq(one .. " だけ", menu_input_crossed(pad({ [one] = true }), one), false)
end
eq("何も入っていない", menu_input_crossed(pad({}), "down"), false)

print("")
print("[2] 同じ軸の同時押しは斜めではない")
-- 上+下 や 左+右 は方向としては打ち消し合うだけで、行と値を同時に触る形には
-- ならない。ここで弾くと、レバーの遊びで両方拾うパッドが操作不能になる。
eq("上+下 の 上", menu_input_crossed(pad({ up = true, down = true }), "up"), false)
eq("左+右 の 左", menu_input_crossed(pad({ left = true, right = true }), "left"), false)

print("")
print("[3] ボタンは弾かない - 斜めのままでも決定と取り消しは効く")
eq("LP", menu_input_crossed(pad(dr), "LP"), false)
eq("MP", menu_input_crossed(pad(dr), "MP"), false)
eq("start", menu_input_crossed(pad(dr), "start"), false)

print("")
print("[4] 手元に無いものを読んでも落ちない")
-- テストの作りごとに入力の表の埋まり方が違う。2P を置いていない harness も
-- あるので、nil は「入っていない」として通ること。
eq("パッドが nil", menu_input_crossed(nil, "down"), false)
eq("input が nil", menu_input_crossed({}, "down"), false)
eq("down の表が nil", menu_input_crossed({ input = {} }, "down"), false)

print("")
print("[5] メニューの歩進がその判定を通っている")
eq("下だけの押し始めは通る",
   check_input_down_autofire(pad({ down = true }, { down = true }), "down", 4), true)
eq("下+右 の押し始めは通らない",
   check_input_down_autofire(pad(dr, dr), "down", 4), false)
eq("その右も通らない",
   check_input_down_autofire(pad(dr, dr), "right", 4), false)
-- 長押しも同じ。しきい値 (23) を越えた窓のどこでも 1 度も通らないこと。
local function repeats(p, name, rate)
  for t = 24, 40 do
    p.input.state_time[name] = t
    if check_input_down_autofire(p, name, rate) then return true end
  end
  return false
end
eq("下だけなら長押しで繰り返す", repeats(pad({ down = true }), "down", 4), true)
eq("斜めのままなら繰り返しも起きない", repeats(pad(dr), "down", 4), false)

print("")
print("[6] 1P の下と 2P の右は斜めではない")
-- メニューはどちらのレバーでも動かせる。2 人ぶんを OR で見て弾くと、片方が
-- レバーを倒しているあいだ、もう片方が何もできなくなる。
local one = pad({ down = true }, { down = true })
local two = pad({ right = true }, { right = true })
eq("1P の下は通る", check_input_down_autofire(one, "down", 4), true)
eq("2P の右も通る", check_input_down_autofire(two, "right", 4), true)

-- ---------------------------------------------------------------- エディタ
-- ここからは本物の actionSequenceEditor を読み込んで、実際に歩かせる。
-- エディタは autofire を通らない pressed / held でも方向を読んでいるので、
-- 上の [5] が通っていても、こちらが素通しなら斜めで行が動いてしまう。
local ram = {}
memory = { readbyte = function(a) return ram[a] or 0 end }
gui = { text = function() end, box = function() end }
local FC = 0
emu = { framecount = function() FC = FC + 1 return FC end }
function mark_training_settings_dirty() end
panel_fill_color = 0 panel_outline_color = 0
text_selected_color = 0 text_default_color = 0
text_default_border_color = 0 text_disabled_color = 0
local csrc = io.open("controller.lua"):read("*a")
local cs = csrc:find("function make_input_sequence", 1, true)
local ce = csrc:find(NL .. "end", csrc:find("return _sequence", cs, true), true)
assert(cs and ce, "make_input_sequence が controller.lua に見つからない")
assert(loadstring(csrc:sub(cs, ce + 4)))()
local R = dofile("actionSequenceRunner.lua")
seq_auto_ticks = R.auto_ticks_for
seq_auto_needs_number = R.auto_needs_number
training_settings = { action_sequences = {}, action_patterns = {} }
ram[0xFF8B82] = 0x05
local P1 = { input = { pressed = {}, down = {}, state_time = {} } }
player_objects = { P1 }
local E = dofile("actionSequenceEditor.lua")

-- 1 回ぶんの入力。押し始めを作るために、前後を空のフレームで挟む。
local function tap(set)
  P1.input.pressed = {} P1.input.down = {} P1.input.state_time = {}
  E.registerBefore()
  P1.input.pressed = set P1.input.down = set P1.input.state_time = {}
  E.registerBefore()
  P1.input.pressed = {} P1.input.down = {} P1.input.state_time = {}
end

-- 行はエディタが描く場所そのままで読む。x=33、y は 37 から 10 刻み。
local function selected()
  local rows = {}
  gui.text = function(x, y, t)
    if x == 33 and y >= 37 and y <= 160 then rows[#rows + 1] = t end
  end
  E.guiRegister()
  gui.text = function() end
  for _, r in ipairs(rows) do
    if r:sub(1, 1) == ">" then return r end
  end
  return ""
end

print("")
print("[7] エディタでも斜めでは行が動かない")
E.open("reversal")
eq("開いている", E.is_active(), true)
local first = selected()
eq("選択行が読めている", first ~= "", true)
tap({ down = true, right = true })
eq("下+右 では動かない", selected(), first)
tap({ down = true })
local moved = selected()
eq("下だけなら動く", moved ~= first, true)
tap({ up = true, left = true })
eq("上+左 でも動かない", selected(), moved)

print("")
print("[8] エディタの pressed も同じ - 斜めの左では閉じない")
-- ここが素通しだと「戻る」が斜めで暴発する。閉じる側も確かめないと、
-- 「閉じなかった」が left を拾えていないだけ、という成立の仕方をする。
tap({ left = true, up = true })
eq("斜めの左では開いたまま", E.is_active(), true)
tap({ left = true })
eq("左だけなら閉じる", E.is_active(), false)


print("")
print("[9] 画面に入った Right の「まだ離していない」判定には門を掛けない")
-- held の呼び出し元は 1 か所、各画面の arming guard だけ。あれが聞いている
-- のは「レバーがまだ物理的に右にあるか」で、「右をメニューの操作として扱う
-- べきか」ではない。ここに斜めの門を掛けると、レバーを斜めへ倒しただけで
-- 「離した」ことになって画面が arm し、真横へ戻した瞬間に同じ長押しのまま
-- もう一段潜る - その guard が防いでいるものそのもの。
--
-- 関数の中だけを見る。ファイル全体を探すと pressed 側の crossed に当たって、
-- 何を書き換えても通るテストになる。
do
  local esrc = io.open("actionSequenceEditor.lua"):read("*a")
  local function body_of(decl)
    local a = esrc:find(decl, 1, true)
    if a == nil then return nil end
    local b = esrc:find(NL .. "end", a, true)
    if b == nil then return nil end
    return esrc:sub(a, b + 3)
  end
  local hb = body_of("local function held(name)")
  local pb = body_of("local function pressed(name)")
  eq("held が見つかる", hb ~= nil, true)
  eq("pressed が見つかる", pb ~= nil, true)
  eq("held は crossed を見ていない",
     hb ~= nil and hb:find("crossed(", 1, true) ~= nil, false)
  eq("pressed は両方のパッドで見ている",
     pb ~= nil and pb:find("crossed(p1, name)", 1, true) ~= nil
     and pb:find("crossed(p2, name)", 1, true) ~= nil, true)
  -- 呼び出し元が増えていたら、上の理由はもう成り立たない。
  local n = 0
  for _ in esrc:gmatch("held%(\"") do n = n + 1 end
  eq("held の呼び出しは 1 か所のまま", n, 2)
end

if fails == 0 then print("") print("全て通った") else print(fails .. " 件 NG") os.exit(1) end
