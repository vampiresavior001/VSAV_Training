-- THE ROUTE, WHICH IS A DIFFERENT QUESTION FROM THE MOVE.
--
-- tickData measures ONE ATTACK: from the tick the attack flag goes up to the
-- tick the attacker can act again. That is the right window for what a move
-- does and the wrong one for how the move was reached. A jumping overhead is
-- not five ticks away, it is a prejump plus a rise plus five ticks away, and
-- the number worth knowing is the sum (user, 2026-09-08).
--
-- A CLOCK, NOT A CHAIN OF STRETCHES.
--
-- This started out printing named lengths - Prejump 3t > Jump 26t > Startup 4t
-- - and the startup was already on the first row, so it was saying the same
-- thing twice. What a route is actually read for is WHEN: which button touched
-- on which tick, counted from the jump (user, 2026-09-09). So every entry is a
-- time, and a length is the reader's subtraction.
--
-- It also stops the model fighting the game. Two attacks in one jump were a
-- problem for stretches, which had to pick one; on a clock they are two points.
--
-- Same shape as tickData - a pure state machine fed snapshots, with no
-- emulator, memory, GUI or globals - and fed the very same snapshot, so the two
-- rows can never disagree about a tick.
--
-- JUMPS, DASHES AND SPECIALS. Walking has no route worth printing and would
-- rewrite the row on every step (user, 2026-09-08); a special is an action in
-- its own right and opens one (user, 2026-09-09).
local M = {}

local previous = nil
local last_tick = nil
local route = nil
local result = nil
local enabled = false
local last_abort = nil

local function bool(v) return v == true end

local function copy_state(s)
  return {
    tick = s.tick,
    p1 = {
      free = bool(s.p1.free),
      stunned = bool(s.p1.stunned),
      jump_state = bool(s.p1.jump_state),
      airborne = bool(s.p1.airborne),
      dash = bool(s.p1.dash),
      action = bool(s.p1.action),
      stance = s.p1.stance,
      attack_seq = s.p1.attack_seq,
      attack = s.p1.attack or 0,
      attack_box = bool(s.p1.attack_box),
      move_key = s.p1.move_key or 0,
      move_name = s.p1.move_name,
      button_name = s.p1.button_name,
      cel = s.p1.cel,
    },
    p2 = {
      status = s.p2.status or 0,
      block_clock = s.p2.block_clock or 0,
      hitstop = s.p2.hitstop or 0,
      guarding = bool(s.p2.guarding),
    },
  }
end

-- ONE CEL RECORD. The animation stepper at 0x027F70 walks its own script with
-- lea ($18,A0),A0, so a step of exactly this is the same move carrying on.
local CEL_SIZE = 0x18

-- HOW LONG A ROUTE MAY STAND STILL BEFORE IT IS OVER.
--
-- Zabel's dash command throw drops through neutral on its way out of the dash,
-- and ending the route on the first free tick cut the throw off the row - the
-- dash read as having simply stopped (user, 2026-09-09). A gap is not the end
-- of an action if the action carries on.
--
-- A NUMBER OF TICKS, which this project otherwise refuses to put in code. It is
-- here because it was asked for by that name, and because there is nothing in
-- RAM that says "this pause belongs to what came before" - the state is simply
-- neutral either way.
--
-- THE PLAYER SETS IT NOW (user, 2026-10-04): Trainer > Tick Data > Timeline
-- Cut (Free Ticks), handed in through set_gap every tick. This is the default
-- that row ships with and what anything it cannot read falls back to.
--
-- The end is still stamped at the FIRST free tick, so waiting costs the
-- reading nothing.
--
-- 15 first, 10 since 2026-09-10: the rows read as too joined-up (user). The
-- case it was picked for still fits - Zabel's dash command throw passes through
-- neutral for 6 ticks on its way out of the dash.
local GAP_TICKS = 10
local gap_ticks = GAP_TICKS

