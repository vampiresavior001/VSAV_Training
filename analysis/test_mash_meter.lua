-- MASH METER (scripts/grabMashing.lua + scripts/timers.lua, 2026-10-19).
--
-- Run from scripts/ - the dofile reads and the icon path are relative.
--   cd scripts && lua5.1 ../analysis/test_mash_meter.lua
--
-- The game hooks are driven by hand: 02991C / 02997A / 02997E for a grab,
-- 0260AC / 026106 / 02610A for a hit timer, and 025F22 / 025EE6 for the 0x34
-- motion. Memory, gui and the emulator clock are mocked. This is the offline
-- check; the in-game check is separate.
local P1, P2 = 0xFF8400, 0xFF8800

local ram, regs, hooks = {}, {}, {}
memory = {
	readbyte = function(a) return ram[a] or 0 end,
	readbytesigned = function(a) return ram[a] or 0 end,
	readword = function(a) return (ram[a] or 0) * 256 + (ram[a + 1] or 0) end,
	readwordsigned = function(a)
		local v = (ram[a] or 0) * 256 + (ram[a + 1] or 0)
		return v >= 0x8000 and v - 0x10000 or v
	end,
	readdword = function(a)
		return (((ram[a] or 0) * 256 + (ram[a + 1] or 0)) * 256 + (ram[a + 2] or 0)) * 256 + (ram[a + 3] or 0)
	end,
	readdwordsigned = function(a) return memory.readdword(a) end,
	writebyte = function(a, v) ram[a] = v % 256 end,
	writeword = function(a, v) ram[a] = math.floor(v / 256) % 256; ram[a + 1] = v % 256 end,
	writedword = function(a, v)
		ram[a + 3] = v % 256; v = math.floor(v / 256)
		ram[a + 2] = v % 256; v = math.floor(v / 256)
		ram[a + 1] = v % 256; v = math.floor(v / 256)
		ram[a] = v % 256
	end,
	getregister = function(name) return regs[name:gsub("^m68000%.", "")] or 0 end,
	registerexec = function(pc, fn) hooks[pc] = fn end,
}

