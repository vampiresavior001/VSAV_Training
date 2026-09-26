-- guardCancel.lua does the same. Without it debugKnockdownModule is nil here
-- and every diagnostic below silently does nothing, which is exactly how the
-- first attempt at this log came back empty.
local debugKnockdownModule = require "./scripts/debugKnockdown"

-- Values to write into memory
local auto_guard_addr_1 = 0xFF8BB2
local auto_guard_addr_2 = 0xFF8BE2
local first_frame = nil 

local function get_block_chance()
    local block_freq_value = globals.options.p2_block_chance
    local function maybe(x) 
        if 100 * math.random() < x then 
            return true
        else 
            return false
        end  
    end    

    local should_block = false

    -- THE NUMBERS ARE THE ONES ON THE MENU.
    --
    -- These read 35 and 65 while menu.lua's p2_block_chance list offers "25%"
    -- and "75%". Same ten-point lie Guard Action Frequency carried, found by
    -- looking for the same shape after that one was fixed.
    if block_freq_value == 0x2 then
        should_block = maybe(25)
    elseif block_freq_value == 0x3 then
        should_block = maybe(50)
    elseif block_freq_value == 0x4 then
        should_block = maybe(75)
    elseif block_freq_value == 0x5 then
        should_block = true
    elseif block_freq_value == 0x1 then
        should_block = false
    end

    return should_block    
end

-- THE GAME'S OWN PROXIMITY GUARD (0x0276AC..0x02776C).
--
-- What was here before was "the opponent started an attack AND we are within
-- 0x100", which is only the crude fallback at the very end of the game's own
-- routine (0x02775A). Two things fall out of that:
--
--   * a whiffed Demon Cradle sets $105 and we are always inside 0x100 - every
--     blocked hit measured sat at |dx| 32..109 - so the dummy holds back on an
--     attack that cannot reach and simply walks backwards.
--   * a separate object such as Kagenui never sets the opponent's $105 at all,
--     so it is not watched.
--
-- The routine the game runs instead is entered at 0x02766A / 0x027688, returns
-- D0 = 1 when the defender should be in a guard stance, and has two halves.
-- The first sweeps every object; the second reads the attack's own hitbox
-- table. Ported here so the dummy holds back exactly when the game thinks
-- something is in range, and not otherwise.

local OBJ_BASE   = 0xFF9400   -- $1400 off A5 (= 0xFF8000)
local OBJ_STRIDE = 0x100
local OBJ_COUNT  = 0x20

local function sw(v)          -- 68000 words are signed
    if v >= 0x8000 then return v - 0x10000 end
    return v
end

local function cel_ptr(obj)
    local p = memory.readdword(obj + 0x1C)
    if p == nil or p < 0x1000 or p >= 0x1000000 then return nil end
    return p
end

-- 0x0276AC: every live object that is not ours and is showing an attack cel.
-- This is the half that covers projectiles and summoned objects.
local function hostile_object_active(me)
    local mine = memory.readbyte(me + 0x70)
    prox_obj_n = 0
    for i = 0, OBJ_COUNT - 1 do
        local o = OBJ_BASE + i * OBJ_STRIDE
        if memory.readbyte(o) == 1
           and memory.readbyte(o + 0x01) ~= 0
           and memory.readbyte(o + 0xA2) == 0
           and memory.readbyte(o + 0x70) ~= mine then
            local c = cel_ptr(o)
            -- bpl: bit 7 clear means this cel threatens.
            if c ~= nil and memory.readbyte(c + 0x17) < 0x80 then
                prox_obj_n = prox_obj_n + 1
            end
        end
    end
    return prox_obj_n > 0
end

-- 0x027712: walk the attack's remaining cels and ask whether any of their
-- hitboxes reaches us. $8c is the per-attack box table, the cel's $0a indexes
-- it 32 bytes apart, +0 is the box offset and +4 its half width.
local function attack_reaches(me, foe)
    local a0 = cel_ptr(foe)
    if a0 == nil then return nil end
    if memory.readbyte(a0 + 0x17) >= 0x80 then return false end
    local tbl = memory.readdword(foe + 0x8C)
    if tbl == nil or tbl < 0x1000 or tbl >= 0x1000000 then return nil end
    local myx  = sw(memory.readword(me + 0x10))
    local foex = sw(memory.readword(foe + 0x10))
    local flip = memory.readbyte(foe + 0x0B) ~= 0
    for _ = 1, 24 do
        local idx = memory.readbyte(a0 + 0x0A)
        if idx ~= 0 then
            local e = tbl + idx * 32
            local d = sw(memory.readword(e))
            if flip then d = -d end
            d = (foex + d) - myx
            if d < 0 then d = -d end
            if d <= sw(memory.readword(e + 0x04)) + 0x80 then return true end
        end
        -- $1 bits 6-7 mark the last cel; otherwise step 0x18 and keep looking.
        if memory.readbyte(a0 + 0x01) % 0x100 >= 0x40 then break end
        a0 = a0 + 0x18
    end
    -- 0x02775A: the fallback the old code was using on its own.
    local d = myx - sw(memory.readword(foe + 0x10)) + 0x80
    return d >= 0 and d < 0x100
