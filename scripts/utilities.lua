local json              = require './scripts/dkjson'

function swap_inputs(keys)
	newKeys = {}

	p1_pattern = "^P1"
	for k, v in pairs(keys) do
		if k:find(p1_pattern) ~= nil then
			old_k = k
			swapped_k = k:gsub("1","2")
			-- print("after", old_k, swapped_k)
			newKeys[swapped_k] = keys[old_k] 
		end
	end
	p1_pattern = "^P2"
	for k, v in pairs(keys) do
		if k:find(p1_pattern) ~= nil then
			old_k = k
			swapped_k = k:gsub("2","1")
			-- print("after", old_k, swapped_k)
			newKeys[swapped_k] = keys[old_k] 
		end
	end
	return newKeys
end


function do_tables_match (o1, o2, ignore_mt)
    if o1 == o2 then return true end
    local o1Type = type(o1)
    local o2Type = type(o2)
    if o1Type ~= o2Type then return false end
    if o1Type ~= 'table' then return false end

    if not ignore_mt then
        local mt1 = getmetatable(o1)
        if mt1 and mt1.__eq then
            --compare using built in method
            return o1 == o2
        end
    end

    local keySet = {}

    for key1, value1 in pairs(o1) do
        local value2 = o2[key1]
        if value2 == nil or do_tables_match(value1, value2, ignore_mt) == false then
            return false
        end
        keySet[key1] = true
    end

    for key2, _ in pairs(o2) do
        if not keySet[key2] then return false end
    end
    return true
end

function to_hex(num)
    local charset = {"0","1","2","3","4","5","6","7","8","9","a","b","c","d","e","f"}
    local tmp = {}
    repeat
        table.insert(tmp,1,charset[num%16+1])
        num = math.floor(num/16)
    until num==0
    return table.concat(tmp)
end
-- History
function get_text_width(_text)
	if #_text == 0 then
	  return 0
	end
  
	return #_text * 4
  end
function string_hash(_str)
	if #_str == 0 then
		return 0
  end

  local _DJB2_INIT = 5381;
	local _hash = _DJB2_INIT
  for _i = 1, #_str do
    local _c = _str.byte(_i)
    _hash = bit.lshift(_hash, 5) + _hash + _c
  end
	return _hash
end
function string_to_color(_str)
	local _HRange = { 0.0, 360.0 }
	  local _SRange = { 0.8, 1.0 }
	  local _LRange = { 0.7, 1.0 }
  
	  local _HAmplitude = _HRange[2] - _HRange[1];
	  local _SAmplitude = _SRange[2] - _SRange[1];
	  local _LAmplitude = _LRange[2] - _LRange[1];
  
	local _hash = string_hash(_str)
  
	local _HI = bit.rshift(bit.band(_hash, 0xFF000000), 24)
	local _SI = bit.rshift(bit.band(_hash, 0x00FF0000), 16)
	  local _LI = bit.rshift(bit.band(_hash, 0x0000FF00), 8)
	  local _base = bit.lshift(1, 8)
  
	  local _H = _HRange[1] + (_HI / _base) * _HAmplitude;
	  local _S = _SRange[1] + (_SI / _base) * _SAmplitude;
	  local _L = _LRange[1] + (_LI / _base) * _LAmplitude;
  
	  local _HDiv60 = _H / 60.0
	  local _HDiv60_Floor = math.floor(_HDiv60);
	  local _HDiv60_Fraction = _HDiv60 - _HDiv60_Floor;
  
	  local _RGBValues = {
		  _L,
		  _L * (1.0 - _S),
		  _L * (1.0 - (_HDiv60_Fraction * _S)),
		  _L * (1.0 - ((1.0 - _HDiv60_Fraction) * _S))
	  }
  
	  local _RGBSwizzle = {
		  {1, 4, 2},
		  {3, 1, 2},
		  {2, 1, 4},
		  {2, 3, 1},
		  {4, 2, 1},
		  {1, 2, 3},
	  }
	  local _SwizzleIndex = (_HDiv60_Floor % 6) + 1
	local _R = _RGBValues[_RGBSwizzle[_SwizzleIndex][1]]
	local _G = _RGBValues[_RGBSwizzle[_SwizzleIndex][2]]
	local _B = _RGBValues[_RGBSwizzle[_SwizzleIndex][3]]
  
	--print(string.format("H:%.1f, S:%.1f, L:%.1f | R:%.1f, G:%.1f, B:%.1f", _H, _S, _L, _R, _G, _B))
  
	local _color = bit.lshift(math.floor(_R * 255), 24) + bit.lshift(math.floor(_G * 255), 16) + bit.lshift(math.floor(_B * 255), 8) + 0xFF
	return _color
  end
