-- GRAB MASHING (scripts/grabMashing.lua, 2026-10-15).
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_grab_mashing.lua
--
--   [1] the ROM the hooks rely on (analysis/mame_code)
--   [2] the hooks: six, none shared with another script
--   [3] the words: Normal / Fast held for their periods from the first Tick,
--       Fastest a new lever press and a new button press every Tick, the raw
--       lever for the facing
--   [4] when: on the dummy's first input after a grab call that held it, in
--       the same state - the call is then used up. Whichever comes first in a
--       Tick (P1's call before the dummy's input, v11.7.26_2; the dummy's own
--       after it, v11.7.26_3). Not with no call since, a let-go or a state
--       change, not for P1's input
--   [5] not while P2 is yours, a recording plays or records, the wizard is up,
--       the menu is open, there is no match, or it is Off
--   [6] grabbed: the reversal plans made before go; grabbing: they stay. A
--       Tick without a call keeps the run's place
--   [7] the log, and the hook-up: menu, config, master script, archive
local fails = 0
local function eq(what, got, want)
	if got == want then print("  ok " .. what .. " = " .. tostring(got))
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

local ram, regs, hooks = {}, {}, {}
memory = {
	readbyte = function(a) return ram[a] or 0 end,
	readword = function(a) return (ram[a] or 0) * 256 + (ram[a + 1] or 0) end,
	readdword = function(a)
		return (((ram[a] or 0) * 256 + (ram[a + 1] or 0)) * 256 + (ram[a + 2] or 0)) * 256 + (ram[a + 3] or 0)
	end,
	writeword = function(a, v) ram[a] = math.floor(v / 256) % 256 ; ram[a + 1] = v % 256 end,
	getregister = function(name) return regs[name:gsub("^m68000%.", "")] or 0 end,
	registerexec = function(pc, fn) hooks[pc] = fn end,
}
local frame = 0
emu = { framecount = function() return frame end }
local wizard_on = false
globals = {
	options = { grab_mashing = 2, knockdown_logger_enable = false },
	controlling_p1 = true, playing = false, recording = false, show_menu = false,
	match_running = function() return true end,
	recordingWizard = { is_active = function() return wizard_on end },
}
local cancels = 0
package.loaded["./scripts/actionSequenceRunner"] = { cancel = function() cancels = cancels + 1 end }
guard_action_input = { csp_due = 5 }
player_objects = { {}, { pending_input_sequence = { 1 }, counter = { sequence = { 1 }, attack_frame = 3, ref_time = 4 } } }

local G = dofile("grabMashing.lua")
G.registerStart()

local P1, P2 = 0xFF8400, 0xFF8800
local STACK = 0xFF0100
local function lg(v) ram[0xFF8081] = v % 256 end
local function word(a, v) memory.writeword(a, v) end
-- A grab call: A6 the grabber, the held side through its $32, then how it returned.
local function grab_call(grabber, held, still, ret)
	regs.a6, regs.a7 = grabber, STACK
	word(grabber + 0x32, held % 0x10000)
	word(STACK, math.floor((ret or 0x02FE54) / 0x10000)) ; word(STACK + 2, (ret or 0x02FE54) % 0x10000)
	hooks[G.PC.enter]()
	if still then hooks[G.PC.held]() else hooks[G.PC.let_go]() end
end
-- The dummy's input routine on this Tick: $122 as the copy left it, then the hook.
local SENTINEL = 0xABCD
local function input_tick(base)
	regs.a6 = base or P2
	word((base or P2) + 0x122, SENTINEL)
	hooks[G.PC.input]()
	return memory.readword((base or P2) + 0x122)
end
local function fresh(mode)
	G.reset("test")
	globals.options.grab_mashing = mode or 2
	globals.controlling_p1, globals.playing, globals.recording, globals.show_menu = true, false, false, false
	wizard_on = false
	ram[P2 + 0x05], ram[P2 + 0x0B], ram[P2 + 0x124], ram[P2 + 0x125] = 0x06, 0, 0, 0
	cancels = 0
end

-- ---------------------------------------------------------------------------
print("[1] ROM の経路 (analysis/mame_code)")
local code = { c20 = slurp("../analysis/mame_code/c20.txt"), c28 = slurp("../analysis/mame_code/c28.txt") }
local function at(src, addr, text)
	return (code[src]:match("\n" .. addr .. ":[^\n]*") or ""):find(text, 1, true) ~= nil
