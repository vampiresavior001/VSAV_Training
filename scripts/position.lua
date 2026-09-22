-- STAGE POSITION SETTER.
--
-- Six arrangements, drawn as the stage rather than described, so the menu
-- reads as a map:
--
--     |12------|   1  self at the left wall
--     |21------|   2  opponent at the left wall
--     |---12---|   3  centre, self on the left
--     |---21---|   4  centre, self on the right
--     |------12|   5  opponent at the right wall
--     |------21|   6  self at the right wall
--
-- 1 is P1 (you), 2 is the dummy, | is the wall.
--
-- WHAT THE GAME WILL AND WILL NOT LET US DO
--
-- $10 is world X, and a position written from outside is NOT clamped - write
-- one past the wall and the character leaves the stage. But the character is
-- confined to the CAMERA window, and the camera follows at its own pace, so a
-- teleport is dragged back to the edge of the view and the camera looks
-- frozen. Writing the scroll words (0xFFB810/890/910/990, the set that tracks
-- the walk on both stages measured) moves the view slightly and no further:
-- the game recomputes them from where the characters actually are.
--
-- So slide instead of teleport. A small step each frame is the same situation
-- as walking and the camera keeps up on its own; re-reading the position every
-- frame means a step the game refused is simply not taken.
--
-- The walls are constants. Measured by walking BOTH characters into the same
-- corner - one alone cannot reach it, the partner holds it back - on two
-- stages: left 280/277, right 1000/1000. The same on both, so every stage is
-- the same width and no per-stage table is needed.
local P1 = 0xFF8400
local P2 = 0xFF8800
local X  = 0x10          -- $10, the integer half of a 16.16 position

local WALL_L = 280
local WALL_R = 1000

-- Closer than any pair can stand, so the game's own push-apart sets the real
-- distance. Character-independent, and no dependency on the hitbox reader.
local CONTACT_GAP = 8

-- Sixteen, because that is the most the camera can be moved in a frame - one
-- tile, the amount the game redraws per bit-4 flip of the camera X. Both
-- characters sliding the same way carries the midpoint at the same speed, so
-- anything faster than this would leave the framing behind exactly as it used
-- to be. See the camera note further down.
local STEP = 16          -- pixels per frame

local last_applied = nil
local pending_mode = nil
local settle = 0
local SETTLE_FRAMES = 20
local steps = nil        -- queue of things to do, one per slide
local arrived = {}
local lastpos = {}       -- for noticing a character that has stopped getting anywhere
local stuck = {}
local guard_frames = 0

local function sw(v)
  if v >= 0x8000 then return v - 0x10000 end
  return v
end

local function getx(base) return sw(memory.readword(base + X)) end

local function setx(base, v)
  if v < WALL_L then v = WALL_L end
  if v > WALL_R then v = WALL_R end
  memory.writeword(base + X, v)
  -- The fractional half goes too, or a sub-pixel offset survives the move.
  memory.writeword(base + X + 2, 0)
end

-- CENTRE IS WHERE THE GAME PUTS THEM.
--
-- Rather than deriving it from the walls - which would be the midpoint of two
-- measurements taken with different characters, and so a little off - take the
-- position the game itself uses at the start of a round. It is recognised by
-- both characters jumping at once while nothing here is moving them.
-- Both positions, not just the midpoint: the centre arrangements put the two
-- exactly where a round begins, spacing included. That is the thing worth
-- practising from - what reaches at the opening - so it should not be
-- approximated by standing them nose to nose in the middle.
-- READ FROM MEMORY, NOT BAKED IN.
--
-- Where a round starts can differ by character, so hardcoding one measured
-- pair would freeze one matchup's spacing into every other. The catch below
-- takes it fresh on every round start, and that is the value used.
--
-- The numbers here only stand in before the first round of a session has been
-- seen. Measured once the catch was made choosy enough: 554 and 728, 174
-- apart. Their midpoint is 641, and the walls independently put the centre at
-- 640 - two measurements that never touched each other agreeing, which is what
-- makes it trustworthy. (An earlier, sloppier catch returned 426/728, 302
-- apart; that fills the whole screen and is not where a round starts.)
local start_l, start_r = 640 - 87, 640 + 87
local have_start = true   -- start_l/start_r describe the round on screen
local prev = { [P1] = nil, [P2] = nil }