end

-- WHICH HEIGHT THE NEXT HIT CAN BE BLOCKED AT (0x018352..0x0183EA).
--
-- All Guard used to add down whenever the attacker's $100 read 2 - a flag for
-- a crouching NORMAL. It is not a property of the attack, so the dummy
-- crouched under specials that a standing guard takes, and a crouching Pose
-- stayed down through overheads, which then hit (user, 2026-09-26).
--
-- The game decides it in the hit routine, from the hit's box entry ($8c table,
-- the cel's $0a, 32 bytes apart - the same table attack_reaches reads) and the
-- defender's $121 (1 while the guard is crouching):
--
--     standing  fails on $17 = 02 03 38 39                        -> "low"
--     crouching fails on $17 = 2C 37 42 48 4A 4D                  -> "high"
--               and on $17 = 00 01 from an airborne attacker that
--               is not an object ($08 = 0) and has $ad clear       -> "high"
--
-- Anything else blocks either way ("mid"). The cels are walked the way
-- attack_reaches walks them, and the first one with a box is the hit to come.
-- nil when nothing readable is there.
local GUARD_LOW  = { [0x02] = true, [0x03] = true, [0x38] = true, [0x39] = true }
local GUARD_HIGH = { [0x2C] = true, [0x37] = true, [0x42] = true, [0x48] = true,
                     [0x4A] = true, [0x4D] = true }

local function attack_height(obj)
    local a0 = cel_ptr(obj)
    if a0 == nil then return nil end
    local tbl = memory.readdword(obj + 0x8C)
    if tbl == nil or tbl < 0x1000 or tbl >= 0x1000000 then return nil end
    for _ = 1, 24 do
        local idx = memory.readbyte(a0 + 0x0A)
        if idx ~= 0 then
            local t = memory.readbyte(tbl + idx * 32 + 0x17)
            if GUARD_LOW[t] then return "low" end
            if GUARD_HIGH[t] then return "high" end
            if (t == 0x00 or t == 0x01)
               and memory.readbyte(obj + 0x38) ~= 0
               and memory.readbyte(obj + 0x08) == 0
               and memory.readbyte(obj + 0xAD) == 0 then
                return "high"
            end
            return "mid"
        end
        if memory.readbyte(a0 + 0x01) % 0x100 >= 0x40 then break end
        a0 = a0 + 0x18
    end
    return nil
end

-- The attacker and every hostile object showing an attack cel (the objects
-- hostile_object_active counts). One side needing low and another high cannot
-- both be met, so that - like nothing at all - leaves it to the Pose.
local function guard_height(me, foe)
    local low, high = false, false
    local function take(h)
        if h == "low" then low = true elseif h == "high" then high = true end
    end
    if memory.readbyte(foe + 0x105) ~= 0 or memory.readbyte(foe + 0x154) ~= 0 then
        take(attack_height(foe))
    end
    local mine = memory.readbyte(me + 0x70)
    for i = 0, OBJ_COUNT - 1 do
        local o = OBJ_BASE + i * OBJ_STRIDE
        if memory.readbyte(o) == 1
           and memory.readbyte(o + 0x01) ~= 0
           and memory.readbyte(o + 0xA2) == 0
           and memory.readbyte(o + 0x70) ~= mine then
            local c = cel_ptr(o)
            if c ~= nil and memory.readbyte(c + 0x17) < 0x80 then
                take(attack_height(o))
            end
        end
    end
    if low and not high then return "low" end
    if high and not low then return "high" end
    return nil
end

-- Which branch decided, so a single recording says where a whiffed move is
-- still being treated as a threat instead of leaving it to be guessed.
prox_why   = nil
prox_obj_n = 0     -- hostile objects showing an attack cel
prox_dx    = 0

-- A LOG OF ITS OWN.
--
-- The knockdown logger only fills rec.writes while an episode is recording,
-- and a WHIFF - the case being chased - starts no episode, so every
-- mark_write diagnostic came back empty. This writes reversal_logs/ag_prox.json
-- directly instead. One entry per CHANGE of the decision, not per frame, so a
-- long whiff is a couple of lines rather than a hundred.
local AG_LOG_PATH = "reversal_logs/ag_prox.json"
local ag_events   = {}
local ag_last     = nil
local ag_dirty    = false

