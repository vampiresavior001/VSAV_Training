-- HOLD: THE DIRECTION STAYS DOWN AFTER THE ATTACK.
--
-- A charge move is a direction held and then let go. A step's input otherwise
-- exists for the one tick it is written - the walker frees the delivery slot
-- and nothing writes 0xFF8B94 again until the next step - so nothing charges.
--
-- The Hold row on an attack marks the step, the compiler turns it into the
-- LEVER of the last entry with the buttons stripped, and the walker keeps
-- asserting that until the next step takes over.
--
-- This drives the real compiler and a stand-in for the walker built to the same
-- rules, recording what lands on the input word each tick.
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_seq_hold.lua
local ram = {}
memory = {
	readbyte  = function(a) return ram[a] or 0 end,
	readdword = function(a) return ram[a] or 0 end,
}
gui = { text = function() end, box = function() end }
emu = { framecount = function() return 1 end }
globals = { dummy = { guard_action = "sequence" }, options = {} }
training_settings = { action_sequences = {} }
function mark_training_settings_dirty() end
function dash_attack_ticks_for() return nil end
-- キャンセル方向の地図 (guardCancel が公開する seq_dash_cancel_reverse の代役)。
seq_dash_cancel_reverse = { ["forward dash cancel"] = "back", ["back dash cancel"] = "forward" }

local csrc = io.open("controller.lua"):read("*a")
local cs = csrc:find("function make_input_sequence", 1, true)
local ce = csrc:find("\nend", csrc:find("return _sequence", cs, true), true)
assert(cs and ce, "make_input_sequence が controller.lua に見つからない")
assert(loadstring(csrc:sub(cs, ce + 4)))()

-- The record queue_input_sequence builds, reduced to what the walker uses.
local queued = nil
function queue_input_sequence(_d, _seq)
	queued = { sequence = _seq, current_frame = 1 }
	_d.pending_input_sequence = queued
end

local R = dofile("actionSequenceRunner.lua")

local fails = 0
local function fail(what, got, want)
	fails = fails + 1
	print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(want) .. "]")
end

-- Names to bits, the same mapping entry_to_bits uses (facing 0 = forward is
-- 0x02). Buttons are only distinguished from zero here.
local BITS = { forward = 0x02, back = 0x01, down = 0x04, up = 0x08 }
local function to_bits(entry)
	local lev, btn = 0, 0
	for _, k in ipairs(entry or {}) do
		if BITS[k] then lev = lev + BITS[k] else btn = 1 end
	end
	return lev, btn
