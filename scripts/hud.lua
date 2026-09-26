local tech_hit_inputs = require './tech-hit-inputs'
-- Read only for the frequency counter below. require returns the module
-- already loaded by menu.lua, so this costs nothing at run time.
local actionSequenceRunnerModule = require './scripts/actionSequenceRunner'

-- WHY All Guard IS HOLDING BACK, ON SCREEN.
--
-- The knockdown logger only records inside an episode, so a WHIFF - which is
-- exactly the case being chased - never produces a recording and the
-- mark_write diagnostics came back empty. Read it live instead: the walk-back
-- is visible on screen at the same moment as the reason for it.
local function draw_ag_why()
	if globals.options.guard ~= 2 and globals.options.guard ~= 4 then return end
	-- A debugging readout, so it rides on the logger checkbox rather than
	-- showing up for everyone who turns All Guard on.
	if debugKnockdownModule == nil or debugKnockdownModule.enabled == nil then return end
	if not debugKnockdownModule.enabled() then return end
	if prox_why == nil then return end
	local _c = (prox_why == "far" or prox_why == "no105") and "#00FF00" or "#FF4040"
	gui.text(4, 24, "AG " .. prox_why .. " obj" .. tostring(prox_obj_n)
		.. " dx" .. tostring(prox_dx), _c)
end

local debugKnockdownModule = require "./scripts/debugKnockdown"

-- The arrangement hotkey 2 just chose, held for a moment so the lever
-- combination can be seen to have landed without opening the menu. Wrapped by
-- the caller: an error in a draw function takes the rest of the overlay with
-- it (see the note on draw_fastest below).
local function draw_position_figure()
	if positionModule == nil or positionModule.figure == nil then return end
	local _f = positionModule.figure()
	if _f == nil then return end
	gui.text(150, 30, _f, "#00FF00")
end

-- TWO ROWS, BECAUSE THE READOUT IS TWO QUESTIONS.
--
-- Startup / Active / Recovery / Advantage / Total describe the move. Hitstun
-- and Hitfreeze describe what happened to the other player. tickData joins them
-- with a newline; gui.text draws one row at a time, so they are split here.
-- AND WRAPPED, BECAUSE A NINE-HIT MOVE DOES NOT FIT.
--
-- Its Active list alone runs past the right edge and takes whatever follows
-- with it. Broken on the double space between fields, never inside one: half of
-- "Recovery 25t" at the end of a line is worse than a shorter line.
--
-- Same width the Action Steps readout uses, measured the same way.
local FD_COLS = 64

