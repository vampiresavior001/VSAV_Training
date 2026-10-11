-- THE SEQUENCE RECOGNIZER'S ROWS (scripts/commandLog.lua, 2026-10-11).
--
--   [1] the ROM path the hooks rely on, read from the MAME disassembly, for
--       each of the ten commands, and their steps against the evidence file
--   [2] the hooks: three per command, nobody else on them
--   [3] what makes a row: steps, the complete command, expiry, misses, a
--       block cleared from outside, the start - and nothing while nobody
--       listens, or for anything but a player
--   [4] the listener (commandTrainer.lua) gets the rows without the file
--   [5] the log: gathered in the hooks, written from the frame callback
--   [6] the hook-up: start-up require, registerStart / registerAfter, archive
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
local code = {
	c28 = slurp("../analysis/mame_code/c28.txt"),
	c38 = slurp("../analysis/mame_code/c38.txt"),
	c04 = slurp("../analysis/mame_code/c040000.txt"),
}
local function has(src, addr, text)
	return (code[src]:match("\n" .. addr .. ":[^\n]*") or ""):find(text, 1, true) ~= nil
end
-- The shared recognizer.
eq("029E7A で表 0x02A6CE を A3 へ (DI / LI)", has("c28", "029E7A", "lea     ($2a6ce,PC), A3"), true)
eq("029E6A で表 0x02A6BA を A3 へ (MP)", has("c28", "029E6A", "lea     ($2a6ba,PC), A3"), true)
eq("どちらも 0x02A0C8 へ", has("c28", "029E7E", "bra     $2a0c8") and has("c28", "029E6E", "bra     $2a0c8"), true)
eq("02A0E4 で $1AC を読む", has("c28", "02A0E4", "move.w  ($1ac,A6), D0"), true)
eq("02A548 でタイマーを表 (PC 相対) から +4 へ", has("c28", "02A548", "move.b  ($10,PC,D0.w), ($4,A4)"), true)
eq("02A57A で +0 を消して D0 = 0", has("c28", "02A57A", "clr.b   (A4)") and has("c28", "02A57C", "moveq   #$0, D0"), true)
eq("02A580 で +0 を消して D0 = 1", has("c28", "02A580", "clr.b   (A4)") and has("c28", "02A582", "moveq   #$1, D0"), true)
-- Per command: the block into A4, the JSR, the BNE after it, the move id and
-- the RTS after it, and the wrapper's table. src: the listing the call is in;
-- src_end: the one the start path is in, when different.
local ROM = {
	di = { src = "c38", lea = "0397FE", jsr = "039802", wrapper = "029E7A", tbl = "2a6ce", bne = "$3997e", id = "039994", rts = "0399A2" },
	fs = { src = "c38", lea = "0397F0", jsr = "0397F4", wrapper = "029E82", tbl = "2a6d8", bne = "$398b8", id = "0398E6", rts = "0398EC" },
	cn = { src = "c38", lea = "0397D4", jsr = "0397D8", wrapper = "029E8A", tbl = "2a6e2", bne = "$399a4", id = "0399C2", rts = "0399D0" },
	li = { src = "c04", lea = "04DCF6", jsr = "04DCFA", wrapper = "029E7A", tbl = "2a6ce", bne = "$4dd80", id = "04DD96", rts = "04DDA4" },
	mp = { src = "c28", src_end = "c30", lea = "02FF98", jsr = "02FF9C", wrapper = "029E6A", tbl = "2a6ba", bne = "$30106", id = "03012E", rts = "030134" },
	ms = { src = "c30", lea = "031D32", jsr = "031D36", wrapper = "029E72", tbl = "2a6c4", bne = "$31e94", id = "031EB6", rts = "031EC0" },
	pm = { src = "c38", lea = "03B886", jsr = "03B88A", wrapper = "029E92", tbl = "2a6ec", bne = "$3ba60", id = "03BA8E", rts = "03BA98" },
	ps = { src = "c38", lea = "03B86A", jsr = "03B86E", wrapper = "029E9A", tbl = "2a6f6", bne = "$3ba9a", id = "03BACA", rts = "03BAD4" },
	pd = { src = "c38", lea = "03B878", jsr = "03B87C", wrapper = "029EA2", tbl = "2a70a", bne = "$3bad6", id = "03BB06", rts = "03BB10" },
	tr = { src = "c04", lea = "04B360", jsr = "04B364", wrapper = "029EB2", tbl = "2a718", bne = "$4b4ac", id = "04B4E0", rts = "04B4EA" },
}
code.c30 = slurp("../analysis/mame_code/c30.txt")