local function ag_record(why, held, extra)
    if debugKnockdownModule == nil or debugKnockdownModule.enabled == nil then return end
    if not debugKnockdownModule.enabled() then return end
    local _k = tostring(why) .. "/" .. tostring(held)
    if _k == ag_last then return end
    ag_last = _k
    if #ag_events >= 400 then table.remove(ag_events, 1) end
    table.insert(ag_events, {
        f    = globals.current_frame,
        why  = why,
        held = held and 1 or 0,      -- was BACK actually pressed this frame
        dx   = prox_dx,
        obj  = prox_obj_n,
        a105 = memory.readbyte(0xFF8400 + 0x105),
        a154 = memory.readbyte(0xFF8400 + 0x154),
        a149 = memory.readword(0xFF8400 + 0x149),
        a4ac = memory.readbyte(0xFF8400 + 0x0AC),
        cel  = memory.readdword(0xFF8400 + 0x1C) % 0x10000,
        ext  = extra,
    })
    ag_dirty = true
end

-- Rewritten whole rather than appended, so it is always a valid document; the
-- gate keeps that off the per-frame path since the decision changes often in
-- a real match.
local ag_flush_tick = 0
local function ag_flush()
    ag_flush_tick = ag_flush_tick + 1
    if not ag_dirty or ag_flush_tick % 120 ~= 0 then return end
    ag_dirty = false
    write_object_to_json_file({ events = ag_events }, AG_LOG_PATH)
end

-- $4AC IS NOT "HOLD BACK NO MATTER WHAT".
--
-- Every single hold-back in the first readable recording came from an early
-- return on $4AC, at every range from dx 302 down to 33, so the port below was
-- never reached. In the game's own routine $ac only skips a REJECTION:
--
--     0276F2  tst.b ($38,A4) / bne $27706
--     0276F8  tst.b ($ac,A4) / bne $27706     <- jumps INTO the range check
--     0276FE  tst.b ($38,A6) / bne $27770
--     027706  ... the per-attack range check runs either way
--
-- so it makes a guard more likely, not certain. The only unconditional yes is
-- $154 at 0x0276E2, and that is inside proximity_guard already. $149 is not in
-- the routine at all - projectiles are covered by the object sweep instead.
local function proximity_guard(me, foe)
    if hostile_object_active(me) then prox_why = "obj"; return true end
    if memory.readbyte(foe + 0x154) ~= 0 then prox_why = "154"; return true end
    if memory.readbyte(foe + 0x105) == 0 then prox_why = "no105"; return false end
    local r = attack_reaches(me, foe)
    if r == nil then prox_why = "unreadable"; return nil end
    prox_why = r and "reach" or "far"
    return r
end

local block_started_frame = nil
local is_blocking = false
local current_block_chance = nil

