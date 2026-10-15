-- THE CHAIN AND RAPID CANCEL CHECK'S ROWS (scripts/chainLog.lua, 2026-10-14).
--
--   [1] the ROM path the hooks rely on, read from the MAME disassembly
--   [2] the hooks: nobody else on them
--   [3] what makes a row: the contact, the timer, a held press, a call of the
--       check that saw a button or accepted - and nothing for the quiet calls,
--       for anything but a player, or while Knockdown Logger is off
--   [4] the log: gathered in the hooks, written from the frame callback
--   [5] the hook-up: start-up require, registerStart / registerAfter, archive
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_chain_log.lua
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

-- ---------------------------------------------------------------------------
-- The fake machine: RAM, the registers the hooks read, and the hooks by PC.
local ram, regs, hooks = {}, {}, {}
memory = {
	readbyte = function(a) return ram[a] or 0 end,
	readword = function(a) return (ram[a] or 0) * 256 + (ram[a + 1] or 0) end,
	readdword = function(a)
		return (((ram[a] or 0) * 256 + (ram[a + 1] or 0)) * 256 + (ram[a + 2] or 0)) * 256 + (ram[a + 3] or 0)
	end,
	getregister = function(name) return regs[name:gsub("^m68000%.", "")] or 0 end,
	registerexec = function(pc, fn) hooks[pc] = fn end,
}
local frame = 0
emu = { framecount = function() return frame end }
globals = { options = { knockdown_logger_enable = true } }
local function word(a, v) ram[a] = math.floor(v / 256) % 256 ; ram[a + 1] = v % 256 end

local C = dofile("chainLog.lua")
C.registerStart()

-- ---------------------------------------------------------------------------
print("[1] ROM の経路 (analysis/mame_code)")
local code = {
	c18 = slurp("../analysis/mame_code/c18.txt"),
	c20 = slurp("../analysis/mame_code/c20.txt"),
	c28 = slurp("../analysis/mame_code/c28.txt"),
}
local function has(src, addr, text)
	return (code[src]:match("\n" .. addr .. ":[^\n]*") or ""):find(text, 1, true) ~= nil
end
local ROM = {
	{ "c18", "018262", "move.b  #$e, ($169,A6)", "contact" },
	{ "c20", "022500", "tst.b   ($169,A6)" },
	{ "c20", "022506", "subq.b  #1, ($169,A6)" },
	{ "c20", "02250A", "tst.b   ($171,A6)", "tick" },
	{ "c20", "02255C", "bsr     $27e76" },
	{ "c20", "027E76", "tst.b   ($169,A6)" },
	{ "c20", "027E7C", "move.w  ($126,A6), D0", "hold" },
	{ "c20", "027E80", "or.w    D0, ($12e,A6)" },
	-- The sig row's value: the mark one tick before a character can act.
	{ "c20", "024F0A", "move.l  #$2020400, ($4,A6)" },
	{ "c28", "028E42", "move.b  ($10e,A5), D0", "entry" },
	{ "c28", "028E52", "bne     $28f34" },
	{ "c28", "028E56", "tst.b   ($3b4,A6)", "inhibit_ok" },
	{ "c28", "028E5A", "bne     $29000" },
	{ "c28", "028E5E", "bsr     $28fb0", "rapid_check" },
	{ "c28", "028E62", "bne     $28ed4" },
	{ "c28", "028E66", "tst.b   ($39,A6)", "rapid_no" },
	{ "c28", "028E6E", "tst.b   ($1b2,A6)", "contact_ok" },
	{ "c28", "028E76", "move.w  ($12e,A6), D0", "c1b2_ok" },
	{ "c28", "028E80", "or.w    ($126,A6), D0" },
	{ "c28", "028E84", "andi.w  #$7700, D0" },
	{ "c28", "028E8C", "bsr     $28f78", "buttons" },
	{ "c28", "028E94", "bsr     $28f36", "one_button" },
	{ "c28", "028E98", "and.w   D1, D0", "mask" },
	{ "c28", "028E9E", "moveq   #$0, D2", "allowed" },
	{ "c28", "028ED0", "st      ($119,A6)", "chain_accept" },
	{ "c28", "028ED4", "move.b  D2, ($102,A6)" },
	{ "c28", "028EDC", "jsr     $d73a.l", "commit" },
	{ "c28", "028F34", "rts", "done" },
	{ "c28", "028FAA", "cmpi.w  #$1, D1" },
	{ "c28", "028FF0", "st      ($11a,A6)", "rapid_accept" },
	{ "c28", "029000", "tst.b   ($39,A6)", "special" },
}
for _, r in ipairs(ROM) do
	eq(r[2] .. " " .. r[3], has(r[1], r[2], r[3]), true)
	if r[4] ~= nil then
		eq("  M.PC." .. r[4] .. " が " .. r[2], C.PC[r[4]], tonumber(r[2], 16))
	end
