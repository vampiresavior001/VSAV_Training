-- THE INVULNERABILITY / Q-BEE WAKE-UP DIAGNOSTIC (scripts/invulnLog.lua).
--
-- It records, per tick, the bytes that can make a player invulnerable, so the
-- one Bishamon's Kirisute Gomen uses for its frames 1-13 can be read off the
-- game instead of guessed - and, since 2026-10-08, what Q-Bee's wake-up head
-- shake needs: the cel, its counter and +$0B, the inputs, the confirmed strikes
-- and the reversal tick Meaty Timing waits on. Pinned here: it records only
-- with Knockdown Logger on and in a match, only the ticks something changed
-- (the cel counter alone only for Q-Bee, or while a move runs - version 3, for
-- Tick Data against Frame Meter, with the attack box id), appends JSON lines
-- after a header,
-- and writes from the frame callback (never from an exec hook, which cannot
-- open files). io.open is swallowed: this test must not write the real log.
--
--   lua5.1 analysis/test_invuln_log.lua

local fails = 0
local function want(what, got, w)
	if got ~= w then
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(w) .. "]")
	else
		print("  ok " .. what)
	end
end

local ram = {}
memory = {
	readbyte = function(a) return ram[a] or 0 end,
	readword = function(a) return ram[a] or 0 end,
	readdword = function(a) return ram[a] or 0 end,
}
local fc = 0
emu = { framecount = function() return fc end }
globals = { options = { knockdown_logger_enable = true }, match_running = function() return true end }

-- The modules the log reads, as the master script would have loaded them.
local totals = { [0xFF8400] = { body = 0, proj = 0 }, [0xFF8800] = { body = 0, proj = 0 } }
package.loaded["./scripts/tickDataVsav"] = { strike_totals = function() return totals end }
local waiting = nil
package.loaded["./scripts/meatyTiming"] = { waitingSince = function() return waiting end }

