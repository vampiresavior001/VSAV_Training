-- COMMAND TRAINER (scripts/commandTrainer.lua, 2026-10-11).
--
--   [1] the Trainer tab row: one row, its names in commandLog.lua's order,
--       Off by default, a help text per command
--   [2] an attempt from the recognizer's rows: steps, ticks between them, the
--       calls the warning counts, misses, and how it ended
--   [3] what is not taken: P2, another command, an attempt begun before
--   [4] drawing, with FBNeo's drawing calls stood in: no nil colour, the
--       numbers, the orange, the dimmed steps, the wrong character
--   [5] the hook-up: GC Command Trace makes way (the boxes would overlap),
--       start-up require, the frame and load callbacks
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_command_trainer.lua
local fails = 0
local function eq(what, got, want)
	if got == want then print("  ok " .. what)
	else
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(want) .. "]")
	end
end
local function slurp(path)
	local fh = io.open(path)
	assert(fh, path .. " が読めない")
	local s = fh:read("*a")
	fh:close()
	return s
end

-- Stand-ins for FBNeo.
local ram = {}
memory = {
	readbyte = function(a) return ram[a] or 0 end,
	readword = function(a) return ram[a] or 0 end,
	readdword = function(a) return ram[a] or 0 end,
	getregister = function() return 0 end,
	registerexec = function() end,
}
emu = { framecount = function() return 0 end }
globals = { options = { command_trainer = 1 } }
package.preload["./scripts/commandLog"] = function() return dofile("commandLog.lua") end
local LOG = require "./scripts/commandLog"
local T = dofile("commandTrainer.lua")

