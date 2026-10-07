-- THE SETTINGS FILE MOVED TO training_data\, AND NOTHING IS LOST ON THE WAY.
--
-- scripts\settingsFile.lua, against real files in a temporary FBNeo folder
-- whose path has spaces and brackets in it. Each case loads the module afresh,
-- as a start of FBNeo would.
--
--   old only / new only / both / neither
--   a broken old or new file (and an empty one)
--   a copy that cannot be written, a save that cannot be written
--   an interrupted save (.bak left behind)
--   save, start again, read back - Action Steps and Action Patterns included
--   no training folder found
--
-- Run from the repository root, NOT scripts\: the module's last candidate for
-- the FBNeo folder is "..", and from scripts\ that is this repository - a
-- case that should find nothing would find it, and write into it.
--   lua5.1 analysis/test_settings_file.lua

package.preload["./scripts/dkjson"] = function() return dofile("scripts/dkjson.lua") end
local json = require "./scripts/dkjson"

local fails = 0
local function want(what, got, w)
	if got ~= w then
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(w) .. "]")
	else
		print("  ok " .. what)
	end
end

-- ---------------------------------------------------------------------------
-- A throwaway FBNeo folder

local TMP = assert(os.getenv("TEMP") or os.getenv("TMP"), "TEMP が無い")
local ROOT = TMP .. "\\vsav settings test (x86)"
local BASE = ROOT .. "\\Fight cade\\fbneo"
local NEW_DIR = BASE .. "\\training_data"
local NEW = NEW_DIR .. "\\training_settings.json"
local OLD = BASE .. "\\scripts\\training_settings.json"
local MASTER = BASE .. "\\scripts\\vsav_training_master_script.lua"

local function sh(cmd) os.execute(cmd .. " >nul 2>nul") end
local function rmtree(p) sh('rmdir /s /q "' .. p .. '"') end
local function mkdir(p) sh('mkdir "' .. p .. '"') end

local function put(path, text)
	local f = assert(io.open(path, "wb"))
	f:write(text)
	f:close()
end
local function get(path)
	local f = io.open(path, "rb")
	if f == nil then return nil end
	local s = f:read("*a")
	f:close()
	return s
end
local function present(path) return get(path) ~= nil end

local function fresh_tree()
	rmtree(ROOT)
	mkdir(BASE .. "\\scripts")
	put(MASTER, "-- master\n")
end

-- The module as a new start of FBNeo sees it.
local function start(master_source)
	local S = dofile("scripts/settingsFile.lua")
	S.set_master_source(master_source or ("@" .. MASTER))
	return S
end

local function same(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) ~= "table" then return a == b end
	for k, v in pairs(a) do if not same(v, b[k]) then return false end end
	for k in pairs(b) do if a[k] == nil then return false end end
	return true
end

local function shown(S, needle)
	local lines = S.error_lines()
	if lines == nil then return false end
	for _, l in ipairs(lines) do
		if l:find(needle, 1, true) then return true end
	end
	return false
end

-- An old-style file as the previous versions wrote it: CRLF, indented, with
-- Action Steps, Action Patterns and a key this version does not know.
local OLD_SETTINGS = {
	settings_version = 5,
	p2_throw_tech = 3,
	action_sequences = { ["1"] = { { action = "forward dash", wait = 12 }, { action = "LP" } } },
	action_patterns = { { name = "Short LP", enabled = true, steps = { { action = "LP" } } } },
	zz_key_from_the_future = { kept = true },
}
local OLD_TEXT = json.encode(OLD_SETTINGS, { indent = true }):gsub("\n", "\r\n")

-- ---------------------------------------------------------------------------
print("-- 配置先")
fresh_tree()
local S = start()
want("一時フォルダの配置先を見つける (リポジトリではない)", S.paths().base, BASE)
want("新しい保存先", S.paths().new, NEW)
want("旧保存先", S.paths().old, OLD)

-- ---------------------------------------------------------------------------
print("-- 両方ない: 初回")
fresh_tree()
S = start()
want("空の表", next(S.load()), nil)
want("エラーなし", S.error_lines(), nil)
want("読むだけでは何も作らない", present(NEW), false)
want("保存できる (training_data を作る)", (S.save({ a = 1, b = { "x" } })), true)
want("新しい保存先に書かれる", same(json.decode(get(NEW)), { a = 1, b = { "x" } }), true)
want("旧保存先には書かない", present(OLD), false)
want(".tmp も .bak も残らない", present(NEW .. ".tmp") or present(NEW .. ".bak"), false)

