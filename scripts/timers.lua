-- Without this debugKnockdownModule is nil here and every gated diagnostic
-- silently does nothing - the same way autoguard.lua's first All Guard log
-- came back empty.
local debugKnockdownModule = require "./scripts/debugKnockdown"

local rb, rbs, rw, rws, rd, rds = memory.readbyte, memory.readbytesigned, memory.readword, memory.readwordsigned, memory.readdword, memory.readdwordsigned
local wb, ww, wd = memory.writebyte, memory.writeword, memory.writedword

local timers = {
    p1_pushblock_counter = 0,
    p2_pushblock_counter = 0,
    p1_pushblock_ok = false,
    p2_pushblock_ok = false,
    p1_pb_simul = 0,
    p2_pb_simul = 0,
    p1_pb_marks = {},
    p2_pb_marks = {},
    p1_pb_raws = {},
    p2_pb_raws = {},
}

-- THE PUSH BLOCK COUNT, TAKEN AT THE INCREMENT (v248).
--
-- $170 is the right byte - it is the count of presses the game keeps itself -
-- but WHEN it is read decides whether the number is true. It used to be
-- sampled once per DISPLAYED frame and finalised on the edge where the window
-- $1AB reaches zero, and both halves of that are wrong:
--
--   * the frame callback never sees roughly four ticks in ten (turbo 3 runs
--     4 ticks per 3 displayed frames), so the edge can be observed late;
--   * guard's exit clears the count and the window in the same breath
--
--         024AEE  clr.b ($184,A6)      the success flag
--         024AF2  clr.b ($170,A6)      the count
--         024AF6  clr.b ($1ab,A6)      the window
--
--     so anything reading $170 after that edge reads a zero.
--
-- Measured over the archive, the last tick of every medium block is
-- (count 1, window 0) -> (0, 0). The window expires at 14 ticks and the stun
-- runs 16, so there are two ticks of grace and a missed frame lands past it.
-- A LIGHT block has no grace at all: the stun is 11 ticks, so $1AB never
-- reaches zero on its own and the only zero in existence is the one the clear
-- writes - there was nothing but 0 to read there.
--
-- Take it at the increment instead:
--
--     027606  addq.b #1, ($170,A6)     <- hooked here
--     02760A  move.b ($170,A6), D0
--     02760E  cmpi.b #$8, D0           <- eight is guaranteed
--     027616  lea ($28d50,PC), A0      <- fewer than eight goes to the table
--
-- registerexec fires BEFORE the instruction runs, so the press being counted
-- is $170 + 1. No peak bookkeeping is needed: $170 itself restarts at zero
-- when the clear runs, so the next attempt counts up from one on its own.
--
-- 0x02760E already carries a diagnostic hook; 0x027606 is free. Not hooked on
-- 0x02211A - guardCancel.lua owns that address and a second registerexec on it
-- risks replacing the hook the whole tick machinery depends on.
-- THE PUSH BLOCK COUNT IS A TRAINING NUMBER: PRESSES MADE (v250).
--
-- Six presses inside the window is a guaranteed push block, so the number
-- worth showing is how many times you actually pressed - you practise until
-- it reads six. The game's own $170 cannot be that number, because it stops
-- the moment the push block is granted:
--
--     0275D8  tst.b ($1ab,A6) / beq exit      window closed
--     0275E0  tst.b ($184,A6) / bne exit      ALREADY GRANTED - exits here
--     0275E8  cmpi.w #$202, ($4,A6) / bne exit
--     0275F0  cmpi.b #$2, ($140,A6) / bne exit
--     0275F8  tst.b ($3b4,A6) / bne exit
--     0275FE  bsr $274ba / beq exit           $15D == 0 and ($126 & $77)
--     027606  addq.b #1, ($170,A6)
--
-- so a lucky attempt that is granted on three reads three however hard you
-- keep mashing. Measured over the archive, 81 of 90 granted push blocks
-- stopped below six - which is why six never appeared on screen.
--
-- Counted here instead. The WINDOW is still entirely the game's: reaching
-- 0x0275E0 already means $1ab is non-zero, so nothing below widens the period
-- the presses are counted over. Only the tests that sit AFTER the $184 early
-- out are repeated, so a press made after the grant is counted the same as one
-- made before.
local function and77(v)
    local r = 0
    for _, b in ipairs({1, 2, 4, 16, 32, 64}) do
        if math.floor(v / b) % 2 == 1 then r = r + b end
    end
    return r
