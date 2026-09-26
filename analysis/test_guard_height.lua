-- ALL GUARD PICKS THE HEIGHT THE HIT NEEDS, OVER THE POSE.
--
-- All Guard added down whenever the attacker's $100 read 2 (a crouching
-- normal), which is not a property of the attack: the dummy crouched under
-- specials a standing guard takes, and a crouching Pose stayed down through
-- overheads (user, 2026-09-26). The game decides it in the hit routine from
-- the hit's box entry $17 (0x018352..0x0183EA); autoguard.lua now reads the
-- same byte.
--
-- Run from scripts/ - autoguard.lua is loaded by relative path.
--   cd scripts && lua5.1 ../analysis/test_guard_height.lua

package.preload["./scripts/debugKnockdown"] = function()
	return { mark_write = function() end }
end

local ram, dw = {}, {}
memory = {
	readbyte = function(a) return ram[a] or 0 end,
	readword = function(a) return ram[a] or 0 end,
	readdword = function(a) return dw[a] or 0 end,
	writebyte = function(a, v) ram[a] = v end,
}
emu = { framecount = function() return 1 end }

local ME, FOE = 0xFF8800, 0xFF8400
local CEL, TBL = 0x100000, 0x200000
local OBJ = 0xFF9400
local OCEL, OTBL = 0x110000, 0x210000

globals = {
	controlling_p1 = true,
	options = { guard = 4, p2_block_chance = 5 },
	dummy = { p1_attack_flag = true, p2_away_btn = "P2 Left", p1_status_2 = "",
	          p2_status_1 = "" },
}
local player_objects = { {}, { guard_ended = false } }

dofile("autoguard.lua")

local fails = 0
local function want(what, got, w)
	if got ~= w then
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(w) .. "]")
	else
		print("  ok " .. what)
	end
end

-- The attacker P1 swinging one cel with a box at index 3, in reach.
local function attacker(t, opts)
	opts = opts or {}
	ram, dw = {}, {}
	dw[FOE + 0x1C] = CEL
	dw[FOE + 0x8C] = TBL
	ram[FOE + 0x105] = 1
	ram[FOE + 0x10], ram[ME + 0x10] = 0x100, 0x140
	ram[FOE + 0x38] = opts.air and 1 or 0
	ram[FOE + 0x08] = opts.object and 1 or 0
	ram[FOE + 0xAD] = opts.ad and 1 or 0
	ram[FOE + 0x100] = opts.flag100 or 0
	local cel = CEL
	if opts.box_later then
		ram[cel + 0x0A] = 0            -- this cel has no box yet
		ram[cel + 0x01] = 0            -- and is not the last
		cel = cel + 0x18
	end
	ram[cel + 0x0A] = 3
	ram[cel + 0x01] = 0x40             -- last cel
	ram[TBL + 3 * 32 + 0x00] = 0x20    -- box offset: in reach
	ram[TBL + 3 * 32 + 0x04] = 0x10
	ram[TBL + 3 * 32 + 0x17] = t
end

local function guard(pose_keys)
	local keys = {}
	for k, v in pairs(pose_keys or {}) do keys[k] = v end
	dummy_guard(keys, player_objects)
	return keys
end
local CROUCH = { ["P2 Down"] = true }

print("-- 立ちのポーズ")
attacker(0x02)
local k = guard()
want("下段は下後ろ", k["P2 Down"] == true and k["P2 Left"] == true, true)
attacker(0x10)
want("どちらでもよい技は立ったまま", guard()["P2 Down"] ~= true, true)
attacker(0x10, { flag100 = 2 })
want("攻撃側の $100 が 2 でも、下段でなければしゃがまない", guard()["P2 Down"] ~= true, true)
attacker(0x4D)
want("中段は立ったまま", guard()["P2 Down"] ~= true, true)

print("-- しゃがみのポーズ")
attacker(0x4D)
want("中段は立つ", guard(CROUCH)["P2 Down"], false)
for _, t in ipairs({ 0x2C, 0x37, 0x42, 0x48, 0x4A }) do
	attacker(t)
	want(string.format("中段 %02X も立つ", t), guard(CROUCH)["P2 Down"], false)
