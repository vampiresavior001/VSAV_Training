-- MENU GATE TEST: "Reversal Action Steps" is on the Dummy tab only while
-- Guard Action Type is "Reversal - Action Steps" (0xB).
--
-- Loads the REAL menu.lua and the REAL editor with only the two load-time
-- requires stubbed, rebuilds the menu the way guiRegister does, and asks the
-- row's is_disabled directly. The draw loop hides disabled rows and navigation
-- skips them, so is_disabled IS the visibility switch - what this test pins is
-- that the row disappears under every other guard action and comes back under
-- 0xB, with the editor openers still attached.
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_menu_gate.lua
package.preload["./scripts/charMoves"] = function()
	return { get_player_movelists = function()
		return { P1 = { reversal_names = { "Stub" } }, P2 = { reversal_names = { "Stub" } } }
	end }
end
package.preload["./scripts/actionSequenceEditor"] = function()
	return dofile("actionSequenceEditor.lua")
end
package.preload["./scripts/actionSequenceRunner"] = function()
	return dofile("actionSequenceRunner.lua")
	end
package.preload["./scripts/position"] = function()
	return dofile("position.lua")
end


training_settings = {}
globals = {}
local ram = {}
memory = { readbyte = function(a) return ram[a] or 0 end }
gui = { text = function() end, box = function() end }
dofile("menu.lua")

menuModule.guiRegister()
local player
for _, tab in ipairs(menu) do
	if tab.name == "Dummy" then player = tab end
end
assert(player, "Dummy tab not found")

-- WHICH TAB A ROW SITS ON IS NOT WHAT THESE TESTS ARE ABOUT.
--
-- Two blocks below used to walk the Display tab by name, and both broke the
-- day the display switches were split across Display / Trainer / System /
-- Debug - not because anything they check had changed, but because the row
-- had moved one tab over. What they actually pin is that a setting is
-- REACHABLE and that the menu, config.lua and the drawing code all name the
-- same property. So look for the row anywhere, and report the tab it was
-- found on so a move is still visible in the output.
local function find_row(_name)
	for _, tab in ipairs(menu) do
		for _, e in ipairs(tab.entries) do
			if e.name == _name then return e, tab.name end
		end
	end
	return nil, nil
end

local ras, delay, loop
local pob, pobat, loopat
for _i, e in ipairs(player.entries) do
	local _ = _i
	if e.name == "Loop Wait" then loopat = _i end
	if e.name == "Reversal Action Steps" then ras = e end
	if e.name == "Guard Action Delay (Ticks)" then delay = e end
	if e.name == "Loop Wait" then loop = e end
	if e.name == "Loop Steps" then loopsw = e end
	if e.name == "Pit of Blame" then pob = e end
	if pob ~= nil and pobat == nil then pobat = _ end
end
assert(ras, "Reversal Action Steps entry not found")
assert(type(ras.is_disabled) == "function", "is_disabled missing on Reversal Action Steps")
assert(type(ras.right) == "function" and type(ras.validate) == "function", "editor openers lost")
assert(loop, "Loop Wait entry not found")
assert(loopsw, "Loop Steps entry not found")
assert(type(loop.is_disabled) == "function", "is_disabled missing on Loop Wait")
assert(pob, "Pit of Blame entry not found")
assert(type(pob.is_disabled) == "function", "is_disabled missing on Pit of Blame")

local fails = 0
local function want(what, got, w)
	if got ~= w then
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(w) .. "]")
	else
		print("  ok " .. what)
	end
end

training_settings.guard_action = 0xB
want("0xB (Action Steps) -> enabled", ras.is_disabled(), false)
training_settings.guard_action = 6
want("6 (Reversal - Specified) -> disabled", ras.is_disabled(), true)
training_settings.guard_action = 4
want("4 (Reversal - Char Specific) -> disabled", ras.is_disabled(), true)
training_settings.guard_action = 2
want("2 (Guard Cancel) -> disabled", ras.is_disabled(), true)
training_settings.guard_action = 1
want("1 (None) -> disabled", ras.is_disabled(), true)
-- The loop belongs to the list, so it is gated with the list. A Loop Wait row
-- under a guard action that cannot run a list is a setting with nothing to act
-- on.
training_settings.guard_action = 0xB
want("Loop Wait at 0xB -> enabled", loop.is_disabled(), false)
want("Loop Steps at 0xB -> enabled", loopsw.is_disabled(), false)
training_settings.guard_action = 6
want("Loop Wait at 6 -> disabled", loop.is_disabled(), true)
training_settings.guard_action = 1
want("Loop Wait at 1 -> disabled", loop.is_disabled(), true)
want("Loop Steps at 1 -> disabled", loopsw.is_disabled(), true)
-- The existing gate is untouched: the Delay row stays off in sequence mode.
training_settings.guard_action = 0xB
want("Delay row still disabled at 0xB", delay.is_disabled(), true)

