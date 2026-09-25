-- ジャンプ後の攻撃の最速 - 公開資料の表から起こしたもの。
--
-- WHY THIS EXISTS. ジャンプの後の Auto (Fastest) には数字が無く、状態判定
-- (「動作が終わった」= ほぼ着地) まで待っていた。最低空攻撃は手で Ticks を
-- 入れるしかなかった。
--
-- 数字は「Vampire Savior System Data」のジャンプのページ、「攻撃前」の列
-- (単位はフレーム)。本人の指示で表から起こした (2026-09-25)。
--
--   * 表のフレームはティックとして扱う。予備動作 3 が、実測の離陸「起点から
--     2〜4t」と整合している (VSAV_MEMORY_NOTES)。
--   * 1 引く。ジャンプはボタンの無い 1 エントリなので 2 ティック入り、予備動作は
--     その 1 ティック目に始まる。Wait は最後のティックから数える。
--   * 確かめたのはオルバス前方 (表 5、実測 4) とジェダ前方 (表 6、実測 5)。
--
-- ここでは表の値そのものを固定する。書き換わっていたら、資料と見比べること。
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_jump_attack_floor.lua
local NL = string.char(10)
local src = io.open("guardCancel.lua"):read("*a")

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

-- 区間で挟んで取り出す。表と関数は do ... end の中にある (ファイル全体の
-- ローカルが Lua 5.1 の上限 200 に達しているため)。その do から end まで。
local s = src:find(NL .. "do" .. NL .. "	local JUMP_BEFORE_ATTACK = {", 1, true)
local f = src:find("function jump_attack_ticks_for(_jump)", s or 1, true)
local e = src:find(NL .. "end", f or 1, true)
assert(s ~= nil and f ~= nil and e ~= nil, "jump_attack_ticks_for の区間が見つからない")

local cid = 0
memory = { readbyte = function(a) return (a == 0xFF8B82) and cid or 0 end }
assert(loadstring(src:sub(s, e + 4) .. NL .. "_G.jaf = jump_attack_ticks_for"))()

-- 資料の「攻撃前」(フレーム)。前方 / 垂直 / 後方。
local PAGE = {
	[0x00] = { "Bulleta",    6,  6,  6 },
	[0x01] = { "Demitri",    6,  6,  6 },
	[0x02] = { "Gallon",     5,  5,  5 },
	[0x03] = { "Victor",     6,  6,  6 },
	[0x04] = { "Zabel",      5,  5,  5 },
	[0x05] = { "Morrigan",   6,  6,  6 },
	[0x06] = { "Anakaris",  15, 19, 15 },
	[0x07] = { "Felicia",    5,  5,  5 },
	[0x08] = { "Bishamon",   6,  6,  6 },
	[0x09] = { "Aulbath",    5,  5,  5 },
	[0x0A] = { "Sasquatch",  5,  5,  5 },
	[0x0C] = { "Q-Bee",      6,  6,  5 },
	[0x0D] = { "Lei-Lei",    6,  6,  6 },
	[0x0E] = { "Lilith",     6,  6,  6 },
	[0x0F] = { "Jedah",      6,  6,  6 },
}

print("[1] 本人の実測 - オルバス前方 4、ジェダ前方 5")
do
	-- 実測と「表 - 1」が一致していることが、換算規則の裏付け。攻撃前の値が
	-- 違う 2 キャラ (5 と 6) で合っている。「予備動作 + 1」はオルバスでは
	-- 同じ 4 になるが、ジェダを 4 と予想して外れた (本人、2026-09-25)。
	cid = 0x09
	want("オルバス前方", jaf("jump.f"), 4)
	want("オルバスは表 - 1 と一致", jaf("jump.f"), PAGE[0x09][2] - 1)
	cid = 0x0F
	want("ジェダ前方", jaf("jump.f"), 5)
	want("ジェダは表 - 1 と一致", jaf("jump.f"), PAGE[0x0F][2] - 1)
	want("「予備動作 + 1」(4) ではない", jaf("jump.f") ~= 4, true)
end

print("")
print("[2] 他は全部「表 - 1」")
do
	local bad = {}
	local n = 0
	for id, row in pairs(PAGE) do
		cid = id
		for i, j in ipairs({ "jump.f", "jump.n", "jump.b" }) do
			n = n + 1
			local got = jaf(j)
			if got ~= row[i + 1] - 1 then
				bad[#bad + 1] = string.format("%s %s = %s (表 %d)", row[1], j, tostring(got), row[i + 1])
			end
		end
	end
	want("15 キャラ x 3 方向", n, 45)
	want("すべて表 - 1", table.concat(bad, " / "), "")
	-- 形の違う 2 キャラは念のため値で見る。
	cid = 0x06
	want("アナカリス垂直は 18", jaf("jump.n"), 18)
	cid = 0x0C
	want("キュービィ後方だけ 4", jaf("jump.b"), 4)
end

print("")
print("[3] 表に無いものは数字を出さない")
do
	for _, id in ipairs({ 0x0B, 0x12, 0x18 }) do
		cid = id
		want(string.format("0x%02X は nil", id), jaf("jump.f"), nil)
	end
	cid = 0x09
	want("スーパージャンプは nil", jaf("sj.f"), nil)
	want("ジャンプ以外は nil", jaf("dash.f"), nil)
end

print("")
if fails == 0 then
	print("ALL OK")
else
	print(fails .. " NG")
	os.exit(1)
end