local opens = {}   -- { mode, text } per io.open of the log
local real_open = io.open
io.open = function(path, mode)
	if path == "reversal_logs/invuln_log.jsonl" then
		local o = { mode = mode, buf = {} }
		opens[#opens + 1] = o
		return { write = function(_, s) o.buf[#o.buf + 1] = s end, close = function() end }
	end
	return real_open(path, mode)
end

local M = dofile("scripts/invulnLog.lua")
local P1, P2 = 0xFF8400, 0xFF8800

local function all_text()
	local t = {}
	for _, o in ipairs(opens) do t[#t + 1] = table.concat(o.buf) end
	return table.concat(t)
end
local function rows_in(s) local n = 0 for _ in s:gmatch('"seq"') do n = n + 1 end return n end
local tick = 0
local function step(n) for _ = 1, n or 1 do tick = tick + 1 ; M.on_tick(tick) end end
local function flush() fc = fc + 100 ; M.registerAfter() end

-- Three ticks with nothing changing: one row per player for the first.
step(3) ; flush()
want("最初の書き込みは新しいファイル (w)", opens[1] and opens[1].mode, "w")
want("1 行目は見出し (読む位相の説明つき)", all_text():match('^{"log": "invuln_log", "version": 4, "read_at": "tick clock') ~= nil, true)
want("最初の Tick だけ記録 (両プレイヤー)", rows_in(all_text()), 2)
want("1 行 1 オブジェクト", select(2, all_text():gsub("\n", "")), 3)
want("Tick の番号も", all_text():find('"seq": 1, "tick": 1, "p": 1', 1, true) ~= nil, true)
-- Bishamon's move starts and $11E goes up: one more row for P1.
ram[P1 + 0x105] = 1 ; ram[P1 + 0x106] = 0x0A ; ram[P1 + 0x11E] = 1
step(2) ; flush()
want("2 回目からは追記 (a)", opens[2] and opens[2].mode, "a")
want("追記は新しい行だけ (見出しは繰り返さない)", select(2, table.concat(opens[2].buf):gsub('"log"', "")), 0)
want("変わった Tick だけ足す", rows_in(all_text()), 3)
want("$11E が記録される", all_text():find('"p": 1, .-"f11e": 1') ~= nil, true)
want("技 ID も", all_text():find('"move": "0x0A"', 1, true) ~= nil, true)

-- Q-Bee: the cel, its counter, +$08 and +$0B. The counter alone makes a row.
local CEL = 0x204C46
ram[P2 + 0x382] = 0x0C
ram[P2 + 0x1C] = CEL ; ram[CEL + 0x08] = 6 ; ram[CEL + 0x0B] = 0xFE
ram[P2 + 0x20] = 3 ; ram[P2 + 0x23] = 0xFF ; ram[P2 + 0x143] = 5
ram[P2 + 0x04] = 0x02000002
step() ; flush()
local qrow = all_text():match('[^\n]*"p": 2, "char": "0x0C"[^\n]*')
want("Q-Bee の行", qrow ~= nil, true)
want("セル", qrow and qrow:find('"cel": "0x204C46"', 1, true) ~= nil, true)
want("カウンター", qrow and qrow:find('"cnt": 3,', 1, true) ~= nil, true)
want("セル +$0B", qrow and qrow:find('"c0b": "0xFE"', 1, true) ~= nil, true)
want("セル +$08", qrow and qrow:find('"c08": 6,', 1, true) ~= nil, true)
want("$23", qrow and qrow:find('"f23": "0xFF"', 1, true) ~= nil, true)
want("状態", qrow and qrow:find('"state": "0x02000002"', 1, true) ~= nil, true)
local n = rows_in(all_text())
ram[P2 + 0x20] = 2
step() ; flush()
want("Q-Bee はカウンターだけでも 1 行", rows_in(all_text()), n + 1)
-- Another character's counter: a row only while a move runs ($105 not 0).
-- P1's move from above is still running.
ram[P1 + 0x20] = 7
step() ; flush()
want("ほかのキャラも技の最中はカウンターだけで 1 行", rows_in(all_text()), n + 2)
ram[P1 + 0x105] = 0
step() ; flush()
local m = rows_in(all_text())
ram[P1 + 0x20] = 6
step() ; flush()
want("技の外ではカウンターだけでは行にしない", rows_in(all_text()), m)
-- The attack box id at the cel's +$0A, as Tick Data and Frame Meter read it.
local P1CEL = 0x12E06A
ram[P1 + 0x1C] = P1CEL ; ram[P1CEL + 0x0A] = 5
step() ; flush()
want("攻撃判定の id", all_text():find('"p": 1, .-"box": 5,') ~= nil, true)
-- The knockdown flag Tick Data reads for Wakeup (version 4).
ram[P2 + 0x1A7] = 1
step() ; flush()
want("ダウンの印 $1A7", all_text():find('"p": 2, .-"kd": 1,') ~= nil, true)
ram[P2 + 0x1A7] = 0

-- Inputs, confirmed strikes, the Meaty Timing base.
ram[P2 + 0x122] = 0x01 ; ram[P2 + 0x125] = 0x08
step() ; flush()
want("入力 (ボタン・レバー)", all_text():find('"btn": "0x01", "dir": "0x08"', 1, true) ~= nil, true)
totals[P1].body = 4
step() ; flush()
want("打撃の累計 (P1 本体)", all_text():find('"p": 1, .-"sb": 4, "sp": 0', 1) ~= nil, true)
waiting = 1234
step() ; flush()
want("Meaty Timing の待っているリバーサル Tick", all_text():find('"mt_rev": 1234}', 1, true) ~= nil, true)
waiting = nil

-- Every line after the header is one JSON object.
local bad = 0
for line in all_text():gmatch("[^\n]+") do
	if not (line:sub(1, 1) == "{" and line:sub(-1) == "}") then bad = bad + 1 end
end
want("どの行も { … }", bad, 0)

-- Knockdown Logger off: nothing recorded.
local before = #opens
globals.options.knockdown_logger_enable = false
ram[P1 + 0x147] = 9
step() ; flush()
want("Knockdown Logger が OFF なら書かない", #opens, before)

-- Out of a match: nothing recorded either.
globals.options.knockdown_logger_enable = true
globals.match_running = function() return false end
n = rows_in(all_text())
ram[P1 + 0x147] = 8
step() ; flush()
want("試合外の Tick は記録しない", rows_in(all_text()), n)

-- Not from a hook.
local src = real_open("scripts/invulnLog.lua", "rb"):read("*a")
want("registerexec を使わない (ファイルを書けないため)", src:find("registerexec(", 1, true), nil)
local arch = real_open("analysis/archive_logs.py", "rb"):read("*a")
want("archive_logs.py が .jsonl も移す", arch:find('"invuln_log.jsonl"', 1, true) ~= nil, true)

io.open = real_open
if fails == 0 then print("test_invuln_log ok") else print(fails .. " 件 NG") os.exit(1) end