-- Two ways in, because one of them kept missing.
--
--   * both positions jumping at once catches a round change during play, but
--     not the first round: the emulator is already in the match by the time
--     anything here has a previous frame to compare against.
--   * $10 reads 0 while a round is being set up (which is what made an earlier
--     probe mistake 0 for the left wall), so 0 -> somewhere is the start of a
--     round, first one included.
-- THE TWO ARE NOT ZEROED ON THE SAME FRAME.
--
-- $10 reads 0 while a round is being set up, but the debug dump showed only
-- two frames in 4320 with a zero in them and no capture at all: the previous
-- version wanted BOTH to read 0 on the same frame, and they take turns. So arm
-- on either of them touching zero, and take the pair on the first frame after
-- that where neither is - which is the moment the game has just placed them,
-- before anybody can walk.
-- AND WAIT UNTIL THEY HAVE STOPPED.
--
-- Arming on a zero and taking the very next frame caught a moment that was not
-- the start line at all - 302 apart, which is nearly the whole screen. The
-- round opens with both standing still for a beat, so require that: both off
-- zero AND neither has moved for a few frames. Anything caught mid-placement
-- fails that.
local armed = false
local still = 0

-- NOT DURING THE ROUND INTRO.
--
-- A slide writes X every frame, and so does the game while the characters are
-- making their entrance. The two fight, the pair ends up somewhere neither
-- intended and the camera is left nowhere near them - the arrangement looks
-- shredded and the controls read as dead.
--
-- Only P1 is tested. $05 is non-zero through stun and knockdown, $06 is the
-- action id with 0 for standing neutral, so this is "the player's character is
-- actually standing there and able to move". Testing the dummy too would block
-- the shortcut whenever it happens to be guarding or mid-pose, which is a
-- normal thing to want to reposition out of.
-- Declared here, defined with the rest of the camera work further down. A
-- local referenced before its definition would resolve to a global instead -
-- nil at run time, and a crash the moment the shortcut is used.
local camera_restore_busy
local camera_for
local camera_write

local function slide_allowed()
  if globals == nil or globals.hotkeys_armed ~= true then return false end
  if not have_start then return false end
  -- NOT WHILE A RESTORE IS LANDING, AND NOT DURING THE WIZARD.
  --
  -- A restore is placing both characters itself, and a slide starting on top
  -- of it fights for the same addresses - but it only lasts a couple of dozen
  -- frames, so the press is simply held off rather than lost.
  --
  -- The wizard is blocked for the whole of its run, which is its own rule:
  -- while it is up the only thing worth being able to do is cancel it.
  --
  -- Ordinary looped playback is NOT blocked. An earlier version of this stopped
  -- slides during any macro playback at all, which quietly killed the Hotkey 2
  -- shortcut during exactly the practice it is most wanted in.
  if camera_restore_busy() then return false end
  local wiz = globals.recordingWizard
  if wiz ~= nil and wiz.is_active ~= nil and wiz.is_active() then return false end
  -- IDLE INCLUDES WALKING, AND THAT IS THE WHOLE BUG.
  --
  -- This asked for $06 == 0x00 and nothing else. Walking is $06 = 0x04 (the
  -- same thing the Action Timeline had to learn: 580 ticks of it measured on
  -- 2026-09-10, 569 of them with a direction held). The shortcut is worked by
  -- HOLDING a direction and pressing the key - and holding left or right walks
  -- the character. So the two sideways arrangements could never be asked for:
  -- the act of asking made the test fail.
  --
  -- Down is why the diagonals worked. Crouching keeps $06 at 0x00, so
  -- down+left and down+right passed and left and right did not. That is
  -- exactly the split reported, and the trace has it: seven presses dropped
  -- with "slide not allowed (armed=true ready=true)" - both the earlier
  -- conditions satisfied, this one refusing (user, 2026-09-13).
  local _status = memory.readbyte(P1 + 0x05)
  local _state = memory.readbyte(P1 + 0x06)
  return _status == 0 and (_state == 0x00 or _state == 0x04)
end