end

-- THE READOUT FOLLOWS THE GAME'S OWN COUNT AND ADDS TO IT, RATHER THAN KEEPING
-- A SEPARATE ONE.
--
-- The count that decides a push block is $170: 0x02760E takes eight as
-- guaranteed and 0x02761E rolls against a table below that, and both read $170.
-- This used to keep a count of its own and reset it at 0x023966, where a
-- blocked hit re-arms the window. THE GAME DOES NOT RESET $170 THERE - it is
-- cleared only when guard stun ends (0x024AF2 / 0x024B1A) and by the wholesale
-- object reset at 0x026E60. So through a multi-hit blocked string the readout
-- restarted from zero while the game kept counting, and showed a smaller number
-- than the one being used. Measured over eleven granted push blocks: seven
-- disagreed, the worst reading 1 against the game's 4
-- (analysis/pb_flag_probe_20260913.log, 2026-09-13).
--
-- $170 on its own is not enough either, because the game stops counting the
-- moment it grants: 0x0275E0 exits on $184 and never reaches the increment. A
-- lucky attempt granted on three reads three however hard you keep mashing. So
-- the presses made AFTER the grant are counted here and added to it.
--
-- There is no reset hook any more, and that is the point: a fresh guard shows
-- up as $170 == 0 with $184 == 0, and the count and the granted flag are
-- cleared together at that moment. They cannot disagree - which they did,
-- drawing a green 0 on the red "nothing counted" box (user screenshot,
-- 2026-09-13).
local pb = {
    [0xFF8400] = { count = 0, ok = false, after = 0, simul = 0, marks = {}, raws = {} },
    [0xFF8800] = { count = 0, ok = false, after = 0, simul = 0, marks = {}, raws = {} },
}

local function pb_publish()
    timers.p1_pushblock_counter = pb[0xFF8400].count
    timers.p2_pushblock_counter = pb[0xFF8800].count
    timers.p1_pushblock_ok      = pb[0xFF8400].ok
    timers.p2_pushblock_ok      = pb[0xFF8800].ok
    timers.p1_pb_simul          = pb[0xFF8400].simul
    timers.p2_pb_simul          = pb[0xFF8800].simul
    timers.p1_pb_marks          = pb[0xFF8400].marks
    timers.p2_pb_marks          = pb[0xFF8800].marks
    timers.p1_pb_raws           = pb[0xFF8400].raws
    timers.p2_pb_raws           = pb[0xFF8800].raws
end

-- THE TIMELINE MARK (user, 2026-09-21).
--
-- One character per tick of the window, drawn beside the count in hud.lua:
-- the digit is HOW MANY buttons edge on that tick (1 = a clean single, 2..6
-- a simultaneous press). The ruler is the game's own countdown - $1ab opens
-- at 14 on the block (0x023966) and reads one less per tick, so 15 - $1ab is
-- "which tick of the window this is" and no Lua-side clock is needed.
--
-- A skilled input is one button per tick, spaced across the window (user):
-- two buttons on ONE tick buy one count (the ROM's addq runs once per tick,
-- however many buttons edge together) where a spaced pair would have bought
-- two. That lost count is why the simultaneous tick goes into the marks and
-- into MultiPush, the negative the readout exists to show.
--
-- Rewind-safe: marks are keyed by position, so a speculative re-execution
-- rewrites the same slot instead of appending a second one - the same shape
-- the count's $n + 1 recomputation uses.
local function count_pb_buttons(v)
    local r = 0
    for _, b in ipairs({1, 2, 4, 16, 32, 64}) do
        if math.floor(v / b) % 2 == 1 then r = r + 1 end
    end
    return r
end