end
local ROM = {
	-- The input routine: the two players in an order picked at random (bit 0
	-- of 014E8A). It runs after the grab calls of the same Tick - measured
	-- (v11.7.26_2), not readable here.
	{ "c20", "02207E", "tst.b   ($137,A5)" },
	{ "c20", "02209A", "jsr     $14e8a.l" },
	{ "c20", "0220A0", "btst    #$0, D0" },
	{ "c20", "0220A6", "lea     ($400,A5), A6" },
	{ "c20", "0220CC", "lea     ($800,A5), A6" },
	{ "c20", "022114", "move.w  ($122,A6), ($124,A6)" },
	{ "c20", "02211A", "move.w  ($394,A6), ($122,A6)" },
	{ "c20", "022120", "move.w  ($12a,A6), ($12c,A6)", "input" },
	{ "c20", "022126", "move.w  ($394,A6), ($12a,A6)" },
	{ "c20", "02218E", "tst.b   ($b,A6)" },
	{ "c20", "022194", "move.w  ($122,A6), D0" },
	{ "c20", "0221AA", "move.w  ($124,A6), D0" },
	{ "c20", "0221B4", "move.w  D0, ($126,A6)" },
	-- The held side's mash, A6 the grabber.
	{ "c28", "02991C", "tst.b   ($10d,A5)", "enter" },
	{ "c28", "029924", "movea.w ($32,A6), A4" },
	{ "c28", "029928", "tst.b   ($3b4,A4)" },
	{ "c28", "029930", "move.b  ($127,A4), D0" },
	{ "c28", "029934", "andi.b  #$f, D0" },
	{ "c28", "029952", "move.b  ($126,A4), D0" },
	{ "c28", "029956", "andi.b  #$77, D0" },
	{ "c28", "029974", "subq.w  #1, ($15c,A6)" },
	{ "c28", "02997A", "moveq   #$0, D0", "held" },
	{ "c28", "02997E", "clr.w   ($15c,A6)", "let_go" },
	{ "c28", "029982", "moveq   #$1, D0" },
	{ "c28", "0299B4", "moveq   #$0, D0", "held_cpu" },
	-- The grabber's own mash.
	{ "c28", "0299B8", "tst.b   ($3b4,A6)", "own" },
	{ "c28", "0299BE", "tst.b   ($126,A6)" },
	{ "c28", "0299CA", "tst.b   ($127,A6)" },
}
for _, r in ipairs(ROM) do
	eq(r[2] .. " " .. r[3], at(r[1], r[2], r[3]), true)
	if r[4] ~= nil then eq("  M.PC." .. r[4] .. " が " .. r[2], G.PC[r[4]], tonumber(r[2], 16)) end
end
local named = 0
for _ in pairs(G.PC) do named = named + 1 end
eq("M.PC は全部照合した", named, 6)

-- ---------------------------------------------------------------------------
print("[2] フック: 6 か所、他のスクリプトとは重ならない")
local n = 0
for _, pc in pairs(G.PC) do if hooks[pc] ~= nil then n = n + 1 end end
eq("全部に登録", n, 6)
local others = {}
for _, f in ipairs({ "guardCancel.lua", "debugKnockdown.lua", "timers.lua", "dummyState.lua",
                     "tickDataVsav.lua", "idleSound.lua", "frameskip-service.lua",
                     "stage-select.lua", "commandLog.lua", "cps2-hitboxes.lua", "invulnLog.lua" }) do
	local fh = io.open(f)
	if fh ~= nil then
		local s = fh:read("*a") ; fh:close()
		for hx in s:gmatch("registerexec%((0x%x+)") do others[tonumber(hx)] = f end
	end
end
others[0x018230] = "tickDataVsav.lua (STRIKE_PC)"
for a = 0x26D00, 0x26D90, 2 do others[a] = "debugKnockdown.lua (sweep)" end
local tdv = slurp("tickDataVsav.lua"):match("GRAB_ATTEMPTS%s*=%s*(%b{})")
for hx in (tdv or ""):gmatch("0x%x+") do others[tonumber(hx)] = "tickDataVsav.lua (GRAB_ATTEMPTS)" end
for _, pc in pairs(dofile("chainLog.lua").PC) do others[pc] = "chainLog.lua" end
local clash = nil
for k, pc in pairs(G.PC) do if others[pc] ~= nil then clash = k .. " / " .. others[pc] end end
eq("重なりなし", clash, nil)

