-- DARKNESS ILLUSION'S RECOGNIZER LOG (scripts/commandLog.lua, 2026-10-11).
--
--   [1] the ROM path the hooks rely on, read from the MAME disassembly
--   [2] the hooks: four addresses, nobody else on them
--   [3] what makes a row: steps, the complete command, expiry, misses, a
--       block cleared from outside, the meter test and the start - and
--       nothing while Knockdown Logger is off or for anything but a player
--   [4] the log: gathered in the hooks, written from the frame callback
--   [5] the hook-up: start-up require, registerStart / registerAfter, archive
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_command_log.lua
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

-- ---------------------------------------------------------------------------
print("[1] ROM の経路 (analysis/mame_code)")
local c28 = slurp("../analysis/mame_code/c28.txt")
local c38 = slurp("../analysis/mame_code/c38.txt")
local function has(src, addr, text)
	return (src:match("\n" .. addr .. ":[^\n]*") or ""):find(text, 1, true) ~= nil
end
eq("0397FE でブロック +$330 を A4 へ", has(c38, "0397FE", "lea     ($330,A6), A4"), true)
eq("039802 で DI の入口 0x029E7A を呼ぶ", has(c38, "039802", "jsr     $29e7a.l"), true)
eq("039808 は D0 が 1 なら 0x03997E へ", has(c38, "039808", "bne     $3997e"), true)
eq("03997E でゲージ ($109) を見る", has(c38, "03997E", "tst.b   ($109,A6)"), true)
eq("039994 で技 ID 8 を書く", has(c38, "039994", "move.b  #$8, ($106,A6)"), true)
eq("0399A2 は書いた後の rts", has(c38, "0399A2", "rts"), true)
eq("029E7A で表 0x02A6CE を A3 へ", has(c28, "029E7A", "lea     ($2a6ce,PC), A3"), true)
eq("029E7E で共通の認識器 0x02A0C8 へ", has(c28, "029E7E", "bra     $2a0c8"), true)
eq("02A0E4 で $1AC を読む", has(c28, "02A0E4", "move.w  ($1ac,A6), D0"), true)
eq("02A548 でタイマーを表 (PC 相対) から +4 へ", has(c28, "02A548", "move.b  ($10,PC,D0.w), ($4,A4)"), true)
eq("02A57A で +0 を消して D0 = 0", has(c28, "02A57A", "clr.b   (A4)") and has(c28, "02A57C", "moveq   #$0, D0"), true)
eq("02A580 で +0 を消して D0 = 1", has(c28, "02A580", "clr.b   (A4)") and has(c28, "02A582", "moveq   #$1, D0"), true)

