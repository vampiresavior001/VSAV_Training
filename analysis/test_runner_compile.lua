-- WHERE AN Auto STEP'S PRESS ACTUALLY LANDS.
--
-- A step's press lands on its LAST entry, so everything in front of that entry
-- pushes it later. Under a numbered wait service_body subtracts lead and starts
-- the list early, landing on the named tick. Under Auto it cannot: the tick is
-- a state test and the future is not visible, so lead IS how many ticks past
-- free+0 the press falls.
--
-- The tool's rule is that anything not entered as a special-move command has to
-- land on free+0 or it does not come out. So for those, lead must be 0. A
-- command motion is exempt - its own inputs are the entries, and there is
-- nothing to remove.
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_runner_compile.lua
local ram={} memory={readbyte=function(a) return ram[a] or 0 end,
                     readdword=function() return 0 end}
gui={text=function() end,box=function() end}
emu={framecount=function() return 1 end}
globals={dummy={}} training_settings={action_sequences={}}
function mark_training_settings_dirty() end
function dash_attack_ticks_for(m) return (m=="forward dash" or m=="forward dash cancel") and 6 or nil end
-- キャンセル方向の地図 (guardCancel が公開する seq_dash_cancel_reverse の代役)。
seq_dash_cancel_reverse = { ["forward dash cancel"] = "back", ["back dash cancel"] = "forward" }
-- ザベルだけ実測されている表の代役。行が無いキャラは nil を返し、Auto は
-- 状態判定のまま - 他人の踏切を借りない、という表と同じ規則。
local AIR_ROW = nil
-- ジャンプの向きとダッシュの向きの組で引く。ザベルは前→前が 8 なのに
-- 後ろ→前は 4 で、踏切だけでは決まらないことが分かったため。
local function air_pair(jump, dash)
  if AIR_ROW == nil then return nil end
  return AIR_ROW[tostring(jump)..">"..tostring(dash)]
end
function air_dash_ticks_for(j,d) local p=air_pair(j,d) return p and p.dash end
function air_dash_attack_ticks_for(j,d) local p=air_pair(j,d) return p and p.atk end
-- ジャンプ -> 攻撃の表 (guardCancel の jump_attack_ticks_for) の代役。
local JUMP_ROW = nil
function jump_attack_ticks_for(j) return JUMP_ROW and JUMP_ROW[j] end

-- The real make_input_sequence, lifted out of controller.lua so this runs
-- without the emulator. Taking the real one is the point: a motion whose entry
-- list changes there has to show up here.
local src=io.open("controller.lua"):read("*a")
local s=src:find("function make_input_sequence",1,true)
local e=src:find("\nend",src:find("return _sequence",s,true),true)
assert(s and e,"make_input_sequence が controller.lua で見つからない")
assert(loadstring(src:sub(s,e+4)))()

local R=dofile("actionSequenceRunner.lua")

local fails=0
local function fail(what,got,want)
  fails=fails+1
  print("  NG "..what.."   got ["..tostring(got).."]  want ["..tostring(want).."]")
end

-- 期待値との単純な照合。fail は落ちたときだけ書くので、通ったことも残す。
local function want(what, got, w)
  if got ~= w then fail(what, got, w) else print("  ok " .. what) end
end