local draws = {}
gui = {
	text = function(x, y, s, c) draws[#draws + 1] = { kind = "text", x = x, y = y, s = tostring(s), c = c } end,
	rect = function(x1, y1, x2, y2, c, o) draws[#draws + 1] = { kind = "rect", x1 = x1, y1 = y1, x2 = x2, y2 = y2 } end,
	box = function() end,
	gdoverlay = function() end,
}
local _img = { gdStr = function() return "" end }
gd = { createFromPng = function() return _img end,
       createFromPngStr = function() return _img end, copyResampled = function() end }
emu = {
	framecount = function() return 1 end,
	screenwidth = function() return 384 end,
	screenheight = function() return 224 end,
}

globals = {
	options = { grab_mashing = 1, show_mash_timer = true, knockdown_logger_enable = false },
	controlling_p1 = true, playing = false, recording = false, show_menu = false,
	match_running = function() return true end,
	recordingWizard = { is_active = function() return false end },
}
package.preload["./scripts/debugKnockdown"] = function() return { mark_write = function() end } end
package.loaded["./scripts/actionSequenceRunner"] = {
	cancel = function() end,
	pending_count = function() return 0 end,
}
guard_action_input = {}
player_objects = { {}, {} }

local G = dofile("grabMashing.lua")
G.registerStart()
package.loaded["./scripts/grabMashing"] = G
local timersModule = dofile("timers.lua")

local fails = 0
local function want(what, got, expected)
	if got == expected then
		print("  ok " .. what)
	else
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(expected) .. "]")
	end
end

local function put_byte(a, v) memory.writebyte(a, v) end
local function put_word(a, v) memory.writeword(a, v) end
local function put_dword(a, v) memory.writedword(a, v) end
local function call(pc, a6)
	regs.a6 = a6
	regs.a7 = 0
	hooks[pc]()
end

-- One grab call: A6 the grabber, ($32,A6) the held side.
local function grab_call(grabber, held, timer, s05)
	put_word(grabber + 0x32, held % 0x10000)
	put_word(grabber + 0x15C, timer)
	put_byte(held + 0x05, s05 or 0x06)
	put_byte(held + 0x3B4, 0)
	call(G.PC.enter, grabber)
end
local function grab_end(grabber)
	hooks[G.PC.let_go]()
end
local function hit_call(base, timer, s05, s54, s140)
	put_word(base + 0x15C, timer)
	put_byte(base + 0x05, s05 or 0x02)
	put_byte(base + 0x54, s54 or 0x1D)
	put_byte(base + 0x140, s140 or 0x00)
	call(G.PC.hit_enter, base)
	call(G.PC.hit_held, base)
end
local function hit_end(base)
	call(G.PC.hit_enter, base)
	hooks[G.PC.hit_end]()
end
local function motion_call(base, ptr, count, s05, s140)
	put_dword(base + 0x1C, ptr)
	put_byte(base + 0x20, count)
	put_byte(base + 0x05, s05 or 0x02)
	put_byte(base + 0x140, s140 or 0x34)
	call(G.PC.motion, base)
end
local function motion_end(base)
	hooks[G.PC.motion_end]()
end

local function draw()
	draws = {}
	timersModule.guiRegister()
	return draws
end
local function find_text(d, s)
	for _, row in ipairs(d) do
		if row.kind == "text" and row.s == s then return row end
	end
	return nil
end
local function text_count(d, s)
	local n = 0
	for _, row in ipairs(d) do
		if row.kind == "text" and row.s == s then n = n + 1 end
	end
	return n
end
local function rect_widths(d)
	local out = {}
	for _, row in ipairs(d) do
		if row.kind == "rect" then out[#out + 1] = row.x2 - row.x1 end
	end
	table.sort(out)
	return out
end

print("[1] モーション表: 15 区間 = 120、終了レコードの 6 は加えない")
want("区間数", #G.MOTION_LENGTHS, 15)
local total = 0
for _, n in ipairs(G.MOTION_LENGTHS) do total = total + n end
want("合計", total, 120)
want("最初の区間", G.motion_remaining(G.MOTION_BASE, 16), 120)
want("2 番目の区間", G.motion_remaining(G.MOTION_BASE + G.MOTION_STRIDE, 10), 104)
want("最後の区間", G.motion_remaining(G.MOTION_BASE + 14 * G.MOTION_STRIDE, 4), 4)
want("終了レコードは 0", G.motion_remaining(G.MOTION_END, 6), 0)
want("最後の区間の次は終了", G.motion_remaining(G.MOTION_BASE + 14 * G.MOTION_STRIDE, 1), 1)
want("区間内の残り 1 は 1 減る", G.motion_remaining(G.MOTION_BASE, 15), 119)
want("追加更新 2 回ぶんは 2 減る", G.motion_remaining(G.MOTION_BASE, 14), 118)
want("不明なポインタは推測しない", G.motion_remaining(0x123456, 16), nil)
want("範囲外のカウントは推測しない", G.motion_remaining(G.MOTION_BASE, 0), nil)
want("区間長を超えるカウントも推測しない", G.motion_remaining(G.MOTION_BASE, 17), nil)

print("[2] つかみ: タイマーはつかんだ側、表示先はつかまれた側")
G.reset_meter()
put_word(P1 + 0x10, 100) ; put_word(P1 + 0x14, 100)
put_word(P2 + 0x10, 300) ; put_word(P2 + 0x14, 100)
grab_call(P1, P2, 120, 0x06)
local p2m = G.meter_state(P2)
want("P2 の状態が有効", p2m.active, true)
want("種類は grab", p2m.kind, "grab")
want("表示先は P2", p2m.target, P2)
want("タイマー所有者は P1", p2m.owner, P1)
want("初期残量", p2m.remaining, 120)
want("基準残量", p2m.baseline, 120)
want("P1 には出さない", G.meter_state(P1).active, false)
local d = draw()
want("Mash Escape が 1 つ", text_count(d, "Mash Escape"), 1)
local esc = find_text(d, "Mash Escape")
want("P2 の頭上 (x > 200)", esc ~= nil and esc.x > 200, true)
want("数値 120", find_text(d, "120") ~= nil, true)
grab_call(P1, P2, 60, 0x06)
want("更新後の残量", G.meter_state(P2).remaining, 60)
want("途中で基準を取り直さない", G.meter_state(P2).baseline, 120)
put_word(P1 + 0x15C, 59)
G.registerAfter()
want("フレーム終端では現在値", G.meter_state(P2).remaining, 59)
d = draw()
local widths = rect_widths(d)
want("固定幅のバー (40)", widths[#widths], 40)
want("半分の塗り (20)", widths[#widths - 1], 20)
grab_end(P1)
want("離したら P2 の状態が消える", G.meter_state(P2).active, false)
d = draw()
want("Mash Escape も消える", text_count(d, "Mash Escape"), 0)

print("[3] P2 が P1 をつかむ: 表示先と所有者が逆、前の状態を持ち越さない")
grab_call(P2, P1, 120, 0x06)
want("P1 の状態", G.meter_state(P1).active, true)
want("表示先は P1", G.meter_state(P1).target, P1)
want("タイマー所有者は P2", G.meter_state(P1).owner, P2)
want("P2 には出さない", G.meter_state(P2).active, false)
d = draw()
esc = find_text(d, "Mash Escape")
want("P1 の頭上 (x < 200)", esc ~= nil and esc.x < 200, true)
grab_end(P2)
want("P1 の状態が消える", G.meter_state(P1).active, false)

print("[4] タイマー短縮型: 自分の $15C、表示先も自分")
G.reset_meter()
hit_call(P1, 40, 0x02, 0x1D)
want("P1 の recovery_timer", G.meter_state(P1).kind, "recovery_timer")
want("残量 40", G.meter_state(P1).remaining, 40)
want("P2 には出さない", G.meter_state(P2).active, false)
d = draw()
want("Mash Recovery が 1 つ", text_count(d, "Mash Recovery"), 1)
want("数値 40", find_text(d, "40") ~= nil, true)
hit_end(P1)
want("終了で消える", G.meter_state(P1).active, false)

print("[4b] 残量0と終了を区別し、P1/P2を混ぜない")
G.reset_meter()
hit_call(P1, 0, 0x02, 0x1D)
want("残量0でも状態は有効", G.meter_state(P1).active, true)
want("残量0", G.meter_state(P1).remaining, 0)
d = draw()
want("0を表示する", find_text(d, "0") ~= nil, true)
hit_call(P2, 30, 0x02, 0x1D)
want("P2 も独立して有効", G.meter_state(P2).active, true)
want("P1 は 0 のまま", G.meter_state(P1).remaining, 0)
d = draw()
want("2 人ぶんのラベル", text_count(d, "Mash Recovery"), 2)
hit_end(P1)
want("P1 だけ終了", G.meter_state(P1).active, false)
want("P2 は残る", G.meter_state(P2).active, true)
hit_end(P2)
want("P2 も終了", G.meter_state(P2).active, false)

print("[4c] 画面端では位置を補正する")
G.reset_meter()
put_word(P1 + 0x10, 0)
put_word(P2 + 0x10, 384)
hit_call(P1, 20, 0x02, 0x1D)
hit_call(P2, 20, 0x02, 0x1D)
d = draw()
local off = nil
for _, row in ipairs(d) do
	if row.kind == "text" and (row.x < 0 or row.x > 384) then off = row.s end
	if row.kind == "rect" and (row.x1 < 0 or row.x2 > 384) then off = "rect" end
end
want("ラベルとバーが画面内", off, nil)
hit_end(P1)
hit_end(P2)

print("[5] モーション早送り型: 120 から区間と残り回数で計算")
G.reset_meter()
motion_call(P1, G.MOTION_BASE, 16, 0x02, 0x34)
local p1m = G.meter_state(P1)
want("P1 の recovery_motion", p1m.kind, "recovery_motion")
want("初期残量 120", p1m.remaining, 120)
want("基準は 120", p1m.baseline, 120)
put_byte(P1 + 0x20, 14)
G.registerAfter()
want("フレーム終端で更新 2 回ぶん", G.meter_state(P1).remaining, 118)
d = draw()
want("Mash Recovery が 1 つ", text_count(d, "Mash Recovery"), 1)
want("数値 118", find_text(d, "118") ~= nil, true)
motion_call(P1, G.MOTION_BASE + G.MOTION_STRIDE, 10, 0x02, 0x34)
want("区間 2 の残量", G.meter_state(P1).remaining, 104)
motion_call(P1, G.MOTION_BASE, 0, 0x02, 0x34)
want("不明なカウントは unknown", G.meter_state(P1).unknown, true)
want("不明なカウントは値を出さない", G.meter_state(P1).remaining, nil)
d = draw()
want("Mash Recovery は残る", text_count(d, "Mash Recovery"), 1)
want("不明時は -", find_text(d, "-") ~= nil, true)
want("不明時はバーを描かない", #rect_widths(d), 0)
motion_call(P1, 0x123456, 16, 0x02, 0x34)
want("不明なポインタも推測しない", G.meter_state(P1).remaining, nil)
d = draw()
want("不明なポインタでもバーを描かない", #rect_widths(d), 0)
motion_call(P1, G.MOTION_BASE, 16, 0x02, 0x34)
want("再観測で値が戻る", G.meter_state(P1).remaining, 120)
motion_end(P1)
want("終了で消える", G.meter_state(P1).active, false)

print("[6] Auto Mash Off でも観測し、メニュー停止中は保持する")
G.reset_meter()
globals.options.grab_mashing = 1
hit_call(P2, 50, 0x02, 0x1D)
want("OFF でも状態がある", G.meter_state(P2).active, true)
globals.controlling_p1 = false
globals.playing = true
hit_call(P2, 45, 0x02, 0x1D)
want("P2 操作中・再生中でも観測", G.meter_state(P2).active, true)
globals.controlling_p1 = true
globals.playing = false
globals.show_menu = true
put_byte(P2 + 0x05, 0x00)
G.registerAfter()
G.registerAfter()
want("メニュー中は消さない", G.meter_state(P2).active, true)
globals.show_menu = false
G.registerAfter()
G.registerAfter()
want("メニューを閉じた後の不一致で消える", G.meter_state(P2).active, false)
globals.options.grab_mashing = 2

hit_call(P1, 10, 0x02, 0x1D)
want("reset 前に状態がある", G.meter_state(P1).active, true)
G.reset_meter()
want("表示用 reset で両方が消える",
	(G.meter_state(P1).active or G.meter_state(P2).active), false)
hit_call(P1, 10, 0x02, 0x1D)
globals.match_running = function() return false end
G.registerAfter()
want("試合外では状態を初期化", G.meter_state(P1).active, false)
globals.match_running = function() return true end

print("[7] メニュー・設定・配線")
local function slurp(path)
	local f = io.open(path)
	assert(f, path)
	local s = f:read("*a")
	f:close()
	return s
end
local menu = slurp("menu.lua")
want("Dummy に Auto Mash", menu:find('list_menu_item("Auto Mash", training_settings, "grab_mashing"', 1, true) ~= nil, true)
want("旧 Grab Mashing の行は無い", menu:find('"Grab Mashing"', 1, true), nil)
local display_at = menu:find('name = "Display"', 1, true)
local trainer_at = menu:find('name = "Trainer"', 1, true)
local mash_row = menu:find('checkbox_menu_item("Show Mash Meter", training_settings, "show_mash_timer"', 1, true)
want("Show Mash Meter は Display 内", display_at ~= nil and trainer_at ~= nil
	and mash_row ~= nil and display_at < mash_row and mash_row < trainer_at, true)
local mash_line = menu:match("[^\n]*Show Mash Meter[^\n]*")
want("Show Mash Meter は子項目ではない", mash_line ~= nil and mash_line:find("child_of", 1, true) == nil, true)
want("Analysis から Show Mash Timer が消えた", menu:find('Show Mash Timer', 1, true), nil)
local cfg = slurp("config.lua")
want("grab_mashing の既定は 1", cfg:find("\n  grab_mashing = 1,\n", 1, true) ~= nil, true)
want("show_mash_timer の既定は false", cfg:find("\n  show_mash_timer = false,\n", 1, true) ~= nil, true)
local ms = slurp("vsav_training_master_script.lua")
want("キャラ選択でメーターを初期化", ms:find("timersModule.clear()\n\t\t\tgrabMashingModule.reset_meter()", 1, true) ~= nil, true)
want("ステート復元でメーターを初期化", ms:find('grabMashingModule.reset("load")\n\t\tgrabMashingModule.reset_meter()', 1, true) ~= nil, true)

if fails == 0 then
	print("test_mash_meter ok")
else
	print(fails .. " 件 NG")
	os.exit(1)
end