-- One span = one window ($1ab 14 -> 0). A blocked hit re-arms the window
-- mid-string, and each span is drawn fresh; the COUNT carries across them
-- the same way the game keeps $170.
local function pb_mark_tick(_a6, _t)
    local _w = memory.readbyte(_a6 + 0x1AB)
    if _w >= 14 then _t.marks = {}; _t.raws = {} end
    local _pos = 15 - _w
    if _pos < 1 or _pos > 14 or _t.marks[_pos] ~= nil then return end
    local _mark = "-"
    local _raw = 0
    if memory.readword(_a6 + 0x04) == 0x0202
       and memory.readbyte(_a6 + 0x140) == 0x02
       and memory.readbyte(_a6 + 0x3B4) == 0
       and memory.readbyte(0xFF815D) == 0 then
        local _e = and77(memory.readbyte(_a6 + 0x126))
        if _e ~= 0 then
            local _nbtn = math.min(count_pb_buttons(_e), 9)
            _mark = tostring(_nbtn)
            _raw = _e
            if _nbtn >= 2 then _t.simul = _t.simul + 1 end
        end
    end
    _t.marks[_pos] = _mark
    _t.raws[_pos] = _raw
    pb_publish()
end

-- LATEMASH: THE BUTTONS PRESSED AFTER THE WINDOW HAS CLOSED.
--
-- The push block window is fourteen ticks: 0x023966 writes it into $1ab and
-- 0x02249C takes one off per tick. Inside it every press is a legitimate
-- attempt, whether or not the block has already been granted - the player
-- cannot see the grant, so pressing on is not a mistake (user, 2026-09-23).
-- PAST THE FOURTEEN it buys nothing at all, and that is the habit worth
-- showing. "LateMash" is what fighting game players call it.
--
-- WHY THIS NEEDS ITS OWN OBSERVATION POINT. The 0x0275E0 hook above only ever
-- runs while the window is open - two instructions earlier the ROM tests $1ab
-- and leaves - so the presses this counts are invisible from there. Reading
-- once per displayed frame is not enough either: at turbo the game runs four
-- ticks per three frames and the edge is missed, which is the same trap the
-- note at the top of this file records. So it rides the tick stream.
--
-- THE FOURTEEN IS READ, NOT WRITTEN DOWN. Whatever $1ab holds on the tick the
-- window opens is the length, so a build or a situation that uses a different
-- number is followed rather than contradicted.
--
-- THE END IS COUNTED FROM THE OPENING, NOT FROM $1ab REACHING ZERO. A LIGHT
-- block's guard stun is eleven ticks and the exit clears $1ab (0x024AF6)
-- before it can count down, so the zero never arrives on its own - waiting for
-- it would miss every light block (measured, see the note at the top).
local LATEMASH_CAP = 60         -- ticks past the window end (user, 2026-09-23)
local om_subscribed = false
local om = {
    [0xFF8400] = { n = 0, late = 0, open_lg = nil, len = 0, was = 0 },
    [0xFF8800] = { n = 0, late = 0, open_lg = nil, len = 0, was = 0 },
}

local function om_publish()
    timers.p1_pb_latemash      = om[0xFF8400].n
    timers.p2_pb_latemash      = om[0xFF8800].n
    timers.p1_pb_latemash_late = om[0xFF8400].late
    timers.p2_pb_latemash_late = om[0xFF8800].late
end

-- One tick of the stream. Exported below so the offline test can drive it:
-- nothing else can, because the real caller is the emulator's own clock.
local function latemash_tick()
    local _now = memory.readbyte(0xFF8081)
    for _a6, _o in pairs(om) do
        local _w = memory.readbyte(_a6 + 0x1AB)
        -- A RISE IS AN OPENING. The window only ever counts down while it is
        -- running, so a larger value than last tick is 0x023966 arming it -
        -- including the re-arm a blocked string makes mid-count, which starts
        -- a new attempt and therefore a new tally.
        if _w > _o.was then
            _o.open_lg, _o.len, _o.n, _o.late = _now, _w, 0, 0
        end
        _o.was = _w
        if _o.open_lg ~= nil then
            -- Eight bits, so the gap wraps; the same % 256 every other gap in
            -- this tool uses. _since is 0 on the opening tick, so the window
            -- itself is 0 .. len-1 and the first tick outside it is +1.
            local _since = (_now - _o.open_lg) % 256
            local _past = _since - _o.len + 1
            if _past >= 1 then
                if _past > LATEMASH_CAP then
                    -- Past the limit the readout stops following. A player who
                    -- simply keeps the buttons down would otherwise climb for
                    -- as long as they felt like it, and the number would stop
                    -- meaning anything (user, 2026-09-23).
                    _o.open_lg = nil
                else
                    local _e = and77(memory.readbyte(_a6 + 0x126))
                    if _e ~= 0 then
                        -- BUTTONS, not ticks: two at once is two presses that
                        -- bought nothing. MultiPush is the one that counts
                        -- ticks, and it is about a different mistake.
                        _o.n = _o.n + count_pb_buttons(_e)
                        _o.late = _past
                    end
                end
            end
        end
    end
    om_publish()
