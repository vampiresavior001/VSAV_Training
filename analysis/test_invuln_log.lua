-- THE INVULNERABILITY DIAGNOSTIC (scripts/invulnLog.lua).
--
-- It records, per tick, the bytes that can make a player invulnerable, so the
-- one Bishamon's Kirisute Gomen uses for its frames 1-13 can be read off the
-- game instead of guessed. Pinned here: it records only with Knockdown Logger
-- on and in a match, only the ticks something changed, and writes from the
-- frame callback (never from an exec hook, which cannot open files).
-- io.open is swallowed: this test must not write the real log.
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
	readdword = function(a) return ram[a] or 0 end,
}
local fc = 0
emu = { framecount = function() return fc end }
globals = { options = { knockdown_logger_enable = true }, match_running = function() return true end }

local written = {}
local real_open = io.open
io.open = function(path, mode)
	if path == "reversal_logs/invuln_log.json" then
		local buf = {}
		written[#written + 1] = buf
		return { write = function(_, s) buf[#buf + 1] = s end, close = function() end }
	end
	return real_open(path, mode)
end

local M = dofile("scripts/invulnLog.lua")
local P1 = 0xFF8400

local function text() return table.concat(written[#written] or {}) end
local function rows_in(s) local n = 0 for _ in s:gmatch('"seq"') do n = n + 1 end return n end

-- Three ticks with nothing changing: one row per player for the first.
for _ = 1, 3 do M.on_tick() end
fc = 100 ; M.registerAfter()
want("最初の Tick だけ記録 (両プレイヤー)", rows_in(text()), 2)
-- Bishamon's move starts and $11E goes up: one more row for P1.
ram[P1 + 0x105] = 1 ; ram[P1 + 0x106] = 0x0A ; ram[P1 + 0x11E] = 1
M.on_tick() ; M.on_tick()
fc = 200 ; M.registerAfter()
want("変わった Tick だけ足す", rows_in(text()), 3)
want("$11E が記録される", text():find('"p": 1, .-"f11e": 1') ~= nil, true)
want("技 ID も", text():find('"move": "0x0A"', 1, true) ~= nil, true)

-- Knockdown Logger off: nothing recorded.
local before = #written
globals.options.knockdown_logger_enable = false
ram[P1 + 0x147] = 9
M.on_tick()
fc = 300 ; M.registerAfter()
want("Knockdown Logger が OFF なら書かない", #written, before)

-- Out of a match: nothing recorded either.
globals.options.knockdown_logger_enable = true
globals.match_running = function() return false end
ram[P1 + 0x147] = 8
M.on_tick()
fc = 400 ; M.registerAfter()
want("試合外の Tick は記録しない", rows_in(text()), 3)

-- Not from a hook.
local src = real_open("scripts/invulnLog.lua", "rb"):read("*a")
want("registerexec を使わない (ファイルを書けないため)", src:find("registerexec(", 1, true), nil)

io.open = real_open
if fails == 0 then
	print("test_invuln_log ok")
else
	print(fails .. " 件 NG")
	os.exit(1)
end
