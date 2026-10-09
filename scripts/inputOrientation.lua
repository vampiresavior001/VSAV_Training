-- AUTO-FLIP INPUTS ON SIDE SWITCH (user, 2026-10-09).
--
-- The dummy's automated inputs follow a side switch: a recording's left and
-- right are swapped whenever P2 faces the other way from the take
-- (vsav_training_master_script.lua, merge_macro_keys), and Action Steps'
-- forward and back are resolved against the facing every tick
-- (guardCancel.lua facing_for_input, controller.lua). That is what reproduces
-- a move from either side, and it stays the default.
--
-- OFF is for studying what the SAME input does after the characters turn
-- round - an option select on a cross-up, say. The left / right the run sent
-- its first input under is kept until the run ends, through any number of
-- switches; the game then reads those inputs against its own new facing, as
-- it would a player's who kept holding the same way. Nothing else changes:
-- directions the take or the list itself changes are sent as written, and
-- buttons, timing, Wait and Hold mean what they did.
--
-- A RUN is one recording playback (Play Recording, one Looped Playback pass, a
-- Recording guard action), or one Action Steps / Action Patterns / Specified
-- input from its arm to its end, or one Loop Steps lap. Whether it is ON or
-- OFF is read when the run starts, and does not change inside it. The facing
-- is taken on the run's FIRST INPUT - the first tick that presses something -
-- not when it is armed, so a switch while it waits still counts, and a
-- buffered command's first direction is that first input. A new run takes it
-- again; a stale one is never read, because only inputs tagged with the
-- current run ask for it.
--
-- Pure: no memory reads. The setting is read from training_settings when a
-- run starts.

local M = {}

local function auto_flip()
	return not (training_settings ~= nil and training_settings.auto_flip_inputs == false)
end
M.auto_flip = auto_flip

-- RECORDINGS. One run per playback; macro.lua counts them (playback_serial).
local rec = { serial = nil, off = false, flip = nil }

-- serial: the playback this frame belongs to. live: whether the existing rule
-- would swap left and right this frame. pressing: the frame presses a P2 key.
-- Returns the swap to use.
function M.rec_flip(serial, live, pressing)
	if serial ~= rec.serial then
		rec = { serial = serial, off = not auto_flip(), flip = nil }
	end
	if not rec.off then return live end
	if rec.flip == nil then
		if not pressing then return live end
		rec.flip = live
	end
	return rec.flip
end

-- ACTION STEPS. actionSequenceRunner and guardCancel start a run and tag each
-- input list they queue with its id; holds and the like belong to the run
-- whose guard action owns the dummy.
local steps_serial = 0
local steps = nil   -- { id, off, face }

function M.steps_begin()
	steps_serial = steps_serial + 1
	steps = { id = steps_serial, off = not auto_flip(), face = nil }
	return steps_serial
end

function M.steps_run()
	return steps and steps.id or nil
end

function M.steps_end()
	steps = nil
end

-- live: the facing the existing code resolves forward / back against (0 or
-- 1). id: the run the input belongs to, or nil for anything that is not a
-- run's. press: this resolution is for an input that presses something - the
-- first one fixes the facing (guardCancel only; the frame path is a tick
-- behind and only reads). Returns the facing to use.
function M.steps_face(live, id, press)
	if id == nil or steps == nil or id ~= steps.id or not steps.off then return live end
	if steps.face == nil then
		if press then steps.face = live end
		return live
	end
	return steps.face
end

-- Loading a state, a new match or character select: nothing carries over.
function M.reset()
	rec = { serial = nil, off = false, flip = nil }
	steps = nil
end

-- For the offline tests.
function M.state() return { rec = rec, steps = steps } end

return M
