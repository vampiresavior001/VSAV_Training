-- THE SHADOW GUIDE (scripts/shadowGuide.lua, v11.7.28).
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_shadow_guide.lua
--
--   [1] the shapes (analysis/gen_shadow_bounds.py): 54, ellipses centred on
--       their origin, and the columns for either facing
--   [2] the sample: the cel's shape and offset, the facing, the air; none
--       when the game draws none
--   [3] the words: Both, then Standing, then Crouching, else No UBK, ends in
--   [4] the line: the front pixel of your shadow is on it exactly when the
--       distance is in a range, and on the run of that kind - every distance,
--       both sides; walking moves the shadow, not the line
--   [5] the rows: Q-Bee's two (no green), Gallon's one, none for Morrigan, none
--       in the air or with no shadow
--   [6] the check at 01BD96: a part written where it was worked out reads 0
--   [7] the hook-up: master, cps2-hitboxes, hud, menu, config, archive
local fails = 0
local function eq(what, got, want)
	if got == want then print("  ok " .. what .. " = " .. tostring(got))
	else
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(want) .. "]")
	end
end
local function slurp(p)
	local fh = io.open(p)
	assert(fh, p .. " が読めない")
	local s = fh:read("*a")
	fh:close()
	return s
end

local ram, regs, hooks = {}, {}, {}
local function byte(a) return ram[a] or 0 end
local function word(a) return byte(a) * 256 + byte(a + 1) end
local function signed(v, bits) if v >= 2 ^ (bits - 1) then return v - 2 ^ bits end return v end
memory = {
	readbyte = byte,
	readbytesigned = function(a) return signed(byte(a), 8) end,
	readword = word,
	readwordsigned = function(a) return signed(word(a), 16) end,
	readdword = function(a) return word(a) * 65536 + word(a + 2) end,
	getregister = function(n) return regs[n:gsub("^m68000%.", "")] or 0 end,
	registerexec = function(pc, fn) hooks[pc] = fn end,
}
local function setw(a, v) v = v % 65536 ; ram[a] = math.floor(v / 256) ; ram[a + 1] = v % 256 end
local function setd(a, v) setw(a, math.floor(v / 65536)) ; setw(a + 2, v % 65536) end
local frame = 0
emu = { framecount = function() return frame end }
globals = { options = { knockdown_logger_enable = false } }

local S = dofile("shadowGuide.lua")

-- ---------------------------------------------------------------------------
print("[1] 影の形: 54 種、中心から左右対称の楕円 (41 だけ 1 ずれる)")
do
	local n = 0
	for _ in pairs(S.SHAPES) do n = n + 1 end
	eq("54 種", n, 54)
	local rule = true
	for i = 2, 40 do local s = S.SHAPES[i] ; if s[1] ~= -(23 + i) or s[2] ~= 23 + i then rule = false end end
	eq("2〜40 は半幅 23 + 番号", rule, true)
	eq("ビシャモンの 23 は 92 ピクセル (配置枠 112 ではない)", S.SHAPES[23][2] - S.SHAPES[23][1], 92)
	eq("41 は [-67, 68)", S.SHAPES[41][1] .. "," .. S.SHAPES[41][2], "-67,68")
	local L, R = S.columns(41, true)
	eq("向きが逆なら [-R, -L)", L .. "," .. R, "-68,67")
	L, R = S.columns(23, false)
	eq("  向きがそのままなら [L, R)", L .. "," .. R, "-46,46")
	eq("番号の無い形は nil", S.columns(0, false), nil)
end

-- ---------------------------------------------------------------------------
print("[2] サンプル: セルの形と横補正、向き、空中")
local P1, CEL = 0xFF8400, 0x1C664A
local function player(n, dx, flipped, y14, y3a)
	ram[P1], ram[P1 + 1] = 1, 1
	setd(P1 + 0x1C, CEL)
	ram[CEL + 0x11], ram[CEL + 0x15] = n, dx % 256
	ram[P1 + 0x0B] = flipped and 1 or 0
	setw(P1 + 0x14, y14 or 40) ; setw(P1 + 0x3A, y3a or 40)
