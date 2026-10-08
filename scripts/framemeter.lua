-- Frame meter module by tirsod - based on vampiresavior001's VSAV Trainer w/ newest tickrate display
-- VSAV_Training: taken from tirsod/VSAV_FrameMeter (fc2-v11, afb0e87). Every
-- local change is marked "VSAV_Training:" so the next sync can carry it over.
	-- TO-DO?
	-- Mark groups of 5/10 | Allow chain timers | Make "Frame meter and you" menu page | Allow for player 2's inputs to be logged also
	-- 

-- Loads the framemeter images
require "gd"
img_noaction = gd.createFromPng("images/framemeter/FM_inactive.png"):gdStr()
img_startup = gd.createFromPng("images/framemeter/FM_startup.png"):gdStr()
img_active = gd.createFromPng("images/framemeter/FM_active.png"):gdStr()
img_recovery = gd.createFromPng("images/framemeter/FM_recovery.png"):gdStr()
img_hurt = gd.createFromPng("images/framemeter/FM_hurt.png"):gdStr()
img_projectile = gd.createFromPng("images/framemeter/FM_projectile.png"):gdStr()
img_invul = gd.createFromPng("images/framemeter/FM_invul.png"):gdStr()
img_nothrow = gd.createFromPng("images/framemeter/FM_nothrow.png"):gdStr()
img_movement = gd.createFromPng("images/framemeter/FM_move.png"):gdStr()

img_noaction_prev = gd.createFromPng("images/framemeter/FMO_inactive.png"):gdStr()
img_startup_prev = gd.createFromPng("images/framemeter/FMO_startup.png"):gdStr()
img_active_prev = gd.createFromPng("images/framemeter/FMO_active.png"):gdStr()
img_recovery_prev = gd.createFromPng("images/framemeter/FMO_recovery.png"):gdStr()
img_hurt_prev = gd.createFromPng("images/framemeter/FMO_hurt.png"):gdStr()
img_projectile_prev = gd.createFromPng("images/framemeter/FMO_projectile.png"):gdStr()
img_invul_prev = gd.createFromPng("images/framemeter/FMO_invul.png"):gdStr()
img_nothrow_prev = gd.createFromPng("images/framemeter/FMO_nothrow.png"):gdStr()
img_movement_prev = gd.createFromPng("images/framemeter/FMO_move.png"):gdStr()

img_pushblock = gd.createFromPng("images/framemeter/FM_pushblock.png"):gdStr()
img_pushblock_OK = gd.createFromPng("images/framemeter/FM_pushblock_OK.png"):gdStr()

img_skipped = gd.createFromPng("images/framemeter/FM_skipped.png"):gdStr()

img_dir_1 = gd.createFromPng("images/framemeter/btn/BT_1.png"):gdStr()
img_dir_2 = gd.createFromPng("images/framemeter/btn/BT_2.png"):gdStr()
img_dir_3 = gd.createFromPng("images/framemeter/btn/BT_3.png"):gdStr()
img_dir_4 = gd.createFromPng("images/framemeter/btn/BT_4.png"):gdStr()
img_dir_5 = gd.createFromPng("images/framemeter/btn/BT_5.png"):gdStr()
img_dir_6 = gd.createFromPng("images/framemeter/btn/BT_6.png"):gdStr()
img_dir_7 = gd.createFromPng("images/framemeter/btn/BT_7.png"):gdStr()
img_dir_8 = gd.createFromPng("images/framemeter/btn/BT_8.png"):gdStr()
img_dir_9 = gd.createFromPng("images/framemeter/btn/BT_9.png"):gdStr()

img_bt = gd.createFromPng("images/framemeter/btn/BT_BG.png"):gdStr()
img_lp = gd.createFromPng("images/framemeter/btn/BT_LP.png"):gdStr()
img_mp = gd.createFromPng("images/framemeter/btn/BT_MP.png"):gdStr()
img_hp = gd.createFromPng("images/framemeter/btn/BT_HP.png"):gdStr()
img_lk = gd.createFromPng("images/framemeter/btn/BT_LK.png"):gdStr()
img_mk = gd.createFromPng("images/framemeter/btn/BT_MK.png"):gdStr()
img_hk = gd.createFromPng("images/framemeter/btn/BT_HK.png"):gdStr()

-- Images for every state. [1] for current block, [2] for previous.
local states = {
	{img_noaction, img_noaction_prev},			-- 0/1/nil
	{img_startup, img_startup_prev},			-- 2
	{img_active, img_active_prev},				-- 3
	{img_recovery, img_recovery_prev},			-- 4
	{img_hurt, img_hurt_prev},					-- 5
	{img_projectile, img_projectile_prev},		-- 6
	{img_nothrow, img_nothrow_prev},			-- 7
	{img_invul, img_invul_prev},				-- 8
	{img_movement, img_movement_prev}			-- 9
}

-- Intended for images that overlay on top of the frames. Pushblock timer primarily, though pursuit and mash timers come to mind.
local timers = {
	img_pushblock, -- 1
	img_pushblock_OK -- 2
}

-- Images to display "input tombstones" on top of the frames.
local input_images = {
	{img_dir_1, img_dir_2, img_dir_3, img_dir_4, img_dir_5, img_dir_6, img_dir_7, img_dir_8, img_dir_9}, -- Literally.
	{img_lp, img_mp, img_hp, img_lk, img_mk, img_hk} -- Buttons.
}

-- Stated format: 0/nil/1 = idle | 2 > refer to states[]
-- state_log[] shows player status per frame (tick). 
-- [1] = States, player 1
-- [2] = States, player 2
-- [3] = Timers, player 1
-- [4] = Timers, player 2
-- [5] = Inputs, player 1 only
-- [6] = Inputs, player 2 (Not implemented)
-- [7] = Displayed frame each tick was logged in (VSAV_Training: 120Hz ticks)
-- [8] = Reversal-only tick, player 1 (VSAV_Training, see REVERSAL-ONLY TICK)
-- [9] = Reversal-only tick, player 2
-- [10] = Still in hitstop, player 1 (VSAV_Training, see read_motion)
-- [11] = Still in hitstop, player 2
-- [12] = Throw invulnerable ($143), player 1 (VSAV_Training, display only)
-- [13] = Throw invulnerable ($143), player 2
-- [14] = Invulnerable, player 1 (VSAV_Training, display only - see mark_lower)
-- [15] = Invulnerable, player 2
-- breakdown_log[] shows number of grouped frames counted @ specific positions 
-- [1] = Player 1
-- [2] = Player 2
-- [3] = Open/Close for editing

