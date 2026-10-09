-- Pure game-tick frame-data state machine. This module deliberately has no
-- emulator, memory, GUI, or globals dependencies so its boundary rules can be
-- tested outside FBNeo.
local M = {}

local previous = nil
local last_tick = nil
local measurement = nil
local result = nil
local enabled = false
local last_abort = nil

local function bool(v) return v == true end

local function copy_state(s)
  return {
    tick = s.tick,
    p1 = {
      attack = s.p1.attack or 0,
      attack_box = bool(s.p1.attack_box),
      attack_box_id = s.p1.attack_box_id,
      anim = s.p1.anim,
      cel = s.p1.cel,
      airborne = bool(s.p1.airborne),
      air_normal = bool(s.p1.air_normal),
      status = s.p1.status or 0,
      hitfreeze = bool(s.p1.hitfreeze),
    },
    p2 = {
      status = s.p2.status or 0,
      state = s.p2.state,
      block_clock = s.p2.block_clock or 0,
      hitfreeze = bool(s.p2.hitfreeze),
      knockdown = bool(s.p2.knockdown),
    },
  }
end

local function abort(reason)
  measurement = nil
  last_abort = reason
end

-- ONE CEL RECORD. The stepper at 0x027F70 walks its own animation with
-- lea ($18,A0),A0, so a step of exactly this is the same move carrying on.
local CEL_SIZE = 0x18

local function start_measurement(tick, in_dash)
  measurement = {
    attack_start = tick,
    -- Whether the flag went up ON A DASH. Latched here rather than asked each
    -- tick: one of the two dash attacks measured leaves the dash state on the
    -- tick the attack starts, which is the very tick the question is about.
    started_in_dash = in_dash,
    reanchored = false,
    -- The span the attack hitbox is actually out, and the attacker's own
    -- hitfreeze inside and after it. Freeze stops the animation, so the box
    -- stays on screen for ticks the move did not advance through.
    active_start = nil,
    active_end = nil,
    attack_end = nil,
    -- Latched when the first box comes out: whether it came out as an airborne
    -- normal. Such a move ends on touchdown (see A JUMP NORMAL ENDS ON
    -- TOUCHDOWN in M.update).
    air_normal_box = false,
    -- Ticks the animation did NOT advance, inside the box span and after it.
    -- Hitstop is only one reason it can stand still, and an アニメ move does
    -- not stand still during hitstop at all - so this counts the standing
    -- still, not the hitstop.
    -- ONE ENTRY PER RUN OF BOX TICKS, NOT ONE SPAN.
    --
    -- A multi-hit move puts its box out, takes it away and puts it out again.
    -- Measured as a single span the gaps counted as active; kept as runs, the
    -- row can say 3 / 3 / 3 and the total is their sum (user, 2026-09-07).
    runs = {},
    run = nil,
    -- Still ticks since the last run closed. Thrown away when another run
    -- starts - they were a gap between hits, not recovery.
    still_gap = 0,
    still_total = 0,
    -- Advancing box ticks the attacker spent in hitstop. That IS the アニメ
    -- property: frames the move took while the world was stopped.
    anime = 0,
    first_contact = nil,
    last_contact = nil,
    kind = nil,
    contacts = 0,
    attacker_free = nil,
    attacker_was_stunned = false,
    -- Latched on the CONTACT tick only, and only if the attacker was an
    -- airborne normal then. Asked at that moment rather than later because a
    -- jump made after a grounded hit would otherwise reclassify it.
    air_normal_contact = false,
    defender_free = nil,
    p1_hf_after_first = 0,
    p2_hf_after_last = 0,
    p1_hf_total = 0,
    p2_hf_total = 0,
    candidate = nil,
    knockdown = false,
  }
end

local function note_contact(tick, kind)
  local m = measurement
  if not m then return end
  if m.first_contact == nil then m.first_contact = tick end
  m.last_contact = tick
  m.kind = kind
  m.contacts = m.contacts + 1
  m.defender_free = nil
  m.p2_hf_after_last = 0
  m.candidate = nil
end

