-- Tick-based replacement for the legacy displayed-frame counter.
-- Public entry points are kept so the master script and saved option remain
-- compatible. Measurement runs from globals.truth.ticker; registerAfter only
-- publishes the latest completed result.
local tickData = require "./scripts/tickData"
-- The route the move was reached by - a second window over the same ticks.
-- Fed the same snapshot so the two rows can never disagree about one.
local actionRoute = require "./scripts/actionRoute"
local vsav = require "./scripts/tickDataVsav"

local M = {}
local subscription_generation = 0
local last_enabled = false
local last_menu = false
local last_match = false

local function option_enabled()
  return globals ~= nil and globals.options ~= nil
    and globals.options.mo_enable_frame_data == true
end

local function on_tick(tick)
  local on = option_enabled()
  if not on then
    if last_enabled then
      tickData.reset("disabled", true)
      actionRoute.reset("disabled", true)
    end
    last_enabled = false
    last_menu = false
    last_match = false
    return
  end
  last_enabled = true

  local menu = globals.show_menu == true
  -- NOT match_begun. IT GOES FALSE DURING A TRANSFORMATION.
  --
  -- gameState derives it from 0xFF8401 / 0xFF8801 both reading 1, and those
  -- drop to 0 while a character is transformed. Demitri's Bat Spin therefore
  -- reset the measurement mid-move and the readout stayed empty for the whole
  -- special - reported as "some specials produce nothing", diagnosed as
  -- [no result: match_not_running] (user, 2026-09-07).
  --
  -- The master script already has the conservative test for this, written for
  -- the same bug in the drawing path. Asked here rather than copied.
  local match
  if globals.match_running ~= nil then
    match = globals.match_running() == true
  else
    match = globals.game_state ~= nil
      and globals.game_state.match_begun == true
  end
  if menu then
    if not last_menu then
      tickData.reset("menu_open", false)
      actionRoute.reset("menu_open", false)
    end
    last_menu = true
    last_match = match
    return
  end
  last_menu = false
  -- NOT WHILE THE CHARACTERS ARE STILL WALKING ON.
  --
  -- match_running is already true during the entrance, so the rows were being
  -- built - and kept - before the round existed (user, 2026-09-10). Nothing
  -- measured there is worth reading, and it arrives on screen ahead of the
  -- first thing the player actually does.
  --
  -- hotkeys_armed is the master script's own answer to "is the round live",
  -- match_running AND position.lua's round_ready, and it is the gate the menu
  -- and the position shortcut already sit behind. Asked rather than copied,
  -- for the same reason the note above says: one definition, not two.
  local armed = globals.hotkeys_armed
  if armed == nil then armed = match end
  if not match or armed ~= true then
    if last_match then
      local why = match and "round_not_ready" or "match_not_running"
      tickData.reset(why, true)
      actionRoute.reset(why, true)
    end
    last_match = false
    return
  end
  last_match = true

  -- WHICH PLAYER THE READOUT IS MEASURING.
  --
  -- The option stores a 1-based index into { "P1", "P2" }, the way every
  -- list_menu_item does. Anything else - a settings file written before this
  -- row existed, a value that never was - reads as P1, which is how the readout
  -- has behaved since it shipped.
  local side = "P1"
  if globals.options ~= nil and globals.options.mo_frame_data_side == 2 then
    side = "P2"
  end
  -- A ROUTE CANNOT BE HALF ONE PLAYER AND HALF THE OTHER.
  --
  -- Both readers carry state from one tick to the next, so without this the
  -- ticks measured before the flip would be joined onto the ticks after it and
  -- printed as one action that nobody performed. The result is cleared too: it
  -- belongs to the side being left.
  if vsav.set_side(side) then
    tickData.reset("side_changed", true)
    actionRoute.reset("side_changed", true)
  end

  -- ONE CAPTURE, TWO READERS. vsav.capture hands back the same table every
  -- tick, so calling it twice would not give two snapshots - it would give the
  -- same one twice, and cost a second pass over the RAM for nothing.
  local snapshot = vsav.capture(tick)
  tickData.update(snapshot)
  actionRoute.update(snapshot)
end

function M.registerStart()
  tickData.reset("emulator_start", true)
  actionRoute.reset("emulator_start", true)
  subscription_generation = subscription_generation + 1
  local mine = subscription_generation
  globals.truth.ticker:subscribe(function(tick)
    if mine == subscription_generation then on_tick(tick) end
  end)
end

function M.registerLoad()
  tickData.reset("savestate_load", true)
  actionRoute.reset("savestate_load", true)
end

function M.registerAfter()
  if not option_enabled() then
    globals.set_last_data("")
    globals.set_last_route("")
    return
  end
  -- TWO READOUTS, KEPT APART.
  --
  -- They used to be joined with a newline here and drawn as one block. The two
  -- do not mean the same thing - the first rows are one move measured in
  -- frames, the route is a whole action on a clock - so they are handed over
  -- separately and the HUD draws the route in its own colour (user,
  -- 2026-09-10). Empty when there is nothing to say, and the readout goes back
  -- to two rows on its own.
  -- SO A SCREENSHOT SAYS WHICH SIDE IT IS.
  --
  -- Nothing is added on P1: that is the default and the rows have read that way
  -- since they shipped. The marker is its own double-space field, so the HUD
  -- wraps it like any other.
  local data = tickData.formatResult()
  local route = actionRoute.formatResult()
  if vsav.side() == "P2" then
    if data ~= "" then data = "P2  " .. data end
    if route ~= "" then route = "P2  " .. route end
  end
  globals.set_last_data(data)
  globals.set_last_route(route)
end

return M