-- A whole number of Ticks, 0 or more. 0 ends the route on its first free tick,
-- the behaviour the gap was added to stop - allowed, because it is a choice
-- now and not a default. Anything else is the default, so a settings file with
-- a stray value cannot leave the row unable to end.
function M.set_gap(n)
  n = tonumber(n)
  if n == nil or n < 0 or n ~= math.floor(n) then n = GAP_TICKS end
  gap_ticks = n
end

local function abort(reason)
  route = nil
  last_abort = reason
end

-- ONE ENTRY PER THING THAT HAPPENED, IN ORDER, WITH THE TICK IT HAPPENED ON.
local function add(kind, tick, text, from_cel)
  route.events[#route.events + 1] =
    { kind = kind, tick = tick, text = text, from_cel = from_cel }
end

-- The move the row is currently talking about, or nil before the first one.
local function last_move()
  for i = #route.events, 1, -1 do
    if route.events[i].kind == "move" then return route.events[i] end
  end
  return nil
end

-- A THROW OUT OF A DASH IS NOT AN ATTACK THAT THEN THREW.
--
-- Bishamon's dash HP throw read 10t Dash > 17t HP > 25t Throw. The HP is the
-- throw's own animation: inside a dash a move is found by the animation leaving
-- its script, and a throw leaves it too. Naming it after the button that
-- started it says an HP came out, and none did (user, 2026-09-10).
--
-- Dropped rather than never added, because at 17t there is nothing to say it
-- was a throw - the grab is 8 ticks later. Only a move found from the animation
-- and with no contact of its own: a dash attack that connected and THEN threw
-- is two things that both happened.
local function drop_move_before_throw()
  local m, at = nil, nil
  for i = #route.events, 1, -1 do
    if route.events[i].kind == "move" then m, at = route.events[i], i break end
  end
  if m == nil or not m.from_cel then return end
  for i = at + 1, #route.events do
    if route.events[i].kind == "contact" then return end
  end
  m.dropped = true
end

local function has(kind)
  for _, e in ipairs(route.events) do
    if e.kind == kind then return true end
  end
  return false
end

-- The phases happen once each. A move or a contact can happen again.
local function add_once(kind, tick, text)
  if not has(kind) then add(kind, tick, text) end
end

-- ONCE PER TRIP THROUGH THE AIR, NOT ONCE PER ROUTE.
--
-- Air and Landing were once-per-route, so a jump taken out of the landing
-- recovery of the last one left no mark at all: the row read
-- 1t PreJump > 4t Air > 46t Landing > 102t Free for TWO jumps, and the second
-- one was invisible (user, 2026-09-10). A route is a sequence of things the
-- player did, and jumping again is one of them.
--
-- The two arm each other, and neither is driven by the PreJump entry. Holding
-- up jumps again the moment the character lands, and $06 never leaves 0x06
-- across that - so there is no rising edge to hang a re-arm on, and ten jumps
-- read as 1t PreJump > 4t Air > 45t Landing > 52t Air > 961t Free (user,
-- 2026-09-10). Leaving the ground and touching it are the edges that always
-- happen, so they are the ones that count.

local function complete(tick)
  local r = route
  add("end", tick, "Free")
  local events, contact_at = {}, nil
  for _, e in ipairs(r.events) do
    -- A DASH THAT NEVER PUT A BOX OUT DID NOT ATTACK.
    --
    -- Inside a dash the move is found by the animation leaving its script, and
    -- an animation can also LOOP - which looks the same. Demitri's dash loops,
    -- and his row read 1t Dash > 13t HK out of a dash he cannot even attack
    -- from (the frame table gives him no 攻撃前 at all). The name came from the
    -- strength bytes still holding the HK before it (user, 2026-09-09).
    --
    -- Asked at the end rather than at the time, because the box comes AFTER the
    -- move starts - that gap is the startup, and it is the thing worth showing.
    -- The box has to belong to THIS move, not to something later in the route:
    -- a phantom early in a dash was being kept alive by the real move's box
    -- forty ticks after it.
    -- Only the animation-found ones are checked; a move found by name said so
    -- itself. A dash command throw goes through the name (its state leaves
    -- 0x14) and so is not caught here, which is right - a throw has no box.
    local phantom = e.from_cel and not e.box_seen
    if not phantom and not e.dropped then
    -- ONE BASED. The first tick of the route is 1t, the way the frame tables
    -- count and the way tickData counts a startup.
    local at = e.tick - r.start + 1
    events[#events + 1] = { at = at, text = e.text, kind = e.kind }
    if e.kind == "contact" and contact_at == nil then contact_at = at end
    end
  end
  result = { events = events, contact_at = contact_at, total = tick - r.start + 1 }
  route = nil
  last_abort = nil
end

function M.reset(reason, clear_result)
  previous = nil
  last_tick = nil
  route = nil
  last_abort = reason
  enabled = false
  if clear_result then result = nil end
end

function M.update(s)
  if type(s) ~= "table" or type(s.tick) ~= "number"
     or type(s.p1) ~= "table" or type(s.p2) ~= "table" then
    abort("invalid_snapshot")
    return "aborted"
  end

  if not enabled then
    enabled = true
    previous = copy_state(s)
    last_tick = s.tick
    return "initialized"
  end
  if s.tick == last_tick then return "ignored" end
  if s.tick ~= last_tick + 1 then
    abort("tick_discontinuity")
    previous = copy_state(s)
    last_tick = s.tick
    return "aborted"
  end

  local p = previous

  -- WHERE A ROUTE STARTS, AND WHY NOT "LEFT NEUTRAL".
  --
  -- The tail of the previous action passes through another state on its way
  -- out, and starting there put six ticks of somebody else's recovery in front
  -- of the prejump. Starting on the jump state itself gives four every time
  -- (measured over seven jumps, 2026-09-08).
  local jump_started = s.p1.jump_state and not p.p1.jump_state
  local dash_started = s.p1.dash and not p.p1.dash
  -- ANY ACTION OPENS ONE, not just a jump or a dash (user, 2026-09-09). A
  -- standing normal, a special, Dark Force - each is something the player did.
  -- Nothing is printed for the opening except for a jump or a dash: everything
  -- else has a move name landing on the same tick, and that says it better than
  -- a label would.
  local action_started = s.p1.action and not p.p1.action
  -- WALKING AND CROUCHING COUNT TOO (user, 2026-09-09). They are not states in
  -- $06 - the adapter reads them off the lever - but they are things the player
  -- did, and a walk up to an attack is part of the route that reached it.
  local stance_started = s.p1.stance ~= nil and s.p1.stance ~= p.p1.stance
  -- A THROW OPENS ONE TOO. The grab is seen on the defender, and the thrower's
  -- own state does not always turn into an action first - a throw from standing
  -- was leaving no row at all (user, 2026-09-09).
  local throw_started = p.p2.status ~= 0x06 and s.p2.status == 0x06
  if route == nil and (jump_started or dash_started or action_started
     or stance_started or throw_started) then
    route = { start = s.tick, events = {}, from_dash = dash_started }
    if dash_started then add("start", s.tick, "Dash")
    elseif jump_started then add("start", s.tick, "PreJump") end
  end

  local r = route
  if r then
    -- THE ROUTE IS ABOUT WHAT THE ATTACKER DID, SO BEING HIT ENDS IT.
    --
    -- Getting caught out of a prejump leaves a route that never reached its
    -- attack. Printing the ticks up to the interruption as if they were the
    -- plan would be a reading of something nobody did.
    if s.p1.stunned and not p.p1.stunned then
      abort("attacker_hit")
      previous = copy_state(s)
      last_tick = s.tick
      return "aborted"
    end

    -- AIR, NOT JUMP. The entry means "the feet left the ground", which a jump
    -- is only one way to do: Sasquatch's ground dash is a 浮遊 type and is
    -- airborne from its first tick, so the row read 1t Dash > 1t Jump (user,
    -- 2026-09-09). Air says the fact instead of guessing at the cause, and
    -- reads right after PreJump as well.
    -- One entry per change of stance, so holding forward is one Walk and not
    -- one per tick. Cleared when the lever goes back to neutral so walking
    -- again says so.
    if s.p1.stance ~= r.stance then
      if s.p1.stance ~= nil then add("stance", s.tick, s.p1.stance) end
      r.stance = s.p1.stance
    end

    -- A SECOND JUMP INSIDE THE SAME ROUTE STILL SAYS SO.
    --
    -- The route's own first entry already named the jump that opened it, so
    -- this is only for the later ones. Landing recovery is not free, which is
    -- why a jump out of it lands inside the route that is already running.
    --
    -- ON THE GROUND, THOUGH. An air dash puts $06 at 0x14 and then hands it
    -- BACK to 0x06 when the attack comes out (measured 2026-09-10), so the
    -- jump state rises again in mid-air and the row printed a second PreJump
    -- on top of the attack: 30t Dash > 44t PreJump > 44t HP. A jump starts
    -- from the floor - the prejump is the tick before $38 goes up.
    --
    -- The landing tick counts as grounded too, and $06 comes back to 0x06
    -- there as well, which left one more: 31t Dash > 85t PreJump > 85t
    -- Landing. So the tick before has to be grounded as well - a jump is
    -- started by someone who was already standing there.
    -- UNTIL THE THROW IS OVER, NOT FOR THE REST OF THE ROUTE.
    --
    -- What the throw suppression is for is the tail of the throw itself: a kick
    -- throw lets go while the thrower is still playing it out, and the button
    -- that started it was being read as a move that came out afterwards.
    --
    -- Sasquatch's Big Branch throws and can then be comboed from, and the
    -- follow-up was disappearing (user, 2026-09-10). So the suppression ends
    -- where the throw does: the opponent is no longer held AND the thrower can
    -- act again. Both, because either alone is still inside the throw - the
    -- release comes first and the recovery runs on past it.
    if r.threw and s.p1.free and s.p2.status ~= 0x06 then
      r.threw = false
    end

    -- NOT WHILE A THROW IS PLAYING, WHICH IS THE RULE THE MOVES ALREADY FOLLOW.
    --
    -- "投げはいつ投げたかがわかればよく、あとその技が終わるまでの経過は不要"
    -- (user, 2026-09-09) - that is why what plays out inside a throw is not read
    -- as a new move. The phases were left out of it and a dash throw printed
    -- 40t Throw > 67t PreJump (user, 2026-09-10). Whatever the state bytes do
    -- inside the throw belongs to that one point.
    if jump_started and s.tick ~= r.start and not r.threw
       and not s.p1.airborne and not p.p1.airborne then
      add("jump", s.tick, "PreJump")
    end

    -- THE DASH COMES FIRST, BECAUSE IT IS WHAT LIFTS THE FEET.
    --
    -- Sasquatch's dash is a hop: $38 goes 0 -> 1 on the dash's own first tick
    -- (measured, three dashes on 2026-09-11). Both entries land on that tick,
    -- and the row printed 171t Air > 171t Dash - the effect ahead of its cause
    -- (user, 2026-09-10). Dash is added first so the pair reads in the order it
    -- happened.
    --
    -- EVERY DASH, NOT THE FIRST ONE.
    --
    -- Once-per-route again: a second dash printed nothing, so a dash MP into
    -- another dash MP read as 20t MP > 42t Landing > 46t Air > 77t Landing -
    -- the second dash and its attack both missing (user, 2026-09-10). Only the
    -- route's own opening tick is skipped, because that one already said Dash.
    if s.p1.dash and not p.p1.dash and not r.threw then
      if s.tick ~= r.start then add("dash", s.tick, "Dash") end
      -- The attack that comes out of THIS dash has not been seen yet.
      r.dash_move_seen = false
    end
    if s.p1.airborne and not p.p1.airborne and not r.threw then
      if not r.air_seen then
        add("airborne", s.tick, "Air")
        r.air_seen = true
      end
      r.land_seen = false
    end

    -- A DIFFERENT MOVE IS A DIFFERENT NAME.
    --
    -- The key is what the row prints - the button for a normal, the special's
    -- own id for a special - so the thing being compared and the thing being
    -- shown cannot drift apart. It is constant while a move plays, changes when
    -- another one starts, and does NOT move on the hit, which is where $10B
    -- went wrong (VSAV_MEMORY_NOTES.md). An animation looping does not change
    -- it either, and neither does leaving the ground - the two faults that made
    -- the cel pointer need three exclusions to be usable here.
    --
    -- Zero means no move is out. One move straight into another is one change
    -- and so one entry.
    --
    -- THE SAME BUTTON TWICE IS TWO ENTRIES, AND THE GAME COUNTS THEM.
    --
    -- A rapid-fire LP into LP keeps one key, so the name cannot say a second
    -- one started. $1B8 can: the ROM adds 1 to it at every entry that starts an
    -- attack, the rapid restart at 0x028F18 included, and nothing else touches
    -- it until the round ends. Details in the adapter, which owns the address.
    --
    -- INSIDE A DASH THE NAME CANNOT CHANGE, so the animation has to say it.
    -- A dash attack keeps $06 = 0x14 and the strength bytes never move (a dash
    -- LP reads 00/00 throughout), so there is no change to see. The cel
    -- pointer leaving its own script is the moment; the name is the button.
    -- The stepper walks with lea ($18,A0),A0, so anything but +0x18 came from
    -- outside it (VSAV_MEMORY_NOTES.md).
    --
    -- Entering a dash, leaving the ground and the route's own first tick all
    -- swap the animation too, and none of them is a move. Once only: a dash
    -- carries one attack, and anything after it has left 0x14 and is caught by
    -- the name instead.
    local body_changed = (s.p1.dash and not p.p1.dash)
      or (s.p1.airborne ~= p.p1.airborne) or s.tick == r.start
    local cel_jumped = s.p1.cel ~= nil and p.p1.cel ~= nil
      and s.p1.cel ~= p.p1.cel and s.p1.cel ~= p.p1.cel + CEL_SIZE
      and not body_changed
    -- NOTHING AFTER A THROW IS A NEW MOVE.
    --
    -- The animation of a throw is the throw, and a throw is entered with a
    -- button - so an empty jump into a throw printed 47t Throw > 51t HP >
    -- 104t HP, naming the throw's own animation after the button that started
    -- it as if a normal had come out (user, 2026-09-09).
    --
    -- Asking only whether the defender is still held was not enough: a kick
    -- throw lets go while the thrower is still playing it out, and the row came
    -- back as 158t Throw > 293t MK > 293t Hit. A throw is one point - the tick
    -- it caught - and the rest of it belongs to that point.
    -- The game's own count of attacks started. Used twice below: for a repeat
    -- of the same button, and for a second attack inside one dash.
    local seq_changed = s.p1.attack_seq ~= nil and p.p1.attack_seq ~= nil
      and s.p1.attack_seq ~= p.p1.attack_seq
    -- THE TICK THE GRAB LANDS IS STILL THE MOVE'S OWN TICK.
    --
    -- Asked of the PREVIOUS tick, not this one. Victor's 360 and 720 throws
    -- catch on the same tick the move starts - $06 goes to 0x0E (or 0x12 for
    -- the 720, which is an EX) and the opponent reads 0x06 on one and the same
    -- line of the trace (measured 2026-09-11). With this tick's grab as the
    -- test, the move that did the throwing was suppressed by its own throw and
    -- the row named nothing at all.
    --
    -- What the suppression is for is what plays out AFTER the catch, and the
    -- previous tick answers that just as well: from the tick after the grab
    -- onwards the opponent was already held.
    local thrown = p.p2.status == 0x06 or r.threw
    if thrown then
      -- nothing: the throw is playing
    elseif s.p1.move_key ~= 0 and s.p1.move_key ~= p.p1.move_key then
      add("move", s.tick, s.p1.move_name or "Attack")
      r.contact_done = false
    elseif s.p1.move_key ~= 0 and seq_changed then
      -- Same key, new count: the same move started again. The name is the same
      -- because it IS the same move - what changed is that this is another one.
      add("move", s.tick, s.p1.move_name or "Attack")
      r.contact_done = false
    elseif s.p1.dash and cel_jumped and not r.dash_move_seen then
      add("move", s.tick, s.p1.button_name or "Attack", true)
      r.dash_move_seen = true
      r.contact_done = false
    -- A SECOND ATTACK INSIDE THE SAME DASH.
    --
    -- "Once only" was written for the animation, which cannot tell a second
    -- attack from a loop. It also threw away a real one: Sasquatch's dash LP
    -- into MP printed only the LP (user, 2026-09-10). The state stays 0x14 for
    -- both, so the key never moves and the name cannot say it either.
    --
    -- THE BUTTON SAYS IT, AND $1B8 CANNOT - NOT IN THE AIR.
    --
    -- 0x028F0E tests $38 and branches past 0x028F18 when the character is off
    -- the ground, so an airborne chain never bumps the count. Sasquatch's dash
    -- IS airborne from its first tick, which is why counting attacks did not
    -- show his dash LP into MP either (user, 2026-09-10).
    --
    -- 0x028ED4 writes $102 and $101 before that test, on every path through, so
    -- the strength and family are the new attack's whether the feet are down or
    -- not. LP into MP moves $102 from 0 to 2. The count is kept as well: it
    -- covers a repeat of the SAME button, where the name cannot change.
    elseif s.p1.dash and r.dash_move_seen
       and (seq_changed or s.p1.button_name ~= p.p1.button_name) then
      add("move", s.tick, s.p1.button_name or "Attack")
      r.contact_done = false
    end
    -- Marked on the move that is out RIGHT NOW, not on the route: a box that
    -- belongs to a later move says nothing about an earlier one.
    if s.p1.attack_box then
      local _m = last_move()
      if _m ~= nil then _m.box_seen = true end
    end

    -- CONTACT, IN THE ORDER THE SIGNALS CAN BE TRUSTED.
    --
    -- The first three are the edges tickData reads, and they name what kind of
    -- contact it was. The fourth only says THAT one happened: the defender's
    -- hitstop is slammed back up by a hit even when they are already in stun,
    -- which is the case the $05 edge cannot see and the case a jump-in during
    -- a combo always is. Guard was not in the trace that found it, so it is
    -- asked last - the block clock keeps naming blocks.
    -- ONCE PER MOVE. What is wanted is what touched and when, not how many
    -- times it went on touching: an ES Demon Cradle filled the row with nine
    -- Hits and buried everything else (user, 2026-09-09). The count is on the
    -- first row already, as the Active list.
    local _kind = nil
    -- Whether one happened, and separately what it was. The block clock is kept
    -- as a trigger because it can move on a tick nothing else does; the NAME
    -- comes from the defender's recovery kind, which is the only thing that
    -- told hit and guard apart in practice.
    local _grabbed = p.p2.status ~= 0x06 and s.p2.status == 0x06
    local _touched = _grabbed
      or (s.p2.block_clock > p.p2.block_clock)
      or (p.p2.status ~= 0x02 and s.p2.status == 0x02)
      or (s.p2.hitstop > p.p2.hitstop)
    if _touched then
      if s.p2.status == 0x06 then _kind = "Throw"
      elseif s.p2.guarding then _kind = "Guard"
      else _kind = "Hit" end
    end
    -- A GRAB IS NEVER "THE SAME MOVE TOUCHING AGAIN".
    --
    -- Once per move is right for hits, and wrong for a throw: a light attack
    -- guarded and then a throw showed only the guard, because the throw's own
    -- move entry is suppressed while the defender is held and so never cleared
    -- the flag (user, 2026-09-09). The two rules were fighting each other.
    -- THE DEFENDER'S RECOVERY KIND CAN BE A TICK LATE.
    --
    -- The first attack of a chain came out as Hit while the rest read Guard
    -- (user, 2026-09-09): $140 is not always written on the same tick $05
    -- enters stun. The last contact is held for one tick and corrected if it
    -- turns out to be a guard. A real hit never starts guarding afterwards, so
    -- this can only fix, never spoil. Resolved before the new contact is
    -- looked at, so two contacts on consecutive ticks both get their tick.
    if r.pending ~= nil and s.tick > r.pending_tick then
      if s.p2.guarding then r.pending.text = "Guard" end
      r.pending = nil
    end
    if _kind ~= nil and (_grabbed or not r.contact_done) then
      -- Before the contact is added, so "no contact of its own" is asked of
      -- what was there before this one.
      if _kind == "Throw" then drop_move_before_throw() end
      add("contact", s.tick, _kind)
      r.contact_done = true
      if _kind == "Throw" then
        r.threw = true
      else
        r.pending = r.events[#r.events]
        r.pending_tick = s.tick
      end
    end

    if (not s.p1.airborne) and p.p1.airborne and not r.threw then
      if not r.land_seen then
        add("land", s.tick, "Landing")
        r.land_seen = true
      end
      -- Back on the ground: the next takeoff is a new trip, whether or not a
      -- PreJump was seen for it.
      r.air_seen = false
    end

    -- A pause, not necessarily the end. Held open for gap_ticks in case the
    -- action continues out of it; cleared the moment it does.
    -- Standing still, not merely able to act: a walk is free by $05 and $06 and
    -- would otherwise end its own route fifteen ticks into itself.
    if s.p1.free and s.p1.stance == nil then
      if r.free_at == nil then r.free_at = s.tick end
      if s.tick - r.free_at >= gap_ticks then complete(r.free_at) end
    else
      r.free_at = nil
    end
  end

  previous = copy_state(s)
  last_tick = s.tick
  return "measured"
end

function M.getResult() return result end
function M.getAbortReason() return last_abort end

-- ONE ROW, BUILT SO IT CAN BE BROKEN.
--
-- hud.lua wraps on the double space between fields and never inside one, so a
-- route with seven entries is wider than the screen and a row joined with a
-- bare arrow could not be broken at all - it would run off the right edge. The
-- arrow rides at the END of each field instead, so a wrapped line still says it
-- continues.
-- LIVE, NOT ONLY WHEN IT IS OVER.
--
-- The row used to appear when the route closed, which is ten ticks after the
-- last thing happened - long enough that the reading felt disconnected from the
-- action that produced it (user, 2026-09-10). Each entry is already stamped the
-- tick it was confirmed, so showing the ones confirmed so far costs nothing and
-- is not a guess about what comes next.
--
-- The finished route stays up while the next one has nothing in it yet, so the
-- row does not blink out between actions. A Hit that turns out to be a Guard
-- corrects itself a tick later; that is the same one-tick grace the label has
-- always had, now visible.
function M.formatResult()
  local r = result
  if route ~= nil and #route.events > 0 then r = route end
  if not r or #r.events == 0 then return "" end
  local out = {}
  for _, e in ipairs(r.events) do
    -- A finished route carries the time it already worked out; one still
    -- running is measured from its own start, the same one-based count.
    -- A phantom dash move is not filtered here - that test needs the end of
    -- the route, so a route being watched live can show one and then drop it.
    -- A dropped one is different: it is already known not to have happened.
    if not e.dropped then
      local at = e.at or (e.tick - r.start + 1)
      out[#out + 1] = tostring(at) .. "t " .. e.text
    end
  end
  return table.concat(out, " >  ")
end

return M
