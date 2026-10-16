-- Run from scripts/: lua5.1 ../analysis/test_after_dash_fastest.lua
--
-- A GROUND DASH ON AUTO (AFTER) BEHIND THE DUMMY'S OWN MOVE STARTS ITS RUN-UP
-- AS THE MOVE ENDS (v11.7.28; user, 2026-10-16: "最速ダッシュは欲しいです").
--
--   [1] the walk to the end of the animation (M.anim_ticks_left)
--   [2] fired when what is left of the move is no more than the run-up, and
--       marked seq_free_aim for the walker; not before
--   [3] not in hit stop, hit, in the air, walking; not for a step that is not
--       a ground dash (it waits for free as before)
--   [4] the walker holds the last tap for free and asks the recogniser
--   [5] the ROM: the dash recogniser runs in the per-tick routine
--   [6] which animation ends the move is learnt from how it ended; an
--       animation not known to end it is not aimed at (the first time a move
--       is seen, and the Big Branch's first animation, which goes on into
--       another one). User, 2026-10-16: "２回目だけ最速で" - the first time not.
local P2, CLOCK = 0xFF8800, 0xFF8081
local CEL = 0x1000
local ram = {}
memory = {
	readbyte = function(a) return ram[a] or 0 end,
	readdword = function(a) return ram[a] or 0 end,
}
gui = { text = function() end, box = function() end }
emu = { framecount = function() return 1 end }
globals = { dummy = { guard_action = "sequence" }, options = {} }
function mark_training_settings_dirty() end
function dash_attack_ticks_for() return nil end
local csrc = assert(io.open("controller.lua")):read("*a")
local first = assert(csrc:find("function make_input_sequence", 1, true))
local last = assert(csrc:find("\nend", csrc:find("return _sequence", first, true), true))
assert(loadstring(csrc:sub(first, last + 3)))()
local queued
function queue_input_sequence(d, s)
	queued = s
	d.pending_input_sequence = { sequence = s, current_frame = 1 }
end
local R = dofile("actionSequenceRunner.lua")
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

-- An animation of three cels, 4 / 3 / 2 ticks, the last flagged bit 6.
local function cels(count_left)
	ram[P2 + 0x1C] = CEL
	ram[CEL + 1] = 0x00
	ram[CEL + 0x18] = 3 ; ram[CEL + 0x18 + 1] = 0x00
	ram[CEL + 0x30] = 2 ; ram[CEL + 0x30 + 1] = 0x40
	ram[P2 + 0x20] = count_left
end

print("[1] アニメの残り: 今のセルの残り + 後のセルの長さ、最後 (bit6) まで")
do
	ram = {}
	cels(4)
	eq("4 + 3 + 2", R.anim_ticks_left(), 9)
	ram[CEL + 0x18 + 1] = 0x80
	eq("途中で飛ぶ (bit7) なら分からない", R.anim_ticks_left(), nil)
	ram[P2 + 0x1C] = 0
	eq("セルが無ければ分からない", R.anim_ticks_left(), nil)
end

-- A list of the dummy's own special, then the dash on Auto (After).
local function setup(action)
	ram = { [0xFF8B82] = 10 }
	queued = nil
	R.cancel()
	training_settings = {
		action_sequences = { reversal = { ["10"] = { version = 1, steps = {
			{ action = "atk", button = "HP", lever = "none", wait = 0 },
			{ action = action, button = "MK", lever = "none", wait = -1 },
		} } } },
	}
	R.arm("reversal")
	-- The animation the tests run in is one already seen to end the move.
	R.final_anim = { [CEL + 0x30] = true }
	local d = {}
	queued = nil
	return d
end
-- One tick of the move: busy on the ground, the animation's count down by one.
local function tick(d, st)
	ram[CLOCK] = ((ram[CLOCK] or 0) + 1) % 256
	ram[P2 + 0x05] = st.s05 or 0
	ram[P2 + 0x06] = st.s06 or 0x10
	ram[P2 + 0x38] = st.air or 0
	ram[P2 + 0x5C] = st.stop or 0
	R.service(d)
end

print("[2] 技の残りが入力に要る分以下になったら、動ける前に出す (seq_free_aim)")
do
	local d = setup("dashc.f")
	local fired_at, aim = nil, nil
	for left = 12, 0, -1 do
		-- the count of the last cel stands for what is left
		ram[P2 + 0x1C] = CEL + 0x30
		ram[CEL + 0x30 + 1] = 0x40
		ram[P2 + 0x20] = left
		tick(d, {})
		if queued ~= nil and fired_at == nil then
			fired_at = left
			aim = d.pending_input_sequence and d.pending_input_sequence.seq_free_aim
		end
	end
	eq("動ける前に出した (残り > 0)", fired_at ~= nil and fired_at > 0, true)
	eq("  早すぎない (残り 6 以下)", fired_at ~= nil and fired_at <= 6, true)
	eq("  最後の前は walker が動けるまで待つ印", aim, true)
	-- Free with no prediction (a move that loops): After as before, no aim.
	d = setup("dashc.f")
	ram[P2 + 0x1C] = 0
	tick(d, {})
	eq("予測が無い間は出さない", queued, nil)
	tick(d, { s06 = 0 })
	eq("  動けたら出す", queued ~= nil, true)
	eq("  印は無い", d.pending_input_sequence.seq_free_aim, nil)
end

