local p1_inp_disp_x = 125
local p1_inp_disp_y = 28
local p2_inp_disp_x = 225
local p2_inp_disp_y = 28
require "gd"
img_1_dir = gd.createFromPng("images/1_dir.png"):gdStr()
img_2_dir = gd.createFromPng("images/2_dir.png"):gdStr()
img_3_dir = gd.createFromPng("images/3_dir.png"):gdStr()
img_4_dir = gd.createFromPng("images/4_dir.png"):gdStr()
img_5_dir = gd.createFromPng("images/5_dir.png"):gdStr()
img_6_dir = gd.createFromPng("images/6_dir.png"):gdStr()
img_7_dir = gd.createFromPng("images/7_dir.png"):gdStr()
img_8_dir = gd.createFromPng("images/8_dir.png"):gdStr()
img_9_dir = gd.createFromPng("images/9_dir.png"):gdStr()
img_L_button = gd.createFromPng("images/L_button.png"):gdStr()
img_M_button = gd.createFromPng("images/M_button.png"):gdStr()
img_H_button = gd.createFromPng("images/H_button.png"):gdStr()
-- Hollowed-out versions, drawn on the frame a button is RELEASED. Releases
-- were previously invisible on the strip, which matters here: a dragon punch
-- (and so a guard cancel) can be completed by releasing a punch as well as by
-- pressing one, so the frame the command actually completed had nothing drawn
-- on it at all.
img_L_button_release = gd.createFromPng("images/L_button_release.png"):gdStr()
img_M_button_release = gd.createFromPng("images/M_button_release.png"):gdStr()
img_H_button_release = gd.createFromPng("images/H_button_release.png"):gdStr()
-- Dimmed versions, drawn when a button is STILL HELD from an earlier column
-- rather than newly pressed on this one. A column starts whenever anything
-- about the input changes, so moving the stick while holding a button used to
-- redraw that button at full brightness on the new column - indistinguishable
-- from pressing it again. Three states now: bright = pressed this frame,
-- dim = held, hollow = released.
img_L_button_held = gd.createFromPng("images/L_button_held.png"):gdStr()
img_M_button_held = gd.createFromPng("images/M_button_held.png"):gdStr()
img_H_button_held = gd.createFromPng("images/H_button_held.png"):gdStr()
img_no_button = gd.createFromPng("images/no_button.png"):gdStr()
img_dir = {
img_1_dir,
img_2_dir,
img_3_dir,
img_4_dir,
img_5_dir,
img_6_dir,
img_7_dir,
img_8_dir,
img_9_dir
}
input_history_size_max = 80
input_history = {
    {},
    {}
}

-- create as a subject so we can push values directly
-- https://github.com/bjornbytes/RxLua/tree/master/doc#subject
-- both P1 and P2 producers send events of the form:
-- {direction=5,
-- 	buttons={false, false, false, false, false, false},
-- 	frame=87100,
-- 	pb_event='p1_pb_none',
-- 	gc_event='p1_gc_none'}

-- these producers send human input on each frame where the input changed
-- they remember the 100 most recent messages
-- TODO interleave them with skipped frames to create a true input history
local p1_input_history_producer = Rx.ReplaySubject.create(100)
local p2_input_history_producer = Rx.ReplaySubject.create(100)


