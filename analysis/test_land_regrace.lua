-- 凍った配送だけ、最終押しを着地まで待つ。猶予を超えたら頭から入れ直す。
--
-- 着地歩は lead ティック早く commit され、最終エントリが「行動可能になる最初の
-- ティック」に乗る予定で組まれている。それは予測であり、commit の後にヒット
-- ストップが始まると物理だけ止まって歩進はティックを数え続ける。着地は後ろへ
-- ずれ、最終押しは空中で出る。free+0 を外した押しは「遅い」ではなく「出ない」。
--
-- 2026-09-19 実測 (各 10 回):
--   ダッシュ小P  FD:0   動く
--   ダッシュ大P  FD:48  AF 24/24 が床の手前 2 ティックで空振り
-- 遅い技は降下の遅い側で当たるので、凍結がこの配送の中に入る。
--
-- 凍った配送だけを触る。以前「空中なら待つ」だけにしたら LW:240 (24 周) まで
-- 膨れ、動いていた小P側まで遅らせてダッシュキャンセルを壊して差し戻した。
-- 小P の最終押しも半分は空中だが、1 ティックのずれはゲームが受け付けている。
--
-- 待ってもエッジは失わないが、窓は失う。ダッシュの真ん中のニュートラルに
-- 許されるのは 10 ティック (資料、VSAV_MEMORY_NOTES.md)。ヒットストップは
-- 11 ティックなので、猶予を超えたら死んだ窓に押し込まず入れ直す。
--
-- scripts/ から走らせる。
--   cd scripts && lua5.1 ../analysis/test_land_regrace.lua
local ram = {}
memory = {
	readbyte  = function(a) return ram[a] or 0 end,
	readdword = function(a) return ram[a] or 0 end,
}
gui = { text = function() end, box = function() end }
emu = { framecount = function() return 1 end }
globals = { dummy = { guard_action = "sequence" }, options = {} }
training_settings = { action_sequences = {} }
function mark_training_settings_dirty() end
function dash_attack_ticks_for() return nil end
seq_dash_cancel_reverse = { ["forward dash cancel"] = "back", ["back dash cancel"] = "forward" }

local csrc = io.open("controller.lua"):read("*a")
local cs = csrc:find("function make_input_sequence", 1, true)
local ce = csrc:find("\nend", csrc:find("return _sequence", cs, true), true)
assert(cs and ce, "make_input_sequence が controller.lua に見つからない")
assert(loadstring(csrc:sub(cs, ce + 4)))()

function queue_input_sequence(_d, _seq)
	_d.pending_input_sequence = { sequence = _seq, current_frame = 1 }
end

local R = dofile("actionSequenceRunner.lua")

local fails = 0
local function want(what, got, w)
	if got ~= w then
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(w) .. "]")
	else
		print("  ok " .. what)
	end
end

local BITS = { forward = 0x02, back = 0x01, down = 0x04, up = 0x08 }
local function to_bits(entry)
	local lev, btn = 0, 0
	for _, k in ipairs(entry or {}) do
		if BITS[k] then lev = lev + BITS[k] else btn = 1 end
	end
	return lev, btn
end

local P2 = 0xFF8800

