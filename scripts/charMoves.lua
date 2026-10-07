local function get_character(base_addr)
    local char_id = memory.readbyte(base_addr + 0x382)
    if     char_id == 0x00  then return "Bulleta"
    elseif char_id == 0x01 	then return "Demitri"
    elseif char_id == 0x02 	then return "Gallon"
    elseif char_id == 0x03 	then return "Victor"
    elseif char_id == 0x04 	then return "Zabel"
    elseif char_id == 0x05 	then return "Morrigan"
    elseif char_id == 0x06 	then return "Anakaris"
    elseif char_id == 0x07 	then return "Felicia"
    elseif char_id == 0x08 	then return "Bishamon"
    elseif char_id == 0x09 	then return "Aulbath"
    elseif char_id == 0x0A 	then return "Sasquatch"
    elseif char_id == 0x0B 	then return "Zabel"
    elseif char_id == 0x0C 	then return "Q-Bee"
    elseif char_id == 0x0D 	then return "Lei-Lei"
    elseif char_id == 0x0E 	then return "Lilith"
    elseif char_id == 0x0F 	then return "Jedah"
    elseif char_id == 0x12 	then return "Dark Gallon"
    elseif char_id == 0x18 	then return "Oboro" end
end

function get_moves_Morrigan()
    -- PL1 (MO) FF8506
    -- 00 = Finishing Shower
    -- 02 = Shadow Blade
    -- 04 = Soul Fist
    -- 06 = Air Soul Fist
    -- 08 = Darkness Illusion
    -- 0A = Cryptic Needle
    -- 0C = Valkyrie Turn
    -- 0E = Vector Drain
    -- 10 = Pursuit
    -- 12 = Taunt
    -- 14 = Incomplete Animation - Invincible
    return {
        {value = 0x00, name = "Finishing Shower",   conditions = {}, isReversalMove = true  , isEX = true},
        {value = 0x02, name = "Shadow Blade",       conditions = {}, isReversalMove = true  },
        {value = 0x04, name = "Soul Fist",          conditions = {}, isReversalMove = true  },
        {value = 0x06, name = "Air Soul Fist",      conditions = {}, isReversalMove = false },
        {value = 0x08, name = "Darkness Illusion",  conditions = {}, isReversalMove = true  , isEX = true},
        {value = 0x0A, name = "Cryptic Needle",     conditions = {}, isReversalMove = true  , isEX = true},
        {value = 0x0C, name = "Valkyrie Turn",      conditions = {}, isReversalMove = true  , isEX = true},
        {value = 0x0E, name = "Vector Drain",       conditions = {}, isReversalMove = true  },
        {value = 0x10, name = "Pursuit",            conditions = {}, isReversalMove = false , isPursuit = true },
        {value = 0x12, name = "Taunt",              conditions = {}, isReversalMove = true },
        -- {value = 0x14, name = "Incomplete Animation - Invincible"},
    }
end
function get_moves_Demitri()
    -- PL1 (DE) FF8506
    -- 00 = Ground Chaos Flare
    -- 02 = Air Chaos Flare
    -- 04 = Demon Cradle
    -- 06 = Dash DP
    -- 08 = Negative Stolen
    -- 0A = Pursuit
    -- 0C = Bat Spin
    -- 0E = Demon Billion
    -- 10 = Midnight Bliss
    -- 12 = Taunt
    -- 14 = Midnight Pleasure
    -- 16 = Crash
    return {
        {value = 0x00, name = "Ground Chaos Flare", conditions = {}, isReversalMove = true  },
        {value = 0x02, name = "Air Chaos Flare",    conditions = {}, isReversalMove = false },
        {value = 0x04, name = "Demon Cradle",       conditions = {}, isReversalMove = true  },
        -- WHAT IT IS CALLED ON SCREEN, WHICH IS NOT THE KEY.
        --
        -- 0x06 is a Demon Cradle done out of a dash - the game gives it its own
        -- id, and this file named it for what it is rather than for what the
        -- player asked for. The Action Route row reads out what the player just
        -- did, and Action Steps calls that move Demon Cradle (0x06 has no
        -- command entry, so the editor never offers "Dash DP" at all). Two
        -- names for the same input was the complaint (user, 2026-09-10).
        --
        -- name stays the game data name: saved steps and the reversal list are
        -- keyed on it, the same rule the command table's display_name follows.
        {value = 0x06, name = "Dash DP",            conditions = {}, isReversalMove = true, display_name = "Demon Cradle" },
        {value = 0x08, name = "Negative Stolen",    conditions = {}, isReversalMove = true  },
        {value = 0x0A, name = "Pursuit",            conditions = {}, isReversalMove = false , isPursuit = true },
        {value = 0x0C, name = "Bat Spin",           conditions = {}, isReversalMove = true  },
        {value = 0x0E, name = "Demon Billion",      conditions = {}, isReversalMove = true  , isEX = true  },
        {value = 0x10, name = "Midnight Bliss",     conditions = {}, isReversalMove = true  , isEX = true  },
        {value = 0x12, name = "Taunt",              conditions = {}, isReversalMove = true  },
        {value = 0x14, name = "Midnight Pleasure",  conditions = {}, isReversalMove = true  , isEX = true  },
    }
end
function get_moves_Bulleta()
    -- 00 = High Missile
    -- 02 = Low Missile
    -- 04 = Molotov Cocktail
    -- 06 = Basket
    -- 08 = Apple 4 You
    -- 0A = Pursuit
    -- 0C = Vert Missile
    -- 0E = Beautiful Memory
    -- 10 = Sentimental Typhoon
    -- 12 = Guard Cancel
    -- 14 = Huntsman
    -- 16 = Tell Me Why
    -- 18 = Taunt
    -- 1A = Not Allocated - No crash
    -- 1C = Crash
    return {
        {value = 0x00, name = "High Missile",           conditions = {}, isReversalMove = true  },
        {value = 0x02, name = "Low Missile",            conditions = {}, isReversalMove = true  },
        {value = 0x04, name = "Molotov Cocktail",       conditions = {}, isReversalMove = true  },
        {value = 0x06, name = "Basket",                 conditions = {}, isReversalMove = true  },
        {value = 0x08, name = "Apple 4 You",            conditions = {}, isReversalMove = true  , isEX = true  },
        {value = 0x0A, name = "Pursuit",                conditions = {}, isReversalMove = false , isPursuit = true },
        {value = 0x0C, name = "Vert Missile",           conditions = {}, isReversalMove = true  },
        {value = 0x0E, name = "Beautiful Memory",       conditions = {}, isReversalMove = true  , isEX = true },
        {value = 0x10, name = "Sentimental Typhoon",    conditions = {}, isReversalMove = true  },
        {value = 0x12, name = "Guard Cancel",           conditions = {}, isReversalMove = true  },
        {value = 0x14, name = "Cool Hunting",           conditions = {}, isReversalMove = true  , isEX = true},
        {value = 0x16, name = "Tell Me Why",            conditions = {}, isReversalMove = true  },
        {value = 0x18, name = "Taunt",            conditions = {}, isReversalMove = true  },
    }
end
function get_moves_Gallon()
    -- PL1 (GA) FF8506
    -- 00 = Climb Razor
    -- 02 = Million Flicker
    -- 04 = Dragon Cannon
    -- 06 = Moment Slice
    -- 08 = Horiz. Beast.C
    -- 0A = Vert. Beast.C
    -- 0C = 3- Beast.C
    -- 0E = 8-Beast.C
    -- 10 = 2-Beast.C
    -- 12 = Pursuit
    -- 14 = Wild Circular
    -- 16 = Quick Move
    -- 18 = Taunt
    -- 1A = Unlisted - No Crash
    -- 1C = Crash
    return {
        {value = 0x00, name = "Climb Razor",        conditions = {}, isReversalMove = true  },
        {value = 0x02, name = "Million Flicker",    conditions = {}, isReversalMove = true  },
        {value = 0x04, name = "Dragon Cannon",      conditions = {}, isReversalMove = true  , isEX = true},
        {value = 0x06, name = "Moment Slice",       conditions = {}, isReversalMove = true  , isEX = true },
        {value = 0x08, name = "Horiz. Beast Cannon (qcf)",  conditions = {}, isReversalMove = true },
        {value = 0x0A, name = "Vert. Beast Cannon (dp)",    conditions = {}, isReversalMove = true  },
        {value = 0x0C, name = "3-Beast Cannon",             conditions = {}, isReversalMove = false },
        {value = 0x0E, name = "8 Beast Cannon",     conditions = {}, isReversalMove = true  },
        {value = 0x10, name = "2 Beast Cannon",     conditions = {}, isReversalMove = false },
        {value = 0x12, name = "Pursuit",            conditions = {}, isReversalMove = false , isPursuit = true },
        {value = 0x14, name = "Wild Circular",      conditions = {}, isReversalMove = true  },
        {value = 0x16, name = "Quick Move",         conditions = {}, isReversalMove = true  },
        {value = 0x18, name = "Taunt",            conditions = {}, isReversalMove = true  },
    }
end
function get_moves_Victor()
    -- PL1 (VI) FF8506
    -- 00 = Gyro Crush
    -- 02 = Giga Burn
    -- 04 = Giga Hammer - !!Night Warriors!!
    -- 06 = Giga Buster - !!Night Warriors!!
    -- 08 = Pursuit
    -- 0A = Mega Shock
    -- 0C = Minimum Step
    -- 0E = 360
    -- 10 = Thunder Break
    -- 12 = Mega Forehead
    -- 14 = Mega Stake
    -- 16 = Taunt
    -- 18 = 720
    -- 1A = 720-Taunt
    -- 1C = Crash
    return {
        {value = 0x00, name = "Gyro Crush",                 conditions = {}, isReversalMove = true  },
        {value = 0x02, name = "Giga Burn ",                 conditions = {}, isReversalMove = true  },
        {value = 0x04, name = "Giga Hammer ~~Easter Egg~~", conditions = {}, isReversalMove = true  },
        {value = 0x06, name = "Giga Buster ~~Easter Egg~~", conditions = {}, isReversalMove = true  },
        {value = 0x08, name = "Pursuit",                    conditions = {}, isReversalMove = false , isPursuit = true },
        {value = 0x0A, name = "Mega Shock",                 conditions = {}, isReversalMove = true  },
        {value = 0x0C, name = "Minimum Step",               conditions = {}, isReversalMove = true  },
        {value = 0x0E, name = "Mega Spike",                 conditions = {}, isReversalMove = true  },
        {value = 0x10, name = "Thunder Break",              conditions = {}, isReversalMove = true  , isEX = true },
        {value = 0x12, name = "Mega Forehead",              conditions = {}, isReversalMove = true  },
        {value = 0x14, name = "Mega Stake",                 conditions = {}, isReversalMove = true  },
        {value = 0x16, name = "Taunt",                      conditions = {}, isReversalMove = true  },
        {value = 0x18, name = "Gerdenheim 3",               conditions = {}, isReversalMove = true  , isEX = true},
    }
