-- ACTION SEQUENCE EDITOR.
--
-- The Guard Action settings are already a two-step sequence: a delay, then one
-- motion with one button. Dash attack is exactly that - dash, wait fourteen
-- ticks, press. This builds the general form of it, so a trigger can run any
-- number of steps in order.
--
-- Navigation is the same at every level, and the same as everywhere else in
-- this menu: Right or LP goes in, Left comes out, Up and Down select.
--
-- Nothing here touches the game. Edits are made to a draft and only reach the
-- settings on Save, so leaving by any other route changes nothing.
--
-- TWO ROWS PER STEP, AND NO MORE.
--
-- A step is one thing to do and one answer to when. Earlier drafts had four or
-- five rows - lever, button, start, wait, hold - and they were hard to read
-- because they were hard to think about:
--
--   * lever and button were split, so "Demon Cradle" could not be one choice,
--     and every step made the user assemble a move out of two rows
--   * "start" and "wait" were two rows asking one question
--   * "hold" was a LENGTH on every step, although a length is not what holding
--     needs: the next step's Wait already says when the holding stops
--
-- So: strength is part of the move's name, and start and wait are one field
-- where Auto is a value. Everything that remains is a named action.
--
-- HOLD CAME BACK, AS A YES OR NO.
--
-- A charge move is a direction held and then let go, and nothing else here can
-- say "keep holding this". So an attack that ends on a plain direction gets one
-- more row, Hold, and it is a yes or no rather than a number - how long is the
-- next step's Wait, which is where that question already lived.
--
-- It is deliberately not automatic. Holding every step's direction by default
-- would change how every saved sequence behaves between steps, silently. As a
-- row, a dummy that keeps crouching after an attack is doing it because the
-- step says so.
--
-- STORED AS STRINGS, NOT INDICES.
--
-- The existing Reversal/Counter Input Motion is stored as an INDEX into a list
-- in menu.lua, so three files have to agree about what index 20 is - menu.lua's
-- list, dummyState.lua's index-to-string chain, and make_input_sequence in
-- controller.lua. That has broken twice and needs a settings migration every
-- time the list changes. These steps store action ids as strings, so adding an
-- action cannot renumber anything.
local M = {}

local MAX_STEPS = 4096

-- Wait is one field with one magic value: this means "when the dummy can act"
-- rather than a count. Kept as a number so the saved file stays plain.
local WAIT_AUTO = -1
local TIMING_CHAIN = "chain"
local TIMING_CANCEL = "cancel"
local TIMING_LATE_CANCEL = "late_cancel"
local TIMING_LANDING = "landing"
-- 連打キャンセル. The runner carries the ROM conditions; what matters here is
-- that it is a different question from Chain - it repeats the SAME button and
-- needs no hit - so it gets its own row rather than hiding inside Chain.
local TIMING_RAPID = "rapid"
local WAIT_MAX = 120
-- Step one's wait is handed to kd_delay_ticks, which clamps at 30. Showing a
-- number the machinery would not use is the kind of false unit this tool does
-- not keep, so the row stops where the mechanism does.
local WAIT_MAX_FIRST = 30

-- Every action is a named thing. id, label, and how it is built:
--   motion  - the string make_input_sequence takes
--   button  - pressed on the last input of that motion, or nil for none
-- Stage 2 compiles from these two fields and nothing else.
local function act(id, label, motion, button)
	return { id = id, label = label, motion = motion, button = button }
end

-- POSTURE IS THE GROUP, DIRECTION IS THE ITEM.
--
-- Standing still, walking forward and walking back are one posture with three
-- directions, exactly as crouching is - so they are one group, and the
-- standalone "do nothing" entry disappears into it as Stand Neutral. Two fewer
-- rows in the list, and every group ends up the same shape: what the character
-- is doing, then which way.
--
-- The ids do not change. walk.f is still walk.f, so nothing saved needs
-- migrating; only the grouping and the labels move.
--
-- No duration field is needed. A movement step's input goes in and the game
-- carries the movement from there; how long the next step waits is the next
-- step's Wait.
--
-- These do NOT keep holding the direction - only an attack with Hold does. A
-- walk that lasts as long as you want is therefore not expressible yet; see the
-- note on Hold at the top of this file.
local STAND = {
	act("neutral", "Neutral", "none"),
	act("walk.f",  "Forward", "forward"),
	act("walk.b",  "Back",    "back"),
}

local CROUCH = {
	act("crouch.d", "Neutral", "down"),
	act("crouch.f", "Forward",       "down-forward"),
	act("crouch.b", "Back",          "down-back"),
}

-- A dash is a dash. The button belongs to the attack step that follows it -
-- actionSequenceRunner folds "dash, then Auto attack" back into the single
-- input list the game actually wants, because the game delays only the PRESS
-- inside a dash and the motion goes in at once.
--
-- A dash briefly carried its own button here. That made every new Dash step an
-- LP attack, because picking an assembled group defaults the button, and it
-- stopped the fusion from firing at all.
local DASH = {
	act("dash.f",  "Forward",        "forward dash"),
	act("dash.b",  "Back",           "back dash"),
	act("dashc.f", "Forward Cancel", "forward dash cancel"),
	act("dashc.b", "Back Cancel",    "back dash cancel"),
}

-- AN AIR DASH IS THE SAME COMMAND AND A DIFFERENT ACTION.
--
-- The input is byte for byte a ground dash, so this was expressible already -
-- put a Dash step after a Jump. What was not expressible is its TIMING, and
-- that is the whole reason it needs a name of its own:
--
--   after a GROUND dash   Auto resolves to the measured dash-attack offset,
--                         which is a per-character number in DASH_AUTO_TICKS
--   after an AIR dash     that number is meaningless. Zabel's ground value is
--                         1, so Auto gave "0 ticks after the dash" for a move
--                         that cannot come out anywhere near there
--
-- Named separately, an air dash falls through to the airborne state test - the
-- animation frame's permission bit, measured on Jedah at 25 and 24 - which
-- needs no table and is the same for every character.
--
-- No cancel variants: those are ground dash cancels.
--
-- NOT EVERY DUMMY HAS ONE.
--
-- Four characters can air dash and only two of those can do it backwards, so
-- the rest are offered a step that produces nothing. An action that cannot come
-- out is worse than a missing one: the sequence looks right, runs, and does
-- nothing, and there is no way to tell that from a timing mistake.
--
-- Keyed on $382. Zabel 2 (0x0B) and Oboro (0x18) are alternate forms and are
-- not in this list because they have not been checked.
local AIR_DASH_CHARS = {
	[0x04] = true,   -- Zabel
	[0x0C] = true,   -- Q-Bee
	[0x0D] = true,   -- Lei-Lei
	[0x0F] = true,   -- Jedah
}

local AIR_BACK_CHARS = {
	[0x04] = true,   -- Zabel
	[0x0D] = true,   -- Lei-Lei
}

local function only(a, set) a.only = set return a end

local AIR_DASH = {
	only(act("air.f", "Forward", "forward dash"), AIR_DASH_CHARS),
	only(act("air.b", "Back",    "back dash"),    AIR_BACK_CHARS),
}

-- Back from the short-lived assembled form to the named entries.
local DASH_BACK = {
	["forward dash"]        = "dash.f",
	["back dash"]           = "dash.b",
	["forward dash cancel"] = "dashc.f",
	["back dash cancel"]    = "dashc.b",
}

