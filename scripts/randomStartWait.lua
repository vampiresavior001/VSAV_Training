-- RANDOM START WAIT (user, 2026-10-02).
--
-- One setting, in game Ticks, 0 to 60. Every time the dummy starts an action of
-- its own, a number from 0 up to the setting is drawn, and the action comes out
-- that many Ticks later than it would at 0. Drawn again every time, so the
-- player cannot learn a rhythm.
--
-- WHAT WAITS:
--   * Reversal and Counter Attack, every kind: Specified, Character Specific,
--     Recording, Action Steps, Action Patterns
--   * each loop lap of Action Steps / Action Patterns (after Loop Wait)
--   * recording playback: Play Recording, the playback hotkey, each Looped
--     Playback pass (after Loop Interval)
--
-- WHAT NEVER WAITS: defence. Guard, push block, guard cancel, throw tech and
-- air guard answer the opponent's attack inside a window the game sets, so a
-- wait there would only make them fail. The Recording Wizard's check playback
-- does not wait either: it is there to show the take that was just made.
--
-- 0 IS THE TOOL AS IT WAS. A reversal at 0 is still placed on the free tick by
-- the arm. One that waits cannot be: its input has to go in once the dummy can
-- act, so a small wait comes out no earlier than that input takes (a dash or a
-- dragon punch, about four Ticks).
local M = {}

M.MAX = 60

-- The setting, clamped. Anything that is not a number reads as 0 (off).
function M.limit()
	local v = training_settings and training_settings.random_start_wait
	v = tonumber(v) or 0
	v = math.floor(v)
	if v < 0 then v = 0 end
	if v > M.MAX then v = M.MAX end
	return v
end

-- One draw, 0..limit inclusive, every value equally likely. 0 when off, so
-- callers can take the old path on 0 without asking twice.
function M.roll()
	local n = M.limit()
	if n <= 0 then return 0 end
	return math.random(0, n)
end

-- RANDOM DELAY ON THE BUTTON (v11.7.21.2).
--
-- Reversal / Counter Attack - Specified only: the row under Button Wait.
-- Unlike the start wait above it moves nothing but the button -
-- the motion still goes in at once - so a dash or jump attack is pressed at a
-- different point of the dash or jump each time. Same range, same clamp, same
-- draw; it lives here so the two random timings read the same way.
function M.button_limit()
	local v = training_settings and training_settings.button_random_delay
	v = tonumber(v) or 0
	v = math.floor(v)
	if v < 0 then v = 0 end
	if v > M.MAX then v = M.MAX end
	return v
end

function M.roll_button()
	local n = M.button_limit()
	if n <= 0 then return 0 end
	return math.random(0, n)
end

return M
