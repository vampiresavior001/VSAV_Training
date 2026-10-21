-- THE GAME STANDS STILL WHILE THE MENU IS OPEN (scripts/gameFreeze.lua, v11.7.28).
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_game_freeze.lua
--
--   [1] the ROM the hooks rely on (analysis/mame_code c00.txt)
--   [2] when it stands: the menu open, in a match, no position move, the ROM's
--       empty block read back as zeros; A0 pointed there only then
--   [3] the check: a Tick that moves after the first frame switches it off
--       for the session, with a message
--   [4] the hook-up: master (before every early return), hooks shared with
--       no other script; globals.game_frozen set right after, a load drops it
--   [5] the check, characters too (v11.7.28.1): state, X, Y, cel, what is
--       left of the cel - after the first frame, either player
--   [6] a frame the Lua side ends (the menu closed, a position move started
--       from it) is not checked; a state load ends it with no row
--   [7] freeze_log (Knockdown Logger only): the work RAM read after the
--       first frame and when it ends, the differing addresses as ranges; a
--       failed check writes its row at once, with why
--   [8] the menu's hold on the players ($3B4 / $200) is off while the game
--       stands, on while it runs under the menu (v11.7.28.1: with $3B4 set the
--       game skips the dash recognizer, ROM 0223AC)
--   [9] the give-up notice goes to macro.lua's hold_message too (drawn under
--       Display > Recording GUI's box), once the menu has closed
local fails = 0
local function eq(what, got, want)
	if got == want then print("  ok " .. what .. " = " .. tostring(got))
	else
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(want) .. "]")
	end
end
local function slurp(p)
	local fh = io.open(p)
	assert(fh, p .. " が読めない")
	local s = fh:read("*a")
	fh:close()
	return s
end