-- THE ROUTE ROW IS NOT THE SAME KIND OF THING AS THE ROWS ABOVE IT.
--
-- The first rows are one move measured in frames - startup, active, recovery,
-- advantage. The route is a whole action on a clock, and reading them as one
-- block invites treating a route tick as a frame number. A different colour
-- says they are different at a glance (user, 2026-09-10).
local FD_ROUTE_COLOR = "#8FE68F" 
local function fd_lines(text)
	local out = {}
	for _line in tostring(text):gmatch("[^" .. string.char(10) .. "]+") do
		local cur = nil
		for _field in (_line .. "  "):gmatch("(.-)  ") do
			if _field ~= "" then
				if cur == nil then cur = _field
				elseif #cur + 2 + #_field <= FD_COLS then cur = cur .. "  " .. _field
				else out[#out + 1] = cur cur = "  " .. _field end
			end
		end
		if cur ~= nil then out[#out + 1] = cur end
	end
	return out
end

local function draw_fd()
	mid_width = 23
	mid_height = 47
	local _row = 0
	if globals.last_fd ~= nil and globals.last_fd ~= "" then
		for _, _line in ipairs(fd_lines(globals.last_fd)) do
			gui.text(mid_width, mid_height + _row * 9, _line)
			_row = _row + 1
		end
	end
	-- Under the frame data, and drawn even when there is none: the route can
	-- have something to say before a move has been measured.
	if globals.last_route ~= nil and globals.last_route ~= "" then
		for _, _line in ipairs(fd_lines(globals.last_route)) do
			gui.text(mid_width, mid_height + _row * 9, _line, FD_ROUTE_COLOR)
			_row = _row + 1
		end
	end
end

local function draw_rec()
    if globals == nil 
        or globals.macroLua == nil
        or globals.options == nil
    then
		return;
	end
	local recording = globals.macroLua.recording
	local playing = globals.macroLua.playing
	local slot = globals.options.recording_slot - 1

	mid_width =  23
	mid_height = 38
	if recording and playing then
		gui.rect(mid_width - 2, mid_height - 1, mid_width + 125, mid_height + 7, "#ff0000")
		gui.text( mid_width, mid_height, "Slot "..slot..": Recording While Playing")
	elseif recording == true and playing ~= true then
		gui.rect(mid_width - 2, mid_height - 1, mid_width + 68, mid_height + 7, "#ff0000")
		gui.text( mid_width, mid_height, "Slot "..slot..": Recording")
	elseif recording ~= true and playing == true then 
		gui.rect(mid_width - 2, mid_height - 1, mid_width + 65, mid_height + 7, "#00ff00")
		gui.text( mid_width, mid_height, "Slot "..slot..": Playing")
	elseif recording ~= true and playing ~= true then
		gui.rect(mid_width - 2, mid_height - 1, mid_width + 65, mid_height + 7, "#000000")
		gui.text( mid_width, mid_height, "Slot "..slot..": Paused")
	end 
end

local last_tech_success = false

local function draw_pb_counter()
	if globals.options.display_pb_counter == true then
		if globals == nil then return;	end
		local color = "#0000ff"
		if globals.timers.p1_pushblock_counter == 0 then
			-- NOT PRESSING IS NOT AN ERROR (user, 2026-09-22). The red box
			-- used to say "nothing counted" as if that were a failure, but a
			-- player who chooses to just guard is playing correctly. Inactive
			-- grey instead of alarming red.
			color = "#555555"
		end

		local x = 21
		local y = 27
		-- THE DUMMY'S COUNT SITS BESIDE P1'S WHEN THE DUMMY IS PUSH BLOCKING.
		--
		-- Guard Action = Push Block had no feedback on screen: this readout was
		-- P1's $170 only. The game's rule is a count inside a window, so the
		-- count is the thing worth showing, and six is where it is guaranteed
		-- (0x02760E takes eight, but six is 100% through the table below it).
		local _ga = globals.dummy and globals.dummy.guard_action
		local _showp2 = (_ga == 'pb' or _ga == 'recording on pushblock')
		-- THE TIMELINE INSIDE THE WIDENED BOX (user, 2026-09-21).
		--
		-- One character per tick of the window, published by timers.lua:
		-- Guard = the block that opens it, Expired = the tick it closes, and
		-- the digit is HOW MANY buttons edge on that tick. A skilled input is
		-- one button per tick spaced across the window, so a tick reading 2 or
		-- more is the mistake the colour exists to show - the ROM adds one
		-- count per TICK, so two buttons together buy one where a spaced pair
		-- would have bought two. MultiPush is the count of those ticks.
		--
		-- The window being open is read live ($1ab): while it is, the line is
		-- still growing and no label closes it; when it reads zero the last
		-- span is complete and stays up until the next one starts.
		local _marks = globals.timers.p1_pb_marks
		local _simul = globals.timers.p1_pb_simul or 0
		local _last = 0
		if _marks ~= nil then
			for _p = 1, 14 do if _marks[_p] ~= nil then _last = _p end end
		end
		local _live = memory.readbyte(0xFF84AB) > 0

		-- RECT FIRST, THEN TEXT ON TOP - gui.rect is a filled rect and covers
		-- anything drawn under it. The width is computed from the parts before
		-- drawing, because drawing and measuring in the same pass would leave
		-- the rect on top of the text it is meant to frame.
		-- EVERY ADVANCE IS MEASURED FROM ITS OWN TEXT (2026-09-23).
		--
		-- The trailing fields used fixed allowances - 40 for at:, 56 for
		-- MultiPush, 70 for LateMash - while the box was sized from the same
		-- constants. LateMash's worst case is nineteen characters (about 80px)
		-- against an allowance of 70, so the text ran past its own box and off
		-- the right edge of the screen, over the art (user screenshot,
		-- 2026-09-23). Measuring every part keeps the box and the text in step
		-- whatever the numbers grow to, and hands back the ~25px the old
		-- allowances were rounding away.
		--
		-- 4.2px is the advance the timeline has always used for one glyph.
		local CH, GAP = 4.2, 4
		local _first, _lastpress = nil, nil
		for _p = 1, _last do
			if (_marks and _marks[_p] or "-") ~= "-" then _first = _p break end
		end
		for _p = _last, 1, -1 do
			if (_marks and _marks[_p] or "-") ~= "-" then _lastpress = _p break end
		end
		-- THE FIRST PRESS TICK, AFTER THE METER (user, 2026-09-22): the marks
		-- are hard to count by eye, so the tick the pressing started on is
		-- called out as a number. Lowercase "at" because it is a preposition,
		-- not a field name. The pair is head and tail - at:8-13t with
		-- PB Count: 6 is the ideal spacing, six presses on six consecutive
		-- ticks with none wasted on a simultaneous one.
		local _attxt = nil
		if _first ~= nil then
			_attxt = (_lastpress ~= nil and _lastpress ~= _first)
				and ("at:" .. _first .. "-" .. _lastpress .. "t")
				or ("at:" .. _first .. "t")
		end
		local _mptxt = "MultiPush: " .. _simul
		-- LATEMASH: THE BUTTONS PRESSED AFTER THE WINDOW CLOSED.
		--
		-- The word is the one fighting game players use for it, not one
		-- invented here (user, 2026-09-23).
		--
		-- INSIDE the fourteen ticks every press is a fair attempt, grant or no
		-- grant: the player cannot see the grant, so carrying on is not a
		-- mistake and PB Count keeps counting it. PAST the fourteen nothing can
		-- be bought, and that is the habit this shows. The bracket is how far
		-- past the window the LAST of them landed; the tally stops sixty ticks
		-- out so holding the buttons down cannot make it climb forever.
		local _over = globals.timers.p1_pb_latemash or 0
		local _late = globals.timers.p1_pb_latemash_late or 0
		local _omtxt = "LateMash: " .. _over
			.. ((_over > 0) and (" (+" .. _late .. "t)") or "")

		local _tlw = 0
		if _last > 0 then
			_tlw = GAP + 5 * CH                      -- "Guard"
				+ _last * CH                          -- the timeline
				+ (_live and 0 or (1 * CH))           -- the "|" that closes it
				+ ((_attxt ~= nil) and (GAP + #_attxt * CH) or 0)
				+ GAP + #_mptxt * CH
				+ GAP + #_omtxt * CH
		end
		local _pbtxt = "PB Count: " .. globals.timers.p1_pushblock_counter
		local _w = 4 + #_pbtxt * CH + ((_showp2) and 28 or 0) + _tlw
		gui.rect(x, y, x + _w, y + 8, color)

		gui.text( x + 2, y + 1, _pbtxt,
			globals.timers.p1_pushblock_ok and "#00FF00" or "#FFFFFF")
		local _cx = x + 2 + #_pbtxt * CH
		if _showp2 and globals.timers.p2_pushblock_counter then
			local _n = globals.timers.p2_pushblock_counter
			gui.text( _cx + GAP, y + 1, "P2:".._n,
				globals.timers.p2_pushblock_ok and "#00FF00" or "#FFD700")
			_cx = _cx + GAP + 4 * CH
			-- THE DUMMY'S DELIVERY IS ONE BUTTON PER TICK (guardCancel's PB
			-- taps are one entry per tick for exactly this reason) - so its
			-- MultiPush reads 0, and a number here is a bug in this tool.
			local _s2 = globals.timers.p2_pb_simul or 0
			if _s2 > 0 then
				gui.text( _cx + GAP, y + 1, "MULTI!", "#FF0000")
				_cx = _cx + GAP + 6 * CH
			end
		end
		if _last > 0 then
			_cx = _cx + GAP
			gui.text(_cx, y + 1, "Guard", "#AAAAAA")
			_cx = _cx + 5 * CH
			for _p = 1, _last do
				local _m = (_marks and _marks[_p]) or "-"
				if _m == "-" then
					gui.text(_cx, y + 1, "-", "#555555")
				elseif tonumber(_m) >= 2 then
					gui.text(_cx, y + 1, _m, "#FF0000")
				else
					gui.text(_cx, y + 1, _m, "#FFFFFF")
				end
				_cx = _cx + CH
			end
			if not _live then
				-- JUST THE BAR (2026-09-23). It used to read "|Expired", and
				-- the word costs seven glyphs to repeat what the bar and the
				-- end of the timeline already say. With the dummy's count
				-- beside P1's the line ran 12px off the right edge of the
				-- screen; this is where the room came from.
				gui.text(_cx, y + 1, "|", "#AAAAAA")
				_cx = _cx + 1 * CH
			end
			if _attxt ~= nil then
				_cx = _cx + GAP
				gui.text(_cx, y + 1, _attxt, "#FFFFFF")
				_cx = _cx + #_attxt * CH
			end
			_cx = _cx + GAP
			gui.text(_cx, y + 1, _mptxt, (_simul > 0) and "#FF0000" or "#888888")
			_cx = _cx + #_mptxt * CH
			-- Same colour rule as MultiPush, the other negative on this line:
			-- grey at zero, red once there is something to fix.
			_cx = _cx + GAP
			gui.text(_cx, y + 1, _omtxt, (_over > 0) and "#FF0000" or "#888888")
			_cx = _cx + #_omtxt * CH
		end
	-- NOTHING TO DO WHEN THE READOUT IS OFF.
	--
	-- This used to zero the two counts here, reaching into the table timers.lua
	-- publishes - and it left the granted flags alone, so switching the row off
	-- and back on after a push block gave a count of 0 that was still coloured
	-- as granted. timers.lua now clears both together where the game clears its
	-- own, and owns that state; drawing is all that belongs in here.
	end
end

local screen_midpoint = 41983616

local function base_x_calc(x_offset_left, x_offset_right, trainer_1, trainer_2, trainer_3, other_trainer_offset)
	local base_x = 0
	local offset_x = 0
	local x_location = memory.readdword(0xFF8410)

	if trainer_1 == true then
		offset_x = default_x_offset
	end

	if x_location < screen_midpoint then
		base_x = 335 - x_offset_right
	else
		base_x = 10 + x_offset_left
	end

	if  trainer_2 == true or trainer_3 == true then
		base_x = other_trainer_offset
	end

	return base_x
end

-- This function shows you the length of dashes in frames, and for sasquatch tells you if you got a short or long hop
local function draw_dash_length_trainer()
	if globals.options.display_dash_length_trainer == true then
		local p1_char = util.get_character(0xFF8400)
		local copy_of_table = copytable(globals.dash_length_frames)

		table.sort(copy_of_table, function (left, right) return left < right end)

		local base_x = base_x_calc(30, 0, globals.options.display_dash_interval_trainer, globals.options.display_dash_attack_cancel_trainer, globals.options.display_attack_dash_gap_trainer, 335)

		gui.text(base_x, 50 , "Dash\nLength")
		for i = #globals.dash_length_frames, 1, -1 do
			local color = "#FFFFFF"
			if globals.dash_length_frames[i] == copy_of_table[1] then color = "#00FF00" end
			if globals.dash_length_frames[i] == copy_of_table[#copy_of_table] then
				color = "#FF0000" 
			end
			if p1_char == "Sasquatch" then
				if globals.dash_length_frames[i] < 20 then
					gui.text(base_x, 80 + ((#globals.dash_length_frames - i) * 10), ":)", 'green')
				else
					gui.text(base_x, 80 + ((#globals.dash_length_frames - i) * 10), ":(", 'red')				
				end
			else
				gui.text(base_x, 80 + ((#globals.dash_length_frames - i) * 10), globals.dash_length_frames[i], color)
			end
		end
	end
end

-- This function tells you how many frames between each hop, with fewer frames between hops being more optimal
local function draw_dash_trainer()
	if globals.options.display_dash_interval_trainer == true then
		local p1_char = util.get_character(0xFF8400)

		local copy_of_table = copytable(globals.time_between_dashes)
		table.sort(copy_of_table, function (left, right) return left < right end)

		local base_x = base_x_calc(0, 30, globals.options.display_dash_length_trainer, globals.options.display_dash_attack_cancel_trainer, globals.options.display_attack_dash_gap_trainer, 305)

		gui.text(base_x, 50, "Time\nBTW\nDash")
	
		for i = #globals.time_between_dashes, 1, -1 do
			local color = "#FFFFFF"
			if globals.time_between_dashes[i] == copy_of_table[1] then color = "#00FF00" end
			if globals.time_between_dashes[i] == copy_of_table[#copy_of_table] then color = "#FF0000" end
			if globals.time_between_dashes[i] < 2 then color = "#FFD700" end
			gui.text(base_x, 80 + ((#globals.time_between_dashes - i) * 10), globals.time_between_dashes[i], color)
		end
	end
end

local function draw_jump_in_trainer()
	if globals.options.display_jump_in_trainer == true then
		gui.text(42, 195, "Jump In (Disp F): ")
		local copy_of_table = copytable(globals.jump_in_frames)
		table.sort(copy_of_table, function (left, right) return left < right end)
		for i = #globals.jump_in_frames, 1, -1 do
			local color = "#FFFFFF"
			if globals.jump_in_frames[i] == copy_of_table[1] then color = "#00FF00" end
			if globals.jump_in_frames[i] == copy_of_table[#copy_of_table] then
				color = "#FF0000" 
			end
			gui.text(105 + ((#globals.jump_in_frames - i) * 14), 195, globals.jump_in_frames[i], color)
		end
	end
end

-- this function creates a counter that tracks how many short hops you can successfully do in a row
local function draw_short_hop_counter()
	if globals.options.display_short_hop_counter == true then
		local p1_char = util.get_character(0xFF8400)

		if  p1_char ~= "Sasquatch"
		then
			return
		end

		local color = "#000000"
		local x = 161
		local y = 53
		local count = 0
		gui.rect(x, y, x+61, y+8, color)
		gui.text( x + 2, y + 1, "Short hops: 0", "#FF0000")
		local copy_of_table = copytable(globals.short_hop_counter)
		table.sort(copy_of_table, function (left, right) return left < right end)

		for i = #globals.short_hop_counter, 1, -1 do
			if globals.short_hop_counter[i] < 20 then
				gui.text( x + 2, y + 1, "Short hops: ".. count + 1, "#00FF00")
				count = count + 1
			else
				return				
			end
		end
	end
end

-- This function show stats for pushblocking
local function draw_pb_stats()
	if globals.options.display_pb_stats == true then
		gui.text( 172, 54, "Total: ".. util.tablelength(globals.total_pb_attempt_counter))
		gui.text( 172, 63, "Pass: " .. util.tablelength(globals.successful_pb_counter), "#00FF00")
		gui.text( 210, 63, "% ", "#00FF00")
		if util.tablelength(globals.successful_pb_counter) > 0 then
			gui.text( 210, 63, "%" .. string.format("%02d", util.tablelength(globals.successful_pb_counter) / util.tablelength(globals.total_pb_attempt_counter) * 100), "#00FF00")
		end
		gui.text( 172, 73, "Fail: " .. util.tablelength(globals.total_pb_attempt_counter) - util.tablelength(globals.successful_pb_counter), "#FF0000")
		tech_hit_inputs()
	end
end

-- WHAT GUARD ACTION FREQUENCY IS ACTUALLY DOING.
--
-- The setting was fixed three times by reasoning about the code and was wrong
-- three times, because the two halves are indistinguishable on screen: a guard
-- action that armed this block, and a leftover step from an earlier one, look
-- identical. These five numbers separate them.
--
--   freq   what shouldGC() really read - catches the setting not arriving
--   opp    opportunities counted (a blocked hit, or entering stun)
--   roll+  opportunities the roll allowed          roll+/opp is the real rate
--   arm    step one actually queued                should equal roll+
--   seq    later steps the runner sent             above opp means leaks
--   drop   later steps thrown away by a refusal
-- WHAT THE GAME TOOK ON THE WAY TO A GUARD CANCEL.
--
-- guardCancel.lua collects it from the engine's own command block - one row
-- per direction the game ACCEPTED, which is not the same as one row per
-- direction pressed. Seeing the difference is the point: a motion that came
-- apart and a button that arrived late fail the same way on screen and are
-- not the same mistake.
--
-- DRAWN WITH THE INPUT VIEWER'S OWN ARTWORK (user, 2026-09-23). The arrows
-- are img_dir, indexed by the numpad number worked out at the tick the step
-- was taken, and the buttons are the same two rows of three the viewer lays
-- out along the bottom. A direction has to read the same in both places or
-- they cannot be held against each other.
--
-- EACH ROW IS THE GAP FROM THE ONE ABOVE IT (user, 2026-09-23). Input as
-- fast as the engine can take it reads 1t on every direction, and a button
-- that lands on the same tick as the last direction reads 0t - so the number
-- is what there is to tighten, rather than a running total to subtract in
-- your head. The first row has nothing above it and carries no number, the
-- way the sketch this was built from had none on its Guard.
--
-- SUCCESS IS THE EXCEPTION and counts from the GUARD. It is the same number
-- already drawn beside SUCCESS in the input viewer, and it is the one that
-- says how fast the cancel came out. The two Expired lines count from the
-- start of the attempt - from the guard, GC Expired would read 14 every time.
--
-- NOTHING IS DRAWN WITHOUT A GUARD. The motion is collected all the time,
-- but a trace with no guard in it is just a lever history.
local GCT_ROW_H = 11
-- ONE COLUMN FOR EVERY NUMBER, RIGHT ALIGNED.
--
-- The ticks used to be written straight after their label, so the terminal
-- line put its number wherever the label happened to end - Command Expired
-- is fifteen characters and pushed it far past the column the rows use,
-- which read as a mistake (user, 2026-09-23). Right aligning also lines the
-- digits up, so 1t and 31t end in the same place.
--
-- TWO MEASUREMENTS LIVE HERE, BUT ONE COLUMN IS ENOUGH.
--
-- The directions, the button and Cmd Expired are one set: they are about the
-- motion, each counted from the input before it. Guard, Success and GC
-- Expired are the other, counted from the guard. They were briefly given a
-- column each, until the brackets round the guard's number made the split
-- unnecessary - the brackets say that row is not part of the chain, and the
-- labels say the rest (user, 2026-09-23). One column is narrower and lines
-- every number up.
--
-- The edge clears the longest label: Cmd Expired, eleven characters at about
-- five pixels each.
local GCT_NUM_R = 78
-- ONE GLYPH IS 4.2 PIXELS, NOT 5.
--
-- Right aligning with 5 leaves every string short of the edge by 0.8 of a
-- pixel per character, so the longer ones sit further left: 2t landed in one
-- place, 13t a little left of it, (7t) further still. It reads as the column
-- wobbling (user, 2026-09-23, twice - once for the brackets and once for
-- Success). 4.2 is what draw_pb_counter in this same file measures with.
local GCT_CH = 4.2
-- THE BRACKETS HANG PAST THE COLUMN, so the digits inside them line up with
-- the digits above. Right aligning the whole of (13t) would push its 13t a
-- character to the left of every other number. One character's width is
-- exactly the closing bracket.
local GCT_BRACKET = GCT_CH
-- The failure red the input viewer already draws a dead GC in, so the two
-- readouts say the same thing in the same colour (user, 2026-09-23).
-- A GAP THE RANDOM GRACE ONLY JUST CARRIED.
--
-- The wait between two inputs of a special is rolled, not fixed. What a
-- player experiences is 11 to 15 ticks, so eleven still comes up often and
-- anything past it only landed because the roll was generous (user,
-- 2026-09-24).
--
-- NOT THE ROM TABLE. 0x02A55A holds 32 entries reading 14 16/32, then 15,
-- 16, 17, 18, 19 with falling odds - the same shape four ticks higher. That
-- byte is what the step timer is loaded with; it is not the window a player
-- gets, because the acceptance around it is its own thing (user). The table
-- is written down in VSAV_MEMORY_NOTES; it is not what this threshold is.
--
-- So it is a WARNING, not an error: the cancel did come out (user,
-- 2026-09-24). Orange, which is neither the gold of Success nor the red of a
-- failure. It was an amber (#FFA000) at first, and that sat close enough to
-- Success's gold to be read as it (user, 2026-09-25).
--
-- Only a gap between two inputs the game took is warned - a guard or an expiry
-- at either end means the random grace is not what the number measures. The
-- closing line keeps its own colour: it is a result, not a gap.
local GCT_WARN_AT = 12
local GCT_WARN = "#FF7F00"
local function gct_warn(_n)
	if _n >= GCT_WARN_AT then return GCT_WARN end
	return nil
end

-- THE ARROW BESIDE A WARNED NUMBER GOES ORANGE TOO (user, 2026-09-25).
--
-- gui.image is FBNeo's gdoverlay: position, image and an opacity, no colour.
-- So the orange arrows are their own images, built from the input viewer's
-- arrows by analysis/make_warn_arrows.py - the white fill recoloured, the
-- black outline and every transparent pixel copied as they are.
--
-- There is no orange 5: the neutral arrow has no white fill. Loaded guarded,
-- so a missing file costs the arrow its colour and nothing else - the number
-- beside it still turns orange.
local img_dir_warn = {}
for _, _n in ipairs({ 1, 2, 3, 4, 6, 7, 8, 9 }) do
	local _im = gd.createFromPng("images/" .. _n .. "_dir_warn.png")
	if _im ~= nil then img_dir_warn[_n] = _im:gdStr() end
end
-- The empty button dot, orange, for a late button (gct_draw_buttons). Kept in
-- the same table so this file's main chunk takes no new local.
do
	local _im = gd.createFromPng("images/no_button_warn.png")
	if _im ~= nil then img_dir_warn.no_button = _im:gdStr() end
end
local GCT_BAD = "#FF0000"
local GCT_OK  = "#FFD700"
-- A COLOUR ALWAYS, NEVER nil. The row numbers ask for no particular colour,
-- and passing the nil straight through made gui.text throw
-- "invalid colour" - which takes the whole HUD down with it (user,
-- 2026-09-23). White is what they were drawn in before.
local GCT_PLAIN = "#FFFFFF"
local function gct_at(_x, _y, _s, _r, _c)
	-- Rounded, so two strings never land half a pixel apart.
	gui.text(math.floor(_x + _r - #_s * GCT_CH + 0.5), _y, _s, _c or GCT_PLAIN)
end
local function gct_num(_x, _y, _n, _r, _c)
	gct_at(_x, _y, tostring(_n) .. "t", _r, _c)
end
-- A LATE BUTTON WARNS THE WAY AN ARROW DOES (user, 2026-09-26).
--
-- The arrow's white fill turns orange and its outline stays. The button's
-- counterpart is the empty dots: they turn orange, and the pressed ones keep
-- their colour, because that colour is which strength was pressed. An orange
-- frame round the dots was tried first and looked out of place - the only box
-- in the trace, reading like a selection cursor rather than a warning.
local function gct_draw_buttons(_x, _y, _b, _late)
	if img_no_button == nil then return end
	local _img = { img_L_button, img_M_button, img_H_button }
	local _empty = (_late and img_dir_warn.no_button) or img_no_button
	for _i = 1, 3 do
		gui.image(_x + (_i - 1) * 5, _y,
			(_b[_i] and _img[_i]) or _empty)
		gui.image(_x + (_i - 1) * 5, _y + 5,
			(_b[_i + 3] and _img[_i]) or _empty)
	end
end

local function draw_gc_command_trace()
	if globals.options.display_gc_command_trace ~= true then return end
	local _t = globals.gc_trace
	if _t == nil or _t.guard == nil or #_t.rows == 0 then return end
	-- Moved in from 250: the block sat under the P2 input column and the
	-- Fastest readout at the top right (user, 2026-09-23).
	local _x, _y = 226, 50
	local _t0 = _t.rows[1].t
	gui.text(_x, _y, "GC Command Trace", "#FFD700")
	-- A NUMBER IS COUNTED FROM THE INPUT BEFORE IT, AND BRACKETS MEAN IT WAS
	-- COUNTED AGAINST THE GUARD INSTEAD (user, 2026-09-23).
	--
	-- The guard is not an input, so it never becomes the mark the next row
	-- counts from - but it gets a number of its own, because how long after
	-- the last input the guard landed is what says the motion was early or
	-- late. Brackets say that number is not part of the chain.
	--
	-- The same applies from the other side. Guarding FIRST and then starting
	-- the motion leaves the first direction with no input before it, and it
	-- was drawn bare - but ticks-since-the-guard is exactly what matters
	-- there, so it is shown, in brackets for the same reason.
	--
	-- A DEAD COMMAND CUTS THE CHAIN (user, 2026-09-24).
	--
	-- What follows a re-attached expiry belongs to a second go at the motion,
	-- so counting it from an input of the first one adds three spans together
	-- and reads as one wait. Measured across the two boundaries instead: the
	-- guard from the expiry, and the first direction from the guard - which is
	-- the guard-first rule above, now that nothing before it counts.
	local _last_in = nil    -- the input chain. Only a dead command cuts it:
	                        -- the guard deliberately does not, so the inputs
	                        -- around it keep counting among themselves.
	local _dead_t = nil     -- the last expiry. A guard is measured from it.
	local _mark = nil       -- where a cut chain starts counting again: the
	                        -- guard, or the expiry when the guard came first.
	for _i, _r in ipairs(_t.rows) do
		local _ry = _y + _i * GCT_ROW_H
		if _r.k == "guard" then
			-- A block that landed while the guard pose was persisting - back
			-- already let go - names the tick of it (user, 2026-09-25). "G-"
			-- keeps it beside the plain Guard rows and the GC heading; the
			-- word is the Japanese wiki's own for it. Same length as
			-- "Cmd Expired", so the bracket column needs no room made.
			local _label = "Guard"
			if type(_r.v) == "number" then _label = "G-Persist " .. _r.v end
			gui.text(_x + 2, _ry + 2, _label, "#99EE99")
		elseif _r.k == "dead" then
			-- The command died and a guard came soon enough that the rows above
			-- are still worth reading. Marked so they are not taken for part of
			-- the attempt that follows.
			gui.text(_x + 2, _ry + 2, tostring(_r.v), GCT_BAD)
		elseif _r.k == "btn" then
			-- The number's own test, as for the arrows below, so the dots and
			-- the number cannot disagree.
			gct_draw_buttons(_x + 2, _ry, _r.v or {},
				_last_in ~= nil and gct_warn((_r.t - _last_in) % 256) ~= nil)
		elseif img_dir ~= nil then
			-- The same test the number below makes for this row, so the arrow
			-- and its number cannot disagree.
			local _v = _r.v or 5
			local _img = img_dir[_v]
			if _last_in ~= nil and gct_warn((_r.t - _last_in) % 256) ~= nil then
				_img = img_dir_warn[_v] or _img
			end
			gui.image(_x + 2, _ry, _img)
		end
		-- ONLY AN INPUT THE GAME TOOK CAN BE WARNED (user, 2026-09-24).
		--
		-- Amber says "this gap only got through because the roll went your
		-- way". That reading needs both ends to be inputs of the motion, so
		-- it belongs to the plain numbers alone. A guard is not an input, and
		-- a dead command's number is the wait that killed it rather than one
		-- that was let through - it carries its row's own red instead.
		if _r.k == "guard" then
			-- After an expiry the guard answers "how long was the command
			-- dead before you blocked", which is the boundary worth reading.
			local _from = _dead_t or _last_in
			if _from ~= nil then
				gct_at(_x, _ry + 2, "(" .. (_r.t - _from) % 256 .. "t)",
					GCT_NUM_R + GCT_BRACKET)
			end
		elseif _last_in ~= nil then
			local _n = (_r.t - _last_in) % 256
			local _c = gct_warn(_n)
			if _r.k == "dead" then _c = GCT_BAD end
			gct_num(_x, _ry + 2, _n, GCT_NUM_R, _c)
		elseif _mark ~= nil then
			-- Plain: the guard, or the expiry before it, really is where the
			-- count starts again, so this number IS the chain (user,
			-- 2026-09-24). Only the guard's own number keeps its brackets.
			-- Never amber either - neither end of it is an input.
			gct_num(_x, _ry + 2, (_r.t - _mark) % 256, GCT_NUM_R)
		end
		if _r.k == "guard" then
			_mark = _r.t
		elseif _r.k == "dead" then
			-- Nothing below counts from an input of the attempt that died.
			_dead_t, _mark, _last_in = _r.t, _r.t, nil
		elseif _r.k == "dir" or _r.k == "btn" then
			_last_in = _r.t
		end
	end
	if _t.done ~= nil and _t.at ~= nil then
		-- FAILURES COUNT FROM THE LAST INPUT, NOT FROM THE START.
		--
		-- The step timer starts when a direction is TAKEN, so how long after
		-- your last accepted input the command fell apart is the number that
		-- can be held against the engine's own 14 to 19 tick step timeout.
		-- Counted from the start of the attempt it says nothing you can act
		-- on (user, 2026-09-23: "it should count from after the down-forward").
		--
		-- Guard is not an input, so it is skipped. With no input at all the
		-- guard is all there is to count from.
		local _from = _t.guard
		if _t.done ~= "Success" then
			for _i = #_t.rows, 1, -1 do
				local _k = _t.rows[_i].k
				-- Stop at a dead command: an input above it belongs to the
				-- attempt that already ended, so the guard is the mark.
				if _k == "dead" then break end
				if _k == "dir" or _k == "btn" then
					_from = _t.rows[_i].t
					break
				end
			end
		end
		local _c = (_t.done == "Success") and GCT_OK or GCT_BAD
		local _ry = _y + (#_t.rows + 1) * GCT_ROW_H
		gui.text(_x + 2, _ry + 2, _t.done, _c)
		gct_num(_x, _ry + 2, (_t.at - _from) % 256, GCT_NUM_R, _c)
	end
end

local function draw_gc_frequency_counter()
	if globals.options.display_gc_freq_counter ~= true then return end
	local _r = actionSequenceRunnerModule
	local _seq  = (_r and _r.steps_fired) or 0
	local _drop = (_r and _r.steps_dropped) or 0
	local _wait = (_r and _r.pending_count and _r.pending_count()) or 0
	local _opp  = gc_opportunity or 0
	local _true = gc_rolls_true or 0
	-- Green while the measured rate is within five points of the setting, so
	-- the answer is readable without doing the division.
	local _want = ({ [1] = 0, [2] = 25, [3] = 50, [4] = 75, [5] = 100 })[globals.options.gc_freq] or -1
	local _got  = (_opp > 0) and (_true * 100 / _opp) or -1
	local _c = "#FFFF00"
	if _opp >= 8 and _want >= 0 then
		_c = (math.abs(_got - _want) <= 5) and "#00FF00" or "#FF0000"
	end
	gui.text(21, 36, string.format("GC freq=%s opp=%d roll+=%d arm=%d seq=%d drop=%d wait=%d",
		tostring(globals.options.gc_freq), _opp, _true, gc_fires or 0, _seq, _drop, _wait), _c)
end

-- WHAT THE ACTION STEPS ACTUALLY WAITED.
--
-- The Wait row can say Auto (After) or Auto (Chain) without ever saying how
-- long that turned out to be, and the number is the point: it is what the tool
-- is used to find, and by hand it costs a run per guess. The runner records it
-- where the step fires, so this only prints.
--
--   Step.1 Act:3 / Step.2 Wait:13 Act:1 / Loop Wait:11 / Step.1 Act:3
--
-- Wait is measured; Act is how long the step spends entering its own inputs.
-- Built by actionSequenceRunner.wait_log_lines, which is where the wording and
-- the reasoning behind it live. This only decides where it goes.
--
-- HOW WIDE, MEASURED OFF A SCREENSHOT AND NOT GUESSED.
--
-- The unwrapped line reached the right edge of the 384 px screen at 86
-- characters, starting from x=21: 4.2 px per character. The scrolling input
-- viewer occupies the right of the screen from about x=298, so a line has to
-- stop before that - (298 - 21) / 4.2 = 65 characters.
--
-- Four rows is the cap: a sixteen-step list would otherwise cover the fight.
local WAIT_LOG_COLS = 64
local WAIT_LOG_ROWS = 4
--
-- Ticks, not displayed frames, because that is the unit the Wait row is in.
local function draw_step_wait_ticks()
	if globals.options.display_step_wait_ticks ~= true then return end
	local _r = actionSequenceRunnerModule
	local _lines = _r and _r.wait_log_lines and _r.wait_log_lines(WAIT_LOG_COLS)
	if _lines == nil then return end
	-- One line below the GC counter when both are on, so neither is hidden.
	local _y = (globals.options.display_gc_freq_counter == true) and 46 or 36
	for _i, _l in ipairs(_lines) do
		if _i > WAIT_LOG_ROWS then break end
		gui.text(21, _y + (_i - 1) * 9, _l, "#FFFF00")
	end
end

local function draw_airdash_trainer()
	if globals.options.display_airdash_trainer == true then
		local p1_char = util.get_character(0xFF8400)

		if p1_char ~= "Q-Bee" and p1_char ~= "Zabel" and p1_char ~= "Lei-Lei" and p1_char ~= "Jedah" then
			return
		end

		local copy_of_table = copytable(globals.airdash_heights)
		table.sort(copy_of_table, function (left, right) return left < right end)

		local base_airdash = 50
		local average = 0
		
		for _,item in pairs(globals.airdash_heights) do average = average + item end
		average = average / #globals.airdash_heights
		if tostring(average) == "-nan(ind)"  then average = 0 end
		gui.text(10, base_airdash , "IAD Height. Avg:".. math.floor(average))
		for i = #globals.airdash_heights, 1, -1 do
			local color = "#FFFFFF"
			if globals.airdash_heights[i] == copy_of_table[1] then color = "#00FF00" end
			if globals.airdash_heights[i] == copy_of_table[#copy_of_table] then
				color = "#FF0000" 
			end
			gui.text(10, base_airdash + 10 + ((#globals.airdash_heights - i) * 10), globals.airdash_heights[i], color)
		end
	end
end

-- This function tracks time between dash startup and cancleing dash with attack
local function draw_dash_cancel_trainer()
	if globals.options.display_dash_attack_cancel_trainer == true then
		local p1_char = util.get_character(0xFF8400)

		local base_x = base_x_calc(0, 30, globals.options.display_attack_dash_gap_trainer, globals.options.display_dash_length_trainer, globals.options.display_dash_interval_trainer, 10)

        local da_len = globals.player_state_service.
            p1_derived_events.dash_attack_lengths

		gui.text(base_x, 50 , "Dash\nATK")
        for i, event in ipairs(da_len) do
			local color = "#FFFFFF"
            local printable = string.format("%dF %dT", event["frame_diff"],
                event["tick_diff"])
            -- perfect dashes (fastest consistent dash)
            -- character-dependent timing from
            -- https://darkstalkers-web-fc2-com.translate.goog/savior/system-s/dash-s/dash-s.html?_x_tr_sch=http&_x_tr_sl=ja&_x_tr_tl=en&_x_tr_hl=en&_x_tr_pto=wapp
            -- tested to be accurate for forward dashes
            -- if your backdash has different data, it's not supported
            -- except leilei, where *only* backdash is supported
            if (p1_char == "Sasquatch")
                and event["frame_diff"] == 2 then color = "#00FF00"
            end
            if (p1_char == "Bulleta"
                or p1_char == "Anakaris"
                or p1_char == "Lilith"
                or p1_char == "Victor"
                or p1_char == "Lei-Lei")
                and event["frame_diff"] == 4 then color = "#00FF00"
            end
            if (p1_char == "Bishamon"
                or p1_char == "Q-Bee"
                or p1_char == "Aulbath")
                and event["frame_diff"] == 5 then color = "#00FF00"
            end
            if (p1_char == "Felicia" or
                p1_char == "Gallon")
                and event["frame_diff"] == 6 then color = "#00FF00"
            end
            if (p1_char == "Jedah"
                or p1_char == "Morrigan")
                and event["frame_diff"] == 9 then color = "#00FF00"
            end
            -- Zabel dashing sets the attack flag
            -- So attack delta is always 0, disable feature for him.
            if (p1_char ~= "Zabel"
                and p1_char ~="Demitri") then
                gui.text(base_x, 85 + ((#da_len - i) * 10),
                    printable, color)
            end
        end
	end
end

-- This function tracks the gap between attack ending and dash starting
local function draw_dash_link_trainer()
	if globals.options.display_attack_dash_gap_trainer == true then
		local p1_char = util.get_character(0xFF8400)

		local copy_of_table = copytable(globals.time_between_attack_end_dash_start)
		table.sort(copy_of_table, function (left, right) return left < right end)

		local base_x = base_x_calc(30, 0, globals.options.display_dash_attack_cancel_trainer, globals.options.display_dash_length_trainer, globals.options.display_dash_interval_trainer, 40)

		gui.text(base_x, 50 , "Gap\nBTW\nATK\nDash")
		for i = #globals.time_between_attack_end_dash_start, 1, -1 do
			local color = "#FFFFFF"
			if globals.time_between_attack_end_dash_start[i] == copy_of_table[1] then color = "#00FF00" end
			if globals.time_between_attack_end_dash_start[i] == copy_of_table[#copy_of_table] then
				color = "#FF0000" 
			end
			gui.text(base_x, 85 + ((#globals.time_between_attack_end_dash_start - i) * 10), globals.time_between_attack_end_dash_start[i], color)
		end
	end
end

-- This function checks the frame gaps between a character recovering from hit or block and the next hit or block
local function frame_trap_trainer()
	if globals.options.display_frame_trap_trainer == true then

		local copy_of_table = copytable(globals.frames_between_attacks)
		table.sort(copy_of_table, function (left, right) return left < right end)

		local average = 0
		local x_location = memory.readdword(0xFF8410)

		-- "Frame trap" stays the name of the technique, but the number under it
		-- is a tick count now, so the label has to say so.
		if x_location < screen_midpoint then
			gui.text(310, 50 , "Tick Gap")
		else
			gui.text(10, 50 , "Tick Gap")
		end
		for i = #globals.frames_between_attacks, 1, -1 do
			local color = "#FFFFFF"
			if globals.frames_between_attacks[i] == copy_of_table[1] then color = "#00FF00" end
			if globals.frames_between_attacks[i] == copy_of_table[#copy_of_table] then
				color = "#FF0000" 
			end
			if x_location < screen_midpoint then
				gui.text(310, 60 + ((#globals.frames_between_attacks - i) * 10), globals.frames_between_attacks[i], color)
			else
				gui.text(10, 60 + ((#globals.frames_between_attacks - i) * 10), globals.frames_between_attacks[i], color)
			end
		end
	end
end

local function draw_push_dist()
	if (globals and globals.options and globals.options.show_x_distance == 1) or not globals.pushboxes then
		return
	end
	local distance = globals.dummy.distance_between_players
	local pushes = globals.pushboxes

	if not pushes.p1 or not pushes.p2 then
		return
	end

	local on_left = 'p1'

	if pushes.p1.right > pushes.p2.right then
		on_left = 'p2'		
	end 
	
	if on_left == 'p1' then


		if globals.options.show_x_distance == 3 and pushes and pushes.p1 and pushes.p2 then
			local p1_x = pushes.p1.left + (pushes.p1.right  - pushes.p1.left) / 2
			local p1_y = pushes.p1.top  + (pushes.p1.bottom - pushes.p1.top)  / 2
			local p2_x = pushes.p2.left + (pushes.p2.right  - pushes.p2.left) / 2
			local p2_y = pushes.p2.top  + (pushes.p2.bottom - pushes.p2.top)  / 2
			local x_dist = p2_x - p1_x
			local y_dist = p2_y - p1_y
			local tri_dist = math.sqrt((x_dist^2) + (y_dist^2))
			gui.text(p1_x, 66,  "X Dist: "..(x_dist))
			gui.text(p1_x, 73,  "Y Dist: "..(y_dist))
			gui.text(p1_x, 81,  "Tri Dist: "..(util.round(tri_dist,2)))
			gui.line(
				p1_x,
				p1_y,
				p2_x,
				p2_y,
				"green"
			)
		else
			gui.line(pushes.p1.right, 150, pushes.p2.left, 150 , "green")
			gui.text((pushes.p1.right), 58,  "X Dist: "..distance)
		end
	else
		
		if globals.options.show_x_distance == 3 and pushes and pushes.p1 and pushes.p2 then
			local p1_x = pushes.p1.right + (pushes.p1.left   - pushes.p1.right) / 2
			local p1_y = pushes.p1.top   + (pushes.p1.bottom - pushes.p1.top)   / 2
			local p2_x = pushes.p2.right + (pushes.p2.left   - pushes.p2.right) / 2
			local p2_y = pushes.p2.top   + (pushes.p2.bottom - pushes.p2.top)   / 2
			local x_dist = p1_x - p2_x
			local y_dist = p2_y - p1_y
			local tri_dist = math.sqrt((x_dist^2) + (y_dist^2))
			gui.text(p1_x - 50, 66,  "X Dist: "..(x_dist))
			gui.text(p1_x - 50, 73,  "Y Dist: "..(y_dist))
			gui.text(p1_x - 50, 81,  "Tri Dist: "..(util.round(tri_dist,2)))
			gui.line(
				p1_x,
				p1_y,
				p2_x,
				p2_y,
				"green"
			)
		else
			gui.line(pushes.p2.right, 150, pushes.p1.left, 150 , "green")
			gui.text((pushes.p2.right),  58,  "X Dist: "..distance)
		end
	end
end

local function draw_bishamon_ubk_trainer()
	local p1_char = globals.getCharacter(0xFF8400)
	if globals.options.display_bishamon_ubk_trainer == true and p1_char == "Bishamon" then

		local bish_ubk_distance_object = globals.get_bishamon_ubk_ranges_by_char(0xFF8800)
		local distance = globals.dummy.distance_between_players
		local pushes = globals.pushboxes
		if not bish_ubk_distance_object or not distance then
			return
		end
		-- {
		--     charName = "AU",
		--     standingDist  = { startDist = 74, endDist = 88 },
		--     crouchingDist = { startDist = 74, enddist = 90 },
		--     overlapRange  = { startDist = 74, endDist = 88 }, 
		--     length = 14
		-- },
		if bish_ubk_distance_object.notes then
			gui.text(50,50, bish_ubk_distance_object.notes, "#FFC0CB")
		end


		midpt_x = pushes.p2.left + ((pushes.p2.right - pushes.p2.left) / 2) - 18
		midpt_y = pushes.p2.top + ((pushes.p2.bottom - pushes.p2.top) / 2) - 10

		if
			bish_ubk_distance_object.overlapRange and
			bish_ubk_distance_object.overlapRange.startDist and  
			bish_ubk_distance_object.overlapRange.endDist and  
			distance >= bish_ubk_distance_object.overlapRange.startDist and
			distance <= bish_ubk_distance_object.overlapRange.endDist   
		then
			gui.text(midpt_x, midpt_y,  "Both", "green")
			return
		end

		if 
			bish_ubk_distance_object.standingDist and
			bish_ubk_distance_object.standingDist.startDist and  
			bish_ubk_distance_object.standingDist.endDist and  
			distance >= bish_ubk_distance_object.standingDist.startDist and
			distance <= bish_ubk_distance_object.standingDist.endDist  
		then
			gui.text(midpt_x, midpt_y, "Standing", "green")
			return
		end
		if
			bish_ubk_distance_object.crouchingDist and  
			bish_ubk_distance_object.crouchingDist.startDist and  
			bish_ubk_distance_object.crouchingDist.endDist and  
			distance >= bish_ubk_distance_object.crouchingDist.startDist and
			distance <= bish_ubk_distance_object.crouchingDist.endDist   
		then
				gui.text(midpt_x, midpt_y,  "Crouching", "green")
			return
		end
		gui.text(midpt_x, midpt_y,  "No UBK", "red")
	end
end

local function draw_controlling()
	if globals.controlling_p1 == true then 
		gui.text( 1, 1, "Controlling: P1")
	else 
		gui.text( 1, 1, "Controlling: P2")
	end
end

-- HOW LATE THE DUMMY ACTED, ON SCREEN (v137).
--
-- guardCancel.lua measures it on the tick the dummy becomes free; this only
-- draws it. See the note there for the test.
--
-- WORD CHOICE. The game already prints REVERSAL by itself, and only for a
-- special on the first free frame, so that word is taken and means something
-- narrower than what is being shown here. FASTEST is used for frame one
-- whatever came out - a normal, a throw, a jump and a dash are all just as
-- perfect there, and the whole point is that the game says nothing for them.
--
-- The number matters more than the word. A pass/fail light tells you that you
-- missed; "+3F" tells you by how much, which is the thing you can actually
-- practise against. So a miss prints the count, not a failure message.
local FASTEST_HOLD = 90        -- displayed frames to keep it up
-- The earliest tick each category can appear on, relative to the free tick.
-- Kept here rather than imported so the drawing has no dependency on load
-- order; guardCancel.lua has the same table and the note explaining it.
local FASTEST_FLOOR = {
	["Special"] = 0, ["ES"] = 0, ["EX"] = 0,
	["Normal"] = 1, ["Jump"] = 1, ["Dash"] = 1, ["Dark Force"] = 1,
}
-- Anything not in that table is treated as a next-tick action, which is what
-- everything except a special is. A throw is a command normal, so it belongs
-- with them: earliest on free+1, and calling that "+1F" would be wrong.
local FASTEST_FLOOR_DEFAULT = 1

local function draw_fastest()
	if globals == nil or globals.p2_fastest == nil then return end
	local _f = globals.p2_fastest
	local _age = emu.framecount() - (_f.frame or 0)
	if _age < 0 or _age > FASTEST_HOLD then return end

	-- THE FASTEST FRAME IS NOT THE SAME FOR EVERY CATEGORY.
	--
	-- Only a special (or a guard) can come out on the tick the character
	-- becomes free. A normal, a dash, Dark Force and a jump are refused there
	-- and are earliest on the NEXT tick, so free+1 IS perfect for them and
	-- printing "+1F" would be telling the user off for doing it right.
	local _floor = FASTEST_FLOOR[_f.act or ""] or FASTEST_FLOOR_DEFAULT
	-- No free-1 signature means the input window opens on the free tick, so
	-- nothing can appear before free+1 for this character (see guardCancel.lua).
	if _f.nosig and _floor < 1 then _floor = 1 end
	local _over  = (_f.late or 0) - _floor
	local _text, _color
	if _over <= 0 then
		_text  = "Fastest"
		_color = "#66ff66"
	else
		-- "TICK", NOT "F". A displayed frame is about 1.6 game ticks, so calling
		-- the unit a frame was simply untrue - and every number this tool
		-- measures, places or waits on is counted in ticks.
		_text  = string.format("+%d Tick", _over)
		-- Within a couple of frames is close enough to read as "nearly";
		-- past that it is a different mistake and should look like one.
		_color = (_over <= 2) and "#ffdd55" or "#ff8866"
	end

	local _x = emu.screenwidth() - 83
	local _y = 44
	gui.box(_x - 3, _y - 2, _x + 78, _y + 18, "#00000099", "#00000055")
	gui.text(_x, _y, _text, _color, 0x101000ff)
	-- What actually came out, so "FASTEST" cannot be misread as "the move you
	-- wanted came out" when a normal leaked instead of the special.
	gui.text(_x, _y + 9, _f.act or "", "#c8d8e8", 0x101000ff)
end

local hudModule = {
    -- EXPOSED FOR THE OFFLINE TEST. Nothing executes the drawing otherwise,
    -- which is how a nil colour reached gui.text and took the HUD down.
    ["draw_gc_command_trace"] = draw_gc_command_trace,
    ["registerStart"] = function()
    end,
    ["guiRegister"] = function()
		draw_fd()
		-- PROTECTED, BECAUSE WHAT COMES AFTER IT MATTERS MORE.
		--
		-- The master script calls hudModule.guiRegister() BEFORE
		-- vsavScriptModule.guiRegister(), which is what draws the dummy's
		-- scrolling input column. An error thrown anywhere in here therefore
		-- takes that column - and the hitboxes, and the menu - off the screen
		-- with it, and the symptom reads as "the history stopped displaying"
		-- with nothing pointing at the HUD.
		--
		-- Only this one is wrapped: it is the newest drawing here and the one
		-- reading a table another file fills in.
		local _ok, _err = pcall(draw_fastest)
		if not _ok and debugKnockdownModule and debugKnockdownModule.mark_write then
			debugKnockdownModule.mark_write("fastest_err", 1, 0)
		end
		pcall(draw_position_figure)
		draw_ag_why()
		draw_pb_counter()
		draw_gc_frequency_counter()
		draw_gc_command_trace()
		draw_step_wait_ticks()
		draw_controlling()
		draw_airdash_trainer()
		draw_dash_trainer()
		draw_dash_length_trainer()
		draw_bishamon_ubk_trainer()
		draw_short_hop_counter()
		draw_dash_cancel_trainer()
		draw_dash_link_trainer()
		frame_trap_trainer()
		draw_push_dist()
		draw_pb_stats()
		draw_jump_in_trainer()
		if globals.options.display_recording_gui == true then
			draw_rec()
		end
    end
}

return hudModule