-- ---------------------------------------------------------------------------
-- Stand-ins for FBNeo.
local ram, regs, hooks = {}, {}, {}
memory = {
	readbyte = function(a) return ram[a] or 0 end,
	readword = function(a) return ram[a] or 0 end,
	readdword = function(a) return ram[a] or 0 end,
	getregister = function(r) return regs[r] or 0 end,
	registerexec = function(a, f) hooks[a] = f end,
}
local fc = 0
emu = { framecount = function() return fc end }
globals = { options = { knockdown_logger_enable = false }, p1_tick_seq = 100 }
-- The log file is caught here, never written: a real log in reversal_logs
-- must not get test output mixed into it.
local written = nil
local in_hook, opened_in_hook = false, 0
local real_open = io.open
io.open = function(path, mode)
	if in_hook then opened_in_hook = opened_in_hook + 1 end
	if path == "reversal_logs/command_log.jsonl" then
		local buf = {}
		return { write = function(_, s) buf[#buf + 1] = s end,
		         close = function() written = (written or "") .. table.concat(buf) end }
	end
	return real_open(path, mode)
end
local M = dofile("commandLog.lua")

print("[2] フック")
M.registerStart()
local n = 0
for _ in pairs(hooks) do n = n + 1 end
eq("4 か所", n, 4)
eq("呼び出し 0x039802", hooks[0x039802] ~= nil, true)
eq("戻り 0x039808", hooks[0x039808] ~= nil, true)
eq("入力成立 0x03997E", hooks[0x03997E] ~= nil, true)
eq("技発動 0x0399A2", hooks[0x0399A2] ~= nil, true)
local others = {}
for _, name in ipairs({ "guardCancel.lua", "debugKnockdown.lua", "autoguard.lua", "airGuardLog.lua",
                        "cps2-hitboxes.lua", "gcStats.lua", "throwTech.lua", "position.lua", "idleSound.lua",
                        "vsav_training_master_script.lua", "framemeter.lua", "tickDataVsav.lua", "invulnLog.lua" }) do
	local fh = real_open(name)
	if fh then
		local s = fh:read("*a"):lower() ; fh:close()
		for _, a in ipairs({ "39802", "39808", "3997e", "399a2" }) do
			if s:find("0x0" .. a, 1, true) or s:find("0x" .. a, 1, true) then others[#others + 1] = name .. ":" .. a end
		end
	end
end
eq("ほかのスクリプトはこの 4 か所を使っていない", table.concat(others, ","), "")

-- ---------------------------------------------------------------------------
print("[3] 何が行になるか")
local P1, P2 = 0xFF8400, 0xFF8800
local function set_block(base, ph, st, tm)
	ram[base + 0x330], ram[base + 0x331], ram[base + 0x334] = ph, st, tm
end
-- One call of the recognizer: what the call sees, then what it leaves.
local function call(base, before, edge, after_, d0)
	regs["m68000.a6"] = base
	set_block(base, before[1], before[2], before[3])
	ram[base + 0x1AC] = edge
	in_hook = true
	hooks[0x039802]()
	set_block(base, after_[1], after_[2], after_[3])
	regs["m68000.d0"] = d0 or 0
	hooks[0x039808]()
	in_hook = false
end
local function fire(addr, base)
	regs["m68000.a6"] = base
	in_hook = true
	hooks[addr]()
	in_hook = false
end
local LP, FWD, LK, HP, MP = 0x0100, 0x0002, 0x1000, 0x0400, 0x0200

call(P1, { 0, 0, 0 }, LP, { 2, 2, 15 })
eq("Knockdown Logger が OFF なら行を作らない", #M._rows(), 0)
globals.options.knockdown_logger_enable = true
set_block(P1, 0, 0, 0)
call(P1, { 0, 0, 0 }, 0, { 0, 0, 0 })                -- idle call: nothing
ram[P1 + 0x109] = 1
call(P1, { 0, 0, 0 }, LP, { 2, 2, 15 })               -- step 1, timer 15
call(P1, { 2, 2, 15 }, 0, { 2, 2, 14 })               -- countdown only
call(P1, { 2, 2, 14 }, LP + MP, { 2, 2, 13 })         -- two edges at once: not LP
call(P1, { 2, 2, 13 }, LP, { 2, 4, 19 })              -- step 2, timer 19
call(P1, { 2, 4, 19 }, FWD, { 2, 6, 14 })             -- step 3
call(P1, { 2, 6, 14 }, LK, { 2, 8, 16 })              -- step 4
call(P1, { 2, 8, 16 }, HP, { 0, 8, 16 }, 1)           -- complete
fire(0x03997E, P1)
ram[P1 + 0x106] = 0x08
fire(0x0399A2, P1)
local r = M._rows()
local kinds = {}
for _, x in ipairs(r) do kinds[#kinds + 1] = x.kind .. x.step end
eq("順番", table.concat(kinds, " "), "step1 miss2 step2 step3 step4 complete5 met-1 started-1")
eq("1 歩目のタイマー (+4 の設定値)", r[1].tm2, 15)
eq("2 歩目のタイマー", r[3].tm2, 19)
eq("同時押しは miss で、待っていたのは 2 歩目", r[2].kind == "miss" and r[2].step == 2 and r[2].edge == LP + MP, true)
eq("calls: 1 歩目から miss まで 2 回 (数えるだけの 1 回を含む)", r[2].calls, 2)
eq("calls: miss から 2 歩目まで 1 回", r[3].calls, 1)
eq("完成は D0 = 1", r[6].d0, 1)
eq("発動の行に技 ID", r[8].move, 0x08)
eq("時計は p1_tick_seq", r[1].tick, 100)
eq("フックの中ではファイルを開かない", opened_in_hook, 0)

-- The timer runs out: four calls from a timer of 4.
local before = #M._rows()
call(P1, { 0, 0, 0 }, LP, { 2, 2, 4 })
call(P1, { 2, 2, 4 }, 0, { 2, 2, 3 })
call(P1, { 2, 2, 3 }, 0, { 2, 2, 2 })
call(P1, { 2, 2, 2 }, 0, { 2, 2, 1 })
call(P1, { 2, 2, 1 }, 0, { 0, 2, 0 })
r = M._rows()
eq("期限切れで 2 行 (1 歩目と expired)", #r - before, 2)
eq("expired は 2 歩目を待っていた", r[#r].kind == "expired" and r[#r].step == 2, true)
eq("expired までの calls はタイマーの値と同じ 4", r[#r].calls, 4)

-- Cleared from outside between two calls (a hit, another state).
before = #M._rows()
call(P1, { 0, 0, 0 }, LP, { 2, 2, 15 })
call(P1, { 0, 2, 15 }, 0, { 0, 2, 15 })
r = M._rows()
eq("外から消えたら cleared", r[#r].kind, "cleared")
eq("cleared は呼び出しの前の状態 (待っていたのは 2 歩目)", r[#r].step, 2)

-- P2, and anything that is not a player.
before = #M._rows()
call(P2, { 0, 0, 0 }, LP, { 2, 2, 17 })
r = M._rows()
eq("P2 も記録", r[#r].p, 2)
call(0xFF9400, { 0, 0, 0 }, LP, { 2, 2, 17 })
eq("プレイヤー以外は記録しない", #M._rows(), before + 1)

-- ---------------------------------------------------------------------------
print("[4] ログ")
fc = 100
M.registerAfter()
eq("フレーム側で書く", written ~= nil, true)
local first = written and written:match("^[^\n]*") or ""
eq("1 行目は見出し", first:find('"log": "command_log", "version": 1', 1, true) ~= nil, true)
eq("行に kind と tm2", written ~= nil and written:find('"kind": "step", "step": 1', 1, true) ~= nil
	and written:find('"tm2": 15', 1, true) ~= nil, true)
eq("書いた後は空", #M._rows(), 0)
local len = #written
fc = 110
call(P1, { 0, 0, 0 }, LP, { 2, 2, 15 })
M.registerAfter()
eq("1 秒たつまでは書かない", #written, len)
fc = 170
M.registerAfter()
eq("1 秒たてば追記する", #written > len, true)
local w2 = written
M.registerAfter()
eq("新しい行が無ければ書かない", written, w2)

-- ---------------------------------------------------------------------------
print("[5] つなぎ込み")
local master = slurp("vsav_training_master_script.lua")
eq("起動時に require", master:find('= require "./scripts/commandLog"', 1, true) ~= nil, true)
eq("registerStart を呼ぶ", master:find("commandLogModule.registerStart()", 1, true) ~= nil, true)
eq("registerAfter を呼ぶ", master:find("commandLogModule.registerAfter()", 1, true) ~= nil, true)
local archive = slurp("../analysis/archive_logs.py")
eq("archive_logs.py が command_log.jsonl を退避する", archive:find('"command_log.jsonl"', 1, true) ~= nil, true)

io.open = real_open
print(fails == 0 and "\n全て通った" or ("\n" .. fails .. " 件 NG"))
os.exit(fails == 0 and 0 or 1)