local last_frame_data = nil
function printRamAddresses(start_addr, end_addr)
	local current_frame_data = {}
	for i = start_addr, end_addr, 1 do 
		current_frame_data[to_hex(i)] = memory.readbyte(i)
	end
	diffs = {}
	if last_frame_data ~= nil then 
		for k,v in pairs(current_frame_data) do
			if last_frame_data[k] ~= current_frame_data[k] then 
				diffs[k] = v
			end
		end
		print("\t",last_frame_data["frame"], "\t", emu.framecount())
		
	end
	for k,v in pairs(diffs) do
		print(k,"\t", v,"\t", last_frame_data[k], "\n")
	end

	last_frame_data = current_frame_data
	last_frame_data["frame"] = emu.framecount()
end
function read_object_from_json_file(_file_path)
	local _f = io.open(_file_path, "r")
	if _f == nil then
	  return nil, "the file could not be opened"
	end

	local _object
	local _pos, _err
	-- THE ERROR IS IN _err, NOT err. This used to test `if (err)` - a global
	-- that is always nil - so a missing file AND a broken file both came back
	-- as silent nil, and the caller could only say "that is not a pattern
	-- file" with no way to tell which. The second return value carries the
	-- reason; every existing caller reads only the first, so this stays
	-- compatible with all of them.
	_object, _pos, _err = json.decode(_f:read("*all"))
	_f:close()

	if _object == nil then
	  print(string.format("Failed to read json file \"%s\" : %s",
		_file_path, tostring(_err or "no value")))
	  return nil, tostring(_err or "no value")
	end

	return _object
  end
  
  function write_object_to_json_file(_object, _file_path)
	local _f = io.open(_file_path, "w")
	if _f == nil then
	  return false
	end
  
	local _str = json.encode(_object, { indent = true })
	_f:write(_str)
	_f:close()
  
	return true
end
-- Do not write the JSON on every menu step.
--
-- save_training_data used to encode training_settings and hit the disk on
-- every left/right. The in-memory table is already the live settings
-- (globals.options IS training_settings), and registerBefore rebuilds
-- dummy from it every displayed frame, so the write was only for
-- persistence. On a low-spec machine that hitch is what "the button
-- change is slow" actually was.
--
-- Mark dirty on change; write once when the menu closes, or if the
-- script exits with unsaved edits. Do not reintroduce a write on
-- left/right - it will feel like the original bug.
training_settings_dirty = false

function mark_training_settings_dirty()
	training_settings_dirty = true
end

function save_training_data()
	-- backup_recordings()
	if not write_object_to_json_file(training_settings, training_settings_file) then
		print(string.format("Error: Failed to save training settings to \"%s\"", training_settings_file))
	else
		training_settings_dirty = false
	end

	if globals and globals.dummy and globals.dummy.refresh_dummy then
		globals.dummy = globals.dummy.refresh_dummy()
	end
end

function save_training_data_if_dirty()
	if training_settings_dirty then
		save_training_data()
	end
