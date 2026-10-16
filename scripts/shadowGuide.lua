-- SHADOW GUIDE (Trainer > Show Bishamon UBK Trainer, which draws it, v11.7.28;
-- design UBK_SHADOW_GUIDE_DESIGN, user 2026-10-16: "絡め魂からやりましょう").
--
-- Karame Dama's unblockable spacing, learnt from the shadows. On the ground, at
-- your shadow's middle row, a short line marks where its front edge has to be
-- for each range the opponent has (charMoves.lua's table, the pushbox
-- distance the trainer's text already uses): blue the standing range, yellow
-- the crouching one, green the part that is both. Put the front of the shadow
-- you see on the line. The
-- shadows are what is left once the trainer is off; the line only says where.
-- No shadow is drawn, and only the tip of yours crosses the line, when it is on
-- it. Not under the shadow, as the design had it: the Frame Meter's top edge
-- is right under the shadows and covered the line (user, 2026-10-16, a
-- screenshot with nothing to be seen). Drawn all the time, near or far (user:
-- "近寄る前から、でっぱなしにして、どこまでよればいいかを教えるかたちが覚えやすい").
--
-- THE SHADOW (ROM 01BC9C, analysis/gen_shadow_bounds.py). Each player's is
-- drawn from its cel: cel+$11 the shape (0: none), cel+$15 a signed x offset
-- (negated when $0B is set), placed at the player's X and its ground height
-- $3A. The shapes are ellipses; SHAPES holds the columns [L, R) and rows
-- [T, B) that have a visible pixel, from the decoded graphics - not the
-- sprite blocks, which are wider (Bishamon's 23 is 92 wide in a 112 block).
-- Flipped, a pixel at u lands at -u - 1: the columns become [-R, -L).
--
-- THE MARK. d is the pushbox distance (dummyState.lua's sum: the facing edges
-- of the two push boxes), s +1 with the opponent on the right. The front
-- pixel of your shadow is f; at a distance t it would be f + s * (d - t), the
-- opponent and your cel staying as they are. So a range [a, b] is drawn over
-- those pixels, and moving towards or away moves the shadow onto it, not the
-- line: the line stays put while only your X changes. A cel with another
-- pushbox or shadow moves it, as it moves where the edge has to be.
-- Worked out every drawn frame from the sample cps2-hitboxes.lua draws its
-- boxes from, so the line, the text and the boxes are the same frame.
--
-- WHEN IT DRAWS NOTHING. No range for the opponent (Morrigan, Lilith), no
-- shadow shape, either player in the air ($14 not $3A), no push box, no match.
--
-- THE CHECK (Knockdown Logger only): 01BD96, where the game writes each part
-- of a shadow, compares the part's x with the one worked out here, and the
-- counts go to reversal_logs/shadow_log.jsonl. diff 0 is a match; the game
-- also adds $10C when $8 is 0 (a shake) and a screen shake when $24 is set,
-- logged beside it. First run (2026-10-16, Bishamon on Sasquatch, archive
-- v11.7.28_3): 114 348 parts at 0, 2 922 off by exactly their $10C, and 44
-- flipped ones off by 32 or 80 (11 of each sign) - not explained yet, and
-- not what the line uses: it takes the shape's columns, not the parts.

local M = {}

-- 54 shapes, from analysis/gen_shadow_bounds.py: { L, R, T, B }.
M.SHAPES = {
	[1] = { -24, 24, -6, 7 },
	[2] = { -25, 25, -7, 8 },
	[3] = { -26, 26, -7, 8 },
	[4] = { -27, 27, -7, 8 },
	[5] = { -28, 28, -7, 8 },
	[6] = { -29, 29, -7, 8 },
	[7] = { -30, 30, -7, 8 },
	[8] = { -31, 31, -7, 8 },
	[9] = { -32, 32, -7, 8 },
	[10] = { -33, 33, -7, 8 },
	[11] = { -34, 34, -7, 8 },
	[12] = { -35, 35, -7, 8 },
	[13] = { -36, 36, -7, 8 },
	[14] = { -37, 37, -7, 8 },
	[15] = { -38, 38, -7, 8 },
	[16] = { -39, 39, -7, 8 },
	[17] = { -40, 40, -7, 8 },
	[18] = { -41, 41, -7, 8 },
	[19] = { -42, 42, -7, 8 },
	[20] = { -43, 43, -7, 8 },
	[21] = { -44, 44, -7, 8 },
	[22] = { -45, 45, -7, 8 },
	[23] = { -46, 46, -7, 8 },
	[24] = { -47, 47, -7, 8 },
	[25] = { -48, 48, -7, 8 },
	[26] = { -49, 49, -7, 8 },
	[27] = { -50, 50, -7, 8 },
	[28] = { -51, 51, -7, 8 },
	[29] = { -52, 52, -7, 8 },
	[30] = { -53, 53, -7, 8 },
	[31] = { -54, 54, -7, 8 },
	[32] = { -55, 55, -7, 8 },
	[33] = { -56, 56, -7, 8 },
	[34] = { -57, 57, -7, 8 },
	[35] = { -58, 58, -7, 8 },
	[36] = { -59, 59, -7, 8 },
	[37] = { -60, 60, -7, 8 },
	[38] = { -61, 61, -7, 8 },
	[39] = { -62, 62, -7, 8 },
	[40] = { -63, 63, -7, 8 },
	[41] = { -67, 68, -7, 8 },
	[42] = { -71, 71, -7, 8 },
	[43] = { -75, 75, -7, 8 },
	[44] = { -79, 79, -7, 8 },
	[45] = { -83, 83, -7, 8 },
	[46] = { -87, 87, -7, 8 },
	[47] = { -91, 91, -7, 8 },
	[48] = { -95, 95, -7, 8 },
	[49] = { -99, 99, -7, 8 },
	[50] = { -103, 103, -7, 8 },
	[51] = { -107, 107, -7, 8 },
	[52] = { -20, 20, -6, 7 },
	[53] = { -16, 16, -5, 6 },
	[54] = { -12, 12, -4, 5 },
}

-- The diagnostic (Knockdown Logger only): see THE CHECK at the end.
local counts, last_write, started, last_plan = {}, 0, false, nil
local function logging()
	return globals ~= nil and globals.options ~= nil and globals.options.knockdown_logger_enable == true
end

-- The trainer's words and colours, text and line alike. No UBK has no line.
M.COLOR = { both = "#00FF00", standing = "#00CAFF", crouching = "#FFFF00", none = "#FF0000" }
M.WORD = { both = "Both", standing = "Standing", crouching = "Crouching", none = "No UBK" }
local BRACKET, BRACKET_IN = "#808080", "#FFFFFF"

-- The visible columns [L, R) of shape n for the facing.
function M.columns(n, flipped)
	local s = M.SHAPES[n]
	if s == nil then return nil end
	if flipped then return -s[2], -s[1] end
	return s[1], s[2]
end

-- At the hitbox sample (cps2-hitboxes.lua's update_object): what the game draws
-- for this player's shadow, in the boxes' screen coordinates. nil for none.
-- Why the last sample of a player had no shadow, by base (the diagnostic).
M.why = {}
function M.sample(base, pos_x, ground_y)
	if memory.readbyte(base) == 0 or memory.readbyte(base + 1) == 0 then M.why[base] = "off" return nil end
	local cel = memory.readdword(base + 0x1C)
	if cel == 0 then M.why[base] = "no cel" return nil end
	local n = memory.readbyte(cel + 0x11)
	if M.SHAPES[n] == nil then M.why[base] = string.format("shape %d (cel %06X)", n, cel) return nil end
	M.why[base] = nil
	local dx = memory.readbytesigned(cel + 0x15)
	local flipped = memory.readbyte(base + 0x0B) ~= 0
	if flipped then dx = -dx end
	return { n = n, x = pos_x + dx, y = ground_y, flipped = flipped,
	         air = memory.readwordsigned(base + 0x14) ~= memory.readwordsigned(base + 0x3A),
	         -- Standing free: not hit or throwing ($05 0), standing or
	         -- crouching ($06 0x00), not attacking ($105, framemeter.lua).
	         stand = memory.readbyte(base + 0x05) == 0 and memory.readbyte(base + 0x06) == 0
	                 and memory.readbyte(base + 0x105) == 0 }
end

local function range(r)
	if r == nil or r.startDist == nil or r.endDist == nil then return nil end
	return { r.startDist, r.endDist }
end
local function inside(t, rg) return rg ~= nil and t >= rg[1] and t <= rg[2] end

-- What the distance is, in the trainer's order: both, then standing, then
-- crouching, else none. Ends included.
function M.classify(d, ranges)
	if d == nil or ranges == nil then return nil end
	if inside(d, range(ranges.overlapRange)) then return "both" end
	if inside(d, range(ranges.standingDist)) then return "standing" end
	if inside(d, range(ranges.crouchingDist)) then return "crouching" end
	return "none"
end

-- The pushbox distance, as dummyState.lua sums it: P1 is on the left unless
-- its right edge is further right than P2's.
function M.distance(p1, p2)
	if p1 == nil or p2 == nil or p1.push_r == nil or p2.push_r == nil then return nil end
	local left = not (p1.push_r > p2.push_r)
	if left then return p2.push_l - p1.push_r, true end
	return p1.push_l - p2.push_r, false
end

-- The rows of the mark: one, classified as the text is, when the table has an
-- overlap (or the two ranges do not meet); two - standing above, crouching
-- under - when they meet with no overlap, as Q-Bee's do (different moves:
-- nothing there works for both, so nothing is green).
local function rows_of(ranges)
	local st, cr, ov = range(ranges.standingDist), range(ranges.crouchingDist), range(ranges.overlapRange)
	if st and cr and not ov and st[1] <= cr[2] and cr[1] <= st[2] then
		return { { { st, "standing" } }, { { cr, "crouching" } } }
	end
	local row = {}
	if ov then row[#row + 1] = { ov, "both" } end
	if st then row[#row + 1] = { st, "standing" } end
	if cr then row[#row + 1] = { cr, "crouching" } end
	if #row == 0 then return {} end
	return { row }
end

-- The mark for this frame: { d, class, rows = { { y, runs = { { x1, x2, kind } } } },
-- x_min, x_max, y_top, y_bottom }, or nil when nothing is drawn.
-- How far ahead of your push box edge your shadow's tip was the last time you
-- stood (see THE LINE STAYS below); nil until then.
M.ahead = nil
function M.reset() M.ahead = nil end

-- nil and why when nothing is drawn.
function M.plan(p1, p2, ranges)
	if ranges == nil then return nil, "no range" end
	if p1 == nil then return nil, "no P1 push box" end
	if p2 == nil then return nil, "no P2 push box" end
	if p1.shadow == nil then return nil, "no shadow: " .. tostring(M.why[0xFF8400]) end
	if p1.shadow.air then return nil, "P1 in the air" end
	if p2.shadow ~= nil and p2.shadow.air then return nil, "P2 in the air" end
	local d, left = M.distance(p1, p2)
	if d == nil then return nil, "no distance" end
	local L, R = M.columns(p1.shadow.n, p1.shadow.flipped)
	local s = left and 1 or -1
	local front = left and (p1.shadow.x + R - 1) or (p1.shadow.x + L)
	-- THE LINE STAYS WHILE YOU ATTACK (user, 2026-10-16: "通常技、必殺技を出して影が
	-- 動いた際に枠が動くのをとめたい"). How far the shadow's tip is ahead of your
	-- push box edge is a matter of the cel: a normal or a special moves the
	-- shadow and the box, and the line with them. So it is taken while you
	-- stand (sample's stand) and kept through everything else: the line then
	-- hangs off the opponent's push box edge alone,
	--   pixel(t) = their edge - s * (t - ahead)
	-- which is f + s * (d - t) whenever ahead is this cel's own. The words and
	-- the white ends still follow the distance of this frame.
	local own_edge = left and p1.push_r or p1.push_l
	local opp_edge = left and p2.push_l or p2.push_r
	if p1.shadow.stand or M.ahead == nil then M.ahead = s * (front - own_edge) end
	local ahead = M.ahead
	local function pixel(t) return opp_edge - s * (t - ahead) end
	local out = { d = d, class = M.classify(d, ranges), rows = {} }
	-- The middle row of the shadow, where its tip is; two rows one above and
	-- one under it.
	local rows = rows_of(ranges)
	local first_y = p1.shadow.y - (#rows - 1)
	for i, row in ipairs(rows) do
		-- Each t takes the first entry of the row that has it (both, standing,
		-- crouching), then runs of the same kind become one line.
		local lo, hi = nil, nil
		for _, e in ipairs(row) do
			lo = lo and math.min(lo, e[1][1]) or e[1][1]
			hi = hi and math.max(hi, e[1][2]) or e[1][2]
		end
		local runs, cur = {}, nil
		for t = lo, hi do
			local kind = nil
			for _, e in ipairs(row) do
				if inside(t, e[1]) then kind = e[2] break end
			end
			if kind ~= nil and cur ~= nil and cur.kind == kind and cur.t2 == t - 1 then
				cur.t2 = t
			else
				if cur ~= nil then runs[#runs + 1] = cur end
				cur = kind and { kind = kind, t1 = t, t2 = t } or nil
			end
		end
		if cur ~= nil then runs[#runs + 1] = cur end
		local y = first_y + 2 * (i - 1)
		local r = { y = y, runs = {} }
		for _, run in ipairs(runs) do
			local a, b = pixel(run.t1), pixel(run.t2)
			local x1, x2 = math.min(a, b), math.max(a, b)
			r.runs[#r.runs + 1] = { x1, x2, run.kind }
			out.x_min = out.x_min and math.min(out.x_min, x1) or x1
			out.x_max = out.x_max and math.max(out.x_max, x2) or x2
		end
		out.rows[#out.rows + 1] = r
		out.y_top = out.y_top or y
		out.y_bottom = y
	end
	if out.x_min == nil then return nil, "no range" end
	return out
end

-- The line. With Knockdown Logger on, why there is none goes to the log only
-- (shown on the screen under the word once; user, 2026-10-16: "この白い文字は要らない").
function M.draw(plan, why, x, y)
	if logging() then
		local key = plan ~= nil and "plan/ok" or ("plan/" .. tostring(why))
		counts[key] = (counts[key] or 0) + 1
		if plan ~= nil then
			last_plan = string.format("x %d-%d y %d d %d", plan.x_min, plan.x_max, plan.y_top, plan.d)
		end
	end
	if plan == nil then return end
	for _, row in ipairs(plan.rows) do
		for _, run in ipairs(row.runs) do
			gui.line(run[1], row.y, run[2], row.y, M.COLOR[run[3]])
		end
	end
	-- The two ends, brighter while the distance is in a range.
	local c = (plan.class ~= nil and plan.class ~= "none") and BRACKET_IN or BRACKET
	local y1, y2 = plan.y_top - 3, plan.y_bottom + 3
	gui.line(plan.x_min - 1, y1, plan.x_min - 1, y2, c)
	gui.line(plan.x_max + 1, y1, plan.x_max + 1, y2, c)
end

-- ---------------------------------------------------------------------------
-- THE CHECK (Knockdown Logger only). 01BD96: movem.w D0-D3,(A2) of a shadow
-- part; D0 its x (with the 0x40 sprite offset, & 0x3FF), A1 just past its
-- x/y pair, D3 its attr (bit 5 the flip, bits 8-11 its width - 1).
M.PART_PC = 0x01BD96
local LOG = "reversal_logs/shadow_log.jsonl"

function M.on_part()
	if not logging() then return end
	local a6 = memory.getregister("m68000.a6")
	if a6 ~= 0xFF8400 and a6 ~= 0xFF8800 then return end
	local a1 = memory.getregister("m68000.a1")
	local d0 = memory.getregister("m68000.d0") % 0x400
	local d3 = memory.getregister("m68000.d3") % 0x10000
	local px = memory.readwordsigned(a1 - 4)
	local w = 16 * (math.floor(d3 / 256) % 16 + 1)
	local cel = memory.readdword(a6 + 0x1C)
	local dx = memory.readbytesigned(cel + 0x15)
	local flipped = memory.readbyte(a6 + 0x0B) ~= 0
	if flipped then dx = -dx px = -px - w end
	local want = memory.readwordsigned(a6 + 0x10) - memory.readwordsigned(0xFF8290) + 0x40 + dx + px
	local shake = (memory.readbyte(a6 + 0x08) == 0) and memory.readwordsigned(a6 + 0x10C) or 0
	local key = string.format("%d/%d/%d/%s", (d0 - want) % 0x400 > 0x200 and (d0 - want) % 0x400 - 0x400 or (d0 - want) % 0x400,
		shake, (memory.readword(a6 + 0x24) ~= 0) and 1 or 0, flipped and "f" or "-")
	counts[key] = (counts[key] or 0) + 1
end

function M.registerStart()
	memory.registerexec(M.PART_PC, M.on_part)
end

function M.registerAfter()
	if not logging() then return end
	local now = emu.framecount()
	if now - last_write < 300 or next(counts) == nil then return end
	last_write = now
	local f = io.open(LOG, started and "a" or "w")
	if f == nil then return end
	if not started then
		f:write('{"log": "shadow_log", "version": 1, "hook": "01BD96 a shadow part written (scripts/shadowGuide.lua)", '
			.. '"key": "diff / shake / screen shake / facing: diff the part x the game wrote less the one worked out here '
			.. '(X - 0xFF8290 + 0x40 + the cel offset + the part offset); shake the $10C the game adds when $8 is 0; '
			.. 'screen shake 1 when $24 is set; f flipped", "counts": "parts since the row before"}\n')
		started = true
	end
	local keys = {}
	for k in pairs(counts) do keys[#keys + 1] = k end
	table.sort(keys)
	local parts = {}
	for _, k in ipairs(keys) do parts[#parts + 1] = string.format('"%s": %d', k, counts[k]) end
	if last_plan ~= nil then parts[#parts + 1] = string.format('"last_plan": "%s"', last_plan) end
	f:write(string.format('{"frame": %d, %s}\n', now, table.concat(parts, ", ")))
	f:close()
	counts = {}
end

-- For analysis/test_shadow_guide.lua.
function M._counts() return counts end

return M