-- ---------------------------------------------------------------------------
print("[3] 入力: Normal / Fast は周期ごと、Fastest は毎 Tick 新しい押し")
do
	local function seq(mode, count)
		local out = {}
		for i = 0, count - 1 do local b, l = G.word(mode, i, 0, 0) ; out[#out + 1] = string.format("%02X%02X", b, l) end
		return table.concat(out, " ")
	end
	-- Normal: lever every 4 (dr d dl l ...), buttons every 6 (LP, LK).
	eq("Normal 0-11", seq("Normal", 12), "0106 0106 0106 0106 0104 0104 1004 1004 1005 1005 1005 1005")
	local b, l = G.word("Normal", 32, 0, 0)
	eq("Normal は 8 方向で 1 周 (32t で dr に戻る)", l, 0x06)
	b, l = G.word("Normal", 12, 0, 0)
	eq("Normal はボタン 2 つで 1 周 (12t で LP に戻る)", b, 0x01)
	-- Fast: lever every 3 (dl d ur u dl ur), buttons every 4 (LP, LK).
	eq("Fast 0-8", seq("Fast", 9), "0105 0105 0105 0104 1004 1004 100A 100A 010A")
	b, l = G.word("Fast", 20, 0, 0)
	eq("Fast 20t: ボタンは 2 つ目 (LK)", b, 0x10)
	-- Fastest: a bit not held on the last Tick.
	b, l = G.word("Fastest", 0, 0x00, 0x00)
	eq("Fastest、前に何も無い: LP と前", string.format("%02X %02X", b, l), "01 02")
	b, l = G.word("Fastest", 1, 0x01, 0x02)
	eq("  前が LP と前: LK と後ろ", string.format("%02X %02X", b, l), "10 01")
	b, l = G.word("Fastest", 2, 0x10, 0x01)
	eq("  前が LK と後ろ: LP と前", string.format("%02X %02X", b, l), "01 02")
	b, l = G.word("Fastest", 0, 0x03, 0x06)
	eq("  LP と MP を押したまま、下と前: LK と後ろ", string.format("%02X %02X", b, l), "10 01")
	b, l = G.word("Fastest", 0, 0x11, 0x03)
	eq("  LP と LK を押したまま: 離す (0) - 次の Tick に押せる", string.format("%02X %02X", b, l), "00 00")
	-- Light buttons only: medium and heavy ones tech the throw (v11.7.26_3).
	local heavy = false
	for _, m in ipairs({ "Normal", "Fast" }) do
		for i = 0, 47 do local bb = G.word(m, i, 0, 0) ; if bb % 0x10 > 1 or bb >= 0x20 then heavy = true end end
	end
	for _, pb in ipairs({ 0x00, 0x01, 0x10, 0x03, 0x77 }) do
		local bb = G.word("Fastest", 0, pb, 0) ; if bb % 0x10 > 1 or bb >= 0x20 then heavy = true end
	end
	eq("中・強のボタンは押さない (投げ抜けしないように)", heavy, false)
	eq("Off は何も入れない", select(1, G.word("Off", 0, 0, 0)), 0)
	-- Raw lever: 022194 swaps bits 0 and 1 when $b is set.
	eq("向き 0: そのまま", G.raw_lever(0x06, 0), 0x06)
	eq("向き 1: 前 (0x02) は 0x01 で書く", G.raw_lever(0x02, 1), 0x01)
	eq("  下+前 (0x06) は 0x05", G.raw_lever(0x06, 1), 0x05)
	eq("  上 (0x08) は変わらない", G.raw_lever(0x08, 1), 0x08)
end

-- ---------------------------------------------------------------------------
print("[4] いつ: つかみの呼出が続いていたら、その後のダミーの入力に (呼出は使い切り)。離された・状態が変わった・呼出が無いときは入れない")
do
	-- The input routine runs after the grab call of the same Tick (v11.7.26_2),
	-- and what it makes is read by the next Tick's call.
	fresh(2)
	lg(10)
	eq("つかみの前は入れない", input_tick(), SENTINEL)
	grab_call(P1, P2, true)                      -- P1 grabs the dummy on Tick 10, held
	eq("呼ばれた Tick: Normal の 1 つ目 (LP、下+前)", input_tick(), 0x0106)
	eq("  P1 の入力には入れない", input_tick(P1), SENTINEL)
	lg(11) ; grab_call(P1, P2, true)
	eq("続く: 2 Tick 目も同じ組み合わせ", input_tick(), 0x0106)
	lg(12) ; grab_call(P1, P2, false)            -- let go on Tick 12
	eq("離された Tick は入れない", input_tick(), SENTINEL)
	eq("  続きも消える", G._run(), nil)
	lg(13)
	eq("  その次の Tick も入れない", input_tick(), SENTINEL)
	-- The dummy's state changed after a call that held.
	fresh(2)
	lg(20) ; grab_call(P1, P2, true)
	ram[P2 + 0x05] = 0x02
	eq("状態 ($05) が変わったら入れない", input_tick(), SENTINEL)
	-- A call is used up by the input after it: a second input with no call
	-- since gets nothing (the grab may be over).
	fresh(2)
	lg(30) ; grab_call(P1, P2, true)
	eq("呼出の後の入力には入れる", input_tick(), 0x0106)
	lg(31)
	eq("  その後に呼出が無ければ、次の入力には入れない", input_tick(), SENTINEL)
	-- The dummy grabbing: its call of a Tick comes after that Tick's input
	-- (v11.7.26_3), so the input it gets is the next Tick's.
	fresh(2)
	ram[P2 + 0x05] = 0x04
	lg(34)
	eq("ダミーがつかむ: その Tick の入力 (呼出の前) には入れない", input_tick(), SENTINEL)
	grab_call(P2, P1, true)
	lg(35)
	eq("  次の Tick の入力 (前の呼出の後) に入れる", input_tick(), 0x0106)
	-- Too old: two Ticks.
	fresh(2)
	lg(36) ; grab_call(P1, P2, true)
	lg(38)
	eq("2 Tick 前の呼出では入れない", input_tick(), SENTINEL)
	-- Free ($05 0): never.
	fresh(2)
	ram[P2 + 0x05] = 0
	lg(40) ; grab_call(P1, P2, true)
	eq("ダミーが動ける状態 ($05 0) なら入れない", input_tick(), SENTINEL)
	-- A grab between others: nothing for the dummy.
	fresh(2)
	lg(50) ; grab_call(P1, 0xFF9000, true)
	eq("ダミーの関わらないつかみでは入れない", input_tick(), SENTINEL)
	-- The facing: raw lever.
	fresh(4)
	ram[P2 + 0x0B] = 1
	lg(60) ; grab_call(P1, P2, true)
	eq("Fastest、向き 1: LP と前 (raw 0x01)", input_tick(), 0x0101)
end

-- ---------------------------------------------------------------------------
print("[5] 入れないとき")
do
	local function blocked(set, unset)
		fresh(2)
		lg(70) ; grab_call(P1, P2, true)
		set()
		local w = input_tick()
		unset()
		return w
	end
	eq("P2 を操作している", blocked(function() globals.controlling_p1 = false end, function() globals.controlling_p1 = true end), SENTINEL)
	eq("レコーディングの再生中", blocked(function() globals.playing = true end, function() globals.playing = false end), SENTINEL)
	eq("記録中", blocked(function() globals.recording = true end, function() globals.recording = false end), SENTINEL)
	eq("Recording Wizard", blocked(function() wizard_on = true end, function() wizard_on = false end), SENTINEL)
	eq("メニュー", blocked(function() globals.show_menu = true end, function() globals.show_menu = false end), SENTINEL)
	eq("試合中でない", blocked(function() globals.match_running = function() return false end end,
	                            function() globals.match_running = function() return true end end), SENTINEL)
	eq("Off", blocked(function() globals.options.grab_mashing = 1 end, function() globals.options.grab_mashing = 2 end), SENTINEL)
	-- Why nothing went in is logged.
	globals.options.knockdown_logger_enable = true
	blocked(function() globals.playing = true end, function() globals.playing = false end)
	local rr = G._rows()
	eq("入れなかった理由を残す (skip / playing)", rr[#rr] and (rr[#rr].kind .. " / " .. tostring(rr[#rr].why)), "skip / playing")
	globals.options.knockdown_logger_enable = false
	-- And a run in progress ends there.
	fresh(2)
	lg(80) ; grab_call(P1, P2, true) ; input_tick()
	globals.show_menu = true
	lg(81) ; grab_call(P1, P2, true) ; input_tick()
	eq("メニューを開いたら続きも消える", G._run(), nil)
	globals.show_menu = false
end

-- ---------------------------------------------------------------------------
print("[6] つかまれたら、前の反撃の予定は消す。つかんだときは消さない")
do
	fresh(2)
	guard_action_input.csp_due = 5
	player_objects[2].pending_input_sequence = { 1 }
	player_objects[2].counter.sequence = { 1 }
	lg(90) ; grab_call(P1, P2, true) ; input_tick()
	eq("Action Steps / Specified の残りを消す (runner.cancel)", cancels, 1)
	eq("  Character Specific の待ちを消す", guard_action_input.csp_due, nil)
	eq("  送る前の入力を消す", player_objects[2].pending_input_sequence, nil)
	eq("  反撃の列を消す", player_objects[2].counter.sequence, nil)
	lg(91) ; grab_call(P1, P2, true) ; input_tick()
	eq("  続きの Tick では消し直さない", cancels, 1)
	-- The dummy grabbing.
	fresh(2)
	ram[P2 + 0x05] = 0x04
	guard_action_input.csp_due = 7
	lg(100) ; grab_call(P2, P1, true)
	eq("つかんだ側でも入れる", input_tick(), 0x0106)
	eq("  自分の行動の予定は消さない", cancels, 0)
	eq("  Character Specific の待ちも残す", guard_action_input.csp_due, 7)
	-- A Tick with no call (a freeze): nothing that Tick, the run keeps its place.
	fresh(2)
	lg(110) ; grab_call(P1, P2, true) ; input_tick()               -- n 0
	lg(111) ; grab_call(P1, P2, true) ; input_tick()               -- n 1
	lg(112)
	eq("呼ばれなかった Tick は入れない", input_tick(), SENTINEL)
	eq("  続きは残る", G._run() ~= nil, true)
	lg(113) ; grab_call(P1, P2, true) ; input_tick()               -- n 2
	lg(114) ; grab_call(P1, P2, true) ; input_tick()               -- n 3
	lg(115) ; grab_call(P1, P2, true)
	eq("  続きから数える: 5 Tick 目 (n 4) で方向が変わる (下)", input_tick(), 0x0104)
end

-- ---------------------------------------------------------------------------
print("[7] ログと組み込み")
do
	fresh(2)
	globals.options.knockdown_logger_enable = true
	local base = #G._rows()
	lg(120) ; grab_call(P1, P2, true) ; input_tick()
	local kinds = {}
	for i = base + 1, #G._rows() do local r = G._rows()[i] ; kinds[r.kind] = (kinds[r.kind] or 0) + 1 end
	eq("call の行", kinds.call, 1)
	eq("end の行", kinds["end"], 1)
	eq("run (start) の行", kinds.run, 1)
	eq("inject の行", kinds.inject, 1)
	local bad = nil
	for _, r in ipairs(G._rows()) do
		local t = G._row_text(r)
		if t:find("nil", 1, true) or not t:match("^{.*}\n$") then bad = t end
	end
	eq("行の文字に nil が無い", bad, nil)
	local wrote = {}
	local real_open = io.open
	io.open = function(path, mode)
		if path:find("grab_log", 1, true) then
			return { write = function(_, s) wrote[#wrote + 1] = s end, close = function() end }
		end
		return real_open(path, mode)
	end
	frame = 100 ; G.registerAfter()
	io.open = real_open
	eq("フレームの後で書く (ヘッダ + 行)", #wrote >= 2 and wrote[1]:sub(1, 19) == '{"log": "grab_log",', true)
	globals.options.knockdown_logger_enable = false

	local menu = slurp("menu.lua")
	eq("Dummy タブに Grab Mashing (Off / Normal / Fast / Fastest、既定 Off)",
	   menu:find('list_menu_item("Grab Mashing", training_settings, "grab_mashing", { "Off", "Normal", "Fast", "Fastest" }, 1,', 1, true) ~= nil, true)
	local i_tech = menu:find('list_menu_item("Random Throw Tech %"', 1, true)
	local i_grab = menu:find('list_menu_item("Grab Mashing"', 1, true)
	local i_guard = menu:find('list_menu_item("Guard", training_settings', 1, true)
	eq("  Random Throw Tech % の下、Guard の上", i_tech ~= nil and i_grab ~= nil and i_guard ~= nil and i_tech < i_grab and i_grab < i_guard, true)
	eq("  旧名 Grab Mash を UI に使わない", menu:find('"Grab Mash"', 1, true), nil)
	eq("config の既定は 1 (Off)", slurp("config.lua"):find("\n  grab_mashing = 1,\n", 1, true) ~= nil, true)
	local ms = slurp("vsav_training_master_script.lua")
	eq("起動時に require", ms:find('\nlocal grabMashingModule  = require "./scripts/grabMashing"', 1, true) ~= nil, true)
	eq("registerStart", ms:find("\tgrabMashingModule.registerStart()\n", 1, true) ~= nil, true)
	eq("registerAfter", ms:find("\tgrabMashingModule.registerAfter()\n", 1, true) ~= nil, true)
	local load = ms:match("savestate%.registerload%(function%(slot%)(.-)\nend%)")
	eq("ステートのロードで止める", load ~= nil and load:find('grabMashingModule.reset("load")', 1, true) ~= nil, true)
	eq("archive_logs.py が退避する", slurp("../analysis/archive_logs.py"):find('"grab_log.jsonl"', 1, true) ~= nil, true)
end

print(fails == 0 and "\n全て通った" or ("\n" .. fails .. " 件 NG"))
os.exit(fails == 0 and 0 or 1)
