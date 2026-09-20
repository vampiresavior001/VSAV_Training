-- VSAV RAM adapter for tickData.lua. Read-only by design.
local M = {}
local P1 = 0xFF8400
local P2 = 0xFF8800
-- WHICH SIDE IS BEING MEASURED, AND WHICH IS THE OTHER ONE.
--
-- THE SNAPSHOT KEYS DO NOT MEAN PLAYER ONE AND PLAYER TWO. p1 is whoever is
-- being measured and p2 is their opponent - which is what the two readers have
-- always asked for: p1 carries the fields describing an action, p2 carries the
-- seven that say what was done TO them (block clock, guarding, hitstop,
-- knockdown). Swapping the bases below therefore measures the other player
-- with nothing changed downstream: tickData.lua and actionRoute.lua contain no
-- addresses at all.
--
-- Everything that has to know a side reads these, the throw hook included - it
-- is registered once when the module loads and so cannot hold a constant.
local ATK, DEF = P1, P2
local ATK_KEY = "P1"
-- 32 objects of 0x100 bytes. A fireball, Demitri's bats, anything the move
-- spawns rather than swings.
local PROJ = 0xFF9400
local PROJ_COUNT = 32
local snapshot = { p1 = {}, p2 = {} }

-- IS THE ATTACK HITBOX OUT THIS TICK?
--
-- The same read the hitbox display makes, so what the readout counts is what
-- the boxes on screen show: cps2-hitboxes.lua describes VSAV's attack box as
-- anim_ptr 0x1C, id_ptr 0x0A, and treats id 0 as "no box". $1C is the pointer
-- to the current animation cel; +0x0A in that cel is the attack box id.
--
-- Startup used to end at the first CONTACT, which made it depend on how far
-- away the opponent was standing and produced nothing at all on a whiff.
-- Returns the box ID, or 0 for no box. The ID matters as well as the presence:
-- two hits can be back to back with the box never going away - the table writes
-- that with a middle dot (Demitri's standing HK is 6・10, against 2(5)2(5)2 for
-- his standing HP, where the brackets are real gaps). What changes between them
-- is which box is out.
local function attack_box(base)
  local cel = memory.readdword(base + 0x1C)
  if cel == nil or cel == 0 then return 0 end
  return memory.readbyte(cel + 0x0A)
end

-- THE THROW BOX IS NOT IN RAM, BUT THE CHECK RUNS EVERY TICK IT IS OUT.
--
-- The attack box id is animation data the stepper copies into the object every
-- tick, so it can be read. The throw box id is not: it is a literal in the
-- character's own script. Demitri's moving command throw is the shape:
--
--   030AC4  move.b #$1e, ($26,A6)     30 ticks
--   030ADE  subq.b #1, ($26,A6)       one off per tick
--   030AEA  add.l  D0, ($10,A6)       advance
--   030AEE  moveq  #$39, D0           throw box id
--   030AF0  jsr    $2947e.l           attempt it, EVERY TICK
--
-- 30 against the table's 持続 29. So the check IS the window, and hooking it is
-- the way to measure it.
--
-- LATCHED, NOT TIME-STAMPED. The first attempt compared the tick counter the
-- hook saw against the one capture saw, which reads as order-independent and is
-- not: the hook runs inside the state dispatch and capture runs from the ticker
-- subscription, so capture usually sampled the tick before. That is why Midnight
-- Bliss reported one active tick instead of twenty-nine (user, 2026-09-07).
--
-- SAFE TO HOOK. cps2-hitboxes.lua lists 0x029450 among its breakpoints but its
-- registerexec call is commented out, so nothing is registered on this routine.
-- The tool's own hooks are 0x02211A and 0x0221CC.
local throw_seen = false
if memory ~= nil and memory.registerexec ~= nil then
  memory.registerexec(0x029406, function()
    -- The measured side only. A6 is the object attempting the throw.
    local _a6 = memory.getregister and memory.getregister("m68000.a6")
    if _a6 ~= ATK then return end
    throw_seen = true
  end)