end
om_publish()

memory.registerexec(0x0275E0, function()
    local _a6 = memory.getregister("m68000.a6")
    local _t = pb[_a6]
    if _t == nil then return end
    local _n = memory.readbyte(_a6 + 0x170)
    local _granted = memory.readbyte(_a6 + 0x184) ~= 0

    -- A guard the game has counted nothing for yet. Clearing here rather than
    -- on the first press means a guard you did not mash through stops showing
    -- the previous one's number.
    if _n == 0 and not _granted
       and (_t.count ~= 0 or _t.ok or _t.after ~= 0 or _t.simul ~= 0) then
        _t.count, _t.ok, _t.after, _t.simul, _t.marks, _t.raws = 0, false, 0, 0, {}, {}
        pb_publish()
    end

    pb_mark_tick(_a6, _t)

    -- The tests the ROM makes after this point, repeated, so the readout moves
    -- on exactly the presses the game takes. $184 is deliberately not among
    -- them: a press made after the grant still counts here.
    if memory.readword(_a6 + 0x04) ~= 0x0202 then return end
    if memory.readbyte(_a6 + 0x140) ~= 0x02 then return end
    if memory.readbyte(_a6 + 0x3B4) ~= 0 then return end
    if memory.readbyte(0xFF815D) ~= 0 then return end
    if and77(memory.readbyte(_a6 + 0x126)) == 0 then return end

    if _granted then
        -- $170 is frozen from the grant on, so the rest are ours to add.
        _t.after = _t.after + 1
        -- STILL FOLDED INTO THE TOTAL. A press after the grant is a press the
        -- player made and could not have known was unnecessary, so PB Count
        -- keeps showing it; only LateMash - the window's OUTSIDE - is a
        -- mistake (user, 2026-09-23).
        _t.count = _n + _t.after
    else
        -- $170 is read here, one instruction before 0x027606 adds to it, so
        -- the press being decided right now is the +1.
        _t.count = _n + 1
    end
    pb_publish()
end)

-- 027632: move.b #$1, ($184,A6)   the push block is granted
memory.registerexec(0x027632, function()
    local _a6 = memory.getregister("m68000.a6")
    local _t = pb[_a6]
    if _t == nil then return end
    _t.ok = true
    pb_publish()
end)

local function hex(val)
    val = string.format("%X",val)
    return val
end

function drawaxis(x,y,axis)
    gui.line(x+axis,y,x-axis,y,'yellow')
    gui.line(x,y-axis,x,y+axis,'red')
end

--Collision Box function
function collisionbox(adr,playerx,playery,color,flip)

    local hval = rws(adr + 0x0)
    local vval = rws(adr + 0x2)
    local hrad =  rw(adr + 0x4)
    local vrad =  rw(adr + 0x6)

    local hval	 = playerx + hval * flip
    local vval	 = playery - vval
    local left	 = hval - hrad
    local right	 = hval + hrad
    local top	 = vval - vrad
    local bottom = vval + vrad
    
    --gui.line(playerx,playery,left,bottom) To help ID where the box is if your maths is wrong
    -- gui.box(left,top,right,bottom,color)
    return {
        left = left,
        top = top,
        right = right,
        bottom = bottom
    }

end

