function swap_inputs(_out_input_table)
  function swap(_input)
    local carry = _out_input_table["P1 ".._input]
    _out_input_table["P1 ".._input] = _out_input_table["P2 ".._input]
    _out_input_table["P2 ".._input] = carry
  end

  swap("Up")
  swap("Down")
  swap("Left")
  swap("Right")
  swap("Weak Punch")
  swap("Medium Punch")
  swap("Strong Punch")
  swap("Weak Kick")
  swap("Medium Kick")
  swap("Strong Kick")
end
function togglecontrolling()

	globals.controlling_p1 = not globals.controlling_p1

	local controlling = "P1"

	if globals.controlling_p1 ~= true then controlling = "P2" end

end
function disable_player( player_num )
	local player_addr = 0
	if player_num == 1 then
		player_addr = 0xFF8400
	else
		player_addr = 0xFF8800
	end 

	memory.writebyte(player_addr + 0x200, 0x01)
	memory.writebyte(player_addr + 0x3B4, 0x01)
end
function enable_player( player_num )
	local player_addr = 0
	if player_num == 1 then
		player_addr = 0xFF8400
	else
		player_addr = 0xFF8800
	end 
	memory.writebyte(player_addr + 0x200, 0x00)
	memory.writebyte(player_addr + 0x3B4, 0x00)
end
function disable_both_players()
	disable_player(1)
	disable_player(2)
end
function enable_both_players( )
	enable_player(1)
	enable_player(2)
end

local function debounce(func, debounceTime)
  if globals.debounceStarted == nil then 
    globals.debounceStarted = globals.current_frame
    func()
    return
  end
  if globals.debounceStarted + debounceTime <=  globals.current_frame then
    globals.debounceStarted = globals.current_frame
    func()
    return
  end
end

-- THE RECORDING SAVESTATE BELONGS TO ONE MATCH.
--
-- "current_recording" is a whole machine state under a single fixed name, so
-- loading one taken in a different match does not restore a setup - it swaps
-- the entire match back, characters and all. Record with Sasquatch vs Demitri,
-- reselect the two the other way round, and a playback would drag the old pair
-- back onto the screen.
--
-- The character pair is remembered next to it and checked before every load.
-- A mismatch skips the load only; the playback itself still runs, because the
-- recordings are already kept per dummy character.
local saved_state_chars = nil
local state_mismatch_warned = false

local function current_chars()
	return memory.readbyte(0xFF8400 + 0x382), memory.readbyte(0xFF8800 + 0x382)
end

function mark_recording_state_saved()
	local _a, _b = current_chars()
	saved_state_chars = { _a, _b }
	state_mismatch_warned = false
end

function drop_recording_state()
	saved_state_chars = nil
	state_mismatch_warned = false
end

function recording_state_valid()
	if saved_state_chars == nil then return false end
	local _a, _b = current_chars()
	if saved_state_chars[1] == _a and saved_state_chars[2] == _b then return true end
	if not state_mismatch_warned then
		state_mismatch_warned = true
		print("Savestate skipped: it was taken with different characters.")
	end
	return false
end

local last_inputs = nil
function handle_hotkeys()
  local _inputs = joypad.getup()
  local down = player_objects[1].input.down
  -- The wizard owns recording and playback while it is up. Volume Up would
  -- run reccontrol() straight through it - stopping the take and writing it
  -- to the normal slot - and with Use Savestate Upon Recording on it also
  -- saves a state in the middle of the take. Volume Down would start a
  -- playback over it. Coin (swap sides) is left alone: it is harmless, and
  -- the wizard restores the control target itself.
  local _wizard_busy = globals.recordingWizard ~= nil
                       and globals.recordingWizard.is_active ~= nil
                       and globals.recordingWizard.is_active()
  if last_inputs ~= nil then
    -- if  down["start"] == true and down["LP"] == true then 
    -- if down["start"] == true then 
		-- 	debounce(globals.menuModule.togglemenu,20)
    -- end
    -- if  down["start"] == true and down["MP"] == true then 
		-- 	debounce(globals.menuModule.togglegraphmenu,10)
    -- end
    -- if  down["start"] == true and down["LK"] == true then 
		-- 	debounce(globals.menuModule.dec_graph,5)
    -- end
    -- if  down["start"] == true and down["MK"] == true then 
		-- 	debounce(globals.menuModule.inc_graph,5)
		-- end

		-- Not while a macro is playing: the playback is driving P2, so taking
		-- the pad over there means both are writing the same side and the
		-- dummy does neither cleanly. Stop the playback first (Volume Down or
		-- Play Recording), then swap.
		if  _inputs["P1 Coin"] == nil and last_inputs["P1 Coin"] == false
		    and globals.macroLua.playing ~= true then
			globals.controllerModule.togglecontrolling()
		end
		if  (not _wizard_busy and _inputs["Volume Down"] == nil and last_inputs["Volume Down"] == false ) then 

      if globals.macroLua.playing then
        globals.macroLua.playcontrol()
      else
        -- Not while recording: the load would switch recording off (see the
        -- note at the loop restart in macro.lua).
        if globals.options.use_recording_savestate == true
           and globals.macroLua.recording ~= true
           and recording_state_valid() then
          savestate.load("current_recording")
        end
        globals.macroLua.playcontrol()
      end
    
		end
		if  not _wizard_busy and _inputs["Volume Up"] == nil and last_inputs["Volume Up"] == false then 
      if globals.macroLua.recording then
        globals.macroLua.reccontrol()
      else
        if globals.options.use_recording_savestate == true then
          globals.save_state = savestate.create("current_recording")
          savestate.save(globals.save_state)
          mark_recording_state_saved()
          globals.show_menu = false
        end
        globals.macroLua.reccontrol()

      end
		end
  end
  last_inputs = _inputs
  return _inputs
end

stick_gesture = {
  "none",
  "forward",
  "back",
  "down",
  "up",
  "QCF",
  "QCB",
  "HCF",
  "HCB",
  "DPF",
  "DPB",
  "HCharge",
  "VCharge",
  "360",
  "DQCF",
  "720",
  "back dash",
  "forward dash",
  "Shun Goku Ratsu", -- Gouki hidden SA1
  "Kongou Kokuretsu Zan", -- Gouki hidden SA2
}