end

-- THE DAMAGE IS NOT ALWAYS ON THE ATTACKER.
--
-- A projectile is its own object with its own animation, so the player's cel
-- carries no attack box at all and the move measured as nothing - reported for
-- Demitri's Demon Billion, where the bats do the hitting (user, 2026-09-07).
--
-- Same read as the player: cps2-hitboxes.lua gives vsav no hitbox_ptr, so a
-- projectile's box comes from $1C -> +0x0A exactly like the player's.
--
-- OWNERSHIP IS RECORDED BY THE GAME. Every object-spawn path writes the
-- creator into $30 of the new object:
--
--   020A18  394E 0030    move.w  A6, ($30,A4)
--
-- so a projectile belongs to P1 when its $30 is P1's base. Eight spawn sites,
-- all the same shape.
--
-- Active when readword(base) > 0x0100 and readbyte(base + 4) == 0x02, which is
-- the test the hitbox display uses.
local function projectile_box()
  for i = 0, PROJ_COUNT - 1 do
    local b = PROJ + i * 0x100
    if memory.readword(b) > 0x0100 and memory.readbyte(b + 0x04) == 0x02
       and memory.readword(b + 0x30) == (ATK % 0x10000) then
      local id = attack_box(b)
      -- Kept apart from the player's own ids (0..0xFF) and from the throw
      -- sentinel, so a run splits when the source changes rather than when two
      -- unrelated boxes happen to share a number.
      if id ~= 0 then return 0x200 + id end
    end
  end
  return 0
end