local ram, regs, hooks, messages = {}, {}, {}, {}
memory = {
	readbyte = function(a) return ram[a] or 0 end,
	setregister = function(n, v) regs[n:gsub("^m68000%.", "")] = v end,
	registerexec = function(pc, fn) hooks[pc] = fn end,
}
emu = { message = function(m) messages[#messages + 1] = m end }
local in_match, busy = true, false
globals = { show_menu = false, match_running = function() return in_match end }
positionModule = { busy = function() return busy end }

local F = dofile("gameFreeze.lua")
F.registerStart()

-- ---------------------------------------------------------------------------
print("[1] ROM (analysis/mame_code c00.txt)")
local code = slurp("../analysis/mame_code/c00.txt")
local function at(addr, text) return (code:match("\n" .. addr .. ":[^\n]*") or ""):find(text, 1, true) ~= nil end
local ROM = {
	{ "0011A4", "clr.b   (-$7b9c,A5)" },
	{ "0011A8", "lea     (-$7da4,A5), A0" },
	{ "0011AC", "move.w  #$f, D0", "tasks" },
	{ "0011BA", "move.b  (A0), D1" },
	{ "0011BC", "cmpi.b  #$4, D1" },
	{ "0011C0", "bcc     $11d6" },
	{ "0011C6", "lea     ($20,A0), A0" },
	{ "0011CA", "dbra    D0, $11b0" },
	{ "001350", "lea     (-$7da4,A5), A0" },
	{ "001354", "move.w  #$f, D0", "waits" },
	{ "001358", "cmpi.b  #$1, (A0)" },
	{ "00135E", "subq.b  #1, ($1,A0)" },
	{ "001364", "move.b  #$4, (A0)" },
	{ "00136C", "dbra    D0, $1358" },
	{ "001370", "rts" },
	{ "008E10", "addq.b  #1, ($81,A5)" },
}
for _, r in ipairs(ROM) do
	eq(r[1] .. " " .. r[2], at(r[1], r[2]), true)
	if r[3] then eq("  M.PC." .. r[3] .. " が " .. r[1], F.PC[r[3]], tonumber(r[1], 16)) end
end
eq("16 件 x 0x20 が空き領域に収まる", F.EMPTY_LEN, 16 * 0x20)

-- ---------------------------------------------------------------------------
print("[2] 止めるとき: メニュー中・試合中・位置の移動なし・空き領域が 0")
-- One frame: before, the game's run (during, if given), after.
local function frame(during)
	F.registerBefore()
	if during then during() end
	regs.a0 = nil
	hooks[F.PC.tasks]()
	local a_tasks = regs.a0
	regs.a0 = nil
	hooks[F.PC.waits]()
	local a_waits = regs.a0
	F.registerAfter()
	return a_tasks, a_waits
end
do
	F._reset()
	globals.show_menu = false
	local a, b = frame()
	eq("メニューを閉じている: A0 はそのまま", tostring(a) .. "/" .. tostring(b), "nil/nil")
	globals.show_menu = true
	a, b = frame()
	eq("メニュー中: タスクも待ちも A0 を空き領域へ", string.format("%X/%X", a or 0, b or 0), "B8540/B8540")
	eq("  止まっている", F.frozen(), true)
	in_match = false
	a = frame()
	eq("試合中でない: 止めない", a, nil)
	in_match = true
	busy = true
	a = frame()
	eq("位置の移動中: 止めない (着くまで動かす)", a, nil)
	busy = false
	a = frame()
	eq("  着いたらまた止める", a, F.EMPTY)
	globals.show_menu = false
	a = frame()
	eq("メニューを閉じたら動かす", a, nil)
	-- The block is not empty on this build: never.
	F._reset()
	ram[F.EMPTY + 0x20 * 5] = 4
	globals.show_menu = true
	a = frame()
	eq("空き領域が 0 でなければ止めない", a, nil)
	ram[F.EMPTY + 0x20 * 5] = nil
	globals.show_menu = false
end

-- ---------------------------------------------------------------------------
print("[3] 確かめ: 止めている間に Tick が動いたら、この起動中は止めない")
do
	F._reset()
	messages = {}
	globals.show_menu = true
	ram[0xFF8081] = 10
	-- The first frame may finish the pass that was running: the Tick it ends
	-- on is the one that must hold.
	frame(function() ram[0xFF8081] = 11 end)
	frame()
	frame()
	eq("最初のフレームで動いても、その後止まっていれば続ける", F.frozen(), true)
	frame(function() ram[0xFF8081] = 12 end)
	eq("Tick が動いた: 止めるのをやめる", F.frozen(), false)
	eq("  理由", F.broken(), "the Tick moved")
	eq("  知らせる", #messages, 1)
	local a = frame()
	eq("  その後はメニュー中でも止めない", a, nil)
	globals.show_menu = false
end

-- ---------------------------------------------------------------------------
print("[4] 組み込み")
do
	local ms = slurp("vsav_training_master_script.lua")
	eq("起動時に require", ms:find('\nlocal gameFreezeModule   = require "./scripts/gameFreeze"', 1, true) ~= nil, true)
	eq("registerStart", ms:find("\tgameFreezeModule.registerStart()\n", 1, true) ~= nil, true)
	local rb = ms:find("emu.registerbefore(function()", 1, true)
	local call = ms:find("\tgameFreezeModule.registerBefore()\n", rb or 1, true)
	local first_return = ms:find("\n%s*return\n", rb or 1)
	eq("registerBefore は、最初の return より前", rb ~= nil and call ~= nil and first_return ~= nil and call < first_return, true)
	local ra = ms:find("emu.registerafter(function()", 1, true)
	local call2 = ms:find("\tgameFreezeModule.registerAfter()\n", ra or 1, true)
	local ret2 = ms:find("\n%s*return\n", ra or 1)
	eq("registerAfter も、最初の return より前", ra ~= nil and call2 ~= nil and ret2 ~= nil and call2 < ret2, true)
	-- No other script hooks the same two PCs (a second registerexec replaces
	-- the first).
	local clash = nil
	for _, f in ipairs({ "guardCancel.lua", "debugKnockdown.lua", "timers.lua", "dummyState.lua", "tickDataVsav.lua",
	                     "idleSound.lua", "stage-select.lua", "commandLog.lua", "cps2-hitboxes.lua", "invulnLog.lua",
	                     "chainLog.lua", "grabMashing.lua", "shadowGuide.lua", "frameskip-service.lua" }) do
		local fh = io.open(f)
		if fh ~= nil then
			local s = fh:read("*a") ; fh:close()
			for hx in s:gmatch("registerexec%((0x%x+)") do
				local pc = tonumber(hx)
				if pc == F.PC.tasks or pc == F.PC.waits then clash = f end
			end
		end
	end
	eq("同じ PC を他のスクリプトがフックしていない", clash, nil)
	eq("RAM は書かない (レジスタだけ)", slurp("gameFreeze.lua"):find("memory.write", 1, true), nil)
	-- What the Lua side asks before it counts a frame: published at once, so
	-- every module below reads this frame's answer.
	local CALL = "\tgameFreezeModule.registerBefore()\n"
	local pub = ms:find(CALL, rb or 1, true)
	local set = ms:find("\tglobals.game_frozen = gameFreezeModule.frozen()\n", pub or 1, true)
	local between = (pub and set) and ms:sub(pub + #CALL, set - 1) or "x"
	eq("globals.game_frozen はその直後に (間はコメントだけ)",
	   set ~= nil and between:gsub("%-%-[^\n]*", ""):gsub("%s", "") == "", true)
	local function after(text) local p = ms:find(text, rb or 1, true) ; return p ~= nil and set ~= nil and p > set end
	eq("  体力の回復はその後", after("\thealthAndMeter.registerBefore()\n"), true)
	eq("  再生 (macroLua) もその後", after("\tglobals.macroLua  = macroLuaModule.registerBefore()\n"), true)
	local ld = ms:find("savestate.registerload(function(slot)", 1, true)
	local ld_end = ld and ms:find("\n\tend)\n", ld, true)
	local body = (ld and ld_end) and ms:sub(ld, ld_end) or ""
	eq("ステートを読んだら after_load", body:find("gameFreezeModule.after_load()", 1, true) ~= nil, true)
	eq("  globals.game_frozen も下ろす", body:find("globals.game_frozen = false", 1, true) ~= nil, true)
	eq("archive_logs.py が freeze_log を退避", slurp("../analysis/archive_logs.py"):find('"freeze_log.jsonl"', 1, true) ~= nil, true)
end

-- ---------------------------------------------------------------------------
print("[5] 確かめ (v11.7.28.1): キャラクターも動かないこと")
local P1, P2 = 0xFF8400, 0xFF8800
do
	local FIELDS = { { 0x05, "状態 $05" }, { 0x06, "行動 $06" }, { 0x11, "X $10" }, { 0x15, "Y $14" },
	                 { 0x1F, "セル $1C" }, { 0x20, "セルの残り $20" } }
	for _, f in ipairs(FIELDS) do
		for _, who in ipairs({ { P1, "P1" }, { P2, "P2" } }) do
			F._reset()
			messages = {}
			globals.show_menu = true
			ram[0xFF8081] = 20
			frame(function() ram[who[1] + f[1]] = 7 end)     -- the first frame may
			frame()
			local held = F.frozen()
			frame(function() ram[who[1] + f[1]] = 8 end)
			eq(who[2] .. " の " .. f[2] .. " が動いた: やめて知らせる (最初のフレームは許す)",
			   tostring(held) .. "/" .. tostring(F.frozen()) .. "/" .. tostring(F.broken()) .. "/" .. #messages,
			   "true/false/a character moved/1")
			ram[who[1] + f[1]] = nil
		end
	end
	-- What the tool writes and the game does not watch here: not a reason.
	F._reset()
	globals.show_menu = true
	frame()
	frame(function() ram[P2 + 0x176] = 0x60 ; ram[P2 + 0x52] = 0x90 end)
	eq("対象外 (ダークフォース・体力) を書いても続ける", F.frozen(), true)
	ram[P2 + 0x176], ram[P2 + 0x52] = nil, nil
	globals.show_menu = false
	frame()
end

-- ---------------------------------------------------------------------------
print("[6] Lua 側が終えるフレームは確かめない。ステートを読んだら行も書かない")
do
	F._reset()
	messages = {}
	globals.show_menu = true
	frame()
	frame()
	-- The menu closed in this frame (Restore State, a row that closes it) and
	-- the row's own write moved a character.
	frame(function() globals.show_menu = false ; ram[P1 + 0x11] = 3 end)
	eq("メニューを閉じたフレームの書き込み: やめない", F.broken(), nil)
	frame()
	eq("  次のフレームは動かす", F.frozen(), false)
	ram[P1 + 0x11] = nil
	-- A position move asked from the menu (LP on the Position row) writes X
	-- at once.
	F._reset()
	globals.show_menu = true
	frame()
	frame()
	frame(function() busy = true ; ram[P2 + 0x11] = 9 end)
	eq("メニューから位置を動かした: やめない", F.broken(), nil)
	local a = frame()
	eq("  着くまで動かす", a, nil)
	busy = false
	a = frame()
	eq("  着いたらまた止める", a, F.EMPTY)
	ram[P2 + 0x11] = nil
	-- Restore State: the menu closes and the state loads after the check
	-- (trainingState.registerAfter runs after this one), and registerload
	-- puts the menu away.
	F._reset()
	frame()
	frame()
	ram[0xFF8081], ram[P1 + 0x11] = 99, 4
	F.after_load()
	globals.show_menu = false
	eq("ステートを読んだら止めていない扱い", F.frozen(), false)
	frame()
	eq("  やめない", F.broken(), nil)
	eq("  知らせない", #messages, 0)
	ram[0xFF8081], ram[P1 + 0x11] = nil, nil
end

-- ---------------------------------------------------------------------------
print("[7] freeze_log (Knockdown Logger のときだけ)")
do
	local rows = {}
	local real_open = io.open
	io.open = function(name, mode)
		if name == "reversal_logs/freeze_log.jsonl" then
			return { write = function(_, s) rows[#rows + 1] = s end, close = function() end }
		end
		return real_open(name, mode)
	end
	eq("範囲: 4 バイト以内はつなぐ", table.concat(F._ranges("\0\0\0\0\0\0\0\0\0\0\0\0", "\1\0\0\0\1\0\0\0\0\0\1\0"), " "),
	   "FF0000-FF0004 FF000A")
	eq("  同じなら空", #F._ranges("abc", "abc"), 0)
	local many_a, many_b = {}, {}
	for i = 1, 3000 do many_a[i] = "\0" ; many_b[i] = (i % 10 == 1) and "\1" or "\0" end
	eq("  200 件で打ち切る", #F._ranges(table.concat(many_a), table.concat(many_b)), 200)
	globals.options = { knockdown_logger_enable = false }
	F._reset()
	globals.show_menu = true
	frame()
	frame()
	globals.show_menu = false
	frame()
	eq("Logger Off: 書かない", #rows, 0)
	globals.options.knockdown_logger_enable = true
	F._reset()
	ram[0xFF8081] = 33
	globals.show_menu = true
	frame()
	frame(function() ram[0xFF8080] = 5 end)          -- the vblank counter runs on
	frame(function() ram[0xFF8080] = 6 ; ram[0xFF9001] = 1 ; ram[0xFF9003] = 1 end)
	globals.show_menu = false
	frame()
	eq("見出しと 1 行", #rows, 2)
	eq("  見出し", (rows[1] or ""):match('^{"log": "freeze_log", "version": 2,') ~= nil, true)
	eq("  行", rows[2], '{"frames": 3, "tick": 33, "changed": ["FF8080", "FF9001-FF9003"]}\n')
	-- Ended by a load: no row.
	F._reset()
	globals.show_menu = true
	frame()
	frame(function() ram[0xFF8080] = 7 end)
	F.after_load()
	globals.show_menu = false
	frame()
	eq("ステートを読んで終わった: 行は書かない", #rows, 2)
	-- A failed check writes its row at once, with why (review of 328c706).
	F._reset()
	messages = {}
	globals.show_menu = true
	frame()
	frame(function() ram[0xFF8081] = 34 ; ram[P2 + 0x11] = 5 end)
	eq("止められなかった: その場で 1 行", #rows, 3)
	eq("  理由と変わった場所", rows[3], '{"frames": 2, "tick": 33, "gave_up": "the Tick moved", "changed": ["FF8081", "FF8811"]}\n')
	globals.show_menu = false
	frame()
	eq("  閉じても重ねて書かない", #rows, 3)
	F._reset()
	ram[P2 + 0x11] = nil
	io.open = real_open
	globals.options = nil
	for k in pairs(ram) do if k >= 0xFF0000 then ram[k] = nil end end
end

-- ---------------------------------------------------------------------------
print("[8] 止まっている間はメニューが両者の $3B4 / $200 を立てない")
do
	local c20 = slurp("../analysis/mame_code/c20.txt")
	local function at20(addr, text) return (c20:match("\n" .. addr .. ":[^\n]*") or ""):find(text, 1, true) ~= nil end
	eq("ROM 0223AC: $3B4 を見る", at20("0223AC", "tst.b   ($3b4,A6)"), true)
	eq("  0223B0: 0 でなければ本人の処理を飛ばす", at20("0223B0", "bne     $22406"), true)
	eq("  0223EC: 飛ばされる側に前ダッシュの受付", at20("0223EC", "jsr     $29f12.l"), true)
	local ms = slurp("vsav_training_master_script.lua")
	local SET = "\tglobals.game_frozen = gameFreezeModule.frozen()\n"
	local HEAD = "\tif globals.show_menu == true and globals.controllerModule ~= nil then\n"
	local s = ms:find(SET, 1, true)
	local h = s and ms:find(HEAD, s, true)
	local e = h and ms:find("\n\tend\n", h, true)
	eq("globals.game_frozen の直後 (間はコメントだけ)",
	   h ~= nil and ms:sub(s + #SET, h - 1):gsub("%-%-[^\n]*", ""):gsub("%s", "") == "", true)
	local fn = (h and e) and loadstring(ms:sub(h, e + 5)) or nil
	eq("  切り出して動かせる", fn ~= nil, true)
	local saved = globals
	local calls
	local function run(show, frozen)
		calls = {}
		globals = { show_menu = show, game_frozen = frozen, controllerModule = {
			enable_both_players = function() calls[#calls + 1] = "enable" end,
			disable_both_players = function() calls[#calls + 1] = "disable" end } }
		if fn then fn() end
		return table.concat(calls, ",")
	end
	eq("メニュー中・止まっている: 立てない (外す)", run(true, true), "enable")
	eq("メニュー中・動いている (位置の移動・試合外): 立てる", run(true, false), "disable")
	eq("メニューを閉じている: 触らない (閉じるときに togglemenu が外す)", run(false, false), "")
	globals = saved
	local first_return = ms:find("\n%s*return\n", ms:find("emu.registerbefore(function()", 1, true) or 1)
	eq("最初の return より前", h ~= nil and first_return ~= nil and h < first_return, true)
	eq("$3B4 を書くのは controller.lua だけ",
	   (slurp("controller.lua"):find("player_addr + 0x3B4", 1, true) ~= nil) and ms:find("0x3B4", 1, true) == nil, true)
end

-- ---------------------------------------------------------------------------
print("[9] やめた知らせは、メニューを閉じてから Recording GUI の枠の下へも (hold_message)")
do
	local held = {}
	globals.macroLua = { hold_message = function(t) held[#held + 1] = t end }
	F._reset()
	messages = {}
	globals.show_menu = true
	ram[0xFF8081] = 30
	frame()
	frame()
	frame(function() ram[0xFF8081] = 31 end)
	eq("やめた: メッセージ欄へはその場で", #messages, 1)
	frame()
	eq("  メニュー中は枠の下へはまだ渡さない", #held, 0)
	globals.show_menu = false
	frame()
	eq("  閉じたら 1 回渡す", #held, 1)
	eq("  文", held[1], "Menu: the game could not be stopped - it runs under the menu this session")
	frame()
	eq("  それ以上は渡さない", #held, 1)
	globals.macroLua = nil
	ram[0xFF8081] = nil
end

print(fails == 0 and "\n全て通った" or ("\n" .. fails .. " 件 NG"))
os.exit(fails == 0 and 0 or 1)