-- Box data from Jed's VSAV script
function getHeadBoxTopXY(adr)

    local CamADR = 0xFF8280
    local camx = rw(CamADR + 0x20)
    local camy = rw(CamADR + 0x24)
    local px = rw(adr + 0x010) - camx 
    local py = 244 - rw(adr + 0x014) + camy
    local anipnt = rd(adr + 0x1C)
    local boxset = rd(adr + 0x64) + rb(anipnt + 0x09)*4
    local special = rd((rb(adr + 0x382)*4 + 0xbd57a))  
    local charid = rb(adr + 0x382)
    local p2x = rw(0xFF8800 + 0x010) - camx 
    local p2y = 244 - rw(0xFF8800 + 0x014) + camy
    
    local p1x = rw(0xFF8400 + 0x010) - camx 
    local p1y = 244 - rw(0xFF8400 + 0x014) + camy

 
    if rb(adr + 0x0B) == 0 then
        pflip = 1
        else
        pflip = -1
        end 
    ------------------------
    ----------Head----------
    ------------------------
    local headpnt = rd(adr + 0x80)
    local head = headpnt + (rb(boxset + 0x00) * 0x08)
    -- gui.box(224,34,383,54,{0x00,0xFF,0xFF,0x40})

    -- gui.text(228,36,"Head Pointer: " .. hex(head))
    -- gui.text(228,44,"XP: " .. hex(rw(head + 0x00)))
    -- gui.text(268,44,"YP: " .. hex(rw(head + 0x02)))
    -- gui.text(308,44,"XR: " .. hex(rw(head + 0x04)))
    -- gui.text(348,44,"YR: " .. hex(rw(head + 0x06)))
    local head_box_coords = collisionbox(head,px,py,{0x00,0xFF,0xFF,0x00},pflip) 
    -- drawaxis(px,py,8)
    -- gui.box()
    return {
        head = head_box_coords,
        base = { x = px, y = py }
    }

end

local function draw_projectile_count_limiter( _ , coords)
    local projectile_count_limiter = memory.readbyte(0xFFF9BE)
    gui.text(135,50, "Projectile Allocation Value: ".."0x"..to_hex(projectile_count_limiter))
end

local function draw_invuln_timer( player_adr , coords)
    local invuln_timer = memory.readbyte(player_adr + 0x147)
    if invuln_timer ~= 0 then
        gui.rect(coords.base.x - 20, coords.base.y - 100, coords.base.x - 20 + (invuln_timer * 2), coords.base.y - 110, 0x00FF0099,0x00000099)
        gui.text(coords.base.x - 17, coords.base.y - 108, invuln_timer)
        gui.text((coords.base.x - 35), coords.base.y - 108, "Inv." )
    end
end

local function draw_throw_invuln(player_adr, coords)
    local invuln_timer = memory.readbyte(player_adr + 0x143) 	-- Throw Invulnerability Timer 
    if invuln_timer ~= 0 then
        gui.rect(coords.base.x - 20, coords.base.y - 112, coords.base.x - 20 + (invuln_timer * 7), coords.base.y - 122, 0xFFFF0099,0x00000099)
        gui.text(coords.base.x - 17, coords.base.y - 120, invuln_timer)
        gui.text((coords.base.x - 57), coords.base.y - 120, "Throw Inv" )
    end
end

-- THESE THREE LINES DISAGREE WITH EACH OTHER. SEE
-- analysis/ISSUE-PURSUIT-INDICATOR-001.md BEFORE CHANGING ANY OF THEM.
--
-- Two of the three are guarded by globals.options.show_ground_special, which
-- has no default in config.lua and no row in the menu - so it is always nil and
-- Player OK / Pursuit OK have never been drawn. On top of that the first two
-- both read P1 while calling it "Opponent" and "Player", and get_pursuit_ok()
-- in dummyState.lua ANDs them, which only makes sense for one actor. Which of
-- the two labels is wrong cannot be settled from Lua: it needs ROM 0x27ACC and
-- 0x27B14, where can_pursuit is cleared and set.
--
-- Left alone deliberately (2026-09-13): the user does not want the feature and
-- a half-measure here would just be a different kind of wrong.
local function draw_pursuit_timer(player, coords)
  local player_can_pursuit = false --Pursuit Enabled
  if player == 1 then
    player_can_pursuit = globals.dummy.p1_can_pursuit
  else
    player_can_pursuit = globals.dummy.p2_can_pursuit
  end

  if player_can_pursuit == true and globals.options.show_pursuit_indicator == true then
    gui.text(23, 119, "Opponent OK", "green")
  elseif globals.options.show_pursuit_indicator == true then
    gui.text(23, 119, "Opponent OK", "grey")
  end
end