end
do
	player(23, 2, false)
	ram[P1 + 0x05], ram[P1 + 0x06], ram[P1 + 0x105] = 0, 0, 0
	local s = S.sample(P1, 150, 200)
	eq("形 23、x は pos_x + 2", s and (s.n .. " / " .. s.x), "23 / 152")
	eq("  地上", s and s.air, false)
	eq("  立っている ($05 0、$06 0、$105 0)", s and s.stand, true)
	ram[P1 + 0x06] = 0x0E
	eq("  技 ($06 0E): 立っていない", S.sample(P1, 150, 200).stand, false)
	ram[P1 + 0x06], ram[P1 + 0x105] = 0, 1
	eq("  攻撃中 ($105 1): 立っていない", S.sample(P1, 150, 200).stand, false)
	ram[P1 + 0x105] = 0
	player(23, 2, true)
	s = S.sample(P1, 150, 200)
	eq("向きが逆なら横補正も逆 (148)", s and s.x, 148)
	player(23, -3, true)
	eq("負の補正も (153)", S.sample(P1, 150, 200).x, 153)
	player(23, 0, false, 70, 40)
	eq("$14 が $3A でなければ空中", S.sample(P1, 150, 200).air, true)
	player(0, 0, false)
	eq("形 0 は影なし", S.sample(P1, 150, 200), nil)
	player(23, 0, false) ; ram[P1 + 1] = 0
	eq("$01 が 0 なら描かない", S.sample(P1, 150, 200), nil)
end

-- ---------------------------------------------------------------------------
print("[3] 文字: Both、Standing、Crouching の順、なければ No UBK。端も入る")
local AU = { standingDist = { startDist = 74, endDist = 88 }, crouchingDist = { startDist = 74, endDist = 90 },
             overlapRange = { startDist = 74, endDist = 88 } }
local QB = { standingDist = { startDist = 85, endDist = 109 }, crouchingDist = { startDist = 85, endDist = 91 },
             overlapRange = { startDist = nil, endDist = nil } }
local GA = { standingDist = { startDist = nil, endDist = nil }, crouchingDist = { startDist = 77, endDist = 98 },
             overlapRange = { startDist = nil, endDist = nil } }
local MO = { standingDist = { startDist = nil, endDist = nil }, crouchingDist = { startDist = nil, endDist = nil },
             overlapRange = { startDist = nil, endDist = nil } }