end
function get_moves_Zabel()
    -- 00 = Skull Sting
    -- 02 = Air Death Hurricane   = Death Hurricane. The move exists on the
    --                            ground too and the command is the same, but
    --                            this VALUE is the air one - see isActionStepOnly
    -- 04 = Death Voltage
    -- 06 = Skull Punish
    -- 08 = Evil Scream
    -- 0A = Hell Dunk
    -- 0C = Hell Gate
    -- 0E = Pursuit
    -- 10 = Guard Cancel
    -- 12 = Taunt
    -- 14 = Incomplete no animation
    return {
        {value = 0x00, name = "Skull Sting",            conditions = {}, isReversalMove = true  },
        {value = 0x02, name = "Air Death Hurricane",    conditions = {}, isReversalMove = false , isActionStepOnly = true },
        {value = 0x04, name = "Death Voltage",          conditions = {}, isReversalMove = true  , isEX = true },
        {value = 0x06, name = "Skull Punish",           conditions = {}, isReversalMove = true  },
        {value = 0x08, name = "Evil Scream",            conditions = {}, isReversalMove = true  , isEX = true },
        {value = 0x0A, name = "Hell Dunk",              conditions = {}, isReversalMove = true  , isEX = true },
        {value = 0x0C, name = "Hell Gate",              conditions = {}, isReversalMove = true  },
        {value = 0x0E, name = "Pursuit",                conditions = {}, isReversalMove = false , isPursuit = true },
        {value = 0x10, name = "Guard Cancel",           conditions = {}, isReversalMove = true  },
        {value = 0x12, name = "Taunt",                  conditions = {}, isReversalMove = true  },
    }
end
function get_moves_Anakaris()
    -- 00 = Coffin
    -- 02 = Spell of Turn - IN
    -- 04 = Spell of Turn - OUT
    -- 06 = Curse            = Royal Judgement (air)
    -- 08 = Cobra Blow
    -- 0A = Hands            = Mummy Drop (ground)
    -- 0C = Float
    -- 0E = Pit to Underworld
    -- 10 = P.Magic
    -- 1E = P.Magic
    -- 12 = Pursuit
    -- 14 = P.Salvation
    -- 16 = Pit of Blame
    -- 18 = Guard Cancel
    -- 1A = Taunt
    -- 1C = P.Decoration
    --
    -- 14 AND 1C WERE THE WRONG WAY ROUND until 2026-10-07. 0x14 is Pharaoh
    -- Salvation (HK MP 2 MK HP, 2 levels) and 0x1C Pharaoh Decoration (HK MP LK
    -- 2 LP MK HP, 3 levels): darkstalkers.web.fc2.com's Anakaris EX move page,
    -- checked against the ROM (user). vsavscriptv2.lua's Salvation readout keys
    -- on the same 0x14 ($105-$106 = 0x0114). With them swapped, picking
    -- "P. Salvation" as a Character Specific Reversal poked Decoration, and
    -- Tick Data named each one as the other.
    --
    -- Only the values moved. The names stay as they were - Action Steps save
    -- the name and find the command by it (character_command_registry below,
    -- whose commands were right all along) - and so does the order, because
    -- p2_reversal_list saves a position in this list.
    return {
        {value = 0x00, name = "Coffin",             conditions = {}, isReversalMove = true },
        {value = 0x02, name = "Spell of Turn - IN", conditions = {}, isReversalMove = true },
        {value = 0x04, name = "Spell of Turn - OUT",conditions = {}, isReversalMove = true },
        {value = 0x06, name = "Curse",              conditions = {}, isReversalMove = true },
        {value = 0x08, name = "Cobra Blow",         conditions = {}, isReversalMove = true },
        {value = 0x0A, name = "Hands",              conditions = {}, isReversalMove = true },
        {value = 0x0C, name = "Float",              conditions = {}, isReversalMove = true },
        {value = 0x0E, name = "Pit to Underworld",  conditions = {}, isReversalMove = true  , isEX = true },
        {value = 0x10, name = "Pharoah Magic",      conditions = {}, isReversalMove = true  , isEX = true },
        {value = 0x1E, name = "Pharoah Magic",      conditions = {}, isReversalMove = true  , isEX = true },
        {value = 0x14, name = "P. Salvation",       conditions = {}, isReversalMove = true  , isEX = true },
        {value = 0x1C, name = "Pharoah Decoration", conditions = {}, isReversalMove = true  , isEX = true },
        {value = 0x12, name = "Pursuit",            conditions = {}, isReversalMove = false , isPursuit = true },
        {value = 0x16, name = "Pit of Blame",       conditions = {}, isReversalMove = true  },
        {value = 0x18, name = "Guard Cancel",       conditions = {}, isReversalMove = false },
        -- FIX: a second "Pit of Blame" entry sat here with value 0x1C, which
        -- is a super (Pharaoh Decoration - see the note above the list; when
        -- this was removed the list still had it as P. Salvation). Name lookups
        -- (dummyState.lua get_p2_char_specific_reversal) keep the LAST match,
        -- so picking "Pit of Blame" in the menu silently poked 0x1C instead of
        -- the correct 0x16 above. Duplicate removed.
        {value = 0x1A, name = "Taunt",              conditions = {}, isReversalMove = true  },
    }
end
function get_moves_Felicia()
    -- 00 = Taunt
    -- 02 = 22+KK
    -- 04 = Rolling Buckler
    -- 06 = Delta Kick
    -- 08 = Cat Spike
    -- 0A = Hell Cat
    -- 0C = Dancing Flash
    -- 0E = Please Help Me
    -- 10 = Head Ride
    -- 12 = Toy Touch
    -- 14 = Pursuit
    -- 16 = Command Taunt
    -- 18 = Delta Kick (Previously could have been Sand Scratch ???)
    return {
        {value = 0x00, name = "Taunt",              conditions = {}, isReversalMove = true  },
        {value = 0x02, name = "22+KK",              conditions = {}, isReversalMove = true  },
        {value = 0x04, name = "Rolling Buckler",    conditions = {}, isReversalMove = true  },
        {value = 0x06, name = "Delta Kick",         conditions = {}, isReversalMove = true  },
        {value = 0x08, name = "Cat Spike",          conditions = {}, isReversalMove = true  },
        {value = 0x0A, name = "Hell Cat",           conditions = {}, isReversalMove = true  },
        {value = 0x0C, name = "Dancing Flash",      conditions = {}, isReversalMove = true  , isEX = true },
        {value = 0x0E, name = "Please Help me",     conditions = {}, isReversalMove = true  , isEX = true },
        {value = 0x10, name = "Head Ride",          conditions = {}, isReversalMove = false },
        {value = 0x12, name = "Toy Touch",          conditions = {}, isReversalMove = false },
        {value = 0x14, name = "Pursuit",            conditions = {}, isReversalMove = false , isPursuit = true },
        {value = 0x16, name = "Command Taunt",      conditions = {}, isReversalMove = true  },
        -- {value = 0x18, name = "Delta Kick ?", conditions = {}, isReversalMove = false},
    }
end
function get_moves_Bishamon()
    -- 00 = Kienzan - Uppercut
    -- 02 = Iai Giri High
    -- 04 = Iai Giri Low
    -- 06 = Air K.D.
    -- 08 = K.D.
    -- 0A = Command Throw
    -- 0C = Oni Kubi
    -- 0E = Bricks
    -- 10 = Pursuit
    -- 12 = OTG Slap-Chop
    -- 14 = K.D. 4+P
    -- 16 = K.D. Hayate
    -- 18 = K.D. ES-Hayate
    -- 1A = Taunt
    -- 1C = Not allocated
    return {
        {value = 0x00, name = "Kienzan",        conditions = {}, isReversalMove = true  },
        {value = 0x02, name = "Iai Giri High",  conditions = {}, isReversalMove = true  },
        {value = 0x04, name = "Iai Giri Low",   conditions = {}, isReversalMove = true  },
        {value = 0x06, name = "Air K.D.",       conditions = {}, isReversalMove = false },
        {value = 0x08, name = "K.D.",           conditions = {}, isReversalMove = true  },
        {value = 0x0A, name = "Command Throw",  conditions = {}, isReversalMove = true  },
        -- Oni Kubi Hineri is an EX move (6324PP) - user, 2026-09-05. The flag was
        -- missing while Bricks two lines down had it, and both are entered with
        -- two punches, so this reads as an omission rather than a distinction.
        -- It moves the row into EX Special AND changes the palette effect
        -- poke_special writes for a Character Specific reversal (0x1E, the EX
        -- flicker, instead of 0x1C).
        {value = 0x0C, name = "Oni Kubi",       conditions = {}, isReversalMove = true  , isEX = true},
        {value = 0x0E, name = "Bricks",         conditions = {}, isReversalMove = true  , isEX = true},
        {value = 0x10, name = "Pursuit",        conditions = {}, isReversalMove = false , isPursuit = true },
        {value = 0x12, name = "OTG Slap Chop",  conditions = {}, isReversalMove = false , isEX = true, isPursuit = true },
        {value = 0x14, name = "K.D. 4+P",       conditions = {}, isReversalMove = false },
        {value = 0x16, name = "K.D. Hayate",    conditions = {}, isReversalMove = false },
        {value = 0x18, name = "K.D. ES-Hayate?",conditions = {}, isReversalMove = false },
        {value = 0x1A, name = "Taunt",          conditions = {}, isReversalMove = true  },

    }