local function draw_ground_special(player, coords)
  local player_ground_special = false
  if player == 1 then
     player_ground_special = globals.dummy.p1_ground_special
  else
     player_ground_special = globals.dummy.p2_ground_special
  end

  if player_ground_special == true and globals.options.show_pursuit_indicator == true then
    gui.text(23, 111, "Player   OK", "green")
  elseif globals.options.show_pursuit_indicator == true then
    gui.text(23, 111, "Player   OK", "grey")
  end
end

local function draw_pursuit_OK()
  local player_ground_special = false
  local player_can_pursuit = false

  if globals.controlling_p1 == true then
    player_ground_special = globals.dummy.p1_ground_special
    player_can_pursuit = globals.dummy.p1_can_pursuit
  else
    player_ground_special = globals.dummy.p2_ground_special
    player_can_pursuit = globals.dummy.p2_can_pursuit
  end
 
  if player_ground_special == true and player_can_pursuit == true and globals.options.show_pursuit_indicator == true
  then
    globals.dummy.player_pursuit_ok = true 
    gui.text(23, 127, "Pursuit  OK", "green")
  elseif globals.options.show_pursuit_indicator == true then
    globals.dummy.player_pursuit_ok = false
    gui.text(23, 127, "Pursuit  OK", "grey")
  end
  if 
    globals.controlling_p1 == true and 
    globals.p1_last_pursuit_length and 
    globals.p1_last_pursuit_length > 0 and
    globals.options.show_pursuit_indicator == true
  then
    gui.text(72,127, globals.p1_last_pursuit_length.."F", "green")
  elseif 
    globals.p2_last_pursuit_length and 
    globals.p2_last_pursuit_length > 0 and
    globals.options.show_pursuit_indicator == true
  then
    gui.text(72,27, globals.p2_last_pursuit_length.."F", "green")
  end
  -- print("last 1", globals.p2_last_pursuit_length)
  -- if
  --   globals.controlling_p1 ~= true and 
  --   globals.p2_last_pursuit_length and
  --   globals.p2_last_pursuit_length > 0 
  -- then
  --   gui.text(72,27, globals.p2_last_pursuit_length.."F", "green")
  -- end  
end

local function draw_curse_timer(player_adr, coords)
    local curse_timer = memory.readword(player_adr + 0x156) 	-- Curse Timer  
    if curse_timer ~= 0 then
        gui.rect(coords.base.x - 20, coords.base.y - 32, coords.base.x - 20 + (curse_timer * 1), coords.base.y - 42, 0xFF00FF99,0x00000099)
        gui.text(coords.base.x - 17, coords.base.y - 40, curse_timer)
        gui.text((coords.base.x - 55), coords.base.y - 40, "Curse" )
    end
end

local function draw_mash_timer(player_adr, coords)
    local mash_timer = memory.readword(player_adr + 0x15C) 	-- Mash Timer 
    if mash_timer ~= 0 then
        gui.rect(coords.base.x - 20, coords.base.y - 112, coords.base.x - 20 + (mash_timer * 2), coords.base.y - 122, 0x00FFFF99,0x00000099)
        gui.text(coords.base.x - 17, coords.base.y - 120, mash_timer)
        gui.text((coords.base.x - 55), coords.base.y - 120, "Mash" )
    end
end

local function draw_push_block_timer(player_adr, coords)
    local push_block_timer = memory.readbyte(player_adr + 0x1AB) 	-- Pushblock timer
    if push_block_timer ~= 0 then
        gui.rect(coords.base.x - 20, coords.base.y - 112, coords.base.x - 20 + (push_block_timer * 3), coords.base.y - 122, 0xFF00FF99,0x00000099)
        gui.text(coords.base.x - 17, coords.base.y - 120, push_block_timer)
        gui.text((coords.base.x - 35), coords.base.y - 120, "PB" )
    end
end

local function draw_push_block_push_back_timer(player_adr, coords)
    local push_block_push_back_timer = memory.readword(player_adr + 0x1B0) 	-- Pushblock pushback timer
    if push_block_push_back_timer ~= 0 then
        gui.rect(coords.base.x - 20, coords.base.y - 112, coords.base.x - 20 + (push_block_push_back_timer * 3), coords.base.y - 122, 0xDDA0DD99,0x00000099)
        gui.text(coords.base.x - 17, coords.base.y - 120, push_block_push_back_timer)
        gui.text((coords.base.x - 65), coords.base.y - 120, "PB PushBack" )
    end
