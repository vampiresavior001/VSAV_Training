-- menu
-- Centralized palette only. Layout, font, row height, labels, and input handling
-- stay unchanged in this acceptance stage.
local MENU_STYLE = {
  text = 0xF7FFF7FF,
  text_outline = 0x101008FF,
  selected_text = 0xFFFF00FF,
  disabled_text = 0x909090FF,
  panel_fill = 0x101018E8,
  panel_outline = 0x606878FF,
}
text_default_color = MENU_STYLE.text
text_default_border_color = MENU_STYLE.text_outline
text_selected_color = MENU_STYLE.selected_text
text_disabled_color = MENU_STYLE.disabled_text
-- The panel colours are exported the same way the text ones are, so a module
-- that draws its own full-screen panel (the action sequence editor) matches
-- this one without copying the values and drifting from them.
panel_fill_color = MENU_STYLE.panel_fill
panel_outline_color = MENU_STYLE.panel_outline
charMovesModule   = require "./scripts/charMoves"
actionSequenceEditorModule = require "./scripts/actionSequenceEditor"
actionSequenceRunnerModule = require "./scripts/actionSequenceRunner"
positionModule    = require "./scripts/position"
-- A DIAGONAL IS NOT A MENU DIRECTION.
--
-- The four direction blocks in the menu are independent and they do different
-- jobs: a vertical moves the cursor down the rows, a horizontal changes the
-- value ON the row. Held together they both fire on the same frame, so a stick
-- passing through down-right walks the list AND edits a setting in one motion,
-- with nothing on screen to say the second thing happened (user, 2026-09-23).
--
-- So a direction counts only while its own axis is the only one held. Both are
-- dropped while the stick sits on a diagonal, and coming back to a cardinal is
-- what lets one through again.
--
-- PER PAD, NOT ACROSS THE TWO. 1P holding Down while 2P pushes Right is two
-- players, not a diagonal - either stick drives this menu, and testing them
-- together would let one player's hold lock the other one out.
--
-- BUTTONS ARE NOT FILTERED. Confirm and cancel still answer with the stick on
-- a diagonal. Only what moves the cursor is dropped.
local MENU_CROSS_AXIS = {
  up    = { "left", "right" },
  down  = { "left", "right" },
  left  = { "up",   "down"  },
  right = { "up",   "down"  },
}
function menu_input_crossed(_player_object, _input)
  local _other = MENU_CROSS_AXIS[_input]
  if _other == nil then return false end
  local _down = _player_object and _player_object.input
                and _player_object.input.down
  if _down == nil then return false end
  -- == true rather than truthiness: the offline harnesses build these sets
  -- with the keys they are driving and leave every other one nil.
  return _down[_other[1]] == true or _down[_other[2]] == true
end
function check_input_down_autofire(_player_object, _input, _autofire_rate, _autofire_time)
  if menu_input_crossed(_player_object, _input) then return false end
  _autofire_rate = _autofire_rate or 4
  -- A RATE OF ZERO TURNED THE HOLD OFF, SILENTLY.
  --
  -- The test below is `state_time % rate == 0`, and in Lua 5.1 `23 % 0` is nan.
  -- nan equals nothing, not even zero, so the branch could never be taken: the
  -- row moved one step per press and holding did nothing at all. Five rows were
  -- built with a 0 - Loop Wait, Guard Action Delay, GC Input Delay, Scroll
  -- Input Viewer and Game Speed - and every one of them had no hold.
  --
  -- Zero reads as "as fast as it goes", which is the only thing it can sensibly
  -- have meant on a row that runs to 120. One is that: a step every frame once
  -- the hold has been held long enough to count as one.
  if _autofire_rate < 1 then _autofire_rate = 1 end
  _autofire_time = _autofire_time or 23
  if _player_object.input.pressed[_input] or (_player_object.input.down[_input] and _player_object.input.state_time[_input] > _autofire_time and (_player_object.input.state_time[_input] % _autofire_rate) == 0) then
    return true
  end
  return false
end

function gauge_menu_item(_name, _object, _property_name, _unit, _fill_color, _gauge_max, _subdivision_count)
  local _o = {}
  _o.name = _name
  _o.object = _object
  _o.property_name = _property_name
  _o.player_id = _player_id
  _o.autofire_rate = 1
  _o.unit = _unit or 2
  _o.gauge_max = _gauge_max or 0
  _o.subdivision_count = _subdivision_count or 1
  _o.fill_color = _fill_color or 0x0000FFFF

  function _o:draw(_x, _y, _selected)
    local _c = text_default_color
    local _prefix = ""
    local _suffix = ""
    if _selected then
      _c = text_selected_color
      _prefix = "< "
      _suffix = " >"
    end
    gui.text(_x, _y, _prefix..self.name.." : ", _c, text_default_border_color)

    local _box_width = self.gauge_max / self.unit
    local _box_top = _y + 1
    local _box_left = _x + get_text_width("< "..self.name.." : ") - 1
    local _box_right = _box_left + _box_width
    local _box_bottom = _box_top + 4
    gui.box(_box_left, _box_top, _box_right, _box_bottom, text_default_color, text_default_border_color)
    local _content_width = self.object[self.property_name] / self.unit
    gui.box(_box_left, _box_top, _box_left + _content_width, _box_bottom, self.fill_color, 0x00000000)
    for _i = 1, self.subdivision_count - 1 do
      local _line_x = _box_left + _i * self.gauge_max / (self.subdivision_count * self.unit)
      gui.line(_line_x, _box_top, _line_x, _box_bottom, text_default_border_color)
    end

    gui.text(_box_right + 2, _y, _suffix, _c, text_default_border_color)
  end

  function _o:left()
    self.object[self.property_name] = math.max(self.object[self.property_name] - self.unit, 0)
  end

  function _o:right()
    self.object[self.property_name] = math.min(self.object[self.property_name] + self.unit, self.gauge_max)
  end

  function _o:reset()
    self.object[self.property_name] = 0
  end

  function _o:legend()
    return "MP: Reset to default"
  end

  return _o
end

available_characters = {
  " ",
  "A",
  "B",
  "C",
  "D",
  "E",
  "F",
  "G",
  "H",
  "I",
  "J",
  "K",
  "L",
  "M",
  "N",
  "O",
  "P",
  "Q",
  "R",
  "S",
  "T",
  "U",
  "V",
  "X",
  "Y",
  "Z",
  "0",
  "1",
  "2",
  "3",
  "4",
  "5",
  "6",
  "7",
  "8",
  "9",
  "-",
  "_",
}