-- NEUTRAL, NOT "STRAIGHT UP".
--
-- The glossary (@hagure's English/Japanese FGC terminology) gives 垂直ジャンプ =
-- Neutral Jump. "Straight up" describes it but is not what it is called, and
-- this menu is read by people who know the vocabulary.
local JUMP = {
	act("jump.n", "Neutral", "up"),
	act("jump.f", "Forward",     "up-forward"),
	act("jump.b", "Back",        "up-back"),
}

-- Last of the movement kinds, as the least ordinary of them.
--
-- Two characters have the command, and neither of them has an air dash - so the
-- two restricted groups never appear together, and no sequence can ask for a
-- super jump into an air dash.
local SUPER_JUMP_CHARS = {
	[0x05] = true,   -- Morrigan
	[0x0E] = true,   -- Lilith
}

local SUPER_JUMP = {
	only(act("sj.n", "Neutral", "super jump"),         SUPER_JUMP_CHARS),
	only(act("sj.f", "Forward", "super jump forward"), SUPER_JUMP_CHARS),
	only(act("sj.b", "Back",    "super jump back"),    SUPER_JUMP_CHARS),
}

-- A NORMAL IS A DIRECTION AND A BUTTON, NOT A POSTURE.
--
-- This used to be twelve fixed entries: six standing and six "Crouching X".
-- That named the wrong thing. Down and a button is not crouching - Zabel has a
-- downward air attack on exactly that input - and there was no way to ask for
-- forward or back at all, so command normals were unreachable except through
-- Custom.
--
-- So an attack step carries a direction and a button, assembled the same way a
-- Custom step is. The difference between the two is only which lever list they
-- offer: plain directions here, motions as well there.
local ATTACK_ID = "atk"

local ATTACK_DIRS = {
	{ "Neutral", "none" }, { "Forward", "forward" }, { "Back", "back" },
	{ "Down", "down" }, { "Up", "up" },
	{ "Down Forward", "down-forward" }, { "Down Back", "down-back" },
	{ "Up Forward", "up-forward" }, { "Up Back", "up-back" },
}

-- The escape hatch. Command normals, throws, and any character whose moves are
-- not named yet all go through here, which is what lets the named lists stop
-- short of covering everything.
local CUSTOM_ID = "custom"

local CUSTOM_LEVERS = {
	{ "Neutral", "none" }, { "Forward", "forward" }, { "Back", "back" },
	{ "Down", "down" }, { "Up", "up" },
	{ "Up Forward", "up-forward" }, { "Up Back", "up-back" },
	{ "Down Forward", "down-forward" }, { "Down Back", "down-back" },
	{ "QCF", "QCF" }, { "QCB", "QCB" }, { "DPF", "DPF" }, { "DPB", "DPB" },
	{ "HCF", "HCF" }, { "HCB", "HCB" }, { "360", "360" }, { "720", "720" },
	{ "Charge Back-Forward", "HCharge" }, { "Charge Down-Up", "VCharge" },
}

-- $382 for Victor. Named because the button list below reads it and a bare
-- 0x03 there would say nothing.
local VICTOR = { [0x03] = true }

local CUSTOM_BUTTONS = {
	{ "None", "none" },
	{ "LP", "LP" }, { "MP", "MP" }, { "HP", "HP" },
	{ "LK", "LK" }, { "MK", "MK" }, { "HK", "HK" },
	{ "PPP", "EXP" }, { "KKK", "EXK" },
	-- VICTOR'S ELECTRIC NORMALS.
	--
	-- Not a different button, a button that stays down: Mizuumi writes them
	-- 5[MP] and 2[MP], the bracket meaning held. Offered only to Victor,
	-- because on anyone else the row would be a choice that changes nothing -
	-- the same rule the Air Dash list follows.
	--
	-- Light has no electric version, so only the four are here.
	{ "Elec.MP", "Elec.MP", VICTOR }, { "Elec.HP", "Elec.HP", VICTOR },
	{ "Elec.MK", "Elec.MK", VICTOR }, { "Elec.HK", "Elec.HK", VICTOR },
	{ "LP+LK", "LP+LK" }, { "MP+MK", "MP+MK" }, { "HP+HK", "HP+HK" },
	-- The one pair that is not two of the same strength. Felicia's Please
	-- Help me is the move that needs it.
	{ "LK+MK", "LK+MK" },
}

local HELP = {
	step   = "Open this step to change what it does and when it starts.",
	-- Recovered is exact on the ground. In the air the next attack is allowed a
	-- little before the animation has finished - measured, Jedah's LK runs 31
	-- ticks and the next is taken at 24 - so the word is an approximation there
	-- and the description says so rather than pretending otherwise.
	add    = "Add a step to the end of the list.",
	save   = "Keep this list. Guard Action Type is what runs it.",
	cancel = "Leave without saving. Nothing changes.",
	action = "What the dummy does on this step.",
	wait   = "Ticks from the trigger, or from the step before. Auto is the earliest. Chain and Cancel use the first legal point; Late uses the last known point.\nRapid Fire repeats the same light button off the animation, with no hit needed.\nNot Measured: nobody has timed this pair yet. Set a number instead.",
	lever  = "Held with the button. Attack takes a direction, Custom a motion.",
	button = "Pressed on the last input of the motion. None does the motion alone.",
	hold   = "Keep the direction down after the attack, until the next step.\nA charge move needs the steps before it to hold.\nA charge Special leaves the charge out of its command - it starts from neutral, so hold the direction here on every step before it, including across a Wait.\nA dash cancel holds its reverse direction automatically.",
	order  = "Where this step sits in the list. Left and Right move it.",
	delete = "Remove this step from the list. Asks first.",
	clear  = "Empty the list back to one step. Asks first.",
	back   = "Back to the previous screen.",
}

local active = false
local trigger = "reversal"
local stack = {}
local draft = nil
local editor_character_id = nil
local last_input_frame = -1
local checked = false

local function copy(v)
	if type(v) ~= "table" then return v end
	local o = {}
	for k, x in pairs(v) do o[k] = copy(x) end
	return o
end

-- Groups, in the order they are offered. Character Moves joins this once the
-- command registry is ported; a group with nothing in it is not shown, so no
-- empty screen ever appears.
-- P2's $382. Read here rather than further down because groups() filters on it:
-- an action the dummy does not have is not offered.
local CID_ADDR = 0xFF8B82

local function cid_num()
	return memory.readbyte(CID_ADDR)
end

-- An entry with an `only` set is offered to those characters and no others.
local function shown(x)
	return x.only == nil or x.only[cid_num()] == true
end

-- SPECIAL MOVES, ONE NAME PER ROW.
--
-- The point of the group. The header of this file says the split between lever
-- and button was what stopped "Demon Cradle" being one choice; this is that
-- choice. And it reaches what Custom cannot: an ES or super entered as an
-- ordered run of buttons and directions (Finishing Shower is MP LP 4 LK MK) has
-- no motion name for the Motion row to hold.
--
-- BUILT AS THE UNION, FILTERED BY only.
--
-- Every character's moves go in one list, each row carrying the set of ids that
-- have it. shown() then does the per-character work that Air Dash already
-- relies on, and a group whose rows all go, goes - which is how the eight
-- characters with no entries lose the group entirely rather than opening an
-- empty screen. groups(all) still returns the union, so a step saved under one
-- dummy is still named under another instead of showing a raw id.
--
-- Built once. The registry does not change while the tool runs, and rebuilding
-- per draw would walk every character on every frame.
local special_cache = nil

local function SPECIAL()
	if special_cache ~= nil then return special_cache end
	-- Not cached when the registry is not loaded yet. charMoves publishes it and
	-- menu.lua loads that first, but caching an empty answer would make the
	-- group vanish for good if the order ever changed.
	if seq_special_list == nil then return {} end
	special_cache = {}
	local by_id = {}
	-- $382 ids run to 0x18 (Oboro). Asking for one that is not a character is
	-- answered with nil, so the range costs nothing to overshoot.
	for cid = 0x00, 0x18 do
		local list = seq_special_list(cid)
		if list ~= nil then
			for _, m in ipairs(list) do
				local id = "sp." .. m.name
				local row = by_id[id]
				if row == nil then
					-- label, not name: the id stays the game data name so saved
					-- steps keep resolving, while the row can read differently.
					row = { id = id, label = m.label or m.name, only = {},
					        command = m.command, ex = m.is_ex }
					by_id[id] = row
					special_cache[#special_cache + 1] = row
				end
				row.only[cid] = true
			end
		end
	end
	return special_cache
end

-- THE PURSUIT LIST, BUILT THE SAME WAY.
--
-- A pursuit is aimed at an opponent already on the floor, so it is neither a
-- Special nor an EX Special - it answers a different question and gets its own
-- group. charMoves keeps them apart with isPursuit; nothing appears in both.
--
-- The id shares the sp. prefix on purpose: the runner resolves a step through
-- seq_special_command whatever group the row was picked from, and that lookup
-- now asks the current dummy's table first - which it has to, because "Pursuit"
-- is a real name in all fifteen of them with two different commands.
local pursuit_cache = nil
local function PURSUIT()
	if pursuit_cache ~= nil then return pursuit_cache end
	if seq_pursuit_list == nil then return {} end
	pursuit_cache = {}
	local by_id = {}
	for cid = 0x00, 0x18 do
		local list = seq_pursuit_list(cid)
		if list ~= nil then
			for _, m in ipairs(list) do
				local id = "sp." .. m.name
				local row = by_id[id]
				if row == nil then
					row = { id = id, label = m.label or m.name, only = {},
					        command = m.command }
					by_id[id] = row
					pursuit_cache[#pursuit_cache + 1] = row
				end
				row.only[cid] = true
			end
		end
	end
	return pursuit_cache
end

-- SPECIAL SPLIT IN TWO AT THE GROUP LEVEL.
--
-- One list of fifteen mixed rows made the reader sort supers from specials by
-- recognising the names. The split is the game's own isEX flag, so the question
-- "is this an EX move" is answered by the data rather than by this file.
--
-- The id does NOT change with the group: a step stays "sp.<name>" whichever
-- side it lands on, so saved lists keep resolving and a move that is
-- reclassified moves rows without stranding anything.
local special_split = nil
local function SPECIAL_SIDE(want_ex)
	if special_split == nil then
		local all = SPECIAL()
		-- Not cached before the registry is loaded - SPECIAL() returns {} then,
		-- and caching that would empty both groups for good.
		if #all == 0 then return {} end
		special_split = { [true] = {}, [false] = {} }
		for _, x in ipairs(all) do
			local side = special_split[x.ex == true]
			side[#side + 1] = x
		end
	end
	return special_split[want_ex]
end

-- The row for a step's action, or nil when the step is not a special.
local function special_of(s)
	for _, x in ipairs(SPECIAL()) do
		if x.id == s.action then return x end
	end
	-- A pursuit carries the same sp. prefix, so everything that asks "is this
	-- step a named move" has to see it too - the button row, the label, Hold.
	for _, x in ipairs(PURSUIT()) do
		if x.id == s.action then return x end
	end
	return nil
end

-- WHICH BUTTONS THE MOVE TAKES.
--
-- The registry says: allowed_buttons names them outright, button_group names a
-- strength column. A sequence carries its own buttons and has no row at all.
--
-- ex_button_pair (Valkyrie Turn) is NOT expressed here. It says the ES form
-- takes two buttons, but which pair was never written down, and this menu's
-- PPP / KKK are a different thing. Offering a guess would be offering a row
-- that does nothing.
local BUTTON_GROUP = {
	P = { "LP", "MP", "HP" },
	K = { "LK", "MK", "HK" },
}

-- The button list this dummy is offered. Entries with an `only` set follow
-- the same rule the action groups do.
local function buttons_for(cid)
	local out = {}
	for _, e in ipairs(CUSTOM_BUTTONS) do
		if e[3] == nil or e[3][cid] then out[#out + 1] = e end
	end
	return out
end

local function special_buttons(s)
	local x = special_of(s)
	if x == nil then return nil end
	-- A repeat takes a button the same way a motion does; only a sequence
	-- carries its own.
	if x.command.type ~= "motion" and x.command.type ~= "repeat" then return nil end
	local want = x.command.allowed_buttons or BUTTON_GROUP[x.command.button_group]
	if want == nil then return nil end
	local keep = {}
	for _, b in ipairs(want) do
		for _, e in ipairs(CUSTOM_BUTTONS) do
			if e[2] == b then keep[#keep + 1] = e break end
		end
	end
	if #keep == 0 then return nil end
	return keep
end

-- THE ROW IS ONLY WORTH DRAWING WHEN THERE IS SOMETHING TO CHOOSE.
--
-- An EX move is entered with all three punches or all three kicks. A row
-- reading "Button : PPP" with nothing else on the line asks a question that has
-- one answer, and the group heading already said EX.
--
-- The two that do need it keep it, and both are real: Aqua Spread takes either
-- PPP or KKK, and Please Help me takes LK+MK, which is neither.
--
-- This is about DRAWING only. special_buttons stays the full list, because the
-- step still has to carry a button - a hidden row is not an absent input.
local function special_button_row(s)
	local b = special_buttons(s)
	if b == nil then return nil end
	if #b == 1 and (b[1][2] == "EXP" or b[1][2] == "EXK") then return nil end
	return b
end

-- WHAT THIS DUMMY CAN BE ASKED TO DO.
--
-- Without an argument, entries the current character does not have are left
-- out, and a group whose entries all go leaves with them - which is the same
-- rule the comment above groups() has always described, now with something to
-- apply it to.
--
-- With `all`, nothing is filtered. Naming a step and finding its motion have to
-- work whatever the dummy is, or switching character mid-edit would turn rows
-- into raw ids.
local function groups(all)
	local a = {
		-- Most used first, movement together, then the two that are neither:
		-- doing nothing, and the escape hatch for everything the named lists
		-- deliberately do not cover.
		{ label = "Attack",      assemble = ATTACK_ID },
		{ label = "Special",     list = SPECIAL_SIDE(false) },
		{ label = "EX Special",  list = SPECIAL_SIDE(true) },
		{ label = "Pursuit",     list = PURSUIT() },
		{ label = "Dash",        list = DASH },
		{ label = "Air Dash",    list = AIR_DASH },
		{ label = "Jump",        list = JUMP },
		{ label = "Super Jump",  list = SUPER_JUMP },
		{ label = "Stand",       list = STAND },
		{ label = "Crouch",      list = CROUCH },
		{ label = "Custom",      assemble = CUSTOM_ID },
	}
	if all then return a end
	local out = {}
	for _, g in ipairs(a) do
		if g.list == nil then
			out[#out + 1] = g
		else
			local keep = {}
			for _, x in ipairs(g.list) do
				if shown(x) then keep[#keep + 1] = x end
			end
			if #keep > 0 then
				out[#out + 1] = { label = g.label, list = keep, assemble = g.assemble }
			end
		end
	end
	return out
end

local function label_of(list, id)
	for _, e in ipairs(list) do
		if e[2] == id then return e[1] end
	end
	return tostring(id)
end

-- The lever list a step is assembled from, or nil when it is a named action.
local function parts_list(s)
	if s.action == ATTACK_ID then return ATTACK_DIRS end
	if s.action == CUSTOM_ID then return CUSTOM_LEVERS end
	return nil
end

-- Attack only offers plain directions; Custom also offers command motions, so
-- the two rows are not the same question. "Lever" was a Japanism for it -
-- English names what goes in, not the hardware.
--
-- The row and the heading of the screen it opens have to say the same word, so
-- both read it from here.
local function lever_row_name(s)
	return (s.action == ATTACK_ID) and "Direction" or "Motion"
end

-- WHEN THERE IS A DIRECTION TO KEEP HOLDING.
--
-- One rule, and it is mechanical: a step can hold if its input list ENDS on a
-- direction. That is the thing the runner would keep asserting, so it is also
-- the thing worth offering.
--
--   Attack Down Back + LP   ends {down,back,LP}   the row appears
--   Stand Forward           ends {forward}        appears - walk until the
--                                                 next step, which is what
--                                                 "15 ticks then throw" needs
--   Attack Neutral + LP     ends {LP}             no direction, no row
--   Stand Neutral           ends {}               nothing at all, no row
--
-- Attack was the only group offered at first, and movement was left out on the
-- grounds that a dash is a fixed animation. That was the wrong cut: a walk that
-- lasts two ticks is not a walk, and the whole point of Wait is to say how long
-- the thing before it goes on for.
--
-- Read from make_input_sequence rather than from a list of ids kept here, so a
-- motion whose entries change cannot leave this offering a row that does
-- nothing. Cached: this is asked on every drawn frame.
local HOLD_DIRS = {
	["forward"] = true, ["back"] = true, ["up"] = true, ["down"] = true,
}

local holdable_cache = {}

local function motion_holdable(motion)
	if motion == nil or motion == "none" then return false end
	-- A DASH CANCEL HOLDS ITS REVERSE DIRECTION ON ITS OWN.
	--
	-- The runner parks the cancel direction two ticks past the step's taps and
	-- merges it into the next step's button - that IS the move. The Hold row
	-- here would keep the dash's own forward down instead, which releases the
	-- cancel; so the row is not offered at all.
	if motion == "forward dash cancel" or motion == "back dash cancel" then
		return false
	end
	local c = holdable_cache[motion]
	if c ~= nil then return c end
	local r = false
	local ok, seq = pcall(make_input_sequence, motion, "none", "", 0)
	if ok and type(seq) == "table" and #seq > 0 then
		for _, k in ipairs(seq[#seq] or {}) do
			if HOLD_DIRS[k] then r = true break end
		end
	end
	holdable_cache[motion] = r
	return r
end

-- EVERY ACTION NAMES ITS GROUP FIRST.
--
-- A named action always did - "Dash Forward" - but an assembled one showed only
-- its parts, so the same row read at two different grain sizes: "Dash Forward"
-- beside a bare "LP". Leading with the group makes one shape for all of them,
-- and it is what tells "Neutral" (do nothing) apart from "Attack Neutral + LP".
local function group_name_of(s)
	for _, grp in ipairs(groups(true)) do
		if grp.assemble == s.action then return grp.label end
	end
	return nil
end

-- mark is " (Hold)" when the list wants to show that the direction stays down,
-- and "" everywhere else. It goes straight after the DIRECTION, because that is
-- what is being held - the button is released either way.
--
--   Attack Down Back (Hold) + LP
--   Stand Forward (Hold)
--
-- The detail screen passes nothing: it has a Hold row of its own right below,
-- and saying it twice on one screen is how the Action row got confusing before.
-- sep is what goes between the group and the item. The list uses " : " so the
-- two read as separate columns; the detail screen's Action row already begins
-- with "Action : " and would say it twice, so that one asks for a space.
local function action_label(s, mark, sep)
	mark = mark or ""
	sep = sep or " : "
	local levers = parts_list(s)
	if levers ~= nil then
		local head = group_name_of(s)
		head = (head ~= nil) and (head .. sep) or ""
		local dir = s.lever or "none"
		local body = (dir == "none") and "" or (label_of(levers, dir) .. mark .. " + ")
		if (s.button or "none") ~= "none" then
			return head .. body .. label_of(CUSTOM_BUTTONS, s.button)
		end
		-- No button at all: the direction is the whole action.
		if dir == "none" then return head .. "Nothing" end
		return head .. label_of(levers, dir) .. mark
	end
	for _, grp in ipairs(groups(true)) do
		if grp.action and grp.action.id == s.action then return grp.label .. mark end
		if grp.list then
			for _, x in ipairs(grp.list) do
				if x.id == s.action then
					-- A motion special names its strength too: the move and the
					-- button are one action, which is what this group is for.
					-- A sequence special has no button of its own to name.
					-- "Pursuit : Pursuit" says one thing twice. The group is
					-- named after the only move in it for most characters, so
					-- the name is dropped when it repeats the heading.
					local head = (x.label == grp.label) and grp.label
					             or (grp.label .. sep .. x.label)
					local spb = special_button_row(s)
					if spb ~= nil and (s.button or "none") ~= "none" then
						return head .. mark .. " + " .. label_of(spb, s.button)
					end
					return head .. mark
				end
			end
		end
	end
	return tostring(s.action)
end

-- The motion string a step will be built from, or nil if it names nothing.
local function step_motion(s)
	-- A special names a move, not a motion. Hold asks whether the last entry
	-- ends on a direction, so it takes the command's own motion; a sequence has
	-- none and is not holdable, which is the right answer for a command that
	-- already ends on its own button.
	local sp = special_of(s)
	if sp ~= nil then
		return (sp.command.type == "motion") and sp.command.motion or nil
	end
	if parts_list(s) ~= nil then return s.lever or "none" end
	for _, grp in ipairs(groups(true)) do
		if grp.action and grp.action.id == s.action then return grp.action.motion end
		if grp.list then
			for _, x in ipairs(grp.list) do
				if x.id == s.action then return x.motion end
			end
		end
	end
	return nil
end

-- Named actions and assembled ones both answer through step_motion, so Dash,
-- Jump, Stand and Crouch get the Hold row on exactly the same terms an Attack
-- does.
local function can_hold(s)
	return motion_holdable(step_motion(s))
end

-- STEP ONE HAS NO Auto.
--
-- It used to, and it meant the dash-attack press offset - a different thing
-- from the Auto on every later step, which is "as early as the game allows".
-- One word for two ideas is what made the setting unreadable.
--
-- It is not needed any more either: "Dash Forward, then Auto attack" as two
-- steps produces the same dash attack, measured, so the one-step spelling has
-- nothing left to say. Step one's floor is simply zero.
local function wait_floor(_s, index)
	if index > 1 then return WAIT_AUTO end
	return 0
end

-- WHAT AN Auto ACTUALLY RESOLVES TO, WHEN IT RESOLVES TO A NUMBER.
--
-- Auto after a dash is the measured dash-attack offset, as is (the arm's
-- kd_press_base() already covers the tick from the free-1 signature to the
-- dash's own last tap - see actionSequenceRunner). Showing
-- the number is the whole point of this: the same expression the compiler uses
-- is used here, so the screen cannot drift from what runs.
--
-- Every other Auto is a state test - "the dummy can act", or the airborne
-- animation flag - and has no number to show.
-- THE RUNNER OWNS THIS ANSWER. THE ROW ONLY PRINTS IT.
--
-- This used to work it out again from the motion of the step before, which
-- cannot tell an air dash from a ground one - so the row said Auto (0) while
-- the schedule was using the state test. Two copies of one rule is how a
-- setting comes to mean something different from what it shows.
--
-- seq_auto_ticks is published by guardCancel.lua, which owns both measured
-- tables. nil is a real answer: no number, so Auto is the state test.
local function auto_ticks(s, i)
	if i <= 1 or seq_auto_ticks == nil then return nil end
	local prev = draft and draft.steps and draft.steps[i - 1]
	if prev == nil then return nil end
	-- Two back as well: the attack after an air dash is timed from the jump.
	return seq_auto_ticks(prev, s, draft.steps[i - 2])
end

-- Rapid fire repeats the button already out, so the step in FRONT is what
-- decides whether the row makes sense. A light attack, or a custom step whose
-- button is a light one - both are a light normal to the game.
local function prev_is_light(prev)
	if prev == nil then return false end
	if prev.action ~= ATTACK_ID and prev.action ~= "custom" then return false end
	local b = prev.button
	return b == "LP" or b == "LK"
end

-- Wait choices are displayed vertically in a stable order. Their stored values
-- remain the existing strings/numbers, so changing the GUI does not migrate or
-- reinterpret saved Action Steps. Step one is still a trigger offset and only
-- offers Fixed Ticks.
local WAIT_CHOICES = {
	{ label = "After",       timing = nil },
	{ label = "Landing",     timing = TIMING_LANDING },
	{ label = "Rapid",       timing = TIMING_RAPID },
	{ label = "Chain",       timing = TIMING_CHAIN },
	{ label = "Cancel",      timing = TIMING_CANCEL },
	{ label = "Late Cancel", timing = TIMING_LATE_CANCEL },
	{ label = "Fixed Ticks", fixed = true },
}

-- RAPID FIRE IS ONLY OFFERED BEHIND A LIGHT ATTACK.
--
-- The runner asks the animation cel, not the strength, because that is where
-- the game keeps the answer (0x028FB0 never looks at $102 to decide whether a
-- repeat is allowed, only to work out which button counts). The row is
-- narrower than the gate on purpose: light attacks are what carry the flag in
-- practice, and a mode that silently never fires is worse on a menu than one
-- that is not there.
--
-- A step that already holds it keeps it, so editing the step in front cannot
-- strand a saved setting on a row the cursor can no longer reach.
local function wait_choices_for(st, prev)
	if prev_is_light(prev) or (st ~= nil and st.timing == TIMING_RAPID) then
		return WAIT_CHOICES
	end
	local out = {}
	for _, c in ipairs(WAIT_CHOICES) do
		if c.timing ~= TIMING_RAPID then out[#out + 1] = c end
	end
	return out
end

local function wait_choice_index(st, index, prev)
	if index == 1 then return 1 end
	local list = wait_choices_for(st, prev)
	if st.timing ~= nil then
		for i, c in ipairs(list) do
			if c.timing == st.timing then return i end
		end
	end
	if st.wait ~= WAIT_AUTO then return #list end
	return 1
end

-- STEP ONE IS COUNTED FROM THE TRIGGER, THE REST FROM THE STEP BEFORE.
--
-- Step one's wait is a real setting, not a formality: "dragon punch on the
-- fifth tick after the guard" is one of the things this is for. It is the same
-- offset Guard Action Delay uses, so the motion goes in at once and only the
-- press waits - which is the only way to put a press on a named tick.
local function wait_label(s, i)
	local v = s.wait or 0
	-- ONE WORD FOR IT: Auto. What it waits for belongs in the description, not
	-- in the value - a value that is a sentence reads as a different setting
	-- every time the sentence changes.
	-- ONE WORD, Auto, AND A BRACKET SAYING WHICH KIND OF EARLIEST.
	--
	-- Every Auto in this tool means "timed so it comes out as early as it can".
	-- What differs is which earliest, so the bracket names it:
	--
	--   Fastest    step one. The trigger's own earliest - free+0 for a special,
	--              the next tick for a normal, a dash or a jump. Same word the
	--              HUD prints when a reversal lands there, so the setting and
	--              the result read alike.
	--   Recovered  after the previous move has finished. The glossary gives
	--              Recovery/stun for 硬直, so this is 硬直明け.
	--   11         when it resolves to a count (a dash attack).
	if i == 1 then
		-- A saved -1 from when step one had an Auto reads here too, because
		-- that is what it now does.
		if v <= 0 then return "Auto (Fastest)" end
		return tostring(v) .. " Ticks"
	end
	if s.timing == TIMING_LANDING then return "Auto (Landing)" end
	-- RAPID FIRE, NOT "REPEAT" OR "MASH".
	--
	-- Rapid fire is the term Capcom's own material uses for 連打キャンセル, and
	-- it is what the English-speaking side of this game calls it. Repeat is
	-- already taken here by the repeat-type commands, and Mash names what the
	-- player does rather than what the game grants.
	if s.timing == TIMING_RAPID then return "Auto (Rapid Fire)" end
	if s.timing == TIMING_CHAIN then return "Auto (Chain)" end
	if s.timing == TIMING_CANCEL then return "Auto (Cancel)" end
	if s.timing == TIMING_LATE_CANCEL then return "Auto (Late Cancel)" end
	if v == WAIT_AUTO then
		local n = auto_ticks(s, i)
		if n ~= nil then return "Auto (" .. n .. ")" end
		-- Recovered IS THE EARLIEST AFTER AN ATTACK, AND ONLY THERE.
		--
		-- "The dummy has finished what it was doing" is exactly the earliest
		-- when the thing it was doing was an attack - measured on Jedah's air
		-- chain, and it is what makes step four of an air string land.
		--
		-- After a jump, a dash or an air dash it is not the earliest at all,
		-- and printing the word there promises something the row does not do.
		-- Those come from a measured table, so when the table has no entry for
		-- the combination the row says so rather than naming the wrong thing.
		local prev = draft and draft.steps and draft.steps[i - 1]
		if seq_auto_needs_number ~= nil and seq_auto_needs_number(prev) then
			return "Auto (Not Measured)"
		end
		return "Auto (After)"
	end
	-- A NUMBER AND A UNIT, NOT A SENTENCE.
	--
	-- These used to read "Right after the input" and "5 Ticks after the last
	-- step". The reference point is fixed by position - step one counts from
	-- the trigger, every later step from the one before it - so saying it on
	-- every row bought nothing and cost a phrase to parse. Digits read the
	-- same in any language; English prose does not.
	return tostring(v) .. " Ticks"
end

-- Checked once, against the real implementation, so an action whose motion has
-- been renamed shows up here instead of silently delivering nothing.
local function validate()
	if checked then return end
	checked = true
	if make_input_sequence == nil then return end
	local bad = 0
	for _, grp in ipairs(groups(true)) do
		local all = grp.list or (grp.action and { grp.action }) or {}
		for _, a in ipairs(all) do
			-- A SPECIAL IS CHECKED AGAINST ITS OWN COMMAND.
			--
			-- It has no motion of its own - the name is the action - so passing
			-- a.motion here asked make_input_sequence for nil and counted every
			-- special as broken. A motion command still goes through the real
			-- implementation, which is what this check is for; a sequence
			-- command is the input list already, so what there is to check is
			-- that it has entries.
			if a.command ~= nil then
				if a.command.type == "sequence" then
					if type(a.command.sequence) ~= "table"
					   or #a.command.sequence == 0 then bad = bad + 1 end
				-- A repeat has no motion to look up either - what it needs is a
				-- count and a button, and the button comes from the step. Asking
				-- make_input_sequence for its nil motion is what printed
				-- "no branch for stick 'nil'" at startup.
				elseif a.command.type == "repeat" then
					if type(a.command.count) ~= "number" or a.command.count < 2 then
						bad = bad + 1
					end
				else
					local ok, seq = pcall(make_input_sequence, a.command.motion, "none", "", 0)
					if not ok or type(seq) ~= "table" or #seq == 0 then bad = bad + 1 end
				end
			else
				local ok, seq = pcall(make_input_sequence, a.motion, "none", "", 0)
				if not ok or type(seq) ~= "table" or #seq == 0 then bad = bad + 1 end
			end
		end
	end
	if bad > 0 then
		print("actionSequenceEditor: " .. bad .. " action(s) have no motion in make_input_sequence")
	end
end

local function store()
	training_settings.action_sequences = training_settings.action_sequences or {}
	return training_settings.action_sequences
end

-- ONE SEQUENCE PER CHARACTER.
--
-- A sequence is built around a particular dummy - which moves it has, how high
-- it has to be, how long its animations run - and building one is enough work
-- that losing it on a character change would make the feature not worth using.
-- Keyed by $382, as a string so the settings file stays a plain object.

local CHARS = {
	[0x00] = "Bulleta",  [0x01] = "Demitri",  [0x02] = "Gallon",
	[0x03] = "Victor",   [0x04] = "Zabel",    [0x05] = "Morrigan",
	[0x06] = "Anakaris", [0x07] = "Felicia",  [0x08] = "Bishamon",
	[0x09] = "Aulbath",  [0x0A] = "Sasquatch",[0x0B] = "Zabel 2",
	[0x0C] = "Q-Bee",    [0x0D] = "Lei-Lei",  [0x0E] = "Lilith",
	[0x0F] = "Jedah",    [0x12] = "Dark Gallon", [0x18] = "Oboro",
}

local function cid_name()
	return CHARS[cid_num()] or string.format("Char %02X", cid_num())
end

-- Read-only: safe to call from a draw, where creating tables as a side effect
-- would be a surprise. Returns nil when this character has nothing saved.
local function current(which)
	local root = training_settings and training_settings.action_sequences
	local per = root and root[which]
	if type(per) ~= "table" then return nil end
	if per.steps ~= nil then return nil end        -- pre-split entry
	return per[tostring(memory.readbyte(CID_ADDR))]
end

-- The per-character table for a trigger, created on demand. An entry saved
-- before this split has "steps" at the top level; it belonged to whichever
-- dummy was up at the time and there is no way to recover which, so it is
-- handed to the current one rather than thrown away.
local function read_saved(which, character_id)
	local root = training_settings and training_settings.action_sequences
	local per = root and root[which]
	if type(per) ~= "table" then return nil end
	-- Pre-split data is copied into the Draft, but migrated only by Save.
	-- Merely opening or discarding the Editor must not mutate settings.
	if per.steps ~= nil then return per end
	return per[tostring(character_id)]
end

local function bucket(which, character_id)
	local root = store()
	local per = root[which]
	if type(per) ~= "table" then per = {} ; root[which] = per end
	if per.steps ~= nil then
		local old = per
		per = { [tostring(character_id or cid_num())] = old }
		root[which] = per
	end
	return per
end

local function new_step()
	-- NOT A REAL ACTION, AND Auto BY DEFAULT.
	--
	-- Every step used to default to Dash Forward, so adding steps produced a
	-- column of identical rows that read as "Add step copied row one". Neutral
	-- is visibly a blank to fill in, and it is the one action that does nothing
	-- if left alone.
	--
	-- Auto is right in either position, which is why one default covers both:
	-- step one shows Auto (Fastest) and clamps to 0, later steps get
	-- Auto (Recovered) - or a number when the step before is a dash.
	return { action = "neutral", wait = WAIT_AUTO }
end

-- ADD Step COPIES THE LAST ONE.
--
-- Not the same thing as the bug above, though it looks like it. That one gave
-- every new step the same DEFAULT - Dash Forward - which read as a copy of row
-- one without being one, and was useless because it was never what was wanted.
-- This copies the row actually just built, which is what a list like
-- "LP, LP, LP, LP" is made of: adding a step stopped meaning Action > Attack >
-- Button > LP every single time.
--
-- The whole step is copied, Wait included. A first step's Auto is stored as -1
-- and reads as Auto (Recovered) in second position, so the meaning carries over
-- on its own.
--
-- The first step of an empty list has nothing to copy and gets the blank.
local function added_step()
	local last = draft and draft.steps and draft.steps[#draft.steps]
	if last == nil then return new_step() end
	return copy(last)
end

local function defaults()
	-- No enabled flag: Guard Action Type = Reversal - Sequence is the switch.
	return { version = 1, steps = { new_step() } }
end

-- THE LIBRARY'S OWN STORE, BESIDE THE ONE ACTION STEPS USES.
--
-- Same shape as action_sequences, so the per-character split reads the same
-- way: action_patterns[trigger][character_id] = { version, items }. An item is
-- one saved list - { name, use, steps }.
--
-- "use" IS THE PLAY MODE. One ticked runs that one, several ticked pick
-- between them. There is no Play Mode row, because the ticks already say it
-- and that is one thing to learn instead of two
-- (design_action_pattern_library.md).
-- WHICH LIBRARY ITEM THE DRAFT BELONGS TO, READ FROM THE STACK.
--
-- Derived rather than stored. Three places pop the stack, and a flag left
-- behind by any one of them would point the next Save at the wrong list - which
-- is the shape of two of the four bugs the ported implementation had.
local function pattern_edit()
	for i = #stack, 2, -1 do
		if stack[i].type == "root" and stack[i - 1].type == "pattern" then
			return stack[i - 1].index
		end
	end
	return nil
end

local function pattern_store()
	training_settings.action_patterns = training_settings.action_patterns or {}
	return training_settings.action_patterns
end

local function pattern_row(which, character_id)
	local per = pattern_store()[which]
	if type(per) ~= "table" then per = {} ; pattern_store()[which] = per end
	local key = tostring(character_id or cid_num())
	local row = per[key]
	if type(row) ~= "table" then row = { version = 1, items = {} } ; per[key] = row end
	if type(row.items) ~= "table" then row.items = {} end
	return row
end

local function pattern_items()
	return pattern_row(trigger, editor_character_id).items
end

local function push(s) stack[#stack + 1] = s end
local function top() return stack[#stack] end

local function close()
	active = false
	stack = {}
	draft = nil
	editor_character_id = nil
end

local function back()
	if #stack > 1 then table.remove(stack) else close() end
end

-- SAVING IS ONE PLACE, BECAUSE TWO ROWS DO IT.
--
-- The Save row and Save and Close on the close screen have to write the same
-- thing. A fresh table every time: the runner keys its compile cache on this
-- table's identity, so replacing it IS the invalidation.
local function save_draft()
	-- Back to where it came from. Saving a library item into the Action Steps
	-- list would overwrite a list the player never opened.
	local _i = pattern_edit()
	if _i ~= nil then
		local items = pattern_items()
		local it = items[_i]
		if it ~= nil then
			-- A WHOLE NEW TABLE, NOT A NEW steps FIELD. The runner keys its
			-- compile cache on this table's identity, so replacing it IS the
			-- invalidation - the same reason the Action Steps branch below
			-- assigns a fresh table rather than editing one in place.
			items[_i] = { name = it.name, use = it.use, steps = copy(draft).steps }
		end
		-- And the runner is holding a reference to the one just replaced.
		if seq_forget_pick ~= nil then seq_forget_pick() end
		mark_training_settings_dirty()
		return
	end
	bucket(trigger, editor_character_id)[editor_character_id] = copy(draft)
	mark_training_settings_dirty()
end

-- HAS ANYTHING ACTUALLY CHANGED?
--
-- The close screen used to appear on the way out whatever the player had done,
-- so opening the list to look at it and leaving asked a question with no
-- content. And the OTHER way out - Left off the root - never asked at all, so
-- a real edit could be dropped in silence. Both are the same missing fact:
-- whether the draft still equals what is saved.
--
-- Compared field by field rather than by serialising, because the draft carries
-- nil-valued keys (a step with no timing, a sequence special with no button)
-- and those have to compare equal to a saved table that simply lacks them.
local function same_step(a, b)
	if a == nil or b == nil then return a == b end
	local seen = {}
	for k, v in pairs(a) do seen[k] = true if b[k] ~= v then return false end end
	for k, v in pairs(b) do if not seen[k] and a[k] ~= v then return false end end
	return true
end

-- WHAT THE DRAFT IS BEING COMPARED WITH.
--
-- While a library item is open it is that item's own steps, not the Action
-- Steps list. The ported implementation took its baseline from the wrong place
-- and the editor read "changed" from the moment it opened
-- (design_action_pattern_library.md, bug 3).
local function saved_baseline()
	local _i = pattern_edit()
	if _i ~= nil then
		local it = pattern_items()[_i]
		if it == nil or type(it.steps) ~= "table" then return nil end
		return { version = 1, steps = it.steps }
	end
	return read_saved(trigger, editor_character_id)
end

local function dirty()
	if draft == nil then return false end
	local saved = saved_baseline()
	-- Nothing saved yet: a list with one untouched default step is still
	-- nothing, and asking about it would be the same empty question.
	if saved == nil or type(saved.steps) ~= "table" then
		if #draft.steps ~= 1 then return true end
		return not same_step(draft.steps[1], new_step())
	end
	if #draft.steps ~= #saved.steps then return true end
	for i = 1, #draft.steps do
		if not same_step(draft.steps[i], saved.steps[i]) then return true end
	end
	return false
end

-- OUT THROUGH togglemenu, THE WAY THE WIZARD GOES.
--
-- Setting show_menu on its own would leave both players disabled behind a menu
-- that is no longer drawn (see recordingWizard's back_to_menu). Called only
-- after close(), so the guard in togglemenu does not send it straight back
-- here.
local function leave_menu()
	if globals ~= nil and globals.menuModule ~= nil
	   and globals.menuModule.togglemenu ~= nil then
		globals.menuModule.togglemenu()
	end
end

-- THE MENU BUTTON IS A THIRD WAY OUT, AND IT USED TO BE SILENT.
--
-- A draft only reaches training_settings on Save, so the two rows on the root
-- screen are the whole contract: Save keeps it, Back Without Saving drops it.
-- The menu button went past both and took the edit with it - several screens
-- deep, with nothing on screen saying that would happen.
--
-- A FLAG AND NOTHING MORE. This is reached from togglemenu, which the hotkey
-- callback calls; the wizard's request_cancel carries the note that doing real
-- work in that callback once killed the hotkey outright. The screen is pushed
-- on the next registerBefore like any other.
--
-- Returns whether the close was taken over, so togglemenu knows to stop.
local close_requested = false

function M.request_close()
	if not active then return false end
	close_requested = true
	return true
end

-- THE LIST SAYS WHAT THE STEP SAYS.
--
-- This used to compress the timing into a second vocabulary - Auto(11) without
-- the space, +5t for what the step calls 5 Ticks - and it printed nothing at
-- all for step one, so a list beginning "1  Dash Forward" hid the fact that the
-- dash is timed at all. Step one's Auto (Fastest) is a real answer to when, and
-- the reversal's whole point.
--
-- So the row uses wait_label, the same words the step itself shows. The longest
-- this can get is 16 + Auto (Recovered) + Custom Charge Back-Forward + LP+LK,
-- which is 62 characters with the cursor and arrow - 248 px inside a panel that
-- has 327.
-- THREE COLUMNS, SO THE LIST CAN BE READ DOWNWARDS.
--
-- The number, the when, and the what. Ragged, the whens and the whats both
-- start at a different place on every row and the eye has to find them again
-- each time - which matters most for the thing the list is FOR: seeing whether
-- a run of steps shares a timing, or whether a Hold is missing from the middle
-- of a charge.
--
-- Widths are measured from the list being drawn rather than fixed, so a list of
-- short waits does not carry a gap sized for Auto (Not Measured).
local function step_label(s, i, num_w, wait_w)
	-- Hold is shown here and nowhere else in the list. A charge is built by
	-- several steps in a row holding, and whether that chain is unbroken is a
	-- property of the LIST - reading it one step at a time is how a missing
	-- Hold in the middle goes unnoticed.
	local mark = (s.hold and can_hold(s)) and " (Hold)" or ""
	local n, w = tostring(i), wait_label(s, i)
	return n .. string.rep(" ", (num_w or #n) - #n + 2)
	    .. w .. string.rep(" ", (wait_w or #w) - #w + 2)
	    .. action_label(s, mark)
end

local function root_items()
	-- Two passes: the widths cannot be known until every row has been asked what
	-- it says. This was written when the cap was sixteen; at 4096 it is the
	-- reason the editor slows down, and the fix is to build only the rows on
	-- screen. Measured in handoff_v11.5_action_steps.md.
	local num_w, wait_w = 0, 0
	for i, s in ipairs(draft.steps) do
		local n, w = #tostring(i), #wait_label(s, i)
		if n > num_w then num_w = n end
		if w > wait_w then wait_w = w end
	end

	local a = {}
	for i, s in ipairs(draft.steps) do
		a[#a + 1] = { label = step_label(s, i, num_w, wait_w),
		              kind = "step", index = i, child = true }
	end
	-- Set apart from the steps: these act on the LIST, not on a step in it.
	if #draft.steps < MAX_STEPS then
		a[#a + 1] = { label = "+ Add Step", kind = "add", child = true, gap_before = true }
	end
	a[#a + 1] = { label = "Save", kind = "save", gap_before = true }
	a[#a + 1] = { label = "Back Without Saving", kind = "cancel" }
	-- LAST, AND ONLY WHEN THERE IS SOMETHING TO CLEAR.
	--
	-- It acts on the whole list, so it sits below the two rows that also do -
	-- and at the bottom, where a walk down the list cannot arrive on it by
	-- accident. A list that is already one empty step has nothing to clear and
	-- the row would do nothing, so it is not offered.
	if #draft.steps > 1 or not same_step(draft.steps[1], new_step()) then
		a[#a + 1] = { label = "Clear All Steps", kind = "clear", gap_before = true }
	end
	return a
end

local function detail_items(i)
	local s = draft.steps[i]
	-- THE ACTION AND ITS PARTS STAY TOGETHER.
	--
	-- Wait used to sit between them, so the indented Direction and Button rows
	-- read as if they belonged to Wait. They belong to Action; Wait is the
	-- other question this step answers, and it comes after.
	-- THE ROW SHOWS WHAT ITS OWN SCREEN CHOOSES.
	--
	-- Opening Action picks a group, and for an assembled step that is all it
	-- picks - the direction and the button are the two rows below. Printing
	-- "Attack LP" here would say the button twice. A named action has no rows
	-- below it, so there the whole name belongs on this line.
	local head = group_name_of(s)
	local a = {
		{ label = "Action : " .. (head or action_label(s, "", " ")),
		  kind = "action", child = true },
	}
	-- Attack and Custom are assembled from parts. Everything else is one name.
	local levers = parts_list(s)
	if levers ~= nil then
		a[#a + 1] = { label = "  " .. lever_row_name(s) .. " : " .. label_of(levers, s.lever or "none"),
		              kind = "lever", child = true }
		a[#a + 1] = { label = "  Button : " .. label_of(CUSTOM_BUTTONS, s.button or "none"),
		              kind = "button", child = true }
	end
	-- A named special takes its button on its own row, and there is no Motion
	-- row above it: the motion IS the name. A sequence move gets no row at all -
	-- its buttons are part of the command.
	local spb = special_button_row(s)
	if spb ~= nil then
		a[#a + 1] = { label = "  Button : " .. label_of(spb, s.button or "none"),
		              kind = "button", child = true }
	end
	-- Indented, because it is part of the action rather than a sibling of Wait:
	-- it says what the input IS, not when it happens. Outside the block above so
	-- a named action - Dash, Jump, Stand, Crouch - gets it on the same terms.
	if can_hold(s) then
		a[#a + 1] = { label = "  Hold : " .. (s.hold and "Yes" or "No"),
		              kind = "hold" }
	end
	-- "Wait", and it stays "Wait".
	--
	-- This was briefly "Start", because the screen it opened was headed WHEN DOES
	-- IT START? and beside that question "Wait : Auto (Fastest)" reads as waiting
	-- for the fastest. The question was the fault: a screen that asks something
	-- makes its row answer, and the row's name drifts. The headings are locations
	-- now (see guiRegister), so this is the noun it always was - the wait - and
	-- Auto (Fastest) is its value.
	a[#a + 1] = { label = "Wait : " .. wait_label(s, i), kind = "wait", child = true }
	-- What to do with the step, kept apart from what the step does.
	if #draft.steps > 1 then
		a[#a + 1] = { label = "Move Step : " .. tostring(i) .. " / " .. tostring(#draft.steps),
		              kind = "order", child = true, gap_before = true }
		a[#a + 1] = { label = "Remove This Step", kind = "delete", child = true }
		a[#a + 1] = { label = "Back", kind = "back" }
	else
		a[#a + 1] = { label = "Back", kind = "back", gap_before = true }
	end
	return a
end

-- TYPING A NAME HAPPENS OUTSIDE, AND EVERYTHING STOPS WHILE IT DOES.
--
-- FBNeo's Lua has no text entry. io.popen -> PowerShell -> a Windows Forms box
-- is the route the file dialog probe proved on hardware (2026-09-16), and it
-- costs what that cost: the emulator is frozen until the box is closed,
-- measured there at 6.6s to 39s. Acceptable for an explicit menu action, which
-- is the only place this is reachable from.
--
-- THE PLAYER IS TOLD FIRST. The naming screen is drawn on one frame and the box
-- opens on the next, because registerBefore runs BEFORE the frame is presented:
-- opening it immediately would freeze the picture on the previous screen, with
-- no clue that a keyboard is now wanted.
local NAME_MAX = 66
local NAME_PS1 = nil
local function find_name_ps1()
	if NAME_PS1 ~= nil then return NAME_PS1 end
	-- io.open resolves a relative path against THIS script's own folder, which
	-- is where the .ps1 sits. The second candidate covers being driven from
	-- the package root.
	for _, cand in ipairs({ "name_prompt.ps1", "scripts/name_prompt.ps1" }) do
		local f = io.open(cand, "r")
		if f ~= nil then f:close() ; NAME_PS1 = cand ; return NAME_PS1 end
	end
	return nil
end

-- ASCII ONLY, BECAUSE gui.text DRAWS NOTHING ELSE.
--
-- Measured 2026-09-16: anything outside ASCII comes out blank, so a name typed
-- in Japanese would save correctly and then show as an empty row. Stripped
-- rather than refused, so a mixed name keeps the part that can be read.
local function clean_name(s, max)
	local out = {}
	for i = 1, #tostring(s) do
		local b = tostring(s):byte(i)
		if b >= 0x20 and b <= 0x7E then out[#out + 1] = string.char(b) end
	end
	local t = table.concat(out)
	t = t:gsub("^%s+", ""):gsub("%s+$", "")
	if #t > max then t = t:sub(1, max) end
	return t
end

-- Replaced wholesale by the offline tests, which must never spawn a process.
function M.prompt_name(current)
	if io.popen == nil then return nil end
	local ps1 = find_name_ps1()
	if ps1 == nil then return nil end
	-- 2>&1 MATTERS. Without it PowerShell's own errors go to stderr, Lua sees
	-- only the interactive banner, and a failure reports as "nothing happened"
	-- with no way to say why. That cost a whole probe run in 2026-09-16.
	local cmd = 'powershell -NoProfile -STA -ExecutionPolicy Bypass -File "'
		.. ps1 .. '" "' .. clean_name(current, NAME_MAX):gsub('"', "'") .. '" '
		.. NAME_MAX .. ' 2>&1'
	local f = io.popen(cmd, "r")
	if f == nil then return nil end
	local ok, out = pcall(function() return f:read("*a") end)
	f:close()
	if not ok or type(out) ~= "string" then return nil end
	-- Markers, not line numbers: the banner and anything on stderr land on the
	-- same stream, and neither of them is between these two.
	local body = out:match("VSAV_NAME_BEGIN(.-)VSAV_NAME_END")
	if body == nil then return nil end
	local status, name = body:match("^%s*([^\r\n]*)[\r\n]+(.-)%s*$")
	-- CANCELLED and ERROR both mean "leave it alone", and they have to be told
	-- apart from "PowerShell never ran" only in the log, not here.
	if status == nil or status:sub(1, 2) ~= "OK" then return nil end
	return clean_name(name, NAME_MAX)
end

-- WHAT IS ON SCREEN WHILE THE BOX IS OPEN.
--
-- Not a menu: the stick does nothing here and a cursor would say it did.
local function naming_items(s)
	local what = (s.purpose == "new") and "the new pattern" or "this pattern"
	return {
		{ plain = true, label = "USE YOUR KEYBOARD." },
		{ plain = true, label = "" },
		{ plain = true, label = "A window has opened for the name of " .. what .. "." },
		{ plain = true, label = "The game is stopped until you close it." },
		{ plain = true, label = "" },
		{ plain = true, label = "If it is hiding behind this one, Alt+Tab to it." },
		{ plain = true, label = "Cancel there changes nothing." },
	}
end

-- WHAT THE TYPED NAME DOES, WHICH DEPENDS ON WHY IT WAS ASKED FOR.
local function apply_name(s, name)
	-- Cleaned again here, not only in prompt_name. This is the one place a
	-- name reaches the saved data, and a row that cannot be drawn is worse
	-- than a truncated one.
	name = clean_name(name, NAME_MAX)
	if name == "" then return end
	local items = pattern_items()
	if s.purpose == "rename" then
		local it = items[s.index]
		if it ~= nil then it.name = name ; mark_training_settings_dirty() end
		return
	end
	-- Add from current Steps. The list the player already has, kept as it is -
	-- a copy, so editing the pattern afterwards does not reach back into it.
	if s.purpose == "import" then
		local src = read_saved(trigger, editor_character_id)
		local steps = nil
		if type(src) == "table" and type(src.steps) == "table" then
			steps = copy(src).steps
		end
		if steps == nil or #steps == 0 then steps = { new_step() } end
		items[#items + 1] = { name = name, use = true, steps = steps }
		mark_training_settings_dirty()
		-- Not into the editor: it already has its steps, so the item screen is
		-- where there is something to decide.
		push({ type = "pattern", index = #items, cursor = 1 })
		return
	end
	-- New. NOTHING IS CREATED UNTIL THERE IS A NAME TO PUT ON IT, so a Cancel
	-- in the box leaves the list exactly as it was rather than dropping an
	-- unnamed row into it.
	--
	-- Ticked on the way in: making one is asking to use it, and the tick is
	-- visible on the row it lands on.
	items[#items + 1] = { name = name, use = true, steps = { new_step() } }
	mark_training_settings_dirty()
	push({ type = "pattern", index = #items, cursor = 1 })
	-- Straight into the editor. An empty pattern is not worth stopping to look
	-- at (design_action_pattern_library.md).
	draft = { version = 1, steps = { new_step() } }
	push({ type = "root", cursor = 1 })
end

-- SENDING A LIBRARY OUT AND TAKING ONE IN.
--
-- Whole library, one file, one character - which is the unit anybody would
-- actually share ("my Sasquatch set"), and one dialog instead of one per
-- pattern. Each dialog freezes the emulator for as long as it is open.
--
-- LUA NEVER TOUCHES THE CHOSEN PATH. Lua 5.1 on Windows opens files through
-- the ANSI API, so io.open cannot open a UTF-8 path - measured 2026-09-16, and
-- cp932 cannot spell every path Windows allows either. The bytes are staged at
-- an ASCII path of our own and PowerShell copies to or from the chosen file.
local PATTERN_STAGE = "action_patterns_transfer.json"
local IMPORT_MAX = 256
local PATTERN_PS1 = nil
local function find_pattern_ps1()
	if PATTERN_PS1 ~= nil then return PATTERN_PS1 end
	for _, cand in ipairs({ "pattern_file.ps1", "scripts/pattern_file.ps1" }) do
		local f = io.open(cand, "r")
		if f ~= nil then f:close() ; PATTERN_PS1 = cand ; return PATTERN_PS1 end
	end
	return nil
end

-- Replaced wholesale by the offline tests, which must never spawn a process.
-- Returns the status word: OK, CANCELLED, or ERROR: something.
-- The file name the save dialog offers. ASCII only and no path separators -
-- it is pasted into a command line and then into a Windows file name.
local function file_who()
	local out = {}
	for _, ch in ipairs({ string.byte(cid_name() or "", 1, 64) }) do
		if (ch >= 0x30 and ch <= 0x39) or (ch >= 0x41 and ch <= 0x5A)
		   or (ch >= 0x61 and ch <= 0x7A) or ch == 0x20 or ch == 0x2D then
			out[#out + 1] = string.char(ch)
		end
	end
	return table.concat(out)
end

-- THE SUGGESTED FILE NAME FOR ONE PATTERN: the character AND the pattern's
-- own name. A folder of one-pattern files all called the same thing is the
-- same dead end a folder of libraries called the same thing is. The pattern
-- name carries whatever the player typed, so it is narrowed to the character
-- set file_who() allows - the value is pasted into a command line and then
-- into a Windows file name.
local function file_name_of(s)
	local out = {}
	for _, ch in ipairs({ string.byte(tostring(s or ""), 1, 64) }) do
		if (ch >= 0x30 and ch <= 0x39) or (ch >= 0x41 and ch <= 0x5A)
		   or (ch >= 0x61 and ch <= 0x7A) or ch == 0x20 or ch == 0x2D then
			out[#out + 1] = string.char(ch)
		end
	end
	local t = table.concat(out)
	t = t:gsub("^%s+", ""):gsub("%s+$", "")
	if t == "" then return "vsav_action_pattern(" .. file_who() .. ").json" end
	return "vsav_action_pattern(" .. file_who() .. "-" .. t .. ").json"
end

-- THE FOLDER THE LAST ACCEPTED DIALOG ENDED IN (user, 2026-09-21). One for
-- the whole tool: a file handed to someone and a file received live wherever
-- the player keeps them, not per character. Empty means "no memory yet" and
-- the dialog opens where it always did. The value is written back through the
-- ordinary settings save, which the distribution never includes.
local function remember_dir()
	local s = training_settings
	if type(s) ~= "table" then return "" end
	if type(s.pattern_dir) ~= "string" then return "" end
	return s.pattern_dir
end

-- Only an OK carries a folder. A cancel says "I looked, then changed my
-- mind" - the Windows dialogs themselves do not move for one of those, and
-- neither does this.
local function store_dir(dir)
	if type(dir) ~= "string" or dir == "" then return end
	if training_settings == nil then return end
	if training_settings.pattern_dir == dir then return end
	training_settings.pattern_dir = dir
	mark_training_settings_dirty()
end

-- THE REMEMBER PARAMETER IS FOR THE TESTS, which stub nothing here but assert
-- on what was handed over. Every caller in this file passes nothing, and the
-- settings value is what runs.
function M.transfer_file(mode, who, suggest, remember)
	if io.popen == nil then return "ERROR: no io.popen", nil end
	local ps1 = find_pattern_ps1()
	if ps1 == nil then return "ERROR: pattern_file.ps1 not found", nil end
	-- 2>&1, or PowerShell's errors go to stderr and Lua sees only the banner.
	local cmd = 'powershell -NoProfile -STA -ExecutionPolicy Bypass -File "'
		.. ps1 .. '" ' .. mode .. ' "' .. PATTERN_STAGE .. '" "'
		.. tostring(who or "") .. '" "' .. tostring(suggest or "") .. '" "'
		.. tostring(remember or remember_dir()):gsub('"', "'") .. '" 2>&1'
	local f = io.popen(cmd, "r")
	if f == nil then return "ERROR: io.popen returned nil", nil end
	local ok, out = pcall(function() return f:read("*a") end)
	f:close()
	if not ok or type(out) ~= "string" then
		return "ERROR: nothing came back", nil
	end
	local body = out:match("VSAV_PATTERN_BEGIN(.-)VSAV_PATTERN_END")
	if body == nil then return "ERROR: the script did not run", nil end
	-- THE FOURTH LINE INSIDE THE FENCE IS THE FOLDER OF THE CHOSEN FILE.
	-- Empty for CANCELLED and ERROR. The status stays the first line and the
	-- byte count the second, exactly as before this existed.
	local lines = {}
	for line in body:gmatch("[^\r\n]+") do lines[#lines + 1] = line end
	local status = (lines[1] or ""):match("^%s*(.-)%s*$")
	if status == nil or status == "" then return "ERROR: no status", nil end
	return status, lines[3]
end

local function export_now()
	if write_object_to_json_file == nil then return "ERROR: no json writer" end
	local items = pattern_items()
	if #items == 0 then return "ERROR: there is nothing saved to send" end
	local out = { version = 1, trigger = trigger,
	              character = cid_num(), items = {} }
	for i, it in ipairs(items) do
		-- Copied field by field, so nothing the editor happens to be keeping
		-- on an item rides along into a file other people will read.
		out.items[i] = { name = it.name, use = it.use, steps = it.steps }
	end
	if not write_object_to_json_file(out, PATTERN_STAGE) then
		return "ERROR: could not write the staging file"
	end
	local st, dir = M.transfer_file("save", file_who())
	if st == "OK" then store_dir(dir) end
	os.remove(PATTERN_STAGE)
	return st
end

-- ONE PATTERN, NOT THE LIBRARY (user, 2026-09-21). A single shared pattern is
-- the thing people hand each other; asking for the whole library and deleting
-- what arrives is not. The file is the same schema with a single item, so an
-- import that already knows how to add items takes it unchanged - and arrives
-- unticked there, like everything does.
local function export_one_now(i)
	if write_object_to_json_file == nil then return "ERROR: no json writer" end
	local it = pattern_items()[i]
	if it == nil then return "ERROR: that pattern is gone" end
	local out = { version = 1, trigger = trigger,
	              character = cid_num(), items = {} }
	-- The same field-by-field copy as the whole-library export, so nothing
	-- the editor happens to be keeping on an item rides along into a file
	-- other people will read.
	out.items[1] = { name = it.name, use = it.use, steps = it.steps }
	if not write_object_to_json_file(out, PATTERN_STAGE) then
		return "ERROR: could not write the staging file"
	end
	local st, dir = M.transfer_file("save", file_who(), file_name_of(it.name))
	if st == "OK" then store_dir(dir) end
	os.remove(PATTERN_STAGE)
	return st
end

-- EVERYTHING IN THAT FILE IS SOMEONE ELSE'S. None of it is trusted.
--
-- Fields are copied into a fresh table one at a time rather than the loaded
-- table being kept: an item carrying anything else would go straight into the
-- settings file and then into whatever that player exports next.
local function import_now()
	if read_object_from_json_file == nil then return "ERROR: no json reader" end
	os.remove(PATTERN_STAGE)
	local st, dir = M.transfer_file("open", file_who())
	if st ~= "OK" then return st end
	-- THE READ CARRIES ITS REASON NOW (utilities.lua). A missing stage and a
	-- broken file are no longer the same silent nil, and the message below
	-- names the file so a wrong pick is visible on the spot.
	local got, reason = read_object_from_json_file(PATTERN_STAGE)
	os.remove(PATTERN_STAGE)
	if got == nil then
		return "ERROR: could not read the chosen file (" .. tostring(reason) .. ")"
	end
	if type(got) ~= "table" or type(got.items) ~= "table" then
		return "ERROR: that is not a pattern file"
	end
	local items = pattern_items()
	local added, skipped = 0, 0
	for _, it in ipairs(got.items) do
		if added >= IMPORT_MAX then break end
		local nm = (type(it) == "table") and clean_name(it.name, NAME_MAX) or ""
		local src = (type(it) == "table") and it.steps or nil
		if nm == "" or type(src) ~= "table" or #src == 0 or #src > MAX_STEPS then
			skipped = skipped + 1
		else
			local steps, ok = {}, true
			for j, one in ipairs(src) do
				if type(one) ~= "table" then ok = false break end
				steps[j] = {
					action = one.action, lever = one.lever, button = one.button,
					wait = tonumber(one.wait) or WAIT_AUTO,
					timing = one.timing, hold = one.hold,
				}
			end
			if not ok then
				skipped = skipped + 1
			else
				-- ADDED, NEVER REPLACING. An import that wiped the list would
				-- destroy work that took far longer to make than the file did.
				--
				-- AND NEVER TICKED. Opening a file someone sent is not asking
				-- for the dummy's behaviour to change on the spot; MP on the
				-- row is one press when it is wanted.
				items[#items + 1] = { name = nm, use = false, steps = steps }
				added = added + 1
			end
		end
	end
	if added == 0 then return "ERROR: nothing usable in that file" end
	mark_training_settings_dirty()
	store_dir(dir)
	if skipped > 0 then
		return "OK  " .. added .. " added, " .. skipped .. " skipped"
	end
	return "OK  " .. added .. " added"
end

-- THE SCREEN THAT IS UP WHILE THE DIALOG HAS THE EMULATOR STOPPED, AND THE
-- ANSWER AFTERWARDS. One screen with two states, because the second one has to
-- replace the first without the player having gone anywhere.
local function transfer_items(s)
	if s.result ~= nil then
		return {
			{ plain = true, label = s.result },
			{ plain = true, label = "" },
			{ plain = true, label = "Import adds to this list. Nothing is replaced," },
			{ plain = true, label = "and what arrives starts unticked." },
		}
	end
	local verb = (s.purpose == "import" or s.purpose == "import_file")
		and "open" or "save"
	return {
		{ plain = true, label = "A FILE WINDOW HAS OPENED." },
		{ plain = true, label = "" },
		{ plain = true, label = "Pick where to " .. verb .. " the pattern file." },
		{ plain = true, label = "The game is stopped until you close it." },
		{ plain = true, label = "" },
		{ plain = true, label = "If it is hiding behind this one, Alt+Tab to it." },
		{ plain = true, label = "Cancel there changes nothing." },
	}
end

-- THE LIST. One row per saved pattern, then the two ways to make another.
local function pattern_list_items()
	local a = {}
	local items = pattern_items()
	-- The number is the ROW, not an id. Identity belongs to the item; what the
	-- player points at is a position, and a position is what they can count.
	local w = (#items >= 100) and 3 or 2
	for i, it in ipairs(items) do
		a[#a + 1] = {
			kind = "pattern", index = i, child = true,
			label = ((it.use == true) and "[x] " or "[ ] ")
				.. string.format("%0" .. w .. "d", i)
				.. "  " .. tostring(it.name or ""),
		}
	end
	a[#a + 1] = { kind = "new", child = true, label = "New",
		gap_before = (#items > 0) or nil }
	a[#a + 1] = { kind = "import", child = true, label = "Add from current Steps" }
	-- Set apart: these two leave the tool and take time, and the rows above
	-- are the ones used every session.
	a[#a + 1] = { kind = "export", child = true, label = "Export to a File",
		gap_before = true }
	a[#a + 1] = { kind = "import_file", child = true, label = "Import from a File" }
	a[#a + 1] = { kind = "back", label = "Back", gap_before = true }
	return a
end

-- ONE ITEM. Edit first, because it is what the row is for.
local function pattern_item_items(i)
	local it = pattern_items()[i]
	return {
		{ kind = "edit",   child = true, label = "Edit" },
		-- LP or Right toggles it, and Left is left alone to mean Back. A value
		-- on the stick's Left is a row the player cannot walk out of
		-- (design_action_pattern_library.md).
		{ kind = "use",    label = "Use in Random : "
			.. (((it ~= nil) and it.use == true) and "Yes" or "No") },
		{ kind = "rename", child = true, label = "Rename" },
		{ kind = "copy",   label = "Copy" },
		{ kind = "move",   child = true, label = "Move" },
		{ kind = "delete", child = true, label = "Delete" },
		-- Set apart, like its siblings on the list: this leaves the tool and
		-- takes time.
		{ kind = "export_one", child = true, label = "Export this Pattern",
			gap_before = true },
		{ kind = "back",   label = "Back" },
	}
end

local function build(s)
	if s.type == "naming" then return naming_items(s) end
	if s.type == "transfer" then return transfer_items(s) end
	if s.type == "patterns" then return pattern_list_items() end
	if s.type == "pattern" then return pattern_item_items(s.index) end
	-- THE SAME TWO SCREENS Move Step AND Remove USE, on the item list instead
	-- of the step list. Same shape, same keys, nothing new to learn.
	if s.type == "pattern_order" then
		local _p = tostring(s.index) .. " / " .. tostring(#pattern_items())
		if s.cursor == 1 then _p = "< " .. _p .. " >" end
		return { { label = "Position : " .. _p, kind = "order" },
		         { label = "Back", kind = "back", gap_before = true } }
	end
	if s.type == "pattern_delete" then
		return { { label = "No, keep it", kind = "no" },
		         { label = "Yes, delete this pattern", kind = "yes" } }
	end
	if s.type == "root" then return root_items() end
	if s.type == "detail" then return detail_items(s.index) end
	if s.type == "groups" then
		local a = {}
		for _, g in ipairs(groups()) do a[#a + 1] = { label = g.label, group = g, child = true } end
		return a
	end
	if s.type == "actions" then
		local a = {}
		for _, x in ipairs(s.list) do a[#a + 1] = { label = x.label, action = x } end
		return a
	end
	if s.type == "pick" then
		local a = {}
		for _, e in ipairs(s.list) do a[#a + 1] = { label = e[1], value = e[2] } end
		return a
	end
	if s.type == "wait" then
		local a = {}
		if s.index == 1 then
			-- Step one is measured from the trigger, not from a preceding action.
			-- Connection conditions have no meaning here.
			a[1] = { label = "Fixed Ticks : " .. wait_label(draft.steps[s.index], s.index),
			         kind = "fixed_wait", child = true, fixed = true }
		else
			for _, c in ipairs(wait_choices_for(draft.steps[s.index],
			                                    draft.steps[s.index - 1])) do
				local label = c.label
				-- SAY WHAT PICKING IT WILL DO.
				--
				-- The row this writes reads Auto (10) after a dash, because the
				-- earliest an attack can come out of one is a measured number -
				-- the attack lands INSIDE the dash, it does not follow it. The
				-- choice still said After, so the word on the menu and the word
				-- on the row disagreed and neither told you the tick.
				--
				-- Only where a dash makes After wrong. After an attack it is
				-- exactly right - the step waits for the dummy to finish - so
				-- that case keeps the word it has always had.
				if c.timing == nil and not c.fixed then
					local _n = auto_ticks(draft.steps[s.index], s.index)
					if _n ~= nil then
						label = "Fastest (" .. _n .. ")"
					elseif seq_auto_needs_number ~= nil
					       and seq_auto_needs_number(draft.steps[s.index - 1]) then
						label = "Fastest (Not Measured)"
					end
				end
				if c.fixed and draft.steps[s.index].timing == nil
				   and draft.steps[s.index].wait ~= WAIT_AUTO then
					label = label .. " : " .. tostring(draft.steps[s.index].wait)
				end
				a[#a + 1] = { label = label, kind = "wait_choice",
				                 timing = c.timing, fixed = c.fixed }
			end
		end
		a[#a + 1] = { label = "Back", kind = "back", gap_before = true }
		return a
	end
	if s.type == "fixed_wait" then
		local _v = tostring(draft.steps[s.index].wait or ((s.index > 1) and 1 or 0)) .. " Ticks"
		if s.cursor == 1 then _v = "< " .. _v .. " >" end
		return { { label = _v, kind = "fixed_wait" },
		         { label = "Back", kind = "back", gap_before = true } }
	end
	if s.type == "order" then
		-- THE SAME SHAPE AS Wait, BECAUSE IT IS THE SAME KIND OF SCREEN.
		--
		-- Both are one number set with the stick. Wait had a value row and a
		-- Back row and moved on Left/Right; this had one row, moved on Up/Down,
		-- and left on Left OR Right - so the two screens that do the same thing
		-- disagreed about every key. Left/Right moves the step now, and leaving
		-- is a row, exactly as it is there.
		local _p = tostring(s.index) .. " / " .. tostring(#draft.steps)
		if s.cursor == 1 then _p = "< " .. _p .. " >" end
		return { { label = "Position : " .. _p, kind = "order" },
		         { label = "Back", kind = "back", gap_before = true } }
	end
	if s.type == "confirm" then
		return { { label = "No, keep it", kind = "no" }, { label = "Yes, remove it", kind = "yes" } }
	end
	-- Same shape as the remove screen: the row that changes nothing leads.
	if s.type == "clear" then
		return { { label = "No, keep them", kind = "no" },
		         { label = "Yes, clear all steps", kind = "yes" } }
	end
	-- CANCEL FIRST, BECAUSE THE CURSOR STARTS ON ROW ONE.
	--
	-- This screen appears under the player's hand rather than being walked to,
	-- so whatever sits on row one is what a second press of a button already
	-- being pressed will take. The row that changes nothing goes there, the
	-- same way "No, keep it" leads the remove screen above.
	-- LEAVING A LIBRARY ITEM IS NOT LEAVING THE MENU.
	--
	-- The close screen below drops out of the editor AND the menu, which is
	-- right for the menu button. Left off a pattern's steps goes back to the
	-- pattern - so it is the same question with a different destination, and
	-- saying "Close" there would be a lie.
	if s.type == "pattern_close" then
		return { { label = "Cancel", kind = "no" },
		         { label = "Save and go back", kind = "save_back", gap_before = true },
		         { label = "Go back without saving", kind = "discard_back" } }
	end
	if s.type == "close" then
		return { { label = "Cancel", kind = "no" },
		         { label = "Save and Close", kind = "save_close", gap_before = true },
		         { label = "Close Without Saving", kind = "discard_close" } }
	end
	return {}
end

local function clamp(s, items)
	if #items == 0 then s.cursor = 1 return end
	if s.cursor < 1 then s.cursor = #items end
	if s.cursor > #items then s.cursor = 1 end
end

-- Opens on what is already set. Starting these lists at the top made Right
-- feel destructive: three presses walked in and confirmed row one, quietly
-- rewriting the step.
local function pick_screen(list, field, index)
	local current = draft.steps[index][field]
	local cursor = 1
	for i, e in ipairs(list) do
		if e[2] == current then cursor = i break end
	end
	local crumb = (field == "button") and "Button" or lever_row_name(draft.steps[index])
	return { type = "pick", list = list, field = field, index = index,
	         cursor = cursor, crumb = crumb }
end

-- THE FIRST SCREEN HAS TO OPEN ON THE CURRENT VALUE TOO.
--
-- Opening on what is already set was fixed for the lists below, and then the
-- picker gained a level in front of them - so Right landed on "Stand still"
-- again no matter what the step was set to, and the fix only applied after the
-- damage was done.
local function group_index_of(id)
	for i, g in ipairs(groups()) do
		if g.action and g.action.id == id then return i end
		if g.list then
			for _, x in ipairs(g.list) do
				if x.id == id then return i end
			end
		end
		-- Attack and Custom are assembled from parts rather than chosen.
		if g.assemble ~= nil and g.assemble == id then return i end
	end
	return 1
end

local function groups_screen(index)
	return { type = "groups", index = index, crumb = "Action",
	         cursor = group_index_of(draft.steps[index].action) }
end

local function actions_screen(group, index)
	local cursor = 1
	for i, a in ipairs(group.list) do
		if a.id == draft.steps[index].action then cursor = i break end
	end
	return { type = "actions", list = group.list, index = index,
	         cursor = cursor, crumb = group.label }
end

-- WHERE THE STEP LIST GOES BACK TO.
--
-- Out of the menu when it IS the Action Steps list - the menu row is what
-- opened it, so that is where it came from. One level up when it is a library
-- item: the pattern sits above its steps, and leaving the menu is not what
-- Save asked for (user, 2026-09-20).
local function leave_root()
	if pattern_edit() ~= nil then
		table.remove(stack)
		draft = nil
		return
	end
	close()
end

local function enter()
	local s = top()
	local items = build(s)
	local item = items[s.cursor]
	if item == nil then return end

	if s.type == "transfer" then
		-- Any of them closes it. There is nothing on this screen to choose.
		back()

	elseif s.type == "patterns" then
		if item.kind == "pattern" then
			push({ type = "pattern", index = item.index, cursor = 1 })
		elseif item.kind == "new" then
			push({ type = "naming", cursor = 1, crumb = "New", purpose = "new" })
		elseif item.kind == "import" then
			push({ type = "naming", cursor = 1, crumb = "Add", purpose = "import" })
		elseif item.kind == "export" then
			push({ type = "transfer", cursor = 1, crumb = "Export",
				purpose = "export" })
		elseif item.kind == "import_file" then
			push({ type = "transfer", cursor = 1, crumb = "Import",
				purpose = "import" })
		elseif item.kind == "back" then
			back()
		end

	elseif s.type == "pattern" then
		if item.kind == "edit" then
			local it = pattern_items()[s.index]
			if it ~= nil then
				draft = copy({ version = 1, steps = it.steps or {} })
				if type(draft.steps) ~= "table" or #draft.steps == 0 then
					draft.steps = { new_step() }
				end
				push({ type = "root", cursor = 1 })
			end
		elseif item.kind == "rename" then
			local it = pattern_items()[s.index]
			push({ type = "naming", cursor = 1, crumb = "Rename",
				purpose = "rename", index = s.index,
				current = (it ~= nil) and it.name or "" })
		elseif item.kind == "use" then
			local it = pattern_items()[s.index]
			if it ~= nil then
				it.use = not (it.use == true)
				mark_training_settings_dirty()
			end
		elseif item.kind == "copy" then
			local items = pattern_items()
			local it = items[s.index]
			if it ~= nil then
				-- Next to the original, not at the end: a copy is made to be
				-- changed, and hunting for it down a list of thirty is work
				-- the player did not ask for. Duplicate names are allowed, so
				-- the name goes across untouched.
				table.insert(items, s.index + 1, copy(it))
				mark_training_settings_dirty()
				-- BACK TO THE LIST, ON THE NEW ROW. Nothing on this screen
				-- changes when a copy is made, so staying here would look
				-- exactly like nothing having happened.
				table.remove(stack)
				local list = top()
				if list ~= nil then list.cursor = s.index + 1 end
			end
		elseif item.kind == "move" then
			push({ type = "pattern_order", index = s.index, cursor = 1,
				crumb = "Move" })
		elseif item.kind == "delete" then
			push({ type = "pattern_delete", index = s.index, cursor = 1,
				crumb = "Delete" })
		elseif item.kind == "export_one" then
			-- The index rides the state, the same way rename/move/delete
			-- carry it: the export happens when the dialog has been closed,
			-- and asks "which row" not "which table".
			push({ type = "transfer", cursor = 1, crumb = "Export",
				purpose = "export_one", index = s.index })
		elseif item.kind == "back" then
			back()
		end

	elseif s.type == "pattern_delete" then
		if item.kind == "yes" then
			table.remove(pattern_items(), s.index)
			mark_training_settings_dirty()
			-- The confirm AND the item screen: the item it belonged to is
			-- gone, so there is nothing to come back to.
			table.remove(stack)
			table.remove(stack)
		else
			back()
		end

	elseif s.type == "root" then
		if item.kind == "step" then
			push({ type = "detail", index = item.index, cursor = 1 })
		elseif item.kind == "add" then
			table.insert(draft.steps, added_step())
			push({ type = "detail", index = #draft.steps, cursor = 1 })
		elseif item.kind == "save" then
			save_draft()
			leave_root()
		elseif item.kind == "clear" then
			push({ type = "clear", cursor = 1, crumb = "Clear All" })
		elseif item.kind == "cancel" then
			-- The row says "Without Saving", so it does not need to ask when
			-- there is nothing to drop.
			if dirty() then
				push({ type = (pattern_edit() ~= nil) and "pattern_close" or "close",
					cursor = 1, crumb = "Close" })
			else
				leave_root()
			end
		end

	elseif s.type == "detail" then
		local i = s.index
		if item.kind == "action" then
			push(groups_screen(i))
		elseif item.kind == "wait" then
			local _st = draft.steps[i]
			local _cursor = wait_choice_index(_st, i, draft.steps[i - 1])
			push({ type = "wait", index = i, cursor = _cursor, crumb = "Wait" })
		elseif item.kind == "lever" then
			push(pick_screen(parts_list(draft.steps[i]) or CUSTOM_LEVERS, "lever", i))
		elseif item.kind == "button" then
			-- A special offers only the strengths its command takes.
			push(pick_screen(special_button_row(draft.steps[i])
			                 or buttons_for(cid_num()), "button", i))
		elseif item.kind == "hold" then
			-- Two values, so a screen of its own would be a screen to say Yes on.
			-- Right or LP flips it in place, which is what those do everywhere
			-- else here: the thing the row is for.
			draft.steps[i].hold = not draft.steps[i].hold
		elseif item.kind == "order" then
			push({ type = "order", index = i, cursor = 1, crumb = "Move Step" })
		elseif item.kind == "delete" then
			push({ type = "confirm", index = i, cursor = 1, crumb = "Remove" })
		elseif item.kind == "back" then
			back()
		end

	elseif s.type == "groups" then
		local st = draft.steps[s.index]
		if item.group.action then
			st.action = item.group.action.id
			back()
		elseif item.group.list then
			push(actions_screen(item.group, s.index))
		else
			-- Assembled from parts. Keep what the step already had when the
			-- new group can express it - Custom offers a superset of both
			-- other lists - and fall back to that list's first entry when it
			-- cannot, so a Dash never sits on "Neutral".
			st.action = item.group.assemble
			local list = parts_list(st)
			local keep = false
			for _, e in ipairs(list) do
				if e[2] == st.lever then keep = true break end
			end
			if not keep then st.lever = list[1][2] end
			st.button = st.button or "LP"
			if not can_hold(st) then st.hold = nil end
			back()
		end

	elseif s.type == "actions" then
		local st = draft.steps[s.index]
		st.action = item.action.id
		-- A motion special needs a strength, and the step may arrive with one
		-- the move does not take (or none at all). The first the command offers
		-- is the same fallback the Dash group uses when a lever cannot carry
		-- over.
		local spb = special_buttons(st)
		if spb ~= nil then
			local keep = false
			for _, e in ipairs(spb) do
				if e[2] == st.button then keep = true break end
			end
			if not keep then st.button = spb[1][2] end
		-- A sequence special carries its own buttons, so a strength left over
		-- from the move chosen before it would sit in the saved file with no row
		-- to show it - the same reason a Hold is dropped just below.
		elseif special_of(st) ~= nil then
			st.button = nil
		end
		-- Stand Neutral has nothing to hold, so a Hold left over from Stand
		-- Forward would sit in the saved file with no row to show it.
		if not can_hold(st) then st.hold = nil end
		table.remove(stack)
		back()

	elseif s.type == "wait" then
		if item.kind == "back" then
			back()
		elseif item.fixed then
			local st = draft.steps[s.index]
			st.timing = nil
			if s.index > 1 and (type(st.wait) ~= "number" or st.wait < 1) then st.wait = 1 end
			if s.index == 1 and (type(st.wait) ~= "number" or st.wait < 0) then st.wait = 0 end
			push({ type = "fixed_wait", index = s.index, cursor = 1, crumb = "Fixed Ticks" })
		else
			local st = draft.steps[s.index]
			st.wait = WAIT_AUTO
			st.timing = item.timing
			back()
		end

	elseif s.type == "fixed_wait" then
		if item.kind == "back" then back() end

	elseif s.type == "pick" then
		local st = draft.steps[s.index]
		st[s.field] = item.value
		-- A Hold on a step that no longer ends on a direction means nothing, and
		-- would sit in the saved file as a flag with no row to show it.
		if not can_hold(st) then st.hold = nil end
		back()

	elseif s.type == "confirm" then
		if item.kind == "yes" then
			table.remove(draft.steps, s.index)
			table.remove(stack)
			table.remove(stack)
		else
			back()
		end

	elseif s.type == "clear" then
		if item.kind == "yes" then
			-- One empty step, not none: the root screen and every list rule
			-- here assume a first step exists, and "no steps" is not a state
			-- the editor has. This is the same list M.open builds from nothing.
			draft.steps = { new_step() }
			back()
		else
			back()
		end

	elseif s.type == "pattern_close" then
		if item.kind == "save_back" then
			-- Saved BEFORE the stack is popped: save_draft finds which item
			-- the draft belongs to by reading the root frame underneath.
			save_draft()
			table.remove(stack)
			table.remove(stack)
			draft = nil
		elseif item.kind == "discard_back" then
			table.remove(stack)
			table.remove(stack)
			draft = nil
		else
			back()
		end

	elseif s.type == "close" then
		-- Cancel leaves the draft and the screen it was on exactly as they
		-- were: back() pops only this screen, so a close asked for three
		-- levels deep returns to the third level.
		if item.kind == "save_close" then
			save_draft()
			close()
			leave_menu()
		elseif item.kind == "discard_close" then
			close()
			leave_menu()
		else
			back()
		end
	end
end

local function pressed(name)
	local p1 = player_objects and player_objects[1]
	local p2 = player_objects and player_objects[2]
	if p1 and p1.input and p1.input.pressed and p1.input.pressed[name] then return true end
	if p2 and p2.input and p2.input.pressed and p2.input.pressed[name] then return true end
	return false
end

local function held(name)
	local p1 = player_objects and player_objects[1]
	local p2 = player_objects and player_objects[2]
	if p1 and p1.input and p1.input.down and p1.input.down[name] then return true end
	if p2 and p2.input and p2.input.down and p2.input.down[name] then return true end
	return false
end

-- The rate every row is walked at. One step per four frames once the hold has
-- been held long enough to count as one.
local REPEAT_RATE = 4
-- A step per frame. Only where a row is a plain count with a long way to go.
local REPEAT_RATE_FAST = 1

local function held_repeat_at(name, rate)
	local p1 = player_objects and player_objects[1]
	local p2 = player_objects and player_objects[2]
	if p1 and check_input_down_autofire(p1, name, rate) then return true end
	if p2 and check_input_down_autofire(p2, name, rate) then return true end
	return false
end

local function held_repeat(name)
	return held_repeat_at(name, REPEAT_RATE)
end

-- HOW LONG THE DIRECTION HAS BEEN DOWN, IN FRAMES.
--
-- The same clock the autofire helper reads to decide WHETHER a repeat happens
-- this frame, exposed so the root list can decide HOW FAR one goes.
--
-- ONLY FROM A PLAYER WHO IS ACTUALLY HOLDING IT.
--
-- state_time counts frames in the CURRENT state, up as well as down: a
-- direction nobody has touched has been in its state for the whole session and
-- its clock is in the tens of thousands. Taking the highest of the two players
-- without asking whether either was holding anything read P2's untouched Down
-- as an hours-long hold, so every list opened in top gear and one row at a time
-- did not exist (user, 2026-09-08).
local function held_time(name)
	local best = 0
	for _i = 1, 2 do
		local p = player_objects and player_objects[_i]
		local inp = p and p.input
		if inp and inp.down and inp.down[name] then
			local t = inp.state_time and inp.state_time[name]
			if type(t) == "number" and t > best then best = t end
		end
	end
	return best
end

-- THE ROOT LIST IS AS LONG AS THE SEQUENCE, AND A SEQUENCE CAN BE 4096 STEPS.
--
-- One row per four frames puts the far end four and a half minutes away, so a
-- list that long could be built but not walked (user, 2026-09-08). Held on, a
-- repeat covers more rows.
--
-- THE GEARS COME IN EARLY, AND A TAP IS WHAT AIMS.
--
-- These bands were pushed out to 120 / 200 / 260 once, because holding read as
-- page scrolling with no fine control. That was not the bands: held_time was
-- reading an untouched player's clock and every list opened in top gear (see
-- the note on state_time below). With that fixed the early speed was asked for
-- back (user, 2026-09-08).
--
-- So aiming is the TAP, which is one row and always has been, and the hold is
-- for travelling. The autofire helper sits still for 23 frames before it
-- repeats at all, so a hold short enough to be an aim never reaches a gear.
--
-- The top gear is the LIST's, not a number - count / 50 crosses any list in
-- about fifty repeats, so 4096 steps and 400 steps take about the same time to
-- get through.
--
-- Under a screenful there are no gears at all. A list that short is crossed
-- before the first band, so the only thing a gear could do there is take the
-- wrap away from a hold that was using it.
local function scroll_stride(name, count)
	if count < 32 then return 1 end
	local t = held_time(name)
	if t >= 100 then return math.max(16, math.floor(count / 50)) end
	if t >= 60 then return 8 end
	if t >= 30 then return 2 end
	return 1
end

function M.open(which)
	validate()
	trigger = which or "reversal"
	editor_character_id = tostring(cid_num())
	draft = copy(read_saved(trigger, editor_character_id)) or defaults()
	if type(draft.steps) ~= "table" or #draft.steps == 0 then draft.steps = { new_step() } end
	-- Sequences saved before attacks became direction + button hold ids like
	-- "n.MP" and "c.HP". The runner still understands those, but the editor no
	-- longer offers them, so a step would show its raw id and could not be
	-- edited. Converted on the way in; nothing is written back until Save.
	for _i, st in ipairs(draft.steps) do
		-- A zero wait after step one put the step on the same tick as the one
		-- before it, and the two went out as a single input. It is not offered
		-- any more, so a saved zero is raised here rather than shown on a row
		-- the stick cannot leave - Left from zero would find no branch, because
		-- one is the floor now.
		--
		-- Auto is WAIT_AUTO (negative), not zero, and is left alone.
		if _i > 1 and st.wait == 0 then st.wait = 1 end
		-- LATE CHAIN IS GONE. A step saved with it never fired - the mode was
		-- asking for something that could not happen - so the list it sat in
		-- stopped there. Chain is the same connection asked for at the start of
		-- the window instead of the end, which is the nearest thing that runs,
		-- and it makes those lists work rather than leaving a row the stick
		-- cannot even walk off.
		if st.timing == "late_chain" then st.timing = TIMING_CHAIN end
		local id = tostring(st.action or "")
		local head, btn = id:match("^([nc])%.(.+)$")
		if head ~= nil then
			st.action = ATTACK_ID
			st.lever = (head == "c") and "down" or "none"
			st.button = btn
		end
		-- A dash briefly carried its own button. It does not any more, and a
		-- saved one would show a Button row that no longer exists.
		if id == "dash" then
			st.action = DASH_BACK[st.lever] or "dash.f"
			st.lever = nil
			st.button = nil
		end
	end
	stack = { { type = "root", cursor = 1 } }
	active = true
end

-- THE LIBRARY'S OWN DOOR. A separate parent, so nothing about the Action Steps
-- row changes for anyone not using this.
function M.open_patterns(which)
	validate()
	trigger = which or "reversal"
	editor_character_id = tostring(cid_num())
	draft = nil
	pattern_row(trigger, editor_character_id)
	stack = { { type = "patterns", cursor = 1 } }
	active = true
end

function M.abort(reason)
	close_requested = false
	close()
end

function M.is_active() return active end

function M.registerBefore()
	if not active then return end
	if editor_character_id ~= nil and tostring(cid_num()) ~= editor_character_id then
		M.abort("character_changed")
		return
	end
	-- THE BOX OPENS ONE FRAME AFTER ITS SCREEN WAS DRAWN.
	--
	-- io.popen is synchronous and runs on this thread, so the emulator stops
	-- dead until the box is closed. Opening it on the frame that pushed the
	-- screen would freeze the picture on the PREVIOUS screen, leaving no clue
	-- that a keyboard is now wanted. guiRegister sets shown, and this runs
	-- before the next frame, so by then the notice is up.
	local naming = top()
	if naming ~= nil and naming.type == "naming" then
		if not naming.shown then return end
		local got = M.prompt_name(naming.current)
		table.remove(stack)
		-- Cancel, an error, and a name that was nothing but unprintable
		-- characters all mean the same thing here: leave it alone.
		if got ~= nil and got ~= "" then apply_name(naming, got) end
		return
	end

	-- THE FILE WINDOW OPENS ONE FRAME AFTER ITS SCREEN WAS DRAWN, for exactly
	-- the reason the naming box does. The answer replaces the notice on the
	-- same screen, so the player has not been moved anywhere by it.
	local xfer = top()
	if xfer ~= nil and xfer.type == "transfer" and xfer.result == nil then
		if not xfer.shown then return end
		if xfer.purpose == "export" then
			xfer.result = export_now()
		elseif xfer.purpose == "export_one" then
			xfer.result = export_one_now(xfer.index)
		else
			xfer.result = import_now()
		end
		xfer.shown = false
		return
	end

	-- The flag request_close raised, turned into a screen here where every
	-- other screen is made. Pushed before the frame gate below so the press
	-- that asked for it is not also read as a press ON it - the armed gate
	-- takes care of the rest.
	if close_requested then
		close_requested = false
		-- Nothing to lose, nothing to ask. The menu button then does what it
		-- says it does.
		if not dirty() then
			close()
			leave_menu()
			return
		end
		local _t = top()
		if _t == nil or _t.type ~= "close" then
			push({ type = "close", cursor = 1, crumb = "Close" })
		end
	end
	if emu.framecount() == last_input_frame then return end
	last_input_frame = emu.framecount()

	local s = top()
	if s == nil then close() return end
	local items = build(s)
	clamp(s, items)

	-- THE PRESS THAT OPENED A SCREEN IS NOT A PRESS ON IT.
	--
	-- Right is what walks in, and it auto-repeats once held long enough, so
	-- arriving with it still down acts on the new screen straight away - three
	-- levels deep in one hold, or a number climbing on its own. Every screen
	-- waits for Right to be released once before it listens. Tapping through
	-- levels is unaffected: a tap is a release.
	if not s.armed then
		if held("right") or held("LP") then return end
		s.armed = true
	end

	if s.type == "wait" then
		local items = build(s)
		if held_repeat("down") then
			s.cursor = math.min(#items, s.cursor + 1)
		elseif held_repeat("up") then
			s.cursor = math.max(1, s.cursor - 1)
		elseif pressed("left") then
			back()
		elseif pressed("right") or pressed("LP") then
			enter()
		end
		return
	end

	if s.type == "fixed_wait" then
		if held_repeat("down") then
			s.cursor = 2
		elseif held_repeat("up") then
			s.cursor = 1
		elseif s.cursor == 2 then
			if pressed("left") or pressed("LP") or pressed("right") then back() end
		else
			local st = draft.steps[s.index]
			local floor = (s.index > 1) and 1 or 0
			local top = (s.index == 1) and WAIT_MAX_FIRST or WAIT_MAX
			local v = tonumber(st.wait) or floor
			if held_repeat_at("right", REPEAT_RATE_FAST) then
				v = math.min(top, v + 1)
			elseif held_repeat_at("left", REPEAT_RATE_FAST) then
				v = math.max(floor, v - 1)
			elseif pressed("MP") then
				v = floor
			end
			st.wait = v
			st.timing = nil
		end
		return
	end

	if s.type == "pattern_order" then
		-- Every key means what it means on Move Step, one screen over.
		if held_repeat("down") then
			s.cursor = 2
		elseif held_repeat("up") then
			s.cursor = 1
		elseif s.cursor == 2 then
			if pressed("left") or pressed("LP") or pressed("right") then back() end
		else
			local items = pattern_items()
			local i = s.index
			if held_repeat("left") and i > 1 then
				items[i], items[i - 1] = items[i - 1], items[i]
				s.index = i - 1
				stack[#stack - 1].index = s.index
				mark_training_settings_dirty()
			elseif held_repeat("right") and i < #items then
				items[i], items[i + 1] = items[i + 1], items[i]
				s.index = i + 1
				stack[#stack - 1].index = s.index
				mark_training_settings_dirty()
			end
		end
		return
	end

	if s.type == "order" then
		-- Up/Down picks the row and Left/Right moves the step, which is what
		-- the Wait screen above does with its number. The detail frame
		-- underneath is renumbered with it, so its heading follows.
		if held_repeat("down") then
			s.cursor = 2
		elseif held_repeat("up") then
			s.cursor = 1
		elseif s.cursor == 2 then
			if pressed("left") or pressed("LP") or pressed("right") then back() end
		else
			local i = s.index
			if held_repeat("left") and i > 1 then
				draft.steps[i], draft.steps[i - 1] = draft.steps[i - 1], draft.steps[i]
				s.index = i - 1
				stack[#stack - 1].index = s.index
			elseif held_repeat("right") and i < #draft.steps then
				draft.steps[i], draft.steps[i + 1] = draft.steps[i + 1], draft.steps[i]
				s.index = i + 1
				stack[#stack - 1].index = s.index
			end
		end
		return
	end

	-- MP TICKS THE ROW UNDER THE CURSOR.
	--
	-- A SHORTCUT AND NOTHING MORE. The same switch is on the item's own screen,
	-- reachable with the lever and LP like everything else here - which is the
	-- rule, and the reason the ported implementation's MP-only Random was wrong.
	-- Ticking is the one thing done over and over, though: choosing which four
	-- of thirty to use is what the list is FOR, and a trip in and back out for
	-- each of them is the trip worth saving (design_action_pattern_library.md).
	if s.type == "patterns" and pressed("MP") then
		local row = items[s.cursor]
		if row ~= nil and row.kind == "pattern" then
			local it = pattern_items()[row.index]
			if it ~= nil then
				it.use = not (it.use == true)
				mark_training_settings_dirty()
			end
		end
		return
	end

	-- Only the root list runs. Every other screen here is a handful of rows
	-- long, and a gear it can never reach is a gear that is only in the way.
	local _fast = (s.type == "root") and #items or 0
	if held_repeat("down") then
		local _n = (_fast > 0) and scroll_stride("down", _fast) or 1
		s.cursor = s.cursor + _n
		-- A run stops at the end instead of coming out at the other one. The
		-- wrap is how a single press reaches Save from row one and that stays,
		-- but arriving there at sixteen rows a frame is not being taken there.
		if _n > 1 and s.cursor > #items then s.cursor = #items else clamp(s, items) end
	elseif held_repeat("up") then
		local _n = (_fast > 0) and scroll_stride("up", _fast) or 1
		s.cursor = s.cursor - _n
		if _n > 1 and s.cursor < 1 then s.cursor = 1 else clamp(s, items) end
	elseif pressed("left") then
		-- LEFT OFF THE ROOT IS A WAY OUT TOO.
		--
		-- It reached close() directly and took the edit with it. Deeper screens
		-- are unaffected: back() there only pops one level.
		--
		-- ASKED ON THE ROOT, NOT ON stack[1]. A library item's steps sit on a
		-- root frame three deep, and testing the depth instead of the screen
		-- let Left drop an edited pattern without a word.
		if s.type == "root" and dirty() then
			if pattern_edit() ~= nil then
				push({ type = "pattern_close", cursor = 1, crumb = "Close" })
			else
				push({ type = "close", cursor = 1, crumb = "Close" })
			end
		else
			back()
		end
	elseif pressed("right") or pressed("LP") then
		enter()
	end
end

-- THE HEADING IS WHERE YOU ARE, NOT WHAT YOU ARE BEING ASKED.
--
-- Half of these screens used to be headed by a question - WHAT SHOULD IT DO?,
-- WHEN DOES IT START? - and the other half by a location. That seam is felt
-- before it can be named, and the questions cost more than the inconsistency: a
-- screen that asks "when does it start" makes its row answer the question, and
-- that is how the Wait row briefly became Start.
--
-- So a heading is the trail of rows pressed to reach it, and a crumb is exactly
-- the label of the row that opened the screen - which is why the row and its
-- screen can never drift apart again. It is also the rule the rest of this menu
-- already follows: see make_popup in menu.lua, whose title is the parent row's
-- name.
--
--   REVERSAL ACTION STEPS: Bulleta  >  STEP 5  >  Action  >  Crouch
--
-- Detail's crumb is computed rather than stored, because Order renumbers the
-- step underneath it and the heading has to follow while the stick is moving.
-- THE PANEL IS 360px AND THE GLYPHS ARE 4px, WITH ROWS STARTING AT x=33.
-- Eighty-one characters, measured (design_action_pattern_library.md).
local TITLE_COLS = 81

local function crumb_of(f)
	if f.type == "detail" then return "STEP " .. tostring(f.index) end
	if f.type == "pattern" then return string.format("%02d", f.index) end
	return f.crumb
end

-- The trigger leads, so Counter and Guard need no new string here when they
-- arrive. Exposed so a test can read a heading without drawing a screen.
-- THE HEADING NAMES WHAT IS ON SCREEN, NOT HOW THE PLAYER GOT THERE.
--
-- Crumbs are counted from the editor's own root when there is one above the
-- library, so opening Edit switches to "... ACTION STEPS: Name" instead of
-- growing a trail. Measured: the full trail reaches 105 characters = 453px and
-- runs off a 360px panel (design_action_pattern_library.md).
function M.title()
	-- Which frame is the library item, and where the editor's own heading
	-- starts. A root above the item means the steps are open, and then the
	-- heading is the steps editor's - the trail is replaced, not grown.
	local pat_at, base, head = nil, 1, " ACTION STEPS: "
	if stack[1] ~= nil and stack[1].type == "patterns" then
		head = " ACTION PATTERNS: "
		for i = 1, #stack do
			if stack[i].type == "pattern" then pat_at = i end
			if stack[i].type == "root" then base, head = i, " ACTION STEPS: " end
		end
	end
	local t = string.upper(trigger) .. head .. cid_name()
	local tail = ""
	for i = math.max(base, (pat_at or 0) + 1), #stack do
		local c = crumb_of(stack[i])
		if c ~= nil then tail = tail .. "  >  " .. c end
	end
	if pat_at ~= nil then
		t = t .. "  >  " .. string.format("%02d", stack[pat_at].index)
		-- THE NAME, WHILE THERE IS ROOM FOR IT.
		--
		-- Without it the steps editor said nothing about WHICH pattern was open
		-- (user, 2026-09-20). It goes in FRONT of the crumbs and gives way to
		-- them: they say where you are now and must not be cut, while the
		-- number identifies the pattern on its own whatever happens to the name.
		local it = pattern_items()[stack[pat_at].index]
		local nm = it and it.name or nil
		if nm ~= nil and nm ~= "" then
			local room = TITLE_COLS - #t - #tail - 2
			if room > 0 then
				t = t .. "  " .. ((#nm > room) and nm:sub(1, room) or nm)
			end
		end
	end
	return t .. tail
end

function M.guiRegister()
	if not active then return end
	local s = top()
	if s == nil then return end
	local items = build(s)
	clamp(s, items)

	-- Same frame as the menu panel, which this replaces in place - see the
	-- note on _menu_box_bottom in menu.lua. A different bottom edge here
	-- would make the frame jump on the way in and out.
	gui.box(23, 15, 360, 207, panel_fill_color, panel_outline_color)

	gui.text(33, 21, M.title(), text_selected_color, text_default_border_color)

	-- THE DOORS LINE UP IN A COLUMN.
	--
	-- Measured across the WHOLE list rather than the visible dozen, so the
	-- column does not move under the cursor while scrolling.
	local door_col = 0
	for _, it in ipairs(items) do
		if it.child and #it.label > door_col then door_col = #it.label end
	end
	door_col = door_col + 2

	local first = 1
	if #items > 12 then first = math.max(1, math.min(s.cursor - 5, #items - 11)) end
	local y = 37
	local shown = 0
	local i = first
	while shown < 12 and items[i] ~= nil do
		local item = items[i]
		if item.gap_before then y = y + 6 end
		local selected = (i == s.cursor)
		-- ONE MARK FOR THE CURSOR, ONE FOR "THIS OPENS SOMETHING".
		--
		-- A selected child row used to read "< label >   >", which is two marks
		-- for the cursor and a third for the door, and the two kinds of > were
		-- impossible to tell apart.
		--
		-- The brackets came from menu.lua's rows, where they mean something:
		-- Left and Right CHANGE the value inside them. In a list they do not -
		-- Left goes back and Right goes in - so the brackets were borrowed for a
		-- place with nothing to say. They are kept on the two screens where the
		-- stick really does move a number, Wait and Move Step.
		-- A PLAIN ROW IS A MESSAGE, NOT A CHOICE. No cursor on it: a cursor
		-- says the stick can do something here, and on the naming screen it
		-- cannot - the keyboard is what is wanted.
		local mark = item.plain and "   " or (selected and ">  " or "   ")
		gui.text(33, y, mark .. item.label
			.. (item.child and (string.rep(" ", door_col - #item.label) .. ">") or ""),
			(selected and not item.plain) and text_selected_color or text_default_color,
			text_default_border_color)
		y = y + 10
		shown = shown + 1
		i = i + 1
	end

	local cur = items[s.cursor]
	local note = cur and HELP[cur.kind or ""] or nil
	if note then gui.text(33, 168, note, text_disabled_color, text_default_border_color) end

	local help = "Up/Down: Select   Right or LP: Enter   Left: Back"
	if s.type == "patterns" and cur ~= nil and cur.kind == "pattern" then
		-- Named only where it does something. On New or Back it would be a
		-- button that does nothing, which is worse than no legend at all.
		help = "Up/Down: Select   Right or LP: Open   MP: Tick   Left: Back"
	elseif s.type == "naming" then
		help = "USE THE KEYBOARD in the other window"
	elseif s.type == "transfer" then
		help = (s.result ~= nil) and "Left or LP: Back"
			or "Use the file window that has opened"
	elseif s.type == "wait" then
		help = "Up/Down: Select   Right or LP: Apply   Left: Back"
	elseif s.type == "fixed_wait" then
		if s.cursor == 2 then help = "Left, Right or LP: Back"
		else help = "Left: fewer   Right: more   MP: Reset" end
	elseif s.type == "order" or s.type == "pattern_order" then
		if s.cursor == 2 then help = "Left, Right or LP: Back"
		else help = "Left: earlier   Right: later" end
	elseif cur and cur.kind == "hold" then
		-- Enter is wrong for a row with two values and no screen behind it.
		help = "Up/Down: Select   Right or LP: Toggle   Left: Back"
	end
	gui.text(33, 181, help, text_disabled_color, text_default_border_color)

	-- ON THE PICTURE NOW. registerBefore waits for this before it opens
	-- anything that blocks, so the notice is up before the emulator stops.
	s.shown = true
end

-- THE LIBRARY'S ROW ON THE MENU, BESIDE THE ONE ACTION STEPS HAS.
--
-- A separate parent, so nothing about the Action Steps row changes for anyone
-- not using this (design_action_pattern_library.md). What it says is what the
-- library HOLDS - which of them runs is the Guard Action Type's question, the
-- same division the row below draws.
function M.patterns_parent_item(which, label)
	return {
		name = label,
		draw = function(self, x, y, selected)
			local row = pattern_store()[which]
			local list = row and row[tostring(cid_num())]
			local items = (type(list) == "table" and type(list.items) == "table")
				and list.items or {}
			local on = 0
			for _, it in ipairs(items) do if it.use == true then on = on + 1 end end
			local state
			if #items == 0 then
				state = "Empty"
			else
				state = #items .. " saved, " .. on .. " ticked"
			end
			gui.text(x, y, (selected and "< " or "") .. self.name .. " : "
				.. cid_name() .. " : " .. state .. "  >",
				selected and text_selected_color or text_default_color,
				text_default_border_color)
		end,
		right = function() M.open_patterns(which) end,
		validate = function() M.open_patterns(which) end,
		left = function() end,
		legend = function() return "Right or LP: Open" end,
		description = function()
			return "Named Action Steps lists, saved so they can be picked again."
				.. "\nTick the ones to use: one ticked runs that one, several"
				.. " ticked pick between them."
				.. "\nNothing here is lost when you edit the Action Steps list below."
		end,
	}
end

function M.parent_item(which, label)
	return {
		name = label,
		draw = function(self, x, y, selected)
			local seq = current(which)
			local n = (type(seq) == "table" and type(seq.steps) == "table") and #seq.steps or 0
			-- What the list HOLDS, not whether it runs. Guard Action Type is
			-- what runs it, and saying "Off" here while that was set to
			-- Reversal - Sequence would be the second switch this deliberately
			-- does not have.
			-- Named, because the list belongs to this dummy and switching
			-- character shows a different one.
			local state = cid_name() .. " : "
				.. ((n > 0) and (n .. " step" .. ((n == 1) and "" or "s")) or "Empty")
			gui.text(x, y, (selected and "< " or "") .. self.name .. " : " .. state .. "  >",
				selected and text_selected_color or text_default_color, text_default_border_color)
		end,
		right = function() M.open(which) end,
		validate = function() M.open(which) end,
		left = function() end,
		legend = function() return "Right or LP: Edit" end,
		description = function()
			return "A list of actions the dummy runs in order when it reverses.\nEach step is one action and one answer to when it starts.\nNothing is saved until you Save. Set Guard Action Type to\nReversal - Sequence to make the dummy run it."
		end,
	}
end

return M