local function watch_round_start()
  local a, b = getx(P1), getx(P2)
  -- X reads 0 while the round is being set up. From there until the resting
  -- pair has been read back, start_l/start_r are last round's - and every
  -- arrangement is computed from them, so nothing may move on them yet.
  -- Seeded true rather than false: the constants above are the measured round
  -- start, so a tool started mid-match still has a usable basis and does not
  -- have to sit out until the next round.
  if a == 0 or b == 0 then armed = true still = 0 have_start = false end
  if prev[P1] == a and prev[P2] == b then
    still = still + 1
  else
    still = 0
  end
  local from_init = armed and a ~= 0 and b ~= 0 and still >= 8
  if from_init then armed = false end
  local both_jumped = prev[P1] ~= nil
     and math.abs(a - prev[P1]) > 40 and math.abs(b - prev[P2]) > 40
  if steps == nil and (from_init or both_jumped) then
    if a <= b then start_l, start_r = a, b else start_l, start_r = b, a end
    have_start = true
  end
  prev[P1], prev[P2] = a, b

end

-- EXCHANGE FIRST, THEN SLIDE.
--
-- Every arrangement is two places on the stage and a question of who stands in
-- which. Sliding a character THROUGH the other one is the part the game will
-- not allow, so do not ask it to - exchange the two positions outright and let
-- the slide run with the order already correct.
--
-- The exchange has to come FIRST. Doing it last, on arrival, leaves the pair
-- overlapping against a wall: the push-apart shoves the outer one into the
-- wall, the wall shoves back, and it judders there indefinitely. Doing it
-- first, whatever overlap it creates is resolved by the very next thing that
-- happens, which is both of them sliding away.
--
-- Left slot goes to P1 on the odd arrangements and P2 on the even ones, which
-- is just what the diagrams say: |12 and |21, ...12 and ...21.
local function slots_for(mode)
  local gap = CONTACT_GAP
  if mode == 1 or mode == 2 then
    return WALL_L, WALL_L + gap
  elseif mode == 5 or mode == 6 then
    return WALL_R - gap, WALL_R
  end
  return start_l, start_r
end

local ROOM = 24          -- how far off the wall to stand while exchanging

-- TEMPORARY: A TRACE OF ONE SLIDE, TO position_slide.log.
--
-- The repeat-rate fix (a held hotkey fires every frame, so place() was rebuilt
-- every frame) is necessary and measured, but it was not sufficient: holding
-- the lever sideways still does not rearrange the pair (user, 2026-09-13). The
-- offline test cannot see why, because it stubs memory - and in the real game
-- the two characters push each other apart and the game writes their X back.
--
-- So log what the slide actually does. TURN THIS OFF BEFORE A RELEASE: it
-- opens a file and appends while a slide runs.
local TRACE = false
local trace_file = nil
local function trace(fmt, ...)
	if not TRACE then return end
	if trace_file == nil then
		trace_file = io.open("position_slide.log", "a")
		if trace_file then
			trace_file:write("\n=== position slide \n")
		end
	end
	if trace_file then
		trace_file:write(string.format(fmt, ...))
		trace_file:flush()
	end
end

