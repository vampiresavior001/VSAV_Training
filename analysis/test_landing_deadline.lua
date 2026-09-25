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

-- 起きなかった着地を待ち続けない。
--
-- 実機報告 (2026-09-17)、旧版 v11.7.2 でも再現。3 歩の並び
--   1 Auto (Fastest)  Dash : Forward Cancel
--   2 Auto (3)        Attack : LP
--   3 Auto (Landing)  Attack : Down
-- でダッシュが出ず、立ち小 P のあとで止まった。跳んでいないので着地は永久に
-- 来ない。接続待ちの枝には前から期限があったが、着地には無かった。

local fails = 0
local function want(what, got, w)
	if got ~= w then
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(w) .. "]")
	else
		print("  ok " .. what)
	end
end

local function buttons()
	local n = 0
	for _, e in ipairs(log) do if e.btn ~= 0 then n = n + 1 end end
	return n
end

print("[1] 跳ばないまま Landing 待ちのステップがある")
-- 2 歩目を着地待ちにする。地上で殴るだけなので着地は起きない。
install({
	{ action = "atk", lever = "none", button = "LP", wait = 0 },
	{ action = "atk", lever = "none", button = "MP", timing = "landing", wait = -1 },
})
start()
-- 硬直に入れてから解く。これが「一度忙しくなって、また自由になった」という
-- 期限そのもの。
set_stun()
run(4)
set_free()
run(30)
want("着地を待たずに出た", buttons() >= 1, true)
print("   " .. trace():sub(1, 90))

print("[2] 期限は接続待ちと同じものを使っている")
-- timing_missed は「一度忙しくなって、また自由になった」。最初から自由なまま
-- の場合は対象外で、それで正しい - 直前のステップが必ず硬直を作るので、実際に
-- 詰まるのは今回のような「跳ばなかった」場合だけ。接続待ちと同じ関数を使って
-- いることをソースで固定しておく。別々に育つと、また片方だけ期限を失う。
do
	local src = io.open("actionSequenceRunner.lua"):read("*a")
	-- 2026-09-20 に診断を挟んだので、1 行の式ではなくなった。見張りたいのは
	-- 「着地の分岐が両方の門を見て、どちらも閉じていれば返す」こと。
	local at = src:find("local _lr = landing_ready(step)", 1, true)
	want("着地が landing_ready を見る", at ~= nil, true)
	want("着地が timing_missed も見る",
		at ~= nil and src:find("timing_missed(step)", at, true) ~= nil, true)
	want("どちらも閉じていれば返す",
		at ~= nil and src:find("else", at, true) ~= nil
		and src:find("return", at, true) ~= nil, true)
	want("接続待ちも同じ関数",
		src:find("if not _ok and not timing_missed(step) then", 1, true) ~= nil, true)
	-- 2026-09-20: 期限が狙いを追い越していた。落下中はダミーも「自由」なので、
	-- timing_missed が landing_ready より 3 ティック早く開き、押しが空中に
	-- 落ちていた (実測 13 回中 11 回)。着地が来るあいだは順番を譲ること。
	--
	-- 2026-09-25: 予測が取れない空中 (アナカリスの浮遊) では期限が開いていて、
	-- 着地後の MP が着地 5 フレーム前の空中で押された。空中では予測の有無に
	-- かかわらず期限を効かせない - 期限は地上にいるときだけ。[3] が実際に動かす。
	local tm_a = at and src:find("local _tm = false", at, true)
	local tm_b = tm_a and src:find("if _lr or _tm then", tm_a, true)
	local tm = (tm_a and tm_b) and src:sub(tm_a, tm_b) or ""
	want("期限は地上にいるときだけ",
		tm:find("_tm = (memory.readbyte(P2_BASE + 0x38) == 0)", 1, true) ~= nil, true)
	want("予測が無いことを理由に空中で期限を開けない",
		tm:find("seq_ticks_to_landing", 1, true), nil)
	-- 跳ばなかった場合の保険は残すこと。ここが消えると [1] が永久に待つ。
	want("着地が来ないなら期限は生きている",
		at ~= nil and src:find("timing_missed(step) then", at, true) ~= nil, true)
end

print("[3] 予測の取れない空中で動作が終わっても、着地までは押さない")
-- 実機 2026-09-25。アナカリスの浮遊の最後の攻撃が終わり、空中の待機 ($07 = 02)
-- に戻った瞬間に、着地待ちの MP が押された。空中で出ず、着地後の攻撃が消えた。
-- 着地の予測はこの浮遊を解けない (seq_ticks_to_landing は nil を返す)。
install({
	{ action = "atk", lever = "none", button = "LP", wait = 0 },
	{ action = "atk", lever = "none", button = "MP", timing = "landing", wait = -1 },
})
start()
local real_ld = seq_ticks_to_landing
seq_ticks_to_landing = function() return nil end
-- 空中で攻撃中 ($07 = 06) - 忙しい。
ram[P2 + 0x38], ram[P2 + 0x05], ram[P2 + 0x06], ram[P2 + 0x07] = 1, 0, 0x06, 0x06
run(4)
-- 空中の待機に戻る ($07 = 02) - 空中では「自由」。ここで押してはいけない。
ram[P2 + 0x07] = 0x02
local before = buttons()
run(10)
want("空中の待機では押さない", buttons(), before)
-- 着地。最初の地上のティックで押す。
ram[P2 + 0x38], ram[P2 + 0x06], ram[P2 + 0x07] = 0, 0, 0
run(6)
want("着地したら押す", buttons() > before, true)
seq_ticks_to_landing = real_ld
print("   " .. trace():sub(1, 110))

print(fails == 0 and "REP_OK" or (fails .. " REP_NG"))
os.exit(fails == 0 and 0 or 1)