local function complete()
  local m = measurement
  if not m then return end
  local atkrec = nil
  if m.first_contact ~= nil and m.attacker_free ~= nil
     and m.attacker_free >= m.first_contact then
    atkrec = m.attacker_free - m.first_contact - m.p1_hf_after_first
    if atkrec < 0 then atkrec = 0 end
  end
  -- A WHIFF HAS NO DEFENDER, AND THAT IS NOT A REASON TO REPORT NOTHING.
  --
  -- Startup, active, recovery and total come from the attacker's own boxes, so
  -- they are just as measurable when the move hits nothing. Only the two that
  -- describe the other player are missing.
  --
  -- Two things made this worth doing. Aborting left the PREVIOUS move's numbers
  -- on screen with nothing saying they were old - a crouching LK whiffed over a
  -- downed opponent and the throw before it stayed up, which reads as the tool
  -- being stuck. And a throw that CONNECTS ends its own window early: Midnight
  -- Bliss measured 23 active against the table's 29, because the check stops
  -- once it has grabbed. Whiffed, it runs the whole window
  -- (user, 2026-09-07).
  local hitstun = nil
  if m.defender_free ~= nil and m.last_contact ~= nil then
    hitstun = m.defender_free - m.last_contact - m.p2_hf_after_last
    if hitstun < 0 then hitstun = 0 end
  end
  -- A knockdown and a throw used to report nothing here, because "out of stun"
  -- is not "can act" for them. Now that free is measured to the actionable
  -- tick, both have a real answer and it is the one that matters: how long
  -- until the wake-up.
  local wakeup = m.knockdown or m.kind == "throw"
  -- STARTUP, ACTIVE AND RECOVERY COME FROM THE HITBOX, NOT FROM THE CONTACT.
  --
  -- Split the way a frame-data timechart splits it, so the three add up to the
  -- whole move:
  --
  --   startup   the move begins ($105) up to AND INCLUDING the tick the box
  --             first appears - the same thing 発生 counts on a frame-data
  --             table, so Demitri's close LP reads 4 and not 3
  --   active    the box is out, less the ticks the animation stood still
  --   recovery  the tick after the box goes, up to AND INCLUDING the tick the
  --             attacker can act again - the same thing 硬直 counts
  --   total     the whole move, less the ticks it stood still
  --
  -- Startup and active therefore SHARE the tick the box appears, exactly as a
  -- published table does (発生4 / 持続3 / 硬直7 against a 13 frame move), so
  -- total is one less than the three added up.
  --
  -- An adapter that cannot see the boxes leaves attack_box nil throughout; the
  -- old contact-based startup is kept for that case and the rest stay nil
  -- rather than being invented.
  local startup, active, recovery, total = nil, nil, nil, nil
  if m.active_start ~= nil and m.active_end ~= nil and m.attack_end ~= nil then
    startup = m.active_start - m.attack_start + 1
    active = 0
    for _, run in ipairs(m.runs) do active = active + run.adv end
    -- INCLUSIVE AT BOTH ENDS, LIKE STARTUP.
    --
    -- attack_end is the tick the attacker becomes actionable. Counting up to
    -- the tick BEFORE it read one short of every published table: measured
    -- against Demitri's close standing LP (発生4 / 持続3 / 硬直7, and the table
    -- is in ticks) startup and active matched and recovery came out 6.
    --
    -- The table counts the actionable tick as the last tick of 硬直, the same
    -- way 発生 counts the first active tick. Startup already follows that
    -- convention here, so recovery does too and the row is consistent - and
    -- total keeps its relation, 4 + 3 + 7 - 1 = 13 (user, 2026-09-07).
    recovery = (m.attack_end - m.active_end) - m.still_gap
    if startup < 0 then startup = 0 end
    if active < 0 then active = 0 end
    if recovery < 0 then recovery = 0 end
    -- The whole move, less the ticks it stood still. Not the three added up:
    -- a multi-hit move has gaps between its runs that are neither startup,
    -- active nor recovery, and they are part of the move.
    total = (m.attack_end - m.attack_start + 1) - m.still_total
  elseif m.first_contact ~= nil then
    -- No box to read. The old measure, on the same inclusive footing.
    startup = m.first_contact - m.attack_start + 1
  end
  -- Nothing to say at all: no box and no contact. Better to leave the previous
  -- reading up than to publish a row of dashes.
  if startup == nil then
    measurement = nil
    last_abort = "whiff"
    return
  end
  result = {
    startup = startup,
    active = active,
    recovery = recovery,
    total = total,
    attack_recovery = atkrec,
    hitstun = nil,
    advantage = nil,
    hitfreeze = m.p2_hf_total,
    attacker_hitfreeze = m.p1_hf_total,
    projectile_marker = m.p2_hf_total > 0 and m.p1_hf_total == 0,
    contact_kind = m.kind,
    -- The wait was a wake-up, not hit stun. Same measurement, different word.
    wakeup = wakeup or nil,
    contact_count = m.contacts,
    -- Advancing box ticks spent in hitstop - the アニメ property, measured
    -- rather than looked up. Zero on an ordinary move.
    -- ONE TICK IS NOT アニメ, PER RUN.
    --
    -- A run of exactly one is the CONTACT tick and nothing else: hitstop starts
    -- on the tick the hit lands and the step into it was taken before. The
    -- tables call アニメ two frames or more, so a lone one is dropped where it
    -- is counted rather than at the total - a nine-hit special came out as
    -- Anime 1 / 1 / 1 / ... purely from that (user, 2026-09-07).
    anime = (function()
      if m.active_start == nil then return nil end
      local n = 0
      for _, run in ipairs(m.runs) do
        if run.anime > 1 then n = n + run.anime end
      end
      return n
    end)(),
    -- One number per run of box ticks, so a multi-hit move reads 3 / 3 / 3.
    -- The table writes the same shape - Demitri's standing HP is 2(5)2(5)2 -
    -- and marks its アニメ column ○x3, so the anime count is per run too.
    active_runs = (function()
      if #m.runs == 0 then return nil end
      local out = {}
      for i, run in ipairs(m.runs) do out[i] = run.adv end
      return out
    end)(),
    anime_runs = (function()
      if #m.runs == 0 then return nil end
      local out = {}
      for i, run in ipairs(m.runs) do out[i] = (run.anime > 1) and run.anime or 0 end
      return out
    end)(),
  }
  result.hitstun = hitstun
  result.advantage = (m.defender_free ~= nil and m.attacker_free ~= nil)
    and (m.defender_free - m.attacker_free) or nil
  measurement = nil
  last_abort = nil
