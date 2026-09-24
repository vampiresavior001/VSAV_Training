-- Auto (Chain) / Auto (Cancel) が $06 を見ないこと。
--
-- WHY THIS EXISTS. 両ゲートは「通常技が出ているか」の代わりに $06 == 0x0A を
-- 見ていた。接触ティックの $06 はキャラがその時やっていたことの値で、実測は
--
--     0x06 ジャンプ   空中接触 13 件中 12
--     0x14 ダッシュ   地上接触 12 件中 7
--     0x00            地上接触 12 件中 5
--     0x0A 通常技     空中接触 13 件中 1
--
-- (VSAV_MEMORY_NOTES、2026-09-09)。0x0A はどこでも少数派で、空中チェーンも
-- ダッシュ攻撃からのキャンセルも弾かれていた (本人、2026-09-24)。
--
-- ROM はチェーン (0x028E42) が $39 / $1B2 / $12E / セルのフラグ、キャンセルが
-- $167 / $168 / $119 を見るだけで、どちらも $06 も $38 も見ていない。条件ごと
-- 外すのが正しい。
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_chain_air.lua
local NL = string.char(10)
local src = io.open("actionSequenceRunner.lua"):read("*a")

local fails = 0
local function want(what, got, expected)
	if got == expected then
		print("  ok " .. what)
	else
		fails = fails + 1
		print("  NG " .. what)
		print("     got  [" .. tostring(got) .. "]  want [" .. tostring(expected) .. "]")
	end
end

-- 区間で挟んで取り出す。CHAIN_RANK から chain_ready の end まで。
local s = src:find("local CHAIN_RANK = {", 1, true)
local c = src:find("local function cancel_ready(step, late)", s or 1, true)
local e = src:find(NL .. "end", c or 1, true)
assert(s ~= nil and c ~= nil and e ~= nil, "chain_ready / cancel_ready の区間が見つからない")

local BASE = 0xFF8800
local ram = {}
memory = { readbyte = function(a) return ram[a] or 0 end }
P2_BASE = BASE
assert(loadstring(src:sub(s, e + 4) .. NL
	.. "_G.chain_ready = chain_ready" .. NL
	.. "_G.cancel_ready = cancel_ready" .. NL
	.. "_G.gate_why_now = function() return gate_why end"))()

-- LP が当たった直後に MP を繋ぐ、という通る形を土台にする。
local function ground()
	ram = {}
	ram[BASE + 0x06] = 0x0A   -- 通常技
	ram[BASE + 0x39] = 1      -- 接触あり
	ram[BASE + 0x1B2] = 0     -- チェーン禁止なし
	ram[BASE + 0x102] = 0     -- 弱
	ram[BASE + 0x101] = 0     -- パンチ
end
local MP = { button = "MP" }

print("[1] 地上は今までどおり通る")
do
	ground()
	want("LP -> MP", chain_ready(MP), true)
end

print("")
print("[2] 空中 ($06 = 0x06 のまま) でも通る")
do
	ground()
	ram[BASE + 0x06] = 0x06   -- ジャンプのまま当たった
	ram[BASE + 0x38] = 1      -- 空中
	want("空中 LP -> MP", chain_ready(MP), true)
	ground()
	ram[BASE + 0x06] = 0x14   -- ダッシュ攻撃のまま当たった (?act14)
	want("ダッシュ攻撃から MP", chain_ready(MP), true)
end

print("")
print("[3] $06 が何であっても通る - 条件ではない")
do
	-- 実測された 4 種類すべて。どれも接触があれば繋がる。
	for _, v in ipairs({ 0x00, 0x06, 0x0A, 0x0E, 0x14 }) do
		ground()
		ram[BASE + 0x06] = v
		want(string.format("$06 = 0x%02X", v), chain_ready(MP), true)
	end
	-- 見ていないこと自体を区間で挟んで固定する。
	local a = src:find("local function chain_ready(step)", 1, true)
	local b = src:find(NL .. "end", a or 1, true)
	want("chain_ready は $06 を読まない",
		src:sub(a or 1, (b or 1) + 4):find("P2_BASE + 0x06", 1, true), nil)
	local c = src:find("local function cancel_ready(step, late)", 1, true)
	local d = src:find(NL .. "end", c or 1, true)
	want("cancel_ready も $06 を読まない",
		src:sub(c or 1, (d or 1) + 4):find("P2_BASE + 0x06", 1, true), nil)
end