end
local function lev_name(lev)
	if lev == 0 then return "-" end
	local out = {}
	for _, k in ipairs({ "up", "down", "back", "forward" }) do
		if lev % (BITS[k] * 2) >= BITS[k] then out[#out + 1] = k end
	end
	return table.concat(out, "+")
end

local P2 = 0xFF8800
local function set_free() ram[P2 + 0x05] = 0 ; ram[P2 + 0x06] = 0 ; ram[P2 + 0x38] = 0 end
local function set_stun() ram[P2 + 0x05] = 2 ; ram[P2 + 0x06] = 0x0A ; ram[P2 + 0x38] = 0 end

-- THE WALKER, TO THE SAME RULES AS guardCancel's seq_tick BLOCK.
--
-- Two passes so one tick can end a segment and start the next; the v158 hold
-- (buttonless entries take two ticks); the hold picked up when a segment runs
-- off its end; and dropped once the schedule is empty.
local held_lever = nil
local defender = {}
local log = {}
local function tick()
	local wrote = nil
	for _pass = 1, 2 do
		R.service(defender)
		local s = defender.pending_input_sequence
		if s == nil or s.sequence == nil then break end
		held_lever = nil
		local i = s.current_frame or 1
		if i <= #s.sequence then
			local lev, btn = to_bits(s.sequence[i])
			wrote = { lev = lev, btn = btn, src = "step" }
			local hold = (btn == 0 and lev ~= 0) and 2 or 1
			s.tick_held = (s.tick_held or 0) + 1
			if s.tick_held >= hold then
				s.current_frame = i + 1
				s.tick_held = 0
			end
			break
		end
		held_lever = s.seq_hold
		defender.pending_input_sequence = nil
	end
	if wrote == nil and held_lever ~= nil then
		if R.pending_count() == 0 then
			held_lever = nil
		else
			local lev = to_bits(held_lever)
			wrote = { lev = lev, btn = 0, src = "hold" }
		end
	end
	log[#log + 1] = wrote or { lev = 0, btn = 0, src = "none" }
	return log[#log]
end
local function run(n) for _ = 1, n do tick() end end
local function trace()
	local out = {}
	for _, e in ipairs(log) do
		out[#out + 1] = e.src .. ":" .. lev_name(e.lev) .. (e.btn ~= 0 and "+B" or "")
	end
	return table.concat(out, " ")
end

local function install(steps)
	ram[0xFF8B82] = 0x08                       -- Bishamon
	training_settings.action_sequences = { reversal = { ["8"] = { version = 1, steps = steps } } }
end
local function start()
	log = {} ; held_lever = nil ; queued = nil
	defender = {}
	R.cancel()
	R.arm("reversal")                          -- 1 歩目は呼び出し側が出す
end

-- 凍結中は予測で撃たない。ただし黙らない。
--
-- ticks_to_landing() は物理の時間で答え、入力の配送は時計で進む。ヒットストップ
-- はその 2 つを引き離す - 位置が止まってもティックは進む (2026-09-18 実測)。
-- そこで撃つと助走が窓を食いながら進み、モーションが途中で切れる。コマンド受付
-- カウンタは物理と一緒には止まらない (本人の経験則)。
--
-- 待っても失うものは無い。時機を逃せば、空中でなくなった時点で着地時に出る。
-- 遅れても出る方が、黙るより有意義 (本人、2026-09-18)。

local P2 = 0xFF8800
local fails = 0
local function want(what, got, w)
	if got ~= w then
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(w) .. "]")
	else
		print("  ok " .. what)
	end
end

-- 着地まで 4 ティックに見せる弾道。助走 4 のダッシュがちょうど commit する形。
local function airborne_about_to_land()
	ram[P2 + 0x38] = 1                    -- 空中
	ram[P2 + 0x14] = 6 * 65536            -- y
	ram[P2 + 0x44] = -65536               -- 落下中
	ram[P2 + 0x4C] = -65536               -- 加速
	ram[P2 + 0x3A] = 0                    -- 床
end

local seen = {}
seq_ticks_to_landing = function() return 4 end

local function install_landing_step()
	ram[0xFF8B82] = 0x0A
	training_settings.action_sequences = { reversal = { ["10"] = { version = 1, steps = {
		{ action = "atk", lever = "none", button = "LP", wait = 0 },
		{ action = "dash.f", timing = "landing", wait = -1 },
	} } } }
end

print("[1] 凍っていなければ、予測で撃つ")
install_landing_step()
start()
airborne_about_to_land()
ram[P2 + 0x5C] = 0                        -- ヒットストップ無し
local before = #log
run(3)
want("撃った", #log > before, true)

print("[2] 凍っている間は撃たない")
install_landing_step()
start()
airborne_about_to_land()
ram[P2 + 0x5C] = 11                       -- ヒットストップ中
local n = 0
for _ = 1, 12 do
	local e = tick()
	if e.src == "step" then n = n + 1 end
end
want("凍っている間は 1 回も撃たない", n, 0)

print("[3] 解ければ撃つ")
ram[P2 + 0x5C] = 0
local m = 0
for _ = 1, 6 do
	local e = tick()
	if e.src == "step" then m = m + 1 end
end
want("解けたら撃つ", m > 0, true)

print("[4] 黙らない - 着地してしまっても出る")
install_landing_step()
start()
airborne_about_to_land()
ram[P2 + 0x5C] = 11
for _ = 1, 8 do tick() end                -- 凍っている間に
ram[P2 + 0x38] = 0                        -- 着地してしまった
ram[P2 + 0x5C] = 0
set_free()
local k = 0
for _ = 1, 20 do
	local e = tick()
	if e.src == "step" then k = k + 1 end
end
want("時機を逃しても出る", k > 0, true)

print(fails == 0 and "REP_OK" or (fails .. " REP_NG"))
os.exit(fails == 0 and 0 or 1)
