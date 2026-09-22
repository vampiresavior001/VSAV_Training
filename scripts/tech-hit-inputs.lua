-- The numbered button sequences beside PB Stats, now fed from timers.lua's
-- tick-based push block marks (user, 2026-09-22).
--
-- WAS: its own hook at 0x02762a (PB success) reading the game's $170, which
-- freezes at the grant. PB Count counts presses made, including post-grant,
-- so the two disagreed whenever the PB was granted before the player stopped
-- pressing. Reading the same tick marks PB Count uses makes the row counts
-- agree by construction.
--
-- The display shows one numbered entry per press the tick timeline recorded,
-- with button icons parsed from the raw $126 edge mask that timers.lua also
-- publishes (p1_pb_raws).
--
-- This module no longer hooks anything: timers.lua owns the tick clock and
-- this only reads what it publishes.

local ICON_FILE = 'scrolling-input/capcom-8.png'
local BLANK_PNG_BYTES = {
  '0x89', '0x50', '0x4E', '0x47', '0x0D', '0x0A', '0x1A', '0x0A', '0x00',
  '0x00', '0x00', '0x0D', '0x49', '0x48', '0x44', '0x52', '0x00', '0x00',
  '0x00', '0x40', '0x00', '0x00', '0x00', '0x20', '0x01', '0x03', '0x00',
  '0x00', '0x00', '0x98', '0x53', '0xEC', '0xC7', '0x00', '0x00', '0x00',
  '0x03', '0x50', '0x4C', '0x54', '0x45', '0x00', '0x00', '0x00', '0xA7',
  '0x7A', '0x3D', '0xDA', '0x00', '0x00', '0x00', '0x01', '0x74', '0x52',
  '0x4E', '0x53', '0x00', '0x40', '0xE6', '0xD8', '0x66', '0x00', '0x00',
  '0x00', '0x0D', '0x49', '0x44', '0x41', '0x54', '0x18', '0x95', '0x63',
  '0x60', '0x18', '0x05', '0xF8', '0x00', '0x00', '0x01', '0x20', '0x00',
  '0x01', '0xBF', '0xC1', '0xB1', '0xA8', '0x00', '0x00', '0x00', '0x00',
  '0x49', '0x45', '0x4E', '0x44', '0xAE', '0x42', '0x60', '0x82'
}

local icons = {}

local png_str_from_bytes = function(bytes)
  local str = ''
  for _, b in pairs(bytes) do
    str = str .. string.char(b)
  end
  return str
end

local image_setup = function()
  local icon_sheet = gd.createFromPng(ICON_FILE)
  for i = 1,6 do
    local tmp = gd.createFromPngStr(png_str_from_bytes(BLANK_PNG_BYTES))
    gd.copyResampled(tmp, icon_sheet, 0, 0, 0, 8 * (8 + (i - 1)), 8, 8, 8, 8)
    icons[#icons + 1] = tmp:gdStr()
  end
end

image_setup()

---Converts a raw button edge mask ($126 & $77) into a list of button icon
---strings (1 = LP, 2 = MP, 3 = HP, 5 = LK, 6 = MK, 7 = HK; index 4 skipped)
---@param raw_mask number
---@return table
local parse_mask = function(raw_mask)
  local pressed = {}
  if raw_mask == nil or raw_mask <= 0 then return pressed end
  for i = 1, 7 do
    if i ~= 4 and math.floor(raw_mask / 2 ^ (i - 1)) % 2 == 1 then
      local icon
      if i < 4 then icon = icons[i] else icon = icons[i - 1] end
      pressed[#pressed + 1] = icon
    end
  end
  return pressed
end

-- A tick counts as a press when the mark is a digit (not "-") and the raw
-- mask is non-zero. The mark alone is not enough: a tick the ROM's gates
-- refused draws "-" but the mark might be a digit if the gates passed with
-- no edge (impossible, but the defensive check costs nothing).
local function is_press(mark, raw)
  return mark ~= nil and mark ~= "-" and raw ~= nil and raw > 0
end

local guiRegister = function()
  local marks = globals.timers and globals.timers.p1_pb_marks
  local raws = globals.timers and globals.timers.p1_pb_raws
  if marks == nil or raws == nil then return end

  local entry_num = 0
  for pos = 1, 14 do
    local m = marks[pos]
    local r = raws[pos]
    if is_press(m, r) then
      entry_num = entry_num + 1
      local y = emu.screenheight() - 160 + 10 * entry_num
      gui.text(5, y, entry_num .. ': ')
      local icons_list = parse_mask(r)
      for j, icon in ipairs(icons_list) do
        local x = 5 + 10 * j
        gui.gdoverlay(x, y - 1, icon)
      end
      -- TECH HIT: the entry that granted the push block. timers.lua
      -- publishes ok as a span-level flag; the granting entry is the last
      -- one before the count froze, which in the marks is the last press
      -- while ok is true.
      if globals.timers.p1_pushblock_ok then
        local _grant_pos = nil
        for p2 = pos, 14 do
          if marks[p2] ~= nil and marks[p2] ~= "-" then _grant_pos = p2 end
        end
        if _grant_pos ~= nil and pos == _grant_pos then
          gui.text((#icons_list + 1) * 10 + 7, y, 'TECH HIT')
        end
      end
    end
  end
end

image_setup()

return guiRegister