local function show(list)
  local p={}
  for _,ent in ipairs(list) do p[#p+1]="{"..table.concat(ent,"+").."}" end
  return table.concat(p," ")
end

-- Compile the action as step TWO with Auto, which is the case under test.
local function step2(action,lever,button)
  local out=R.compile({version=1,steps={
    {action="neutral",wait=0},
    {action=action,lever=lever,button=button,wait=-1}}})
  assert(out and out[2],"compile が失敗した: "..tostring(action))
  return out[2]
end

local function check(label,want_lead,action,lever,button)
  local st=step2(action,lever,button)
  local mark=(st.lead==want_lead) and "  ok " or "  NG "
  if st.lead~=want_lead then fails=fails+1 end
  print(string.format("%s%-28s lead=%d  free+%d  %s",
    mark,label,st.lead,st.lead,show(st.sequence)))
end

print("[1] 通常技は free+0 - 方向がボタンと同じエントリに乗るので先頭ニュートラルは不要")
check("Attack Neutral + LP",      0,"atk","none","LP")
check("Attack Down Back + LP",    0,"atk","down-back","LP")
check("Attack Forward + HP",      0,"atk","forward","HP")
check("Attack Down + HK",         0,"atk","down","HK")
check("Attack Up Forward + MP",   0,"atk","up-forward","MP")

print("[2] 裸の方向は先頭ニュートラルを残す - 押しエッジを作れるのがそれしかない")
check("Stand Forward",            1,"walk.f")
check("Stand Back",               1,"walk.b")
check("Crouch Neutral",           1,"crouch.d")
check("Jump Forward",             1,"jump.f")
check("Jump Neutral",             1,"jump.n")

print("[3] 何も押さないステップ")
check("Stand Neutral",            0,"neutral")

print("[4] コマンド技はエントリ自体がコマンド - lead は取り除けない")
-- 裸の方向エントリは v158 の規則で 2 ティック占める(ボタンを伴えば 1)。
-- DPF は {} 1 + {forward} 2 + {down} 2 = 5、ダッシュは {} 1 + {forward} 2 +
-- {} 1 = 4。Auto ではこの分だけ free から遅れるが、これはコマンドそのもの。
check("Custom DPF + HP",          5,"custom","DPF","HP")
check("Custom QCF + LK",          5,"custom","QCF","LK")
check("Dash Forward",             4,"dash.f")
check("Super Jump Forward",       3,"sj.f")

-- HCB-full IS THE HALF CIRCLE WITH NOTHING LEFT OUT.
--
-- The abbreviated "HCB" is what the generic recogniser (0x2A684) takes and it
-- skips down-back. Valkyrie Turn names the unabbreviated form, so the two have
-- to stay different: a rename or a dropped branch in controller.lua falls back
-- to one empty entry, which delivers nothing while looking like a motion.
do
  local hcb  = show(make_input_sequence("HCB", "none", "", 0))
  local full = show(make_input_sequence("HCB-full", "none", "", 0))
  want("HCB は down-back を通らない 4 点", hcb,
       "{forward} {down+forward} {down} {back}")
  want("HCB-full は 5 点すべて", full,
       "{forward} {down+forward} {down} {down+back} {back}")
end

print("[5] ボタンだけを外すと裸の方向に戻る - ニュートラルが復活する")
check("Custom Down Back + none",  1,"custom","down-back","none")

print("[5b] Hold と明示した 1 エントリの姿勢には先頭ニュートラルを入れない")
-- ニュートラルは「方向に押しエッジを作る」ためのもの。Hold はタップではなく
-- レバーを置いておくことなので、エッジは要らない。しかも入れると前のステップの
-- 保持が 1 ティック切れ、Auto では lead が補正されず free+1 に落ちる。
local function check_hold(label, want_lead, want_first_neutral, action, lever, button)
	local out = R.compile({version=1,steps={
		{action="neutral",wait=0},
		{action=action,lever=lever,button=button,hold=true,wait=-1}}})
	local st = out[2]
	local first_neutral = (#st.sequence[1] == 0)
	local ok = (st.lead == want_lead) and (first_neutral == want_first_neutral)
	if not ok then fails = fails + 1 end
	print(string.format("%s%-30s lead=%d 先頭ニュートラル=%-5s %s",
		ok and "  ok " or "  NG ", label, st.lead, tostring(first_neutral), show(st.sequence)))
end
check_hold("Attack Down Back + None",   0, false, "atk", "down-back", "none")
check_hold("Attack Down Back + LP",     0, false, "atk", "down-back", "LP")
check_hold("Stand Forward",             0, false, "walk.f")
check_hold("Crouch Back",               0, false, "crouch.b")
-- 複数エントリはタップの列。1 発目のエッジは Hold と関係なく要る。
check_hold("Dash Forward",              4, true,  "dash.f")
check_hold("Super Jump Forward",        3, true,  "sj.f")
check_hold("Custom DPF + HP",           5, true,  "custom", "DPF", "HP")
-- Hold を外せばニュートラルは戻る。
do
	local out = R.compile({version=1,steps={
		{action="neutral",wait=0},
		{action="atk",lever="down-back",button="none",wait=-1}}})
	local st = out[2]
	if st.lead == 1 and #st.sequence[1] == 0 then
		print("  ok Hold 無しの Attack Down Back + None は今までどおり  " .. show(st.sequence))
	else
		fail("Hold 無しのニュートラル", show(st.sequence), "{} {down+back}")
	end
end

print("[6] 数値の wait は lead を引くので、どの技も名指しのティックに乗る")
local out=R.compile({version=1,steps={
  {action="neutral",wait=0},
  {action="dash.f",wait=10},
  {action="atk",lever="down-back",button="LP",wait=7}}})
for i=2,3 do
  local st=out[i]
  local start=st.wait-st.lead
  if start<0 then start=0 end
  print(string.format("     step %d  wait=%d lead=%d -> 開始 +%d、押し +%d",
    i,st.wait,st.lead,start,start+st.lead))
  if start+st.lead~=st.wait then fail("step "..i.." が名指しのティックに乗らない",start+st.lead,st.wait) end
end
print("  ok 数値の wait は両方とも一致")

print("[6b] 複数ボタンが本物のボタン名に展開されるか")
-- PPP と KKK は "EXP"/"EXK" という文字列のままエントリに入っていた。
-- entry_to_bits は BUTTON_BITS を引いて or 0 なので、方向だけあってボタンが
-- 無いエントリになり、技が出なかった。ビシャモンの締めの PPP で発覚。
local BTN = { LP=true, MP=true, HP=true, LK=true, MK=true, HK=true }
for _, case in ipairs({
	{ "EXP",   { "LP", "MP", "HP" } },
	{ "EXK",   { "LK", "MK", "HK" } },
	{ "LP+LK", { "LP", "LK" } },
	{ "HP",    { "HP" } },
}) do
	local btn, want_list = case[1], case[2]
	local st = step2("atk", "forward", btn)
	local last = st.sequence[#st.sequence]
	local got = {}
	for _, k in ipairs(last) do if BTN[k] then got[#got + 1] = k end end
	table.sort(got)
	local w = {}
	for _, k in ipairs(want_list) do w[#w + 1] = k end
	table.sort(w)
	local g, ww = table.concat(got, "+"), table.concat(w, "+")
	if g == ww then print(string.format("  ok %-5s -> %s", btn, g))
	else fail("ボタン " .. btn, g, ww) end
end

print("[6c] Auto の解決先は、直前のアクションの種類で決まる")
-- 入力は同じでも意味が違う。地上ダッシュは表、空中ダッシュは 0、ジャンプ→
-- 空中ダッシュは踏切の実測値。解決は runner の auto_ticks_for が一手に持ち、
-- エディタの行も同じものを呼ぶ。
do
	-- head は 1 歩目。空中ダッシュ後の攻撃はジャンプの向きまで見るので、
	-- そこを差し替えられるようにしておく。
	local function auto_of(prev_action, this_action, lever, button, head)
		local out = R.compile({version=1,steps={
			{action=head or "neutral", wait=0},
			{action=prev_action, wait=-1},
			{action=this_action, lever=lever, button=button, wait=-1}}})
		return out[3]
	end
	local function want_auto(label, st, auto, wait)
		if st.auto ~= auto or (auto == false and st.wait ~= wait) then
			fail(label, string.format("auto=%s wait=%s", tostring(st.auto), tostring(st.wait)),
			     string.format("auto=%s wait=%s", tostring(auto), tostring(wait)))
		else
			print(string.format("  ok %-34s auto=%-5s wait=%s", label, tostring(st.auto), tostring(st.wait)))
		end
	end

	AIR_ROW = nil
	-- 導出は「行の無いキャラ」の話になった。MEASURED_STEP_FLOORS が全キャラ
	-- 埋まったので、行のあるキャラでは導出は一度も走らない。ザベル 2 (0x0B) は
	-- 別形態でどちらの表にも行が無く、いま導出に落ちる唯一の経路 (デミトリは
	-- 利用者の指示で 0 の行を持つ)。
	ram[0xFF8B82] = 0x0B
	-- スタブは forward dash = 6 を返す → そのまま 6 (2026-09-01: -1 をやめた。
	-- kd_press_base() の +1 を二重に引いていた。詳細は actionSequenceRunner.lua)
	want_auto("行の無いキャラは導出", auto_of("dash.f","atk","down","HP"), false, 6)
	-- キャンセルは逆方向が 2 ティック後から効くので、その分を足す。
	want_auto("行の無いキャラのキャンセルは+2", auto_of("dashc.f","atk","down","HP"), false, 8)

	-- 実測行があれば導出は見ない。スタブは何を訊かれても 6 を返すので、
	-- 6 でも 8 でもない数が出たら表から来ている。0 も値であることを
	-- ザベルで押さえる (行が無いのと区別できているか)。
	ram[0xFF8B82] = 0x00   -- Bulleta   f 4
	want_auto("実測行が導出に勝つ", auto_of("dash.f","atk","down","HP"), false, 4)
	ram[0xFF8B82] = 0x02   -- Gallon    fc 15
	want_auto("キャンセルも表から", auto_of("dashc.f","atk","down","HP"), false, 15)
	ram[0xFF8B82] = 0x04   -- Zabel     f 0
	want_auto("実測の 0 は 0 のまま", auto_of("dash.f","atk","down","HP"), false, 0)

	-- 利用者が入れた 0 だけ 1 に上げる。0 は step1 と同じティックに落ち、
	-- 2 つの入力が 1 つとして読まれる。Auto が表から解決した 0 (すぐ上の
	-- ザベル) は測定値なので触らない - ここが取り違えやすい。
	do
		local function w2(v)
			training_settings.action_sequences = { reversal = { ["4"] = { version = 1, steps = {
				{ action = "atk", lever = "none", button = "LP", wait = 0 },
				{ action = "atk", lever = "none", button = "MP", wait = v } } } } }
			ram[0xFF8B82] = 0x04
			local sc = R.schedule("reversal")
			return sc and sc[2] and sc[2].wait
		end
		want("2 歩目の 0 は 1 に上がる", w2(0), 1)
		want("1 はそのまま",             w2(1), 1)
		want("5 はそのまま",             w2(5), 5)
		-- 1 歩目は基準がトリガなので 0 のまま。
		want("1 歩目の 0 は 0 のまま",
		     (function()
		        training_settings.action_sequences = { reversal = { ["4"] = { version = 1, steps = {
		          { action = "atk", lever = "none", button = "LP", wait = 0 } } } } }
		        ram[0xFF8B82] = 0x04
		        local sc = R.schedule("reversal")
		        return sc and sc[1] and sc[1].wait
		     end)(), 0)
	end
	ram[0xFF8B82] = 0x00
	-- 行が無ければ空中ダッシュの次も状態判定。0 は「測ってある 0」であって
	-- 既定値ではない - レイレイは 5 だった。
	want_auto("空中ダッシュの次、表が無ければ状態判定", auto_of("air.f","atk","down","HP"), true, nil)
	want_auto("ジャンプの次、表が無ければ状態判定", auto_of("jump.f","air.f"), true, nil)

	AIR_ROW = { ["jump.f>air.f"] = { dash = 8, atk = 0 } }
	want_auto("ジャンプの次、表があれば実測値", auto_of("jump.f","air.f"), false, 8)
	want_auto("空中ダッシュの次も表から",       auto_of("air.f","atk","down","HP","jump.f"), false, 0)
	AIR_ROW = { ["jump.f>air.f"] = { dash = 9, atk = 5 } }
	want_auto("レイレイ形: ダッシュ 9",         auto_of("jump.f","air.f"), false, 9)
	want_auto("レイレイ形: 攻撃 5",             auto_of("air.f","atk","none","LP","jump.f"), false, 5)
	-- 1 歩目がジャンプでなければ、どの組か決まらないので数字は出ない。
	want_auto("ジャンプ以外の後の空中ダッシュ", auto_of("air.f","atk","none","LP"), true, nil)
	-- 後ろ空中ダッシュは未実測なので、行があっても数字は出ない。
	AIR_ROW = { ["jump.f>air.f"] = { dash = 8, atk = 0 } }
	want_auto("未実測の組は状態判定のまま", auto_of("jump.f","air.b"), true, nil)
	-- スーパージャンプは踏切が別物。実測が無いので借りない。
	want_auto("スーパージャンプの次は借りない", auto_of("sj.f","air.f"), true, nil)
	AIR_ROW = nil

	-- ジャンプ -> 攻撃。表 (公開資料の「攻撃前」- 1) があれば数字、無ければ
	-- 今までどおり状態判定 (2026-09-25)。
	JUMP_ROW = nil
	want_auto("ジャンプ->攻撃、表が無ければ状態判定", auto_of("jump.f","atk","none","LP"), true, nil)
	JUMP_ROW = { ["jump.f"] = 4, ["jump.n"] = 4, ["jump.b"] = 4 }
	want_auto("ジャンプ->攻撃は表の数字",          auto_of("jump.f","atk","none","LP"), false, 4)
	want_auto("垂直ジャンプも同じ口",              auto_of("jump.n","atk","none","LP"), false, 4)
	-- 表の列は通常技の話。必殺技や空中ダッシュは今までの扱いのまま。
	want_auto("ジャンプ->必殺技は借りない",        auto_of("jump.f","custom","none","LP"), true, nil)
	want_auto("ジャンプ->空中ダッシュは空中の表",  auto_of("jump.f","air.f"), true, nil)
	want_auto("スーパージャンプ->攻撃は借りない",  auto_of("sj.f","atk","none","LP"), true, nil)
	JUMP_ROW = nil

	-- 空中ダッシュの入力は地上ダッシュと同一であること。名前だけの違い。
	local air = R.compile({version=1,steps={
		{action="neutral",wait=0},{action="air.f",wait=-1}}})[2]
	local gnd = R.compile({version=1,steps={
		{action="neutral",wait=0},{action="dash.f",wait=-1}}})[2]
	if show(air.sequence) ~= show(gnd.sequence) then
		fail("空中ダッシュの入力", show(air.sequence), show(gnd.sequence))
	else
		print("  ok 入力は地上ダッシュと同一  " .. show(air.sequence))
	end
end

print("[6d] ダッシュキャンセルのステップ - rev を運び、Hold 行を握りつぶす")
do
	-- 次のステップがある cancel は逆方向を運ぶ。リスト自体は素ダッシュの
	-- まま - 逆方向はエントリではなく、runner がタップの 2 ティック後から
	-- 保持して次のボタンに合流させる。
	local two = R.compile({version=1,steps={
		{action="dashc.f",wait=-1},
		{action="atk",lever="none",button="HP",wait=-1}}})
	if two[1].rev ~= "back" then fail("cancel ステップの rev", tostring(two[1].rev), "back")
	else print("  ok rev = back   " .. show(two[1].sequence)) end
	if two[2].rev ~= nil then fail("攻撃ステップの rev", tostring(two[2].rev), "nil") end
	-- 保存データに Hold が残っていても、cancel ステップでは握りつぶす。
	-- 保持すべきは逆方向であって、ダッシュ自身の forward ではない。
	local held = R.compile({version=1,steps={
		{action="dashc.f",wait=-1,hold=true},
		{action="atk",lever="none",button="HP",wait=-1}}})
	if held[1].hold ~= nil then fail("cancel ステップの hold", tostring(held[1].hold), "nil")
	else print("  ok cancel ステップの hold は nil (自動の逆方向が優先)") end
	-- 最終ステップの cancel は次のボタンが無いので rev を運ばない。
	local last = R.compile({version=1,steps={
		{action="atk",lever="none",button="LP",wait=0},
		{action="dashc.f",wait=-1}}})
	if last[2].rev ~= nil then fail("最終ステップの rev", tostring(last[2].rev), "nil")
	else print("  ok 最終ステップの cancel は rev なし") end
end

print("[7] ユーザ報告の並び - ダッシュ攻撃からしゃがみ LP へ目押し")
local aul=R.compile({version=1,steps={
  {action="dash.f",wait=-1},
  {action="atk",lever="none",button="MP",wait=-1},
  {action="atk",lever="down-back",button="LP",wait=-1},
  {action="atk",lever="down-back",button="LP",wait=-1}}})
for i,st in ipairs(aul) do
  print(string.format("     step %d  auto=%-5s wait=%-2s lead=%d  %s",
    i,tostring(st.auto),tostring(st.wait),st.lead,show(st.sequence)))
end
for i=3,4 do
  if aul[i].lead~=0 then fail("step "..i.." の押しが free+0 に乗らない","free+"..aul[i].lead,"free+0") end
end
-- 止まった条件は行にも出る。Wait の数字だけでは「窓が開くのが遅かった」のか
-- 「一度も開かず締切で出た」のかが区別できない (本人、2026-09-24)。
print("[wait_log] 止まった条件が行に出る")
do
  R.wait_log = {
    { index = 1, mode = "Auto", op = 5 },
    { index = 2, mode = "Set", ticks = 11, op = 1 },
    { index = 3, mode = "Cancel", ticks = 29, op = 7, why = "hit" },
  }
  local lines = R.wait_log_lines(120)
  local all = table.concat(lines, " ")
  want("理由が付く", all:find("Step.3 Wait:29 Act:7 ?hit", 1, true) ~= nil, true)
  R.wait_log[3].why = nil
  all = table.concat(R.wait_log_lines(120), " ")
  want("通った step には付かない", all:find("?", 1, true), nil)
  R.wait_log = {}
end

if fails==0 then print("  ok 3 歩目も 4 歩目も free+0") end


-- LOOP: THE LIST STARTS AGAIN WHEN IT ENDS.
--
-- Driven through M.service the way the walker drives it, because the whole
-- point is WHEN the first step comes back round - a test that only inspected
-- the schedule would pass while the restart never fired.
print("\n[8] ループ")

-- The delivery slot, and the walker's half of the contract: queue it, then free
-- it once the entries have gone in. Nothing here models entries - the runner
-- only cares whether the slot is occupied.
local D = {}
local delivered = {}
function queue_input_sequence(d, seq)
  delivered[#delivered + 1] = show(seq)
  d.pending_input_sequence = { sequence = seq, current_frame = 1 }
end
local function tick()
  ram[0xFF8081] = ((ram[0xFF8081] or 0) + 1) % 256
  R.service(D)
  -- The walker frees the slot on the tick after the last entry went in.
  D.pending_input_sequence = nil
end
local function run(n) for _ = 1, n do tick() end end
local function reset(loop_wait, steps)
  ram[0xFF8081] = 0
  ram[0xFF8B82] = 0x05
  -- Free to act: $05 and $06 both zero, and not airborne ($38).
  ram[0xFF8805], ram[0xFF8806], ram[0xFF8838] = 0, 0, 0
  training_settings.action_steps_loop = (loop_wait ~= false)
  training_settings.action_steps_loop_wait = (loop_wait ~= false) and loop_wait or -1
  training_settings.action_sequences = { reversal = { ["5"] = { version = 1, steps = steps } } }
  delivered = {}
  D.pending_input_sequence = nil
  R.cancel()
  R.arm("reversal")
end
-- Two steps that are one entry each, so a delivery is one tick and the
-- arithmetic below stays about the WAIT rather than about the motion.
local TWO = { { action = "atk", lever = "none", button = "LP", wait = 0 },
              { action = "atk", lever = "none", button = "MP", wait = 0 } }
local function count(what)
  local n = 0
  for _, s in ipairs(delivered) do if s == what then n = n + 1 end end
  return n
end

-- Off: today's behaviour, byte for byte. Step two goes out and nothing follows.
reset(false, TWO)   -- スイッチが Off
run(40)
if count("{MP}") ~= 1 or count("{LP}") ~= 0 then
  fail("スイッチ Off では繰り返さない", "LP "..count("{LP}").." / MP "..count("{MP}"), "LP 0 / MP 1")
else print("  ok スイッチ Off では繰り返さない") end

-- A number: the list comes back round, starting at step one.
reset(3, TWO)
run(40)
if count("{LP}") < 2 or count("{MP}") < 2 then
  fail("数値で 1 歩目から回る", "LP "..count("{LP}").." / MP "..count("{MP}"), "どちらも 2 以上")
else print("  ok 数値で 1 歩目から回る") end
if delivered[1] ~= "{MP}" or delivered[2] ~= "{LP}" then
  fail("回る順は 2 歩目の次が 1 歩目", tostring(delivered[1]).." "..tostring(delivered[2]), "{MP} {LP}")
else print("  ok 回る順は 2 歩目の次が 1 歩目") end

-- Auto: waits for the dummy. While $05 says it is busy, nothing restarts - and
-- that is the difference from the numeric branch below.
reset(-1, TWO)
run(4)
ram[0xFF8805] = 1
-- One tick to let anything already queued finish; what is measured is whether
-- a NEW pass starts while the gate is shut.
tick()
local _before = #delivered
run(40)
if #delivered ~= _before then
  fail("Auto は動けないあいだ回らない", #delivered, _before)
else print("  ok Auto は動けないあいだ回らない") end
ram[0xFF8805] = 0
run(10)
if #delivered <= _before then
  fail("Auto は動けるようになったら回る", #delivered, "> ".._before)
else print("  ok Auto は動けるようになったら回る") end

-- A NUMBER DOES NOT ASK THE DUMMY. That is what a loop tight enough to be an
-- infinite needs: the restart has to land while the opponent is still being
-- hit, which is exactly when the dummy is not free.
reset(3, TWO)
run(4)
ram[0xFF8805] = 1
local _busy = #delivered
run(40)
if #delivered <= _busy then
  fail("数値は攻撃中でも回る", #delivered, "> ".._busy)
else print("  ok 数値は攻撃中でも回る") end
ram[0xFF8805] = 0

-- cancel() ends it. Without the loop state going too, the schedule would come
-- back on the next tick.
reset(3, TWO)
run(10)
R.cancel()
local _after = #delivered
run(40)
if #delivered ~= _after then
  fail("cancel でループも止まる", #delivered, _after)
else print("  ok cancel でループも止まる") end

-- THE MENU ENDS THE RUN, AND CLOSING IT DOES NOT START ONE.
--
-- Was "closing the menu resumes the loop". Changed deliberately: the menu does
-- not pause the game, so a schedule left standing behind it is elapsing rather
-- than waiting, and resuming on close meant the dummy was already moving before
-- the menu had finished closing - after an edit, running a lap nobody asked
-- for. The pass and the loop both go; a fresh arm brings it back
-- (user, 2026-09-06).
reset(3, TWO)
run(4)
globals.show_menu = true
tick()
local _menu = #delivered
run(40)
if #delivered ~= _menu then
  fail("メニュー中は回らない", #delivered, _menu)
else print("  ok メニュー中は回らない") end
globals.show_menu = nil
run(40)
if #delivered ~= _menu then
  fail("閉じても勝手には回らない", #delivered, _menu)
else print("  ok 閉じても勝手には回らない") end
R.arm("reversal")
run(20)
if #delivered <= _menu then
  fail("武装し直せば回る", #delivered, "> ".._menu)
else print("  ok 武装し直せば回る") end

-- THE LEAD SUBTRACTION SURVIVES THE LOOP, which is the whole reason a number is
-- offered: the input list has to START early enough for its last entry to land
-- on the named tick. A dash is four entries, so a wait under its lead goes as
-- early as it can rather than late.
local DASH = { { action = "dash.f", wait = 0 },
               { action = "atk", lever = "none", button = "LP", wait = 0 } }
-- Pass one's step one goes out through the ARM, which does not come through
-- queue_input_sequence - so every dash seen here is a LOOPED one.
reset(0, DASH)
run(30)
if count("{forward} {} {forward}") < 1 then
  fail("ループの 1 歩目にダッシュが来る", table.concat(delivered, " / "), "ダッシュを含む")
else print("  ok ループの 1 歩目にダッシュが来る") end
queue_input_sequence = nil

-- ONE CONNECTION PER CONTACT.
--
-- $39 stays non-zero for the whole hit stop, so a mode that only asks "is there
-- contact" arms again on the next tick and the step after it goes in during the
-- SAME stop. Measured in game: light -> medium chains, medium -> heavy does not.
-- What is pinned here is the PHASE each step fired in, not the order: an
-- assertion on order alone passes while both land in the first stop.
print("\n[9] 同一ヒットストップで 2 段は出さない")
do
  local PHASE = 0
  local hits = {}
  local D2 = {}
  local realq = queue_input_sequence
  queue_input_sequence = function(d, seq)
    local p = {} for _, e in ipairs(seq) do p[#p+1] = table.concat(e, "+") end
    hits[#hits+1] = { phase = PHASE, what = table.concat(p, " ") }
    d.pending_input_sequence = { sequence = seq }
  end
  local P2 = 0xFF8800
  ram[0xFF8081] = 0
  ram[0xFF8B82] = 0x06
  ram[P2 + 0x06]  = 0x0A
  ram[P2 + 0x1B2] = 0
  ram[P2 + 0x102] = 0     -- 現在 = 小P (rank 1)
  ram[P2 + 0x101] = 0
  training_settings.action_steps_loop = false
  training_settings.action_sequences = { reversal = { ["6"] = { version = 1, steps = {
    { action = "atk", lever = "none", button = "LP", wait = 0 },
    { action = "atk", lever = "none", button = "MP", wait = -1, timing = "chain" },
    { action = "atk", lever = "none", button = "HP", wait = -1, timing = "chain" } } } } }
  R.cancel()
  R.arm("reversal")
  local function run(n, contact, phase)
    PHASE = phase
    for _ = 1, n do
      ram[0xFF8081] = (ram[0xFF8081] + 1) % 256
      ram[P2 + 0x39] = contact
      R.service(D2)
      D2.pending_input_sequence = nil
    end
  end
  run(12, 1, 1)          -- 小がヒット。ヒットストップ 1
  run(4, 0, 0)           -- 明ける。中はまだ当たっていない
  ram[P2 + 0x102] = 2    -- 中が出た
  run(12, 1, 2)          -- 中がヒット。ヒットストップ 2
  queue_input_sequence = realq
  if #hits ~= 2 then
    fail("2 段だけ出る", #hits, 2)
  elseif hits[1].what ~= "MP" or hits[2].what ~= "HP" then
    fail("順は 中 -> 大", hits[1].what .. " " .. hits[2].what, "MP HP")
  elseif hits[1].phase ~= 1 or hits[2].phase ~= 2 then
    fail("別のヒットストップに分かれる",
         "1 段目=" .. hits[1].phase .. " 2 段目=" .. hits[2].phase, "1 と 2")
  else
    print("  ok 中と大が別のヒットストップに分かれる")
  end
end

-- THE LEVER IS HELD WHILE THE BUTTON WAITS, AND NOTHING ELSE MOVES.
--
-- Inside a hit stop the attacker's script is frozen, and a direction arriving
-- on the same tick as the button came out standing. Held for the whole wait
-- instead - which is how a chain is played by hand - with nothing added to the
-- input list, so the press still lands on the tick the gate opens.
print("\n[10] ボタン待ちの間レバーを入れておく")
do
  local function sched_of(steps)
    training_settings.action_sequences = { reversal = { ["10"] = { version = 1, steps = steps } } }
    ram[0xFF8B82] = 0x0A
    return R.schedule("reversal")
  end
  local CROUCH_LK = { action = "atk", lever = "down-back", button = "LK", wait = -1, timing = "chain" }
  local s = sched_of({ { action = "atk", lever = "none", button = "LP", wait = 0 }, CROUCH_LK })

  -- 入力列も lead も足されていないこと。足すと押しが遅れる。
  if show(s[2].sequence) ~= "{down+back+LK}" then
    fail("しゃがみ小 K の入力列は 1 エントリのまま", show(s[2].sequence), "{down+back+LK}")
  else print("  ok しゃがみ小 K の入力列は 1 エントリのまま") end
  if s[2].lead ~= 0 then fail("lead は 0 のまま", s[2].lead, 0) else print("  ok lead は 0 のまま") end

  -- 起き上がり最速投げ: 1 歩目は timing を持てないので、待機レバーの対象外。
  -- リストも lead も従来どおりで、Fastest の置き方は変わらない。
  local t = sched_of({ { action = "custom", lever = "HCB", button = "HP", wait = -1, timing = "chain" } })
  if t[1].timing ~= nil then fail("1 歩目に timing は乗らない", tostring(t[1].timing), "nil")
  else print("  ok 1 歩目に timing は乗らない (最速投げは従来どおり)") end
end

-- 待機レバーが出る条件と、出てはいけない条件。
do
  local function lever_for(steps)
    training_settings.action_sequences = { reversal = { ["10"] = { version = 1, steps = steps } } }
    ram[0xFF8B82] = 0x0A
    R.cancel()
    R.arm("reversal")
    -- 1 歩目はアームが持っていくので、2 歩目が先頭になる。
    local l = R.waiting_lever()
    return l and table.concat(l, "+") or nil
  end
  local HEAD = { action = "atk", lever = "none", button = "LP", wait = 0 }
  local function two(second) return { HEAD, second } end

  want("方向つきチェーンはレバーを出す",
       lever_for(two({ action = "atk", lever = "down-back", button = "LK", wait = -1, timing = "chain" })),
       "down+back")
  want("Chain も同じ",
       lever_for(two({ action = "atk", lever = "down", button = "MK", wait = -1, timing = "chain" })),
       "down")
  -- 方向を持たない攻撃は保持するものが無い。
  want("方向なしは出さない",
       lever_for(two({ action = "atk", lever = "none", button = "MP", wait = -1, timing = "chain" })),
       nil)
  -- timing が無いステップは対象外。Auto (After) は今のままで正しく出ている。
  want("Auto (After) は対象外",
       lever_for(two({ action = "atk", lever = "down-back", button = "LK", wait = -1 })),
       nil)
  -- コマンド技は連続したタップそのものが技。前に方向を差すと崩れる。
  want("コマンド技には出さない",
       lever_for(two({ action = "custom", lever = "QCF", button = "HP", wait = -1, timing = "cancel" })),
       nil)
end

-- THE LAST STEP KEEPS ITS DIRECTION TOO.
--
-- A step in the middle gets it for free: the next one is already waiting with
-- the same lever. The last has nothing behind it, so the direction came off on
-- the tick after the press and a press the game did not take as a chain was
-- read later as a standing normal. Held to the end of the contact, and no
-- further - the dummy must not be left leaning on a direction afterwards.
do
  local P2 = 0xFF8800
  local D3 = {}
  local realq = queue_input_sequence
  local shots = {}
  queue_input_sequence = function(d, seq) shots[#shots+1] = true d.pending_input_sequence = { sequence = seq } end
  ram[0xFF8B82] = 0x0A
  ram[P2 + 0x06] = 0x0A ram[P2 + 0x1B2] = 0 ram[P2 + 0x102] = 0 ram[P2 + 0x101] = 0
  training_settings.action_steps_loop = false
  training_settings.action_sequences = { reversal = { ["10"] = { version = 1, steps = {
    { action = "atk", lever = "none", button = "LP", wait = 0 },
    { action = "atk", lever = "down-back", button = "HK", wait = -1, timing = "cancel" } } } } }
  R.cancel()
  R.arm("reversal")
  local seen = {}
  for i = 1, 12 do
    ram[0xFF8081] = i
    ram[P2 + 0x39] = (i >= 3 and i <= 8) and 1 or 0
    R.service(D3)
    D3.pending_input_sequence = nil
    local l = R.waiting_lever()
    seen[i] = l and table.concat(l, "+") or nil
  end
  queue_input_sequence = realq
  want("押す前は入っている",        seen[2],  "down+back")
  want("押した後も接触の間は残る",  seen[6],  "down+back")
  want("接触が切れたら離す",        seen[10], nil)
end

-- Auto (Landing) - THE TOUCHDOWN, FROM guardCancel's OWN CLOCK.
--
-- Auto (After) asks air_ready while the dummy is airborne ("may it press now
-- in the AIR"), which is the wrong question for a grounded follow-up.
-- This one asks the clock the reversal arm already uses. The clock itself is
-- stubbed here: what is pinned is that the step waits for it and fires on the
-- arm offset, not the physics, which guardCancel owns and tests elsewhere.

print("\n[11] Auto (Landing)")
do
  local P2 = 0xFF8800
  local D4 = {}
  local realq = queue_input_sequence
  local real_ld = seq_ticks_to_landing
  local LD = nil
  seq_ticks_to_landing = function() return LD end
  local shot, shots
  local function setup(steps)
    shot, shots = nil, {}
    queue_input_sequence = function(d, seq)
      local p = {} for _, e in ipairs(seq) do p[#p+1] = table.concat(e, "+") end
      shot = ram[0xFF8081] shots[#shots+1] = table.concat(p, " ")
      d.pending_input_sequence = { sequence = seq }
    end
    ram[0xFF8B82] = 0x0A
    ram[P2 + 0x06] = 0x0A ram[P2 + 0x1B2] = 0
    ram[P2 + 0x102] = 0 ram[P2 + 0x101] = 0
    ram[P2 + 0x39] = 0
    training_settings.action_steps_loop = false
    training_settings.action_sequences = { reversal = { ["10"] = { version = 1, steps = steps } } }
    R.cancel()
    local sch = R.schedule("reversal")
    R.arm("reversal")
    return sch
  end
  local function tick(i, air, ld)
    ram[0xFF8081] = i
    ram[P2 + 0x38] = air
    LD = ld
    R.service(D4)
    D4.pending_input_sequence = nil
  end
  local HEAD = { action = "atk", lever = "none", button = "LP", wait = 0 }
  local CROUCH_HP = { action = "atk", lever = "down-back", button = "HP", wait = -1, timing = "landing" }

  -- ONE ENTRY: THE PRESS GOES IN ON THE FLOOR, NOT ABOVE IT.
  --
  -- lead 0 means the button IS the whole step, so there is nothing to start
  -- early for. Firing while still airborne is a press that goes in and produces
  -- nothing - the input display showed it arriving, and no move came out.
  setup({ HEAD, CROUCH_HP })
  local lever_mid
  for i = 1, 6 do
    tick(i, 1, 8 - i)
    if i == 3 then local l = R.waiting_lever() lever_mid = l and table.concat(l, "+") or nil end
  end
  want("落下中はレバーを入れて待つ", lever_mid, "down+back")
  want("落下中は押さない", shot, nil)
  tick(7, 0, nil)
  want("接地したティックで押す", shot, 7)

  -- LEAD > 0: START EARLY, SO THE LAST ENTRY LANDS ON THE TOUCHDOWN.
  local sch = setup({ HEAD,
    { action = "custom", lever = "QCF", button = "HP", wait = -1, timing = "landing" } })
  want("QCF の lead は 5", sch[2].lead, 5)
  for i = 1, 12 do tick(i, 1, 13 - i) end
  want("lead のぶん早く始まる", shot, 8)

  -- 地上のまま頭に来たら待つ。着地するものが無い。
  setup({ HEAD, CROUCH_HP })
  for i = 1, 12 do tick(i, 0, nil) end
  want("地上のままなら出さない", shot, nil)

  -- 着地は接触を食わない。ヒットで計っていないので、後ろのチェーンが待っている
  -- 接触を横取りしない。
  setup({ HEAD,
    { action = "atk", lever = "down-back", button = "LK", wait = -1, timing = "landing" },
    { action = "atk", lever = "down-back", button = "MP", wait = -1, timing = "chain" } })
  for i = 1, 3 do tick(i, 1, 5 - i) end
  for i = 4, 10 do ram[P2 + 0x39] = 1 tick(i, 0, nil) end
  want("着地のあと同じ接触でチェーンが出る", #shots, 2)
  if #shots == 2 then
    want("順は 着地 -> チェーン", shots[1] .. " / " .. shots[2], "down+back+LK / down+back+MP")
  end

  seq_ticks_to_landing = real_ld
  queue_input_sequence = realq
  ram[P2 + 0x38] = 0 ram[P2 + 0x39] = 0
end

-- SPECIAL MOVES: THE TWO SHAPES A COMMAND COMES IN.
--
-- motion moves were already expressible through Custom; sequence moves were not,
-- and that is why the group exists. What is pinned here is the compiled input,
-- because a named move that delivers the wrong list is worse than one that
-- delivers nothing.
print("\n[12] Special Move")
do
  local real = seq_special_command
  -- The real registry lives in charMoves.lua, which this test does not load -
  -- the runner only ever sees it through this global.
  local REG = {
    ["Shadow Blade"]     = { type = "motion", motion = "DPF", button_group = "P" },
    ["Vector Drain"]     = { type = "motion", motion = "HCB", allowed_buttons = {"MP","HP"} },
    ["Finishing Shower"] = { type = "sequence",
                             sequence = {{"MP"},{"LP"},{"back"},{"LK"},{"MK"}} },
  }
  seq_special_command = function(name) return REG[name] end
  local HEAD = { action = "atk", lever = "none", button = "LP", wait = 0 }
  local function sched(step)
    training_settings.action_sequences = { reversal = { ["5"] = { version = 1,
      steps = { HEAD, step } } } }
    ram[0xFF8B82] = 0x05
    return R.schedule("reversal")
  end

  local a = sched({ action = "sp.Shadow Blade", button = "HP", wait = 0 })
  want("motion 型はレジストリのモーション", show(a[2].sequence),
       "{} {forward} {down} {down+forward+HP}")

  local b = sched({ action = "sp.Finishing Shower", wait = 0 })
  want("sequence 型はレジストリの入力列そのもの", show(b[2].sequence),
       "{MP} {LP} {back} {LK} {MK}")
  want("sequence 型の lead", b[2].lead, 5)

  -- 先頭ニュートラルは方向で始まるときだけ。MP で始まる列には付かない。
  want("sequence 型に先頭ニュートラルは付かない", b[2].sequence[1][1], "MP")

  -- コンパイルはレジストリを書き戻さない。共有物なので壊すと全リストに波及する。
  b[2].sequence[1][1] = "BROKEN"
  want("レジストリは書き換わらない", REG["Finishing Shower"].sequence[1][1], "MP")

  -- 連打型 (Q-Bee SxP)。同じボタンを 4 回、間にニュートラル - 4 押し 3 空きで
  -- 7 ティック。強度は利用者が選ぶので、押し方は同じで中身だけ変わる。
  REG["SxP"] = { type = "repeat", count = 4,
                 allowed_buttons = {"LK","MK","HK","EXK"} }
  do
    local r = sched({ action = "sp.SxP", button = "LK", wait = 0 })
    want("連打は 7 ティック", #r[2].sequence, 7)
    want("連打の中身", show(r[2].sequence), "{LK} {} {LK} {} {LK} {} {LK}")
    -- KKK も同じ道を通る。展開しないと "EXK" という名前のままエントリに乗り、
    -- ボタンの立たない入力になる。
    local e = sched({ action = "sp.SxP", button = "EXK", wait = 0 })
    want("KKK は 3 ボタンに開く", show(e[2].sequence),
         "{LK+MK+HK} {} {LK+MK+HK} {} {LK+MK+HK} {} {LK+MK+HK}")
    -- ボタンが無ければコンパイルしない。押されない入力を作るより拒否する。
    want("ボタン無しは拒否", sched({ action = "sp.SxP", wait = 0 }), nil)
  end
  REG["SxP"] = nil

  -- 知らない技はコンパイルが通らない。出ない行を作るより、リストごと拒否する。
  want("レジストリに無い技はコンパイルしない",
       sched({ action = "sp.Nope", wait = 0 }), nil)

  seq_special_command = real
end

-- THE PRESS OFFSET DEPENDS ON BEING A SPECIAL, AND A SUPER IS ONE.
--
-- guardCancel presses a special on free-1 and everything else on free+0
-- (kd_press_base, keyed on SPECIAL_MOTION by motion NAME). A button-order
-- super has no motion name - its command is an ordered run of buttons - so it
-- was classified as a normal and every one of them came out on +1 Tick.
-- The record says it outright instead.
do
  local real = seq_special_command
  local REG = {
    ["Shadow Blade"]     = { type = "motion", motion = "DPF", button_group = "P" },
    ["Finishing Shower"] = { type = "sequence",
                             sequence = {{"MP"},{"LP"},{"back"},{"LK"},{"MK"}} },
  }
  seq_special_command = function(name) return REG[name] end
  local HEAD = { action = "atk", lever = "none", button = "LP", wait = 0 }
  local function first_special(step)
    training_settings.action_sequences = { reversal = { ["5"] = { version = 1,
      steps = { step, HEAD } } } }
    ram[0xFF8B82] = 0x05
    return R.first_is_special("reversal")
  end

  want("sequence 型の必殺技は special",
       first_special({ action = "sp.Finishing Shower", wait = 0 }), true)
  want("motion 型の必殺技も special",
       first_special({ action = "sp.Shadow Blade", button = "HP", wait = 0 }), true)
  -- 通常技を free-1 で押すと「出ない」ティックを頼むことになる。
  -- press_free0 の技は special ではない扱いにする。押しが 1 ティック早いと
  -- 出ない技があり (ビシャモンの鬼炎斬)、モーションは他の技と同じ DPF なので
  -- モーション名では見分けられない。
  REG["Kienzan"]  = { type = "motion", motion = "DPF", button_group = "P",
                      press_free0 = true }
  REG["Own Kien"] = { type = "motion", motion = "DPF", button_group = "P" }
  want("press_free0 の技は free+0 で押す",
       first_special({ action = "sp.Kienzan", button = "HP", wait = 0 }), false)
  want("旗が無ければ従来どおり free-1",
       first_special({ action = "sp.Own Kien", button = "HP", wait = 0 }), true)
  -- guardCancel は first_is_special が false のときモーション表に落ちる。DPF は
  -- その表にあるので、"special ではない" だけでは free-1 に戻されてしまう。
  -- 旗そのものを訊けることが要る。
  local function press0(step)
    training_settings.action_sequences = { reversal = { ["5"] = { version = 1,
      steps = { step, HEAD } } } }
    ram[0xFF8B82] = 0x05
    return R.first_press_free0("reversal")
  end
  want("旗は単独で訊ける",
       press0({ action = "sp.Kienzan", button = "HP", wait = 0 }), true)
  want("旗の無い DPF は false",
       press0({ action = "sp.Own Kien", button = "HP", wait = 0 }), false)
  want("通常技も false",
       press0({ action = "atk", lever = "down", button = "HP", wait = 0 }), false)

  -- 旗を訊く側の配線。counter_is_special は first_is_special が偽のとき
  -- SPECIAL_MOTION に落ちるので、旗の判定はその前に無いと意味が無い。
  do
    local gc = io.open("guardCancel.lua"):read("*a")
    local fn = gc:match("local function counter_is_special%(%)(.-)\nend")
    assert(fn ~= nil, "counter_is_special が読めない")
    local at_flag = fn:find("first_press_free0", 1, true)
    local at_spec = fn:find("first_is_special", 1, true)
    want("counter_is_special が旗を見ている", at_flag ~= nil, true)
    want("旗を先に見ている", (at_flag or math.huge) < (at_spec or 0), true)
  end
  REG["Kienzan"], REG["Own Kien"] = nil, nil

  want("通常技は special ではない",
       first_special({ action = "atk", lever = "down", button = "HP", wait = 0 }), false)
  want("Custom も special ではない (motion 名で判定される側)",
       first_special({ action = "custom", lever = "QCF", button = "HP", wait = 0 }), false)
  want("ダッシュも special ではない",
       first_special({ action = "dash.f", wait = 0 }), false)

  seq_special_command = real
end

-- MIZUUMI の数字列モーションと、溜め技の書き方。
--
-- エディタには技名しか出るので、モーション名が controller.lua に無いことは
-- 「選んでも何も起きない」という形でしか現れない。展開そのものを固定する。
do
  local src = io.open("controller.lua"):read("*a")
  local s = src:find("function make_input_sequence", 1, true)
  local e = src:find("\nend", src:find("return _sequence", s, true), true)
  local f = assert(loadstring(src:sub(s, e + 4)))
  setfenv(f, setmetatable({}, {__index = _G}))
  f()
  local function ex(m, b)
    local p = {}
    for _, en in ipairs(make_input_sequence(m, b, "", 0)) do
      p[#p + 1] = "{" .. table.concat(en, "+") .. "}"
    end
    return table.concat(p, " ")
  end

  -- 2 度目の下にはニュートラルが要る (ダッシュと同じ)。さらにボタンは
  -- その下と同じティックでは受け付けられないので、末尾に空のエントリがあり
  -- ボタンはそこへ乗る。同時に押すと技が出ない (実測)。
  want("22 の 2 度目の下には N が入る", ex("22", "LP"), "{down} {} {down} {LP}")
  want("46", ex("46", "LP"), "{back} {forward+LP}")
  want("263", ex("263", "HP"), "{down} {forward} {down+forward+HP}")
  want("632", ex("632", "HP"), "{forward} {down+forward} {down+HP}")
  want("41236", ex("41236", "HP"),
       "{back} {down+back} {down} {down+forward} {forward+HP}")
  want("2~8", ex("2~8", "LK"), "{down} {up+LK}")
  want("6~4", ex("6~4", "HP"), "{forward} {back+HP}")

  -- 余分の 1 方向は先頭に置く。末尾に足すとボタンが up から外れ、投げが
  -- Fastest ではなく +1 で出る (実測)。up で終わることと、方向が 1 つ食われても
  -- 一周残ること、その両方を満たす形。
  want("360 は up で終わる", ex("360", "HP"),
       "{up} {forward} {down} {back} {up+HP}")
  want("720 も up で終わる", ex("720", "EXK"),
       "{up} {forward} {down} {back} {up} {forward} {down} {back} {up+LK+MK+HK}")

  -- 溜めはコマンドに入らない。最後のエントリが空なので、ボタンは方向と同じ
  -- ティックではなく次のティックに単独で乗る - 利用者の言う「N 前 ボタン」。
  want("[4]6 はボタンが単独で最後に来る", ex("[4]6", "HP"), "{} {forward} {HP}")
  want("[2]8", ex("[2]8", "HK"), "{} {up} {HK}")
  -- 同強度でない唯一のボタンの組。展開されないと "LK+MK" という名前のまま
  -- entry_to_bits に渡り、ボタンの立たないエントリになる (EXP/EXK と同じ落ち方)。
  local function ex_comma(m, btn)
    local p = {}
    for _, en in ipairs(make_input_sequence(m, btn, "", 0)) do
      p[#p + 1] = "{" .. table.concat(en, ",") .. "}"
    end
    return table.concat(p, " ")
  end
  want("LK+MK は 2 つのボタンに開く", ex_comma("HCF", "LK+MK"),
       "{back} {down,back} {down} {down,forward,LK,MK}")

  -- 押しのオフセットは SPECIAL_MOTION の名前で決まる。抜けると 1 ティック遅れる。
  local gc = io.open("guardCancel.lua"):read("*a")
  local decl = gc:match("local SPECIAL_MOTION = {(.-)\n}")
  assert(decl ~= nil, "SPECIAL_MOTION が読めない")
  local set = assert(loadstring("return {" .. decl .. "}"))()
  for _, m in ipairs({"22","46","263","632","41236","2~8","6~4","[4]6","[2]8"}) do
    want("SPECIAL_MOTION に " .. m, set[m], true)
  end
end
-- 電撃ボタン (ビクトル)。Elec.MP は MP と同じ入力で、押したあと 8 ティック
-- 下げたままにする。Mizuumi の 5[MP] の角括弧がこれ。
--
-- 保持は入力列には入らない。アーム経路は押しを自分で入れたあと列を捨てるので、
-- 複製を積んでも 1 つも届かない (実測: 電撃でない中P が出た)。記録の上で
-- 持たせ、guardCancel が押しのあとに当てる。
do
  local function sc(step)
    training_settings.action_sequences = { reversal = { ["3"] = { version = 1,
      steps = { step } } } }
    ram[0xFF8B82] = 0x03
    return R.schedule("reversal")[1], R.first_len("reversal")
  end
  local plain = sc({ action = "atk", lever = "none", button = "MP", wait = 0 })
  local elec, flen = sc({ action = "atk", lever = "none", button = "Elec.MP", wait = 0 })

  want("入力は MP と同じもの", show(elec.sequence), "{MP}")
  want("入力列は伸びない",     show(elec.sequence), show(plain.sequence))
  want("lead も変わらない",     elec.lead, plain.lead)
  want("first_len も変わらない", flen, 1)
  want("保持するボタン", table.concat(elec.hold_btn or {}, "+"), "MP")
  want("保持するティック数", elec.hold_btn_ticks, 30)
  want("普通のボタンには付かない", plain.hold_btn, nil)

  -- 方向は保持に混ぜない。それはレバーの Hold の仕事。
  local cr = sc({ action = "atk", lever = "down", button = "Elec.HK", wait = 0 })
  want("入力は下 + HK",   show(cr.sequence), "{down+HK}")
  want("保持はボタンだけ", table.concat(cr.hold_btn or {}, "+"), "HK")

  -- モーション付きでも列は変わらない。
  local dpf  = sc({ action = "custom", lever = "DPF", button = "Elec.HP", wait = 0 })
  local dpf0 = sc({ action = "custom", lever = "DPF", button = "HP", wait = 0 })
  want("モーションの列は同じ", show(dpf.sequence), show(dpf0.sequence))
  want("モーションの lead も同じ", dpf.lead, dpf0.lead)

  -- 2 歩目以降はセグメントに乗る。ここが抜けると 1 歩目だけ効く。
  training_settings.action_sequences = { reversal = { ["3"] = { version = 1, steps = {
    { action = "atk", lever = "none", button = "LP", wait = 0 },
    { action = "atk", lever = "none", button = "Elec.MP", wait = 5 } } } } }
  ram[0xFF8B82] = 0x03
  local sc2 = R.schedule("reversal")
  want("2 歩目にも乗る", table.concat(sc2[2].hold_btn or {}, "+"), "MP")

  -- 1 歩目はアーム経路から拾う。
  training_settings.action_sequences = { reversal = { ["3"] = { version = 1, steps = {
    { action = "atk", lever = "none", button = "Elec.MP", wait = 0 } } } } }
  ram[0xFF8B82] = 0x03
  local _n, _t = R.first_hold_button("reversal")
  want("arm 経路のボタン",     table.concat(_n or {}, "+"), "MP")
  want("arm 経路のティック数", _t, 30)

  -- 受け渡しは 1 回きり。毎ティック答えると、期限で切れた次のティックに
  -- 再武装して技が出続ける (実測: 電撃パンチが無限に連発した)。
  R.arm("reversal")
  local _a1, _c1 = R.take_arm_hold_button()
  want("arm したら 1 回目は答える", table.concat(_a1 or {}, "+"), "MP")
  want("ティック数も一緒に",         _c1, 30)
  local _a2 = R.take_arm_hold_button()
  want("2 回目は答えない", _a2, nil)
  -- もう一度 arm すればまた答える。
  R.arm("reversal")
  want("arm し直せば答える",
       table.concat((R.take_arm_hold_button()) or {}, "+"), "MP")
  -- cancel でも消える。
  R.arm("reversal")
  R.cancel()
  want("cancel で消える", R.take_arm_hold_button(), nil)

  -- 配送側が one-shot の方を呼んでいること。
  do
    local gc2 = io.open("guardCancel.lua"):read("*a")
    want("配送は take_arm_hold_button を呼ぶ",
         gc2:find("take_arm_hold_button()", 1, true) ~= nil, true)
    want("配送は first_hold_button を呼ばない",
         gc2:find("first_hold_button", 1, true) ~= nil, false)
  end

  -- 配送側の配線。ここが繋がっていないと、記録に載っても押されない。
  do
    -- 2 歩目以降は fire がセグメントに載せる。記録に載っていても、ここが
    -- 抜けていれば配送側には何も届かない。
    local rn = io.open("actionSequenceRunner.lua"):read("*a")
    want("セグメントに載せている",
         rn:find("q.seq_hold_btn = step.hold_btn", 1, true) ~= nil, true)
    want("ティック数も載せている",
         rn:find("q.seq_hold_btn_ticks = step.hold_btn_ticks", 1, true) ~= nil, true)
    local gc = io.open("guardCancel.lua"):read("*a")
    want("セグメントの保持を拾う", gc:find("seq_hold_btn", 1, true) ~= nil, true)
    want("arm の保持を拾う",       gc:find("take_arm_hold_button", 1, true) ~= nil, true)
    want("期限を持っている",       gc:find("seq_held_btn_until", 1, true) ~= nil, true)
    -- 保持は自分のステップより長生きしてはいけない。次のセグメントが始まる
    -- ときに消えないと、次の押しに古い保持が乗り、間の空きティックでは
    -- 早期 return して下の処理を飢えさせる。
    local newseg = gc:match("A new segment is being delivered(.-)\n\t\t\tlocal _i")
    want("新しいセグメントでレバー保持を消す",
         newseg ~= nil and newseg:find("seq_held_lever = nil", 1, true) ~= nil, true)
    want("ボタン保持も一緒に消す",
         newseg ~= nil and newseg:find("seq_held_btn = nil", 1, true) ~= nil, true)
    want("期限も消す",
         newseg ~= nil and newseg:find("seq_held_btn_until = nil", 1, true) ~= nil, true)
    local blk = gc:match("BEFORE the lever hold(.-)\n\t\tif seq_held_lever ~= nil then")
    want("期限で自分から降りる",
         blk ~= nil and blk:find("seq_held_btn = nil", 1, true) ~= nil, true)
    -- entry_to_bits は lever, button の順。第 1 値をボタンとして渡すと
    -- 何も押されない。
    want("ボタンは第 2 値を渡す",
         blk ~= nil and blk:find("local _hl, _hb = entry_to_bits(seq_held_btn)", 1, true) ~= nil,
         true)
    want("押すのは第 2 値",
         blk ~= nil and blk:find("assert_input_bits(_hl, _hb)", 1, true) ~= nil, true)
  end
end

-- Late Chain は無くなった。窓の終わりを事前に知る手段が無く、旧実装は
-- 一度も発火していなかった (最終セルと接触は同時に成り立たない)。
do
  local rn = io.open("actionSequenceRunner.lua"):read("*a")
  want("late_chain を捌く枝は無い",
       rn:find("TIMING_LATE_CHAIN", 1, true) ~= nil, false)
  want("chain_ready に late は無い",
       rn:find("chain_ready(step, true)", 1, true) ~= nil, false)
  -- Chain / Cancel / Late Cancel は残る。
  want("Chain は残る",       rn:find("TIMING_CHAIN", 1, true) ~= nil, true)
  want("Late Cancel も残る", rn:find("TIMING_LATE_CANCEL", 1, true) ~= nil, true)
end


-- 連打キャンセル。ROM 0x028FB0 の条件をそのまま並べ、1 つずつ外して
-- 発火しなくなることを見る。接触 ($39) は条件に無い - 呼び出し側が成功時に
-- 接触判定を飛び越すので、空振りでも成立する。
print("\n[15] 連打キャンセル")
do
  local hits = {}
  local D3 = {}
  local realq = queue_input_sequence
  queue_input_sequence = function(d, seq)
    local p = {} for _, e in ipairs(seq) do p[#p+1] = table.concat(e, "+") end
    hits[#hits+1] = table.concat(p, " ")
    d.pending_input_sequence = { sequence = seq }
  end
  local P2 = 0xFF8800
  local function setup()
    hits = {}
    ram[0xFF8081] = 0
    -- 保存リストのキーはキャラ id の 10 進。15 番のリストは 0x0F で引かれる。
    ram[0xFF8B82] = 0x0F
    ram[P2 + 0x06]  = 0x0A   -- 通常技中
    ram[P2 + 0x38]  = 0      -- 地上
    ram[P2 + 0x21]  = 0      -- セルはまだ受け付けない
    ram[P2 + 0x39]  = 0      -- 空振り。連打には要らない
    ram[P2 + 0x102] = 0      -- 小
    ram[P2 + 0x101] = 0      -- パンチ
    ram[P2 + 0x110] = 0
    ram[P2 + 0x111] = 0
    training_settings.action_steps_loop = false
    training_settings.action_sequences = { reversal = { ["15"] = { version = 1, steps = {
      { action = "atk", lever = "none", button = "LP", wait = 0 },
      { action = "atk", lever = "none", button = "LP", wait = -1, timing = "rapid" },
      { action = "atk", lever = "none", button = "LP", wait = -1, timing = "rapid" } } } } }
    R.cancel()
    R.arm("reversal")
  end
  local function run(n)
    for _ = 1, n do
      ram[0xFF8081] = (ram[0xFF8081] + 1) % 256
      R.service(D3)
      D3.pending_input_sequence = nil
    end
  end

  setup()
  run(6)
  want("セルの bit0 が無ければ出ない", #hits, 0)
  ram[P2 + 0x21] = 0x01
  run(1)
  want("bit0 が立てば出る", #hits, 1)
  -- 窓は 1 回きり。開きっぱなしの間に残り全部が 1 tick 刻みで出てはいけない。
  run(6)
  want("同じ窓で 2 発目は出ない", #hits, 1)
  ram[P2 + 0x21] = 0x00
  run(1)
  ram[P2 + 0x21] = 0x01
  run(1)
  want("窓が開き直せば次が出る", #hits, 2)

  -- 空中は別経路。0x028FB0 の最初の判定。
  setup()
  ram[P2 + 0x38] = 1
  ram[P2 + 0x21] = 0x01
  run(6)
  want("空中では出ない", #hits, 0)

  -- ボタンは $102/$101 から作られるので、同じボタン以外は受け付けない。
  setup()
  ram[P2 + 0x21] = 0x01
  ram[P2 + 0x102] = 2       -- 出ているのは中。ステップは小
  run(6)
  want("違う強さでは出ない", #hits, 0)
  setup()
  ram[P2 + 0x21] = 0x01
  ram[P2 + 0x101] = 2       -- 出ているのはキック。ステップはパンチ
  run(6)
  want("違う系統では出ない", #hits, 0)

  -- ROM は $110 == $111 を要求する。
  setup()
  ram[P2 + 0x21] = 0x01
  ram[P2 + 0x111] = 1
  run(6)
  want("$110 と $111 が違えば出ない", #hits, 0)

  -- 通常技中でなければ、そもそもこの経路に入らない。
  setup()
  ram[P2 + 0x21] = 0x01
  ram[P2 + 0x06] = 0x00
  run(6)
  want("通常技中でなければ出ない", #hits, 0)

  -- ヒットストップ中は 0x022552 が $06 のディスパッチを飛ばすので、この判定
  -- 自体が走らない。連打は $126 (1 tick の押しエッジ) しか見ないため、その間に
  -- 押しても捨てられる。チェーンが $12E (ラッチ) で助かるのとはここが違う。
  setup()
  ram[P2 + 0x21] = 0x01
  ram[P2 + 0x39] = 1
  ram[P2 + 0x5C] = 8
  run(6)
  want("ヒットストップ中は押さない", #hits, 0)
  ram[P2 + 0x5C] = 0
  run(1)
  want("明けたら出る", #hits, 1)
  ram[P2 + 0x39] = 0
  ram[P2 + 0x5C] = 0

  queue_input_sequence = realq
  ram[P2 + 0x21] = 0
  ram[P2 + 0x06] = 0
  ram[P2 + 0x102] = 0
  ram[P2 + 0x101] = 0
  ram[P2 + 0x111] = 0
end

-- 実測した wait を記録する。Auto (After) や Auto (Chain) が何 tick だったかは
-- 行に出ないので、発火したところで数えて外へ出す。
print("\n[16] wait の実測ログ")
do
  local D4 = {}
  local realq = queue_input_sequence
  queue_input_sequence = function(d, seq) d.pending_input_sequence = { sequence = seq } end
  local P2 = 0xFF8800
  ram[0xFF8081] = 0
  ram[0xFF8B82] = 0x10
  ram[P2 + 0x06] = 0x00
  ram[P2 + 0x38] = 0
  ram[P2 + 0x21] = 0
  training_settings.action_steps_loop = false
  training_settings.action_sequences = { reversal = { ["16"] = { version = 1, steps = {
    { action = "atk", lever = "none", button = "LP", wait = 0 },
    { action = "atk", lever = "none", button = "MP", wait = 5 },
    { action = "atk", lever = "none", button = "HP", wait = 3 } } } } }
  R.cancel()
  R.arm("reversal")
  -- 1 歩目は arm 経路で出るので wait は測れない。Act だけは入力列の長さなので
  -- ここで分かる。
  want("武装したら 1 歩目の Act だけ載る", #R.wait_log, 1)
  want("その項目に wait は無い", R.wait_log[1].ticks, nil)
  want("Act は載る", R.wait_log[1].op, 1)
  for _ = 1, 20 do
    ram[0xFF8081] = (ram[0xFF8081] + 1) % 256
    R.service(D4)
    D4.pending_input_sequence = nil
  end
  queue_input_sequence = realq
  if #R.wait_log ~= 3 then
    fail("1 歩目 + 2 歩分", #R.wait_log, 3)
  else
    want("何歩目か", R.wait_log[2].index .. "," .. R.wait_log[3].index, "2,3")
    -- 数値待ちは打った値どおりに出る。ずれたらここが動く。
    want("実測は指定どおり",
         R.wait_log[2].ticks .. "," .. R.wait_log[3].ticks, "5,3")
    -- 指定値は持たない。行に書いてあるものを二度出さない。
    want("指定値は持たない", R.wait_log[2].set, nil)
    want("モード名", R.wait_log[2].mode, "Set")
    -- 操作 tick は wait とは別。単発ボタンは 1。
    want("操作 tick", R.wait_log[2].op .. "," .. R.wait_log[3].op, "1,1")
    -- 画面に出る文字列そのもの。HUD はこれを表示するだけ。
    want("表示行", R.wait_log_text(),
         "Step.1 Act:1 / Step.2 Wait:5 Act:1 / Step.3 Wait:3 Act:1")
    -- 右端で切れて新しいほうが消えていたので折り返す。区切りでのみ折る。
    do
      local w = R.wait_log_lines(40)
      want("40 桁なら 2 行", #w, 2)
      want("1 行目は続きを示す /",
           w[1], "Step.1 Act:1 / Step.2 Wait:5 Act:1 /")
      want("2 行目に残り", w[2], "Step.3 Wait:3 Act:1")
      for _i, _l in ipairs(w) do
        if #_l > 40 + 2 then fail("行が桁数を超えない", #_l, "<= 42") end
      end
      want("広ければ 1 行", #R.wait_log_lines(200), 1)
    end
  end

  -- コマンド入力は自分の入力に何 tick か使う。wait はその手前の空きなので、
  -- 別の数として出す。
  training_settings.action_sequences = { reversal = { ["16"] = { version = 1, steps = {
    { action = "atk", lever = "none", button = "LP", wait = 0 },
    { action = "custom", lever = "QCF", button = "HP", wait = 6 } } } } }
  R.cancel()
  local sched = R.schedule("reversal")
  -- QCF は {} {down} {down+forward} {forward+HP}。方向だけのエントリが 2 tick、
  -- ボタンが乗ると 1 tick なので 1 + 2 + 2 + 1 = 6。
  want("コマンドの操作 tick", sched[2].op_ticks, 6)
  want("単発は 1", sched[1].op_ticks, 1)
end

-- ループ 2 周目以降の 1 歩目は Loop Wait で出るので、行の数字が答えている
-- 問いが違う。名前で区別する。
print("\n[17] ループの wait は Loop と出す")
do
  local D5 = {}
  local realq = queue_input_sequence
  queue_input_sequence = function(d, seq) d.pending_input_sequence = { sequence = seq } end
  local P2 = 0xFF8800
  ram[0xFF8081] = 0
  ram[0xFF8B82] = 0x10
  ram[P2 + 0x06] = 0x00
  ram[P2 + 0x38] = 0
  ram[P2 + 0x21] = 0
  training_settings.action_steps_loop = true
  training_settings.action_steps_loop_wait = 4
  training_settings.action_sequences = { reversal = { ["16"] = { version = 1, steps = {
    { action = "atk", lever = "none", button = "LP", wait = 0 },
    { action = "atk", lever = "none", button = "MP", wait = 2 } } } } }
  R.cancel()
  R.arm("reversal")
  for _ = 1, 30 do
    ram[0xFF8081] = (ram[0xFF8081] + 1) % 256
    R.service(D5)
    D5.pending_input_sequence = nil
  end
  queue_input_sequence = realq
  training_settings.action_steps_loop = false
  -- 2 歩目 -> ループ -> 1 歩目 -> 2 歩目 ... と続く。
  local saw_loop = false
  for _, e in ipairs(R.wait_log) do if e.mode == "Loop" then saw_loop = true end end
  want("ループ再開に Loop の項目が出る", saw_loop, true)
  local loopw
  for _, e in ipairs(R.wait_log) do if e.mode == "Loop" then loopw = e.ticks end end
  want("その値は Loop Wait", loopw, 4)
  -- 待ちは Loop の項目が持ち、その後ろの Step.1 は Act だけを持つ。1 つに
  -- まとめると 4 がステップ 1 の設定に読め、両方に書くと 2 つの間隔を足した
  -- ように読める。
  -- 1 周ごとに捨てる。残すと行が伸びて、探している Loop が右端で切れる。
  want("Loop から始まる",
       R.wait_log_text():sub(1, 26), "Loop Wait:4 / Step.1 Act:1")
  want("前の周は残っていない",
       R.wait_log_text():find("Loop", 27, true), nil)
  want("Step.1 に Wait は付かない",
       R.wait_log_text():find("Step.1 Wait:", 1, true) ~= nil, false)
end


-- 走り終えた向きが次へ持ち越されないこと。
--
-- held_after は「押したあとも接触の間はレバーを残す」ための状態で、消えるのは
-- refresh_contact が $39 == 0 を見たときだけ。refresh_contact は M.service の
-- 中にあり、M.service はガードアクションが Action Steps のときしか呼ばれない。
-- つまり接触が続いたまま中断すると、向きが掴まれたまま残る。
print("\n[18] 中断と再武装で向きを離す")
do
  local D6 = {}
  local realq = queue_input_sequence
  queue_input_sequence = function(d, seq) d.pending_input_sequence = { sequence = seq } end
  local P2 = 0xFF8800
  ram[0xFF8081] = 0
  ram[0xFF8B82] = 0x10
  ram[P2 + 0x06]  = 0x0A
  ram[P2 + 0x38]  = 0
  ram[P2 + 0x1B2] = 0
  ram[P2 + 0x102] = 0
  ram[P2 + 0x101] = 0
  ram[P2 + 0x39]  = 1        -- 接触中。ここが続くかぎり自力では消えない
  training_settings.action_steps_loop = false
  training_settings.action_sequences = { reversal = { ["16"] = { version = 1, steps = {
    { action = "atk", lever = "none", button = "LP", wait = 0 },
    { action = "atk", lever = "down", button = "MP", wait = -1, timing = "chain" } } } } }
  R.cancel()
  R.arm("reversal")
  for _ = 1, 8 do
    ram[0xFF8081] = (ram[0xFF8081] + 1) % 256
    R.service(D6)
    D6.pending_input_sequence = nil
  end
  local function lev()
    local _l = R.waiting_lever()
    if _l == nil then return nil end
    if type(_l) ~= "table" then return tostring(_l) end
    return table.concat(_l, "+")
  end
  want("2 歩目が出て向きが残っている", lev(), "down")

  R.cancel()
  want("cancel で離す", lev(), nil)

  -- 再武装でも引き継がない。2 歩目に timing が無いリストで見る - timing が
  -- あると待っているステップ自身のレバーが返り、持ち越しと見分けがつかない。
  R.arm("reversal")
  for _ = 1, 8 do
    ram[0xFF8081] = (ram[0xFF8081] + 1) % 256
    R.service(D6)
    D6.pending_input_sequence = nil
  end
  want("もう一度残した", lev(), "down")
  training_settings.action_sequences = { reversal = { ["16"] = { version = 1, steps = {
    { action = "atk", lever = "none", button = "LP", wait = 0 },
    { action = "atk", lever = "none", button = "MP", wait = 5 } } } } }
  R.arm("reversal")
  want("arm でも引き継がない", lev(), nil)

  -- メニュー / エディタを開いている間は握らない。門はそこでは開かないので
  -- 握る意味が無く、開けっぱなしのあいだ入り続ける。ループの入切やタイミング
  -- 変更で「最後の入力が残る」と見えていたのはこれ。
  training_settings.action_sequences = { reversal = { ["16"] = { version = 1, steps = {
    { action = "atk", lever = "none", button = "LP", wait = 0 },
    { action = "atk", lever = "down", button = "MP", wait = -1, timing = "chain" } } } } }
  R.arm("reversal")
  ram[P2 + 0x39] = 0                 -- 接触がまだ来ていないので 2 歩目は待つ
  for _ = 1, 4 do
    ram[0xFF8081] = (ram[0xFF8081] + 1) % 256
    R.service(D6)
    D6.pending_input_sequence = nil
  end
  want("待っている間は握る", lev(), "down")
  globals.show_menu = true
  want("メニュー中は握らない", lev(), nil)
  globals.show_menu = false
  want("閉じれば戻る", lev(), "down")
  R.cancel()

  -- メニューを開いたら走っているパスは捨てる。凍結にしないのは、メニュー中も
  -- ティックが進むから - 数値 Wait はそこで経過し切り、Auto は棒立ちのダミーに
  -- 対して「動けるか」を訊くことになる。途中から再開しようがない。
  training_settings.action_steps_loop = false
  training_settings.action_sequences = { reversal = { ["16"] = { version = 1, steps = {
    { action = "atk", lever = "none", button = "LP", wait = 0 },
    { action = "atk", lever = "none", button = "MP", wait = 40 },
    { action = "atk", lever = "none", button = "HP", wait = 40 } } } } }
  R.arm("reversal")
  want("2 歩ぶん待っている", R.pending_count(), 2)
  local _dropped = R.steps_dropped
  -- 何かが配送途中の状態にしておく - これが残ると閉じた後に出てしまう。
  D6.pending_input_sequence = { sequence = { { "down" } }, seq_tick = true }
  globals.show_menu = true
  ram[0xFF8081] = (ram[0xFF8081] + 1) % 256
  R.service(D6)
  want("メニューで捨てる", R.pending_count(), 0)
  want("捨てた数を数えている", R.steps_dropped - _dropped, 2)
  -- 配送中のぶんも落とす。残すと、閉じた直後に古い走りの入力の続きが出る。
  want("配送中も落とす", D6.pending_input_sequence, nil)
  globals.show_menu = false
  ram[0xFF8081] = (ram[0xFF8081] + 1) % 256
  R.service(D6)
  want("ループ off なら戻ってこない", R.pending_count(), 0)

  -- ループは別。メニューを見ただけで止まってはいけない - 閉じたら頭から回る。
  training_settings.action_steps_loop = true
  training_settings.action_steps_loop_wait = 3
  R.arm("reversal")
  globals.show_menu = true
  ram[0xFF8081] = (ram[0xFF8081] + 1) % 256
  R.service(D6)
  want("ループでもそのパスは捨てる", R.pending_count(), 0)
  globals.show_menu = false
  for _ = 1, 30 do
    ram[0xFF8081] = (ram[0xFF8081] + 1) % 256
    R.service(D6)
    D6.pending_input_sequence = nil
  end
  -- 閉じても勝手には回り出さない。メニューを閉じ切る前にダミーが動き出すのは
  -- メニューを閉じる操作の結果として正しくない。
  want("閉じても回り出さない", R.pending_count(), 0)
  -- 次のガード機会で戻ってくる。
  R.arm("reversal")
  want("武装し直せば回る", R.pending_count(), 2)
  training_settings.action_steps_loop = false
  R.cancel()

  -- ループを回したままステップを編集したら、次の周から新しいリストになること。
  -- 以前は arm したときにコンパイルしたものを回し続けていたので、編集は次の
  -- 武装まで効かず、ループ中は永遠に来ないことがあった。
  training_settings.action_steps_loop = true
  training_settings.action_steps_loop_wait = 2
  training_settings.action_sequences = { reversal = { ["16"] = { version = 1, steps = {
    { action = "atk", lever = "none", button = "LP", wait = 0 },
    { action = "atk", lever = "none", button = "MP", wait = 2 } } } } }
  R.arm("reversal")
  want("2 歩で始まる", R.pending_count(), 1)
  -- エディタの保存と同じ形 - 新しいテーブルを書き込む。
  training_settings.action_sequences = { reversal = { ["16"] = { version = 1, steps = {
    { action = "atk", lever = "none", button = "LP", wait = 0 },
    { action = "atk", lever = "none", button = "MP", wait = 2 },
    { action = "atk", lever = "none", button = "HP", wait = 2 },
    { action = "atk", lever = "none", button = "LK", wait = 2 } } } } }
  for _ = 1, 40 do
    ram[0xFF8081] = (ram[0xFF8081] + 1) % 256
    R.service(D6)
    D6.pending_input_sequence = nil
    if R.pending_count() == 3 then break end
  end
  want("次の周は 4 歩のリスト", R.pending_count(), 3)

  -- 読み直しが nil を返したらループを止める。nil になるのは「このダミーの分が
  -- 無い」「保存が消えた」「編集が壊れている」のいずれかで、そのまま手元の周を
  -- 回し続けると、エディタがもう見せていない入力を出し続けることになる。
  local _saved = training_settings.action_sequences
  training_settings.action_sequences = {}
  for _ = 1, 60 do
    ram[0xFF8081] = (ram[0xFF8081] + 1) % 256
    R.service(D6)
    D6.pending_input_sequence = nil
  end
  want("読めなくなったらループは止まる", R.pending_count(), 0)
  -- 止まるだけで、壊れはしない。戻せば次のガード機会から普通に回る。
  training_settings.action_sequences = _saved
  R.arm("reversal")
  want("戻して武装し直せば回る", R.pending_count(), 3)
  training_settings.action_steps_loop = false
  R.cancel()

  queue_input_sequence = realq
  ram[P2 + 0x39] = 0
  ram[P2 + 0x06] = 0
end


-- つながらなかったときの締切。
--
-- チェーンもキャンセルも連打も、前の技の中でしか起きない。空振りなどで窓が
-- 開かないと、そのステップは頭に居座り、レバーを握ったまま残りが一切出ない。
-- 一本ミスっただけで走り全体が終わるのは、ドリルとしておかしい。
-- so Auto (After) - 前の技が終わったところ - を締切にして、そこを過ぎたら
-- つながらなくてもそのステップを出す。
print("\n[19] つながらなければ After で出す")
do
  local hits = {}
  local D7 = {}
  local realq = queue_input_sequence
  queue_input_sequence = function(d, seq)
    local p = {} for _, e in ipairs(seq) do p[#p+1] = table.concat(e, "+") end
    hits[#hits+1] = table.concat(p, " ")
    d.pending_input_sequence = { sequence = seq }
  end
  local P2 = 0xFF8800
  local function setup(timing)
    hits = {}
    ram[0xFF8081] = 0
    ram[0xFF8B82] = 0x0F
    ram[P2 + 0x05] = 0
    ram[P2 + 0x06] = 0
    ram[P2 + 0x38] = 0
    ram[P2 + 0x39] = 0
    ram[P2 + 0x21] = 0
    ram[P2 + 0x1B2] = 0
    ram[P2 + 0x102] = 0
    ram[P2 + 0x101] = 0
    ram[P2 + 0x110] = 0
    ram[P2 + 0x111] = 0
    training_settings.action_steps_loop = false
    training_settings.action_sequences = { reversal = { ["15"] = { version = 1, steps = {
      { action = "atk", lever = "none", button = "LP", wait = 0 },
      { action = "atk", lever = "none", button = "MP", wait = -1, timing = timing } } } } }
    R.cancel()
    R.arm("reversal")
  end
  local function run(n)
    for _ = 1, n do
      ram[0xFF8081] = (ram[0xFF8081] + 1) % 256
      R.service(D7)
      D7.pending_input_sequence = nil
    end
  end

  -- 技が出ているあいだは待つ。ここで出してしまうと、締切がチェーンの機会を
  -- 食い潰すことになる。
  setup("chain")
  ram[P2 + 0x06] = 0x0A          -- 通常技中。接触は無い = 空振り
  run(20)
  want("技が出ているあいだは出ない", #hits, 0)
  -- 技が終わった = After。ここでつながらなかったと分かる。
  ram[P2 + 0x06] = 0
  run(2)
  want("終わったら出る", #hits, 1)

  -- キャンセルも同じ。
  setup("cancel")
  ram[P2 + 0x06] = 0x0A
  run(20)
  want("キャンセルも待つ", #hits, 0)
  ram[P2 + 0x06] = 0
  run(2)
  want("キャンセルも終われば出る", #hits, 1)

  -- 連打も同じ。窓は前の技のセルに属している。
  setup("rapid")
  ram[P2 + 0x06] = 0x0A
  run(20)
  want("連打も待つ", #hits, 0)
  ram[P2 + 0x06] = 0
  run(2)
  want("連打も終われば出る", #hits, 1)

  -- 押した直後の 1 tick は「動ける」に見える。そこを締切と読むと、どの接続も
  -- 一度も試されないまま出てしまう。技が始まるのを見てからでないと数えない。
  setup("chain")
  run(3)                          -- まだ技が始まっていない
  want("始まる前は締切にしない", #hits, 0)

  -- 締切は 1 ステップにつき 1 回。出たあとに latch が残っていると、次の
  -- ステップが同じ「動ける」をそのまま締切として読み、続けざまに出てしまう。
  training_settings.action_sequences = { reversal = { ["15"] = { version = 1, steps = {
    { action = "atk", lever = "none", button = "LP", wait = 0 },
    { action = "atk", lever = "none", button = "MP", wait = -1, timing = "chain" },
    { action = "atk", lever = "none", button = "HP", wait = -1, timing = "chain" } } } } }
  hits = {}
  ram[0xFF8081] = 0
  ram[P2 + 0x06] = 0
  ram[P2 + 0x39] = 0
  R.cancel()
  R.arm("reversal")
  ram[P2 + 0x06] = 0x0A
  run(10)
  ram[P2 + 0x06] = 0
  run(2)
  want("2 歩目が締切で出る", #hits, 1)
  run(6)
  want("3 歩目は続けて出ない", #hits, 1)
  ram[P2 + 0x06] = 0x0A
  run(4)
  ram[P2 + 0x06] = 0
  run(2)
  want("3 歩目も自分の窓を待って出る", #hits, 2)

  -- つながったときは締切を待たない。
  setup("chain")
  ram[P2 + 0x06] = 0x0A
  ram[P2 + 0x39] = 1              -- 接触あり
  ram[P2 + 0x102] = 0             -- 小 -> 中はランクが上
  run(2)
  want("つながればその場で出る", #hits, 1)

  queue_input_sequence = realq
  ram[P2 + 0x06] = 0
  ram[P2 + 0x39] = 0
end

print(fails==0 and "\n全て通った" or ("\n"..fails.." 件 NG"))
os.exit(fails==0 and 0 or 1)
