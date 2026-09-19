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

-- Loop Wait に Auto (Landing) を足した。
--
-- 2 歩 (跳ぶダッシュ → 空中の小技) を、着地で回したい。Auto (After) では
-- ダッシュの助走 4 ティックの分だけ遅れる。数値では跳んだ時間が毎回違うので
-- 当たらない。着地で回すのが唯一の答え。

local fails = 0
local function want(what, got, w)
	if got ~= w then
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(w) .. "]")
	else
		print("  ok " .. what)
	end
end

print("[1] loop_wait が -2 を素通しする")
training_settings.action_steps_loop_wait = -2
want("Auto (Landing) が潰れない", R.loop_wait(), -2)
training_settings.action_steps_loop_wait = -1
want("Auto (After) はそのまま", R.loop_wait(), -1)
training_settings.action_steps_loop_wait = 0
want("0 は Auto に倒す", R.loop_wait(), -1)
training_settings.action_steps_loop_wait = 7
want("数値はそのまま", R.loop_wait(), 7)

print("[2] コンパイラは 1 歩目に timing を付けない")
-- loop_refill が 1 歩目へ landing を書き込めるのは、そこが常に空だから。
install({
	{ action = "dash.f", timing = "landing", wait = -1 },
	{ action = "atk", lever = "none", button = "LK", wait = -1 },
})
-- timing は両方の歩に置く。1 歩目のものは捨てられ、2 歩目のものは残る -
-- それが loop_refill が 1 歩目へ書き込んでよい根拠。
local sched = R.compile({ version = 1, steps = {
	{ action = "dash.f", timing = "landing", wait = -1 },
	{ action = "atk", lever = "none", button = "LK", timing = "landing", wait = -1 },
} })
want("1 歩目の timing は捨てられる", sched[1].timing, nil)
want("2 歩目の timing は残る", sched[2].timing, "landing")

print("[3] ソースの配線")
do
	local src = io.open("actionSequenceRunner.lua"):read("*a")
	want("LOOP_LANDING がある", src:find("local LOOP_LANDING = -2", 1, true) ~= nil, true)
	want("loop_refill が landing を書く",
		src:find("_first.timing = TIMING_LANDING", 1, true) ~= nil, true)
	local m = io.open("menu.lua"):read("*a")
	want("メニューの下限が -2", m:find('"action_steps_loop_wait", -2, 120', 1, true) ~= nil, true)
	-- 説明文にも "Auto (Landing)" は出てくる。それを拾って通ってしまい、描画の
	-- 分岐が入っていないのに緑になった。描くのは gui.text の側だと名指しする。
	want("-2 を Auto (Landing) と描く",
		m:find('" : Auto (Landing)"', 1, true) ~= nil, true)
	want("その分岐が -2 を見ている",
		m:find("if _v == LOOP_WAIT_LANDING then", 1, true) ~= nil, true)
end

print(fails == 0 and "REP_OK" or (fails .. " REP_NG"))
os.exit(fails == 0 and 0 or 1)
