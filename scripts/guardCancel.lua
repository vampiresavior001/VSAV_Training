local debugKnockdownModule = require "./scripts/debugKnockdown"
local actionSequenceRunnerModule = require "./scripts/actionSequenceRunner"

local function maybe(x)
	if 100 * math.random() < x then 
		return true
	else 
		return false
	end  
end 
local function shouldGC()
	local GC_freq_value = globals.options.gc_freq
    local function maybe(x) 
        if 100 * math.random() < x then 
            return true
        else 
            return false
        end  
    end    

	local should_GC = false

	-- THE NUMBERS ARE THE ONES ON THE MENU.
	--
	-- These read 35 and 65 while menu.lua's gc_freq list offers "25%" and
	-- "75%", so the two settings either side of the middle were off by ten
	-- points from what they said. Nobody could see it while the per-frame draw
	-- (see gc_should_perform below) turned every setting into 100%.
	if GC_freq_value == 0x2 then
        should_GC = maybe(25)
    elseif GC_freq_value == 0x3 then
        should_GC = maybe(50)
	elseif GC_freq_value == 0x4 then
		should_GC = maybe(75)
	elseif GC_freq_value == 0x5 then
        should_GC = true
    elseif GC_freq_value == 0x1 then
		should_GC = false
    end

    return should_GC
end

-- ONE ROLL PER ARM, NOT ONE PER DISPLAYED FRAME AND NOT ONE PER STUN SPAN.
--
-- Guard Action Frequency had no effect: every setting above None came out
-- essentially always. shouldGC() was called from guardCancelCheck once per
-- frame, and a failed roll returns before the arm is consumed - but an arm is a
-- LATCH, not a per-frame edge. BLK.edge is raised in service_held_reversal and
-- cleared only where it is consumed or when stun ends, so a failed roll left it
-- standing and the next frame drew again, and the one after that:
--
--     P(fire) = 1 - (1 - p)^frames-of-stun    ->  50% over 10 frames = 99.9%
--
-- This is the trap the pit-of-blame note already names in this file - "rolling
-- anywhere that runs every frame would effectively force 100%" - and that path
-- was fixed by rolling once on arming and latching it. kd_armed_roll was
-- declared for the same fix here and never assigned or read.
--
-- THE OPPORTUNITY IS AN ARM, AND AN ARM IS ONE BLOCKED HIT.
--
-- Rolling once per stun span was the first attempt and it reads low, because a
-- span is not one opportunity. BLK.episode is cleared on every rise of $158 -
-- see "EVERY BLOCKED HIT GETS ITS OWN MOTION" below - so a three-hit
-- blockstring arms three times inside one span. One draw for the three turns
-- 1 - 0.75^3 = 58% into 25%.
--
-- So the roll belongs to the arm: drawn on the frame an arm first stands, held
-- while it stands (an arm waits several frames to be consumed and the gate must
-- not flicker underneath it), and drawn again for the next arm.
--
-- A REFUSAL CONSUMES THE ARM.
--
-- Otherwise a refused arm stays latched, the next arm cannot be told apart from
-- it, and the early return below blocks the rest of the function for the whole
-- span. Dropping it says what the refusal means - this hit, no guard action -
-- and leaves the machinery running.
--
-- AN ARM IS NOT AN OPPORTUNITY EITHER.
--
-- Rolling once per arm was the second attempt and still reads as 100%, because
-- one blocked hit can arm several times: BLK.episode is cleared BOTH on the
-- $158 rise (a new hit, which is a new opportunity) AND on any frame where
-- $140 leaves the block-recovery values (which is not). Every extra arm drew
-- again, so the rate climbed back toward 1 - (1-p)^arms.
--
-- The boundary the code itself names is the $158 rise - see "EVERY BLOCKED HIT
-- GETS ITS OWN MOTION" below, which is where the design says one blocked hit
-- is one motion. So that is what the roll is counted against: a serial bumped
-- where a new opportunity begins, and one draw per serial. Knockdown and hit
-- stun get theirs on entering stun, which is once per span for them.
--
-- Global, not a file local: service_held_reversal bumps it and is at Lua 5.1's
-- 60-upvalue ceiling, and a global costs it nothing.
gc_opportunity = 0

-- The direction a Hold step left behind, as an input entry (names, not bits -
-- the bits depend on facing, which is read fresh on each tick). nil when
-- nothing is being held.
--
-- Global for the same reason gc_opportunity is: the tick hook reads and writes
-- it, and a file-level local costs that closure an upvalue.
seq_held_lever = nil
-- THE BUTTON HOLD, WHICH IS THE LEVER HOLD WITH AN END TO IT.
--
-- Victor's medium and heavy normals turn electric when the button is kept down
-- (Mizuumi writes them 5[MP]). seq_held_lever cannot carry it: that one holds
-- until the next step, and a button held that long leaves the next attack no
-- press edge. So this is its own pair - the names, and the tick the holding
-- stops on.
--
-- It cannot be in the input list either. The arm path presses the button
-- itself and then drops the sequence, so copies of the pressed entry never
-- reach the game (measured: a plain MP came out).
--
-- entry_to_bits is a plain name-to-bit map and already knows the six buttons,
-- so the assert below is the same one the lever uses.
local seq_held_btn = nil
local seq_held_btn_until = nil

-- COUNTED, BECAUSE THREE FIXES IN A ROW WERE ARGUED RATHER THAN MEASURED.
--
-- Show GC Frequency Counter in the Trainer tab prints these. Read together
-- they say which half is wrong without another round of reasoning:
--
--   rolls_true / opportunity  is the gate's real rate
--   fires == rolls_true       the gate decides what gets armed
--   steps_fired > fires       later steps are coming out on their own
gc_rolls_true = 0
gc_fires      = 0

local gc_rolled_for = -1
local gc_arm_roll = false

-- THE GATE IS CLOSED ON EVERY FRAME OF A REFUSED CHANCE, NOT ONLY ON THE ARM.
--
-- This briefly opened when no arm was standing, reasoning that the frequency
-- decides whether guard actions happen and not whether the rest of
-- guardCancelCheck runs. That is wrong, and it is what made None come out every
-- time: the REACTIVE path needs no arm at all. It writes counter.sequence near
-- the end of guardCancelCheck and the queue below sends it, and the only thing
-- standing between it and the dummy is the early return this value feeds.
--
-- So the answer is held for the whole chance and every frame of it is gated.
-- What the per-opportunity counter buys is WHEN the draw happens, not which
-- frames it covers.
function gc_should_perform(_arm_now)
	if gc_rolled_for ~= gc_opportunity then
		gc_rolled_for = gc_opportunity
		gc_arm_roll = shouldGC()
		if gc_arm_roll then gc_rolls_true = gc_rolls_true + 1 end
		-- One row per opportunity. If a run shows more of these than the dummy
		-- had blocked hits, the boundary is still wrong and this says so.
		debugKnockdownModule.mark_write("gc_roll",
			gc_arm_roll and 1 or 0,
			(globals and globals.options and globals.options.gc_freq) or -1)
	end
	return gc_arm_roll
end

-- FIX: is the move being poked one of the character's inherently-EX moves
-- (charMoves.lua's per-move "isEX" field, e.g. Morrigan's Darkness Illusion)?
-- That field was dead until now - see the note in poke_special() below.
-- globals.char_moves.P2 is rebuilt every frame by charMovesModule.registerBefore(),
-- called earlier in the same frame (vsav_training_master_script.lua), so this
-- reads already-current data rather than recomputing anything itself.
local function move_is_ex(move_value)
	local moves = globals.char_moves and globals.char_moves.P2 and globals.char_moves.P2.all
	if not moves then return false end
	for _, m in pairs(moves) do
		if m.value == move_value then
			return m.isEX == true
		end
	end
	return false
end

-- FEATURE: Anakaris's Pit of Blame ("咎めの穴") is selected like any other
-- Character Specific Reversal, but it is not a reversal - it is used during
-- the opponent's knockdown to swallow a follow-up hit. The ordinary reversal
-- window only opens near wake-up, far too late, so without a trigger of its
-- own the move could be picked from the menu and never come out.
--
-- Declared here (rather than next to its trigger further down) so
-- run_one_frame_special can see it too.
local function move_is_pit_of_blame()
	local m = globals.dummy.p2_char_specific_reversal
	return m ~= nil and m.name == "Pit of Blame"
end

-- Armed by poke_special() when it writes an ES/EX palette effect, so
-- reassert_palette_effect() (further down) knows what to keep re-writing for
-- a few frames past the poke. See the FIX note inside poke_special().
local pending_palette = nil
-- Wake-up: +0x147 is never written. +0x134 / +0x11E / +0x143 are
-- zeroed two ticks after a free-1 poke (reversal+1).
local pending_wakeup_flag_zero = nil

-- Same rule as side_flag_now(): face P1 from X, keep current $b in
-- the overlap deadzone. Defined here because poke_special() sits
-- above side_flag_now() in this file.
local function p2_facing_toward_p1()
	local _mx = memory.readword(0xFF8810)
	local _ox = memory.readword(0xFF8410)
	if _mx >= 32768 then _mx = _mx - 65536 end
	if _ox >= 32768 then _ox = _ox - 65536 end
	local _d = _mx - _ox
	if ((_d + 0x16) % 65536) <= 0x2C then
		return memory.readbyte(0xFF880B)
	end
	if _d < 0 then return 1 end
	return 0
end

-- FIX: the raw pokes that start the reversal, factored out so the
-- turbo-recovery path below can re-issue the exact same sequence.
--
-- 0xFF8805 is cleared as part of this. The dword at 0xFF8804 must read
-- 0x02_00_0E00 for the game to accept the action; if the middle byte still
-- holds 0x02 (hurt / blockstun) the game silently refuses it - b8807 is never
-- set, the reversal counter at 0x174 stops draining, and the dummy is stuck
-- in "Special Attack" until the machine resets. Since 0xFF8805 == 0x02 is
-- exactly the state a reversal comes out of, the byte has to be cleared
-- rather than waited out. Cancelling recovery is what a reversal does anyway.
local function poke_special(move_value, move_strength)
	memory.writebyte(0xFF8902, move_strength)
	memory.writebyte(0xFF8906, move_value)
	-- Character Specific skips command recognition, so throw
	-- self-direction never runs. Face P1 here instead.
	memory.writebyte(0xFF880B, p2_facing_toward_p1())
	-- FIX: ES/EX palette flash (was dead code - see below).
	--
	-- 0x14E is Palette Effects & Curse (ES/EX/etc). This was originally two
	-- copies of the same ES check, one of them guarded by "isEX", a variable
	-- never defined anywhere in this file or passed into this function - a
	-- global read as nil, so that branch never ran.
	--
	-- ES is selected purely through the Strength dropdown (Light/Medium/
	-- Heavy/ES), which writes move_strength == 0x06 - see
	-- run_one_frame_special() above. EX is a property of the MOVE itself,
	-- not the strength: a handful of moves per character (e.g. Morrigan's
	-- Darkness Illusion) are inherently EX-only, marked isEX = true in their
	-- charMoves.lua entry - that field is what the dead "isEX" branch should
	-- have been reading. move_is_ex() above does that lookup.
	--
	-- VALUES CORRECTED against the original comment: the comment (kept from
	-- before this was enabled) labelled 0x1E as ES and 0x1C as EX. Real
	-- hardware showed the opposite - 0x1E produces a flicker (the EX look),
	-- 0x1C produces the blue-white flash (the ES look).
	--
	-- FIX: this write alone was not enough for a WAKEUP reversal (rev == 9 at
	-- 0xFF8974). Paired kd_sNN/kd_mNN.json logs showed the byte land here
	-- correctly on the poke frame in every case, wakeup or not, then get
	-- wiped back to 0x00 exactly one frame later in every wakeup case but
	-- one - and stick as written in every hit/block-stun reversal (rev == 5).
	-- Something tied to the wakeup transition clears it right after, which a
	-- single write here cannot beat. See reassert_palette_effect() below,
	-- which re-writes it for a few frames past the poke so it wins that race
	-- regardless of which path the reversal came from.
	local palette_value = nil
	if move_is_ex(move_value) then
		palette_value = 0x1E
	elseif move_strength == 0x06 then
		palette_value = 0x1C
	end
	if palette_value then
		memory.writebyte(0xFF8800 + 0x14E, palette_value)
		pending_palette = { value = palette_value, frames_left = 5 }
	else
		pending_palette = nil
	end
	-- -- Write WORD at FF8406 to value 0x0E00
	-- FIX: clear the leftover state the dummy is coming out of.
	--
	-- Writing the action byte starts the move's animation, but on its own it
	-- leaves state from the knockdown in place, and the game then skips the
	-- work that normally accompanies a move start. Three symptoms, one cause:
	-- the projectile is never spawned (Soul Fist comes out with no fireball),
	-- the hurtboxes are never rebuilt (the character reads as fully
	-- invincible until landing) and the sprite can disappear entirely.
	--
	-- These five bytes were found by sweeping the whole P2 object across
	-- reversals that worked and reversals that did not: they read 0 on the
	-- poke frame in every working case and non-zero in every failing one.
	-- Their individual roles are undocumented; P2+0x140 matches the reversing
	-- notes' remark that moves needing an extra lookup "set player + 0x140
	-- before resolving the animation ID".
	--
	-- The set is deliberately this and no larger - see the note below.
	memory.writebyte(0xFF890D, 0x00)
	memory.writebyte(0xFF8917, 0x00)
	memory.writebyte(0xFF8945, 0x00)
	memory.writebyte(0xFF8980, 0x00)
	memory.writebyte(0xFF898E, 0x00)

	-- FIX: invisible reversal. Found the same way as the five above (sweep
	-- at the poke frame, compare working vs failing recordings). The byte
	-- right before 0xFF890D, which the five above never touch.
	--
	-- Unlike the five above, this one is not simply "residue present or not":
	-- in EVERY recording, marked or not, it flickers 0x00/0xFF every couple
	-- of frames before the poke - almost certainly the ordinary hit/knockdown
	-- flash. What differs is which phase it happens to be sitting on at the
	-- exact poke frame: every kd_mNN.json (player marked the reversal as
	-- coming out invisible) reads 0xFF there and then holds it, unchanging,
	-- for the ~65 frames of the reversal; every unmarked recording reads 0x00
	-- at the same frame and holds THAT instead. So the flicker is not reset
	-- by the poke, and whichever phase it lands on gets frozen for the whole
	-- move - a timing race, which fits invisibility being intermittent rather
	-- than tied to any fixed state. Forced to the 0x00 (visible) phase here.
	--
	-- CONFIRMED on real hardware: fixes the invisibility. A/B tested against
	-- a separate report of ES Shadow Blade not flashing blue-white - that
	-- happened identically with this line disabled, so it predates this fix
	-- and is not a side effect of it (see move_strength == 0x06 note below).
	memory.writebyte(0xFF890C, 0x00)

	-- TESTED AND DISPROVEN: 0xFF8920 clearing here (paired kd_sNN.json logs
	-- had shown it stuck at 1 through the whole window only in an invisible
	-- reversal, 0 by mid-reversal in a normal one). Real-hardware test:
	-- invisibility still reproduced repeatedly with the clear in place, so the
	-- byte is a downstream symptom/correlate, not the cause. Do not re-add
	-- without new evidence.

	-- Bytes deliberately NOT cleared, each established by testing:
	--
	--   0xFF89A7  holds the knockdown type. Clearing it loses the "can air
	--             recover" property, so a sweep knockdown becomes a hard one.
	--             Unlike the five above it is a counter (0x18..0x1B), not a
	--             flag, which fits it being an animation/knockdown id.
	--   0xFF8944  NO LONGER on this list - see the combo/hit-count FIX
	--             further down, which clears it unconditionally on every
	--             poke. Left here for history: clearing it was long believed
	--             to make Shadow Blade's animation vanish (found stopping a
	--             reversal being stuffed by a meaty jump-in during the
	--             crush-bug investigation), and a targeted arm_edge-only
	--             clear was tried and reverted for the invisibility bug
	--             (correlated, not causal - see 0xFF890C's note above for
	--             what the actual cause was). Blanket-clearing it here was
	--             requested anyway for the hit-count fix, and on real
	--             hardware the animation was fine. Why that differs from the
	--             earlier finding is unresolved - if Shadow Blade's animation
	--             is ever reported missing again, this write is the first
	--             thing to suspect.
	--   0xFF8940  no measured effect once the five above are cleared. Also
	--             tested as a targeted "rewrite 0x04 to 0x00" against the
	--             invisible-reversal case, on the theory that a stale
	--             animation-table selector was behind it: no effect either.
	--             Reverted; the theory is disproven.
	--
	-- 0xFF890D / 0xFF8917 are the pair that keeps the knockdown recoverable;
	-- without them a sweep knockdown stays down.

	-- Do not write +0x147. A poke-frame 0x01 stays for the whole special
	-- when the game never overwrites it.
	--
	-- Wake-up: do not touch invuln bytes on poke (reversal-1) or the
	-- next tick (reversal). The tick hook zeros +0x134 / +0x11E /
	-- +0x143 on reversal+1. It never writes +0x147.
	-- Guard reversals never arm that zero.
	local _rev = memory.readbyte(0xFF8974)
	local _kd  = memory.readbyte(0xFF89A7)
	if _rev == 9 or _kd > 0 then
		pending_wakeup_flag_zero = 2
	else
		pending_wakeup_flag_zero = nil
	end

	memory.writebyte(0xFF8805, 0x00)
	memory.writeword(0xFF8806, 0x0E00)
	-- FIX: was 0xFF87B5, which is P1+0x3B5. Every other write in this
	-- function targets the dummy at P2 (0xFF8800+), so this one was
	-- inconsistent - most likely a P1 address left unconverted. Corrected to
	-- P2+0x3B5. Note: no behavioural difference was observed either way
	-- during testing, so the role of this byte remains undocumented.
	memory.writebyte(0xFF8BB5, 0x0C)

	-- TESTED AND DISPROVEN: clearing P1+0x1B7 / P1+0x1B9 here as candidate
	-- combo/hit-count bytes (found climbing by 1 at each hit in a chained
	-- test session, see git history / handoff doc for the detail). No effect
	-- on real hardware - the on-screen count still carried over. Either the
	-- wrong address, or the right address read but not what the game
	-- actually derives the display from. Do not re-add without new evidence.

	-- FIX: combo/hit count carrying over into the next confrontation.
	--
	-- Reported symptom: repeating reversal -> meaty, with the dummy never
	-- reaching neutral in between, kept adding to the on-screen HIT counter
	-- instead of each reversal starting its own count.
	--
	-- 0xFF8944 (b144 - see "Bytes deliberately NOT cleared" above) climbed in
	-- lockstep with the on-screen hit count in a chained reversal-meaty test
	-- session (1,2,4,1,2,3,5,6,7,8 - ending at 8, matching the reported
	-- on-screen count for that same session).
	--
	-- This is the SAME byte earlier notes say makes Shadow Blade's animation
	-- vanish when blanket-cleared, found during the crush-bug investigation -
	-- cleared here anyway, on request, accepting that risk. CONFIRMED on
	-- real hardware for THIS symptom: the count now resets on each reversal
	-- and the animation still plays correctly. Unclear why this differs from
	-- the earlier crush-bug finding - possibly a different value range, or a
	-- different knockdown path, was involved there. If Shadow Blade's
	-- animation is ever reported missing again, this line is the first
	-- thing to suspect and revert.
	memory.writebyte(0xFF8944, 0x00)

end

-- Armed after a poke so the next frame can verify it survived.
-- See retry_if_swallowed().
local pending_retry = nil

-- FORWARD DECLARED, AND IT HAS TO BE (v164).
--
-- The tick hook calls this through a reference so it can place the poke on the
-- free-1 signature. v160 assigned the reference immediately after the function
-- and declared the local LATER in the file, which in Lua means the assignment
-- wrote a global and the later `local ... = nil` shadowed it - the hook read
-- nil and Character Specific stopped firing entirely.
--
-- check_lua_scope.py reported it ("371 gyou de shiyou / 494 gyou de sengen")
-- and the output was not read. That is the fifth time this class of bug has
-- cost a test session; the check exists for exactly this.
local run_one_frame_special_ref = nil

local function run_one_frame_special()
	-- 1f specials/supers
	-- Allocate the strength at 0xFF8502, where  
	-- 0x00 = Light, 0x02 = Medium, 0x04 = Heavy & 0x06 = ES
	-- Allocate the specific move at 0xFF8506 - see tweets per character
	-- Write WORD at FF8406 to value 0x0E00
	-- Add dark force reversals using this ram address 0x110
	--
	-- FIX (crash): this used to index .value straight off
	-- p2_char_specific_reversal, which is nil whenever the selected reversal
	-- index does not resolve to a move - and it stops resolving as soon as
	-- the dummy changes to a character with a shorter reversal list, since
	-- p2_reversal_list keeps its old index across a character change.
	-- Reproduced as "attempt to index field 'p2_char_specific_reversal' (a
	-- nil value)" after switching the dummy from Anakaris (14 reversals) to
	-- Morrigan with a high index selected. Nothing can be poked without a
	-- move, so return rather than crash the whole script.
	local selected_move = globals.dummy.p2_char_specific_reversal
	if selected_move == nil then return end

	-- FIX: Pit of Blame must never be poked, full stop - it has its own
	-- real-input trigger in service_held_reversal() (see the HISTORY note
	-- below the action_slot guard further down). This used to be excluded
	-- only at the 'Character Specific Reversal' call site in
	-- guardCancelCheck(); 'Character Specific Counter' had no such
	-- exclusion, so selecting Pit of Blame there still poked it - the exact
	-- poke path this move was moved off of. Guarded here instead, at the
	-- one place every call site funnels through, so no future call site can
	-- reopen it by omission.
	if move_is_pit_of_blame() then return end

	local move_value = selected_move.value
	local move_strength = globals.dummy.p2_reversal_strength

	-- FIX: don't poke over an action that is already running.
	--
	-- 0xFF8806 holds the action in progress. Overwriting an unknown action
	-- mid-flight is what leaves the object in a state the game never
	-- acknowledges: it freezes in "Special Attack" and the machine resets.
	--
	-- 0x04 is explicitly allowed. It appears with status_2 "Walk" at the tail
	-- of hitstun - exactly when a reversal is meant to come out - and
	-- rejecting it made the reversal silently not happen (reproduced with a
	-- Demitri mirror match: Demon Cradle intermittently failing to appear
	-- after an air counter-hit).
	--
	-- Note on history, because it is easy to re-break this: the guard first
	-- rejected every non-zero value, based on one measured freeze whose state
	-- was b8805=2, b8806=4. That attribution was wrong. The freeze came from
	-- b8805 staying at 2, which makes the write land as 0x02_02_0E00 - a
	-- pattern the game silently refuses. At the time of that measurement the
	-- b8805 clear in poke_special() did not exist. With it in place the same
	-- situation writes 0x02_00_0E00 and is accepted.
	--
	-- Values other than 0x00 / 0x04 stay blocked: none have been observed at
	-- a trigger, so there is no evidence either way.
	--
	-- HISTORY: Pit of Blame used to be allowed to skip this guard, because the
	-- action byte sits at 0x02 for ~38 frames after the hit that starts a
	-- knockdown - the whole window that move is useful in - so the guard
	-- rejected every attempt. That bypass carried a freeze risk and is gone:
	-- Pit of Blame no longer pokes at all, it feeds the real command as button
	-- presses (see service_held_reversal). Do not reintroduce it.
	local action_slot = memory.readbyte(0xFF8806)
	if action_slot ~= 0x00 and action_slot ~= 0x04 then
		return
	end

	-- AND $05 HAS TO AGREE (v160).
	--
	-- $06 == 0x00 is not only "idle". It is also the IMPACT FREEZE of being
	-- hit, and this poke fires from the once-per-frame callback, so it could
	-- land in the middle of a hurt animation - which is what "a special
	-- suddenly comes out mid-hitstun and mashes" is. $06 alone cannot tell the
	-- two apart; $05 can.
	--
	-- Allowed:
	--   $05 == 0x00                     the character is genuinely free
	--   the free-1 signature            02/04/00, the last recovery tick, which
	--                                   is exactly where a reversal belongs
	local _p05 = memory.readbyte(0xFF8805)
	local _sig = (_p05 == 0x02 and action_slot == 0x04
	              and memory.readbyte(0xFF8807) == 0x00)
	if _p05 ~= 0x00 and not _sig then
		return
	end

	poke_special(move_value, move_strength)

	pending_retry = {
		frame         = globals.current_frame,
		move_value    = move_value,
		move_strength = move_strength,
	}
end
run_one_frame_special_ref = run_one_frame_special   -- see the forward declaration above
-- FIX (turbo 3): re-assert a poke that was swallowed by an invisible tick.
--
-- Turbo 3 runs 4 game ticks across 3 displayed frames - the logical frame
-- counter at 0xFF8081 advances 1,1,2,1,1,2... A Lua callback fires once per
-- displayed frame, so on a double-tick frame the second tick executes with no
-- chance for the script to act, and it can clear the action byte we just
-- wrote. The game may already have shown "REVERSAL" by then, which matches
-- the reported symptom: the reversal is acknowledged but no move appears.
--
-- One frame after a poke, check whether it survived. Re-issue it only when
-- all three hold:
--   * 0xFF8806 == 0  - our action is gone and nothing else claimed the slot
--   * 0xFF8805 == 0  - the dummy was NOT hit, so this was not a legitimate
--                      loss to an attack (re-poking after a real hit would
--                      cancel hitstun and leave the hit effect on screen
--                      while the move comes out)
--   * 0x174    > 0   - still inside the reversal window
--
-- Fires at most once, on the immediately following frame only. If the
-- swallowing theory is wrong it simply never fires and behaviour is
-- unchanged. Delete this function and its single call site to remove it.
local function retry_if_swallowed()
	if not pending_retry then return end
	if globals.current_frame ~= pending_retry.frame + 1 then
		pending_retry = nil
		return
	end

	local swallowed =
		memory.readbyte(0xFF8806) == 0x00 and
		memory.readbyte(0xFF8805) == 0x00 and
		memory.readbyte(0xFF8974) > 0

	if swallowed then
		poke_special(pending_retry.move_value, pending_retry.move_strength)
	end
	pending_retry = nil
end

-- Zero wakeup leftover on reversal+1. Do not write +0x147.
local function zero_wakeup_invuln_flags()
	memory.writebyte(0xFF8934, 0x00)
	memory.writebyte(0xFF891E, 0x00)
	memory.writebyte(0xFF8943, 0x00)
end

-- FIX: keep the ES/EX palette effect written for a few frames past the poke.
--
-- See the note inside poke_special(). A single write there is enough for a
-- hit/block-stun reversal (rev == 5 at 0xFF8974) but not a wakeup one
-- (rev == 9): something clears 0xFF894E back to 0x00 one frame after the
-- poke in that case, almost every time. Rewriting it here for a handful of
-- frames is enough to win that race regardless of which path the reversal
-- came from - harmless on the rev == 5 path too, since it just rewrites the
-- same value that was already going to stick.
local function reassert_palette_effect()
	if not pending_palette then return end
	memory.writebyte(0xFF8800 + 0x14E, pending_palette.value)
	pending_palette.frames_left = pending_palette.frames_left - 1
	if pending_palette.frames_left <= 0 then
		pending_palette = nil
	end
end

-- GC専用の任意フレーム入力ディレイ（gc_input_delay）。
--
-- 既定の GC は、ガード開始を検知したフレームで最速入力（DPF + ボタン）を
-- queue する。ここでは「ガード開始エッジで予約を持ち、指定フレーム後に
-- queue する」形にして、ガードキャンセル本来のタイミングに任意のディレイを
-- 足せるようにする（人間の手入力の遅れを再現）。
--
-- started_guarding は playerObject.lua で p2_guarding の立ち上がりのみ true に
-- なる 1フレームエッジ。そのためこの予約は、GC分岐の started_guarding 依存
-- ロジック（else で counter.sequence を nil にする側）とは分離し、
-- shouldGC() の早期 return より前で毎フレーム処理する。こうしないと
-- attack_frame を未来にしても翌フレームで予約が消える。
--
-- 発火は queue_input_sequence を直接使う。counter.sequence / common queue
-- 経路は通さないので、後続のGC分岐が sequence を nil にしても失われない。
--
-- 方針（ユーザー指定）: 遅延カウント中に GC 受付窓（blockstun終了）を過ぎた
-- 場合でも、予約を破棄せず到着フレームで入力する。
local gc_delayed = nil  -- { start_lg = <byte>, wait = <ticks>, button = <int> }

-- COUNTED IN TICKS, NOT DISPLAYED FRAMES (v167).
--
-- This used to schedule on globals.current_frame. A displayed frame is about
-- 1.6 game ticks, so "10" meant roughly sixteen ticks and the number on the
-- menu did not mean what it said - while the guard action delay next to it has
-- been in ticks since v140. lg (0xFF8081) advances once per tick, so the wait
-- is measured on it instead and the two settings finally agree.
--
-- >= rather than ==: this runs once per displayed frame and would miss an exact
-- match four times in ten (section 0).
local function service_gc_input_delay()
	if gc_delayed == nil then return end
	if globals.dummy.guard_action ~= 'gc' then
		gc_delayed = nil
		return
	end
	local _el = (memory.readbyte(0xFF8081) - gc_delayed.start_lg) % 256
	-- A reservation that never fired - the guard ended, or the count wrapped -
	-- is dropped rather than left to go off at some unrelated moment later.
	if _el > gc_delayed.wait + 60 then
		gc_delayed = nil
		return
	end
	if _el < gc_delayed.wait then return end

	local _d = player_objects and player_objects[2]
	if _d and _d.pending_input_sequence == nil then
		-- delay_before は使わない（ディレイは fire_frame で制御）。
		-- 空文字列なら make_input_sequence は Neutral を挿入しない。
		local _seq = make_input_sequence("DPF", gc_delayed.button, "", 0)
		if _seq and #_seq > 0 then
			queue_input_sequence(_d, _seq)
		end
	end
	gc_delayed = nil
end

util = require "./scripts/utilities"
-- frameStartedGuarding is written in two places and read in NONE. Left alone
-- rather than deleted because the counter is about to be measured and it is
-- the obvious place to hang "how long was the block" off, but nothing depends
-- on it today.
local frameStartedGuarding = 0
-- (frameEndedGuarding lived here. It was read once, as the counter's
-- attack_frame, and never written - so that attack_frame was always 0 and the
-- queue gate `attack_frame - current_frame <= #sequence + 1` passed on every
-- frame. v191 moved the counter onto the reversal's tick path, which does not
-- use attack_frame at all, so the variable has no reader left.)
local wasJustGuarding = false
local numBlockStunExitInput = 3
local blockStunRunCommand = false

-- Pre-buffered reversal bookkeeping.
--
-- prev_in_stun gives the frame the dummy ENTERS hit/block stun. The motion is
-- armed on that edge and only there, so the Guard Action Frequency roll is
-- taken exactly once per knockdown, the same as before. Arming on every frame
-- of the stun would roll dozens of times and effectively force 100%.
local prev_in_stun = false
local arm_edge     = false
-- True on the same frame as arm_edge when the arm came from the $1a7 character
-- table, which is the only case the tick hook can drive the motion for.
local arm_tick_driven = false
-- Same, for the landing branch, which is timed on ticks_to_landing() instead.
local arm_land_driven = false
-- Hit-stun equivalent of kd_armed/arm_edge. See the note where it is computed.
local hs_armed     = false
local hs_arm_edge  = false
-- Character Specific: the frame side asks, the tick hook places it on free-1.
local csp_pending = false
-- Block stun's own arm edge. It cannot share hs_arm_edge: that one is reset to
-- false further down the same function than the block test sits, so a value
-- written here would be wiped before the queue site ever reads it.
-- ONE TABLE, NOT FIVE LOCALS.
--
-- Lua 5.1 allows a function 60 upvalues and service_held_reversal reached it;
-- every file-level local this function touches costs one. Grouping the block
-- state keeps it to a single upvalue.
--   edge     armed this frame, consumed at the queue site
--   episode  latched for the whole block episode, not just the stun span
--   prev158  $158 as it read last frame, to find the zero edge
--   zero_lg  lg on the tick $158 reached zero
--   lg       lg on the tick the motion was armed
local BLK = { edge = false, episode = false, prev158 = 0,
              zero_lg = nil, lg = nil, lead = nil }

-- THE TWO EVENTS A COUNTER MAY FIRE ON (v192).
--
-- hs_arm_edge on its own is too wide. It is the hit-stun arm, and hit stun
-- covers three different recoveries that $140 tells apart:
--
--     0x0A  knockdown wake-up      <- not a counter
--     0x04  air recovery           <- not a counter
--     other ground hit stun        <- a counter
--
-- $140 ALONE IS NOT ENOUGH (v193).
--
-- v192 tested only $140 and the counter still came out on everything. Counted
-- over every archived batch, on the tick hs_arm actually fires:
--
--     $140=0A  $1a7>0    120     wake-up, labelled
--     $140=00  $1a7>0     78     wake-up, NOT labelled - $140 reads zero
--     $140=04            1297    air recovery
--     $140=00/02/0E  $1a7=0      ground hit stun and block
--
-- So a fifth of the wake-ups reach here with $140 = 0. **$1a7 is the reliable
-- one**: it is the wake-up tally and only counts during a wake-up, which is
-- the whole basis of KD_END_1A7. Tested first for that reason.
--
-- $38 backs up the air case the same way, in case an air recovery ever arrives
-- without $140 = 0x04 - it is the byte dummyState.lua reads for p1_in_air.
local function counter_arm_edge()
	if BLK.edge then return true end
	if not hs_arm_edge then return false end
	if memory.readbyte(0xFF89A7) ~= 0 then return false end
	local _b140 = memory.readbyte(0xFF8940)
	if _b140 == 0x0A or _b140 == 0x04 then return false end
	if memory.readbyte(0xFF8838) ~= 0 then return false end
	return true
end
-- $158 as it read on the previous frame, so the moment it reaches zero can be
-- told from the many frames it stays there.
--
-- BLK.episode is latched for the whole block episode rather than for the stun
-- span. A multi-hit blocked string can blip out of stun between hits, and
-- re-arming there put a SECOND motion into a recogniser that still held the
-- first: the tail of QCF QCF is forward, down, down-forward, which is a dragon
-- punch. Measured by the user as "on multi-hit it turns into Shadow Blade".

-- HOW LONG BLOCK RECOVERY IS, PAST THE POINT $158 REACHES ZERO.
--
-- $158 is a fixed 14 (0x023960) and is spent well before the character is free,
-- so the remainder is what has to be predicted. Measured over 108 block spans,
-- it is decided by the attack's stun class $59 ALONE:
--
--     $59 = 0 (light)    10 ticks   31 of 31
--     $59 = 1 (medium)   15         26 of 31   (13 on the other 5)
--     $59 = 2 (heavy)    19         51 of 51
--
-- v146 also keyed on $121, standing or crouching, from a smaller sample that
-- happened to associate the two - and got heavy-standing wrong as 11. With
-- wait 0 that left 19 ticks of lead against a step timeout of 14 to 19
-- (0x02A55A), so the motion had expired: "single crouching heavy comes out,
-- single standing heavy almost never does". Crouching heavy got wait 7 and
-- worked, which is the same law with the right number. $121 is gone.
--
-- The value is how long to WAIT after the zero edge before arming, chosen to
-- leave about eleven ticks of lead in every case.
-- Guard = Push Block, one entry per strength. The menu carries the strength in
-- the entry itself rather than spending a second row on it.
local GUARD_PUSH_BLOCK = {
	[5] = "light",
	[6] = "medium",
	[7] = "heavy",
}

local BLK_WAIT = { [0] = 0, [1] = 4, [2] = 8 }
local function blk_wait_ticks()
	return BLK_WAIT[memory.readbyte(0xFF8859)] or 0
end

-- HOW MANY TICKS AFTER THE ARM THE CHARACTER IS FREE.
--
-- distance - wait, from the same measurement:
--     light   10 - 0 = 10
--     medium  15 - 4 = 11
--     heavy   19 - 8 = 11
--
-- Everything except light gets eleven; light is one tick tighter because its
-- distance is already inside the window and there is nothing to wait for.
--
-- The dash schedule needs this rather than a constant. v156/v157 placed the
-- release and the first tap at arm+8 and arm+9, which is free-3 and free-2
-- when the lead is eleven but free-2 and free-1 when it is ten - and free-1 is
-- where the release before the second tap goes, so on a LIGHT attack the two
-- collided and the dash lost its gap. Measured by the user as "hard to get out
-- on light, occasionally works".
--
-- Superseded by the guard script (see the arm in the tick hook): BLK.lead
-- holds the distance measured at the arm, and this table is only what is left
-- when the script cannot be read.
local BLK_LEAD = { [0] = 10, [1] = 11, [2] = 11 }
local function blk_lead_ticks()
	if BLK.lead ~= nil then return BLK.lead end
	return BLK_LEAD[memory.readbyte(0xFF8859)] or 11
end
local hs_countdown = nil
local hs_arm_lg    = nil     -- lg when the wait started; see the tick hook

-- Hits taken in the current stun span. $06 dropping to 0x00 is the impact
-- freeze of a new hit (section 8.6.22), so counting its rising edges counts
-- the hits - a chain combo is one span with several of them.
--
-- Declared here, above every hook: a local declared further down is not in
-- scope for a closure created earlier, so it would silently read as a nil
-- global. luac does not catch that.
local hit_count   = 0
local hit_prev06  = nil

-- Frame trap gap, measured in TICKS. playerObject.lua used to take this with
-- emu.framecount(), which counts DISPLAYED frames - about 1.6 ticks each - so
-- a 3 tick gap and a 4 tick gap both printed as 2. The edge is the same one it
-- watched ($8805 == 2, P2 in hit or block stun); sampling it in the tick hook
-- is what makes the number the one the game itself counts.
local trap_stun   = nil
local trap_end_lg = nil

-- EMULATOR PACING.
--
-- The game itself is deterministic, but the pre-buffered motion is delivered
-- one entry per Lua FRAME CALLBACK (joypad.set), while everything it is timed
-- against is counted in game ticks. If the emulator falls behind and a
-- callback covers more ticks than usual, the motion stretches and the second
-- direction is held longer - which is exactly how these failures look.
--
--   lag_ticks_max   most game ticks ever seen between two callbacks
--   lag_slow        callbacks that covered 3+ ticks
--   lag_ms_max      longest wall-clock gap between callbacks, if os.clock
--                   is available (it is standard Lua, but guard it anyway)
local lag_ticks_max = 0
local lag_slow      = 0
local lag_frames    = 0
local lag_ms_max    = 0
local lag_prev_clock = nil
local hs_0c_armed  = false
local hs_throw_armed = false
local hs_ready       = false
local hs_ready_wait  = 0       -- ticks spent waiting for the recogniser to clear
local hs_tick_count  = 0       -- ticks seen since the last displayed frame
local hs_ticks_per_frame = 1   -- measured, see the note at the countdown
local hs_last_deliver_f = nil
-- Lever bits to push in for one tick to finish an abandoned motion, or nil.
-- See the note where it is set.
-- Queue of {lev, btn} pairs, one per tick, that finishes an abandoned motion.
local hs_flush_q = {}

-- Displayed frames that must pass between one delivery of the motion and the
-- next, so an abandoned attempt cannot corrupt the fresh one.
--
-- When a new hit interrupts a motion that has already put forward and down
-- in, the recogniser is left parked on its down-forward step with 14-19 ticks
-- still on the clock (0x02A55A). That step is satisfied by a bitwise AND, not
-- an equality:
--
--     02A51A: and.w D1, D0      ; pressed edge AND required mask
--     02A51C: bne  $2a580       ; non-zero -> SUCCESS
--     02A520: bra  $2a57a       ; zero -> FAIL
--
-- so the FORWARD of the next attempt (0x02) satisfies a down-forward step
-- (0x06) on its own. The stale command completes mid-stun, is thrown away
-- with it, and clears the work block - after which the new attempt's DOWN
-- arrives at step 0, which wants forward, and fails. The dragon punch is
-- desynced from there on. Measured: two-hit spans with a short final lead,
-- 36 reversal / 7 nothing, and both failures examined show exactly this.
--
-- 20 is one more than the longest step timeout, so the stale block has always
-- expired and reset itself before the new forward goes in.
-- Ticks a delivery must be kept clear of the previous one, and of a flush.
-- 16 rather than 20: 16 measured 32/4 while 13 measured 1/8, and a larger
-- value pushes the fresh motion closer to the actionable tick than the
-- shortest leads can afford.
local HS_STALE_CLEAR = 16

-- HOW LONG TO WAIT BEFORE QUEUEING THE HIT-STUN MOTION.
--
-- Not a constant: it has to scale with the length of the stun, because what
-- actually matters is how long the motion sits parked on its second-to-last
-- entry waiting for the final direction. The recogniser's step timeout is
-- 14-19 ticks and is re-rolled per step (0x02A55A), so a hold near that
-- length fails at random - which is exactly the reported symptom, reversals
-- coming out against light and medium attacks and only sometimes against
-- heavy ones.
--
-- Measured (v42 batch, 33 hit-stun recoveries, ticks from $06 going 0x00 ->
-- 0x02 to the actionable tick), against a flat 6-frame wait:
--
--     lead 14  hold  6 ticks   16 reversal /  0 nothing
--     lead 19  hold 11 ticks    6 reversal /  0 nothing
--     lead 23  hold 15 ticks    4 reversal /  7 nothing
--
-- $56 predicts the lead exactly. Every one of the 33 fell into one of three
-- classes and the byte never disagreed:
--
--     $56 = 0 -> lead 14      $56 = 1 -> lead 19      $56 = 2 -> lead 23
--
-- It is also stable for the whole stun in all 33, so it is not scratch being
-- read at a lucky moment. ($54, the documented hit type, does NOT separate
-- them - value 1 covers all three leads.)
--
-- The waits below are lead - 14 + 6, i.e. they give every class the same
-- 6-tick hold that measured 16 of 16.
-- ARMING CONSTANTS (keyed on $59) = THE MEASURED LEADS, UNBIASED.
--
-- 0x075E2C copies $59 out of the attack's own row in the table at 0x0764EA,
-- so for a ground normal it IS the light/medium/heavy distinction. Measured
-- over 82 spans it gives the lead exactly, 82/82: 14 / 19 / 23.
--
-- These were 17 / 22 / 26 for a while - the measured values plus 3. That bias
-- was fitted against batches that were ALL recorded with run-ahead on, which
-- was not noticed at the time (489 of 490 archived attempts, section 8.6.70).
-- It is a run-ahead compensation, not a property of the game:
--
--     countdown = lead - (HS_TARGET_HOLD + 1) - ticks_per_frame
--     forward lands at   free - (lead - constant + 7 + ticks_per_frame)
--
-- With run-ahead OFF, ticks_per_frame is 1, so the unbiased constant puts the
-- forward at free-8 for every class, and the +3 version puts it at free-5 -
-- outside the band that was measured to work (free-9 .. -15). The bias only
-- made sense while a displayed frame covered 2-3 ticks and stretched the
-- delivery. Off, it overshoots.
local HS_LEAD_BY_59 = { [0] = 14, [1] = 19, [2] = 23 }

-- SPECIAL HURT REACTIONS GET A SECOND, LATER ARMING POINT.
--
-- Moves like Chaos Flare put the dummy in a much longer stun, and $56 cannot
-- see it: those spans read $56 = 0, the same value as a light attack, while
-- lasting 42 ticks instead of 14. Arming off $56 there delivers the motion
-- about 28 ticks early and it always expires - measured 0 of 16.
--
-- They are distinguishable by structure rather than by a strength byte. $07
-- runs 0x02 -> 0x0C -> 0x04 -> 0x00 through them, and the 0x0C sub-phase does
-- not occur at all in the short spans:
--
--     lead 14 / 19 / 23   $07 = 0x0C never appears   (11 / 7 / 5 spans)
--     lead 42             $07 = 0x0C appears, starting at free-21, 16 of 16
--     lead 62             $07 = 0x0C appears, starting at free-41, 1 of 1
--
-- So 0x0C is both the marker for "this is a long reaction" and a clock in its
-- own right. Arming again when it appears replaces the wrong $56-derived
-- timing with one measured from 21 ticks out.
--
-- The 41 entry is a SINGLE sample and is marked as such - it is here only
-- because falling back to 21 for that class is certainly wrong, not because
-- one observation is a measurement.
-- LONG HIT-STUN: ONE CONSTANT, AND IT IS A COMPROMISE.
--
-- The table this replaced was keyed on $56, which is now known not to
-- separate anything reliably (section 8.6.55), and its values came from a
-- batch where the 0x0C lead measured a steady 21. Over 21 spans it is not
-- steady - it is bimodal, 9..13 and 19:
--
--     lead  9:2  10:3  11:1  12:3  13:1  19:11
--
-- and an exhaustive search over the object found nothing that predicts it
-- (worst within-value spread 8 or more for every byte). 21 spans is too few
-- to fit anything to, so this stays a constant until there is more data.
--
-- With lead L the forward lands (real - L + 8) ticks before free, and the
-- band is about 8..15, so L covers reals L..L+7. 12 covers 12..19, which is
-- 15 of the 21 observed; the previous 21 covered none of them, which is the
-- 4/21 that was measured.
-- 19, THE MODE, NOT 12.
--
-- 12 was chosen when 21 spans made the long reaction's lead look bimodal at
-- 9..13 and 19, and it was chosen to straddle them. At 55 spans (run-ahead
-- off) that shape is gone - it is one cluster with a long tail:
--
--     14:3 15:3 16:1 17:4 18:4 19:11 20:15 21:4   45 spans, 82%
--     24:1 28:2 32:2 38:1 39:3                     9 spans, the tail
--
-- so the same rule the rest of the tool now follows applies here: make the
-- constant the measured lead. 19 puts the forward at free-8 for the cluster,
-- which is the position hit stun scores 85/85 from. The tail is left to the
-- periodic re-arm, which is what already covers it - nothing predicts which
-- spans land there (section 8.6.74), so nothing else can.
-- BACK TO 12, AND THE REASON MATTERS.
--
-- 19 measured 0/18, and not by mistiming: every one of the 18 had $318 empty
-- at the actionable tick, meaning nothing was delivered at all. The countdown
-- is lead - 8, so 19 gives 11 - one MORE than HS_0C_REARM. Each re-arm reset
-- the countdown a tick before it would have fired, so after the first motion
-- nothing ever went in again. Starvation, not a lead error.
--
-- CONSTRAINT: HS_0C_LEAD_DEFAULT - (HS_TARGET_HOLD + 1) - hs_ticks_per_frame
-- must stay BELOW HS_0C_REARM, or the re-arm starves itself.
local HS_0C_LEAD_DEFAULT = 12

-- Ticks between repeated 0x0C arms. Short enough that the newest motion is
-- always well inside the 14-19 tick step timeout when the transition lands,
-- long enough not to thrash. See the re-arm block.
-- ARM THE LONG REACTION OFF THE STUN TIMER, NOT A PERIOD.
--
-- $15c is the stun timer itself: 0x026100 does subq.w #1 on it every tick,
-- 0x0260D8 and 0x0260FA subtract a RANDOM amount whenever new direction or
-- button input appears, and 0x02610A clears it and recovers when it goes
-- negative. That is the lever-mashing escape.
--
-- Measured over 56 long reactions, $07 leaves 0x0C exactly 2 ticks before the
-- actionable tick, 56 of 56, and $15c reaches 0 one or two ticks before it. So
-- the distance to free is $15c + 2, and since $15c never increases, that is an
-- UPPER BOUND on the time remaining - which is all the arming needs.
--
-- Arming at $15c == 10 puts the forward around free-10, inside the free-9..-15
-- band that measured 70/0. The periodic re-arm it replaces is deleted, and
-- that is the more important half of this change: the re-arm pushed forward
-- and down every 10 ticks, and every one of those inputs took a random amount
-- off $15c. The tool was mashing its own target out of the stun and then
-- failing to predict the recovery it had itself randomised.

local HS_0C_REARM = 10

-- Air recovery ($140 = 0x04). See where it is used.
-- Biased to the SHORT end of the measured range (35-40), not the middle.
-- The tolerance is asymmetric: across 152 recoveries every hold from 1 to 11
-- ticks produced a reversal, while a delivery that lands at free-1 or free-2
-- has no room for the motion at all and always fails. Aiming early costs a
-- longer hold, which the data says is free; aiming late costs the attempt.
-- Raised 34 -> 37 (v74). The real lead varies 35-41 ticks while this is one
-- constant, so what actually matters is where the forward ends up:
--
--     forward at free-12 .. -15   28 reversal /  0 nothing
--     forward at free-16          3 /  4
--     forward at free-17          3 /  9
--     forward at free-18 .. -20   3 /  4
--
-- With the wait now measured in real ticks, forward lands at
-- (real lead - countdown), so 37 puts the whole 35-41 range at free-9 .. -15.
-- Erring toward the late end of that band is safe: a shorter hold has never
-- failed (section 8.6.42), a long one times out of the recogniser.
-- AIR RECOVERY'S LEAD IS NOT A CONSTANT - IT IS HOW FAR THERE IS LEFT TO FALL.
--
-- Measured over 109 air recoveries, the lead from the arming marker to the
-- actionable tick runs continuously from 35 to 45 with no classes in it, and
-- it tracks the character's height ($14, the Y word) almost exactly:
--
--     lead = 0.094 * Y + 31.6      residual 0 in 102 of 109, +-1 in the rest
--
-- No constant can cover a 10-tick spread against a band about 7 wide, which
-- is why every value tried (34, 37, 40) fixed one end and broke the other.
-- Reading the height instead makes it exact, the same way $59 made hit stun
-- exact - the difference being that hit stun has discrete classes and this is
-- a continuous quantity.
--
-- Integer form: 32 + Y*3/32 is within a tick of the fit across the whole
-- observed range (Y 46..149).
-- TICKS UNTIL THIS OBJECT LANDS, BY RUNNING THE GAME'S OWN PHYSICS.
--
-- 0x0273E2 is the routine every airborne state calls, and the wake-up handlers
-- of Demitri, Felicia and Bishamon end on its result:
--
--     0273F2  move.l ($4c,A6), D0      Y acceleration
--     0273F6  add.l  D0, ($44,A6)        -> Y velocity
--     0273FA  move.l ($44,A6), D0
--     0273FE  add.l  D0, ($14,A6)        -> Y position
--     027402  tst.w  ($44,A6)          only test while falling
--     027406  bpl    $27410
--     027408  move.w ($14,A6), D0      Y position, high word
--     02740C  cmp.w  ($3a,A6), D0        against the floor
--
-- Two things to read off that. The add is a LONG and the compare is a WORD, so
-- $14, $44 and $4c are 16.16 fixed point and the floor test uses the integer
-- part. And the compare only runs when $44 is negative, so falling is NEGATIVE
-- Y velocity and the character has landed once Y drops below $3a.
--
-- Everything here comes from memory, so this is character-independent: it is
-- the same arithmetic the game runs, not a fit to one character's numbers.
-- Returns nil when the object is not on a descending path, which is the signal
-- to fall back on the animation-timer rule.
local function ticks_to_landing()
	local function _sdw(_a)
		local _v = memory.readdword(_a)
		if _v >= 2147483648 then _v = _v - 4294967296 end
		return _v
	end
	local _y  = _sdw(0xFF8814)
	local _vy = _sdw(0xFF8844)
	local _ay = _sdw(0xFF884C)
	local _g  = memory.readword(0xFF883A)
	if _g >= 32768 then _g = _g - 65536 end
	-- ALREADY ON THE FLOOR MEANS THERE IS NO LANDING TO PREDICT.
	--
	-- Without this the routine reports "lands in 1 tick" forever for a grounded
	-- character, because y is already below the floor. That is what killed
	-- Morrigan in v100: her ld read 1 on every tick of the wake-up, so the
	-- landing branch always won and the $21 branch it actually needs was never
	-- reached. 0/18.
	--
	-- Morrigan's handler is at 0x039112 and it does not consult the floor at
	-- all - $07 == 2 goes straight to tst.b ($21,A6) / bpl, and 0x0391AA
	-- clears $44, $48 and $4c to zero when the wake-up starts. She is grounded
	-- and motionless by construction.
	if math.floor(_y / 65536) < _g then return nil end
	for _t = 1, 60 do
		_vy = _vy + _ay
		_y  = _y + _vy
		-- The ROM only compares against the floor while $44 is negative
		-- (0x027402 tst.w / bpl), so a rising object is not "about to land".
		-- math.floor matches the 68000 taking the high word of a signed long.
		if _vy < 0 and math.floor(_y / 65536) < _g then return _t end
	end
	return nil
end

local function air_lead_now()
	local _y = memory.readword(0xFF8814)
	if _y >= 32768 then _y = _y - 65536 end
	if _y < 0 then _y = 0 end
	local _lead = 32 + math.floor(_y * 3 / 32)
	if _lead < 20 then _lead = 20 end
	if _lead > 60 then _lead = 60 end
	return _lead
end


-- THROW ESCAPE ($140 = 0x0E). A fifth recovery variant, and the last one the
-- tick hook was still excluding - it measured 0 of 15 purely because of that.
--
-- The span opens with $05 = 0x06 ("Be Thrown"), then $05 becomes 0x02 and
-- $140 becomes 0x0E together, and it ends on the ordinary signature. The
-- clock is the tightest of the lot: $140 turning 0x0E sat at free-36 in 14 of
-- 14 (the fifteenth span was truncated by the window, not a different value).
-- SUPERSEDED (v95): the throw escape arms off $21 now. Kept as a record
-- of the measurement - 33 was Morrigan's, and only Morrigan's.
local HS_THROW_LEAD = 33
local HS_TARGET_HOLD = 6
local HS_DELIVER_AFTER = 6   -- fallback for an unseen $56, = the v42 behaviour
local kd_armed     = false
-- 直近の arm が着地系だったか。着地系のラッチだけ解除できる。
local kd_armed_by_land = false

-- Set when a motion has been pre-buffered for the current knockdown, cleared
-- once the dummy is fully idle again.
--
-- Without it the reversal branch below queued a SECOND motion on the trigger
-- frame, on top of the pre-buffered one that had just fired. Measured: four
-- of nine reversals ran the motion twice, and all four produced the wrong
-- special. The join is the reason - the tail of the first pass and the head of
-- the second read down, down-back, back, which is a quarter circle, so the
-- dummy answered with a fireball instead of a dragon punch. The three that ran
-- the pre-buffered motion alone all produced the right move.
local prebuffer_used = false

-- How far into the knockdown to enter the motion.
--
-- 0xFF89A7 climbs by one per game tick while the dummy is down and reaches
-- 0x1A-0x1B on the exact frame the reversal window opens. Measured on eleven
-- logged knockdowns across two sessions it was 0x1B at the trigger in nine of
-- them and 0x19-0x1A in the other two, so it is a reliable clock for "the
-- wake-up is about to happen" - which nothing else in the object provides.
--
-- Arming at 0x15 leaves three to five displayed frames: enough to walk through
-- a dragon punch motion and still finish a few ticks BEFORE the button, which
-- is what the move needs, while staying well inside the ten ticks an input
-- remains live. Entering it any earlier risks the first direction expiring,
-- and it cannot be re-entered to refresh it - see the note in
-- process_pending_input_sequence about doubled motions being rejected.
-- Arming point for an ordinary wake-up, as a knockdown-clock value.
--
-- RAISED from 0x15 (21) to 23. $1a7 == 21 is free-7 and put the motion's
-- FORWARD on free-6 or free-7 - which is exactly where a head-crossover flips
-- the resolved facing. Measured over 46 crossover knockdowns the flip lands on
-- free-5 (23 of them) or free-6 (21), and the outcome was an even 23/23 split
-- depending on which side of it the forward happened to fall:
--
--     facing steady through delivery   23 reversal /  0 nothing
--     facing changed during delivery   23 reversal / 23 nothing
--
-- and the failures show the mirroring directly - forward going in as raw 2
-- while the resolved facing already reads 1, or the final direction landing
-- as down-BACK instead of down-forward.
--
-- Two ticks later puts the whole motion after the flip in every case
-- observed. It costs margin: the hold drops to about 2 ticks, which the data
-- says is fine (holds of 1 and 2 both produce reversals - section 8.6.42),
-- but there is less room if a delivery is slow. If this regresses the
-- non-crossover knockdowns, put it back to 0x15 - those measured 23/23.
-- 着地系の arm 位置。free-5 相当。
-- HOW EARLY TO ARM = HOW LONG THE COMMAND IS, PLUS SLACK.
--
-- A fixed constant only ever fits one command. DPF is three entries and the
-- controller delivers one per displayed frame, so arming at free-6 leaves
-- three spare ticks - and that measured 32/34 on Bishamon's rolling wake-up,
-- against 12/23 at free-5. But HCF is FIVE entries, and the same free-6 would
-- be two ticks short before the motion even finished going in.
--
-- Entry counts, from make_input_sequence() in controller.lua:
--
--     forward / back / down / up / the diagonals    1
--     HCharge, VCharge                              2
--     QCF, QCB, DPF, DPB, back dash, forward dash   3
--     HCF, HCB                                      5
--     360, DQCF                                     6
--     720                                          11
--
-- SLACK is why free-6 works for a 3-entry command and free-4 does not: a
-- delivery frame sometimes produces no new entry (section 8.6.138), and the
-- spare ticks absorb it. Three has measured well; it is not tuned beyond that.
--
-- The cap matters for the long ones. The recogniser times a step out after
-- 14-19 ticks (section 8.6.25), so the first entry must not go in more than
-- ~14 ticks before the last. 720 at 11 entries is already at that limit and
-- cannot be given slack on top, hence the clamp.
-- 1 -> 2: absorb the delivery lag, which is not constant.
--
-- v120 cut this from 3 to 1 because the motion was finishing early and the
-- held direction was gone by the injection point. That was the right
-- direction and it fixed the long reaction (48% -> 86%), but for the wake-up
-- it went one step too far. Measured on 33 spans with the arm firing at
-- free-3 every time:
--
--     lag from arm to first entry:  0 ticks x8, 1 x16, 2 x7
--
--     delivery starts free-3   8/8   100%
--     delivery starts free-2   8/16   50%
--     delivery starts free-1   0/7     0%
--
-- The arm is in the right place; what varies is how long the controller takes
-- to put the first entry out. With the arm at free-3 a two-tick lag lands the
-- whole motion on free-1, where nothing can complete.
--
-- 2 puts the arm at free-4, so the spread lands on free-4..-2 instead of
-- free-3..-1. free-4 has not been measured - the honest position is that this
-- moves the worst case from 0% to 50% and the best case stays at 100%, rather
-- than that it is optimal. 3 would put the worst case on free-3, but that was
-- the value that was failing before v124 removed the wasted deliveries, so it
-- is not a step to take blind.
local KD_SLACK = 2
local KD_ARM_MAX = 14

-- HOW MANY ENTRIES THE CHOSEN MOTION HAS.
--
-- Asked of make_input_sequence rather than kept in a table beside it. The
-- table this replaces had drifted: the super jumps were never added to it and
-- fell back to 3 while the real sequence was 2, and DQCF sat in it long after
-- the menu entry was commented out. Nothing kept the two in step, and nothing
-- ever would have - a motion is added in one file and the count lives in
-- another.
--
-- The button and the delay do not change the count: the button is appended
-- into the LAST entry, and the delay is applied elsewhere. So "none" and 0
-- give the entry count of the motion itself.
--
-- Cached because this runs from the arming path, and an unknown motion prints
-- a warning inside make_input_sequence that is worth seeing once rather than
-- every frame.
local _seq_len_cache = {}
local function seq_len(_stick)
	-- THE SEQUENCE GUARD ACTION IS NOT NAMED BY A STICK (v300).
	--
	-- Every arm below sizes its window from the motion's length, asked for by
	-- the stick name. A compiled sequence has no stick name and its first
	-- segment can be any length, so it has to be asked directly - and before
	-- the cache, which is keyed on a name that would not distinguish it.
	if globals and globals.dummy and globals.dummy.guard_action == 'sequence' then
		local _sn = actionSequenceRunnerModule.first_len("reversal")
		if _sn ~= nil then return _sn end
	end
	if _stick == nil then return 3 end
	local _n = _seq_len_cache[_stick]
	if _n ~= nil then return _n end
	local _ok, _seq = pcall(make_input_sequence, _stick, "none", "", 0)
	if _ok and type(_seq) == "table" and #_seq > 0 then
		_n = #_seq
	else
		_n = 3
	end
	_seq_len_cache[_stick] = _n
	return _n
end

-- WHERE A GUARD ACTION'S INPUT COMES FROM (v300).
--
-- The paths below used to call make_input_sequence directly. The sequence
-- guard action is a second source - the editor's steps, compiled - and it has
-- to enter at exactly these points, or it would run on machinery that was
-- never measured against it.
--
-- Only the FIRST segment comes back. That is the one the arm places on the
-- actionable tick, which is the only tick this file has been tuned for. The
-- rest wait for the dummy to be able to act, and the runner hands those over.
--
-- Falling back to make_input_sequence when there is nothing to compile is what
-- makes a one-step sequence identical to the ordinary reversal rather than
-- merely similar: with one step there is one segment, and the list handed over
-- is byte for byte the list make_input_sequence would have built.
-- WHAT THE ARM IS AIMING WITH (v300).
--
-- The arm does not only need the input list. It asks what the motion IS - to
-- decide whether the press sits on free+0 or free+1, which dash Auto should
-- read, whether a release is needed - and it asks which button to put in when
-- an entry carries none. Every one of those questions used to be answered by
-- the Reversal Input Motion and Button rows.
--
-- In sequence mode those rows describe something the dummy is not doing, and
-- the button one is actively harmful: a jump carries no button, so the "if the
-- entry has none, use the configured one" fallback ORed an unrelated press
-- onto it and the dummy jumped AND attacked. There is nothing to fall back to
-- here - a step that presses nothing presses nothing.
-- A GLOBAL, DELIBERATELY. Lua 5.1 allows a function 60 upvalues and
-- service_held_reversal already sits at exactly that, so any new file-local it
-- touches stops the file compiling. A global is read with GETGLOBAL and costs
-- no upvalue at all, which is why this one table is not a local.
guard_action_input = {}
local GA = guard_action_input

function GA.stick()
	if globals.dummy.guard_action == 'sequence' then
		local _m = actionSequenceRunnerModule.first_motion("reversal")
		if _m ~= nil then return _m end
	end
	return globals.dummy.counter_attack_stick
end

function GA.button()
	if globals.dummy.guard_action == 'sequence'
	   and actionSequenceRunnerModule.first_motion("reversal") ~= nil then
		return actionSequenceRunnerModule.first_button("reversal") or "none"
	end
	return globals.dummy.counter_attack_button
end

local function ga_sequence(_stick, _button, _delay_type, _delay)
	if globals.dummy.guard_action == 'sequence' then
		local _seq = actionSequenceRunnerModule.arm("reversal")
		if _seq ~= nil then return _seq end
	end
	return make_input_sequence(_stick, _button, _delay_type, _delay)
end

-- Ticks before the actionable tick to arm the LANDING branch. Returns the
-- value KD_LAND_ARM used to be: the arm fires when ticks_to_landing() reaches
-- it, which is one tick earlier than the distance to free.
local function kd_land_arm()
	local _n = 3
	if globals and globals.dummy then
		_n = seq_len(globals.dummy.counter_attack_stick)
	end
	-- WIDER SINCE v132, BECAUSE ARMING IS NO LONGER THE TIMING DECISION.
	--
	-- This used to be entries + KD_SLACK - 1, sized so the motion would finish
	-- exactly on the landing, because the motion started at the arm. The tick
	-- hook now holds every entry back until ld counts down to it, so all this
	-- has to do is get the sequence queued before ld reaches #entries. Four
	-- ticks of slack is several frames at 1.6 ticks per frame; the old value of
	-- 4 for a three-entry motion left exactly one tick, and Demitri's single
	-- failure on the v131 batch armed at ld = 4 and only got two entries in.
	local _v = _n + 4
	if _v > KD_ARM_MAX then _v = KD_ARM_MAX end
	if _v < 2 then _v = 2 end
	return _v
end
-- The animation branch has to scale with the command too.
--
-- kd_land_arm() already does this for the landing branch, but KD_CEL_ARM was
-- left at a fixed 4 - which is free-6, and free-6 only fits a 3-entry command.
-- Bishamon's ordinary wake-up runs through the animation branch (his handler
-- at 0x042F2E dispatches $07 == 2 to tst.b ($21,A6) / bpl, same shape as
-- Morrigan's), so with HCF at 4 entries or a 360 at 6 the motion cannot finish
-- going in before he is actionable.
--
-- $20 counts down inside the final cel, so gating on it at (entries + 1) puts
-- a 3-entry command at free-6 exactly as before and gives longer ones the room
-- they need.
-- WHERE EACH CHARACTER'S WAKE-UP ENDS, ON THE $1a7 CLOCK.
--
-- $1a7 counts up exactly one per tick for every character (section 8.6.83), so
-- if the value it ends on is known, the distance to the actionable tick is
-- known too - which the $21/$20 route cannot give, because the length of the
-- final animation cel differs per character. Gallon's $21 turns 0x40 only two
-- ticks before he is actionable, which is not enough room for a three-entry
-- motion; Morrigan gets five.
--
-- Measured over every archived recording, at the tick before the character
-- becomes actionable. The key is the character id ($382) and the $07 the
-- wake-up STARTED with (0x02 ordinary, 0x04 rolling, 0x06 a third form Victor
-- has):
--
--     Morrigan  2 -> 27 (275 spans)   4 -> 47 (94)
--     Lilith    2 -> 27 (198)         4 -> 47 (11)
--     Bishamon  2 -> 23  (89)         4 -> 30 (270)
--     Victor                          6 -> 30 (19+13)
--     Gallon    2 -> 29  (17+22)
--     Zabel     2 -> 22  (12+20)
--     Sasquatch 2 -> 23   (2+18)
--     Anakaris  2 -> 27  (20)
--
-- Every one of those is a single value across all its spans. Demitri is the
-- exception - 26 on 178 spans and 28 on 131 - and he is deliberately absent
-- here: he goes through the LANDING branch, which is exact and already scores
-- 24/24, so the table is not consulted for him.
--
-- The second span counts are the v130 batch, which re-measured Gallon, Victor,
-- Zabel and Sasquatch at 22/19/20/18 spans and reproduced every value exactly -
-- including Sasquatch's 23, which until then rested on two samples.
--
-- THE ORDINARY VALUES ARE NOT GUESSES ANY MORE - THE ROM PRODUCES THEM (v132).
--
-- 0x027EC0 loads the wake-up animation from a per-character script list at
-- 0x0BCF7A, and 0x027F70 walks it 24 bytes at a time, +0 being the cel's
-- duration in ticks and +1 its flags (bit6 = last cel). Summing the durations
-- of animation 0x44 and dumping it alongside the recordings:
--
--     Gallon 27  Victor 28  Zabel 20  Morrigan 25
--     Anakaris 25  Bishamon 21  Sasquatch 21  Lilith 25
--
-- and the measured $1a7 terminal is EXACTLY that plus two, for all eight. The
-- +2 is the pair of ticks the wake-up spends in $07 == 0 choosing between the
-- ordinary and rolling forms before the animation is started.
--
-- Demitri is the one character that breaks the law (31 + 2 = 33 against a
-- measured 26/28) and the ROM says why: his handler at 0x03103E does not end
-- on the animation at all -
--     0310CA  tst.b ($21,A6) / bne
--     0310E0  jsr $273e2          <- the LANDING test
--     0310E6  bcc $310fa          <- not down yet, keep waiting
-- so his wake-up ends on physics. That is exactly the 26-vs-28 split, and it is
-- why he is absent from this table and served by the landing branch instead.
--
-- The rolling values do not follow a single law (the roll is animation 0x45/47
-- and then 0x46/48 with a velocity applied in between, and half the roster has
-- its own handler), so those stay measured: Gallon 31, Zabel 38, Anakaris 46,
-- Sasquatch 47, all single-valued over 10-23 spans on the v131 batch.
--
-- This is measured at development time and shipped as data. Making the tool
-- learn it at runtime was considered and rejected: it would make the user
-- spend their own time collecting what can simply be known.
--
-- Unknown character or unknown start value falls back to the $21/$20 rule.
--
-- $07 == 0x06 IS THE SAME WAKE-UP AS 0x04.
--
-- The roll runs $07 through 4 -> 6 -> 2, and which of 4 and 6 is showing on the
-- tick $1a7 first reads 1 is just where the frame boundary fell. Measured on
-- the full-roster batch every character that produced both keys ended on the
-- same value either way - Anakaris 46, Bishamon 30, Morrigan 47, Zabel 38 - so
-- 6 is filled in from 4 rather than left to fall through to the $21 rule.
local KD_END_1A7 = {
	[0x00] = {                            },  -- Bulleta: see the note below
	[0x02] = { [0x02] = 29, [0x04] = 31 },    -- Gallon
	[0x03] = { [0x02] = 30, [0x06] = 30 },    -- Victor
	[0x04] = { [0x02] = 22, [0x04] = 38 },    -- Zabel
	[0x05] = { [0x02] = 27, [0x04] = 47 },    -- Morrigan
	[0x06] = { [0x02] = 27, [0x04] = 46 },    -- Anakaris
	[0x08] = { [0x02] = 23, [0x04] = 30 },    -- Bishamon
	[0x09] = { [0x02] = 28, [0x04] = 33 },    -- Aulbath
	[0x0A] = { [0x02] = 23, [0x04] = 47 },    -- Sasquatch
	[0x0C] = { [0x02] = 15 },                 -- Q-Bee: overridden by KD_END_0A
	-- 0x0B is a SECOND ZABEL SLOT. charMoves.lua's get_character() returns
	-- "Zabel" for both 0x04 and 0x0B, and the animation script list dumped for
	-- it is identical to 0x04's, so the values are 0x04's. Untested in play.
	[0x0B] = { [0x02] = 22, [0x04] = 38 },
	-- 0x12 is Dark Gallon. vsavscriptv2.lua's own check says he "is exactly the
	-- same as regular Gallon", so he gets Gallon's values. Untested in play.
	[0x12] = { [0x02] = 29, [0x04] = 31 },
	[0x0D] = { [0x02] = 29, [0x04] = 30 },    -- Lei-Lei
	[0x0E] = { [0x02] = 27, [0x04] = 47 },    -- Lilith
	[0x0F] = { [0x02] = 24, [0x04] = 39 },    -- Jedah
}
for _cid, _v in pairs(KD_END_1A7) do
	if _v[0x06] == nil and _v[0x04] ~= nil then _v[0x06] = _v[0x04] end
end

-- Q-BEE HAS NO FREE-1 SIGNATURE, AND HER ROLLS SPLIT ON THE ANIMATION.
--
-- Her handler is 0x04A6FA and it is the only one in the game that does not
-- write move.l #$2020400,($4,A6) on the way out:
--
--     04A764  jsr    $27f70.l          step the animation
--     04A76A  tst.b  ($23,A6)          <- $23, not $21
--     04A76E  bpl    $4a7b2            still recovering
--     04A780  tst.b  ($3b4,A6)
--     04A784  bne    $4a7aa            <- the only route to the signature
--     04A7A0  move.l #$2000002, ($4,A6)   <- the normal exit, in one write
--
-- $3b4 reads 0 in play, so 04A7A0 is what runs: $05 and $06 both go to zero
-- together and the intermediate state every other character passes through
-- never exists. Measured, the signature appears on 249 of 250 wake-ups across
-- the other thirteen characters and 0 of 21 on hers.
--
-- So her button cannot be placed by the signature hook and has to come off the
-- clock instead - which is what KD_NO_SIG selects.
--
-- AND THE BUTTON GOES IN ONE TICK LATER THAN EVERYONE ELSE (v162).
--
-- Two positions have been tried and both produced nothing: v160 pressed on the
-- tick her counter reaches its terminal (the trace's free-1, where every other
-- character's button belongs) and v161 pressed one earlier. The motion itself
-- was perfect both times - down, down-forward, forward+button on consecutive
-- ticks - and $06 stayed 0x00 straight through free.
--
-- The reason is WHERE THE INPUT WINDOW IS OPENED. For everyone else the
-- signature at 0x024F0A is followed immediately by
--     024F12  move.b #$5, ($174,A6)
-- so $174 is already open on free-1 and a button pressed there is buffered into
-- the free tick. Q-Bee opens hers in the exit path itself:
--     04A77C  addq.b #5, ($174,A6)
--     04A7A0  move.l #$2000002, ($4,A6)
-- and 0x024E84 runs the handler AFTER the input for that tick has been copied,
-- so on the tick the window opens the recogniser has already looked. A press
-- there has nowhere to sit.
--
-- So her button belongs on the tick AFTER, which is the free tick itself - the
-- same relationship a normal has for everybody (section 8.5). The terminals go
-- back to the measured 15 / 40 / 47 and the final entry is handed to the
-- deferred-press path with an offset of one, which is machinery that already
-- works rather than another constant.
local KD_NO_SIG = { [0x0C] = true }

-- Her three wake-ups are chosen at 0x04A70E by the SIGN OF $a, and that is the
-- key - not $07, and not $27.
--
--     $a == 0   in place                      terminal 15
--     $a  < 0   roll                          terminal 40
--     $a  > 0   roll                          terminal 47
--
-- Measured on 43 spans, without exception. $07 does not separate them ($a > 0
-- turned up with $07 == 2 as well as 4), and $27 - which the ROM does write the
-- animation id into at 0x04A74E - reads 0 on the tick $1a7 first reads 1,
-- because the id is stashed later in the same pass. v161 keyed on $27 and the
-- lookup therefore never matched, which is why the rolls fell through to the
-- $21 rule and produced nothing at all while the in-place wake-up was perfect.
local KD_END_0A = {
	[0x0C] = { zero = 15, neg = 40, pos = 47 },
}

-- $07 as it was when this wake-up began, i.e. on the tick $1a7 read 1. It has
-- to be remembered: by the time the arm point arrives $07 has moved on.
-- $a likewise: its sign is what picks Q-Bee's wake-up.
local kd_start_07 = nil
local kd_start_0a = nil
-- Set once the tick-driven motion has put its final entry in, so the reactive
-- path at the wake-up frame does not queue a second motion behind it.
local kd_motion_done = false

local function kd_end_1a7()
	if kd_start_07 == nil then return nil end
	local _cid = memory.readbyte(0xFF8B82)
	-- Characters whose wake-up length is picked by the sign of $a rather than
	-- by $07. Q-Bee is the only one so far.
	local _c0a = KD_END_0A[_cid]
	if _c0a ~= nil and kd_start_0a ~= nil then
		if kd_start_0a == 0 then return _c0a.zero end
		if kd_start_0a >= 0x80 then return _c0a.neg end
		return _c0a.pos
	end
	local _c = KD_END_1A7[_cid]
	return _c and _c[kd_start_07] or nil
end

-- CAPTURED PER TICK, NOT PER FRAME.
--
-- This used to live in service_held_reversal(), which runs once per DISPLAYED
-- FRAME. Measured on the v130 batch, a knockdown advances about 1.6 game ticks
-- per frame there (2445 tick transitions, 1482 of them crossing a frame
-- boundary), so roughly four ticks in ten are never seen by the frame side -
-- and $1a7 == 1 lasts exactly one tick. When it was missed, kd_start_07 stayed
-- nil, kd_end_1a7() returned nil, and the whole character table was skipped in
-- favour of the $21 fallback: Victor 7 of 19 spans and Gallon 5 of 22 never
-- armed at all, which matches that miss rate.
--
-- Called from the 0x02211A hook, which runs every tick for P2.
-- ONE GUARD ACTION PER RECOVERY.
--
-- kd_motion_done says the knockdown motion has already gone in. It is mirrored
-- onto globals so controller.lua can honour it: measured on the v141 batch the
-- dummy pressed the same button a SECOND time about nine frames after the
-- first, with no seq_queued and no 0xFF8B94_inject in the log, which leaves
-- joypad.set(globals._input) in the master script as the only way it can have
-- reached the game. Nine frames into a light normal is inside its own recovery,
-- and VSAV chain-cancels a normal into itself on a fresh press, so it comes out
-- as a second swing.
--
-- Cleared on a NEW hit rather than only on a new knockdown, so a reversal out
-- of hit-stun straight after a wake-up is still allowed: $05 non-zero with
-- $06 == 0x00 is the impact freeze, which is the same edge the hit-stun re-arm
-- uses (section 8.6.18).
local function kd_set_motion_done(_v)
	kd_motion_done = _v
	if globals ~= nil then globals.kd_action_done = _v end
end

local function kd_capture_start_07()
	local _kd = memory.readbyte(0xFF89A7)
	if memory.readbyte(0xFF8805) ~= 0 and memory.readbyte(0xFF8806) == 0x00 then
		kd_set_motion_done(false)
	end
	if _kd == 0 then
		kd_start_07 = nil
		kd_start_0a = nil
	elseif kd_start_07 == nil then
		kd_start_07 = memory.readbyte(0xFF8807)
		kd_start_0a = memory.readbyte(0xFF880A)
		-- Cleared when a NEW knockdown begins, not when the old one ends.
		-- $1a7 is already back to 0 on the tick the character becomes free, and
		-- the frame callback that reads this flag runs after that tick - so
		-- clearing it on $1a7 == 0 would clear it just before the one frame it
		-- exists to cover.
		kd_set_motion_done(false)
	end
end

local function kd_cel_arm()
	local _n = 3
	if globals and globals.dummy then
		_n = seq_len(globals.dummy.counter_attack_stick)
	end
	-- entries, not entries + 1.
	--
	-- $20 counts 4,3,2,1 repeatedly and $21 turns 0x40 on the final cel, so what
	-- picks the tick is the first $20 at or below this value AFTER $21 flips.
	-- Measured on 138 wake-ups, that is one tick too early:
	--
	--     shippai  $21 flips at free-5, $20 = 4, arms immediately  -> 0 of 9
	--     seikou   same flip, arms at free-4 with $20 = 3          -> 120 of 129
	--
	-- Both traces are otherwise identical; the ones that armed on the flip tick
	-- delivered a tick early and had nothing held by the injection point. One
	-- lower puts every span on the tick the successes used.
	local _v = _n
	if _v > 12 then _v = 12 end
	if _v < 1 then _v = 1 end
	return _v
end

-- MOVED BELOW seq_len (v119, then the table it read became a function).
-- This sat at line 691 while the length lookup is declared above, so the upvalue
-- did not exist yet and the table read as a nil global at runtime:
--   guardCancel.lua:694: attempt to index global 'SEQ_LEN' (a nil value)
-- The table is gone, but the ordering rule it taught still applies.
-- luac -p cannot see it - an undeclared name is a legal global reference.
-- Fourth time this exact mistake has been made in this file; keep any
-- helper that reads the length lookup below it.
-- SCALE WITH THE COMMAND, like every other branch does.
--
-- This was a fixed 8 while kd_land_arm() and kd_cel_arm() both scale with the
-- number of entries. Measured on the long reaction, the four failures all had
-- the delivery running exactly one tick behind the successes:
--
--     seikou   -7: 0002 (forward)   -6: 0004 (down)
--     shippai  -7: 0000             -6: 0002 (forward)
--
-- with otherwise identical traces. $15c is decremented by OUR OWN inputs as
-- well as by the clock (section 8.6.87), so the actionable tick creeps closer
-- while the motion is going in and a threshold with no slack cannot absorb it.
--
-- The distance to free is about $15c + 2 (section 8.6.89), so entries + 7 puts
-- a 3-entry command at free-12 and a 4-entry one at free-13.
--
-- Honest note: this value could NOT be chosen from the logs. Replaying the
-- recorded spans only shifts where the arm lands - the outcome is already
-- fixed in the recording, so no threshold can be scored against it. It needs
-- measuring.
-- WILL THIS HIT END IN A KNOCKDOWN? Read it from $54.
--
-- $54 is copied out of the attack's own data when the hit lands (0x075E20)
-- and 0x02384E dispatches on it through a jump table at 0x02385C. The airborne
-- branch at 0x023A00 is the interesting one:
--
--     023A08  move.b #$4, ($140,A6)      air recovery
--     023A4C  cmpi.b #$4, ($54,A6)
--     023A54  tst.b  ($117,A6)
--     023A5A  move.b #$5, ($54,A6)       <- 4 becomes 5 when $117 is set
--
-- so 4 and 5 share a target because one turns into the other, and 5 is the
-- version that ends on the floor. Measured at the impact freeze over two
-- batches, the separation is total:
--
--     $54 = 4    air recovery   6/6
--     $54 = 5    knockdown      4/4
--     $54 = 64   hit stun      35/35
--     $54 = 73   knockdown     18/18
--
-- Why it matters: a motion delivered for the wrong recovery still occupies the
-- command block for 14-19 ticks, and the real attempt then goes in on top of a
-- busy recogniser. Knowing at hit time that this ends in a knockdown means not
-- delivering the hit-stun motion at all.
--
-- Unknown values return nil, which leaves the old behaviour untouched - the
-- table is what has been observed, not the whole of the ROM's dispatch, so it
-- must fail open.
local KNOCKDOWN_54 = { [0x05] = true, [0x49] = true }
local AIR_54       = { [0x04] = true }
local HITSTUN_54   = { [0x40] = true }

local function hit_ends_in_knockdown()
	return KNOCKDOWN_54[memory.readbyte(0xFF8854)] == true
end

local function hs_0c_arm_at()
	local _n = 3
	if globals and globals.dummy then
		_n = seq_len(globals.dummy.counter_attack_stick)
	end
	-- +3, not +7. Same correction as KD_SLACK: the long reaction was starting
	-- far too early. $15c + 2 is the distance to free, so +3 puts the first
	-- entry about five ticks out for a 3-entry command and the last one on the
	-- actionable tick.
	local _v = _n + 3
	if _v > 16 then _v = 16 end
	return _v
end

local KD_ARM_AT = 23

-- SECOND ARMING POINT, FOR THE ROLLING WAKE-UP.
--
-- A rolling (moving) wake-up runs 20 ticks longer than an ordinary one, and
-- the knockdown clock shows it plainly - measured at free-1:
--
--     $1a7 = 27   ordinary wake-up   lead 7 from $1a7 == 21
--     $1a7 = 47   rolling wake-up    lead 27 from $1a7 == 21
--
-- so arming at 21 delivers the motion 20 ticks too early on a roll and it has
-- always expired by the time the character is actionable: 0 of 12.
--
-- 41 puts the roll back on the same 7-tick lead the ordinary wake-up uses. An
-- ordinary wake-up never reaches 41 (it ends at 27), so this second edge
-- simply never fires for one.
-- Left at its v62 value: 41 measured 18 of 18 on rolling wake-ups, and
-- nothing about the crossover fix below applies to it.
-- 43, so the roll arms at free-4 - the SAME distance the ordinary wake-up
-- arms from, which scores 34/34. The two wake-ups run different lengths on the
-- same clock: $1a7 counts up one per tick and the character becomes free at
-- $1a7 == 27 for an ordinary wake-up and $1a7 == 47 for a roll (43/43 at every
-- offset, section 8.6.74). 41 was free-6; 43 lines the roll up with the case
-- that already works.
-- SUPERSEDED (v92) and kept only as a record of the measurement.
-- The roll now arms off $21/$07 like every other wake-up. 43 was
-- free-4 for Morrigan; it is not free-4 for a character whose
-- wake-up animation runs a different length.
local KD_ARM_AT_ROLL = 43

-- Pit of Blame trigger: a fixed number of frames after entering hit/block
-- stun (status_1 == 0x02), NOT 0xFF8980. See the long history below.
--
-- 0xFF8980 (0 -> 1) was the original trigger, found by sweeping every byte of
-- the three logged regions across 8 marked recordings (10 knockdowns),
-- looking for one that reliably changes shortly BEFORE the knockdown clock
-- (0xFF89A7) starts, and it IS knockdown-specific (reads 0 for a plain hit or
-- block, back to 0 once the knockdown ends, 0 during the intro). It is also
-- one of the five knockdown-residue bytes poke_special() clears.
--
-- REAL INPUT, NOT A POKE. This used to call run_one_frame_special() - i.e.
-- write the move straight into the action byte - after counting 8 frames
-- from the 0xFF8980 edge. That produced inconsistencies, because a poke
-- skips everything the game normally does when a move starts. It now feeds
-- the actual command (DPF + kick) as button presses, and lets the game
-- decide when the move is legal. Consequences:
--   * poke_special's action_slot bypass is no longer needed for this move
--     (that bypass carried a freeze risk - see run_one_frame_special)
--   * a mid-knockdown side switch is handled by queue_input_sequence's
--     existing facing/restart machinery, which a poke never went through
--
-- WHY 0xFF8980 WAS DROPPED AS THE INPUT TRIGGER. A second P1-side
-- measurement (this time recording from the HIT, with Y position, across 7
-- manual knockdowns) showed 0xFF8980 firing 20-24 displayed frames AFTER the
-- dummy's Y position had already returned to the ground - it is a later
-- signal (something like "wake-up eligible"), not landing. The unheld queue
-- fired ON that edge therefore sent its button 23-27 frames after the real
-- landing in every sample - and a human pressing the button that late,
-- confirmed separately on real hardware, does not get the move either. Every
-- one of the 7 human inputs landed at hit+40 to hit+48, i.e. within a couple
-- of frames of the Y-measured landing (hit+45 to hit+50) and 20+ frames
-- BEFORE the 0xFF8980 edge (hit+70 to hit+71) - so the true window sits
-- around real landing, not around 0xFF8980.
--
-- TRIED AND REVERTED before landing on the airborne-landing design below:
--   1. Queued UNHELD, on the 0xFF8980 edge. Showed correctly in P2's own
--      input history but did not produce the move - see the timing finding
--      above for why (23-27 frames late).
--   2. Held (queue_input_sequence's third argument) from the SAME 0xFF8980
--      edge, released 11 frames later. Regressed further: nothing appeared
--      in P2's input history at all, not just the move. Root cause, found
--      later: this held the direction for far longer than the ~10 displayed
--      frames an input stays live for (see HOLD_LIMIT above
--      service_held_reversal) - the direction had gone stale by release
--      time. Not attempted again with a short hold: doing so would run
--      through the SAME release code that services the ordinary kd_armed
--      pre-buffer (the block right after this one, guarded on 0xFF8974),
--      which would then be free to release or drop Pit of Blame's held
--      sequence on a condition that has nothing to do with it. Sending the
--      whole motion unheld, only 3 frames from first direction to button,
--      sidesteps that entanglement entirely.
--   3. Fixed PIT_OF_BLAME_INPUT_DELAY frames after entering stun (status_1
--      == 0x02), no knockdown check at all. Fired correctly on a single
--      knockdown hit, but status_1 == 0x02 is not knockdown-specific: it
--      also went out on a plain hit that did not knock down, and on a
--      chain combo it armed and fired off the FIRST hit in the chain -
--      status_1 stays 0x02 continuously across chained hits with no gap to
--      re-arm on, so the delay counted from the wrong hit and the command
--      was spent before the knockdown blow at the end of the chain ever
--      landed.
--   4. globals.dummy.p2_in_air (byte at 0xFF8800+0x38, the same field
--      p1_in_air mirrors for P1) going 0 -> nonzero -> 0, on the reasoning
--      that only a knockdown launches the dummy and a plain hit or an
--      earlier chain hit does not. Never produced the move at all - this
--      byte most likely tracks the voluntary-jump state machine, not a
--      knockdown bounce, so it probably never went nonzero here and the
--      landing edge this trigger waits for never came.
--   5. Landing edge on globals.dummy.p2_y instead (rise more than
--      PIT_OF_BLAME_AIR_MARGIN above the pre-hit value, then back down to
--      within a few units of it). Also never produced the move - the send
--      still landed too late relative to whatever the real acceptance
--      window turns out to be, even though the Y arc itself matches the P1
--      measurement closely. Approach 3's fixed 28-frame delay from stun was
--      confirmed on real hardware to be the right SEND timing for a single
--      hit; the problem with it was only ever which hit it counted from.
--
-- Current design: PIT_OF_BLAME_INPUT_DELAY frames after P2 is first seen
-- airborne (globals.dummy.p2_y rising more than PIT_OF_BLAME_AIR_MARGIN
-- above where it stood when the current hurt/block span began), fired
-- unconditionally at that point regardless of whether still airborne by
-- then. This started from approach 3's confirmed-good 28-frame delay from
-- stun (stun onset and going airborne are only a few frames apart for a
-- single hit, so the same constant landed the button in the same place
-- there), then measured lower on real hardware - some knockdowns still
-- missed at 28, and PIT_OF_BLAME_INPUT_DELAY is now 22. The point of
-- counting from airborne instead of from stun onset was always about WHICH
-- hit it counts from, not the number itself: on a chain combo the count
-- only starts once the knockdown blow lands, not the first hit of the
-- chain, wherever in the chain it falls. A plain hit, and a chain combo's
-- non-launching hits, never move Y at all, so they never start the count in
-- the first place.
--
-- An air combo restarts the count on every hit it lands while airborne,
-- using 0xFF8944 (the hit counter the combo/hit-count FIX above clears -
-- see the note there) to notice a new hit: any change is treated as a fresh
-- hit and the delay starts over from it, so a multi-hit juggle always counts
-- PIT_OF_BLAME_INPUT_DELAY from its LAST hit, not its first. Not yet
-- confirmed on real hardware that 0xFF8944 climbs for airborne hits the same
-- way it was confirmed to for the grounded chain it was found on.
--
-- FIX (turbo 3): the count is in real game ticks (0xFF8081), not displayed
-- frames. Reported symptom: the move does not come out at turbo 3, except
-- rarely. Turbo 3 runs 4 ticks across 3 displayed frames - the Lua callback
-- this counter used to advance once per call, i.e. once per displayed frame
-- (see the note above service_held_reversal's HOLD_LIMIT for the same
-- turbo-3 mechanism). 22 CALLS is therefore only 22 ticks at normal speed
-- but roughly 22 * 4/3 =~ 29 ticks at turbo 3 - seven ticks later than
-- intended, which fits landing outside the acceptance window this delay was
-- tuned against at normal speed. "Rarely" fits too: how many of the 22
-- callbacks happen to land on a double-tick frame varies, so the overshoot
-- itself varies. Counting the actual 0xFF8081 delta each callback instead of
-- a flat +1 makes PIT_OF_BLAME_INPUT_DELAY mean the same number of real
-- ticks at any speed.
local PIT_OF_BLAME_STICK         = "DPF"
local PIT_OF_BLAME_INPUT_DELAY   = 22
local PIT_OF_BLAME_AIR_MARGIN    = 15
local pit_of_blame_armed         = false
local pit_of_blame_fired         = false
local pit_of_blame_prev_tick     = 0
local pit_of_blame_air_seen      = false
local pit_of_blame_frames        = -1
local pit_of_blame_prev_hits     = 0
local pit_of_blame_ground_y      = 0
-- Result of this knockdown's Guard Action Frequency roll. This trigger sits
-- ahead of the roll in guardCancelCheck, so it has to take its own.
local pit_of_blame_roll   = false

-- Strength dropdown (Light/Medium/Heavy/ES) mapped onto kicks. get_p2_reversal_strength
-- in dummyState.lua returns the raw poke values 0x00/0x02/0x04/0x06 for those
-- four entries; ES is two kicks, matching how the game takes an ES special.
local function pit_of_blame_button()
  local s = globals.dummy.p2_reversal_strength
  if s == 0x06 then return "MK+HK" end
  if s == 0x04 then return "HK" end
  if s == 0x02 then return "MK" end
  return "LK"
end

-- TEMPORARY diagnostic, read-only. MAME's debugger (real Lua 5.1-decrypted
-- 68k disassembly, not the raw-byte capstone attempt from earlier this
-- session that produced garbage) found the actual gate the game itself
-- checks before letting ANY move commit:
--
--   026D64: tst.b ($190,A6)   ; player-object offset 0x190 = 0xFF8990 for P2
--   026D68: bne   $26df8      ; nonzero -> reject path, no move
--
-- The reject path at $26df8 then does "move.b #$1, ($190,A6)" - it SETS this
-- same byte on its way out. A separate, unrelated routine (0x01833A, the
-- general move-input handler - not the reversal-specific one) tests the
-- SAME byte before accepting any input at all, so this is not narrow to the
-- reversal window - it reads as a general "character cannot act right now"
-- latch. Also found: 0x024E7E skips the 0xFF89A7 (knockdown clock) increment
-- entirely while offset 0x194 (0xFF8994) is nonzero, jumping to an
-- unexplored handler at 0x3bb68 instead - a plausible explanation for the
-- 0xFF89A7 plateau observed earlier (reached 0x1B and sat there 40-100+
-- frames instead of continuing to climb or reset).
--
-- Neither address was already hooked anywhere in the scripts (checked - both
-- free slots) and neither is inside debugKnockdown.lua's existing REGIONS
-- sweep (0xFF8800,256 only covers offsets 0x00-0xFF; 0x190/0x194 are past
-- that). Logging only - service_held_reversal() below is untouched.
-- TEMPORARY diagnostic, read-only. THE decisive one - static disassembly of
-- the real (MAME-decrypted) 68k found only 13 instructions in the whole
-- 0x18000-0x40000 range that touch offset 0x174, i.e. the reversal window:
--
--   move.b #$5  at 0x024BE6, 0x024F12, 0x039180   -> window = 5
--   move.b #$a  at 0x022A8C, 0x022C22, 0x026A08, 0x026AD2, 0x026C1E
--   addq.b #5   at 0x025FCA, 0x02CFD2             -> window += 5
--   subq.b #1   at 0x02247E                       -> the per-tick countdown
--   tst.b       at 0x022478                       -> countdown guard
--
-- Old PC-stamped logs show the failing case runs 5 ->(countdown) 4 ->(+5) 9,
-- so the 9 that marks every failure comes from the addq at 0x025FCA. And the
-- three instructions before it are:
--
--   025FBA: bsr    $26058                 ; clear a block of state
--   025FBE: move.b ($120,A6), ($b,A6)     ; INPUT (offset 0x120) -> facing
--   025FC4: move.b #$5, ($143,A6)
--   025FCA: addq.b #5, ($174,A6)          ; window += 5  -> 9
--
-- i.e. the failing path is an INPUT-DRIVEN wake-up. That matches the two
-- measurements: MAME, knocked down by hand with nothing held during wake-up,
-- was the good type 5/5; FBNeo with this tool pre-buffering a direction into
-- the wake-up was the bad type 12/18.
--
-- FBNeo reports the PC AFTER the writing instruction, so expect:
--   pc 0x022482 -> the countdown       (0x02247E)
--   pc 0x025FCE -> addq #5             (0x025FCA)  <- marks the failing path
--   pc 0x024F18 / 0x024BEC / 0x039186 -> window = 5 (the good paths)
--
-- Slot is free: debugKnockdown.lua's own hook for this address is commented
-- out, and the v9 baseline polls 0xFF8974 rather than hooking it.
memory.registerwrite(0xFF8974, 1, function()
	debugKnockdownModule.mark_write("0xFF8974", memory.readbyte(0xFF8974), memory.getregister("m68000.pc"))
end)

-- TICK-ACCURATE BUTTON INJECTION (offline training only - see the warning).
--
-- joypad.set() is one tick late, structurally. The main loop is:
--     008E16: jsr $14E52    input stage 2: builds the input word and stores it
--             014E7A: move.w D2, ($b94,A5)      <- 0xFF8B94, P2's input word
--     008E1C: jsr $91564    game logic, which consumes it:
--             02211A: move.w ($394,A6), ($122,A6)
--     008E2C: bsr $8EB2     input stage 1: reads the HARDWARE ports into
--                           ($58,A5)/($5c,A5) for the NEXT iteration
--     008E30: bra $8E0C
-- Stage 1 sits at the END of the loop and stage 2 at the start, so whatever
-- FBNeo puts on the emulated pad for frame N is not seen by the game until
-- tick N+1. Writing 0xFF8B94 directly, at the moment stage 2 has just filled
-- it, lands the input in tick N itself - exactly one tick earlier.
--
-- That is the entire remaining failure mode: measured on v14, every one of
-- the 5 losses that fell through to the window fallback released on the
-- actionable frame itself, one tick too late. One tick earlier puts them in
-- the 88-100% buckets.
--
-- Note 0xFF8B94 == ($b94,A5) == ($394,A6) for P2 - the global stage-2 output
-- and the player object's input word are the same address. It has exactly one
-- writer in the whole 4MB (0x014E7A) and is consumed at 0x02211A/0x022126,
-- so hooking its write puts us precisely between producer and consumer.
-- P1's equivalent is 0xFF8794 and is not touched.
--
-- Only the BUTTON is injected. The directions are already held by the
-- pre-buffered motion and arrive through the normal path; re-deriving them
-- here would mean reproducing the facing correction at 0x022194, which is
-- pointless risk. Layout of the word: HIGH byte (0xFF8B94) = buttons
-- (bit0 LP, bit1 MP, bit2 HP, bit4 LK, bit5 MK, bit6 HK), LOW byte
-- (0xFF8B95) = lever. Same layout inputHistory.lua decodes at +0x122/+0x123.
--
-- joypad.set() still delivers the same button on the following tick, so the
-- game sees press-then-held rather than two presses - the edge lands on the
-- injected tick, which is what matters.
--
-- WARNING: this is a memory write, not an input. It is fine for offline
-- training (confirmed with the user) but would desync Fightcade netplay.
local P2_INPUT_WORD = 0xFF8B94

local BUTTON_BITS = {
	LP = 0x01, MP = 0x02, HP = 0x04,
	LK = 0x10, MK = 0x20, HK = 0x40,
}

local function button_mask(_name)
	if _name == nil then return 0 end
	local m = 0
	for part in tostring(_name):gmatch("[^%+]+") do
		m = m + (BUTTON_BITS[part] or 0)
	end
	return m
end

-- Lua 5.1 (what FBNeo bundles) has no bitwise operators - same arithmetic
-- style the rest of this codebase uses for bit work.
local function bor8(a, b)
	local r, bit = 0, 1
	for _ = 0, 7 do
		if (math.floor(a / bit) % 2) == 1 or (math.floor(b / bit) % 2) == 1 then
			r = r + bit
		end
		bit = bit * 2
	end
	return r
end

-- Exchange the two facing-relative lever bits (0 and 1), leave the rest.
-- Arithmetic style, like bor8 above - Lua 5.1 has no bitwise operators.
-- No-op on 0, 3 and anything without exactly one of the two bits set, so
-- down/up combinations and non-direction values pass through untouched.
local function swap_facing_bits(_lev)
	local _bit0 = _lev % 2
	local _bit1 = math.floor(_lev / 2) % 2
	if _bit0 == _bit1 then return _lev end
	return _lev + (_bit0 == 1 and -1 or 1) + (_bit1 == 1 and -2 or 2)
end

-- Inject the motion's FINAL DIRECTION too, not just the button.
--
-- This was originally left out on purpose ("the directions arrive through the
-- normal path"), and that turned out to be the whole remaining failure. The
-- lever value one tick after injection separates the two outcomes perfectly
-- over 30 attempts at identical timing:
--       reversal (24):  $123 = 6  = down + forward   (the DP's last direction)
--       nothing  (6) :  $123 = 4  = down only
-- The button was injected on time but the diagonal was still one tick behind
-- it, arriving via joypad.set(), so the motion was incomplete when the button
-- landed and no special could come out.
--
-- The raw/corrected distinction matters here. We write 0xFF8B94/95, which is
-- $394 - the RAW word. The facing swap happens downstream at 0x022194, which
-- exchanges lever bits 0 and 1 when the facing byte $b is set. The observed
-- successes have CORRECTED bit1 (forward), so the raw bit to set is bit1 when
-- $b == 0 and bit0 when it is not. Bit2 (down) is not facing-relative and is
-- written as-is.
local LEVER_DOWN = 0x04

local inject_dir   = nil     -- "DPF" / "DPB" / nil - which diagonal to complete
local inject_mask  = 0       -- button bits to force on the next stage-2 write
local inject_guard = false   -- our own write must not re-enter this hook

-- WHICH FACING TO RESOLVE "forward"/"back" AGAINST.
--
-- Verified against the engine rather than inferred. The special-move forms
-- read $12a (0x029F68, 0x029FAC) and the edges derived from it ($1ac/$1ae at
-- 0x022204/0x022212), NOT $122/$126 - those are what the dash recogniser uses
-- (section 8.6.25). And $12a is corrected under a different gate from $122:
--
--     02218E: tst.b ($b,A6) / beq $221aa      ; $122 uses $b alone
--     0221CC: move.b ($b,A6), D0
--     0221D0: tst.b ($38,A6)  / bne $221e0    ; airborne -> keep $b
--     0221D6: tst.b ($115,A6) / bne $221e0
--     0221DC: move.b ($120,A6), D0            ; otherwise $120
--     0221E0: tst.b D0 / beq $221fa           ; zero -> no swap at all
--     0221E4: ... swap bits 0 and 1 of $12a via the LUT at 0x0221C8 (00 02 01 03)
--
-- $120 IS READ ONE TICK STALE IF TAKEN FROM MEMORY.
--
-- Within a tick the order is:
--     02211A  move.w ($394,A6),($122,A6)   <- this hook injects here
--     022130  bsr $22160                   <- $120 is UPDATED here
--     022134  bsr $2218e                   <- the correction uses the NEW $120
--
-- so anything written at 0x02211A is corrected against a $120 that has not
-- been computed yet. Reading the byte gives the previous tick's value, and on
-- the tick the two characters cross that is exactly the wrong one.
--
-- 0x022160 is short enough to reproduce, which gives the value the correction
-- will actually use:
--
--     022166: move.w ($10,A6), D0
--     02216A: sub.w  ($10,A4), D0      ; D0 = mine.x - opponent.x
--     02216E: bpl $22172 / 022170: moveq #$1,D1   ; D1 = 1 when mine.x < opp.x
--     022172: addi.w #$16, D0
--     022176: cmpi.w #$2c, D0
--     02217A: bls $2218c               ; UNSIGNED - inside +-0x16, $120 is left alone
--     02217C: move.b #$0,($120,A6) / 022186: move.b #$1,($120,A6)
--
-- The deadzone is the part that cannot be guessed: while the two are within
-- 0x16 units, $120 keeps its old value and does NOT follow the X positions.
-- That is why plain "who is on the left" was right on the ground and wrong up
-- close, and why reading the stale byte fails on a walk-through.
local function side_flag_now()
	local _mx = memory.readword(0xFF8810)
	local _ox = memory.readword(0xFF8410)
	if _mx >= 32768 then _mx = _mx - 65536 end
	if _ox >= 32768 then _ox = _ox - 65536 end
	local _d = _mx - _ox
	-- cmpi.w/bls is unsigned, so wrap to 16 bits before comparing.
	if ((_d + 0x16) % 65536) <= 0x2C then
		return memory.readbyte(0xFF8920)      -- deadzone: unchanged
	end
	if _d < 0 then return 1 end
	return 0
end

-- IS THE CHARACTER STILL FACING THE WAY IT CAME?
--
-- $b is the facing the engine corrects a raw direction against, and it only
-- moves when the character actually turns - which happens when it becomes
-- free, not when the two cross over. While $b disagrees with the side the
-- opponent is really on, "forward" points AWAY from them.
--
-- THIS MATTERS FOR DASHES AND NOTHING ELSE. Which way a dash travels is fixed
-- the moment it is granted, so there is nothing to correct afterwards: a dash
-- entered before the turn runs the wrong way for its whole length (user,
-- 2026-09-20).
local function facing_unsettled()
	return memory.readbyte(0xFF880B) ~= side_flag_now()
end

local function facing_for_input()
	if memory.readbyte(0xFF8838) ~= 0 or memory.readbyte(0xFF8915) ~= 0 then
		return memory.readbyte(0xFF880B)
	end
	-- A DASH IS NOT A COMMAND MOTION, AND IT IS NOT CORRECTED LIKE ONE.
	--
	-- $122 is swapped on $b ALONE (0x02218E) while $12a is swapped on $120
	-- when grounded (0x0221DC). side_flag_now() exists because $120 IS
	-- recomputed between the injection at 0x02211A and the correction at
	-- 0x022134, so reading the byte gives the tick before - a $12a problem
	-- only. NOTHING recomputes $b in between, so for $122 the byte is read
	-- outright and there is nothing to reproduce.
	--
	-- MEASURED 2026-09-20, three crossovers, same shape every time:
	--
	--     lg 18   $b=0  $120=1  used=0   injected L2
	--     lg 19   $b=0  $120=1  used=0   injected L2
	--     lg 21   $b=0  $120=1  used=1   injected L1   <- our answer flips
	--     lg 22   $b=1  $120=1  used=1   injected L1   <- $b catches up after
	--
	-- Three different values at once, and the two taps of ONE dash went out as
	-- opposite screen directions while the game's own reference had not moved.
	-- Reported as: dash, Landing, dash - and the second dash does not come out
	-- when the sides swapped during the first one (user, 2026-09-20).
	--
	-- Asked of the sequence being delivered rather than passed down through
	-- twenty-odd call sites: the flag belongs to the command, and this is the
	-- one place any of them resolves a direction.
	local _d = player_objects and player_objects[2]
	local _s = _d and _d.pending_input_sequence
	if _s ~= nil and _s.raw_dir == true then
		return memory.readbyte(0xFF880B)
	end
	return side_flag_now()
end

-- THE LEVER AT THE MOMENT THE BUTTON GOES IN.
--
-- The fourth part of the input description, beside motion, delay and button.
-- Until this existed the press simply inherited whatever direction the motion
-- had ended on, so a dash could only ever produce the dash attack - Bulleta's
-- dash-neutral MP could not be asked for at all, and neither could Zabel's
-- back jump into down MK.
--
-- Applied at the PRESS, never to the motion: the dash's own taps are left
-- alone, so nothing about getting the dash out changes.
--
-- Forward and Back are facing-relative and resolved here, at injection time,
-- because $b flips mid-motion (section 8.6.63) - which is what makes playing
-- on the right side need no separate entries.
--
-- Menu indices: 1 As Is (nil, inherit) / 2 Neutral (0) / 3..10 the eight
-- directions / 11 Character Specific.
local BUTTON_LEVER_DIR = {
	[3]  = { "up" },
	[4]  = { "up", "forward" },
	[5]  = { "forward" },
	[6]  = { "down", "forward" },
	[7]  = { "down" },
	[8]  = { "down", "back" },
	[9]  = { "back" },
	[10] = { "up", "back" },
}

-- Returns the raw lever bits, or nil to inherit whatever the motion ended on.
--
-- Levers only. Picking the special on this line was tried and dropped: the
-- move list carries ids and names with no command data anywhere (every entry's
-- `conditions` is empty), so it could only ever have been the code hack, and
-- that is a different thing wearing the same clothes.
local function button_lever_bits()
	if globals == nil or globals.options == nil then return nil end
	local _i = globals.options.counter_attack_lever
	if _i == nil or _i <= 1 then return nil end
	if _i == 2 then return 0 end
	local _t = BUTTON_LEVER_DIR[_i]
	if _t == nil then return nil end
	local _facing  = facing_for_input()
	local _forward = (_facing == 0) and 0x02 or 0x01
	local _back    = (_facing == 0) and 0x01 or 0x02
	local _lev = 0
	for _k = 1, #_t do
		local _v = _t[_k]
		if     _v == "forward" then _lev = _lev + _forward
		elseif _v == "back"    then _lev = _lev + _back
		elseif _v == "down"    then _lev = _lev + LEVER_DOWN
		elseif _v == "up"      then _lev = _lev + 0x08 end
	end
	return _lev
end

-- Raw lever bits for the final entry of the configured motion, or 0 if the
-- motion has no facing-relative final direction to complete.
local function inject_lever_bits()
	-- The override wins outright. ORing it with the motion's own diagonal
	-- would put two directions in at once.
	local _ov = button_lever_bits()
	if _ov ~= nil then return _ov end
	if inject_dir == nil then return 0 end
	local _facing  = facing_for_input()
	local _forward = (_facing == 0) and 0x02 or 0x01
	local _back    = (_facing == 0) and 0x01 or 0x02
	if inject_dir == "DPF" then return LEVER_DOWN + _forward end
	if inject_dir == "DPB" then return LEVER_DOWN + _back end
	return 0
end

-- Also clear the "holding back" lever bit on the injected tick.
--
-- The actionable wake-up handler does not go free unconditionally:
--     025FEA: bsr $2766a
--     025FEE: bne $27774        <- diverted to the GUARD path, no free this tick
-- and 0x02766A is the block test:
--     02766A: tst.b ($3b2,A6)      / bne $276a6
--     027672: btst  #$0,($12b,A6)  / bne $276a6
--     02767C: btst  #$0,($123,A6)  / bne $276a6   <- lever bit0 = BACK
--     0276A6: (proximity test against the opponent's attack list at $1400,A5)
-- Measured: (status_1 $02, status_2 $04) lasts TWO ticks on 19 of 48 wake-ups
-- and one tick on 22 - the two-tick cases are the ones this gate turned away
-- on their first pass, which is exactly the jitter that stops the actionable
-- frame from being predictable.
--
-- Clearing bit0 of the lever for the single injected tick removes our own
-- contribution to that gate. It cannot suppress a genuine block the player
-- wanted (this is the dummy, mid-wake-up, executing a scripted reversal) and
-- it only lasts one tick. $3b2 and $12b are left alone - they are not ours.
local LEVER_BACK = 0x01


-- One sequence entry -> raw lever bits + button bits.
--
-- RAW, because 0xFF8B94 is $394 and the facing swap happens downstream at
-- 0x022194 (it exchanges lever bits 0 and 1 when the facing byte $b is set).
-- So "forward" is raw bit1 when $b == 0 and raw bit0 when it is not.
local function entry_to_bits(_entry)
	local _lev, _btn = 0, 0
	if _entry == nil then return 0, 0 end
	local _facing  = facing_for_input()
	local _forward = (_facing == 0) and 0x02 or 0x01
	local _back    = (_facing == 0) and 0x01 or 0x02
	for _i = 1, #_entry do
		local _v = _entry[_i]
		if     _v == "forward" then _lev = bor8(_lev, _forward)
		elseif _v == "back"    then _lev = bor8(_lev, _back)
		elseif _v == "down"    then _lev = bor8(_lev, 0x04)
		elseif _v == "up"      then _lev = bor8(_lev, 0x08)
		else _btn = bor8(_btn, BUTTON_BITS[_v] or 0) end
	end
	return _lev, _btn
end

-- THE WHOLE MOTION GOES THROUGH THE INJECTION, NOT joypad.set().
--
-- This hook fires once per TICK, at 0x014E7A, right after input stage 2 has
-- filled 0xFF8B94 and before the game logic consumes it at 0x02211A. That is
-- the only place where a decision and the input it implies can happen inside
-- the same tick. joypad.set() cannot: stage 1 (0x008EB2) sits at the END of
-- the main loop, so anything FBNeo puts on the pad is not seen until the
-- following tick.
--
-- Everything now runs here:
--   * the release decision (was in service_held_reversal, once per DISPLAYED
--     FRAME - which silently skips ticks at turbo)
--   * the motion's directions (were delivered by joypad.set, one tick late,
--     which is what left the diagonal incomplete when the button landed -
--     measured: lever 6 = reversal, lever 4 = nothing, over 30 attempts)
--   * the final button
--
-- joypad.set() still delivers the same entries one tick behind. That is
-- harmless: the game sees our value first and the pad value after, so each
-- input reads as press-then-held and the EDGE lands on the injected tick.
local function try_release_in_hook(_seq, _d)
	-- release_input_sequence is a global from controller.lua, resolved at call
	-- time; this hook only ever runs long after every require has completed.
	if release_input_sequence == nil then return false end
	local _recovery = memory.readbyte(0xFF8940)   -- $140 recovery variant
	local _animctr  = memory.readbyte(0xFF8820)   -- $20  animation counter
	local _sub      = memory.readbyte(0xFF8807)   -- $7   wake-up sub-state
	if _recovery ~= 0x0A or _animctr ~= 0 then return false end
	-- ONE TICK OF WAIT, UNCONDITIONALLY.
	--
	-- The predictor condition is the same one the frame-based version used,
	-- but the input it produces now lands a tick sooner: joypad.set() went
	-- through stage 1 at the END of the main loop, so it was always one tick
	-- behind, and the injection is not. Firing on the same condition therefore
	-- delivers the whole motion one tick early - measured as 20 consecutive
	-- failures, all of the "came out too fast" kind.
	--
	-- One unconditional tick of wait gives that tick back, restoring the
	-- timing v18 measured (2 ticks early = 25/25, 1 tick = 23/28) while
	-- keeping the per-tick decision and the injected directions.
	--
	-- It is unconditional, not "$7 == 2" as before: that split existed to
	-- compensate for joypad.set()'s latency applying unevenly across the two
	-- sub-states, and there is no joypad.set() in this path any more.
	if not _seq.predict_waited then
		_seq.predict_waited = true
		return false
	end
	release_input_sequence(_d)
	return true
end

local hook_ticks = 0

-- Asserts lever/button bits onto the input word 0xFF8B94.
--
-- Pulled out of the registerwrite hook below so the tick-exact release
-- (registerexec on 0x02211A) can put the same bits in place at the precise
-- tick it wants, instead of setting a flag and waiting for the next write.
-- Measured on the v32 batch, that wait cost 0-3 ticks of jitter, which is
-- the whole error budget: the press edge has to land on ONE specific tick.
local function assert_input_bits(_lev, _btn)
	-- NOTHING GOES IN BEHIND THE MENU.
	--
	-- Reported 2026-09-20: with the menu open the dummy stands still, as it
	-- should, but its inputs keep arriving. Of the twenty-eight places that
	-- assert bits, only the two hold paths asked about the menu; the walker
	-- stops because M.service drops the pass, and the ARM's own delivery had
	-- nothing stopping it at all. Present before the Action Pattern work -
	-- confirmed on Reversal - Action Steps (0xB) as well (user).
	--
	-- Asked HERE rather than at the top of the hook. Returning from the hook
	-- would also skip M.service, and that call is what drops a pass when the
	-- menu opens - "the menu ends the run, it does not pause it" would quietly
	-- become "it pauses it".
	if globals ~= nil and globals.show_menu == true then return end
	inject_guard = true
	-- ALWAYS write the base address, even when there is no button.
	--
	-- Measured: during the hold phase the hook wrote only 0xFF8B95 (the lever
	-- byte) and the game's $123 stayed 0x00 on every one of those frames - the
	-- forward and down of the motion never arrived. The single frame that DID
	-- arrive was the release, which is also the only frame that wrote
	-- 0xFF8B94 as well. Writing just the second byte of the hooked range does
	-- not take; writing the base address does (proved separately at 37/37
	-- when the injection was button-only). So write both bytes every time,
	-- ORing in a zero button mask when there is no button to press.
	memory.writebyte(P2_INPUT_WORD, bor8(memory.readbyte(P2_INPUT_WORD), _btn))
	-- REPLACE THE LEVER, DO NOT OR INTO IT.
	--
	-- This used to OR _lev over whatever was already held, with a special case
	-- that dropped left when right was asserted and vice versa. That covers
	-- the left/right axis only, so a held DOWN survived and combined with a
	-- newly asserted BACK into down-back.
	--
	-- It went unnoticed because the dragon punch's last entry IS down-forward:
	-- OR-ing forward onto a held down produces exactly the value the entry
	-- already carried, so the bug was invisible for every command measured so
	-- far. The rotation recogniser at 0x2A1B4 compares with cmpi against the
	-- four cardinals, so a diagonal is rejected outright - measured, the motion
	-- reached position 2 with one step remaining and then died on 0x05.
	--
	-- The entry's own bits are what should be held, so assign them.
	local _cur = _lev
	memory.writebyte(P2_INPUT_WORD + 1, _cur)
	-- Belt and braces: re-assert the whole thing as a single word write, the
	-- same shape the game itself uses at 0x014E7A (move.w D2,($b94,A5)). If
	-- the byte writes above are what fails, this one still lands; if they
	-- work, this writes back the identical value and changes nothing.
	memory.writeword(P2_INPUT_WORD,
		memory.readbyte(P2_INPUT_WORD) * 256 + memory.readbyte(P2_INPUT_WORD + 1))
	inject_guard = false

	debugKnockdownModule.mark_write("0xFF8B94_inject", memory.readbyte(P2_INPUT_WORD),
		memory.getregister("m68000.pc"))
	debugKnockdownModule.mark_write("0xFF8B95_lever", memory.readbyte(P2_INPUT_WORD + 1),
		memory.getregister("m68000.pc"))

end

memory.registerwrite(P2_INPUT_WORD, 2, function()
	if inject_guard then return end
	-- TEMPORARY diagnostic: prove the hook fires at all, and that it is not
	-- being turned away by the globals guard. One entry per 64 ticks keeps the
	-- log small while still being unmistakable if it is missing entirely.
	hook_ticks = hook_ticks + 1
	if (hook_ticks % 64) == 0 then
		debugKnockdownModule.mark_write("hook_alive", hook_ticks % 256,
			(globals ~= nil and globals.dummy ~= nil) and 1 or 0)
	end
	if globals == nil or globals.dummy == nil then return end

	-- TEMPORARY diagnostic, measurement only: log EVERY write to 0xFF8B94
	-- with its PC while a pre-buffered reversal is live.
	--
	-- The open question: injected directions were written correctly during the
	-- knockdown (the log showed lever = 2 then 4) yet never appeared in
	-- $122/$123, while the same injection on the release frame did arrive.
	-- joypad.set() reaches $122 during the knockdown fine, so the game IS
	-- running the 0x02211A copy - something must be overwriting 0xFF8B94
	-- between our write and that copy. Static analysis says there are only two
	-- writers, 0x014E7A (input stage 2) and 0x0090AE; this shows which of them
	-- actually fire, in what order, and how many times per tick.
	--
	-- Scoped to frames where a held sequence exists, so the volume stays at a
	-- few entries per knockdown.
	do
		local _dd = player_objects and player_objects[2]
		local _ss = _dd and _dd.pending_input_sequence
		if _ss ~= nil and _ss.hold_last then
			debugKnockdownModule.mark_write("b94_writer",
				memory.readbyte(P2_INPUT_WORD) * 256 + memory.readbyte(P2_INPUT_WORD + 1),
				memory.getregister("m68000.pc"))
		end
	end

	local _lev, _btn = 0, 0

	local _d = player_objects and player_objects[2]
	local _seq = _d and _d.pending_input_sequence

	-- TEMPORARY diagnostic: v22 produced ZERO injection events and P2 received
	-- no input at all, so the bits path is never being reached. The logging
	-- below only fires while a pending sequence exists, which keeps the volume
	-- bounded, and records exactly which precondition is failing.
	if _seq ~= nil then
		debugKnockdownModule.mark_write("hook_seq",
			(_seq.hold_last and 1 or 0) * 100
			+ (_seq.released and 1 or 0) * 10
			+ (_seq.current_frame or 0),
			(_seq.sequence and #_seq.sequence or 0))
	end

	-- FINAL ENTRY ONLY (back to what v18 measured).
	--
	-- v19-v27 tried to carry the WHOLE motion through this hook. It does not
	-- work: while the dummy is still down, the injected directions were
	-- written to 0xFF8B94 correctly but never appeared in $122/$123, so the
	-- motion was never entered. Only the release frame's input ever landed -
	-- by which point the character is actionable and the game is reading input
	-- again. joypad.set() carries the motion; this hook carries the final
	-- button and diagonal, one tick earlier than the pad can.
	-- INJECT ON EVERY WRITE, not once per displayed frame.
	--
	-- Measured: 0xFF8B94 is written THREE times per displayed frame, all from
	-- 0x014E7E (input stage 2), and the event-sequence numbers put them 7+
	-- events apart - they are three genuinely separate writes, not one write
	-- reported per byte. A once-per-frame injection therefore had its value
	-- overwritten by the two stage-2 writes that followed it, which is exactly
	-- why the injected directions never reached $122/$123 during the
	-- knockdown while joypad.set()'s did.
	--
	-- Re-asserting on every write costs nothing (the same bits, ORed onto
	-- whatever stage 2 just put there) and removes the race entirely.
	local _released_now = _seq ~= nil and _seq.released
	if _seq ~= nil and _seq.hold_last and _seq.sequence ~= nil and _released_now then
		-- EACH ENTRY IS INJECTED FOR EXACTLY ONE TICK.
		--
		-- Without this the hook re-injects whatever entry current_frame points
		-- at on every tick, and release_input_sequence() parks current_frame on
		-- the LAST entry - so the final direction+button was being held for as
		-- long as the sequence lived. P2's input history showed it directly:
		-- ten consecutive frames of down-forward + punch, with the earlier
		-- entries of the motion nowhere to be seen.
		--
		-- WHICH ENTRY TO INJECT.
		--
		-- Do not try to derive it from current_frame here. Two things make
		-- that wrong, and both were measured the hard way:
		--   * controller.lua writes the entry and only THEN advances
		--     current_frame (controller.lua:564), so by hook time it already
		--     points past the entry that was used.
		--   * while a pre-buffered motion is held, controller.lua CLAMPS
		--     current_frame to #sequence - 1 every single frame
		--     (controller.lua:614) - it stops being a position at all. With
		--     the clamp in play, "current_frame - 1" was permanently 1, so
		--     entry 1 ("forward") was injected once and entry 2 ("down") never
		--     was. The diagnostic caught it exactly: hook_seq read 102 every
		--     tick = hold_last, not released, current_frame pinned at 2.
		-- vsav_training_master_script.lua records the real index into
		-- _seq.inject_idx immediately before calling
		-- process_pending_input_sequence, which is exact.
		--
		-- The held direction is re-injected EVERY frame, not once: holding is
		-- the point of the pre-buffer, and joypad.set() used to re-send it
		-- each frame too. inject_frame keeps that to one injection per
		-- displayed frame even when several ticks share one (turbo).
		_lev, _btn = entry_to_bits(_seq.sequence[#_seq.sequence])
	end

	-- Legacy one-shot path (kept so nothing else that arms inject_mask breaks).
	if inject_mask ~= 0 then
		_btn = bor8(_btn, inject_mask)
		_lev = bor8(_lev, inject_lever_bits())
	end

	if _lev == 0 and _btn == 0 then return end
	assert_input_bits(_lev, _btn)

	inject_mask = 0
	inject_dir  = nil
end)

-- TICK-RESOLUTION TRACE (read-only, changes no behaviour).
--
-- REPLACES the earlier 0x02211A copy diagnostic, which answered its question
-- (the copy does run while the dummy is down) and is now subsumed by this.
--
-- Anchor: 0x0221CC, inside the per-object input routine that runs once per
-- player per game tick, unconditionally, BEFORE the state dispatcher at
-- 0x02244E:
--     022114: move.w ($122,A6), ($124,A6)   ; $124 := previous input
--     02211A: move.w ($394,A6), ($122,A6)   ; $122 := current input
--     ...
--     0221AA: move.w ($124,A6), D0 / not.w / and.w ($122,A6)
--     0221B4: move.w D0, ($126,A6)          ; $126 := PRESS edge, this tick
--     0221C2: move.w D0, ($128,A6)          ; $128 := RELEASE edge
--     0221C6: bra $221cc
--     0221CC: move.b ($b,A6), D0            <- hooked here
-- Hooking after 0x0221B4/0x0221C2 means the row carries the edges for the
-- CURRENT tick, not the previous one.
--
-- Why this is needed: on the v31 batch the release fired from a state
-- condition that was byte-identical in all 45 attempts (kd=26, $7=2,
-- $20=0), yet 28 succeeded and 17 did not. Per-displayed-frame logging
-- cannot see where the variance is, because 0x0221CC runs 2/3/4 times per
-- displayed frame. This makes each tick individually visible.
local tick_tail = 0

-- $06 values that mean "an action started". 0x00 is idle and 0x04 is the tick
-- before free, so neither counts. See VSAV_REFERENCE.md section 1.
-- Title case throughout, to match the menus. These are shown on screen under
-- the verdict, so they are labels rather than shouting.
local FASTEST_ACTION = {
	-- 0x02 IS NOT SAFE TO NAME.
	--
	-- It was reported from the screen as a throw and labelled accordingly, and
	-- the label then turned up on moves that are not throws. It is also hit
	-- stun proper on the receiving side, and Q-Bee sits in it while free, so
	-- one number is covering at least three things. Naming it produces wrong
	-- labels more often than right ones, so it goes back to being shown as its
	-- number until something distinguishes them.
	[0x06] = "Jump",  [0x0A] = "Normal", [0x0E] = "Special",
	[0x10] = "ES",    [0x12] = "EX",     [0x14] = "Dash",
	[0x16] = "Dark Force",
	[0x1A] = "DF Stop",     -- Dark Force deactivation, reported as ACT 1A
}
-- ANYTHING ELSE IS STILL AN ACTION (v153).
--
-- A throw produced nothing at all on screen. Two reasons, and this table was
-- only the second of them: whatever $06 a throw sets is not in it, so the
-- action was never recognised. The ROM does not enumerate cheaply either -
-- there are only ten `move.b #imm, ($6,A6)` sites in the whole program and the
-- rest go through addq or the bulk move.l writes - so rather than guess, an
-- unmapped value is now reported with its number. The user sees something, the
-- log carries the pair, and it can be given its real name next time.
-- Values that are NOT the dummy doing something.
--   0x00 idle, and the impact freeze of being hit
--   0x04 the tick before free
--   0x0C guard - reported from the screen as ACT 0C on a standing block. The
--        dummy holding back to keep blocking is not an action to time.
local FASTEST_IDLE = { [0x00] = true, [0x04] = true, [0x0C] = true }
local function fastest_name(_06)
	return FASTEST_ACTION[_06] or string.format("Act %02X", _06)
end
-- Frames to keep counting before giving up on the dummy doing anything.
local FASTEST_GIVE_UP = 30

-- WHAT IS ALLOWED ON THE FREE TICK, AND WHAT IS NOT.
--
-- On the tick the character becomes free only a SPECIAL (or a guard) can come
-- out. A normal, a dash, Dark Force and a jump are all refused there and are
-- only possible from the NEXT tick.
--
-- Measured over 373 wake-ups across every archive, the input relationship is
-- exact and has no exceptions: a press edge on tick X produces the action on
-- tick X+1.
--
--     press free-1 -> action free+0   336 spans
--     press free+0 -> action free+1     5
--     press free+1 -> action free+2     2
--     press free+2 -> action free+3     6   ... and so on
--
-- So a special has to be pressed on free-1, which is what the signature below
-- has always done, and everything else has to be pressed on free+0 - one tick
-- later. Pressing a normal on free-1 asks for it on the tick it cannot happen.
--
-- The earliest possible frame therefore differs by category, and the display
-- has to say so: for a normal, coming out on free+1 IS the fastest there is.
local FASTEST_FLOOR = {
	["Special"] = 0, ["ES"] = 0, ["EX"] = 0,
	["Normal"] = 1, ["Jump"] = 1, ["Dash"] = 1, ["Dark Force"] = 1,
}
-- The motions that produce a SPECIAL, listed explicitly.
--
-- The entry count is not the test, though it looks like it: it carries a count
-- for every stick setting including "down-forward" and "forward dash", so
-- keying on it called a crouching punch a special and pressed it on free-1 -
-- the one tick a normal cannot come out on.
--
-- A dash is in here nowhere on purpose. It is a command, but the game refuses
-- it on the free tick along with the normals, so it wants the later press.
local SPECIAL_MOTION = {
	["QCF"] = true, ["QCB"] = true, ["DPF"] = true, ["DPB"] = true,
	["HCF"] = true, ["HCB"] = true, ["DQCF"] = true,
	-- The unabbreviated half circle is a special too. Only "HCB" was here, so
	-- Valkyrie Turn - the one move that names HCB-full - was pressed on free+0
	-- like a normal and came out a tick late.
	["HCB-full"] = true,
	["360"] = true, ["720"] = true,
	["HCharge"] = true, ["VCharge"] = true,
	-- The Mizuumi digit-string motions. Every one of them names a special, so
	-- they all press on free-1 like the abbreviated ones above. Leaving one out
	-- is not a missing feature - it is a move that comes out a tick late, which
	-- is how "HCB-full" was found.
	["22"] = true, ["46"] = true, ["263"] = true, ["632"] = true,
	["41236"] = true, ["2~8"] = true, ["6~4"] = true,
	["[4]6"] = true, ["[2]8"] = true,
	["Shun Goku Ratsu"] = true, ["Kongou Kokuretsu Zan"] = true,
}
local function counter_is_special()
	if globals == nil or globals.dummy == nil then return true end
	-- A BUTTON-ORDER SUPER HAS NO MOTION NAME TO LOOK UP.
	--
	-- Its command is an ordered run of buttons and directions, so the runner's
	-- "motion" for it is the move's own id and no table of motions can carry
	-- it. It is still a special: measured here as every one of them coming out
	-- on +1 Tick, which is a normal's press offset.
	if globals.dummy.guard_action == 'sequence' then
		-- ASKED AND ANSWERED, NOT FALLEN THROUGH.
		--
		-- A move that opts out of the early press has to say so before the
		-- motion table is consulted: Kienzan is a DPF, and DPF is in
		-- SPECIAL_MOTION, so a plain "not a special" answer here would be
		-- overturned two lines down and the move would stay on free-1. Measured
		-- as "Fastest does not come out, +1 Tick does" (user, 2026-09-05).
		if actionSequenceRunnerModule.first_press_free0 ~= nil
		   and actionSequenceRunnerModule.first_press_free0("reversal") then
			return false
		end
		if actionSequenceRunnerModule.first_is_special ~= nil
		   and actionSequenceRunnerModule.first_is_special("reversal") then
			return true
		end
	end
	-- A MOVE MAY OPT OUT OF THE EARLY PRESS.
	--
	-- Bishamon's Kienzan is a DPF like several others, so the motion table
	-- cannot tell it apart - and it is the move, not the motion, that wants
	-- free+0. The registry says so per move; this is the Character Specific
	-- path reading the same field the sequence path reads through
	-- first_is_special.
	local _sel = globals.dummy.p2_char_specific_reversal
	if _sel ~= nil and _sel.command ~= nil and _sel.command.press_free0 == true then
		return false
	end
	return SPECIAL_MOTION[GA.stick()] == true
end
-- lg (0xFF8081) on the tick the free-1 signature fired, when the press was
-- deliberately held back to the free tick. Compared as a difference of exactly
-- one, so a speculative re-execution simply fails the test instead of firing
-- early - the same shape as hs_arm_lg.
local fast_press_lg = nil
local fast_press_lev = 0
local fast_press_btn = 0
local fast_press_off = 0
-- THE FACING THE BITS WERE RESOLVED AGAINST, AT DEFER TIME (2026-09-20).
--
-- Raw bits only mean one direction against the facing the game's swap
-- (0x022194) will apply where they land. A wake-up turns the dummy between the
-- defer and the delivery - measured 15 of 15 failed wake-up dashes had $b flip
-- exactly on the free tick, 12 of 12 successes kept it - so the deferred
-- press, the only part of the delivery that straddles the turn, must be
-- re-aimed. Both defer sites store the reference; the delivery swaps the two
-- facing-relative bits when the reference has moved on.
local fast_press_fref = nil
-- THE DELAY SEPARATES THE MOTION FROM THE BUTTON (v173).
--
-- fast_press_moff is where the motion's LAST entry goes, fast_press_off where
-- the button goes. Without a delay they are the same tick and the two are
-- injected together, exactly as before. With one, the motion still finishes at
-- its earliest place and only the button waits - "fastest dash, then HP N ticks
-- later", not "the whole dash N ticks later".
local fast_press_moff = 0
local fast_press_mlev = 0
local fast_press_hold = false
-- Set only for a dash cancel: the lever the tick hook switches to once the
-- dash exists, and then holds until the button. nil for everything else.
local fast_press_rev  = nil
-- THE PREFIX THE FRAME PATH NEVER DELIVERED (v176).
--
-- In hit stun the motion is walked by process_pending_input_sequence, once per
-- DISPLAYED frame, and it races the arm lead - which varies with the strength
-- of the attack that connected (HS_LEAD_BY_59). Measured on the v174 batch,
-- ground hit stun, forward dash + HP: three spans got the first tap and became
-- a dash, five never got it at all and became a walk plus a normal. The delay
-- setting did not separate them - one of the successes was delay 5 and two of
-- the failures were as well.
--
-- So whatever the frame path has not delivered by the signature tick is
-- delivered from here instead, one entry per tick. Entries are kept rather
-- than bits because entry_to_bits() resolves forward/back against the facing
-- byte at the moment it is called, and the character can turn round.
local fast_press_q = {}

-- THE GUARD ACTION DELAY, IN TICKS.
--
-- The setting is labelled in frames and used to be applied by prepending that
-- many blank entries to the sequence. On the tick-driven path that does nothing
-- useful: the blanks become part of the motion, so the whole thing shifts
-- EARLIER while the button still lands on the tick the schedule puts it, and
-- the delay has no effect on when the action comes out.
--
-- Applied here instead, as a straight offset on the press, one tick per unit.
-- One game tick is one game frame for move timing, so the number on the menu
-- means what it says. The motion in front of the button is left where it is:
-- the recogniser holds a completed motion for 14 to 19 ticks (0x02A55A), so a
-- delay of up to about ten still finds it, and pressing late after the motion
-- is exactly what a delayed reversal is by hand.
-- ============================================================
--  Auto DASH TIMING TABLE  -  EDIT HERE
-- ============================================================
--
-- The one place Auto gets its numbers from. Everything below is data; no code
-- has to change to retune it.
--
--   UNIT      game TICKS, exactly what the Guard Action Delay menu takes.
--             Auto simply fills this number in, so a value here and the same
--             number typed into the menu behave identically.
--   MEANING   how long after the MOTION finishes the button is pressed.
--             For a dash that is after the second tap; for a dash cancel it is
--             after the cancel direction.
--   0         press with the motion, no gap.
--
--   fc/bc no longer have to place the cancel direction. The attack wiki
--   (Sasquatch, Short Dash) says the reverse direction may simply be HELD from
--   right after the dash - the game looks for it on a single frame and a held
--   lever cannot miss it - so v201 puts it in the sequence and holds it. What
--   is left for fc/bc is the gap from that reverse direction to the BUTTON,
--   and the wiki confirms 0 is legal: "pressing the button together with the
--   reverse direction still gives the dash attack" - so a 0 in this column
--   would be a value and not a gap in the data. No character carries one now:
--   the old build's flat 10, and its cancel_frame reading that implied 0 for
--   Sasquatch, were both replaced by the measured pass below.
--
--   f    forward dash              fc   forward dash cancel
--   b    back dash                 bc   back dash cancel
--
-- MEASURED ON THIS BUILD BY THE USER. ALL FOUR COLUMNS.
--
-- Everything except Morrigan and Sasquatch (which were measured earlier and
-- carry their own notes below) comes from one pass over the whole cast. The
-- cancels mostly sit two ticks under the plain dash, and where they do not -
-- Jedah above it, Q-Bee one under, Lei-Lei and Zabel level at 1 - that is
-- measured, not derived.
--
-- Keyed by $382. A character with no row, or a row with no field, gets no Auto
-- value and falls back to 0.
--
-- HISTORY. THE PASS ABOVE REPLACED EVERY NUMBER THAT WAS HERE.
--
-- f and b were first tuned by hand against the 2026-06-25 build (see
-- VSAV_REFERENCE.md 8.32); fc came from that build's
-- forward_dash_cancel_timing; bc had no per-character value there at all and
-- carried a placeholder so the column would be usable. The note that stood
-- here called bc "the first thing to retune" and said Sasquatch's cancels
-- were a gap of 0 because the old build pressed the button on the cancel
-- frame. Both are now wrong: bc was retuned with the rest, and Sasquatch's
-- fc measured 7 on this build (see its row).
local DASH_AUTO_TICKS = {
	--                      f    b    fc   bc
	[0x00] = { name = "Bulleta",   f =  5, b =  5, fc =  3, bc =  3 },
	[0x02] = { name = "Gallon",    f =  8, b =  3, fc =  6, bc =  1 },
	[0x03] = { name = "Victor",    f =  5, b =  5, fc =  3, bc =  3 },
	[0x04] = { name = "Zabel",     f =  1, b =  1, fc =  1, bc =  1 },
	-- Morrigan and Jedah were re-measured after the whole cast was done, and
	-- both moved. The earlier 14 came out of a session where the joypad.set
	-- echo was still confusing the reading (section 8.46); with the rest of the
	-- table measured the same way, 12 is what holds up.
	[0x05] = { name = "Morrigan",  f = 12, b = 12, fc = 13, bc = 13 },
	[0x06] = { name = "Anakaris",  f =  5, b =  5, fc =  3, bc =  3 },
	[0x07] = { name = "Felicia",   f =  8, b =  8, fc =  6, bc =  6 },
	[0x08] = { name = "Bishamon",  f =  6, b =  3, fc =  4, bc =  1 },
	[0x09] = { name = "Aulbath",   f =  6, b =  1, fc =  4, bc =  1 },
	[0x0A] = { name = "Sasquatch", f =  2, b =  1, fc =  7, bc =  7 },
	-- Sasquatch fc measured on THIS build by the user: 7. The old build's
	-- "button on the cancel frame" implied 0, which was wrong here. bc was
	-- measured too, also 7.
	[0x0C] = { name = "Q-Bee",     f =  6, b =  6, fc =  5, bc =  5 },
	[0x0D] = { name = "Lei-Lei",   f =  1, b =  5, fc =  1, bc =  1 },
	[0x0E] = { name = "Lilith",    f =  5, b =  5, fc =  3, bc =  3 },
	[0x0F] = { name = "Jedah",     f = 10, b = 10, fc =  9, bc =  9 },
	-- Dark Gallon gets Gallon's values, the same judgement KD_END_1A7 above
	-- already made: vsavscriptv2.lua's own check says he "is exactly the
	-- same as regular Gallon". Confirmed by the user, 2026-09-19.
	--
	-- BOTH TABLES OR NEITHER: this one drives the arm and
	-- MEASURED_STEP_FLOORS drives the step. A character present in one but
	-- not the other has the two paths saying different things about him -
	-- the trap the Demitri row was written to avoid.
	[0x12] = { name = "Dark Gallon", f =  8, b =  3, fc =  6, bc =  1 },
	-- DEMITRI (0x01) HAS NO ROW, AND SHOULD NOT GET ONE FOR THE CANCELS.
	--
	-- The attack wiki's Demitri page, basic actions: both dashes are
	-- 'chuudan fuka' - they CANNOT be interrupted. Forward Dash Cancel and
	-- Back Dash Cancel are not moves he has, so fc/bc have nothing to
	-- measure. hud.lua reaches the same conclusion from the other side: it
	-- excludes Demitri from the dash-attack-cancel trainer.
	--
	-- f/b (a plain dash into a button) are simply unmeasured - the source
	-- build had no Demitri row at all. Adding them is fine; adding fc/bc is
	-- measuring something that does not exist.
}

-- Which field of the row a motion uses. This is also the list of motions Auto
-- is offered for at all - menu.lua keys off the same names.
local DASH_AUTO_FIELD = {
	["forward dash"]        = "f",
	["back dash"]           = "b",
	["forward dash cancel"] = "fc",
	["back dash cancel"]    = "bc",
}

-- nil unless the configured motion is one of the four dashes AND the character
-- has a value for it. Written long-hand: these values can be 0, and `a and b
-- or c` on a possibly-zero field is the shape that went wrong in v194.
-- ALL FOUR DASHES, INCLUDING THE CANCELS (v209).
--
-- v206 left the cancels out because they had their own tick-driven prefix at
-- the time. v207 took that away - a cancel's sequence IS the plain dash now,
-- and only the reverse direction afterwards differs - so the dash half needs
-- exactly the same neutral/tap scheduling. Leaving them out meant a BACK dash
-- cancel had no press edge on its first tap, because the dummy holds back to
-- guard, and nothing came out at all. Same failure as the plain back dash in
-- v206, one motion further along.
-- The direction a dash cancel reverses INTO. Held by the tick hook through the
-- delay wait and pressed with the button, rather than sitting in the sequence -
-- see the note in controller.lua.
local DASH_CANCEL_REVERSE = {
	["forward dash cancel"] = "back",
	["back dash cancel"]    = "forward",
}
-- TICKS UNTIL THE ANIMATION ENDS, WALKED FROM THE GAME'S OWN CEL LIST.
--
-- A block ends on its guard ANIMATION - 0x02393A sets the guard state and
-- leaves through 0x027EC0 with an animation id - so "how long until free" is
-- not something to predict from strength. It is written in the animation data
-- and the game walks it the same way:
--
--     027EEC: move.l (A0), ($20,A6)   ; $20 duration, $21 flags
--     027F70: subq.b #1, ($20,A6)     ; one off per tick
--     027F7A: move.b ($1,A0), D0      ; the cel's flag byte
--     027F80: bmi $27f8e              ; bit7 -> jump to ($18,A0)
--     027F88: st ($21,A6)             ; bit6 -> last cel, animation over
--     027F96: lea ($18,A0), A0        ; cels are 24 bytes
--
-- So the remaining time is $20 plus the durations of the cels after it, up to
-- and including the one carrying bit6. nil when a cel jumps (bit7), because
-- the length then depends on where it jumps to.
--
-- NOTE: during an impact freeze the stepper does not run, so this is the
-- remaining ANIMATION time, not wall time. It becomes exact once the freeze
-- ends. Traced first, built on second.
-- HOW LONG THIS GUARD LASTS, KNOWN ON THE FIRST TICK OF IT.
--
-- 0x027DE4 ends guard the moment its script byte goes negative:
--
--     027DEA  move.b ($59,A6), D0     reaction type, from the attack's data
--     027DF0  lea    ($285de,PC), A0  word offsets, signed, relative to itself
--     027DF8  lea    (A0,D0.w), A0
--     027DFC  move.w ($164,A6), D0    cursor, +1 per tick
--     027E00  move.b (A0,D0.w), D0
--     027E04  bmi    $27e2a           negative = over
--
-- so the whole length is readable up front - no counter to watch, and no
-- per-strength guesswork (BLK_LEAD/BLK_WAIT). Returns total ticks, or nil if
-- the table reads back as nonsense.
local GUARD_PUSH_TABLE = 0x0285DE

local function guard_script_len(_s59)
	if _s59 == nil or _s59 > 15 then return nil end
	local _off = memory.readword(GUARD_PUSH_TABLE + _s59 * 2) % 0x10000
	if _off >= 0x8000 then _off = _off - 0x10000 end
	local _a = GUARD_PUSH_TABLE + _off
	if _a < 0x1000 or _a >= 0x400000 then return nil end
	for _i = 0, 63 do
		if memory.readbyte(_a + _i) % 0x100 >= 0x80 then return _i end
	end
	return nil
end

-- Hung on BLK rather than referenced directly: the tick hook is already at the
-- 60-upvalue ceiling, and BLK is a upvalue it holds anyway.
BLK.script_len = guard_script_len

local function anim_ticks_left()
	local _p = memory.readdword(0xFF881C)
	if _p == nil or _p < 0x1000 or _p >= 0x400000 then return nil end
	local _left = memory.readbyte(0xFF8820)
	for _i = 1, 24 do
		local _flag = memory.readbyte(_p + 1)
		if _flag >= 0x80 then return nil end
		if _flag % 0x80 >= 0x40 then return _left end
		_p = _p + 0x18
		_left = _left + memory.readbyte(_p)
	end
	return nil
end

local function dash_cancel_reverse_bits()
	-- THE SEQUENCE RUNNER HOLDS ITS OWN REVERSE.
	--
	-- For a single-motion reversal this drives the +2 press offset and the
	-- reverse riding the button. A sequence's step one has no deferred button
	-- for it to ride, and the runner parks the reverse itself - letting the
	-- arm fire here would push the dash's own last tap two ticks past free
	-- and turn the fastest dash into a late one.
	if globals and globals.dummy and globals.dummy.guard_action == 'sequence' then
		return nil
	end
	local _s = globals and globals.dummy and GA.stick()
	local _rev = DASH_CANCEL_REVERSE[_s]
	if _rev == nil then return nil end
	local _lev = entry_to_bits({ _rev })
	return _lev
end

-- ONLY THE BACK DASHES (v210).
--
-- The neutral/tap injection this gates exists for ONE reason: the dummy holds
-- BACK to guard, so asking for back again produces no press edge
-- ($126 = ~$124 & $122) and the first tap does not exist. Forward is never
-- held, so a forward dash never needed it - and getting it anyway adds a tap
-- the motion did not ask for.
--
-- The two reports are the same fact from both sides:
--
--     v205  gate off for every dash    forward comes out, back does not
--     v206  gate on for both           back comes out, forward does not
--
-- So it follows the guard direction, not "is this a dash".
-- TWO DIFFERENT NEEDS, AND THEY ARE NOT THE SAME SET (v225).
--
-- v210 turned the whole block off for the forward dashes on the grounds that
-- forward is never held, so it does not need a release to make a press edge.
-- That half is right. The other half is not: the TAP still has to arrive, and
-- for a forward dash it was left to the frame path, which does not always get
-- there. Measured on a block against Demitri, forward dash, 8 spans - and the
-- successes and failures differ by one tick:
--
--     free-2   lev=2 (forward)      lev=1 (still the guard hold)
--     free-1   lev=.                lev=.
--     free+0   lev=2                lev=2
--     free+1   $06 = 0x14  dash     $06 = 0x04  nothing
--
-- Four of eight had no first tap at all. One tap is a walk.
--
-- So the tap is guaranteed for all four dashes, and only the ones whose
-- direction the dummy is ALREADY HOLDING get the release in front of it.
-- Releasing for a forward dash would drop the guard for five ticks and buy
-- nothing.
local NEEDS_TAP_EDGE = {
	["forward dash"] = true, ["back dash"] = true,
	["forward dash cancel"] = true, ["back dash cancel"] = true,
}
local NEEDS_RELEASE = {
	["back dash"] = true, ["back dash cancel"] = true,
}
local function needs_release()
	local _s = globals and globals.dummy and GA.stick()
	return NEEDS_RELEASE[_s] == true
end

-- HOW LONG THE LEVER IS RELEASED BEFORE THE FIRST TAP (v211).
--
-- The release is what turns the next back into a press edge. One tick of it
-- worked but not reliably - reported as "the back dash comes out, but not
-- often". Widening it costs nothing the dash needs: these ticks are inside
-- block stun, where the dummy cannot act anyway.
--
-- It is not free in a BLOCKSTRING, though. The lever is off back while this
-- runs, so a hit arriving in those ticks is not guarded. That is already true
-- of the single tick this replaces; it just lasts longer now. If a multi-hit
-- string starts getting through, this is the number to bring back down.
-- Raised 3 -> 5 (v212). "It comes out, but not always, and heavy attacks look
-- worse" - and heavy is a different row of BLK_LEAD, so the release may simply
-- be landing in the wrong place for that strength. A wider release covers a
-- lead that is off by a tick or two without having to guess which way.
local BACK_TAP_NEUTRAL_TICKS = 4

-- HOW MANY TICKS EARLIER THAN lead-2 THE FIRST TAP GOES (v213).
--
-- Measured on the v212 batch, tap1 to the real free tick, by attack strength:
--
--     $59=0 light    3 x4   2 x3                 never 1
--     $59=1 medium   2 x8   3 x3   1 x2
--     $59=2 heavy    2 x8   3 x4   1 x3
--
-- A distance of 1 means the tap landed ON the signature tick. This block
-- returns before the signature hook runs, so the neutral that belongs on
-- free-1 never goes in, the second tap on free+0 has nothing to be an edge
-- against, and no dash comes out. The frequency matches the report exactly:
-- light none, medium twice, heavy three times.
--
-- The real distance from the arm to free varies by a tick or two; BLK_LEAD is
-- one number per strength and cannot follow that. It does not have to: a tap
-- that is EARLY is harmless - measured, anything within ten ticks of free
-- still dashes (8.18) - while a tap that is late is fatal. So the placement is
-- biased early rather than made accurate.
-- The tap is HELD, not struck once. A two tick tap is easier for the game to
-- take than a one tick one, and holding it longer costs the dash nothing. The
-- extra tick comes out of the release above rather than being added on top.
local BACK_TAP_HOLD_TICKS = 2
-- One further tick early, so the WIDER tap still cannot reach free-1.
local BACK_TAP_BIAS = 3
local function is_plain_dash()
	local _s = globals and globals.dummy and GA.stick()
	return NEEDS_TAP_EDGE[_s] == true
end

-- The measured dash-attack offset for an explicit motion, for the sequence
-- compiler. A global so the runner can reach it without this file's table
-- being duplicated there, and without costing an upvalue here.
function dash_attack_ticks_for(_motion)
	local _field = DASH_AUTO_FIELD[_motion]
	if _field == nil then return nil end
	local _row = DASH_AUTO_TICKS[memory.readbyte(0xFF8B82)]
	if _row == nil then return nil end
	return _row[_field]
end

-- HOW SOON AFTER A JUMP AN AIR DASH CAN COME OUT.
--
-- Counted the same way DASH_AUTO_TICKS is: the tick the dash's LAST tap lands
-- on, measured from the jump input. The floor is the takeoff, so it is a
-- property of the character's jump and not of the dash.
--
-- Measured by walking a sequence's Wait down one tick at a time until the dash
-- stops coming out - the procedure in VSAV_MEMORY_NOTES:
--
--     Zabel, forward jump then forward air dash    +8 comes out, +7 does not
--
-- ONE MEASUREMENT IS ONE ENTRY. A character with no row here gets no number:
-- Auto stays the airborne state test rather than borrowing someone else's
-- takeoff, which is the same rule DASH_AUTO_TICKS follows.
-- Zabel's back air dash measures the same 8, both sides checked. That is two
-- directions agreeing on one character, which is what the takeoff being a
-- property of the JUMP would predict - but Lei-Lei is the only other character
-- with a back air dash, so it stays two fields until she is measured too.
--
-- Q-Bee is 6, from a back jump into a forward air dash. Different from Zabel's
-- 8, which is what settles the question the table was written for: the floor is
-- a per-character number and there is no single one to use.
--
-- b is absent for Q-Bee because she has no back air dash at all - the editor
-- does not offer it. An empty field is "not measured"; the row simply has
-- nothing to measure.
-- Lei-Lei is 9, from a forward jump into a forward air dash, and her back air
-- dash is 9 as well. Three characters, three different floors - 8, 6, 9 - so
-- the per-character table is what this has to be. Both characters measured on
-- both sides came out the same forwards and backwards, which is the takeoff
-- being a property of the jump.
--
-- No super jump row will ever be needed here: the two characters with a super
-- jump command (Morrigan and Lilith) have no air dash at all.
--
-- atk IS HOW SOON AN ATTACK FOLLOWS THE AIR DASH, AND IT IS NOT ALWAYS ZERO.
--
-- This was written as a flat 0 on the reasoning that the ground offset only
-- exists because the press has to land INSIDE the dash, and the air one does
-- not. Zabel and Q-Bee both measure 0, so the reasoning looked right. Lei-Lei
-- is 5 - at 4 the LP does not come out - so it was wrong, and this is a
-- measurement like every other number here.
-- All four measured. Jedah's glide is a dash like the others here: 7 to reach
-- it and 6 before an attack. It stays in $06 = 0x14 for its whole length (see
-- the glide note further down), which is why "a glide lets a normal out at any
-- time" is about CHAINING inside it and not about how soon the first one comes.
-- KEYED ON THE PAIR, BECAUSE THE JUMP'S DIRECTION MATTERS TOO.
--
-- This was two fields, f and b, on the assumption that the floor is the takeoff
-- and so belongs to the jump alone. Zabel disproves it: forward into forward is
-- 8 and back into back is 8, but back into FORWARD comes out as soon as the
-- input can be delivered. Same character, same takeoff, different answer - so
-- the number belongs to the combination.
--
-- Unmeasured pairs get no number and fall back to the airborne state test. A
-- neutral jump is unmeasured for everyone.
--
-- FOUR IS THE FLOOR OF THE MEASUREMENT, NOT OF THE GAME.
--
-- A dash's own input is {} {forward} {} {forward}, which is four ticks, so a
-- wait of 0, 1, 2, 3 or 4 all put the last tap on tick four - see the lead
-- subtraction in service_body. Below four there is nothing left to measure with
-- this action, and 4 is what "as early as it can be delivered" is called.
local AIR_DASH_TICKS = {
	-- Zabel. Only the two that jump and dash the SAME way have a dash floor
	-- above the input's own length.
	[0x04] = { name = "Zabel",
	           ["jump.f>air.f"] = { dash = 8, atk = 0 },
	           ["jump.b>air.b"] = { dash = 8, atk = 0 },
	           ["jump.f>air.b"] = { dash = 4, atk = 4 },
	           ["jump.b>air.f"] = { dash = 4, atk = 4 },
	           ["jump.n>air.f"] = { dash = 4, atk = 4 },
	           ["jump.n>air.b"] = { dash = 4, atk = 4 } },
	-- Q-Bee, all three she has. Forward and back both floor at 6 and only the
	-- neutral jump comes out as soon as it can be delivered - a different shape
	-- from Zabel's, where the two SAME-direction pairs are the slow ones.
	[0x0C] = { name = "Q-Bee",
	           ["jump.f>air.f"] = { dash = 6, atk = 0 },
	           ["jump.b>air.f"] = { dash = 6, atk = 0 },
	           ["jump.n>air.f"] = { dash = 4, atk = 0 } },
	-- Lei-Lei, all six. She is what proved atk belongs to the pair too: 5 after
	-- the same-direction dash and 8 after any of the other four.
	--
	-- A FOURTH GENERALISATION, TESTED AND DEAD.
	--
	-- dash + atk is constant per character on three of them - 14 on all six of
	-- Lei-Lei's, 13 on all three of Jedah's, 8 on Zabel's - which reads as the
	-- attack's floor being counted from the JUMP rather than from the dash. It
	-- would have filled every remaining blank by arithmetic.
	--
	-- Q-Bee kills it. Her neutral jump is dash 4, and the attack comes out at 0,
	-- so her sum is 4 where her forward jump's is 6. Measured, not assumed.
	--
	-- That is four generalisations about this one table, all wrong: "the air
	-- attack is always 0", "the floor belongs to the jump", "only same-direction
	-- pairs are slow", and now this. The numbers go in one at a time.
	[0x0D] = { name = "Lei-Lei",
	           ["jump.f>air.f"] = { dash = 9, atk = 5 },
	           ["jump.b>air.b"] = { dash = 9, atk = 5 },
	           ["jump.n>air.f"] = { dash = 6, atk = 8 },
	           ["jump.b>air.f"] = { dash = 6, atk = 8 },
	           ["jump.f>air.b"] = { dash = 6, atk = 8 },
	           ["jump.n>air.b"] = { dash = 6, atk = 8 } },
	-- Jedah, all three he has. Both his measured sums are 13, which is a third
	-- character agreeing with the observation above.
	[0x0F] = { name = "Jedah",
	           ["jump.f>air.f"] = { dash = 7, atk = 6 },
	           ["jump.b>air.f"] = { dash = 4, atk = 9 },
	           ["jump.n>air.f"] = { dash = 4, atk = 9 } },
}

-- The measured offsets for one jump-into-air-dash pair, or nil where that pair
-- has not been measured. Global for the same reason dash_attack_ticks_for is.
--
--   dash  ticks from the jump to the air dash
--   atk   ticks from the air dash to the first attack
--
-- Both are per PAIR. The attack one is asked with the jump that came two steps
-- back, because Lei-Lei's is 5 after a same-direction dash and 8 after any
-- other - the dash alone does not say which.
local function air_dash_row(_jump, _dash)
	local _row = AIR_DASH_TICKS[memory.readbyte(0xFF8B82)]
	if _row == nil then return nil end
	return _row[tostring(_jump) .. ">" .. tostring(_dash)]
end

function air_dash_ticks_for(_jump, _dash)
	local _p = air_dash_row(_jump, _dash)
	return _p and _p.dash
end

function air_dash_attack_ticks_for(_jump, _dash)
	local _p = air_dash_row(_jump, _dash)
	return _p and _p.atk
end

-- HOW SOON AN ATTACK CAN FOLLOW A JUMP, PER CHARACTER AND DIRECTION.
--
-- NOT MEASURED HERE, UNLIKE EVERY OTHER TABLE IN THIS FILE. These are the
-- "before attack" column of the jump page in Vampire Savior System Data: the
-- frames, counted from the start of the jump's pre-motion, during which an
-- attack cannot come out yet - it comes out on the frame after. Taken whole at
-- the user's direction (2026-09-25), knowing the note above AIR_DASH_TICKS:
-- four generalisations about that table, all wrong.
--
-- THE PAGE'S FRAMES ARE TICKS. Its pre-motion of 3 agrees with takeoff
-- measured 2 to 4 ticks after the jump starts (VSAV_MEMORY_NOTES, jump and
-- dash route section), so there is no frame-to-tick scaling.
--
-- ONE IS TAKEN OFF. A jump is a single buttonless entry, so it is held for two
-- ticks (v158) and the pre-motion starts on the first of them - while a Wait
-- counts from the last. A press on the page's first attack frame is therefore
-- a Wait of one less than the page says. That rule is the same for every
-- character and direction, because the jump's input is.
--
-- TWO POINTS CONFIRM IT, measured by the user on characters whose page values
-- differ: Aulbath forward, page 5, measured 4; Jedah forward, page 6, measured 5
-- (2026-09-25). The obvious alternative - pre-motion plus one, which also gives
-- Aulbath's 4 - predicted 4 for Jedah and is wrong. Everything else is the
-- page's number carried by that rule. A row that turns out wrong in play gets
-- measured and goes in JUMP_ATTACK_MEASURED, which wins.
--
-- Not here: Lilith's high jump (the page has it, but it is the super jump,
-- which Auto does not resolve yet), Dark Gallon and Oboro (not on the page),
-- and 0x0B.
-- In a block of its own: this file's main chunk is at Lua 5.1's limit of 200
-- active locals, and four more at the top level would not load ("main
-- function has more than 200 local variables", 2026-09-25). Locals inside
-- do ... end are released at its end; the global function keeps them.
do
	local JUMP_BEFORE_ATTACK = {
		[0x00] = { name = "Bulleta",   f =  6, n =  6, b =  6 },
		[0x01] = { name = "Demitri",   f =  6, n =  6, b =  6 },
		[0x02] = { name = "Gallon",    f =  5, n =  5, b =  5 },
		[0x03] = { name = "Victor",    f =  6, n =  6, b =  6 },
		[0x04] = { name = "Zabel",     f =  5, n =  5, b =  5 },
		[0x05] = { name = "Morrigan",  f =  6, n =  6, b =  6 },
		[0x06] = { name = "Anakaris",  f = 15, n = 19, b = 15 },
		[0x07] = { name = "Felicia",   f =  5, n =  5, b =  5 },
		[0x08] = { name = "Bishamon",  f =  6, n =  6, b =  6 },
		[0x09] = { name = "Aulbath",   f =  5, n =  5, b =  5 },
		[0x0A] = { name = "Sasquatch", f =  5, n =  5, b =  5 },
		[0x0C] = { name = "Q-Bee",     f =  6, n =  6, b =  5 },
		[0x0D] = { name = "Lei-Lei",   f =  6, n =  6, b =  6 },
		[0x0E] = { name = "Lilith",    f =  6, n =  6, b =  6 },
		[0x0F] = { name = "Jedah",     f =  6, n =  6, b =  6 },
	}
	local JUMP_INPUT_OFFSET = 1
	local JUMP_ATTACK_MEASURED = {
		[0x09] = { ["jump.f"] = 4 },   -- Aulbath, measured by the user, 2026-09-25
		[0x0F] = { ["jump.f"] = 5 },   -- Jedah, measured by the user, 2026-09-25
	}
	local JUMP_DIR = { ["jump.f"] = "f", ["jump.n"] = "n", ["jump.b"] = "b" }

	-- Ticks from a jump to the earliest attack after it, or nil where neither a
	-- measurement nor the page has a number. Global for the same reason the two
	-- air dash ones above are.
	function jump_attack_ticks_for(_jump)
		local _cid = memory.readbyte(0xFF8B82)
		local _m = JUMP_ATTACK_MEASURED[_cid]
		if _m ~= nil and _m[_jump] ~= nil then return _m[_jump] end
		local _row = JUMP_BEFORE_ATTACK[_cid]
		local _d = JUMP_DIR[_jump]
		if _row == nil or _d == nil or _row[_d] == nil then return nil end
		return _row[_d] - JUMP_INPUT_OFFSET
	end
end

-- WHAT AN Auto RESOLVES TO, FOR THE EDITOR'S ROW.
--
-- The runner owns the answer; the editor only prints it. Published here rather
-- than required in the editor because the editor is loaded standalone by the
-- offline tests, and because both tables it reads live in this file.
seq_auto_ticks = actionSequenceRunnerModule.auto_ticks_for
-- The editor calls this after writing a library item back, so the runner
-- lets go of the copy it was holding.
seq_forget_pick = actionSequenceRunnerModule.forget_pick
-- The knockdown logger, for the runner to leave diagnostic marks on.
-- It is a local in every file that requires it, so the runner cannot see
-- it otherwise - and requiring it there would break the offline tests,
-- which dofile the runner on its own.
seq_debug = debugKnockdownModule
-- Same reason: the editor asks whether "Recovered" would be a lie on this
-- row, and the runner is where that is decided.
seq_auto_needs_number = actionSequenceRunnerModule.auto_needs_number
-- THE LANDING CLOCK, FOR Auto (Landing).
--
-- ticks_to_landing() replays the ROM's own physics - y, velocity, gravity and
-- the floor, with the "only while falling" test the ROM makes at 0x027402. The
-- runner asks it directly and decides its own firing point from the step's
-- lead; kd_land_arm() is NOT what it wants, because that is an arm window with
-- slack for a path where the tick hook holds entries back afterwards, and
-- nothing holds them back on the sequence side.
seq_ticks_to_landing = ticks_to_landing
-- THE SEQUENCE RUNNER NEEDS THE CANCEL DIRECTIONS TOO.
--
-- The runner produces the input, and a dash-cancel step has to know which way
-- its reverse points: it parks the direction two ticks past the step's taps
-- and holds it until the next step's button. Published here rather than
-- copied there so the arm and the runner cannot drift apart - they are the
-- same move, seen from two clocks.
seq_dash_cancel_reverse = DASH_CANCEL_REVERSE

local function dash_attack_ticks()
	local _s = globals and globals.dummy and GA.stick()
	local _field = DASH_AUTO_FIELD[_s]
	if _field == nil then return nil end
	local _row = DASH_AUTO_TICKS[memory.readbyte(0xFF8B82)]
	if _row == nil then return nil end
	return _row[_field]
end

local function kd_delay_ticks()
	local _d = globals and globals.options and globals.options.gc_delay
	-- IN SEQUENCE MODE THE FIRST STEP'S WAIT IS THIS DELAY (v300).
	--
	-- "Dragon punch on the fifth tick after the guard" is exactly what this
	-- offset already does: the motion goes in at once and only the press waits,
	-- which is the only way to put a press on a named tick. So the sequence's
	-- first step asks for it here rather than growing a second mechanism
	-- beside it, and Guard Action Delay is greyed out while it does.
	--
	-- The two agree on Auto without conversion: the editor stores -1 and
	-- everything below already reads negative as "the per-character dash
	-- value".
	if globals and globals.dummy and globals.dummy.guard_action == 'sequence' then
		local _w = actionSequenceRunnerModule.first_wait("reversal")
		if _w ~= nil then _d = _w end
	end
	if type(_d) ~= "number" then return 0 end
	-- NEGATIVE IS "Auto", NOT A DELAY (v198).
	--
	-- v197 used 0 for this, which took the only way to ask for no delay at all.
	-- The menu carries -1 now and draws it as Auto, so 0 means zero again and
	-- the automatic value is a separate choice the user can move off at any
	-- time. Auto on anything that is not a dash is simply 0.
	if _d < 0 then
		_d = dash_attack_ticks() or 0
	end
	if _d > 30 then _d = 30 end
	return _d
end

-- Ticks after the free-1 signature that the press belongs on.
--   special      free-1 + delay   -> offset 0 + delay
--   everything   free+0 + delay   -> offset 1 + delay
local function kd_press_base()
	return counter_is_special() and 0 or 1
end

local function kd_press_offset()
	return kd_press_base() + kd_delay_ticks()
end

-- Whether the lever stays down while the button waits.
--
-- v173 released it for dashes, on the reasoning that a dash is a tap and the
-- edge is all the game needs. That is true of STARTING the dash and wrong
-- about keeping it: reported from play, a dash attack came out at delay 0-3
-- and turned into a walking attack at 4. The run ends when the direction goes,
-- so by the fourth tick there is no dash left to cancel - exactly what holding
-- forward is for when a player does this by hand.
--
-- So everything holds except a special. A special has already been matched and
-- the recogniser keeps it for 14-19 ticks (0x02A55A); leaving the last
-- direction down would only add a walk and risk the press reading as a command
-- normal instead.
--
-- NOTE: a fixed-length dash still runs out. Past its own length the attack is
-- a walking one no matter what is held - that is the character, not the tool.
local function kd_holds_direction()
	return not counter_is_special()
end

-- HOW FAR IN FRONT OF THE DASH THE FIRST TAP MAY SIT.
--
-- Measured on the v176 batch, ground hit stun, forward dash + HP - the last
-- tick the lever was down before the free-1 signature, against whether $06
-- ever became 0x14:
--
--     tap on free-2    dash x12        no tap at all    NO dash x8
--     tap on free-3    dash x3
--     tap on free-4    dash x3
--     tap on free-10   dash x1
--
-- So the gap is not what fails, and nothing within ten ticks fails. Kept here
-- because it is the reason two different fixes were wrong: v177 moved the tap
-- (placement was never the problem) and v178 added one (it was never missing
-- once the delay stopped being applied twice - see v179).

local fast_prev05 = nil
local fast_wait   = nil

-- Hand the result to the HUD, and put it in the recording so a batch can be
-- checked without watching the screen.
local function fastest_report(_late, _act)
	if globals == nil then return end
	globals.p2_fastest = {
		late  = _late,
		act   = _act,
		-- A character with no free-1 signature opens its input window on the
		-- free tick itself, so its special is earliest on free+1 and "+1F"
		-- would be scolding the tool for doing the best that exists. Measured:
		-- Q-Bee's in-place wake-up is +1 on 13 of 13.
		nosig = KD_NO_SIG[memory.readbyte(0xFF8B82)] and true or false,
		frame = (emu ~= nil and emu.framecount) and emu.framecount() or 0,
	}
	-- val = frames late, pc = ($05,$06) packed. The pair is what names an
	-- action the table does not know yet.
	debugKnockdownModule.mark_write("fastest", _late,
		memory.readbyte(0xFF8805) * 256 + memory.readbyte(0xFF8806))
end
-- Last ($125,$122) pair pushed to the input history, so held states are not
-- pushed again on every tick.
local tick_input_last = -1
-- Same, for P1's bar along the bottom.
local p1_tick_input_last = -1
-- The guard cancel window state, carried across ticks so the transitions
-- can be spotted. Mirrors handle_gc_event() in inputHistory.lua.
local p1_gc_state = "p1_gc_none"
-- The tick the window opened on, so the label can say how far into it the
-- cancel came out. p1_tick_seq is monotonic, so this is a plain subtraction -
-- $FF8081 is a byte and wraps.
local p1_gc_open_seq = nil

-- THE WINDOW, ONE TICK AT A TIME.
--
-- Same test as handle_gc_event() in inputHistory.lua: $158 is the block
-- clock, and the cancel came out if $06 is a special (0x0E), an ES (0x10) or
-- an EX (0x12) on the tick it reaches zero. Checked against 35 attempts
-- logged both ways (analysis/gc_success_probe_20260915b.log).
--
-- SUCCESS IS ALSO REACHABLE STRAIGHT FROM BEGIN. It used to require
-- in_progress, and a cancel that came out on the tick right after the window
-- opened arrives while the state is still begin: no branch matched, the
-- state stayed begin, and it stayed there until the NEXT guard - so the
-- cancel came out, was correct, and drew no SUCCESS at all. Cancelling on
-- the guard itself is exactly when that happens (user, 2026-09-23).
--
-- Pure, and out of the hook, so it can be driven tick by tick offline -
-- the hook only runs when the game reaches 0x0221CC.
local function gc_next_state(_state, _clock, _act)
	if _clock == 0 and (_state == "p1_gc_in_progress"
						or _state == "p1_gc_begin") then
		if _act == 0x0E or _act == 0x10 or _act == 0x12 then
			return "p1_gc_success"
		end
		return "p1_gc_ended"
	end
	if _state == "p1_gc_none" and _clock > 0 then return "p1_gc_begin" end
	if _clock > 0 then return "p1_gc_in_progress" end
	if _state == "p1_gc_ended" or _state == "p1_gc_success" then
		return "p1_gc_none"
	end
	return _state
end

-- ------------------------------------------------------- GC COMMAND TRACE
-- WHAT THE GAME ACCEPTED ON THE WAY TO A GUARD CANCEL, AND WHEN.
--
-- The engine keeps one 8 byte block per command at $300..$358, walked by
-- 0x029F4A. Which block is the guard cancel's is per character (GC_BLOCK
-- below) and every one of them is a DPF.
--
--   +0  WHICH HANDLER runs: 02 while directions are being taken, 04 once it
--       is waiting for the button. NOT the step number - reading it as one
--       made a dragon punch look like two directions (2026-09-23).
--   +1  THE STEP. 02 / 04 / 06 are the first, second and third direction.
--   +4  ticks the current step has left; it goes back up when one is taken.
--
-- A direction is 'taken' when +1 rises, and the lever ON THAT TICK is what
-- was taken - read from the game rather than from what we think a dragon
-- punch is, so a shortcut the engine allowed still shows what it allowed.
--
-- NOTHING IS DRAWN UNTIL A GUARD. Rows are collected all the time, because
-- the motion often starts before the guard, but a trace only becomes visible
-- when one arrives - otherwise every lever wiggle would draw (user,
-- 2026-09-23).
local GC_BLOCK = {
	[0x00] = 0x340, [0x01] = 0x308, [0x02] = 0x328, [0x03] = 0x308,
	[0x04] = 0x338, [0x05] = 0x318, [0x06] = 0x330, [0x07] = 0x310,
	[0x08] = 0x300, [0x09] = 0x348, [0x0A] = 0x308, [0x0B] = 0x338,
	[0x0C] = 0x330, [0x0D] = 0x310, [0x0E] = 0x310, [0x0F] = 0x308,
}
-- HOW LONG A DEAD COMMAND STAYS WORTH SHOWING.
--
-- The wait between two inputs of a special is rolled, and 15 ticks is the
-- widest a player gets, so 16 covers a guard still inside the reach of the
-- motion that just died (user, 2026-09-24).
--
-- NOT the 14..19 the step timer is loaded with from 0x02A55A - that byte is
-- not the window a player experiences; the acceptance around it is its own
-- thing (user).
local REATTACH_TICKS = 16
local P1_BASE = 0xFF8400
local TRACE_ROWS = 8
-- The attempt being collected. rows are {kind, tick, value}.
local gct = { rows = {}, guard = nil, prog = nil, step = nil, done = nil, at = nil }

local function gct_reset()
	gct.rows, gct.guard, gct.done, gct.at = {}, nil, nil, nil
	gct.prog, gct.step = nil, nil
end

local function gct_add(kind, tick, value)
	if #gct.rows >= TRACE_ROWS then table.remove(gct.rows, 1) end
	gct.rows[#gct.rows + 1] = { k = kind, t = tick, v = value }
end

-- WHAT IS COLLECTED AND WHAT IS SHOWN ARE NOT THE SAME THING.
--
-- A motion often starts before the guard, so collecting never stops. But a
-- finished trace was being thrown away the moment the next motion began, and
-- after a successful cancel the stick is usually still moving - so the
-- result vanished a tick or two after it appeared, before anyone could read
-- it (user, 2026-09-23).
--
-- So the last attempt THAT HAD A GUARD IN IT stays on screen, and the one
-- being collected only takes its place once it has a guard of its own. No
-- timer decides this: a guard is what a trace is about, so a guard is what
-- replaces one.
--
-- Published whole, so the drawing never sees half an update. gct_reset makes
-- a NEW rows table rather than emptying this one, which is what lets the
-- shown copy go on pointing at the old one.
local gct_shown = nil
local function gct_publish()
	if globals == nil then return end
	if gct.guard ~= nil then
		gct_shown = { rows = gct.rows, guard = gct.guard,
		              done = gct.done, at = gct.at }
	end
	globals.gc_trace = gct_shown
end

-- THE DIRECTION, READ THE SAME WAY THE INPUT VIEWER READS IT.
--
-- The point of this readout is to be held against the bar along the bottom,
-- so an arrow has to mean the same thing in both places. The surest way to
-- get that is not to have a second opinion: this is read_game_input's rule
-- from inputHistory.lua, byte for byte - $125 for the lever and $b for the
-- facing, swapped back the same way, turned into the same numpad number that
-- indexes the same arrow images.
--
-- TWO WRONG ANSWERS CAME BEFORE THIS ONE, both from deciding the rule
-- instead of borrowing it (user, 2026-09-23). First $12B was drawn raw and a
-- 1P dragon punch came out as a 2P one. Then $12B was swapped on $120,
-- because 0x0221CC picks $120 over $b on the ground - true of what the
-- ENGINE matches on, but $120's own sense of which way is which was never
-- checked, and the arrows stayed mirrored.
--
-- $125 is the PREVIOUS tick's direction and is the steady one: measured over
-- recorded play, $123 changed value on 20.3% of frames during a held
-- horizontal against 4.2% for $125 (inputHistory.lua). The bar lags by that
-- same tick, so the two still line up.
local function gct_numpad()
	local _d = memory.readbyte(P1_BASE + 0x125)
	local _b0 = (_d % 2) >= 1
	local _b1 = (math.floor(_d / 2) % 2) >= 1
	local _left, _right
	if memory.readbyte(P1_BASE + 0x00B) == 0 then
		_left, _right = _b1, _b0
	else
		_left, _right = _b0, _b1
	end
	local _down = (math.floor(_d / 4) % 2) >= 1
	local _up   = (math.floor(_d / 8) % 2) >= 1
	if _down then
		if _left then return 1 elseif _right then return 3 else return 2 end
	elseif _up then
		if _left then return 7 elseif _right then return 9 else return 8 end
	end
	if _left then return 4 elseif _right then return 6 end
	return 5
end

-- WHICH BUTTONS FINISHED IT, IN THE VIEWER'S OWN ORDER.
--
-- $1AC and $1AE are the press edges the engine's button step reads
-- (0x029FEC): bits 8/9/10 are the punches, 12/13/14 the kicks. Returned as
-- LP MP HP LK MK HK so the drawing can lay them out as the input viewer
-- does - two rows of three - rather than spelling a name. A kick completed a
-- guard cancel in the measurements, so a punch-shaped label was never safe.
--
-- No bitwise operators in Lua 5.1, so the bits are divided out.
local GCT_BITS = { 8, 9, 10, 12, 13, 14 }
local function gct_buttons()
	local _w = memory.readword(P1_BASE + 0x1AC)
	local _v = memory.readword(P1_BASE + 0x1AE)
	local _out = {}
	for _i, _bit in ipairs(GCT_BITS) do
		local _p = 2 ^ _bit
		_out[_i] = (math.floor(_w / _p) % 2 == 1)
					or (math.floor(_v / _p) % 2 == 1)
	end
	return _out
end

local function gct_tick(_gc)
	local _blk = GC_BLOCK[memory.readbyte(P1_BASE + 0x382)]
	if _blk == nil then gct_reset() gct.motion = {} return end
	local _now = globals.p1_tick_seq or 0
	local _step = memory.readbyte(P1_BASE + _blk + 1)
	local _prog = memory.readbyte(P1_BASE + _blk)
	local _was_prog, _was_step = gct.prog or 0, gct.step or 0

	-- WHICH TICK OF THE GUARD POSE'S PERSISTENCE THE BLOCK LANDED ON.
	--
	-- Letting go of back does not drop the guard pose at once: it runs on for
	-- a few ticks, and a hit inside that span is still blocked. Guard cancels
	-- lean on it - the motion leaves the guard direction and the pose covers
	-- the gap (user, 2026-09-25). The game keeps it in $07 while $06 is 0x0C
	-- (the handler is 0x022FDA, one branch per value):
	--
	--     $07 00   standing, the guard direction is held
	--     $07 02   standing, released, and the pose is persisting
	--     $07 04   crouching, the guard direction is held
	--     $07 06   crouching, released, and the pose is persisting
	--     $07 08   the pose's first tick, before it picks 00 or 04
	--
	-- Only 02 was counted at first, so a crouching block never read as
	-- persisting (user, 2026-09-25: "does G-Persist show on a crouch
	-- guard?"). No log had caught 06 - every crouch guard in them was hit
	-- while still held - so it comes from the ROM: 04 steps to 06 exactly
	-- where 00 steps to 02.
	--
	-- Measured on Demitri, 65 blocks: persisting blocks landed 1 to 6 ticks
	-- in; with the lever left at neutral the pose ran out after 5 to 8. Letting
	-- go of back steps into persisting first, whatever the lever; from there
	-- a lever that is only forward - not down-forward - walks (0x027122).
	-- Cross-up blocks read 00 -
	-- the guard direction follows the attacker, not the facing byte - so they
	-- are held blocks, correctly (VSAV_MEMORY_NOTES, guard pose persistence).
	--
	-- The pose ends on the contact tick ($06 leaves 0x0C with $05 set), which
	-- is a tick before the cancel window opens (the guard row below says
	-- why), so the count is taken there and kept for the guard row. Dropped
	-- once the stun is over, so a hit that opened no window cannot hand its
	-- count to a later block.
	-- Fields of gct, not locals: this file's main chunk is at the limit.
	local _s06 = memory.readbyte(P1_BASE + 0x06)
	local _s05 = memory.readbyte(P1_BASE + 0x05)
	if _s06 == 0x0C then
		local _s07 = memory.readbyte(P1_BASE + 0x07)
		if _s07 == 0x02 or _s07 == 0x06 then
			if gct.pers_start == nil then gct.pers_start = _now end
		else
			gct.pers_start = nil
		end
		gct.pers_n = nil
	elseif gct.pose_prev == 0x0C then
		-- A PERSISTENCE THAT BEGAN AND WAS HIT BETWEEN TWO LOOKS.
		--
		-- This hook runs at the top of P1's update, before the pose handler.
		-- Letting go of back on the tick before the hit turns the pose to
		-- persisting further down that same update, and the hit is written
		-- after it - as $05 02 $06 00 $07 00, over the 02 this never saw. It
		-- read as a plain Guard although back was already let go (user,
		-- 2026-09-25: ← held 4, then neutral, blocked on the first neutral
		-- tick).
		--
		-- The pose tests bit 0 of $12B, the facing-corrected lever, to stay
		-- held (0x027694; $3B2 skips the test). By this hook that word has
		-- moved to $12C (0x022120), so $12D is the very lever the pose last
		-- tested. Clear there means it stepped to persisting: tick 0.
		if _s05 ~= 0 and gct.pers_start == nil
			and memory.readbyte(P1_BASE + 0x3B2) == 0
			and memory.readbyte(P1_BASE + 0x12D) % 2 == 0 then
			gct.pers_start = _now
		end
		if _s05 ~= 0 and gct.pers_start ~= nil then
			gct.pers_n = (_now - gct.pers_start) % 256
		else
			gct.pers_n = nil
		end
		gct.pers_start = nil
	elseif _s05 == 0 then
		gct.pers_n = nil
	end
	gct.pose_prev = _s06

	-- THE TICK THE BLOCK LANDED, FOR THE GUARD ROW.
	--
	-- The hit is written into P1 as $05 02, $06 00, $07 00 (0x0182D8 and its
	-- neighbours, through A1 - code writing some other object), and P1's own
	-- handler moves $07 on
	-- the next time P1 runs - loading the block clock as it does. So that
	-- state is the contact, and this hook sees it for one tick. Only its first
	-- tick is taken: a hit that was not blocked was once logged holding it for
	-- two. Dropped once the stun is over, like the count above.
	local _pre = _s05 == 0x02 and _s06 == 0x00
		and memory.readbyte(P1_BASE + 0x07) == 0x00
	if _pre and not gct.pre_prev then
		gct.contact = _now
	elseif _s05 == 0 then
		gct.contact = nil
	end
	gct.pre_prev = _pre

	-- WHICH BYTE CARRIES THE STATE, AND WHY IT IS NOT THE STEP NUMBER.
	--
	-- +0 is the handler the command sits in: 0 waiting for a first
	-- direction, 2 waiting for a middle one, 4 waiting for the button. +1 is
	-- the step index inside the motion, and the game does NOT clear it when
	-- an attempt dies - it keeps its last value until a later attempt writes
	-- over it.
	--
	-- So an attempt ends when +0 falls back to 0, and a fresh first
	-- direction is +0 leaving 0. Reading either of those off +1 misses them.
	--
	-- Replaying the 2026-09-23 log (6831 ticks) through this: 47 attempts
	-- died part-way, and the version that watched +1 saw NONE of them. 25 of
	-- those were restarted while +1 still read 02, which the old reading
	-- also could not see - two goes then collect into one trace, and the gap
	-- drawn between two directions is the sum of both waits. That is the
	-- shape of the 19t the trace showed once (2026-09-24), but the log holds
	-- no instance that reached the drawing, so the link is not proven.
	local _restart = _was_prog == 0 and _prog ~= 0
	local _dropped = _was_prog ~= 0 and _prog == 0
	-- A direction landed if the handler moved on, OR if the step index
	-- advanced. The index has to be able to carry it alone: when the button
	-- lands on the same tick as the last direction, +0 falls back to 0 in
	-- that same tick, and requiring +0 to be non-zero drops the direction.
	-- One of the three cancels in the 2026-09-23 log does exactly this
	-- (seq=5576, 02.04 -> 00.06 with the success event).
	local _took = _prog > _was_prog or _step > _was_step

	-- THE MOTION THAT IS ALIVE RIGHT NOW, WHATEVER THE TRACE IS SHOWING.
	--
	-- A finished trace is held on screen until the next attempt, and nothing
	-- goes into its rows while it is held. The command can still be half way
	-- through a motion, though: a blocked chain opens a fresh window on every
	-- hit, so one window can run out mid-motion and the next guard finish it.
	-- That cancel drew as a single direction and a button (user, 2026-09-25,
	-- guarding Aulbath's five-hit jump chain) - the directions taken before the
	-- new guard had gone nowhere, although the input viewer had all of them.
	--
	-- So the live motion is followed on its own, from its first direction to
	-- the tick +0 falls back to 0, and a guard that ends the hold takes it
	-- over. The copy is taken before this tick is added, so a direction that
	-- lands on the guard's own tick is recorded once, by the path below.
	-- A field of gct and not a local: this file's main chunk is at Lua 5.1's
	-- limit of 200 locals.
	local _dir_v = _took and gct_numpad() or nil
	local _carry = {}
	for _i, _m in ipairs(gct.motion or {}) do _carry[_i] = _m end
	if _restart then gct.motion = {} end
	if _took then
		gct.motion = gct.motion or {}
		gct.motion[#gct.motion + 1] = { t = _now, v = _dir_v }
	end
	if _dropped then gct.motion = {} end

	-- A GUARD THAT LANDS RIGHT AFTER A DEAD COMMAND BELONGS TO THE SAME GO.
	--
	-- One input's grace is random, and REATTACH_TICKS is the widest it gets,
	-- so a guard closer than that is inside the span the motion was still
	-- live for. Throwing the rows away there loses exactly the thing worth
	-- seeing - the inputs that were too slow, and then the guard (user,
	-- 2026-09-24).
	--
	-- The expiry becomes a row of its own rather than vanishing, so the rows
	-- above it are still marked as belonging to the attempt that died. This
	-- falls through rather than returning, so a direction taken on the same
	-- tick as the guard is still recorded - and the guard row is left to the
	-- same code as every other guard, so it is placed the same way.
	if gct.done == "Cmd Expired" and _gc == "p1_gc_begin"
		and gct.at ~= nil and ((_now - gct.at) % 256) <= REATTACH_TICKS then
		gct_add("dead", gct.at, gct.done)
		gct.done, gct.at = nil, nil
		gct.guard = nil
	elseif gct.done == "Cmd Expired" and _restart and gct.guard ~= nil
		and _gc == "p1_gc_in_progress" then
		-- A DEAD COMMAND IS NOT THE END WHILE THE GUARD IS STILL OPEN.
		--
		-- The cancel window outlasts one go at the motion, so dropping it and
		-- inputting it again cancels off the SAME guard. Resetting here threw
		-- that guard away, and the attempt that then succeeded had no guard of
		-- its own - so it was never published, and the screen kept showing the
		-- expiry while the input viewer said SUCCESS (user, 2026-09-24).
		--
		-- The 2026-09-23 log holds 11 windows and not one of them is restarted
		-- after a drop, which is why this was never seen there. The evidence
		-- is two screenshots: the trace stopped at Cmd Expired three ticks
		-- after the guard while the input viewer counted SUCCESS twelve ticks
		-- off that same guard.
		gct_add("dead", gct.at, gct.done)
		gct.done, gct.at = nil, nil
	elseif gct.done ~= nil then
		-- A finished attempt stays up until the next one starts.
		if _gc == "p1_gc_begin" or _restart then
			gct_reset()
			-- A guard that ends the hold takes the motion still alive into the
			-- new trace, above the guard - it is the start of this cancel. Not
			-- one that dies on this very tick. A restart needs nothing here:
			-- +0 was 0 a tick ago, so the motion was already emptied.
			if not _dropped then
				for _, _m in ipairs(_carry) do gct_add("dir", _m.t, _m.v) end
			end
		else
			gct.prog, gct.step = _prog, _step
			gct_publish()
			return
		end
	end

	if gct.done == nil then
		-- A direction the game took.
		if _took then
			gct_add("dir", _now, _dir_v)
		end
		if _gc == "p1_gc_begin" and gct.guard == nil then
			-- THE GUARD ROW SITS AT THE CONTACT, NOT AT THE WINDOW.
			--
			-- The window opens a tick after the block lands. This hook runs at
			-- the top of P1's update (0x022114 reads the input, then 0x0222AC
			-- dispatches on $04), the hit is written from outside that update,
			-- and the block clock is loaded further down it by the guard handler
			-- (0x023960). So a direction taken on the tick the window opened
			-- came after the block, yet it was drawn above the guard, 0t apart -
			-- which read as blocking with the lever already forward (user,
			-- 2026-09-25: G-Persist 5 (0t) under a forward that came the tick
			-- after the contact).
			--
			-- So the row takes the contact tick and moves up past whatever came
			-- after it, and a tie keeps the direction first. Every other row is
			-- already in tick order, so this keeps the whole trace in it - a
			-- command that died between the contact and the window goes below
			-- the guard, where the drawing counts both from the input before
			-- them instead of wrapping to 255t. With no contact seen, the
			-- window's own tick is all there is.
			--
			-- gct.guard stays the window's tick: Success and GC Expired count
			-- from it, as the SUCCESS count in the input viewer does.
			gct.guard = _now
			local _at = gct.contact or _now
			gct_add("guard", _at, gct.pers_n)
			local _rows, _i = gct.rows, #gct.rows
			while _i > 1 do
				local _p = _rows[_i - 1]
				local _d = (_p.t - _at) % 256
				if _d == 0 or _d > (_now - _at) % 256 then break end
				_rows[_i - 1], _rows[_i] = _rows[_i], _p
				_i = _i - 1
			end
			gct.pers_n, gct.contact = nil, nil
		end
		if _gc == "p1_gc_success" then
			gct_add("btn", _now, gct_buttons())
			gct.done, gct.at = "Success", _now
		elseif _gc == "p1_gc_ended" then
			gct.done, gct.at = "GC Expired", _now
		elseif _dropped and #gct.rows > 0 then
			-- The motion did not stay together. A cancel that succeeds drops
			-- +0 on the same tick as the success event, so this has to come
			-- after both events, not before them (log, 2026-09-24).
			--
			-- Kept even when no guard has happened yet: without that, the
			-- re-attach above can never fire for the case it exists for -
			-- the command dying first and the guard arriving after.
			gct.done, gct.at = "Cmd Expired", _now
		end
	end
	gct.prog, gct.step = _prog, _step
	gct_publish()
end
-- --------------------------------------------------- END GC COMMAND TRACE

-- WHEN THE COUNT STARTS, AND WHAT IT COMES TO.
--
-- Pulled out of the hook on purpose. The hook only runs when the game
-- reaches 0x0221CC, so nothing offline can drive it; this is lifted out of
-- the file and run tick by tick by analysis/test_gc_success_ticks.lua, the
-- same way make_input_sequence is lifted out of controller.lua.
--
-- Returns the tick count to hang on this tick's column (nil on every tick
-- but the one a cancel came out on) and the opening tick to carry forward.
local function gc_tick_count(_gc, _open_seq, _seq)
	if _gc == "p1_gc_begin" then return nil, _seq end
	if _gc == "p1_gc_success" then
		if _open_seq == nil then return nil, nil end
		return _seq - _open_seq, nil
	end
	return nil, _open_seq
end
memory.registerexec(0x0221CC, function()
	local _who = memory.getregister("m68000.a6")

	-- P1'S BAR, ALSO PER TICK.
	--
	-- The bar was built once per DISPLAYED frame, and the input that completes
	-- a command is a one-tick event: measured over 19 guard cancels, the frame
	-- sampler saw the qualifying press or release 3 times and missed it 16,
	-- with 10 of those drawing SUCCESS against no input column at all. The
	-- cancel itself was fine every time - only the drawing lost it
	-- (analysis/gc_success_probe_20260915b.log).
	--
	-- $125, NOT $123, which is the opposite of the choice made for the dummy
	-- below. The note there explains why $123 suits a dummy: it is the current
	-- tick's direction and the dummy holds nothing, so the flicker between the
	-- two horizontal bits cannot bite. A human holds directions constantly and
	-- it would. $125 is the previous tick's direction and is what the bar has
	-- always drawn from; checked against 248 lever changes in the probe logs,
	-- it turns over cleanly at tick resolution - one A->B->A inside two ticks
	-- in the whole set.
	--
	-- Pairing this tick's buttons with last tick's direction is also the right
	-- way round for a motion: in 6 2 3 + button the button lands a tick after
	-- the 3, so $125 still reads 3 when the button arrives.
	if _who == 0xFF8400 then
		-- Monotonic, unlike $FF8081, which is a byte and wraps. inputHistory
		-- uses this as its clock so it can tell two ticks inside one displayed
		-- frame apart - without it the history appends at most one column per
		-- frame however many inputs happened.
		globals.p1_tick_seq = (globals.p1_tick_seq or 0) + 1
		local _btn = memory.readbyte(0xFF8522)
		local _dir = memory.readbyte(0xFF8525)
		local _v = _dir * 256 + _btn

		-- THE GUARD CANCEL STATE, ON THE SAME CLOCK AS THE COLUMNS.
		--
		-- inputHistory.lua worked this out once per DISPLAYED frame and stamped
		-- the answer onto every column built that frame. While a frame produced
		-- at most one column that was invisible; now that a frame can produce
		-- three or four, SUCCESS lands on whichever of them came first and the
		-- input that actually completed the cancel can be several columns away.
		--
		-- Same test as handle_gc_event(): the window is the block clock $158,
		-- and the cancel came out if $06 is a special (0x0E), an ES (0x10) or an
		-- EX (0x12) on the tick it reaches zero. Checked against 35 attempts
		-- logged both ways - tick side and frame side agreed on every one, so
		-- moving it here changes WHERE the label lands, not WHAT it says
		-- (analysis/gc_success_probe_20260915b.log).
		local _clock = memory.readbyte(0xFF8558)
		local _gc = gc_next_state(p1_gc_state, _clock,
			memory.readbyte(0xFF8406))
		-- HOW FAR INTO THE WINDOW THE CANCEL CAME OUT, IN TICKS.
		--
		-- $158 takes 14 on a guard and 0x022492 removes one EVERY TICK, so this
		-- is a tick count or it is nothing. It is measured here rather than in
		-- inputHistory because that side runs on displayed frames - at turbo 3
		-- that is 3 frames to 4 ticks, and the number would be frames under a
		-- tick label.
		--
		-- Counted from the tick the window OPENED rather than read out of $158,
		-- because a cancel clears the clock early and the last value before it
		-- was cleared is already gone by the time we know it succeeded. Both
		-- ends are sampled in this one hook, so whatever offset the hook sits
		-- at within a tick cancels out of the difference.
		local _gct
		_gct, p1_gc_open_seq = gc_tick_count(_gc, p1_gc_open_seq, globals.p1_tick_seq)
		gct_tick(_gc)
		local _gc_changed = _gc ~= p1_gc_state
		p1_gc_state = _gc

		-- A tick earns a column when the input changed OR the window did. The
		-- second half is what puts SUCCESS on the tick it happened rather than
		-- on the first tick of the frame that noticed.
		if _v ~= p1_tick_input_last or _gc_changed then
			p1_tick_input_last = _v
			-- Nothing drains it while the menu is up, so do not fill it there:
			-- a queue held across the menu would flush stale columns the moment
			-- it closed.
			if globals.show_menu ~= true then
				local _q = globals.p1_tick_inputs
				if _q == nil then _q = {}; globals.p1_tick_inputs = _q end
				if #_q < 64 then
					table.insert(_q, { dir = _dir, btn = _btn,
						seq = globals.p1_tick_seq, gc = _gc, gct = _gct })
				end
			end
		end
		return
	end

	if _who ~= 0xFF8800 then return end

	-- THE DUMMY'S SCROLLING INPUT, SAMPLED PER TICK (v135).
	--
	-- The viewer at the top right of the screen is vsavscriptv2.lua's
	-- scrolling input, and it built P2's column from joypad.getdown(2) once per
	-- DISPLAYED FRAME. Two things break that:
	--
	--   * the wake-up motion has not gone through joypad.set() since v131, it
	--     is written straight to $394, and the pad never sees a memory write;
	--   * a displayed frame is about 1.6 game ticks during a knockdown, and
	--     every entry of the motion is exactly one tick long.
	--
	-- So sample here, where every tick is visible, and let the viewer drain it.
	-- One queued entry per tick on which the input CHANGED, which is exactly
	-- "if there was a one-tick input, it gets written".
	--
	-- $123, NOT $125. inputHistory.lua's frame read uses $125 - the low byte of
	-- $124, i.e. the PREVIOUS tick's direction - because $123 flickers between
	-- the two horizontal bits while a human holds a direction one way round
	-- (measured there: 20.3% of frames against 4.2%). Per tick that trade does
	-- not apply and it actively hurts: $122's high byte is the CURRENT tick's
	-- buttons, so pairing it with $125 would put the reversal's button next to
	-- the previous direction. $122/$123 are one word written by a single move.w
	-- at 0x02211A, so together they are coherent, and the flicker cannot bite
	-- here anyway - this samples the DUMMY, which holds nothing except when the
	-- tool is feeding it a motion.
	do
		local _btn = memory.readbyte(0xFF8922)
		local _dir = memory.readbyte(0xFF8923)
		local _v = _dir * 256 + _btn
		if _v ~= tick_input_last then
			tick_input_last = _v
			if globals ~= nil then
				local _q = globals.p2_tick_inputs
				if _q == nil then _q = {}; globals.p2_tick_inputs = _q end
				-- Bounded so it cannot grow without limit if nothing drains it
				-- (the viewer is behind a display option).
				if #_q < 64 then
					table.insert(_q, { dir = _dir, btn = _btn,
						facing = memory.readbyte(0xFF880B) })
					-- The exact stream the viewer consumes, in the recording.
					-- kd_report.py --viewer replays the column from it, so
					-- "the history looks wrong" can be checked here instead of
					-- off a screenshot. val = $122<<8 | $123, pc = facing.
					debugKnockdownModule.mark_write("p2_inp", _v,
						memory.readbyte(0xFF880B))
				end
			end
		end
	end

	-- HOW LATE THE DUMMY'S ACTION WAS, IN FRAMES (v137).
	--
	-- The game shows REVERSAL by itself, but only for a special on the first
	-- free frame. A normal, a throw, a jump or a dash coming out on that same
	-- frame is just as perfect and the game says nothing, so there is no way to
	-- tell "frame one" from "frame three" while practising.
	--
	-- The test is the one classify_reversals.py has always used, and it is
	-- exact: $05 goes 0x02 -> 0x00 on the tick the character becomes free, and
	-- whatever $06 reads on that tick is the action that started ON it. If $06
	-- is still 0x00 the character did nothing that frame, so count ticks until
	-- it becomes an action - that count IS how many frames late the input was.
	--
	-- One game tick is one game frame here. The 1.6 ticks per DISPLAYED frame
	-- that the arming code has to worry about is the Lua callback rate, not the
	-- game's; move timing is counted in ticks and always has been.
	do
		local _now05 = memory.readbyte(0xFF8805)
		local _now06 = memory.readbyte(0xFF8806)
		-- The free tick itself: anything that is not idle and not the
		-- pre-free substate is an action that started ON it.
		local _act = nil
		if not FASTEST_IDLE[_now06] then
			_act = fastest_name(_now06)
		end
		if fast_prev05 == 0x02 and _now05 == 0x00 then
			if _act ~= nil then
				fastest_report(0, _act)
			else
				fast_wait = 0
			end
		elseif fast_wait ~= nil then
			fast_wait = fast_wait + 1
			-- $05 GOING NON-ZERO IS NOT AUTOMATICALLY A FAILURE.
			--
			-- It used to abort here, which is the first reason a throw showed
			-- nothing: the throw starts and the master state leaves 0x00 on the
			-- same tick, so the count was thrown away before $06 was even
			-- looked at. Only $06 == 0x00 with $05 non-zero is a real abort -
			-- that is the impact freeze of being hit, i.e. the dummy was
			-- interrupted rather than having acted.
			if not FASTEST_IDLE[_now06] then
				fastest_report(fast_wait, fastest_name(_now06))
				fast_wait = nil
			elseif _now05 ~= 0x00 or fast_wait > FASTEST_GIVE_UP then
				fast_wait = nil
			end
		end
		fast_prev05 = _now05
	end

	-- THE TRACE TABLE IS 25 MEMORY READS. DO NOT BUILD IT FOR NOTHING.
	--
	-- Lua evaluates the argument before the call, so mark_tick() returning
	-- early when logging is off does not save any of this - the table was
	-- already built and thrown away, every tick of every hit and block.
	if not debugKnockdownModule.enabled() then return end

	local _st1 = memory.readbyte(0xFF8805)
	local _d   = player_objects and player_objects[2]
	local _seq = _d and _d.pending_input_sequence
	if _st1 ~= 0 or _seq ~= nil then
		tick_tail = 24
	elseif tick_tail > 0 then
		tick_tail = tick_tail - 1
	else
		return
	end
	debugKnockdownModule.mark_tick({
		g = memory.readbyte(0xFF8081),
		a = _st1,
		b = memory.readbyte(0xFF8806),
		c = memory.readbyte(0xFF8807),
		n = memory.readbyte(0xFF8820),
		k = memory.readbyte(0xFF89A7),
		i = memory.readbyte(0xFF8922) * 256 + memory.readbyte(0xFF8923),
		e = memory.readbyte(0xFF8926) * 256 + memory.readbyte(0xFF8927),
		j = memory.readbyte(0xFF8B94) * 256 + memory.readbyte(0xFF8B95),
		-- The two gates at 0x024E78 / 0x024E82 that can stop the wake-up
		-- handler from advancing on a tick, plus $11f (0x024E5C) and $21
		-- (animation-finished). If a signature run lasts two ticks, one of
		-- these has to differ between them - that is what this is for.
		z = memory.readbyte(0xFF815D),
		w = memory.readbyte(0xFF8994),
		v = memory.readbyte(0xFF891F),
		u = memory.readbyte(0xFF8821),
		-- $140, the recovery-variant selector (0x0A = knockdown wake-up,
		-- 0x04 = air-hit landing). Needed now that the trace is being used
		-- for hit-stun as well - without it a hit-stun transition cannot be
		-- told apart from a knockdown one in the same recording.
		r = memory.readbyte(0xFF8940),
		-- $164, the guard pushback timer. This is what the COUNTER triggers on
		-- (playerObject.lua watches it go from non-zero to zero), and nothing
		-- has ever checked whether that moment is the tick the dummy actually
		-- becomes actionable - the block path computes that from $158 plus a
		-- per-strength lead instead (BLK_LEAD). Traced so the two can be
		-- compared rather than assumed equal.
		pbk = memory.readword(0xFF8964),
		-- $59 is the reaction type the ATTACK carries (0x0764EA+5), and it is
		-- the only thing that picks the guard script - so it, not the
		-- defender's state, is what makes normal demon and diagonal demon
		-- differ. gsl is the length that script predicts; the answer-check is
		-- gsl against the pbk the tick guard ends.
		-- WHICH DEMON THIS WAS.
		--
		-- Zero demon and normal demon are the SAME move at different range, so
		-- no move id can tell them apart - $0A, $54 and $5A are hit-stun
		-- fields and read 0/255/0 through a guard, and Demitri's $382 is 1 for
		-- all of them. The distance at the moment of the block is the only
		-- thing that separates them. $10 is 16.16, so the word is the integer
		-- X.
		-- WHICH HIT OF THE MOVE CONNECTED.
		--
		-- A demon cradle is multi-hit and $59 reads 2 for every range, so the
		-- guard script is common and only the freeze differs. If the freeze is
		-- per-hit data then the cel that was live at the block should differ
		-- between the two ranges. $1c is the attacker's current cel, $0a its
		-- hitbox index into the $8c table and $17 the flags the proximity
		-- check reads - low byte $17, high byte $0a.
		p1cel = memory.readdword(0xFF841C) % 0x10000,
		p1box = (function()
			local _p = memory.readdword(0xFF841C)
			if _p == nil or _p < 0x1000 or _p >= 0x1000000 then return nil end
			return memory.readbyte(_p + 0x0A) * 256 + memory.readbyte(_p + 0x17)
		end)(),
		p1x = memory.readword(0xFF8410),
		p2x = memory.readword(0xFF8810),
		s59 = memory.readbyte(0xFF8859),
		gsl = guard_script_len(memory.readbyte(0xFF8859)),
		-- $26 IS THE STUN ITSELF, AND IT IS A COUNTDOWN.
		--
		--     027D46: move.b ($54,A6), D0          ; per-attack index
		--     027D4A: move.b (A0,D0.w), ($26,A6)   ; table -> $26
		--     024CA4: subq.b #1, ($26,A6)          ; one off per tick
		--     024CA8: bne    $24cc0                ; zero is the recovery
		--
		-- So the ticks remaining until the character can act are simply $26 -
		-- no lead table, no wait, no prediction. BLK_WAIT and BLK_LEAD are keyed
		-- on $59 (strength), and measurement says that is the wrong key: the
		-- same $59 = 2 produced 22, 24 and 34 tick blocks. $54 and $59 are two
		-- separate fields of the same reaction entry (0x0764EA, 8 bytes each,
		-- +5 is $59), so strength and stun length are independent by design.
		--
		-- Traced to confirm it lines up with free before anything is rebuilt on
		-- it.
		st26 = memory.readbyte(0xFF8826),
		-- The animation walk. If this equals the distance to the free-1
		-- signature, it replaces BLK_LEAD, BLK_WAIT and every other guess.
		anl = anim_ticks_left(),
		-- TEMPORARY SWEEP (v230). Nothing already traced counts down to the
		-- free-1 signature during a BLOCK - checked across every integer field.
		-- So the byte that governs guard recovery is not one we are watching.
		-- $158 (guard cancel), $1ab (push block) and $1a7 (wake-up) all live in
		-- $100-$1FF, so that page is swept per tick while the character is in
		-- stun, and the analysis looks for the byte that reaches zero at free-1.
		--
		-- Delete this once the byte is known - it is 512 characters a tick.
		-- (the sweep is gone: see sig_callers in debugKnockdown.lua)
		-- $105, the attack flag (rawStateService.lua reads the P1 copy at
		-- 0xFF8505 for the same purpose). Needed because $06 STAYS 0x14 for
		-- the whole dash - a dash attack is a jump attack performed inside the
		-- dash state, so the action byte never changes and the trace could not
		-- tell "the button did something" from "the button did nothing".
		-- Measured over the v179 and v180 batches: $06 reads 14 14 14 ... on
		-- every span from the press onward, at every dash frame from 11 to 22.
		at = memory.readbyte(0xFF8905),
		-- The push block's two counters, so a batch can be read without
		-- guessing. $170 is the press count (0x027606) and $1ab is the window
		-- it has to be spent in (0x023966, 0x02249C, 0x0275D8). What matters is
		-- the value $170 reaches while $1ab is still non-zero.
		pbc = memory.readbyte(0xFF8970),
		pbw = memory.readbyte(0xFF89AB),
		-- $184 IS WHY THE COUNT STOPS (v187).
		--
		-- 0x0275E0 refuses the whole routine while $184 is non-zero, and
		-- 0x027632 sets it to 1 on the tick the push block SUCCEEDS (beside
		-- $171 = 0x10 and $5c = 1). So $170 freezing part-way through the tap
		-- train does not mean the taps were lost - it means the push block
		-- already came out and the rest were never going to be counted.
		-- Without this byte the two cases are indistinguishable in the trace,
		-- which is how the v186 batch read as a regression.
		pbok = memory.readbyte(0xFF8984),
		pbst = memory.readbyte(0xFF8971),
		-- Facing. Needed to confirm mid-motion turnarounds are happening and
		-- that each direction went in under the facing true at its own tick.
		x = memory.readbyte(0xFF880B),
		-- THE ATTACK'S OWN HIT DATA.
		--
		-- 0x075E0C loads five fields from an 8-byte-per-entry table at
		-- 0x0764EA, indexed by $a:
		--
		--     075E20  move.w (A1,D0.w),    ($54,A6)     +0
		--     075E26  move.w ($2,A1,D0.w), ($56,A6)     +2
		--     075E2C  move.b ($5,A1,D0.w), ($59,A6)     +5   the stun class
		--     075E32  move.b ($6,A1,D0.w), ($5a,A6)     +6   ?
		--     075E38  move.b ($7,A1,D0.w), ($5b,A6)     +7   ?
		--
		-- $59 is only a class - three values standing in for leads of 14, 19
		-- and 23. If $5a or $5b is the duration itself, the arming can read it
		-- instead of looking one up, and the whole class table goes away.
		-- Reading the ROM to decide is ambiguous (the byte order admits two
		-- readings, one making +6 look like a class and the other making +7
		-- look like a duration), so correlate the live values against the
		-- lead that is actually measured instead.
		aa = memory.readbyte(0xFF885A),
		ab = memory.readbyte(0xFF885B),
		-- THE STUN TIMER ITSELF ($15c, a WORD).
		--
		-- 0x026100 does subq.w #1, ($15c,A6) once per tick and clears it when it
		-- goes negative, which is the recovery. 0x0260D8 and 0x0260FA subtract a
		-- RANDOM amount from it - indexed by 0x14e8a's output into tables at
		-- 0x283c4 (directions) and 0x28404 (buttons) - whenever $127 or $126
		-- shows new input. That is the lever-mashing escape.
		--
		-- It was never swept because the P2 region is only $00..$FF, and $15c is
		-- past the end. Logging it directly.
		sc = memory.readword(0xFF895C),
		-- $54 AND $26: what decides how the hit ends.
		--
		-- 0x027D46 reads $54 and uses it to index one of three tables
		-- (0x28ca0 / 0x28be0 / 0x28c40, chosen by $1a8 and $a) to fill $26, the
		-- hit-stun timer. 0x024CA4 counts $26 down and, when it reaches zero,
		-- branches on the velocities $50/$52 into 0x027D52, which is the ONLY
		-- place $140 is set to 0x0A - the knockdown.
		--
		-- $54 is copied from the attack's own data at hit time (0x075E20), so it
		-- is known before the recovery type is. Measured over 410 spans it
		-- separates strongly: 4 -> air only, 5 -> knockdown 43/44, 64 -> hit stun
		-- only. Half the spans read 0 because the sample was taken at the start of
		-- the recorded window rather than at the impact freeze, which is what
		-- logging it per tick fixes.
		--
		-- The point of having it: a motion delivered before the recovery type is
		-- known occupies the command block for 14-19 ticks and blocks the real
		-- attempt. Knowing at hit time whether this ends in a knockdown or an air
		-- recovery means not delivering the wrong one at all.
		hs = memory.readbyte(0xFF8854),
		-- $117: what actually decides knockdown-vs-air-recovery.
		--
		-- 0x023A00 handles the airborne hit: it sets $140 = 4, $07 = 0x0C and
		-- $38 = 0xFF, and then
		--     023A4C  cmpi.b #$4, ($54,A6)
		--     023A54  tst.b  ($117,A6)
		--     023A5A  move.b #$5, ($54,A6)     <- 4 becomes 5 when $117 is set
		-- so $54 == 4 and $54 == 5 share a target because one turns into the
		-- other. 5 is the version that ends in a knockdown, which is why the two
		-- separated perfectly in measurement (air 6/6, knockdown 8/8) even though
		-- they run the same code.
		hr = memory.readbyte(0xFF8917),
		-- THE SEQUENCE'S OWN STATE, per tick.
		--
		-- Two probes placed in controller.lua (seq_queued, release) never produced
		-- a single record: mark_write is exported on debugKnockdown's module table
		-- and that name is not bound in controller.lua's scope. Recording from
		-- here instead, where it demonstrably works.
		--
		-- rl = released, cf = current_frame, sl = #sequence. The failing wake-ups
		-- put their last entry out at free-3, so `released` must be getting set
		-- there - this shows on which tick it flips and what the delivery index
		-- was doing at the time.
		-- THE ARM LATCHES THEMSELVES.
		--
		-- Failing wake-ups have every arm condition satisfied and still do not
		-- arm: at free-6 the trace shows $07=02, $21=64, $20=4, ld=1, which is
		-- exactly what the animation branch asks for. The remaining explanation is
		-- that kd_armed is already set from an earlier knockdown and was never
		-- cleared, so record the latches per tick.
		--
		-- ka = kd_armed, kb = kd_armed_by_land, hz2 = hs_armed.
		ka = (kd_armed and 1 or 0) * 100 + (kd_armed_by_land and 1 or 0) * 10
		     + (hs_armed and 1 or 0),
		rl = (function()
			local _o = player_objects and player_objects[2]
			local _q = _o and _o.pending_input_sequence
			if _q == nil then return -1 end
			return (_q.released and 1 or 0) * 100 + (_q.current_frame or 0) * 10
			       + (_q.sequence and #_q.sequence or 0)
		end)(),
		-- $1c, the pointer to the animation cel currently playing (0x027EE8
		-- writes it). With it the whole remaining animation can be walked
		-- offline - 24 bytes per cel, +0 duration, +1 flags - which is the
		-- general form of KD_END_1A7 and would retire the table entirely.
		-- Recorded to check that offline before shipping it.
		ac1c = memory.readword(0xFF881C) * 65536 + memory.readword(0xFF881E),
		-- $174: the wake-up handler writes 5 on the free-1 tick (0x024F12) and
		-- 0x02247E counts it down one per tick. If it reads 4 on the free tick
		-- and 3 on the one after, then ($05 == 0 and $174 >= 4) identifies the
		-- free tick with no Lua state at all, and the lg bookkeeping can go.
		-- Recorded to check that before relying on it.
		w174 = memory.readbyte(0xFF8974),
		-- The block-stun clock and its twin. 0x023960/0x023966 write 14 into
		-- both on a blocked hit; 0x022492 and 0x02249C count them down. Traced
		-- so the exact value at free-1 can be read off instead of assumed.
		w158 = memory.readbyte(0xFF8958),
		-- $121: 0 standing, 1 crouching. 0x02397C picks block animation 0x0C or
		-- 0x0D with it, so if the 24/29/33 split is standing vs crouching this
		-- is what shows it.
		w121 = memory.readbyte(0xFF8921),
		-- $54 is the attack's own data index, fixed at hit time. If the split
		-- is by attack strength instead, it shows here.
		w54b = memory.readbyte(0xFF8854),
		w1ab = memory.readbyte(0xFF89AB),
		hz = memory.readbyte(0xFF8826),
		ac = memory.readbyte(0xFF8859),
		ad = memory.readbyte(0xFF880A),
		-- Hits taken so far in this stun span (1 = single, 2+ = chain).
		hc = hit_count,
		-- The ATTACKER's side, so a hit can be attributed to the move that
		-- caused it. $a is the index into the hit-data table at 0x0764EA
		-- (0x075E1A), $382 is the character's current move, $06 its action
		-- category. P1's object is at 0xFF8400.
		pa = memory.readbyte(0xFF840A),
		-- $382 is the CHARACTER ID, not the current move. charMoves.lua
		-- resolves base+0x382 to the name (0x05 = Morrigan) and 0x024E8A uses
		-- it to index the per-character handler table at $bd47a. The earlier
		-- comment here calling it "the character's current move" was wrong,
		-- which also means every "attacker $382" line in the lead analyses was
		-- really telling us which character was attacking.
		pm = memory.readbyte(0xFF8782),
		-- P2's own character id, so a batch can be split by character.
		p2c = memory.readbyte(0xFF8B82),
		-- THE SPECIAL-MOVE ID. $106, i.e. 0xFF8906 for P2.
		--
		-- charMoves.lua documents it as "PL1 (MO) FF8506" and the tool's
		-- Character Specific mode drives a special by WRITING this byte, so it is
		-- the game's own identifier for which special is out - 0x0A is Bishamon's
		-- command throw, 0x02 Morrigan's Shadow Blade, and so on.
		--
		-- Recorded because the success test was wrong. It asked whether $06 became
		-- 0x0E/0x10/0x12, which a THROW never does: a batch where the 360 came out
		-- 17 times scored 0/18. Reading the move id says both whether a special
		-- came out and WHICH one, so a reversal can be checked against the move
		-- that was actually configured.
		mv = memory.readbyte(0xFF8906),
		-- 着地までの予測ティック数(nil は落下していない)
		ld = ticks_to_landing(),
		p6 = memory.readbyte(0xFF8406),
		-- THE COMMAND RECOGNISER'S OWN STATE, PER TICK.
		--
		-- The special-move work blocks are at $300..$350, eight bytes each -
		-- 0x02DF84 onwards loads them: lea ($330,A6),A4 / ($348,A6) /
		-- ($338,A6) / ($320,A6) / ($318,A6) / ($340,A6) / ($310,A6) /
		-- ($300,A6) / ($308,A6) / ($328,A6) / ($350,A6). ($1f0/$1f8, which
		-- an earlier note pointed at, are the DASH blocks - section 8.6.25.)
		--
		-- $318 is the block that carries the dragon punch here (it is the only
		-- one holding anything through these recoveries). Packed as
		-- dispatch-index, step, timer:
		--     (A4) = 0x318   ($1,A4) = 0x319   ($4,A4) = 0x31C
		--
		-- The per-frame sweep already covers 0xFF8B00-0xFF8B58, but only once
		-- per displayed frame. That was enough to show the blocks are clean
		-- when the motion starts and NOT enough to explain the two air-hit
		-- failures, whose input, delivery offsets and block state are all
		-- identical to the successes. This makes the step the recogniser is
		-- actually on visible at the exact tick each direction lands.
		q = memory.readbyte(0xFF8B18) * 65536
		    + memory.readbyte(0xFF8B19) * 256
		    + memory.readbyte(0xFF8B1C),
	})
end)

-- TICK-EXACT RELEASE. The press edge is placed on ONE specific tick.
--
-- REPLACES the v31 hook on 0x024E84. That fired on a state condition which
-- was byte-identical in all 55 v32 attempts (kd=26, $7=2, $20=0) and still
-- only converted 44%, because it set a flag and let the next 0xFF8B94 write
-- deliver it: measured 0/1/2/3 ticks later (5/15/14/10 of 44). Here the bits
-- go in inside the hook, on the tick the decision is made.
--
-- WHAT THE v32 TICK TRACE SHOWED. Measuring where the button's press edge
-- landed relative to the tick the character leaves Hurt ($05 $02 -> $00):
--
--     edge at free-1 tick : 14 reversal /  0 nothing     <- the window
--     edge at free+2 tick : 10 reversal /  0 nothing     <- see below
--     edge at free-2 tick :  0 reversal / 13 nothing
--     edge at free-3 tick :  0 reversal /  6 nothing
--     edge at free-4 tick :  0 reversal /  1 nothing
--
-- Perfectly separated, and it matches the engine exactly. Command
-- recognition (0x0223EC, section 8.7 of VSAV_ENGINE.md) runs every tick
-- BEFORE the state dispatcher at 0x02244E, but its result lands in $113/$114
-- which are cleared by 0x0223E4/0x0223E8 on the very next tick. So a
-- recognised command survives exactly one tick. Land it on the tick the Hurt
-- handler transitions to free and that same tick starts the move; land it
-- one tick earlier and it is erased before anything can use it.
--
-- (The free+2 group is a different thing: the character is already free and
-- this is just a slightly late special that happens to fall inside the same
-- DISPLAYED frame. It counts as a reversal to the log classifier and looks
-- like one on screen, but it is not the frame-1 case. Aiming at free-1 is
-- what makes it deterministic.)
--
-- IDENTIFYING free-1 PROSPECTIVELY. On the v32 batch the tick before the
-- transition carried this signature in 44 of 44 attempts:
--
--     $05 = 0x02   still Hurt
--     $06 = 0x04   wake-up has reached the actionable sub-state
--     $07 = 0x00
--     $20 = 0      animation counter exhausted
--     $1a7 = 27    knockdown clock
--
-- It is usually exactly one tick long (88 of 103 knockdown transitions), but
-- in 15 it lasted two ticks - and firing on the first of those two puts the
-- edge at free-2, which is 0-for-13. The second tick of such a run is one
-- where the wake-up handler did not advance, and 0x024E78/0x024E82 are the
-- only two gates that can do that:
--
--     024E78: tst.b ($15d,A5)   ; global freeze -> 024E9C rts, nothing runs
--     024E7E: tst.b ($194,A6)   ; per-object    -> 024E9E jmp $3bb68
--     024E84: addq.b #1,($1a7,A6)
--
-- so both are required clear here. Whether that fully accounts for the
-- two-tick runs is the open question this build measures - the tick trace
-- now records both bytes, so the next batch answers it either way.
--
-- Hooked at 0x02211A (move.w ($394,A6),($122,A6)) rather than 0x0221CC:
-- registerexec fires BEFORE the instruction, so bits written here are
-- carried into $122 by that very copy, and $126's press edge is computed
-- from them at 0x0221B4 in the same tick.
-- Set the first time the emulator is caught re-running a tick. 0xFF8081 is
-- incremented once per tick at 0x008E10, so between two consecutive P2 ticks
-- it can only go up by one; anything else means the state was restored and
-- these ticks are being run again (run-ahead). Monotone and set long before
-- any reversal, so latching it is safe.
--
-- It exists so the cleanup below can be immediate when nothing is re-running
-- - which is both what v34 did and what keeps the input history honest - and
-- cautious only when it has to be.
local rewind_seen = false
local last_p2_lg = nil


-- RUN-AHEAD DETECTION.
--
-- FBNeo's setting is not readable from Lua, but the behaviour is: 0xFF8081 is
-- incremented once per tick at 0x008E10, so between two consecutive P2 ticks
-- it can only ever go UP by one. Anything else means the emulator restored an
-- earlier state and is re-running ticks it has already run.
--
--   ra_rewinds     how many times that has happened
--   ra_depth_max   the largest single jump backwards, in ticks. With one
--                  run-ahead frame this is about one frame's worth of ticks.
--   ra_ticks       ticks seen, so the rate can be expressed as a proportion
--
-- Measured on a real session with run-ahead on: 24.4% of tick pairs went
-- backwards, depth 1-2. With it off the count stays at zero.
local ra_rewinds  = 0
local ra_depth_max = 0
local ra_ticks    = 0

memory.registerexec(0x02211A, function()
	if globals == nil or globals.dummy == nil then return end
	if memory.getregister("m68000.a6") ~= 0xFF8800 then return end

	-- ANYTHING ELSE THAT NEEDS THE TICK CLOCK CALLS IN HERE.
	--
	-- registerexec does not stack: a second one on 0x02211A replaces the first,
	-- silently. The air-chain probe learned that the expensive way - it was
	-- registered before this file and never executed once. So a tool that needs
	-- per-tick state adds a call at the top of this hook rather than a hook of
	-- its own, and makes it a global so it costs no upvalue here.
	kd_capture_start_07()

	-- Hit counter, maintained here so it is per TICK and cannot miss a short
	-- freeze the way a once-per-frame check would.
	local _st1now = memory.readbyte(0xFF8805)
	local _st2now = memory.readbyte(0xFF8806)
	if _st1now == 0 then
		hit_count = 0
	elseif _st2now == 0x00 and hit_prev06 ~= 0x00 then
		hit_count = hit_count + 1
	end
	hit_prev06 = (_st1now == 0) and nil or _st2now

	local _lg = memory.readbyte(0xFF8081)

	-- THE THROW ESCAPE ARMS HERE, NOT ON THE FRAME CLOCK (v300).
	--
	-- $21 reads 0x40 for exactly ONE tick. Measured over seven recordings,
	-- every throw escape is identical - 0x00 x19, 0x40 x1, 0xFF x16 - and the
	-- ones that produced nothing differ in no byte at all. What differed was
	-- the sampler: service_held_reversal, where this test used to live, runs
	-- once per DISPLAYED frame, about 1.33 ticks at turbo 3, so it walked past
	-- that single tick roughly a quarter of the time. Four of seven armed,
	-- three never armed and nothing came out.
	--
	-- The condition is unchanged. Only the clock it is read on.
	if _st1now == 0x02
	   and (not hs_throw_armed)
	   and memory.readbyte(0xFF8940) == 0x0E
	   and memory.readbyte(0xFF8821) == 0x40
	   and memory.readbyte(0xFF89A7) == 0
	then
		hs_throw_armed = true
		hs_armed = true
		hs_countdown = 1
		hs_arm_lg = _lg
		debugKnockdownModule.mark_write("hs_armthrow21", 0x40, 1)
	end


	-- Frame trap gap, in ticks. See trap_stun above.
	local _stun = (_st1now == 2)
	if _stun ~= trap_stun then
		if not _stun then
			trap_end_lg = _lg
		elseif trap_end_lg ~= nil then
			local _gap = (_lg - trap_end_lg) % 256
			-- The old rule: anything 20 or over is not a trap, it is the next
			-- exchange. Kept so the list means the same thing as before.
			if _gap < 20 then
				local _t = globals.frames_between_attacks
				table.insert(_t, _gap)
				while #_t > 10 do table.remove(_t, 1) end
			end
		end
		trap_stun = _stun
	end
	local _step = (last_p2_lg ~= nil) and ((_lg - last_p2_lg) % 256) or 1
	if last_p2_lg ~= nil then
		ra_ticks = ra_ticks + 1
		-- ONLY A BACKWARD STEP IS A REWIND.
		--
		-- This used to set rewind_seen for any _step ~= 1, which includes
		-- FORWARD jumps - the hook misses ticks at round transitions, menus and
		-- pauses - so it went true within a few seconds of every session and
		-- stayed true. Measured with run-ahead genuinely off: 73 of 75
		-- recordings reported active = true with ra_rewinds = 0.
		--
		-- That was not only a wrong readout. rewind_seen also gates the release
		-- debounce (_wait = rewind_seen and 8 or 0), which the comment there
		-- says applies "only with run-ahead on" - so every run-ahead-off session
		-- has been paying an 8-frame debounce it did not need.
		if _step > 128 then
			rewind_seen = true
			ra_rewinds = ra_rewinds + 1
			local _depth = 256 - _step
			if _depth > ra_depth_max then ra_depth_max = _depth end
		end
	end
	last_p2_lg = _lg

	-- COUNT EVERY TICK THIS HOOK SEES, RE-EXECUTIONS INCLUDED.
	--
	-- That looks wrong and it is deliberate. With run-ahead the emulator
	-- re-runs about a frame's worth of ticks and discards the first pass
	-- (section 8.6.9), so this tally counts each of those twice and the ratio
	-- reads about 4 where the game advances roughly one tick per displayed
	-- frame. Two separate attempts to "correct" it - deriving the ratio from
	-- 0xFF8081 over the real frame delta (v64), and a high-water mark that
	-- ignores replayed ticks (v67) - both measured WORSE, and v67 measured
	-- much worse:
	--
	--     v66, tally including replays   56 / 56    (throw escape 44/44)
	--     v67, high-water mark          127 / 176   (throw escape  0/12)
	--
	-- The reason is that this number is not really "how fast does the game
	-- tick". It is used only to work out how long an entry takes to be
	-- DELIVERED, and delivery goes through joypad.set, which under run-ahead
	-- is subject to the same re-execution. The inflated figure tracks that;
	-- the true tick rate does not.
	--
	-- With run-ahead off there is nothing to double-count and this reduces to
	-- the true rate on its own, which is the form every good Normal-speed
	-- batch was taken with.
	hs_tick_count = hs_tick_count + 1

	-- THE ARMING COUNTDOWN RUNS ON TICKS, NOT DISPLAYED FRAMES.
	--
	-- Every lead in this file was measured in game ticks. The countdown used
	-- to be decremented from the once-per-displayed-frame callback, which is
	-- the same thing only at Normal speed, where the two run about 1:1
	-- (section 8.6.185). Under turbo one callback covers several ticks, so a
	-- countdown of 30 "frames" is 100+ ticks and the character is actionable
	-- long before it expires - nothing is ever queued.
	--
	-- That is exactly the reported split: knockdown arms off $1a7 with no
	-- countdown at all and kept working, short hit-stun countdowns mostly
	-- still fitted, and the two long ones - air recovery (30) and throw
	-- escape (28) - failed.
	-- THE WAIT IS MEASURED WITH lg, NOT BY DECREMENTING A COUNTER.
	--
	-- This hook fires on the discarded run-ahead pass as well, so a counter
	-- decremented here drains faster than the game actually advances -
	-- measured, 29% of ticks are re-runs, so a wait of 23 elapses in about 16
	-- real ticks. The motion is delivered that much too early and the second
	-- direction ends up held far past the recogniser's step timeout:
	--
	--     throw escape  forward at free-27, down held to free-2   0 / 15
	--     air recovery  forward at free-26..-28                   0 /  9
	--     hit stun      forward at free-11..-17 (short wait)      23 / 25
	--
	-- The hold in the first two is about 25 ticks against a timeout of 14-19,
	-- so they expire every time. Only the variants with a long wait are
	-- affected, which is why hit stun and the $1a7-armed knockdown were fine.
	--
	-- 0xFF8081 rewinds with the game, so elapsed time derived from it is the
	-- same on a re-executed tick as it was the first time - the wait now
	-- measures real game progress no matter how often a tick is replayed.
	--
	-- (This is only the WAIT. The delivery still goes through joypad.set, and
	-- hs_ticks_per_frame still estimates how long that takes - see the note
	-- above, where the inflated figure is the right one for that purpose.)
	if hs_countdown ~= nil and hs_arm_lg ~= nil then
		if ((_lg - hs_arm_lg) % 256) >= hs_countdown then
			-- DO NOT START A MOTION WHILE THE RECOGNISER IS STILL BUSY.
			--
			-- $318 is the work block the dragon punch uses (section 8.6.25
			-- for where these live). Its first byte is the step dispatcher,
			-- and it is non-zero exactly while a motion is part-way through.
			--
			-- Measured on light chains, the block state at the moment the
			-- fresh forward went in separates the outcome completely:
			--
			--     block idle  (0,*,*)      16 reversal /  0 nothing
			--     block busy  (2,4,1..4)    0 reversal /  5 nothing
			--
			-- and the failures show what happens: the forward is swallowed by
			-- the stale block, which then times out, so by the actionable tick
			-- the block reads (0,0,0) - nothing was ever recognised.
			--
			-- This replaces guessing at a spacing constant. HS_STALE_CLEAR
			-- tried to buy the same thing with a fixed 16 ticks and did not
			-- work (26/5 against 25/5 without it) because the time the block
			-- actually needs varies. Reading it is exact.
			--
			-- Bounded, so a block that never clears cannot stall the attempt
			-- forever - past the bound it goes in regardless, which is no
			-- worse than the old behaviour.
			-- IDLE GATE REMOVED (v97).
			--
			-- This waited, up to 20 ticks, for 0xFF8B18 to read 0. $318 is
			-- the DP's work block for MORRIGAN; the special-move blocks are
			-- allocated per character from $300-$350 in move-list order, so
			-- for another character 0xFF8B18 is some other move's block, or
			-- none. Measured across four characters in hit stun:
			--
			--     Morrigan  $318 == 0 on 307 of 464 ticks   29/29
			--     Bishamon             186 of 272           15/17
			--     Demitri               22 of 304            1/19
			--     Lilith                14 of 224            3/14
			--
			-- For Demitri and Lilith it is almost never 0, so the gate spent
			-- its full 20 ticks waiting on every attempt and then delivered
			-- far too late. Bishamon's successful reversals come out with
			-- (dispatch 4, step 8) - a different block entirely.
			--
			-- The gate was added in v84 against the run-ahead delivery
			-- stretch, and it did not measurably help even then. With
			-- run-ahead off it has no job left, and it is built on a
			-- character-specific address, so it goes.
			if false then
				hs_ready_wait = hs_ready_wait + 1
			else
				-- val = the block byte at the moment we gave up waiting,
				-- pc = how many ticks we waited. Non-zero val means we went
				-- ahead into a busy block because the bound ran out, which
				-- the outcome data says is hopeless (0 of 15). Distinguishes
				-- "the gate never fired" from "the gate fired and lost".
				debugKnockdownModule.mark_write("idlegate",
					memory.readbyte(0xFF8B18), hs_ready_wait)
				hs_countdown = nil
				hs_arm_lg = nil
				hs_ready_wait = 0
				hs_ready = true
			end
		end
	end

	-- CHARACTER SPECIFIC, ON THE EXACT TICK (v160).
	--
	-- The poke used to happen in guardCancelCheck, once per DISPLAYED FRAME.
	-- That is about 1.6 ticks during a recovery, so where it landed relative to
	-- the free tick was not controllable - the same problem the input path had
	-- before v131, and the reason this mode's timing was poor.
	--
	-- The free-1 signature is exact and covers every recovery variant, so the
	-- frame side now only requests and this places it. No sequence is involved,
	-- which is why the test is here rather than in the block below.
	--
	-- Consume BEFORE poke: a wake-up poke sets pending_wakeup_flag_zero
	-- to 2 on reversal-1. The next tick is reversal (count 1, no write).
	-- The tick after that is reversal+1 (count 0, zero +0x134 / +0x11E / +0x143).
	if pending_wakeup_flag_zero ~= nil then
		pending_wakeup_flag_zero = pending_wakeup_flag_zero - 1
		if pending_wakeup_flag_zero <= 0 then
			zero_wakeup_invuln_flags()
			pending_wakeup_flag_zero = nil
			debugKnockdownModule.mark_write("csp_wu_flags", 1,
				memory.readbyte(0xFF8947))
		end
	end
	if csp_pending and run_one_frame_special_ref ~= nil then
		local _cs05 = memory.readbyte(0xFF8805)
		local _csig = (_cs05 == 0x02
		               and memory.readbyte(0xFF8806) == 0x04
		               and memory.readbyte(0xFF8807) == 0x00)
		-- A character with no free-1 signature opens its input window on the
		-- free tick itself, so that is where its poke belongs - the same one
		-- tick later the input path already gives them (section 4.7).
		local _csnosig = (KD_NO_SIG[memory.readbyte(0xFF8B82)] and _cs05 == 0x00
		                  and memory.readbyte(0xFF8940) == 0x0A)
		if _csig or _csnosig then
			csp_pending = false
			run_one_frame_special_ref()
			debugKnockdownModule.mark_write("csp_poke",
				_csig and 1 or 2, memory.readbyte(0xFF8940))
		end
	end

	-- Resolve an abandoned motion: one tick of its final DIRECTION, no button.
	-- See hs_request_flush(). Done here rather than from the frame callback
	-- because a write made there can be overwritten by input stage 2 before
	-- 0x02211A consumes it; written from in front of that instruction it is
	-- carried by the very copy this hook precedes.
	--
	-- Cleared before the write so a rewind that replays this tick simply does
	-- it again from the flag the frame side re-sets - and doing it twice is
	-- harmless anyway, the block is already at step 0 the second time.
	-- THE DEFERRED PRESS, ONE TICK AFTER THE SIGNATURE.
	--
	-- Placed here, ahead of every early return below, because by the free tick
	-- the pending sequence may already have been dropped - service_held_reversal
	-- lets it go once the character is out of stun with the knockdown clock at
	-- zero, and that runs on the frame boundary, not on the tick. The bits were
	-- captured at defer time so nothing here depends on the sequence surviving.
	if fast_press_lg ~= nil then
		-- A BUTTONLESS PRESS IS HELD FOR TWO TICKS (v158).
		--
		-- A button only has to exist for the tick its press edge is taken on;
		-- the second tap of a dash does not. Reported from play and consistent
		-- with everything else here: one tick of the direction is not enough
		-- for the game to take it as the second tap, two is.
		--
		-- Only when the entry carries no button, so nothing that presses one is
		-- affected - a special or a normal still goes in for exactly one tick,
		-- which is what stops a chain-cancellable normal being swung twice.
		local _dlg = (memory.readbyte(0xFF8081) - fast_press_lg) % 256

		-- THE MOTION'S LAST ENTRY, WHILE THE BUTTON IS STILL WAITING (v173).
		--
		-- Only when a delay actually split the two (moff < off). The entry is
		-- buttonless here by construction, so it gets the same two tick hold a
		-- buttonless press gets - that is what makes the second tap of a dash
		-- register. After it, the lever either stays down (a command normal
		-- like forward+HP) or is released (a dash tap, or a special the
		-- recogniser has already matched and will hold for 14-19 ticks).
		-- A PREFIX ALONE IS REASON ENOUGH TO HOLD THE TICKS (v176).
		--
		-- Gating this on moff < off would skip the drain whenever the delay is
		-- zero, because then the button rides with the last entry and the two
		-- offsets are equal - which is exactly the default setting.
		if (#fast_press_q > 0 or fast_press_moff < fast_press_off)
		   and _dlg < fast_press_off then
			if _dlg < fast_press_moff then
				-- Still walking the prefix the frame path did not deliver.
				-- Everything past it is the neutral in front of the last
				-- entry, which is what gives that entry its press edge.
				local _pe = fast_press_q[_dlg + 1]
				if _pe ~= nil then
					local _pl, _pb = entry_to_bits(_pe)
					assert_input_bits(_pl, _pb)
					debugKnockdownModule.mark_write("prefix_now",
						_pl * 256 + _pb, _dlg)
				else
					assert_input_bits(0, 0)
				end
			elseif _dlg <= fast_press_moff + 1 then
				assert_input_bits(fast_press_mlev, 0)
				debugKnockdownModule.mark_write("motion_now",
					fast_press_mlev * 256, _dlg)
			elseif fast_press_rev ~= nil then
				-- Past the dash's own two ticks: reverse and stay there. This
				-- is the cancel, and holding it is what makes the game's one
				-- frame recognition window unmissable.
				assert_input_bits(fast_press_rev, 0)
				debugKnockdownModule.mark_write("cancel_now",
					fast_press_rev * 256, _dlg)
			elseif fast_press_hold then
				assert_input_bits(fast_press_mlev, 0)
			else
				assert_input_bits(0, 0)
			end
			-- RETURNING HERE SKIPS THE BLK BOOKKEEPING AT THE END OF THIS HOOK.
			--
			-- The old code returned from this region too, but only for a tick
			-- or two; a delay of 14 holds it for fourteen. If the dummy starts
			-- blocking inside that window, BLK.prev158 and BLK.episode are not
			-- updated on those ticks, so the $158 zero edge can be missed or
			-- seen one tick late. Both failure modes are bounded - a stale
			-- episode flag suppresses an arm rather than inventing one - and it
			-- takes a blockstring landing inside a delayed wake-up reversal to
			-- reach at all. Untested; if delayed reversals and block reversals
			-- interfere, this is the first place to look.
			return
		end

		local _phold = (fast_press_btn == 0) and 1 or 0
		if _dlg >= fast_press_off and _dlg <= fast_press_off + _phold
		   and (_dlg > fast_press_off or memory.readbyte(0xFF8805) == 0x00) then
			-- RE-AIM THE DEFERRED PRESS AT THE FACING IT LANDS UNDER (2026-09-20).
			--
			-- The bits were captured raw at defer time, one to three ticks
			-- before free. A knockdown whose dummy is lying facing away ends
			-- with the wake-up turn: $b flips exactly on the free tick and the
			-- swap at 0x022194 then reads the captured bits as the opposite
			-- direction. Measured shape of every failure (kd_c05_s12..s16,
			-- kd_c0A_s19..s37): tap one went in as corrected forward, the
			-- press landed as corrected back, the two taps of ONE dash
			-- disagreed, no dash came out, and the counter attack's own button
			-- came out alone as a plain normal (0x0A at free+2..+3) or as
			-- nothing at all. Swapping the two facing-relative bits when the
			-- reference has moved restores the corrected direction the press
			-- was asked for, tick by tick - a turn between the press's own two
			-- ticks is handled the same way.
			--
			-- facing_for_input() is stable within a tick for this purpose:
			-- nothing recomputes $b between the inject at 0x02211A and the
			-- correction at 0x022134 (see the dash_facing diagnostic), so the
			-- value read here is what the swap will use this tick.
			local _pl = fast_press_lev
			if fast_press_fref ~= nil
			   and facing_for_input() ~= fast_press_fref then
				_pl = swap_facing_bits(_pl)
			end
			assert_input_bits(_pl, fast_press_btn)
			debugKnockdownModule.mark_write("press_now",
				_pl * 256 + fast_press_btn, _dlg)
			if _dlg < fast_press_off + _phold then
				-- More ticks of this press to come; keep the state.
				return
			end
			-- THE MOTION IS SPENT. DROP IT (v144).
			--
			-- v142 stopped process_pending_input_sequence from delivering it
			-- instead, which killed the second press but left the sequence
			-- pending forever: measured on the v143 batch, 43 of 114 lived past
			-- 40 ticks. A pending sequence makes queue_input_sequence refuse the
			-- NEXT one, so the following guard action could not be queued at
			-- all - which is what "the guard reversal still needs work" is.
			--
			-- Dropping it here does both jobs: nothing is left to deliver, so
			-- there is no second press, and the slot is free for the next
			-- recovery.
			local _dd = player_objects and player_objects[2]
			if _dd ~= nil then _dd.pending_input_sequence = nil end
			fast_press_lg = nil
			fast_press_q = {}
			kd_set_motion_done(true)
			return
		elseif _dlg > fast_press_off + _phold + 1 then
			-- The free tick never arrived where it was expected. Let it go
			-- rather than pressing at some unrelated moment later.
			fast_press_lg = nil
			fast_press_q = {}
		end
	end

	if #hs_flush_q > 0 then
		local _e = table.remove(hs_flush_q, 1)
		local _lev, _btn = entry_to_bits(_e.entry)
		if _e.last and _btn == 0 then
			_btn = button_mask(GA.button())
		end
		assert_input_bits(_lev, _btn)
		debugKnockdownModule.mark_write("hs_flush", _lev, _btn)
		return
	end

	-- A DASH'S TWO TAPS HAVE TO BE ADJACENT (v156).
	--
	-- The trace says both taps do go in - hook_seq reads 102 the whole time, so
	-- entry 1 was delivered once at queue time and the clamp then held the
	-- empty entry 2 - but they land seven or eight ticks apart: the first when
	-- the sequence is queued, the second on the free tick. That is a walk
	-- backwards, not a dash.
	--
	-- Everything else in a motion can be spread out because the recogniser
	-- holds a step for 14 to 19 ticks, but a dash is two presses of the SAME
	-- direction and the game reads it as a double tap, which is a much shorter
	-- window. So for a buttonless motion the first tap is placed here instead,
	-- two ticks before the press: the block schedule puts free about eleven
	-- ticks after the arm (section 5.5.2), so arm + 9 is free - 2. v155 already
	-- puts neutral on free-1 and the press on free+0, which completes
	-- tap, release, tap on three consecutive ticks.
	--
	-- SCOPED BY MOTION NAME, NOT BY THE LAST ENTRY'S BUTTON (v206).
	--
	-- This used to test `_lastbtn == 0`, meaning to exclude specials. It
	-- excluded the dashes as well the moment a button was configured:
	-- make_input_sequence puts the button INTO the last entry, so a back dash
	-- with LK ends on {back, LK} and the whole neutral/tap scheduling below was
	-- skipped. The dummy holds back to guard, so without it the first tap of a
	-- BACK dash is no press edge at all and no dash comes out - reported as
	-- "back dash does not come out either" while forward dash was fine, which
	-- is exactly the asymmetry a held back explains.
	--
	-- Same mistake as v180's dash_pre, in the other place that made it.
	do
		local _d0 = player_objects and player_objects[2]
		local _s0 = _d0 and _d0.pending_input_sequence
		if _s0 ~= nil and _s0.blk_hold and _s0.sequence ~= nil
		   and BLK.lg ~= nil and #_s0.sequence >= 2 and is_plain_dash() then
			-- INPUT-BASED NEUTRAL INJECTION. Spend the post-arm neutral ticks
			-- here, one per tick, before the dash schedule runs - the held
			-- guard direction would otherwise eat the first tap's edge.
			if BLK.neutral and BLK.neutral > 0 then
				assert_input_bits(0, 0)
				BLK.neutral = BLK.neutral - 1
				debugKnockdownModule.mark_write("blk_neutral", BLK.neutral, memory.readbyte(0xFF8081))
				return
			end
			local _lastlev = entry_to_bits(_s0.sequence[#_s0.sequence])
			-- NEUTRAL, TAP, NEUTRAL, TAP - FOUR TICKS (v157).
			--
			-- v156 placed the first tap and left what came before it alone. That
			-- is only half of it: if the direction is already held when the
			-- first tap is due, the tap is not a press edge either and the game
			-- sees one long hold. The dummy holds back to guard, so on a back
			-- dash that is the normal case.
			--
			-- Measured on the v156 batch, and it is unambiguous: every span that
			-- got both taps produced $06 = 0x14, a dash - 22 of 22 - and every
			-- failure is a span where the first tap is missing.
			--
			--     -2:back +0:back  -> $06 = 0x14   x14
			--     -3:back +0:back  -> $06 = 0x14   x8
			--     -1:back only     -> $06 = 0x00   x7
			--
			-- So the release in front of the first tap is added, giving the four
			-- ticks the user described: neutral, back, neutral, back.
			local _dstep = (memory.readbyte(0xFF8081) - BLK.lg) % 256
			local _dlead = blk_lead_ticks()
			-- TICKS LEFT, READ LIVE, NOT COUNTED FROM THE ARM.
			--
			-- _dstep plus a latched lead is two estimates stacked: the arm is
			-- placed by a hook that only sees about six ticks in ten, so it
			-- lands anywhere in a four-tick band, and the lead it latches
			-- inherits that. The guard script has the answer on every tick -
			-- length minus the cursor - so read it here and place the taps
			-- against free directly. nil on the hit-stun path, which has no
			-- script; that path keeps _dstep.
			local _grem = nil
			do
				-- THE SAME CLOCK THE ARM USES.
				--
				-- v290 switched the ARM to $26 once a push block is granted,
				-- but left this on the guard script - and the script is
				-- abandoned at that point, so $164 stops and length - $164
				-- freezes at some large number. It then never reaches the
				-- release window (4..7) or the tap window (2..3), and the back
				-- dash simply never comes out after a push block. The forward
				-- dash survived because it holds rather than tapping.
				if memory.readbyte(0xFF8807) == 0x06 then
					_grem = memory.readbyte(0xFF8826)
				else
					local _gl = BLK.script_len(memory.readbyte(0xFF8859))
					if _gl ~= nil then _grem = _gl - memory.readword(0xFF8964) end
				end
			end
			-- A FORWARD DASH DOES NOT AIM. IT JUST HOLDS (v226).
			--
			-- BLK_LEAD assumes ten or eleven ticks from the block arm to free,
			-- and aims the tap at lead-5. Against Demitri's demon the arm lands
			-- ONE tick before the signature - measured, 7 of 7 - so _dstep never
			-- gets near the target and the tap never fires. 2 of 20 came out,
			-- worse than leaving it to the frame path.
			--
			-- The arm can be anywhere from free-2 to free-11 and nothing tells
			-- us which, so a forward dash stops aiming: the direction goes down
			-- at the arm and stays down until the signature puts the neutral on
			-- free-1. Whenever free arrives, the shape in front of it is right.
			-- Forward is not the guard direction, so holding it costs the block
			-- nothing the release did not already cost.
			--
			-- Back still aims, because for back the RELEASE has to come first
			-- and that does need a position. It is measured working there.
			-- INJECT AND FALL THROUGH. DO NOT RETURN (v227).
			--
			-- v226 returned here on every tick from the arm, and the free-1
			-- SIGNATURE is handled further down this same hook. With the arm at
			-- free-2 the signature tick lands inside that window, so it never
			-- ran: no neutral on free-1, no deferred press, no second tap, no
			-- button. Nothing came out at all, including the ordinary blocks
			-- that used to work. Hit-stun was untouched because it does not
			-- come through here.
			--
			-- The hold does not need the early exit. Whatever runs after this
			-- writes last and wins, which on the signature tick is exactly what
			-- should happen.
			if not needs_release() and _dstep <= 20 then
				local _l1, _b1 = entry_to_bits(_s0.sequence[1])
				assert_input_bits(_l1, _b1)
				debugKnockdownModule.mark_write("dash_hold",
					_l1 * 256 + _b1, _dstep)
			end

			-- WHERE THE TAP GOES, AND WHY THE NUMBER MOVED (v236).
			--
			-- v235 made _dlead truthful and that alone broke the placement.
			-- The old lead was a constant 10/11/11 while the real distance was
			-- 8/9/9, and BACK_TAP_BIAS had been tuned on top of that error, so
			-- "_dlead - 2 - BIAS" happened to land the tap at free-3. Feed it
			-- an honest lead and the same expression lands at free-5. Measured
			-- over every recording in reversal_logs_archive, tap1 sat at free-0
			-- to free-4 while it was working; v235 put every one of them at
			-- free-5 or free-6, which is the accuracy the user lost.
			--
			-- So say the distance out loud instead of deriving it. BIAS is now
			-- what it always meant: how many ticks before free the first tap
			-- goes. The window still spans BACK_TAP_HOLD_TICKS, and the
			-- release still sits in the BACK_TAP_NEUTRAL_TICKS in front of it.
			local _tapstep = _dlead - 2 - BACK_TAP_BIAS
			if needs_release() and _grem ~= nil then
				if _grem >= BACK_TAP_BIAS + 1
				   and _grem <= BACK_TAP_BIAS + BACK_TAP_NEUTRAL_TICKS then
					assert_input_bits(0, 0)
					debugKnockdownModule.mark_write("dash_rel1",
						memory.readbyte(0xFF8859) * 256 + _dlead, _grem)
					return
				end
			elseif needs_release()
			   and _dstep >= _tapstep - BACK_TAP_NEUTRAL_TICKS
			   and _dstep <= _tapstep - 1 then
				assert_input_bits(0, 0)
				debugKnockdownModule.mark_write("dash_rel1",
					memory.readbyte(0xFF8859) * 256 + _dlead, _dstep)
				return
			end
			local _in_tap
			if _grem ~= nil then
				_in_tap = _grem <= BACK_TAP_BIAS
				          and _grem >= BACK_TAP_BIAS - BACK_TAP_HOLD_TICKS + 1
			else
				_in_tap = _dstep >= _tapstep
				          and _dstep <= _tapstep + BACK_TAP_HOLD_TICKS - 1
			end
			if _in_tap then
				local _l1, _b1 = entry_to_bits(_s0.sequence[1])
				assert_input_bits(_l1, _b1)
				-- val = $59<<8 | lead, pc = _dstep. Without the strength the
				-- next batch cannot be split the way the report was.
				debugKnockdownModule.mark_write("dash_tap1",
					memory.readbyte(0xFF8859) * 256 + _dlead, _grem or _dstep)
				return
			end
		end
	end

	-- (v178's dash_pre went here and is gone again in v181. Once the delay
	-- stopped being counted twice, the first tap was never missing: measured
	-- over both batches, counting only spans where the dummy actually became
	-- free and stayed free, v179 without it is 109 of 109 and v180 with it is
	-- 35 of 35. It caught nothing and put an extra forward into hit stun on
	-- every armed dash, which is the shape of bug this file has been bitten by
	-- before. See VSAV_REFERENCE.md 8.21.)

	-- THE PUSH BLOCK TAPS, ONE PER TICK (v184).
	--
	-- $1ab is the window: 14 at the block (0x023966, beside $158), one off per
	-- tick (0x02249C), and 0x0275D8 refuses the push block once it is zero -
	-- about twelve usable ticks. $170 counts a press on any tick where
	-- $126 & $77 is non-zero (0x027606, via the test at 0x0274BA), eight is a
	-- guaranteed push block (0x02760E) and fewer is a chance per count.
	--
	-- So the eleven entries of {LP},{},{LP},... are eleven TICKS here, which
	-- puts all six presses inside the window. The frame path took about
	-- eighteen for the same entries and left the last two or three outside it.
	--
	-- One tick per press is enough: a button only has to exist on the tick its
	-- edge is taken. The two tick hold the dash taps need is for BUTTONLESS
	-- entries, which these are not.
	do
		local _d0 = player_objects and player_objects[2]
		local _s0 = _d0 and _d0.pending_input_sequence
		if _s0 ~= nil and _s0.pb_tick and _s0.sequence ~= nil then
			local _i = _s0.current_frame or 1
			-- ONCE IT IS GRANTED, STOP.
			--
			-- $184 is the game's own success flag and 0x0275E0 refuses every
			-- press after it, so the rest of the taps do nothing. They do cost
			-- something here though: they hold the delivery slot, and the
			-- counter that is meant to follow cannot be queued until it is
			-- free. Dropping the remainder is what lets "push block, then act"
			-- happen at all.
			if memory.readbyte(0xFF8984) ~= 0 then
				_d0.pending_input_sequence = nil
				_i = #_s0.sequence + 1
			end
			if _i <= #_s0.sequence then
				local _pl, _pb = entry_to_bits(_s0.sequence[_i])
				assert_input_bits(_pl, _pb)
				_s0.current_frame = _i + 1
				debugKnockdownModule.mark_write("pb_tick", _pl * 256 + _pb, _i)
				return
			end
			-- Spent. Free the slot so the next guard action can be queued.
			_d0.pending_input_sequence = nil
		end
	end

	-- AN ACTION SEQUENCE'S LATER SEGMENTS, ON THE TICK CLOCK (v300).
	--
	-- The first segment is placed by the arm and lands on free+0 because the
	-- free-1 signature below sees the actionable tick coming. A later segment
	-- cannot use that signature: it does not follow stun, it follows the dummy
	-- finishing its own move, and $05/$06 both reaching zero IS that moment
	-- rather than the tick before it. Read here, on the tick, and injected
	-- from in front of 0x02211A, "both zero" and free+0 are the same tick.
	--
	-- Deciding this once per DISPLAYED frame instead would be up to two ticks
	-- late, and delivering it there costs about 1.6 ticks per entry on top.
	do
		local _d0 = player_objects and player_objects[2]
		-- TWO PASSES, SO ONE TICK CAN END A SEGMENT AND START THE NEXT.
		--
		-- The delivery slot is only freed once the walk below runs off the end
		-- of a segment, and the queue refuses while it is occupied. Doing those
		-- on separate ticks spends a tick doing nothing - and a tick is the
		-- whole unit this path exists to get right.
		for _pass = 1, 2 do
			if _d0 == nil or globals.dummy.guard_action ~= 'sequence' then break end
			actionSequenceRunnerModule.service(_d0)
			local _s0 = _d0.pending_input_sequence
			if _s0 == nil or not _s0.seq_tick or _s0.sequence == nil then break end
			-- A new segment is being delivered, so whatever the last one was
			-- holding is over. Cleared before the entry goes in, not after, or
			-- the two would fight over the same tick.
			--
			-- The button hold goes with it. Left standing it outlived its own
			-- step: the next chain step's press went in while the previous
			-- button was still being asserted, so the second and third links
			-- were not electric, and on the free ticks between steps the stale
			-- hold returned early and starved everything below - which is what
			-- stopped a Late Cancel step from coming out at all (user,
			-- 2026-09-05).
			seq_held_lever = nil
			seq_held_btn = nil
			seq_held_btn_until = nil
			local _i = _s0.current_frame or 1
			-- THE LAST PRESS WAITS FOR THE REAL TOUCHDOWN - BUT NOT FOREVER.
			--
			-- A landing step is committed lead ticks early so its final entry
			-- falls on the tick the dummy can first act. That is a PREDICTION,
			-- and a hit stop starting after the commit stops the physics while
			-- this walk keeps counting ticks: the touchdown moves back, the
			-- last press goes out in the air, and a press that misses free+0
			-- does not come out late - it does not come out at all.
			--
			-- Measured 2026-09-19, ten runs each. Dash LP: FD:0, works. Dash
			-- HP: FD:48, and every single landing press (AF 24 of 24) went out
			-- roughly two ticks above the floor. The slow move connects late in
			-- the descent, so its freeze lands inside this delivery.
			--
			-- ONLY A DELIVERY THAT WAS FROZEN IS TOUCHED. An earlier attempt
			-- waited whenever the dummy was airborne at the last entry, which
			-- fires constantly - half of the working LP presses are airborne
			-- too, one tick out and perfectly fine - and measured LW:240 over
			-- 24 laps. It pushed the dash cancel out of its window and had to
			-- be reverted. saw_freeze is what keeps the working case untouched.
			--
			-- WAITING COSTS NO EDGE, BUT IT DOES COST THE WINDOW. The entry
			-- before the last is neutral, so holding asserts nothing and the
			-- forward is pressed fresh on the real touchdown. But the game's
			-- command clock does not stop for hit stop, and the dash allows
			-- only DASH_GRACE_TICKS on that neutral. Past it the motion is
			-- dead, so the whole thing is entered again from the top rather
			-- than pressed into a window that has already closed.
			-- ONLY AS THE LAST ENTRY IS ABOUT TO START.
			--
			-- The last forward is asserted for TWO ticks (a buttonless entry
			-- needs the v158 hold). On the first of them the dash is granted -
			-- and Sasquatch's dash lifts his feet, so $38 goes 0 -> 1 on that
			-- very tick (VSAV_MEMORY_NOTES.md). On the second tick this branch
			-- then saw "airborne and on the way down" and re-entered the motion,
			-- which granted another dash, which lifted him again: dash, land,
			-- dash, land, for as long as the list was running (reported
			-- 2026-09-19). The guard was reacting to the dash it had just
			-- produced.
			--
			-- tick_held is zero only before the entry has been asserted at all,
			-- so this now asks the question once, at the moment it is still a
			-- question. A hold keeps it zero - that path returns before writing
			-- - so waiting and re-entering both still work.
			-- ticks_to_landing() > 0 WAS TRIED HERE AND BROKE SASQUATCH.
			--
			-- The reasoning was that saw_freeze is only a proxy for "would this
			-- press land before the touchdown", which is true - but the direct
			-- form waits on EVERY descending delivery, and a press that is
			-- already aimed at the touchdown is still descending when it goes
			-- out. Sasquatch's second dash went late again, the same LW:240 as
			-- 2026-09-19. Reverted the same day it was tried (user, 2026-09-20).
			--
			-- The Morrigan case it was meant to fix is real and still open: the
			-- freeze that shifts the schedule belongs to the PREVIOUS step's
			-- contact and is over before this segment starts being delivered,
			-- so saw_freeze - which only watches the delivery - never sees it.
			-- Whatever replaces this has to ask about the freeze since the
			-- ANCHOR, not the freeze during the delivery.
			if _s0.seq_land and _s0.saw_freeze and _i == #_s0.sequence
			   and (_s0.tick_held or 0) == 0
			   -- The touchdown, not "able to act".
			   --
			   -- 2026-09-19: releasing on $05/$06 both zero instead was tried,
			   -- because Jedah's landing press is on the floor every time
			   -- (AF:0) and cannot act every time (NF 2 of 2) and still
			   -- produces nothing. It made Sasquatch's second dash LATE - the
			   -- case that was working - so it was taken straight back out.
			   --
			   -- The two are not the same question, and the evidence says so:
			   -- Sasquatch's landing presses were AIRBORNE (AF 46 of 46) and
			   -- his dash came out anyway. Whatever decides this is not simply
			   -- "the press must land on free+0", and guessing again is how the
			   -- working case keeps getting broken. Jedah is left unsolved and
			   -- written up in design_landing_prediction.md.
			   and memory.readbyte(0xFF8838) ~= 0
			   and ticks_to_landing() ~= nil then
				local _R = actionSequenceRunnerModule
				_s0.land_hold = (_s0.land_hold or 0) + 1
				-- One tick of the grace is already spent by the neutral entry
				-- itself, so the hold may use the rest and no more.
				if _s0.land_hold < (_R.DASH_GRACE_TICKS or 10) - 1 then
					return
				end
				-- Spent. Start the motion over so the window is fresh.
				--
				-- saw_freeze STAYS SET. Clearing it made the second attempt
				-- blind: it would walk straight to its own last entry and press
				-- in the air again, which is the thing being fixed. Keeping it
				-- means the list cycles - run up, hold out the grace, enter it
				-- again - until the floor is really there. Every cycle hands the
				-- final press a window that is still open.
				--
				-- This cannot spin forever: the whole branch is under
				-- ticks_to_landing() ~= nil, so the moment the dummy is not on
				-- its way down the press goes out instead.
				_s0.current_frame = 1
				_s0.tick_held = 0
				_s0.land_hold = 0
				_i = 1
			end
			-- THE WINDOW RAN OUT WHILE WAITING. START OVER INSTEAD.
			--
			-- Not counting frozen ticks keeps a press alive through a SHORT
			-- freeze, which is what Jedah needed: three frozen ticks, the
			-- forward held five, the dash came out. It cannot save a long
			-- one. Sasquatch's HP freezes for eleven, the forward ends up
			-- held thirteen ticks, and the game only lets the first
			-- direction of a dash continue for ten (VSAV_MEMORY_NOTES.md).
			-- Past that the motion is dead and every further tick feeds
			-- something that cannot come out.
			--
			-- So stop asserting, let the freeze finish, and enter the whole
			-- motion again on a window that is open. Traced 2026-09-19: the
			-- runs that did re-enter (e3, then e1 again) produced a dash
			-- every time, and the ones that kept feeding never did.
			if _s0.restart_pending then
				if memory.readbyte(0xFF885C) ~= 0 then return end
				_s0.restart_pending = nil
				_s0.current_frame = 1
				_s0.tick_held = 0
				_s0.entry_ticks = 0
				_i = 1
			end
			-- A DASH CANNOT BE AIMED WHILE THE CHARACTER IS STILL TURNING.
			--
			-- Held, not corrected: the direction a dash travels is decided when
			-- the game grants it, so one entered facing the old way runs away
			-- from the opponent for its whole length. Waiting for the turn is
			-- the only thing that puts it the right way round, because a back
			-- dash cannot be used instead - $b flips inside the command window
			-- and half a back dash plus half a forward dash is neither.
			--
			-- ONLY RAW DIRECTIONS, AND ONLY WHILE THE TWO DISAGREE. Outside a
			-- crossover they never disagree, so nothing else waits a tick.
			--
			-- CAPPED BY THE COMMAND'S OWN WINDOW. If the turn has not happened
			-- within the grace the dash has anyway (10 ticks Normal, 8 Turbo -
			-- VSAV_MEMORY_NOTES.md), waiting longer buys nothing: the motion
			-- would be dead by then. Past the cap it goes out as it did before,
			-- which is no worse than not waiting at all.
			if _s0.raw_dir == true and facing_unsettled() then
				_s0.face_hold = (_s0.face_hold or 0) + 1
				if _s0.face_hold
				   <= (actionSequenceRunnerModule.DASH_GRACE_TICKS or 10) then
					return
				end
			else
				_s0.face_hold = 0
			end
			if _i <= #_s0.sequence then
				local _pl, _pb = entry_to_bits(_s0.sequence[_i])
				-- Every tick this entry has been asserted, frozen ones too -
				-- the game's command clock does not stop for hit stop.
				_s0.entry_ticks = (_s0.entry_ticks or 0) + 1
				-- THE FREEZE DOES NOT HAVE TO STILL BE RUNNING.
				--
				-- This used to require $5C at the very tick the count crossed,
				-- and that is not when the damage shows. A freeze that ends at
				-- tick 8 leaves the entry asserted for another few ticks while
				-- tick_held catches up, so the count crosses on a tick that is
				-- no longer frozen, the guard misses it, and the entry goes out
				-- having been held THIRTEEN ticks - past the ten the game gives
				-- a dash's first direction, and with no press edge left at the
				-- end because it never let go.
				--
				-- MEASURED 2026-09-20 (Morrigan, dash then Forward+MK, looped).
				-- Every lap that dashed had entry one asserted 2 ticks; every
				-- lap that did not had it asserted 12 or 13 and walked instead:
				--
				--     lg 144..156  e1 L2   (13 ticks)  -> no dash, $06 = 04
				--     lg 185..186  e1 L2   ( 2 ticks)  -> dash,    $06 = 14
				--
				-- Which is why a whiff works and a hit does not: without the
				-- hit there is no freeze to stretch the entry (user, 2026-09-20).
				--
				-- saw_freeze, so a delivery that never met a freeze still comes
				-- out exactly as it did before - the same rule the re-timing
				-- below already follows.
				-- 2026-09-20: two guards were added here and then removed.
				-- An early one that fired on the first frozen tick took landing
				-- segments away from the landing measures above, and widening
				-- this one with saw_freeze did not fix what it was aimed at
				-- (Morrigan's looped dash MK). Both are recorded in
				-- handoff_v11.5_action_steps.md; neither belongs here.
				if (_pl ~= 0 or _pb ~= 0)
				   and memory.readbyte(0xFF885C) ~= 0
				   and _s0.entry_ticks
				       > (actionSequenceRunnerModule.DASH_GRACE_TICKS or 10) then
					_s0.restart_pending = true
					return
				end
				-- THE PARKED REVERSE RIDES THE FIRST ENTRY THAT HAS ROOM.
				--
				-- An entry with no lever of its own - an Attack step pressing a
				-- bare button - takes the reverse direction under it, which is
				-- the dash cancel attack: the button presses WITH the back. An
				-- entry that carries its own direction takes the lever instead,
				-- the same rule the arm's lever row uses (an explicit choice
				-- replaces the reverse), and the holding ends there either way.
				local _rvn = actionSequenceRunnerModule.rev_lever_now(
					memory.readbyte(0xFF8081))
				if _rvn ~= nil then
					if _pl == 0 then
						_pl = entry_to_bits({ _rvn })
						if _pb ~= 0 then actionSequenceRunnerModule.rev_clear() end
					else
						actionSequenceRunnerModule.rev_clear()
					end
				end
				assert_input_bits(_pl, _pb)
				-- THE v158 HOLD, APPLIED HERE TOO.
				--
				-- A buttonless press has to exist for two ticks or the game
				-- does not take it - the second tap of a dash is exactly that
				-- case, and a sequence step is far more likely to be a bare
				-- direction than a guard action ever was. An entry that
				-- presses a button still goes in for exactly one tick, which
				-- is what stops a chain-cancellable normal being swung twice.
				local _hold = (_pb == 0 and _pl ~= 0) and 2 or 1
				-- A TICK THE GAME DID NOT PROCESS IS NOT A TICK DELIVERED.
				--
				-- $126 is one tick's press edge, so a press made during hit
				-- stop is thrown away (measured on Zabel's crouching LP, see
				-- rapid_fire_open). Counting those ticks anyway retired an
				-- entry the game never saw.
				--
				-- It bit the two tick entries. A buttonless direction has to
				-- exist for two ticks or the game does not take it (v158), and
				-- a dash is N forward N forward - all directions. Traced on
				-- 2026-09-19 over ten Jedah runs: the five that worked had no
				-- frozen press ticks at all, and the five that failed each had
				-- EXACTLY ONE, always the second tick of the first forward.
				-- So that tap was delivered for one effective tick, never
				-- registered, and the second forward arrived alone - which is
				-- not a dash. $06 never reached 0x14 in any of the five.
				--
				-- Nothing changes where nothing freezes: all five working runs
				-- had $5C at zero on every press tick.
				-- ONLY FOR AN ENTRY THAT ASSERTS SOMETHING.
				--
				-- A neutral entry hands the game nothing to take, so there is
				-- no press for the freeze to discard and nothing is gained by
				-- sitting on it. Waiting there only burns the dash's neutral
				-- grace, which is ten frames and not renewable.
				--
				-- Traced 2026-09-19: an eleven tick freeze landed on the
				-- neutral of Sasquatch's second dash, this held it for twelve
				-- ticks, and the motion expired - breaking a case that had
				-- been working. The same freeze on a DIRECTION is the case
				-- this whole guard exists for, so the two are split here.
				if (_pl ~= 0 or _pb ~= 0)
				   and memory.readbyte(0xFF885C) ~= 0 then
					-- asserted, but the game is not looking: not delivered
				else
					_s0.tick_held = (_s0.tick_held or 0) + 1
				end
				if _s0.tick_held >= _hold then
					_s0.current_frame = _i + 1
					_s0.tick_held = 0
					_s0.entry_ticks = 0
				end
				-- ON THE RECORD, NOT IN A GLOBAL. Only the delivery that was
				-- actually frozen may be re-timed above; a run that never met a
				-- freeze has to come out exactly as it did before.
				--
				-- Measured 2026-09-19: dash LP never freezes mid delivery and
				-- works, dash HP does and did not.
				if memory.readbyte(0xFF885C) ~= 0 then
					_s0.saw_freeze = true
				end
				debugKnockdownModule.mark_write("seq_tick", _pl * 256 + _pb, _i)
				return
			end
			-- Spent. Free the slot so the next segment can be queued on this
			-- same tick, by the second pass.
			--
			-- A step with Hold leaves its direction behind. This is the tick it
			-- starts: the entry has been delivered and nothing else will write
			-- 0xFF8B94 until the next step, so without this the direction is
			-- released and a charge never accumulates.
			seq_held_lever = _s0.seq_hold
			if _s0.seq_hold_btn ~= nil then
				seq_held_btn = _s0.seq_hold_btn
				seq_held_btn_until = (memory.readbyte(0xFF8081)
				                      + (_s0.seq_hold_btn_ticks or 0)) % 256
			end
			if seq_held_lever ~= nil then
				-- Once, where the holding starts. Logging it on every tick of
				-- the hold would roughly double the tick trace for nothing -
				-- the value cannot change while it stands.
				debugKnockdownModule.mark_write("seq_hold",
					entry_to_bits(seq_held_lever), memory.readbyte(0xFF8081))
			end
			-- THE DASH CANCEL'S REVERSE, PARKED FROM HERE.
			--
			-- This is the tick the step's last tap went in; the reverse starts
			-- two ticks past it (park_rev adds the offset). A compile only
			-- puts rev on a step with a next step behind it, so the pending
			-- check below only ever fires for a spent LAST segment - clearing
			-- a reverse whose button never came, instead of holding it into
			-- nothing.
			if _s0.seq_rev ~= nil then
				actionSequenceRunnerModule.park_rev(_s0.seq_rev,
					memory.readbyte(0xFF8081))
			end
			if actionSequenceRunnerModule.pending_count() == 0 then
				actionSequenceRunnerModule.rev_clear()
			end
			_d0.pending_input_sequence = nil
		end
		-- STEP ONE'S Hold, COLLECTED ONCE ITS RECORD IS GONE.
		--
		-- The arm places step one, and that path only takes an input list - it
		-- never saw the hold, so "walk twenty ticks, then throw" stood still.
		-- The runner parks it instead, and this is the first tick on which
		-- nothing is being delivered, which is exactly when the holding starts.
		if seq_held_lever == nil and _d0 ~= nil
		   and _d0.pending_input_sequence == nil then
			seq_held_lever = actionSequenceRunnerModule.take_arm_hold()
			-- take_, not first_: this must be handed over once. Asking the
			-- schedule answers the same thing every tick, and the attack came
			-- out again the moment the deadline let go.
			if seq_held_btn == nil
			   and actionSequenceRunnerModule.take_arm_hold_button ~= nil then
				local _hb, _hn = actionSequenceRunnerModule.take_arm_hold_button()
				if _hb ~= nil then
					seq_held_btn = _hb
					seq_held_btn_until = (memory.readbyte(0xFF8081) + (_hn or 0)) % 256
				end
			end
			if seq_held_lever ~= nil then
				debugKnockdownModule.mark_write("seq_hold",
					entry_to_bits(seq_held_lever), memory.readbyte(0xFF8081))
			end
			-- STEP ONE'S DASH-CANCEL REVERSE, COLLECTED WITH IT.
			--
			-- The arm could not carry it either; the runner parked it at arm
			-- time and it starts here, two ticks past the last tap. Inside the
			-- same gate on purpose: the parking takes the tick, and only a
			-- free tick after the record is gone is that tick the anchor.
			actionSequenceRunnerModule.arm_rev_due(memory.readbyte(0xFF8081))
		end
		-- THE PARKED REVERSE, ASSERTED WHILE NOTHING ELSE HAS THE INPUT.
		--
		-- From two ticks past the cancel step's last tap until the next step's
		-- button merges it in the walk above. On the free ticks between, this
		-- is what keeps the back down - the game's cancel window is one frame,
		-- and a gap here is a missed cancel. Switching the guard action away
		-- cancels the schedule below in guardCancelCheck, which empties this.
		do
			local _rvn = actionSequenceRunnerModule.rev_lever_now(
				memory.readbyte(0xFF8081))
			if _rvn ~= nil and globals.dummy.guard_action == 'sequence'
			   and _d0 ~= nil and _d0.pending_input_sequence == nil then
				assert_input_bits(entry_to_bits({ _rvn }), 0)
				return
			end
		end
		-- THE WAITING STEP'S OWN DIRECTION, HELD UNTIL ITS BUTTON GOES IN.
		--
		-- A chain or cancel step waits at the head of the queue through the
		-- previous move's hit stop. Its lever used to arrive with its button on
		-- one tick, and inside a hit stop that is not enough for the game to
		-- pick the crouching version - the attacker's script is frozen there.
		-- Held for the whole wait instead, which is how a chain is played by
		-- hand. The runner adds nothing to the input list for this, so the
		-- button still lands on the tick the gate opens.
		--
		-- After the reverse above, which is a cancel in progress and owns the
		-- lever while it lasts.
		do
			local _wl = actionSequenceRunnerModule.waiting_lever()
			if _wl ~= nil and globals.dummy.guard_action == 'sequence'
			   and _d0 ~= nil and _d0.pending_input_sequence == nil then
				assert_input_bits(entry_to_bits(_wl), 0)
				return
			end
		end
		-- KEEP IT DOWN UNTIL SOMETHING ELSE HAS THE INPUT.
		--
		-- Buttons are deliberately not carried: a held button leaves the next
		-- attack no press edge, and releasing a charge is a direction change,
		-- not a button one.
		--
		-- Dropped when the schedule is empty, so the dummy is not left leaning
		-- on a direction after the sequence has finished.
		-- BEFORE the lever hold, because that one returns when it asserts and
		-- the two have to go down together on a crouching electric attack.
		--
		-- Deliberately NOT dropped when the schedule empties, unlike the lever:
		-- an electric normal is often the whole list, and letting go the tick
		-- it finishes would be letting go before the game has read anything.
		-- The deadline is what ends it.
		if seq_held_btn ~= nil then
			-- The clock is a byte and wraps, so compare a difference. A wrap
			-- ends the hold early rather than holding for another 250 ticks.
			local _left = (seq_held_btn_until - memory.readbyte(0xFF8081)) % 256
			if _left == 0 or _left > 64
			   or globals.dummy.guard_action ~= 'sequence' then
				seq_held_btn = nil
				seq_held_btn_until = nil
			elseif _d0 ~= nil and _d0.pending_input_sequence == nil
			       and globals.show_menu ~= true then
				-- Not behind the menu. Same reason as waiting_lever in the
				-- runner: nothing the hold is for can happen there, and the
				-- button would be asserted for as long as the menu is open.
				--
				-- entry_to_bits answers lever, button - in that order. The
				-- held names are buttons, so what comes back here is the
				-- SECOND value; passing the first would press nothing.
				local _hl, _hb = entry_to_bits(seq_held_btn)
				if seq_held_lever ~= nil then
					_hl = bor8(_hl, (entry_to_bits(seq_held_lever)))
				end
				assert_input_bits(_hl, _hb)
				return
			end
		end
		if seq_held_lever ~= nil then
			if actionSequenceRunnerModule.pending_count() == 0
			   or globals.dummy.guard_action ~= 'sequence' then
				seq_held_lever = nil
			elseif _d0 ~= nil and _d0.pending_input_sequence == nil
			       and globals.show_menu ~= true then
				-- Not behind the menu. A charge held while a Wait row is being
				-- walked is a charge built by the menu, not by the list.
				assert_input_bits(entry_to_bits(seq_held_lever), 0)
				-- Returning here skips nothing: everything below needs a
				-- pending_input_sequence, and there is none while a hold is up.
				return
			end
		end
	end

	if release_input_sequence == nil then return end

	local _d = player_objects and player_objects[2]
	local _seq = _d and _d.pending_input_sequence
	if _seq == nil or _seq.released then return end
	-- kd_tick SEQUENCES MAY LEGITIMATELY CARRY hold_last=false.
	--
	-- queue_input_sequence refuses to hold a sequence that has buttons before
	-- its last entry, which every button-order super does (Darkness Illusion is
	-- LP N LP 6 LK HP). Returning on hold_last alone skipped BOTH the tick
	-- delivery below and the free-1 signature, so the slot sat parked at
	-- current_frame 1 and the frame path put the button on free-3/-2.
	if not _seq.hold_last and not _seq.kd_tick then return end

	-- THE MOTION IN FRONT OF THE BUTTON, ONE ENTRY PER TICK, ON THE $1a7 CLOCK.
	--
	-- What the v130 batch settled, across five characters and 99 wake-ups:
	--
	--     every entry delivered AND button on free-1   30 reversal /  0 nothing
	--     anything else                                 0 reversal / 50 nothing
	--
	-- Two conditions, both necessary, together sufficient. The button half was
	-- already exact - the signature below fires on free-1 and nowhere else - so
	-- every one of those 50 failures is the motion in front of it:
	--
	--     Anakaris   2 of 3 entries, button on free-1   0 of  9
	--     Gallon     2 of 3                             0 of  8
	--     Victor     2 of 3                             0 of  4
	--     Zabel      3 of 3, button on free-2/3/4       0 of 15
	--
	-- The prefix was being delivered by joypad.set() from
	-- process_pending_input_sequence(), which runs once per DISPLAYED FRAME.
	-- A frame is about 1.6 ticks during a knockdown and the arm lands 3-5 ticks
	-- before free, so there is simply not room to walk a three-entry motion
	-- through at that rate - the middle diagonal never got a frame of its own,
	-- and a quarter-circle without its diagonal is not a quarter-circle.
	--
	-- $1a7 counts one per tick and its terminal value is known per character
	-- (KD_END_1A7), so the entry that belongs on this tick is arithmetic:
	--
	--     step = $1a7 - (end - #sequence)      1 .. #sequence-1 here
	--
	-- which puts entry 1 on free-#sequence and the last prefix entry on free-2,
	-- leaving free-1 to the signature below. Written from in front of 0x02211A
	-- so the copy this hook precedes carries it, the same reason the hit-stun
	-- flush above is done here rather than from the frame callback.
	-- FOUR CLOCKS, NOT ONE. Ported from v300, where the Character Specific
	-- real-input path was measured against every one of them.
	--
	-- This used to run only on $140 == 0x0A, the wake-up. A fixed sequence
	-- armed on a guard or an ordinary hit therefore never reached the tick
	-- schedule at all: it fell back to the frame path, which walks one entry
	-- per DISPLAYED frame and put the button on free-3/-2, where no reversal
	-- can start. Measured in v300 on Darkness Illusion (LP N LP 6 LK HP), and
	-- reported here as "every button-order super fails except after a Chaos
	-- Flare" - a Chaos Flare being the one reaction that reaches this hook by
	-- another route.
	local _b140tick = memory.readbyte(0xFF8940)
	if _seq.kd_tick and _seq.sequence ~= nil
	   and (_b140tick == 0x0A or _b140tick == 0x04 or _b140tick == 0x00
	        or _b140tick == 0x02 or _b140tick == 0x12 or _b140tick == 0x0E) then
		local _len  = #_seq.sequence
		local _step = nil
		if _seq.hs_tick_lg ~= nil then
			-- HIT-STUN ELAPSED CLOCK.
			--
			-- There is no input-clean countdown in memory for hit stun: $15c is
			-- shortened by our OWN injected inputs, which is also why a Chaos
			-- Flare's recovery moves under the command being entered. So the
			-- schedule runs off the tick the sequence was queued on instead -
			-- entry k goes in k+1 ticks after the queue - and the prefix covers
			-- free-7..-3 for a six-entry command.
			--
			-- The free-1 signature (b=04, c=00) is NEVER a delivery tick: when
			-- the schedule reaches it the prefix falls through and the signature
			-- below places the button. lg rewinds with the game, so a
			-- re-executed tick recomputes the same step.
			if memory.readbyte(0xFF8806) == 0x04
			   and memory.readbyte(0xFF8807) == 0x00 then
				-- fall through to the signature
			else
				local _el = ((memory.readbyte(0xFF8081) - _seq.hs_tick_lg) % 256) - 1
				if _el >= 1 and _el <= _len - 1 then
					local _plev, _pbtn = entry_to_bits(_seq.sequence[_el])
					assert_input_bits(_plev, _pbtn)
					debugKnockdownModule.mark_write("kd_step", _el * 256 + _plev,
						memory.readbyte(0xFF8081))
					return
				end
			end
		elseif _b140tick == 0x02 or _b140tick == 0x12 then
			-- BLOCK CLOCK. grem = gsl - $164 is the measured distance to free
			-- and reads one less per tick until it pins at 0 for the last two
			-- ticks (free-2 and free-1). step = len - grem puts entry 1 on
			-- grem len-1 and the last prefix entry on grem 1 = free-3, with
			-- free-1 left to the signature below - the same shape as the $1a7
			-- schedule.
			local _gl = BLK.script_len(memory.readbyte(0xFF8859))
			if _gl ~= nil then
				_step = _len - (_gl - memory.readword(0xFF8964))
			end
		elseif _seq.kd_land then
			-- THE LANDING CLOCK, FOR THE CHARACTERS $1a7 CANNOT TIME (v132).
			--
			-- Demitri's wake-up does not end on his animation - 0x0310E0 calls
			-- the landing test at 0x0273E2 and waits for it - so his $1a7
			-- terminal is 26 on some knockdowns and 28 on others and no table
			-- can hold him. ticks_to_landing() replays that same physics, and
			-- measured over all 17 of his v131 wake-ups it is exact:
			--
			--     free-7  ld=6   free-5  ld=4   free-3  ld=2
			--     free-6  ld=5   free-4  ld=3   free-2  ld=1   free-1  ld=1
			--
			-- so ld == n - k + 1 places entry k, entry 1 landing on free-(n+1)
			-- and the last prefix entry on free-3. ld reads 1 on both free-2 and
			-- free-1, which is why the prefix stops at n-1 and leaves free-2
			-- empty - a one tick gap costs nothing against a step timeout of
			-- 14 to 19 ticks (0x02A55A), and it keeps this branch from stealing
			-- the tick the signature below needs.
			local _ld = ticks_to_landing()
			if _ld ~= nil then _step = _len - _ld + 1 end
		else
			local _end = kd_end_1a7()
			if _end ~= nil then
				_step = memory.readbyte(0xFF89A7) - (_end - _len)
			end
		end
		-- THE LAST ENTRY TOO, WHEN THERE IS NO SIGNATURE TO PLACE IT.
		--
		-- Everyone else gets their button from the free-1 signature hook below.
		-- Q-Bee has no signature at all (see KD_NO_SIG), so for her the final
		-- entry - the one carrying the button - is injected here, on the tick
		-- $1a7 reaches her terminal, which measurement puts at free-1 exactly
		-- as it does for everybody else.
		local _laststep = _len - 1
		if KD_NO_SIG[memory.readbyte(0xFF8B82)] then _laststep = _len end
		if _step ~= nil and _step >= 1 and _step <= _laststep then
			local _plev, _pbtn = entry_to_bits(_seq.sequence[_step])
			if _step == _len and _pbtn == 0 then
				_pbtn = button_mask(GA.button())
			end
			if _step == _len then
				-- Direction now, button on the next tick - the free tick, where
				-- her input window finally is. Handed to the same deferred path
				-- the normals use.
				assert_input_bits(_plev, 0)
				fast_press_lg  = memory.readbyte(0xFF8081)
				fast_press_fref = facing_for_input()
				fast_press_lev = _plev
				fast_press_btn = _pbtn
				fast_press_off = 1
				debugKnockdownModule.mark_write("nosig_defer",
					_plev * 256 + _pbtn, memory.readbyte(0xFF89A7))
				return
			end
			assert_input_bits(_plev, _pbtn)
			debugKnockdownModule.mark_write("kd_step", _step * 256 + _plev,
				memory.readbyte(0xFF89A7))
			return
		end
	end

	-- THE CORE SIGNATURE, AND IT IS THE SAME FOR EVERY RECOVERY VARIANT.
	--
	-- Measured on the canonical (rewind-free) timeline, this state lasts
	-- exactly one tick, and the tick after it is always the transition to
	-- actionable:
	--
	--     $140 = 0x00  hit-stun            24 of 24, run length 1, 0 false
	--     $140 = 0x0A  knockdown wake-up    1 of  1
	--     $140 = 0x04  air-hit landing      1 of  1
	--
	-- It never once occurred without the next tick being free. So $20 == 0
	-- and $1a7 == 27, which the knockdown path tests below, are an
	-- unnecessary specialisation of this - $1a7 is not even running during
	-- hit-stun, and $20 reads 1 or 254 there.
	if memory.readbyte(0xFF8805) ~= 0x02 then return end   -- $05 still Hurt
	if memory.readbyte(0xFF8806) ~= 0x04 then return end   -- $06 actionable sub-state
	if memory.readbyte(0xFF8807) ~= 0x00 then return end   -- $07

	-- THE EXTRA KNOCKDOWN CONDITIONS ARE GONE, AND SO IS THE 0x04 EXCLUSION.
	--
	-- The knockdown path used to also require $20 == 0 and $1a7 == 27. Those
	-- were kept because that combination had measured 100% over hundreds of
	-- attempts - but every one of those attempts was against the SAME dummy
	-- character. Run against Demitri instead and the wake-up ends one tick
	-- later with a different animation counter:
	--
	--     dummy A   free-1:  $1a7 = 27,  $20 = 0
	--     Demitri   free-1:  $1a7 = 28,  $20 = 4     -> hook never fired, 0/20
	--
	-- They are character-specific timings, not part of the signature. The
	-- signature itself is not: $06 = 0x04 with $07 = 0x00 held at free-1 in
	-- all 68 transitions of that batch and all 112 of the one before it,
	-- across both dummies and all three recovery variants.
	--
	-- 0x04 (air recovery) is enabled for the same reason. It was excluded on
	-- one sample; the Demitri batch produced 31 transitions that reach free
	-- with $140 still 0x04, all carrying the same signature.
	-- BLOCK IS 0x02 ON THE GROUND AND 0x12 IN THE AIR (v143).
	--
	-- 0x02393A is the block routine:
	--     02393A  move.b #$12, ($140,A6)     ; air block
	--     023954  tst.b  ($38,A6) / bne      ; airborne?
	--     02395A  move.b #$2,  ($140,A6)     ; ground block
	--     023960  move.b #$e,  ($158,A6)     ; 14 ticks of block stun
	--     023966  move.b #$e,  ($1ab,A6)
	--     02397A  moveq  #$c, D0             ; animation 0x0C standing
	--     02397C  tst.b  ($121,A6) / moveq #$d   ; 0x0D crouching
	-- and 0x022492 counts $158 down one per tick, in the same generic block as
	-- $174. Character code keys Guard Cancels on it (0x02E17C, 0x02FFE2 test
	-- $158 before writing a move id), which is what makes it the block clock.
	--
	-- The free-1 signature is IDENTICAL for block. Measured over 39 block spans
	-- already sitting in the archives:
	--     free-1  $05=02 $06=04 $07=00 $140=02
	--     free+0  $05=00 $06=00
	-- exactly what a knockdown does. So the only thing that kept the tool out
	-- of block stun was this list.
	local _recovery = memory.readbyte(0xFF8940)
	if _recovery ~= 0x00 and _recovery ~= 0x0A
		and _recovery ~= 0x04 and _recovery ~= 0x0E
		and _recovery ~= 0x02 and _recovery ~= 0x12 then
		return
	end

	-- NOTHING IS LATCHED HERE. THAT IS THE WHOLE POINT (v34).
	--
	-- The emulator re-executes ticks. Measured on the v33 batch: of 23040
	-- consecutive tick pairs, 6635 had 0xFF8081 go BACKWARD by 1 or 2, and
	-- the knockdown clock $1a7 itself rewound on 1450 of them. About 29% of
	-- the ticks this hook sees are a speculative pass that is thrown away and
	-- run again.
	--
	-- Emulator RAM is restored by that rewind. Lua variables are NOT. So v33,
	-- which called release_input_sequence() on the first tick the signature
	-- matched, permanently flipped a Lua flag during a pass whose memory
	-- write was then discarded - after which the write hook re-asserted the
	-- button from the earliest re-executed tick onward. That is precisely the
	-- "comes out too early / does not come out" failure: the press edge
	-- landed 2 to 6 ticks before the transition instead of 1.
	--
	--     edge at free-1 : 10 reversal /  0 nothing
	--     edge at free-2 :  5 reversal / 13 nothing
	--     edge at free-3 :  1 reversal / 12 nothing
	--     edge at free-4 :  0 reversal / 20 nothing
	--
	-- So this hook must be a pure function of emulator memory, and idempotent:
	-- it writes the bits whenever the signature holds and remembers nothing.
	-- A speculative pass writes them and has the write rolled back; the real
	-- pass writes them again, on the real free-1 tick.
	--
	-- With the re-executed ticks removed from the v33 trace, the signature is
	-- exactly one tick long in 69 of 69 knockdown transitions, and the tick
	-- after it is the transition in 69 of 69. It is an exact predictor - the
	-- "sometimes two ticks long" seen in v32 was this rewind, not the engine,
	-- which is also why the 0xFF815D / $194 gates v33 added are gone again:
	-- they were guarding against an artefact.
	local _lev, _btn = 0, 0
	if _seq.sequence ~= nil then
		_lev, _btn = entry_to_bits(_seq.sequence[#_seq.sequence])
	end
	if _btn == 0 then _btn = button_mask(GA.button()) end
	local _base = kd_press_base()
	local _off  = kd_press_offset()

	-- SPLIT THE MOTION FROM THE BUTTON WHEN THERE IS A DELAY (v173).
	--
	-- The delay used to move the last entry and the button together, and the
	-- prefix in front of them does NOT move - it is placed off $1a7 and always
	-- lands earliest. So "Forward Dash + HP, delay 14" put tap one on free-3
	-- and tap two on free+14: seventeen ticks apart, which is not a dash at
	-- all, just a late forward+HP. A quarter circle survived only because the
	-- recogniser's step timeout is 14-19 ticks and the gap fitted inside it.
	--
	-- What the delay is being asked for is "fastest dash, THEN press HP N ticks
	-- later", so the motion finishes where it always did and the button alone
	-- waits. With no delay, or with no button to wait for, moff == off and this
	-- is the old single injection.
	-- TAKE THE WHOLE MOTION, NOT WHAT current_frame CLAIMS IS LEFT (v177).
	--
	-- v176 trusted current_frame. The v176 batch says that is not safe: on the
	-- delay-4 spans it read 2 every time - the frame path had advanced past
	-- entry one - and yet on half of them the forward NEVER APPEARS in $394 at
	-- all in the fourteen ticks before the signature. The counter moved and the
	-- input did not arrive. Successes have it exactly one tick before the
	-- signature, failures nowhere:
	--
	--     s10 g=180  lev=2  -> $06 = 0x14 at g=183   dash
	--     s09 g=54..67  no lev=2 anywhere -> $06 = 0x04   walk
	--
	-- Same delay, same character, same everything. That is the "4 is messy" the
	-- report describes, and no arithmetic on current_frame can fix it because
	-- the counter is not evidence that the entry went in.
	--
	-- So the whole motion goes in from here, one entry per tick, and the frame
	-- path's opinion is ignored. Re-sending an entry it did deliver costs
	-- nothing: the tick hook writes in front of the copy the game consumes, so
	-- the last write for a tick is the only one that counts.
	--
	-- NOT for kd_tick sequences. There the $1a7 schedule has already walked the
	-- prefix at one entry per tick, and process_pending_input_sequence returns
	-- early for them so current_frame never moves - taking over would replay a
	-- motion that already went in. Wake-ups keep the placement they have.
	-- A LONG MOTION CANNOT BE WALKED BY THE FRAME PATH (v204).
	--
	-- The prefix is normally left to process_pending_input_sequence, which is
	-- one entry per DISPLAYED frame. That is fine for the three entry motions
	-- everything was measured on - two entries in the five to eight ticks
	-- between the arm and the signature - and it is a tick FASTER than taking
	-- over here, because the first tap gets in before the signature and the
	-- second can then land on free+0 rather than free+1. v178 removed the
	-- takeover for exactly that reason.
	--
	-- It does not survive a longer motion. A dash cancel is six entries since
	-- v203, so the frame path needs about seven ticks for the five in front of
	-- the last one and the lead is not that long: the motion never finishes and
	-- NOTHING comes out. Reported as "Forward Dash Cancel never fires once".
	--
	-- So the tick hook takes the prefix over once the motion is long enough
	-- that the frame path cannot have finished it. One entry per tick always
	-- fits; the cost is the single tick v178 was protecting, and a motion that
	-- is a tick late beats one that never arrives.
	--
	-- NOT FOR SPECIALS (v205). The first cut of this tested length alone and
	-- broke every special of four entries or more - 360, HCF, HCB, 720 - which
	-- were coming out perfectly well. A special's press belongs on free-1
	-- (kd_press_base returns 0 for one), and taking the prefix over moves it to
	-- free+3 or later, because the last entry cannot land before the prefix in
	-- front of it is out. Four ticks late is not a reversal.
	--
	-- The frame path gets those there in time, so it keeps them. What is left
	-- is the dash cancel, which is the only long motion that is not a special -
	-- and the only one that was actually broken.
	-- (v204 took the prefix over for long motions and v205 had to exclude
	-- specials from it. Neither is needed now: the only long motion was the
	-- dash cancel, and v207 made that three entries again. Left empty rather
	-- than deleted so the reasoning above stays attached to the code it is
	-- about.)
	fast_press_q = {}

	-- A DASH CANCEL REVERSES AFTER THE DASH, NOT WITH IT (v207).
	--
	-- The motion is the plain dash, so its second tap is on free+0 and the dash
	-- itself on free+1. The reverse cannot go in before that or there is no
	-- dash to cancel - which is what v203 hit. Two ticks past the motion is the
	-- first place it can sit, so the whole press moves back by that much and
	-- fc/bc count from there.
	fast_press_rev = dash_cancel_reverse_bits()
	if fast_press_rev ~= nil then
		_off = _off + 2
	end

	local _split = (_off > _base) and (_btn ~= 0)
	-- The last entry cannot land before the prefix in front of it is out.
	local _moff = _base
	if #fast_press_q > _moff then _moff = #fast_press_q end
	if _moff > _base then
		_off = _off + (_moff - _base)
		_split = (_btn ~= 0)
	end
	fast_press_moff = _split and _moff or _off
	fast_press_mlev = _lev
	fast_press_hold = kd_holds_direction()

	if _off == 0 then
		assert_input_bits(_lev, _btn)
	else
		-- LEAD WITH THE DIRECTION ONLY WHEN THERE IS A BUTTON TO FOLLOW.
		--
		-- For a command normal like forward+HP the direction can go in early at
		-- no cost - it is not what the game refuses - and holding it makes the
		-- later press unambiguous.
		--
		-- A DASH HAS NO BUTTON. Its final entry IS a direction press, and the
		-- edge is the whole point: $126 is ~$124 & $122, so a forward already
		-- held from the tick before produces no edge at all and the second tap
		-- of the dash never registers. Measured as "the dash is not fastest".
		-- So when the entry carries no button, put nothing in early.
		-- WITH NO BUTTON, THE TICK BEFORE MUST BE NEUTRAL (v155).
		--
		-- v140 stopped leading with the direction here because a dash's final
		-- entry IS the press and a held direction produces no edge. Injecting
		-- nothing is not enough though: the dummy holds BACK continuously to
		-- block, and the trace shows $394 bit0 set for fourteen ticks straight
		-- before the wake-up. A back dash asks for back again on top of a back
		-- that never went away, so $126 - which is ~$124 & $122 - stays zero and
		-- the second tap does not exist. Forward dash was unaffected because
		-- forward is not the direction being held.
		--
		-- So put neutral in for this one tick. It is a release, which is exactly
		-- what a player does to dash backwards out of blockstun, and it cannot
		-- cost anything: the character is still in blockstun on this tick and
		-- cannot be hit out of it.
		if _split then
			-- Tick zero of the split. The prefix goes first when there is one,
			-- otherwise this is either the last entry itself (_moff == 0) or
			-- the neutral in front of it.
			local _pe = fast_press_q[1]
			if _pe ~= nil then
				local _pl, _pb = entry_to_bits(_pe)
				assert_input_bits(_pl, _pb)
				debugKnockdownModule.mark_write("prefix_now", _pl * 256 + _pb, 0)
			else
				assert_input_bits(_moff == 0 and _lev or 0, 0)
			end
		elseif _btn ~= 0 then
			assert_input_bits(_lev, 0)
		else
			assert_input_bits(0, 0)
		end
		fast_press_lg  = memory.readbyte(0xFF8081)
		fast_press_fref = facing_for_input()
		-- What rides in WITH the button. Merged with the motion when there is
		-- no delay; on a split it is the held direction, or nothing.
		local _ov = button_lever_bits()
		if _ov ~= nil then
		-- Ahead of fast_press_rev on purpose: an explicit choice should not be
		-- quietly overruled by the dash cancel's reverse direction. It does
		-- mean picking a lever on a dash cancel stops the cancel happening,
		-- which the menu text says.
		fast_press_lev = _ov
	elseif fast_press_rev ~= nil then
		fast_press_lev = fast_press_rev
	elseif _split then
		if fast_press_hold then fast_press_lev = _lev else fast_press_lev = 0 end
	else
		fast_press_lev = _lev
	end
		fast_press_btn = _btn
		fast_press_off = _off
		debugKnockdownModule.mark_write("press_defer",
			fast_press_lev * 256 + _btn, _off)
	end
	-- The tick-driven motion is now complete. Remembered so the reactive path
	-- at the wake-up frame does not queue the whole thing again behind it -
	-- that second motion is what the delay-12/13 tail in the v130 batch is
	-- (Gallon 8, Anakaris 7, Victor 4 spans), and on screen it reads as the
	-- command being entered twice.
	if _seq.kd_tick then
		kd_set_motion_done(true)
		-- Same as the deferred path above: the whole motion including its
		-- button has gone in, so nothing is left for the frame-side delivery
		-- and the slot should be free for the next recovery. Only when the
		-- press actually happened - a deferred one has not fired yet and must
		-- keep its sequence until it does.
		if _off == 0 then
			_d.pending_input_sequence = nil
		end
	end

	-- Diagnostic only. This DOES persist across a rewind, so speculative
	-- passes show up as extra entries - which is exactly what makes the
	-- rewind visible in the next batch. It must not gate anything.
	debugKnockdownModule.mark_hold({ kd = memory.readbyte(0xFF89A7),
		st1 = memory.readbyte(0xFF8805), st2 = memory.readbyte(0xFF8806),
		sub = memory.readbyte(0xFF8807), anim_fin = memory.readbyte(0xFF8821),
		recovery = _recovery, held = _seq.held or 0, lev = _lev, btn = _btn,
		lg = memory.readbyte(0xFF8081),
		event = "tick_inject", trigger = "ticktimed" })
end)

memory.registerwrite(0xFF8990, 1, function()
	debugKnockdownModule.mark_write("0xFF8990", memory.readbyte(0xFF8990), memory.getregister("m68000.pc"))
end)
memory.registerwrite(0xFF8994, 1, function()
	debugKnockdownModule.mark_write("0xFF8994", memory.readbyte(0xFF8994), memory.getregister("m68000.pc"))
end)

-- REMOVED, and why - so none of these get retried:
--
--   * 0xFF8996 - 784 writes in one ~260-frame recording, toggling 1/2 nearly
--     every frame. An unrelated fast counter that only looked meaningful in a
--     single noisy A/B snapshot pair.
--   * The ten "snapdiff" candidates (0xFF804C/8838/8839/8895/8896/8897/88AC/
--     8905/890D/8930), taken from a 3-REVERSAL vs 4-normal MAME snapshot
--     intersection. Superseded: checked against user-marked ground truth,
--     none separated success from failure, and several were pure noise
--     (0xFF8930 logged 1568 writes in one recording).
--   * memory.registerwrite(0xFF8804, 4, ...), testing for the dword
--     0x02020400 (dummyState.lua's p2_reversal_frame). Two things wrong.
--     The theory was disproven against marked ground truth - and, far worse,
--     a size-4 hook covers 0xFF8804..0xFF8807, so it SILENTLY STOLE
--     debugKnockdown.lua's own 0xFF8806 hook (registerwrite is single-slot,
--     and that applies across a size range, not just the base address). One
--     whole test batch logged zero 0xFF8806 writes because of it, which
--     briefly looked like "the special never comes out at all". Watch the
--     size argument on every registerwrite: it claims a RANGE.
--
-- WHAT ACTUALLY WORKS (confirmed on two independent data sources, 18/18 on
-- user-marked FBNeo recordings and 7/7 on live MAME snapshots taken with
-- "REVERSAL" visible/not visible on screen):
--
--   a reversal happened  <=>  0xFF89A7 (knockdown clock) is still NONZERO on
--                             the frame 0xFF8806 (action) becomes a special
--                             (0x0E / 0x10 / 0x12)
--
-- The move itself comes out either way - 18 of 18 recorded attempts reached
-- 0x0E within 1-2 frames of release, successes and failures alike. So
-- "did a special come out" is NOT a success test; it was the false-positive
-- source behind several wrong readings earlier in this investigation. The
-- real difference is whether the move starts while the wake-up state is
-- still live (reversal) or 1-2 frames later once it has been cleared
-- (ordinary special, no reversal).
--
-- No new hook is needed for this: BOTH bytes are already inside
-- debugKnockdown.lua's REGIONS sweep (0xFF8800,256 covers 0xFF8800-0xFF8BFF,
-- so 0xFF8806 and 0xFF89A7 are both captured every frame in rows), which
-- means any recording - including every one already on disk - can be
-- classified offline with no instrumentation at all.

-- TEMPORARY diagnostic, read-only. User's own question: is a second attack
-- (e.g. a follow-up Shadow Blade) landing on P2 before it has fully
-- recovered from the first knockdown, re-extending the down/hurt state and
-- adding noise to the timing measurements above? 0xFF8406 is P1's status_2
-- (parse_status_2 in dummyState.lua has the value table - 0x0A "Ground
-- Normal Attack", 0x0E/0x10/0x12 specials). No existing hook on it anywhere
-- in the scripts (checked - free slot).
memory.registerwrite(0xFF8406, 1, function()
	debugKnockdownModule.mark_write("0xFF8406", memory.readbyte(0xFF8406), memory.getregister("m68000.pc"))
end)

-- Runs before the frequency roll, because a sequence that is already armed has
-- to be released on the exact frame the reversal window opens whatever this
-- frame's roll says - and has to be cleaned up if the window never comes.
-- FINISH AN ABANDONED MOTION INSTEAD OF WAITING FOR IT TO EXPIRE.
--
-- When a new hit interrupts a motion that has already put forward and down
-- in, the recogniser is left parked on its down-forward step. Section 8.6.26
-- covers what that does to the next attempt: the step is matched by a bitwise
-- AND, so the next attempt's FORWARD satisfies it, the stale command
-- completes mid-stun, and the new attempt is desynced from there.
--
-- v46 waited HS_STALE_CLEAR frames so the stale block timed out on its own.
-- That works but costs lead time, and the lead is the scarce resource here.
--
-- Completing the motion is better, because it resolves the command outright
-- instead of waiting for it to rot.
--
-- CORRECTION (v48). v47 sent the last DIRECTION only, on the reasoning that
-- clearing the work block needs nothing more. That reasoning came from
-- 0x02A506, which on closer reading is the DASH recogniser and not the
-- special-move one - it is entered from 0x029F12/0x029F1C with A4 = $1f0/$1f8
-- and D1 = 2/1, and its result lands in $113/$114, the two dash flags cleared
-- every tick at 0x0223E4/0x0223E8. The special-move forms at 0x029F4A test
-- the HELD lever for equality (029FBA: cmp.w D1,D0 against $12a) and return
-- without clearing on a mismatch, so they do not behave the same way at all.
--
-- The buffer is not released until the BUTTON goes in after the motion has
-- completed. So the flush sends the motion's final direction AND its button,
-- for one tick. The dummy is in hit stun and cannot act on it, so nothing
-- comes out; the point is only that the command reaches its end and the
-- buffer is free for the next attempt.
--
-- The cost is one frame of direction+button in the input history during the
-- combo. That is a real input and is shown honestly.
local function hs_request_flush(_stale)
	if _stale == nil or _stale.sequence == nil then return end
	-- Nothing was delivered yet, so there is nothing stale to resolve.
	local _next = _stale.current_frame or 0
	if _next <= 1 then return end

	-- FINISH THE MOTION FROM WHERE IT WAS INTERRUPTED - not just its last
	-- entry (v50).
	--
	-- v48/v49 pushed in the final entry alone. That completes the command
	-- only when the abort happened while the motion was already parked on its
	-- last-but-one entry. When the new hit arrives earlier - and it often
	-- does, the trace shows aborts with only FORWARD delivered - the flush
	-- puts in forward then down-forward, skipping the down. That is not a
	-- dragon punch, so there is no completed motion for the button to
	-- release, and the buffer stays dirty exactly as before:
	--
	--     -26  $122 = 0x0002   F        <- 2nd hit lands here
	--     -25  $122 = 0x0206   DF+MP    <- flush; F -> DF, no D
	--      ...
	--      -1  $122 = 0x0206   DF+MP    <- fresh attempt, still no reversal
	--
	-- So replay every entry the motion had not reached yet, one per tick,
	-- ending on the last one with its button. controller.lua leaves
	-- current_frame pointing at the NEXT entry to send (it writes the entry
	-- and only then advances - controller.lua:564), so that index is where
	-- the replay starts.
	-- STORE THE ENTRIES, NOT THE BITS (v53).
	--
	-- entry_to_bits() resolves "forward"/"back" against the facing byte at the
	-- moment it is called. Called here, that is the frame the flush is
	-- REQUESTED; the ticks that actually deliver it come later, and the
	-- character can turn round in between - which is exactly what Morrigan's
	-- wake-ups and air recoveries do. Converting at injection time instead
	-- means every direction goes in under the facing that is true when it
	-- goes in.
	hs_flush_q = {}
	local _n = #_stale.sequence
	for _i = math.min(_next, _n), _n do
		table.insert(hs_flush_q, { entry = _stale.sequence[_i], last = (_i == _n) })
	end
	if #hs_flush_q > 0 then
		-- SPACE THE NEXT DELIVERY AWAY FROM THIS FLUSH.
		--
		-- v50 cleared this instead, on the reasoning that a flushed block is
		-- back at step 0 so nothing needs spacing. Measured over 64 light
		-- chains that is wrong - the flush's own input is still live in the
		-- recogniser for a while after it:
		--
		--     flush -> fresh forward, 13 ticks    1 reversal /  8 nothing
		--     14 ticks                            9 /  1
		--     16 ticks and more                  32 /  4
		--
		-- 14 is the shortest step timeout, which is what that boundary is.
		-- Recording the flush time here makes hs_clamp_delivery() hold the
		-- fresh motion off until the flush has aged out.
		--
		-- (Emulator pacing was checked as an alternative explanation and is
		-- not one: 2 ticks per displayed frame during delivery gives 86/15
		-- and 3 ticks gives 50/10 - the same rate.)
		hs_last_deliver_f = memory.readbyte(0xFF8081)
	end
end

-- Pushes a planned delivery out far enough that any previously delivered
-- motion has certainly timed out of the recogniser first. See HS_STALE_CLEAR.
-- Turns a measured lead (in ticks) into a countdown (in ticks).
--
-- Two things have to come out of the lead before the final direction lands:
-- the hold, and the delivery of the entries before it. The controller sends
-- one entry per DISPLAYED frame, so those cost hs_ticks_per_frame ticks each,
-- not one - at Normal that is the 2 the old frame-based arithmetic assumed,
-- under turbo it is several times more.
-- HOW MANY ENTRIES THE COMMAND HAS, FOR THE COUNTDOWN BELOW.
--
-- The same question the three other arm points ask, through the same function:
-- seq_len answers with first_len("reversal") in sequence mode and with the
-- motion's own length otherwise. Three is what the countdown's constants were
-- measured against, so that is the fallback when there is nothing to ask.
local HS_BASE_ENTRIES = 3

local function hs_entries()
	if globals == nil or globals.dummy == nil then return HS_BASE_ENTRIES end
	local _n = seq_len(globals.dummy.counter_attack_stick)
	if type(_n) ~= "number" or _n < 1 then return HS_BASE_ENTRIES end
	return _n
end

local function hs_countdown_for(_lead)
	-- Where the final direction has to land is fixed: free-1. Working back
	-- from there, the second-to-last entry should land HS_TARGET_HOLD ticks
	-- before it, and that entry is delivered one DISPLAYED FRAME after the
	-- first - which is hs_ticks_per_frame ticks, not one.
	--
	--     countdown = lead - (hold + 1) - ticks_per_frame
	--
	-- The previous form was `lead - hold - 2*ticks_per_frame`. At one tick per
	-- frame the two are the same expression (lead - 8), which is why every
	-- Normal-speed batch was unaffected and this went unnoticed. At turbo they
	-- diverge: measured at 4.0 ticks per frame the old form delivers three
	-- ticks early, the hold stretches to 12-16 ticks, and the motion times out
	-- of the recogniser (14-19). That is the whole of the air-recovery 0/16
	-- and throw-escape 0/12 in the v65 turbo batch.
	--
	-- A LONG COMMAND NEEDS THE WHOLE PREFIX IN BEFORE free-1.
	--
	-- The tick schedule puts entry k at queue+k+1 and leaves free-1 to the
	-- signature, so a list of n entries needs the queue n+2 ticks before free.
	-- The expression above puts it at free-8 whatever n is: a 5-entry command
	-- lands its last prefix entry on free-3 with two ticks to spare, and a
	-- 6-entry one lands on free-2 with none.
	--
	-- Zero slack is not enough, because free moves. $15c is decremented by OUR
	-- OWN injected inputs as well as by the clock (see the note at kd_land_arm),
	-- so the actionable tick creeps closer while the motion is going in - and
	-- the more entries, the more it creeps. Measured here: Finishing Shower
	-- (5 entries) reverses every time, Darkness Illusion (6, LP N LP 6 LK HP)
	-- about half the time, and the failures come out without the LK - the entry
	-- that had been scheduled onto the signature's own tick.
	--
	-- Starting earlier is safe in a way that starting later is not: the BUTTON
	-- is placed by the signature, not by this schedule, and the recogniser
	-- holds a completed motion for 14 to 19 ticks (0x02A55A). A prefix that
	-- finishes early simply waits.
	--
	-- Written as the EXCESS over three rather than as (n-1), so a 3-entry
	-- command keeps exactly the countdown its constants were measured against.
	local _extra = (hs_entries() - HS_BASE_ENTRIES) * hs_ticks_per_frame
	if _extra < 0 then _extra = 0 end
	local _c = _lead - (HS_TARGET_HOLD + 1) - hs_ticks_per_frame - _extra
	if _c < 1 then _c = 1 end
	return _c
end

local function hs_clamp_delivery(_ticks)
	-- A flushed block is already back at step 0, so the spacing that
	-- HS_STALE_CLEAR buys is not needed and would only eat into the lead.
	if hs_last_deliver_f == nil then return _ticks end
	-- HS_STALE_CLEAR is a step timeout, so it is in TICKS. The elapsed part
	-- is a difference of displayed frames, so convert it before subtracting -
	-- mixing the two is what the countdown itself was getting wrong.
	local _elapsed = (globals.current_frame - hs_last_deliver_f) * hs_ticks_per_frame
	local _min = HS_STALE_CLEAR - _elapsed
	if _ticks < _min then return _min end
	return _ticks
end

-- Current run-ahead reading, for the logger and for anything that wants to
-- behave differently under it. See the counters above.
-- Emulator pacing over the session, for the logger. See the counters above.
function guardcancel_lag_state()
	return {
		ticks_max   = lag_ticks_max,
		slow_frames = lag_slow,
		frames      = lag_frames,
		ms_max      = math.floor(lag_ms_max * 10) / 10,
		tpf_now     = math.floor(hs_ticks_per_frame * 100) / 100,
	}
end

function guardcancel_runahead_state()
	local _pct = 0
	if ra_ticks > 0 then _pct = math.floor(1000 * ra_rewinds / ra_ticks) / 10 end
	return {
		active     = rewind_seen,
		rewinds    = ra_rewinds,
		ticks      = ra_ticks,
		percent    = _pct,
		depth_max  = ra_depth_max,
	}
end

local function service_held_reversal()
	-- Knockdown and hit stun arm once per stun span, so entering stun is their
	-- opportunity. The block path bumps again on each $158 rise below, which is
	-- the one place a second opportunity exists inside a single span.
	if memory.readbyte(0xFF8805) ~= 0 and not prev_in_stun then
		gc_opportunity = gc_opportunity + 1
	end
	local _d = player_objects and player_objects[2]
	local _in_stun = memory.readbyte(0xFF8805) ~= 0
	local _kd = memory.readbyte(0xFF89A7)

	-- A SEQUENCE SEGMENT IS NOT THIS FUNCTION'S BUSINESS (v300).
	--
	-- Everything below places a held reversal's button and tidies away motions
	-- that never found a window. A later segment of an action sequence has
	-- neither need: the tick hook walks it entry by entry and releases nothing.
	--
	-- It would also be destroyed here. The drop at the bottom fires when the
	-- dummy is neither in stun nor knocked down - which is precisely the state
	-- a segment runs in - so without this the segment was deleted on the very
	-- frame it was queued.
	if _d ~= nil and _d.pending_input_sequence ~= nil
	   and _d.pending_input_sequence.seq_tick then
		return
	end

	-- Pre-buffering is armed ONLY off the knockdown clock at 0xFF89A7.
	--
	-- An earlier version also armed on entering hit/block stun, on the
	-- reasoning that stun is short. That was wrong, and wrong in the worst
	-- way: at the moment a knockdown STARTS the dummy is in stun and the
	-- knockdown clock has not begun, so the stun branch fired first and put the
	-- motion in thirty-odd ticks before the wake-up. An input only stays live
	-- for about ten, so the first direction had long expired by the time the
	-- button went in and the move degraded to a normal.
	--
	-- There is no clock for plain hit or block stun, and without one there is
	-- no way to know whether the trigger is two ticks away or forty. So those
	-- reversals are left on the original path - a couple of frames late, but
	-- correct. That also keeps directions out of block stun entirely, which
	-- removes any question of the pre-buffer interfering with guarding.
	--
	-- kd_armed keeps it to one attempt per knockdown, and with it one Guard
	-- Action Frequency roll, matching the old behaviour.
	if _kd == 0 then
		kd_armed = false; kd_armed_by_land = false
	end
	-- kd_start_07 and kd_motion_done are maintained by kd_capture_start_07()
	-- from the per-tick hook. Doing it here as well would be harmless but
	-- pointless: this function only sees about six ticks in ten.

	-- Pit of Blame: its own trigger, because the ordinary reversal window
	-- opens far too late for this move. See the constants above this function
	-- for the full history of why this waits for the dummy to go airborne
	-- and then counts a fixed delay from there, instead of watching 0xFF8980
	-- or counting from stun onset.
	--
	-- Two guards on arming, both from real-hardware misfires:
	--   * 0xFF8009 == 4 (match in progress) - it fired during the intro.
	--   * status_1 exactly 0x02 "Hurt or Block" - the usual "in stun" test
	--     (0xFF8805 ~= 0) is also true for 0x06 "Be Thrown" and 0x0E "Intro"
	--     (see dummyState.lua parse_status_1).
	--
	-- FIX: Guard Action Frequency had no effect on this move - it came out
	-- every single knockdown whatever the setting said. This trigger runs
	-- ahead of the shouldGC() call in guardCancelCheck (that call sits behind
	-- an early return), so it was never subject to the roll at all. It now
	-- takes its own, once, here on arming - rolling anywhere that runs every
	-- frame would effectively force 100%, the same trap the pre-buffer arming
	-- note above this function describes.
	--
	-- pit_of_blame_armed holds arming (and the frequency roll) to one attempt
	-- per hurt/block span - which may contain a whole chain combo, not just
	-- one hit. pit_of_blame_fired holds the actual send to one attempt within
	-- that span, PIT_OF_BLAME_INPUT_DELAY frames after the dummy is first
	-- seen airborne - i.e. the knockdown hit specifically, wherever it falls
	-- in the chain. All reset on leaving 0x02, which every knockdown does
	-- once it is over.
	local _hurt_or_block = memory.readbyte(0xFF8805) == 0x02
	local _p2_y = globals.dummy.p2_y
	if not _hurt_or_block then
		pit_of_blame_armed = false
		pit_of_blame_fired = false
		pit_of_blame_air_seen = false
		pit_of_blame_frames = -1
	end
	if memory.readbyte(0xFF8009) == 4 and _hurt_or_block and not pit_of_blame_armed then
		pit_of_blame_armed = true
		pit_of_blame_roll = shouldGC()
		-- Y where the dummy stood (or crouched) right before any launch, so
		-- the rise check below is relative to THIS hit, not a fixed
		-- absolute value.
		pit_of_blame_ground_y = _p2_y
	end
	if pit_of_blame_armed and not pit_of_blame_fired then
		if not pit_of_blame_air_seen then
			if _p2_y - pit_of_blame_ground_y > PIT_OF_BLAME_AIR_MARGIN then
				-- This is the hit that actually knocks the dummy down. Start
				-- counting from here, not from whenever the span started.
				pit_of_blame_air_seen = true
				pit_of_blame_frames = 0
				pit_of_blame_prev_hits = memory.readbyte(0xFF8944)
				pit_of_blame_prev_tick = memory.readbyte(0xFF8081)
			end
		else
			local _hits = memory.readbyte(0xFF8944)
			if _hits ~= pit_of_blame_prev_hits then
				-- Another hit landed while airborne (air combo) - the delay
				-- restarts from THIS hit instead of running out mid-juggle.
				pit_of_blame_frames = 0
				pit_of_blame_prev_hits = _hits
			end
			-- Tick delta, not a flat +1 - see the turbo-3 FIX note above this
			-- function. 0xFF8081 is a byte counter, so this wraps correctly
			-- at 255 -> 0 as long as at least one callback happens per lap.
			local _tick = memory.readbyte(0xFF8081)
			pit_of_blame_frames = pit_of_blame_frames + ((_tick - pit_of_blame_prev_tick) % 256)
			pit_of_blame_prev_tick = _tick
			if pit_of_blame_frames >= PIT_OF_BLAME_INPUT_DELAY then
				pit_of_blame_fired = true
				-- TWO WAYS IN, ONE TRIGGER.
				--
				-- The Character Specific route is the original: pick the move
				-- there and it comes out here. The Pit of Blame row on the
				-- Dummy tab is the second, and it does not care what the guard
				-- action is - the move is used while the opponent is down, so
				-- tying it to a reversal setting meant giving that setting up.
				--
				-- Its own strength, too. The Character Specific route reads the
				-- Strength dropdown, which belongs to the reversal; the row is
				-- its own setting and says Normal or ES outright.
				local _pob = (training_settings and training_settings.pit_of_blame) or 1
				local _via_row = _pob ~= 1
				local _via_cs  = globals.dummy.guard_action == 'Character Specific Reversal'
				                 and move_is_pit_of_blame()
				if pit_of_blame_roll and (_via_row or _via_cs) and _d ~= nil then
					-- ES is two kicks, the way the game takes an ES special.
					local _btn = _via_row
					             and ((_pob == 3) and "MK+HK" or "LK")
					             or pit_of_blame_button()
					queue_input_sequence(
						_d,
						make_input_sequence(PIT_OF_BLAME_STICK, _btn, "delay_before", 0))
				end
			end
		end
	end

	-- Cleared only once everything is genuinely over.
	--
	-- The obvious test - knockdown clock at zero and not in stun - fires on the
	-- trigger frame itself whenever the dummy wakes straight into an actionable
	-- state, which is exactly when the pre-buffered motion is going out. The
	-- flag was dropped there and the old path queued a second motion on top,
	-- putting the doubled input back. Requiring the reversal window to be shut
	-- as well keeps the flag up across that frame, and it still clears once the
	-- dummy is idle so ordinary stun reversals are unaffected.
	if _kd == 0 and not _in_stun and memory.readbyte(0xFF8974) == 0 then
		prebuffer_used = false
	end
	-- AIR RECOVERY THAT TURNS INTO A KNOCKDOWN HANDS OVER (v52).
	--
	-- With some dummies the air reaction reaches free with $140 still 0x04;
	-- with others $140 flips to 0x0A about 28 ticks out and it finishes as an
	-- ordinary wake-up (section 8.6.31). In the second case the motion armed
	-- by the air path is timed for the wrong ending, and worse, it would keep
	-- pending_input_sequence non-nil so the knockdown arming below - which
	-- requires it to be nil - would never run at all.
	--
	-- Drop it while the knockdown clock is still early, flushing it so the
	-- recogniser is left clean (section 8.6.29), and let arm_edge re-arm on
	-- the knockdown's own clock.
	-- Read $140 inline: the _recovery local of this function is declared
	-- further down, so using the name here would resolve to a nil global and
	-- the test would silently never fire. luac cannot catch that.
	--
	-- IT MUST NOT EAT A MOTION THE KNOCKDOWN PATH ITSELF ARMED (v131).
	--
	-- KD_ARM_AT is 23 and this branch fires for the whole of any wake-up that
	-- ends below it. Zabel's ends on $1a7 = 22 and Sasquatch's on 23, so from
	-- the moment their pre-buffer was queued this flushed it on the very next
	-- frame: the queue was emptied into hs_flush_q, which the tick hook drains
	-- one entry per tick with no timing at all, and pending_input_sequence was
	-- set to nil. Straight out of the v130 logs, Zabel arm at f=17593 and the
	-- flush at f=17594, delivering entries 2 and 3 (lever 5 then 1+button) and
	-- never entry 1 - the button landing on free-2, -3 or -4 in 15 of 20
	-- wake-ups and not one of them producing the move.
	--
	-- Those are exactly the two characters the flush reaches, and exactly the
	-- two reported as having a broken input history. The handover is still
	-- right for a sequence armed by the AIR path - that one is timed for an
	-- ending that is no longer coming - so the test is who armed it, not when.
	--
	-- WIDENED TO EVERY KNOCKDOWN-ARMED SEQUENCE (v136).
	--
	-- v131 guarded only kd_tick, which is set when the $1a7 table knows the
	-- character. The characters that fall through to the $21 rule were left
	-- exposed, and on the full-roster batch that is exactly where the failures
	-- were: their $21 arm lands below $1a7 == 23, this branch fires, the queue
	-- is emptied into hs_flush_q and pending_input_sequence is set to nil.
	--
	--     Lei-Lei   ends on 29, $21 arm at ~20   0 of 33
	--     Jedah     ends on 24, arm at ~18       1 of  5
	--     Aulbath   ends on 28, arm at ~22       2 of  4  (ordinary)
	--     Bulleta   ends on 31/33, arm at ~26   21 of 21  - above 23, untouched
	--     Felicia   ends on 55, arm at ~49       9 of  9  - above 23, untouched
	--
	-- The split is entirely "does the arm land below KD_ARM_AT". kd_owned is set
	-- by the knockdown arm whatever route it took, so the test is now who armed
	-- it rather than which clock will drive it. The handover is still right for
	-- a sequence armed by the AIR path - that one is timed for an ending that is
	-- no longer coming.
	if memory.readbyte(0xFF8940) == 0x0A and _kd > 0 and _kd < KD_ARM_AT then
		local _handover = _d and _d.pending_input_sequence
		if _handover ~= nil and _handover.hold_last and not _handover.released
		   and not _handover.kd_owned then
			hs_request_flush(_handover)
			_d.pending_input_sequence = nil
			hs_armed = false
			hs_countdown = nil
			hs_arm_lg = nil
		end
	end

	-- ARM ON THE GAME'S OWN WAKE-UP TIMER, NOT ON A TALLY.
	--
	-- $1a7 was never the timer. 0x024E84 increments it once per tick and then
	-- dispatches on $382 and $07, and every wake-up handler branches on $21:
	--
	--     $07 == 2  getting up   tst.b ($21,A6) / bpl  -> when negative,
	--                            move.l #$2020400, ($4,A6)  <- the free-1
	--                            signature this tool keys on
	--     $07 == 6  rolling      tst.b ($21,A6) / bmi  -> while non-negative it
	--                            adds $40 to $10, which IS the roll's movement;
	--                            when negative it sets $07 = 2
	--
	-- $21 is the animation script's own cel timer, so its length comes from the
	-- character's animation data. That matters: wake-up length differs per
	-- character, and $1a7 == 23 / 43 were Morrigan's numbers. Reading $21
	-- instead needs no per-character table at all.
	--
	-- Measured over 116 knockdown spans of both kinds, $21 runs
	--
	--     0x00 ... free-6     0x40 at free-5 .. free-2     0xFF at free-1
	--
	-- and ($21 == 0x40 and $07 == 0x02) fires exactly ONCE per span, 116 of 116,
	-- always at free-5, 109 of 109. One rule, both variants, no constants.
	--
	-- $07 == 0x02 is what excludes the roll's own earlier 0x40: the rolling cel
	-- ends with one too, which is why the raw edge fires twice on a roll. The
	-- $140 test scopes it to a knockdown - hit stun also reaches 0x40.
	--
	-- This replaces KD_ARM_AT and KD_ARM_AT_ROLL as ARMING points. KD_ARM_AT is
	-- still used above, for the early handover flush.
	-- TWO WAYS A WAKE-UP CAN END, AND ONLY TWO.
	--
	-- Reading every character's handler out of the table at 0x0BD47A and
	-- looking at what precedes the free signature in each:
	--
	--   tst.b ($21,A6) / bpl   common handler, Bulleta, Gallon, Victor,
	--                          Morrigan, Lei-Lei, Lilith, Bishamon(1)
	--   jsr $273e2.l           Demitri, Felicia, Bishamon(2)   <- LANDING
	--
	-- The two characters that scored 0/13 and 0/6 are exactly the landing ones.
	-- Their wake-up does not end on an animation cel at all, it ends when Y
	-- reaches the floor, so $21 could never have predicted it.
	--
	-- The landing branch is preferred whenever the physics says the character
	-- is on a descending path, because it is exact and character-independent.
	-- Otherwise fall back to the animation rule, which is what the $21
	-- characters need. The landing arm point now comes from kd_land_arm(),
	-- which scales with the command's entry count.
	local _land = ticks_to_landing()

	-- THE LATCH HAS TO BE RELEASABLE, BECAUSE A KNOCKDOWN LANDS TWICE.
	--
	-- $140 stays 0x0A from the moment the character is knocked down, so the
	-- FALL onto the floor is inside the same span as the wake-up. Its landing
	-- also drives ticks_to_landing() down to 4, so v99 armed there - twenty-odd
	-- ticks early - and kd_armed then blocked the real one. Measured: not one
	-- kd_arm21 event fell inside a recording window, because every arm had
	-- already been spent on the fall.
	--
	-- Releasing the latch whenever the predicted landing is far away again
	-- makes the arm follow the LAST approach to the floor rather than the
	-- first. The wake-up is the last one by construction, since $140 leaves
	-- 0x0A at the actionable tick.
	-- ld == 1 IS NOT A LANDING, IT IS STANDING ON THE FLOOR.
	--
	-- A grounded character sits one tick above the floor with gravity still
	-- applied, so the simulation always answers "lands next tick". Morrigan
	-- reads ld = 1 on every tick of her wake-up (measured: 252 ticks, all 1),
	-- while Demitri's counts down 17, 16, ... 2, 1 as he actually falls. The
	-- distinction is not the value but whether it is really approaching.
	--
	-- Requiring ld >= 2 separates them. It costs nothing on the landing side:
	-- ld == 1 is free-2, far too late to deliver a motion into anyway.
	--
	-- This is what killed Morrigan in v100 and again in v101. v101 fixed the
	-- "already below the floor" case, but Morrigan is just ABOVE it.
	-- GROUNDED vs AIRBORNE decides which timer is the authority, and $20
	-- decides WHERE inside the animation to arm.
	--
	-- A grounded character sits one tick above the floor with gravity applied,
	-- so ticks_to_landing() answers nil or 1 forever. That is the only case the
	-- animation timer owns; anything actually falling belongs to the landing
	-- branch, including Bishamon's $07 == 6 wake-up.
	--
	-- $21 == 0x40 alone is not enough for the animation branch. It only says
	-- the final cel has STARTED, and cels differ in length per character, so
	-- that edge sits at free-6 for Morrigan but free-8 for Bishamon's $07 == 2
	-- wake-up. Measured, arming at free-8 is 0 of 9: the whole command finishes
	-- while the character is still in recovery and the recogniser consumes it
	-- before it can come out - the trace shows $318 reaching (4,8) and then
	-- dropping to (0,0) two ticks before the actionable tick.
	--
	-- $20 is the frame counter INSIDE the cel, so gating on it lines the
	-- characters up:
	--
	--                free-6      free-5      free-4      free-3
	--     Morrigan   (64,4)      (64,3)      (64,2)      (64,1)
	--     Bishamon   (64,3)      (64,2)      (64,1)      (255,0)
	--
	-- $20 <= 4 therefore arms Morrigan at free-6 and Bishamon at free-6, and
	-- the outcome data by arm position is free-6: 41/1, free-5: 47/8,
	-- free-8: 0/9. Replayed over the logs this moves 9 spans out of free-8 and
	-- leaves everything else where it already measured well.
	local _grounded = (_land == nil or _land == 1)

	-- THE $1a7 CLOCK OWNS THE WAKE-UP OUTRIGHT WHEN IT KNOWS THE CHARACTER.
	--
	-- Both branches used to be able to arm the same wake-up, and on the v131
	-- batch Victor did exactly that: the landing branch armed at $1a7 = 21 and
	-- put a whole 360 in with its button on free-7, then released its latch when
	-- he touched down and the $1a7 branch armed again and put a SECOND 360 in on
	-- free-4..-1. Thirteen of thirteen still came out - the first motion
	-- completes and the recogniser resets - but the input history carries two
	-- copies of the command, which is the thing that is supposed to be fixed.
	--
	-- $1a7 counts whether the character is on the ground or not, so when the
	-- table has a value there is nothing the landing prediction can add.
	local _known = kd_end_1a7()
	local _land_ok = (_known == nil) and (not _grounded)
	                 and _land <= kd_land_arm()

	-- Only a latch taken by the landing branch is releasable. The animation
	-- branch must stay latched, because $21 == 0x40 lasts several ticks and
	-- would otherwise re-arm on every one of them.
	if kd_armed_by_land and not _land_ok
	   and memory.readbyte(0xFF8940) == 0x0A then
		kd_armed = false
		kd_armed_by_land = false
	end

	-- ARMING IS NO LONGER THE TIMING DECISION, IT ONLY HAS TO BE EARLY ENOUGH.
	--
	-- It used to be both: the motion started at the arm and walked forward from
	-- there, so the arm point WAS the delivery point. That cannot work from a
	-- once-per-frame function - measured on the v130 batch the arm landed on
	-- $1a7 = 18, 19 or 20 for Zabel against a window that opens at 19, because a
	-- frame covers one tick or two and which one is not controllable. Only the
	-- spans that happened to land on 20 came out (4 of 4; the other 16, 0).
	--
	-- Delivery is on the $1a7 clock in the tick hook now, so all this has to do
	-- is get the sequence queued BEFORE the first entry is due, which is
	-- $1a7 == end - #sequence + 1. KD_ARM_LEAD ticks of slack in front of that
	-- is several frames' worth at 1.6 ticks per frame; nothing is injected
	-- during them.
	local KD_ARM_LEAD = 5
	local _kd_tick_ok = false
	local _kd_edge = (not kd_armed)
		and memory.readbyte(0xFF8940) == 0x0A
		and (_land_ok
		     or (_known ~= nil and (function()
		         -- Known character: arm a fixed distance from the end of the
		         -- $1a7 clock, which is the same distance for everyone.
		         --
		         -- NO "grounded" TEST HERE (v132). That gate belongs to the $21
		         -- fallback, whose whole problem was that the animation timer
		         -- means different things in the air. $1a7 does not care: it is
		         -- one per tick either way. Keeping the gate would have blocked
		         -- Bishamon's rolling wake-up, which is still airborne when its
		         -- injection window opens - measured, ld reads 2 to 6 across
		         -- free-3..-7 on 11 of his 16 spans.
		         local _n = 3
		         if globals and globals.dummy then
		             _n = seq_len(globals.dummy.counter_attack_stick)
		         end
		         _kd_tick_ok = (_kd >= (_known - _n + 1 - KD_ARM_LEAD)
		                        and _kd <= _known)
		         return _kd_tick_ok
		     end)())
		     or (_known == nil and _grounded
		         and memory.readbyte(0xFF8821) == 0x40
		         and memory.readbyte(0xFF8807) == 0x02
		         and memory.readbyte(0xFF8820) <= kd_cel_arm()))
	if _kd_edge then
		kd_armed = true
		kd_armed_by_land = _land_ok
		-- $a is what separates Q-Bee's three wake-ups, and $27 was what v161
		-- wrongly keyed on; both are logged so the choice stays checkable.
		--
		-- Read from memory rather than from the captured locals on purpose:
		-- Lua 5.1 allows a function 60 upvalues and this one is at the limit,
		-- so naming another file-level local here stops the file compiling.
		debugKnockdownModule.mark_write("kd_arm21", _kd,
			memory.readbyte(0xFF880A) * 256 + memory.readbyte(0xFF8807))
	end
	-- Which clock the tick hook should use. The $21 fallback keeps the delivery
	-- it was measured with; the other two are driven per tick.
	arm_tick_driven = _kd_edge and _kd_tick_ok and not _land_ok
	arm_land_driven = _kd_edge and _land_ok

	arm_edge = _kd_edge

	-- BLOCK STUN GETS ONE AS WELL (v143).
	--
	-- Block has its own clock and it is a constant: 0x023960 writes 14 into
	-- $158 on every blocked hit and 0x022492 counts it down one per tick. So
	-- unlike plain hit stun there is no guessing about how far away the trigger
	-- is - the distance is $158 itself.
	--
	-- Armed while there is still room for the motion rather than on the edge:
	-- a blocked string refreshes $158 on every hit, so arming at a threshold
	-- re-arms naturally on the last hit of the string, which is the one that
	-- matters. The button is placed by the free-1 signature, exactly as it is
	-- for a knockdown, so this only has to get the motion in.
	--
	-- BLOCK_ARM_AT is deliberately below the 14 the counter starts at: putting
	-- the motion in at the very start of a long blockstring would leave it to
	-- expire against the recogniser's 14-19 tick step timeout.
	-- ARM ON $158 REACHING ZERO, NOT ON THE WAY DOWN (v145).
	--
	-- v143 armed at $158 <= 8, on the assumption that $158 counts down to the
	-- moment the character is free. It does not. Measured over 118 block spans,
	-- $158 is ALREADY ZERO at free-1 in 114 of them: it is the guard-cancel
	-- window (character code at 0x02E17C / 0x02FFE2 tests it before writing a
	-- move id), not the length of block stun.
	--
	-- The real distance, from the tick $158 stops being non-zero to free-1:
	--
	--     10 ticks   73 spans      total recovery 24 from the blocked hit
	--     15 ticks   28                           29
	--     19 ticks    8                           33
	--
	-- Three lengths, which is what blockstun by attack strength looks like.
	-- Arming at $158 <= 8 therefore put the motion in 18, 23 or 27 ticks before
	-- free, and the recogniser drops a step after 14 to 19 (0x02A55A) - the
	-- motion had expired every time. That is why a special comes out on hit and
	-- not on block.
	--
	-- Arming on the zero EDGE gives 10 ticks of lead in the common case, which
	-- is inside the window with room. The 15 and 19 cases are still marginal;
	-- fixing those needs the block length itself, which is what the animation
	-- dump added in this version is for.
	local _blk140 = (memory.readbyte(0xFF8940) == 0x02
	                 or memory.readbyte(0xFF8940) == 0x12)
	if not _blk140 then BLK.episode = false end
	-- EVERY BLOCKED HIT GETS ITS OWN MOTION.
	--
	-- v146 latched for the whole episode, which is wrong for a blockstring: if
	-- $158 happens to reach zero in a gap between hits the motion goes in, the
	-- next hit pushes the free tick another 24 to 33 ticks away, and nothing
	-- re-arms - the motion expires and the string ends with nothing buffered.
	-- Measured by the user as "multi-hit block is completely broken".
	--
	-- Re-arming on the rising edge of $158 cannot double the motion the way
	-- arming twice inside one stun span did (the Shadow Blade case): the next
	-- arm is the zero edge plus the wait, which is at least 22 ticks after this
	-- one, and the recogniser drops a step after 14 to 19. The previous motion
	-- is always gone by then.
	-- A RISE, NOT THE VALUE 14.
	--
	-- $158 is set to 14 on contact and counts down one per tick, while this
	-- runs once per displayed frame - about 1.6 ticks - so 14 itself is missed
	-- roughly four times in ten. The episode then never cleared and the second
	-- hit of a multi-hit guard was never re-armed. The counter only ever goes
	-- up when it is re-set, so any rise says the same thing 14 did, and says it
	-- whichever value the sample happened to land on.
	local _s158 = memory.readbyte(0xFF8958)
	if _s158 > BLK.prev158 then
		BLK.episode = false
		BLK.zero_lg = nil
		BLK.lead = nil
		-- A new blocked hit is a new opportunity, and the frequency gets one
		-- draw per opportunity. This is the only place that says so - the
		-- episode is also cleared by $140 above, which re-arms within the SAME
		-- hit and must not buy another draw.
		gc_opportunity = gc_opportunity + 1
	end
	-- Counted from the zero edge, so the wait above can be applied.
	if _s158 == 0 and BLK.prev158 > 0 then
		BLK.zero_lg = memory.readbyte(0xFF8081)
	end
	-- >=, NOT ==.
	--
	-- This function runs once per DISPLAYED FRAME, which is about 1.6 ticks, so
	-- roughly four ticks in ten are never sampled here (section 0). An exact
	-- match would be missed that often - the same trap that cost v130. Arming
	-- is latched by BLK.episode, so the first sample at or past the wait is the
	-- only one that fires.
	--
	-- $158 AND THE GUARD SCRIPT RUN ON DIFFERENT CLOCKS.
	--
	-- $158 is set to 14 on contact and decremented every tick by 0x022492.
	-- The guard script (0x027DE4) is a separate thing: $164 only advances on
	-- ticks the character is actually moving, so it stands still for the whole
	-- hit freeze. On an attack with a long freeze - Demitri's zero demon holds
	-- $164 at 0 for twelve ticks - $158 has burned most of its count before
	-- the script has taken a single step, and the zero edge lands wherever the
	-- freeze happened to leave it.
	--
	-- Replayed over the 710 complete block spans in reversal_logs_archive, the
	-- zero-edge arm put the lead at -1, 0 or nowhere at all on 111 of the 229
	-- heavy spans: the arm was at or past free, so nothing came out. That is
	-- the "zero demon gives no fastest dash" report, and it was never about
	-- the stun being short - a blocked zero demon is 20 ticks, same as any
	-- heavy.
	--
	-- The script knows the answer directly. Its length is fixed the moment the
	-- attack connects and $164 is the cursor into it, so the ticks left are
	-- length - $164 on any tick, freeze or not. Arm when that reaches the lead
	-- we want. Same replay: 221 of 229 heavy spans land on 10 or 11.
	--
	-- Clamped to length - 1 because a light attack's script is 11 long, so a
	-- flat 11 would be satisfied at cursor 0 - during the freeze, before the
	-- script has started - and the motion would expire before free (the step
	-- timeout is 14 to 19 at 0x02A55A). One less puts it at cursor 1, which is
	-- the first tick the script actually moves, and reproduces the 10 that
	-- BLK_LEAD already claimed for light.
	--
	-- WHY 9 AND NOT 11 (v237).
	--
	-- The arm is not just a schedule anchor: make_input_sequence runs on it,
	-- and the last entry of that sequence has to land on free+0 or the move
	-- does not come out at all (section 8, the free+0 rule). So moving the arm
	-- moves the whole motion, and v235's honest 11 put it three ticks early -
	-- which is why fixing the tap placement in v236 changed nothing for
	-- ordinary blocks: the taps were landing on free-3 exactly as intended and
	-- the sequence was still finishing before free.
	--
	-- The old zero-edge arm was measured at a lead of 8 or 9 on every ordinary
	-- block (349 light spans peak at 8, 132 medium at 9). Nine reproduces
	-- that: replayed over the archive it arms at 8 or 9 on the same spans. So
	-- ordinary blocks keep the timing they were tuned with, and only the case
	-- the old rule got wrong changes - a long freeze used to arm at free+1 or
	-- later, and now arms at free-8 like everything else.
	local BLK_ARM_LEAD = 9
	local _blk_ready = false
	local _glen = BLK.script_len(memory.readbyte(0xFF8859))
	-- PER-STRENGTH ARM LEAD (measured, 57/57).
	--
	-- The flat 9 tuned on ordinary blocks is too tight for the impact freeze
	-- that precedes Light and Medium guards: their $59 arm reads 0 or 1 while
	-- the freeze is still running, and the arm then fires after the freeze
	-- ends, past the point the dash schedule can recover from. Light and
	-- Medium arm at 12 instead; Heavy keeps 9.
	local _arm_lead = BLK_ARM_LEAD
	local _s59arm = memory.readbyte(0xFF8859)
	if _s59arm == 0 or _s59arm == 1 then _arm_lead = 12 end
	local _gleft = nil
	-- A GRANTED PUSH BLOCK CHANGES THE CLOCK.
	--
	-- 0x024A6C moves the guard state to $07 = 6 and sets $26 = 10, and from
	-- there 0x024AFC counts $26 down and falls into the same free signature at
	-- 0x024B02. The guard script is abandoned, so length - $164 stops meaning
	-- anything and the arm never fires - which is "the push block comes out
	-- but the fastest action does not".
	--
	-- $26 IS the remaining ticks on that path, so it can be used directly.
	if _blk140 and memory.readbyte(0xFF8807) == 0x06 then
		_gleft = memory.readbyte(0xFF8826)
		_blk_ready = _gleft <= _arm_lead
	elseif _glen ~= nil and _blk140 then
		_gleft = _glen - memory.readword(0xFF8964)
		_blk_ready = _gleft <= (_glen - 1 < _arm_lead
		                        and _glen - 1 or _arm_lead)
	elseif BLK.zero_lg ~= nil and _blk140 then
		-- Fallback for a reaction type whose script does not read back: the
		-- original zero-edge-plus-wait, unchanged.
		_blk_ready = ((memory.readbyte(0xFF8081) - BLK.zero_lg) % 256)
		              >= blk_wait_ticks()
	end
	-- NOT INSIDE THE IMPACT FREEZE.
	--
	-- The drop further down this same function clears everything armed while
	-- $06 reads 0x00, so an arm placed during the freeze is queued and thrown
	-- away in the same displayed frame - and BLK.episode is left standing, so
	-- nothing re-arms when the freeze ends either. Waiting for the freeze to
	-- pass is what makes the arm survive.
	if (not BLK.episode)
		and _in_stun
		and memory.readbyte(0xFF8805) == 0x02
		and memory.readbyte(0xFF8806) ~= 0x00
		and _blk140
		and _blk_ready
		and _kd == 0
	then
		BLK.episode = true
		hs_armed = true
		hs_ready = true
		hs_countdown = nil
		BLK.edge = true
		BLK.lg = memory.readbyte(0xFF8081)
		-- INPUT-BASED NEUTRAL INJECTION (measured, 57/57 with the per-strength
		-- lead). The dummy holds back to guard, so the back dash's first tap
		-- is no press edge unless the direction is released first. Three ticks
		-- of forced neutral after the arm give release, tap, release, tap on
		-- consecutive ticks - replacing the old memory-write neutral hack.
		BLK.neutral = 3
		-- The MEASURED distance to free, not a table lookup. Frame sampling
		-- misses about four ticks in ten, so the arm lands on 10 as often as
		-- 11; passing the real number lets the dash schedule below place its
		-- taps correctly either way instead of assuming one of them.
		BLK.lead = _gleft
		debugKnockdownModule.mark_write("blk_arm",
			memory.readbyte(0xFF8958), memory.readbyte(0xFF8940))
	end

	BLK.prev158 = memory.readbyte(0xFF8958)

	-- HIT-STUN GETS A PRE-BUFFER TOO (v41).
	--
	-- The note above this function says plain hit stun cannot be pre-buffered
	-- because "there is no clock ... no way to know whether the trigger is two
	-- ticks away or forty". That was true with the information available then.
	-- It is not any more: $06 runs 0x00 -> 0x02 -> 0x04 through a hit-stun,
	-- and measured at tick resolution the 0x00 -> 0x02 edge sits a fixed
	-- distance from the actionable tick:
	--
	--     lead = 19 ticks : 11 of 14
	--     lead = 14 ticks :  3 of 14
	--
	-- ($06 = 0x00 while $05 = 0x02 is the impact freeze; 0x02 is hit stun
	-- proper; 0x04 is the single tick before the character becomes free, which
	-- is the signature the tick hook keys on.)
	--
	-- 14 ticks is enough. The motion needs two entries delivered and then the
	-- last one held, and the recogniser's step timeout is 14-19 ticks
	-- (0x02A55A, randomised per step - section 8.7.3), so a hold of roughly
	-- ten ticks is inside it with room to spare.
	--
	-- Armed on first SEEING $06 == 0x02 rather than on the edge itself: this
	-- runs once per displayed frame, about three ticks, so an edge test would
	-- miss the transition two times in three. Seeing the state costs at most
	-- three ticks of lead and cannot be missed. hs_armed holds it to one
	-- attempt per stun span, exactly as kd_armed does per knockdown.
	if not _in_stun then
		-- A request that never found its signature dies with the stun span, so
		-- it cannot go off on some later recovery the user did not ask for.
		csp_pending = false
		BLK.edge = false
		BLK.zero_lg = nil
		hs_armed = false; hs_countdown = nil; hs_arm_lg = nil; hs_0c_armed = false; hs_0c_lg = nil
		hs_ready_wait = 0
		hs_throw_armed = false; hs_ready = false
		hs_last_deliver_f = nil
		hs_flush_q = {}
	end

	-- EVERY HIT IN A COMBO RE-ARMS (v44).
	--
	-- hs_armed used to clear only on LEAVING stun, so a multi-hit attack armed
	-- once - on its first hit - and never again. The motion was queued and
	-- timed for that hit, then held across the rest of the combo until
	-- HOLD_LIMIT dropped it. Measured on the v43 batch:
	--
	--     one impact freeze in the span   35 reversal /  4 nothing
	--     two impact freezes              0 reversal / 13 nothing
	--     three impact freezes            0 reversal /  1 nothing
	--
	-- and the trace shows it exactly: the held direction runs the whole combo
	-- and goes to 0x0000 on the tick the FINAL hit's stun begins, so there is
	-- nothing left to inject 14 ticks later at the signature.
	--
	-- $06 returning to 0x00 is the impact freeze of a new hit (section
	-- 8.6.18), so it is the re-arm edge. Dropping the stale sequence here is
	-- safe against a rewind: the freeze runs about twelve ticks and the
	-- transition it matters for is a whole stun away.
	if _in_stun and memory.readbyte(0xFF8806) == 0x00 then
		hs_armed = false
		hs_countdown = nil
		hs_0c_armed = false
		hs_0c_lg = nil
		hs_throw_armed = false
		hs_ready = false
		-- The episode goes with it. Without this a rise in $158 that the frame
		-- sampling missed leaves the episode standing through the freeze, and
		-- the arm that should have happened when it ended never does. In hit
		-- stun this line is reached too, but _blk140 is false there and the
		-- episode was never set, so it changes nothing.
		BLK.episode = false
		local _stale = _d and _d.pending_input_sequence
		if _stale ~= nil and _stale.hold_last and not _stale.released then
			hs_request_flush(_stale)
			_d.pending_input_sequence = nil
		end
	end

	if (not hs_armed)
		and _in_stun
		and memory.readbyte(0xFF8805) == 0x02
		and memory.readbyte(0xFF8806) == 0x02
		-- Read $140 here rather than using _recovery: that local is declared
		-- further down in this same function, so up here the name would
		-- resolve to a nil global and this whole test would silently never
		-- fire. luac cannot catch that - it is valid Lua.
		and (memory.readbyte(0xFF8940) == 0x00
		     or memory.readbyte(0xFF8940) == 0x04)
		-- Do not pre-buffer hit stun for a hit that ends in a knockdown. $140
		-- still reads 0x00 here - it does not become 0x0A until the stun timer
		-- runs out (0x027D52) - so without this the motion goes in early, holds
		-- the command block, and the wake-up attempt lands on a busy
		-- recogniser.
		and not hit_ends_in_knockdown()
		and _kd == 0
	then
		hs_armed = true
		-- $59, NOT $56.
		--
		-- $56 does not separate the classes. Measured over 82 short hit-stun
		-- spans:
		--
		--     $56 = 0  ->  real lead 14 in 19 spans AND 19 in another 19
		--     $56 = 1  ->  real lead 19 in 44
		--     $59 = 0  ->  real lead 14 in 19        $59 = 1 -> 19 in 63
		--
		-- $59 is exact on all 82; $56 is a coin flip for half of them. Section
		-- 8.6.20 treated the two as interchangeable because they agreed on the
		-- batch available then - they do not in general.
		--
		-- The ambiguity is the whole of the remaining hit-stun failure: a lead
		-- 19 span armed as though it were 14 waits 5 ticks too few, the second
		-- direction is held that much longer, and it times out.
		local _sl = memory.readbyte(0xFF8859)
		local _lead = HS_LEAD_BY_59[_sl]
		if memory.readbyte(0xFF8940) == 0x04 then
			-- AIR RECOVERY. $56 does not classify it, and it does not need to:
			-- measured over 30 spans the lead from here to the actionable tick
			-- is 35 to 40 ticks, tight enough for one constant. 38 puts the
			-- hold between 3 and 8 ticks across that whole range, well inside
			-- the shortest step timeout.
			-- No delivery bias here either. air_lead_now() already IS the
			-- measured lead (109/109 within a tick), so adding to it moves the
			-- forward to free-5, out of the band. See HS_LEAD_BY_59.
			_lead = air_lead_now()
		end
		if _lead ~= nil then
			hs_countdown = hs_clamp_delivery(hs_countdown_for(_lead)); hs_arm_lg = memory.readbyte(0xFF8081)
		else
			-- Unseen stun class. Keep the v42 behaviour rather than
			-- extrapolating, and record the value so the table can be
			-- extended from real data instead of guessed at.
			hs_countdown = hs_clamp_delivery(hs_countdown_for(14)); hs_arm_lg = memory.readbyte(0xFF8081)
			debugKnockdownModule.mark_write("hs_unknown56", _sl, 0)
		end
	end

	-- THE MOTION IS QUEUED LATE, NOT AT RECOGNITION (v42).
	--
	-- v41 queued it the moment hit stun was recognised, and measured, that is
	-- too early on both counts:
	--
	--   * The lead from there to the actionable tick is 14 or 19 ticks, and
	--     the motion parks on its second-to-last entry for all of it. The
	--     recogniser's step timeout is 14-19 ticks, randomised per step
	--     (0x02A55A), so a 12-17 tick hold sits right on top of it - the
	--     motion expires about as often as it survives.
	--   * HOLD_LIMIT below dropped the sequence outright at 10 displayed
	--     frames. The v41 trace shows it exactly: the held direction goes to
	--     0x0000 three ticks before the signature tick, so there was nothing
	--     left to inject.
	--
	-- Waiting HS_DELIVER_AFTER frames first puts the hold at 5-10 ticks
	-- instead, comfortably inside the shortest possible step timeout, and
	-- inside HOLD_LIMIT as well.
	-- Throw escape. Its own block rather than another branch inside the
	-- $56 arming above, so the variants that already measure clean cannot be
	-- disturbed by it.
	-- ARM OFF $21, NOT OFF A CONSTANT.
	--
	-- HS_THROW_LEAD = 33 measured 44/44 and 22/22, but only on one character.
	-- 33 is the length of Morrigan's throw-escape animation, and there is no
	-- reason another character's would match - the same mistake $1a7 == 27/47
	-- made for the wake-up (section 8.6.83).
	--
	-- $21 is the animation script's own cel timer, so it needs no per-character
	-- table. Measured over 31 throw escapes it is 0x40 at free-8 and 0xFF from
	-- free-7 onward, 31 of 31 with no exceptions - the same shape the wake-up
	-- has, three ticks earlier.
	--
	-- Delivering from free-8 puts the forward around free-7, and the wake-up
	-- arms from free-5 and scores 64/64, so there is more room here, not less.
	--
	-- Air recovery deliberately does NOT move to this rule: its $21 transition
	-- floats with the fall (0x40 at free-8 on only 44 of 70), which is exactly
	-- why that one is computed from the height instead.
	-- The throw escape used to arm here. It is done on the tick clock now, in
	-- the 0x02211A hook - $21 holds 0x40 for one tick and this function does
	-- not see every tick. See the note there.

	-- LONG HIT-STUN RE-ARMS REPEATEDLY, BECAUSE ITS LENGTH IS NOT KNOWABLE.
	--
	-- Every other variant has something that gives its lead: $59 for ordinary
	-- hit stun, height for air recovery, $1a7 for a knockdown, a constant for
	-- a throw escape. This one has nothing. Measured over 30 spans the 0x0C
	-- phase lasts anywhere from 3 to 37 ticks, and it is NOT a property of the
	-- attack - the same $a, the same $59 and the same attacker move produce
	-- lengths 3, 4, 6, 10, 17, 19, 22, 26, 30 and 37. An exhaustive sweep of
	-- the object found no byte that predicts it either.
	--
	-- The one exact marker is useless: the phase always ENDS 3 ticks before
	-- the actionable tick (30 of 30), but "the last tick of the phase" cannot
	-- be recognised while standing on it.
	--
	-- STALE COMMENT REMOVED (v94): this described the periodic re-arm, which
	-- no longer exists. The arming is now a single $15c threshold.
	-- recent motion is at most that old, which keeps the second direction
	-- inside the recogniser's 14-19 tick step timeout. The stale one is
	-- flushed first, which is the mechanism that already fixed multi-hit
	-- (section 8.6.29).
	-- The periodic re-arm used to live here. It is gone: see HS_0C_ARM_AT.


	-- The 0x0C sub-phase: arm ONCE, when the game's own stun timer says the
	-- recovery is close. Discards whatever the $59 path set up for this stun.
	if _in_stun
		and (not hs_0c_armed)
		and memory.readbyte(0xFF8805) == 0x02
		and memory.readbyte(0xFF8807) == 0x0C
		and memory.readbyte(0xFF8940) == 0x00
		and memory.readword(0xFF895C) <= hs_0c_arm_at()
		and not hit_ends_in_knockdown()
		and _kd == 0
	then
		hs_0c_armed = true
		hs_0c_lg = memory.readbyte(0xFF8081)
		hs_armed = true
		local _stale = _d and _d.pending_input_sequence
		if _stale ~= nil and _stale.hold_last and not _stale.released then
			-- Flushed only when this is a REPEAT of the 0x0C arm (the motion
			-- being replaced has been sitting long enough to have registered);
			-- on the first arm it is the same-stun replacement described
			-- below and must not be flushed.
			if hs_0c_lg ~= nil
			   and ((memory.readbyte(0xFF8081) - hs_0c_lg) % 256) >= HS_0C_REARM then
				hs_request_flush(_stale)
			end
			-- NO FLUSH ON THE FIRST ARM, deliberately.
			--
			-- The sequence being discarded was armed for THIS stun, off $56,
			-- and is simply mistimed - the reaction turned out to be a long
			-- one. It is not a leftover from an earlier hit, which is the
			-- situation the flush exists for.
			--
			-- Measured, flushing here is actively harmful. Without it this
			-- path ran 19 of 19; with it, 9 of 15. The re-arm still has the
			-- HS_STALE_CLEAR spacing behind it, which is what this path was
			-- running with when it measured clean.
			_d.pending_input_sequence = nil
		end
		-- Deliver at once. The wait this used to compute existed to bridge the
		-- distance from the START of the 0x0C phase, whose length is exactly
		-- what cannot be known. Arming off $15c removes the distance, so there
		-- is nothing left to wait for.
		hs_countdown = 1; hs_arm_lg = memory.readbyte(0xFF8081)
		debugKnockdownModule.mark_write("hs_arm0c15c", memory.readword(0xFF895C), 0)
		debugKnockdownModule.mark_write("hs_arm0c", _lead, 0)
	end

	-- Measure how many ticks a displayed frame is worth, so the countdowns
	-- below can be expressed in ticks and still allow for the motion being
	-- DELIVERED one entry per displayed frame (controller.lua). Smoothed,
	-- because the frameskip pattern is not uniform.
	--
	-- NOTE (v65): a version of this derived the ratio from 0xFF8081 divided by
	-- the real frame delta, which is sounder in principle - this tally does
	-- not reset on a frame where this function does not run, so it can drift
	-- high. It is back to the tally form because the derived version measured
	-- WORSE across the board, and this is the form every good batch was taken
	-- with. If the drift is ever confirmed to be causing failures, fix it
	-- then, with a measurement rather than on the argument alone.
	if hs_tick_count > 0 then
		hs_ticks_per_frame = (hs_ticks_per_frame * 3 + hs_tick_count) / 4
		if hs_ticks_per_frame < 1 then hs_ticks_per_frame = 1 end
		-- Pacing stats, recorded so the "is emulator lag causing this" question
		-- can be answered from the logs rather than guessed at.
		lag_frames = lag_frames + 1
		if hs_tick_count > lag_ticks_max then lag_ticks_max = hs_tick_count end
		if hs_tick_count >= 3 then lag_slow = lag_slow + 1 end
		hs_tick_count = 0
	end
	if os ~= nil and os.clock ~= nil then
		local _now = os.clock()
		if lag_prev_clock ~= nil then
			local _ms = (_now - lag_prev_clock) * 1000
			if _ms > lag_ms_max and _ms < 1000 then lag_ms_max = _ms end
		end
		lag_prev_clock = _now
	end

	hs_arm_edge = false
	-- BLK.edge is NOT reset here: the block test above this point has
	-- already run for this frame and its edge has to survive to the queue site.
	-- It is cleared at the queue site instead, and whenever stun ends.
	if hs_ready then
		hs_ready = false
		hs_arm_edge = true
		hs_last_deliver_f = globals.current_frame
		debugKnockdownModule.mark_write("hs_arm", memory.readbyte(0xFF8859),
			math.floor(hs_ticks_per_frame * 10))
	end

	prev_in_stun = _in_stun

	if _d == nil then return end
	local _seq = _d.pending_input_sequence
	if _seq == nil or not _seq.hold_last or _seq.released then return end

	-- Safety net for the same failure the arming rule above exists to prevent:
	-- if the window has not opened while the motion was still live, the motion
	-- is spent. Holding a stale direction cannot produce the move and only
	-- risks feeding the dummy an input it never asked for, so let it go.
	-- HOLD_LIMIT is in displayed frames, comfortably past the ten ticks an
	-- input survives at turbo 3.
	-- RAISED from 10 (v42). Ten displayed frames was measured to cut the
	-- hit-stun pre-buffer off three ticks before the signature tick - with
	-- run-ahead off the game advances about one tick per displayed frame, so
	-- a 14-19 tick lead is 14-19 frames and a 10-frame limit cannot reach it.
	--
	-- Safe to raise now: this is only a backstop. Every in-stun recovery is
	-- released by the ownership branch below as soon as $05 returns to 0, so
	-- a sequence can no longer be left holding a direction indefinitely,
	-- which is the situation this limit was added for.
	local HOLD_LIMIT = 20
	_seq.held = (_seq.held or 0) + 1
	if _seq.held > HOLD_LIMIT then
		_d.pending_input_sequence = nil
		return
	end

	-- Release on the window opening ALONE. Do not also wait for 0xFF8805 to
	-- clear.
	--
	-- That extra condition was tried and made things worse. 0xFF8805 still
	-- reads 0x02 on the frame the window opens in ten of thirteen measured
	-- reversals, so waiting for it held the button back one to four frames and
	-- the move landed two to five frames late - it came out every time but was
	-- no longer a reversal. Pressing while that byte is still 0x02 is fine: the
	-- game buffers the input and the move starts as soon as it can.
	--
	-- The single case that motivated the extra condition turned out to be a
	-- dummy that stayed in stun for twenty frames. No reversal was possible
	-- there by any means, so it was never evidence for delaying the button.
	-- ...and release one frame before that when the wake-up clock says so.
	--
	-- The window opening sits in one of two places relative to the frame the
	-- dummy can actually move, and which one decides whether the result is a
	-- reversal:
	--
	--   window one frame early  - dummy still shows 0xFF8805 = 0x02 there. The
	--                             button lands, the move starts on the first
	--                             free frame. All eight confirmed reversals
	--                             are this case.
	--   window on the free frame - dummy already reads 0xFF8805 = 0x00. The
	--                             button is a frame late before it is even
	--                             sent, and the move starts one frame after
	--                             the dummy could have acted. Never a reversal.
	--
	-- 0xFF89A7 reaches 0x1A on the frame before the window in both, so
	-- releasing on it puts the button in early enough for the second case
	-- while leaving the first unchanged - the move still cannot start before
	-- the dummy is free, the input simply waits in the buffer.
	--
	-- WATCH THIS: at 0x1A the dummy is technically still down, and a moving
	-- wake-up is a direction plus a button. The reversals that already work
	-- press the same direction and button at 0x1B while equally still down and
	-- do not roll, so the roll input has almost certainly stopped being
	-- accepted by then - but "almost certainly" is not "measured". If the dummy
	-- starts rolling instead of reversing, this is the line to move back.
	--
	-- REVERTED: releasing early on 0xFF89A7 >= 0x1A.
	--
	-- That was meant to rescue the wake-ups where the window frame is already
	-- the actionable frame, by getting the button in one frame sooner. It does
	-- get the button in sooner, and on the other kind of wake-up that frame is
	-- still knockdown, so the press misses - and in this game a press that
	-- misses WIPES the buffered command. The completed motion was thrown away
	-- and the frame the dummy could have reversed on had nothing behind it.
	-- Three of ten produced no move at all. Pressing late costs a frame;
	-- pressing early costs the whole reversal.
	-- PREDICT the actionable frame instead of REACTING to the window flag.
	--
	-- Why the old trigger (0xFF8974 > 0) tops out around one third:
	--   The button has to be delivered on the frame BEFORE the dummy becomes
	--   actionable. Measured over 18 logged attempts, with the actionable
	--   frame defined as status_1 (0xFF8805) going $02 -> $00:
	--       button on free-1  -> reversal, 6 of 6
	--       button on free    -> never, 0 of 12
	--   0xFF8974 is set during the CPU of some frame N. Lua's registerbefore
	--   poll cannot see it until the start of frame N+1, so the earliest
	--   possible release is N+1. That is early enough only when the window
	--   opens two frames ahead of the actionable frame (about a third of
	--   wake-ups); on the rest it opens one frame ahead and N+1 IS the
	--   actionable frame - already too late. No amount of tuning fixes a
	--   reaction that is structurally one frame behind.
	--
	-- The predictor: 0xFF8820 is the animation frame counter ($20), which the
	-- animation engine decrements every frame (0x027F70) and reloads from the
	-- current 0x18-byte script element. Across all 18 logged wake-ups it runs
	-- 1..4 in a cycle and reaches 0 ONLY in the last one or two frames before
	-- the dummy becomes actionable - never mid-animation. Combined with
	-- 0xFF8940 ($140, the recovery-variant selector) reading 0x0A, which is
	-- what the knockdown entry at 0x027D5A writes, that pins the moment down
	-- without waiting for the window flag at all.
	--
	-- See analysis/VSAV_ENGINE.md ch.4.5 for the recovery state machines and
	-- ch.8.1 for how "reversal" is defined against status_1/status_2.
	--
	-- MEASURED (23 attempts, v10-predict-animctr.1): firing on $20 == 0 alone
	-- lands 1, 2 or 3 frames before the actionable frame, and how early it
	-- lands decides everything:
	--       free-1  ->  5 of 5   reversal
	--       free-2  ->  7 of 11  reversal
	--       free-3  ->  0 of 7   (nothing comes out at all)
	-- That is the buffer-wipe failure the REVERTED note above describes,
	-- now measured instead of assumed: too early does not just miss, it
	-- destroys the buffered motion.
	--
	-- What separates them at decision time is $7, the wake-up sub-state:
	--       $7 == 0  ->  8 of 8   reversal   (wake-up already transitioned;
	--                                         status_2 is $04, so this frame
	--                                         IS free-1)
	--       $7 == 2  ->  4 of 14  reversal   (still in the get-up state; the
	--                                         transition has not happened yet,
	--                                         so free is still 1-3 frames off)
	-- $21 was logged too and is useless here - it reads 0xFF in every single
	-- case, because $20 == 0 already implies the animation ended.
	--
	-- So: fire immediately when $7 says we are exactly one frame out, and
	-- wait one frame when it says we are not. Waiting shifts the $7 == 2
	-- population from {3,3,3,2,2,...} to {2,2,2,1,1,...}, i.e. off the
	-- always-fails free-3 bucket and onto the buckets that work.
	local _recovery = memory.readbyte(0xFF8940)   -- $140 recovery variant
	local _animctr  = memory.readbyte(0xFF8820)   -- $20  animation frame counter
	local _sub      = memory.readbyte(0xFF8807)   -- $7   wake-up sub-state

	-- One-frame hold, for $7 == 2 ONLY. Kept on the sequence itself so it
	-- cannot leak between knockdowns.
	--
	-- MEASURED (50 attempts, v11-predict-substate.1) after the wait was first
	-- added as "$7 ~= 0", which was too broad:
	--       $7 == 0  ->  27 reversal /  2 nothing   (fire now: already free-1)
	--       $7 == 2  ->  12 reversal /  0 nothing   (wait one frame: perfect)
	--       $7 == 4  ->   0 reversal /  8 nothing   (waiting RUINED these)
	-- $7 == 4 is the roll/tech get-up branch of the wake-up machine
	-- (0x03918E for Morrigan, 0x024F1E generic). It reaches $20 == 0 exactly
	-- one frame before the actionable frame already, so the extra wait pushed
	-- every one of them onto the free frame itself - and by timing bucket,
	-- firing on the free frame is 0 for 8 while one frame early is 24 of 26
	-- and two frames early is 15 of 15.
	-- One-frame hold, for $7 == 2 only.
	--
	-- WHAT DECIDES SUCCESS IS THE STATE AT RELEASE, NOT HOW EARLY IT IS.
	-- Measured, grouped by $7 (the wake-up sub-state) at the moment of release:
	--       $7 == 0  (st2 = $04, wake-up already transitioned, kd = 27)
	--            fire immediately     -> 20/25, 27/29, 3/3 reversal
	--       $7 == 2  (st2 = $02, still in the get-up state, kd = 26)
	--            wait one frame       -> 12/12 and 9/9 reversal
	--            fire immediately     ->  1/9  (v13)
	--
	-- REVERTED (v13): dropping the wait and gating on kd >= 26 instead.
	-- The justification was a bucket table saying "two frames early is 15/15",
	-- but that table was confounded: nearly every one of those 15 was a
	-- $7 == 0 case. Once the kd gate let $7 == 2 cases fire two frames early
	-- as well, they collapsed to 1 of 9. How early the press lands is a
	-- symptom; the sub-state is the cause. Do not re-derive timing rules from
	-- offset statistics without splitting by $7 first.
	--
	-- Still unsolved, and NOT what the wait causes: the attempts where this
	-- predictor never fires at all and the window fallback releases on the
	-- free frame itself (logged with sub = 4, which is the CROUCH free state
	-- from 0x026D72 - not a roll). Those are ~12% and need a separate signal.
	-- REMOVED AGAIN (v16), and this time for a reason that did not exist
	-- before: the wait was calibrated against joypad.set()'s built-in one-tick
	-- latency. The 0xFF8B94 injection removes exactly that tick, so the wait
	-- now over-delays by the same amount it used to compensate for.
	--
	-- The measurement flipped accordingly. Before injection the best bucket
	-- was one tick early; with injection (v15) it is TWO:
	--       injected 0 ticks early:  0 reversal /  2 nothing
	--       injected 1 tick  early: 19 reversal /  3 nothing
	--       injected 2 ticks early: 12 reversal /  0 nothing   <- 100%
	-- ...and PUT BACK (v17). The reasoning above was wrong: v16 measured
	-- 21/48, worse than v15's 31/36. Removing the wait pushed attempts onto
	-- the three-ticks-early bucket, which is fatal:
	--       injected 1 tick  early: 23/26 across v15+v16
	--       injected 2 ticks early: 29/37
	--       injected 3 ticks early:  0/19   <- every single one produced nothing
	-- The "2 ticks early is 100%" figure that justified v16 was 12/12 - a
	-- small sample that did not hold up (17/25 once v16 fed it more cases).
	-- One tick early is the best bucket, with or without injection, so the
	-- wait stays.
	-- PUT BACK HERE (v26). v19-v25 moved this into the tick hook; measured, it
	-- released three frames before the actionable frame and scored 0 of 9.
	-- The hook is still the thing that DELIVERS the input (one tick earlier
	-- than joypad.set can), but this is where the timing is decided, because
	-- this is the version that measured 88%.
	-- THE KNOCKDOWN WAKE-UP NO LONGER RELEASES FROM HERE (v33).
	--
	-- It is decided in the registerexec hook on 0x02211A, on one specific
	-- game tick - see the long note there. This function runs once per
	-- DISPLAYED frame, i.e. once per ~3 ticks, so anything released here
	-- lands on an arbitrary tick within the frame. That is precisely the
	-- error the tick hook exists to remove, and a copy of the predictor here
	-- would fire first and take the release away from it.
	--
	-- The previous occupant of this branch was the "$7 == 0 and $06 == 0x04"
	-- predictor. Same state the tick hook now keys on, evaluated on the wrong
	-- clock; it is not a safety net for the tick hook, it is a competitor.
	-- The window branch below still catches a wake-up the tick hook misses,
	-- so the dummy can never be left holding a direction forever.
	if _seq.tick_owned or _in_stun then
		-- EVERY IN-STUN RECOVERY IS OWNED BY THE 0x02211A TICK HOOK.
		--
		-- Widened from knockdown-only (v40). The window fallback below fires
		-- on 0xFF8974 as soon as the reversal window opens, which for
		-- hit-stun is well before the actionable tick. It released there, so
		-- the special came out reliably and was never a reversal - exactly
		-- the reported "Shadow Blade always comes out, never REVERSAL". It
		-- must not be allowed to pre-empt the tick hook.
		--
		-- The hook deliberately never releases the sequence (it cannot - see
		-- the rollback note there), so the sequence is still pending after
		-- the reversal has already happened, and it has to be cleaned up
		-- from here. NOTHING in this branch may touch Lua state until well
		-- past the reversal.
		--
		-- Why the delay, and why it is not paranoia: with run-ahead enabled
		-- the emulator re-runs about one displayed frame's worth of ticks and
		-- discards the first pass (section 8.6.12). Emulator RAM is restored,
		-- Lua state is not. An earlier version released here the moment $05
		-- read 0 - if the discarded pass is the one that contains the free
		-- tick, that release latches, and on the re-run the tick hook sees
		-- an already-released sequence and never injects. It breaks on
		-- exactly the frame that matters, and only when run-ahead is on.
		--
		-- tick_owned latches while the character is still in Hurt, which is
		-- many frames before the transition, so it is safe against a rewind.
		-- It is needed because both $05 and $140 stop indicating a recovery
		-- once it finishes; without it the cleanup would fall through to the
		-- window branch below and put a second button press on the dummy
		-- while the reversal is still coming out.
		_seq.tick_owned = true
		if memory.readbyte(0xFF8805) == 0x00 then
			-- RELEASE, not drop. Releasing lets the controller emit the final
			-- entry of the motion - down-forward + button - which is what
			-- draws the last column of the dragon punch in P2's input
			-- history. Dropping the sequence instead (v35-v37) removed that
			-- column and left the history showing only forward and down.
			--
			-- Immediately when nothing is being re-run, which is v34's
			-- behaviour and the one confirmed to display correctly. Only when
			-- a rewind has actually been observed is it debounced, because
			-- then a discarded pass could latch the release and the re-run
			-- would find an already-released sequence and never inject. The
			-- debounce costs a few frames of held direction in the history;
			-- that is the honest trade and it applies only with run-ahead on.
			-- ALWAYS DEBOUNCE. This read "rewind_seen and 8 or 0", on the
			-- reasoning that the debounce only pays for itself when a
			-- discarded run-ahead pass could latch the release. rewind_seen
			-- was accidentally true in every session (see the note at its
			-- declaration), so what was actually measured all along was a
			-- constant 8 - including v87's 133/144 with run-ahead off.
			--
			-- Making it honest by letting it fall to 0 was measured and it is
			-- a regression, on the two variants that were already weakest:
			--
			--     long hit stun      21/27 (78%) -> 15/28 (54%)
			--     rolling wake-up    38/43 (88%) -> 17/21 (81%)
			--     TOTAL             133/144 (92%) -> 69/86 (80%)
			--
			-- So it stays at 8 unconditionally, as a value that is doing real
			-- work rather than as a run-ahead workaround. Why 8 helps is not
			-- established; it is kept because it is what the measurements say.
			local _wait = 8
			_seq.idle_frames = (_seq.idle_frames or 0) + 1
			if _seq.idle_frames > _wait then
				release_input_sequence(_d)
			end
		else
			_seq.idle_frames = 0
		end
	elseif memory.readbyte(0xFF8974) > 0 then
		-- Fallback: the original reactive trigger, kept for the recoveries the
		-- predictor above does not cover (it is scoped to $140 == 0x0A, the
		-- knockdown wake-up). Hit-stun and block-stun reversals still come
		-- through here. release_input_sequence() is a no-op once released, so
		-- the two triggers cannot fight.
		debugKnockdownModule.mark_hold({ kd = _kd, in_stun = _in_stun,
			rev = memory.readbyte(0xFF8974), st1 = memory.readbyte(0xFF8805),
			st2 = memory.readbyte(0xFF8806), sub = memory.readbyte(0xFF8807),
			anim_fin = memory.readbyte(0xFF8821), recovery = _recovery,
			held = _seq.held or 0,
			event = "released", trigger = "window" })
		-- NOT FOR A MOTION THE TICK HOOK OWNS (v141).
		--
		-- inject_mask/inject_dir are the legacy one-shot: the 0xFF8B94 write
		-- hook ORs them onto every write for as long as they are set, so the
		-- button goes in again on a later tick. For a special that lands on the
		-- same tick as the real press and is invisible, because the second
		-- press is the same input as the first.
		--
		-- For a normal it is not invisible. VSAV chain-cancels a normal into
		-- itself on a fresh press, so a second edge is a SECOND SWING - which
		-- is exactly what "a chain-cancellable normal swings twice" is. The
		-- tick hook has already put the press exactly where it belongs, so
		-- there is nothing for this to add.
		-- ...AND NOT FOR A BLOCK MOTION EITHER (v154).
		--
		-- v141 excluded kd_tick, which is the knockdown path. Block motions are
		-- marked blk_hold and were still getting the one-shot, so the button
		-- was ORed in on top of whatever the sequence itself put down. On a
		-- back dash - whose entries are directions with no button at all - that
		-- turns the second tap into back+button, and the trace shows exactly
		-- that: $122 = 0x0401 on the free tick and $06 = 0x0A, a normal, on the
		-- one after. A dash never had a chance.
		if not _seq.kd_tick and not _seq.blk_hold then
			inject_mask = button_mask(guard_action_input.button())
			inject_dir  = guard_action_input.stick()
		end
		release_input_sequence(_d)
	elseif not _in_stun and _kd == 0 then
		-- Neither down nor in stun and no window ever opened. Drop the motion
		-- instead of leaving the dummy holding a direction forever.
		_d.pending_input_sequence = nil
	end
end

local function guardCancelCheck(run_dummy_input, macroLua_funcs)
	-- FIX: runs before any early return - verifying a poke already made must
	-- not depend on this frame's random frequency roll.
	retry_if_swallowed()
	reassert_palette_effect()
	service_held_reversal()
	service_gc_input_delay()

	-- DROP A HALF-RUN SEQUENCE AT THE EDGES.
	--
	-- Steps after the first live on the Lua side, so nothing the game does
	-- reaches them. Two things have to clear them, and both are here rather
	-- than further down because everything below can return early:
	--
	--   * the guard action is no longer a sequence - the steps belong to a
	--     setting that is not selected any more
	--   * the match is not running - a round ending mid-run would otherwise
	--     leave the rest of the steps to fire into the next one, against a
	--     dummy that never blocked anything
	--
	-- Loading a savestate is handled separately, in the master script, beside
	-- the same clean-up for pending_input_sequence.
	if globals.dummy.guard_action ~= 'sequence'
	   or globals.game_state == nil
	   or not globals.game_state.match_begun then
		actionSequenceRunnerModule.cancel()
	end

	-- GUARD = PUSH BLOCK IS NOT A GUARD ACTION.
	--
	-- Everything below this line is gated on the guard-action frequency roll,
	-- and with Guard Action Type set to None that frequency is off - so the
	-- push block never got as far as being built. It is part of how the dummy
	-- DEFENDS, so none of the guard-action gating should apply to it.
	local _pb_guard = (GUARD_PUSH_BLOCK[globals.options.guard] ~= nil)

	-- This is the randomness check i.e. "should happen 0%-100% of the time".
	--
	-- Drawn once per ARM - see gc_should_perform above for why calling
	-- shouldGC() here made every setting behave as 100%, and why one draw per
	-- stun span reads low on a blockstring. service_held_reversal ran at the
	-- top of this function, so the three arm latches are up to date here.
	local _arm_now = (arm_edge or hs_arm_edge or BLK.edge)
	local should_perform = gc_should_perform(_arm_now)
	if _arm_now and not should_perform then
		-- Refused, so the opportunity is spent. Leaving it latched is what let
		-- a later frame's draw pick it up.
		arm_edge = false
		hs_arm_edge = false
		BLK.edge = false
		-- AND THE PREVIOUS OPPORTUNITY'S LEFTOVERS GO WITH IT.
		--
		-- This is what made the frequency look like 100% however the gate was
		-- counted. M.arm() returns step one and parks steps two onward in the
		-- runner, where nothing in the game can end them - see "NO TIMEOUT
		-- ANYWHERE HERE" in actionSequenceRunner. So a schedule that could not
		-- finish because the dummy got blocked again simply waited, and came
		-- out on the next block - one the roll had refused.
		--
		-- On screen those are indistinguishable from a fresh guard action, so
		-- three fixes to the gate itself changed nothing visible. A hit passes
		-- and replaces the schedule wholesale; a refusal has to drop it, or an
		-- opportunity is not one unit.
		actionSequenceRunnerModule.cancel()
		-- And the direction a Hold step left down goes with it. The walker
		-- would drop it on its next pass anyway, once the schedule reads empty;
		-- doing it here means the dummy is not leaning on a direction for the
		-- tick in between.
		seq_held_lever = nil
		seq_held_btn = nil
		seq_held_btn_until = nil
	end

	-- TEMPORARY diagnostic: arming lives past these two early returns, so if
	-- either of them is taken on the one frame arm_edge is true, the reversal
	-- is silently never queued. Logged only on that frame to keep the volume
	-- to one entry per knockdown.
	if arm_edge then
		debugKnockdownModule.mark_write("arm_gate",
			should_perform and 1 or 0,
			(last_dummy_dict and last_dummy_dict[globals.current_frame]
			 and last_dummy_dict[globals.current_frame - 1]) and 1 or 0)
	end

	if not should_perform and not _pb_guard then return {} end

	if
		not last_dummy_dict or
		not last_dummy_dict[globals.current_frame] or
		not last_dummy_dict[globals.current_frame - 1]
	then
		return {}
	end

	_defender = player_objects[2]

	local current = last_dummy_dict[globals.current_frame]
	local prev    = last_dummy_dict[globals.current_frame - 1]
	local state_minus_2  = last_dummy_dict[globals.current_frame - 2]
	local state_minus_3  = last_dummy_dict[globals.current_frame - 3]
	-- The raw setting still feeds make_input_sequence's delay_before for push
	-- block and the dash cancels, and those count blanks - a negative would
	-- silently skip the `for` loop that spaces them. Auto is 0 there.
	local delay = globals.options.gc_delay
	if type(delay) ~= "number" or delay < 0 then delay = 0 end
	local delay_type = "delay_before"
	local _stick
	local _button
	local block_stop_timer = memory.readbyte(0xFF8558 + 0x400 )
	-- THE "True Reversal" OPTION IS GONE (v166).
	--
	-- It picked between two ways of spotting the game's reversal window, and it
	-- existed because the original author could not hit frame one through
	-- joypad.set - its own tooltip said so ("on turbo speed a true frame one
	-- reversal is only possible 75% of the time... other reversal actions are
	-- about 1-2 frames past earliest"). That is no longer how anything is
	-- timed: every reversal in this file is placed by the tick hook off $1a7,
	-- $158, ticks_to_landing() or the free-1 signature, and none of them look
	-- at this window at all.
	--
	-- What is left of should_reversal only gates the reactive fallback and some
	-- bookkeeping, so the toggle changed nothing a user could see and could
	-- only mislead. The kept behaviour is the one the default selected.
	local bulletproof_reversal = current.p2_reversal > 0 and prev.p2_reversal == 0 and
									(prev.p2_status_1 == "Hurt or Block" or state_minus_2.p2_status_1 == "Hurt or Block")

	local should_reversal = bulletproof_reversal
	
	if wasJustGuarding == false and block_stop_timer ~= 0 then
		wasJustGuarding = true
		frameStartedGuarding = globals.game_state.cur_frame
	end

	-- Still read by the two RECORDING counters, which play a macro and are
	-- frame-paced by nature. The input-driven counter no longer looks at it.
	local should_counter = player_objects[2].guard_ended and wasJustGuarding == true


	-- GUARD = PUSH BLOCK: THE PUSHING IS PART OF THE DEFENCE.
	--
	-- Queued here, in front of the guard action chain and outside it, because
	-- it is no longer a guard ACTION. Sitting in that chain made it exclusive
	-- with the counters, and the question it exists to answer - is a dash
	-- attack guaranteed after a push block? - is asked from the attacking
	-- side, so it needs nothing from Guard Action Type. That setting stays
	-- free for whatever else is being tested.
	--
	-- Same sequence and same tick pacing as the guard-action version: its taps
	-- are counted inside a 12 tick window, so they have to be spent in ticks.
	-- QUEUED HERE, NOT VIA counter.sequence.
	--
	-- Measured: the sequence was built on all 16 guard edges and queued on
	-- none of them. counter.sequence is the guard action's slot, and the guard
	-- action chain runs after this and clears it - `if not should_counter then
	-- _defender.counter.sequence = nil` - which is true for the whole of the
	-- blockstun. So the push block was built and thrown away every time.
	--
	-- It is not a guard action, so it should never have been in that slot.
	-- Handed straight to the tick hook instead, which also means the guard
	-- action is free to use its own slot for whatever comes next.
	local _pb_strength = GUARD_PUSH_BLOCK[globals.options.guard]
	if _pb_strength ~= nil then
		if player_objects[2].started_guarding
		   and _defender.pending_input_sequence == nil then
			-- THE DELAY IS NOT THIS SETTING'S BUSINESS.
			--
			-- gc_delay belongs to the guard action - "motion, then N ticks,
			-- then button". Passing it here prepends N blank entries in FRONT
			-- of the push block taps, which pushes them out of the game's 12
			-- tick window and the push block simply does not happen.
			--
			-- It only looked like a dash problem: on Auto the setting is -1, so
			-- `for i = 1, -1` never runs and no blanks are inserted. Every
			-- other value broke it.
			local _pbseq = make_input_sequence(
				"PB-" .. _pb_strength, "", "", 0)
			if _pbseq ~= nil then
				queue_input_sequence(_defender, _pbseq)
				if _defender.pending_input_sequence ~= nil then
					_defender.pending_input_sequence.pb_tick = true
				end
			end
		end
	end

	-- Neither of these early exits applies when Guard is Push Block: the
	-- pushing is not a guard action, so it must not be gated by one being
	-- selected or by the guard-action frequency. With guard_action 'none' the
	-- chain below simply matches nothing and falls through to the queueing.
	if globals.dummy.guard_action == 'none' and not _pb_guard then
		return {}
	elseif 	globals.options.gc_freq == 0 and not _pb_guard then
		emu.message("Not running Guard Action. There is no frequency set")
		return {}
	elseif globals.dummy.guard_action == 'gc' then
		if player_objects[2].started_guarding then
			local _input_delay = globals.options.gc_input_delay or 0
			if _input_delay and _input_delay > 0 then
				-- FIX/GC input delay: ガード開始エッジで、ガードキャンセルを
				-- 指定フレーム遅延して実行する予約を保持する。実際の入力は
				-- service_gc_input_delay() が fire_frame 到達時に queue する。
				gc_delayed = {
					start_lg = memory.readbyte(0xFF8081),
					wait     = _input_delay,
					button   = globals.dummy.gc_button,
				}
			else
				-- ディレイ0 = 従来どおり最速で入力（Neutral挿入も attack_frame
				-- 遅延もなし）。delay_type は GC では使わない。
				_defender.counter.attack_frame = globals.current_frame
				_stick = "DPF"
				_button = globals.dummy.gc_button
				_defender.counter.sequence = make_input_sequence(_stick, _button, "delay_before", 0)
			end
		else
			_defender.counter.sequence = nil
		end

	elseif globals.dummy.guard_action == 'pb' then
		if player_objects[2].started_guarding then 
			_defender.counter.attack_frame = globals.current_frame
			_stick = "PB-"..globals.dummy.pb_type
			_button = ""
			_defender.counter.sequence = make_input_sequence(_stick, _button, delay_type, delay)
		else
			_defender.counter.sequence = nil
		end
	elseif globals.dummy.guard_action ==  'recording on pushblock' then
		if player_objects[2].started_guarding then 
			_defender.counter.attack_frame = globals.current_frame
			_stick = "PB-"..globals.dummy.pb_type_rec
			_button = ""
			_defender.counter.sequence = make_input_sequence(_stick, _button, delay_type, delay)
		else
			_defender.counter.sequence = nil
		end
		if should_reversal then 
			if not globals.macroLua.playing then  
				globals.macroLua.playcontrol()
			end
		else
			-- _defender.counter.sequence = nil
			-- _defender.pending_input_sequence = nil
		end

	elseif globals.dummy.guard_action == "recording on counter" then
		if wasJustGuarding == false and block_stun_timer ~= 0 then
			wasJustGuarding = true
			frameStartedGuarding = globals.game_state.cur_frame
		end

		if should_counter then
			if not globals.macroLua.playing then  
				globals.macroLua.playcontrol()
			end
			wasJustGuarding = false
		else
			_defender.counter.sequence = nil
			_defender.pending_input_sequence = nil
		end

	elseif globals.dummy.guard_action == 'reversal'
	    or globals.dummy.guard_action == 'counter'
	    or globals.dummy.guard_action == 'sequence' then
		-- SEQUENCE RIDES THE REVERSAL, IT DOES NOT COPY IT (v300).
		--
		-- Only the source of the input list differs; when it fires, how it is
		-- placed on the actionable tick, and every gate that decides whether it
		-- may fire at all are the reversal's, unchanged. _is_counter stays
		-- false for it, so it arms on the reversal's three edges.
		-- COUNTER IS THIS PATH WITHOUT THE WAKE-UP ARM (v191).
		--
		-- It used to be its own branch, triggered on $164 (the guard pushback
		-- timer) reaching zero and delivered by the frame path at one entry per
		-- DISPLAYED frame - the arrangement the reversal gave up in v131
		-- because a three entry motion cannot be walked through in the three to
		-- five ticks before the character is actionable.
		--
		-- Nothing about the two differs except WHEN they may fire. A reversal
		-- arms on a wake-up, a hit-stun recovery or a block; a counter is the
		-- same thing after a block or a hit and never on a wake-up. So the
		-- trigger is the only thing that has to change, and everything the
		-- reversal has been measured into - the free-1 signature, the tick
		-- driven prefix, kd_press_offset, the held last entry - applies
		-- unchanged.
		--
		-- $164 is not consulted at all any more. It was never checked against
		-- the tick the dummy actually becomes actionable, and the block path
		-- already computes that from $158 and BLK_LEAD.
		-- Arm the motion the moment the dummy enters stun, so the directions
		-- are already in the game's input buffer by the time the reversal
		-- window opens. Only the final entry - the one with the button - waits;
		-- service_held_reversal() lets it through on the window frame.
		--
		-- Falls back to the original behaviour on its own: if the motion is a
		-- single entry, or anything before the last entry presses a button,
		-- queue_input_sequence refuses to hold it and the sequence below runs
		-- exactly as it always did.
		local _is_counter = (globals.dummy.guard_action == 'counter')
		-- NOT `_is_counter and counter_arm_edge() or (...)` (v194).
		--
		-- That is the `a and b or c` idiom and it only works when b is never
		-- false. Here b IS false - that is the entire job of the gate - so
		-- every refusal fell straight through to the reversal's own condition
		-- and armed anyway. Measured on the v193 batch: wake-up 9 moves, air
		-- 10 moves, exactly the cases the gate was written to stop.
		local _armed
		if _is_counter then
			_armed = counter_arm_edge()
		else
			_armed = (arm_edge or hs_arm_edge or BLK.edge)
		end
		if _armed and _defender.pending_input_sequence == nil then
			-- ONE ROW PER GUARD ACTION THAT ACTUALLY GOES OUT.
			--
			-- gc_roll counts opportunities, this counts fires. Their ratio is
			-- the frequency the dummy really has, measured rather than argued
			-- about - which is what this setting needed from the start.
			gc_fires = gc_fires + 1
			debugKnockdownModule.mark_write("gc_fire", gc_opportunity % 256,
				(globals and globals.options and globals.options.gc_freq) or -1)
			if _is_counter then
				-- What the counter armed on, so the next batch can be split by
				-- recovery type without inferring it: val = $140<<8 | $1a7,
				-- pc = the airborne byte.
				debugKnockdownModule.mark_write("ctr_arm",
					memory.readbyte(0xFF8940) * 256 + memory.readbyte(0xFF89A7),
					memory.readbyte(0xFF8838))
			end
			prebuffer_used = true
			-- TEMPORARY diagnostic: v23 recorded knockdowns that reached
			-- kd = 27 with $140 = 0x0A, yet no sequence ever existed - the
			-- tick hook logged zero pending sequences and there were no
			-- release events. This records whether arming is reached at all
			-- and what make_input_sequence produced, so "never armed" can be
			-- told apart from "armed but produced nothing".
			-- NO LEADING BLANKS. NOT FOR HIT STUN EITHER (v179).
			--
			-- The delay is applied to the press by kd_press_offset(), and that
			-- runs off the free-1 signature, which hit stun reaches exactly as
			-- a knockdown does - the traces show press_defer with off = 1 +
			-- delay on every hit-stun span. So the "the hit-stun path still
			-- uses them" carve-out that used to be here counted the delay
			-- TWICE, and the copy it added landed in front of the motion:
			--
			--   delay N, forward dash  ->  {} x N, {forward}, {}, {forward}
			--
			-- which makes sequence[1] a blank - so v178's first tap was a
			-- neutral - and gives the frame path N more entries to walk before
			-- it reaches the forward at all. The v178 sweep shows the cost
			-- directly, and it is monotonic in the delay:
			--
			--   delay 2  dash 6/7     delay 5  dash 2/5
			--   delay 3  dash 23/30   delay 6+ dash 0/25
			--
			-- The motion goes in at once; only the button waits.
			local _mk = ga_sequence(
				globals.dummy.counter_attack_stick,
				globals.dummy.counter_attack_button,
				"", 0)
			debugKnockdownModule.mark_write("arm_edge",
				(_mk ~= nil) and #_mk or 0,
				memory.readbyte(0xFF89A7))
			-- Which recovery this armed on, and whether the list came from the
			-- sequence. val = $140<<8 | $05, pc = 1 when in sequence mode.
			debugKnockdownModule.mark_write("arm_kind",
				memory.readbyte(0xFF8940) * 256 + memory.readbyte(0xFF8805),
				(globals.dummy.guard_action == 'sequence') and 1 or 0)
			queue_input_sequence(_defender, _mk, true)
			local _after = _defender.pending_input_sequence
			-- A FIXED SEQUENCE: buttons before the last entry, so
			-- queue_input_sequence would not hold it.
			--
			-- Derived rather than re-tested. controller.lua sets hold_last only
			-- when the arm asked for it AND no entry before the last carries a
			-- button, and this arm always asks - so for a list of two or more
			-- entries, hold_last=false says exactly "there is a button in front
			-- of the last one". Re-walking the entries here would be a second
			-- copy of that rule, free to drift from it.
			local _is_fixed_seq = _after ~= nil and _after.sequence ~= nil
			                      and not _after.hold_last
			                      and #_after.sequence >= 2
			-- Hand the motion to the tick hook. It has to be held (the hook
			-- keys on hold_last) and it must not also be walked forward by
			-- joypad.set, which is what kd_tick turns off in controller.lua.
			-- NOT GATED ON hold_last ANY MORE.
			--
			-- A fixed sequence carries buttons before its last entry, so
			-- queue_input_sequence refused to hold it - and everything below
			-- was then skipped, leaving the frame path to walk all six entries
			-- out in a few ticks. Measured in v300 as the button landing on
			-- free-3/-2, where no reversal can start.
			--
			-- The tick clock each recovery rides is chosen here, from the arm
			-- edges this file already computes. v300 read the same answer out of
			-- characterAction.classify_recovery; the edges say it directly.
			if _after ~= nil and (_after.hold_last or _is_fixed_seq) then
				-- Armed by the knockdown path, whichever clock drives it.
				_after.kd_owned = arm_edge
				-- A BLOCK MOTION KEEPS ITS BUTTON FOR THE SIGNATURE.
				--
				-- It is not tick-driven (there is no block clock to drive it
				-- with yet) so the frame path still walks the prefix in, which
				-- is what it is good at. What it must NOT do is release: the
				-- idle-frames and window branches would let the final entry out
				-- at a frame boundary, and the signature hook skips a sequence
				-- that is already released - so the button would land early and
				-- the free-1 tick would pass with nothing on it.
				_after.blk_hold = BLK.edge
				if arm_tick_driven or arm_land_driven then
					_after.kd_tick = true
					_after.kd_land = arm_land_driven
				elseif _is_fixed_seq then
					-- A FIXED SEQUENCE NEEDS A CLOCK ON EVERY RECOVERY.
					--
					-- The two above are the wake-up and the landing. Without a
					-- clock the frame path walks the whole list out in a few
					-- ticks and the button lands on free-3/-2. Which clock is
					-- read off the arm edges this file already has; the tick
					-- hook picks the branch from $140 and hs_tick_lg.
					if BLK.edge then
						-- BLOCK. The hook reads the guard script cursor
						-- (gsl - $164), which is the measured distance to free.
						_after.kd_tick = true
					elseif hs_arm_edge then
						-- GROUND HIT STUN. There is no input-clean countdown
						-- here - $15c is shortened by our own injected inputs -
						-- so the hook runs off the tick the queue happened on.
						_after.kd_tick = true
						_after.hs_tick_lg = memory.readbyte(0xFF8081)
					end
				end
			end
			BLK.edge = false
			debugKnockdownModule.mark_write("arm_result",
				(_after ~= nil) and 1 or 0,
				(_after ~= nil and _after.hold_last) and 1 or 0)
		end

		-- NO REACTIVE FALLBACK FOR A COUNTER (v193).
		--
		-- should_reversal comes from 0xFF8974, the game's own reversal window,
		-- and that window opens on EVERY recovery - wake-up, air recovery,
		-- ground hit stun, block alike. It cannot tell them apart, so for a
		-- counter it undid the whole point of counter_arm_edge(): the tick arm
		-- correctly refused a wake-up, prebuffer_used stayed false, and this
		-- fallback queued the motion anyway. That is "起き上がりも空中やられも
		-- でてしまった、全部出る" - the gate was right and this was behind it.
		--
		-- A counter is defined by WHERE it may fire, and this path cannot
		-- honour that, so it does not run for one. If the tick arm did not
		-- take, nothing comes out - which is the correct answer.
		if should_reversal and not _is_counter then
			-- The pre-buffered motion covers this knockdown - whether it is
			-- still holding, already released, or has finished. Queueing here
			-- as well would run the motion a second time back to back, and the
			-- seam between the two passes spells a different move. Only fall
			-- through to the old path when pre-buffering never took.
			-- kd_motion_done covers the case the other two miss: the tick hook
			-- put the whole motion in and the sequence has since been dropped,
			-- so by this frame there is nothing left to see. Without it the
			-- reactive path queued the command a SECOND time on the wake-up
			-- frame - the delay-12/13 tail in every batch, and on screen a
			-- second copy of the motion in the input history.
			local _held = _defender.pending_input_sequence
			if prebuffer_used or kd_motion_done
			   or (_held ~= nil and _held.hold_last) then
				_defender.counter.sequence = nil
			else
				_defender.counter.attack_frame = globals.current_frame
				-- Same as the counter branch above: the tick hook owns the
				-- delay, so no blanks in front of the motion (v179).
				_stick = globals.dummy.counter_attack_stick
				_button = globals.dummy.counter_attack_button
				_defender.counter.sequence = ga_sequence(_stick, _button, delay_type, 0)
			end
		else
			-- Safe for a counter too: counter.sequence is the REACTIVE path's
			-- staging slot, and the tick arm queues straight into
			-- pending_input_sequence, so clearing it here cannot disturb a
			-- motion that armed correctly.
			_defender.counter.sequence = nil
		end

	elseif globals.dummy.guard_action == 'recording on reversal' then
		if should_reversal then 
			if not globals.macroLua.playing then  
				globals.macroLua.playcontrol()
			end
		else
			_defender.counter.sequence = nil
			_defender.pending_input_sequence = nil
		end
	elseif globals.dummy.guard_action == 'Character Specific Reversal' then
		-- Pit of Blame has its own trigger in service_held_reversal. The
		-- ordinary reversal window opens for ANY hit or block stun, not just
		-- knockdowns, so leaving it on this path as well made it come out on
		-- hits that never knock down at all.
		-- THE SAME ARM THE INPUT PATH USES, NOT should_reversal (v165).
		--
		-- should_reversal is derived from 0xFF8974, the game's own reversal
		-- window, and that window opens ON the free frame or later. The poke is
		-- placed on the free-1 signature, so a request that only arrives with
		-- should_reversal is always one tick too late to be placed at all:
		-- ground hit stun never fired, knockdowns and air recoveries fired only
		-- when frame jitter happened to line them up.
		--
		-- arm_edge / hs_arm_edge / BLK.edge are the arms service_held_reversal
		-- computes for the INPUT path - the ones every measurement in this file
		-- was made against. Using them means Character Specific is timed by the
		-- same machinery as a real reversal, which is the whole point of the
		-- work that went into them.
		if (arm_edge or hs_arm_edge or BLK.edge)
		   and not move_is_pit_of_blame() then
			csp_pending = true
		end
		if not should_reversal then
			_defender.counter.sequence = nil
		end
	elseif globals.dummy.guard_action == 'Character Specific Counter' then
		-- A counter acts as the block ends, and BLK.edge is exactly that moment
		-- measured on the block clock (section 5.5.2) rather than reacted to.
		-- hs_arm_edge alongside it (v191), so this arms on the same two events
		-- as the input-driven counter: after a block and after a hit, never on
		-- a wake-up. Without it the character specific counter was block-only
		-- while its input-driven twin covered both.
		if counter_arm_edge() and not move_is_pit_of_blame() then
			csp_pending = true
		end
		if not should_counter then
			_defender.counter.sequence = nil
		end
	elseif not _pb_guard then
		-- WHY THIS IS NOT A PLAIN else (v286).
		--
		-- With Guard = Push Block and no guard action selected, nothing in the
		-- chain matches and the old `else return {}` fired - so the sequence
		-- built above was thrown away before it could be queued, and no push
		-- block ever came out. Falling through is the point: the queueing step
		-- below is what actually hands it over.
		return {}
	end


	if _defender.counter.sequence then
		local _frames_remaining = _defender.counter.attack_frame - globals.current_frame
		if _debug then
		  print(_frames_remaining)
		end
		if _frames_remaining <= (#_defender.counter.sequence + 1) then
		  if _debug then
			print(frame_number.." - queue ca")
		  end
		  queue_input_sequence(_defender, _defender.counter.sequence)
		  -- HAND A PUSH BLOCK TO THE TICK HOOK (v184).
		  --
		  -- Its taps are counted by the game inside a 12 tick window, so they
		  -- have to be spent in ticks - see the note in
		  -- process_pending_input_sequence. Tagged here rather than in
		  -- queue_input_sequence because this is the only place that still
		  -- knows which guard action built the sequence.
		  local _ga = globals.dummy.guard_action
		  if (_ga == 'pb' or _ga == 'recording on pushblock')
		     and _defender.pending_input_sequence ~= nil then
		    _defender.pending_input_sequence.pb_tick = true
		  end
		  _defender.counter.sequence = nil
		  _defender.counter.attack_frame = -1
		end
	end
end

guardCancelModule = {
	["registerBefore"] = function(run_dummy_input, macroLua_funcs)
        return guardCancelCheck(run_dummy_input, macroLua_funcs)
    end
}
return guardCancelModule