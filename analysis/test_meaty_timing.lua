-- MEATY TIMING (scripts/meatyTiming.lua), fed the way framedata.lua feeds it:
-- each tick's snapshot goes to the real tickData.lua first, then to Meaty
-- Timing with tickData.currentRun().
--
-- The snapshots are built by a small model of one recovery and one attack:
--   the defender is put into recovery on tick E (a guard, a hit, a knockdown
--   or a hit in the air), carries the marker ($04..$07 = 02 02 04 00) on the
--   tick(s) before R, and is free from R - the reversal tick;
--   the attacker's box goes out in runs; each contact raises the defender's
--   hitstop and stops the attacker's animation for 8 ticks, unless the move is
--   one that plays through hitstop (anime).
--
-- Run from the package root.
--   lua5.1 analysis/test_meaty_timing.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
local td = require "scripts/tickData"
local mt = dofile("scripts/meatyTiming.lua")

local fails = 0
local function want(what, got, w)
	if got ~= w then
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(w) .. "]")
	else
		print("  ok " .. what)
	end
end

local FREEZE = 8

-- o.kind      "down" / "guard" / "hit" / "air": what put the defender in recovery
-- o.E, o.R    that tick, and the reversal tick
-- o.marker    how many ticks the marker lasts (1)
-- o.runs      the attacker's box: { {from, to}, ... }
-- o.attack    { from, to } the attack flag ($105)
-- o.contacts  { {tick, "hit"/"block"/"throw"}, ... }
-- o.body      false: the box is a projectile's
-- o.anime     the move plays through hitstop
-- o.first, o.last  ticks fed (o.first > 1: measuring switched on late)
-- o.skip      a tick that is not fed (ticks missed)
local function model(o)
	local mlen = o.marker or 1
	local snaps = {}
	for t = o.first or 1, o.last or (o.R + 40) do
		local d = { status = 0, state = 0, block_clock = 0, hitstop = 0, knockdown = false,
			marker = false, airborne = false }
		if t >= o.E and t < o.R then d.status = 2 end
		if t >= o.R - mlen and t < o.R then d.marker = true end
		if o.kind == "down" and t > o.E and t < o.R - mlen then d.knockdown = true end
		if o.kind == "air" and t >= o.E and t <= o.R then d.airborne = true end
		local function rise(at, peak, field)
			if t >= at then d[field] = math.max(d[field], peak - (t - at)) end
		end
		rise(o.E, FREEZE, "hitstop")
		if o.kind == "guard" then rise(o.E, 20, "block_clock") end
		local frozen, p1_hf = false, false
		for _, c in ipairs(o.contacts or {}) do
			local at, kind = c[1], c[2]
			rise(at, 10, "hitstop")
			if kind == "block" then rise(at, 15, "block_clock") end
			if t >= at and kind == "hit" then d.status = 2 end
			if t >= at and kind == "throw" then d.status = 6 end
			if t >= at and t <= at + FREEZE then p1_hf = true end
			if t > at and t <= at + FREEZE and not o.anime then frozen = true end
		end
		local box, id = false, 0
		for i, r in ipairs(o.runs or {}) do
			if t >= r[1] and t <= r[2] then box, id = true, i end
		end
		local a = o.attack or { 0, -1 }
		snaps[#snaps + 1] = { t = t, d = d, box = box, id = id, frozen = frozen, p1_hf = p1_hf,
			attacking = t >= a[1] and t <= a[2] }
	end
	-- The animation counter: one step a tick unless frozen.
	local anim = 1000
	local out = {}
	for _, s in ipairs(snaps) do
		if not s.frozen then anim = anim + 1 end
		if s.t ~= o.skip then
			out[#out + 1] = {
				tick = s.t,
				p1 = { attack = s.attacking and 1 or 0, status = 0, hitfreeze = s.p1_hf,
					attack_box = s.box, attack_box_id = s.id,
					body_box = s.box and o.body ~= false, anim = anim, cel = 0x100000 },
				p2 = s.d,
			}
			out[#out].p2.hitfreeze = s.d.hitstop ~= 0
		end
	end
	return out
end

local function run(o)
	td.reset("test", true)
	if not o.keep then mt.reset("test", true) end
	for _, s in ipairs(model(o)) do
		td.update(s)
		mt.update(s, td.currentRun())
	end
	return mt.formatResult()
end

-- ---------------------------------------------------------------------------
print("-- 状況と Reversal の数え方")
want("起き上がりに重ね: 同じ Tick は +0t",
	run({ kind = "down", E = 5, R = 60, attack = { 54, 80 }, runs = { { 58, 62 } }, contacts = { { 60, "hit" } } }),
	"Wake-up  Reversal +0t  Active 3t")
want("ガード後: +4t",
	run({ kind = "guard", E = 5, R = 30, attack = { 28, 50 }, runs = { { 33, 36 } }, contacts = { { 34, "block" } } }),
	"After Guard  Reversal +4t  Active 2t")
want("ヒット後: After Hit",
	run({ kind = "hit", E = 5, R = 30, attack = { 25, 50 }, runs = { { 30, 33 } }, contacts = { { 32, "hit" } } }),
	"After Hit  Reversal +2t  Active 3t")
want("空中で復帰: Air Recovery",
	run({ kind = "air", E = 5, R = 30, attack = { 25, 50 }, runs = { { 31, 33 } }, contacts = { { 31, "hit" } } }),
	"Air Recovery  Reversal +1t  Active 1t")

print("-- 0 から 30 Tick まで")
local function at(d)
	return run({ kind = "guard", E = 5, R = 30, attack = { 25, 30 + d + 5 },
		runs = { { 30 + d, 30 + d + 3 } }, contacts = { { 30 + d, "block" } }, last = 30 + d + 20 })
end
want("+1t", at(1), "After Guard  Reversal +1t  Active 1t")
want("+30t は採る", at(30), "After Guard  Reversal +30t  Active 1t")
want("+31t は採らない", at(31), "")

print("-- 復帰前の接触は +0t にしない")
-- A blockstring: the second hit lands while the first one's stun is still on.
-- Nothing is recorded for it; the recovery after it is the one measured.
want("硬直中の接触だけなら何も出ない",
	run({ kind = "guard", E = 5, R = 30, attack = { 20, 40 }, runs = { { 26, 28 } },
		contacts = { { 27, "block" } }, last = 29 }),
	"")
-- The marker tick itself: a contact there takes the marker off with it, so the
-- model's defender shows no marker on that tick and stays in stun.
do
	local o = { kind = "guard", E = 5, R = 30, attack = { 20, 40 }, runs = { { 28, 31 } },
		contacts = { { 29, "block" } } }
	local snaps = model(o)
	for _, s in ipairs(snaps) do
		if s.tick == 29 then s.p2.marker = false end
		if s.tick >= 29 then s.p2.status = 2 end
	end
	td.reset("test", true) mt.reset("test", true)
	for _, s in ipairs(snaps) do td.update(s) mt.update(s, td.currentRun()) end
	want("目印の Tick の接触: 採らない", mt.formatResult(), "")
end

print("-- ヒット / ガード / 空振り")
want("空振りでは何も出ない",
	run({ kind = "guard", E = 5, R = 30, attack = { 28, 40 }, runs = { { 31, 33 } } }), "")
run({ kind = "guard", E = 5, R = 30, attack = { 28, 40 }, runs = { { 31, 33 } }, contacts = { { 32, "block" } } })
want("前の結果は空振りの後も残る",
	run({ kind = "guard", E = 5, R = 30, attack = { 28, 40 }, runs = { { 31, 33 } }, keep = true }),
	"After Guard  Reversal +2t  Active 2t")
want("範囲外の接触の後も残る",
	run({ kind = "guard", E = 5, R = 30, attack = { 60, 70 }, runs = { { 62, 64 } },
		contacts = { { 63, "block" } }, last = 80, keep = true }),
	"After Guard  Reversal +2t  Active 2t")

print("-- 持続の何 Tick 目か")
want("持続の始めに当たる", run({ kind = "down", E = 5, R = 60, attack = { 50, 80 },
	runs = { { 60, 65 } }, contacts = { { 60, "hit" } } }), "Wake-up  Reversal +0t  Active 1t")
want("持続の後半に当たる", run({ kind = "down", E = 5, R = 60, attack = { 50, 80 },
	runs = { { 55, 65 } }, contacts = { { 60, "hit" } } }), "Wake-up  Reversal +0t  Active 6t")

print("-- 多段技は最初の接触だけ")
want("2 回目のヒットで上書きしない",
	run({ kind = "guard", E = 5, R = 30, attack = { 28, 60 }, runs = { { 31, 33 }, { 45, 47 } },
		contacts = { { 32, "block" }, { 46, "block" } } }),
	"After Guard  Reversal +2t  Active 2t")

print("-- ヒットストップ")
-- Run 1 is blocked during the stun (not recorded) and the attacker freezes;
-- run 2 meets the reversal tick. The frozen box ticks are not counted.
local function second_run(anime)
	return run({ kind = "guard", E = 5, R = 40, attack = { 20, 70 }, anime = anime,
		runs = { { 22, 26 }, { 37, 45 } }, contacts = { { 23, "block" }, { 41, "block" } } })
end
want("第 2 区間の 5 Tick 目", second_run(false), "After Guard  Reversal +1t  Active 2:5t")
do
	-- One run straight through a freeze: the 8 frozen ticks are not counted,
	-- unless the move plays through hitstop.
	local function through(anime)
		return run({ kind = "guard", E = 5, R = 40, attack = { 20, 70 }, anime = anime,
			runs = { { 30, 45 } }, contacts = { { 31, "block" }, { 41, "block" } } })
	end
	want("止まっていた Tick は数えない", through(false), "After Guard  Reversal +1t  Active 4t")
	want("ヒットストップ中も動く技は数える", through(true), "After Guard  Reversal +1t  Active 12t")
end

print("-- 飛び道具・投げ・攻撃元の分からない接触")
-- The attack is still running when the projectile lands, so Tick Data has a
-- run open for its box: the active tick must still not be read off it.
want("飛び道具: Active -", run({ kind = "guard", E = 5, R = 30, attack = { 20, 45 }, body = false,
	runs = { { 28, 40 } }, contacts = { { 33, "block" } } }), "After Guard  Reversal +3t  Active -")
want("投げ: Active -", run({ kind = "hit", E = 5, R = 30, attack = { 30, 50 },
	runs = {}, contacts = { { 31, "throw" } } }), "After Hit  Reversal +1t  Active -")
want("箱が無い接触は採らない", run({ kind = "guard", E = 5, R = 30, attack = { 28, 40 },
	runs = { { 31, 32 } }, contacts = { { 35, "block" } } }), "")

print("-- 新しい復帰で測り直す")
run({ kind = "guard", E = 5, R = 30, attack = { 28, 40 }, runs = { { 31, 33 } }, contacts = { { 32, "block" } } })
want("次の復帰の結果に替わる",
	run({ kind = "down", E = 5, R = 60, attack = { 50, 80 }, runs = { { 58, 62 } },
		contacts = { { 61, "hit" } }, keep = true }),
	"Wake-up  Reversal +1t  Active 4t")

print("-- リセットと途中 ON")
mt.reset("savestate_load", true)
want("リセットで消える", mt.formatResult(), "")
want("復帰の途中から測り始めた分は推定しない",
	run({ kind = "down", E = 5, R = 60, first = 40, attack = { 50, 80 }, runs = { { 58, 62 } },
		contacts = { { 60, "hit" } } }), "")
want("Tick が飛んだら、その復帰は測らない (リバーサル Tick と接触の間)",
	run({ kind = "down", E = 5, R = 60, skip = 61, attack = { 50, 80 }, runs = { { 58, 66 } },
		contacts = { { 64, "hit" } } }), "")

print("-- 目印が 2 Tick 続いた場合")
want("消えた Tick ちょうどの接触は採らない (復帰前と区別できない)",
	run({ kind = "guard", E = 5, R = 30, marker = 2, attack = { 25, 40 }, runs = { { 28, 33 } },
		contacts = { { 30, "block" } } }), "")
want("接触が後なら採る",
	run({ kind = "guard", E = 5, R = 30, marker = 2, attack = { 25, 40 }, runs = { { 31, 33 } },
		contacts = { { 32, "block" } } }), "After Guard  Reversal +2t  Active 2t")

-- ---------------------------------------------------------------------------
print("-- つなぎ込み")
local function slurp(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end
local cfg = dofile("scripts/config.lua").default_training_settings
want("初期値は ON", cfg.display_meaty_timing, true)
local menu = slurp("scripts/menu.lua")
local a = menu:find('"Tick Data Side"', 1, true)
local b = menu:find('"Show Meaty Timing", training_settings, "display_meaty_timing", true,', 1, true)
local c = menu:find('"Show Action Timeline"', 1, true)
want("メニューの並び: Tick Data Side → Meaty → Action Timeline", a ~= nil and b ~= nil and c ~= nil and a < b and b < c, true)
local hud = slurp("scripts/hud.lua")
local h1 = hud:find("globals.last_fd ~= nil", 1, true)
local h2 = hud:find("globals.last_meaty ~= nil", 1, true)
local h3 = hud:find("globals.last_route ~= nil", 1, true)
want("画面の並び: Tick Data → Meaty → Action Timeline", h1 ~= nil and h2 ~= nil and h3 ~= nil and h1 < h2 and h2 < h3, true)
want("空なら行を取らない", hud:find('globals.last_meaty ~= nil and globals.last_meaty ~= ""', 1, true) ~= nil, true)
local fd = slurp("scripts/framedata.lua")
local resets = 0
for _ in fd:gmatch("meatyTiming%.reset%(") do resets = resets + 1 end
want("Tick Data と同じ場面で消す (無効・メニュー・試合外・側の変更・起動・ロード・OFF)", resets, 7)
want("P2 のときは P2 と付ける", fd:find('if meaty ~= "" then meaty = "P2  " .. meaty end', 1, true) ~= nil, true)
-- Saved settings: missing key -> the default (on); a saved off stays off.
do
	package.preload["./scripts/dkjson"] = function() return {} end
	local saved
	training_settings_store = { load = function() return saved end, save = function() return true end }
	dofile("scripts/utilities.lua")
	saved = { settings_version = 5 }
	training_settings = dofile("scripts/config.lua").default_training_settings
	load_training_data()
	want("旧設定に項目が無ければ ON", training_settings.display_meaty_timing, true)
	saved = { settings_version = 5, display_meaty_timing = false }
	training_settings = dofile("scripts/config.lua").default_training_settings
	load_training_data()
	want("保存した OFF は OFF のまま", training_settings.display_meaty_timing, false)
end

if fails == 0 then
	print("test_meaty_timing ok")
else
	print(fails .. " 件 NG")
	os.exit(1)
end
