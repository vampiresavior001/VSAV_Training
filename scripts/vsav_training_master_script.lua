for _,var in ipairs({playbackfile, use_last_recording,
					path,playkey,recordkey,togglepausekey,toggleloopkey,longwait,longpress,longline,framemame, show_position,
					 display_recording_gui,
					 use_hb_config, hb_config_blank_screen, hb_config_draw_axis, hb_config_draw_pushboxes, hb_config_draw_throwable_boxes, hb_config_no_alpha,
					 mo_enable_frame_data, debug, quiet_framedata, show_controls_message}) do
	var = nil
end

function script_path()
	local str = debug.getinfo(2, "S").source:sub(2)
	return str:match("(.*[/\\])")
end
function deepcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deepcopy(orig_key)] = deepcopy(orig_value)
        end
        setmetatable(copy, deepcopy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end
copytable = deepcopy
dofile("macro-options.lua", "r") --load the globals
dofile("macro-modules.lua", "r")

serialize                = require './scripts/ser'
local configModule       = require './scripts/config'
training_settings_file   = "training_settings.json"
training_settings        = configModule.default_training_settings
Rx                       = require "./scripts/rx-lua/rx"
local inpHistoryModule   = require"./scripts/inputHistory"
-- local inpDispModule      = require "./input-display"
local frameDataModule    = require "./scripts/framedata"
local rollingModule      = require "./scripts/rolling" 

local vsavScriptModule   = require "./scripts/vsavscriptv2"
local macroLuaModule     = require "./scripts/macro"
local recordingWizardModule = require "./scripts/recordingWizard"
local actionSequenceEditorModule = require "./scripts/actionSequenceEditor"
local actionSequenceRunnerModule = require "./scripts/actionSequenceRunner"
local guardCancelModule  = require "./scripts/guardCancel"
local debugKnockdownModule = require "./scripts/debugKnockdown"
local autoguardModule    = require "./scripts/autoguard"
local gameStateModule    = require './scripts/gameState'
local dummyStateModule   = require './scripts/dummyState'
local neutralModule      = require './scripts/dummyNeutral' 
local util               = require './scripts/utilities'
local playerObject       = require './scripts/playerObject'
local menuModule         = require './scripts/menu'
local controllerModule   = require './scripts/controller'
local cps2HitboxModule   = require "./scripts/cps2-hitboxes"
local healthAndMeter     = require "./scripts/healthAndMeter"
local hudModule          = require "./scripts/hud"
local timersModule       = require "./scripts/timers"
local positionModule     = require "./scripts/position"
local throwTechModule    = require "./scripts/throwTech"
local stageSelectModule  = require "./scripts/stage-select"
local stageDataModule    = require "./scripts/stage-data"
local vsavTestMenuModule = require "./scripts/vsav-test-menu"
local soundModule        = require "./scripts/sound"

-- this module provides clocks and game data from memory
-- data and clock signals are provided every tick
local rawStateServiceModule = require "./scripts/rawStateService"
-- this module has business logic for processing raw state data
-- + converting it into global tables for use by GUI components
local playerStateServiceModule = require "./scripts/playerStateService"

if show_controls_message == true then
	print("* Press Start open the training menu..")
	print("* Press Coin to swap controls to dummy")
	print("* Press Volume Down to play back recording. (found in 'map game inputs')")
	print("* Press Volume Up to record dummy. (found in 'map game inputs')")
	print("* Press Alt + 3 to toggle looping playback.")
	print("* Press Alt + 4 to return to character select.")
end

local p1_addr = 0xFF8400
local p2_addr = 0xFF8800
last_dummy_config = {  }
last_dummy_dict = {}
local graph_data = nil
function update_graph_data()
	local keyset={}
	local n=0
	for k,v in pairs(last_dummy_config) do
		n=n+1
		if tonumber(k) ~= nil then
			keyset[tonumber(k)]=v
		end
	end

	local sorted = {}
	for k, v in pairs(keyset) do
		table.insert(sorted,{frame = k, state = v})
	end

	table.sort(sorted, function(a,b) 
		return a["frame"] < b["frame"] 
	end)
	local min_items = 7
	local chopped = {}
	local chop_index = - min_items
	for key, val in pairs(sorted) do
		if 
			(chop_index > globals.graph_data_index and chop_index < globals.graph_data_index + 7) 
		then 
			table.insert(chopped,{frame = val.frame, state = val.state})
		end

		chop_index = chop_index + 1

	  end
	  
	graph_data = chopped
end

-- SEED THE GENERATOR, OR EVERY SESSION IS THE SAME SESSION.
--
-- Lua 5.1's math.random is the C library's rand(), and without a
-- math.randomseed the C library starts from seed 1 - so the sequence is
-- byte-identical on every launch. Measured: two runs of the same script both
-- produced 0 2 0 4 2 2 1 4.
--
-- Nothing in this tool seeded it. Guard Action Frequency, P2 Block Chance and
-- Use Random Recording Slot all draw from that one generator, so the dummy
-- repeated the same pattern every time FBNeo started. The distribution was
-- right; the sequence was learnable, which for a training dummy is the same
-- complaint.
--
-- os.time() moves once a second and its low bits barely move the first draw,
-- so os.clock() is folded in and the first values are thrown away - the usual
-- Lua 5.1 precaution. Wrapped in pcall because os is the one library a host
-- may withhold, and an unseeded generator is better than no script.
local function seed_rng()
	local _ok, _t = pcall(os.time)
	if not _ok or type(_t) ~= "number" then _t = 0 end
	local _ok2, _c = pcall(os.clock)
	if not _ok2 or type(_c) ~= "number" then _c = 0 end
	math.randomseed(math.floor(_t % 1000000) * 1000
	                + math.floor((_c * 1000000) % 1000))
	for _ = 1, 5 do math.random() end
end
seed_rng()

local init_clock = 0
local fc = 0
local prev_frames = {}

globals = {
	game_state      = nil,
	dummy_state     = nil,
	config_state    = nil,
	show_menu       = false,
	controlling_p1  = true,
	quiet_framedata = quiet_framedata,
	show_position = show_position,
	show_meter = show_meter,
	show_life = show_life,
	timers = {},
	dmg_calc = {
		p2_red_life = training_settings.p2_max_life,
		p2_white_life = training_settings.p2_max_life,
		p1_red_life = training_settings.p1_max_life,
		p1_white_life = training_settings.p1_max_life,
	},
	skip_frame = false,
	save_state = nil,
	debounceStarted = nil,
	macroLua = nil,
	last_fd = "",
	-- The Action Route row, kept apart from last_fd so the HUD can draw it in
	-- its own colour: the two readouts do not mean the same thing.
	last_route = "",
	airdash_heights = {},
	time_between_dashes = {},
	dash_length_frames = {},
	short_hop_counter = {},
	total_pb_attempt_counter = {},
	successful_pb_counter = {},
	time_between_dash_start_attack_start = {},
	time_between_attack_end_dash_start = {},
	frames_between_attacks = {},
	jump_in_frames = {},
	last_dash_ended = nil,
	last_dash_started = nil,
	last_attack_started = nil,
	last_attack_ended = nil,
	p2_hit_or_block_begin = nil,
	p2_hit_or_block_end = nil,
	jump_in_attack_start = nil,
	jump_in_attack_end = nil,
	set_last_data = function (fd) 
		globals.last_fd = fd
	end,
	set_last_route = function (route)
		globals.last_route = route
	end,
	pushboxes = {},
	gc_event = "p1_gc_none",
	pb_event = "p1_pb_none",
	controllerModule = nil,
	dummyStateModule = nil,
	util = nil,
	menuModule = nil,
	frameskipReady = false,
	graph_data_index = 0,
	graph_data_max = 8,
	show_graph_menu = false,
	update_graph_data = update_graph_data,
	input_history = {P1 ={}, P2 = {}},
	_input = {},
	parsed_dummy_state = {},
	graph_data_max = 100,
	playing = false,
	recording = false,
	desired_stage = nil,
	frameskipService = require "./scripts/frameskip-service",
	history_service_p1 = inpHistoryModule.get_history_p1(),
	history_service_p2 = inpHistoryModule.get_history_p2(),
    -- dummy_state_service can be read/subbed by anyone
	dummy_state_service = dummyStateModule.dummy_state_service(),
    -- this should only get called in 1 script for consistent timing
	dummy_state_service_updater = dummyStateModule.dummy_state_service_updater,
    truth = rawStateServiceModule,
    player_state_service = playerStateServiceModule,
	p1_last_pursuit_length = nil,
	p2_last_pursuit_length = nil
}

local gather_graph_data = false
local was_gathering_graph_data = false

input.registerhotkey(5, function()
	-- The wizard owns the screen and the run of play while it is up, and every
	-- other hotkey here reaches past it: the loop toggle changes what a
	-- playback does mid-playback, and character select tears the match out from
	-- under a recording. Key 1 is left alone deliberately - it cancels the
	-- wizard, which is the one thing worth being able to do.
	if globals.recordingWizard ~= nil and globals.recordingWizard.is_active ~= nil
	   and globals.recordingWizard.is_active() then return end
	if actionSequenceEditorModule.is_active() then return end

	-- print("=======p1======")
	-- globals.util.printRamAddresses(0xFF8400, 0xFF8400 + 0x400)
	print("=======RESETTING======")
	-- globals.util.printRamAddresses(0xFF8800, 0xFF8800 + 0x400)
end)

-- ENDING THE MATCH, FROM EITHER OF THE TWO PLACES THAT ASK FOR IT.
--
-- Lua hotkey 4 was the only way in, which meant it only existed for people who
-- had found that line in the startup text. The Game tab has a row for it now
-- and both go through here, so the guards and the tear-down cannot drift apart.
local function return_to_character_select()
	-- The wizard owns the screen and the run of play while it is up, and every
	-- other hotkey here reaches past it: the loop toggle changes what a
	-- playback does mid-playback, and character select tears the match out from
	-- under a recording. Key 1 is left alone deliberately - it cancels the
	-- wizard, which is the one thing worth being able to do.
	if globals.recordingWizard ~= nil and globals.recordingWizard.is_active ~= nil
	   and globals.recordingWizard.is_active() then return end
	if actionSequenceEditorModule.is_active() then return end
	-- Return to char select
	-- CLOSING THE MENU BY HAND SKIPS WHAT togglemenu() DOES ON THE WAY OUT.
	--
	-- Opening it disables both pads, and only togglemenu() puts them back. This
	-- has always set the flag directly, which left the pads disabled until the
	-- menu was opened and closed again - survivable when a hotkey was the only
	-- way in, since the menu was usually shut, but the Game tab now has a row
	-- for this and that row is only ever pressed with the menu OPEN.
	globals.show_menu = false
	if globals.controllerModule ~= nil and globals.controllerModule.enable_both_players ~= nil then
		globals.controllerModule.enable_both_players()
	end
	memory.writebyte(0xFF8005, 0x0C)
	globals.airdash_heights = {}
	globals.time_between_dashes = {}
	globals.dash_length_frames = {}
	globals.short_hop_counter = {}
	globals.time_between_dash_start_attack_start = {}
	globals.time_between_attack_end_dash_start = {}
	globals.frames_between_attacks = {}
	globals.jump_in_frames = {}
	globals.total_pb_attempt_counter = {}
	globals.successful_pb_counter = {}
	globals.last_fd = ""
	globals.last_route = ""
	-- Nothing else drops a playback on the way out, so it stayed "playing"
	-- across the return and into the next match - the Play Recording row kept
	-- reading (playing) and the loop kept trying to restart. The wizard has to
	-- come down too, or it would sit there owning the screen at character
	-- select with no match behind it.
	if globals.macroLua ~= nil then
		if globals.macroLua.stop_macro_playback ~= nil then globals.macroLua.stop_macro_playback() end
		if globals.macroLua.end_temporary_playback ~= nil then globals.macroLua.end_temporary_playback() end
		if globals.macroLua.cancel_temporary_recording ~= nil then globals.macroLua.cancel_temporary_recording() end
	end
	if globals.recordingWizard ~= nil and globals.recordingWizard.shutdown ~= nil then
		globals.recordingWizard.shutdown()
	end
	-- The recording savestate is a whole machine state tied to this match.
	-- Going back to select ends that match, so it stops being something worth
	-- loading - see the note in controller.lua.
	if globals.controllerModule ~= nil and globals.controllerModule.drop_recording_state ~= nil then
		globals.controllerModule.drop_recording_state()
	end
end
globals.return_to_css = return_to_character_select
input.registerhotkey(4, return_to_character_select)

input.registerhotkey(3, function()
	-- The wizard owns the screen and the run of play while it is up, and every
	-- other hotkey here reaches past it: the loop toggle changes what a
	-- playback does mid-playback, and character select tears the match out from
	-- under a recording. Key 1 is left alone deliberately - it cancels the
	-- wizard, which is the one thing worth being able to do.
	if globals.recordingWizard ~= nil and globals.recordingWizard.is_active ~= nil
	   and globals.recordingWizard.is_active() then return end
	if actionSequenceEditorModule.is_active() then return end
	globals.macroLua.toggleloop()
end)

-- Macro playback carries absolute stick directions, so a recording only
-- reproduces the move it captured while the dummy stands on the side it was
-- recorded from. macro.lua now writes that side into the .mis header, so the
-- playback is mirrored whenever the dummy is on the other one.
--
-- Files recorded before the header carried it report nothing, and fall back
-- to the standing convention: recordings are made with P2 on the right, which
-- is exactly when the facing byte at +0x0B reads 0 (guardCancel's
-- p2_facing_toward_p1 returns 1 when P2.x is left of P1.x, and autoguard reads
-- the same byte as "flipped").
local P2_FACING_ADDR = 0xFF880B

local function macro_playback_flipped()
	local _now = memory.readbyte(P2_FACING_ADDR)
	local _rec = globals.macroLua ~= nil and globals.macroLua.get_playback_facing ~= nil
	             and globals.macroLua.get_playback_facing() or nil
	if _rec ~= nil then return _now ~= _rec end
	return _now ~= 0
end

local function merge_macro_keys(_out, _keys, _flip)
	for k, v in pairs(_keys) do
		if _flip and k == "P2 Left" then
			_out["P2 Right"] = v
		elseif _flip and k == "P2 Right" then
			_out["P2 Left"] = v
		else
			_out[k] = v
		end
	end
end
input.registerhotkey(1, function()
	-- Ignored until the match is actually running (globals.hotkeys_armed).
	if globals.hotkeys_armed ~= true then return end
	-- While the wizard is up it owns the screen, so togglemenu() would only
	-- disable both players behind a menu that never draws - and with no arm
	-- timeout the wizard would sit there for good. Key 1 cancels it instead.
	-- The callback raises a flag and nothing more: doing real work in here
	-- once killed this hotkey outright.
	if globals.recordingWizard ~= nil and globals.recordingWizard.is_active()
	   and globals.recordingWizard.request_cancel ~= nil then
		globals.recordingWizard.request_cancel()
		return
	end
	globals.menuModule.togglemenu()
end)
toggleloop = nil
emu.registerstart(function()
 	globals.frameskipService.registerStart()
	rawStateServiceModule.registerStart()
    playerStateServiceModule.registerStart()
	util.load_training_data()
	-- globals.frameSkipHandlerModule = frameskipHandlerModule.registerStart()
	globals["options"] = configModule.registerBefore()
	globals.show_menu = false
	globals.controllerModule = controllerModule.registerStart()
	globals.util = util.registerStart()
	globals.inpHistoryModule = inpHistoryModule.registerStart() 
	globals.inpHistoryModule.reset_inp_history_scroll()
	globals.menuModule = menuModule.registerStart()
	globals.getCharacter = utilitiesModule.get_character
	globals.get_bishamon_ubk_ranges_by_char = charMovesModule.get_bishamon_ubk_ranges_by_char()

	player_objects = {
		playerObject.make_player_object(1, 0xFF8400, "P1"),
		playerObject.make_player_object(2, 0xFF8800, "P2")
	}
	P1 = player_objects[1]
	P2 = player_objects[2]
	stageSelectModule.registerStart()
	frameDataModule.registerStart()
	cps2HitboxModule.registerStart(globals)
	macroLuaModule.registerStart()
	debugKnockdownModule.registerStart()

end)

local last 
-- FIX: is a match really running, even though match_begun says otherwise?
--
-- gameState.lua derives match_begun from two per-character bytes
-- (0xFF8401 / 0xFF8801 both equal 1). Those also drop to 0 while a character
-- is transformed, so mid-match the tool behaved as if it were back on the
-- character select screen: the per-frame processing below bailed out, leaving
-- globals.dummy and globals.timers stale, and the gui hook drew the select
-- screen help text instead of the overlays. That is the flicker seen every
-- time Demitri does Bat Spin, and it would last the whole of Midnight Bliss.
--
-- Overriding match_begun itself is not an option - it is read from five other
-- places. So this is a separate, deliberately conservative test used only to
-- decide whether to keep going. All three must hold:
--
--   * globals.dummy exists - proof a full frame of processing has already
--     completed once, so the modules below are initialised. Without this the
--     overlay code runs before it is ready and crashes in timers.lua.
--   * at least one character is active - both bytes read 0 on the select
--     screen, whereas a transformation only ever clears one of them.
--   * 0xFF8009 says in-match (2 = select screen, 4 = match).
--
-- 0xFF8009 alone is NOT sufficient: it was seen reading 4 on the select
-- screen after returning from a match, which is what broke an earlier attempt
-- at this fix. If any condition is unclear the original behaviour is kept, so
-- the worst case is the flicker returning - never a crash.
local function match_actually_running()
	return globals.dummy ~= nil
		and (memory.readbyte(0xFF8401) == 1 or memory.readbyte(0xFF8801) == 1)
		and memory.readbyte(0xFF8009) == 4
end

emu.registerbefore(function()

	-- print("currently selected", memory.readbyte(0xFF8400 + 0x382))
	-- print("unknown mirror",memory.readbyte(0xFF6198))
	-- print("have selected character", memory.readbyte(0xFF8400 + 0x3BD))
	-- memory.writebyte(0xFF8400 + 0x3BD, 0x02)

	-- print("P1 guard", memory.readbyte(0xFF8400 + 0x1AB))
	-- if memory.readbyte(0xFF8400 + 0x1AB) > 0 then
	-- 	print("P1 blockin")
	-- 	memory.writebyte(0xFF8400 + 0x170, 0x06)
	-- end
	-- fc = fc + 1
    -- if fc % 60 == 0 then 
    --     local cur_clock = os.clock()
    --     print("ending at", cur_clock)
    --     print("It takes this amount of time to run 60 frame", cur_clock - init_clock )
    --     table.insert(prev_frames, 1, {cur_clock - init_clock})
    --     fc = 0
    --     init_clock = cur_clock
    -- end
    -- if tablelength(prev_frames) == 6 then
    --     print(serialize(prev_frames))
	-- end
	gameStateModule.registerBefore()

	-- THE CHARACTER SELECT STOPS THE LOOP (user, 2026-09-21).
	--
	-- The Action Pattern loop refills itself whenever its queue is empty, and
	-- nothing in the runner knows what scene the game is in. Back on this
	-- screen the runner's service gate is not enough: service runs from the
	-- 0x02211A hook, which has no reason to still be executing here, and
	-- globals.dummy is never rebuilt on this screen (the early return below
	-- skips the refresh), so a stale object kept answering. The lap survived
	-- and the next one was delivered here, moving the P2 cursor by itself.
	--
	-- Scene 2 is this screen and nothing else. No pattern should ever run
	-- here, so the whole pass goes - the same cancel the savestate load does,
	-- plus the delivery slot, whose runner-side half cancel cannot reach.
	-- Every frame while the scene says so: the runner's refill may run later
	-- in the same frame, and this has to win.
	if memory.readbyte(0xFF8009) == 2 then
		actionSequenceRunnerModule.cancel()
		if player_objects ~= nil and player_objects[2] ~= nil then
			player_objects[2].pending_input_sequence = nil
		end
	end

	-- Lua keys 1 and 2 are held off until the match is genuinely running -
	-- the same gate the overlay uses, meaning the characters are on screen
	-- and the modules behind those keys are initialised. Pressing them during
	-- the intro armed the menu or a measurement against a half-built state.
	-- The hotkey callbacks only read this flag; they must stay trivial.
	-- Also waits for the round itself. match_actually_running() is already true
	-- during the entrance, and neither the menu nor the position shortcut does
	-- anything good there - an arrangement would be computed from a round start
	-- that has not been read back yet, and a menu opened over the intro leaves
	-- the two disabled in the middle of it. position.lua owns that detection,
	-- so the gate is asked of it rather than duplicated here.
	-- Published so other modules can ask the same question. framedata used
	-- match_begun and stopped measuring for the whole of a transformation -
	-- Demitri's Bat Spin produced no reading at all, which is the exact flicker
	-- the note above this function describes. One definition, not two.
	globals.match_running = match_actually_running
	globals.hotkeys_armed = match_actually_running()
		and (positionModule.round_ready == nil or positionModule.round_ready())

	if globals.game_state.match_begun == false and not match_actually_running() then
		-- Arcade stick only: mirror P1 inputs to P2 during character select
		-- after P1 has locked in, so P2 can be chosen with the same stick.
		-- Stage select via P1 Coin (stage-select.lua) is preserved, Coin itself is not mirrored.
		-- Wait a bit after P1 locks in so Stage can be chosen with Coin before mirroring starts.
		if memory.readbyte(0xFF8009) == 2 then
			-- NOT $3BD ON ITS OWN. It is the character id, and Bulleta is
			-- zero, so she read as "has not chosen" and the mirror never
			-- started for her. See util.char_chosen.
			local p1_sel = util.char_chosen(0xFF8400)
			local p2_sel = util.char_chosen(0xFF8800)
			if p1_sel and not p2_sel then
				globals._p1_mirror_wait = globals._p1_mirror_wait or 0
				if globals._p1_mirror_wait == 0 then
					globals._p1_mirror_wait = emu.framecount() + 30
				end
				if emu.framecount() >= globals._p1_mirror_wait then
					local _inp = joypad.get()
					-- Directions: OR of P1 and original P2 so both controllers work
					_inp["P2 Up"] = _inp["P1 Up"] or _inp["P2 Up"]
					_inp["P2 Down"] = _inp["P1 Down"] or _inp["P2 Down"]
					_inp["P2 Left"] = _inp["P1 Left"] or _inp["P2 Left"]
					_inp["P2 Right"] = _inp["P1 Right"] or _inp["P2 Right"]
					-- Buttons (6-button layout): OR
					_inp["P2 Weak Punch"] = _inp["P1 Weak Punch"] or _inp["P2 Weak Punch"]
					_inp["P2 Medium Punch"] = _inp["P1 Medium Punch"] or _inp["P2 Medium Punch"]
					_inp["P2 Strong Punch"] = _inp["P1 Strong Punch"] or _inp["P2 Strong Punch"]
					_inp["P2 Weak Kick"] = _inp["P1 Weak Kick"] or _inp["P2 Weak Kick"]
					_inp["P2 Medium Kick"] = _inp["P1 Medium Kick"] or _inp["P2 Medium Kick"]
					_inp["P2 Strong Kick"] = _inp["P1 Strong Kick"] or _inp["P2 Strong Kick"]
					-- START IS MIRRORED. COIN IS NOT.
					--
					-- Both were held back for fear of confirming the pick or jumping
					-- the stage. Neither applies on this screen (user, 2026-09-19):
					-- the mirror does not start until the wait above has run, so
					-- nothing is standing on Start when control arrives, and stage
					-- select is on Coin (stage-select.lua), which stays on P1.
					--
					-- Holding it is how the secret characters are picked - Start plus
					-- two punches or two kicks - so without this Dark Gallon cannot be
					-- chosen for P2 at all.
					--
					-- THE NAME IS NOT FIXED. FBNeo spells it differently per driver;
					-- macro.lua already probes the same three. The P2 spelling is the
					-- P1 one with its single 1 turned into a 2.
					for _, _s in ipairs({ "1 Player Start", "P1 Start", "Start 1" }) do
						if _inp[_s] ~= nil then
							local _p2 = _s:gsub("1", "2", 1)
							_inp[_p2] = _inp[_s] or _inp[_p2]
							break
						end
					end
					joypad.set(_inp)
				end
			else
				globals._p1_mirror_wait = 0
			end
		else
			globals._p1_mirror_wait = 0
		end
		return
	end
	soundModule.registerBefore()
	charMovesModule.registerBefore()

	globals["options"] 		 = configModule.registerBefore()
	globals["game"]    		 = gameStateModule.registerBefore() 
	globals["pushboxes"]     = cps2HitboxModule.getPushboxes()
	globals["char_moves"]    = charMovesModule.registerBefore()
	globals["dummy"]   		 = dummyStateModule.registerBefore().get_dummy_state()
	-- globals["skip_frame"] 	 = frameskipHandlerModule.registerBefore()
	globals["timers"] 		 = timersModule.registerBefore()
	positionModule.registerBefore()
	globals["current_frame"] = emu.framecount()
	-- print("rev", globals.dummy.p2_reversal)

	globals.util.disable_taunts()
	healthAndMeter.registerBefore()
	cps2HitboxModule.registerBefore()
	vsavTestMenuModule.registerBefore(globals.options.game_speed)
	rollingModule.roll()

	globals.controllerModule.handle_hotkeys()

	globals._input = controllerModule.registerBefore()

	globals.macroLua  = macroLuaModule.registerBefore()
	globals.macroLua.setloop()
	globals.recordingWizard = recordingWizardModule

	if globals.options.display_pb_stats == false then
		globals.total_pb_attempt_counter = {}
		globals.successful_pb_counter = {}
	end
	-- if globals.macroLua and (globals.macroLua.playing == true or globals.macroLua.recording == true) then
	-- 	if was_gathering_graph_data == false then
	-- 		last_dummy_config = {}
	-- 	end
	-- 	gather_graph_data = true
	-- 	was_gathering_graph_data = true
	-- else 
	-- 	gather_graph_data = false
	-- 	was_gathering_graph_data = false
	-- end

	if 
		globals and
		globals.current_frame and 
		-- gather_graph_data and
		last_dummy_config 
	then
		last_dummy_config[globals.current_frame] = globals.parsed_dummy_state
		last_dummy_dict[globals.current_frame] = globals["dummy"]
		if util.tablelength(last_dummy_config) > globals.graph_data_max then
			last_dummy_dict[globals.current_frame - globals.graph_data_max]  = nil
			last_dummy_config[globals.current_frame - globals.graph_data_max] = nil
		end
	end

	playerObject.read_player_vars(player_objects[1], player_objects[2])
	-- playerObject.read_player_vars(player_objects[2])
	
	-- RECORDING WIZARD: swallow the pad here, BEFORE the macro keys are merged
	-- below. Masking after the merge could only ever clear P1 - clearing P2
	-- would have wiped the playback it had just written - which left the
	-- answering button leaking through to P2 whenever control sat there. From
	-- in front of the merge both sides can be cleared safely: the playback is
	-- written afterwards and survives.
	--
	-- Called even when the wizard is idle: after it closes it still has to
	-- swallow the button that answered its last prompt until that button is
	-- released. mask_input decides for itself and returns at once otherwise.
	if globals.recordingWizard ~= nil and globals.recordingWizard.mask_input ~= nil then
		globals.recordingWizard.mask_input(globals._input)
	end

	-- While the wizard is active the user's pad drives P2 for the
	-- recording, so the dummy automation (Pose, Guard, Guard Action,
	-- autoguard, throw tech) must not write P2 keys - same reason the dummy
	-- modules are skipped while a macro playback runs. Macro playback keys
	-- are NOT merged either: a stale keytable would hold P2 keys down and
	-- the wizard would never see a neutral frame.
	if globals.recordingWizard ~= nil and globals.recordingWizard.is_active() then
		-- Wizard: the swapped pad is the only P2 input source - except during
		-- the confirmation playback, where the macro drives P2 and the user
		-- watches from P1. Without this merge the preview plays to nothing.
		--
		-- Recorded input is absolute stick direction. If P2 ends up facing the
		-- other way from when it was recorded, left and right are swapped on
		-- the way in, so the playback reproduces the same move rather than its
		-- mirror image.
		if globals.macroLua.playing == true then
			-- The wizard knows the facing its own take was recorded at, so the
			-- preview compares against that rather than assuming a side.
			merge_macro_keys(globals._input, globals.macroLua.get_keytable(),
				globals.recordingWizard.preview_flip ~= nil
				and globals.recordingWizard.preview_flip())
		end
	elseif globals.macroLua.playing == true then
		-- Normal slot playback. Nothing records which side the take was made
		-- from, so the standing convention is used: recordings are made with
		-- P2 on the right, and the playback is mirrored once the sides have
		-- swapped.
		merge_macro_keys(globals._input, globals.macroLua.get_keytable(),
			macro_playback_flipped())
	else
		local dummy_neutral_keys = neutralModule.registerBefore(globals._input)
		autoguardModule.registerBefore(dummy_neutral_keys, player_objects)
		local gc_keys = guardCancelModule.registerBefore()
		throwTechModule.registerBefore(globals._input)
	end

	debugKnockdownModule.registerBefore()

	globals.controllerModule.process_pending_input_sequence(player_objects[1], globals._input)

	-- Record WHICH sequence entry P2 is about to be fed, before
	-- process_pending_input_sequence consumes it. guardCancel.lua's tick hook
	-- injects that entry directly into 0xFF8B94, one tick ahead of where
	-- joypad.set() would have delivered it.
	--
	-- It has to be captured here rather than derived in the hook: while a
	-- pre-buffered motion is held, controller.lua clamps current_frame to
	-- #sequence - 1 every frame (controller.lua:614), so by the time the hook
	-- runs the index no longer says which entry was actually used. Reading it
	-- one line earlier is exact and needs no guessing.
	local _p2pre = player_objects and player_objects[2]
	local _p2preseq = _p2pre and _p2pre.pending_input_sequence
	if _p2preseq ~= nil then
		_p2preseq.inject_idx = _p2preseq.current_frame
	end

	globals.controllerModule.process_pending_input_sequence(player_objects[2], globals._input)



	-- local p2_horizontal_charge = memory.readword(0xFF8740 + 0x400)
	-- local p2_horizontal_charge_1 = memory.readbyte(0xFF8800 + 0x316)
	-- local p2_horizontal_charge_2 = memory.writebyte(0xFF8800 + 0x33E, 0x3C)

	-- print(p2_horizontal_charge, p2_horizontal_charge_1,p2_horizontal_charge_2)

	-- MEASUREMENT BUILD: record what was actually set for P2 on this frame,
	-- after the sequence has been written into _input and before joypad.set
	-- passes it to the emulator. Used to separate "the sequence is delivered a
	-- frame out of step" from "P2+0x122 / P2+0x125 lag by a frame".
	debugKnockdownModule.record_input(globals._input)

	-- REVERTED: stripping P2's keys so the tick injection was the only input
	-- source. Measured over six rounds, the pre-buffered motion simply never
	-- reached the game that way: during the knockdown the injected forward and
	-- down were written to 0xFF8B94 correctly (the log shows lever = 2 then 4)
	-- but $122/$123 stayed 0x00 the whole time, and only the release frame's
	-- input ever arrived. The likely reason is that the game does not run the
	-- 0x02211A input copy while the character is still down, so there is
	-- nothing to inject INTO until it becomes actionable - which makes
	-- joypad.set() the only thing that can carry the motion.
	--
	-- The injection is still used, but only for what it is proven to do:
	-- putting the final button and diagonal in one tick earlier than
	-- joypad.set() can (37/37 confirmed reaching $122 on the same tick).
	positionModule.mask_input(globals._input)
	-- RECORDING WIZARD: swallow the pad while the wizard is picking a slot and
	-- while it is still waiting for a neutral frame, so the LP that confirms
	-- the slot cannot reach the game and punch the dummy. It stops masking the
	-- moment the latch is set, so the first real input is delivered normally
	-- and lands in the recording.
	joypad.set(globals._input)

	inpHistoryModule.registerBefore(globals._input)
	-- VerticalCharge Value is at PL1/PL2 + 0x33E & 0x34E
	-- A successful charge value is equal to or greater than a value of 0x3C
	-- That address is a WORD and there is address 0x33C & 0x34c that starts at at 
	-- value 0x3C and reduces the value until value 0x00, this is another check for the charge function.
	
	-- I did find anotehr indication that a charge time is complete.
	-- Horizontal Charge State Address = 0xFF8740. 
	-- Where a "charging" value is 0x02 and a sucessful charge is value "0x04".

	-- Vertical Charge State Address = 0xFF8738 & 0xFF8748.
	-- Where a "charging" value is 0x02 and a sucessful charge is value "0x04".

end)


emu.registerafter(function() --recording is done after the frame, not before, to catch input from playing macros
	if globals.game_state.match_begun == false then
		if globals == nil or globals.options == nil then
			return
		end
		stageSelectModule.registerAfter()
		return
	end
	-- if memory.readdword(0xFF8804) == 0x02020400 then
	-- 	-- print("reversal frame registered after frame was drawn", emu.framecount())		
	-- 	-- local current = last_dummy_dict[globals.current_frame]
	-- 	-- current.p2_reversal_frame = true
	-- 	memory.writebyte(0xFF8902, 0x00)
	-- 	memory.writebyte(0xFF8906, 0x02)
	-- end

	vsavScriptModule.registerAfter()
	cps2HitboxModule.registerAfter()
	frameDataModule.registerAfter()
	macroLuaModule.registerAfter()
end)

if savestate.registersave and savestate.registerload then --registersave/registerload are unavailable in some emus

	savestate.registersave(function(slot)
		macroLuaModule.registerSave(slot)
	end)
	
	savestate.registerload(function(slot)
		globals.show_menu = false
		globals.debounceStarted = nil
		globals.controllerModule.enable_both_players()
		globals["options"] = configModule.registerBefore()
		globals["game"]    = gameStateModule.registerBefore() 
		globals["dummy"]   = dummyStateModule.registerBefore().get_dummy_state()

		configModule.registerBefore()
		frameDataModule.registerLoad()
		vsavScriptModule.registerLoad(slot)
		cps2HitboxModule.registerLoad()
		macroLuaModule.registerLoad(slot)
		globals.dmg_calc.red_life = 0
		globals.dmg_calc.white_life = 0
		input_history[1] = {}
		input_history[2] = {}
		globals.last_dash_ended = nil
		globals.last_dash_started = nil
		globals.last_attack_started = nil
		globals.last_attack_ended = nil
		globals.p2_hit_or_block_begin = nil
		globals.p2_hit_or_block_end = nil

		-- DROP ANYTHING STILL BEING DELIVERED.
		--
		-- A load rewinds the game but not the Lua side, and an input sequence
		-- is placed against ticks counted from before the load. Whatever is
		-- left of it then lands in the wrong place - which is why push block
		-- gets less reliable with Use Savestate Upon Recording on: its taps
		-- have to fall inside a 12 tick window, and a loop reloading mid-guard
		-- leaves the rest of them pointing at ticks that no longer exist.
		-- Cleared here so the next guard arms from scratch.
		-- An action sequence's remaining segments are held on the Lua side, so
		-- clearing the delivery slot above does not reach them. They would
		-- outlive the load and fire into a game that had rewound underneath
		-- them, which is the same fault this whole block exists to prevent.
		actionSequenceEditorModule.abort("savestate_load")
		actionSequenceRunnerModule.cancel()
		for _i = 1, 2 do
			local _p = player_objects and player_objects[_i]
			if _p ~= nil then
				_p.pending_input_sequence = nil
				if _p.counter ~= nil then
					_p.counter.sequence = nil
					_p.counter.attack_frame = -1
					_p.counter.ref_time = -1
				end
			end
		end
	end)
	
end

emu.registerexit(function() --Attempt to save if the script exits while recording
	if recording then recording = false finalize(recinputstream) end
	-- RECORDING WIZARD: restore control target and drop an in-flight recording.
	if globals.recordingWizard ~= nil then globals.recordingWizard.shutdown() end
	if save_training_data_if_dirty then save_training_data_if_dirty() end
end)

-- RUN-AHEAD BREAKS THE REVERSAL TIMING, SO SAY SO WHERE IT CANNOT BE MISSED.
--
-- Every reversal lead is counted in GAME TICKS, but the pre-buffered motion is
-- delivered one entry per DISPLAYED FRAME. Measured across 489 archived
-- attempts, one displayed frame covers 1 tick with run-ahead off and 2-3 with
-- it on, so the three-entry command stretches from 3 ticks to 6-9 and runs
-- into the command recogniser's 14-19 tick step timeout. The prediction stays
-- correct - it is the delivery that no longer fits.
--
-- FBNeo does not expose the setting to Lua, so it is inferred: 0xFF8081 is
-- incremented once per tick at 0x008E10 and can only ever go up by one, so it
-- going backwards means the emulator restored an earlier state and is re-running
-- ticks. A sustained rate is required rather than a single event, so that
-- loading a savestate does not raise the banner.
local function draw_runahead_warning()
	if type(guardcancel_runahead_state) ~= "function" then return end
	local ra = guardcancel_runahead_state()
	if ra == nil or ra.rewinds < 20 or ra.percent < 5 then return end
	local w = emu.screenwidth()
	-- Blink: a banner that never changes stops registering after a few minutes.
	local on = ((globals and globals.current_frame or 0) % 60) < 40
	gui.box(0, 0, w - 1, 32, on and 0xB00000C0 or 0x30000060, 0xFF0000FF)
	gui.text(4,  3, "*** RUN-AHEAD DETECTED - REVERSAL TIMING IS WRONG ***",
		on and 0xFFFF00FF or 0xFFFFFFFF)
	gui.text(4, 12, string.format("%.1f%% of game ticks are being re-run (depth %d)",
		ra.percent, ra.depth_max))
	gui.text(4, 21, "Set Run-ahead to Disabled in FBNeo, then restart the emulator.")
end

----------------------------------------------------------------------------------------------------
--[[ Handle pausing in the while true loop. ]]--
while true do
	gui.register(function()
		-- if memory.readdword(0xFF8804) == 0x02020400 then
		-- 	print("reversal frame registered during gui lifecycle hook")
		-- end
	
		if globals == nil or globals.options == nil then
			gui.clearuncommitted()
			return
		end
		-- Same test as the per-frame hook above, so the two never disagree:
		-- if processing was allowed to run for this frame, the overlays must be
		-- allowed to draw for it too. Guarding only one of the two was why an
		-- earlier version still flickered.
		if globals.game_state and globals.game_state.match_begun == false
			and not match_actually_running() then
			gui.clearuncommitted()
			draw_runahead_warning()
			-- Only show the help text on the select screen itself.
			if memory.readbyte(0xFF8009) == 2 then
				if globals.desired_stage ~= nil then
					gui.text(5, emu.screenheight() - 40, "Selected stage: " .. stageDataModule.get_stage_name(globals.desired_stage))
				end
				gui.text(0,0, 
				"Open Input --> Map Game Inputs --> Lua Hotkey 1 and set it for the menu button\nSet Volume Up to record dummy    Volume Down for playback \nLua Hotkey 4 to return to CSS at any time"
			)
			end
			return
		end
		hudModule.guiRegister()
		vsavScriptModule.guiRegister(display_hud, display_movelist)
		cps2HitboxModule.guiRegister(globals.options.display_hitbox_default, use_hb_config)
		vsavScriptModule.runCheats()
		timersModule.guiRegister()
		-- RECORDING WIZARD: while it is active the wizard owns the screen and
		-- the inputs - the normal menu neither draws nor listens.
		if globals.recordingWizard ~= nil and globals.recordingWizard.is_active() then
			recordingWizardModule.guiRegister()
		else
			menuModule.guiRegister()
			-- The wizard has already dropped to IDLE by the time its result
			-- message matters, so the message is drawn from this side too -
			-- otherwise COMPLETE / CANCELLED is set and never seen.
			if globals.recordingWizard ~= nil and globals.recordingWizard.draw_flash ~= nil then
				globals.recordingWizard.draw_flash()
			end
		end
		if globals.options.show_scrolling_input == true then
			inpHistoryModule.guiRegister(globals._input)
		end
		-- dummyStateModule.guiRegister() -- debug

		-- local frame_index = 0

		-- local step_x = 50
		-- local step_y = 10
		-- local init_x = 2
		-- local init_y = 2
		-- local current_x = 0
		-- local current_y = 0 
		-- if 
		-- 	graph_data ~= nil 
		-- 	and globals.show_graph_menu == true 
		-- 	and globals.input_history 
		-- 	and globals.input_history.P2 
		-- then
		-- 	gui.box(0,0,emu.screenwidth(), emu.screenheight(),"black")
		-- 	update_graph_data()
		-- 	local added_space = 0

		-- 	for k, v in ipairs(graph_data) do
		-- 		if frame_index == 0 then

		-- 			local index_row = 0 

		-- 			for _k, _v in pairs(v["state"]) do
		-- 				local __x = init_x
		-- 				local __y = init_y + 12 +  10 + ( step_y * index_row )
		-- 				if type(_v.value) ~= "function" then
		-- 					if tostring(_v.name) == "p2_input" then
		-- 						added_space = 8
		-- 					end
		-- 					gui.text(__x,__y + added_space, _v.name)
		-- 					index_row = index_row + 1
		-- 				end
		-- 			end
		-- 		end
		-- 		local _x = init_x + 70 + (step_x * frame_index)
		-- 		local _y = init_y

		-- 		gui.text(_x,_y,v["frame"])
		-- 		if globals.input_history.P1 and globals.input_history.P1[v.frame] then
		-- 			globals.inpHistoryModule.draw_input_history_entry(globals.input_history.P1[v.frame], _x,_y + 8, 0)
		-- 		end
		-- 		local index_row = 0 

		-- 		added_space = 0
		-- 		if util.tablelength(v.state) then 
		-- 			for key, val in pairs(v["state"]) do
		-- 			local __y = init_y + 12 + 10 + ( step_y * index_row )

		-- 			if type(val.value) ~= "function" then

		-- 				if tostring(val.name) == "p2_input" then
		-- 					if globals.input_history.P2 and globals.input_history.P2[v.frame] then
		-- 						globals.inpHistoryModule.draw_input_history_entry(globals.input_history.P2[v.frame], _x,__y+5, 0)
		-- 					end
		-- 					added_space = 10
		-- 					index_row = index_row + 1
		-- 				else 
		-- 					local color =  util.string_to_color(tostring(val.name)..tostring(val.value))
		-- 					gui.rect(_x - 1,__y + added_space, _x + step_x - 1, __y + step_y+ added_space, color)
		-- 					gui.text(_x + 2,__y + 2+ added_space, tostring(val.value), color)
		-- 					index_row = index_row + 1
		-- 				end
		-- 			end
		-- 		end
		-- 	end
		-- 		frame_index = frame_index+1
		-- 		current_x = _x
		-- 		current_y = _y
		-- 	end
		-- end	

		-- Last, so it paints over the hud and the hitbox overlay rather than
		-- under them.
		draw_runahead_warning()
	end)

	macroLuaModule.gameLoop()

	amountOfGarbage = collectgarbage("count")
	if amountOfGarbage > 15000 then
		collectgarbage("collect")
	end
end
