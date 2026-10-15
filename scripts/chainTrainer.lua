-- CHAIN TRAINER (Trainer tab, 2026-10-14).
--
-- What the game's own cancel check did with the presses after each hit of a
-- normal attack, and whether a link out of a finished normal combo'd - one
-- line per link (handoff 2026-10-14, sections 6, 7 and 9). The rows come from
-- chainLog.lua's exec hooks; nothing here reads the inputs itself or guesses
-- what the game would accept.
--
-- DRAWN AS AIR GUARD GAPS IS (user, 2026-10-15: the band of the first
-- version could not be read - "AirGap くらいメモリがはっきり"). One glyph per
-- tick; label, ticks, result on one line. At AirGap's height and spacing, but
-- further right: "コンボ練習だからコンボ数は出るようにしたい、ゆえにもう少し右に
-- 寄せる" (same day) - the game's hit count is drawn under the attacker's life
-- bar on its own side, which AirGap's x 21 covered for P1. x 104 is a first
-- guess at clearing it, not a measured edge. Under AirGap's lines when both
-- are on. GC Command Trainer and Seq. Command Trainer are not drawn while this
-- is on: from here it reaches their boxes (hud.lua, commandTrainer.lua).
--
-- A CHAIN OR RAPID LINE: 1t is the first tick a new press counts (C+1, C =
-- the body contact that sets the attacker's $169 to 14), as AirGap's 1t is
-- your first tick:
--   -   $169 not 0 and hit stop running: a press here is held in $12E and
--       judged when the stop ends
--   =   the check ran with $169 not 0: a press here is judged on the tick
--   .   outside that: past the window, or a rapid cancel's line (its window,
--       the cel's bit 0, has not been measured)
--   P K a press, in its strength's colour - the dummy input column's, as
--       AirGap's (two on one tick show the heavier)
--   |   the cancel came out (when no press is on that tick). The line ends
--       there: after it the old move is gone and nothing more is observed.
-- Both window marks come from this hit's own values (VSAV_MEMORY_NOTES,
-- section 14: 13 ticks with hit stop 11 on every hit measured), not from a
-- fixed 13 - a move that ends early ends its window.
-- Results, capitals first as AirGap's: CHAIN Nt (the press on Nt was taken),
-- RAPID, LATE Nt (after the window's last tick), EARLY Nt (only a press before
-- the hit, in the move before it: Nt before 1t), MULTI (two or more buttons
-- in $12E | $126 - held ones from different Ticks of hit stop count too -
-- 028F78), NO CHAIN (the button is not one the move chains into, 028E98), ?
-- (in the window, refused for another reason), HIT (got hit). A link with no
-- press is not kept once it ends.
--
-- A LINK LINE (user, 2026-10-15: "弱から弱の目押しコンボをつないだのをわかる
-- ように", and "ダッシュ中Pから小Pの目押しも"): a move that hit and ended,
-- then a fresh press for the next one, which hit. 1t is the first tick you
-- could act after it - on the ground, $05 0 and $06 0x00 (standing), 0x02
-- (crouching), 0x04 (walking) or the landing 0x06 / 0x04 (free(), below) - so
-- a dash attack (D.MP: $06 stays 0x14 through it and its landing) counts the
-- same as a normal. The P / K is the press that started the second. The
-- result is the other side's state just before the second hit (chainLog's
-- opp05 / opp140, read ahead of the game rewriting it):
--   LINK Nt  still in hit stun ($05 2, $140 not a block): it combo'd
--   GUARD Nt in block stun ($140 0x02 / 0x12): a block string, not a combo
--   GAP Nt   out of stun ($05 not 2): they could act - no combo
-- A press on the first tick they could act is not a combo; this only reads
-- whether the stun was still running when the hit landed (handoff 6). Air
-- links are not judged ($06 does not say a normal is running in the air).
--
-- AND THE LAST PRESS THAT WOULD HAVE LINKED: /Mt (user, 2026-10-15: "Linkの
-- 猶予を正確にだすことはできる？" / "リバーサルフレームからガードが可能になる").
-- The second hit has to land before the other side's reversal tick R - from
-- R a guard comes out. R comes from chainLog's rows of the other side: its
-- sig if it got there, else its react (the impact freeze over) plus
-- M.REV_LEAD by the stun class $59 - 13 / 18 / 22 Ticks on the game clock,
-- every one of 77 hits (Anakaris's normals on Morrigan, v11.7.25.2_13). With
-- d the Ticks from this press to this hit, the last press that lands before R
-- is on R - d - F, F the first free tick (1t). So LINK 3t/5t was pressed on
-- 3t and would have linked up to 5t at this distance; GAP 7t/5t was two late.
-- The window is drawn as = on the line. A result the prediction disagrees
-- with (a LINK past M, a GAP inside it) drops the /Mt rather than show both.
--
-- AND A LINK PRESSED TOO EARLY: EARLY Nt/Mt (red). A press past the chain
-- window but before the move was over brings nothing out; when that button
-- could have linked from there it is a link line, not the chain's LATE - see
-- early_link. The P comes first, a . for each Tick still in the move, then
-- the window from 1t: P..= is EARLY 3t/1t.
--
-- SPECIALS, ES, EX AND DARK FORCE BY NAME (user, 2026-10-15: "ES、SP、EXなど
-- をかいて"): the attacker's $06 becoming 0x0E (special), 0x10 (ES), 0x12 (EX)
-- or 0x16 (Dark Force) - VSAV_MEMORY_NOTES' $06 table - is that move coming
-- out. Inside a normal that hit, it is a cancel: the line ends there with
-- SP / ES / EX / DF Nt, N the press that brought it out (the last press up to
-- that tick). No window is drawn - a special's cancel window is not the
-- chain's and has not been measured - only the press and |. After a normal
-- ended, it is a link like any other (MK > SP LINK 3t/5t), and a special that
-- hit names the next line (SP > LP).
--
-- AND WHETHER THE CANCEL COMBO'D: /Mt (user, 2026-10-15: "必殺技がつながらな
-- かったとき、何Tick遅かったかは出せる？"). Read off the other side, not the
-- body contact: Bishamon's specials hit with something else first (the
-- other side's freeze began 18 to 29 Ticks before their body touched,
-- v11.7.25.2_18), and the contact row sees only a body. So the special's first
-- hit is chainLog's first `hit` row of the other side after it came out (the
-- update after the hit: H = that tick - 1), and it combo'd if they were in
-- stun and not blocking on the update before. With R the reversal tick of the
-- normal's stun (its react + M.REV_LEAD, or its sig if it came first), the
-- last press that still lands before R is M = n + (R - 1 - H). SP 8t/10t
-- combo'd with two to spare; SP 8t/6t (red) was two late. This is the combo's
-- deadline, not the cancel's: how late a special can still cancel the normal
-- has not been measured. A special that never hits gets no /Mt.
--
-- A PURSUIT IS NOT A NORMAL (user, 2026-10-15: "追い打ちは通常技扱いしないで"):
-- a hit on the other side while it is down ($140 0x0A before the hit, the
-- knockdown) makes no line - no chain window, no link - and the presses before
-- it were its own. Measured on Bishamon (v11.7.25.2_18): his pursuit hits with
-- $06 0x0E in the air, so it read as SP > LP EARLY 12t, the LP being the
-- pursuit's button.
--
-- Nor is a special's own hit a chain: a special, ES, EX or DF that hits
-- opens no chain line (the chain is between normals), and what was pressed
-- during it is not early for anything. It is still a link's start - SP > LP
-- LINK 3t/5t. Same session: presses during Bishamon's specials read as
-- SP > LP EARLY on 17 lines.
--
-- A NEW COMBO STARTS AT THE TOP (user, 2026-10-15: "10tick以上あいた場合は一行
-- 目からかきなおし"): a hit that lands M.FRESH_GAP or more Ticks after the
-- other side could act again clears the lines first. Inside a combo the other
-- side never gets there, so nothing is cleared.

local M = {}
local chainLog = require "./scripts/chainLog"

M.MAX_ROWS = 6                -- lines kept (display space, not game time)
M.MAX_BAR = 22                -- ticks drawn on a line: 13 window + 9 past it
M.SPAN = 40                   -- Ticks after the hit a chain line may stay open
M.LINK_SPAN = 60              -- Ticks after a normal ends a link may start
-- From react to the reversal tick, by $59 (see the top). Ground hit stun only
-- ($140 0x00); anything else has no number here and gets no /Mt.
M.REV_LEAD = { [0] = 13, [1] = 18, [2] = 22 }
-- A press this many Ticks past the last one that would have linked is the
-- next attack, not a link that missed (v11.7.25.2_13: single hits waited out,
-- then GAP 38t/3t). Not a line.
M.LINK_LATE_MAX = 10
M.FRESH_GAP = 10

local rows = {}               -- finished lines, oldest first
local cur = nil               -- the chain being measured
local pre = {}                -- presses inside a normal before its hit
local seen_char = nil
-- The link being followed: was the last update inside a normal, the first
-- tick out of it, the press that started the next, the move that hit, and the
-- other side's react row and reversal tick since that hit.
local link = { busy = false, free_at = nil, starter = nil, last_hit = nil, react = nil, sig = nil }
-- A special cancel's line waiting for the special's first hit on the other
-- side: { row, C, n, start, react, sig, until }.
local sp_wait = nil
-- The tick the other side could last act again after a stun (its sig), kept
-- until it is hit again: a hit this long after it starts a new combo.
local opp_free_at = nil
-- STARTUPS SEEN (early_link): the Ticks from a press on a free tick to the
-- first contact of the ground normal it brought out, the fewest seen, by
-- attacker, other side, strength, punch / kick and the lever down on the
-- press - a crouching normal is a move of its own, though no startup in the
-- logs has differed by it yet. The fewest, as the same move does not always
-- hit on the same Tick: char 0x08's LP with the lever 0x02 held (walking, or
-- setting off) on 5, 13 of 13, from neutral or down on 4, 3 of 3
-- (v11.7.25.2_27) - the distance, presumably. Only a press's, not a chain's: counted
-- from the accept the same moves came out a Tick later or sooner (Felicia's
-- LP / LK / MP 5 against 4, HK 8 against 7; char 0x08's MP 4 against 6), and a
-- link is a press. Facts about the moves, so kept across M.reset().
M.startup = {}
local opp_char = nil
-- The measured side's lever ($123) and whether it was free, on the last tick
-- it had a row, and on the tick before that one when it had a row too.
local lv = { tick = nil, now = nil, prev = nil }
-- The ground normal that began, until its first contact: { tick, str, typ, key }.
local started = nil

-- 2 P1, 3 P2; 1 (or anything else) Off.
function M.side()
	local v = globals ~= nil and globals.options ~= nil and globals.options.chain_trainer
	if v == 2 then return 1 elseif v == 3 then return 2 end
	return nil
end
function M.is_visible() return M.side() ~= nil end

function M.reset()
	rows, cur, pre, seen_char, mv, last06 = {}, nil, {}, nil, nil, nil
	link = { busy = false, free_at = nil, starter = nil, last_hit = nil, react = nil, sig = nil }
	opp_free_at = nil
	sp_wait = nil
	lv = { tick = nil, now = nil, prev = nil }
	started = nil
end

local BTN = { { 0x0100, "LP" }, { 0x0200, "MP" }, { 0x0400, "HP" },
              { 0x1000, "LK" }, { 0x2000, "MK" }, { 0x4000, "HK" } }
local function has(w, b) return math.floor(w / b) % 2 == 1 end
function M.names(w)
	local out = {}
	for _, k in ipairs(BTN) do if has(w, k[1]) then out[#out + 1] = k[2] end end
	return table.concat(out, "+")
end
local function b06(state) return math.floor(state / 0x100) % 0x100 end
local function b05(state) return math.floor(state / 0x10000) % 0x100 end
local function down(lever) return lever ~= nil and math.floor(lever / 4) % 2 == 1 end
local function startup_key(char, opp, str, typ, dn)
	return string.format("%d:%d:%d:%d:%s", char or -1, opp or -1, str or -1, typ or -1, dn and "d" or "n")
end
M.startup_key = startup_key
-- A single button's move: $102 strength, $101 punch (0) / kick (2).
local BTN_MOVE = { [0x0100] = { 0, 0 }, [0x0200] = { 2, 0 }, [0x0400] = { 4, 0 },
                   [0x1000] = { 0, 2 }, [0x2000] = { 2, 2 }, [0x4000] = { 4, 2 } }
-- $06 of a move that is not a normal, by its name.
M.SPECIAL = { [0x0E] = "SP", [0x10] = "ES", [0x12] = "EX", [0x16] = "DF" }
-- $102 strength (0 / 2 / 4), $101 type (0 punch, 2 kick), $38 airborne; a
-- dash attack is one done in the dash state ($06 0x14), in the air or not.
local STR = { [0] = "L", [2] = "M", [4] = "H" }
function M.move_name(str, typ, air, state)
	if state ~= nil and M.SPECIAL[b06(state)] ~= nil then return M.SPECIAL[b06(state)] end
	local pre = ""
	if state ~= nil and b06(state) == 0x14 then pre = "D."
	elseif air ~= nil and air ~= 0 then pre = "J." end
	return pre .. (STR[str] or "?") .. ((typ == 2) and "K" or "P")
end

-- Free to start a move: on the ground, $05 0 and $06 0x00 (standing), 0x02
-- (crouching - with $05 0 it is not a hurt) or 0x04 (walking); VSAV_MEMORY_NOTES
-- section 5. Anything else on the ground is in a move (a normal 0x0A, a dash
-- attack 0x14, a landing 0x06, a special...). The crouch was missing: a link
-- into a crouching MK read as LATE 12t on the standing MP's line, its press
-- made from 0x02 (user, 2026-10-15, v11.7.25.2_22: "小中チェーンから、目押しで
-- MKをつないだケース").
--
-- AND THE LANDING, $06 0x06 / $07 0x04 on the ground: Felicia's dash MP is in
-- the air, lands as 0x14 / 0x08 and goes on to 0x06 / 0x04 - and a press there
-- starts a move on the next update, 13 of 13, from its first tick on, where 23
-- of 23 in the 0x14 / 0x08 before it started nothing (v11.7.25.2_26; no other
-- character's landing in the logs). Missing, her D.MP > crouching LP read as
-- LATE 8t on the D.MP's line though it combo'd (user, 2026-10-15: "ダッシュMPから
-- しゃがみ小Pがつながったケース。コンボならつないでほしい"). Before the jump
-- leaves the ground $06 is 0x06 too, with $07 0x02 (0x025286 writes 02 00 06
-- 02, VSAV_MEMORY_NOTES).
local function free(r)
	local s6 = b06(r.state or 0)
	if (r.air or 0) ~= 0 or b05(r.state or 0) ~= 0 then return false end
	if s6 == 0x06 then return (r.state or 0) % 0x100 == 0x04 end
	return s6 == 0x00 or s6 == 0x02 or s6 == 0x04
end
-- In a move on the ground: a press there is not the press that started it.
local function attacking(r) return (r.air or 0) == 0 and not free(r) end

-- WHICH PRESS STARTED THE MOVE (user, 2026-10-15: "一行目が謎" - D.LK > LK
-- EARLY 5t, where that LK was the one that made the dash attack). The press
-- that starts a move is read before the move has begun, so it lands in `pre`
-- with the presses inside the move; a move's start clears `pre`, and only the
-- presses after it are early. The start is airGuardGap.lua's move_start, on
-- the same fields: $1B8 moving; $105 rising outside a dash; a new strength /
-- punch-kick with $105 up (a chain); inside a dash already on, $105 rising
-- (a dash raises $105 by itself for some characters, Zabel's on its first
-- tick, so that tick only learns the values).
local mv = nil
-- The measured side's $06 on its last row: a special starting is a change into
-- one of M.SPECIAL.
local last06 = nil
local function move_started(r)
	local s, f, s06 = r.s1b8 or 0, r.f105 or 0, b06(r.state or 0)
	local id = (f ~= 0) and ((r.str or 0) * 256 + (r.typ or 0)) or nil
	local fresh = false
	if mv ~= nil then
		local rise = f ~= 0 and mv.f == 0
		fresh = s ~= mv.seq
			or (s06 ~= 0x14 and (rise or (id ~= nil and mv.id ~= nil and id ~= mv.id)))
			or (s06 == 0x14 and mv.s06 == 0x14 and rise)
	end
	mv = { seq = s, f = f, id = id, s06 = s06 }
	return fresh
end

local function push_row(row)
	rows[#rows + 1] = row
	while #rows > M.MAX_ROWS do table.remove(rows, 1) end
end

-- NO CHAIN LINE TO THE SAME BUTTON (user, 2026-10-15: "HK→HKのつなぎはない。同じ
-- ボタンへのつなぎは書かないで"). A chain never goes from a move to its own
-- button - 028E98's mask leaves it out (VSAV_MEMORY_NOTES section 14: HK
-- held in a standing HK fell there on every check) - so HK > HK EARLY / LATE /
-- MULTI / NO CHAIN says nothing. RAPID and LINK lines are a different thing
-- and do happen to the same button (LP > LP), so they stay.
local function same_button(c)
	return c.tgt ~= nil and c.src ~= nil and (c.src:gsub("^[DJ]%.", "")) == c.tgt
end
local function push_chain_row(c)
	if same_button(c) then return end
	push_row(c)
end

local function window_last(c)
	local last = nil
	for t, _ in pairs(c.band) do if last == nil or t > last then last = t end end
	return last
end

-- The other side's reversal tick, as far as it is known: seen, or predicted
-- from its react (M.REV_LEAD).
local function reversal_tick()
	local L = link
	if L.sig ~= nil then return L.sig end
	if L.react ~= nil and L.react.s140 == 0 and M.REV_LEAD[L.react.s59] ~= nil then
		return L.react.tick + M.REV_LEAD[L.react.s59]
	end
	return nil
end

-- A PRESS PAST THE CHAIN WINDOW, STILL INSIDE THE MOVE, AIMED AT A LINK (user,
-- 2026-10-15: "チェーン受付終了後でも、猶予的に目押しが可能な組み合わせならそちらを
-- 狙ったとして判断してほしい"). Felicia's crouching LP > MP: the MP pressed 3
-- Ticks before the LP was over, so it never came out (a normal is free+0), and
-- it read as the chain's LATE 4t. When that button could have linked, it is a
-- link line instead: with d its startup (M.startup, for that button and the
-- lever on the press), F the first free tick and R the other side's reversal
-- tick, the last press that lands before R is M = R - d - F, and 1t or more
-- means it could. EARLY 3t/1t: three Ticks before 1t, and a press on 1t would
-- have linked. No startup seen for it yet, no reversal tick, or M under 1t:
-- the chain's LATE, as before. The last press is the one judged - the closest
-- to 1t.
local function early_link(c, F)
	local p = nil
	for _, q in ipairs(c.presses) do if q.t > c.window_last then p = q end end
	local bm = p and BTN_MOVE[p.b]
	local R = reversal_tick()
	if bm == nil or R == nil then return false end
	local d = M.startup[startup_key(seen_char, opp_char, bm[1], bm[2], p.down)]
	if d == nil then return false end
	local m = R - d - F
	if m < 1 then return false end
	local k = F - (c.C + 1 + p.t)
	push_row({ link = true, src = c.src, tgt = M.names(p.b), press_t = -k, press_b = p.b,
	           result = "EARLY " .. k .. "t/" .. m .. "t", last_ok = m, late = true })
	return true
end

-- The chain line's result, once nothing more can change it. t is 0 on C+1
-- here and shown one up: the first tick is 1t. F: the first free tick, when
-- the move's end is what closes it.
local function close(c, why, F)
	cur = nil
	local last = window_last(c)
	c.window_last = last
	if c.accept ~= nil then
		local a = c.accept
		c.tgt = M.names(a.b)
		if a.kind == "special" then
			-- The press that brought it out: the last one up to its tick.
			local pick = nil
			for _, p in ipairs(c.presses) do if p.t <= a.t then pick = p end end
			c.tgt = a.label
			local pt = (pick and pick.t) or a.t
			c.result = a.label .. " " .. (pt + 1) .. "t"
			push_row(c)
			sp_wait = { row = c, C = c.C, n = pt + 1, start = c.C + 1 + a.t, react = link.react,
			            ["until"] = c.C + 1 + a.t + M.LINK_SPAN }
			return
		end
		if a.kind == "chain" then
			local pick = nil
			for _, p in ipairs(c.presses) do
				if c.band[p.t] ~= nil and a.b ~= 0 and has(p.b, a.b) then pick = p break end
			end
			c.result = "CHAIN " .. (((pick and pick.t) or a.t) + 1) .. "t"
		else
			c.result = "RAPID"
		end
		push_row(c)
		return
	end
	local inside, late = nil, nil
	local all = 0
	for _, p in ipairs(c.presses) do
		if c.band[p.t] ~= nil then
			inside = inside or p
			for _, k in ipairs(BTN) do
				if has(p.b, k[1]) and not has(all, k[1]) then all = all + k[1] end
			end
		elseif last ~= nil and p.t > last and late == nil then
			late = p
		end
	end
	if why == "hit" and (inside ~= nil or late ~= nil or #c.early > 0) then
		c.tgt = M.names((inside or late or c.early[#c.early]).b)
		c.result = "HIT"
		push_chain_row(c)
		return
	end
	if inside ~= nil then
		local multi, nomask = false, false
		for t, s in pairs(c.stages) do
			if t >= inside.t then
				if s == "buttons" then multi = true elseif s == "mask" then nomask = true end
			end
		end
		c.tgt = (all ~= 0) and M.names(all) or M.names(inside.b)
		c.result = multi and "MULTI" or (nomask and "NO CHAIN" or "?")
		push_chain_row(c)
	elseif late ~= nil then
		if F ~= nil and early_link(c, F) then return end
		c.tgt = M.names(late.b)
		c.result = "LATE " .. (late.t - last) .. "t"
		push_chain_row(c)
	elseif #c.early > 0 then
		local e = c.early[#c.early]
		c.tgt = M.names(e.b)
		-- e.t is 0 on 1t: a press on the hit's own tick is -1, one tick early.
		c.result = "EARLY " .. (-e.t) .. "t"
		push_chain_row(c)
	elseif #c.presses > 0 then
		c.tgt = M.names(c.presses[1].b)
		c.result = "?"
		push_chain_row(c)
	end
end

-- The first hit on the other side of a special that cancelled a normal (its
-- `hit` row): did it combo, and the last press that would have.
local BLOCK = { [0x02] = true, [0x12] = true }
local function special_on_hit(r)
	local S = sp_wait
	sp_wait = nil
	if S == nil or r.tick > S["until"] then return end
	local H = r.tick - 1
	local R = nil
	if S.sig ~= nil and S.sig <= H then R = S.sig
	elseif S.react ~= nil and S.react.s140 == 0 and M.REV_LEAD[S.react.s59] ~= nil then
		R = S.react.tick + M.REV_LEAD[S.react.s59]
	end
	if R == nil then return end
	local m = S.n + (R - 1 - H)
	-- THEIR REVERSAL TICK SEEN BEFORE THE HIT: NOT A COMBO, whatever $05 says.
	-- The update before a hit on that tick reads the mark 0x02020400, whose $05
	-- is 2 as well (VSAV_MEMORY_NOTES section 5) - so it looked like a stun.
	-- Measured 2026-10-15 (v11.7.25.2_20, Bishamon LK > SP): sig on C+26, the
	-- freeze on the next update, and the game's count did not go on (user:
	-- "これはつながらなかった").
	local combo
	if S.sig ~= nil and S.sig <= H then combo = false
	else combo = r.prev05 == 0x02 and not BLOCK[r.prev140 or 0] and not BLOCK[r.s140 or 0] end
	-- The game and the window have to agree, or the window is not shown.
	if (combo and S.n > m) or (not combo and S.n <= m) then
		S.row.mismatch = true
		return
	end
	S.row.result = S.row.result .. "/" .. math.max(m, 0) .. "t"
	S.row.last_ok = math.max(m, 0)
	S.row.late = not combo or nil
end

-- A normal hit: was it the second half of a link?
local function link_on_contact(r)
	local L = link
	if L.starter ~= nil and L.last_hit ~= nil and L.free_at ~= nil
	   and L.starter.tick >= L.free_at and r.tick - L.free_at <= M.LINK_SPAN
	   and (r.air or 0) == 0 and r.opp05 ~= nil then
		local n = L.starter.tick - L.free_at + 1
		-- The other side's reversal tick: seen, or predicted from its react.
		local R = reversal_tick()
		local last_ok = nil
		if R ~= nil then last_ok = R - (r.tick - L.starter.tick) - L.free_at end
		local kind
		if r.opp05 == 0x02 and (r.opp140 == 0x02 or r.opp140 == 0x12) then kind = "GUARD"
		elseif r.opp05 == 0x02 then kind = "LINK"
		else kind = "GAP" end
		-- THEIR REVERSAL TICK SEEN, AND NOT HIT SINCE: NOT A COMBO, whatever
		-- $05 says - as special_on_hit (review, 2026-10-15). The mark
		-- 0x02020400 has $05 2, so a hit on that very Tick would read as a stun.
		-- Not seen in the archives: 424 hits after a sig with no hit between
		-- (v11.7.25.2_13 to v11.7.26_5), all with $05 0, GAP already. A hit in
		-- between (a projectile's react after the sig) is a new stun: left alone.
		if kind == "LINK" and L.sig ~= nil and r.tick >= L.sig
		   and (L.react == nil or L.react.tick < L.sig) then
			kind = "GAP"
		end
		-- What the game did and what the window says have to agree, or the
		-- window is not shown.
		local agree = last_ok ~= nil
		if agree and kind == "LINK" and n > last_ok then agree = false end
		if agree and kind == "GAP" and n <= last_ok then agree = false end
		local res = kind .. " " .. n .. "t"
		if agree then res = res .. "/" .. math.max(last_ok, 0) .. "t" end
		if agree and n - math.max(last_ok, 0) >= M.LINK_LATE_MAX then
			L.starter, L.free_at, L.react, L.sig = nil, nil, nil, nil
			L.last_hit = M.move_name(r.str, r.typ, r.air, r.state)
			return
		end
		push_row({ link = true, src = L.last_hit, tgt = M.move_name(r.str, r.typ, r.air, r.state),
		           press_t = n - 1, press_b = L.starter.b, result = res,
		           last_ok = agree and last_ok or nil, mismatch = (last_ok ~= nil and not agree) or nil })
	end
	L.starter, L.free_at = nil, nil
	L.react, L.sig = nil, nil
	L.last_hit = M.move_name(r.str, r.typ, r.air, r.state)
end

-- One row from chainLog.lua.
function M.on_row(r)
	local side = M.side()
	if side == nil then return end
	-- The other side: only its recovery, for the link window.
	if r.p ~= side then
		if r.char ~= nil then opp_char = r.char end
		if r.kind == "react" then
			link.react = r ; opp_free_at = nil
			if sp_wait ~= nil and sp_wait.react == nil then sp_wait.react = r end
		elseif r.kind == "sig" then
			link.sig = r.tick ; opp_free_at = r.tick
			if sp_wait ~= nil and sp_wait.sig == nil and r.tick > sp_wait.start then sp_wait.sig = r.tick end
		elseif r.kind == "hit" and sp_wait ~= nil and r.tick > sp_wait.start then
			special_on_hit(r)
		end
		return
	end
	if seen_char ~= nil and r.char ~= seen_char then M.reset() end
	seen_char = r.char
	if r.lever ~= nil and r.tick ~= lv.tick then
		lv.prev = (lv.tick == r.tick - 1) and lv.now or nil
		lv.tick, lv.now = r.tick, { lever = r.lever, free = free(r) }
	end
	-- Past its span, whatever comes next is not part of it. registerAfter does
	-- the same once a frame; this covers a row that arrives first.
	if cur ~= nil and r.tick - cur.C > M.SPAN then close(cur) end
	if r.kind == "contact" then
		-- The startup of the ground normal that hit (a pursuit's is its own).
		local s = started
		started = nil
		if s ~= nil and r.opp140 ~= 0x0A and (r.air or 0) == 0 and r.str == s.str and r.typ == s.typ then
			local d = r.tick - (s.tick - 1)
			if M.startup[s.key] == nil or d < M.startup[s.key] then M.startup[s.key] = d end
		end
		if cur ~= nil then close(cur) end
		if r.opp140 == 0x0A then
			pre = {}
			link.starter, link.free_at, link.react, link.sig, link.last_hit = nil, nil, nil, nil, nil
			opp_free_at = nil
			sp_wait = nil
			return
		end
		if opp_free_at ~= nil and r.tick - opp_free_at >= M.FRESH_GAP then rows = {} end
		opp_free_at = nil
		link_on_contact(r)
		if M.SPECIAL[b06(r.state or 0)] ~= nil then
			pre = {}
			return
		end
		local early = {}
		for _, p in ipairs(pre) do early[#early + 1] = { t = p.tick - r.tick - 1, b = p.b } end
		cur = { C = r.tick, src = M.move_name(r.str, r.typ, r.air, r.state), band = {}, presses = {},
		        early = early, stages = {} }
		pre = {}
		return
	end
	if r.kind == "tick" then
		-- A move began: the presses before it were not inside it. A ground
		-- normal out of a free tick is where a startup counts from: the update
		-- before, the press, with its lever.
		if move_started(r) then
			pre = {}
			started = nil
			if b06(r.state or 0) == 0x0A and (r.air or 0) == 0 and lv.tick == r.tick
			   and lv.prev ~= nil and lv.prev.free then
				started = { tick = r.tick, str = r.str, typ = r.typ,
				            key = startup_key(r.char, opp_char, r.str, r.typ, down(lv.prev.lever)) }
			end
		end
		local s6 = b06(r.state or 0)
		local sp = M.SPECIAL[s6]
		-- Into one, or from one to another (an ES into a pursuit, a super cancel).
		local sp_start = sp ~= nil and last06 ~= nil and last06 ~= s6
		last06 = s6
		local b = chainLog.buttons(r.edge)
		if sp_start then
			-- A cancel out of the normal that hit: that line ends with it.
			--
			-- EVEN WHEN NOTHING WAS PRESSED SINCE THE HIT (user, 2026-10-15:
			-- "キャンセル必殺技がつながる、つながらないの判断にいいから"). Bishamon's
			-- crouching MP was in 0x0E on the update after it hit, its hit stop
			-- at 11 (v11.7.25.2_24), and the line read MP > SP SP 1t/0t: no press
			-- to number, so the tick it came out; whether it combo'd is still
			-- read off the other side. Kept as it is.
			if cur ~= nil and r.tick > cur.C then
				if b ~= 0 then cur.presses[#cur.presses + 1] = { t = r.tick - cur.C - 1, b = b } end
				cur.accept = { t = r.tick - cur.C - 1, kind = "special", label = sp, b = 0 }
				close(cur)
			end
			pre = {}
		end
		local atk = attacking(r)
		local is_free = free(r)
		-- The first free tick after a move: a link counts from it, and the
		-- chain line ends - the move is over, nothing chains out of it any more,
		-- and a press from here (a jump's J.MK, say) is the next move's.
		if link.busy and is_free then
			link.free_at, link.starter = r.tick, nil
			if cur ~= nil and r.tick > cur.C then close(cur, nil, r.tick) end
		end
		link.busy = not is_free
		if b ~= 0 and is_free and link.starter == nil and link.free_at ~= nil then
			link.starter = { tick = r.tick, b = b }
		end
		if cur ~= nil and r.tick > cur.C then
			if b05(r.state or 0) == 0x02 then close(cur, "hit") return end
			-- THE MOVE IS OVER: A PRESS NOW STARTS A NEW ONE. Not a late chain -
			-- it is the next normal (a link, judged at its hit), so the chain
			-- line ends without it. On the ground only: in the air $06 does not
			-- say a normal is running.
			if b ~= 0 and is_free then
				close(cur)
				pre = {}
				return
			end
			local t = r.tick - cur.C - 1
			if r.t169 > 0 and r.hs > 0 then cur.band[t] = "held" end
			if b ~= 0 then cur.presses[#cur.presses + 1] = { t = t, b = b, down = down(r.lever) } end
		elseif b ~= 0 then
			if atk then pre[#pre + 1] = { tick = r.tick, b = b } else pre = {} end
		end
		return
	end
	if r.kind ~= "check" then return end
	local acc = (r.accept ~= nil and r.accept ~= "") and r.accept or nil
	if cur ~= nil and r.tick > cur.C then
		local t = r.tick - cur.C - 1
		if r.t169 > 0 and r.hs == 0 then cur.band[t] = "judged" end
		if not r.quiet then cur.stages[t] = r.stage end
		if acc ~= nil then
			-- 028ED0: D0 is the one button left after the mask. 028FF0: D1 is
			-- the bit of the button the move's own strength asks for.
			local ab = (acc == "chain") and chainLog.buttons(r.d0) or (2 ^ ((r.d1 or 8) % 16))
			cur.accept = { t = t, kind = acc, b = ab }
			close(cur)
			pre = {}
		end
	elseif acc == "rapid" then
		-- A rapid cancel out of a move that hit nothing: no hit to count from.
		push_row({ src = M.move_name(r.str, r.typ, r.air, r.state), tgt = M.names(2 ^ ((r.d1 or 8) % 16)),
		           band = {}, presses = {}, early = {}, result = "RAPID", nometer = true })
		pre = {}
	end
	-- A cancel is not a link: the next hit comes out of no free tick.
	if acc ~= nil then link.free_at, link.starter = nil, nil end
end

-- After the frame: a line past its span is over, and the setting decides.
function M.registerAfter()
	if M.side() == nil then
		if cur ~= nil or #rows > 0 then M.reset() end
		return
	end
	-- chainLog's clock: the game's tick counter, the one the rows carry.
	if cur ~= nil and chainLog.clock ~= nil and chainLog.clock() - cur.C > M.SPAN then
		close(cur)
	end
	if M.last_side ~= M.side() then M.reset() end
	M.last_side = M.side()
end

function M.registerStart()
	chainLog.set_listener(M.on_row, M.is_visible)
end

-- For analysis/test_chain_trainer.lua.
function M._rows() return rows end
function M._cur() return cur end

-- ---------------------------------------------------------------------------
-- The lines, as text: each a list of { text, colour } drawn left to right at
-- one glyph per character, as hud.lua draws AirGap's - so the offline test
-- reads exactly what the screen gets.
local C_HEAD, C_TEXT, C_DASH = "#AAAAAA", "#FFFFFF", "#555555"
local C_HELD, C_JUDGED = "#888888", "#FFFFFF"
local C_WIN, C_BAD = "#00FF00", "#FF0000"
-- AirGap's: the dummy input column's colours (scripts/scrolling-input).
local STRENGTH_COLOR = { L = "#00CAFF", M = "#FFFF00", H = "#FF0000" }
local HEAVY_FIRST = { { 0x0400, "HP" }, { 0x4000, "HK" }, { 0x0200, "MP" },
                      { 0x2000, "MK" }, { 0x0100, "LP" }, { 0x1000, "LK" } }

local function press_cell(b)
	for _, k in ipairs(HEAVY_FIRST) do
		if has(b, k[1]) then return { k[2]:sub(2), STRENGTH_COLOR[k[2]:sub(1, 1)] } end
	end
	return { "?", C_TEXT }
end

M.SPECIAL_RESULT = { SP = true, ES = true, EX = true, DF = true }
local function result_color(s)
	if s:sub(1, 5) == "CHAIN" or s == "RAPID" or s:sub(1, 4) == "LINK" then return C_WIN end
	if M.SPECIAL_RESULT[s:sub(1, 2)] then return C_WIN end
	if s == "?" or s == "" or s:sub(1, 5) == "GUARD" then return C_TEXT end
	return C_BAD
end

function M.bar_cells(row)
	local cells = {}
	if row.nometer then return cells end
	if row.link then
		-- From the first tick you could act: = as far as a press would still
		-- have linked, . after it, and the press that started it.
		local w = row.last_ok or 0
		if row.press_t < 0 then
			-- EARLY (early_link): the press, a . for each Tick it was still in
			-- the move, then the window from 1t.
			cells[1] = press_cell(row.press_b)
			local dots = math.max(0, math.min(-row.press_t - 1, M.MAX_BAR - 1 - w))
			for i = 1, dots do cells[#cells + 1] = { ".", C_DASH } end
			for i = 1, math.min(w, M.MAX_BAR - 1) do cells[#cells + 1] = { "=", C_JUDGED } end
			return cells
		end
		local n = math.min(math.max(row.press_t + 1, w), M.MAX_BAR)
		for i = 1, n do cells[i] = (i <= w) and { "=", C_JUDGED } or { ".", C_DASH } end
		if row.press_t + 1 <= M.MAX_BAR then cells[row.press_t + 1] = press_cell(row.press_b)
		else cells[n] = { ">", C_TEXT } end
		return cells
	end
	local rapid = row.accept ~= nil and (row.accept.kind == "rapid" or row.accept.kind == "special")
	local last = window_last(row) or -1
	for _, p in ipairs(row.presses) do if p.t > last then last = p.t end end
	-- The cancel ends the line: nothing after it belongs to this link - but a
	-- special's combo deadline is drawn out to its last press, as a link's is.
	if row.accept ~= nil then last = row.accept.t end
	if row.accept ~= nil and row.accept.kind == "special" and row.last_ok ~= nil then
		last = math.max(last, row.last_ok - 1)
	end
	local n = last + 1
	local over = n > M.MAX_BAR
	if over then n = M.MAX_BAR end
	for i = 1, n do
		local k = (not rapid) and row.band[i - 1] or nil
		if k == "held" then cells[i] = { "-", C_HELD }
		elseif k == "judged" then cells[i] = { "=", C_JUDGED }
		else cells[i] = { ".", C_DASH } end
	end
	-- A special cancel's line: = as far as its press would still have combo'd.
	if rapid and row.accept.kind == "special" and row.last_ok ~= nil then
		for i = 1, math.min(row.last_ok, n) do cells[i] = { "=", C_JUDGED } end
	end
	if row.accept ~= nil and row.accept.t + 1 <= n then cells[row.accept.t + 1] = { "|", C_WIN } end
	for _, p in ipairs(row.presses) do
		if p.t >= 0 and p.t + 1 <= n then cells[p.t + 1] = press_cell(p.b) end
	end
	if over then cells[n] = { ">", C_TEXT } end
	return cells
end

local function label_of(row)
	return row.src .. " > " .. ((row.tgt ~= nil and row.tgt ~= "") and row.tgt or "?")
end

function M.lines()
	local side = M.side()
	if side == nil then return {} end
	local list = {}
	for _, r in ipairs(rows) do list[#list + 1] = r end
	-- The chain being measured, while there is anything in it to show.
	if cur ~= nil and (next(cur.band) ~= nil or #cur.presses > 0) then list[#list + 1] = cur end
	while #list > M.MAX_ROWS do table.remove(list, 1) end
	-- Columns: the widest label, then the bars from one place, as AirGap's.
	local lw, bw = 0, 0
	local bars = {}
	for i, row in ipairs(list) do
		lw = math.max(lw, #label_of(row))
		bars[i] = M.bar_cells(row)
		bw = math.max(bw, #bars[i])
	end
	local out = { { { "Chain P" .. side, C_HEAD } } }
	for i, row in ipairs(list) do
		local label = label_of(row)
		local l = { { label .. string.rep(" ", lw - #label + 1), C_TEXT } }
		for _, c in ipairs(bars[i]) do l[#l + 1] = c end
		l[#l + 1] = { string.rep(" ", bw - #bars[i] + 1), C_TEXT }
		local res = row.result or ""
		l[#l + 1] = { res, row.late and C_BAD or result_color(res) }
		out[#out + 1] = l
	end
	return out
end

-- ---------------------------------------------------------------------------
-- Drawing: AirGap's height, box and spacing (hud.lua draw_air_guard_gap),
-- right of the game's hit count (see the top).
M.X, M.Y = 104, 37
local CH, ROW = 4.2, 8

local function width(l)
	local n = 0
	for _, c in ipairs(l) do n = n + #c[1] end
	return n
end

function M.draw()
	if M.side() == nil then return end
	local lines = M.lines()
	local x, y = M.X, M.Y
	-- UNDER AIRGAP'S LINES WHEN BOTH ARE ON: one place for the two, AirGap
	-- first, as it is drawn there by hud.lua.
	if globals.options.display_air_guard_gap == true then
		local ag = package.loaded["./scripts/airGuardGap"]
		local n = (type(ag) == "table" and ag.lines ~= nil) and #ag.lines() or 0
		if n > 0 then y = y + n * ROW + 3 end
	end
	local w = 0
	for _, l in ipairs(lines) do w = math.max(w, width(l)) end
	gui.box(x - 2, y - 1, x + w * CH + 2, y + #lines * ROW, "#00000099", "#00000055")
	for i, l in ipairs(lines) do
		local cx = x
		for _, c in ipairs(l) do
			if c[1]:find("%S") then gui.text(math.floor(cx + 0.5), y + (i - 1) * ROW, c[1], c[2]) end
			cx = cx + #c[1] * CH
		end
	end
end

return M