-- PIT OF BLAME: アナカリスのときだけ出る行。
--
-- 咎めの穴はリバーサルではないので、ガードアクションでは絞らない - 相手が
-- ダウン中に使う技で、どのガードアクションと同時に使えても構わない。
-- 絞るのはキャラだけ。
ram[0xFF8B82] = 0x06
training_settings.guard_action = 1
want("アナカリスなら出る (guard action 1)", pob.is_disabled(), false)
training_settings.guard_action = 0xB
want("アナカリスなら出る (guard action 0xB)", pob.is_disabled(), false)
ram[0xFF8B82] = 0x05
want("モリガンでは出ない", pob.is_disabled(), true)
ram[0xFF8B82] = 0x0F
want("ジェダでも出ない", pob.is_disabled(), true)
ram[0xFF8B82] = 0x06
-- 置き場所はループ行の下。二つはどちらも「リストとは別の、繰り返しの話」で
-- 並べて読む。
want("行はループの下", pobat > loopat, true)
-- None / Normal / ES と、その 3 つから選ぶ Random (本人、2026-09-26)。
want("None / Normal / ES / Random の 4 つ", #pob.list, 4)
want("Random は最後 (保存は番号なので足すのは末尾だけ)", pob.list[4], "Random")
want("既定は None", pob.list[training_settings.pit_of_blame or 1], "None")

-- 発火側の配線。行が非 None なら、ガードアクションが何であっても出す。
-- Character Specific 経由の従来の道も残っていること。
do
  local gc = io.open("guardCancel.lua"):read("*a")
  local blk = gc:match("TWO WAYS IN, ONE TRIGGER%.(.-)\n\t\t\tend")
  -- 行の値は、頻度のロールと同じところで 1 回だけ読み、Random ならそこで引く。
  -- 発火側はその値を使う。毎フレーム引くと 3 つ全部が混ざる。
  want("発火側は、アームで決めた値を使う",
       blk ~= nil and blk:find("tonumber(pit_of_blame_roll)", 1, true) ~= nil, true)
  local arm = gc:match("pit_of_blame_roll = shouldGC%(%)(.-)pit_of_blame_ground_y")
  want("アームで行を読む",
       arm ~= nil and arm:find("training_settings.pit_of_blame", 1, true) ~= nil, true)
  want("Random (4) はアームで 3 つから引く",
       arm ~= nil and arm:find("if _pob == 4 then _pob = math.random(3) end", 1, true) ~= nil, true)
  want("頻度が外れたら引かない",
       arm ~= nil and arm:find("if pit_of_blame_roll then", 1, true) ~= nil, true)
  -- 条件そのもの。値を計算していても、条件に入っていなければ意味が無い。
  want("行と Character Specific のどちらでも開く",
       blk ~= nil and blk:find("(_via_row or _via_cs)", 1, true) ~= nil, true)
  want("Character Specific の道も残る",
       blk ~= nil and blk:find("move_is_pit_of_blame()", 1, true) ~= nil, true)
  want("行が None ならこの道は開かない",
       blk ~= nil and blk:find("_via_row = _pob ~= 1", 1, true) ~= nil, true)
  -- ES は 2 ボタン。1 つだと ES にならない。
  want("ES は 2 ボタン",
       blk ~= nil and blk:find('"MK+HK"', 1, true) ~= nil, true)
  -- 頻度のロールは従来どおり通る。素通りさせると 100% になる。
  want("頻度のロールを通る",
       blk ~= nil and blk:find("pit_of_blame_roll and", 1, true) ~= nil, true)
end
-- 既定値がある。無いとアナカリス以外でも nil 比較で拾ってしまう。
do
  local cfg = io.open("config.lua"):read("*a")
  want("config に既定がある", cfg:find("pit_of_blame = 1", 1, true) ~= nil, true)
end


-- WHAT THE Loop Wait ROW SAYS.
--
-- Off and Auto are stored below zero, so integer_menu_item's own draw would
-- print "-2" and "-1". And Auto's bracket is not decoration: the step before
-- the loop's first step is the LAST step of the list, so where that pairing has
-- a measured floor the row has to show the number - saying After over a number
-- promises something the row does not do.
local function row_text()
	local out = nil
	local _t = gui.text
	gui.text = function(_x, _y, t) out = t end
	loop.draw(loop, 0, 0, false)
	gui.text = _t
	return out
end
local function set_loop(v, steps)
	training_settings.action_steps_loop = true
	training_settings.action_steps_loop_wait = v
	ram[0xFF8B82] = 0x0A   -- Sasquatch, who has measured floors
	training_settings.action_sequences = { reversal = { ["10"] = { version = 1, steps = steps } } }
end
-- A list that ends on an attack: nothing measured about attack-into-step-one,
-- so Auto is the state test and says so.
local ATK = { { action = "atk", lever = "none", button = "LP", wait = 0 } }
-- A list that ends on a dash cancel. Looping makes it step one's predecessor,
-- and Sasquatch's back dash cancel is measured at 8.
local BDC = { { action = "atk", lever = "none", button = "LP", wait = 0 },
              { action = "dashc.b", wait = 0 } }


set_loop(-1, ATK)
want("測っていない組は Auto (After)", row_text(), "Loop Wait : Auto (After)")
set_loop(-1, BDC)
want("最終ステップがダッシュなら数字", row_text(), "Loop Wait : Auto (8)")
set_loop(5, ATK)
want("数値はそのまま", row_text(), "Loop Wait : 5")

-- Show Step Wait Ticks は 3 か所が同じキーを指していないと黙って何も出ない。
-- メニューが書く先、config が配る既定値、HUD が読む先。
do
	local row, on_tab = find_row("Show Step Wait Ticks")
	want("行がある (" .. tostring(on_tab) .. " タブ)", row ~= nil, true)
	want("書く先", row ~= nil and row.property_name or "", "display_step_wait_ticks")
	local shipped = dofile("config.lua").default_training_settings
	want("既定値は OFF", shipped.display_step_wait_ticks, false)
	local hud = io.open("hud.lua"):read("*a")
	want("HUD が同じキーを読む",
		hud:find("globals.options.display_step_wait_ticks", 1, true) ~= nil, true)
	want("HUD は runner が組んだ行を出すだけ",
		hud:find("_r.wait_log_lines(WAIT_LOG_COLS)", 1, true) ~= nil, true)
	-- 1 行で出すと右端で切れて、探している Loop が消える。
	want("HUD は折り返して描く",
		hud:find("_y + (_i - 1) * 9", 1, true) ~= nil, true)
end


-- 押しっぱなしで数字が動くか。全メニュー行を歩いて、autofire_rate を持つ行が
-- ちゃんと繰り返すことを見る。
--
-- 0 を渡した行が 5 つあり、どれも繰り返しが死んでいた: 判定が
-- state_time % rate == 0 で、Lua 5.1 の 23 % 0 は nan、nan は 0 と等しくない。
-- 1 回押しは効くので、押し続けても速くならないという形で出ていた。
do
	local held = { input = { pressed = {}, down = { left = true }, state_time = {} } }
	-- しきい値 (23) を越えて持ち続けている窓のどこかで 1 度は通ること。
	-- 何ティック目で通るかは rate 次第なので、窓で見る。
	local function repeats(rate)
		for t = 24, 40 do
			held.input.state_time.left = t
			if check_input_down_autofire(held, "left", rate) then return true end
		end
		return false
	end
	want("rate 0 でも繰り返す", repeats(0), true)
	want("rate 4 は従来どおり", repeats(4), true)
	local dead = {}
	for _, tab in ipairs(menu) do
		for _, e in ipairs(tab.entries) do
			if e.autofire_rate ~= nil and not repeats(e.autofire_rate) then
				dead[#dead + 1] = e.name
			end
		end
	end
	want("繰り返しが死んでいる行は無い", table.concat(dead, ", "), "")
	-- しきい値の手前では動かない。押しっぱなし判定そのものは残っていること。
	local brief = { input = { pressed = {}, down = { left = true },
		state_time = { left = 5 } } }
	-- しきい値の手前。
	want("押した直後は繰り返さない",
		check_input_down_autofire(brief, "left", 0), false)
end


-- P2 の入力アイコンには行が無く、HUD ごと消すしか手が無かった。
-- メニューが書く先、config の出荷値、描く側が読む先の 3 か所を突き合わせる。
do
	local row, on_tab = find_row("Show P2 Inputs")
	want("Show P2 Inputs の行がある (" .. tostring(on_tab) .. " タブ)", row ~= nil, true)
	want("書く先", row ~= nil and row.property_name or "", "display_p2_inputs")
	local shipped = dofile("config.lua").default_training_settings
	-- 行は新しいが、描いていること自体は前からなので既定は ON。
	want("既定値は ON", shipped.display_p2_inputs, true)
	local v2 = io.open("vsavscriptv2.lua"):read("*a")
	want("描く側が同じキーを読む",
		v2:find("globals.options.display_p2_inputs", 1, true) ~= nil, true)
	-- 使われていないグローバルが同じ用途で残っていた。行を足した以上、
	-- どちらが本物か分からなくなる前に消す。
	local master = io.open("vsav_training_master_script.lua"):read("*a")
	want("死んでいた show_p2 は残っていない",
		master:find("show_p2", 1, true) ~= nil, false)
end

-- P2 RANDOM GUARD % は、その値が実際に読まれるところで出ていること。
--
-- autoguard.lua が dummy_guard に通すのは guard == 2 と guard >= 4 のすべて。
-- そこで get_block_chance() を見てから Back を握るので、プッシュブロック
-- (5/6/7) もこの確率に従う。行を隠しても依存は消えず、既定が "None" なので
-- ガードせず押しもしなかった (user, 2026-09-12)。
do
	local row
	for _, e in ipairs(player.entries) do
		if e.name == "P2 Random Guard %" then row = e end
	end
	want("P2 Random Guard % の行がある", row ~= nil, true)
	local function shown(g)
		training_settings.guard = g
		return not row.is_disabled()
	end
	want("None では出ない", shown(1), false)
	want("Stand Block では出る", shown(2), true)
	want("Auto Guard では出ない", shown(3), false)
	want("All Guard では出る", shown(4), true)
	want("Push Block Light で出る", shown(5), true)
	want("Push Block Medium で出る", shown(6), true)
	want("Push Block Heavy で出る", shown(7), true)
	-- 出す条件は autoguard.lua が読む条件と同じでなければならない。片方だけ
	-- 直すと同じ事故が戻る。
	local ag = io.open("autoguard.lua"):read("*a")
	want("autoguard が 2 と 4 以上を同じ経路に通している",
		ag:find("globals.options.guard == 2 or globals.options.guard >= 4", 1, true) ~= nil,
		true)
end


-- 足元の Timer / Mash に自前のスイッチができた (2026-09-23)。
--
-- $1AB と $170 の生値で、Show PB Counter が同じ 2 バイトを履歴として
-- 出している。同じ情報が 2 か所に出たうえ、受付が開くたびに Mash: 0 が
-- 足元に居座っていた。既定 OFF にしたので、出荷値が true に戻ったら
-- 気付けるようにする。
--
-- メニューが書く先、config の出荷値、描く側が読む先の 3 か所を突き合わせる。
do
	local row, on_tab = find_row("Show Tech Hit Mash")
	want("行がある (" .. tostring(on_tab) .. " タブ)", row ~= nil, true)
	want("書く先", row ~= nil and row.property_name or "", "display_tech_hit")
	local shipped = dofile("config.lua").default_training_settings
	want("既定値は OFF", shipped.display_tech_hit, false)
	local v2 = io.open("vsavscriptv2.lua"):read("*a")
	-- 1P と 2P の 2 か所とも門の内側にあること。片方だけ塞ぐと、
	-- 消したはずの表示が対戦相手側にだけ残る。
	local n = 0
	for _ in v2:gmatch("globals%.options%.display_tech_hit") do n = n + 1 end
	want("描く側は 2 か所とも読んでいる", n, 2)
	-- 門の無い元の形が残っていないこと。
	want("素の if が残っていない",
		v2:find("		if memory.readbyte(0xff85ab) > 0 then", 1, true), nil)
	want("2P 側も同じ",
		v2:find("		if memory.readbyte(0xff89ab) > 0 then", 1, true), nil)
end
if fails == 0 then print("全て通った") else print(fails .. " failures") os.exit(1) end