end
function load_training_data()
	local _training_settings = read_object_from_json_file(training_settings_file)
	if _training_settings == nil then
		_training_settings = {}
	end
	-- update old versions data
	-- if _training_settings.recordings then
	--   for _key, _value in pairs(_training_settings.recordings) do
	-- 	for _i, _slot in ipairs(_value) do
	-- 	  if _value[_i].inputs == nil then
	-- 		_value[_i] = make_recording_slot()
	-- 	  else
	-- 		_slot.delay = _slot.delay or 0
	-- 		_slot.random_deviation = _slot.random_deviation or 0
	-- 	  end
	-- 	end
	--   end
	-- end
	for _key, _value in pairs(_training_settings) do
		training_settings[_key] = _value
	end

	-- THE VERSION THE FILE REPORTED, NOT THE ONE IN FRONT OF US.
	--
	-- The defaults table already carries the current version, and the merge
	-- above only overwrites keys the file actually has. A file written before
	-- settings_version existed - anything from v11.3.x - therefore reads back
	-- as current and skips every migration it needs, silently shifting the
	-- saved counter motion and dropping the saved loop interval. Read it from
	-- the raw file table instead, where a missing key means old.
	local _file_version = tonumber(_training_settings.settings_version) or 1

	-- COUNTER MOTION INDEX MIGRATION (v11.4).
	--
	-- counter_attack_stick is stored as an INDEX into menu.lua's
	-- counter_attack_stick list, and the three super jumps moved into it just
	-- after Back Dash Cancel. Everything from Character Specific onwards
	-- shifted by three, so a saved setting has to be remapped or it comes
	-- back as the entry next to the one that was chosen.
	--
	--   19..22  Character Specific / Forward / Back / Down  -> +3
	--   23..25  the super jumps, briefly parked at the end  -> -4
	--
	-- Keyed on settings_version so it runs exactly once. Values 1..18 are
	-- untouched: nothing before Back Dash Cancel moved.
	if _file_version < 2 then
		local _s = training_settings.counter_attack_stick
		if type(_s) == "number" then
			if _s >= 23 and _s <= 25 then
				training_settings.counter_attack_stick = _s - 4
			elseif _s >= 19 and _s <= 22 then
				training_settings.counter_attack_stick = _s + 3
			end
		end
		training_settings.settings_version = 2
	end

	-- LOOP INTERVAL MIGRATION. The former single interval happened before the
	-- next playback, following recovery. Preserve that value as After; Before
	-- is new and starts at zero. Read the raw file table because the defaults
	-- already contain both new keys by the time this migration runs.
	if _file_version < 3 then
		local _old = _training_settings.loop_interval_frames
		if type(_old) == "number" then
			training_settings.loop_interval_before_frames = 0
			training_settings.loop_interval_after_frames = _old
		end
		training_settings.loop_interval_frames = nil
		training_settings.settings_version = 3
	end

	-- TECH THROWS BECAME A RATE (v11.5).
	--
	-- It was a checkbox and is now an index into menu.lua's
	-- p2_throw_tech_chance, the same five the other two rate rows on the Player
	-- tab use. A saved boolean would reach list_menu_item, where left() does
	-- arithmetic on it and the row throws.
	--
	--   true  -> 5, "100%", which is what the checkbox did when it was on
	--   false -> 1, "None"
	if _file_version < 4 then
		local _t = training_settings.p2_throw_tech
		if type(_t) == "boolean" then
			training_settings.p2_throw_tech = _t and 5 or 1
		end
		training_settings.settings_version = 4
	end
	-- ACTION STEPS LOOP WAIT ZERO REMOVAL (v11.5 beta).
	--
	-- A loop boundary is either Auto (After), stored as -1, or at least one
	-- game tick. Zero allowed the last step and the next lap to compete on the
	-- same tick and was never an intended user setting. Preserve old files by
	-- moving zero to Auto rather than silently changing it to one tick.
	if _file_version < 5 then
		if training_settings.action_steps_loop_wait == 0 then
			training_settings.action_steps_loop_wait = -1
		end
		training_settings.settings_version = 5
	end
	-- restore_recordings()
end
function disable_taunts()
		-- Set remaining taunts to 0 for better start button behavior
		memory.writebyte(0xFF8400 + 0x179, 0)
		memory.writebyte(0xFF8800 + 0x179, 0)
end
local function mergeTables(first_table, second_table)
	if first_table == nil or second_table == nil then
		return {}
	end
	for k,v in pairs(second_table) do first_table[k] = v end
end

function lookForValue(start_addr, end_addr, player)
	for i = start_addr, end_addr, 1 do 
		val = memory.readbyte(i)
		-- if val == 12 then print("found 12", to_hex(i), val) end
		if val == 11 then print(player.."==== found 11", to_hex(i), val) end
	end
end
function to_hex(num)
	local charset = {"0","1","2","3","4","5","6","7","8","9","a","b","c","d","e","f"}
	local tmp = {}
	repeat
		table.insert(tmp,1,charset[num%16+1])
		num = math.floor(num/16)
	until num==0
	return table.concat(tmp)
end
function tablelength(T)
	local count = 0
	for _ in pairs(T) do count = count + 1 end
	return count