print("")
print("[4] ROM の条件は空中でも外さない")
do
	ground()
	ram[BASE + 0x06] = 0x06
	ram[BASE + 0x39] = 0
	want("接触が無ければ繋がない", chain_ready(MP), false)
	ground()
	ram[BASE + 0x06] = 0x06
	ram[BASE + 0x1B2] = 1
	want("チェーン禁止なら繋がない", chain_ready(MP), false)
	ground()
	ram[BASE + 0x06] = 0x06
	want("弱から弱へは繋がない", chain_ready({ button = "LP" }), false)
	ground()
	ram[BASE + 0x06] = 0x06
	ram[BASE + 0x102] = 4      -- 強
	want("強から中へは繋がない", chain_ready(MP), false)
end

print("")
print("[5] キャンセルも同じ - 空中で $06 が 0x06 のまま通ること")
do
	-- ROM のキャンセル許可は $167 / $168 と $119 で、$06 は見ていない。
	-- chain と同じ行が cancel_ready にもあった (本人の指摘、2026-09-24)。
	local ATK = { button = "MP", lead = 2 }
	ground()
	want("地上の Auto Cancel", cancel_ready(ATK, false), true)
	ground()
	ram[BASE + 0x06] = 0x06
	ram[BASE + 0x38] = 1
	want("空中の Auto Cancel", cancel_ready(ATK, false), true)

	-- Late Cancel は $119 が 0 で、窓が lead+1 以内のときだけ。
	ground()
	ram[BASE + 0x06] = 0x06
	ram[BASE + 0x38] = 1
	ram[BASE + 0x167] = 2
	want("空中の Late Cancel", cancel_ready(ATK, true), true)
	ram[BASE + 0x119] = 1
	want("チェーン始動は Late Cancel させない", cancel_ready(ATK, true), false)
	ground()
	ram[BASE + 0x06] = 0x06
	ram[BASE + 0x167] = 9      -- まだ窓が先
	want("窓が遠ければ待つ", cancel_ready(ATK, true), false)

	ground()
	ram[BASE + 0x06] = 0x14    -- ダッシュ攻撃 (実機で出た ?act14)
	want("ダッシュ攻撃からキャンセルできる", cancel_ready(ATK, false), true)
	ground()
	ram[BASE + 0x06] = 0x06
	ram[BASE + 0x39] = 0
	want("接触が無ければ Auto Cancel しない", cancel_ready(ATK, false), false)
end

print("")
print("[6] 止まった条件を名前で残す")
do
	-- Wait の数字だけでは「窓が開くのが遅かった」のか「一度も開かず締切で
	-- 出た」のかが区別できない。止まった条件を Show Step Wait Ticks に出す
	-- (本人、2026-09-24 の Wait:29)。
	local ATK = { button = "MP", lead = 2 }
	ground()
	ram[BASE + 0x39] = 0
	cancel_ready(ATK, false)
	want("接触待ちは hit", gate_why_now(), "hit")

	ground()
	ram[BASE + 0x06] = 0x06
	ram[BASE + 0x119] = 1
	cancel_ready(ATK, true)
	want("チェーン始動は chain", gate_why_now(), "chain")

	ground()
	ram[BASE + 0x06] = 0x06
	ram[BASE + 0x167] = 9
	cancel_ready(ATK, true)
	want("窓が遠いときは win と値", gate_why_now(), "win9")

	-- 通ったときは何も残さない。連結した step に理由が付くと嘘になる。
	ground()
	want("通れば消える", (function()
		cancel_ready(ATK, false)
		return gate_why_now()
	end)(), nil)

	ground()
	ram[BASE + 0x1B2] = 1
	chain_ready(MP)
	want("チェーン禁止は inhib", gate_why_now(), "inhib")
	ground()
	chain_ready(MP)
	want("チェーンも通れば消える", gate_why_now(), nil)

	-- log_wait が理由を項目に載せていること。行に出す側は
	-- test_runner_compile が実際に組み立てて見ている。区間で挟んで、
	-- 別の log_entry に当たらないようにする。
	local a = src:find("local function log_wait(step, ticks)", 1, true)
	local b = src:find(NL .. "end", a or 1, true)
	local body = src:sub(a or 1, (b or 1) + 4)
	want("log_wait に why がある",
		body:find("why   = CONNECT_TIMED[step.timing] and gate_why", 1, true) ~= nil,
		true)
end

print("")
if fails == 0 then
	print("ALL OK")
else
	print(fails .. " NG")
	os.exit(1)
end
