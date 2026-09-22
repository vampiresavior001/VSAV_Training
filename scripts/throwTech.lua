-- HOW OFTEN THE DUMMY ESCAPES A THROW.
--
-- Was a checkbox: every throw, or none. Now the same five the Dummy tab's
-- other two rate rows offer - Guard Action Frequency and P2 Random Guard % -
-- because it is the same question about a different reaction.

-- ONE ROLL PER THROW, NOT ONE PER FRAME.
--
-- registerBefore runs every frame the dummy is in "Be Thrown", and the escape
-- succeeds if the input is present on ANY of them. Rolling here would make
-- every setting above None come out as
--
--     P(escape) = 1 - (1 - p)^frames-of-throw
--
-- which is ~100% over the length of a throw. That is exactly the trap Guard
-- Action Frequency fell into - see the note above shouldGC in guardCancel.lua -
-- and the fix is the same: roll on the edge into the state and hold the answer
-- until the state ends.
--
-- nil means "not in a throw", so the next one rolls again.
local tech_roll = nil

local function maybe(x)
    if 100 * math.random() < x then
        return true
    else
        return false
    end
end

-- The numbers are the ones on the menu. Both other rate rows carried a
-- ten-point lie here (35 and 65 under labels reading 25% and 75%); written out
-- so the same drift is visible if it ever starts.
local function rolled_tech()
    local _v = globals.options.p2_throw_tech
    if _v == 0x2 then return maybe(25) end
    if _v == 0x3 then return maybe(50) end
    if _v == 0x4 then return maybe(75) end
    if _v == 0x5 then return true end
    if _v == 0x1 then return false end
    -- A file saved before this was a rate reads as a boolean. The migration in
    -- utilities.lua converts it, but a value that reaches here unconverted must
    -- not be silently read as None.
    if _v == true then return true end
    return false
end

throwTechModule = {
    ["registerBefore"] = function(cur_keys)

        if globals.dummy.p2_status_1 ~= "Be Thrown" then
            tech_roll = nil
            return
        end

        if tech_roll == nil then tech_roll = rolled_tech() end
        if not tech_roll then return end

        local towards_btn    = globals.dummy.p2_away_btn
        cur_keys[towards_btn] = true
        cur_keys["P2 Medium Punch"] = true
    end
}

return throwTechModule