end
local named = 0
for _ in pairs(C.PC) do named = named + 1 end
eq("M.PC は全部照合した", named, 18)

-- ---------------------------------------------------------------------------
print("[2] フック: 18 か所、他のスクリプトとは重ならない")
local n = 0
for pc, _ in pairs(C.PC) do if hooks[C.PC[pc]] ~= nil then n = n + 1 end end
eq("全部に登録", n, 18)
local others = {}
for _, f in ipairs({ "guardCancel.lua", "debugKnockdown.lua", "timers.lua", "dummyState.lua",
                     "tickDataVsav.lua", "idleSound.lua", "frameskip-service.lua",
                     "stage-select.lua", "commandLog.lua", "cps2-hitboxes.lua" }) do
	local s = slurp(f)
	for hx in s:gmatch("registerexec%((0x%x+)") do others[tonumber(hx)] = f end
end
-- The ones that are not literals at the call.
others[0x018230] = "tickDataVsav.lua (STRIKE_PC)"
for a = 0x26D00, 0x26D90, 2 do others[a] = "debugKnockdown.lua (sweep)" end
for _, prof in ipairs(dofile("commandLog.lua").PROFILES) do
	others[prof.call] = "commandLog.lua"; others[prof.ret] = "commandLog.lua"; others[prof.start] = "commandLog.lua"
end
local tdv = slurp("tickDataVsav.lua"):match("GRAB_ATTEMPTS%s*=%s*(%b{})")
for hx in (tdv or ""):gmatch("0x%x+") do others[tonumber(hx)] = "tickDataVsav.lua (GRAB_ATTEMPTS)" end
local clash = nil
for k, pc in pairs(C.PC) do if others[pc] ~= nil then clash = k .. " / " .. others[pc] end end
eq("重なりなし", clash, nil)

