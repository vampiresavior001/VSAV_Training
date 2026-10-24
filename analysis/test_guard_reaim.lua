-- ALL GUARD'S BACK RE-AIMED EVERY TICK (scripts/guardCancel.lua GA.ag_reaim,
-- scripts/autoguard.lua globals.ag_back), v11.7.32.
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_guard_reaim.lua
--
-- Logs v11.7.31_4: two jump-ins All Guard did not guard. Both times the
-- dummy's facing $0B flipped 01 -> 00 one Tick before the hit and the lever it
-- held read forward ($125 = 02) on the hit Tick - the frame's Back, by the
-- facing the frame began with.
--
--   [1] GA.ag_reaim writes Back by THIS Tick's facing: bit0 while $0B = 0,
--       bit1 while set; Down kept as the guard chose it; buttons left alone
--   [2] nothing without a decision, or with one more than a frame old
--   [3] the hook-up: autoguard leaves the decision only when it holds Back
--       and the dummy is P2; the Tick hook calls it first, before anything
--       else injects that Tick
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

local src = slurp("guardCancel.lua")
local f0 = assert(src:find("function GA.ag_reaim()", 1, true))
local e0 = assert(src:find("\nend\n", f0, true))
local ram, frame_no, wrote = {}, 100, nil
memory = { readbyte = function(a) return ram[a] or 0 end }
emu = { framecount = function() return frame_no end }
GA = {}
local function assert_input_bits(lev, btn) wrote = { lev = lev, btn = btn } end
_G.assert_input_bits = assert_input_bits
local chunk = "local GA, assert_input_bits = GA, assert_input_bits\n" .. src:sub(f0, e0 + 4) .. "\nreturn GA.ag_reaim"
local reaim = assert(loadstring(chunk))()
local FACE = 0xFF880B

-- ---------------------------------------------------------------------------
print("[1] その Tick の向きで後ろを書く")
do
	globals = { ag_back = { down = false, f = frame_no } }
	ram[FACE] = 0 ; wrote = nil ; reaim()
	eq("$0B = 0: 後ろは bit0 (0x01)", wrote and wrote.lev, 0x01)
	eq("  ボタンは触らない (0 を OR)", wrote and wrote.btn, 0)
	ram[FACE] = 1 ; wrote = nil ; reaim()
	eq("$0B = 1 (振り向いた後でも、その Tick の向き): bit1 (0x02)", wrote and wrote.lev, 0x02)
	globals.ag_back.down = true
	ram[FACE] = 0 ; wrote = nil ; reaim()
	eq("下も入れる (下後ろ 0x05)", wrote and wrote.lev, 0x05)
	ram[FACE] = 1 ; wrote = nil ; reaim()
	eq("  振り向いた後の下後ろ (0x06)", wrote and wrote.lev, 0x06)
end

-- ---------------------------------------------------------------------------
print("[2] 判断が無い、または古いときは書かない")
do
	globals = {}
	wrote = nil ; reaim()
	eq("ガードの判断が無い: 書かない", wrote, nil)
	globals = { ag_back = { down = false, f = frame_no - 1 } }
	wrote = nil ; reaim()
	eq("1 フレーム前の判断: 書く", wrote ~= nil, true)
	globals = { ag_back = { down = false, f = frame_no - 2 } }
	wrote = nil ; reaim()
	eq("2 フレーム前 (ガードの処理が回らなかった): 書かない", wrote, nil)
	globals = nil
	wrote = nil ; reaim()
	eq("globals が無い: 書かない", wrote, nil)
end

-- ---------------------------------------------------------------------------
print("[3] 組み込み")
do
	local ag = slurp("autoguard.lua")
	eq("autoguard: 後ろを入れて、ダミーが P2 のときだけ判断を残す",
	   ag:find("if _held and globals.controlling_p1 then%s+globals.ag_back = { down = cur_keys%[\"P2 Down\"%] == true, f = emu.framecount%(%) }%s+else%s+globals.ag_back = nil") ~= nil, true)
	local hook = src:match("memory%.registerexec%(0x02211A, function%(%)(.-)\nend%)")
	eq("Tick のフックがある", hook ~= nil, true)
	hook = hook or ""
	local at = hook:find("GA.ag_reaim()", 1, true)
	eq("  先頭近くで呼ぶ (kd_capture_start_07 の直後)", at ~= nil and hook:find("kd_capture_start_07%(%)%s+%-%-[^\n]*\n%s+GA%.ag_reaim%(%)") ~= nil, true)
	local first_inject = hook:find("assert_input_bits(", 1, true)
	eq("  ほかの入力を書くより前 (反撃の入力が後から上書きする)", at ~= nil and (first_inject == nil or at < first_inject), true)
	eq("assert_input_bits を通す (メニュー中は書かない、監視の処理は自分の書き込みを無視する)",
	   src:sub(f0, e0):find("assert_input_bits(_back + (_g.down and 0x04 or 0), 0)", 1, true) ~= nil, true)
	eq("  assert_input_bits と GA はそれより前に定義されている",
	   src:find("local function assert_input_bits(", 1, true) < f0 and src:find("local GA = guard_action_input", 1, true) < f0, true)
end

print(fails == 0 and "\n全て通った" or ("\n" .. fails .. " 件 NG"))
os.exit(fails == 0 and 0 or 1)
