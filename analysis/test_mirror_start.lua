-- キャラ選択のミラーは Start を渡す。Coin は渡さない。
--
-- P1 が決定したあと、同じスティックで P2 を選べるようにミラーが動く。方向と
-- 攻撃 6 つだけを渡しており、Start は「決定が暴発する」として除外されていた。
--
-- その心配はこの画面では当たらない (本人、2026-09-19)。ミラーは上の Wait が
-- 終わるまで動き出さないので、制御が移る時点で Start が押しっぱなしになって
-- いることがない。ステージセレクトは Coin なので、そちらは P1 に残す。
--
-- Start を握るのは隠しキャラの選び方 (Start + PP / KK) なので、渡さないと
-- ダークガロンを P2 に選べない。
--
-- 入力名は FBNeo のドライバごとに違う。macro.lua が同じ 3 つを順に試している
-- のと同じやり方で、P1 側の名前を見つけて P2 側を導く。
--
-- ミラー全体を走らせるにはエミュレータ API 一式が要る (test_state_load_wiring
-- の注記と同じ)。Start の部分は _inp しか触らないので、そこだけ切り出して
-- 実際に動かす。
--
--   cd C:/fightcaVSAV-Debug/emulator/fbneo && lua5.1 analysis/test_mirror_start.lua
local path = "scripts/vsav_training_master_script.lua"
local fh = io.open(path)
assert(fh, path .. " が読めない")
local src = fh:read("*a") ; fh:close()

local fails = 0
local function want(what, got, w)
	if got ~= w then
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(w) .. "]")
	else
		print("  ok " .. what)
	end
end

-- Start を渡すブロックを切り出して関数にする。
local i = src:find('for _, _s in ipairs({ "1 Player Start"', 1, true)
assert(i, "Start を渡すブロックが見つからない")
local j = src:find("joypad.set(_inp)", i, true)
assert(j, "ブロックの終わりが見つからない")
local block = src:sub(i, j - 1)
local mirror = assert(loadstring("local _inp = ...\n" .. block .. "\nreturn _inp"))

print("[1] 名前の綴りが 3 通りとも通る")
for _, pair in ipairs({ { "P1 Start", "P2 Start" },
                        { "1 Player Start", "2 Player Start" },
                        { "Start 1", "Start 2" } }) do
	local p1, p2 = pair[1], pair[2]
	local inp = { [p1] = true, [p2] = false }
	mirror(inp)
	want(p1 .. " → " .. p2, inp[p2], true)
end

print("[2] 押していなければ渡らない")
do
	local inp = { ["P1 Start"] = false, ["P2 Start"] = false }
	mirror(inp)
	want("false のまま", inp["P2 Start"], false)
end

print("[3] P2 自身の Start は潰さない")
-- 方向や攻撃と同じ OR の扱い。2 本目のコントローラーも生きている。
do
	local inp = { ["P1 Start"] = false, ["P2 Start"] = true }
	mirror(inp)
	want("P2 の押しが残る", inp["P2 Start"], true)
end

print("[4] Coin は渡さない - ステージセレクトは P1 の手に残す")
do
	local inp = { ["P1 Start"] = true, ["P2 Start"] = false,
	              ["P1 Coin"] = true,  ["P2 Coin"] = false }
	mirror(inp)
	want("P2 Coin は false のまま", inp["P2 Coin"], false)
end
-- ミラー本体にも Coin への代入が無いこと。切り出した範囲の外で渡していたら
-- 上の [4] は通ってしまう。
do
	local a = src:find("Arcade stick only: mirror", 1, true)
	local b = src:find("joypad.set(_inp)", a, true)
	local body = src:sub(a, b)
	want("ミラー内で P2 Coin に代入していない",
		body:find('_inp["P2 Coin"]', 1, true) == nil, true)
end

print("[5] 名前が 1 つも無い環境で落ちない")
-- 見つからなければ何もせずに抜ける。未知のドライバでミラーごと死なせない。
do
	local inp = { ["P2 Start"] = false }
	local ok = pcall(mirror, inp)
	want("例外を出さない", ok, true)
	want("何も足さない", inp["P2 Start"], false)
end

print(fails == 0 and "REP_OK" or (fails .. " REP_NG"))
if fails ~= 0 then os.exit(1) end