-- ---------------------------------------------------------------------------
print("[1] Trainer タブの行")
local menu = slurp("menu.lua")
-- The row is built at the top of get_menu() (_ct_item) and placed in the tab.
local a = menu:find("        _ct_item,\n", 1, true)
local agg = menu:find('"Show Air Guard Gaps", training_settings', 1, true)
local ftt = menu:find('"Show Frame Trap Trainer", training_settings', 1, true)
eq("行がある", a ~= nil, true)
eq("Show Air Guard Gaps のすぐ下 (本人、2026-10-11)", agg ~= nil and ftt ~= nil and a ~= nil and agg < a and a < ftt, true)
-- ITS LONGEST VALUE RUNS PAST WHERE THE SECOND COLUMN STARTS, selected:
-- "< Command Trainer : Midnight Pleasure >". That is clear only while no
-- second-column row is on its line. The draw loop puts rows 1-11 in the first
-- column and row 11 + n on the line of row n (menu.lua: _draw_index > 10).
-- Which rows are drawn depends on Tick Data (its three children) and Show
-- Action Timeline (Timeline Cut), so every state is worked out here -
-- test_menu_layout looks at a fresh install only.
do
	local tb = menu:find('name = "Trainer"', 1, true)
	local te = menu:find('reset_tab_item("Trainer")', tb or 1, true)
	local order = {}
	local tab = menu:sub(tb or 1, te or 1):gsub("_ct_item,", 'x_menu_item("Seq. Command Trainer",')
	for label in tab:gmatch('_menu_item%("([^"]+)"') do order[#order + 1] = label end
	order[#order + 1] = "Reset This Tab"
	local TD_CHILD = { ["Tick Data Side"] = true, ["Show Meaty Timing"] = true, ["Show Action Timeline"] = true }
	local states = {
		{ "Tick Data OFF", false, false },
		{ "Tick Data ON・Action Timeline OFF", true, false },
		{ "Tick Data ON・Action Timeline ON", true, true },
	}
	for _, st in ipairs(states) do
		local shown = {}
		for _, l in ipairs(order) do
			local hidden = (TD_CHILD[l] and not st[2])
				or (l == "Timeline Cut (Free Ticks)" and not (st[2] and st[3]))
			if not hidden then shown[#shown + 1] = l end
		end
		local k = nil
		for i, l in ipairs(shown) do if l == "Seq. Command Trainer" then k = i end end
		local clear = k ~= nil and (k > 11 or shown[k + 11] == nil)
		eq(st[1] .. ": 同じ高さの右の列に行が無い (" .. tostring(k) .. " 行目 / 全 " .. #shown .. ")", clear, true)
	end
end
-- The values and help come from _ct at the top of get_menu(): name,
-- character and inputs per command, the shared rules under each.
eq("行は _ct から作った値と説明を使う",
	menu:find('list_menu_item("Seq. Command Trainer", training_settings, "command_trainer", _ct_names, 1, _ct_help)', 1, true) ~= nil, true)
local cta = menu:find("local _ct = {", 1, true)
local ctb = menu:find("\n}\n", cta or 1, true)
local ct = {}
for n, c, k in menu:sub(cta or 1, ctb or 1):gmatch('{ "([^"]+)",%s*"([^"]+)",%s*"([^"]+)" }') do
	ct[#ct + 1] = { n, c, k }
end
eq("_ct は PROFILES と同じ数", #ct, #LOG.PROFILES)
local WORD = { LP = 0x0100, MP = 0x0200, HP = 0x0400, LK = 0x1000, MK = 0x2000, HK = 0x4000,
               back = 0x0001, forward = 0x0002, down = 0x0004, up = 0x0008 }
for i, p in ipairs(LOG.PROFILES) do
	local c = ct[i] or {}
	local words = {}
	for k in (c[3] or ""):gmatch("%S+") do words[#words + 1] = WORD[k] or -1 end
	local same = #words == #p.steps
	for j = 1, #p.steps do if words[j] ~= p.steps[j] then same = false end end
	eq(p.key .. ": 名前・キャラ・入力が PROFILES と同じ (" .. tostring(c[1]) .. ")",
		c[1] == p.name and c[2] == p.char_name and same, true)
end
eq("初期値は Off (1)", dofile("config.lua").default_training_settings.command_trainer, 1)
-- LEFT AND RIGHT STOP AT OFF AND P1'S OWN COMMANDS (user, 2026-10-11).
-- commandTrainer.step does it; the row only hands it the value and P1's $382.
eq("左右は commandTrainer.step に P1 の $382 を渡す",
	menu:find('_m.step(self.object[self.property_name], d, memory.readbyte(0xFF8782))', 1, true) ~= nil
	and menu:find('_ct_item.left = function(self) _ct_press(self, -1, _ct_left) end', 1, true) ~= nil
	and menu:find('_ct_item.right = function(self) _ct_press(self, 1, _ct_right) end', 1, true) ~= nil
	and menu:find('package.loaded["./scripts/commandTrainer"]', 1, true) ~= nil, true)
local function walk(v, d, cid, times)
	local out = {}
	for _ = 1, times do v = T.step(v, d, cid) out[#out + 1] = v end
	return table.concat(out, " ")
end
-- 1 Off, 2 di, 3 fs, 4 cn, 5 li, 6 mp, 7 ms, 8 pm, 9 ps, 10 pd, 11 tr
eq("モリガン: 右で Off -> DI -> FS -> CN -> Off", walk(1, 1, 0x05, 4), "2 3 4 1")
eq("モリガン: 左で Off -> CN -> FS -> DI -> Off", walk(1, -1, 0x05, 4), "4 3 2 1")
eq("リリス: Off と LI だけ", walk(1, 1, 0x0E, 2), "5 1")
eq("デミトリ: Off と MP だけ", walk(1, 1, 0x01, 2), "6 1")
eq("ガロン: Off と Moment Slice", walk(1, 1, 0x02, 2), "7 1")
eq("ダークガロンも Moment Slice", walk(1, 1, 0x12, 2), "7 1")
eq("アナカリス: Off -> Magic -> Salvation -> Decoration", walk(1, 1, 0x06, 4), "8 9 10 1")
eq("レイレイ: Off と Tenraiha", walk(1, 1, 0x0D, 2), "11 1")
eq("順押しの技が無いキャラ (サスカッチ) は Off のまま", walk(1, 1, 0x0A, 2), "1 1")
eq("ほかのキャラの技 (DI) を選んだままリリスにして右: LI へ", T.step(2, 1, 0x0E), 5)
eq("同じく左: Off へ", T.step(2, -1, 0x0E), 1)
eq("範囲外の値は Off から数える", T.step(99, 1, 0x05), 2)
-- Every help line within the width the other rows keep to: the Off text, the
-- rules, and each command's first line.
local longest, widest = 0, ""
local function measure(line) if #line > longest then longest, widest = #line, line end end
local rules = menu:sub(menu:find("local _ct_rules =", 1, true) or 1, menu:find("local _ct_names", 1, true) or 1)
local offh = menu:sub(menu:find("local _ct_help =", 1, true) or 1, menu:find("for _, _c in ipairs(_ct) do", 1, true) or 1)
for _, src in ipairs({ rules, offh }) do
	for q in src:gmatch('"([^"]*)"') do
		for line in (q .. "\\n"):gmatch("(.-)\\n") do measure(line) end
	end
end
for _, c in ipairs(ct) do measure(c[1] .. ", " .. c[2] .. ": " .. c[3] .. ".") end
eq("説明の 1 行は 79 文字まで (最長 " .. longest .. ": " .. widest .. ")", longest <= 79, true)

-- ---------------------------------------------------------------------------
print("[2] 1 回の試行")
local function row(kind, step, tick, extra)
	local r = { p = 1, cmd = "di", kind = kind, step = step, tick = tick, calls = 1, face = 1 }
	for k, v in pairs(extra or {}) do r[k] = v end
	return r
end
globals.options.command_trainer = 2      -- Darkness Illusion
eq("選んだ技", T.selected() and T.selected().key, "di")
T.on_row(row("step", 1, 100))
T.on_row(row("miss", 2, 104, { edge = 0x0102, calls = 4 }))
T.on_row(row("step", 2, 112, { calls = 8 }))
T.on_row(row("step", 3, 126, { calls = 14 }))
T.on_row(row("step", 4, 129, { calls = 3 }))
T.on_row(row("complete", 5, 131, { calls = 2 }))
local t = T._trace()
eq("2 歩目は 12t 後", t.rows[2].gap, 12)
eq("2 歩目の calls は miss の前後の合計 12", t.rows[2].calls, 12)
eq("3 歩目は 14 calls", t.rows[3].calls, 14)
eq("miss は待っていた 2 歩目に", t.miss[2], 0x0102)
eq("完成した直後は発動待ち", t.done, "pending")
T.on_row(row("started", -1, 131))
eq("発動したら Success", t.done, "Success")
T.registerAfter()
eq("Success はそのまま", T._trace().done, "Success")
T.on_row(row("miss", 1, 140, { edge = 0x0400 }))
eq("終わった後の押しは足さない", T._trace().miss[1], nil)

-- Not started: complete, and the frame ends with no start.
T.on_row(row("step", 1, 200))
for k = 2, 4 do T.on_row(row("step", k, 200 + k)) end
T.on_row(row("complete", 5, 206))
T.registerAfter()
eq("発動しなければ Not started", T._trace().done, "Not started")

-- Expired and Interrupted.
T.on_row(row("step", 1, 300))
T.on_row(row("step", 2, 310))
T.on_row(row("expired", 3, 324))
t = T._trace()
eq("Expired と待っていた歩", t.done == "Expired" and t.waiting == 3 and t.at == 324, true)
T.on_row(row("step", 1, 400))
T.on_row(row("cleared", 2, 405))
eq("外から消えたら Interrupted", T._trace().done, "Interrupted")

-- ---------------------------------------------------------------------------
print("[3] 取らないもの")
T.on_row(row("step", 1, 500))
T.on_row(row("step", 2, 510, { p = 2 }))
eq("P2 の行は使わない", T._trace().rows[2], nil)
T.on_row(row("step", 2, 511, { cmd = "mp" }))
eq("選んでいない技の行は使わない", T._trace().rows[2], nil)
T.reset()
T.on_row(row("step", 3, 520))
eq("途中から始まった試行は推定しない", T._trace(), nil)
T.on_row(row("step", 1, 600))
globals.options.command_trainer = 3      -- another command (Finishing Shower)
T.registerAfter()
eq("技を替えたら消える", T._trace(), nil)
globals.options.command_trainer = 1
eq("Off なら何も選ばれていない", T.selected(), nil)

-- A CHANGE OF CHARACTER TAKES THE COMMAND WITH IT (user, 2026-10-11).
-- 1 Off, 2 di, 3 fs, 4 cn, 5 li, 6 mp, 7 ms, 8 pm, 9 ps, 10 pd, 11 tr
do
	local P1C = 0xFF8400 + 0x382
	local function at(cid) ram[P1C] = cid T.registerAfter() return globals.options.command_trainer end
	globals.match_running = function() return true end
	globals.options.command_trainer = 4          -- Cryptic Needle
	eq("モリガンの Cryptic Needle はそのまま", at(0x05), 4)
	eq("デミトリにしたら Midnight Pleasure", at(0x01), 6)
	eq("モリガンに戻したら前に選んでいた Cryptic Needle", at(0x05), 4)
	eq("初めてのアナカリスは最初の Pharaoh Magic", at(0x06), 8)
	eq("技の無いサスカッチでは変えない", at(0x0A), 8)
	eq("アナカリスに戻れば Pharaoh Magic のまま", at(0x06), 8)
	eq("レイレイにしたら Tenraiha", at(0x0D), 11)
	eq("ダークガロンにしたら Moment Slice", at(0x12), 7)
	globals.options.command_trainer = 1
	eq("Off は Off のまま", at(0x01), 1)
	globals.match_running = function() return false end
	globals.options.command_trainer = 2
	eq("試合中でなければ変えない (選択画面の $382 は途中の値)", at(0x01), 2)
	globals.match_running = nil
	globals.options.command_trainer = 1
	ram[P1C] = nil
end

-- ---------------------------------------------------------------------------
print("[4] 描画")
local texts, images, boxes, bad = {}, {}, {}, {}
gui = {
	text = function(x, y, s, c)
		texts[#texts + 1] = { x = x, y = y, s = s, c = c }
		if c == nil or (type(c) ~= "string" and type(c) ~= "number") then bad[#bad + 1] = tostring(s) end
	end,
	image = function(x, y, img) images[#images + 1] = { x = x, y = y, img = img } end,
	box = function(x1, y1, x2, y2, f, o) boxes[#boxes + 1] = { x1 = x1, y1 = y1, y2 = y2, f = f } end,
}
gd = { createFromPng = function(p) return { gdStr = function() return "png:" .. p end } end }
img_dir = {}
for i = 1, 9 do img_dir[i] = "dir" .. i end
img_no_button, img_L_button, img_M_button, img_H_button = "n", "l", "m", "h"
local function draw()
	texts, images, boxes, bad = {}, {}, {}, {}
	T.draw()
end
local function text(s)
	for _, x in ipairs(texts) do if x.s == s then return x end end
	return nil
end

globals.options.command_trainer = 1
draw()
eq("Off なら何も描かない", #texts + #images + #boxes, 0)

globals.options.command_trainer = 2
ram[0xFF8400 + 0x382] = 0x01        -- Demitri, not Morrigan
draw()
-- User, 2026-10-11: a character without the command gets no box at all.
eq("キャラが違えば何も描かない", #texts + #images + #boxes, 0)

ram[0xFF8400 + 0x382] = 0x05        -- Morrigan
ram[0xFF8400 + 0x0B] = 0            -- facing left
T.reset()
draw()
eq("試行の前: 5 歩を描く (ボタンは点 6 個、前は矢印)", #images, 6 * 4 + 1)
local arrow = nil
for _, im in ipairs(images) do if tostring(im.img):find("^dir") then arrow = im.img end end
eq("左向きなら前は左の矢印", arrow, "dir4")
eq("数字はまだ無い", #texts, 1)

T.on_row(row("step", 1, 100, { face = 1 }))
T.on_row(row("miss", 2, 104, { edge = 0x0102, calls = 4 }))
T.on_row(row("step", 2, 112, { calls = 8, face = 1 }))
T.on_row(row("step", 3, 126, { calls = 14, face = 1 }))
draw()
eq("色が nil の描画は無い", table.concat(bad, ","), "")
eq("2 歩目の 12t は白", text("12t") and text("12t").c, "#FFFFFF")
eq("3 歩目の 14t (14 calls) はオレンジ", text("14t") and text("14t").c, "#FF7F00")
eq("受け付けた歩の前の押しはオレンジで LP+F", text("LP+F") and text("LP+F").c, "#FF7F00")
local orange_arrow = false
for _, im in ipairs(images) do if im.img == "png:images/6_dir_warn.png" then orange_arrow = true end end
eq("14 calls の前の矢印はオレンジ (受け付けたときの右向き)", orange_arrow, true)
local dims = 0
for _, b in ipairs(boxes) do if b.f == "#000000BB" then dims = dims + 1 end end
eq("待っている 4 歩目より後 (5 歩目) だけ暗くする", dims, 1)
eq("まだ結果の行は無い", text("Success") == nil and text("Expired") == nil, true)

T.on_row(row("step", 4, 129, { calls = 3, face = 1 }))
T.on_row(row("complete", 5, 131, { calls = 2, face = 1 }))
T.on_row(row("started", -1, 131))
draw()
eq("Success は金色で、最初から最後までの 31t", text("Success") and text("Success").c == "#FFD700"
	and text("31t") ~= nil and text("31t").c == "#FFD700", true)

T.on_row(row("step", 1, 300, { face = 1 }))
T.on_row(row("step", 2, 310, { face = 1 }))
T.on_row(row("miss", 3, 315, { edge = 0x1002 }))
T.on_row(row("expired", 3, 324))
draw()
eq("Expired は赤で、最後に受け付けた歩から 14t", text("Expired") and text("Expired").c == "#FF0000"
	and text("14t") ~= nil and text("14t").c == "#FF0000", true)
eq("切れた歩の前の押しは赤で LK+F", text("LK+F") and text("LK+F").c, "#FF0000")
local mark = text("x")
eq("切れた 3 歩目に赤い x", mark ~= nil and mark.c == "#FF0000" and mark.y == text("LK+F").y, true)
eq("x の後ろに押した入力", mark ~= nil and text("LK+F").x > mark.x, true)

-- One LP, then nothing (user's screenshot, 2026-10-11): row 1 and row 2 drew
-- alike. The dead step gets the x; the ticks stay on the result line.
T.on_row(row("step", 1, 700, { face = 1 }))
T.on_row(row("expired", 2, 714))
draw()
local x2 = text("x")
local row2_y = 38 + 2 * 11 + 2
eq("弱P 1 つで切れたら 2 歩目に x", x2 ~= nil and x2.y == row2_y and x2.c == "#FF0000", true)
local nums = 0
for _, t2 in ipairs(texts) do if t2.s:find("^%d+t$") and t2.y < 38 + 6 * 11 then nums = nums + 1 end end
eq("歩の行には数字を出さない (時間は結果の行だけ)", nums, 0)
eq("結果の行は Expired 14t", text("Expired") ~= nil and text("14t") ~= nil and text("14t").c == "#FF0000", true)

T.on_row(row("step", 1, 400, { face = 1 }))
for k = 2, 4 do T.on_row(row("step", k, 400 + k, { face = 1 })) end
T.on_row(row("complete", 5, 406, { face = 1 }))
T.registerAfter()
draw()
eq("Not started はオレンジ", text("Not started") and text("Not started").c, "#FF7F00")
eq("色が nil の描画は無い (結果の行も)", table.concat(bad, ","), "")
-- Right of Tick Data, left of the P2 input column (screen width minus three
-- icons: 384 - 3 * 8 * 384 / 224 / (4/3) = 353). User, 2026-10-11: at 210 it lay
-- over Tick Data.
eq("箱は x 260 から、y 37 から", boxes[1] and boxes[1].x1 == 260 and boxes[1].y1 == 37, true)
local p2col = 384 - 3 * (8 * 384 / 224 / (4 / 3))
eq("箱の右端は P2 の入力の列 (" .. math.floor(p2col) .. ") より左", 262 + 78 + 4.2 + 2 < p2col, true)

-- The other shapes: seven steps, a command ending on a direction, Dark Gallon.
local function index_of(key)
	for i, p in ipairs(LOG.PROFILES) do if p.key == key then return i + 1 end end
end
globals.options.command_trainer = index_of("pd")
ram[0xFF8400 + 0x382] = 0x06        -- Anakaris
T.reset()
draw()
local dirs = {}
for _, im in ipairs(images) do if tostring(im.img):find("^dir") then dirs[#dirs + 1] = im.img end end
eq("Pharaoh Decoration: 7 歩 (ボタン 6 歩 x 点 6 個 + 下の矢印 1 つ)", #images, 6 * 6 + 1)
eq("下は下の矢印", dirs[1], "dir2")
eq("7 歩の箱は見出し + 7 行 (y 37 から 37 + 8 x 11 + 2 まで)", boxes[1] ~= nil and boxes[1].y1 == 37 and boxes[1].y2 == 38 + 8 * 11 + 1, true)
globals.options.command_trainer = index_of("tr")
ram[0xFF8400 + 0x382] = 0x0D        -- Lei-Lei
draw()
dirs = {}
for _, im in ipairs(images) do if tostring(im.img):find("^dir") then dirs[#dirs + 1] = im.img end end
eq("Tenraiha: 最後の歩は上の矢印", dirs[#dirs], "dir8")
globals.options.command_trainer = index_of("ms")
ram[0xFF8400 + 0x382] = 0x12        -- Dark Gallon
draw()
eq("Moment Slice はダークガロンでも描く", text("Moment Slice") ~= nil and #images > 0, true)
ram[0xFF8400 + 0x382] = 0x05
draw()
eq("ほかのキャラなら何も描かない", #texts + #images + #boxes, 0)
globals.options.command_trainer = 2

-- ---------------------------------------------------------------------------
print("[5] つなぎ込み")
local hud = slurp("hud.lua")
local g = hud:find("local function draw_gc_command_trace()", 1, true)
eq("表示できる場合だけ GC Command Trace を隠す",
	hud:sub(g or 1, (g or 1) + 400):find("commandTrainerModule.is_visible() then return end", 1, true) ~= nil, true)
globals.options.command_trainer = 2
ram[0xFF8782] = 0x05
eq("DI 選択中のモリガンでは GC を隠す", T.is_visible(), true)
ram[0xFF8782] = 0x08
eq("対象外キャラでは GC を隠さない", T.is_visible(), false)
globals.options.command_trainer = 1
ram[0xFF8782] = 0x05
eq("Off では GC を隠さない", T.is_visible(), false)
local master = slurp("vsav_training_master_script.lua")
eq("起動時に require", master:find('= require "./scripts/commandTrainer"', 1, true) ~= nil, true)
eq("registerStart を呼ぶ", master:find("commandTrainerModule.registerStart()", 1, true) ~= nil, true)
eq("フレームの後に registerAfter", master:find("commandTrainerModule.registerAfter()", 1, true) ~= nil, true)
eq("描画は守って呼ぶ", master:find("pcall(commandTrainerModule.draw)", 1, true) ~= nil, true)
eq("ステートの読み込みで消す", master:find("commandTrainerModule.reset()", 1, true) ~= nil, true)
local r1 = master:find("commandLogModule.registerStart()", 1, true)
local r2 = master:find("commandTrainerModule.registerStart()", 1, true)
eq("commandLog のフックを登録してから聞き手を付ける", r1 ~= nil and r2 ~= nil and r1 < r2, true)

print(fails == 0 and "\n全て通った" or ("\n" .. fails .. " 件 NG"))
os.exit(fails == 0 and 0 or 1)