-- ---------------------------------------------------------------------------
print("-- 旧だけ: 写して、旧は残す")
fresh_tree()
put(OLD, OLD_TEXT)
S = start()
local got = S.load()
want("旧の中身を読む", same(got, OLD_SETTINGS), true)
want("エラーなし", S.error_lines(), nil)
want("新しい保存先へバイト単位で写す", get(NEW), OLD_TEXT)
want("知らないキーも落とさない", got.zz_key_from_the_future and got.zz_key_from_the_future.kept, true)
want("旧ファイルはそのまま", get(OLD), OLD_TEXT)
-- Saved, then a new start reads it back.
got.p2_throw_tech = 5
want("保存できる", (S.save(got)), true)
want("旧ファイルは更新されない", get(OLD), OLD_TEXT)
S = start()
local again = S.load()
want("再起動して読み戻せる", again.p2_throw_tech, 5)
want("Action Steps が残る", same(again.action_sequences, OLD_SETTINGS.action_sequences), true)
want("Action Patterns が残る", same(again.action_patterns, OLD_SETTINGS.action_patterns), true)
want("知らないキーも残る", again.zz_key_from_the_future and again.zz_key_from_the_future.kept, true)
want("二度目は写さない (旧は読まれない)", get(OLD), OLD_TEXT)

-- ---------------------------------------------------------------------------
print("-- 新だけ")
fresh_tree()
mkdir(NEW_DIR)
put(NEW, '{"p2_throw_tech": 2}')
S = start()
want("新を読む", S.load().p2_throw_tech, 2)
want("旧は作らない", present(OLD), false)

-- ---------------------------------------------------------------------------
print("-- 両方: 新を使い、旧は混ぜない")
fresh_tree()
mkdir(NEW_DIR)
put(NEW, '{"p2_throw_tech": 2}')
put(OLD, OLD_TEXT)
S = start()
got = S.load()
want("新の値", got.p2_throw_tech, 2)
want("旧のキーは混ざらない", got.action_sequences, nil)
want("新ファイルはそのまま", get(NEW), '{"p2_throw_tech": 2}')
want("旧ファイルはそのまま", get(OLD), OLD_TEXT)

-- ---------------------------------------------------------------------------
for _, broken in ipairs({ { "壊れた", '{"p2_throw_tech": ' }, { "空の", "" } }) do
	print("-- " .. broken[1] .. "新ファイル: エラーを出し、何も上書きしない")
	fresh_tree()
	mkdir(NEW_DIR)
	put(NEW, broken[2])
	put(OLD, OLD_TEXT)
	S = start()
	got = S.load()
	want("初期値 (空の表)", next(got), nil)
	want("旧へは切り替えない", got.action_sequences, nil)
	want("パスを表示する", shown(S, NEW), true)
	want("保存しないと表示する", shown(S, "Nothing will be saved"), true)
	want("保存は断る", (S.save({ p2_throw_tech = 1 })), false)
	want("新ファイルは元のまま", get(NEW), broken[2])
	want("旧ファイルも元のまま", get(OLD), OLD_TEXT)
end

-- ---------------------------------------------------------------------------
print("-- 壊れた旧ファイル (新はない)")
fresh_tree()
put(OLD, "not json at all")
S = start()
want("初期値 (空の表)", next(S.load()), nil)
want("旧のパスを表示する", shown(S, OLD), true)
want("新ファイルは作らない (初期値で旧を隠さない)", present(NEW), false)
want("保存は断る", (S.save({ p2_throw_tech = 1 })), false)
want("保存を断った後も新ファイルは無い", present(NEW), false)
want("旧ファイルは元のまま", get(OLD), "not json at all")

-- ---------------------------------------------------------------------------
print("-- 写せない (training_data がファイルになっている)")
fresh_tree()
put(NEW_DIR, "in the way")
put(OLD, OLD_TEXT)
S = start()
got = S.load()
want("旧の中身で動く", same(got, OLD_SETTINGS), true)
want("新しい保存先のパスを表示する", shown(S, NEW), true)
want("保存は断る", (S.save(got)), false)
want("旧ファイルは元のまま", get(OLD), OLD_TEXT)
want("邪魔なファイルも元のまま", get(NEW_DIR), "in the way")

