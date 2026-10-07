-- MUTE IDLE SOUNDS (user, 2026-10-06).
--
-- Gallon growls, Jedah drips, and so on, over and over while a character just
-- stands there. Game tab > Mute Idle Sounds stops those sound requests and
-- nothing else: the idle animation still plays, and every other sound - attack,
-- guard, hit, BGM - is left alone.
--
-- WHERE A CHARACTER'S ANIMATION ASKS FOR A SOUND (c20, the MAME disassembly).
-- When a new animation cel is set, 0x027F08 reads the cel's +0x16. Zero ends
-- there (0x027F6E, rts). Otherwise 0x027F0E saves D0-D3/A3-A4 to a fixed RAM
-- area (0x330E), looks the character's entry up in the table at 0x0BF41A, and
-- at 0x027F36 tests the entry's sound id in D1:
--
--   027F36: tst.w D1
--   027F38: beq   $27f68        ; no sound for this entry
--   ...                          ; build D2/D3, jsr $4ce2 - the sound request
--   027F68: jmp   $3306          ; restore D0-D3/A3-A4, rts
--
-- THE HOOK SETS D1 TO ZERO AT 0x027F36, so the game takes its own "this entry
-- has no sound" branch and leaves through the same restore as every other
-- path. Nothing is skipped by moving the PC, no stack or saved register is left
-- half-done, and D1 itself comes back from the save on the way out. Writing a
-- data register from an exec hook, before the instruction runs, is what
-- cps2-hitboxes.lua already does (d1 at 0x0191A2).
--
-- WHAT IS MUTED: a player object (A6 = 0xFF8400 or 0xFF8800) whose character
-- ($382) and current cel ($1C, set at 0x027EE8 just before) are one of the
-- pairs below, while a match is running. Not a sound id, not "nobody pressed
-- anything": the same cel is the idle animation and nothing else is known to
-- use it. That last part is what the log below is for.
--
-- THE PAIRS ARE FROM STATIC ANALYSIS (ROM + disassembly, 2026-10-06). Which
-- ones have been confirmed by ear is in CONFIRMED.
--
-- THE LOG. With Analysis > Knockdown Logger on, every sound request a player's
-- animation makes during a match is written to reversal_logs/idle_sound.json:
-- tick, player, character, state ($04..$07), cel, the cel's +0x16, the sound
-- id, and whether it was muted. It is gathered in the hook and written from the
-- frame callback - io.open cannot write from inside an exec hook.
local M = {}

local HOOK = 0x027F36
local PLAYERS = { [0xFF8400] = 1, [0xFF8800] = 2 }

-- character id ($382) -> { [cel address] = what it is }.
-- Dark Gallon (0x12) uses Gallon's idle animation and sound table.
M.IDLE_CELS = {
	[0x02] = { [0x13B926] = "Gallon standing idle" },
	[0x12] = { [0x13B926] = "Dark Gallon standing idle (Gallon's animation)" },
	[0x0F] = { [0x2490D4] = "Jedah standing idle" },
	[0x03] = { [0x150AF4] = "Victor standing idle" },
	[0x00] = { [0x112E62] = "B.B. Hood crouching idle" },
}
-- Which of the above someone has heard stop. Reported, not used: the mute
-- applies to all of them, and this only keeps the record honest.
-- 2026-10-06 (user, by ear, with the log): the request came only in state
-- $04..$07 = 02 00 00 02 (standing neutral), muted ones were silent, and every
-- other sound in the session was left alone.
-- Later the same day (user, by ear): Victor, B.B. Hood (crouching), the P1
-- side and normal speed. Dark Gallon as P1 is in the log too: muted 5 times,
-- in 02 00 00 02 only. Victor's and B.B. Hood's sessions were not logged
-- (each run rewrites idle_sound.json), so their state is not checked.
M.CONFIRMED = {
	[0x02] = "Gallon: 0x13B926, sound 0x01CC - 2026-10-06, log + ear",
	[0x0F] = "Jedah: 0x2490D4, sound 0x0144 - 2026-10-06, log + ear",
	[0x12] = "Dark Gallon (P1): 0x13B926 - 2026-10-06, log + ear",
	[0x03] = "Victor: 0x150AF4 - 2026-10-06, ear",
	[0x00] = "B.B. Hood crouching: 0x112E62 - 2026-10-06, ear",
}

local events = {}        -- gathered in the hook, written from the frame callback
local MAX_EVENTS = 2000
local dirty = false
local last_write = 0

local function enabled()
	return globals ~= nil and globals.options ~= nil
	   and globals.options.mute_idle_sounds == true
end
local function logging()
	return globals ~= nil and globals.options ~= nil
	   and globals.options.knockdown_logger_enable == true
end
local function in_match()
	if globals == nil then return false end
	if globals.match_running ~= nil then return globals.match_running() == true end
	return globals.game_state ~= nil and globals.game_state.match_begun == true
end

-- True when this request is one of the idle sounds.
function M.is_idle_sound(char, cel)
	local cels = M.IDLE_CELS[char]
	return cels ~= nil and cels[cel] ~= nil
end

local function on_sound_entry()
	local a6 = memory.getregister("m68000.a6")
	local p = PLAYERS[a6]
	if p == nil or not in_match() then return end
	local char = memory.readbyte(a6 + 0x382)
	local cel = memory.readdword(a6 + 0x1C)
	local mute = enabled() and M.is_idle_sound(char, cel)
	if logging() then
		events[#events + 1] = {
			tick = memory.readbyte(0xFF8081), frame = emu.framecount(), p = p,
			char = char, state = memory.readdword(a6 + 0x04), cel = cel,
			spec = memory.readbyte(cel + 0x16),
			sound = memory.getregister("m68000.d1") % 0x10000,
			muted = mute,
		}
		if #events > MAX_EVENTS then table.remove(events, 1) end
		dirty = true
	end
	if mute then
		-- The game's own "no sound" branch; see the note at the top.
		memory.setregister("m68000.d1", 0)
	end
end

function M.registerStart()
	-- registerexec holds one callback per address; registering again on a
	-- reload replaces this one rather than adding a second.
	memory.registerexec(HOOK, on_sound_entry)
end

local function hex(n, w) return string.format("0x%0" .. w .. "X", n) end

-- Once a second at most, and only when something new came in.
function M.registerAfter()
	if not dirty or not logging() then return end
	local now = emu.framecount()
	if now - last_write < 60 then return end
	last_write = now
	dirty = false
	local f = io.open("reversal_logs/idle_sound.json", "w")
	if f == nil then return end
	f:write("{\n  \"note\": \"sound requests from player animations; muted = Mute Idle Sounds took it\",\n")
	f:write("  \"events\": [\n")
	for i, e in ipairs(events) do
		f:write(string.format(
			"    {\"tick\": %d, \"frame\": %d, \"p\": %d, \"char\": \"%s\", \"state\": \"%s\", \"cel\": \"%s\", \"spec\": \"%s\", \"sound\": \"%s\", \"muted\": %s}%s\n",
			e.tick, e.frame, e.p, hex(e.char, 2), hex(e.state, 8), hex(e.cel, 6),
			hex(e.spec, 2), hex(e.sound, 4), tostring(e.muted), i < #events and "," or ""))
	end
	f:write("  ]\n}\n")
	f:close()
end

-- For analysis/test_idle_sound.lua.
M._hook_address = HOOK
M._on_sound_entry = on_sound_entry
M._events = function() return events end

return M