end
function round(num, numDecimalPlaces)
	local mult = 10^(numDecimalPlaces or 0)
	return math.floor(num * mult + 0.5) / mult
  end
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
    elseif char_id == 0x0B 	then return "Random Select"
    elseif char_id == 0x0C 	then return "Q-Bee"
    elseif char_id == 0x0D 	then return "Lei-Lei"
    elseif char_id == 0x0E 	then return "Lilith"
    elseif char_id == 0x0F 	then return "Jedah"
    elseif char_id == 0x12 	then return "Dark Gallon"
    elseif char_id == 0x18 	then return "Oboro" end
end
-- HAS THIS PLAYER CHOSEN A CHARACTER YET?
--
-- NOT FROM WHAT THE GAME WRITES, BECAUSE ALL OF IT CAN BE ZERO.
--
-- $3BD and $3E0 are the character id (0x020AC8), and BULLETA IS 0x00.
-- $3AE and its copy $3E1 are the number of the button the pick was confirmed
-- with - measured on the select screen, 2026-09-23: MP gave 1, LK gave 3, MK
-- gave 4, so the order is LP MP HP LK MK HK and LP GIVES 0.
--
-- Bulleta confirmed with LP therefore leaves every one of those four bytes
-- at zero. The character is chosen; there is simply nothing to read. That is
-- the whole of the bug where the arcade-stick mirror never handed control to
-- P2 - it needed Bulleta AND light punch, which is why it came and went
-- (user, 2026-09-23, isolated it to exactly that pair).
--
-- The byte range $380..$3FF was scanned frame by frame across four sessions
-- and nothing else moves on that confirm. $3BC and $3E3 stay zero throughout
-- (the disassembly makes them look like the answer; they are not).
--
-- SO WATCH THE CONFIRM ITSELF. On the select screen an attack button IS the
-- confirm, and $394 is the button half of the input pair ($395 is the lever,
-- $396/$397 the previous tick's). A press edge there means that player has
-- picked, whatever the id and whatever the button.
--
-- Only attack buttons count: $77 is the same mask the command code uses
-- (0x029FE8 takes $7700 of the word), so Start and Coin cannot latch it.
--
-- The latch is dropped whenever the screen is not select, so a new visit
-- starts clean. The two original reads are kept: they answer the moment the
-- id lands, which is a frame earlier, and nothing that works today may start
-- failing because of this.
local CSS_SCENE = 2
local css_picked = {}
local css_btn_was = {}

local function css_attack_bits(_b)
	-- No bitwise operators in Lua 5.1. $77 is LP MP HP . LK MK HK .
	for _, _bit in ipairs({ 0, 1, 2, 4, 5, 6 }) do
		if math.floor(_b / 2 ^ _bit) % 2 == 1 then return true end
	end
	return false
end

local function char_chosen(base_addr)
	local _written = memory.readbyte(base_addr + 0x3BD) ~= 0
		or memory.readbyte(base_addr + 0x3E1) ~= 0
	if memory.readbyte(0xFF8009) ~= CSS_SCENE then
		css_picked[base_addr] = nil
		css_btn_was[base_addr] = nil
		return _written
	end
	local _btn = css_attack_bits(memory.readbyte(base_addr + 0x394))
	if _btn and css_btn_was[base_addr] == false then
		css_picked[base_addr] = true
	end
	css_btn_was[base_addr] = _btn
	return _written or css_picked[base_addr] == true
end
utilitiesModule = {
	["char_chosen"] = char_chosen,
    ["save_training_data"]         = save_training_data,
    ["save_training_data_if_dirty"] = save_training_data_if_dirty,
    ["mark_training_settings_dirty"] = mark_training_settings_dirty,
    ["load_training_data"]         = load_training_data,
    ["do_tables_match"]            = do_tables_match,
    ["to_hex"]                     = to_hex,
	["round"]                      = round,
    ["read_object_from_json_file"] = read_object_from_json_file,
	["write_object_to_json_file"]  = write_object_to_json_file,
	["string_to_color"]			   =  string_to_color,
	["tablelength"]                = tablelength,
	["get_character"]			   = get_character,
	["registerStart"]              = function()
		return {
			printRamAddresses = printRamAddresses,
			disable_taunts = disable_taunts,
			char_chosen = char_chosen,
		}
	end
}
return utilitiesModule