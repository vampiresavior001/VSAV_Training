-- 選べるキャラは、ダッシュの後で Not Measured にならない。
--
-- ダッシュの次の攻撃は「ダッシュが終わってから」ではなく「ダッシュの最中」に
-- 出るので、Auto は実測値に解決する。表に行が無いと解決できず、エディタは
-- Fastest (Not Measured) と出し、動きとしては黙って After に落ちて遅くなる。
--
-- 行が無かったのは 0x0B Zabel 2 / 0x12 Dark Gallon / 0x18 Oboro の 3 つ。
-- このうち**選べるのは Dark Gallon だけ** (本人、2026-09-19) なので、そこを
-- 埋めれば到達可能な範囲から Not Measured が消える。
--
-- 表は local なので読み込めない。ソースを読んで確かめる。
--   cd C:/fightcaVSAV-Debug/emulator/fbneo && lua5.1 analysis/test_dash_auto_coverage.lua
local fails = 0
local function want(what, got, w)
	if got ~= w then
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(w) .. "]")
	else
		print("  ok " .. what)
	end
end

-- 選べるキャラ。0x0B と 0x18 は選択画面に出ない。
local PICKABLE = { 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
                   0x09, 0x0A, 0x0C, 0x0D, 0x0E, 0x0F, 0x12 }

local function read(path)
	local f = io.open(path)
	assert(f, "開けない: " .. path)
	local s = f:read("*a") ; f:close() ; return s
end

-- `NAME = {` から対応する `}` までを切り出す。
local function table_body(src, name)
	local i = src:find("local " .. name .. "%s*=%s*{")
	if i == nil then return nil end
	i = src:find("{", i, true)
	local depth, j = 0, i
	while j <= #src do
		local c = src:sub(j, j)
		if c == "{" then depth = depth + 1
		elseif c == "}" then
			depth = depth - 1
			if depth == 0 then return src:sub(i, j) end
		end
		j = j + 1
	end
	return nil
end

-- 1 キャラ分の行を { f=, b=, fc=, bc= } として拾う。
local function rows_of(body)
	local out = {}
	for cid, row in body:gmatch("%[(0x%x%x)%]%s*=%s*{(.-)}") do
		local r = {}
		for k, v in row:gmatch("(%a+)%s*=%s*(%-?%d+)") do r[k] = tonumber(v) end
		out[tonumber(cid)] = r
	end
	return out
end

local floors = rows_of(table_body(read("scripts/actionSequenceRunner.lua"),
                                  "MEASURED_STEP_FLOORS"))
local arm    = rows_of(table_body(read("scripts/guardCancel.lua"),
                                  "DASH_AUTO_TICKS"))

print("[1] 選べるキャラは 4 モーションすべて実測値を持つ")
-- MEASURED_STEP_FLOORS が先に見られるので、ここが埋まっていれば Not Measured
-- には落ちない。
do
	local missing = {}
	for _, cid in ipairs(PICKABLE) do
		local r = floors[cid]
		if r == nil then
			missing[#missing + 1] = string.format("%02X(行なし)", cid)
		else
			for _, k in ipairs({ "f", "b", "fc", "bc" }) do
				if r[k] == nil then
					missing[#missing + 1] = string.format("%02X.%s", cid, k)
				end
			end
		end
	end
	want("欠けている組み合わせ", table.concat(missing, " "), "")
end

print("[2] 選べないキャラは埋めていない - 埋めたら「測った」と嘘になる")
-- 0x0B Zabel 2 と 0x18 Oboro。選択画面に出ないので測りようがない。
want("0x0B は行なし", floors[0x0B] == nil, true)
want("0x18 は行なし", floors[0x18] == nil, true)

print("[3] Dark Gallon はガロンと同じ値")
-- vsavscriptv2.lua 自身の判定が「通常ガロンとまったく同じ」と言っている。
-- KD_END_1A7 も既に同じ判断でガロンの値を入れている。
for _, k in ipairs({ "f", "b", "fc", "bc" }) do
	want("歩側 " .. k, floors[0x12] and floors[0x12][k], floors[0x02][k])
	want("アーム側 " .. k, arm[0x12] and arm[0x12][k], arm[0x02][k])
end

print("[4] 両方の表に居るか、どちらにも居ないか")
-- 片方だけに居ると、アーム側と歩側が同じキャラについて違うことを言う。
-- デミトリだけは例外で、ダッシュ攻撃そのものが存在しないため歩側に 0 が
-- 置いてある (その旨がソースに書いてある)。
do
	local odd = {}
	for _, cid in ipairs(PICKABLE) do
		local a, b = floors[cid] ~= nil, arm[cid] ~= nil
		if a ~= b and cid ~= 0x01 then
			odd[#odd + 1] = string.format("%02X", cid)
		end
	end
	want("片方にしか居ないキャラ", table.concat(odd, " "), "")
	want("デミトリは歩側だけ (例外、理由はソースに)",
		(floors[0x01] ~= nil) and (arm[0x01] == nil), true)
end

print(fails == 0 and "REP_OK" or (fails .. " REP_NG"))
if fails ~= 0 then os.exit(1) end