-- ---------------------------------------------------------------------------
print("[3] 行になるもの")
local P1, P2 = 0xFF8400, 0xFF8800
regs.a5 = 0xFF8000
local function rows() return C._rows() end
local function last() local r = rows() ; return r[#r] end
local function run(pc) hooks[pc]() end
local function count() return #rows() end

-- The contact: P1's body hit P2.
regs.a6, regs.a1 = P1, P2
ram[P1 + 0x169] = 0
run(C.PC.contact)
eq("接触で 1 行", count(), 1)
eq("  contact", last().kind, "contact")
eq("  攻撃側 P1", last().p, 1)
eq("  当てた相手 P2", last().opp, 2)
eq("  時計はゲームの Tick (0xFF8081)", last().tick, 0)
ram[0xFF8081] = 250 ; run(C.PC.contact)
ram[0xFF8081] = 4 ; run(C.PC.contact)
eq("  0xFF8081 が 1 周しても続けて数える (250 -> 4 は +10)", last().tick - rows()[#rows() - 1].tick, 10)
ram[0xFF8081] = 3 ; run(C.PC.contact)
eq("  1 つ戻ったら (同じ Tick のやり直し) 1 つ戻る", last().tick - rows()[#rows() - 1].tick, -1)
-- A pause with no rows: 200 Ticks, 2 a frame, registerAfter every frame (it
-- must not write here - frame stays 0, and the log is not opened).
do
	local real_open = io.open
	io.open = function(path, mode)
		assert(not path:find("chain_log", 1, true), "テストが実機のログを開いた")
		return real_open(path, mode)
	end
	for _ = 1, 100 do ram[0xFF8081] = (ram[0xFF8081] + 2) % 256 ; C.registerAfter() end
	io.open = real_open
end
run(C.PC.contact)
eq("  行の無い 200 Tick の後も続けて数える (毎フレーム時計を見る)", last().tick - rows()[#rows() - 1].tick, 200)
table.remove(C._rows())
ram[0xFF8081] = 0
table.remove(C._rows()) ; table.remove(C._rows()) ; table.remove(C._rows())
ram[P2 + 0x05], ram[P2 + 0x140] = 2, 0x02
run(C.PC.contact)
eq("  当たる前の相手の $05 (0182D8 が書き換える前)", last().opp05, 2)
eq("  当たる前の相手の $140 (0x02 = ガード)", last().opp140, 0x02)
ram[P2 + 0x05], ram[P2 + 0x140] = 0, 0
table.remove(C._rows())

-- The timer, after it counted down.
ram[P1 + 0x169] = 13
run(C.PC.tick)
eq("タイマーが 0 でない更新は 1 行", count(), 2)
eq("  t169 = 13", last().t169, 13)
ram[P1 + 0x169] = 0
run(C.PC.tick)
eq("何もない更新は行にならない", count(), 2)
word(P1 + 0x126, 0x0200)       -- MP pressed this update
ram[P1 + 0x123] = 0x04         -- with the lever down
run(C.PC.tick)
eq("ボタンの押しは行になる", count(), 3)
eq("  レバー ($123、0x04 = 下) も持つ", last().lever, 0x04)
ram[P1 + 0x123] = 0
word(P1 + 0x126, 0x0002)       -- a direction only
run(C.PC.tick)
eq("方向だけは行にならない", count(), 3)
word(P1 + 0x126, 0)
ram[P1 + 0x06] = 0x0A          -- a normal starts
run(C.PC.tick)
eq("通常技に入った更新は行になる", count(), 4)
run(C.PC.tick)
eq("  続いている間は行にならない", count(), 4)
ram[P1 + 0x06] = 0x00          -- and ends
run(C.PC.tick)
eq("通常技を抜けた更新も行になる (目押しの 1t)", count(), 5)
run(C.PC.tick)
eq("  そのあとは行にならない", count(), 5)
table.remove(C._rows()) ; table.remove(C._rows())

-- The other side's recovery: the impact freeze ending, and the reversal tick.
local function state(base, v)
	ram[base + 4] = math.floor(v / 0x1000000) % 0x100 ; ram[base + 5] = math.floor(v / 0x10000) % 0x100
	ram[base + 6] = math.floor(v / 0x100) % 0x100 ; ram[base + 7] = v % 0x100
end
regs.a6 = P2
state(P2, 0x02020000)                 -- in stun, impact freeze
run(C.PC.tick)
local n0 = count()
local function kinds_since(n)
	local out = {}
	for i = n + 1, count() do out[#out + 1] = rows()[i].kind end
	return table.concat(out, ",")
end
local function find(kind)
	for i = count(), 1, -1 do if rows()[i].kind == kind then return rows()[i] end end
end
ram[P2 + 0x59] = 1
state(P2, 0x02020202)                 -- the hurt reaction runs
run(C.PC.tick)
-- $06 changed as well, so the update is a tick row too.
eq("停止が明けた更新は react (と $06 が変わった tick)", kinds_since(n0), "react,tick")
eq("  P2 の行", find("react").p, 2)
eq("  $59 を持つ", find("react").s59, 1)
local n1 = count()
run(C.PC.tick)
eq("  続いている間は行にならない", count(), n1)
state(P2, 0x02020400)                 -- the mark one tick before it can act
run(C.PC.tick)
eq("復帰 1 Tick 前の印は sig (と tick)", kinds_since(n1), "sig,tick")
local n2 = count()
run(C.PC.tick)
eq("  1 回だけ", count(), n2)
state(P2, 0x02000000)
run(C.PC.tick)
eq("  動けるようになっても sig は増えない ($06 の変化の tick だけ)", kinds_since(n2), "tick")
local n3 = count()
state(P2, 0x02020000)                 -- hit again: the freeze begins from free
run(C.PC.tick)
eq("当たって停止が始まった更新は hit (飛び道具でも本体でも)", kinds_since(n3):sub(1, 3), "hit")
eq("  当たる直前は動ける状態 (prev05 0)", find("hit").prev05, 0)
-- Everything this block added goes, so the counts below are the same.
while count() > n0 do table.remove(C._rows()) end
ram[P2 + 0x59] = 0
regs.a6 = P1

-- A press held in hit stop.
word(P1 + 0x126, 0x0400)
run(C.PC.hold)
eq("ヒットストップ中の押しは hold", last().kind, "hold")
word(P1 + 0x126, 0)
run(C.PC.hold)
eq("押していなければ hold は無い", last().kind, "hold")
eq("  増えない", count(), 4)

-- A chain accepted: LP into MP.
local function call(stages, d)
	run(C.PC.entry)
	for _, s in ipairs(stages) do
		if d and d[s] then for k, v in pairs(d[s]) do regs[k] = v end end
		run(C.PC[s])
	end
	run(C.PC.done)
end
word(P1 + 0x126, 0x0200)
ram[P1 + 0x39] = 1
call({ "inhibit_ok", "rapid_check", "rapid_no", "contact_ok", "c1b2_ok", "buttons",
       "one_button", "mask", "allowed", "chain_accept", "commit" },
     { buttons = { d0 = 0x0200 }, mask = { d0 = 0x0200, d1 = 0x0600 },
       chain_accept = { d0 = 0x0200, d2 = 2, d3 = 0 } })
eq("チェーン成立で check 1 行", last().kind, "check")
eq("  accept = chain", last().accept, "chain")
eq("  経路は normal", last().path, "normal")
eq("  一番先は commit", last().stage, C.STAGE.commit)
eq("  次の強さ (D2)", last().d2, 2)
eq("  終わりは rts", last().ends, "rts")
eq("  calls = 1", last().calls, 1)

-- Two quiet calls, then a press the contact flag stopped.
local before = count()
word(P1 + 0x126, 0)
ram[P1 + 0x39] = 0
call({ "inhibit_ok", "rapid_check", "rapid_no" })
call({ "inhibit_ok", "rapid_check", "rapid_no" })
eq("ボタンを見ていない呼び出しは行にならない", count(), before)
word(P1 + 0x126, 0x0400)
call({ "inhibit_ok", "rapid_check", "rapid_no" })
eq("押していたが $39 で止まった: 1 行", count(), before + 1)
eq("  一番先は rapid_no", last().stage, C.STAGE.rapid_no)
eq("  成立なし", last().accept, nil)
eq("  calls は静かな 2 回を含む", last().calls, 3)

-- Held, but the inhibit stopped it - still a row, at the entry.
word(P1 + 0x126, 0)
word(P1 + 0x12E, 0x0100)
call({})
eq("保持だけでも行になる (entry で止まった)", last().stage, C.STAGE.entry)
word(P1 + 0x12E, 0)

-- Rapid.
word(P1 + 0x126, 0x0100)
call({ "inhibit_ok", "rapid_check", "rapid_accept", "commit" }, { rapid_accept = { d0 = 0x0100, d1 = 8 } })
eq("連打キャンセル成立", last().accept, "rapid")
eq("  D1 はビット番号", last().d1, 8)

-- Entered at 028E6E without 028E42.
word(P1 + 0x126, 0x0200)
run(C.PC.contact_ok) ; run(C.PC.c1b2_ok) ; run(C.PC.done)
eq("028E42 を通らない呼び出しは direct", last().path, "direct")

-- $3B4: the other path, left open, closed by the next call.
before = count()
run(C.PC.entry) ; run(C.PC.inhibit_ok) ; run(C.PC.special)
run(C.PC.entry) ; run(C.PC.done)
eq("開いたままの呼び出しは次の入口で閉じる", count(), before + 2)
eq("  その行は special / open", rows()[before + 1].path .. " / " .. rows()[before + 1].ends, "special / open")

-- P2's own calls are its own.
regs.a6 = P2
word(P2 + 0x126, 0x1000)
call({ "inhibit_ok" })
eq("P2 は P2 の行", last().p, 2)

-- Not a player.
before = count()
regs.a6 = 0xFF9000
run(C.PC.contact) ; run(C.PC.tick) ; run(C.PC.hold) ; call({ "inhibit_ok" })
eq("プレイヤー以外は行にならない", count(), before)

-- Knockdown Logger off.
regs.a6 = P1
globals.options.knockdown_logger_enable = false
ram[P1 + 0x169] = 5
run(C.PC.contact) ; run(C.PC.tick) ; run(C.PC.hold) ; call({ "inhibit_ok", "buttons" })
eq("Knockdown Logger OFF では何も積まない", count(), before)
globals.options.knockdown_logger_enable = true

-- ---------------------------------------------------------------------------
print("[4] ファイル: フックで積み、フレームの後で書く")
local written = {}
local real_open = io.open
io.open = function(path, mode)
	if path:find("chain_log", 1, true) then
		return { write = function(_, s) written[#written + 1] = s end, close = function() end }
	end
	return real_open(path, mode)
end
local rowcount = count()
frame = 100
C.registerAfter()
eq("書いたあと積んだ行は空", count(), 0)
local text = table.concat(written)
eq("1 行目はヘッダ", text:sub(1, 20), '{"log": "chain_log",')
local lines = 0
for line in text:gmatch("[^\n]+") do
	lines = lines + 1
	if line:find("nil", 1, true) then eq("nil を書かない: " .. line, false, true) end
	local o = select(2, line:gsub("{", "")) ; local c = select(2, line:gsub("}", ""))
	if o ~= c then eq("括弧の対: " .. line, false, true) end
end
eq("ヘッダ + 積んだ行", lines, 1 + rowcount)
eq("check 行に段階の名前", text:find('"stage": "commit"', 1, true) ~= nil, true)
eq("行にレバーを書く (0x04)", text:find('"lever": "0x04"', 1, true) ~= nil, true)
eq("check 行に成立の種類", text:find('"accept": "rapid"', 1, true) ~= nil, true)
written = {}
regs.a6 = P1
word(P1 + 0x126, 0x0200)
run(C.PC.tick)
frame = 120
C.registerAfter()
eq("60 フレーム以内には書かない", #written, 0)
frame = 170
C.registerAfter()
eq("過ぎたら追記 (ヘッダは 1 回だけ)", table.concat(written):find('"log"', 1, true), nil)
io.open = real_open

-- ---------------------------------------------------------------------------
print("[5] 組み込み")
local ms = slurp("vsav_training_master_script.lua")
eq("起動時に require", ms:find('\nlocal chainLogModule     = require "./scripts/chainLog"', 1, true) ~= nil, true)
eq("registerStart", ms:find("\tchainLogModule.registerStart()\n", 1, true) ~= nil, true)
eq("registerAfter", ms:find("\tchainLogModule.registerAfter()\n", 1, true) ~= nil, true)
eq("archive_logs.py が退避する", slurp("../analysis/archive_logs.py"):find('"chain_log.jsonl"', 1, true) ~= nil, true)

print(fails == 0 and "\n全て通った" or ("\n" .. fails .. " 件 NG"))
os.exit(fails == 0 and 0 or 1)