end
function get_moves_Aulbath()
    -- PL1 (AU) 0xFF8506

    -- 00 = Sonic Wave
    -- 02 = Gas
    -- 04 = Aqua Spread
    -- 06 = Incomplete - Crash
    -- 08 = Sea Rage
    -- 0A = Water Jail
    -- 0C = Direct Scissors
    -- 0E = Gem's Anger
    -- 10 = Crystal Lancer
    -- 12 = Trick Fish
    -- 14 = Pursuit
    -- 16 = Incomplete - Backdash startup ?
    -- 18 = Taunt
    return {
        {value = 0x00, name = "Sonic Wave",     conditions = {}, isReversalMove = true },
        {value = 0x02, name = "Gas",            conditions = {}, isReversalMove = true },
        {value = 0x04, name = "Aqua Spread",    conditions = {}, isReversalMove = true  , isEX = true },
        -- {value = 0x06, name = "Incomplete - Crash", conditions = {}, isReversalMove = false },
        {value = 0x08, name = "Sea Rage",       conditions = {}, isReversalMove = true  , isEX = true },
        {value = 0x0A, name = "Water Jail",     conditions = {}, isReversalMove = true  , isEX = true },
        {value = 0x0C, name = "Direct Scissors",conditions = {}, isReversalMove = true  , isEX = true },
        {value = 0x0E, name = "Gem's Anger",    conditions = {}, isReversalMove = true },
        {value = 0x10, name = "Crystal Lancer", conditions = {}, isReversalMove = true },
        {value = 0x12, name = "Trick Fish",     conditions = {}, isReversalMove = true },
        {value = 0x14, name = "Pursuit",        conditions = {}, isReversalMove = true , isPursuit = true },
        -- {value = 0x16, name = "Incomplete", conditions = {}, isReversalMove = false},
        {value = 0x18, name = "Taunt",          conditions = {}, isReversalMove = true },
    }
end
function get_moves_Sasquatch()
--     PL1 (SA) 0xFF8506

--     00 = Big Breath
--     02 = Big Banana
--     04 = Big Blow
--     06 = Big Towers
--     08 = Big Typhoon
--     0A = Big Freezer
--     0C = Big Swing
--     0E = Big Sledge
--     10 = Big Brunch
--     12 = Big Eisbhan
--     14 = Pursuit
--     16 = Taunt
--     18 = Incomplete - Can Crash
    return {
        {value = 0x00, name = "Big Breath",     conditions = {}, isReversalMove = true  },
        {value = 0x02, name = "Big Banana",     conditions = {}, isReversalMove = true  , isEX = true },
        {value = 0x04, name = "Big Blow",       conditions = {}, isReversalMove = true  },
        {value = 0x06, name = "Big Towers",     conditions = {}, isReversalMove = true  },
        {value = 0x08, name = "Big Typhoon",    conditions = {}, isReversalMove = true  },
        {value = 0x0A, name = "Big Freezer",    conditions = {}, isReversalMove = true  , isEX = true },
        {value = 0x0C, name = "Big Swing",      conditions = {}, isReversalMove = true  },
        {value = 0x0E, name = "Big Sledge",     conditions = {}, isReversalMove = true  , isEX = true },
        {value = 0x10, name = "Big Brunch",     conditions = {}, isReversalMove = true  },
        {value = 0x12, name = "Big Eisban",     conditions = {}, isReversalMove = true  , isEX = true },
        {value = 0x14, name = "Pursuit",        conditions = {}, isReversalMove = false , isPursuit = true },
        {value = 0x16, name = "Taunt",          conditions = {}, isReversalMove = true  },
        -- {value = 0x18, name = "Incomplete", conditions = {}, isReversalMove = false},
    }
end
function get_moves_QBee()
    -- 00 = Delta-A
    -- 02 = SxP
    -- 04 = OM
    -- 06 = C>R
    -- 08 = Pursuit
    -- 0A = QJ
    -- 0C = +B
    -- 10 = Taunt
    -- 12 = R.M.
    -- 14 = Not allocated - Can crash
    return {
        {value = 0x00, name = "Delta-A",    conditions = {}, isReversalMove = true  },
        {value = 0x02, name = "SxP",        conditions = {}, isReversalMove = true  },
        {value = 0x04, name = "OM",         conditions = {}, isReversalMove = true  },
        {value = 0x06, name = "C>R",        conditions = {}, isReversalMove = true  },
        {value = 0x08, name = "Pursuit",    conditions = {}, isReversalMove = false , isPursuit = true },
        {value = 0x0A, name = "QJ",         conditions = {}, isReversalMove = true  , isEX = true},
        {value = 0x0C, name = "+B",         conditions = {}, isReversalMove = true  , isEX = true},
        {value = 0x10, name = "Taunt",      conditions = {}, isReversalMove = true  },
        {value = 0x12, name = "R.M.",       conditions = {}, isReversalMove = true  },
        -- {value = 0x14, name = "Pursuit", conditions = {}, isReversalMove = false},
    }
end
function get_moves_LeiLei()    
--     00 = Pursuit
--     02 = Ankihou
--     04 = Henkyouki
--     06 = Senpuubu
--     08 = Houtengeki
--     0A = Chireitou
--     0C = Tenraiha
--     0E = Chuukadan
--     10 = Taunt
--     12 = Not allocated - can crash
    return {
        {value = 0x00, name = "Pursuit",    conditions = {}, isReversalMove = true , isPursuit = true },
        {value = 0x02, name = "Ankihou",    conditions = {}, isReversalMove = true },
        {value = 0x04, name = "Henkyouki",  conditions = {}, isReversalMove = true },
        {value = 0x06, name = "Senpuubu",   conditions = {}, isReversalMove = true },
        {value = 0x08, name = "Houtengeki", conditions = {}, isReversalMove = true },
        {value = 0x0A, name = "Chireitou",  conditions = {}, isReversalMove = true , isEX = true },
        {value = 0x0C, name = "Tenraiha",   conditions = {}, isReversalMove = true , isEX = true },
        {value = 0x0E, name = "Chuukadan",  conditions = {}, isReversalMove = true , isEX = true },
        {value = 0x10, name = "Taunt",      conditions = {}, isReversalMove = true },
    }
end
function get_moves_Lilith()
    -- 00 = Shining Blade
    -- 02 = Soul Flash
    -- 04 = Air Soul Flash
    -- 06 = Merry Twirl
    -- 08 = Splendor Love
    -- 0A = Super Jump
    -- 0C = Mystic Arrow
    -- 0E = Soul Flash (Lower) ?
    -- 10 = Air Soul Flash (Lower) ?
    -- 12 = Pursuit
    -- 14 = Taunt
    -- 16 = Puppet Show
    -- 18 = LI
    -- 1A = Not allocated - can crash
    return {
        {value = 0x00, name = "Shining Blade",  conditions = {}, isReversalMove = true  },
        {value = 0x02, name = "Soul Flash",     conditions = {}, isReversalMove = true  },
        {value = 0x04, name = "Air Soul Flash", conditions = {}, isReversalMove = false },
        {value = 0x06, name = "Merry Twirl",    conditions = {}, isReversalMove = true  },
        {value = 0x08, name = "Splendor Love",  conditions = {}, isReversalMove = true  , isEX = true},
        {value = 0x0A, name = "Super Jump",     conditions = {}, isReversalMove = true  },
        {value = 0x0C, name = "Mystic Arrow",   conditions = {}, isReversalMove = true  },
        -- {value = 0x0E, name = "Soul Flash (Lower?)", conditions = {}, isReversalMove = true },
        -- {value = 0x10, name = "Air Soul Flash (Lower?)", conditions = {}, isReversalMove = true },
        {value = 0x12, name = "Pursuit",        conditions = {}, isReversalMove = false , isPursuit = true },
        {value = 0x14, name = "Taunt",          conditions = {}, isReversalMove = true  },
        {value = 0x16, name = "Puppet Show",    conditions = {}, isReversalMove = true  , isEX = true},
        {value = 0x18, name = "LI",             conditions = {}, isReversalMove = true  , isEX = true},
    }
end
function get_moves_Jedah()
    -- 00 = Dio Sega
    -- 02 = Air Dio Sega
    -- 04 = Splecio - Guard Cancel
    -- 06 = Finale Rosso
    -- 08 = Prova di Servo
    -- 0A = Ira Spinta
    -- 0C = Nero fatica
    -- 0E = Pursuit
    -- 10 = San Bassale
    -- 12 = Taunt
    -- 14 = Unknown fly state - Weird
    return {
        {value = 0x00, name = "Dio Sega",       conditions = {}, isReversalMove = true  },
        {value = 0x02, name = "Air Dio Sega",   conditions = {}, isReversalMove = false },
        {value = 0x04, name = "Guard Cancel",   conditions = {}, isReversalMove = false },
        {value = 0x06, name = "Finale Rosso",   conditions = {}, isReversalMove = true  , isEX = true  },
        {value = 0x08, name = "Prova di servo", conditions = {}, isReversalMove = true  , isEX = true  },
        {value = 0x0A, name = "Ira Spinta",     conditions = {}, isReversalMove = true  },
        {value = 0x0C, name = "Nero Fatica",    conditions = {}, isReversalMove = true  },
        {value = 0x0E, name = "Pursuit",        conditions = {}, isReversalMove = false , isPursuit = true },
        {value = 0x10, name = "San Bassale",    conditions = {}, isReversalMove = true  },
        {value = 0x12, name = "Taunt",          conditions = {}, isReversalMove = true },
        -- {value = 0x14, name = "Unknown Fly State", conditions = {}, isReversalMove = true},
    }
end

