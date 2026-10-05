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
-- breakdown_log[] shows number of grouped frames counted @ specific positions 
-- [1] = Player 1
-- [2] = Player 2
-- [3] = Open/Close for editing

local state_log = {}
local breakdown_log = {{},{},true}

local function reset_state_log()
	state_log = {{},{},{},{},{},{},{}} -- VSAV_Training: [7]
	breakdown_log = {{},{},true}
end
reset_state_log()

-- Stores display and positioning data for the meter 
local meter_anchor = {
	scroll = 0,
	scroll_hold = 0,
	bound = -90,
	widget_x_offset = 0,
	shake = 0,
	bomb = 0,
	exploded = false,
	extra_wide_txt = 0
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

-- -- Funny
local xsin = 0
local colours = {
	"#003FFF", "#1F4FFF", "#3A2CFF", "#5900FF", "#7300FF", "#A100FF",
	"#C700FF", "#FF00C8", "#FF007F", "#FF004D", "#FF0000", "#FF4D00",
	"#FF8A00", "#FFBB00", "#FFD000", "#D9FF00", "#9DFF00", "#5DFF00",
	"#00FF6A", "#00FF9A", "#00FFAA", "#00D9FF", "#00A9FF", "#006EFF"
}
local particles = {}
local particle_count = 0
local prevHitStop = false

-- Borrowed from other files.
local super_mode = false
local game

-- Addresses for the game's various flags
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

		hitfreeze = function(addr) return memory.readbyte(addr + 0x05C) ~= 0x00 end,
		knockdown = function(addr) return memory.readbyte(addr + 0x1A7) ~= 0 end,
		invulnerable = function(addr) return memory.readbyte(addr + 0x147) ~= 0 end,
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

-- --	Don't worry about it, just keep scrolling.
local function make_particle(x, y, img)
	local new_particle = {
		posX = x,
		posY = y,
		speedY = math.random(-10, -5),
		speedX = math.random(-2, 2),
		image = img
	}
	particle_count = particle_count + 1
	particles[particle_count] = new_particle
	return new_particle
end

local function run_particles()
	for _, part in ipairs(particles) do
		gui.image(part.posX, part.posY, part.image)
		part.posX = part.posX + part.speedX
		part.posY = part.posY + part.speedY

		part.speedY = part.speedY + 0.08
		part.speedX = part.speedX * 0.995
		if (part.posY > 224 and part.speedY > 0) then
			part.posY = 224
			part.speedY = part.speedY * -.8
		end
		if (part.posX < 0 or part.posX > emu.screenwidth()-4) then
			part.posX = clamp(part.posX, 0, emu.screenwidth()-4)
			part.speedX = part.speedX * -.9
		end
	end
end

local function clear_particles()
	particles = {}
	particle_count = 0
end

local function explode_meter()
	globals.show_menu = false
	globals.controllerModule.enable_both_players()
	meter_anchor.exploded = true
	meter_anchor.extra_wide_txt = 20
	xsin = 0
	local block_start = math.floor(log_position / log_drawn) * log_drawn
	for player = 1, 2 do 
		local xx = drawX
		local max_squares = log_drawn - 1 -- boundary will start at 90-1
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
			-- Draws the frame's rectangle
			make_particle(drawX + xx, drawY + (10*player) + relY, image)
        end
    end
end

local function fightcade_txt()
	local ttt = "ur entire identity is built upon a character from a 1995 game"
	meter_anchor.extra_wide_txt = meter_anchor.extra_wide_txt * .9
	for i = 1, #ttt do
		local c = ttt:sub(i,i)

		cc = clamp(math.floor(i+(xsin/4))%#colours, 1, #colours-1)

		local letterx = 64+(4*i)
		local right = ((4*#ttt))
		local left = 64
		local center = ((right/2)+left)
		
		local widen = (letterx - center) * (math.sin(xsin*.02)+.5) * (.3 + meter_anchor.extra_wide_txt)

		gui.text(letterx+widen, 170 + math.sin((xsin*.07)+i) * 2, c, colours[cc])
		-- do something with c
	end
	local sine_period = (math.pi * 2) / 0.02
	xsin = (xsin + 1) % sine_period
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
		player[p].nothrow     = game.nothrow(addr)
		
		player[p].jump		  = game.jump(addr)
		player[p].dash	      = game.dash(addr)
		player[p].movement 	  = player[p].jump or player[p].dash
		player[p].stunned	  = game.stunned(addr)
		player[p].status_1	  = game.status_1(addr)
		player[p].status_2	  = game.status_2(addr)
		player[p].walking 	  = game.walking(addr)
		player[p].dfreturn 	  = game.dfreturn(addr)

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
local function log_player_state(tick)
    local player = get_player_objects()
	for p = 1, 2 do
		-- set current frame's state for each player @ log_position
		local previousState = state_log[p][log_position-1%log_length]

		local priolist = {
			{player[p].invulnerable, 8},
			{player[p].nothrow and globals.options.fm_no_throw, 7},
			{player[p].attack_box, 3},
			{player[p].hurt or player[p].knockbox, 5},
			{player[p].dfreturn, 4},
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

		local op = 2
		if p == 2 then op = 1 end
		if player[op].pbsuccess > 0 and player[op].pbsuccess <= 3 then state_log[p+2][log_position] = 2 end
	end
	-- VSAV_Training: the displayed frame this tick ran in (see second_of_pair).
	state_log[7][log_position] = emu.framecount()
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

	for i = log_position, 0, -1 do
		local s = state(i)
		if (idle_frames > max_idle_frames and breakdown_is_open()) then
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
	if recovery > 0 then recovery = recovery + 1 end
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
			or globals.options.fm_movement_data and (game.dash(addr) or game.jump(addr))
			or game.dfreturn(addr)
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

		meter_anchor.exploded = false
		clear_particles()
		reset_state_log()
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
    drawX = 8 + meter_anchor.widget_x_offset + meter_anchor.shake
    drawY = _height - 64

	local measure1_target = measure_anchor.normal
	if (globals.options.fm_input_p1) then measure1_target = measure_anchor.offset end

	local lerp = (measure_anchor.y - measure1_target) * .3
	measure_anchor.y = measure_anchor.y - lerp
	if (math.abs(lerp) < .1) then measure_anchor.y = measure1_target end

	if math.abs(meter_anchor.shake) > .2 then
		meter_anchor.shake = meter_anchor.shake * -.5
		meter_anchor.bomb = meter_anchor.bomb + 1
		if (meter_anchor.bomb == 60) then explode_meter() end
	else
		meter_anchor.shake = 0
		meter_anchor.bomb = 0
	end

	gui.text(-512-meter_anchor.scroll, 48, "VSAV_FrameMeter by @tirsod.com\nSpecial thanks to Nbee, MBD, KyleW, vampiresavior001\nrar, hagure, zako, dom & enker\nfor all the hard work that made this\nlittle fun project possible!\n\nGo lab those purrsuits! :3 -6410\n(I really had to learn Lua for this, huh?)\nShoutouts to the vsav discord!")

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
			mark_120hz(player, log_ind, drawX + xx, drawY + (10*player) + relY, offset == 0) -- VSAV_Training

			-- Draws the frame's overlay
			local overlay = nil
			local timer_entry = state_log[player+2][log_ind]
			if (timer_entry ~= nil and timer_entry > 0) then
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

			if (breakdown ~= nil and breakdown > 5) then
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

-- Update function called by the subscription made when the module first registers. Calls every method above this to produce the meter. 
-- VSAV_Training: HITSTOP IS SKIPPED BY WHAT STOOD STILL, NOT BY $5C (trial,
-- 2026-10-05). $5C only says a player is in hitstop. Demitri's crouching HK
-- keeps animating through it - its 4 active ticks all run while $5C is set -
-- and an ordinary move stands still (the close LP's box is out 14 ticks, 11 of
-- them frozen). Skipping on $5C read the blocked HK as 1 red tile against 4 on
-- a whiff, and the old one-tick-late flag also dropped the first tick after
-- every hitstop (blocked LP: 2 red against 3). Tick Data counts the same
-- moves right because it asks whether the animation advanced: $20 (the cel's
-- remaining ticks) and $1C (the cel) change on exactly those ticks.
-- A tick is skipped now only while someone is in hitstop AND no attacking
-- player's animation advanced. The defender is left out: entering guard
-- swaps its cel without anything having played.
local last_anim = { nil, nil }
local function anim_advanced()
	local moved = false
	for p = 1, 2 do
		local addr = game.address[p]
		local a = memory.readbyte(addr + 0x20) * 0x10000 + ((memory.readdword(addr + 0x1C) or 0) % 0x10000)
		if last_anim[p] ~= nil and a ~= last_anim[p] and get_attack_state[super_mode](addr) then
			moved = true
		end
		last_anim[p] = a
	end
	return moved
end

local function update(tick)
	-- VSAV_Training: see anim_advanced above.
	local moved = anim_advanced()
	local frozen = (game.hitfreeze(game.address[1]) or game.hitfreeze(game.address[2]))
	               and not globals.options.fm_hitstop
	-- Don't draw any new frames to the meter if the game is frozen for dramatic effect.
	freezeNextFrame = frozen and not moved -- VSAV_Training: now "skip this tick"
	if not freezeNextFrame then
		refresh_meter()
		-- VSAV_Training: match_running, not match_begun - the latter drops to
		-- false during a transformation (Demitri's bat spin and the like).
		if globals.match_running == nil or globals.match_running() then
			if (idle_frames < max_idle_frames) then
				log_player_inputs()
				log_player_state(tick)
			else
				handle_scrolling()
			end
		end
	end

	if prevHitStop ~= globals.options.fm_hitstop then
		local shkvalue = 5 + meter_anchor.bomb
		if not prevHitStop then shkvalue = -5 end

		meter_anchor.shake = shkvalue
		prevHitStop = globals.options.fm_hitstop
	end
	run_particles()
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
    -- VSAV_Training: for analysis/test_framemeter.lua.
    ["second_of_pair"] = second_of_pair,
    ["guiRegister"] = function()
		if (globals.options.display_frame_meter) then
			if (not meter_anchor.exploded) then
        		draw_meter()
			else
				run_particles()
				fightcade_txt()
			end
		end
    end
}

return frameMeterModule