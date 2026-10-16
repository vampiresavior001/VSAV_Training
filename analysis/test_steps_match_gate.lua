-- THE DUMMY'S ACTION STEPS ARE NOT DROPPED WHEN ONE PLAYER'S $1 GOES TO 0
-- (scripts/guardCancel.lua, v11.7.28).
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_steps_match_gate.lua
--
-- User, 2026-10-16: "ブランチの後の最速ダッシュがでない". Sasquatch's Reversal
-- steps were dash, Big Branch, dash, MK; with the Branch connecting, the last
-- two never came out. guardCancel dropped the runner's queue whenever
-- match_begun was false, and match_begun wants both players' $1 at 1 - which a
-- hit clears on the one hit (0240EC, the hit type 0x24 init's airborne branch)
-- as a transformation does.
--
--   [1] the ROM: the clear the Branch's reaction can take
--   [2] guardCancel drops the queue on globals.match_running, not match_begun
--   [3] the master's match_running holds with only one player active
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

print("[1] ROM (analysis/mame_code c20.txt)")
local code = slurp("../analysis/mame_code/c20.txt")
local function at(addr, text) return (code:match("\n" .. addr .. ":[^\n]*") or ""):find(text, 1, true) ~= nil end
eq("0240A0 tst.b ($11f,A6)", at("0240A0", "tst.b   ($11f,A6)"), true)
eq("0240D6 hit type 0x25", at("0240D6", "move.b  #$25, ($54,A6)"), true)
eq("0240EC clr.b ($1,A6)", at("0240EC", "clr.b   ($1,A6)"), true)
eq("gameState: match_begun は両者の $1 が 1",
   slurp("gameState.lua"):find("return p1_char_active == 1 and p2_char_active == 1", 1, true) ~= nil, true)

print("[2] guardCancel: Action Steps を消すのは試合が終わったとき (match_running)")
local gc = slurp("guardCancel.lua")
local a = gc:find("if not actionSequenceRunnerModule.owns(globals.dummy.guard_action)", 1, true)
local b = a and gc:find("actionSequenceRunnerModule.cancel()", a, true)
local gate = (a and b) and gc:sub(a, b) or ""
eq("条件は _live", gate:find("or not _live then", 1, true) ~= nil, true)
eq("  match_begun を見ない", gate:find("match_begun", 1, true), nil)
eq("  _live は globals.match_running (無ければ live)",
   gc:find("local _live = globals.match_running == nil or globals.match_running() == true", 1, true) ~= nil, true)
eq("guardCancel のどこにも match_begun の判定が無い", gc:find("game_state.match_begun", 1, true), nil)

print("[3] master の match_running は片方だけ active でも true")
local ms = slurp("vsav_training_master_script.lua")
eq("どちらかの $1 が 1 で 0xFF8009 が 4",
   ms:find("and (memory.readbyte(0xFF8401) == 1 or memory.readbyte(0xFF8801) == 1)\n\t\tand memory.readbyte(0xFF8009) == 4", 1, true) ~= nil, true)
eq("globals.match_running に出している", ms:find("\tglobals.match_running = match_actually_running\n", 1, true) ~= nil, true)

print("[4] master のフレームの後 (記録をするところ) も同じ判定で続ける")
-- User, 2026-10-16: "レコーディングでブランチの後のコンボが入らない". The take is
-- recorded in macroLua's registerAfter, at the end of this hook; an early
-- return on match_begun alone dropped those frames from the take.
local ra = ms:find("emu.registerafter(function()", 1, true)
local guard = ra and ms:find("\tif globals.game_state.match_begun == false and not match_actually_running() then\n", ra, true)
local mac = ra and ms:find("\tmacroLuaModule.registerAfter()\n", ra, true)
eq("registerAfter の早い return は match_actually_running も見る", guard ~= nil, true)
eq("  記録 (macroLuaModule.registerAfter) はその後", guard ~= nil and mac ~= nil and guard < mac, true)
eq("  match_begun だけの return は残っていない",
   ms:find("\n\tif globals.game_state.match_begun == false then\n", ra or 1, true), nil)

print(fails == 0 and "\n全て通った" or ("\n" .. fails .. " 件 NG"))
os.exit(fails == 0 and 0 or 1)