-- Character Specific real-input command schema (2026-08-24).
--
-- IMPORTANT: isEX classifies the move; it does NOT describe how to enter it.
-- Input syntax is an orthogonal property held by move.command.type:
--   motion    : controller.lua motion plus a button rule
--   sequence  : ordered input steps, including direction GIFs between buttons
--   dedicated : an existing special-purpose timing/execution path
--   unsupported: not yet source-verified; never fall back to poke_special()
--
--
--
-- display_name IS WHAT THE EDITOR READS, NOT WHAT ANYTHING IS KEYED ON.
--
-- The keys here are the names in this file's own move lists - game data, shown
-- by the Reversal list too - and saved steps are keyed on them as "sp.<name>".
-- Several of those names differ from the ones players use: K.D. is Karame
-- Dama, Bricks is Enma Seki, Big Eisban is Big Eisbahn. So the readable name
-- rides alongside instead of replacing the key.
--
-- Q-Bee's C>R and QJ deliberately have none: they stay as they are.
--
-- Victor also has none. Mizuumi prefixes four of his moves "GIGA" where the
-- game and the Japanese frame data both say MEGA, so there the key is already
-- the right name and Mizuumi is the odd one out.
-- CHARGE MOVES LEAVE THE CHARGE OUT OF THE COMMAND.
--
-- Mizuumi writes them "[4],6P" and "[2],8KK". The bracket is a hold the player
-- has already made - it is not an input to send, and there is no length of it
-- this table could name that would be right for every situation. So motions
-- "[4]6" and "[2]8" carry only what is left: neutral, the direction, the
-- button. The charge is the user's job, made with Hold on the steps before,
-- held across a Wait if there is one (the Hold row's help says this).
--
-- The Mizuumi notation is kept verbatim in source_note, so the bracket that is
-- deliberately missing from the motion is still readable here.
-- A sequence is a property of the move itself. Each inner table is one input
-- step/tick; members of an inner table are simultaneous inputs. Directions are
-- relative to facing. Example: {"down","back"} is numpad 1, {"back"} is 4.
local character_command_registry = {
    ["Morrigan"] = {
        ["Finishing Shower"]  = {type="sequence", sequence={{"MP"},{"LP"},{"back"},{"LK"},{"MK"}}, verified=true, source_note="MP LP 4 LK MK"},
        -- The ES form (PPP) has to be selectable (user, 2026-09-05).
        -- button_group="P" offers the three strengths and nothing else, so the
        -- strengths are listed out and EXP added beside them.
        ["Shadow Blade"]      = {type="motion", motion="DPF", allowed_buttons={"LP","MP","HP","EXP"}, verified=true},
        ["Soul Fist"]         = {type="motion", motion="QCF", allowed_buttons={"LP","MP","HP","EXP"}, verified=true},
        ["Air Soul Fist"]     = {type="motion", motion="QCF", allowed_buttons={"LP","MP","HP","EXP"}, verified=true},
        ["Darkness Illusion"] = {type="sequence", sequence={{"LP"}, {}, {"LP"},{"forward"},{"LK"},{"HP"}}, verified=true, source_note="LP N LP 6 LK HP"},
        ["Cryptic Needle"]    = {type="sequence", sequence={{"forward"},{"HP"},{"MP"},{"LP"},{"forward"}}, verified=true, source_note="6 HP MP LP 6"},
        ["Valkyrie Turn"]     = {type="motion", motion="HCB-full", button_group="K", ex_button_pair=true, verified=true},
        ["Vector Drain"]      = {type="motion", motion="HCB", allowed_buttons={"MP","HP","EXP"}, verified=true},
        ["Pursuit"]                     = {type="motion", motion="up", allowed_buttons={"LP","MP","HP","LK","MK","HK","EXP","EXK"}, verified=true, source_note="Mizuumi: 8P/K or 8KK/PP"},
    },
    ["Demitri"] = {
        ["Ground Chaos Flare"] = {type="motion", motion="QCF", allowed_buttons={"LP","MP","HP","EXP"}, display_name="Chaos Flare", verified=true},
        ["Air Chaos Flare"]    = {type="motion", motion="QCF", allowed_buttons={"LP","MP","HP","EXP"}, verified=true},
        ["Demon Cradle"]       = {type="motion", motion="DPF", allowed_buttons={"LP","MP","HP","EXP"}, verified=true},
        ["Negative Stolen"]    = {type="motion", motion="360", allowed_buttons={"MP","HP"}, verified=true},
        ["Bat Spin"]           = {type="motion", motion="QCB", allowed_buttons={"LK","MK","HK","EXK"}, verified=true},
        ["Midnight Pleasure"]  = {type="sequence", sequence={{"LP"},{"MP"},{"forward"},{"MK"}, {}, {"MK"}}, verified=true, source_note="LP MP 6 MK N MK"},
        ["Demon Billion"]               = {type="motion", motion="263", allowed_buttons={"EXK"}, verified=true, source_note="Mizuumi: 263KK"},
        ["Midnight Bliss"]              = {type="motion", motion="263", allowed_buttons={"EXP"}, verified=true, source_note="Mizuumi: 263PP"},
        ["Pursuit"]                     = {type="motion", motion="up", allowed_buttons={"LP","MP","HP","LK","MK","HK","EXP","EXK"}, verified=true, source_note="Mizuumi: 8P or 8K, ES added on measurement - user 2026-09-05"},
    },
    ["Gallon"] = {
        -- REPORTED WRONG IN GAME (2026-09-04), CORRECT COMMAND NOT YET KNOWN.
        -- Left here rather than deleted so the gap is visible; verified=false
        -- keeps it out of the Special list until someone supplies the command.
        ["Climb Razor"]                 = {type="motion", motion="2~8", allowed_buttons={"LK","MK","HK","EXK"}, verified=true, source_note="Mizuumi: 2~8K"},
        ["Million Flicker"]           = {type="motion", motion="QCB", allowed_buttons={"LP","MP","HP","EXP"}, verified=true},
        ["Horiz. Beast Cannon (qcf)"] = {type="motion", motion="QCF", allowed_buttons={"LP","MP","HP","EXP"}, verified=true},
        ["Vert. Beast Cannon (dp)"]   = {type="motion", motion="DPF", allowed_buttons={"LP","MP","HP","EXP"}, display_name="Diagonal Beast Cannon", verified=true, source_note="Mizuumi: 623P (DIAGONAL BEAST CANNON). The registry row was already here - what was missing was isReversalMove on the game data entry"},
        ["Wild Circular"]             = {type="motion", motion="HCB", allowed_buttons={"MK","HK","EXK"}, verified=true, source_note="HCB + K. Was 360, which is not the command - user verified in game 2026-09-04"},
        ["Moment Slice"]                = {type="sequence", sequence={{"LP"},{"MP"},{"forward"},{"LK"},{"MK"}}, verified=true, source_note="Mizuumi: LP,MP,6,LK,MK"},
        ["Dragon Cannon"]               = {type="motion", motion="HCF", allowed_buttons={"EXK"}, verified=true, source_note="Mizuumi: 4123KK"},
        ["Quick Move"]                  = {type="motion", motion="down", allowed_buttons={"EXK"}, verified=true, source_note="Mizuumi: 1/2/3KKK"},
        ["Pursuit"]                     = {type="motion", motion="up", allowed_buttons={"LP","MP","HP","LK","MK","HK","EXP","EXK"}, verified=true, source_note="Mizuumi: 8P or 8K, ES added on measurement - user 2026-09-05"},
    },
    ["Felicia"] = {
        ["Rolling Buckler"] = {type="motion", motion="QCF", allowed_buttons={"LP","MP","HP","EXP"}, verified=true},
        ["Delta Kick"]      = {type="motion", motion="DPF", allowed_buttons={"LK","MK","HK","EXK"}, verified=true, source_note="DPF + K. Was QCB, which is not the command - user verified in game 2026-09-04"},
        ["Cat Spike"]       = {type="motion", motion="DPF", allowed_buttons={"LP","MP","HP","EXP"}, verified=true},
        ["Hell Cat"]        = {type="motion", motion="HCB", allowed_buttons={"MK","HK","EXK"}, verified=true, source_note="HCB + K. Was 360, which is not the command - user 2026-09-05"},
        ["Dancing Flash"]               = {type="motion", motion="HCF", allowed_buttons={"EXP"}, verified=true, source_note="Mizuumi: 4123PP"},
        ["Please Help me"]              = {type="motion", motion="HCF", allowed_buttons={"LK+MK"}, verified=true, source_note="Mizuumi: 4123LK+MK"},
        ["Pursuit"]                     = {type="motion", motion="up", allowed_buttons={"LP","MP","HP","LK","MK","HK","EXP","EXK"}, verified=true, source_note="Mizuumi: 8P or 8K, ES added on measurement - user 2026-09-05"},
    },
    ["Anakaris"] = {
        -- The game data spells it "Pharoah". The move is Pharaoh Magic, so the
        -- key keeps the data's spelling and the row reads the right one.
        ["Pharoah Magic"]      = {type="sequence", sequence={{"MK"},{"LP"},{"down"},{"LK"},{"MP"}}, display_name="Pharaoh Magic", verified=true, source_note="fc2 darkstalkers: MK LP 2 LK MP"},
        ["P. Salvation"]       = {type="sequence", sequence={{"HK"},{"MP"},{"down"},{"MK"},{"HP"}}, display_name="Pharaoh Salvation", verified=true, source_note="fc2 darkstalkers: HK MP 2 MK HP"},
        ["Pharoah Decoration"] = {type="sequence", sequence={{"HK"},{"MP"},{"LK"},{"down"},{"LP"},{"MK"},{"HP"}}, display_name="Pharaoh Decoration", verified=true, source_note="fc2 darkstalkers: HK MP LK 2 LP MK HP"},
        ["Pit of Blame"]       = {type="dedicated", handler="pit_of_blame", verified=true},
        ["Cobra Blow"]                  = {type="motion", motion="46", allowed_buttons={"LP","MP","HP","EXP"}, verified=true, source_note="Mizuumi: 46LP"},
        -- The game data calls these "Hands" and "Curse". They are Mummy Drop on
        -- the ground and Royal Judgement in the air, same command (user,
        -- 2026-09-05) - so same_command folds them into one row, which is what
        -- every other air/ground pair here does.
        ["Hands"]                       = {type="motion", motion="QCF", allowed_buttons={"LP","MP","HP","EXP"}, display_name="Mummy Drop", verified=true, source_note="QCF + P - user 2026-09-05"},
        ["Curse"]                       = {type="motion", motion="QCF", allowed_buttons={"LP","MP","HP","EXP"}, display_name="Royal Judgement", air_only=true, verified=true, source_note="QCF + P, air only - user 2026-09-05"},
        ["Pit to Underworld"]           = {type="motion", motion="HCF", allowed_buttons={"EXK"}, display_name="The Pit to the Underworld", verified=true, source_note="Mizuumi: 4123KK"},
        -- Absorb and Release are one Mizuumi row. IN is the absorb, OUT the release.
        ["Spell of Turn - IN"]          = {type="motion", motion="QCB", allowed_buttons={"LK","MK","HK","EXK"}, display_name="Spell of Turning (IN)", verified=true, source_note="Mizuumi: SPELL OF TURNING (IN = Absorb, 214K)"},
        ["Spell of Turn - OUT"]         = {type="motion", motion="QCF", allowed_buttons={"LK","MK","HK","EXK"}, display_name="Spell of Turning (OUT)", verified=true, source_note="Mizuumi: SPELL OF TURNING (OUT = Release, 236K)"},
        ["Coffin"]                      = {type="motion", motion="22", allowed_buttons={"LP","MP","HP","EXP","LK","MK","HK","EXK"}, display_name="The Dance of Coffins", verified=true, source_note="Mizuumi: 22P or 22K"},
        ["Pursuit"]                     = {type="motion", motion="up", allowed_buttons={"LP","MP","HP","LK","MK","HK","EXP","EXK"}, verified=true, source_note="Mizuumi: 8P or 8K, ES added on measurement - user 2026-09-05"},
    },
    ["Lei-Lei"] = {
        ["Tenraiha"] = {type="sequence", sequence={{"LK"},{"HK"},{"MP"}, {}, {"MP"},{"up"}}, verified=true, source_note="LK HK MP N MP 8"},
        ["Ankihou"]                     = {type="motion", motion="QCF", allowed_buttons={"LP","MP","HP","EXP"}, verified=true, source_note="Mizuumi: 236LP"},
        ["Henkyouki"]                   = {type="motion", motion="QCB", allowed_buttons={"LP","MP","HP","EXP"}, verified=true, source_note="Mizuumi: 214P"},
        ["Senpuubu"]                    = {type="motion", motion="DPF", allowed_buttons={"LP","MP","HP","EXP"}, verified=true, source_note="Mizuumi: 623P"},
        ["Houtengeki"]                  = {type="motion", motion="HCB", allowed_buttons={"MP","HP","EXP"}, verified=true, source_note="Mizuumi: 6324 MP or HP"},
        ["Chireitou"]                   = {type="motion", motion="HCF", allowed_buttons={"EXK"}, verified=true, source_note="Mizuumi: 4123KK"},
        ["Chuukadan"]                   = {type="motion", motion="HCF", allowed_buttons={"EXP"}, verified=true, source_note="Mizuumi: 4123PP"},
        ["Pursuit"]                     = {type="motion", motion="up", allowed_buttons={"LP","MP","HP","LK","MK","HK","EXP","EXK"}, verified=true, source_note="Mizuumi: 8P/K or 8KK/PP"},
    },
    ["Lilith"] = {
        ["LI"] = {type="sequence", sequence={{"LP"}, {}, {"LP"},{"forward"},{"LK"},{"HP"}}, display_name="Luminous Illusion", verified=true, source_note="LP N LP 6 LK HP"},
        ["Shining Blade"]               = {type="motion", motion="DPF", allowed_buttons={"LP","MP","HP","EXP"}, verified=true, source_note="Mizuumi: 623P"},
        ["Soul Flash"]                  = {type="motion", motion="QCF", allowed_buttons={"LP","MP","HP","EXP"}, verified=true, source_note="Mizuumi: 236P"},
        ["Splendor Love"]               = {type="motion", motion="DPF", allowed_buttons={"EXK"}, verified=true, source_note="Mizuumi: 623KK"},
        ["Mystic Arrow"]                = {type="motion", motion="HCB", allowed_buttons={"LP","MP","HP","EXP"}, verified=true, source_note="Mizuumi: 6324P"},
        ["Merry Twirl"]                 = {type="motion", motion="QCB", allowed_buttons={"LK","MK","HK","EXK"}, display_name="Merry Turn", verified=true, source_note="Mizuumi: 214K"},
        ["Puppet Show"]                 = {type="motion", motion="HCF", allowed_buttons={"EXK"}, display_name="Gloomy Puppet", verified=true, source_note="Mizuumi: 4123KK"},
        ["Pursuit"]                     = {type="motion", motion="up", allowed_buttons={"LP","MP","HP","LK","MK","HK","EXP","EXK"}, verified=true, source_note="Mizuumi: 8P/K or 8KK/PP"},
    },
    ["Bulleta"] = {
        ["Beautiful Memory"]            = {type="motion", motion="HCF", allowed_buttons={"EXK"}, verified=true, source_note="Mizuumi: 4123KK"},
        ["Sentimental Typhoon"]         = {type="motion", motion="HCB", allowed_buttons={"MP","HP","EXP"}, verified=true, source_note="Mizuumi: 6324 MP or HP"},
        ["Cool Hunting"]                = {type="motion", motion="HCF", allowed_buttons={"EXP"}, verified=true, source_note="Mizuumi: 4123PP"},
        ["Apple 4 You"]                 = {type="motion", motion="HCB", allowed_buttons={"EXK"}, display_name="Apple For You", verified=true, source_note="Mizuumi: 6324KK"},
        ["High Missile"]                = {type="motion", motion="[4]6", allowed_buttons={"LP","MP","HP","EXP"}, display_name="High Smile & Missile", verified=true, source_note="Mizuumi: [4],6P"},
        ["Low Missile"]                 = {type="motion", motion="[4]6", allowed_buttons={"LK","MK","HK","EXK"}, display_name="Low Smile & Missile", verified=true, source_note="Mizuumi: [4],6K"},
        ["Vert Missile"]                = {type="motion", motion="[2]8", allowed_buttons={"LP","MP","HP","EXP"}, display_name="Hop & Missile", verified=true, source_note="Mizuumi: [2]8P"},
        ["Molotov Cocktail"]            = {type="motion", motion="DPF", allowed_buttons={"LP","MP","HP","EXP"}, display_name="Cheer & Fire", verified=true, source_note="Mizuumi: 623P"},
        ["Pursuit"]                     = {type="motion", motion="up", allowed_buttons={"LP","MP","HP","LK","MK","HK","EXP","EXK"}, verified=true, source_note="Mizuumi: 8P or 8K, ES added on measurement - user 2026-09-05"},
    },
    ["Victor"] = {
        ["Gyro Crush"]                  = {type="motion", motion="QCB", allowed_buttons={"LP","MP","HP","EXP"}, verified=true, source_note="fc2 darkstalkers: 214 + P"},
        -- The move list spells this with a trailing space. Matched as it is rather
        -- than renamed: the name is game data the Reversal list also shows.
        ["Giga Burn "]                  = {type="motion", motion="DPF", allowed_buttons={"LK","MK","HK","EXK"}, verified=true, source_note="fc2 darkstalkers: 623 + K"},
        ["Minimum Step"]                = {type="motion", motion="down", allowed_buttons={"EXK"}, verified=true, source_note="Mizuumi: 2KKK"},
        ["Thunder Break"]               = {type="motion", motion="[2]8", allowed_buttons={"EXK"}, verified=true, source_note="Mizuumi: [2],8KK"},
        ["Gerdenheim 3"]                = {type="motion", motion="720", allowed_buttons={"EXK"}, verified=true, source_note="Mizuumi: 720+KK"},
        -- VICTOR COMES FROM THE JAPANESE FRAME-DATA SITE, NOT MIZUUMI.
        --
        -- Mizuumi prefixes four of these "GIGA" (GIGA SHOCK / SPIKE / FOREHEAD /
        -- STAKE). darkstalkers.web.fc2.com spells them MEGA, which is what the
        -- game's own move list here says, and Victor separately HAS Giga-named
        -- moves (Giga Burn, and the two easter eggs). So the prefix is not a
        -- spelling difference to normalise - Mizuumi is the odd one out.
        --
        -- Every one of these shows light/medium/heavy/ES rows in the frame tables, so all
        -- three strengths plus the ES form are offered. The two supers below
        -- (Thunder Break, Gerdenheim 3) have one row only and stay ES-only.
        ["Mega Forehead"]               = {type="motion", motion="[4]6", allowed_buttons={"LP","MP","HP","EXP"}, verified=true, source_note="fc2 darkstalkers: 4-charge-6 + P"},
        ["Mega Stake"]                  = {type="motion", motion="[2]8", allowed_buttons={"LP","MP","HP","EXP"}, verified=true, source_note="fc2 darkstalkers: 2-charge-8 + P"},
        ["Mega Shock"]                  = {type="motion", motion="QCF", allowed_buttons={"LK","MK","HK","EXK"}, verified=true, source_note="fc2 darkstalkers: 236 + K"},
        ["Mega Spike"]                  = {type="motion", motion="360", allowed_buttons={"LP","MP","HP","EXP"}, verified=true, source_note="fc2 darkstalkers: one turn + P"},
        ["Pursuit"]                     = {type="motion", motion="up", allowed_buttons={"LP","MP","HP","LK","MK","HK","EXP","EXK"}, verified=true, source_note="Mizuumi: 8P/K or 8KK/PP"},
    },
    ["Zabel"] = {
        -- The game data names only the air form, and QCB + K is the whole
        -- move: Mizuumi lists it without a J. prefix, so the ground one is the
        -- same command. Not air-only, so no "(Air)" on the row - the name just
        -- drops the word the data carries (user, 2026-09-05).
        --
        -- isReversalMove was false, which is why it appeared in no list at all.
        ["Air Death Hurricane"]         = {type="motion", motion="QCB", allowed_buttons={"LK","MK","HK","EXK"}, display_name="Death Hurricane", verified=true, source_note="Mizuumi: 214K"},
        ["Death Voltage"]               = {type="motion", motion="HCB", allowed_buttons={"EXK"}, verified=true, source_note="Mizuumi: 6324KK"},
        ["Skull Punish"]                = {type="motion", motion="HCB", allowed_buttons={"MP","HP","EXP"}, verified=true, source_note="Mizuumi: 6324 MP or HP"},
        ["Hell Dunk"]                   = {type="motion", motion="DPF", allowed_buttons={"EXP"}, verified=true, source_note="Mizuumi: 623PP"},
        ["Skull Sting"]                 = {type="motion", motion="2~8", allowed_buttons={"LK","MK","HK","EXK"}, verified=true, source_note="Mizuumi: 2~8LK"},
        ["Evil Scream"]                 = {type="motion", motion="6~4", allowed_buttons={"EXP"}, verified=true, source_note="Mizuumi: 6~4PP"},
        ["Hell Gate"]                   = {type="motion", motion="HCF", allowed_buttons={"LK","MK","HK","EXK"}, display_name="Hells Gate", verified=true, source_note="Mizuumi: 4123K"},
        ["Pursuit"]                     = {type="motion", motion="up", allowed_buttons={"LP","MP","HP","LK","MK","HK","EXP","EXK"}, verified=true, source_note="Mizuumi: 8P or 8K, ES added on measurement - user 2026-09-05"},
    },
    ["Aulbath"] = {
        ["Sea Rage"]                    = {type="motion", motion="HCF", allowed_buttons={"EXP"}, verified=true, source_note="Mizuumi: 4123PP"},
        ["Water Jail"]                  = {type="motion", motion="DPF", allowed_buttons={"EXP"}, verified=true, source_note="Mizuumi: 623PP"},
        ["Gem's Anger"]                 = {type="motion", motion="HCB", allowed_buttons={"MK","HK","EXK"}, verified=true, source_note="Mizuumi: 6324 MK or HK"},
        ["Crystal Lancer"]              = {type="motion", motion="HCB", allowed_buttons={"MP","HP","EXP"}, verified=true, source_note="Mizuumi: 6324 MP or HP"},
        ["Trick Fish"]                  = {type="motion", motion="DPF", allowed_buttons={"LK","MK","HK","EXK"}, verified=true, source_note="Mizuumi: 623K"},
        ["Sonic Wave"]                  = {type="motion", motion="[4]6", allowed_buttons={"LP","MP","HP","EXP"}, verified=true, source_note="Mizuumi: [4],6P"},
        ["Aqua Spread"]                 = {type="motion", motion="632", allowed_buttons={"EXP","EXK"}, verified=true, source_note="Mizuumi: 632PP or 632KK"},
        ["Direct Scissors"]             = {type="motion", motion="22", allowed_buttons={"EXP"}, verified=true, source_note="Mizuumi: 22PPP"},
        ["Gas"]                         = {type="motion", motion="[4]6", allowed_buttons={"LK","MK","HK","EXK"}, display_name="Poison Cloud", verified=true, source_note="Mizuumi: [4],6K"},
        ["Pursuit"]                     = {type="motion", motion="up", allowed_buttons={"LP","MP","HP","LK","MK","HK","EXP","EXK"}, verified=true, source_note="Mizuumi: 8P/K or 8KK/PP"},
    },
    ["Sasquatch"] = {
        ["Big Breath"]                  = {type="motion", motion="QCF", allowed_buttons={"LP","MP","HP","EXP"}, verified=true, source_note="Mizuumi: 236P"},
        ["Big Blow"]                    = {type="motion", motion="DPF", allowed_buttons={"LP","MP","HP","EXP"}, verified=true, source_note="Mizuumi: 623P"},
        ["Big Typhoon"]                 = {type="motion", motion="DPF", allowed_buttons={"LK","MK","HK","EXK"}, verified=true, source_note="Mizuumi: 623LK"},
        ["Big Freezer"]                 = {type="motion", motion="HCF", allowed_buttons={"EXP"}, verified=true, source_note="Mizuumi: 4123PP"},
        ["Big Brunch"]                  = {type="motion", motion="HCB", allowed_buttons={"MP","HP","EXP"}, verified=true, source_note="Mizuumi: 6324 MP or HP"},
        ["Big Towers"]                  = {type="motion", motion="22", allowed_buttons={"LP","MP","HP","EXP"}, verified=true, source_note="Mizuumi: 22LP"},
        ["Big Swing"]                   = {type="motion", motion="360", allowed_buttons={"MK","HK","EXK"}, verified=true, source_note="Mizuumi: 360 MK or HK"},
        ["Big Sledge"]                  = {type="motion", motion="720", allowed_buttons={"EXK"}, verified=true, source_note="Mizuumi: 720+KK"},
        ["Big Eisban"]                  = {type="motion", motion="HCF", allowed_buttons={"EXK"}, display_name="Big Eisbahn", verified=true, source_note="Mizuumi: 4123KK"},
        ["Pursuit"]                     = {type="motion", motion="up", allowed_buttons={"LP","MP","HP","LK","MK","HK","EXP","EXK"}, verified=true, source_note="Mizuumi: 8P or 8K, ES added on measurement - user 2026-09-05"},
    },
    ["Q-Bee"] = {
        ["Delta-A"]                     = {type="motion", motion="QCB", allowed_buttons={"LK","MK","HK","EXK"}, verified=true, source_note="Mizuumi: 214K"},
        ["OM"]                          = {type="motion", motion="HCB", allowed_buttons={"MP","HP","EXP"}, verified=true, source_note="Mizuumi: 6324 MP or HP"},
        -- Guard cancel only, so it is not something a step can ask for on its
        -- own. Left in the Character Specific list, taken out of the editor -
        -- a category of its own is still to come (user 2026-09-05).
        ["R.M."]                        = {type="motion", motion="DPF", allowed_buttons={"LK","MK","HK","EXK"}, action_editor_hidden=true, verified=true, source_note="Mizuumi: 623K"},
        ["C>R"]                         = {type="motion", motion="HCF", allowed_buttons={"LP","MP","HP","EXP"}, verified=true, source_note="Mizuumi: 4123P"},
        ["QJ"]                          = {type="motion", motion="DPF", allowed_buttons={"EXP"}, verified=true, source_note="Mizuumi: 623PP"},
        ["+B"]                          = {type="motion", motion="HCF", allowed_buttons={"EXK"}, verified=true, source_note="HCF + KK - user 2026-09-05"},
        -- SAME BUTTON FOUR TIMES, NOT FOUR DIFFERENT ONES.
        --
        -- Mizuumi writes it "K,K,K,K,K", which reads as a button-order command
        -- and is not one: it is one button pressed again and again. Repeats need
        -- a neutral between them or the second press has no edge - the same rule
        -- the button-order supers follow - so four presses and three gaps is
        -- seven ticks, which is what was measured (user, 2026-09-05).
        --
        -- The strength is the player's, so it is a button row like any motion.
        ["SxP"]                         = {type="repeat", count=4, allowed_buttons={"LK","MK","HK","EXK"}, verified=true, source_note="Same button x4 with a neutral between, 7 ticks - user 2026-09-05"},
        ["Pursuit"]                     = {type="motion", motion="up", allowed_buttons={"LP","MP","HP","LK","MK","HK","EXP","EXK"}, verified=true, source_note="Mizuumi: 8P/K or 8KK/PP"},
    },
    ["Jedah"] = {
        ["Dio Sega"]                    = {type="motion", motion="QCF", allowed_buttons={"LP","MP","HP","EXP"}, verified=true, source_note="Mizuumi: 236P"},
        ["Prova di servo"]              = {type="motion", motion="HCF", allowed_buttons={"EXK"}, verified=true, source_note="Mizuumi: 4123KK"},
        ["Ira Spinta"]                  = {type="motion", motion="HCB", allowed_buttons={"LK","MK","HK","EXK"}, air_only=true, verified=true, source_note="Mizuumi: J.6324K"},
        ["Nero Fatica"]                 = {type="motion", motion="QCB", allowed_buttons={"LP","MP","HP","EXP"}, verified=true, source_note="Mizuumi: 214P"},
        ["San Bassale"]                 = {type="motion", motion="HCB", allowed_buttons={"MK","HK"}, verified=true, source_note="Mizuumi: 6324 MK or HK"},
        ["Finale Rosso"]                = {type="motion", motion="22", allowed_buttons={"EXP"}, verified=true, source_note="Mizuumi: 22PP"},
        ["Pursuit"]                     = {type="motion", motion="up", allowed_buttons={"LP","MP","HP","LK","MK","HK","EXP","EXK"}, verified=true, source_note="Mizuumi: 8P or 8K, ES added on measurement - user 2026-09-05"},
    },
    ["Bishamon"] = {
        -- PRESSED ON free+0, NOT free-1.
        --
        -- Every other special is pressed a tick early, because the recogniser
        -- needs the motion finished before the game asks what the player did.
        -- This one measured a tick late that way: after a guard and after a hit
        -- both, it wanted one more tick (user, 2026-09-05). It is not a motion
        -- property - the same DPF is right for every other move that uses it -
        -- so it is a property of the move, and rides here.
        --
        -- Auto (Fastest) therefore means free+0 for this move, which is what a
        -- normal gets.
        ["Kienzan"]                     = {type="motion", motion="DPF", allowed_buttons={"LP","MP","HP","EXP"}, display_name="Kienzen", press_free0=true, verified=true, source_note="Mizuumi: 623P. Press offset measured by user 2026-09-05"},
        ["Iai Giri High"]               = {type="motion", motion="[4]6", allowed_buttons={"LP","MP","HP","EXP"}, verified=true, source_note="Mizuumi: [4],6P"},
        ["Iai Giri Low"]                = {type="motion", motion="[4]6", allowed_buttons={"LK","MK","HK","EXK"}, verified=true, source_note="Mizuumi: [4],6K"},
        ["Oni Kubi"]                    = {type="motion", motion="HCB", allowed_buttons={"EXP"}, display_name="Oni Kubi Hineri", verified=true, source_note="Mizuumi: 6324PP"},
        ["K.D."]                        = {type="motion", motion="HCF", allowed_buttons={"LP","MP","HP","EXP"}, display_name="Karame Dama", verified=true, source_note="Mizuumi: 4123P"},
        ["Command Throw"]               = {type="motion", motion="360", allowed_buttons={"MP","HP"}, display_name="Kirisute Gomen", verified=true, source_note="Mizuumi: 360 MP or HP"},
        ["Bricks"]                      = {type="motion", motion="HCF", allowed_buttons={"EXK"}, display_name="Enma Seki", verified=true, source_note="Mizuumi: 4123KK"},
        ["Pursuit"]                     = {type="motion", motion="up", allowed_buttons={"LP","MP","HP","LK","MK","HK","EXP","EXK"}, verified=true, source_note="Mizuumi: 8P or 8K, ES added on measurement - user 2026-09-05"},
        ["OTG Slap Chop"]               = {type="motion", motion="22", allowed_buttons={"EXP"}, display_name="Togakubi Sarashi", verified=true, source_note="Mizuumi: TOGAKUBI SARASHI 22PP"},
    },
}

local function attach_character_commands(character_name, moves)
    local defs = character_command_registry[character_name] or {}
    for _, move in pairs(moves) do
        move.command = defs[move.name] or {type="unsupported", verified=false}
        -- TAUNT IS START FOR EVERY CHARACTER. Delivered at joypad level
        -- ("P2 Start"), not through the input word - see
        -- CSP.queue_character_specific_input in guardCancel.lua. A registry
        -- definition would take precedence if one ever appeared.
        if move.command.type == "unsupported" and move.name == "Taunt" then
            move.command = {type="start", verified=true}
        end
        if character_name == "Morrigan" and move.name == "Soul Fist" then
            move.accepted_values = {0x04, 0x06}
        elseif character_name == "Morrigan" and move.name == "Air Soul Fist" then
            move.action_editor_hidden = true
            move.action_editor_alias = "Soul Fist"
        end
    end
    return moves
end

local moves_lookup = {
    ["Morrigan"]  = attach_character_commands("Morrigan", get_moves_Morrigan()),   -- https://twitter.com/VMP_KyleW/status/1062578209777082368
    ["Bulleta"]   = attach_character_commands("Bulleta", get_moves_Bulleta()),	-- https://twitter.com/VMP_KyleW/status/1062246488745500672
    ["Demitri"]   = attach_character_commands("Demitri", get_moves_Demitri()),	-- https://twitter.com/VMP_KyleW/status/1062247999198261248
    ["Gallon"]    = attach_character_commands("Gallon", get_moves_Gallon()),	    -- https://twitter.com/VMP_KyleW/status/1062251253487398912
    ["Victor"]    = attach_character_commands("Victor", get_moves_Victor()),	    -- https://twitter.com/VMP_KyleW/status/1062255444066881536
    ["Zabel"]     = attach_character_commands("Zabel", get_moves_Zabel()),      -- https://twitter.com/VMP_KyleW/status/1062575688199229440
    ["Anakaris"]  = attach_character_commands("Anakaris", get_moves_Anakaris()),	-- https://twitter.com/VMP_KyleW/status/1062584507331559424
    ["Felicia"]   = attach_character_commands("Felicia", get_moves_Felicia()),	-- https://twitter.com/VMP_KyleW/status/1062587739080613889
    ["Bishamon"]  = attach_character_commands("Bishamon", get_moves_Bishamon()), 	-- https://twitter.com/VMP_KyleW/status/1062592100498198529
    ["Aulbath"]   = attach_character_commands("Aulbath", get_moves_Aulbath()),	-- https://twitter.com/VMP_KyleW/status/1062595023688986625
    ["Sasquatch"] = attach_character_commands("Sasquatch", get_moves_Sasquatch()), 	-- https://twitter.com/VMP_KyleW/status/1062975241603866624
    ["Q-Bee"]     = attach_character_commands("Q-Bee", get_moves_QBee()),	    -- https://twitter.com/VMP_KyleW/status/1062980478993485825
    ["Lei-Lei"]   = attach_character_commands("Lei-Lei", get_moves_LeiLei()),     -- https://twitter.com/VMP_KyleW/status/1062983116220813312
    ["Lilith"]    = attach_character_commands("Lilith", get_moves_Lilith()),     -- https://twitter.com/VMP_KyleW/status/1062986908777689088
    ["Jedah"]     = attach_character_commands("Jedah", get_moves_Jedah()),      -- https://twitter.com/VMP_KyleW/status/1063252518686253056
-- ["Oboro"]     = get_moves_Morrigan()	    -- https://twitter.com/VMP_KyleW/status/1063641654622441474
-- ["Hyper Zabel"] = get_moves_Morrigan()   -- https://twitter.com/VMP_KyleW/status/1062978029595455489
    ["Dark Gallon"] 	= attach_character_commands("Gallon", get_moves_Gallon())  -- https://twitter.com/VMP_KyleW/status/1062251253487398912
} 

-- THE COMMAND REGISTRY, FOR THE ACTION SEQUENCE EDITOR AND RUNNER.
--
-- Neither of those requires this file, and neither should have to: guardCancel
-- publishes seq_dash_cancel_reverse the same way, for the same reason. The data
-- lives here, so the lookups do too.
--
-- ONLY WHAT CAN ACTUALLY COME OUT IS OFFERED. dedicated moves need a handler the
-- sequence path does not have, and unsupported ones were never source-verified -
-- the schema note above says plainly never to fall back to poke_special() for
-- them. An action that cannot come out is worse than a missing one.
local function offerable(cmd)
	if cmd == nil then return false end
	if cmd.type ~= "motion" and cmd.type ~= "sequence"
	   and cmd.type ~= "repeat" then return false end
	-- A COMMAND KNOWN TO BE WRONG IS NOT OFFERED.
	--
	-- verified is the schema's own field for this. An entry that was tried in
	-- game and did not produce the move is worse than a missing row: the row
	-- reads as a working choice. Setting verified=false leaves the entry in the
	-- file - so the gap is visible to whoever fills it - and out of the menu.
	if cmd.verified == false then return false end
	return true
end


-- TWO MOVES WITH THE SAME COMMAND ARE ONE CHOICE.
--
-- AIR AND GROUND ARE NOT DISTINGUISHED. Morrigan's Soul Fist and Air Soul Fist
-- are one motion (QCF + P) and so are Demitri's two Chaos Flares; which one
-- comes out is decided by where the dummy IS, and a step list already says that
-- with the step before. Two rows carrying identical input would be two names for
-- one choice.
--
-- Compared by value, not by table identity: attach_character_commands hands each
-- move the registry entry for its own NAME, so the air and ground forms get
-- different tables holding the same thing.
local function same_command(a, b)
	if a.type ~= b.type then return false end
	if a.type == "motion" then
		if a.motion ~= b.motion then return false end
		if a.button_group ~= b.button_group then return false end
		-- An air-only move and a ground move are different moves even when the
		-- command matches, so they are not one row.
		if (a.air_only == true) ~= (b.air_only == true) then return false end
		local x, y = a.allowed_buttons, b.allowed_buttons
		if (x == nil) ~= (y == nil) then return false end
		if x ~= nil then
			if #x ~= #y then return false end
			for i = 1, #x do if x[i] ~= y[i] then return false end end
		end
		return true
	end
	-- sequence
	local x, y = a.sequence, b.sequence
	if x == nil or y == nil or #x ~= #y then return false end
	for i = 1, #x do
		if #x[i] ~= #y[i] then return false end
		for j = 1, #x[i] do if x[i][j] ~= y[i][j] then return false end end
	end
	return true
end
-- THE NAME A ROW SHOWS.
--
-- One place, because two lists build rows and they have to name a move the same
-- way. "(Air)" is appended rather than written into display_name so it cannot
-- be forgotten on the next move that needs it, and cannot be doubled.
local function row_label(move)
	local n = move.command.display_name or move.name
	if move.command.air_only == true then return n .. " (Air)" end
	return n
end

-- Character id -> name, without a player object. get_character reads $382 off a
-- base address; the editor already knows the id and nothing else.
local CID_NAME = {
	[0x00] = "Bulleta", [0x01] = "Demitri", [0x02] = "Gallon",  [0x03] = "Victor",
	[0x04] = "Zabel",   [0x05] = "Morrigan",[0x06] = "Anakaris",[0x07] = "Felicia",
	[0x08] = "Bishamon",[0x09] = "Aulbath", [0x0A] = "Sasquatch",
	[0x0B] = "Zabel",   [0x0C] = "Q-Bee",   [0x0D] = "Lei-Lei", [0x0E] = "Lilith",
	[0x0F] = "Jedah",   [0x12] = "Gallon",  [0x18] = "Oboro",
}

-- The moves this character can be asked for by name, in the order the registry
-- lists them. nil when the character has no entries at all, which is what makes
-- the editor drop the whole Special group for them.
function seq_special_list(cid)
	local moves = moves_lookup[CID_NAME[cid]]
	if moves == nil then return nil end
	local out = {}
	for _, move in ipairs(moves) do
		-- isReversalMove IS THE SPINE. The Character Specific list is built from
		-- it (get_reversal_moves), and the Special list follows that
		-- implementation - the same filter, and this file's own order.
		-- action_editor_hidden was written and never read. A move can be a real
		-- Character Specific reversal and still be nothing a step can ask for -
		-- Q-Bee's R.M. only exists as a guard cancel - so the flag has to be
		-- honoured HERE rather than by dropping it from the game data.
		if offerable(move.command)
		   and (move.isReversalMove == true or move.isActionStepOnly == true)
		   and move.isPursuit ~= true
		   and move.command.action_editor_hidden ~= true then
			local dup = false
			for _, taken in ipairs(out) do
				-- One row per NAME, because Anakaris has two moves called
				-- "Pharoah Magic" (0x10 and 0x1E) and the registry keys on the
				-- name. Duplicate names have caused a lookup bug in this file
				-- before - see the "Pit of Blame" note in get_moves_Anakaris.
				--
				-- And one row per COMMAND, which is what collapses the air and
				-- ground forms of one move into the single choice they are.
				if taken.name == move.name
				   or same_command(taken.command, move.command) then
					dup = true
					break
				end
			end
			if not dup then
				-- THE NAME IS THE KEY; THE LABEL IS WHAT IS READ.
				--
				-- Several moves are called one thing in this file (game data,
				-- which the Reversal list also shows) and another on Mizuumi.
				-- The key has to stay the game data name - it is what the
				-- registry and the saved steps are keyed on - so the wanted
				-- spelling rides alongside as a label instead of replacing it.
				-- isEX is the GAME data classification, and the note at the top
				-- of the registry is explicit that it says nothing about how the
				-- move is entered. That is exactly why it is the right thing to
				-- split the editor group on: "EX Special" is a kind of move, not
				-- a kind of input. Passed through rather than re-derived from the
				-- buttons, because the two do not agree - Oni Kubi Hineri takes
				-- two punches and is not an EX move, and Valkyrie Turn is one
				-- and takes a single kick.
				out[#out + 1] = { name = move.name, command = move.command,
				                  label = row_label(move),
				                  is_ex = (move.isEX == true) or nil }
			end
		end
	end
	if #out == 0 then return nil end
	return out
end

-- SAFE TO INPUT, NOT SAFE TO POKE.
--
-- Character Specific Reversal writes the move value straight into 0xFF8906.
-- That is fine for a move whose value is the one you want, and wrong for a
-- move the game data only names in its AIR form: poking the air value while
-- the dummy stands there is the "unknown action mid-flight" case the poke
-- guard warns about, which is why every other "Air ..." entry has
-- isReversalMove = false.
--
-- Zabel's Death Hurricane is that case and was therefore in no list at all.
-- Action Steps does not poke - it enters the command as real input, and the
-- game picks the version from the dummy's own state - so the move is safe
-- there and nowhere else. isActionStepOnly says exactly that: offered to the
-- editor, kept out of Character Specific.
--
-- THE PURSUIT LIST.
--
-- A pursuit is not a reversal - it is aimed at an opponent already down - so it
-- cannot ride isReversalMove, and a few characters have the flag set on theirs
-- anyway. isPursuit is its own answer, and seq_special_list above now refuses
-- anything carrying it so no move appears in both places.
--
-- Same shape as seq_special_list otherwise, including the label, so the editor
-- can build its group the same way.
function seq_pursuit_list(cid)
	local moves = moves_lookup[CID_NAME[cid]]
	if moves == nil then return nil end
	local out = {}
	for _, move in ipairs(moves) do
		if move.isPursuit == true and offerable(move.command)
		   and move.command.action_editor_hidden ~= true then
			local dup = false
			for _, taken in ipairs(out) do
				if taken.name == move.name or same_command(taken.command, move.command) then
					dup = true
					break
				end
			end
			if not dup then
				out[#out + 1] = { name = move.name, command = move.command,
				                  label = row_label(move) }
			end
		end
	end
	if #out == 0 then return nil end
	return out
end

-- One move by name, for the runner. Names do not collide across the seven
-- characters in the registry, so the character does not have to be named again -
-- and a step saved under one dummy still compiles under another.
function seq_special_command(name)
	-- THE CURRENT DUMMY FIRST.
	--
	-- "Pursuit" is a real name in all fifteen tables and the command is not the
	-- same in all of them - six characters have an ES form and nine do not. A
	-- blind search over pairs() would answer with whichever table came first.
	--
	-- The fallback below is kept deliberately: a step saved under one dummy
	-- still has to compile under another, which is what the whole sp.<name> id
	-- rests on.
	-- P2 is the dummy. CID_NAME, not get_character: the two disagree on Dark
	-- Gallon, where get_character answers "Dark Gallon" and there is no table
	-- of that name - CID_NAME folds it onto Gallon's, which is the same table
	-- seq_special_list and seq_pursuit_list are keyed through.
	local own = character_command_registry[CID_NAME[memory.readbyte(0xFF8800 + 0x382)]]
	if own ~= nil and offerable(own[name]) then return own[name] end
	for _, defs in pairs(character_command_registry) do
		local cmd = defs[name]
		if offerable(cmd) then return cmd end
	end
	return nil
end
local function get_player_moves(base_addr)
    local char_name = get_character(base_addr)
    return moves_lookup[char_name]
end

local function get_reversal_moves(all_moves)
    local reversals = {}

    for k, v in pairs(all_moves) do
        if v["isReversalMove"] == true then
            table.insert(reversals, v)
        end
    end

    return reversals
end
local function get_reversal_moves_names( reversal_moves )
    local names = {}

    for k, v in pairs(reversal_moves) do
        table.insert(names, v["name"])
    end
    return names
end

	
						
-- Character    Standing    Crouching    Overlap    Total Overlap length
local bishamon_unblockable_distance_data = {

    ["Anakaris"] = {  
        charName = "AN",
        standingDist  = { startDist = 74, endDist = 87 },
        crouchingDist = { startDist = 74, endDist = 86 },
        overlapRange  = { startDist = 74, endDist = 86 }, 
        length = 12
    },
    ["Aulbath"] = {
        charName = "AU",
        standingDist  = { startDist = 74, endDist = 88 },
        crouchingDist = { startDist = 74, endDist = 90 },
        overlapRange  = { startDist = 74, endDist = 88 }, 
        length = 14
    },
    ["Bishamon"] = {
        charName = "BI",
        standingDist = { startDist = 73, endDist = 92},
        crouchingDist  = { startDist = 73 , endDist = 92 },
        overlapRange = {startDist = 73, endDist = 92 }, 
        length =  9
    }, 
    ["Bulleta"] = { 
        charName = "BU",
        standingDist = { startDist = 85, endDist = 91},
        crouchingDist  = { startDist = 85 , endDist = 92 },
        overlapRange = {startDist = 85, endDist = 91 }, 
        length =  6
    }, 
    ["Demitri"] = { 
        charName = "DE",
        standingDist = { startDist = 85, endDist = 93},
        crouchingDist  = { startDist = 85 , endDist = 94 },
        overlapRange = {startDist = 85, endDist = 93 }, 
        length =  8
    }, 
    ["Felicia"] = { 
        charName = "FE",
        standingDist = { startDist = 77, endDist = 92},
        crouchingDist  = { startDist = 77 , endDist = 86 },
        overlapRange = {startDist = 77, endDist = 86 }, 
        length =  9
    }, 
    ["Jedah"] = { 
        charName = "JE",
        standingDist  = { startDist = 75, endDist = 88 },
        crouchingDist = { startDist = 75, endDist = 85 },
        overlapRange  = { startDist = 75, endDist = 85 }, 
        length = 10
    },
    ["Lei-Lei"] = {  
        charName = "LE",
        standingDist  = { startDist = 79, endDist = 91 },
        crouchingDist = { startDist = 79, endDist = 91},
        overlapRange  = { startDist = 79, endDist = 91 }, 
        length = 12
    },
    ["Sasquatch"] = {
        charName = "SA",
        standingDist  = { startDist = 69, endDist = 90 },
        crouchingDist = { startDist = 69, endDist = 82 },
        overlapRange  = { startDist = 69, endDist = 82 }, 
        length = 13
    },
    ["Victor"] = {  
        charName = "VI",
        standingDist  = { startDist = 74, endDist = 85 },
        crouchingDist = { startDist = 74, endDist = 95 },
        overlapRange  = { startDist = 74, endDist = 85 },
        length =  9
    }, 
    ["Zabel"] = { 
        charName = "ZA",
        standingDist  = { startDist = 77, endDist = 94 },
        crouchingDist = { startDist = 77, endDist = 100},
        overlapRange  = { startDist = 77, endDist = 94 },
        length = 17
    },
    ["Gallon"] = {  
        charName = "GA",
        standingDist  = { startDist = nil, endDist = nil },
        crouchingDist = { startDist = 77,  endDist = 98  },
        overlapRange  = { startDist = nil, endDist = nil },
        notes = "Crouch under: Frames are for BRICKS",
        length = 17
    },
    ["Morrigan"] = {  
        charName = "MO",
        standingDist  = { startDist = nil,  endDist = nil },
        crouchingDist = { startDist = nil,  endDist = nil  },
        overlapRange  = { startDist = nil,  endDist = nil   },
        notes = "MO crouches under Karame Dama UBK.",
        length = 17
    },
    ["Lilith"] =  {
        charName = "LI",
        standingDist  = { startDist = nil, endDist = nil },
        crouchingDist = { startDist = nil, endDist = nil},
        overlapRange  = { startDist = nil, endDist = nil },
        notes = "LI crouches under Karame Dama UBK.",
        length = 17
    },
    ["Q-Bee"] = {  
        charName = "QB",
        standingDist  = { startDist = 85,  endDist = 109 },
        crouchingDist = { startDist = 85,  endDist = 91  },
        overlapRange  = { startDist = nil, endDist = nil }, 
        notes = "Crouch pixels are for BRICKS, Standing pixels for Karame: when she recovers she has around ~3 frames going from standing > crouching that she is vulnerable to Karame UB",
        length = 17
    },
}

local function get_bishamon_ubk_ranges_by_char(base_addr)
    local char_name = get_character(base_addr)
    return bishamon_unblockable_distance_data[char_name]
end

local function get_moves_obj()
    local p1_all_moves = get_player_moves(0xFF8400)
    local p2_all_moves = get_player_moves(0xFF8800)

    local p1_reversal_moves = get_reversal_moves(p1_all_moves)
    local p2_reversal_moves = get_reversal_moves(p2_all_moves)

    local p1_reversal_moves_names = get_reversal_moves_names(p1_reversal_moves)
    local p2_reversal_moves_names = get_reversal_moves_names(p2_reversal_moves)

    return {
        P1 = {
            all             = p1_all_moves,
            reversals       = p1_reversal_moves,
            reversal_names  = p1_reversal_moves_names,
        },
        P2 = {
            all             = p2_all_moves,
            reversals       = p2_reversal_moves,
            reversal_names  = p2_reversal_moves_names,

        },
    }
end
charMovesModule = {
    ["get_player_movelists"] = function()
        return get_moves_obj()
    end,
    ["get_bishamon_ubk_ranges_by_char"] = function()
        return get_bishamon_ubk_ranges_by_char
    end,
    ["registerBefore"] = function(run_dummy_input, macroLua_funcs)
        return get_moves_obj()
    end
}
return charMovesModule