local state_log = {}
local breakdown_log = {{},{},true}

local function reset_state_log()
	state_log = {{},{},{},{},{},{},{},{},{},{},{},{},{},{},{}} -- VSAV_Training: [7]..[15]
	breakdown_log = {{},{},true}
end
reset_state_log()

-- Stores display and positioning data for the meter 
local meter_anchor = {
	scroll = 0,
	scroll_hold = 0,
	bound = -90,
	widget_x_offset = 0,
}

-- Stores display and positioning data for the text above meter 
local measure_anchor = {
	y = 4,
	normal = 1,
	offset = -6,
	buttons_y = 2
}

-- Screen height for drawing the frame meter.
-- Why does emu.getscreenheight() different values on startup & when the .lua is loaded manually?
local _height = 220

-- Set logging variables & log length
local subscription_generation = 0
local log_drawn = 90
local log_length = log_drawn * 9
local log_position = 0
local idle_frames = 0
local max_idle_frames = 5
local last_inputs = {}
local last_button_string = ""
local freezeNextFrame = false

-- Debugging variable
local test_state = "actionable"

-- VSAV_Training: the easter egg (a shake on toggling Include Hitstop, then the
-- meter blowing apart with scrolling rainbow text, closing the menu and
-- handing both players back) was removed (user, 2026-10-06), and the credits
-- text draw_meter kept off screen with it (2026-10-08).

-- Borrowed from other files.
local super_mode = false
local game

-- Addresses for the game's various flags
-- VSAV_Training: the current cel's +$0B is negative and not $FF - the strike
-- test turns ordinary attacks away (0x018040). See invulnerable below.
-- free_before[addr]: $05 was 0 on the tick before this one (read_free_ticks);
-- nil when not known (the first tick, a load).
local free_before = {}
local function strike_shy_cel(addr)
	local cel = memory.readdword(addr + 0x1C) or 0
	if cel == 0 then return false end
	local f = memory.readbyte(cel + 0x0B)
	return f >= 0x80 and f ~= 0xFF
end
-- VSAV_Training: NO INVULNERABILITY IS DRAWN WHILE DOWN OR IN RECOVERY (user,
-- 2026-10-08): "invulnerable shows not being hit where you would be hit", and
-- "throw invulnerability while down is a given - showing it is wrong". While a
-- character is in recovery ($05 = 2: hit, block, knocked down - on the ground
-- or in the air) or in a cel whose +$0B is $FE (lying down, getting up), the
-- game is protecting it anyway, so neither the white nor the throw stripes are
-- drawn. Q-Bee's head shake is the exception: still $FE, but from the tick
-- after she is free again ($05 = 0 twice) she can start anything.
local function marks_off(addr)
	if strike_shy_cel(addr) then
		return not (memory.readbyte(addr + 0x05) == 0 and free_before[addr] == true)
	end
	return memory.readbyte(addr + 0x05) == 0x02
end