function textfield_menu_item(_name, _object, _property_name, _default_value, _max_length)
  _default_value = _default_value or ""
  _max_length = _max_length or 16
  local _o = {}
  _o.name = _name
  _o.object = _object
  _o.property_name = _property_name
  _o.default_value = _default_value
  _o.max_length = _max_length
  _o.edition_index = 0
  _o.is_in_edition = false
  _o.content = {}

  function _o:sync_to_var()
    local _str = ""
    for i = 1, #self.content do
      _str = _str..available_characters[self.content[i]]
    end
    self.object[self.property_name] = _str
  end

  function _o:sync_from_var()
    self.content = {}
    for i = 1, #self.object[self.property_name] do
      local _c = self.object[self.property_name]:sub(i,i)
      for j = 1, #available_characters do
        if available_characters[j] == _c then
          table.insert(self.content, j)
          break
        end
      end
    end
  end

  function _o:crop_char_table()
    local _last_empty_index = 0
    for i = 1, #self.content do
      if self.content[i] == 1 then
        _last_empty_index = i
      else
        _last_empty_index = 0
      end
    end

    if _last_empty_index > 0 then
      for i = _last_empty_index, #self.content do
        table.remove(self.content, _last_empty_index)
      end
    end
  end

  function _o:draw(_x, _y, _selected)
    local _c = text_default_color
    local _prefix = ""
    local _suffix = ""
    if self.is_in_edition then
      _c =  0xFFFF00FF
    elseif _selected then
      _c = text_selected_color
    end

    local _value = self.object[self.property_name]

    if self.is_in_edition then
      local _cycle = 100
      if ((frame_number % _cycle) / _cycle) < 0.5 then
        gui.text(_x + (#self.name + 3 + #self.content - 1) * 4, _y + 2, "_", _c, text_default_border_color)
      end
    end

    gui.text(_x, _y, _prefix..self.name.." : ".._value.._suffix, _c, text_default_border_color)
  end

  function _o:left()
    if self.is_in_edition then
      self:reset()
    end
  end

  function _o:right()
    if self.is_in_edition then
      self:validate()
    end
  end

  function _o:up()
    if self.is_in_edition then
      self.content[self.edition_index] = self.content[self.edition_index] + 1
      if self.content[self.edition_index] > #available_characters then
        self.content[self.edition_index] = 1
      end
      self:sync_to_var()
      return true
    else
      return false
    end
  end

  function _o:down()
    if self.is_in_edition then
      self.content[self.edition_index] = self.content[self.edition_index] - 1
      if self.content[self.edition_index] == 0 then
        self.content[self.edition_index] = #available_characters
      end
      self:sync_to_var()
      return true
    else
      return false
    end
  end

  function _o:validate()
    if not self.is_in_edition then
      self:sync_from_var()
      if #self.content < self.max_length then
        table.insert(self.content, 1)
      end
      self.edition_index = #self.content
      self.is_in_edition = true
    else
      if self.content[self.edition_index] ~= 1 then
        if #self.content < self.max_length then
          table.insert(self.content, 1)
          self.edition_index = #self.content
        end
      end
    end
    self:sync_to_var()
  end

  function _o:reset()
    if not self.is_in_edition then
      _o.content = {}
      self.edition_index = 0
    else
      if #self.content > 1 then
        table.remove(self.content, #self.content)
        self.edition_index = #self.content
      else
        self.content[1] = 1
      end
    end
    self:sync_to_var()
  end

  function _o:cancel()
    if self.is_in_edition then
      self:crop_char_table()
      self:sync_to_var()
      self.is_in_edition = false
    end
  end

  function _o:legend()
    if self.is_in_edition then
      return "LP/Right: Next   MP/Left: Previous   LK: Leave edition"
    else
      return "LP: Edit   MP: Reset to default"
    end
  end

  _o:sync_from_var()
  return _o
end

-- A CHECKBOX IS A BOOLEAN, AND 0 IS TRUE IN LUA.
--
-- These rows were built with 1 / 0 / true / false as the default at different
-- times, and one was built with its help text there by mistake. reset() wrote
-- that literal straight back, so MP could leave a row holding 1 - which draws
-- as "yes" while every consumer, all of which ask for == true, sees it as off.
-- The Scrolling Input rows disappeared that way: the parent read "yes" and the
-- three rows under it were hidden (user, 2026-09-14).
local function as_switch(_v)
  return _v ~= nil and _v ~= false and _v ~= 0
end

function checkbox_menu_item(_name, _object, _property_name, _default_value, description)
  _default_value = as_switch(_default_value)
  local _o = {}
  _o.name = _name
  _o.object = _object
  _o.property_name = _property_name
  _o.default_value = _default_value

  function _o:draw(_x, _y, _selected)
    local _c = text_default_color
    local _prefix = ""
    local _suffix = ""
    if _selected then
      _c = text_selected_color
      _prefix = "< "
      _suffix = " >"
    end

    -- Settings files written before the coercion above still carry 1 and 0, so
    -- the row heals what it is about to draw rather than drawing a lie.
    local _held = self.object[self.property_name]
    if type(_held) ~= "boolean" then
      _held = as_switch(_held)
      self.object[self.property_name] = _held
    end
    local _value = ""
    if _held then
      _value = "yes"
    else
      _value = "no"
    end
    gui.text(_x, _y, _prefix..self.name.." : ".._value.._suffix, _c, text_default_border_color)
  end

  function _o:left()
    self.object[self.property_name] = not self.object[self.property_name]
  end

  function _o:right()
    self.object[self.property_name] = not self.object[self.property_name]
  end

  function _o:reset()
    self.object[self.property_name] = self.default_value
  end

  function _o:legend()
    return "MP: Reset to default"
  end
  function _o:description()
    if description then
      return description
    else
      return ""
    end
  end
  return _o
end

function list_menu_item(_name, _object, _property_name, _list, _default_value, _item_description, _default_description )
  if _default_value == nil then _default_value = 1 end
  local _o = {}
  _o.name = _name
  _o.object = _object
  _o.property_name = _property_name
  _o.list = _list
  _o.default_value = _default_value

  function _o:draw(_x, _y, _selected)
    local _c = text_default_color
    local _prefix = ""
    local _suffix = ""
    if _selected then
      _c = text_selected_color
      _prefix = "< "
      _suffix = " >"
    end
    -- A VALUE OUTSIDE THE LIST HEALS ITSELF HERE.
    --
    -- pb_type_rec shipped as 0 against a 1-based list, so the row read
    -- "Push Block Type (PB Recording) : nil" and Left took it to -1, -2, ... -
    -- the wrap below only fires on exactly 0. Every settings file written
    -- before this carries that 0, so the fix has to be on the way out, not
    -- only in config.lua.
    local _v = self.object[self.property_name]
    if type(_v) ~= "number" or _v < 1 or _v > #self.list then
      _v = self.default_value
      self.object[self.property_name] = _v
    end
    gui.text(_x, _y, _prefix..self.name.." : "..tostring(self.list[_v]).._suffix, _c, text_default_border_color)
  end

  function _o:left()
    self.object[self.property_name] = self.object[self.property_name] - 1
    if self.object[self.property_name] < 1 then
      self.object[self.property_name] = #self.list
    end
  end

  function _o:right()
    self.object[self.property_name] = self.object[self.property_name] + 1
    if self.object[self.property_name] > #self.list then
      self.object[self.property_name] = 1
    end
  end

  function _o:reset()
    self.object[self.property_name] = self.default_value
  end

  function _o:legend()
    return "MP: Reset to default"
  end

  function _o:description()
    if type(_item_description) == "table" then
      if _item_description[self.object[self.property_name]] ~= nil then
        return _item_description[self.object[self.property_name]]
      elseif _default_description then
        return _default_description
      else 
        return "" 
      end
    elseif type(_item_description) == "string" then
      return _item_description
    elseif not _item_description and _default_description then
      return _default_description
    else
      return ""
    end
  end
  return _o
end

function integer_menu_item(_name, _object, _property_name, _min, _max, _loop, _default_value, _autofire_rate, description)
  if _default_value == nil then _default_value = _min end
  local _o = {}
  _o.name = _name
  _o.object = _object
  _o.property_name = _property_name
  _o.min = _min
  _o.max = _max
  _o.loop = _loop
  _o.default_value = _default_value
  _o.autofire_rate = _autofire_rate

  function _o:draw(_x, _y, _selected)
    local _c = text_default_color
    local _prefix = ""
    local _suffix = ""
    if _selected then
      _c = text_selected_color
      _prefix = "< "
      _suffix = " >"
    end
    gui.text(_x, _y, _prefix..self.name.." : "..tostring(self.object[self.property_name]).._suffix, _c, text_default_border_color)
  end

  function _o:left()
    self.object[self.property_name] = self.object[self.property_name] - 1
    if self.object[self.property_name] < self.min then
      if self.loop then
        self.object[self.property_name] = self.max
      else
        self.object[self.property_name] = self.min
      end
    end
  end

  function _o:right()
    self.object[self.property_name] = self.object[self.property_name] + 1
    if self.object[self.property_name] > self.max then
      if self.loop then
        self.object[self.property_name] = self.min
      else
        self.object[self.property_name] = self.max
      end
    end
  end

  function _o:reset()
    self.object[self.property_name] = self.default_value
  end

  function _o:legend()
    return "MP: Reset to default"
  end
  function _o:description()
    if description then
      return description
    else
      return ""
    end
  end
  return _o
end

function map_menu_item(_name, _object, _property_name, _map_object, _map_property)
  local _o = {}
  _o.name = _name
  _o.object = _object
  _o.property_name = _property_name
  _o.map_object = _map_object
  _o.map_property = _map_property

  function _o:draw(_x, _y, _selected)
    local _c = text_default_color
    local _prefix = ""
    local _suffix = ""
    if _selected then
      _c = text_selected_color
      _prefix = "< "
      _suffix = " >"
    end

    local _str = string.format("%s%s : %s%s", _prefix, self.name, self.object[self.property_name], _suffix)
    gui.text(_x, _y, _str, _c, text_default_border_color)
  end

  function _o:left()
    if self.map_property == nil or self.map_object == nil or self.map_object[self.map_property] == nil then
      return
    end

    if self.object[self.property_name] == "" then
      for _key, _value in pairs(self.map_object[self.map_property]) do
        self.object[self.property_name] = _key
      end
    else
      local _previous_key = ""
      for _key, _value in pairs(self.map_object[self.map_property]) do
        if _key == self.object[self.property_name] then
          self.object[self.property_name] = _previous_key
          return
        end
        _previous_key = _key
      end
      self.object[self.property_name] = ""
    end
  end

  function _o:right()
    if self.map_property == nil or self.map_object == nil or self.map_object[self.map_property] == nil then
      return
    end

    if self.object[self.property_name] == "" then
      for _key, _value in pairs(self.map_object[self.map_property]) do
        self.object[self.property_name] = _key
        return
      end
    else
      local _previous_key = ""
      for _key, _value in pairs(self.map_object[self.map_property]) do
        if _previous_key == self.object[self.property_name] then
          self.object[self.property_name] = _key
          return
        end
        _previous_key = _key
      end
      self.object[self.property_name] = ""
    end
  end

  function _o:reset()
    self.object[self.property_name] = ""
  end

  function _o:legend()
    return "MP: Reset to default"
  end

  return _o
end

function button_menu_item(_name, _validate_function)
  local _o = {}
  _o.name = _name
  _o.validate_function = _validate_function
  _o.last_frame_validated = 0

  function _o:draw(_x, _y, _selected)
    local _c = text_default_color
    if _selected then
      _c = text_selected_color

      if (frame_number - self.last_frame_validated < 5 ) then
        _c = 0xFFFF00FF
      end
    end

    gui.text(_x, _y,self.name, _c, text_default_border_color)
  end

  function _o:validate()
    self.last_frame_validated = frame_number
    if self.validate_function then
      self.validate_function()
    end
  end

  function _o:legend()
    return "LP: Validate"
  end

  return _o
end


-- A parent row whose Right action opens a child popup. The asymmetric
-- chevron is intentional: Left changes menu level upward; Right enters the
-- selected row's detail level.
--
-- Inside the popup the stick alone is enough: Left and Right are the value,
-- Up and Down are the row. Leaving is a row of its own rather than a direction,
-- because Left is spoken for. It sits at the bottom, where the wizard's slot
-- list already puts its way out, and so that opening the popup lands on a
-- value rather than on the exit.
function interval_popup_menu_item(_object)
  local _o = {}
  _o.name = "Loop Interval (Frames)"

  local function close_popup() current_popup = nil end

  -- Right is what opens this popup, and Right auto-repeats while held. Without
  -- a guard the same press that opens the child carries straight on into the
  -- row it lands on and starts adding to Before. Play Recording holds Right
  -- off for 15 frames for the same reason; this matches it.
  local opened_at = nil
  local function right_locked()
    return opened_at ~= nil and emu.framecount() - opened_at < 15
  end

  local function child(name, property, description)
    -- Left and Right are integer_menu_item's own decrement and increment, and
    -- MP its reset. Only the open guard is added.
    local item = integer_menu_item(name, _object, property, 0, 300, false, 0, nil, description)
    local _increase = item.right
    function item:right()
      if right_locked() then return end
      _increase(self)
    end
    function item:legend() return "Left: -   Right: +   MP: Reset" end
    return item
  end

  local function back_row()
    local _b = {}
    _b.name = "Back"
    function _b:draw(_x, _y, _selected)
      local c = _selected and text_selected_color or text_default_color
      gui.text(_x, _y, (_selected and "< " or "") .. self.name, c, text_default_border_color)
    end
    function _b:validate() close_popup() end
    function _b:left() close_popup() end
    -- Deliberately no Right. Right auto-repeats, and the parent row reopens on
    -- Right, so a held direction here would close the popup and open it again
    -- on the next repeat. Right also keeps one meaning that way: further in, or
    -- larger. Leaving is Left or LP.
    function _b:legend() return "Left or LP: Back" end
    function _b:description() return "Return to the menu." end
    return _b
  end

  function _o:draw(_x,_y,_selected)
    local c = _selected and text_selected_color or text_default_color
    local prefix = _selected and "< " or ""
    local before = tonumber(_object.loop_interval_before_frames) or 0
    local after = tonumber(_object.loop_interval_after_frames) or 0
    gui.text(_x,_y,prefix .. self.name .. " : (" .. before .. "/" .. after .. ")  >",c,text_default_border_color)
  end
  function _o:right()
    opened_at = emu.framecount()
    current_popup = make_popup(82,76,302,152,{
      child("Before", "loop_interval_before_frames", "Wait after Reset Distance Each Loop restores the recorded spacing,\nbefore the next playback begins."),
      child("After", "loop_interval_after_frames", "Wait after the previous playback and recovery, before spacing is reset."),
      back_row(),
    }, self.name)
    current_popup.selected_index = 1
  end
  function _o:validate() self:right() end
  function _o:left() end
  function _o:legend() return "Right/LP: Open details" end
  function _o:description()
    return "Repeat interval shown as (Before/After).\nRight opens the child settings, where the stick alone sets both\nvalues. Before is counted after Reset Distance Each Loop warps\nthe characters back."
  end
  return _o
end

-- _title is the name of the parent row. A popup on its own says Before and
-- After and nothing about what they belong to, which is fine while opening it
-- is still fresh and useless a moment later.
function make_popup(_left, _top, _right, _bottom, _entries, _title)
  local _p = {}
  _p.left = _left
  _p.top = _top
  _p.right = _right
  _p.bottom = _bottom
  _p.entries = _entries
  _p.title = _title

  return _p
end

dummy_neutral = {
    "None",
    "Down Back",
    "Down",
    "Down Forward",
    "Back",
    "Forward",
    "Up Back",
    "Up",
    "Up Forward"
}
gc_button = {
    "None",
    "Punch",
    "Kick",
    "Three Punch",
    "Three Kick"
}

roll_direction = {
    "None",
    "Towards",
    "Away",
    "Random (All)",
    "Random (Left/Right Only)"
}
guard_action_type = {
    "None",
    "Guard Cancel",
    "Push Block",
    "Reversal - Character Specific",
    "Reversal - Recording",
    "Reversal - Specified",
    "Counter Attack - Character Specific",
    "Counter Attack - Specified",
    "Counter Attack - Recording",
    "PB Recording",
    -- Appended, never inserted: the index is what the settings file stores.
    "Reversal - Action Steps",
    "Reversal - Action Patterns",
}

_push_block_type = {
    "None",
    "All Light (6 Presses)",
    "All Medium (6 Presses)",
    "All Heavy (6 Presses)",
    "Ascending (LP,LK,MP,MK,HP,HK)",
    "Descending (HP,HK,MP,MK,LP,LK)"
}
-- WHAT THE LEVER IS DOING WHEN THE BUTTON GOES IN.
--
-- The fourth part of the input description, beside Motion, Delay and Button.
-- The motion's own direction used to be whatever was still held at the press,
-- so a dash could only ever produce the dash attack - Bulleta's dash-neutral
-- MP had no way to come out at all. Neutral is the entry that unlocks that;
-- the eight directions cover things like Zabel's back jump into down MK.
--
-- Forward and Back are facing-relative and resolved at the moment of the
-- press, so playing on the right side needs no separate entries.
--
-- Character Specific reads a per-character table in guardCancel.lua, for the
-- cases where one lever is simply the answer for that character.
--
-- "As Is" is the default and changes nothing.
local counter_attack_lever = {
    "As Is",
    "Neutral",
    "Up",
    "Up Forward",
    "Forward",
    "Down Forward",
    "Down",
    "Down Back",
    "Back",
    "Up Back",
    -- Appended, never inserted: this setting is stored as an INDEX into this
    -- table, so anything added in the middle silently turns a saved choice
    -- into its neighbour.
}

local counter_attack_button = {
  "None",
  "LP",
  "LK",
  "MP",
  "MK",
  "HP",
  "HK",
  "MP+HP",
  "MK+HK",
  "LP+LK",
  "MP+MK",
  "HP+HK",
}

local counter_attack_stick = {
  "None",
  "Up",
  "Up Back",
  "Down Back",
  "Up Forward",
  "Down Forward",
  "QCF",
  "QCB",
  "HCF",
  "HCB",
  "DPF",
  "DPB",
  "360",
  -- "DQCF",
  "720",
  -- Forward before back. The pair used to read back-first, which is the wrong
  -- way round for a list people scan. Note this is an INDEX list: the chain in
  -- dummyState.lua that turns the index back into a string was swapped to
  -- match, and a saved "Back Dash" therefore reads as "Forward Dash" once.
  "Forward Dash",
  "Forward Dash Cancel",
  "Back Dash",
  "Back Dash Cancel",
  -- Down, then up - the direction rides on the UP half, which is what makes
  -- it a forward or back super jump. Placed here on purpose, next to the
  -- jumps and dashes. This is an INDEX list, so everything from Character
  -- Specific onwards shifted by three; utilities.lua migrates saved settings
  -- once, keyed on settings_version.
  "Super Jump Forward",
  "Super Jump",
  "Super Jump Back",
  "Character Specific",
  -- APPENDED, NOT INSERTED (v141).
  --
  -- The plain directions were missing from this list even though
  -- make_input_sequence has always handled them - so there was no way to ask
  -- for a bare forward+button or a crouching normal without a diagonal.
  --
  -- They go on the END on purpose: this setting is stored as an INDEX into
  -- this table, so inserting them anywhere else would silently turn a saved
  -- "QCF" into something adjacent and the next test would measure the wrong
  -- move without anyone noticing.
  "Forward",
  "Back",
  "Down"
  -- "HCharge",
  -- "VCharge",
  -- "Shun Goku Ratsu", -- Gouki hidden SA1
  -- "Kongou Kokuretsu Zan", -- Gouki hidden SA2
}

local counter_attack_random_upback = {
  "None",
  "25%",
  "50%",
  "75%",
  "100%",
}

gc_freq = {
    "None",
    "25%",
    "50%",
    "75%",
    "100%",
}
-- Same five as Guard Action Frequency and P2 Random Guard %, because it is the
-- same question asked about a different reaction, and the Dummy tab already
-- teaches the reader what None/25/50/75/100 means.
p2_throw_tech_chance = {
  "None",
  "25%",
  "50%",
  "75%",
  "100%",
}
p2_block_chance = {
  "None",
  "25%",
  "50%",
  "75%",
  "100%",
}
-- Drawn as the stage rather than described in words: 1 is you, 2 is the
-- dummy, | is the wall. Left/right on the lever walks along the stage.
stage_position = {
    "Off",
    "|12------|",
    "|21------|",
    "|---12---|",
    "|---21---|",
    "|------12|",
    "|------21|",
}
-- THE POSITION ROW'S BUTTONS (user, 2026-09-21).
--
-- Returning to the arrangement already stored meant picking another one and
-- back: the row changes the value to re-place, and position.lua's watcher
-- acts only on a CHANGE. So the row gets two shortcuts. LP is free on a list
-- row (there is no child to open); HP is free menu-wide (nothing dispatched
-- on it). MP keeps its reset. Off means leave everyone alone, so neither
-- shortcut does anything there - which is why reapply answers for the close
-- decision: no move, no menu close.
local position_menu_item = list_menu_item("Position", training_settings, "stage_position", stage_position, 1, "Places both characters on the stage. 1 is you, 2 is the dummy, | is the wall.\nWalls put the two touching; the middle puts them exactly where a round starts.\nOff leaves everyone alone. Left/Right pick an arrangement; the move starts\nonce the value has settled.\nLP places the pair at this setting again - practice walks them out of it.\nHP also closes the menu. Both do nothing on Off. MP resets to Off.")
function position_menu_item:validate() positionModule.reapply() end
function position_menu_item:hp()
	if positionModule.reapply() then togglemenu() end
end
function position_menu_item:legend()
	return "LP: Place again   MP: Reset   HP: Place + close"
end
guard = {
    "None",
    "Stand Block",
    "Auto Guard",
    "All Guard",
    -- Appended, never inserted: stored as an INDEX.
    --
    -- Push block belongs with HOW the dummy defends, not with what it does
    -- afterwards. Sitting in Guard Action Type it was exclusive with the
    -- counters, so "push block, then see what punishes" could not be set up at
    -- all - and that question (is a dash attack guaranteed after a push
    -- block?) is answered from the attacking side anyway, which is why this
    -- needs nothing from Guard Action Type.
    --
    -- The strength is part of the entry rather than a second row. The menu is
    -- only so wide, and a separate Push Block Type line for it was a row spent
    -- on three values.
    "Push Block (All Light)",
    "Push Block (All Medium)",
    "Push Block (All Heavy)"
}
input_event_type = {
  "None",
  "Guard Cancel",
  "Push Block"
}
recording_slot = {
  "Last Recording",
  "Slot 1",
  "Slot 2",
  "Slot 3",
  "Slot 4",
  "Slot 5",
}
anak_projectile = {
  "None",
  "Bulleta St.Hk",
  "Bulleta Missile",
  "Demitri Chaos Flare",
  "Morrigan Soul Fist",
  "Morrigan Air Soul Fist",
  "Anakaris Curse",
  "Aulbath Sonic Wave",
  "Lei-Lei Anki Oh",
  "Lillith Soul Flash",
  "Jedah Dio Sega"
}

-- This is for button or stick
local function check_for_counter_attack_disabled()
  return training_settings.guard_action ~= 6 and
          training_settings.guard_action ~= 8
end

local function check_for_gc_disabled()
  return training_settings.guard_action ~= 2 -- GC
end

local function check_for_pb_disabled_rev()
  return training_settings.guard_action ~= 0xA -- PB
end
local function check_for_pb_disabled()
  -- Only for the guard-action version. The Guard entries carry their own
  -- strength, so this row stays out of their way.
  return training_settings.guard_action ~= 0x3 -- PB
end

local pb_button_menu_item = list_menu_item("Push Block Type", training_settings, "pb_type", _push_block_type, 1, {
  "No push block will be performed",
  "A light Push block will be input.\n(lp, no input) x 6, one entry per Tick, so all six presses land\ninside the game's 14 Tick window.",
  "A medium Push block will be input.\n(mp, no input) x 6, one entry per Tick, so all six presses land\ninside the game's 14 Tick window.",
  "A heavy Push block will be input.\n(hp, no input) x 6, one entry per Tick, so all six presses land\ninside the game's 14 Tick window.",
  "An ascending push block will be input.\nSix presses, LP MP HP LK MK HK in order.",
  "A descending push block will be input.\nSix presses, heavy down to light."
})
pb_button_menu_item.is_disabled = check_for_pb_disabled

local pb_rev_button_menu_item = list_menu_item("Push Block Type (PB Recording)", training_settings, "pb_type_rec", _push_block_type, 1, {
  "No push block will be performed",
  "A light Push block will be input.\n(lp, no input) x 6, one entry per Tick, so all six presses land\ninside the game's 14 Tick window.",
  "A medium Push block will be input.\n(mp, no input) x 6, one entry per Tick, so all six presses land\ninside the game's 14 Tick window.",
  "A heavy Push block will be input.\n(hp, no input) x 6, one entry per Tick, so all six presses land\ninside the game's 14 Tick window.",
  "An ascending push block will be input.\nSix presses, LP MP HP LK MK HK in order.",
  "A descending push block will be input.\nSix presses, heavy down to light."
})
pb_rev_button_menu_item.is_disabled = check_for_pb_disabled_rev

local gc_button_menu_item = list_menu_item("Guard Cancel Button", training_settings, "gc_button", gc_button, 1,
      "The button the dummy presses for the guard cancel.\nThree Punch and Three Kick are the two button-pair guard cancels.")
gc_button_menu_item.is_disabled = check_for_gc_disabled

local counter_attack_stick_menu_item = list_menu_item("Reversal/Counter Input Motion", training_settings, "counter_attack_stick", counter_attack_stick, 1, "The motion to be input on reversal or counters.\nPlaced by the tick hook so the last entry lands on the actionable Tick,\nwhichever motion is chosen - it is no longer late by the number of inputs.")
counter_attack_stick_menu_item.is_disabled = check_for_counter_attack_disabled

local counter_attack_button_menu_item = list_menu_item("Reversal/Counter Button", training_settings, "counter_attack_button", counter_attack_button, 1, "In general the strength of move used\nIf stick is set to none this can be used as a counterpoke")
local counter_attack_lever_menu_item = list_menu_item("Reversal/Counter Button Lever", training_settings, "counter_attack_lever", counter_attack_lever, 1, "The lever held at the moment the BUTTON goes in. The motion itself is untouched.\nAs Is keeps whatever the motion ended on - for a dash that is the dash attack.\nNeutral releases it, which is how a dash-neutral normal comes out.\nOn a dash cancel this replaces the reverse direction, so the cancel will not\nhappen.")
counter_attack_button_menu_item.is_disabled = check_for_counter_attack_disabled
counter_attack_lever_menu_item.is_disabled = check_for_counter_attack_disabled

-- -1 IS "Auto" (v198).
--
-- The range starts one below zero so the item can carry a value that is not a
-- tick count. Auto means "use the character's own dash attack timing", which
-- only exists for a dash - for every other guard action it behaves as 0. The
-- point is that a dash attack works without the user looking anything up,
-- while still being a number they can take over at any time.
local guard_action_delay_menu_item = integer_menu_item(
      "Guard Action Delay (Ticks)", training_settings, "gc_delay", -1, 50, false, -1, 0,
      "How long after the MOTION the button is pressed, in game Ticks. The motion still\ncomes out at the earliest moment: Forward Dash + HP with 14 gives the fastest\ndash, then HP 14 Ticks later.\nAuto uses the character's own dash attack timing, and only means anything for a\ndash - anything else treats it as 0. Three displayed frames are four Ticks.\nMeasured after a GUARD; after a HIT it is not always enough (Morrigan, Jedah)."
    )
-- Auto EXISTS ONLY FOR THE FOUR DASH MOTIONS (v199).
--
-- It fills in a per-character dash timing, so on anything else there is
-- nothing for it to mean. Rather than show a setting that does nothing, the
-- item stops at 0 unless one of the dashes is selected, and a stored -1 left
-- over from a dash reads as 0 while some other motion is chosen.
--
-- Derived from the list by NAME rather than written as numbers. The setting is
-- stored as an index, so a hand-written index here would silently point at the
-- wrong motion the next time an entry is added - which is the same trap the
-- list's own comment warns about.
local AUTO_DASH_NAMES = {
  ["Back Dash"] = true, ["Back Dash Cancel"] = true,
  ["Forward Dash"] = true, ["Forward Dash Cancel"] = true,
}
local AUTO_DASH_INDEX = {}
for _i, _name in ipairs(counter_attack_stick) do
  if AUTO_DASH_NAMES[_name] then AUTO_DASH_INDEX[_i] = true end
end
local function auto_delay_available()
  return AUTO_DASH_INDEX[training_settings.counter_attack_stick] == true
end

-- integer_menu_item prints the raw number, and "-1" is not what -1 means here.
local _gad_draw = guard_action_delay_menu_item.draw
guard_action_delay_menu_item.draw = function(self, _x, _y, _selected)
  local _v = self.object[self.property_name] or 0
  if _v >= 0 then return _gad_draw(self, _x, _y, _selected) end
  local _c = text_default_color
  local _prefix, _suffix = "", ""
  if _selected then
    _c = text_selected_color
    _prefix, _suffix = "< ", " >"
  end
  -- NEVER SHOW THE RAW -1.
  --
  -- It is the stored value for Auto, not a delay, and it only means anything
  -- on a dash. On anything else the setting BEHAVES as 0 (kd_delay_ticks
  -- treats it that way), so 0 is what it has to read - a menu that says -1
  -- while the tool uses 0 is just wrong on screen. This is the state the tool
  -- starts in, since the default motion is not a dash.
  local _label = auto_delay_available() and "Auto" or "0"
  gui.text(_x, _y, _prefix..self.name.." : ".._label.._suffix, _c,
           text_default_border_color)
end

-- Stop at 0 rather than stepping onto Auto when it is not on offer.
local _gad_left = guard_action_delay_menu_item.left
guard_action_delay_menu_item.left = function(self)
  _gad_left(self)
  if not auto_delay_available() and (self.object[self.property_name] or 0) < 0 then
    self.object[self.property_name] = 0
  end
end

guard_action_delay_menu_item.is_disabled = function()
  return  training_settings.guard_action == 1 or -- None
          training_settings.guard_action == 9 or -- CA Record
          training_settings.guard_action == 5 or -- REV record
          training_settings.guard_action == 7 or -- CA char Specific
          training_settings.guard_action == 4 or -- REV char Specific
          training_settings.guard_action == 2 or -- GC (see gc_input_delay_menu_item below)
          -- A sequence carries its own waits, one per step. Two places to set
          -- the same thing is how they end up disagreeing.
          training_settings.guard_action == 0xB or
          training_settings.guard_action == 0xC
end

-- GC専用の任意フレーム入力ディレイ。共用の guard_action_delay_menu_item
-- (gc_delay) は「シーケンス先頭に Neutral を挿入する」方式で、GC 分岐は
-- 常に最速で queue されるため入力開始自体は遅らせられない - 詳細は
-- guardCancel.lua の service_gc_input_delay() の note を参照。
local gc_input_delay_menu_item = integer_menu_item(
      "GC Input Delay (Ticks)", training_settings, "gc_input_delay", 0, 50, false, 0, 0,
      "Holds the guard cancel back by this many game Ticks,\nto simulate human input speed. Not a frame count."
    )
gc_input_delay_menu_item.is_disabled = check_for_gc_disabled

local guard_action_frequency_menu_item = list_menu_item("Guard Action Frequency", training_settings, "gc_freq", gc_freq,1, "Use to randomize whether the guard action is performed")
guard_action_frequency_menu_item.is_disabled = function() return training_settings.guard_action == 1 end

function set_p1_reversal_names()
  return charMovesModule.get_player_movelists().P1.reversal_names
end
function set_p2_reversal_names()
  return charMovesModule.get_player_movelists().P2.reversal_names
end
-- NEITHER OF THESE TWO IS ON A TAB. get_menu() never lists them, so the P1
-- reversal hack has no way in from the menu at all - the settings exist and
-- charMoves fills the list, but nothing draws it. Left in place because the
-- feature is wired up everywhere else; it just needs an entry.
local p1_reversal_names = set_p1_reversal_names()
local p1_reversal_list_menu_item = list_menu_item("P1 Reversal List", training_settings, "p1_reversal_list", p1_reversal_names, 1)
local p1_reversal_strength_menu_item = list_menu_item("Reversal Strength", training_settings, "p1_reversal_strength", { "Light", "Medium","Heavy","ES"}, 1)

local function char_specific_reversal_is_disabled()
  return  training_settings.guard_action ~= 4 and
          training_settings.guard_action ~= 7
end
-- THE LIVE ONE IS IN guiRegister, NOT HERE. It rebuilds this item every frame
-- from the current character's move list and reassigns this same local BEFORE
-- calling get_menu(), so the name and description written here are never the
-- ones on screen - the tab shows "P2 Reversal List" with the code-hack
-- warning. Keep the two in step or edits here look like they did nothing.
local p2_reversal_names = set_p2_reversal_names()
local p2_reversal_list_menu_item = list_menu_item("P2 Reversal List", training_settings, "p2_reversal_list", p2_reversal_names, 1, nil, "These are 1f reversals triggered with code hacks. The inputs are not performed.\nPlease use caution! For instance throws cannot be done with lights\nEX should be done with the ES value")
p2_reversal_list_menu_item.is_disabled = char_specific_reversal_is_disabled
local p2_reversal_strength_menu_item = list_menu_item("Reversal Strength", training_settings, "p2_reversal_strength", { "Light", "Medium","Heavy","ES"}, 1, nil, "The strength of the reversal,\nPlease use normal game values (e.g. EX for EX moves)")
p2_reversal_strength_menu_item.is_disabled = char_specific_reversal_is_disabled
local p2_block_chance_menu_item = list_menu_item("P2 Random Guard %", training_settings, "p2_block_chance", p2_block_chance, 1, nil, "Randomize Blocking")
-- ENABLED EXACTLY WHERE THE VALUE IS STILL READ.
--
-- It was hidden on anything but Stand Block (2) and All Guard (4), but
-- autoguard.lua routes 2 and EVERYTHING FROM 4 UP through the same
-- dummy_guard, and that consults this chance before it holds Back:
--
--   if globals.options.guard == 2 or globals.options.guard >= 4 then
--
-- So Push Block (5/6/7) was being throttled by a row the player could not
-- see, and with the shipped default of "None" it never guarded and so never
-- pushed - reported as "push block does not happen when All Guard's random
-- guard is 0" (user, 2026-09-12). Hiding the row did not remove the
-- dependency, it only hid it.
p2_block_chance_menu_item.is_disabled = function()
	return training_settings.guard ~= 2 and training_settings.guard < 4
end

-- SHOWN ONLY WHEN GUARD ACTION TYPE IS "Reversal - Action Steps" (0xB).
--
-- The row used to carry no is_disabled at all, so it sat at the end of the
-- Dummy tab whatever the guard action was - and with the longer lists it was
-- the row that overflowed onto the second column. The menu hides disabled rows
-- and navigation skips them, so gating here removes the row from the list
-- instead of greying it. The saved list itself survives the switch: this gates
-- the ROW, not the data, and Guard Action Type = Reversal - Action Steps is
-- what shows it and runs it again.
local reversal_action_steps_item = actionSequenceEditorModule.parent_item("reversal", "Reversal Action Steps")
reversal_action_steps_item.is_disabled = function()
	return training_settings.guard_action ~= 0xB
end

-- THE LIBRARY SITS BESIDE THE LIST, GATED THE SAME WAY.
--
-- Same reason the row above is gated: the menu hides disabled rows and
-- navigation skips them, so this removes the row rather than greying it. The
-- saved patterns survive the switch - this gates the ROW, not the data.
local reversal_action_patterns_item =
	actionSequenceEditorModule.patterns_parent_item("reversal", "Reversal Action Patterns")
reversal_action_patterns_item.is_disabled = function()
	return training_settings.guard_action ~= 0xC
end

-- LOOP: THE LIST STARTS AGAIN WHEN IT ENDS.
--
-- Two rows, because they are two questions. Whether it repeats is a switch;
-- when the next pass starts is the same "when" a step's Wait answers, and it
-- keeps that row's vocabulary - Auto one step below zero, then a count.
local action_steps_loop_switch = checkbox_menu_item(
      "Loop Steps", training_settings, "action_steps_loop", false,
      "Runs the list again when it ends, until the guard action changes or a\nnew reversal arms.\nLoop Wait below says how long after the last step the first one comes\nback round."
    )

-- The ceiling is the editor's own WAIT_MAX: this value IS step one's wait on
-- every pass after the first (see the runner's LOOP_AUTO note).
-- Mirrors LOOP_LANDING in actionSequenceRunner. Named here so the row and
-- the runner cannot drift apart silently.
local LOOP_WAIT_LANDING = -2
local action_steps_loop_wait_item = integer_menu_item(
      "Loop Wait", training_settings, "action_steps_loop_wait", -2, 120, false, -1, 0,
      "How long after the last step the first one starts again, in game Ticks.\nAuto (After) starts it when the dummy can act - fine for a blocking drill,\nbut NOT the fastest: the input begins then, so a dash is three Ticks later.\nAuto (Landing) starts it so the first step arrives ON the touchdown, which\nis what a hop into an air normal needs to loop at full speed.\nA number lands the first step on that Tick, counted from the last one."
    )

-- Zero is not a supported loop boundary. Keep Auto at -1, but make Left and
-- Right move directly between Auto and 1 so zero cannot be selected in the UI.
local _aslw_left = action_steps_loop_wait_item.left
action_steps_loop_wait_item.left = function(self)
  _aslw_left(self)
  if self.object[self.property_name] == 0 then
    self.object[self.property_name] = -1
  end
end
local _aslw_right = action_steps_loop_wait_item.right
action_steps_loop_wait_item.right = function(self)
  _aslw_right(self)
  if self.object[self.property_name] == 0 then
    self.object[self.property_name] = 1
  end
end

-- integer_menu_item prints the raw number, and -1 is not a number of ticks.
-- Auto's bracket is the same question the editor's Wait row answers - the step
-- before the loop's first step is the LAST step of the list - so it carries a
-- count where there is one and After where there is not. Saying After over a
-- number would promise something the row does not do.
-- PIT OF BLAME IS NOT A REVERSAL, SO IT IS NOT A GUARD ACTION.
--
-- It is used while the OPPONENT is down, to swallow a follow-up hit, and the
-- ordinary reversal window opens far too late for that - which is why it has
-- had a trigger of its own in guardCancel from the start. Until now the only
-- way to reach that trigger was to pick the move in Character Specific
-- Reversal, which also meant giving up whatever else that setting was for.
--
-- One row of its own, so it can be on at the same time as any guard action.
-- Anakaris only: on anyone else the row would be a choice that changes
-- nothing, which is the rule the Air Dash list already follows.
local _pit_of_blame_type = {
    "None",
    "Normal",
    "ES",
}
local pit_of_blame_item = list_menu_item("Pit of Blame", training_settings, "pit_of_blame", _pit_of_blame_type, 1, {
  "Off.",
  "Anakaris swallows a follow-up hit while the opponent is down.\nOne kick.",
  "The ES version. Two kicks.\nCosts meter, and is the one that catches more.",
})
pit_of_blame_item.is_disabled = function()
	-- $382 is the character id the rest of the tool reads P2 by. 0x06 is
	-- Anakaris; Oboro and the boss forms are not him and get no row.
	return memory.readbyte(0xFF8B82) ~= 0x06
end

local _aslw_draw = action_steps_loop_wait_item.draw
action_steps_loop_wait_item.draw = function(self, _x, _y, _selected)
  local _v = self.object[self.property_name] or -1
  if _v >= 0 then return _aslw_draw(self, _x, _y, _selected) end
  -- -2 is Auto (Landing): the restart is timed off the touchdown rather than
  -- off the dummy becoming able to act. Kept above the Auto (After) branch
  -- because that one answers for every negative value.
  if _v == LOOP_WAIT_LANDING then
    local _cl = _selected and text_selected_color or text_default_color
    local _pl = _selected and "< " or ""
    local _sl = _selected and " >" or ""
    gui.text(_x, _y, _pl..self.name.." : Auto (Landing)".._sl, _cl,
             text_default_border_color)
    return
  end
  local _c = text_default_color
  local _prefix, _suffix = "", ""
  if _selected then
    _c = text_selected_color
    _prefix, _suffix = "< ", " >"
  end
  local _n = actionSequenceRunnerModule.loop_auto_ticks("reversal")
  local _label = (_n ~= nil) and ("Auto (".._n..")") or "Auto (After)"
  gui.text(_x, _y, _prefix..self.name.." : ".._label.._suffix, _c,
           text_default_border_color)
end

-- Gated with the row they belong to: the list is only reachable, and only runs,
-- under Reversal - Action Steps.
local function action_steps_rows_disabled()
	-- Both sources run the same list machinery, so the loop belongs to both.
	return training_settings.guard_action ~= 0xB
		and training_settings.guard_action ~= 0xC
end
action_steps_loop_switch.is_disabled = action_steps_rows_disabled
action_steps_loop_wait_item.is_disabled = action_steps_rows_disabled

--1 "None",
--2 "Guard Cancel",
--3 "Push Block",
--4 "Reversal - Character Specific",
--5 "Reversal - Recording",
--6 "Reversal - Specified",
--7 "Counter Attack- Character Specific",
--8 "Counter Attack - Specified",
--9 "Counter Attack - Recording",


local anak_menu_item = list_menu_item("Anak Projectile", training_settings, "anak_projectile", anak_projectile ,1, "Choose Which Projectile Anakaris has eaten")
anak_menu_item.is_disabled = function()
  return globals and globals.getCharacter(0xFF8400) ~= "Anakaris"
end
local lei_lei_stun_menu_item = checkbox_menu_item("Lei-Lei Always Stun Item", training_settings, "lei_lei_stun_item", false, "Lei-Lei will always toss a stun item")
lei_lei_stun_menu_item.is_disabled = function()
  return globals and globals.getCharacter(0xFF8400) ~= "Lei-Lei"
end
local lilith_gps_menu_item = integer_menu_item("Gloomy Puppet Show", training_settings, "lilith_gps", 0, 6, false, 0, nil, "Select which Gloomy Puppet Show Lilith will perform.\n0 = random")
lilith_gps_menu_item.is_disabled = function()
	return globals and globals.getCharacter(0xFF8400) ~= "Lilith"
end

local is_random_playback_on = function() return training_settings.random_playback == false end
local enable_slot_1_menu_item = checkbox_menu_item("Enable Slot 1", training_settings, "enable_slot_1", 0, "Enable this slot for random recording")
enable_slot_1_menu_item.is_disabled = is_random_playback_on 
local enable_slot_2_menu_item = checkbox_menu_item("Enable Slot 2", training_settings, "enable_slot_2", 0, "Enable this slot for random recording")
enable_slot_2_menu_item.is_disabled = is_random_playback_on
local enable_slot_3_menu_item = checkbox_menu_item("Enable Slot 3", training_settings, "enable_slot_3", 0, "Enable this slot for random recording")
enable_slot_3_menu_item.is_disabled = is_random_playback_on
local enable_slot_4_menu_item = checkbox_menu_item("Enable Slot 4", training_settings, "enable_slot_4", 0, "Enable this slot for random recording")
enable_slot_4_menu_item.is_disabled = is_random_playback_on
local enable_slot_5_menu_item = checkbox_menu_item("Enable Slot 5", training_settings, "enable_slot_5", 0, "Enable this slot for random recording")
local enable_slot_items = { enable_slot_1_menu_item, enable_slot_2_menu_item, enable_slot_3_menu_item,
                            enable_slot_4_menu_item, enable_slot_5_menu_item }
enable_slot_5_menu_item.is_disabled = is_random_playback_on

-- A ROW THAT ONLY MATTERS WHILE ANOTHER ROW IS ON.
--
-- Five settings do nothing at all unless their parent is on: the three that
-- live inside the scrolling input bar, the pushbox axis inside the hitbox
-- display, and the dummy's input column inside the HUD. Leaving them visible
-- while they cannot act is what made the Display tab read as a wall of
-- switches, and the draw loop already hides is_disabled rows and navigation
-- already skips them (see the Reversal Action Steps row on the Dummy tab).
--
-- The test is ~= true rather than a falsy check because that is how each
-- parent's OWN consumer reads it - hud() and render_hitboxes() and the
-- master script all ask for == true, so a leftover 1 in a settings file is
-- off for them and has to be off here too, or the row would be offered for a
-- parent that is not actually running.
local function child_of(_parent_property, _item)
  _item.is_disabled = function() return training_settings[_parent_property] ~= true end
  return _item
end


-- RESET A WHOLE TAB, AND IT FINDS OUT WHICH TAB IT IS ON BY ITSELF.
--
-- Every row here already resets on MP; what was missing was doing it to the
-- lot. The place for that is the tab it belongs to, not one tab that owns the
-- others - a tab that resets itself needs no owner, and the rows change in
-- front of you when you press it (user, 2026-09-23).
--
-- NO LIST OF ROWS. It is told which TAB it is on and resets whatever that
-- tab holds at the time, so a row added later is covered without anyone
-- remembering to add it anywhere. Naming the rows would be a second list to
-- keep in step, which is how the test list drifted and left four unrun.
--
-- THE TAB IS NAMED, NOT FOUND. It used to look itself up in menu, which
-- reads better and does not work: menu = get_menu() sits inside guiRegister,
-- so every row object is thrown away and remade EVERY DRAWN FRAME. The popup
-- is answered on a later frame than the one that opened it, and the row held
-- across that gap was an object that no longer existed anywhere in menu -
-- the lookup returned nil and the reset did nothing at all, silently (user,
-- 2026-09-23: the GC Frequency Counter row stayed on). A name survives the
-- rebuild. test_menu_reset_tab.lua checks each row's name against the tab it
-- actually sits in, so a renamed tab fails there rather than in front of
-- someone.
--
-- IT ASKS FIRST, ON EVERY WAY IN. Right, LP and MP all open the same two-row
-- popup rather than doing anything - MP included, because MP resets a single
-- row everywhere else in this menu and the muscle memory that goes with it
-- would wipe a tab (user, 2026-09-23).
--
-- THE STICK ALONE IS ENOUGH. Right opens it, Up/Down choose, Right confirms
-- and Left cancels, so nothing here needs a button. Right keeps its one
-- meaning throughout: further in.
--
-- IT LANDS ON CANCEL, AND RIGHT IS HELD OFF FOR FIFTEEN FRAMES. Right auto-
-- repeats while held, so the press that opens the popup would otherwise
-- carry straight on into the row it lands on - the same guard Play Recording
-- and the Loop Interval popup use. Landing on Cancel means even a repeat
-- that got through would close the popup rather than wipe the tab.
--
-- HIDDEN ROWS ARE RESET TOO. A row behind a parent switch still holds a
-- value and shows it again the moment the parent comes back on, so leaving
-- it alone would make the reset depend on what happened to be on screen.
local function reset_tab_item(_tab_name)
  local _o = {}
  _o.name = "Reset This Tab"
  -- Exposed so the test can hold it against the tab it is in.
  _o.tab_name = _tab_name
  local opened_at = nil
  local function right_locked()
    return opened_at ~= nil and emu.framecount() - opened_at < 15
  end
  -- BY NAME, BECAUSE THE ROWS DO NOT SURVIVE THE FRAME.
  --
  -- menu = get_menu() runs inside guiRegister, which runs every drawn frame,
  -- so every row object is rebuilt each frame. The popup is answered on a
  -- LATER frame than the one that opened it, and holding the row itself over
  -- that gap meant looking for an object that no longer existed anywhere in
  -- menu: tab_of returned nil and the reset did nothing at all, silently
  -- (user, 2026-09-23 - the GC Frequency Counter row stayed on).
  --
  -- The lookup still happens by identity, but on the frame of the press,
  -- where the row IS the one in menu. Only the tab's name crosses the gap.
  local function do_reset(_tab_name)
    for _, _tab in ipairs(menu) do
      if _tab.name == _tab_name then
        for _, _r in ipairs(_tab.entries) do
          if _r.name ~= "Reset This Tab" and _r.reset ~= nil then
            _r:reset()
          end
        end
        return
      end
    end
  end
  local function confirm_rows(_tab_name)
    local _ok = {}
    _ok.name = "OK"
    function _ok:draw(_x, _y, _selected)
      local c = _selected and text_selected_color or text_default_color
      gui.text(_x, _y, (_selected and "< " or "") .. self.name, c, text_default_border_color)
    end
    -- CLOSED FIRST, THEN THE WORK. Closing afterwards hid whether the reset
    -- touched this row too: its own reset opens the box, and clearing the
    -- popup on the way out threw that second box away again, so a reset that
    -- included itself was invisible. This way it would be left standing.
    function _ok:validate() current_popup = nil do_reset(_tab_name) end
    function _ok:right() if right_locked() then return end self:validate() end
    function _ok:legend() return "Right or LP: Reset the tab" end
    function _ok:description() return "" end
    local _no = {}
    _no.name = "Cancel"
    function _no:draw(_x, _y, _selected)
      local c = _selected and text_selected_color or text_default_color
      gui.text(_x, _y, (_selected and "< " or "") .. self.name, c, text_default_border_color)
    end
    function _no:validate() current_popup = nil end
    function _no:left() current_popup = nil end
    function _no:legend() return "Left or LP: Leave it alone" end
    function _no:description() return "" end
    return { _ok, _no }
  end
  local function ask()
    if right_locked() then return end
    opened_at = emu.framecount()
    current_popup = make_popup(92, 84, 292, 144, confirm_rows(_tab_name),
      "Reset " .. (_tab_name or "this tab") .. " to defaults?")
    -- Lands on Cancel. See the note above.
    current_popup.selected_index = 2
  end
  function _o:draw(_x, _y, _selected)
    local _c = text_default_color
    local _prefix, _suffix = "", ""
    if _selected then
      _c = text_selected_color
      _prefix, _suffix = "< ", " >"
    end
    gui.text(_x, _y, _prefix .. self.name .. _suffix, _c, text_default_border_color)
  end
  function _o:right() ask() end
  function _o:validate() ask() end
  -- MP asks as well. Everywhere else in this menu MP resets the row under the
  -- cursor outright, and that habit is the one that would cost a tab.
  function _o:reset() ask() end
  function _o:legend() return "Right / LP / MP: Asks before resetting" end
  function _o:description()
    return "Puts every row on this tab back to the value it ships with. It asks first -"
        .. "\nRight, LP and MP all open the same OK / Cancel box, which lands on Cancel."
        .. "\nIn the box: Up/Down choose, Right or LP confirms, Left cancels."
        .. "\nOnly this tab. The others are left alone."
        .. "\nRows hidden behind another setting are reset too - they are still holding a"
        .. "\nvalue, and it comes back into view when that setting is turned on."
  end
  return _o
end

local function get_menu() 
return {
    {
        name = "Recording",
        entries = {
          { name = "Play Recording",
            draw = function(_self, _x, _y, _selected)
              local _c = text_default_color
              local _label = _self.name
              local _st = globals.macroLua ~= nil and globals.macroLua.get_recording_status ~= nil
                          and globals.macroLua.get_recording_status() or nil
              if _st ~= nil and _st.playing then _label = _label .. "  (playing)" end
              if _selected then
                _c = text_selected_color
                _label = "< " .. _label .. " >"
              end
              gui.text(_x, _y, _label, _c, text_default_border_color)
            end,
            validate = function(_self)
              -- Right activates as well as LP, since Right is how you go into
              -- things elsewhere in this menu. Right auto-repeats while held
              -- though, and playcontrol() TOGGLES - a held direction would
              -- flicker playback on and off - so one activation per press.
              if _self.last_fired ~= nil and emu.framecount() - _self.last_fired < 15 then
                return
              end
              _self.last_fired = emu.framecount()
              -- playcontrol() is the same entry the playback hotkey uses, and
              -- it toggles: pressing this again while a macro runs stops it.
              if globals.macroLua ~= nil and globals.macroLua.playcontrol ~= nil then
                globals.macroLua.playcontrol()
              end
            end,
            right = function(_self) _self:validate() end,
            description = function()
              return "Play back the current recording slot, the same as the playback hotkey\n(Volume Down). LP or Right starts it; press again while running to stop it.\nWhich slot is used follows the slot settings below and Use Random Slot above."
            end },
          checkbox_menu_item("Use Character Specific Slots", training_settings, "use_character_specific_slots", true, "Recording slots are kept per dummy character, so picking a different dummy\ngives you a different set of five.\nOff uses one set of five for everybody.\nThis row had its property name and its default swapped and wrote nowhere, so\nit read 'no' while the feature was on - it ships on."),
          list_menu_item("Recording Slot", training_settings, "recording_slot", recording_slot,1,"Choose a playback/recording slot\nWill be overriden by random playback"),
          checkbox_menu_item("Looped Playback", training_settings, "looped_playback", 0, "The playback slot will be played back when the current recording ends\nThis works with random playback slots enabled below\nas well as with guard actions"),
          interval_popup_menu_item(training_settings),
          checkbox_menu_item("Reset Distance Each Loop", training_settings, "restore_recorded_position", 0, "Puts both characters back to the distance the recording was made from, at the\nstart of every loop. Without it the two drift apart over the passes and the\nsetup you were practising stops happening.\nOnly works on recordings made from v11.4.1 on - the distance is stored in the\nrecording itself.\nNot used with Use Savestate Upon Recording, which restores everything anyway."),
          checkbox_menu_item("Use Savestate Upon Recording", training_settings, "use_recording_savestate", 0, "BETA! EXPERIMENTAL! (But works!)\nCreates a savestate when you hit record, and loads it before playback.\nUse this for timing sensitive training. VERY USEFUL!!!!"),
          checkbox_menu_item("Use Random Recording Slot", training_settings, "random_playback", 0, "This can be used in two ways:\n 1) Random playback file on reversal\n 2) Using looped playback mode a random playback file will be \n    played back when the current recording ends"),
          enable_slot_1_menu_item,
          enable_slot_2_menu_item,
          enable_slot_3_menu_item,
          enable_slot_4_menu_item,
          enable_slot_5_menu_item,
          { name = "Recording Wizard",
            draw = function(_self, _x, _y, _selected)
              local _c = text_default_color
              local _prefix, _suffix = "", ""
              if _selected then
                _c = text_selected_color
                _prefix, _suffix = "< ", " >"
              end
              gui.text(_x, _y, _prefix .. _self.name .. _suffix, _c, text_default_border_color)
            end,
            validate = function()
              if globals.recordingWizard ~= nil then globals.recordingWizard.start() end
            end,
            -- Right goes in, same as LP. No repeat guard needed: start() does
            -- nothing unless the wizard is idle, and it closes the menu.
            right = function(_self) _self:validate() end,
            description = function()
              return "Guided dummy recording. LP or Right to begin. Pick a slot, control switches to\nP2, and recording starts on your first input.\nIt auto-stops after 2 seconds of the dummy standing still, then plays it back\nonce so you can check it.\nAt the prompt: LP saves, MP records again, LK plays again. Lua key 1 cancels.\nBoth return to their starting positions first, inputs mirrored if facing flips."
            end },
        }
      },
      {
        name = "Gauge",
        entries = {
          integer_menu_item("P1 Max Life", training_settings, "p1_max_life", 0, 288, false, 288, nil, "The value written to both life bars when the refill timer fires.\n288 is what the game itself starts a round with on the standard VITALITY\nsetting: it reads $FF815A, filled from a four entry table at ROM 0x0092B6\n(144 / 288 / 432 / 576) chosen by the cabinet's VITALITY dip.\nTwo bats is 288. A cabinet set to another entry starts somewhere else."),
          integer_menu_item("P1 Refill Timer (seconds)", training_settings, "p1_refill_timer", 0, 20, false, 1, nil,"This timer controls when the life meter will be refilled.\nOccurs this many seconds after being hit"),
          checkbox_menu_item("P1 Infinite Dark Force", training_settings, "p1_infinite_df", 0, "The darkforce timer will be held at a value.\nDeactivate to end!"),
          integer_menu_item("P2 Max Life", training_settings, "p2_max_life", 0, 288, false, 288, nil, "The value written to both life bars when the refill timer fires.\n288 is what the game itself starts a round with on the standard VITALITY\nsetting: it reads $FF815A, filled from a four entry table at ROM 0x0092B6\n(144 / 288 / 432 / 576) chosen by the cabinet's VITALITY dip.\nTwo bats is 288. A cabinet set to another entry starts somewhere else."),
          integer_menu_item("P2 Refill Timer (seconds)", training_settings, "p2_refill_timer", 0, 20, false, 1, nil, "This timer controls when the life meter will be refilled.\nOccurs this many seconds after being hit"),
          checkbox_menu_item("P2 Infinite Dark Force", training_settings, "p2_infinite_df", 0, "The darkforce timer will be held at a value.\nDeactivate to end!"),
        }
      },
    {
        name = "Dummy",
        entries = {
            position_menu_item,
            list_menu_item("Pose", training_settings, "dummy_neutral", dummy_neutral,1,"The dummy will hold this direction."),
            list_menu_item("Wakeup", training_settings, "roll_direction", roll_direction,1, "Determines which direction the dummy will roll on knockdown"),
            anak_menu_item,
            lilith_gps_menu_item,
            lei_lei_stun_menu_item,
            list_menu_item("Tech Throws", training_settings, "p2_throw_tech", p2_throw_tech_chance, 5, "How often the dummy escapes a throw.\nRolled once per throw, not per frame - a roll every frame would come out as\n100% whatever this said, which is what Guard Action Frequency used to do.\nNone leaves the throw alone."),
            list_menu_item("Guard", training_settings, "guard", guard,1, "Push Block (All ...) guards like All Guard and pushes, at that strength,\nwithout needing Guard Action Type - so that stays free for what you test next.\nAuto Guard writes the game's own guard flag, so it blocks everything,\nincluding unblockable setups.\nStand Block holds Back while an attack is in range; All Guard adds down, so\nlows are covered too. Both use the game's proximity check - projectiles too."),
            -- integer_menu_item("# Guard Frames", training_settings, "p2_refill_timer", 0, 20, false, 0, nil, "This timer controls when the life meter will be refilled.\nOccurs this many seconds after being hit"),

            p2_block_chance_menu_item,
            list_menu_item("Guard Action Type", training_settings, "guard_action", guard_action_type, 1, {
              --1 "None",
              --2 "Guard Cancel",
              --3 "Push Block",
              --4 "Reversal - Character Specific",
              --5 "Reversal - Recording",
              --6 "Reversal - Specified",
              --7 "Counter Attack - Character Specific",
              --8 "Counter Attack - Specified",
              --9 "Counter Attack - Recording",
              "No Guard Action will be performed",
              "The dummy will input a guard cancel manually.\nYou can delay this with the delay option in order to get later GC's\nYou can also set the frequency option to have it be performed randomly",
              "The dummy will input a push block manually.\nThe game counts button presses inside a 14 Tick window from the block\n($1AB, set to 14 at ROM 0x023966). Eight counted presses is guaranteed;\nbelow that the game rolls once per press.\nYou can delay this with the delay option in order to get later PB's.\nYou can also set the frequency option to have it be performed randomly.",
              "Specify a character specific special move.\nto be performed after the dummy hurt, block, or wakeup",
              "A recording will be played after the opponent guards, is hurt,\nor wakes up.\nThe recording played can be set in the 'Recording' tab.\nThis can be specified or random.",
              "Specify an input to be performed after the dummy hurt, block,\nor wakeup.",
              "USE AT YOUR OWN RISK (OFTEN CRASHES)\nA character specific special move, after the dummy blocks or is hit.",
              "Specify an action to be performed after the dummy blocks or is hit.\nSame timing machinery as Reversal, minus the wake-up.",
              "A recording will be played after the opponent finishes guarding.\nThe recording played can be set in the 'Recording' tab.\nThis can be specified or random.",
              "Play recording after pushblock",
              "Runs the list of steps set in 'Reversal Sequence', in order.\nEach step is one action and one answer to when it starts.\nThe first step's Wait replaces Guard Action Delay, so that row is off.",

            }, "Use this to set up various counter attacks."),
            guard_action_frequency_menu_item,
            counter_attack_stick_menu_item,
            counter_attack_button_menu_item,
            counter_attack_lever_menu_item,
            gc_button_menu_item,
            pb_button_menu_item,
            pb_rev_button_menu_item,
            guard_action_delay_menu_item,
            gc_input_delay_menu_item,
            p2_reversal_list_menu_item,
            p2_reversal_strength_menu_item,
            reversal_action_patterns_item,
            reversal_action_steps_item,
            action_steps_loop_switch,
            action_steps_loop_wait_item,
            pit_of_blame_item,
        }
    },
    {
      name = "Game",
      entries = {
        integer_menu_item("Game Speed", training_settings, "game_speed", 0, 3, false, 3, 0, "Change the game speed\n0 = normal, 1-3 = turbo 1-3"),
        checkbox_menu_item("BGM On", training_settings, "bgm_on", false, "Background music on or off.\nIt only takes proper effect after a trip through character select - switch it\nhere and the music comes back quiet. Return to Character Select below does\nthat, and so does Lua Hotkey 4."),
        list_menu_item("P1 Min PB Presses", training_settings, "min_pb_inputs", { "Normal", "4", "5", "6" }, 1, "How many presses YOU must make before a push block is allowed. P1 only - it\ndoes not make the dummy work harder.\nNormal leaves the game alone: it counts presses in a 14 Tick window and eight\nis a guaranteed push block, fewer is a roll per press.\n4/5/6 rewrite the count the game reads to zero whenever you pressed fewer than\nthat (ROM 0x02760E), so it rolls as if you had not pressed at all."),
        { name = "Return to Character Select",
          draw = function(_self, _x, _y, _selected)
            local _c = text_default_color
            local _prefix, _suffix = "", ""
            if _selected then
              _c = text_selected_color
              _prefix, _suffix = "< ", " >"
            end
            gui.text(_x, _y, _prefix .. _self.name .. _suffix, _c, text_default_border_color)
          end,
          validate = function(_self)
            -- Right auto-repeats while held and this tears the match down, so
            -- one go per press - the same guard the Play Recording row uses.
            if _self.last_fired ~= nil and emu.framecount() - _self.last_fired < 15 then
              return
            end
            _self.last_fired = emu.framecount()
            if globals ~= nil and globals.return_to_css ~= nil then globals.return_to_css() end
          end,
          right = function(_self) _self:validate() end,
          description = function()
            return "Ends the match and goes back to the character select screen, the same as\nLua Hotkey 4. LP or Right does it.\nRecordings stop, the recording savestate is dropped, and the trainer\nreadouts are cleared - none of them describe the next match."
          end },
      }
    },
    {
      name = "Display",
      entries = {
        -- checkbox_menu_item("Use Custom Palettes *at your own risk*", training_settings, "enable_custom_palette", "Shows Health and Meter values"),
        -- integer_menu_item("P1 Char Palette", training_settings, "p1_char_palette", 0, 255, false, 0,0,"Scroll through these on char select to see if you like one\nMany do not look good"),
        -- integer_menu_item("P2 Char Palette", training_settings, "p2_char_palette", 0, 255, false, 0,0,"Scroll through these on char select to see if you like one\nMany do not look good"),

        checkbox_menu_item("HUD (Life / Meter)", training_settings, "display_hud", true, "Red and white life for both players at the top of the screen, the meter, and\nthe character specific readouts - curse, Dark Force timer.\nTech hit has its own row under this one.\nThe trainers and the input bar are not part of this; they have their own rows."),
        child_of("display_hud", checkbox_menu_item("Show Tech Hit Mash", training_settings, "display_tech_hit", false, "Timer and Mash under the characters while the tech hit window is open - the\nraw $1AB and $170, straight from the game.\nShow PB Counter on this tab reads the same two bytes and draws them as a\nhistory, so this is the same information twice.\nPart of the HUD row above - it comes off with that as well.")),
        checkbox_menu_item("Movelist", training_settings, "display_movelist", false,"Shows a character specific move list"),
        checkbox_menu_item("Display Hitboxes", training_settings, "display_hitbox_default",1, "Display hitboxes for P1 and P2"),
        child_of("display_hitbox_default", checkbox_menu_item("Display Pushbox X Center", training_settings, "display_pushbox_axis", false, "Display the x center of the pushbox")),
        list_menu_item("Show Pushbox Distance", training_settings, "show_x_distance", { "Off", "X Only", "X,Y,Triangle"},1,"Gives a numerical / visual representation of the distances between characters"),
        checkbox_menu_item("Show Damage Calc (on P2)", training_settings, "show_damage_calc", false, "This shows a damage calculation.\nDamage calculations are recalculated on hit"),
        checkbox_menu_item("Recording GUI", training_settings, "display_recording_gui", false, "Shows the current recording staet"),
        checkbox_menu_item("Show Scrolling Input", training_settings, "show_scrolling_input",1, "The input bar along the bottom of the screen: YOUR inputs, newest at the right.\nShow P2 Inputs is the same thing for the dummy, down the right edge.\nThe four rows under this one all draw into this bar and come off with it."),
        child_of("show_scrolling_input", integer_menu_item("Scrolling Input History", training_settings, "inp_history_scroll", 0, 80, false, 0,0,"How far back into the Scrolling Input bar above to look. 0 is the newest input.\nRaising it slides the bar along so inputs that have gone off the left come\nback into view. It does not pause anything - new inputs still arrive.")),
        child_of("show_scrolling_input", checkbox_menu_item("Show Button Releases", training_settings, "show_button_releases", true, "Draws a hollow marker on the frame a button is let go, in its own one-frame\ncolumn. Off leaves presses and holds only, and a release just ends the column\nthe button was held in - the way the input bar read before the marker existed.\nHide Negative Edge Inputs below does not touch these columns.")),
        child_of("show_scrolling_input", checkbox_menu_item("Hide Negative Edge Inputs", training_settings, "skip_nedge_displays", true, "Hides the columns that carry nothing new: same direction as the one before and\nno button newly pressed - the clutter a release leaves behind.\nNot the release marker itself. Show Button Releases above owns that, and this\nrow leaves those columns alone.")),
        child_of("show_scrolling_input", checkbox_menu_item("Show GC Trainer", training_settings, "show_gc_trainer", true,"This option shows the GC window in the input viewer.\nThe Green GC shows when the window begins,\nand Red when it is performed or ends.")),
        checkbox_menu_item("Show P2 Inputs", training_settings, "display_p2_inputs", 1, "The dummy's inputs, as icons down the right edge of the screen.\nShow Scrolling Input above is the same thing for YOUR side, along the bottom.\nThis used to come off only with the whole HUD."),
        child_of("display_hud", checkbox_menu_item("Show Character Specific", training_settings, "display_char_specific", false, "Two readouts that exist for one character each, from before this menu had rows\nfor them: Anakaris's swallowed projectile, and Aulbath's Direct Scissors with\nits command lighting up green as 2,2 + PP goes in.\nNothing on screen says what either one is, which is why they ship off.\nPart of the HUD row above - it comes off with that as well.")),
        reset_tab_item("Display"),
      }
    },
    {
      name = "Trainer",
      entries = {
        checkbox_menu_item("Tick Data", training_settings, "mo_enable_frame_data", false, "Startup, active, recovery, advantage, total, hitstun, hitfreeze - in Ticks.\nThe first three come from the ATTACK HITBOX, the box the hitbox display draws,\nso they do not move with distance. They add up to Total and exclude the\nattacker's own hitfreeze; * means the attacker was not frozen.\nACTION TIMELINE (third row, green): one action on a clock, each entry stamped\nwith its Tick. LP..HK and Action Steps names. 1t PreJump > 4t Air > 10t MP."),
        child_of("mo_enable_frame_data", list_menu_item("Tick Data Side", training_settings, "mo_frame_data_side", { "P1", "P2" }, 1, "WHICH PLAYER the rows above measure. P1 is you.\nP2 measures the DUMMY: its move gets Startup / Active / Recovery, the Action\nTimeline follows what the DUMMY did, and YOUR side supplies the hit or guard\nit ran into. This is how to see what a recorded Action Steps pattern really\ncame out as.\nOne side at a time. Both readouts say P2 while it is on.")),
        checkbox_menu_item("Show Step Wait Ticks", training_settings, "display_step_wait_ticks", false,"Shows what each Action Step actually waited, in game Ticks.\nThe Wait row names a mode - Auto (After), Auto (Chain) - without saying how\nlong it came to. This measures it: Step.2 Wait:13 is step two connecting 13 Ticks\nafter step one. Act is the Ticks that step spends entering its own inputs.\nLoop Wait is the gap a loop restart waited, which is not step one own wait.\nMeasured only - what the row is set to is on the row."),
        checkbox_menu_item("Show PB Counter", training_settings, "display_pb_counter",1, "Push block presses the game counted ($170), plus any after it grants - a lucky\nthree would read three however hard you mash. Green once granted; the count\ncarries a blocked string. Right: the TICK timeline of the last window (Guard\nopens it, | closes it, digit = buttons that tick; 2+ red is simultaneous).\nMultiPush counts those. LateMash: buttons pressed AFTER the 14 ticks - they\nLEAK A NORMAL when guard stun ends. Cap 60t. The dummy shows as P2."),
        checkbox_menu_item("Show PB Stats", training_settings, "display_pb_stats", false,"Displays your succeeded, failed and total attempts at pushblocking.\n Turning this feature off and on will reset the data to 0"),
        checkbox_menu_item("Show GC Command Trace", training_settings, "display_gc_command_trace", false, "Every direction the GAME TOOK on the way to a guard cancel, with the tick it\ntook it, the button that finished it, and how it ended.\nDrawn once a guard happens - the motion is followed before that, so a command\nstarted early still shows. Numbers count from the input above, or from the\nguard or expiry once one of those cut the count. GC Expired is the 14 tick\nwindow running out. Cmd Expired is the motion not staying together."),
        checkbox_menu_item("Show GC Frequency Counter", training_settings, "display_gc_freq_counter", 0, "Counts what Guard Action Frequency actually did.\nopp = chances the dummy had, roll+ = how many the roll allowed,\narm = guard actions started, seq = later sequence steps sent.\nGreen when roll+/opp matches the setting. seq above opp means\nleftover steps from an earlier chance are still coming out."),
        checkbox_menu_item("Show Frame Trap Trainer", training_settings, "display_frame_trap_trainer", false,"Shows the gap between p2 recovering from hit or block stun\nand the next one, in game Ticks."),
        checkbox_menu_item("Show Jump In Trainer", training_settings, "display_jump_in_trainer", false,"Displays the gap between p2 getting hit and your character landing,\nin DISPLAYED frames - not game Ticks."),
        checkbox_menu_item("Show IAD Trainer", training_settings, "display_airdash_trainer", 0,"This option shows the HEIGHT of your last few aidashes.\nGreen is best! Red is Worst!"),
        checkbox_menu_item("Show Dashes Interval", training_settings, "display_dash_interval_trainer", 0,"Shows how many DISPLAYED frames between dashes - not game Ticks.\nGreen is best! Red is Worst!"),
        checkbox_menu_item("Show Dash Time", training_settings, "display_dash_length_trainer", 0,"Shows how many DISPLAYED frames you dashed for - not game Ticks.\nIf Sas then Smileys describe short hop success.\nGreen is best! Red is Worst!"),
        checkbox_menu_item("Show Dash Attack Cancel Trainer", training_settings, "display_dash_attack_cancel_trainer", false,"Shows the DISPLAYED frames between starting a dash\nand the start of an attack - not game Ticks.\nThis is printed under Dash ATK in the gui."),
        checkbox_menu_item("Show Attack Dash Gap Trainer", training_settings, "display_attack_dash_gap_trainer", false,"Shows the DISPLAYED frames between an attack recovering\nand the start of a dash - not game Ticks.\nThis is printed under Gap BTW ATK Dash in the gui."),
        checkbox_menu_item("Show Short Hop Counter (Sas)", training_settings, "display_short_hop_counter", false,"Shows how many short hops you.\nhave done in a row on Sasquatch"),
        checkbox_menu_item("Show Bishamon UBK Trainer", training_settings, "display_bishamon_ubk_trainer", false,"Overlays onto P2 whether you are in a crouch or standing\n unblockable distance for Karame Dama or Bricks"),
        reset_tab_item("Trainer"),
      }
    },
    {
      name = "Analysis",
      entries = {
        checkbox_menu_item("Show Invuln Timer", training_settings, "show_invuln_timer", false,"The invulnerability timer ($147), over each character's head: a green bar and\nthe number, labelled Inv. Counts down while the character cannot be hit.\nA raw value read straight from the game, not a measurement."),
        checkbox_menu_item("Show Throw Invuln Timer", training_settings, "show_throw_invuln_timer", false,"The throw invulnerability timer ($143), over each character's head, labelled\nThrow Inv. Counts down while a throw cannot connect.\nA raw value read straight from the game, not a measurement."),
        checkbox_menu_item("Show Mash Timer", training_settings, "show_mash_timer", false,"The mash timer ($15C), over each character's head: a cyan bar and the number,\nlabelled Mash. This is what mashing buttons counts down.\nA raw value read straight from the game, not a measurement."),
        checkbox_menu_item("Show Curse Timer", training_settings, "show_curse_timer", false,"The curse timer ($156), over each character's head, labelled Curse.\nCounts down while the character is cursed.\nA raw value read straight from the game, not a measurement."),
        checkbox_menu_item("Show PB Timer", training_settings, "show_pb_timer", false,"The push block window ($1AB), over each character's head, labelled PB.\nA blocked hit sets it to 14 (ROM 0x023966) and it counts down from there;\npresses are only counted while it is above zero.\nA raw value read straight from the game, not a measurement."),
        checkbox_menu_item("Show PB PushBack Timer", training_settings, "show_pb_pushback_timer", false,"The push block pushback timer ($1B0), over each character's head, labelled\nPB PushBack.\nA raw value read straight from the game. Show Hit Strength + PB PushBack\nprints the same two numbers at the top left instead of over the heads."),
        checkbox_menu_item("Show Pursuit Indicator", training_settings, "show_pursuit_indicator", false,"Opponent OK at the top left, from the game's pursuit (OTG) state.\nINCOMPLETE. Two of its three lines have never been drawn - the option that\nguards them exists nowhere - and the labels on the other two disagree about\nwhich side they describe.\nSee analysis/ISSUE-PURSUIT-INDICATOR-001.md before trusting it."),
        checkbox_menu_item("Show Hit Strength + PB PushBack", training_settings, "show_move_strength", false,"Four lines at the top left: the strength of the attack each character was last\nhit by ($59), and each one's push block pushback timer ($1B0).\nAdded while chasing a delayed-pushback bug. Raw values, no measurement."),
        checkbox_menu_item("Show Projectile Allocation", training_settings, "show_projectile_count_limiter", false,"The projectile allocation value ($FFF9BE) in hex, near the top of the screen.\nThe game's own budget for what can be on screen at once.\nA readout, not a limiter - nothing here changes the value."),
        checkbox_menu_item("Knockdown Logger", training_settings, "knockdown_logger_enable", false,"Writes a JSON trace of every recovery to scripts/reversal_logs.\nFor investigating timing. Leave it off unless you are measuring something -\nit writes a file per recovery."),
        reset_tab_item("Analysis"),
      }
    }
}
end


main_menu_selected_index = 1
is_main_menu_selected = true
sub_menu_selected_index = 1
current_popup = nil

-- Put each slot's capture time on its line. Read when the menu opens rather
-- than every frame: this touches five files, and the rows redraw at 60fps.
-- The seconds are dropped to keep the line short - os.date() is locale
-- dependent, so the stamp is otherwise shown exactly as the .mis header has
-- it ("1/10/2021 11:13 AM" or "2026/08/26 21:05").
local function refresh_slot_names()
	if enable_slot_items == nil then return end
	local wiz = globals.recordingWizard
	for i, item in ipairs(enable_slot_items) do
		local stamp = (wiz ~= nil and wiz.slot_stamp ~= nil) and wiz.slot_stamp(i) or nil
		if stamp == nil or stamp == "Empty" then
			item.name = "Enable Slot " .. i
		else
			item.name = "Enable Slot " .. i .. "  " .. stamp:gsub("(%d+:%d+):%d+", "%1")
		end
	end
end

function togglemenu()
	-- THE STEP EDITOR GETS TO ANSWER FIRST.
	--
	-- A draft only reaches training_settings on Save, so the root screen's two
	-- rows were the whole contract - Save keeps it, Back Without Saving drops
	-- it. This button went past both and dropped the edit silently. The editor
	-- raises its own screen and says it took the close; the rows on that screen
	-- come back through here after close(), when this guard no longer fires.
	if globals.show_menu and actionSequenceEditorModule.is_active()
	   and actionSequenceEditorModule.request_close ~= nil
	   and actionSequenceEditorModule.request_close() then
		return
	end
	-- Opening or closing the menu leaves the top level, so a child popup left
	-- open would still be there on the way back in.
	current_popup = nil
	globals.show_menu =  not globals.show_menu
	if globals.show_menu then
		refresh_slot_names()
		globals.controllerModule.disable_both_players()
	else 
		globals.controllerModule.enable_both_players()
		globals.inpHistoryModule.reset_inp_history_scroll()
		save_training_data_if_dirty()
	end
end
function togglegraphmenu()
  globals.show_graph_menu =  not globals.show_graph_menu
  if globals.show_graph_menu then
    globals.graph_data_index = 0
    globals.update_graph_data()
  end
end
function inc_graph()
  if globals.show_graph_menu then
    globals.graph_data_index = globals.graph_data_index + 1   
    globals.update_graph_data()
  end
end
function dec_graph()
  if globals.show_graph_menu then
      globals.graph_data_index = globals.graph_data_index - 1   
      globals.update_graph_data()
  end
end
local is_main_menu_selected = true
menuModule = {
    ["registerStart"] = function()
      return{
        togglemenu = togglemenu,
        togglegraphmenu = togglegraphmenu,
        inc_graph = inc_graph,
        dec_graph = dec_graph
      }
    end,
    ["guiRegister"] = function()
      p1_reversal_names = set_p1_reversal_names()
      p2_reversal_names = set_p2_reversal_names()
      p1_reversal_list_menu_item = list_menu_item("P1 Reversal List", training_settings, "p1_reversal_list", p1_reversal_names, 1, nil, "These are 1f reversals triggered with code hacks. The inputs are not performed.\nPlease use caution! For instance throws cannot be done with lights\nEX should be done with the ES value" )
      p2_reversal_list_menu_item = list_menu_item("P2 Reversal List", training_settings, "p2_reversal_list", p2_reversal_names, 1, nil, "These are 1f reversals triggered with code hacks. The inputs are not performed.\nPlease use caution! For instance throws cannot be done with lights\nEX should be done with the ES value")
      p2_reversal_list_menu_item.is_disabled = char_specific_reversal_is_disabled

      p2_reversal_strength_menu_item = list_menu_item("Reversal Strength", training_settings, "p2_reversal_strength", { "Light", "Medium","Heavy","ES"}, 1, nil, "The strength of the reversal,\nPlease use normal game values (e.g. EX for EX moves)")
      p2_reversal_strength_menu_item.is_disabled = char_specific_reversal_is_disabled
      
      menu = get_menu()
      
      if globals then
        globals.p1_current_move_list = p1_reversal_names
        globals.p2_current_move_list = p2_reversal_names
      end

        -- THE EDITOR REPLACES THIS PANEL WHILE IT IS OPEN.
        --
        -- Handled here rather than from the master's frame hook so the two read
        -- the pad at the same point in the frame. Reading it in both places
        -- would move the cursor twice for one press.
        if globals.show_menu and actionSequenceEditorModule.is_active() then
          actionSequenceEditorModule.registerBefore()
          actionSequenceEditorModule.guiRegister()
          gui.box(0,0,0,0,0,0)
          return
        end

        -- globals.show_menu = true
        if globals.show_menu then
          local _current_entry = menu[main_menu_selected_index].entries[sub_menu_selected_index]
      
          if current_popup then
            _current_entry = current_popup.entries[current_popup.selected_index]
          end
          local _horizontal_autofire_rate = 4
          local _vertical_autofire_rate = 4
          if not is_main_menu_selected then
            if _current_entry.autofire_rate then
              _horizontal_autofire_rate = _current_entry.autofire_rate
            end
          end
      
          function _sub_menu_down()
            sub_menu_selected_index = sub_menu_selected_index + 1
            _current_entry = menu[main_menu_selected_index].entries[sub_menu_selected_index]
            if sub_menu_selected_index > #menu[main_menu_selected_index].entries then
              is_main_menu_selected = true
            elseif _current_entry.is_disabled ~= nil and _current_entry.is_disabled() then
              _sub_menu_down()
            end
          end
      
          function _sub_menu_up()
            sub_menu_selected_index = sub_menu_selected_index - 1
            _current_entry = menu[main_menu_selected_index].entries[sub_menu_selected_index]
            if sub_menu_selected_index == 0 then
              is_main_menu_selected = true
            elseif _current_entry.is_disabled ~= nil and _current_entry.is_disabled() then
              _sub_menu_up()
            end
          end
      
          if check_input_down_autofire(player_objects[1], "down", _vertical_autofire_rate) or check_input_down_autofire(player_objects[2], "down", _vertical_autofire_rate) then
            if is_main_menu_selected then
              is_main_menu_selected = false
              sub_menu_selected_index = 0
              _sub_menu_down()
            elseif _current_entry.down and _current_entry:down() then
              mark_training_settings_dirty()
            elseif current_popup then
              current_popup.selected_index = current_popup.selected_index + 1
              if current_popup.selected_index > #current_popup.entries then
                current_popup.selected_index = 1
              end
            else
              _sub_menu_down()
            end
          end
      
          if check_input_down_autofire(player_objects[1], "up", _vertical_autofire_rate) or check_input_down_autofire(player_objects[2], "up", _vertical_autofire_rate) then
            if is_main_menu_selected then
              is_main_menu_selected = false
              sub_menu_selected_index = #menu[main_menu_selected_index].entries + 1
              _sub_menu_up()
            elseif _current_entry.up and _current_entry:up() then
                mark_training_settings_dirty()
            elseif current_popup then
              current_popup.selected_index = current_popup.selected_index - 1
              if current_popup.selected_index == 0 then
                current_popup.selected_index = #current_popup.entries
              end
            else
              _sub_menu_up()
            end
          end
      
          if check_input_down_autofire(player_objects[1], "left", _horizontal_autofire_rate) or check_input_down_autofire(player_objects[2], "left", _horizontal_autofire_rate) then
            if is_main_menu_selected then
              main_menu_selected_index = main_menu_selected_index - 1
              if main_menu_selected_index == 0 then
                main_menu_selected_index = #menu
              end
            elseif _current_entry.left then
              _current_entry:left()
              mark_training_settings_dirty()
            end
          end
      
          if check_input_down_autofire(player_objects[1], "right", _horizontal_autofire_rate) or check_input_down_autofire(player_objects[2], "right", _horizontal_autofire_rate) then
            if is_main_menu_selected then
              main_menu_selected_index = main_menu_selected_index + 1
              if main_menu_selected_index > #menu then
                main_menu_selected_index = 1
              end
            elseif _current_entry.right then
              _current_entry:right()
              mark_training_settings_dirty()
            end
          end
      
          if P1.input.pressed.LP or P2.input.pressed.LP then
            if is_main_menu_selected then
            elseif _current_entry.validate then
              _current_entry:validate()
              mark_training_settings_dirty()
            end
          end
      
          if P1.input.pressed.MP or P2.input.pressed.MP then
            if is_main_menu_selected then
            elseif _current_entry.reset then
              _current_entry:reset()
              mark_training_settings_dirty()
            end
          end
      
          if P1.input.pressed.LK or P2.input.pressed.LK then
            if is_main_menu_selected then
            elseif _current_entry.cancel then
              _current_entry:cancel()
              mark_training_settings_dirty()
            end
          end

      if P1.input.pressed.HP or P2.input.pressed.HP then
        if is_main_menu_selected then
        elseif _current_entry.hp then
          _current_entry:hp()
          mark_training_settings_dirty()
        end
      end
      
          -- screen size 383,223
          local _gui_box_bg_color = MENU_STYLE.panel_fill
          local _gui_box_outline_color = MENU_STYLE.panel_outline
          local _menu_box_left = 23
          local _menu_box_top = 15
          local _menu_box_right = 360
          -- TALLER BY TWELVE, FOR THE DESCRIPTION BLOCK.
          --
          -- The description is drawn from a fixed offset above this edge and
          -- the legend sits below it, which left room for four lines. Rows
          -- documented in more than four ran off the panel and over the input
          -- bar, unreadable, with no sign that anything was missing - the Tick
          -- Data row had twelve (user screenshot, 2026-09-13).
          --
          -- Six lines now: 150 to 190 inclusive, with the legend clear of them
          -- at 199. analysis/test_menu_layout.lua measures it and fails on a
          -- description that does not fit.
          local _menu_box_bottom = 207
          gui.box(_menu_box_left, _menu_box_top, _menu_box_right, _menu_box_bottom, _gui_box_bg_color, _gui_box_outline_color)
      
          local _bar_x = _menu_box_left + 10
          local _bar_y = _menu_box_top + 6
          local _base_offset = 0
          for i = 1, #menu do
            local _offset = 0
            local _c = text_disabled_color
            local _t = menu[i].name
            if is_main_menu_selected and i == main_menu_selected_index then
              _t = "< ".._t.." >"
              _c = text_selected_color
            elseif i == main_menu_selected_index then
              _c = text_default_color
              _offset = 8
            else
              _offset = 8
            end
            gui.text(_bar_x + _offset + _base_offset, _bar_y, _t, _c, text_default_border_color)
            _base_offset = _base_offset + (#menu[i].name + 5) * 4
          end
      
      
          local _menu_x = _menu_box_left + 10
          local _menu_y = _menu_box_top + 23
          local _menu_y_interval = 10
          local _menu_x_interval = 10
          local _menu_y_second_column = false
          local _draw_index = 0
          for i = 1, #menu[main_menu_selected_index].entries do            
            if menu[main_menu_selected_index].entries[i].is_disabled == nil or not menu[main_menu_selected_index].entries[i].is_disabled() then
              if _draw_index > 10 then _menu_x_interval = 150 else _menu_x_interval = 0 end
              if _draw_index > 10 then _menu_y_second_column = true else _menu_y_second_column = false end
              if not _menu_y_second_column then 
                menu[main_menu_selected_index].entries[i]:draw(_menu_x + _menu_x_interval, _menu_y + _menu_y_interval * _draw_index, not is_main_menu_selected and not current_popup and sub_menu_selected_index == i)
              else 
                menu[main_menu_selected_index].entries[i]:draw(_menu_x + _menu_x_interval, (_menu_y - 110) + _menu_y_interval * _draw_index, not is_main_menu_selected and not current_popup and sub_menu_selected_index == i)
              end 
              _draw_index = _draw_index + 1
            end
          end
      
          -- recording slots special display
          -- if main_menu_selected_index == 3 then
          --   local _t = string.format("%d frames", #recording_slots[training_settings.current_recording_slot].inputs)
          --   gui.text(_menu_box_left + 83, _menu_y + 2 * _menu_y_interval, _t, text_disabled_color, text_default_border_color)
          -- end
      
          if not is_main_menu_selected then
            if menu[main_menu_selected_index].entries[sub_menu_selected_index].legend then
              gui.text(_menu_x, _menu_box_bottom - 8, menu[main_menu_selected_index].entries[sub_menu_selected_index]:legend(), text_disabled_color, text_default_border_color)
            end
            if menu[main_menu_selected_index].entries[sub_menu_selected_index].description then
              local description = menu[main_menu_selected_index].entries[sub_menu_selected_index]:description()
              gui.text(_menu_x, _menu_box_bottom - 57, description, text_disabled_color, text_default_border_color)
            end
          end
      
          -- popup
          if current_popup then
            gui.box(current_popup.left, current_popup.top, current_popup.right, current_popup.bottom, _gui_box_bg_color, _gui_box_outline_color)
      
            _menu_x = current_popup.left + 10
            _menu_y = current_popup.top + 9
            _draw_index = 0

            if current_popup.title then
              gui.text(_menu_x, _menu_y, current_popup.title, text_selected_color, text_default_border_color)
              _menu_y = _menu_y + _menu_y_interval + 2
            end
      
            for i = 1, #current_popup.entries do
              if current_popup.entries[i].is_disabled == nil or not current_popup.entries[i].is_disabled() then
                current_popup.entries[i]:draw(_menu_x, _menu_y + _menu_y_interval * _draw_index, current_popup.selected_index == i)
                _draw_index = _draw_index + 1
              end
            end
      
            if current_popup.entries[current_popup.selected_index].legend then
              gui.text(_menu_x, current_popup.bottom - 12, current_popup.entries[current_popup.selected_index]:legend(), text_disabled_color, text_default_border_color)
            end
          end
      
        else
          gui.box(0,0,0,0,0,0) -- if we don't draw something, what we drawed from last frame won't be cleared
        end
    end
}

return menuModule