do
	local got = {}
	for _, d in ipairs({ 73, 74, 88, 89, 90, 91 }) do got[#got + 1] = d .. "=" .. S.classify(d, AU) end
	eq("オルバス 73〜91", table.concat(got, " "), "73=none 74=both 88=both 89=crouching 90=crouching 91=none")
	eq("Q-Bee 90 は Standing (重なりが無い: 立ちを先に)", S.classify(90, QB), "standing")
	eq("モリガンは常に No UBK", S.classify(80, MO), "none")
	eq("文字", S.WORD.both .. "/" .. S.WORD.standing .. "/" .. S.WORD.crouching .. "/" .. S.WORD.none,
	   "Both/Standing/Crouching/No UBK")
end

-- ---------------------------------------------------------------------------
print("[4] 線: 影の前の端が線の上にあるのは、間合いが範囲にあるときだけ (左右とも、全距離)")
-- A pair from a distance and a side: P1's push box 40 wide, its shadow shape
-- 23 at the box centre + 2 (Bishamon's first cel), the opponent's box 50 wide.
local function pair(d, p1_left, flipped)
	if p1_left then
		local p1 = { push_l = 100, push_r = 140, shadow = { n = 23, x = 122, y = 180, flipped = flipped or false, air = false, stand = true } }
		return p1, { push_l = 140 + d, push_r = 190 + d }
	end
	local p1 = { push_l = 300, push_r = 340, shadow = { n = 23, x = 318, y = 180, flipped = flipped or true, air = false, stand = true } }
	return p1, { push_l = 250 - d, push_r = 300 - d }
end
local function front(p1, left)
	local L, R = S.columns(p1.shadow.n, p1.shadow.flipped)
	return left and (p1.shadow.x + R - 1) or (p1.shadow.x + L)
end
local function run_at(plan, x)
	for _, row in ipairs(plan.rows) do
		for _, r in ipairs(row.runs) do if x >= r[1] and x <= r[2] then return r[3] end end
	end
	return "none"
end
do
	for _, left in ipairs({ true, false }) do
		local ok, checked = true, 0
		for d = 50, 120 do
			local p1, p2 = pair(d, left)
			local plan = S.plan(p1, p2, AU)
			local want = S.classify(d, AU)
			local got = run_at(plan, front(p1, left))
			if plan.d ~= d or got ~= want then ok = false print("    d " .. d .. ": " .. got .. " / " .. want) end
			checked = checked + 1
		end
		eq((left and "P1 が左" or "P1 が右") .. ": 前の端の上の色 = 文字 (" .. checked .. " 通り)", ok, true)
	end
	-- Walking: the shadow and the box move together, the line stays.
	local p1, p2 = pair(100, true)
	local a = S.plan(p1, p2, AU)
	p1.push_l, p1.push_r, p1.shadow.x = p1.push_l + 15, p1.push_r + 15, p1.shadow.x + 15
	local b = S.plan(p1, p2, AU)
	eq("15 歩いても線は動かない", a.x_min .. "-" .. a.x_max .. " / " .. b.x_min .. "-" .. b.x_max, "177-193 / 177-193")
	eq("  距離は 100 -> 85", a.d .. " -> " .. b.d, "100 -> 85")
	eq("  run: both 179-193、crouching 177-178 (前の端 167 + 100 - t)", a.rows[1].runs[1][1] .. "-" .. a.rows[1].runs[1][2] .. " " .. a.rows[1].runs[1][3]
	   .. ", " .. a.rows[1].runs[2][1] .. "-" .. a.rows[1].runs[2][2] .. " " .. a.rows[1].runs[2][3],
	   "179-193 both, 177-178 crouching")
	eq("  線は影の真ん中の行 (y 180。下端の下は Frame Meter に隠れる)", a.rows[1].y, 180)
	eq("  範囲外: class none", a.class, "none")
	eq("  範囲内: class both", b.class, "both")
	-- An attack: the cel moves the shadow 9 forward and the box 5 - the line
	-- keeps where it was while standing, and the stand after it takes over.
	S.reset()
	p1, p2 = pair(85, true)
	local stand = S.plan(p1, p2, AU)
	p1.shadow.stand = false
	p1.shadow.x, p1.push_r = p1.shadow.x + 9, p1.push_r + 5
	local hit = S.plan(p1, p2, AU)
	eq("技の間: 影と判定が動いても線は止まる", hit.x_min .. "-" .. hit.x_max, stand.x_min .. "-" .. stand.x_max)
	eq("  文字はこのフレームの距離 (85 -> 80)", stand.d .. " -> " .. hit.d, "85 -> 80")
	p1.shadow.stand = true
	local back = S.plan(p1, p2, AU)
	eq("  立ちに戻れば、その時のずれで出し直す (4 前へ)", back.x_min - stand.x_min, 4)
	-- The opponent moving still moves it.
	S.reset()
	p1, p2 = pair(85, true)
	local c = S.plan(p1, p2, AU)
	p1.shadow.stand = false
	p2.push_l, p2.push_r = p2.push_l + 6, p2.push_r + 6
	local e = S.plan(p1, p2, AU)
	eq("  相手が 6 下がれば、技の間でも線は 6 動く", e.x_min - c.x_min, 6)
	-- Both sides: the same with you on the right.
	S.reset()
	p1, p2 = pair(85, false)
	stand = S.plan(p1, p2, AU)
	p1.shadow.stand = false
	p1.shadow.x, p1.push_l = p1.shadow.x - 9, p1.push_l - 5
	hit = S.plan(p1, p2, AU)
	eq("  自分が右でも止まる", hit.x_min .. "-" .. hit.x_max, stand.x_min .. "-" .. stand.x_max)
	S.reset()
end

-- ---------------------------------------------------------------------------
print("[5] 行: Q-Bee は 2 行 (緑なし)、ガロンは 1 行、モリガン・空中・影なしは描かない")
do
	local p1, p2 = pair(95, true)
	local q = S.plan(p1, p2, QB)
	local kinds = {}
	for i, row in ipairs(q.rows) do
		for _, r in ipairs(row.runs) do kinds[#kinds + 1] = i .. ":" .. r[3] end
	end
	eq("Q-Bee: 上が立ち、下がしゃがみ", table.concat(kinds, " "), "1:standing 2:crouching")
	eq("  2 行は真ん中の 1 上と 1 下", q.rows[1].y .. "/" .. q.rows[2].y, "179/181")
	local g = S.plan(p1, p2, GA)
	eq("ガロン: しゃがみの 1 行", #g.rows == 1 and g.rows[1].runs[1][3], "crouching")
	eq("モリガン: 描かない", S.plan(p1, p2, MO), nil)
	p1.shadow.air = true
	eq("自分が空中: 描かない", S.plan(p1, p2, AU), nil)
	p1.shadow.air = false
	p2.shadow = { n = 20, x = 0, y = 0, air = true }
	eq("相手が空中: 描かない", S.plan(p1, p2, AU), nil)
	p2.shadow = nil
	p1.shadow = nil
	eq("影が無い: 描かない", S.plan(p1, p2, AU), nil)
	eq("押し合い判定が無い: 描かない", S.plan({ shadow = { n = 23, x = 0, y = 0 } }, {}, AU), nil)
end

-- ---------------------------------------------------------------------------
print("[6] 01BD96 の照合: 計算どおりの位置に書いた部品は差 0")
do
	S.registerStart()
	eq("フックは 01BD96", hooks[0x01BD96] ~= nil, true)
	globals.options.knockdown_logger_enable = true
	local XY = 0x28B0EC
	setw(0xFF8290, 300)               -- camera X
	setw(P1 + 0x10, 450)              -- X
	ram[P1 + 0x08] = 1                -- no $10C
	setw(P1 + 0x24, 0)
	local function part(px, w, flipped, dx)
		player(23, dx, flipped)
		setw(XY, px) ; setw(XY + 2, -8)
		regs.a6, regs.a1 = P1, XY + 4
		local d = dx
		local x = px
		if flipped then d = -dx x = -px - w end
		regs.d0 = (450 - 300 + 0x40 + d + x) % 0x400 + 0x1000     -- priority bits above
		regs.d3 = (w / 16 - 1) * 256 + 0x16
		hooks[0x01BD96]()
	end
	part(-56, 32, false, 2)
	part(-24, 16, false, 2)
	part(-56, 32, true, 2)
	part(24, 32, true, -3)
	local c = S._counts()
	eq("向きそのまま: 差 0 が 2 部品", c["0/0/0/-"], 2)
	eq("向きが逆: 差 0 が 2 部品", c["0/0/0/f"], 2)
	globals.options.knockdown_logger_enable = false
end

-- ---------------------------------------------------------------------------
print("[7] 組み込み")
do
	local ms = slurp("vsav_training_master_script.lua")
	eq("起動時に require", ms:find('\nlocal shadowGuideModule  = require "./scripts/shadowGuide"', 1, true) ~= nil, true)
	eq("registerStart", ms:find("\tshadowGuideModule.registerStart()\n", 1, true) ~= nil, true)
	eq("registerAfter", ms:find("\tshadowGuideModule.registerAfter()\n", 1, true) ~= nil, true)
	eq("globals.shadowGuide / globals.hitboxes", ms:find("\tglobals.shadowGuide = shadowGuideModule\n", 1, true) ~= nil
	   and ms:find("\tglobals.hitboxes = cps2HitboxModule\n", 1, true) ~= nil, true)
	local hb = slurp("cps2-hitboxes.lua")
	eq("cps2-hitboxes: 箱と同じサンプルで影を読む ($3A)",
	   hb:find("obj.shadow = _sg.sample(obj.base, obj.pos_x, get_y(rws(obj.base + 0x3A)))", 1, true) ~= nil, true)
	-- Its "globals" is a local table of its own (line 25): the master's is
	-- config_globals. Read from the local one, the sample never ran.
	eq("  cps2-hitboxes の globals は自前の local", hb:find("\nlocal globals = {", 1, true) ~= nil, true)
	eq("  だから shadowGuide は config_globals から取る",
	   hb:find("local _sg = config_globals ~= nil and config_globals.shadowGuide or nil", 1, true) ~= nil
	   and hb:find("globals.shadowGuide", 1, true) == hb:find("config_globals.shadowGuide", 1, true) + 7, true)
	eq("  描くフレームの両者を base で返す", hb:find('["drawnPlayers"] = function()', 1, true) ~= nil, true)
	eq("線が出ない理由を画面に出さない (ログだけ。本人、2026-10-16)", slurp("shadowGuide.lua"):find("gui.text", 1, true), nil)
	local hud = slurp("hud.lua")
	eq("hud: 文字は classify と同じ色", hud:find("gui.text(midpt_x, midpt_y, sg.WORD[class], sg.COLOR[class])", 1, true) ~= nil, true)
	eq("  線は UBK Trainer と一緒 (自分の切り替えは無い)", hud:find("\t\tif sg ~= nil then\n", 1, true) ~= nil
	   and hud:find("bishamon_ubk_shadow_guide", 1, true) == nil
	   and hud:find("plan, why = sg.plan(drawn[0xFF8400], drawn[0xFF8800], bish_ubk_distance_object)", 1, true) ~= nil
	   and hud:find("sg.draw(plan, why, midpt_x, midpt_y + 10)", 1, true) ~= nil, true)
	local menu = slurp("menu.lua")
	-- Where it was before v11.7.28, last of the trainers (user, 2026-10-16), and
	-- no Shadow Guide row: one more row put Reset This Tab beside Seq. Command
	-- Trainer's long value.
	eq("menu: Shadow Guide の行は無い", menu:find('"Shadow Guide"', 1, true), nil)
	local hop = menu:find('checkbox_menu_item("Show Short Hop Counter (Sas)"', 1, true)
	local ubk = menu:find('checkbox_menu_item("Show Bishamon UBK Trainer"', 1, true)
	local rst = menu:find('reset_tab_item("Trainer")', 1, true)
	eq("menu: Show Short Hop Counter (Sas) の次、Reset This Tab の前", hop ~= nil and ubk ~= nil and rst ~= nil
	   and hop < ubk and ubk < rst and not menu:sub(hop + 10, ubk - 1):find("_menu_item(", 1, true)
	   and not menu:sub(ubk + 10, rst - 1):find("_menu_item(", 1, true), true)
	eq("config: Shadow Guide の設定は無い", dofile("config.lua").default_training_settings.bishamon_ubk_shadow_guide, nil)
	eq("archive_logs.py が shadow_log を退避", slurp("../analysis/archive_logs.py"):find('"shadow_log.jsonl"', 1, true) ~= nil, true)
end

print(fails == 0 and "\n全て通った" or ("\n" .. fails .. " 件 NG"))
os.exit(fails == 0 and 0 or 1)