-- 歩進の代役。guardCancel の seq_tick ブロックと同じ規則。
local defender = {}
local log = {}
local function tick()
	local wrote = nil
	for _pass = 1, 2 do
		R.service(defender)
		local s = defender.pending_input_sequence
		if s == nil or s.sequence == nil then break end
		local i = s.current_frame or 1
		if s.seq_land and s.saw_freeze and i == #s.sequence
		   and (s.tick_held or 0) == 0
		   and ram[P2 + 0x38] ~= 0
		   and seq_ticks_to_landing() ~= nil then
			s.land_hold = (s.land_hold or 0) + 1
			if s.land_hold < (R.DASH_GRACE_TICKS or 10) - 1 then
				wrote = { src = "hold", lev = 0, btn = 0 }
				break
			end
			s.current_frame = 1
			s.tick_held = 0
			s.land_hold = 0
			i = 1
			restarts = (restarts or 0) + 1
		end
		if i <= #s.sequence then
			local lev, btn = to_bits(s.sequence[i])
			wrote = { src = "step", lev = lev, btn = btn, idx = i }
			if ram[P2 + 0x5C] ~= 0 then s.saw_freeze = true end
			local hold = (btn == 0 and lev ~= 0) and 2 or 1
			s.tick_held = (s.tick_held or 0) + 1
			if s.tick_held >= hold then
				s.current_frame = i + 1
				s.tick_held = 0
			end
			break
		end
		defender.pending_input_sequence = nil
	end
	log[#log + 1] = wrote or { src = "none", lev = 0, btn = 0 }
	return log[#log]
end
local function run(n) for _ = 1, n do tick() end end

local function install()
	ram[0xFF8B82] = 0x0A                       -- サスカッチ
	training_settings.action_sequences = { reversal = { ["10"] = { version = 1, steps = {
		{ action = "atk", lever = "none", button = "LP", wait = 0 },
		{ action = "dash.f", timing = "landing", wait = -1 },
	} } } }
end
local function start()
	log = {} ; restarts = 0
	defender = {}
	R.cancel()
	R.arm("reversal")
end
local function airborne()
	ram[P2 + 0x38] = 1
	ram[P2 + 0x14] = 6 * 65536
	ram[P2 + 0x44] = -65536
	ram[P2 + 0x4C] = -65536
	ram[P2 + 0x3A] = 0
end
local function finals()
	local n = 0
	for _, e in ipairs(log) do if e.src == "step" and e.idx == 4 then n = n + 1 end end
	return n
end
local function holds()
	local n = 0
	for _, e in ipairs(log) do if e.src == "hold" then n = n + 1 end end
	return n
end

seq_ticks_to_landing = function() return 4 end

print("[1] 凍らなかった配送は、これまでどおり出る")
install() ; start() ; airborne()
ram[P2 + 0x5C] = 0
run(10)
want("最終の forward が空中でもそのまま出る", finals() > 0, true)
want("待ちに入らない", holds(), 0)

print("[2] 凍った配送は、着地まで最終押しを待つ")
install() ; start() ; airborne()
-- 凍結は commit の後に始まる。ゲートは凍結中に commit しないので、
-- 最初から凍らせては配送そのものが始まらず、試したことにならない。
ram[P2 + 0x5C] = 0
run(2)                                     -- commit して助走が始まる
ram[P2 + 0x5C] = 11                        -- ここで凍る
run(2)
ram[P2 + 0x5C] = 0                         -- 明けたが、まだ空中
run(4)
want("最終の forward を空中で打たない", finals(), 0)
want("待っている", holds() > 0, true)

print("[3] 本当に着地したら、その場で出る")
ram[P2 + 0x38] = 0
run(2)
want("着地して最終の forward が出た", finals() > 0, true)

print("[4] 猶予を超えたら、頭から入れ直す")
install() ; start() ; airborne()
ram[P2 + 0x5C] = 0
run(2)
ram[P2 + 0x5C] = 11
run(2)
ram[P2 + 0x5C] = 0
run(30)                                    -- 着地しないまま待たせ続ける
want("入れ直した", (restarts or 0) > 0, true)
want("待ちは猶予の内に収まる", holds() <= (R.DASH_GRACE_TICKS - 2) * 3, true)
want("死んだ窓に押し込まない - 入れ直し前の空振りなし", finals(), 0)

print("[5] 着地が来ないなら停滞しない (前に戻しバグの再発防止)")
install() ; start() ; airborne()
ram[P2 + 0x5C] = 0
run(2)
ram[P2 + 0x5C] = 11
run(2)
ram[P2 + 0x5C] = 0
seq_ticks_to_landing = function() return nil end
run(6)
want("最終の forward は出る", finals() > 0, true)
seq_ticks_to_landing = function() return 4 end

print("[6] 出したダッシュ自身のホップで、入れ直しを始めない")
-- 最終の forward は 2 ティック出る。1 ティック目でダッシュが成立し、サスカッチは
-- 足が浮くので $38 が 0 -> 1 になる。2 ティック目に「空中かつ降下中」と見て入れ
-- 直していたため、ダッシュ→着地→ダッシュ→着地が延々続いた (実機 2026-09-19)。
install() ; start() ; airborne()
ram[P2 + 0x5C] = 0
run(2)
ram[P2 + 0x5C] = 11
run(2)
ram[P2 + 0x5C] = 0
run(6)                                     -- 空中で待たせる
ram[P2 + 0x38] = 0                         -- 着地。最終エントリの 1 ティック目が出る
tick()
ram[P2 + 0x38] = 1                         -- ダッシュ成立で足が浮く
local r0 = restarts or 0
local f0 = finals()
run(4)
want("浮いても入れ直さない", (restarts or 0), r0)
want("最終エントリを出し切る", finals() > f0, true)

print("[7] 猶予はダッシュの資料値で、出所が書いてある")
want("DASH_GRACE_TICKS = 10", R.DASH_GRACE_TICKS, 10)
do
	local rsrc = io.open("actionSequenceRunner.lua"):read("*a")
	want("ノーマル 1F = 1 tick の根拠が書いてある",
		rsrc:find("one frame is one tick at Normal", 1, true) ~= nil, true)
	want("ターボと取り違えた経緯が残してある",
		rsrc:find("NOT the emulator's turbo", 1, true) ~= nil, true)

	local gsrc = io.open("guardCancel.lua"):read("*a")
	-- 凍った配送だけを触ること。ここが外れると LW:240 の再発。
	local guard = gsrc:find("if _s0.seq_land and _s0.saw_freeze and _i == #_s0.sequence", 1, true)
	want("凍った配送だけに限っている", guard ~= nil, true)
	want("猶予を超えたら先頭へ戻す",
		guard ~= nil and gsrc:find("_s0.current_frame = 1", guard, true) ~= nil, true)
	local write = (guard ~= nil)
		and gsrc:find("if _i <= #_s0.sequence then", guard, true) or nil
	want("押しの書き込みより手前にある", (guard ~= nil and write ~= nil and guard < write), true)
	-- 入れ直しで印を消さないこと。消すと 2 周目が盲目になり、空中で打つ。
	-- このテストが実装から実際に見つけた穴なので、固定しておく。
	local body = (guard ~= nil and write ~= nil) and gsrc:sub(guard, write) or ""
	want("入れ直しても印を消さない",
		body:find("saw_freeze = false", 1, true) == nil, true)
	-- 出し始めた後は触らないこと。ここが外れると自分の出したダッシュに反応する。
	want("最終エントリが始まる瞬間だけを見る",
		gsrc:find("and (_s0.tick_held or 0) == 0", 1, true) ~= nil, true)
	-- 接地で解除すること。「動けるか」($05/$06) に変えたらサスカッチの 2 回目の
	-- ダッシュが遅れたので戻した (2026-09-19)。NF の計測も $06 を読むので、
	-- ファイル全体ではなくガードの区間だけを見る。
	want("接地で解除する (動けるか、ではない)",
		body:find("0xFF8806", 1, true) == nil, true)
end

print(fails == 0 and "REP_OK" or (fails .. " REP_NG"))
if fails ~= 0 then os.exit(1) end