print("[3] 早出ししないとき")
do
	local function early_with(st, action)
		local d = setup(action or "dashc.f")
		ram[P2 + 0x1C] = CEL + 0x30
		ram[CEL + 0x30 + 1] = 0x40
		ram[P2 + 0x20] = 1
		tick(d, st)
		return queued ~= nil
	end
	eq("ヒットストップ中 ($5C)", early_with({ stop = 5 }), false)
	eq("やられ・投げられ ($05)", early_with({ s05 = 2 }), false)
	eq("空中 ($38)", early_with({ air = 1 }), false)
	eq("歩き ($06 0x04)", early_with({ s06 = 0x04 }), false)
	eq("地上ダッシュでない (MK)", early_with({}, "atk"), false)
	eq("比べ: 同じ状態の地上ダッシュは出す", early_with({}), true)
end

print("[4] walker: 最後の前を動けるまで待ち、ダッシュの認識に聞く")
do
	local gc = slurp("guardCancel.lua")
	local a = gc:find("if _s0.seq_free_aim and _i == #_s0.sequence and (_s0.tick_held or 0) == 0 then", 1, true)
	local b = gc:find("if _s0.seq_land and _s0.saw_freeze and _i == #_s0.sequence", 1, true)
	eq("着地の待ちより前にある", a ~= nil and b ~= nil and a < b, true)
	local blk = (a and b) and gc:sub(a, b) or ""
	eq("  動けるまで待つ (dummy_free_now)", blk:find("elseif not _R.dummy_free_now() then\n\t\t\t\t\treturn", 1, true) ~= nil, true)
	eq("  認識が消えていたら最初から (After のダッシュ)", blk:find("if _st == 0 then", 1, true) ~= nil
	   and blk:find("_s0.current_frame = 1", 1, true) ~= nil, true)
	eq("  最後の段で生きていれば押す", blk:find("elseif not (_st == 4 and _tm >= 2) then", 1, true) ~= nil, true)
	eq("  やられたら印を外す (待つのは 600 回まで: 動けるまで待つ)", blk:find("_s0.aim_wait > 600 or memory.readbyte(0xFF8805) ~= 0", 1, true) ~= nil, true)
	eq("runner は印を載せる", slurp("actionSequenceRunner.lua"):find("q.seq_free_aim = aim_free or nil", 1, true) ~= nil, true)
end

print("[5] ROM: ダッシュの認識は毎 Tick の処理で状態を問わず回る")
do
	local code = slurp("../analysis/mame_code/c20.txt")
	local function at(addr, text) return (code:match("\n" .. addr .. ":[^\n]*") or ""):find(text, 1, true) ~= nil end
	eq("0222B2 $04 で振り分け", at("0222B2", "move.w  ($c,PC,D0.w), D1"), true)
	eq("0223EC jsr $29f12 (前の認識)", at("0223EC", "jsr     $29f12.l"), true)
	eq("0223F8 jsr $29f1c (後ろの認識)", at("0223F8", "jsr     $29f1c.l"), true)
	local c28 = slurp("../analysis/mame_code/c28.txt")
	eq("029F12 lea ($1f0,A6), A4", (c28:match("\n029F12:[^\n]*") or ""):find("lea     ($1f0,A6), A4", 1, true) ~= nil, true)
end

print("[6] 最後のアニメかは、終わり方を見て覚える (この起動の間)")
do
	local A, B = 0x2000, 0x3000
	local function at(last, s06, s05)
		ram[P2 + 0x1C] = last
		ram[last + 1] = 0x40
		ram[P2 + 0x05] = s05 or 0
		ram[P2 + 0x38] = 0
		ram[P2 + 0x06] = s06
		R.observe()
	end
	R.final_anim = {}
	at(A, 0x10) ; at(A, 0x10) ; at(B, 0x10)
	eq("A から B へ (まだ技の中): A は最後ではない", R.final_anim[A], false)
	at(B, 0x10) ; at(B, 0)
	eq("B の後に動けた: B は最後", R.final_anim[B], true)
	at(A, 0x10) ; at(A, 0)
	eq("一度でも続いた A は、動けて終わっても false のまま", R.final_anim[A], false)
	R.final_anim = {}
	at(A, 0x10) ; at(A, 0x10, 2) ; at(A, 0)
	eq("途中でやられたら決めない", R.final_anim[A], nil)
	-- Not known: After as before, even with the end of the animation in reach.
	local d = setup("dashc.f")
	R.final_anim = {}
	ram[P2 + 0x1C] = CEL + 0x30
	ram[CEL + 0x30 + 1] = 0x40
	ram[P2 + 0x20] = 1
	tick(d, {})
	eq("最後と分かっていないアニメでは早出ししない (1 回目)", queued, nil)
	tick(d, { s06 = 0 })
	eq("  動けたら出す (今までの After)", queued ~= nil, true)
	eq("  動けたことで、そのアニメを最後と覚えた (2 回目からは早出し)", R.final_anim[CEL + 0x30], true)
	local o = slurp("actionSequenceRunner.lua")
	eq("service の最初に observe", o:find("function M.service(defender)\n\tM.observe()\n", 1, true) ~= nil, true)
	eq("早出しは最後と分かっているアニメだけ",
	   o:find("and M.final_anim[last_cel_of_anim() or 0] == true then", 1, true) ~= nil, true)
end

print(fails == 0 and "\n全て通った" or ("\n" .. fails .. " 件 NG"))
os.exit(fails == 0 and 0 or 1)
