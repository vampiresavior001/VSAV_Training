-- QUICK RECORDING (Recording tab, v11.7.28; handoff VSAV_Claude_Handoff_Remaining
-- 20261015, RECORDING_STATE_DESIGN sections 2 to 4, user: "11.7.28としてレコー
-- ディングの修正を開始").
--
-- Coin, once: what the dummy was doing stops (a playback, Action Steps or
-- Specified still to come, a queued input), you take over P2, and a take
-- begins. Coin again: the take ends, you are back on P1, and the take plays
-- from there - through the same start as Volume Down, so Looped Playback, the
-- Random Start Wait and Reset Distance Each Loop apply. Coin while anything
-- plays: it stops and a new take begins.
--
-- The take has a slot of its own, the dummy character's quick_recording.mis
-- (macro.lua): a numbered slot is written only by its Copy to Slot row.
-- Auto Trim (on by default) cuts the frames before the first input and after
-- the last, and keeps the place the first input was made from (macro.lua).
--
-- Quick Recording off: Coin only swaps sides, as before. Turned on while you
-- hold P2, the first Coin gives P1 back and starts nothing. A take with no
-- input keeps the old file and plays nothing. The setting turned off, the
-- Recording Wizard, the match ending, the dummy changing or a savestate load
-- during a take: the take goes, the file stays, P1 is yours again. The wizard's
-- Coin is the wizard's (controller.lua does not ask here while it is up).
-- Messages go to the emulator's own line (emu.message): gui.text draws ASCII
-- only.

local M = {}
local actionSequenceRunner = require "./scripts/actionSequenceRunner"

local state = "idle"     -- "idle" / "recording"
local take_char = nil    -- the dummy the take is for

function M.enabled()
	return globals ~= nil and globals.options ~= nil and globals.options.quick_recording == true
end
function M.recording() return state == "recording" end

local function wizard_up()
	local wz = globals.recordingWizard
	return wz ~= nil and wz.is_active ~= nil and wz.is_active()
end
local function in_match()
	return globals.match_running == nil or globals.match_running() == true
end
-- Through macro.lua's hold_message: the take plays right after it is saved,
-- and the playback's progress would write over this the next frame.
local function say(text)
	local mac = globals ~= nil and globals.macroLua or nil
	if mac ~= nil and mac.hold_message ~= nil then mac.hold_message(text)
	elseif emu ~= nil and emu.message ~= nil then emu.message(text) end
	print(text)
end
local function to_side(side)
	local c = globals.controllerModule
	if c ~= nil and c.set_controlling_target ~= nil then c.set_controlling_target(side) end
end

-- What a savestate load drops (vsav_training_master_script.lua): planned
-- before, for a dummy you are about to play yourself.
local function drop_automation()
	actionSequenceRunner.cancel()
	if guard_action_input ~= nil then guard_action_input.csp_due = nil end
	local p = player_objects ~= nil and player_objects[2] or nil
	if p ~= nil then
		p.pending_input_sequence = nil
		if p.counter ~= nil then
			p.counter.sequence = nil
			p.counter.attack_frame = -1
			p.counter.ref_time = -1
		end
	end
end

function M.start()
	local mac = globals.macroLua
	if mac == nil or mac.begin_quick_recording == nil then return false end
	mac.stop_all_playback()
	drop_automation()
	to_side("P2")
	if not mac.begin_quick_recording(globals.options.quick_auto_trim ~= false) then
		to_side("P1")
		say("Quick Recording: could not start")
		return false
	end
	state = "recording"
	take_char = globals.dummy ~= nil and globals.dummy.p2_char or nil
	say("Quick Recording: recording - Coin to finish")
	return true
end

function M.finish()
	local mac = globals.macroLua
	state = "idle"
	to_side("P1")
	local ok, n = mac.finish_quick_recording()
	if not ok then
		say("Quick Recording: no input, not saved")
		return false
	end
	-- COIN SAVES TO = PLAYBACK SLOT (user, 2026-10-21, from a player's request:
	-- the old Coin went straight into a slot). The take is written over the
	-- Playback Slot as well, without asking - what Copy to Slot does by hand.
	-- What plays is still the take itself: with Use Random Recording Slot on,
	-- the slot's own start could pick another one.
	local into = ""
	if globals.options.coin_saves_to == 2 and mac.copy_quick_to_slot ~= nil then
		local okc, name = mac.copy_quick_to_slot(globals.options.recording_slot)
		into = okc and (", saved to " .. name) or (", NOT saved to the slot (" .. tostring(name) .. ")")
	end
	if mac.play_quick() then
		say("Quick Recording: " .. n .. " frames" .. into .. ", playing")
	else
		say("Quick Recording: " .. n .. " frames saved" .. into)
	end
	return true
end

function M.cancel(why)
	if state ~= "recording" then return false end
	state = "idle"
	local mac = globals.macroLua
	if mac ~= nil and mac.cancel_quick_recording ~= nil then mac.cancel_quick_recording() end
	to_side("P1")
	say("Quick Recording: discarded (" .. tostring(why) .. ")")
	return true
end

-- Coin's press (controller.lua). true: handled here, the side swap is not done.
function M.on_coin()
	if wizard_up() or not in_match() then return false end
	if state == "recording" then
		if M.enabled() then M.finish() else M.cancel("off") end
		return true
	end
	if not M.enabled() then return false end
	if globals.controlling_p1 ~= true then
		to_side("P1")
		return true
	end
	M.start()
	return true
end

-- Every frame: a take whose reason to exist went away goes.
function M.registerAfter()
	if state ~= "recording" then return end
	local why = nil
	if not M.enabled() then why = "off"
	elseif wizard_up() then why = "wizard"
	elseif not in_match() then why = "match over"
	elseif globals.dummy ~= nil and take_char ~= nil and globals.dummy.p2_char ~= take_char then why = "dummy changed"
	end
	if why ~= nil then M.cancel(why) end
end

function M.reset(why)
	M.cancel(why or "reset")
end

-- Volume Down (controller.lua): the quick take playing, or waiting to start or
-- to loop, is stopped - pressed again from there, the menu's slot plays.
function M.volume_down()
	local mac = globals.macroLua
	if state == "recording" then return true end
	if mac ~= nil and mac.quick_playing ~= nil and mac.quick_playing() then
		mac.stop_all_playback()
		say("Quick Recording: stopped")
		return true
	end
	return false
end

-- For analysis/test_quick_recording.lua.
function M._state() return state end

return M
