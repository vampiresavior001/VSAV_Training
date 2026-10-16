-- SAVE AND RESTORE A STATE BY HAND (Volume Up; Recording tab), v11.7.28 stage 2;
-- handoff VSAV_Claude_Handoff_Remaining_20261015, RECORDING_STATE_DESIGN
-- sections 5 and 6. User: "段階1と2".
--
-- Volume Up once: when the double-press window has passed, the saved state
-- comes back. Twice inside it: the state is saved - only that, nothing is
-- restored first. Counted on press edges, so held it is one press; after a
-- save or a restore nothing more is taken until it is let go. The window is
-- this script's own count of frames (WINDOW, 15: about 250 ms at 60 frames a
-- second) - not the game's Tick or frame counters, which a load rewinds. The
-- emulator paused, it does not run.
--
-- One state, for this session: a state saved with other characters, at another
-- game speed, or before the last character select (the same pair picked again
-- included) is not restored.
--
-- The state is the game's. What the scripts were doing is not in it yet
-- (stage 3: a playback's place), so:
--   * saving is refused while anything runs that it would not carry: a
--     playback (its start wait, the gap between loops), Action Steps or
--     Specified steps still to come, a queued dummy input or Character
--     Specific wait, Grab Mashing in a grab
--   * restoring stops all that first - the state was saved with none of it -
--     and the load handler (master script) clears the rest: unfinished trainer
--     lines, GC Stats' attempt in progress (not counted), the runner
--   * both are refused during a recording (Quick or not), the Recording Wizard,
--     the Action Steps editor, a position / camera move, or outside a match
--   * a restore asked for with the menu open closes the menu first, then loads
--     (Volume Up once, or the menu's Restore State row; user, 2026-10-16:
--     "ステートロードはメニューを閉じてロード、ボタンでもそれでいいかもしれない" - in
--     place of the refusal of the morning). The game stands under the menu
--     now (gameFreeze.lua), so the menu's Save State saves that scene; it asks
--     first, Yes / No (user: "右を選んでYesで保存とかにしたい")
-- Refused or empty: a message, nothing done. A save that fails keeps the old one.
--
-- Use Savestate Upon Recording is gone with this: nothing saves or loads a state
-- on its own any more - not at a record, a playback or a loop (handoff 1, 7).
-- Messages go to the emulator's line (emu.message): gui.text draws ASCII only.

local M = {}
local actionSequenceRunner = require "./scripts/actionSequenceRunner"

M.WINDOW = 15
M.NAME = "training_state"

local frame = 0            -- this script's frames
local first_at = nil       -- the first press of a pair, waiting for a second
local hold = false         -- after a save or a restore, until the key is let go
local saved = nil          -- { gen, p1, p2, speed }
local asked = false        -- the menu's Restore State row, waiting for the frame's end
local session = 0          -- the character selects since start-up

local function say(text)
	if emu ~= nil and emu.message ~= nil then emu.message(text) end
	print(text)
end
local function chars()
	return memory.readbyte(0xFF8400 + 0x382), memory.readbyte(0xFF8800 + 0x382)
end

-- Why nothing can be saved or restored right now (nil: it can).
function M.blocked()
	if globals == nil or globals.options == nil then return "not ready" end
	if globals.match_running ~= nil and not globals.match_running() then return "no match" end
	local mac = globals.macroLua
	if globals.recording == true or (globals.quickRecording ~= nil and globals.quickRecording.recording()) then
		return "recording"
	end
	local wz = globals.recordingWizard
	if wz ~= nil and wz.is_active ~= nil and wz.is_active() then return "Recording Wizard" end
	local ed = package.loaded["./scripts/actionSequenceEditor"]
	if type(ed) == "table" and ed.is_active ~= nil and ed.is_active() then return "Action Steps editor" end
	local pm = positionModule
	if pm ~= nil and pm.camera_restore_busy ~= nil and pm.camera_restore_busy() then return "position move" end
	return nil
end

-- What runs that a state does not carry (nil: nothing).
function M.running()
	local mac = globals.macroLua
	if mac ~= nil then
		local st = mac.get_recording_status ~= nil and mac.get_recording_status() or {}
		if mac.playing == true or mac.starting == true or st.loop_pending == true then return "playback" end
	end
	if actionSequenceRunner.pending_count() > 0 then return "Action Steps" end
	local p = player_objects ~= nil and player_objects[2] or nil
	if p ~= nil and p.pending_input_sequence ~= nil then return "queued input" end
	if guard_action_input ~= nil and guard_action_input.csp_due ~= nil then return "reversal waiting" end
	local gm = package.loaded["./scripts/grabMashing"]
	if type(gm) == "table" and gm._run ~= nil and gm._run() ~= nil then return "Grab Mashing" end
	return nil
end

-- All of it stops (a restore).
local function stop_running()
	local mac = globals.macroLua
	if mac ~= nil and mac.stop_all_playback ~= nil then mac.stop_all_playback() end
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

function M.save()
	local why = M.blocked() or M.running()
	if why ~= nil then say("State not saved: " .. why) return false end
	local ok = pcall(function()
		local st = savestate.create(M.NAME)
		savestate.save(st)
	end)
	if not ok then say("State not saved: the emulator refused") return false end
	local a, b = chars()
	saved = { gen = session, p1 = a, p2 = b, speed = globals.options.game_speed }
	say("State saved")
	return true
end

function M.valid()
	if saved == nil then return false, "no state saved" end
	local a, b = chars()
	if saved.gen ~= session or saved.p1 ~= a or saved.p2 ~= b then return false, "saved in another session" end
	if saved.speed ~= globals.options.game_speed then return false, "saved at another game speed" end
	return true
end

function M.restore()
	-- THE MENU CLOSES FIRST (see the top). togglemenu is menu.lua's: closing
	-- gives both players back and saves the settings. The Action Steps
	-- editor may keep it open (it asks about its draft): then nothing loads.
	if globals ~= nil and globals.show_menu == true then
		local ok0 = M.valid()
		if not ok0 then
			local _, why0 = M.valid()
			say("State not restored: " .. why0)
			return false
		end
		if togglemenu ~= nil then togglemenu() end
		if globals.show_menu == true then say("State not restored: close the menu first") return false end
	end
	local ok, why = M.valid()
	if not ok then say("State not restored: " .. why) return false end
	why = M.blocked()
	if why ~= nil then say("State not restored: " .. why) return false end
	stop_running()
	savestate.load(M.NAME)
	say("State restored")
	return true
end

-- Volume Up (controller.lua), every frame: edge = pressed this frame, up = not held.
function M.volume_up(edge, up)
	if up then hold = false end
	if not edge or hold then return end
	if first_at == nil then
		first_at = frame
	else
		first_at = nil
		hold = true
		M.save()
	end
end

-- The menu's Restore State row: asked from the menu's draw, loaded at the end
-- of the frame (a frame callback, as Volume Up's restore is).
function M.request_restore() asked = true end

function M.registerAfter()
	frame = frame + 1
	if asked then
		asked = false
		M.restore()
	end
	if first_at ~= nil and frame - first_at > M.WINDOW then
		first_at = nil
		hold = true
		M.restore()
	end
end

-- A character select (master script): what was saved before belongs to the
-- last session.
function M.new_session()
	session = session + 1
	first_at = nil
end

-- For analysis/test_training_state.lua.
function M._saved() return saved end
function M._forget() saved = nil end
function M._pending() return first_at end

return M