-- The character's own name for a special, or a plain label when the registry
-- is not up yet. charMoves rebuilds globals.char_moves every frame; nothing is
-- cached here because the character can change under it.
--
-- display_name WINS. The row says what the player just did, and it should say
-- it the way Action Steps does - the registry's own name is the key that saved
-- steps and the reversal list are built on, and a few of those keys are not
-- what the move is called (user, 2026-09-10: a dash Demon Cradle read as
-- Dash DP, which is the id's name and appears nowhere in the editor).
local SPECIAL_KIND = { [0x0E] = "SP", [0x10] = "ES", [0x12] = "EX" }

-- THE SAME WORDS ACTION STEPS USES.
--
-- The registry name and the name on a step are not the same for 32 of the 128
-- moves the editor offers: Bishamon's Bricks is Enma Seki there, Anakaris's
-- Hands is Mummy Drop, Demitri's Ground Chaos Flare is Chaos Flare. Reading
-- one name on the row and picking another in the editor is the complaint this
-- answers (user, 2026-09-11).
--
-- seq_special_list is what the editor builds its rows from, so asking it is
-- asking the editor. Moves it does not offer - pursuits, taunts, the easter
-- eggs - keep the registry name; there is no step to agree with.
--
-- Cached per character. The list is rebuilt from static tables, and a special
-- is named on every tick one is out.
local label_cache_cid, label_cache = nil, nil
local function step_label(name)
  if seq_special_list == nil then return nil end
  local cid = memory.readbyte(ATK + 0x382)
  if cid ~= label_cache_cid then
    label_cache_cid, label_cache = cid, {}
    local rows = seq_special_list(cid)
    if rows ~= nil then
      for _, m in ipairs(rows) do
        if m.name ~= nil then label_cache[m.name] = m.label or m.name end
      end
    end
  end
  return label_cache[name]
end

local function special_name(id)
  local reg = globals and globals.char_moves and globals.char_moves[ATK_KEY]
  local list = reg and reg.all
  if type(list) == "table" then
    for _, mv in ipairs(list) do
      if mv.value == id and mv.name then
        return step_label(mv.name) or mv.display_name or mv.name
      end
    end
  end
  return nil
end

-- One bit of a byte, without the bit library: the adapter's tests run in plain
-- Lua and b is always a power of two here.
local function held_bit(v, b)
  return (math.floor(v / b) % 2) == 1
end

-- FLIP THE SIDE. TRUE WHEN IT ACTUALLY MOVED.
--
-- The caller resets the two readers on a true, because a route that is half one
-- player and half the other is worse than no route: it reads as one action that
-- nobody performed.
--
-- The label cache is left alone on purpose. It is keyed on the character id and
-- built from nothing else, so it is already right for whichever side asks - a
-- mirror match shares the entry and any other pairing rebuilds on the first
-- lookup.
function M.set_side(side)
  local _p2 = side == "P2" or side == 2
  local _atk = _p2 and P2 or P1
  if _atk == ATK then return false end
  ATK, DEF = _atk, (_p2 and P1 or P2)
  ATK_KEY = _p2 and "P2" or "P1"
  -- A throw latched by the side being left is not this side's move.
  throw_seen = false
  return true
end

function M.side() return ATK_KEY end

function M.capture(tick)
  snapshot.tick = tick
  snapshot.p1.attack = memory.readbyte(ATK + 0x105)
  -- The cel pointer itself, not just the box id inside it: where it points is
  -- what says which move is playing.
  local _cel = memory.readdword(ATK + 0x1C) or 0
  local _box = attack_box(ATK)
  -- The attacker's own box first, then the throw it is offering, then whatever
  -- it has put on the screen. A move is one of the three.
  if _box == 0 then _box = projectile_box() end
  if _box == 0 and throw_seen then
    -- A throw has no attack box, so it borrows an id of its own. Runs, startup
    -- and active then work unchanged.
    _box = 0x100
  end
  -- Read and cleared here, so whichever of the hook and this runs first in a
  -- tick, the answer is "was there a check since the last capture".
  throw_seen = false
  snapshot.p1.attack_box = _box ~= 0
  snapshot.p1.attack_box_id = _box
  -- DID THE ANIMATION ADVANCE THIS TICK?
  --
  -- Not the same question as "is $5C set". A move the frame-data tables mark
  -- アニメ (pink on the timechart - Demitri's crouching HK) keeps animating
  -- through hitstop, so its hitstop ticks are real progress; an ordinary move
  -- stands still. Measured on both: the LP's box was out 14 ticks with 11 of
  -- them frozen, the HK's box was out exactly its 4 active ticks while $5C was
  -- set the whole time.
  --
  -- $20 is the current cel's remaining ticks and the stepper at 0x027F70 takes
  -- one off every tick it runs; $1C is the cel pointer, which moves when a cel
  -- is exhausted. Together they change on exactly the ticks the animation
  -- advanced, which is what "active" and "recovery" are counted in.
  snapshot.p1.anim = memory.readbyte(ATK + 0x20) * 0x10000 + (_cel % 0x10000)
  snapshot.p1.status = memory.readbyte(ATK + 0x005)
  -- THE ROUTE'S MILESTONES, AS BOOLEANS.
  --
  -- actionRoute is game-agnostic, so the $06 values stay on this side. Traced
  -- over jumps and dashes on 2026-09-08 (VSAV_MEMORY_NOTES.md):
  --
  --   0x06 is the jump, and it does NOT change on takeoff - $38 is what
  --        separates the prejump from the float.
  --   0x14 is the dash, and an attack made out of one keeps the flag the dash
  --        already raised.
  --   both bytes zero is free, which is where a route starts and ends.
  --   0x02 is being hit, which ends a route without a reading.
  local _state = memory.readbyte(ATK + 0x006)
  snapshot.p1.jump_state = _state == 0x06
  snapshot.p1.free = snapshot.p1.status == 0x00 and _state == 0x00
  snapshot.p1.stunned = snapshot.p1.status == 0x02
  snapshot.p1.airborne = memory.readbyte(ATK + 0x038) ~= 0
  -- 0x0E / 0x10 / 0x12 are 必殺技 / ES / EX. A special is an action in its own
  -- right, so a route can begin on one (user, 2026-09-09) - it does not have to
  -- be reached through a jump or a dash.
  snapshot.p1.special = _state == 0x0E or _state == 0x10 or _state == 0x12
  -- ANY ACTION CAN OPEN A ROUTE (user, 2026-09-09).
  --
  -- The states that are something the player DID: jump, normal, the three
  -- special tiers, dash, Dark Force. Left out on purpose - 0x00 待機 and
  -- 0x04 自由になる直前 are the tail of something else, 0x02 やられ and 0x0C
  -- ガード are what was done TO them, 0x08 turned up only while landing.
  --
  -- Walking is not in the list either. It has its own state (0x04, measured
  -- below), but it is reported through stance, not as an action - otherwise
  -- every step would open a route, which is why this was held to jumps and
  -- dashes in the first place.
  -- WALKING AND CROUCHING ARE THE LEVER PLUS A GROUNDED STATE.
  --
  -- Crouching holds $06 at 0x00. WALKING DOES NOT: it sits at 0x04, which this
  -- file used to write off as the tail of a previous action. Measured over the
  -- 2026-09-10 traces, $06 = 0x04 appears on 580 ticks, all of them grounded,
  -- and 569 of those have a direction held on the lever. Only 11 have the lever
  -- centred, which is the tail case. So 0x04 is the walk, and requiring a lever
  -- bit is what keeps the other 11 out.
  --
  -- Read only on the ground and only while nothing else is running - holding
  -- forward during a move is not walking.
  --
  -- $125, NOT $122. The first attempt read $122 and nothing ever came out of
  -- it: that byte is the BUTTONS (inputHistory.lua's own map says bit0 LP,
  -- bit1 MP, bit2 HP, bit4 LK, bit5 MK, bit6 HK), and it read 00 on all 859
  -- lines of the trace (user, 2026-09-09).
  --
  -- inputHistory.lua had already measured which byte to use, and why not the
  -- obvious neighbour: $123 carries the same layout but flickers between the
  -- two horizontal bits every frame while facing one way (20.3% of frames
  -- against 4.2%, 83% reconstruction against 99.9%). $125 is the stable one.
  --
  -- The bits are stored RELATIVE TO FACING, which is why that module has to
  -- swap them back to left/right for display. bit2 is down, and down wins over
  -- a diagonal, so crouch-forward is a crouch.
  --
  -- FORWARD AND BACK CAME OUT THE WRONG WAY ROUND ON SCREEN (user, 2026-09-10)
  -- and the row now says Walk for both, which is what was asked for. Which bit
  -- is really forward is therefore UNRESOLVED - do not copy the mapping below
  -- into anything that has to know the direction without measuring it first.
  -- inputHistory.lua reads the same byte and swaps by facing for display; if
  -- the polarity here is wrong, that module is worth re-checking too.
  snapshot.p1.stance = nil
  if snapshot.p1.status == 0x00 and not snapshot.p1.airborne
     and (_state == 0x00 or _state == 0x04) then
    local _lever = memory.readbyte(ATK + 0x125)
    if held_bit(_lever, 0x04) then snapshot.p1.stance = "Crouch"
    elseif held_bit(_lever, 0x01) or held_bit(_lever, 0x02) then
      snapshot.p1.stance = "Walk"
    end
  end

  snapshot.p1.action = _state == 0x06 or _state == 0x0A or _state == 0x0E
    or _state == 0x10 or _state == 0x12 or _state == 0x14 or _state == 0x16
  -- AN AIRBORNE NORMAL, WHICH IS THE ONE THAT CAN CANCEL ITS LANDING.
  --
  -- A jump attack's landing motion is cancellable into a grounded normal, so
  -- counting it as recovery reports the attacker as more minus than they are:
  -- they can cancel the landing and beat what the numbers say beats them
  -- (user, 2026-09-09).
  --
  -- 0x06 is the jump and 0x0A is the normal attack, and BOTH happen airborne.
  -- Measured over nine airborne contacts: $06 was 0x06 eight times and 0x0A
  -- once. Specials are excluded on purpose - 0x0E / 0x10 / 0x12 are 必殺技 / ES
  -- / EX and their landing recovery is real, not something to cancel out of.
  -- WHAT MOVE IS THIS, AS A NAME AND AS SOMETHING TO COMPARE.
  --
  -- Both halves were already in the tree.
  --
  -- A normal is named by its button: $102 is the strength (0 / 2 / 4 = light /
  -- medium / heavy) and $101 is the family (0 punch, otherwise kick). That
  -- pairing comes out of the rapid-fire chain analysis (VSAV_MEMORY_NOTES.md)
  -- and all six combinations were seen in the trace, each with its own box.
  --
  -- A special is named by $106 through charMoves.lua, which carries the id ->
  -- name table for every character ("PL1 (MO) FF8506" in its comments is this
  -- byte). globals.char_moves is rebuilt every frame by the master script.
  --
  -- WHEN IS A MOVE OUT AT ALL? $06 = 0x0A is a grounded normal. In the air the
  -- state stays 0x06 whether or not anything came out, so the attack flag is
  -- what separates a jump attack from a jump (measured: plain jumps carry
  -- $105 = 0 the whole way). A dash raises the flag by itself, but its state is
  -- 0x14 and so falls through to nothing, which is right - the dash is not a
  -- move.
  -- The button, always. Inside a dash the state stays 0x14 and the strength
  -- bytes never move (measured: a dash LP reads 00/00 before, during and
  -- after), so the name is right but the CHANGE cannot be seen - the route
  -- falls back to the animation for the moment, and takes the name from here.
  local _s = memory.readbyte(ATK + 0x102)
  local _f = memory.readbyte(ATK + 0x101)
  snapshot.p1.button_name = (({ [0] = "L", [2] = "M", [4] = "H" })[_s] or "?")
    .. ((_f == 0) and "P" or "K")
  local _name, _key = nil, 0
  if _state == 0x0A or (_state == 0x06 and snapshot.p1.attack ~= 0) then
    _name = snapshot.p1.button_name
    _key = 0x10000 + _s * 0x100 + _f
  elseif _state == 0x0E or _state == 0x10 or _state == 0x12 then
    local _id = memory.readbyte(ATK + 0x106)
    _key = 0x20000 + _state * 0x100 + _id
    _name = special_name(_id) or SPECIAL_KIND[_state]
  end
  snapshot.p1.move_name = _name
  -- Opaque to the reader: only ever compared with itself, so a change is a
  -- different move and nothing else is claimed.
  snapshot.p1.move_key = _key

  -- HOW MANY ATTACKS HAVE BEEN STARTED. $1B8 (word).
  --
  -- The key above cannot see a rapid-fire LP into LP: same button, same key,
  -- one entry. This counter can, and it is the game's own.
  --
  -- The ROM adds 1 to it at every entry that starts an attack - 0x0274D6 and
  -- 0x02751A (the two normal-attack starts), 0x027818 / 0x027870 / 0x0278A6 /
  -- 0x0278DA / 0x027A00, and 0x028F18, which is the tail the chain AND the
  -- rapid restart both fall into after 0x028E5E accepts the repeat. So a
  -- repeat that the game actually granted moves it, and an input it refused
  -- does not.
  --
  -- It is not a flag that needs interpreting: 0x00D348 divides $1B6 (attacks
  -- that connected) by it and clears both, which is the hit-rate grade at the
  -- end of a round. Attacks made, in other words - and nothing else writes it.
  --
  -- Not read: a natural multi-hit stage and an animation loop never re-enter
  -- those start routines, so neither moves the counter. That is the whole
  -- reason to prefer it over watching the animation rewind.
  --
  -- Only ever compared with itself here, so the word order does not matter and
  -- the wrap at 0x10000 costs nothing.
  snapshot.p1.attack_seq = memory.readword(ATK + 0x1B8)

  snapshot.p1.air_normal = snapshot.p1.airborne
    and (_state == 0x06 or _state == 0x0A)
  -- $06 = 0x14 is the dash state, and a dash attack is a move made inside it,
  -- so $06 stays 0x14 across both (VSAV_MEMORY_NOTES.md 11). Paired with the
  -- move id below it is what tells the dash apart from the attack it leads to.
  snapshot.p1.dash = _state == 0x14
  -- WHERE A NEW MOVE BEGINS: THE CEL POINTER LEAVES ITS OWN SCRIPT.
  --
  -- Two earlier answers were wrong. $106 + $102 + $101 does not move inside a
  -- dash at all, and $10B moves for a reason that depends on the move - on
  -- Zabel's dash LP it never moves on a whiff and moves two ticks AFTER the
  -- hitbox on a hit (VSAV_MEMORY_NOTES.md).
  --
  -- The animation says it plainly. The stepper at 0x027F70 advances the cel
  -- pointer with lea ($18,A0),A0 - a cel record is 0x18 bytes and an ordinary
  -- step is exactly that far. Anything else moved $1C from outside the stepper,
  -- which is what starting a different move IS. Measured over three whiffed
  -- dash LPs: +0x18, +0x18, then +0x102e onto the attack's own script.
  snapshot.p1.cel = _cel
  snapshot.p1.hitfreeze = memory.readbyte(ATK + 0x05C) ~= 0

  snapshot.p2.status = memory.readbyte(DEF + 0x005)
  -- $06 as well as $05, because a knockdown leaves $05 before the character can
  -- act - the getting-up animation is $06. "Can act" is $05 and $06 both zero,
  -- which is the test dummy_free uses everywhere else in the tool.
  snapshot.p2.state = memory.readbyte(DEF + 0x006)
  snapshot.p2.block_clock = memory.readbyte(DEF + 0x158)
  -- HIT OR GUARD, WHICH $158 COULD NOT SAY.
  --
  -- $140 is the recovery KIND: 0x02 / 0x12 while guarding, 0x00 / 0x04 in
  -- hitstun (VSAV_MEMORY_NOTES.md; the ROM writes the 2 at 0x02395A, "地上
  -- ガード"). The block clock $158 does move after all - it was 0x00 in every
  -- trace up to 2026-09-09 only because none of them contained a guard. With
  -- guards in the 2026-09-10 trace it loads 0x0E and counts down alongside.
  --
  -- BOTH CAN BE ONE TICK LATE. Of 10 guarded contacts measured on 2026-09-10,
  -- 7 had $140 and $158 already set on the tick hitstop rose and 3 had them
  -- still at 0x00, set on the very next tick. Never later than that. This is
  -- why actionRoute holds its Hit/Guard label open for a tick before printing
  -- it: without the grace those 3 would read as Hit.
  local _recover = memory.readbyte(DEF + 0x140)
  snapshot.p2.guarding = _recover == 0x02 or _recover == 0x12
  -- THE VALUE, NOT JUST WHETHER IT IS SET.
  --
  -- $5C counts down every tick and is slammed back to 0x0B by a hit - and it
  -- does that EVEN WHEN THE DEFENDER IS ALREADY IN STUN, which the $05 edge
  -- does not (five times in the 2026-09-08 trace). A rise in it is the only
  -- contact signal that survives a combo.
  snapshot.p2.hitstop = memory.readbyte(DEF + 0x05C)
  snapshot.p2.hitfreeze = snapshot.p2.hitstop ~= 0
  -- $1A7 is the reliable wake-up tally used by the existing GC trainer.
  snapshot.p2.knockdown = memory.readbyte(DEF + 0x1A7) ~= 0
  return snapshot
end

return M
