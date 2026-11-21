-- The values to write
local roll_address       = 0xFF880A
local roll_toward_value  = 0x01
local roll_away_value    = 0xFF

-- These are the values for the roll options in the cheat
local roll_toward_option         = 0x2
local roll_away_option           = 0x3
local roll_random_option         = 0x4
local roll_random_toward_or_away = 0x5
local roll_none                  = 0x1

local function getRandomIntBetween( lower, upper )
    return math.random(lower, upper)
end

local function getDirection()
    -- This is direction set by the user in cheats
    local direction = globals.options.roll_direction
    -- Handle random rolls
    if direction == roll_random_option then
        flag = getRandomIntBetween(0,2)
        if flag == 1 then
            return roll_toward_value
        elseif flag == 2 then
            return roll_away_value
        else
            return 0x0
        end
    end
    if direction == roll_random_toward_or_away then
        flag = getRandomIntBetween(1,2)
        if flag == 1 then
            return roll_toward_value
        else
            return roll_away_value
        end
    end
    if direction == roll_toward_option then
        return roll_toward_value
    end
    
    if direction == roll_away_option then
        return roll_away_value
    end

    return 0x0

end

-- TOWARDS AND AWAY ARE THE OPPONENT'S, NOT THE DUMMY'S FACING (user,
-- 2026-11-21: "Towards" felt reversed depending on which way the dummy faced).
-- The game reads $0A by the dummy's own facing: 0x024EB8 takes $0A > 0 to
-- $40 = -6 and $0A < 0 to +6, and 0x024F2A negates $40 when $0B is set
-- (facing right), so $0A > 0 rolls the way the dummy faces - a forward roll,
-- not a roll towards the opponent. 8 of the 78 knockdowns in the version 5
-- invuln logs (archive v11.7.33_3 to _6) lay facing away from the opponent;
-- there +1 rolled away. So the sign is flipped while the dummy faces away from
-- P1 ($10, the X word, compared; level X keeps the facing).
local function faces_opponent()
    local x, ox = memory.readword(0xFF8810), memory.readword(0xFF8410)
    if x == ox then return true end
    return (memory.readbyte(0xFF880B) ~= 0) == (ox > x)
end

local function rollToDirection( direction )
    if globals.dummy.enable_roll == true then
        if direction ~= 0x0 and not faces_opponent() then
            direction = (direction == roll_toward_value) and roll_away_value or roll_toward_value
        end
        memory.writebyte(roll_address, direction)
    end
end

rollingModule = {
    ["roll"] = function()
        -- Sets ram address to roll in the direction specified in cheat
        rollToDirection(getDirection())
    end
}
return rollingModule