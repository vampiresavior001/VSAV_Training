-- TECH THROWS IS A RATE, AND THE ROLL HAPPENS ONCE PER THROW.
--
-- registerBefore runs every frame the dummy is in "Be Thrown" and the escape
-- lands if the input is present on ANY of them, so a roll placed there turns
-- every setting into ~100%. Guard Action Frequency shipped with exactly that
-- bug. This pins the latch, the five rates, the shipped default and the
-- migration off the old checkbox.
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_throw_tech.lua

local fails = 0
local function want(what, got, w)
	if got ~= w then
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(w) .. "]")
	else
		print("  ok " .. what)
	end
end

-- ---------------------------------------------------------------- the roll --
globals = { dummy = { p2_status_1 = "", p2_away_btn = "P2 Left" }, options = {} }
local T = dofile("throwTech.lua")

-- math.random is the only source of chance here, so counting the calls is how
-- "once per throw" is checked.
local rolls = 0
local next_roll = 0
local real_random = math.random
math.random = function() rolls = rolls + 1 return next_roll end

local function frames(n, status)
	local keys = {}
	for _ = 1, n do
		globals.dummy.p2_status_1 = status
		T.registerBefore(keys)
	end
	return keys
end

local function pressed(keys)
	return keys["P2 Medium Punch"] == true and keys["P2 Left"] == true
end

print("[1] 1 回の投げにつき 1 回だけ振る")
globals.options.p2_throw_tech = 3      -- 50%
rolls = 0
next_roll = 0.9                        -- 90 >= 50 -> 抜けない
local k = frames(40, "Be Thrown")
want("外れたら抜けない", pressed(k), false)
want("40 フレームで 1 回しか振らない", rolls, 1)

print("\n[2] 投げが終われば次はまた振る")
frames(1, "")                          -- 状態を抜ける
rolls = 0
next_roll = 0.1                        -- 10 < 50 -> 抜ける
k = frames(40, "Be Thrown")
want("当たれば抜ける", pressed(k), true)
want("ここでも 1 回だけ", rolls, 1)

print("\n[3] 当たった投げの間はずっと押し続ける")
-- 抜け入力は 1 フレームでは通らないことがある。ラッチしているので、当たりの
-- 判定はその投げのあいだ保たれる。
local keys = {}
globals.dummy.p2_status_1 = "Be Thrown"
T.registerBefore(keys)
local still = {}
for _ = 1, 20 do
	still = {}
	globals.dummy.p2_status_1 = "Be Thrown"
	T.registerBefore(still)
end
want("20 フレーム後も押している", pressed(still), true)

print("\n[4] 端の 2 つは運に触らない")
frames(1, "")
globals.options.p2_throw_tech = 5      -- 100%
rolls = 0
want("100% は必ず抜ける", pressed(frames(10, "Be Thrown")), true)
want("100% は振らない", rolls, 0)
frames(1, "")
globals.options.p2_throw_tech = 1      -- None
rolls = 0
want("None は抜けない", pressed(frames(10, "Be Thrown")), false)
want("None も振らない", rolls, 0)

print("\n[5] 表示どおりの確率")
-- 25% は 24.9 で当たり 25.1 で外れる。ここがずれると、行の文字と実際の割合が
-- 食い違う - 他の 2 行が 35/65 で出していた不一致と同じ形。
local function fires_at(idx, roll)
	frames(1, "")
	globals.options.p2_throw_tech = idx
	next_roll = roll / 100
	return pressed(frames(3, "Be Thrown"))
end
want("25% は 24.9 で通る", fires_at(2, 24.9), true)
want("25% は 25.1 で落ちる", fires_at(2, 25.1), false)
want("50% は 49.9 で通る", fires_at(3, 49.9), true)
want("50% は 50.1 で落ちる", fires_at(3, 50.1), false)
want("75% は 74.9 で通る", fires_at(4, 74.9), true)
want("75% は 75.1 で落ちる", fires_at(4, 75.1), false)
math.random = real_random

-- ------------------------------------------------------------ 行と既定値と --
print("\n[6] メニュー行と出荷値")
package.preload["./scripts/charMoves"] = function()
	return { get_player_movelists = function()
		return { P1 = { reversal_names = { "Stub" } }, P2 = { reversal_names = { "Stub" } } }
	end }
end
package.preload["./scripts/actionSequenceEditor"] = function()
	return dofile("actionSequenceEditor.lua")
end
package.preload["./scripts/actionSequenceRunner"] = function()
	return dofile("actionSequenceRunner.lua")
end
package.preload["./scripts/position"] = function()
	return dofile("position.lua")
end
training_settings = {}
memory = { readbyte = function() return 0 end }
gui = { text = function() end, box = function() end }
dofile("menu.lua")
menuModule.guiRegister()

local row
for _, tab in ipairs(menu) do
	if tab.name == "Dummy" then
		for _, e in ipairs(tab.entries) do
			if e.name == "Tech Throws" then row = e end
		end
	end
end
want("行がある", row ~= nil, true)
want("チェックボックスではなくリスト", row ~= nil and row.list ~= nil, true)
want("同一画面の他と同じ 5 つ",
	row ~= nil and row.list ~= nil and table.concat(row.list, ","),
	"None,25%,50%,75%,100%")
-- 他の 2 行と同じ既定。旧チェックボックスが on だったのと同じ意味。
want("MP リセットは 100%", row ~= nil and row.default_value, 5)

local shipped = dofile("config.lua").default_training_settings
want("出荷値も 100%", shipped.p2_throw_tech, 5)
-- 移行を足すたびに上がる。ここは「Tech Throws の移行より後の版である」こと
-- だけを見る - 版を直書きすると、次の移行で無関係なテストが落ちる。
want("設定版は 4 以上", shipped.settings_version >= 4, true)

-- -------------------------------------------------------------- 移行 --------
print("\n[7] 旧チェックボックスからの移行")
-- 真偽値のまま list_menu_item へ渡ると left() が true - 1 を計算して落ちる。
local saved = {}
-- scripts/ から走らせているので、utilities.lua の require './scripts/dkjson'
-- は解決できない。JSON は使わない - ファイルの中身は下で直接渡す。
package.preload["./scripts/dkjson"] = function() return {} end
dofile("utilities.lua")
-- 差し替えは dofile の後。read_object_from_json_file は utilities.lua が
-- 定義するグローバルなので、先に置くと上書きされる。
read_object_from_json_file = function() return saved end
write_object_to_json_file = function() return true end

local function migrated(file_table)
	saved = file_table
	training_settings = { p2_throw_tech = 5, settings_version = 4 }
	load_training_data()
	return training_settings.p2_throw_tech, training_settings.settings_version
end
local v, ver = migrated({ p2_throw_tech = true })
want("true は 100%", v, 5)
want("版も上がる", ver >= 4, true)
want("false は None", (migrated({ p2_throw_tech = false })), 1)
want("数字はそのまま", (migrated({ p2_throw_tech = 3, settings_version = 4 })), 3)
-- 版が上がったあとに保存された false は本物の None なので触らない。
want("移行済みの 1 も残る", (migrated({ p2_throw_tech = 1, settings_version = 4 })), 1)

if fails == 0 then print("\n全て通った") else print("\n" .. fails .. " 件 NG") os.exit(1) end