button_gesture =
{
  "none",
  "recording",
  "LP",
  "MP",
  "HP",
  "EXP",
  "LK",
  "MK",
  "HK",
  "EXK",
  "LP+LK",
  -- Felicia's Please Help me is 4123 + LK+MK: the one pair that is not two of
  -- the same strength, and there is no other way to press it (user, 2026-09-05).
  "LK+MK",
  "MP+MK",
  "HP+HK",
}
-- _hold_last: cycle everything except the final entry and wait, instead of
-- running straight through. See the long note in process_pending_input_sequence.
-- RECORD WHAT WAS ACTUALLY QUEUED.
--
-- Two attempts to log the configured motion both produced nil: globals.dummy
-- is rebuilt per frame and globals.options was also unset at write time. The
-- reliable place is here, where the sequence physically exists - length is what
-- the arm calculation depends on, so logging the real thing removes any doubt
-- about which command a batch was measured with.
function queue_input_sequence(_player_obj, _sequence, _hold_last)
	if debugKnockdownModule and debugKnockdownModule.mark_write and _sequence then
		debugKnockdownModule.mark_write("seq_queued", #_sequence,
			(globals and globals.options and globals.options.counter_attack_stick) or 0)
	end
  if _sequence == nil or #_sequence == 0 then
    return
  end

  if _player_obj.pending_input_sequence ~= nil then
    return
  end

  local _seq = {}
  _seq.sequence = copytable(_sequence)
  _seq.current_frame = 1
  -- FIX (mirrored motion): remember which way the character was facing when
  -- the sequence started. process_pending_input_sequence compares against this
  -- every frame - see the note there.
  _seq.flip_input = _player_obj.flip_input
  _seq.restarts = 0

  -- Only sequences that actually contain a facing-relative direction can be
  -- mirrored, so only those may restart. This matters: the push block
  -- sequences are pure button taps ({LP},{},{LP},...) and their input COUNT is
  -- the point - replaying them from the start on a turnaround would silently
  -- change how many taps the dummy performs. Same for any button-only counter.
  _seq.uses_facing = false
  -- WHICH FIELD THE GAME WILL READ THIS OUT OF.
  --
  -- One injected word is corrected TWICE, into two fields, by two different
  -- bytes: $122 on $b alone (0x02218E) and $12a on $120 when grounded
  -- (0x0221DC). While those two disagree - which is what crossing over does -
  -- no single injection can be right for both, so the command has to say
  -- which one it is.
  --
  -- A sequence of nothing but horizontals and neutrals is a dash or a walk,
  -- and those are read raw out of $122. Anything carrying a button, an up or
  -- a down is a command motion, read out of $12a, and keeps the old
  -- resolution. guardCancel's facing_for_input() reads this flag.
  --
  -- Measured 2026-09-20: over three crossovers the tool's own answer flipped
  -- one tick before $b did, so the two taps of ONE dash went out as opposite
  -- screen directions while the game's reference had not moved - which is
  -- "the same direction twice" failing to be twice.
  _seq.raw_dir = false
  for _f = 1, #_seq.sequence do
    for _i = 1, #_seq.sequence[_f] do
      local _v = _seq.sequence[_f][_i]
      if _v == "forward" or _v == "back" then
        _seq.uses_facing = true
        _seq.raw_dir = true
      elseif _v ~= nil then
        -- A button, an up or a down: this is a command motion after all.
        _seq.raw_dir = nil
      end
    end
  end
  if _seq.raw_dir == nil then _seq.raw_dir = false end

  -- Pre-buffering. Only safe when nothing before the final entry presses a
  -- button - see the note in process_pending_input_sequence for why.
  --
  -- A SINGLE-ENTRY SEQUENCE IS HELD TOO (v139).
  --
  -- This used to require more than one entry, on the reasoning that holding is
  -- only meaningful when there is a motion to put in ahead of the button. That
  -- is true of the DELIVERY and false of the TIMING, and the timing is the
  -- whole point: a bare normal is one entry, so it was refused a hold, the tick
  -- hook in guardCancel.lua skips anything that is not held, and the press fell
  -- back to the once-per-displayed-frame path.
  --
  -- Straight out of the log for a crouching punch on Morrigan:
  --     arm_edge   val=1        make_input_sequence returned ONE entry
  --     arm_result val=1 pc=0   queued, hold_last = 0
  --     (no press_defer, no press_now, no kd_step)
  -- The press landed wherever the frame boundary happened to be, which for a
  -- normal - earliest on free+1, refused on free+0 - is almost never right.
  --
  -- With no prefix there is nothing to cycle, so a held single entry simply
  -- waits; process_pending_input_sequence returns early for it below.
  _seq.hold_last = false
  if _hold_last and #_seq.sequence >= 1 then
    local _button_before_last = false
    for _f = 1, #_seq.sequence - 1 do
      for _i = 1, #_seq.sequence[_f] do
        local _v = _seq.sequence[_f][_i]
        if _v ~= "forward" and _v ~= "back" and
           _v ~= "up" and _v ~= "down" and
           _v ~= "h_charge" and _v ~= "v_charge" then
          _button_before_last = true
        end
      end
    end
    _seq.hold_last = not _button_before_last
  end
  _seq.released = false

  _player_obj.pending_input_sequence = _seq
end