local function place(mode)
  if mode < 1 or mode > 6 then return end
  local want_left = (mode % 2 == 1) and P1 or P2
  local want_right = (want_left == P1) and P2 or P1
  local lslot, rslot = slots_for(mode)
  steps = {}
  if ((getx(P1) <= getx(P2)) and P1 or P2) ~= want_left then
    -- MAKE ROOM BEFORE EXCHANGING.
    --
    -- Jammed in a corner there is nowhere for the exchange to land: one of the
    -- two ends up inside the wall, gets pushed out, shoves the other, and the
    -- pair grinds. Ease the inner one off the wall first - a short slide, not
    -- a trip to the middle - and the exchange has somewhere to go.
    local mid = math.floor((getx(P1) + getx(P2)) / 2)
    local l, r = P1, P2
    if getx(P2) < getx(P1) then l, r = P2, P1 end
    table.insert(steps, { move = { [l] = mid - ROOM, [r] = mid + ROOM } })
    table.insert(steps, { swap = true })
  end
  table.insert(steps, { move = { [want_left] = lslot, [want_right] = rslot } })
  trace("place mode=%d want_left=%s P1x=%d P2x=%d steps=%d lslot=%d rslot=%d" ..
		"\n",
		mode, (want_left == P1) and "P1" or "P2", getx(P1), getx(P2),
		#steps, lslot, rslot)
  arrived = {}
  lastpos = {}
  stuck = {}
  -- Shorter than it was: nothing should take this long now, and a ceiling
  -- that is reached is a second and a half of dead controls, not seven.
  guard_frames = 180
end

-- Arriving means letting go: CONTACT_GAP is closer than any pair can stand, so
-- the game pushes them apart the moment they are placed. Keep writing the
-- target after that and the two sides fight every frame, which is the judder.
-- ARRIVING ALSO MEANS GIVING UP.
--
-- At a wall the target cannot be reached. CONTACT_GAP is 8, but two characters
-- actually stand about 30 apart, so the outer one is held there by the inner
-- one and never gets within a step of where it was sent. Waiting for exact
-- arrival meant the slide never finished, and mask_input went on swallowing
-- the player's input until the ceiling - which is what "the character stops
-- responding at the edges, but the middle is fine" was. The middle is fine
-- because its two targets are 174 apart, wider than contact, so both really do
-- arrive.
--
-- Finish on either condition: close enough, or not moving any more. Not moving
-- covers being blocked by the partner and the camera refusing to follow.
local function toward(base, want)
  if arrived[base] then return true end
  local now = getx(base)
  local d = want - now
  if d <= STEP and d >= -STEP then
    setx(base, want)
    arrived[base] = true
    return true
  end
  if lastpos[base] == now then
    stuck[base] = (stuck[base] or 0) + 1
    if stuck[base] >= 4 then
      arrived[base] = true
      return true
    end
  else
    stuck[base] = 0
  end
  lastpos[base] = now
  if d > STEP then d = STEP else d = -STEP end
  setx(base, now + d)
  return false
end

local function run()
  if steps == nil then return end
  guard_frames = guard_frames - 1
  if guard_frames <= 0 then
    trace("  GAVE UP (180 frames) P1x=%d P2x=%d steps left=%d" .. "\n",
      getx(P1), getx(P2), #steps)
    steps = nil return
  end
  local s = steps[1]
  if s == nil then steps = nil return end
  if s.swap then
    local a, b = getx(P1), getx(P2)
    trace("  swap P1x=%d P2x=%d -> P1x=%d P2x=%d" .. "\n", a, b, b, a)
    setx(P1, b)
    setx(P2, a)
    table.remove(steps, 1)
    arrived = {}
    lastpos = {}
    stuck = {}
    return
  end
  local done = true
  for base, want in pairs(s.move) do
    if not toward(base, want) then done = false end
  end
  -- THE VIEW TRAVELS WITH THEM.
  --
  -- Left alone the camera chases at under seven pixels a frame, so a slide of
  -- any length finishes with the pair in place and the framing still on its
  -- way - the arrangement is right and the screen is not. Driven here it
  -- arrives with them. The step above is capped so this never has to move
  -- more than a tile at a time, which is all the background can be drawn in.
  --
  -- Skipped while a restore is running: that owns the camera and both
  -- characters already, and the two would pull against each other.
  if not camera_restore_busy() then
    camera_write(camera_for(getx(P1), getx(P2)))
  end
  if done then
    trace("  step done P1x=%d P2x=%d remaining=%d" .. "\n",
      getx(P1), getx(P2), #steps - 1)
    table.remove(steps, 1)
    arrived = {}
    lastpos = {}
    stuck = {}
    if steps[1] == nil then
      steps = nil
      trace("  finished P1x=%d P2x=%d" .. "\n", getx(P1), getx(P2))
    end
  end
end

-- HOTKEY 2 PLUS THE LEVER.
--
-- One rule: DOWN means "the special side is mine". At a wall that is the wall
-- itself; in the middle it is the 2P side. Six arrangements on six lever
-- positions, nothing else to remember.
--
--     <-      opponent at the left wall      |21------|
--     down+<- I am at the left wall          |12------|
--     (none)  middle, I am on the 1P side    |---12---|
--     down    middle, I am on the 2P side    |---21---|
--     ->      opponent at the right wall     |------12|
--     down+-> I am at the right wall         |------21|
--
-- THE CALLBACK DOES NOTHING BUT RAISE A FLAG.
--
-- A first attempt did the work inside the hotkey callback and took hotkey 1 -
-- the menu toggle, master script line 229 - down with it, which leaves the
-- tool unusable. An error thrown in that context stops the script, and every
-- other hotkey with it. So the callback sets a boolean and the frame handler,
-- where everything else already runs safely, does the rest a frame later. The
-- lever is still held by then.
local FIGURE = { "|12------|", "|21------|", "|---12---|",
                 "|---21---|", "|------12|", "|------21|" }
local figure_left = 0
local figure_shown = 3
local hotkey_pending = false
local traced_mode = nil

-- ONE HOLD IS ONE ARRANGEMENT.
--
-- FBNeo calls this for every frame the key is down, so a single press arrived
-- as hundreds. Measured with the trace: one session of a few presses ran
-- place() 698 times, and after the arrangement had finished each further
-- firing re-pinned the pair to the same two pixels and re-armed mask_input -
-- which swallows the player's own directions while a slide is live. The pair
-- was where it was asked to be and the lever did nothing, which is what
-- "Lua 2 and the character will not move left or right" was (user,
-- 2026-09-13).
--
-- A repeat is a firing on the frame after the last one. Releasing the key for
-- two frames is what makes the next press a press.
local last_hotkey_frame = nil

if input ~= nil and input.registerhotkey ~= nil then
  input.registerhotkey(2, function()
    -- Ignored until the match is actually running (see the master).
    if globals.hotkeys_armed ~= true then return end
    local f = emu.framecount()
    -- MEASURING THE REPEAT RATE, BECAUSE THE THRESHOLD WAS GUESSED.
    --
    -- Folding firings that are one frame apart did not fix it, so they are not
    -- one frame apart. The earlier probe counted 38 firings in what felt like
    -- about a second, which is nearer one every other frame - but "nearer" is
    -- not a measurement. Every firing and its gap goes in the log; the gap
    -- distribution is what the threshold should come from.
    trace("hotkey f=%d gap=%s pending=%s steps=%s" .. "\n",
      f,
      (last_hotkey_frame ~= nil) and tostring(f - last_hotkey_frame) or "first",
      tostring(hotkey_pending), (steps ~= nil) and tostring(#steps) or "nil")
    if last_hotkey_frame ~= nil and (f - last_hotkey_frame) <= 1 then
      -- Still the same hold. Keep the clock moving so the run of frames is
      -- seen as one, and do nothing else.
      last_hotkey_frame = f
      return
    end
    last_hotkey_frame = f
    hotkey_pending = true
  end)
end

-- READ THE PAD, NOT globals._input.
--
-- mask_input clears the directions in that table while a slide runs, and this
-- runs BEFORE the table is rebuilt for the frame - so a second press read the
-- directions it had just wiped and came back neutral every time. That is why
-- one edge to the other always stopped in the middle, and why left could not
-- be changed to down-left. joypad.get is the physical pad and knows nothing
-- about any of that.
local function lever_mode()
  local ok, j = pcall(joypad.get)
  if not ok or j == nil then j = globals and globals._input end
  if j == nil then return 3 end
  local d = j["P1 Down"] == true
  local l = j["P1 Left"] == true
  local r = j["P1 Right"] == true
  if l and not r then if d then return 1 else return 2 end end
  if r and not l then if d then return 6 else return 5 end end
  if d then return 4 end
  return 3
end

-- THE CAMERA.
--
-- 0xFF82A0 is where the camera keeps its X. 0xFF8290 is the copy it publishes
-- every frame - what cps2-hitboxes.lua reads to place its boxes, and what
-- anything else should read. Writing the copy achieves nothing, because the
-- game rebuilds it from the real one during the frame; writing the real one
-- moves the view immediately.
--
-- It is worth writing because the camera cannot be hurried any other way. It
-- chases the midpoint of the two characters at a hard 5 pixels per tick, so
-- putting the pair back in a single step leaves the framing up to a second
-- behind them - which is a scene that has not actually been reproduced.
--
-- Past 640 the game draws tiles that are not there and the background tears,
-- and below 256 the same the other way, so the value is kept inside the range
-- the game itself uses.
-- THE CAMERA.
--
-- 0xFF82A0 is where the camera keeps its X. 0xFF8290 is the copy it publishes
-- every frame - what cps2-hitboxes.lua reads to place its boxes, and what the
-- code that pens characters inside the visible window reads too. That pen runs
-- BEFORE the camera is rebuilt from the real one, so both have to be written:
-- move only the real one and any character placed outside the old window is
-- hauled back into it before the new window exists.
--
-- The camera heads for clamp((P1x + P2x) / 2 - 192, 256, 640), where 192 is
-- half the screen, and chases it at a hard 5 pixels per tick - about 6.7 a
-- displayed frame. Left alone, putting the pair back in one step leaves the
-- framing up to a second behind them, which is a scene that has not actually
-- been reproduced.
--
-- HOW FAR IT CAN BE MOVED AT ONCE, AND WHY.
--
-- Sixteen pixels a frame. Not a guess or a measurement - it is what the game
-- does, at 0x01E466:
--
--     move.w D0, ($20,A6)      the new camera X
--     tst.b  ($3,A6)
--     beq    ...
--     andi.b #$10, D0          bit 4 of it, and nothing else
--     move.b ($38,A6), D1      what bit 4 was last time
--     eor.b  D1, D0
--     bne    ...               unchanged? then nothing happens
--     eori.b #$10, ($38,A6)
--     move.b ($3b,A6), D0      which edge to draw
--     jsr    ...               and one column of tiles is drawn
--
-- A column is drawn when bit 4 of the camera flips, which is once every 16
-- pixels - one tile. The test is on a BIT, not on a distance, so moving 384
-- pixels in a frame still draws exactly one column and the other 23 are never
-- drawn at all. There is no catching up afterwards, because nothing remembers
-- that anything was missed.
--
-- Which is the whole story of the torn background: it never repaired however
-- long anyone waited, no combination of the six camera words made any
-- difference, and 128 pixels a frame tore just as thoroughly as 384. The
-- measurements agree exactly - a 16 pixel jump read at the noise floor and 32
-- was already above it.
--
-- So the full width of the stage takes 24 frames. The pair travels with the
-- camera so nothing is ever left outside the window, and the scene arrives
-- whole.
--
local CAM_PUBLISHED = 0xFF8290
local CAM_STATE     = 0xFF82A0
local CAM_MIN, CAM_MAX = 256, 640
local CAM_STEP_MAX  = 16            -- one tile: see the note above
local HALF_SCREEN   = 192
local WALL_MIN, WALL_MAX = 280, 1000

local function cam_sw(v)
  if v >= 0x8000 then return v - 0x10000 end
  return v
end

local function camera_read()
  return cam_sw(memory.readword(CAM_PUBLISHED))
end

-- Where the camera would end up if it were left to walk to the pair.
function camera_for(p1x, p2x)
  return math.floor((p1x + p2x) / 2) - HALF_SCREEN
end

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

-- One frame, for a move small enough not to need stepping.
function camera_write(v)
  if v == nil then return false end
  v = clamp(v, CAM_MIN, CAM_MAX)
  memory.writeword(CAM_STATE, v)
  memory.writeword(CAM_PUBLISHED, v)
  return true
end

-- A restore in progress: where the camera and the pair have to end up.
local restore = nil

-- THE PAIR TRAVELS WITH THE CAMERA.
--
-- Not "put them at the destination and let the camera catch up" - that leaves
-- them outside the window and the pen drags them somewhere else entirely. They
-- are held at whatever position keeps their FINAL place on screen, so the
-- whole scene slides across as one and lands exactly where it was recorded.
-- The full width of the stage is 24 steps. This only decides how long to keep
-- trying before putting the pair down and moving on.
local RESTORE_MAX_FRAMES = 60

local function camera_restore_start(cam, p1i, p1f, p2i, p2f)
  restore = { clamp(cam, CAM_MIN, CAM_MAX), p1i, p1f, p2i, p2f, frames = 0 }
end

function camera_restore_busy()
  return restore ~= nil
end

local function camera_restore_step()
  if restore == nil then return true end
  local r = restore
  -- The game moves the camera too, and if it ever pulled harder than this does
  -- the two would push against each other for ever - with the wizard waiting
  -- on a restore that never lands. Three frames is the real cost; this only
  -- decides how long to keep trying before putting the pair down and moving on.
  r.frames = r.frames + 1
  if r.frames > RESTORE_MAX_FRAMES then
    camera_write(r[1])
    memory.writeword(P1 + X, r[2])
    memory.writeword(P1 + X + 2, r[3])
    memory.writeword(P2 + X, r[4])
    memory.writeword(P2 + X + 2, r[5])
    restore = nil
    return true
  end
  local cur = camera_read()
  local d = clamp(r[1] - cur, -CAM_STEP_MAX, CAM_STEP_MAX)
  local now = cur + d

  memory.writeword(CAM_STATE, now % 0x10000)
  memory.writeword(CAM_PUBLISHED, now % 0x10000)

  -- Their final screen positions, held at every step along the way.
  local behind = r[1] - now
  memory.writeword(P1 + X, clamp(cam_sw(r[2]) - behind, WALL_MIN, WALL_MAX) % 0x10000)
  memory.writeword(P2 + X, clamp(cam_sw(r[4]) - behind, WALL_MIN, WALL_MAX) % 0x10000)
  if behind == 0 then
    -- Only on the last step, when the integers are exact anyway.
    memory.writeword(P1 + X + 2, r[3])
    memory.writeword(P2 + X + 2, r[5])
    restore = nil
    return true
  end
  return false
end

positionModule = {
  ["camera_read"]  = camera_read,
  ["camera_for"]   = camera_for,
  ["camera_write"] = camera_write,
  ["camera_restore_start"] = camera_restore_start,
  ["camera_restore_busy"]  = camera_restore_busy,
  ["camera_restore_step"]  = camera_restore_step,
  -- The lever that picks an arrangement also walks the character, so drop the
  -- directions while a slide is running. Called from just before joypad.set.
  -- HELD WHILE THE SLIDE RUNS, AND ONLY THEN.
  --
  -- The lever that picks an arrangement also walks the character. Buttons go
  -- too: a slide is about a second and an attack started halfway through it
  -- lands somewhere nobody meant.
  --
  -- Start and Coin are left alone deliberately. Coin is the tool's own
  -- controlling-side toggle and Start reaches the game's pause - neither
  -- should be swallowed by a repositioning. The FBNeo hotkeys are not in this
  -- table at all, so the menu on hotkey 1 is unaffected either way.
  ["mask_input"] = function(t)
    if steps == nil or t == nil then return end
    t["P1 Left"] = false
    t["P1 Right"] = false
    t["P1 Up"] = false
    t["P1 Down"] = false
    t["P1 Weak Punch"] = false
    t["P1 Medium Punch"] = false
    t["P1 Strong Punch"] = false
    t["P1 Weak Kick"] = false
    t["P1 Medium Kick"] = false
    t["P1 Strong Kick"] = false
  end,
  -- True once start_l/start_r describe the round on screen. The master gates
  -- the Lua hotkeys on this as well: acting on the menu before the round is
  -- set up is no better than sliding on it.
  ["round_ready"] = function() return have_start end,
  -- RE-PLACE THE PAIR AT THE CURRENT SETTING (user, 2026-09-21).
  --
  -- The menu row changes the setting to re-place, and the watcher above acts
  -- only on a CHANGE (mode ~= last_applied) - so returning to the arrangement
  -- already stored meant picking another one and back. Asked of the menu row
  -- directly: LP places again, HP places and closes the menu.
  --
  -- Off means leave everyone alone, so it does nothing. The same gates the
  -- hotkey path runs: not while the round is not under way or the wizard is
  -- up (slide_allowed), and not while a slide is already running - the
  -- arrangement on screen is the one just asked for. last_applied rides along
  -- so the settle watcher below does not re-place it a second time.
  ["reapply"] = function()
    local mode = globals and globals.options and globals.options.stage_position
    if mode == nil or mode == 1 then return false end
    if steps ~= nil or not slide_allowed() then return false end
    place(mode - 1)
    last_applied = mode
    pending_mode = nil
    run()
    return true
  end,
  ["figure"] = function()
    if figure_left <= 0 then return nil end
    figure_left = figure_left - 1
    return FIGURE[figure_shown]
  end,
  ["registerBefore"] = function()
    -- Ahead of everything else: a restore in progress owns both characters and
    -- the camera until it lands, and it has to run whatever else is going on.
    camera_restore_step()
    if globals == nil or globals.options == nil then return end
    watch_round_start()
    local mode = globals.options.stage_position
    if mode == nil then return end
    -- WHO CHANGES THE SETTING, AND WHEN.
    --
    -- The trace showed the hotkey doing its job: mode 2 built three steps and
    -- finished at 288/280, exactly |21------|. Then the pair was back at
    -- 400/700 with a place mode=3 that no hotkey asked for - the settle path
    -- re-applying a stored value and undoing the arrangement. The hotkey
    -- writes stage_position itself, so something else is writing it too, and
    -- this says what the value was before and after (user, 2026-09-13).
    if traced_mode ~= mode then
      trace("stage_position %s -> %s (last_applied=%s) P1x=%d P2x=%d" .. "\n",
        tostring(traced_mode), tostring(mode), tostring(last_applied),
        getx(P1), getx(P2))
      traced_mode = mode
    end
    -- The setting is saved between sessions, so on the very first frame it
    -- would read as a change and slide everybody the moment the game starts.
    -- Adopt whatever is stored without acting on it.
    if last_applied == nil then last_applied = mode return end
    if hotkey_pending and camera_restore_busy() then
      -- A restore lands within a couple of dozen frames, so hold the press
      -- rather than drop it. Dropping it here is what made the shortcut feel
      -- unresponsive: the press vanished and nothing happened.
    elseif hotkey_pending and not slide_allowed() then
      trace("press dropped, slide not allowed (armed=%s ready=%s)" .. "\n",
        tostring(globals.hotkeys_armed), tostring(have_start))
      -- Pressed before the round is under way, or during the wizard. Drop it
      -- rather than remember it: acting on it later, once the fight had
      -- started, would be a surprise.
      hotkey_pending = false
    elseif hotkey_pending and steps ~= nil then
      trace("  press dropped, slide still running" .. "\n")
      -- ONE PRESS IS NOT ONE CALLBACK.
      --
      -- FBNeo repeats a Lua hotkey for as long as the key is held: a probe
      -- registering all eight counted 38 firings of hotkey 2 in a session of
      -- a few presses, then 76 (measured 2026-09-12). Acting on every one of
      -- them called place() again every frame, and place() rebuilds the step
      -- list from scratch - so an arrangement that takes more than one step
      -- could never reach its second one.
      --
      -- That is exactly which arrangements were failing. The two that have to
      -- EXCHANGE the pair (the lever held left or right, from a start where
      -- the player is already on the left) are three steps; down+left from
      -- the same start is one, and that one worked. It looked like a lever
      -- problem and was a repeat-rate problem (user, 2026-09-12).
      --
      -- Dropped rather than queued. The arrangement already running is the
      -- one the player just asked for; a second one built from the same held
      -- lever would be the same arrangement again.
      hotkey_pending = false
    elseif hotkey_pending then
      hotkey_pending = false
      local m = lever_mode()
      place(m)
      figure_shown = m
      figure_left = 90
      globals.options.stage_position = m + 1
      last_applied = m + 1
      run()
      return
    end
    -- WAIT FOR THE LEVER.
    --
    -- Changing the setting means holding a direction, and that direction also
    -- walks the character - so a slide started on the keypress spends its
    -- whole length fighting the player's own input, and the exchange in
    -- particular just gets walked back. Start only once the setting has been
    -- left alone for a moment.
    if mode ~= last_applied then
      if mode ~= pending_mode then
        pending_mode = mode
        settle = 0
      else
        settle = settle + 1
        if settle >= SETTLE_FRAMES and slide_allowed() then
          trace("settle applies mode=%d (was last_applied=%s) P1x=%d P2x=%d" ..
            "\n", mode, tostring(last_applied), getx(P1), getx(P2))
          last_applied = mode
          pending_mode = nil
          place(mode - 1)
        end
      end
    end
    run()
  end,
}

return positionModule