package.loaded["./scripts/commandLog"] = nil
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
local P = {}
for _, prof in ipairs(M.PROFILES) do P[prof.key] = prof end

eq("技は 10 個、ROM の表も 10 個", #M.PROFILES == 10 and (function() local n = 0 for _ in pairs(ROM) do n = n + 1 end return n end)(), 10)
-- The steps against the evidence JSON (the table words, & $770F).
local ev = slurp("../analysis/sequence_command_evidence.json")
local function table_words(tbl)
	local a = ev:find('"table": "0x' .. tbl:upper():gsub("^2A", "02A") .. '"', 1, true)
	local b = ev:find('"direct_references"', a or 1, true)
	local out = {}
	for w in ev:sub(a or 1, b or 1):gmatch('"edge_equals": "0x(%x+)"') do out[#out + 1] = tonumber(w, 16) end
	return out
end
local function same(t1, t2)
	if #t1 ~= #t2 then return false end
	for i = 1, #t1 do if t1[i] ~= t2[i] then return false end end
	return true
end
for _, prof in ipairs(M.PROFILES) do
	local key, r = prof.key, ROM[prof.key]
	local endsrc = r.src_end or r.src
	eq(key .. ": " .. r.lea .. " でブロック +$" .. string.format("%x", prof.block) .. " を A4 へ",
		has(r.src, r.lea, string.format("lea     ($%x,A6), A4", prof.block)), true)
	eq(key .. ": " .. r.jsr .. " で入口 " .. r.wrapper .. " を呼ぶ",
		has(r.src, r.jsr, "jsr     $" .. r.wrapper:lower():gsub("^0", "") .. ".l"), true)
	eq(key .. ": 入口は表 0x" .. r.tbl:upper() .. " を A3 に入れて 0x02A0C8 へ",
		has("c28", r.wrapper, "lea     ($" .. r.tbl .. ",PC), A3")
		and has("c28", string.format("%06X", tonumber(r.wrapper, 16) + 4), "bra     $2a0c8"), true)
	eq(key .. ": 呼び出しの番地", string.format("%06X", prof.call), r.jsr)
	eq(key .. ": 戻り (JSR の次、bne)", has(r.src, string.format("%06X", prof.ret), "bne     " .. r.bne), true)
	eq(key .. ": 技 ID " .. string.format("%x", prof.move) .. " を書く",
		has(endsrc, r.id, string.format("move.b  #$%x, ($106,A6)", prof.move)), true)
	eq(key .. ": その後の rts が発動の番地", has(endsrc, string.format("%06X", prof.start), "rts")
		and string.format("%06X", prof.start) == r.rts, true)
	eq(key .. ": 歩は表 0x" .. r.tbl:upper() .. " と同じ", same(prof.steps, table_words(r.tbl)), true)
end

-- ---------------------------------------------------------------------------
print("[2] フック")
M.registerStart()
local n = 0
for _ in pairs(hooks) do n = n + 1 end
eq("10 技 x 3 か所", n, 30)
for _, prof in ipairs(M.PROFILES) do
	eq(prof.key .. ": 呼び出し・戻り・発動", hooks[prof.call] ~= nil and hooks[prof.ret] ~= nil and hooks[prof.start] ~= nil, true)
end
local others = {}
for _, name in ipairs({ "guardCancel.lua", "debugKnockdown.lua", "autoguard.lua", "airGuardLog.lua",
                        "cps2-hitboxes.lua", "gcStats.lua", "throwTech.lua", "position.lua", "idleSound.lua",
                        "vsav_training_master_script.lua", "framemeter.lua", "tickDataVsav.lua", "invulnLog.lua",
                        "commandTrainer.lua" }) do
	local fh = real_open(name)
	if fh then
		local s = fh:read("*a"):lower() ; fh:close()
		for a in pairs(hooks) do
			local h = string.format("%x", a)
			if s:find("0x0" .. h, 1, true) or s:find("0x" .. h, 1, true) then others[#others + 1] = name .. ":" .. h end
		end
	end
end
eq("ほかのスクリプトはこの 30 か所を使っていない", table.concat(others, ","), "")

-- ---------------------------------------------------------------------------
print("[3] 何が行になるか (DI)")
local P1, P2 = 0xFF8400, 0xFF8800
local DI = P.di
local function set_block(prof, base, ph, st, tm)
	local b = base + prof.block
	ram[b], ram[b + 1], ram[b + 4] = ph, st, tm
end
-- One call of the recognizer: what the call sees, then what it leaves.
local function call(prof, base, before, edge, after_, d0)
	regs["m68000.a6"] = base
	set_block(prof, base, before[1], before[2], before[3])
	ram[base + 0x1AC] = edge
	in_hook = true
	hooks[prof.call]()
	set_block(prof, base, after_[1], after_[2], after_[3])
	regs["m68000.d0"] = d0 or 0
	hooks[prof.ret]()
	in_hook = false
end
local function started(prof, base)
	regs["m68000.a6"] = base
	in_hook = true
	hooks[prof.start]()
	in_hook = false
end
local LP, FWD, LK, HP, MP = 0x0100, 0x0002, 0x1000, 0x0400, 0x0200

call(DI, P1, { 0, 0, 0 }, LP, { 2, 2, 15 })
eq("誰も聞いていなければ行を作らない", #M._rows(), 0)
globals.options.knockdown_logger_enable = true
set_block(DI, P1, 0, 0, 0)
call(DI, P1, { 0, 0, 0 }, 0, { 0, 0, 0 })                -- idle call: nothing
call(DI, P1, { 0, 0, 0 }, LP, { 2, 2, 15 })               -- step 1, timer 15
call(DI, P1, { 2, 2, 15 }, 0, { 2, 2, 14 })               -- countdown only
call(DI, P1, { 2, 2, 14 }, LP + MP, { 2, 2, 13 })         -- two edges at once: not LP
call(DI, P1, { 2, 2, 13 }, LP, { 2, 4, 19 })              -- step 2, timer 19
call(DI, P1, { 2, 4, 19 }, FWD, { 2, 6, 14 })             -- step 3
call(DI, P1, { 2, 6, 14 }, LK, { 2, 8, 16 })              -- step 4
call(DI, P1, { 2, 8, 16 }, HP, { 0, 8, 16 }, 1)           -- complete
ram[P1 + 0x106] = 0x08
started(DI, P1)
local r = M._rows()
local kinds = {}
for _, x in ipairs(r) do kinds[#kinds + 1] = x.kind .. x.step end
eq("順番", table.concat(kinds, " "), "step1 miss2 step2 step3 step4 complete5 started-1")
eq("1 歩目のタイマー (+4 の設定値)", r[1].tm2, 15)
eq("2 歩目のタイマー", r[3].tm2, 19)
eq("同時押しは miss で、待っていたのは 2 歩目", r[2].kind == "miss" and r[2].step == 2 and r[2].edge == LP + MP, true)
eq("calls: 1 歩目から miss まで 2 回 (数えるだけの 1 回を含む)", r[2].calls, 2)
eq("calls: miss から 2 歩目まで 1 回", r[3].calls, 1)
eq("完成は D0 = 1", r[6].d0, 1)
eq("発動の行に技 ID", r[7].move, 0x08)
eq("行に技の名前 (cmd)", r[1].cmd, "di")
eq("時計は p1_tick_seq", r[1].tick, 100)
eq("フックの中ではファイルを開かない", opened_in_hook, 0)

-- The timer runs out: four calls from a timer of 4.
local before = #M._rows()
call(DI, P1, { 0, 0, 0 }, LP, { 2, 2, 4 })
call(DI, P1, { 2, 2, 4 }, 0, { 2, 2, 3 })
call(DI, P1, { 2, 2, 3 }, 0, { 2, 2, 2 })
call(DI, P1, { 2, 2, 2 }, 0, { 2, 2, 1 })
call(DI, P1, { 2, 2, 1 }, 0, { 0, 2, 0 })
r = M._rows()
eq("期限切れで 2 行 (1 歩目と expired)", #r - before, 2)
eq("expired は 2 歩目を待っていた", r[#r].kind == "expired" and r[#r].step == 2, true)
eq("expired までの calls はタイマーの値と同じ 4", r[#r].calls, 4)

-- Cleared from outside between two calls (a hit, another state).
call(DI, P1, { 0, 0, 0 }, LP, { 2, 2, 15 })
call(DI, P1, { 0, 2, 15 }, 0, { 0, 2, 15 })
r = M._rows()
eq("外から消えたら cleared", r[#r].kind, "cleared")
eq("cleared は呼び出しの前の状態 (待っていたのは 2 歩目)", r[#r].step, 2)

-- P2, and anything that is not a player.
before = #M._rows()
call(DI, P2, { 0, 0, 0 }, LP, { 2, 2, 17 })
r = M._rows()
eq("P2 も記録", r[#r].p, 2)
call(DI, 0xFF9400, { 0, 0, 0 }, LP, { 2, 2, 17 })
eq("プレイヤー以外は記録しない", #M._rows(), before + 1)

-- Midnight Pleasure's own block and step count.
before = #M._rows()
call(P.mp, P1, { 0, 0, 0 }, LP, { 2, 2, 16 })
call(P.mp, P1, { 2, 8, 16 }, 0x2000, { 0, 8, 16 }, 1)
r = M._rows()
eq("MP は +$330 で、行の cmd は mp", r[before + 1].cmd == "mp" and r[before + 1].tm2 == 16, true)
eq("MP の完成も 5 歩目", r[before + 2].kind == "complete" and r[before + 2].step == 5, true)

-- ---------------------------------------------------------------------------
print("[4] 聞き手 (commandTrainer.lua)")
local heard = {}
local on = false
M.set_listener(function(row) heard[#heard + 1] = row end, function() return on end)
globals.options.knockdown_logger_enable = false
local logged = #M._rows()
call(DI, P1, { 0, 0, 0 }, LP, { 2, 2, 15 })
eq("聞き手が OFF なら何も作らない", #heard, 0)
on = true
call(DI, P1, { 0, 0, 0 }, LP, { 2, 2, 15 })
eq("聞き手が ON なら行が届く", #heard == 1 and heard[1].kind == "step", true)
eq("Knockdown Logger が OFF ならファイル用には積まない", #M._rows(), logged)
on = false
globals.options.knockdown_logger_enable = true

-- ---------------------------------------------------------------------------
print("[5] ログ")
fc = 100
M.registerAfter()
eq("フレーム側で書く", written ~= nil, true)
local first = written and written:match("^[^\n]*") or ""
eq("1 行目は見出し (version 2)", first:find('"log": "command_log", "version": 2', 1, true) ~= nil, true)
eq("行に cmd、kind と tm2", written ~= nil and written:find('"cmd": "di", "kind": "step", "step": 1', 1, true) ~= nil
	and written:find('"tm2": 15', 1, true) ~= nil, true)
eq("書いた後は空", #M._rows(), 0)
local len = #written
fc = 110
call(DI, P1, { 0, 0, 0 }, LP, { 2, 2, 15 })
M.registerAfter()
eq("1 秒たつまでは書かない", #written, len)
fc = 170
M.registerAfter()
eq("1 秒たてば追記する", #written > len, true)
local w2 = written
M.registerAfter()
eq("新しい行が無ければ書かない", written, w2)

-- ---------------------------------------------------------------------------
print("[6] つなぎ込み")
local master = slurp("vsav_training_master_script.lua")
eq("起動時に require", master:find('= require "./scripts/commandLog"', 1, true) ~= nil, true)
eq("registerStart を呼ぶ", master:find("commandLogModule.registerStart()", 1, true) ~= nil, true)
eq("registerAfter を呼ぶ", master:find("commandLogModule.registerAfter()", 1, true) ~= nil, true)
local archive = slurp("../analysis/archive_logs.py")
eq("archive_logs.py が command_log.jsonl を退避する", archive:find('"command_log.jsonl"', 1, true) ~= nil, true)

io.open = real_open
print(fails == 0 and "\n全て通った" or ("\n" .. fails .. " 件 NG"))
os.exit(fails == 0 and 0 or 1)
