-- WAKE-UP TOWARDS / AWAY FOLLOW THE OPPONENT (scripts/rolling.lua), 2026-11-21.
--
-- Run from scripts/ - the require below is relative.
--   cd scripts && lua5.1 ../analysis/test_rolling_toward.lua
--
-- The game rolls by the dummy's own facing: $0A > 0 is a roll the way the
-- dummy faces (0x024EB8, 0x024F2A). Towards must roll at P1 and Away from P1,
-- whichever way the dummy lies.
--
--   [1] facing P1: Towards writes +1, Away -1 (as before)
--   [2] facing away from P1: Towards writes -1, Away +1
--   [3] None writes 0 either way; nothing is written unless the dummy is down
local fails = 0
local function eq(what, got, want)
	if got == want then print("  ok " .. what .. " = " .. tostring(got))
	else
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(want) .. "]")
	end
end

local mem = {}
local written
memory = {
	readbyte = function(a) return mem[a] or 0 end,
	readword = function(a) return mem[a] or 0 end,
	writebyte = function(a, v) if a == 0xFF880A then written = v end end,
}
globals = { options = { roll_direction = 1 }, dummy = { enable_roll = true } }
local roll = assert(loadfile("rolling.lua"))()

-- dummy X, P1 X, dummy facing ($0B: 1 = right)
local function run(opt, dx, px, face, down)
	mem[0xFF8810], mem[0xFF8410], mem[0xFF880B] = dx, px, face
	globals.options.roll_direction = opt
	globals.dummy.enable_roll = (down ~= false)
	written = nil
	roll.roll()
	return written
end
local TOWARDS, AWAY, NONE = 2, 3, 1

print("[1] P1 の方を向いている")
eq("右向き・P1 が右: Towards", run(TOWARDS, 300, 500, 1), 0x01)
eq("右向き・P1 が右: Away", run(AWAY, 300, 500, 1), 0xFF)
eq("左向き・P1 が左: Towards", run(TOWARDS, 500, 300, 0), 0x01)
eq("同じ X: 向きのまま", run(TOWARDS, 400, 400, 0), 0x01)

print("[2] P1 に背を向けている")
eq("左向き・P1 が右: Towards は後ろへ", run(TOWARDS, 300, 500, 0), 0xFF)
eq("左向き・P1 が右: Away は前へ", run(AWAY, 300, 500, 0), 0x01)
eq("右向き・P1 が左: Towards は後ろへ", run(TOWARDS, 500, 300, 1), 0xFF)

print("[3] None とダウン外")
eq("None は 0", run(NONE, 300, 500, 0), 0x00)
eq("ダウンしていなければ書かない", run(TOWARDS, 300, 500, 0, false), nil)

print(fails == 0 and "\n全て通った" or ("\n" .. fails .. " 件 NG"))
os.exit(fails == 0 and 0 or 1)