function dummy_guard(cur_keys,player_objects)
    -- A per-frame get_block_chance() sat here, assigned to a local nothing
    -- ever read. The real roll is current_block_chance below, latched once per
    -- attack - but the dead call still drew a random number sixty times a
    -- second out of the one generator Guard Action Frequency and Use Random
    -- Recording Slot also draw from.
    local p1_x_pos = memory.readword(0xFF8400 + 0x10)
	local p2_x_pos = memory.readword(0xFF8800 + 0x10)
    local p1_proj  = memory.readword(0xFF8400 + 0x149)
    local p2_proj  = memory.readword(0xFF8800 + 0x149)
    local p1_supers_that_activate_proxy_block_check =  memory.readbyte(0xFF8554) ~= 0x00 
    local p1_initiating_proj = memory.readbyte(0xFF84AC) ~= 0
    -- local should_block      = false

    if globals.controlling_p1 then
        attack_flag = globals.dummy.p1_attack_flag
        away_btn    = globals.dummy.p2_away_btn
        proj        = p1_proj
     else
        attack_flag = globals.dummy.p2_attack_flag 
        away_btn    = globals.dummy.p1_away_btn
        proj        = p2_proj
     end

    -- The dummy is whichever side the user is NOT holding, and it is the one
    -- doing the blocking, so it is A6 in the routine this ports.
    local me   = globals.controlling_p1 and 0xFF8800 or 0xFF8400
    local foe  = globals.controlling_p1 and 0xFF8400 or 0xFF8800
    prox_dx = math.abs(p1_x_pos - p2_x_pos)
    local prox = proximity_guard(me, foe)
    local close_enough
    if prox == nil then
        -- Nothing readable this frame: the old behaviour, unchanged, including
        -- its unconditional hold.
        if proj ~= 0 or p1_initiating_proj
           or p1_supers_that_activate_proxy_block_check then
            prox_why = "early"
            cur_keys[ away_btn ] = true
            return cur_keys
        end
        close_enough = math.abs(p1_x_pos - p2_x_pos) < 0x100
    else
        -- prox already answers both halves of the old test, and it answers
        -- them for objects too - $105 belongs to the opponent PLAYER, so
        -- gating on it here is what let Kagenui through untouched.
        close_enough = prox
        attack_flag  = prox
    end
    if debugKnockdownModule and debugKnockdownModule.mark_write then
        debugKnockdownModule.mark_write("ag_prox",
            (prox == true and 1 or prox == false and 0 or 2) * 1000
            + math.abs(p1_x_pos - p2_x_pos) % 1000, prox_why)
    end

    if globals.dummy.p2_status_1 == "Hurt or Block" then
        is_blocking = false
    end
    if attack_flag then
        is_attacking = true
    else 
        block_started_frame = nil
    end

    if attack_flag and current_block_chance == nil then
        current_block_chance = get_block_chance()
    end
    if player_objects[2].guard_ended then 
        current_block_chance = nil
        return cur_keys
    end
    if current_block_chance == false then
        return cur_keys
    end


    -- HOLD, NOT A TAP - ONCE THE RANGE IS KNOWN (v247).
    --
    -- The tap existed because the old test could not tell whether the attack
    -- was actually in range, and holding back out of range walks. It is not a
    -- workaround worth keeping: prox being true IS the game saying the guard
    -- pose applies, and in the guard pose back does not walk. So while prox
    -- holds, hold back.
    --
    -- This is also what projectiles need. They were only ever guarded because
    -- the old $149 early return held back every frame for as long as one was
    -- on screen; v246 turned that into a three-tick tap at the rising edge and
    -- they started going straight through - the projectile arrives long after
    -- the tap has been let go.
    --
    -- v246 also moved the press into guardCancel.lua's tick hook. Removed: the
    -- press does not need tick precision, it needs to still be held when the
    -- thing arrives.
    if current_block_chance == true and attack_flag and close_enough then
        cur_keys[ away_btn ] = true
        -- All Guard, and the Push Block entries that guard like it: the height
        -- the hit needs, over the Pose. A crouching Pose stands for an
        -- overhead; any Pose crouches for a low; otherwise the Pose decides
        -- (guard_height). Stand Block (2) is left as it was.
        -- The dummy's own down: this used to be "P2 Down" whichever side the
        -- dummy was, which pressed the user's down while they played P2.
        if globals.options.guard >= 0x04 then
            local down_btn = globals.controlling_p1 and "P2 Down" or "P1 Down"
            local need = guard_height(me, foe)
            if need == "low" then
                cur_keys[down_btn] = true
            elseif need == "high" then
                cur_keys[down_btn] = false
            end
        end
        if not is_blocking then
            block_started_frame = emu.framecount()
            is_blocking = true
        end
        return cur_keys
    end
    if not attack_flag and is_blocking == true then
        attack_started_frame = nil
        is_blocking = false
        is_attacking = false
    end

    return {}
end

autoguardModule = {
    ["registerBefore"] = function(cur_keys, player_objects)
        if globals.options.guard == 0x3 then
            memory.writebyte(auto_guard_addr_1, 0x1)
            memory.writebyte(auto_guard_addr_2, 0x1)
        else
            memory.writebyte(auto_guard_addr_1, 0x0)
            memory.writebyte(auto_guard_addr_2, 0x0)
        end
        -- 5/6/7 are Push Block at a strength. They defend exactly like All
        -- Guard; the pushing is queued in guardCancel.lua, this only gets the
        -- block up.
        if globals.options.guard == 2 or globals.options.guard >= 4 then
            local _r = dummy_guard(cur_keys, player_objects)
            -- Recorded from the RESULT, not from inside the decision: several
            -- paths return early and only the returned table says whether BACK
            -- is actually being pressed this frame.
            local _away
            if globals.controlling_p1 then _away = globals.dummy.p2_away_btn
            else _away = globals.dummy.p1_away_btn end
            -- vsav_training_master_script.lua DISCARDS this return value, so
            -- what actually reaches the game is the table dummy_guard mutated
            -- in place. Read that, and the return only as a fallback.
            local _held = false
            if _away ~= nil
               and (cur_keys[_away] == true
                    or (_r ~= nil and _r[_away] == true)) then _held = true end
            ag_record(prox_why, _held, nil)
            ag_flush()
            return _r
        else
            return {}
        end
    end
}
return autoguardModule