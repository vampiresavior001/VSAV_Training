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
-- TECH HIT SITS ON THE ROW THE PUSH BLOCK WAS GRANTED ON (user, 2026-10-19).
-- It used to search the marks for the last press while ok was true, so the
-- extra presses made after the grant (which PB Count deliberately keeps
-- counting) moved the label down with them. timers.lua now records the grant's
-- tick position and the window's marks table; the row is looked up from that
-- position, so later presses do not move it and an old window's grant cannot
-- appear on a new window's rows.
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

-- LEVEL WITH PB STATS (user, 2026-09-28: ステータスのボタン内容をもう少し上に).
-- The first entry sits where PB Stats' first line is - hud.lua passes it in;
-- it was at the screen height - 150 (74).
local guiRegister = function(_top)
  _top = _top or 38
  local timers = globals.timers
  local marks = timers and timers.p1_pb_marks
  local raws = timers and timers.p1_pb_raws
  if marks == nil or raws == nil then return end

  -- The entries first, so the box behind them can be sized before anything
  -- is drawn on it.
  local entries = {}
  for pos = 1, 14 do
    local m = marks[pos]
    local r = raws[pos]
    if is_press(m, r) then
      local e = { icons = parse_mask(r) }
      -- ROWS ARE NUMBERS, POSITIONS ARE TICKS. A tick with no press takes no
      -- row, so the grant's tick position has to be matched here while the
      -- row number is being assigned. The marks-table identity keeps a grant
      -- from the previous window out of this window's rows.
      e.tech = (timers.p1_pb_grant_marks == marks
                and timers.p1_pb_grant_pos == pos)
      entries[#entries + 1] = e
    end
  end
  if #entries == 0 then return end

  -- ON THE SAME DARK BOX AS PB STATS (user, 2026-09-28: 左側のボタン背景も同じ
  -- 黒目に). One pixel of margin on the right, not two: an entry with two
  -- buttons and TECH HIT ends at 70.6, and PB Stats' box starts at 72.
  local right = 0
  for _, e in ipairs(entries) do
    local r = 5 + 10 * #e.icons + 8
    if e.tech then r = (#e.icons + 1) * 10 + 7 + 8 * 4.2 end
    if r > right then right = r end
  end
  gui.box(3, _top - 1, right + 1, _top + 10 * #entries - 1, "#00000099", "#00000055")

  for n, e in ipairs(entries) do
    local y = _top + 10 * (n - 1)
    gui.text(5, y, n .. ': ')
    for j, icon in ipairs(e.icons) do
      gui.gdoverlay(5 + 10 * j, y - 1, icon)
    end
    if e.tech then
      -- Green, as Pass and Success in PB Stats and the PB Count line once the
      -- push block is granted: the same success, the same colour (user,
      -- 2026-09-28).
      gui.text((#e.icons + 1) * 10 + 7, y, 'TECH HIT', "#00FF00")
    end
  end
end

image_setup()

return guiRegister