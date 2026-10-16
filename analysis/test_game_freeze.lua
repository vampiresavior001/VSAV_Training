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
--       no other script
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
end

print(fails == 0 and "\n全て通った" or ("\n" .. fails .. " 件 NG"))
os.exit(fails == 0 and 0 or 1)