-- ---------------------------------------------------------------------------
print("-- 保存に失敗しても前のファイルは残る")
fresh_tree()
mkdir(NEW_DIR)
put(NEW, '{"p2_throw_tech": 2}')
S = start()
S.load()
mkdir(NEW .. ".tmp")      -- a folder where the .tmp must go: the write fails
local ok, err = S.save({ p2_throw_tech = 4 })
want("保存は失敗を返す", ok, false)
want("前のファイルは元のまま (空にならない)", get(NEW), '{"p2_throw_tech": 2}')
want("パスを表示する", shown(S, NEW), true)
sh('rmdir "' .. NEW .. '.tmp"')
want("次の保存は通る", (S.save({ p2_throw_tech = 4 })), true)
want("通った後は表示が消える", S.error_lines(), nil)
want("中身が替わる", json.decode(get(NEW)).p2_throw_tech, 4)

-- ---------------------------------------------------------------------------
print("-- 途中で止まった保存 (.bak だけが残った)")
fresh_tree()
mkdir(NEW_DIR)
put(NEW .. ".bak", '{"p2_throw_tech": 3}')
put(OLD, OLD_TEXT)
S = start()
got = S.load()
want(".bak を戻して読む", got.p2_throw_tech, 3)
want("旧からは写さない", got.action_sequences, nil)
want(".bak がファイルに戻る", get(NEW), '{"p2_throw_tech": 3}')
want(".bak は残らない", present(NEW .. ".bak"), false)

-- ---------------------------------------------------------------------------
print("-- 配置先が見つからない")
fresh_tree()
S = start("@" .. ROOT .. "\\nowhere\\scripts\\vsav_training_master_script.lua")
want("見つからない", S.paths().base, nil)
want("空の表", next(S.load()), nil)
want("表示する", shown(S, "Could not find the training folder"), true)
want("保存は断る (別の場所へ黙って保存しない)", (S.save({ a = 1 })), false)

-- ---------------------------------------------------------------------------
print("-- 画面の表示")
local texts = {}
gui = { box = function() end, text = function(_, _, t) texts[#texts + 1] = t end }
emu = { screenwidth = function() return 384 end }
S.draw()
want("エラーの行を描く", #texts >= 2, true)
want("1 行は 94 字まで (画面に収める)", (function()
	for _, t in ipairs(texts) do if #t > 94 then return false end end
	return true
end)(), true)
texts = {}
fresh_tree()
S = start()
S.load()
S.draw()
want("エラーが無ければ何も描かない", #texts, 0)

-- ---------------------------------------------------------------------------
print("-- つなぎ込み")
local function slurp(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end
local master = slurp("scripts/vsav_training_master_script.lua")
want("起動時に require する",
	master:find("training_settings_store  = require './scripts/settingsFile'", 1, true) ~= nil, true)
local draws = 0
for _ in master:gmatch("training_settings_store%.draw%(%)") do draws = draws + 1 end
want("選択画面と試合中の両方で表示する", draws, 2)
want("training_settings_file はもう無い", master:find("training_settings_file", 1, true), nil)
local util = slurp("scripts/utilities.lua")
want("utilities は store で読む", util:find("training_settings_store.load()", 1, true) ~= nil, true)
want("utilities は store で書く", util:find("training_settings_store.save(training_settings)", 1, true) ~= nil, true)
want("utilities に旧ファイルへの書き込みは無い", util:find("training_settings_file", 1, true), nil)
-- Nothing else in scripts\ names the file.
local others = {}
for name in io.popen([[dir /b scripts\*.lua]]):lines() do
	if name ~= "settingsFile.lua" and slurp("scripts\\" .. name):find("training_settings.json", 1, true) then
		others[#others + 1] = name
	end
end
want("ほかのスクリプトは設定ファイル名を持たない", table.concat(others, ","), "")

rmtree(ROOT)
if fails == 0 then
	print("test_settings_file ok")
else
	print(fails .. " 件 NG")
	os.exit(1)
end