-- HISTORY
history = {}
history_sections = {
    global = 1,
    P1 = 2,
    P2 = 3,
}
history_categories = {}
history_recording_on = false
history_category_count = 0
current_entry = 1
history_size_max = 100
history_line_count_max = 25
history_line_offset = 0
local frame_number = 0
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
  
  history_enabled = false
  history_recording_on = false
  history_categories_shown =
{
--   input = false,
--   fight = true,
--   parry_training_FORWARD = false,
  -- PB = true,
  -- GC = true,
  -- hit_spark = true,
  -- hit_spark = true,
  -- idle = true
}
function history_add_entry(_section_name, _category_name, _event_name)
  if not history_enabled then return end
  if not history_recording_on then return end

  _event_name = _event_name or ""
  _category_name = _category_name or ""
  _section_name = _section_name or "global"
  if history_sections[_section_name] == nil then _section_name = "global" end

  if not history_categories_shown[_category_name] then return end

  -- Add category if it does not exists
  if history_categories[_category_name] == nil then
    history_categories[_category_name] = history_category_count
    history_category_count = history_category_count + 1
  end

  -- Insert frame if it does not exists
  if #history == 0 or history[#history].frame ~= frame_number then
    table.insert(history, {
      frame = frame_number,
      events = {}
    })
  end

  -- Remove overflowing history frame
  while #history > history_size_max do
    table.remove(history, 1)
  end

  local _current_frame = history[#history]
  table.insert(_current_frame.events, {
    name = _event_name,
    section = _section_name,
    category = _category_name,
    color = string_to_color(_event_name)
  })
end

history_filtered = {}
history_start_locked = false
function history_update()
  history_filtered = {}
  if not history_enabled then return end

  -- compute filtered history
  for _i = 1, #history do
    local _frame = history[_i]
    local _filtered_frame = { frame = _frame.frame, events = {}}
    for _j, _event in ipairs(_frame.events) do
      if history_categories_shown[_event.category] then
        table.insert(_filtered_frame.events, _event)
      end
    end

    if #_filtered_frame.events > 0 then
      table.insert(history_filtered, _filtered_frame)
    end
  end

--   -- process input
--   if player.input.down.start then
--     if player.input.pressed.HP then
--       history_start_locked = true
--       history_recording_on = not history_recording_on
--       if history_recording_on then
--         history_line_offset = 0
--       end
--     end
--     if player.input.pressed.HK then
--       history_start_locked = true
--       history_line_offset = 0
--       history = {}
--     end

--     if check_input_down_autofire(player, "up", 4) then
--       history_start_locked = true
--       history_line_offset = history_line_offset - 1
--       history_line_offset = math.max(history_line_offset, 0)
--     end
--     if check_input_down_autofire(player, "down", 4) then
--       history_start_locked = true
--       history_line_offset = history_line_offset + 1
--       history_line_offset = math.min(history_line_offset, math.max(#history_filtered - history_line_count_max - 1, 0))
--     end
--   end

--   if not player.input.down.start and not player.input.released.start then
--     history_start_locked = false
--   end
end
function history_draw()
  local _history = history_filtered
  if #_history == 0 then return end

  local _line_background = { 0x333333CC, 0x555555CC }
  local _separator_color = 0xAAAAAAFF
  local _width = emu.screenwidth() - 10
  local _height = emu.screenheight() - 10
  local _x_start = 5
  local _y_start = 5

  local _line_height = 8
  local _current_line = 0
  local _columns_start = { 0, 20, 200 }
  local _box_size = 6
  local _box_margin = 2
  gui.box(_x_start, _y_start , _x_start + _width, _y_start, 0x00000000, _separator_color)
  local _last_displayed_frame = 0
  for _i = 0, history_line_count_max do
    local _frame_index = #_history - (_i + history_line_offset)
    if _frame_index < 1 then
      break
    end
    local _frame = _history[_frame_index]
	local _events = {{}, {}, {}}

	for _j, _event in ipairs(_frame.events) do
	  if history_categories_shown[_event.category] then
        table.insert(_events[history_sections[_event.section]], _event)
      end
    end

    local _y = _y_start + _current_line * _line_height
    gui.box(_x_start, _y, _x_start + _width, _y + _line_height, _line_background[(_i % 2) + 1], 0x00000000)
    for _section_i = 1, 3 do
      local _box_x = _x_start + _columns_start[_section_i]
      local _box_y = _y + 1
      for _j, _event in ipairs(_events[_section_i]) do
        gui.box(_box_x, _box_y, _box_x + _box_size, _box_y + _box_size, _event.color, 0x00000000)
        gui.box(_box_x + 1, _box_y + 1, _box_x + _box_size - 1, _box_y + _box_size - 1, 0x00000000, 0x00000022)
        gui.text(_box_x + _box_size + _box_margin, _box_y, _event.name, text_default_color, 0x00000000)
        _box_x = _box_x + _box_size + _box_margin + get_text_width(_event.name) + _box_margin
      end
    end

    if _frame_index > 1 then
      local _frame_diff = _frame.frame - _history[_frame_index - 1].frame
      gui.text(_x_start + 2, _y + 1, string.format("%d", _frame_diff), text_default_color, 0x00000000)
    end
    gui.box(_x_start, _y + _line_height, _x_start + _width, _y + _line_height, 0x00000000, _separator_color)
    _current_line = _current_line + 1
    _last_displayed_frame = _frame_index
  end
end

-- Read the input the GAME latched, rather than the pad state the emulator
-- saw. The on-screen strip also carries GC / AG window markers, and those are
-- derived from game RAM (handle_gc_event / handle_pb_event), so drawing the
-- inputs from the emulator put two different time bases on the same row - the
-- inputs ran one frame ahead of the markers (measured: 44 of 46 presses at
-- exactly 1 frame, the other 2 at 2 frames across a turbo double-tick).
-- Reading both from RAM keeps the row internally consistent.
--
--   +0x122  buttons: bit0 LP, bit1 MP, bit2 HP, bit4 LK, bit5 MK, bit6 HK
--   +0x125  stick:   bit2 down, bit3 up (absolute), bit0/bit1 back|forward
--   +0x00B  facing
--
-- Note on +0x125: the neighbouring +0x123 holds the same layout and looks
-- like the obvious choice, but it is not stable - while the character faces
-- one way it tracks the stick correctly, and while facing the other way it
-- alternates between the two horizontal bits every frame, which shows up as
-- the arrow flickering left/right even though the stick is being held. +0x125
-- does not do this. Measured over recorded play: during held horizontal
-- input, +0x123 changed value on 20.3% of frames versus 4.2% for +0x125, and
-- reconstruction accuracy is 83% / 96% (facing 1) versus 99.9% overall.
--
-- Left/right are stored relative to facing, so they have to be swapped back:
--   facing == 0 -> bit0 is right, bit1 is left
--   facing ~= 0 -> bit0 is left,  bit1 is right
-- _raw: a ($125,$122) pair captured on a game tick this displayed frame did
-- not sample. guardCancel.lua's hook on 0x0221CC queues one per tick on which
-- the pair CHANGED; registerBefore drains the queue through here before taking
-- its own reading. Without it the bar can only show what survives to the end
-- of a frame, and the input that completes a command is a one-tick event.
local function read_game_input(_prefix, _raw)
  local base = (_prefix == "P2") and 0xFF8800 or 0xFF8400
  local btn = _raw and _raw.btn or memory.readbyte(base + 0x122)
  local dir = _raw and _raw.dir or memory.readbyte(base + 0x125)
  local facing = memory.readbyte(base + 0x00B)

  -- NOTE (v38): there is deliberately NO special case here for the tick-exact
  -- reversal injection. v36/v37 added one, on the reasoning that a one-tick
  -- input can fall between the once-per-frame samples. It can - but the fix
  -- belongs upstream: the controller emits the final entry itself once the
  -- sequence is released, which is what drew that column correctly all along.
  -- Restoring that (guardCancel.lua / controller.lua) removes the need for a
  -- synthetic column here, and a synthetic column that disagrees with memory
  -- by even one frame produces a duplicate one instead of a fix.

  local bit0 = (dir % 2) >= 1
  local bit1 = (math.floor(dir / 2) % 2) >= 1
  local _left, _right
  if facing == 0 then
    _left, _right = bit1, bit0
  else
    _left, _right = bit0, bit1
  end
  local _down = (math.floor(dir / 4) % 2) >= 1
  local _up   = (math.floor(dir / 8) % 2) >= 1

  local _direction = 5
  if _down then
    if _left then _direction = 1
    elseif _right then _direction = 3
    else _direction = 2 end
  elseif _up then
    if _left then _direction = 7
    elseif _right then _direction = 9
    else _direction = 8 end
  else
    if _left then _direction = 4
    elseif _right then _direction = 6
    else _direction = 5 end
  end

  local function pressed(bit_index)
    return (math.floor(btn / 2 ^ bit_index) % 2) >= 1
  end

  return _direction, {
    pressed(0),  -- Weak Punch
    pressed(1),  -- Medium Punch
    pressed(2),  -- Strong Punch
    pressed(4),  -- Weak Kick
    pressed(5),  -- Medium Kick
    pressed(6),  -- Strong Kick
  }
end

-- Buttons released this frame, per player. Cached by frame because the entry
-- builders can both run within the same frame and must see the same answer.
--
-- CHANGED: this is now also part of is_input_history_entry_equal(), so a
-- release forms its own single-frame column instead of merging with the
-- frames that follow it. See the note there.
--
-- Hiding releases is still left to the existing "Hide negative edge
-- inputs" option, which remove_nedge_events() already implements.
local prev_buttons = {}
local released_cache = {}

-- Returns released, pressed - both edges against the previous frame. They are
-- worked out together because this is also where prev_buttons is advanced:
-- computing them in two passes would make the second pass compare against the
-- wrong frame.
local function get_button_edges(_prefix, _buttons)
  local c = released_cache[_prefix]
  if c and c.frame == frame_number then return c.released, c.pressed end

  local rel = { false, false, false, false, false, false }
  local prs = { false, false, false, false, false, false }

  local prev = prev_buttons[_prefix]
  if prev then
    for i = 1, 6 do
      rel[i] = (prev[i] == true) and (_buttons[i] ~= true)
      prs[i] = (_buttons[i] == true) and (prev[i] ~= true)
    end
  else
    -- Nothing to compare against yet, so anything down now is its own press.
    for i = 1, 6 do
      prs[i] = (_buttons[i] == true)
    end
  end

  prev_buttons[_prefix] = _buttons
  released_cache[_prefix] = { frame = frame_number, released = rel, pressed = prs }
  return rel, prs
end

function make_input_history_entry(_prefix, _input, _raw)
  local _direction, _buttons = read_game_input(_prefix, _raw)
  local _released, _pressed = get_button_edges(_prefix, _buttons)

  -- THE RELEASE COLUMN IS ONE SWITCH, AND THIS IS THE ONLY PLACE IT IS HELD.
  --
  -- Dropping `released` here takes the whole feature out: the equality test
  -- stops splitting the release into its own column, _btn() stops reaching for
  -- the hollow image, and both width shortcuts stop making room for it. Every
  -- one of those already reads it defensively, so nothing else has to know.
  --
  -- Before this switch existed, Hide Negative Edge Inputs was the only way to
  -- be rid of the hollow markers - it removes any column with no new press,
  -- which a release column always is. That left one row doing two jobs and the
  -- decluttering could not be had without losing the markers (user, 2026-09-14,
  -- comparing against the N-Bee build).
  --
  -- get_button_edges() is still CALLED either way: it carries the previous
  -- frame's buttons, so skipping it would make the first release after the
  -- switch is turned back on read against stale state.
  if globals.options and globals.options.show_button_releases ~= true then
    _released = nil
  end

  return {
    frame = frame_number,
    direction = _direction,
    buttons = _buttons,
    released = _released,
    -- Which buttons went down on THIS frame. A history column stores the
    -- entry from its first frame, so this stays true for the column that
    -- began with the press and false for later columns where the button is
    -- merely still held. Drawing only - like released, it is deliberately
    -- not part of is_input_history_entry_equal().
    pressed = _pressed,
    gc_event = globals.gc_event,
    -- Drawing only, like pressed and released above - deliberately not
    -- part of is_input_history_entry_equal(). Two columns that differ only
    -- in this cannot happen: it is set on one tick per window.
    gc_ticks = globals.gc_ticks,
    pb_event = globals.pb_event,
  }
end


function make_input_history_entry_for_graph(_prefix, _input)
  local _direction, _buttons = read_game_input(_prefix)

  return {
      direction = _direction,
      buttons = _buttons
  }
end
function is_input_history_entry_equal(_a, _b)
  -- A button release is its own single-frame column.
  --
  -- Releases used to be drawing-only, deliberately left out of this test. The
  -- consequence was that the release column absorbed every following frame
  -- with the same direction and no buttons: holding a direction and letting
  -- the button go produced ONE column showing the release with a count of
  -- 100+, instead of a 1-frame release followed by a separate
  -- direction-still-held column.
  --
  -- Comparing the release edge here splits them: the release frame has
  -- released[i] true, the frame after it has them all false, so the columns
  -- can never merge. The press edge is left out on purpose - a press already
  -- differs by buttons[], and including it would stop a held button from
  -- accumulating its frame count.
  local _ra, _rb = _a.released, _b.released
  if (_ra ~= nil) ~= (_rb ~= nil) then return false end
  if _ra ~= nil then
    for i = 1, 6 do
      if (_ra[i] == true) ~= (_rb[i] == true) then return false end
    end
  end
  if (_a.direction ~= _b.direction) then return false end
  if (_a.buttons[1] ~= _b.buttons[1]) then return false end
  if (_a.buttons[2] ~= _b.buttons[2]) then return false end
  if (_a.buttons[3] ~= _b.buttons[3]) then return false end
  if (_a.buttons[4] ~= _b.buttons[4]) then return false end
  if (_a.buttons[5] ~= _b.buttons[5]) then return false end
  if (_a.buttons[6] ~= _b.buttons[6]) then return false end
  if globals.options and globals.options.show_gc_trainer == true then 
    if (_a.gc_event ~= _b.gc_event) then return false end
    if (_a.pb_event ~= _b.pb_event) then return false end
  end
  return true
end
function is_event_history_entry_equal(_a, _b)
    if globals.options and globals.options.show_gc_trainer == true then 
        if (_a.gc_event ~= _b.gc_event) then
            print("Returning because equal gc") 
            return false
         end
        if (_a.pb_event ~= _b.pb_event) then
            print("Returning because equal pb")

             return false
        end
      end
    return true    
end
function make_event_history_entry(event)
    return {
        type = "event",
        frame = frame_number,
        gc_event = globals.gc_event,
        -- NO gc_ticks HERE. Event entries are built every frame and then
        -- dropped: the isEvent branch of update_input_history that would
        -- insert them is commented out, so nothing built here is ever
        -- drawn. Adding the field would be a line no test can reach.
        pb_event = globals.pb_event    
    }
end

-- wrapper for _history table updates
-- does the table update + sends input on producer
-- DIAGNOSTIC (read-only). Every column actually committed to P2's history,
-- so a missing column can be told apart from a column that was created and
-- then not drawn. debugKnockdown.lua copies this into each recording.
local function trace_history_entry(_prefix, _entry)
  if _prefix ~= "P2" then return end
  if globals == nil then return end
  -- Created here, lazily. Creating it from debugKnockdown.lua at load time
  -- silently did nothing - globals was not populated yet at that point, so
  -- the field stayed nil and every recording reported zero columns, which
  -- reads exactly like "no columns were committed" and is not the same thing.
  if type(globals.hist_trace) ~= "table" then globals.hist_trace = {} end
  local _b = 0
  if _entry.buttons then
    for i = 1, 6 do if _entry.buttons[i] == true then _b = _b + 2 ^ (i - 1) end end
  end
  table.insert(globals.hist_trace, { f = _entry.frame, d = _entry.direction, b = _b })
  while #globals.hist_trace > 400 do table.remove(globals.hist_trace, 1) end
end

function observable_input_update(_history, _prefix, _entry)
	trace_history_entry(_prefix, _entry)
	if _prefix == "P1" then
	  p1_input_history_producer(_entry)
	elseif _prefix == "P2" then
	  p2_input_history_producer(_entry)
	else
		print("unknown edge case in observable_input_update",
		_entry, _prefix)
	end
        table.insert(_history, _entry)
end

function update_input_history(_history, _prefix, _input, isEvent, event, _raw)
  local entry
  local inp_entry = make_input_history_entry_for_graph(_prefix, _input)

  if isEvent then
     _entry = make_event_history_entry(event)
  else
      _entry = make_input_history_entry(_prefix, _input, _raw)
  end 
  -- print("frame", frame_number, _prefix, globals.input_history[_prefix], #globals.input_history[_prefix])
  if 
    _prefix and
    frame_number and
    globals.input_history and
    globals.input_history[_prefix] and
    #globals.input_history[_prefix] == 0 and 
    globals.input_history[_prefix][frame_number]
  then
    globals.input_history[_prefix][frame_number] = inp_entry
  else
    if gather_graph_data == true then 
      local input_last_entry = globals.input_history[_prefix][#globals.input_history]
      if input_last_entry and input_last_entry.frame and input_last_entry.frame ~= frame_number then
        globals.input_history[_prefix][frame_number] = inp_entry
        -- table.insert(globals.input_history, inp_entry)
      end
    else
      globals.input_history = {}
    end

  end
  if #_history == 0 then
    if _entry.type then -- don't broadcast events on input chan
      table.insert(_history, _entry)
    else
      observable_input_update(_history, _prefix, _entry)
    end
  else
    local _last_entry = _history[#_history]
    local _last_event_entry = nil
    for i = #_history, 1, -1 do
        if _last_event_entry == nil and _history[i].type == "event" then 
            _last_event_entry = _history[i]
        end
    end
    if isEvent then
        -- if _last_entry.frame ~= frame_number and _last_event_entry ~= nil and not is_event_history_entry_equal(_entry, _last_event_entry) then
        --     table.insert(_history, _entry)
        -- end
    else
        if _last_entry.frame ~= frame_number and not is_input_history_entry_equal(_entry, _last_entry) then
          observable_input_update(_history, _prefix, _entry)
        end
    end
  end

  while #_history > input_history_size_max do
    table.remove(_history, 1)
  end

  while #input_history > input_history_size_max do
    table.remove(input_history, 1)
  end

end

function draw_input_history_entry(_entry, _x, _y, color, step)
  if _entry and _entry.type then
    if _entry.gc_event == "p1_gc_begin" then
      gui.text(_x + 1 , _y - 9, "GC", "#00FF00")
      gui.box(_x + 10, _y - 9, _x + step - 1, _y - 4, "#99EE9977", "#99EE9977")
    elseif _entry.gc_event == "p1_gc_in_progress" then
      gui.box(_x , _y - 9, _x + step - 2, _y - 4, "#99EE9977","#99EE9977")
    elseif _entry.gc_event == "p1_gc_ended" then
      gui.text(_x + 1 , _y - 9, "GC", "#FF0000")
    elseif _entry.gc_event == "p1_gc_success" then
      -- Cancel came out. The command completes on this same frame - measured
      -- across recorded cancels, the qualifying input (a press, a release, or
      -- the final direction) lands on the frame the timer reaches zero, so
      -- the label belongs here and not a frame either side of it.
      gui.text(_x + 1 , _y - 9, "SUCCESS", "#FFD700")
    end
    
    if _entry.pb_event == "p1_pb_begin" then
      gui.text(_x + 1 , _y - 9, "PB", "#00FF00")
      gui.box(_x + 10 , _y - 9, _x + step - 1, _y - 4, "#99EE9977", "#99EE9977")
    elseif _entry.pb_event == "p1_pb_in_progress" then
      gui.box(_x , _y - 9, _x + step - 2, _y - 4, "#99EE9977","#99EE9977")
    elseif _entry.pb_event == "p1_pb_ended" then
      gui.text(_x + 1 , _y - 9, "PB", "#FF0000")
    end
    return
  end
	local no_buttons =  _entry.buttons[1] == false and
						_entry.buttons[2] == false and
						_entry.buttons[3] == false and
						_entry.buttons[4] == false and
						_entry.buttons[5] == false and
						_entry.buttons[6] == false 

	-- A release frame has no buttons held, but still needs the button area
	-- drawn so the hollow marker is visible - otherwise the shortcuts below
	-- would return early and the release would stay invisible.
	if no_buttons and _entry.released then
		for i = 1, 6 do
			if _entry.released[i] then no_buttons = false break end
		end
	end

	if globals.options.show_gc_trainer == true then 
		if _entry.gc_event == "p1_gc_begin" then
			gui.text(_x + 1 , _y - 9, "GC", "#00FF00")
			gui.box(_x + 10, _y - 9, _x + step - 1, _y - 4, "#99EE9977", "#99EE9977")
		elseif _entry.gc_event == "p1_gc_in_progress" then
			gui.box(_x , _y - 9, _x + step - 2, _y - 4, "#99EE9977","#99EE9977")
		elseif _entry.gc_event == "p1_gc_ended" then
			gui.text(_x + 1 , _y - 9, "GC", "#FF0000")
		elseif _entry.gc_event == "p1_gc_success" then
			gui.text(_x + 1 , _y - 9, "SUCCESS", "#FFD700")
			-- How far into the 14 tick window the cancel came out, measured on
			-- ticks by the hook in guardCancel.lua. Absent when that hook is not
			-- running (the offline tests and the old frame path), and then
			-- nothing is drawn rather than a frame count wearing a t.
			--
			-- SUCCESS is seven glyphs from _x + 1 at about 4.2px each, so this
			-- starts past it. It runs wider than the column, which is already
			-- true of SUCCESS itself; the columns after a cancel draw nothing in
			-- this band unless a push block starts on top of it (user, 2026-09-23).
			if _entry.gc_ticks ~= nil then
				gui.text(_x + 32, _y - 9, _entry.gc_ticks .. "t", "#FFD700")
			end
    end
    if _entry.pb_event == "p1_pb_begin" then
			gui.text(_x + 1 , _y - 9, "PB", "#00FF00")
			gui.box(_x + 10 , _y - 9, _x + step - 1, _y - 4, "#99EE9977", "#99EE9977")
		elseif _entry.pb_event == "p1_pb_in_progress" then
			gui.box(_x , _y - 9, _x + step - 2, _y - 4, "#99EE9977","#99EE9977")
		elseif _entry.pb_event == "p1_pb_ended" then
			gui.text(_x + 1 , _y - 9, "PB", "#FF0000")
		end
  end
	if no_buttons and _entry.direction == 5 then
		-- gui.box(_x -1 , _y - 1, _x + 30, _y + 20, color)
		gui.text(_x + 1 , _y + 2, "IDLE", "#99EE99")
		return;
	elseif no_buttons and _entry.direction ~= 5 then
		gui.image(_x + 2 , _y, img_dir[_entry.direction])
		return;	
	end
  gui.box(_x -1 , _y - 1, _x + 30, _y + 20, color)


  gui.image(_x, _y, img_dir[_entry.direction])

  local _img_LP = img_no_button
  local _img_MP = img_no_button
  local _img_HP = img_no_button
  local _img_LK = img_no_button
  local _img_MK = img_no_button
  local _img_HK = img_no_button
  local _rel = _entry.released or {}
  -- No pressed field means the entry predates it being recorded; treat every
  -- held button as a press then, which is the old behaviour.
  local _prs = _entry.pressed
  local _assume_press = _prs == nil
  _prs = _prs or {}

  local function _btn(_i, _img_press, _img_held, _img_release)
    if _entry.buttons[_i] then
      if _assume_press or _prs[_i] then return _img_press end
      return _img_held
    elseif _rel[_i] then
      return _img_release
    end
    return img_no_button
  end

  _img_LP = _btn(1, img_L_button, img_L_button_held, img_L_button_release)
  _img_MP = _btn(2, img_M_button, img_M_button_held, img_M_button_release)
  _img_HP = _btn(3, img_H_button, img_H_button_held, img_H_button_release)
  _img_LK = _btn(4, img_L_button, img_L_button_held, img_L_button_release)
  _img_MK = _btn(5, img_M_button, img_M_button_held, img_M_button_release)
  _img_HK = _btn(6, img_H_button, img_H_button_held, img_H_button_release)

  gui.image(_x + 13, _y, _img_LP)
  gui.image(_x + 18, _y, _img_MP)
  gui.image(_x + 23, _y, _img_HP)
  gui.image(_x + 13, _y + 5, _img_LK)
  gui.image(_x + 18, _y + 5, _img_MK)
  gui.image(_x + 23, _y + 5, _img_HK)
end

function remove_nedge_events(_history)
	if #_history < 2 then return _history end
	local cleaned_history = {}
	local last_direction = nil
	local last_buttons = {nil, nil, nil, nil, nil, nil}
	for _i = 1, #_history, 1 do
		-- check if history entry is an input event or game state evnt
		-- -- for game state event, just append, do not change
		local current_entry = _history[_i]
		if current_entry.type then
			-- game state event, append and ignore
			table.insert(cleaned_history, current_entry)
		elseif (current_entry.gc_event ~= "p1_gc_none") or (
			current_entry.pb_event ~= "p1_pb_none") then
			table.insert(cleaned_history, current_entry)
			-- if gc/pb occurs, display even if no new button presses
			last_direction = current_entry.direction
			for i = 1,6 do last_buttons[i] = current_entry.buttons[i] end
		else
			-- input event, update last and remove if only neg edge
			local nedge_event = current_entry.direction == last_direction
		        for i = 1,6 do
				if current_entry.buttons[i] and not last_buttons[i] and last_buttons[i] ~= nil then
					nedge_event=false
	                	end
				last_buttons[i] = current_entry.buttons[i]
			end
			last_direction = current_entry.direction
			-- A RELEASE COLUMN IS THE OTHER SWITCH'S BUSINESS.
			--
			-- It never has a newly pressed button, so the rule above always
			-- reads it as clutter - which is how this row came to double as
			-- the on/off for the hollow release markers. Show Button Releases
			-- decides whether those columns exist at all; what is left here is
			-- the job this row was written for: the redundant column that a
			-- release LEAVES BEHIND, same direction and nothing new pressed.
			if current_entry.released then
				for i = 1, 6 do
					if current_entry.released[i] then nedge_event = false break end
				end
			end
			if nedge_event == false then
				table.insert(cleaned_history, current_entry)
			end
	        end
	end
	return cleaned_history
end

function draw_input_history(_history, _x, _y, _is_left)
  local _step_y = 18

  local _step_x_idle = 22
  local _step_x_both = 38
  local _step_x_dirs_only = 18
  local _step_x_buttons_only = 38
  local _step_x_event = 38

  local num_idle = 0 
  local num_buttons_only = 0
  local num_dirs_only = 0
  local num_both = 0
  local num_event = 0

  local _j = 0
  
  local color = "black"
  local scroll_offset = 0
  if globals.options.inp_history_scroll > #_history then
	scroll_offset = #_history
  else
	scroll_offset = globals.options.inp_history_scroll
  end
  for _i = #_history - scroll_offset, 1, -1 do
    local _entry = _history[_i]
    local state = nil
    local no_buttons
    if _entry and _entry.type then
        no_buttons = true
    else
        no_buttons = _entry.buttons[1] == false and
		_entry.buttons[2] == false and
		_entry.buttons[3] == false and
		_entry.buttons[4] == false and
		_entry.buttons[5] == false and
		_entry.buttons[6] == false

        -- FIX: same release override draw_input_history_entry applies, and it
        -- has to be applied HERE too because this is what picks the column
        -- WIDTH. A release frame holds no buttons, so this used to classify it
        -- as "idle" and reserve _step_x_idle (22px) - while the entry drawing
        -- treated it as a button column and drew a 31px box plus the six
        -- button slots. The release column overflowed its slot by 9px and its
        -- hollow marker landed on top of the neighbouring press column, which
        -- read as a press and a release sharing one box.
        if no_buttons and _entry.released then
            for i = 1, 6 do
                if _entry.released[i] then no_buttons = false break end
            end
        end
    end
	local step = 0
	if no_buttons == false and _entry.direction ~= 5 then
		state = "both"
		step = _step_x_both
		num_both = num_both + 1
  	elseif no_buttons and _entry.direction ~= 5 then 
		state = "directions_only"
		step = _step_x_dirs_only
		num_dirs_only = num_dirs_only + 1
	elseif no_buttons and _entry.direction == 5 then
		state = "idle"
		step = _step_x_idle 
		num_idle = num_idle + 1
	elseif no_buttons == false and _entry.direction == 5 then
		state = "buttons_only"
		step = _step_x_buttons_only
		num_buttons_only = num_buttons_only + 1
	end


	local _current_y = _y + _j * _step_y
	local _current_x = 
		_x 
		- (num_both  * _step_x_both) 
		- (num_idle * _step_x_idle)
		- (num_dirs_only * _step_x_dirs_only)
		- (num_buttons_only * _step_x_buttons_only)
		- (num_event * _step_x_event)

	
    local _entry_offset = 0
    if _is_left then _entry_offset = 13 end
    draw_input_history_entry(_entry, _current_x + _entry_offset, _y, color, step)

    local _next_frame = frame_number
    if _i < #_history then
      _next_frame = _history[_i + 1].frame
    end
    local _frame_diff = _next_frame - _entry.frame
    local _text = "-"
    if (_frame_diff < 999) then
      _text = string.format("%d", _frame_diff)
    end

    local _offset = 0
    if _is_left then
      _offset = 8
      if (_frame_diff < 999) then
        if (_frame_diff >= 100) then _offset = 0
        elseif (_frame_diff >= 10) then _offset = 4 end
      end
    else
      _offset = 33
    end
    _j = _j + 1
	local held_length_x = 18
	if state == "idle" then
		held_length_x = 16
	elseif state == "event" then 
		held_length_x = 18
	elseif state == "directions_only" then
		held_length_x = 14
	elseif state == "buttons_only" then
		held_length_x = 10
	elseif state == "both" then
		held_length_x = 18
	end
	-- gui.text(_x + _offset, _current_y + 2, _text, 0xd6e3efff, 0x101000ff)
	gui.text(_current_x + held_length_x + _offset, _y + 11, _text, "#62b8d5", 0x101000ff)
  end
end

-- !History

-- !History
function reset_inp_history_scroll()
    globals.options.inp_history_scroll = 0
end
local function handle_gc_event()
    local hit_spark_timer_addr = 0xFF8558 
    -- local hit_spark_timer = memory.readbyte(hit_spark_timer_addr)
    local p1_gc_timer = memory.readbyte(0xFF8558)

    -- todo: GC event history should be moved to a tick-based queue
    -- (ie accommodate frameskip for more granular event data)
    -- BEGIN COUNTS TOO. A cancel on the tick after the window opened
    -- arrives while the state is still begin, and requiring in_progress
    -- left it stuck there with no SUCCESS drawn. Kept in step with
    -- gc_next_state() in guardCancel.lua, which is the path that runs
    -- when the tick hook is there (user, 2026-09-23).
    if p1_gc_timer == 0 and (globals.gc_event == "p1_gc_in_progress"
                             or globals.gc_event == "p1_gc_begin") then
      -- The window closing does not say WHY it closed. Two different things
      -- were being drawn with the same red "GC":
      --   * the window simply ran out (nothing was cancelled)
      --   * a guard cancel actually came out, which clears the timer early
      -- On the frame the timer reaches zero, P1's action byte (0xFF8406)
      -- identifies what started. dummyState.lua already documents the values:
      --   0x0E = special, 0x10 = ES special (p1_is_es), 0x12 = EX (p1_is_ex)
      -- All three count as a successful cancel - checking only 0x0E missed
      -- every ES guard cancel, which is why some clearly successful cancels
      -- were still being labelled with the red "GC".
      local p1_action = memory.readbyte(0xFF8406)
      if p1_action == 0x0E or p1_action == 0x10 or p1_action == 0x12 then
        globals.gc_event = "p1_gc_success"
      else
        globals.gc_event = "p1_gc_ended"
      end
      history_add_entry("P1", "GC", globals.gc_event)
    elseif globals.gc_event == "p1_gc_none" and p1_gc_timer > 0 then
      globals.gc_event = "p1_gc_begin"
      history_add_entry("P1", "GC", globals.gc_event)
    elseif p1_gc_timer > 0 then
        globals.gc_event = "p1_gc_in_progress"
        -- history_add_entry("P1", "GC", globals.gc_event)
    elseif globals.gc_event == "p1_gc_ended" or globals.gc_event == "p1_gc_success" then 
      globals.gc_event = "p1_gc_none"
    --   history_add_entry("P1", "GC", globals.gc_event)
    else 
        return false
    end
    return true

end
local function handle_pb_event()

    local p1_pushblock_counter = memory.readbyte(0xFF8400 + 0x170)
    local p1_tech_hit_timer = memory.readbyte(0xFF8400 + 0x1AB) 

    if p1_tech_hit_timer == 0 and globals.pb_event == "p1_pb_in_progress" then
        globals.pb_event = "p1_pb_ended"
        history_add_entry("P1", "PB", globals.pb_event)
    elseif globals.pb_event == "p1_pb_none" and p1_tech_hit_timer > 0 then
        globals.pb_event = "p1_pb_begin"
        history_add_entry("P1", "PB", globals.pb_event)
    elseif p1_tech_hit_timer > 0 then
        globals.pb_event = "p1_pb_in_progress"
    elseif globals.pb_event == "p1_pb_ended" then 
        globals.pb_event = "p1_pb_none"
    else 
        return false
    end
    return true

end

local p2_block_state_addr = 0xFF8806 
local p2_prev_hitspark = false
local p2_hitspark_in_progress = false
local function handle_post_hitspark_event()
    local p2_is_post_hitspark = memory.readbyte(p2_block_state_addr) == 0x02
    -- print("blocking?", p2_is_post_hitspark)
    if p2_is_post_hitspark and not p2_prev_hitspark then
        globals.post_hit_spark_event = "p2_post_hitspark_begin"
        p2_prev_hitspark = true
        history_add_entry("P2", "hit_spark", globals.post_hit_spark_event)
    elseif not p2_is_post_hitspark and p2_prev_hitspark then
        globals.post_hit_spark_event = "p2_post_hitspark_end"
        p2_prev_hitspark = false
        history_add_entry("P2", "hit_spark", globals.post_hit_spark_event)
    end
    -- if p2_hit_spark_timer == 0 and globals.hit_spark_event == "p2_hit_spark_in_progress" then
    --     globals.hit_spark_event = "p2_hit_spark_ended"
    --     history_add_entry("P2", "hit_spark", globals.hit_spark_event)
    -- elseif globals.hit_spark_event == "p2_hit_spark_none" and p2_hit_spark_timer > 0 then
    --     globals.hit_spark_event = "p2_hit_spark_begin"
    --     history_add_entry("P2", "hit_spark", globals.hit_spark_event)
    -- elseif p2_hit_spark_timer > 0 then
    --     globals.hit_spark_event = "p2_hit_spark_in_progress"
    -- elseif globals.hit_spark_event == "p2_hit_spark_ended" then 
    --     globals.hit_spark_event = "p2_hit_spark_none"
    -- else 
    --     return false
    -- end
    -- return true
end

local p2_hit_spark_timer_addr = 0xFF8558 + 0x400 
local function handle_hit_spark_event()
    local p2_hit_spark_timer = memory.readbyte(p2_hit_spark_timer_addr)

    if p2_hit_spark_timer == 0 and globals.hit_spark_event == "p2_hit_spark_in_progress" then
        globals.hit_spark_event = "p2_hit_spark_ended"
        history_add_entry("P2", "hit_spark", globals.hit_spark_event)
    elseif globals.hit_spark_event == "p2_hit_spark_none" and p2_hit_spark_timer > 0 then
        globals.hit_spark_event = "p2_hit_spark_begin"
        history_add_entry("P2", "hit_spark", globals.hit_spark_event)
    elseif p2_hit_spark_timer > 0 then
        globals.hit_spark_event = "p2_hit_spark_in_progress"
    elseif globals.hit_spark_event == "p2_hit_spark_ended" then 
        globals.hit_spark_event = "p2_hit_spark_none"
    else 
        return false
    end
    return true
end

function handle_idle_event( was_gc_event, was_pb_event,_was_hit_spark_event)
    if history and not history[#history] then
        history_add_entry("P1", "idle", "Begin")
        history_add_entry("P2", "idle", "Begin")
        
    end
    -- local last_event_was_idle = nil
    -- if history and history[#history] then
    --     last_event_was_idle = history[#history].events[1].category == "idle" and history[#history].events[2].category == "idle"
    -- end

    -- if not was_gc_event and 
    --     not was_pb_event and 
    --     not was_hit_spark_event and 
    --     not last_event_was_idle
    -- then
    --     -- last_event_was_idle = true
    --     history_add_entry("P1", "idle", "No Event")
    --     history_add_entry("P2", "idle", "No Event")
    -- end

end
local inpHistoryModule = {
    ["registerStart"] = function()
        return {
            reset_inp_history_scroll = reset_inp_history_scroll,
            draw_input_history_entry = draw_input_history_entry
        }
    end,
    ["registerBefore"] = function(_input)
        -- THE HISTORY RUNS ON THE GAME'S CLOCK, NOT THE SCREEN'S.
        --
        -- This was emu.framecount(), and frame_number is what decides whether a
        -- column may be appended: update_input_history() only starts a new one
        -- when _last_entry.frame ~= frame_number. On a displayed-frame clock
        -- that is AT MOST ONE COLUMN PER FRAME, however many inputs happened -
        -- and at turbo 3 a frame covers 4/3 of a tick, so the press or release
        -- that completes a command routinely had nowhere to go. Measured over
        -- 19 guard cancels: the qualifying edge was drawn 3 times and lost 16
        -- (analysis/gc_success_probe_20260915b.log).
        --
        -- p1_tick_seq is incremented once per game tick by the hook in
        -- guardCancel.lua, and is monotonic - $FF8081 is a byte and wraps, so
        -- it cannot be used for this directly. The fallback keeps the offline
        -- tests and any load order without that hook working on the old clock.
        local _seq = globals and globals.p1_tick_seq
        frame_number = _seq or emu.framecount()
        -- local _input = joypad.get()
        -- THE GUARD CANCEL STATE COMES FROM THE TICK HOOK WHEN THERE IS ONE.
        --
        -- Working it out here means one answer for the whole displayed frame,
        -- stamped onto every column that frame produces. That was invisible
        -- while a frame made one column; with columns per tick it puts SUCCESS
        -- on the first tick of the frame instead of the tick the cancel came
        -- out on. guardCancel.lua decides it per tick and sends the answer down
        -- with the input, so this only runs when that hook is not there.
        local was_gc_event = false
        if _seq == nil then
            was_gc_event = handle_gc_event()
        end
        -- local was_pb_event = handle_pb_event()
        -- local was_hit_spark_event = handle_hit_spark_event()
        -- handle_post_hitspark_event()
        -- handle_idle_event(was_gc_event, was_pb_event,_was_hit_spark_event)

        if globals.show_menu ~= true then
            -- THE TICKS THIS FRAME DID NOT SEE, IN ORDER, BEFORE THE READING
            -- THIS FRAME DOES SEE.
            --
            -- Each queued entry carries the tick it was captured on, and
            -- frame_number is wound back to it so the column lands on that tick
            -- rather than all of them collapsing into the current one. The
            -- queue only receives ticks on which the input or the guard cancel
            -- window CHANGED, so a held direction still produces one column -
            -- what is added is exactly what used to be lost.
            local _q = globals.p1_tick_inputs
            if _q ~= nil and #_q > 0 then
                for _, _raw in ipairs(_q) do
                    frame_number = _raw.seq or frame_number
                    -- The window state as of THAT tick, so the column carries
                    -- the label belonging to it.
                    if _raw.gc ~= nil then globals.gc_event = _raw.gc end
                    -- nil on every tick but the one the cancel came out
                    -- on, which is how the label clears itself.
                    globals.gc_ticks = _raw.gct
                    update_input_history(input_history[1], "P1", _input, false, nil, _raw)
                end
                globals.p1_tick_inputs = {}
                frame_number = _seq or emu.framecount()
            end

            -- After the drain, so the event row carries the settled state
            -- rather than the one this frame started with.
            update_input_history(input_history[1], "P1", _input, true, {})
            update_input_history(input_history[1], "P1", _input)
            update_input_history(input_history[2], "P2", _input)
            history_update()
            return
        end
    end,
    ["guiRegister"] = function(_i)
        -- local _i = joypad.get()
		
      local _p1 = make_input_history_entry("P1", _i)
      local _p2 = make_input_history_entry("P2", _i)
      globals.p1 = _p1
      globals.p2 = _p2 
		-- gui.rect(p1_inp_disp_x,p1_inp_disp_y ,p1_inp_disp_x + 35 ,p1_inp_disp_y + 10,"#000000")
		-- gui.rect(p2_inp_disp_x,p1_inp_disp_y ,p2_inp_disp_x + 35 ,p1_inp_disp_y + 10,"#000000")

		-- draw_input_history_entry(_p1, p1_inp_disp_x, p1_inp_disp_y)
		-- draw_input_history_entry(_p2, p2_inp_disp_x, p2_inp_disp_y)

		local input_underlay_x = 0
		local input_underlay_y = emu.screenheight() - 21
		gui.box(input_underlay_x, input_underlay_y, emu.screenwidth(), input_underlay_y + 25 ,"#00000099", "#00000055")

	history_draw_candidate = input_history[1]
	if globals.options.skip_nedge_displays then
		history_draw_candidate = remove_nedge_events(input_history[1])
	end
        draw_input_history(history_draw_candidate, emu.screenwidth() - 15 + globals.options.inp_history_scroll, input_underlay_y + 2, true)

        -- history_draw()
    end,
    ["get_history_p1"] = function()
      return p1_input_history_producer
    end,
    ["get_history_p2"] = function()
      return p2_input_history_producer
    end,
}
return inpHistoryModule