end

function M.reset(reason, clear_result)
  previous = nil
  last_tick = nil
  measurement = nil
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
  local attack_started = p.p1.attack == 0 and s.p1.attack ~= 0
  local attack_ended = p.p1.attack ~= 0 and s.p1.attack == 0
  local p1_stun_started = p.p1.status ~= 0x02 and s.p1.status == 0x02
  local p1_became_free = p.p1.status == 0x02 and s.p1.status == 0x00
  local p1_landed = p.p1.airborne and not s.p1.airborne
  local block_contact = s.p2.block_clock > p.p2.block_clock
  local entered_stun = p.p2.status ~= 0x02 and s.p2.status == 0x02
  -- A HIT ON THE REVERSAL TICK ITSELF (user, 2026-10-10).
  --
  -- A meaty that lands on the defender's reversal tick (Meaty Timing's +0t)
  -- finds $05 still at 2 from the wake-up, and it stays 2 into the hit stun:
  -- 10 of 10 such jump-ins in the logs went 0x02020400 -> 0x02020000 with no
  -- $05 = 0 between, while all 3 at +1t passed through it. The edge above never
  -- fired, the move was closed as a whiff, and Advantage and Hitstun read "--".
  -- The game's own strike confirmation (0x018230, the one Meaty Timing reads)
  -- did fire on every one of them. So a strike by the attacker on a defender in
  -- stun is a hit too - only while this measurement has no contact yet, so a
  -- multi-hit move still measures from its first hit as before, and only when it
  -- was not blocked.
  if not entered_stun and measurement ~= nil and measurement.first_contact == nil
     and s.p2.status == 0x02 and not block_contact
     and (s.p1.struck_body == true or s.p1.struck_proj == true) then
    entered_stun = true
  end
  local throw_contact = p.p2.status ~= 0x06 and s.p2.status == 0x06
  local p2_became_free = p.p2.status == 0x02 and s.p2.status == 0x00
  local throw_ended = p.p2.status == 0x06 and s.p2.status == 0x00
  -- ACTIONABLE, WHICH IS NOT THE SAME AS OUT OF STUN.
  --
  -- A knockdown and a throw both leave $05 long before the defender can do
  -- anything - what follows is the getting-up animation, which lives in $06.
  -- Both zero is the test the rest of the tool calls free, and it is the tick a
  -- wake-up reversal comes out on, so it is the same measurement the reversal
  -- machinery is already built around (user, 2026-09-07).
  --
  -- Only used where the ordinary stun edge cannot answer: a knockdown or a
  -- throw. An ordinary hit keeps the $05 edge it always had.
  local p2_can_act = (s.p2.state ~= nil)
    and (s.p2.status == 0x00 and s.p2.state == 0x00)
    and not (p.p2.status == 0x00 and p.p2.state == 0x00)

  -- A completed candidate belongs to the preceding tick. Publish it before a
  -- new attack can replace the measurement on this tick.
  if measurement and measurement.candidate
     and s.tick == measurement.candidate + 1
     and not block_contact and not entered_stun and not throw_contact then
    complete()
  end

  if attack_started then
    if measurement then abort("new_attack") end
    start_measurement(s.tick, s.p1.dash)
  end

  local m = measurement
  if m then
    if p1_stun_started then m.attacker_was_stunned = true end

    -- THE DASH IN FRONT OF A DASH ATTACK IS NOT THE ATTACK.
    --
    -- Zabel's dash raises the attack flag by itself and never drops it, so the
    -- dash attack that follows shares the interval the dash opened and reads
    -- as the dash's travel plus its own startup (user, 2026-09-08). Jedah's
    -- glide is the same shape - both are moves made INSIDE the dash state,
    -- which is why the flag cannot separate them (VSAV_MEMORY_NOTES.md 11).
    --
    -- ONLY WHILE NOTHING HAS COME OUT YET. That is what makes this a prefix
    -- and not a chain split: by the second move of a chain a box has been out,
    -- and re-anchoring THERE is what made the second hit measure as a whiff -
    -- the defender is already in stun so the contact edge never fires again.
    -- Before the first box nothing has been counted, so moving the anchor
    -- moves an anchor and nothing else.
    --
    -- ONCE, AND ONLY FOR A FLAG THAT WENT UP ON A DASH.
    --
    -- The boundary is the CEL POINTER leaving its own script. An earlier
    -- version read $10B instead, on 16 dash attacks that all connected; a whiff
    -- showed it never moves at all there, and a hit showed it moving two ticks
    -- after the hitbox (VSAV_MEMORY_NOTES.md). The animation says it on the
    -- tick the move actually changes, hit or not.
    --
    -- The dash is asked about the START of the measurement because half the
    -- dash attacks leave the dash state on that same tick. Bounded to before
    -- the first box, and to once, because an animation can also loop and a loop
    -- is a jump by this test.
    if m.started_in_dash and not m.reanchored and m.active_start == nil
       and s.p1.cel ~= nil and p.p1.cel ~= nil
       and s.p1.cel ~= p.p1.cel and s.p1.cel ~= p.p1.cel + CEL_SIZE then
      m.attack_start = s.tick
      m.still_total = 0
      m.reanchored = true
    end

    -- The box span. Counted before contact is established so the tick the box
    -- first appears is inside it whether or not it connected on that tick.
    -- nil anim means the adapter cannot see the animation; then nothing is
    -- taken off and the spans are raw.
    local _still = (s.p1.anim ~= nil and p.p1.anim ~= nil and s.p1.anim == p.p1.anim)
    if _still then m.still_total = m.still_total + 1 end
    if s.p1.attack_box then
      if m.active_start == nil then
        m.active_start = s.tick
        m.air_normal_box = bool(s.p1.air_normal)
      end
      m.active_end = s.tick
      -- A DIFFERENT BOX IS A DIFFERENT HIT.
      --
      -- Two hits can run back to back with the box never switching off, which
      -- the tables write with a middle dot rather than a bracket. Splitting on
      -- presence alone folded them into one number, so the id ends a run too.
      if m.run ~= nil and s.p1.attack_box_id ~= nil
         and m.run.id ~= nil and s.p1.attack_box_id ~= m.run.id then
        m.run = nil
      end
      if m.run == nil then
        m.run = { adv = 0, anime = 0, id = s.p1.attack_box_id }
        m.runs[#m.runs + 1] = m.run
        m.still_gap = 0
      end
      if not _still then
        m.run.adv = m.run.adv + 1
        -- Box ticks the attacker spent in hitstop: how many animation frames
        -- the move got through while the world was stopped. Demitri's crouching
        -- HK is four of them - 4 コマアニメ - and reads Active 4 (Anime 4).
        --
        -- A move that does NOT animate through hitstop picks up exactly one
        -- here, the CONTACT tick: hitstop starts on the tick the hit lands, and
        -- the step into that tick was taken before it. That one is the edge of
        -- the property rather than the property, and formatResult drops it by
        -- only writing two or more - the same line the tables draw
        -- (user, 2026-09-07).
        if s.p1.hitfreeze then
          m.anime = m.anime + 1
          m.run.anime = m.run.anime + 1
        end
      end
    else
      m.run = nil
      if m.active_start ~= nil and _still then m.still_gap = m.still_gap + 1 end
    end

    -- Establish contact before counting freeze so the contact tick itself is
    -- included, matching the legacy counter's order of operations.
    local _air_normal_now = false
    if throw_contact then
      note_contact(s.tick, "throw")
    elseif block_contact then
      note_contact(s.tick, "block")
      _air_normal_now = bool(s.p1.air_normal)
    elseif entered_stun then
      note_contact(s.tick, "hit")
      _air_normal_now = bool(s.p1.air_normal)
    end

    m = measurement
    if m and _air_normal_now then m.air_normal_contact = true end
    if m and s.p1.hitfreeze then
      m.p1_hf_total = m.p1_hf_total + 1
      if m.first_contact then m.p1_hf_after_first = m.p1_hf_after_first + 1 end
    end
    if m and s.p2.hitfreeze then
      m.p2_hf_total = m.p2_hf_total + 1
      if m.last_contact then m.p2_hf_after_last = m.p2_hf_after_last + 1 end
    end

    if m then
      -- A KNOCKDOWN BY THIS MOVE, NOT THE ONE THE DEFENDER IS GETTING UP FROM
      -- (user, 2026-10-10). $1A7 counts up while the defender is down and
      -- getting up (20..27 in the log) and is 0 from the hit on: a jumping LP on
      -- a waking Morrigan read Wakeup 14t because the flag was seen before the
      -- contact. Only from the contact tick on does it say this move knocked
      -- down. Her hit stun ended with $05 and $06 both 0 on the same tick, so
      -- the value is the same and the label is now Hitstun.
      if s.p2.knockdown and m.first_contact ~= nil then m.knockdown = true end
      if m.attacker_was_stunned then
        if p1_became_free and not m.attacker_free then m.attacker_free = s.tick end
      elseif m.air_normal_contact then
        -- TOUCHDOWN, NOT THE END OF THE LANDING MOTION.
        --
        -- The landing motion is cancellable into a grounded normal, so the
        -- first tick back on the ground is the first tick the attacker can do
        -- something. Waiting for $05 and $06 to go generally free counts the
        -- cancellable part as recovery and reports the move as more minus than
        -- it plays (user, 2026-09-09).
        if p1_landed and not m.attacker_free then m.attacker_free = s.tick end
        -- A floor, so a reading is never lost. Only reached if the move ends
        -- with the attacker already grounded and no touchdown edge was seen -
        -- nothing measured does that, and a measurement that never sets this
        -- never completes.
        if attack_ended and not m.attacker_free and not s.p1.airborne then
          m.attacker_free = s.tick
        end
      elseif attack_ended and not m.attacker_free then
        m.attacker_free = s.tick
      end
      -- A JUMP NORMAL ENDS ON TOUCHDOWN (user, 2026-10-10).
      --
      -- The rule above made Advantage end there; Recovery and Total still ran
      -- to $105 dropping, through the landing motion - four ticks of $105 = 1
      -- on the ground in the logs (cel 0x12C972), the very part that can be
      -- cancelled into a grounded normal. The cancellable part is not counted
      -- anywhere now: the touchdown tick is the move's last tick, counted the
      -- way the actionable tick always is. Frame Meter ends the move there too.
      -- Only a move whose box came out as an airborne normal, and only if it is
      -- still running at touchdown: one that ended in the air ends where it
      -- ended, and air specials keep their landing recovery, which is real.
      if m.air_normal_box and p1_landed and m.attack_end == nil then
        m.attack_end = s.tick
      end
      if attack_ended and m.attack_end == nil then m.attack_end = s.tick end

      if m.knockdown or m.kind == "throw" then
        -- Down or thrown: the wake-up is the wait, so free is the tick they can
        -- act. throw_ended is kept as the fallback for an adapter with no $06.
        if p2_can_act then m.defender_free = s.tick
        elseif s.p2.state == nil and throw_ended then m.defender_free = s.tick end
      elseif m.first_contact and p2_became_free then
        m.defender_free = s.tick
      end

      if attack_ended and not m.first_contact then
        -- The move is over and hit nothing. complete() reports whatever the
        -- boxes gave and leaves the rest empty; with no boxes either it drops
        -- the measurement from in there.
        m.attack_end = m.attack_end or s.tick
        m.attacker_free = m.attacker_free or s.tick
        complete()
      elseif m and m.first_contact and m.attacker_free and m.defender_free then
        m.candidate = s.tick
      end
    end
  end

  previous = copy_state(s)
  last_tick = s.tick
  return result and "updated" or (measurement and "measuring" or "idle")
end

function M.getResult() return result end
-- THE ACTIVE RUN THE BOX IS IN ON THE TICK JUST UPDATED, for Meaty Timing:
-- which run of this measurement (1-based) and how many advancing ticks of it
-- so far, the contact tick included when it advanced. Still ticks - hitstop the
-- move did not play through - are not in adv, the same count Active uses.
-- nil when nothing is being measured or no box is out this tick.
function M.currentRun()
  local m = measurement
  if m == nil or m.run == nil then return nil end
  return { index = #m.runs, adv = m.run.adv }
end
function M.getAbortReason() return last_abort end
function M.isMeasuring() return measurement ~= nil end

local function tick(v)
  if v == nil then return "--" end
  return tostring(v) .. "t"
end
local function adv(v)
  if v == nil then return "--" end
  if v == 0 then return "0t" end
  return string.format("%+dt", v)
end
function M.formatResult()
  local r = result
  if not r then return "" end
  local hf = tick(r.hitfreeze) .. (r.projectile_marker and "*" or "")
  -- TWO LINES. The first is the move: what it does on its own, in the order a
  -- frame-data table lists it. The second is what happened to the OTHER player,
  -- which is a different question and reads as one when it is on its own row.
  -- A multi-hit move shows one number per run of the box: 3 / 3 / 3.
  local act = tick(r.active)
  if r.active_runs ~= nil and #r.active_runs > 1 then
    act = table.concat(r.active_runs, " / ") .. "t"
  end
  -- anime is already zero on any run that only had the contact tick.
  if r.anime ~= nil and r.anime > 0 then
    local an = tick(r.anime)
    if r.anime_runs ~= nil and #r.anime_runs > 1 then
      an = table.concat(r.anime_runs, " / ") .. "t"
    end
    act = act .. " (Anime " .. an .. ")"
  end
  return "Startup " .. tick(r.startup)
    .. "  Active " .. act
    .. "  Recovery " .. tick(r.recovery)
    -- ADVANTAGE SITS WITH THE TOTAL, NOT WITH THE MOVE.
    --
    -- A nine-hit special fills the first line with its Active list and pushed
    -- Recovery and Advantage off the right of the screen. The second line is
    -- short whatever the move does, so the number most likely to be read is
    -- put where it will always be visible (user, 2026-09-07).
    .. "\n"
    .. "Total " .. tick(r.total)
    .. "  Advantage " .. adv(r.advantage)
    .. "  " .. (r.wakeup and "Wakeup " or "Hitstun ") .. tick(r.hitstun)
    .. "  Hitfreeze " .. hf
end

return M