end

local function get_move_strength(move_strength)
    if move_strength == 0 then 
        move_strength_display = "None / Light"
    elseif move_strength == 1 then 
        move_strength_display = "Medium"
    elseif move_strength == 2 then 
        move_strength_display = "Heavy"
    elseif move_strength == 3 then 
        move_strength_display = "ES"
    else
        move_strength_display = ""
    end
    return move_strength.." ( "..move_strength_display.." )"
end

local function draw_move_strength_display(player_adr)
    local move_strength_p1 = memory.readbyte(0xFF8859)
    local move_strength_display_p1 = get_move_strength(move_strength_p1)

    local move_strength_p2 = memory.readbyte(0xFF8459)
    local move_strength_display_p2 = get_move_strength(move_strength_p2)

    local push_block_push_back_timer_p1 = memory.readword(0xFF8400 + 0x1B0) 
    local push_block_push_back_timer_p2 = memory.readword(0xFF8800 + 0x1B0) 

    gui.text(50,50,"P1 Last Got Hit By       : "..move_strength_display_p2)
    gui.text(50,58,"P2 Last Got Hit By       : "..move_strength_display_p1)
    gui.text(50,66,"P1 Push Back Timer Value : "..push_block_push_back_timer_p1)
    gui.text(50,74,"P2 Push Back Timer Value : "..push_block_push_back_timer_p2)
end


local timerModule = {
  ["guiRegister"] = function()
    -- print("action timer", memory.readword(0xFF8400 + 0x26) )
    -- print("push back", memory.readbyte(0xFF8800 + 0x1B0))
    local p1_coords = getHeadBoxTopXY(0xFF8400)
    local p2_coords = getHeadBoxTopXY(0xFF8800)
    if globals.options.show_pb_pushback_timer then
      draw_push_block_push_back_timer( 0xFF8400, p1_coords)
      draw_push_block_push_back_timer( 0xFF8800, p2_coords)
    end
    if globals.options.show_move_strength then
      draw_move_strength_display()
    end
    if globals.options.show_pb_timer then
      draw_push_block_timer( 0xFF8400, p1_coords)
      draw_push_block_timer( 0xFF8800, p2_coords)
    end
    if globals.options.show_curse_timer then
      draw_curse_timer( 0xFF8400, p1_coords)
      draw_curse_timer( 0xFF8800, p2_coords)
    end
    if globals.options.show_throw_invuln_timer then
      draw_throw_invuln( 0xFF8400, p1_coords)
      draw_throw_invuln( 0xFF8800, p2_coords)
    end
    if globals.options.show_mash_timer then
      draw_mash_timer( 0xFF8400, p1_coords)
      draw_mash_timer( 0xFF8800, p2_coords)
    end
    if globals.options.show_invuln_timer then
      draw_invuln_timer( 0xFF8400, p1_coords)
      draw_invuln_timer( 0xFF8800, p2_coords)
    end
    if globals.options.show_projectile_count_limiter then
      draw_projectile_count_limiter()
    end
    if globals.options.show_pursuit_indicator then
      draw_pursuit_timer(1, 23, 119)
    end
    if globals.options.show_ground_special then
      draw_ground_special(1, 23, 111)
    end
    if globals.options.show_ground_special and globals.options.show_pursuit_indicator then
      draw_pursuit_OK(1)
      -- draw_pursuit_OK(2)
    end
  end,
  -- Driven by the emulator's clock in the real thing; exported so the offline
  -- test can step it by hand, which nothing else can do.
  ["latemash_tick"] = latemash_tick,
  ["registerBefore"] = function()
    -- SUBSCRIBED ONCE, LAZILY. This module is required before globals.truth
    -- exists, so it cannot be done at load; registerBefore runs every frame
    -- and the flag keeps it to one subscription.
    if not om_subscribed and globals ~= nil and globals.truth ~= nil
       and globals.truth.ticker ~= nil then
      om_subscribed = true
      globals.truth.ticker:subscribe(function() latemash_tick() end)
    end
    -- Both counts are maintained by the tick hook above; nothing to sample
    -- here. (v186 added the dummy's count beside P1's so "Guard Action =
    -- Push Block" had feedback on screen instead of only in a log.)
    return timers
  end
}

return timerModule