-- Let a held sequence run its final entry. Safe to call when nothing is held.
function release_input_sequence(_player_obj)
  local _seq = _player_obj.pending_input_sequence
  if _seq == nil or not _seq.hold_last or _seq.released then
    return false
  end
  -- A knockdown motion on the $1a7 clock is owned entirely by the tick hook in
  -- guardCancel.lua, which needs `released` to stay false to keep injecting.
  -- Releasing it here would also SKIP whatever prefix has not gone in yet -
  -- current_frame jumps straight to the last entry below - and a quarter-circle
  -- missing its diagonal produced nothing in 21 of 21 measured wake-ups.
  if _seq.kd_tick then
    return false
  end
  -- Block motions are the same case: guardCancel.lua's signature hook puts the
  -- button on free-1 itself and skips anything already released.
  if _seq.blk_hold then
    return false
  end
  -- An action sequence's later segments are the same case again: the tick hook
  -- walks every entry itself. Releasing would set current_frame to the last
  -- entry and SKIP whatever prefix has not gone in yet - a quarter circle
  -- losing its diagonal, exactly as above.
  if _seq.seq_tick then
    return false
  end
  -- (probe removed: mark_write is not visible from this file - see the rl
  -- field in guardCancel.lua's tick trace instead)
  _seq.released = true

  -- Exactly one button press. Never a second one as insurance.
  --
  -- Vampire Savior clears the command history when a button is pressed and the
  -- motion in front of it has not been completed. A press that misses does not
  -- simply do nothing - it destroys the buffered motion, so a follow-up press
  -- has nothing left behind it. Pressing twice to cover two candidate frames,
  -- which is the obvious way to hedge, is therefore strictly worse than
  -- pressing once: the first press throws away the very input the second one
  -- would have needed.
  --
  -- The same rule is why the button must not go in early. See the release
  -- condition in guardCancel.lua.
  _seq.current_frame = #_seq.sequence
  return true
end

function stick_input_to_sequence_input(_player_obj, _input)
  if _input == "Up" then return "up" end
  if _input == "Down" then return "down" end
  if _input == "Weak Punch" then return "LP" end
  if _input == "Medium Punch" then return "MP" end
  if _input == "Strong Punch" then return "HP" end
  if _input == "Weak Kick" then return "LK" end
  if _input == "Medium Kick" then return "MK" end
  if _input == "Strong Kick" then return "HK" end

  if _input == "Left" then
    if _player_obj.flip_input then
      return "back"
    else
      return "forward"
    end
  end

  if _input == "Right" then
    if _player_obj.flip_input then
      return "forward"
    else
      return "back"
    end
  end
  return ""
end

function make_input_sequence(_stick, _button, _delay_type, _delay_num)

  if _button == "recording" then
    return nil
  end

  local _sequence = {}
  if      _stick == "none"    then _sequence = { { } }
  elseif  _stick == "forward" then _sequence = { { "forward" } }
  elseif  _stick == "back"    then _sequence = { { "back" } }
  elseif  _stick == "down"    then _sequence = { { "down" } }
  elseif  _stick == "up"      then _sequence = { { "up" } }
  -- Down, then up. The direction rides on the UP half, so the same motion
  -- gives a neutral, forward or back super jump.
  --
  -- THE NEUTRAL IN FRONT IS NOT OPTIONAL.
  --
  -- A dummy set to crouch is already holding down, so writing down again
  -- changes nothing the game can see and there is no press edge - the motion
  -- never starts and no super jump comes out. Releasing first gives the down
  -- an edge to be. Same reason back dash carries a neutral between its taps.
  elseif  _stick == "super jump"         then _sequence = { {}, { "down" }, { "up" } }
  elseif  _stick == "super jump forward" then _sequence = { {}, { "down" }, { "up", "forward" } }
  elseif  _stick == "super jump back"    then _sequence = { {}, { "down" }, { "up", "back" } }
  elseif  _stick == "up-forward"    then _sequence = { {"up", "forward" } }
  elseif  _stick == "up-back"       then _sequence = { {"up","back" } }
  elseif  _stick == "down-forward"  then _sequence = {{"down", "forward" } }
  elseif  _stick == "down-back"     then _sequence = { {"down", "back" } }
  elseif  _stick == "QCF"     then _sequence = { { "down" }, {"down", "forward"}, {"forward"} }
  elseif  _stick == "QCB"     then _sequence = { { "down" }, {"down", "back"}, {"back"} }
  -- HCF AND HCB ARE FOUR STEPS, AND THEY ARE NOT MIRROR IMAGES.
  --
  -- Read out of the recogniser's own table (0x02A610, decoded via the ROM dump
  -- in debugKnockdown.lua):
  --
  --     0x2A670  back, down-back, down, down-forward      = HCF
  --     0x2A684  forward, down-forward, down, back        = HCB
  --
  -- HCF ends on DOWN-FORWARD, not forward: the trailing forward this used to
  -- send is not part of the command. HCB ends on BACK and never passes through
  -- down-back, so the symmetric five-step form was wrong in a different way.
  --
  -- Each extra entry costs a tick of lead, because the controller delivers one
  -- entry per displayed frame. Dropping one from each moves the wake-up arm
  -- from free-8 to free-7.
  elseif  _stick == "HCF"     then _sequence = { { "back" }, {"down", "back"}, {"down"}, {"down", "forward"} }
  elseif  _stick == "HCB"     then _sequence = { { "forward" }, {"down", "forward"}, {"down"}, {"back"} }
  -- UNABBREVIATED HALF CIRCLE - five stops including down-back. The generic
  -- recogniser (0x2A684) takes the four-step form above, but the move list
  -- draws Valkyrie Turn with all five stops and its own recogniser entry may
  -- want them. Used only by moves that name it in charMoves.lua; Vector Drain
  -- stays on the abbreviated "HCB" so the two forms can be A/B tested.
  elseif  _stick == "HCB-full" then
    _sequence = { { "forward" }, {"down", "forward"}, {"down"}, {"down", "back"}, {"back"} }
  elseif  _stick == "DPF"     then _sequence = { { "forward" }, {"down"}, {"down", "forward"} }
  elseif  _stick == "DPB"     then _sequence = { { "back" }, {"down"}, {"down", "back"} }
  -- THE MIZUUMI DIGIT STRINGS, EXPANDED AS WRITTEN.
  --
  -- The name is the notation. One digit is one entry, the same way QCF is 2-3-6
  -- and HCB is 6-3-2-4 above, so checking one against the other is counting.
  -- Which move uses which is kept in charMoves.lua's source_note.
  --
  -- A direction that repeats gets a neutral between. Same reason as the dash
  -- (back N back): a direction already held has no edge to press again.
  -- The button does NOT go on the second down. Measured: pressed together
  -- nothing comes out; on the tick after, it does. Aulbath's Direct Scissors is
  -- how this was found (user, 2026-09-05). The trailing empty entry is what
  -- make_input_sequence puts the button on, so it lands one tick later.
  elseif  _stick == "22"      then _sequence = { { "down" }, {}, { "down" }, {} }
  elseif  _stick == "46"      then _sequence = { { "back" }, {"forward"} }
  elseif  _stick == "263"     then _sequence = { { "down" }, {"forward"}, {"down", "forward"} }
  elseif  _stick == "632"     then _sequence = { { "forward" }, {"down", "forward"}, {"down"} }
  elseif  _stick == "41236"   then _sequence = { { "back" }, {"down", "back"}, {"down"}, {"down", "forward"}, {"forward"} }
  -- "2 then 8". Mizuumi's ~ means "and then", not a charge.
  elseif  _stick == "2~8"     then _sequence = { { "down" }, {"up"} }
  elseif  _stick == "6~4"     then _sequence = { { "forward" }, {"back"} }
  -- Charge moves. The charge itself is NOT built here - it is the user's, made
  -- with Hold on the steps before (user, 2026-09-05). The last entry is left
  -- empty so the button lands on its own tick rather than with the direction:
  -- neutral, direction, button.
  elseif  _stick == "[4]6"    then _sequence = { {}, {"forward"}, {} }
  elseif  _stick == "[2]8"    then _sequence = { {}, {"up"}, {} }
  elseif  _stick == "HCharge" then _sequence = { { "back", "h_charge" }, {"forward"} }
  elseif  _stick == "VCharge" then _sequence = { { "down", "v_charge" }, {"up"} }
  -- REVERTED to the original six points, pending the ROM check.
  --
  -- The four-cardinal form (forward, down, back, up) was put in on the
  -- reasoning that 2P side reads left-down-right-up and the diagonals are
  -- redundant. The 360 then stopped coming out, and the ROM has not confirmed
  -- either shape yet - the data for it sits at 0x2A758/0x2A760, past the end of
  -- the 256-byte dump that was taken.
  --
  -- What the disassembly does show is that rotation commands are matched by a
  -- DIFFERENT routine (0x2A2EA, not 0x29F4A) which tests
  --     btst #$7, D6 ; bne -> and.w D1, D0   partial match, any of the bits
  --     otherwise    -> cmp.w D1, D0         exact match
  -- so a diagonal can satisfy a step that asks for down OR forward. Passing
  -- through the diagonals is therefore not wasted, and dropping them can lose
  -- steps. Going back to the shape that was there before until the dump says
  -- otherwise.
  -- THE ROTATION IS THREE ADJACENT CARDINALS, NOT A FULL CIRCLE.
  --
  -- Decoded from the recogniser at 0x2A1B4, which is what Bishamon's
  -- 切り捨て御免 uses (block $320 via 0x29EC2, data 0x2A72C):
  --
  --     02A1CA  move.w ($394,A6), D0     direction, from $394 not $122
  --     02A1D8  cmpi.w #$8 -> position 0 (up)
  --     02A1E0  cmpi.w #$2 -> position 1 (forward)
  --     02A1E8  cmpi.w #$4 -> position 2 (down)
  --     02A1F0  cmpi.w #$1 -> position 3 (back), anything else fails
  --     02A200  move.b D1, ($1,A4)       the START is recorded, so any
  --                                      direction may begin the motion
  --     02A21C  bsr $2a2b6               D2/D3 = the two ADJACENT positions
  --     02A222  cmp.b D0, D2 -> +1       clockwise
  --     02A228  cmp.b D0, D3 -> -1       anticlockwise, else keep waiting
  --     02A230  subq.b #1, ($2,A4)       steps remaining, seeded from data +0
  --     02A238  add.b D1, ($1,A4)
  --     02A23C  andi.b #$3, ($1,A4)      positions wrap 0..3
  --
  -- Three consequences, all measured against the ROM rather than guessed:
  --
  --   Diagonals are rejected outright - cmpi is an exact compare, so the
  --   six-point form was being thrown away at the first entry. That is why
  --   nothing ever came out and a stray crouching HP appeared instead.
  --
  --   Only ADJACENT positions advance it. The order has to walk the circle.
  --
  --   Data +0 is the STEP COUNT, not a direction. Bishamon's is 0x02, so the
  --   motion completes after the start plus two steps - three cardinals, not
  --   a full revolution.
  --
  -- forward -> down -> back is 1 -> 2 -> 3, one step at a time clockwise.
  -- FOUR cardinals. The ROM's step counter said three would do; the game says
  -- otherwise, and the game wins.
  --
  -- Data +0 for Bishamon's rotation is 0x02 and 0x2A230 decrements it once per
  -- adjacent step, which reads as "start plus two". Measured, three cardinals
  -- do not produce the move. Either the counter is consumed somewhere else in
  -- the dispatch chain (0x2A246 onward is not fully decoded) or reaching zero
  -- is not by itself the completion test.
  --
  -- The three-step attempt was also run while assert_input_bits still OR-ed
  -- the lever, so it never got a clean "back" anyway - but four is what the
  -- user observes to be required, so four it is.
  -- THE SPARE DIRECTION GOES IN FRONT, NOT AT THE END.
  --
  -- Four directions is a turn on paper but not to the recogniser: after
  -- blocking a light attack the throw did not come out, and blocking holds
  -- back - so one direction was already spent and the run ended short.
  -- Measured standing vs crouching (user, 2026-09-05).
  --
  -- The spare one went on the END first, and that cost a tick: the button
  -- always rides the LAST entry, so it moved off "up" - where the turn
  -- completes - onto the direction after it, and the throw came out on +1
  -- instead of Fastest (user, 2026-09-05). In front, the turn still finishes on
  -- "up" with the button on it, and a direction eaten going in leaves a whole
  -- turn behind.
  --
  -- Leading with "up" does not jump: every entry but the last lands while the
  -- dummy is still in stun.
  elseif  _stick == "360"     then _sequence = { { "up" }, { "forward" }, {"down"}, { "back" }, { "up" } }
  -- 720 is the 360 twice.
  elseif  _stick == "720"     then _sequence = { { "up" }, { "forward" }, {"down"}, { "back" }, { "up" }, { "forward" }, {"down"}, { "back" }, { "up" } }
  -- full moves special cases
  elseif  _stick == "back dash" then _sequence = { { "back" }, {}, { "back" } }
  elseif  _stick == "forward dash" then _sequence = { { "forward" }, {}, { "forward" } }
  -- THE CANCEL DIRECTION IS HELD, NOT TIMED (v201).
  --
  -- The attack wiki's Sasquatch page, Short Dash section, states it plainly
  -- for turbo 3: the cancel lands when the reverse direction is in five frames
  -- after the dash, the game looks for it on ONE frame only - and "holding the
  -- reverse direction from immediately after the dash is fine". Pressing the
  -- button together with the reverse direction still gives the dash attack,
  -- and the back dash short is identical.
  --
  -- So the reverse direction goes in as the LAST entry and stays down. The
  -- tick hook holds a buttonless final entry through the delay wait already
  -- (kd_holds_direction), which is exactly the "input and leave it" the wiki
  -- describes, and it removes the need to know each character's cancel frame:
  -- a held lever cannot miss a one frame window that a timed press can.
  -- A DASH CANCEL IS A DASH. THE REVERSE COMES FROM THE TICK HOOK (v207).
  --
  -- These are byte for byte the plain dash above, on purpose. The dash has to
  -- be delivered by the frame path, which starts at the arm and so gets the
  -- second tap onto free+0 - and the trace says free+0 is not a preference but
  -- a requirement: with the taps one tick later (tap on free-1, neutral on
  -- free+0, tap on free+1) $06 never reaches 0x14 at all and a plain normal
  -- comes out instead. Any sequence long enough to need the tick hook's
  -- takeover therefore cannot dash, which is what v203-v206 kept running into.
  --
  -- So the reverse direction is not in the sequence any more. guardCancel.lua
  -- holds it during the delay wait and presses the button with it, which is
  -- the same "put it in and leave it" the wiki describes and costs the dash
  -- nothing.
  elseif  _stick == "back dash cancel" then _sequence = { { "back" }, {}, { "back" } }
  elseif  _stick == "forward dash cancel" then _sequence = { { "forward" }, {}, { "forward" } }
  elseif  _stick == "Shun Goku Ratsu" then _sequence = { { "LP" }, {}, {}, { "LP" }, { "forward" }, {"LK"}, {}, { "HP" } }
  elseif  _stick == "Kongou Kokuretsu Zan" then _sequence = { { "down" }, {}, { "down" }, {}, { "down", "LP", "MP", "HP" } }
  elseif _stick == "PB-light" then _sequence = { {"LP"}, {}, {"LP"}, {}, {"LP"}, {}, {"LP"}, {}, {"LP"},{},{"LP"} } 
  elseif _stick == "PB-medium" then  _sequence = { {"MP"}, {}, {"MP"}, {}, {"MP"}, {}, {"MP"}, {}, {"MP"},{},{"MP"} }
  elseif _stick == "PB-heavy" then  _sequence = { {"HP"}, {}, {"HP"}, {}, {"HP"}, {}, {"HP"}, {}, {"HP"}, {} ,{"HP"} }
  elseif _stick == "PB-ascending" then _sequence = { {"LP"}, {"LK"}, {"MP"}, {"MK"}, {"HP"},{"HK"} }
  elseif _stick == "PB-descending" then _sequence = { {"HP"}, {"HP"},{"MP"},{"MK"}, {"LP"},{"LK"} }
  end

  if _delay_type == "delay_before" then
    -- FIX (off-by-one): this read "for i=0, _delay_num", which inserts
    -- _delay_num + 1 blank frames. A Guard Action Delay of 0 still put one
    -- empty frame in front of every sequence, so every guard action was
    -- delivered one frame later than requested and there was no way to ask for
    -- no delay at all.
    --
    -- Measured on the logs: a "Reversal - Specified" dragon punch had its
    -- first direction delivered on trigger+1 and its button on trigger+3, with
    -- trigger+0 spent on the blank. The dummy is already actionable on
    -- trigger+0 (its action byte reads 0x00 or 0x04 there), so that frame is
    -- pure loss.
    --
    -- Now delay N means exactly N blank frames. Note this shifts every guard
    -- action - GC, push block, counters - one frame earlier at the same
    -- setting.
    for i=1, _delay_num do
      table.insert(_sequence,1, {})
    end
  end

  -- A DIAGONAL JUMP IS ONE ENTRY, NOT TWO (v154).
  --
  -- The dash cancels need blank entries here: they are the gap before the
  -- cancel direction that follows. up-forward and up-back do not - they are a
  -- single simultaneous press - but they were in the same list, and `for i=0`
  -- appends one blank even at delay 0. The button then lands on the BLANK
  -- rather than on the diagonal, so the jump came out a tick after the
  -- direction and read as "+1F" on the display.
  --
  -- The diagonals are handled separately now, and only when a delay was
  -- actually asked for.
  if (_stick == "up-forward" or _stick == "up-back")
         and _delay_num and _delay_num > 0 then
    for i=1, _delay_num do
      table.insert(_sequence, {})
    end
  end

  -- (The cancel direction used to be appended here after _delay_num blanks,
  -- with a trailing blank for the button to land on. It is part of the
  -- sequence above now - see the note there.)

  -- NO MENU COMBINATION MAY KILL THE SCRIPT.
  --
  -- The chain above has no else, so a _stick it does not know leaves
  -- _sequence empty - and then _sequence[#_sequence] is _sequence[0], which is
  -- nil, and table.insert throws. The whole script stops on a dialog, which is
  -- what "bad argument #1 to 'insert' (table expected, got nil)" was.
  --
  -- Fall back to the same shape "none" produces: one entry, so the button goes
  -- in with no direction. The name is printed once so the missing case can be
  -- added rather than silently tolerated.
  if #_sequence == 0 then
    _sequence = { {} }
    _unhandled_stick = _unhandled_stick or {}
    local _k = tostring(_stick)
    if not _unhandled_stick[_k] then
      _unhandled_stick[_k] = true
      print("make_input_sequence: no branch for stick '" .. _k .. "'")
    end
  end

  if     _button == "none" then
  elseif _button == "MP+HP"  then
    table.insert(_sequence[#_sequence], "MP")
    table.insert(_sequence[#_sequence], "HP")
  elseif _button == "MK+HK"  then
    table.insert(_sequence[#_sequence], "MK")
    table.insert(_sequence[#_sequence], "HK")
  elseif _button == "LP+LK" then
    table.insert(_sequence[#_sequence], "LP")
    table.insert(_sequence[#_sequence], "LK")
  elseif _button == "LK+MK" then
    table.insert(_sequence[#_sequence], "LK")
    table.insert(_sequence[#_sequence], "MK")
  elseif _button == "MP+MK" then
    table.insert(_sequence[#_sequence], "MP")
    table.insert(_sequence[#_sequence], "MK")
  elseif _button == "HP+HK" then
    table.insert(_sequence[#_sequence], "HP")
    table.insert(_sequence[#_sequence], "HK")
  -- PPP AND KKK WERE NEVER PRESSED AT ALL.
  --
  -- These fell through to the `else` below and went in as the literal strings
  -- "EXP" and "EXK". Nothing downstream knows those names: entry_to_bits looks
  -- them up in BUTTON_BITS, which holds the six buttons and nothing else, and
  -- takes `or 0` - so the entry carried a direction and no button, and the move
  -- simply did not come out. Found on a Bishamon sequence ending in PPP.
  --
  -- Expanded here beside the other multi-button entries rather than taught to
  -- entry_to_bits, so that stays a plain name-to-bit map and hold_last's scan
  -- for "is a button pressed before the last entry" sees real button names too.
  elseif _button == "EXP" then
    table.insert(_sequence[#_sequence], "LP")
    table.insert(_sequence[#_sequence], "MP")
    table.insert(_sequence[#_sequence], "HP")
  elseif _button == "EXK" then
    table.insert(_sequence[#_sequence], "LK")
    table.insert(_sequence[#_sequence], "MK")
    table.insert(_sequence[#_sequence], "HK")
  else
    table.insert(_sequence[#_sequence], _button)
  end

  return _sequence
end
function process_pending_input_sequence(_player_obj, _input, delay)
  if _player_obj.pending_input_sequence == nil then
    return
  end
  -- (v142 blocked delivery here once the tick hook had pressed, to stop a
  -- chain-cancellable normal being swung twice. That worked but left the
  -- sequence pending forever - 43 of 114 past 40 ticks on the v143 batch - and
  -- a pending sequence makes queue_input_sequence refuse the next one. v144
  -- drops the sequence at the press instead, which stops the second delivery
  -- for the same reason and frees the slot, so the guard is gone from here.)

  -- A held sequence with nothing in front of the button has nothing to deliver
  -- until it is released. Returning here also keeps the prefix clamp below from
  -- winding current_frame back to 0 and indexing sequence[0] on the next frame.
  do
    local _s0 = _player_obj.pending_input_sequence
    if _s0.hold_last and not _s0.released and #_s0.sequence <= 1 then
      return
    end
  end
  -- Knockdown motions timed on $1a7 are delivered one entry per game TICK from
  -- the hook in front of 0x02211A. This function runs once per DISPLAYED FRAME,
  -- which is about 1.6 ticks during a wake-up, so letting it walk the same
  -- sequence forward as well would both double the input and lose entries.
  if _player_obj.pending_input_sequence.kd_tick then
    return
  end
  -- PUSH BLOCK IS ON THE TICK CLOCK TOO (v184).
  --
  -- The game counts button presses inside a window it opens at the block
  -- ($1ab, set to 14 at 0x023966 beside $158 and decremented once per tick at
  -- 0x02249C; 0x0275D8 refuses the push block once it reaches zero), so the
  -- taps have to be spent in ticks. Walking {LP},{},{LP},... at one entry per
  -- DISPLAYED frame takes about 18 ticks for the eleven entries and only four
  -- or five of the six presses land inside the window at all. The tick hook in
  -- guardCancel.lua delivers it instead, one entry per tick.
  if _player_obj.pending_input_sequence.pb_tick then
    return
  end
  -- SEQUENCE SEGMENTS ARE ON THE TICK CLOCK TOO (v300).
  --
  -- Same reason as the two above: an action sequence's later segments start on
  -- the tick the dummy becomes actionable and are walked one entry per tick by
  -- the hook in guardCancel.lua. Walking them here as well would double the
  -- input and lose entries.
  if _player_obj.pending_input_sequence.seq_tick then
    return
  end


  -- if is_menu_open then
  --   return
  -- end
  -- if not is_in_match then
  --   return
  -- end

  -- Cancel all input
  _input[_player_obj.prefix.." Up"] = false
  _input[_player_obj.prefix.." Down"] = false
  _input[_player_obj.prefix.." Left"] = false
  _input[_player_obj.prefix.." Right"] = false
  _input[_player_obj.prefix.." Weak Punch"] = false
  _input[_player_obj.prefix.." Medium Punch"] = false
  _input[_player_obj.prefix.." Strong Punch"] = false
  _input[_player_obj.prefix.." Weak Kick"] = false
  _input[_player_obj.prefix.." Medium Kick"] = false
  _input[_player_obj.prefix.." Strong Kick"] = false

  -- Charge moves memory locations
  -- P1
  -- 0x020259D8 H/Urien V/Oro V/Chun H/Q V/Remy
  -- 0x020259F4 (+1C) V/Urien H/Q H/Remy
  -- 0x02025A10 (+38) H/Oro H/Remy
  -- 0x02025A2C (+54) V/Urien V/Alex
  -- 0x02025A48 (+70) H/Alex

  -- P2
  -- 0x02025FF8
  -- 0x02026014
  -- 0x02026030
  -- 0x0202604C
  -- 0x02026068
  local _gauges_base = 0
  if _player_obj.id == 1 then
    _gauges_base = 0x020259D8
  elseif _player_obj.id == 2 then
    _gauges_base = 0x02025FF8
  end
  local _gauges_offsets = { 0x0, 0x1C, 0x38, 0x54, 0x70 }

  -- FIX (mirrored motion): restart the sequence if the character turned around
  -- while it was being fed in.
  --
  -- "forward" and "back" are resolved against _player_obj.flip_input on the
  -- frame they are delivered, and flip_input follows the character's facing.
  -- A character that turns around mid-sequence - which is exactly what happens
  -- while getting up - therefore receives half the motion in one direction and
  -- the rest mirrored. A dragon punch queued as forward, down, down-forward
  -- goes out as forward, down, down-BACK: not the move, and usually not any
  -- move.
  --
  -- Measured on five logged "Reversal - Specified" dragon punches: the facing
  -- flipped inside the motion once, and that was the only one of the five
  -- where no special came out at all (P2's action byte reached 0x0A, a normal,
  -- instead of 0x10). In the other four the motion was delivered under a
  -- single facing and the move came out every time. One case where the flip
  -- landed just BEFORE the first directional input also came out fine, which
  -- is the control that rules out the flip itself being the problem: it is
  -- specifically a flip in the middle that breaks it.
  --
  -- Restarting rather than latching the original facing is deliberate. The
  -- game re-reads the stick against the current facing too, so replaying the
  -- earlier direction under the old orientation would be just as wrong - the
  -- motion has to be re-entered under the facing the character actually ends
  -- up with. The cost is that the move comes out a few frames later; a
  -- mirrored motion produces nothing at all, so this is strictly better.
  --
  -- Bounded to two restarts. If the facing is oscillating every frame no
  -- ordering of inputs can succeed, and looping forever would keep the dummy
  -- permanently occupied.
  -- A MID-MOTION TURNAROUND NO LONGER ABORTS THE SEQUENCE (v53).
  --
  -- This used to throw the rest of the motion away, on the reasoning that a
  -- mirrored motion produces nothing and a REPLAYED one produces the wrong
  -- special (a dragon punch replayed reads "... down, down-back | back,
  -- down ..." and the join is a quarter circle).
  --
  -- That reasoning was about replaying. Continuing is a different thing.
  -- Every entry is resolved against the LIVE facing byte at the tick it is
  -- delivered (see _flip below, and entry_to_bits() in guardCancel.lua which
  -- reads the same byte) - so after a turnaround the remaining entries simply
  -- go in under the new orientation. The game corrects the stick against the
  -- current facing on its own tick too (0x022194), so what the recogniser
  -- sees stays a consistent relative motion across the flip. Nothing is
  -- re-entered, so there is no join and no quarter circle.
  --
  -- Aborting is what made Morrigan unreliable: her wake-ups and air recoveries
  -- turn the character round part-way through the pre-buffered motion, and
  -- every one of those attempts was silently discarded.
  --
  -- flip_input is carried forward so the comparison tracks, rather than
  -- re-firing on every subsequent frame.
  if _player_obj.pending_input_sequence.uses_facing and
     _player_obj.pending_input_sequence.flip_input ~= _player_obj.flip_input then
    _player_obj.pending_input_sequence.flip_input = _player_obj.flip_input
  end

  -- Which way "forward" points for a PRE-BUFFERED motion.
  --
  -- The facing byte says where the character is pointing NOW. For a motion
  -- entered during a knockdown that is the wrong question, because the game
  -- turns the character to face the opponent as it gets up - so the motion is
  -- entered under one orientation and read back under the other, mirrored, and
  -- no move comes out.
  --
  -- Measured over eleven pre-buffered reversals: eight came out, and in every
  -- one the facing at arming already matched the facing the move ran under.
  -- Two of the three failures are exactly the case where it did not - the byte
  -- said one thing while arming and had flipped by the time the move should
  -- have started.
  --
  -- Relative position answers the right question instead: the character will
  -- come up facing the opponent, so whoever is on the left will face right.
  -- That prediction matched the post-wake-up facing in all eleven, including
  -- both mismatched ones.
  --
  -- Only pre-buffered sequences use it. Anything queued at the moment it is
  -- needed keeps reading the live facing byte, which for those is correct.
  --
  -- SUPERSEDED (v36): the relative-position prediction above is gone. It was
  -- answering "which way will the character be facing after it gets up",
  -- because the facing byte was thought to flip during the wake-up. Measured
  -- on the v35 batch with tick-resolution logging, it does not: across all 55
  -- knockdown wake-ups, the swap the game applies at 0x022194 was IDENTICAL on
  -- every one of the last 12 ticks before the character became actionable. The
  -- facing is stable for the whole delivery window.
  --
  -- The prediction was not merely unnecessary, it was wrong twice - and those
  -- two were exactly the two attempts in that batch where no special came out.
  -- Both had the prediction emitting "Right" for forward while the game read
  -- raw bit 1 as BACK, so the dragon punch went in mirrored and the command
  -- never completed.
  --
  -- Read the same byte the game reads, at the moment of delivery. Working the
  -- sign out from the hardware path rather than by trial, because getting it
  -- backwards mirrors every motion:
  --
  --   008F1C: move.b $804000.l, D0   ; P2 port, active low
  --   008F22: not.b  D0
  --   008F26: andi.b #$f, D0
  --   008F32: move.b D0, ($5d,A5)    ; low nibble -> lever
  --   014E76: or.w   ($5c,A5), D2
  --   014E7A: move.w D2, ($b94,A5)   ; ...reaches $394 unchanged
  --
  -- so the raw lever nibble is the pad, untouched. The game then applies
  -- 0x022194's LUT (00,02,01,03 = bits 0 and 1 exchanged) ONLY when $b is
  -- non-zero - 0x02218E branches past the correction when $b is 0. Corrected
  -- bit 1 is forward, so:
  --
  --   $b == 0  ->  no swap  ->  forward is raw bit 1
  --   $b ~= 0  ->  swap     ->  forward is raw bit 0
  --
  -- and inputHistory.lua's read_game_input() pins which raw bit is which on
  -- screen: at facing == 0 it reads corrected bit 1 as LEFT. With no swap at
  -- $b == 0, corrected bit 1 is raw bit 1, so raw bit 1 is the pad's "Left".
  -- Therefore forward is "Left" when $b == 0 and "Right" otherwise, i.e.
  -- _flip (which selects "Right") is true exactly when $b is non-zero.
  --
  -- Checked against the v35 batch: in the successful attempts the motion went
  -- in as raw bit 1 with $b == 0, which this rule reproduces; in the two
  -- failures $b was non-zero while the old prediction still emitted raw bit 1,
  -- which is precisely the mirroring.
  --
  -- This also makes the controller agree with guardCancel.lua's entry_to_bits()
  -- by construction - it resolves the final direction against the same byte.
  -- Them disagreeing is what split the motion: the earlier directions went in
  -- under the prediction and the last one under the live byte.
  -- RESOLVED AGAINST THE BYTE THE GAME ITSELF USES (v55).
  --
  -- 0x0221CC picks what corrects $12a, which is the copy the special-move
  -- recogniser reads: $b while $38 or $115 is set (airborne), $120 otherwise.
  -- guardCancel.lua's facing_for_input() carries the full note and the
  -- measurements; the two must agree or the motion splits between the
  -- controller's entries and the injected one.
  local _base = (_player_obj.id == 1) and 0xFF8400 or 0xFF8800
  local _other = (_player_obj.id == 1) and 0xFF8800 or 0xFF8400
  local _face
  if memory.readbyte(_base + 0x38) ~= 0 or memory.readbyte(_base + 0x115) ~= 0 then
    _face = memory.readbyte(_base + 0x0B)
  else
    -- Reproduce 0x022160 rather than read $120, which is only updated later in
    -- the same tick. guardCancel.lua's side_flag_now() carries the full note.
    local _mx, _ox = memory.readword(_base + 0x10), memory.readword(_other + 0x10)
    if _mx >= 32768 then _mx = _mx - 65536 end
    if _ox >= 32768 then _ox = _ox - 65536 end
    local _d = _mx - _ox
    if ((_d + 0x16) % 65536) <= 0x2C then
      _face = memory.readbyte(_base + 0x120)
    elseif _d < 0 then
      _face = 1
    else
      _face = 0
    end
  end
  local _flip = _face ~= 0

  -- REMOVED (v38): a block here used to return early once the character was
  -- actionable, to stop the dummy holding the pre-buffer's second-to-last
  -- direction after the reversal. It did that, and it also removed the only
  -- thing that ever drew the LAST entry of the motion - the controller
  -- emitting down-forward + button once the sequence is released. P2's input
  -- history lost the "|_ +punch" column completely and showed only the
  -- forward and down of the dragon punch.
  --
  -- The hold was never this function's fault. It was guardCancel.lua delaying
  -- the release; that delay is now conditional on a rewind actually having
  -- been observed, so with run-ahead off the release happens the moment the
  -- character is free, exactly as it did in v34.

  local _s = ""
  local _current_frame_input = _player_obj.pending_input_sequence.sequence[_player_obj.pending_input_sequence.current_frame]
  for i = 1, #_current_frame_input do
    local _input_name = _player_obj.prefix.." "
    if _current_frame_input[i] == "forward" then
      if _flip then _input_name = _input_name.."Right" else _input_name = _input_name.."Left" end
    elseif _current_frame_input[i] == "back" then
      if _flip then _input_name = _input_name.."Left" else _input_name = _input_name.."Right" end
    elseif _current_frame_input[i] == "up" then
      _input_name = _input_name.."Up"
    elseif _current_frame_input[i] == "down" then
      _input_name = _input_name.."Down"
    elseif _current_frame_input[i] == "LP" then
      _input_name = _input_name.."Weak Punch"
    elseif _current_frame_input[i] == "MP" then
      _input_name = _input_name.."Medium Punch"
    elseif _current_frame_input[i] == "HP" then
      _input_name = _input_name.."Strong Punch"
    elseif _current_frame_input[i] == "LK" then
      _input_name = _input_name.."Weak Kick"
    elseif _current_frame_input[i] == "MK" then
      _input_name = _input_name.."Medium Kick"
    elseif _current_frame_input[i] == "HK" then
      _input_name = _input_name.."Strong Kick"
    -- elseif _current_frame_input[i] == "h_charge" then
    --   if _player_obj.char_str == "urien" then
    --     memory.writeword(_gauges_base + _gauges_offsets[1], 0xFFFF)
    --   elseif _player_obj.char_str == "oro" then
    --     memory.writeword(_gauges_base + _gauges_offsets[3], 0xFFFF)
    --   elseif _player_obj.char_str == "chunli" then
    --   elseif _player_obj.char_str == "q" then
    --     memory.writeword(_gauges_base + _gauges_offsets[1], 0xFFFF)
    --     memory.writeword(_gauges_base + _gauges_offsets[2], 0xFFFF)
    --   elseif _player_obj.char_str == "remy" then
    --     memory.writeword(_gauges_base + _gauges_offsets[2], 0xFFFF)
    --     memory.writeword(_gauges_base + _gauges_offsets[3], 0xFFFF)
    --   elseif _player_obj.char_str == "alex" then
    --     memory.writeword(_gauges_base + _gauges_offsets[5], 0xFFFF)
    --   end
    -- elseif _current_frame_input[i] == "v_charge" then
    --   if _player_obj.char_str == "urien" then
    --     memory.writeword(_gauges_base + _gauges_offsets[2], 0xFFFF)
    --     memory.writeword(_gauges_base + _gauges_offsets[4], 0xFFFF)
    --   elseif _player_obj.char_str == "oro" then
    --     memory.writeword(_gauges_base + _gauges_offsets[1], 0xFFFF)
    --   elseif _player_obj.char_str == "chunli" then
    --     memory.writeword(_gauges_base + _gauges_offsets[1], 0xFFFF)
    --   elseif _player_obj.char_str == "q" then
    --   elseif _player_obj.char_str == "remy" then
    --     memory.writeword(_gauges_base + _gauges_offsets[1], 0xFFFF)
    --   elseif _player_obj.char_str == "alex" then
    --     memory.writeword(_gauges_base + _gauges_offsets[4], 0xFFFF)
    --   end
    end
    _input[_input_name] = true
    _s = _s.._input_name
  end

  --print(_s)
  _player_obj.pending_input_sequence.current_frame = _player_obj.pending_input_sequence.current_frame + 1

  -- PRE-BUFFERING. While held, cycle the motion and never reach the final
  -- entry; release_input_sequence() jumps straight to it.
  --
  -- The problem this solves: a sequence used to start on the frame the
  -- reversal was detected, so a dragon punch spent that frame plus two more
  -- walking through forward, down before the button went in. Measured on the
  -- logs, the move started three frames after the dummy was already able to
  -- act - it was never a frame-one reversal, just an early one.
  --
  -- The motion cannot simply be started earlier, because the reversal frame is
  -- only knowable once it arrives: the trigger fires ON it. Nothing in the
  -- player object counts down to it either - a sweep of the whole object found
  -- no monotonic counter reaching zero there.
  --
  -- So the directions are entered ahead of time instead and only the last
  -- entry, the one carrying the button, waits for the trigger. Each direction
  -- stays valid for about ten game ticks, so cycling them keeps a complete
  -- motion sitting in the game's input buffer no matter which frame the
  -- trigger lands on.
  --
  -- Why this is safe during a knockdown: a moving wake-up needs a DIRECTION
  -- AND A BUTTON together. Directions on their own change nothing, and
  -- make_input_sequence only ever appends the button to the final entry, so
  -- everything cycled here is button-free by construction. queue_input_sequence
  -- verifies that rather than trusting it, and refuses to hold a sequence whose
  -- earlier entries press anything - which also leaves the push block
  -- sequences, that are all buttons, running exactly as before.
  --
  -- Timing is left in the game's hands throughout. Nothing here counts frames,
  -- so the turbo setting is irrelevant: on a frame that advances two ticks the
  -- cycle simply covers two ticks, and ten ticks of input window is far more
  -- slack than the cycle needs.
  --
  -- The motion is entered ONCE and then the last direction is simply held.
  -- It is never replayed. Vampire Savior rejects a move whose motion was
  -- entered twice before the button - input a fireball motion twice and press
  -- punch and nothing comes out - so any scheme that loops the motion while
  -- waiting would break the very move it is trying to produce.
  --
  -- Holding the last direction is not a second motion, it is the stick staying
  -- where it was put, which is also what a player does while waiting to press
  -- the button.
  --
  -- Because there is no replay, the motion has to be entered close enough to
  -- the trigger that it has not expired - each input stays live for roughly
  -- ten ticks. Choosing that moment is the caller's job; see the arming code
  -- in guardCancel.lua.
  local _s2 = _player_obj.pending_input_sequence
  if _s2.hold_last and not _s2.released then
    local _prefix_len = #_s2.sequence - 1
    if _s2.current_frame > _prefix_len then
      _s2.current_frame = _prefix_len
    end
    return
  end

  if _player_obj.pending_input_sequence.current_frame > #_player_obj.pending_input_sequence.sequence then
    _player_obj.pending_input_sequence = nil
  end
end
controllerModule = {
  ["registerStart"] = function() 
    enable_both_players()
    return {
      togglecontrolling = togglecontrolling,
      recording_state_valid = recording_state_valid,
      drop_recording_state = drop_recording_state,
      disable_both_players = disable_both_players,
      enable_both_players = enable_both_players,
      handle_hotkeys = handle_hotkeys,
      stick_gesture = stick_gesture,
      button_gesture = button_gesture,
      make_input_sequence = make_input_sequence, 
      process_pending_input_sequence = process_pending_input_sequence,
      queue_input_sequence = queue_input_sequence,
      -- RECORDING WIZARD: explicit control-target API. Thin wrappers over
      -- globals.controlling_p1 / togglecontrolling() so outside modules never
      -- poke the flag or fake Coin input directly.
      get_controlling_target = function()
        return (globals.controlling_p1 == true) and "P1" or "P2"
      end,
      set_controlling_target = function(target)
        local want_p1 = (target == "P1")
        if globals.controlling_p1 ~= want_p1 then togglecontrolling() end
      end,
    }
  end,
  ["registerBefore"] = function()
    _input = joypad.get()
    if globals.controlling_p1 == true then
      return _input
    end
    swap_inputs(_input)
    -- joypad.set(_input)
    return _input
end
}
return controllerModule