end
attacker(0x10)
want("どちらでもよい技はしゃがんだまま", guard(CROUCH)["P2 Down"], true)
attacker(0x02)
want("下段はしゃがんだまま", guard(CROUCH)["P2 Down"], true)
for _, t in ipairs({ 0x03, 0x38, 0x39 }) do
	attacker(t)
	want(string.format("下段 %02X は立ちのポーズでもしゃがむ", t), guard()["P2 Down"], true)
end

print("-- ジャンプ攻撃")
attacker(0x00, { air = true })
want("空中の 00 は立つ", guard(CROUCH)["P2 Down"], false)
attacker(0x01, { air = true })
want("空中の 01 も立つ", guard(CROUCH)["P2 Down"], false)
attacker(0x00, { air = true, ad = true })
want("$ad が立っていればしゃがんだまま", guard(CROUCH)["P2 Down"], true)
attacker(0x00, { air = true, object = true })
want("飛び道具 ($08) ならしゃがんだまま", guard(CROUCH)["P2 Down"], true)
attacker(0x00)
want("地上の 00 はしゃがんだまま", guard(CROUCH)["P2 Down"], true)

print("-- 絵をたどる")
attacker(0x02, { box_later = true })
want("箱のある最初の絵の種類で決める", guard()["P2 Down"], true)

print("-- 飛び道具などの物体")
do
	attacker(0x10)
	ram[FOE + 0x105] = 0                -- 本体は攻撃していない
	ram[OBJ] = 1
	ram[OBJ + 0x01] = 1
	ram[OBJ + 0x70] = 1                 -- 相手のもの (ME の $70 は 0)
	dw[OBJ + 0x1C] = OCEL
	dw[OBJ + 0x8C] = OTBL
	ram[OBJ + 0x08] = 1
	ram[OCEL + 0x0A] = 2
	ram[OCEL + 0x01] = 0x40
	ram[OTBL + 2 * 32 + 0x17] = 0x38
	want("下段の物体にはしゃがむ", guard()["P2 Down"], true)
	-- 本体が中段、物体が下段: 両方は満たせないのでポーズのまま。
	ram[FOE + 0x105] = 1
	ram[TBL + 3 * 32 + 0x17] = 0x4D
	want("中段と下段が重なればポーズのまま (しゃがみ)", guard(CROUCH)["P2 Down"], true)
	want("中段と下段が重なればポーズのまま (立ち)", guard()["P2 Down"] ~= true, true)
end

print("-- All Guard 以外")
globals.options.guard = 2              -- Stand Block
attacker(0x4D)
want("Stand Block は今までどおり (ポーズの下を外さない)", guard(CROUCH)["P2 Down"], true)
attacker(0x02)
want("Stand Block は下段でもしゃがまない", guard()["P2 Down"] ~= true, true)
globals.options.guard = 6              -- Push Block (All Medium)
attacker(0x4D)
want("Push Block は All Guard と同じ", guard(CROUCH)["P2 Down"], false)
globals.options.guard = 4

print("-- ダミーが P1 のとき (P2 を操作している)")
-- 下は P1 Down。以前は "P2 Down" 固定で、操作している人の下を書き換えていた。
globals.controlling_p1 = false
globals.dummy.p2_attack_flag = true
globals.dummy.p1_away_btn = "P1 Right"
ME, FOE = 0xFF8400, 0xFF8800
attacker(0x02)
local kp = guard()
want("P1 の下を入れる", kp["P1 Down"], true)
want("P2 の下には触れない", kp["P2 Down"], nil)
attacker(0x4D)
kp = guard({ ["P1 Down"] = true, ["P2 Down"] = true })
want("中段で P1 の下を外す", kp["P1 Down"], false)
want("人の P2 の下はそのまま", kp["P2 Down"], true)
globals.controlling_p1 = true
ME, FOE = 0xFF8800, 0xFF8400

if fails == 0 then
	print("test_guard_height ok")
else
	print(fails .. " 件 NG")
	os.exit(1)
end