local profile = {
	{
		games = {"vsav","vhunt2","vsav2"},
		address = {0xFF8400, 0xFF8800},
		PROJ = 0xFF9400,
		PROJ_COUNT = 32,
        attacking = function(addr) return memory.readbyte(addr + 0x105) == 0x01 end,

        status_1 = function(addr) return memory.readbyte(addr + 0x05) end,
		hurt      = function(addr) return memory.readbyte(addr + 0x005) == 0x02 end,
		hitstop	 = function(addr) return memory.readbyte(addr + 0x05C) end,
		thrown    = function(addr) return memory.readbyte(addr + 0x005) == 0x06 end,
		throwing  = function(addr) return memory.readbyte(addr + 0x005) == 0x04 end,

		status_2 = function(addr) return memory.readbyte(addr + 0x06) end,
		walking = function(addr) return memory.readbyte(addr + 0x06) == 0x04 end,
		supering  = function(addr) return memory.readbyte(addr + 0x06) == 0x12 end,
		dfreturn  = function(addr) return memory.readbyte(addr + 0x06) == 0x1A end,
		-- VSAV_Training: the Dark Force activation itself (invuln_log.json:
		-- $06 = 0x16 while $147 counts down from 43, Bishamon).
		dfstart   = function(addr) return memory.readbyte(addr + 0x06) == 0x16 end,

		hitfreeze = function(addr) return memory.readbyte(addr + 0x05C) ~= 0x00 end,
		knockdown = function(addr) return memory.readbyte(addr + 0x1A7) ~= 0 end,
		-- VSAV_Training: INVULNERABLE AS THE HITBOX DISPLAY HAS IT (user,
		-- 2026-10-08). This read $147 only, so Bishamon's Kirisute Gomen - fully
		-- invulnerable on its frames 1-13 by the tables - showed nothing: it has
		-- no hurtbox ($94-$96 all 0) and every flag clear (invuln_log.json from
		-- the game). cps2-hitboxes.lua hides a hurtbox for $134, $147, $11E, or
		-- $145 with $1A4 = 0, and a box id of 0 draws nothing; the game's own
		-- throw check (0x029406) refuses an opponent whose $94-$96 are all 0.
		-- VSAV_Training: DOWN IS NOT INVULNERABLE (user, 2026-10-08). See
		-- marks_off above: nothing while down or in recovery. Lying down and
		-- getting up are cels with +$0B = $FE, which the strike test turns away
		-- (0x018040), and usually no hurtbox; not every wake-up ends in $FE
		-- (Morrigan's last 6 ticks are an ordinary cel with no hurtbox and $145),
		-- which is why $05 = 2 counts too. The white used to run to the tick
		-- before the reversal tick on every wake-up.
		-- Q-BEE'S HEAD SHAKE: her last wake-up cel keeps $FE for 3-4 ticks after
		-- she is free again ($05 = 0), and from the tick after she becomes free
		-- she can start anything (Meaty Timing's Actionable +0t) - there it is a
		-- real invulnerability, and her throw invulnerability ($143) runs with
		-- it. The tick she becomes free is not: nothing she does comes out on
		-- it, so in effect she is still down (user, 2026-10-08).
		-- analysis/QBEE_WAKEUP_HEADSHAKE_SURVEY.ja.md 9.
		invulnerable = function(addr)
			if marks_off(addr) then return false end
			if strike_shy_cel(addr) then return true end
			return memory.readbyte(addr + 0x134) > 0
				or memory.readbyte(addr + 0x147) > 0
				or memory.readbyte(addr + 0x11E) > 0
				or (memory.readbyte(addr + 0x145) > 0 and memory.readbyte(addr + 0x1A4) == 0)
				or (memory.readbyte(addr + 0x94) == 0 and memory.readbyte(addr + 0x95) == 0
					and memory.readbyte(addr + 0x96) == 0)
		end,
		nothrow = function(addr) return memory.readbyte(addr + 0x143) ~= 0 end,
		
		jump = function(addr) 	 return memory.readbyte(addr + 0x006) == 0x06 end,
		dash = function(addr) 	 return memory.readbyte(addr + 0x006) == 0x14 end,
		stunned = function(addr) return memory.readbyte(addr + 0x006) == 0x02 end,

		pushblock = function(addr) return memory.readbyte(addr + 0x1AB) end,
		pbsuccess = function(addr) return memory.readword(addr + 0x1B0) end
	}
}
for _, game in ipairs(profile) do
	game.update = game.update or {func = emu.registerafter, cycle = 1}
end
local get_attack_state = {
	[false] = function(addr) --non-super mode
		return game.attacking(addr)
	end,

	[true] = function(addr) --super mode
		return game.supering(addr)
	end,
}

-- --	Utility functions.
-- --	attack_box and player_owns_projectile from tickDataVsav.lua
local function bool(v) return v == true end
local function clamp(x, min, max)
	if x < min then return min
	elseif x > max then return max end
	return x
end
any_true = function(condition)
	for n = 1, #condition do
		if condition[n] == true then return true end
	end
end
local function attack_box(base)
	local cel = memory.readdword(base + 0x1C)
	if cel == nil or cel == 0 then return 0 end
	return memory.readbyte(cel + 0x0A)
end
local function player_owns_projectile(player_address)
	local PROJ_COUNT = game.PROJ_COUNT
	local PROJ = game.PROJ

	for i = 0, PROJ_COUNT - 1 do
		local b = PROJ + i * 0x100
		if memory.readword(b) > 0x0100 and memory.readbyte(b + 0x04) == 0x02 then
			local owner = memory.readword(b + 0x30)
			local id = attack_box(b)
			return owner == (player_address % 0x10000) and id ~= 0
    	end
  	end
	return false
end


--	--	--	--	--	--	--	--	--
--	--	Frame meter begins	--	--
--	--	--	--	--	--	--	--	--

--	Returns player object populated with boolean variables for every flag.
local function get_player_objects()
	local player = {{}, {}}
	for p = 1, 2 do --get the current status of the players from RAM
		local addr = game.address[p]
		local opp_addr = (p == 1 and game.address[2]) or game.address[1]
		player[p].attacking   = get_attack_state[super_mode](addr)
		player[p].hurt        = game.hurt(addr)
		player[p].hitstop     = game.hitstop(addr)
		player[p].thrown      = game.thrown(addr)
		player[p].throwing 	  = game.throwing(addr)
		player[p].hitfreeze   = game.hitfreeze(addr, opp_addr)
		player[p].superfreeze = game.superfreeze and game.superfreeze(addr, opp_addr)
		player[p].projectile  = player_owns_projectile(addr)
		player[p].attack_box  = bool(attack_box(addr) ~= 0)
		player[p].knockdown   = game.knockdown(addr)
		player[p].invulnerable= game.invulnerable(addr)
		player[p].nothrow     = game.nothrow(addr) and not marks_off(addr) -- VSAV_Training
		
		player[p].jump		  = game.jump(addr)
		player[p].dash	      = game.dash(addr)
		player[p].movement 	  = player[p].jump or player[p].dash
		player[p].stunned	  = game.stunned(addr)
		player[p].status_1	  = game.status_1(addr)
		player[p].status_2	  = game.status_2(addr)
		player[p].walking 	  = game.walking(addr)
		player[p].dfreturn 	  = game.dfreturn(addr)
		player[p].dfstart 	  = game.dfstart(addr) -- VSAV_Training

		player[p].pbtimer	  = game.pushblock(addr)
		player[p].pbsuccess   = game.pbsuccess(addr)
	end
	return player
end

-- Returns input from Player 1 exclusively
local function get_player_inputs()
	local base = 0xFF8400
	local btn = memory.readbyte(base + 0x122)
	local dir = memory.readbyte(base + 0x125)
	local facing = memory.readbyte(base + 0x00B)
	local bit0 = (dir % 2) >= 1
	local bit1 = (math.floor(dir / 2) % 2) >= 1
	local _left, _right
	if facing == 0 then
		_left, _right = bit1, bit0
	else
		_left, _right = bit0, bit1
	end
	local _down = (math.floor(dir / 4) % 2) >= 1
	local _up   = (math.floor(dir / 8) % 2) >= 1
	local _direction = 5
	if _down then
		if _left then _direction = 1
		elseif _right then _direction = 3
		else _direction = 2 end
	elseif _up then
		if _left then _direction = 7
		elseif _right then _direction = 9
		else _direction = 8 end
	else
		if _left then _direction = 4
		elseif _right then _direction = 6
		else _direction = 5 end
	end
	local press = false
	local count = 0
	local btn_str = ""
	local function pressed(bit_index)
		local v = (math.floor(btn / 2 ^ bit_index) % 2) >= 1
		if v then
			press = true
			count = count + 1
			btn_str = btn_str .. tostring(bit_index)
		end
		return v
	end
	local inputs = {
		directional = _direction,
		buttons = {pressed(0), pressed(1), pressed(2), pressed(4), pressed(5), pressed(6)}, -- Why is 4 skipped again?
		pressed = press,
		button_count = count,
		button_string = btn_str,
		release = string.len(btn_str) < string.len(last_button_string)
	}
	return inputs
end

-- Logs each player's statuses to state_log[1/2][log_position]
-- VSAV_Training: REVERSAL-ONLY TICK (user, 2026-10-06/07). The tick on which
-- a character coming out of hit stun, block stun, a knockdown or an air
-- recovery can start a SPECIAL (or guard) but not yet a normal, dash, jump or
-- Dark Force. Measured and recorded in guardCancel.lua ("WHAT IS ALLOWED ON
-- THE FREE TICK"): a special pressed on free-1 starts on free+0 (336 spans),
-- everything else pressed on free+0 starts on free+1 - so free+0 is the tick.
--
-- free-1 is marked by the game itself: 0x024F0A writes $04..$07 = 02 02 04 00
-- on the last recovery tick, and 0x024F12 opens the special input window
-- ($174) right after - which is why only a special can make the next tick.
-- The signature held on every transition of two batches (68 and 112) across
-- wake-up, air recovery and ground hit / block, and on 249 of 250 wake-ups.
-- The mark goes on the first tick that no longer carries it. In the archived
-- per-tick logs it lasted exactly one tick on all 4358 recoveries (2026-10-07,
-- knockdown 554, guard 195, hit the rest); an earlier note that it sometimes
-- lasts two (15 of 103) could not be traced to its data. Read this way, a
-- longer one would still be marked on its end.
--
-- Q-Bee's wake-up does not write it (0 of 21) and opens her window one tick
-- late, so her specials come out on free+1 like everything else: no mark.
--
-- Read every tick from the state itself - not from the dummy's input
-- preparation, not from any reversal setting - so it shows for P1 and P2,
-- with or without a guard action, whether a move comes out or not.
-- VSAV_Training: HITSTOP. A character is STILL on a tick when it is in
-- hitstop ($5C) and did not move. "Move" is the animation advancing - $20
-- (the cel's remaining ticks) or $1C (the cel) changing, the test Tick Data
-- uses - and only counts for a character that is attacking: Demitri's
-- crouching HK keeps animating through its own hitstop, while a defender's
-- cel is swapped as it enters guard without anything playing.
--
-- A still tick is drawn with a gray top and left out of that character's
-- numbers and run counts, so the numbers do not depend on which hitstop ticks
-- are on screen. Which ones are: all of them while Show P1 Inputs is on -
-- inputs are taken during hitstop, and seeing when they went in is what the
-- inputs are shown for (user, 2026-10-07; this replaced Include Hitstop) -
-- and otherwise only the ticks in which an attacking character moved.
--
-- AN ATTACKER IS STILL WHILE ANYONE IS IN HITSTOP, not only while its own $5C
-- is set. The attacker's $5C reaches 0 a tick before the defender's, and on
-- that tick it has not moved yet. Asking only its own $5C counted that tick
-- as active with Show P1 Inputs on, while with it off the tick was skipped -
-- close LP blocked read Total 14 against 13 (user's screenshots, 2026-10-07).
-- This is the same test the skip uses, so the two cannot drift apart.
-- The defender keeps its own $5C: its yellow then matches Tick Data's Hitstun.
local last_anim = { nil, nil }
local still_now = { false, false }
local function read_motion()
	local moved = false
	local frozen_any = game.hitfreeze(game.address[1]) or game.hitfreeze(game.address[2])
	for p = 1, 2 do
		local addr = game.address[p]
		local a = memory.readbyte(addr + 0x20) * 0x10000 + ((memory.readdword(addr + 0x1C) or 0) % 0x10000)
		local advanced = last_anim[p] ~= nil and a ~= last_anim[p]
		local attacking = get_attack_state[super_mode](addr)
		if advanced and attacking then moved = true end
		if attacking then
			still_now[p] = frozen_any and not advanced
		else
			still_now[p] = game.hitfreeze(addr)
		end
		last_anim[p] = a
	end
	return moved
end

-- VSAV_Training: AG success, read every tick. The opponent's push block
-- pushback timer ($1B0) at 1..3 is what the original read, on the tile it
-- logged; held here until a tile is logged, and dropped if none is.
local pb_success_pending = { false, false }
local function read_pb_success()
	for p = 1, 2 do
		local op = (p == 1) and 2 or 1
		local v = game.pbsuccess(game.address[op])
		if v > 0 and v <= 3 then pb_success_pending[p] = true end
	end
end

-- VSAV_Training: THROWS (user, 2026-10-08). A throw has no attack box, so the
-- meter drew a whole throw as startup and nothing red, and the one thrown as
-- doing nothing. The throw is checked by the game's own routine on every tick
-- its window is out - the grab attempts Tick Data hooks (tickDataVsav.lua
-- "THE ATTEMPTS, NOT THE RANGE CHECK") - and on the tick the opponent turns
-- thrown; those ticks are drawn as active here. The hooks are Tick Data's:
-- registering a second one would replace it, so its per-player count is read
-- instead. Being thrown ($05 = 0x06, the test refresh_meter and Tick Data
-- already use) is drawn as hurt.
-- tickDataVsav is already loaded by framedata.lua before this file is, so the
-- require is answered from the cache; offline tests preload a stand-in.
local tdv_ok, tickDataVsav = pcall(require, "./scripts/tickDataVsav")
if not tdv_ok then tickDataVsav = nil end
local last_throw_checks = { nil, nil }
local was_thrown = { false, false }
local throw_now = { false, false }
local function read_throw_checks()
	local thrown_now = { false, false }
	for p = 1, 2 do
		local t = game.thrown(game.address[p])
		-- false, not nil: after a load the first read is only a baseline.
		thrown_now[p] = t and was_thrown[p] == false
		was_thrown[p] = t
	end
	for p = 1, 2 do
		local n = tickDataVsav and tickDataVsav.throw_checks
			and tickDataVsav.throw_checks(game.address[p]) or nil
		throw_now[p] = (n ~= nil and last_throw_checks[p] ~= nil and n ~= last_throw_checks[p])
			or thrown_now[(p == 1) and 2 or 1]
		last_throw_checks[p] = n
	end
end

-- VSAV_Training: whether each player was free ($05 = 0) on the tick before,
-- for invulnerable (Q-Bee's head shake). Read every tick, logged or not.
local free_now = {}
local function read_free_ticks()
	for p = 1, 2 do
		local addr = game.address[p]
		free_before[addr] = free_now[addr]
		free_now[addr] = memory.readbyte(addr + 0x05) == 0
	end
end

local REVERSAL_SIGNATURE = 0x02020400
local signature_seen = { false, false }
local reversal_now = { false, false }
local function read_reversal_ticks()
	for p = 1, 2 do
		local sig = memory.readdword(game.address[p] + 0x04) == REVERSAL_SIGNATURE
		reversal_now[p] = signature_seen[p] and not sig
		signature_seen[p] = sig
	end
end

local function log_player_state(tick)
    local player = get_player_objects()
	for p = 1, 2 do
		-- set current frame's state for each player @ log_position
		local previousState = state_log[p][log_position-1%log_length]

		local priolist = {
			-- VSAV_Training: invulnerability is not a state any more (user,
			-- 2026-10-08). It replaced whatever the tick was, so a move whose
			-- invulnerability ends during startup showed white then green, and
			-- Startup was counted from the change. It is kept in [14] / [15] and
			-- drawn on the lower half of the tile (mark_lower), like throw
			-- invulnerability before it.
			-- VSAV_Training: throw invulnerability is not a state any more. It
			-- replaced startup / active / recovery under it, so switching its
			-- display changed the numbers. It is kept in [12] / [13] and drawn
			-- on the lower half of the tile (mark_lower).
			-- VSAV_Training: a throw's window is active too (read_throw_checks).
			{player[p].attack_box or throw_now[p], 3},
			-- VSAV_Training: and being thrown is being hurt.
			{player[p].hurt or player[p].knockbox or player[p].thrown, 5},
			{player[p].dfreturn, 4},
			-- VSAV_Training: Dark Force activation is an animation, drawn as
			-- startup (user, 2026-10-08). It used to show as the white tile;
			-- once invulnerability moved to the lower half it read as doing
			-- nothing. As startup it also keeps the numbers that tile gave
			-- (Startup 43 / Total 43 for Bishamon's).
			{player[p].dfstart, 2},
			{player[p].projectile, 6},
			{player[p].attacking and (previousState == 3 or previousState == 4 or previousState == 6) and (not player[p].walking), 4},
			{player[p].attacking and (not player[p].walking or player[p].throwing), 2},
			{player[p].movement and globals.options.fm_movement_data, 9},
		}

		state_log[p][log_position] = 0
		for _, item in ipairs(priolist) do
			if item[1] then
				state_log[p][log_position] = item[2]
				break
			end
		end

		state_log[p+2][log_position] = 0
		if player[p].pbtimer > 0 then
			state_log[p+2][log_position] = 1
		end

		-- VSAV_Training: the success is noted every tick (read_pb_success),
		-- so one that falls inside skipped hitstop still lands on a tile.
		if pb_success_pending[p] then
			state_log[p+2][log_position] = 2
			pb_success_pending[p] = false
		end
		-- VSAV_Training: still in hitstop (not counted) and throw invulnerable.
		state_log[9+p][log_position] = still_now[p] or nil
		state_log[11+p][log_position] = player[p].nothrow or nil
		state_log[13+p][log_position] = player[p].invulnerable or nil
	end
	-- VSAV_Training: the displayed frame this tick ran in (see second_of_pair).
	state_log[7][log_position] = emu.framecount()
	-- VSAV_Training: this tick's own reversal-only flag (see REVERSAL-ONLY TICK).
	state_log[8][log_position] = reversal_now[1] or nil
	state_log[9][log_position] = reversal_now[2] or nil
	log_position = (log_position + 1) % log_length
end

-- Logs inputs to Player 1's input array. state_log[5][log_position]
local function log_player_inputs()
	local inputs = get_player_inputs()
	if (inputs.button_string ~= last_button_string or inputs.directional ~= last_inputs.directional) then
		state_log[5][log_position] = inputs
		last_button_string = inputs.button_string
	end
	last_inputs = inputs
end

-- Calculates attack startup, recovery, totals and advantages.
local function measure_player(player)
	local recovery, active, startup = 0, 0, 0
	local idle_offset = nil
	local startup_type = 2
	local last_change_at = log_position
	local last_state_seen = 0
	local states_counted = 0
	local counting_rec = true

	local function state(at)
		local index = at % log_length
		return state_log[player][index]
	end
	-- VSAV_Training: a tick this character spent still in hitstop is not
	-- counted and does not break a run (see read_motion).
	local function still(at)
		return state_log[9 + player][at % log_length]
	end

	local function is_idle_state(state)
		return state == nil or state == 0 or state == 1 or state == 7 --or state == 6 -- or state == 9
	end

	local function add_to_breakdown(s, i)
		breakdown_log[player][last_change_at] = states_counted
		if player == 2 then print("lol: "..tostring(breakdown_log[player][last_change_at])) end 
		last_state_seen = s
		states_counted = 1
		last_change_at = i
	end

	local function close_breakdown()
		if player == 2 then -- player 1 was closing the breakdown before player 2 could use it. WOW.
			breakdown_log[3] = false
		end
	end

	local function breakdown_is_open() return breakdown_log[3] end

	for i = log_position, 0, -1 do
		local s = state(i)
		if still(i) then
			-- VSAV_Training: not counted
		else
		if not is_idle_state(s) and idle_offset == nil then
			idle_offset = i
		end

		if idle_offset ~= nil then
			if s == 4 then
				if counting_rec then recovery = recovery + 1 end
			elseif s == 3 then
				active = active + 1
				counting_rec = false
			elseif s == 2 or s == 8 or s == 6 then --or state == 9 then
				if startup_type ~= s then
					startup_type = s
					startup = 0
				end
				startup = startup + 1
			end

			if is_idle_state(s) then
				break
			end
		end
		end
	end

	for i = log_position, 0, -1 do
		local s = state(i)
		if (idle_frames > max_idle_frames and breakdown_is_open()) and not still(i) then
			if (last_state_seen ~= s) then
				add_to_breakdown(s, i)
			elseif (s ~= nil and s > 1) then
				states_counted = states_counted + 1
			end
		end
	end

	if (idle_frames > max_idle_frames and breakdown_is_open()) then
		print("breakdown every frame?")
		add_to_breakdown(s, i)
		close_breakdown()
	end

	-- Inclusive frame counting
	-- VSAV_Training: the tick the character can act again belongs to recovery
	-- even when no recovery tile came before it (2026-10-08). Midnight Pleasure
	-- whiffed goes straight from its 29 active ticks to free, and the tables
	-- and Tick Data read recovery 1 there; this read 0. So the tick is added
	-- once the move has ended - the last tick logged is idle - not only after
	-- a blue tile. While the move is still running nothing is added.
	local ended = is_idle_state(state(log_position - 1))
	if recovery > 0 or (active > 0 and ended) then recovery = recovery + 1 end
	local total = (startup + active + recovery)
	if active > 0 then startup = startup + 1 end
	total = total
	if total < 0 then total = 0 end

	return tostring(startup), tostring(total), tostring(recovery), idle_offset
end

-- Awaits for the player to idle for 5 frames before restarting variables and clearing meter.
local function refresh_meter()
	local player_state = {false, false}

	-- TODO: Merge this with is_idle_state(s) or make a new function that returns idle states from state_log
	for p = 1, 2 do
		local addr = game.address[p]
		player_state[p] = 
			(get_attack_state[super_mode](addr) and (not game.walking(addr)))
			or game.hurt(addr)
			or game.thrown(addr)
			or game.hitfreeze(addr, game.address[(p == 1 and 2) or 1])
			or (game.superfreeze and game.superfreeze(addr, game.address[(p == 1 and 2) or 1]))
			or game.invulnerable(addr)
			-- VSAV_Training: throw invulnerability keeps the meter recording
			-- whether or not it is shown, so the display cannot cut a run short.
			or game.nothrow(addr)
			or globals.options.fm_movement_data and (game.dash(addr) or game.jump(addr))
			or game.dfreturn(addr)
			or game.dfstart(addr) -- VSAV_Training
			or player_owns_projectile(addr)
	end

	if any_true(player_state) then
		test_state = "action"
		if idle_frames > 0 and idle_frames < max_idle_frames then idle_frames = 1 end
	else
		test_state = "idle"
		idle_frames = idle_frames + 1
	end

	if idle_frames >= max_idle_frames and test_state == "action" then
		idle_frames = 0
		log_position = 0
		last_inputs.button_count = -1
		last_button_string = ""
		meter_anchor.scroll = 0

		reset_state_log()
	end
end

-- VSAV_Training: the reversal-only mark - a bar over the top two rows of the
-- tile's fill, in MAGENTA, which no tile and no other mark uses. Light gray on
-- one row was tried first and did not stand out; then the hurt tiles' yellow
-- (#FFF730), which is the hurt tile's own colour - so a meaty that lands ON the
-- reversal tick, the case the mark matters most for, turns that tile yellow and
-- the mark vanished into it (user, 2026-10-07 / 08, Meaty Timing +0t). The tile
-- keeps its own colour on the four rows below - a special that starts on this
-- tick is green there - and the 120Hz dots sit on the third row, so neither
-- covers the other.
local FM_REVERSAL = { "#FF40FFFF", "#7F207FFF" } -- current block, previous block
-- VSAV_Training: the same two rows say "still in hitstop, not counted" in gray.
-- The two never fall on one tick; if they did, the reversal is drawn last.
local FM_STILL = { "#B0B0B0FF", "#585858FF" }
local function mark_top(player, i, x, y, block)
	if state_log[9 + player][i] then
		gui.box(x + 1, y + 1, x + 3, y + 2, FM_STILL[block], FM_STILL[block])
	end
	if state_log[7 + player][i] then
		gui.box(x + 1, y + 1, x + 3, y + 2, FM_REVERSAL[block], FM_REVERSAL[block])
	end
end

-- VSAV_Training: THE LOWER HALF OF THE FILL (rows 4-6) says what cannot touch
-- the character, over whatever the tile is. Display only: the tile's own state,
-- and the numbers, are unaffected.
--   solid white   invulnerable ([14] / [15]) - strikes and throws alike, as the
--                 game's throw check refuses an invulnerable opponent too.
--                 Always shown, as the white tile it replaces was.
--   stripes       throw invulnerable only ($143), the old throw-invulnerable
--                 tile's colours; with Show Throw Invulnerability.
local FM_INVUL = { "#F2F2F2FF", "#3C3C3CFF" } -- the invulnerable tiles' colours
local FM_NOTHROW = { { "#EFF5F1FF", "#CA275FFF" }, { "#3C3D3CFF", "#320A18FF" } } -- even, odd row
local function mark_lower(player, i, x, y, block)
	if state_log[13 + player][i] then
		gui.box(x + 1, y + 4, x + 3, y + 6, FM_INVUL[block], FM_INVUL[block])
	elseif globals.options.fm_no_throw and state_log[11 + player][i] then
		local even, odd = FM_NOTHROW[block][1], FM_NOTHROW[block][2]
		gui.box(x + 1, y + 4, x + 3, y + 4, even, even)
		gui.box(x + 1, y + 5, x + 3, y + 5, odd, odd)
		gui.box(x + 1, y + 6, x + 3, y + 6, even, even)
	end
end

-- VSAV_Training: 120HZ TICKS. At turbo the game runs four Ticks in three
-- displayed frames, so one frame in three carries two Ticks, each on screen for
-- half a frame. state_log[7] holds the displayed frame each logged tick ran
-- in; two neighbours with the same frame are such a pair. At normal speed
-- every frame holds one tick and nothing is marked.
--
-- One black dot each side of the border the pair shares, on the third of
-- the fill's six rows: the arms of a "+" whose upright is that border. The
-- fourth row read as below the middle (user, 2026-10-04: 1ドット上で). Only on a tile that is
-- doing something - idle tiles are black already, and an idle tile in the
-- previous block is not drawn at all, so a dot there would land on the game
-- (user, 2026-10-04: 黒で左右に1ドット). Tried before and dropped, all on
-- 2026-10-04: a paler tile (striped, and pale red read as another state), a
-- dot in each tile (noisy), a white mark on the border (white too loud), the
-- border filled in the tiles' own colour (the user settled on the dots).
local FM_120HZ_DOT = "#000000FF"
local function fm_idle(st) return st == nil or st == 0 or st == 1 end
-- True when tick i ran in the same displayed frame as tick i-1, wrap included.
local function second_of_pair(frames, i, n)
	local f = frames[i]
	if f == nil then return false end
	local prev = i - 1
	if prev < 0 then prev = prev + n end
	return frames[prev] == f
end
-- Called after tile i is drawn at (x, y). Tiles are 5x8 at a 4px pitch, so
-- column x is the border tile i shares with tile i-1 on its left. Not on the
-- first tile of a run: tile i-1 is drawn elsewhere (the far end, or the gap
-- before the previous block), so there is no shared border. x - 1 is the
-- last fill column of tile i-1, x + 1 the first of tile i.
local function mark_120hz(player, i, x, y, first_of_run)
	if first_of_run or not second_of_pair(state_log[7], i, log_length) then return end
	local prev = i - 1
	if prev < 0 then prev = prev + log_length end
	if not fm_idle(state_log[player][prev]) then
		gui.box(x - 1, y + 3, x - 1, y + 3, FM_120HZ_DOT, FM_120HZ_DOT)
	end
	if not fm_idle(state_log[player][i]) then
		gui.box(x + 1, y + 3, x + 1, y + 3, FM_120HZ_DOT, FM_120HZ_DOT)
	end
end

-- Draws the meter to the screen, using the data from the logged states and inputs.
local function draw_meter()
    drawX = 8 + meter_anchor.widget_x_offset
    drawY = _height - 64

	local measure1_target = measure_anchor.normal
	if (globals.options.fm_input_p1) then measure1_target = measure_anchor.offset end

	local lerp = (measure_anchor.y - measure1_target) * .3
	measure_anchor.y = measure_anchor.y - lerp
	if (math.abs(lerp) < .1) then measure_anchor.y = measure1_target end

	-- VSAV_Training: the credits text that sat here, off screen to the left,
	-- was removed (user, 2026-10-08): scrolling the meter brought it onto the
	-- screen. The Frame Meter's origin is credited in the README and manual.

	-- -- The frame meter draws 90 frames to screen (log_drawn), but the log itself is 270 frames long (log_length = log_drawn * 3)
	-- -- The drawing is then divided into 3 blocks of 90 frames. The current block is drawn first, fully colored,
	-- -- The previous block is drawn afterwards, ahead of the current position but with a different set of darker images.

	-- This draws the current block of 90 frames.
	local block_start = math.floor(log_position / log_drawn) * log_drawn

	-- Draw meter for each chara
	for player = 1, 2 do 
		local xx = drawX

		local max_squares = log_drawn - 1 -- boundary will start at 90-1
		if max_squares > meter_anchor.bound then max_squares = meter_anchor.bound end -- it will be limited by "bound"
		if meter_anchor.bound < log_drawn+6 then meter_anchor.bound = meter_anchor.bound + 1 end -- "bound" will surpass 90, but the boundary won't

		for offset = 0, max_squares do
			local i = (block_start + offset) % log_length
			xx = offset%log_drawn * 4

			local log_ind = i+meter_anchor.scroll

			local relY = 0
			relY = (-6) + clamp((meter_anchor.bound) - (offset), 0, 6)
			if player == 2 then relY = relY * -1 end

			local image = states[1][1]
			local st = state_log[player][log_ind]
			local state_entry = states[st]

			if state_entry and state_entry[1] ~= nil then
				image = state_entry[1]
			end

			-- Draws the player inputs
			if (globals.options.fm_input_p1) then 
				local idy = measure_anchor.buttons_y + (measure_anchor.y - measure_anchor.offset)
				
				if player == 1 then 
					local input_entry = state_log[5][log_ind]
					if input_entry then
						local directional = input_entry.directional
						local dir_image = input_images[1][directional]

						gui.image(drawX + xx, drawY+idy+relY, img_bt)
						for bt = 1, 6 do
							if input_entry.buttons[bt] then gui.image(drawX + xx, drawY+2+relY, input_images[2][bt]) end
						end

						gui.image(drawX + xx, drawY+idy+relY, dir_image)

					end
				end
			end

			-- Draws the frame's rectangle
			gui.image(drawX + xx, drawY + (10*player) + relY, image)
			-- VSAV_Training: lower half, top two rows, then the 120Hz dots on row 3.
			mark_lower(player, log_ind, drawX + xx, drawY + (10*player) + relY, 1)
			mark_top(player, log_ind, drawX + xx, drawY + (10*player) + relY, 1)
			mark_120hz(player, log_ind, drawX + xx, drawY + (10*player) + relY, offset == 0)

			-- Draws the frame's overlay
			-- VSAV_Training: the AG window (1) only with Show P1 Inputs, as the
			-- hitstop it mostly falls in is shown only then; the success (2) always.
			local overlay = nil
			local timer_entry = state_log[player+2][log_ind]
			if (timer_entry ~= nil and timer_entry > 0)
			   and (timer_entry == 2 or globals.options.fm_input_p1) then
				if timers[timer_entry] ~= nil then
					overlay = timers[timer_entry]
					gui.image(drawX + xx, drawY + (10*player) + relY, overlay)
				end
			end
        end

		-- Drawing frame breakdown to screen (in front of the tiles)
		for offset = 0, max_squares do
			local i = (block_start + offset) % log_length
			xx = i%log_drawn * 4

			local log_ind = i+meter_anchor.scroll

			local breakdown = breakdown_log[player][log_ind]

			local relY = 0
			relY = (-6) + clamp((meter_anchor.bound) - (offset), 0, 6)
			if player == 2 then
				relY = relY * -1
				--print("p2")
			end

			if (breakdown ~= nil and breakdown >= 5) then -- VSAV_Training: 5, was 6
				local bdXoffset = -1
				if breakdown > 9 then bdXoffset = -5 end
				if breakdown > 99 then bdXoffset = -9 end
				gui.text(drawX + xx + bdXoffset, drawY + 2 + (10*player) + relY, tostring(breakdown))
			end
		end

    end

	-- This draws the previous block, "behind" the frames that are currently being logged. 

	if meter_anchor.scroll == 0 then
		local block = math.floor(log_position / log_drawn)
		block = (block - 1) % (log_length/log_drawn)
		local block_start = block * log_drawn

		for player = 1, 2 do -- Draw meter for each chara
			local xx = drawX
			local run_start = ((log_position%log_drawn)-meter_anchor.scroll)+2 -- VSAV_Training
			for offset = run_start, log_drawn - 1 do
				local i = (block_start + offset) % log_length
				xx = (i%log_drawn) * 4

				local log_ind = i+meter_anchor.scroll

				local image = states[1][2]
				local st = state_log[player][log_ind]
				local state_entry = states[st]
				if state_entry and state_entry[2] ~= nil then
					image = state_entry[2]
					gui.image(drawX + xx, drawY + (10*player), image)
					mark_lower(player, log_ind, drawX + xx, drawY + (10*player), 2) -- VSAV_Training
					mark_top(player, log_ind, drawX + xx, drawY + (10*player), 2) -- VSAV_Training
					mark_120hz(player, log_ind, drawX + xx, drawY + (10*player), offset == run_start) -- VSAV_Training
				end
			end
		end
	end
	
	-- String handling for the frame display.

	local startup1, total1, recovery1, zero1 = measure_player(1)
	local startup2, total2, recovery2, zero2 = measure_player(2)
	local advantage1, advantage2 = "--", "--"
	local plus = 0 -- 0 = neutral, 1 = player 1 has advantage, 2 = player 2 has advantage

	if zero1 ~= nil and zero2 ~= nil then
		advantage1 = tostring(zero2 - zero1)
		advantage2 = tostring(zero1 - zero2)
		if (zero2 - zero1 > 0) then plus = 1 end
		if (zero2 - zero1 < 0) then plus = 2 end
	end

	local measure1 = string.format("Startup %s / Total %s / Recovery %s / Advantage ", startup1, total1, recovery1)
	local measure2 = string.format("Startup %s / Total %s / Recovery %s / Advantage ", startup2, total2, recovery2)

	local adv1 = string.format("%s", advantage1)
	local adv2 = string.format("%s", advantage2)

	-- Draw frame advantage, colored 
	local adv_neutral = "#FFFFFF"
	local adv_positive = "#00BEFF"
	local adv_negative = "#F64100"

	-- Sets color for each player's frame advantage.
	c1, c2 = adv_neutral, adv_neutral
	if (plus == 1) then
		c1 = adv_positive
		c2 = adv_negative
	elseif (plus == 2) then
		c1 = adv_negative
		c2 = adv_positive
	end

	-- Draw measurement string
	local p1_y_offset = measure_anchor.y

	gui.text(drawX + (1), drawY+p1_y_offset, measure1, "#FFFFFF")
	gui.text(drawX + (1), drawY+29, measure2, "#FFFFFF")
	-- Draw frame advantage string
	gui.text(drawX + (1) + string.len(measure1)*4, drawY+p1_y_offset, adv1, c1)
	gui.text(drawX + (1) + string.len(measure2)*4, drawY+29, adv2, c2)

	-- Draw player 1/player 2 labels
	gui.text(drawX + (4*82), drawY+p1_y_offset, "Player 1", "#FFFFFF")
	gui.text(drawX + (4*82), drawY+29, "Player 2", "#FFFFFF")
end

-- Listens for downback / downforward > 30 frames to scroll meter. Works only when meter is frozen after idle_frames > max_idle_frames. 
local function handle_scrolling()
	local input = get_player_inputs()
	if input.directional == 3 then
		meter_anchor.scroll_hold = meter_anchor.scroll_hold + 1	
	elseif input.directional == 1 then
		meter_anchor.scroll_hold = meter_anchor.scroll_hold - 1	
	else
		meter_anchor.scroll_hold = 0
	end

	meter_anchor.scroll_hold = clamp(meter_anchor.scroll_hold, -30, 30)
	if meter_anchor.scroll_hold > 29 then meter_anchor.scroll = meter_anchor.scroll + 1 end
	if meter_anchor.scroll_hold <= -29 then meter_anchor.scroll = meter_anchor.scroll - 1 end
end

-- VSAV_Training: A LOADED STATE IS NOT THE TICK AFTER THE LAST ONE (2026-10-08).
-- The meter went on from the ticks before the load and compared the first
-- tick after it with the last one before: an animation that "advanced", a
-- reversal marker that "went", a thrown flag that "changed" - none of them in
-- the game - and a run that joined the two sides of the load. Whatever is
-- carried from one tick to the next is dropped here, so the first tick after a
-- load is only read, and the meter counts as stopped: the log on screen stays
-- to be read and scrolled, and the next action starts a new one, as after five
-- idle ticks (refresh_meter).
local function reset_after_load()
	free_before = {}
	free_now = {}
	idle_frames = max_idle_frames
	test_state = "idle"
	freezeNextFrame = false
	last_anim = { nil, nil }
	still_now = { false, false }
	pb_success_pending = { false, false }
	last_throw_checks = { nil, nil }
	was_thrown = { nil, nil }
	throw_now = { false, false }
	signature_seen = { false, false }
	reversal_now = { false, false }
end

-- Update function called by the subscription made when the module first registers. Calls every method above this to produce the meter. 
-- VSAV_Training: hitstop ticks are skipped by what stood still, not by $5C
-- alone (2026-10-05): a tick is skipped only while someone is in hitstop AND
-- no attacking character moved. See read_motion for what "moved" is.
local function update(tick)
	-- VSAV_Training: every tick, logged or not (see read_motion).
	read_free_ticks()
	local moved = read_motion()
	read_reversal_ticks()
	read_pb_success()
	read_throw_checks()
	local frozen = (game.hitfreeze(game.address[1]) or game.hitfreeze(game.address[2]))
	               and not globals.options.fm_input_p1
	-- Don't draw any new frames to the meter if the game is frozen for dramatic effect.
	freezeNextFrame = frozen and not moved -- VSAV_Training: now "skip this tick"
	if not freezeNextFrame then
		refresh_meter()
		-- VSAV_Training: match_running, not match_begun - the latter drops to
		-- false during a transformation (Demitri's bat spin and the like).
		local logged = false
		if globals.match_running == nil or globals.match_running() then
			if (idle_frames < max_idle_frames) then
				log_player_inputs()
				log_player_state(tick)
				logged = true
			else
				handle_scrolling()
			end
		end
		-- VSAV_Training: a success is carried over skipped hitstop only.
		if not logged then pb_success_pending = { false, false } end
	end

end

local frameMeterModule = {
    ["registerStart"] = function()
		game = nil
		-- subscription generation borrowed from framedata.lua
		subscription_generation = subscription_generation + 1
		local mine = subscription_generation
		globals.truth.ticker:subscribe(function(tick)
			if mine == subscription_generation then
				if game ~= nil then update(tick, rawState) end
			end
		end)

		for n, module in ipairs(profile) do
			for m, shortname in ipairs(module.games) do
				if emu.romname() == shortname or emu.parentname() == shortname then
					game = module
					if fba and (emu.sourcename() == "CPS1" or emu.sourcename() == "CPS2") then
						print("Warning: FBA gives inaccurate results for CPS1/CPS2.")
					end
					-- VSAV_Training: no such toggle here; Lua Hotkey 2 is the
					-- trainer's own. The hint only misled.
					if game.no_frameskip then
						print("* disabling frameskip")
					end
					if game.address.projectile_slowdown then
						print("* disabling projectile slowdown")
					end
					return
				end
			end
		end

		print("not prepared for " .. emu.romname() .. " frame data")
	end,
    -- VSAV_Training: called from the master script's savestate.registerload.
    ["registerLoad"] = function() reset_after_load() end,
    -- VSAV_Training: for analysis/test_framemeter.lua.
    ["second_of_pair"] = second_of_pair,
    ["guiRegister"] = function()
		if (globals.options.display_frame_meter) then
			draw_meter()
		end
    end
}

return frameMeterModule