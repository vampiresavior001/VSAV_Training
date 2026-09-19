-- RELEASE DEFAULTS TEST: every toggle on the Analysis tab ships OFF.
--
-- The rule is in CLAUDE.md: a release has all of Analysis switched off. Nothing
-- enforced it, and the switches there are diagnostics - a logger that writes a
-- file per recovery, timer overlays, two "Testing:" rows - so one of them left
-- on in config.lua would go out to everyone who unzips the build.
--
-- The list is not written down twice on purpose. This walks the REAL Analysis tab
-- out of menu.lua and asks config.lua what each of those properties ships as,
-- so a row added to the tab later is covered without touching this file.
--
-- THE TAB USED TO BE CALLED "Etc" and held two rows that are not diagnostics.
-- Display Pushbox X Center went to the Display tab (it is a sub-setting of the
-- hitbox display) and is named below instead, because leaving the walk as the
-- only check would have dropped it silently. BGM On went to Game and is NOT
-- named: it is a preference, not a diagnostic, and shipping it on would be a
-- decision rather than a mistake.
--
-- Scalars are not toggles: Game Speed is 0-3 and its shipped 3 IS the setting
-- the tool is used at, so "off" does not apply to it. It now lives on Game
-- and is out of the walk entirely. Only checkbox rows are checked, and they
-- are recognised the way the menu builds them - a checkbox has no min/max and
-- no list.
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_release_defaults.lua
package.preload["./scripts/charMoves"] = function()
	return { get_player_movelists = function()
		return { P1 = { reversal_names = { "Stub" } }, P2 = { reversal_names = { "Stub" } } }
	end }
end
package.preload["./scripts/actionSequenceEditor"] = function()
	return dofile("actionSequenceEditor.lua")
end
package.preload["./scripts/actionSequenceRunner"] = function()
	return dofile("actionSequenceRunner.lua")
end

training_settings = {}
globals = {}
memory = { readbyte = function() return 0 end }
gui = { text = function() end, box = function() end }
dofile("menu.lua")
menuModule.guiRegister()

local shipped = dofile("config.lua").default_training_settings
assert(type(shipped) == "table", "config.lua did not hand back its defaults")

local analysis_tab
for _, tab in ipairs(menu) do
	if tab.name == "Analysis" then analysis_tab = tab end
end
assert(analysis_tab, "Analysis tab not found")

local fails = 0
local function bad(msg)
	print("FAIL " .. msg)
	fails = fails + 1
end

-- A checkbox is the only row here whose value is a switch. integer_menu_item
-- carries min/max, list_menu_item carries list.
local seen = 0
for _, e in ipairs(analysis_tab.entries) do
	if e.property_name ~= nil and e.min == nil and e.list == nil then
		seen = seen + 1
		local v = shipped[e.property_name]
		-- nil reads as off everywhere in the tool, so an absent key passes.
		--
		-- ZERO DOES NOT. This used to accept it, and seven rows shipped as
		-- 0 in config.lua while every one of them is read as
		-- `if globals.options.X then` - which in Lua is TRUE for zero. The
		-- whole Analysis tab came up on for anyone who unzipped a build
		-- without an existing settings file, and this test passed the
		-- entire time because it agreed with the wrong assumption
		-- (reported 2026-09-19).
		--
		-- A checkbox ships false or it does not ship.
		if v ~= nil and v ~= false then
			bad(("Analysis toggle %q ships as %s, must be off"):format(e.name, tostring(v)))
		end
	end
end

if seen < 10 then
	bad("only " .. seen .. " toggles found on the Analysis tab - either the walk is "
	    .. "wrong or a diagnostic row moved off the tab without being named below")
end

-- The one that costs the most if it slips out: it writes a JSON file per
-- recovery. Named so a rename cannot quietly drop it from the walk above.
if shipped.knockdown_logger_enable ~= false then
	bad("knockdown_logger_enable must ship false")
end

-- Named because it is no longer on the walked tab (see the note at the top).
if shipped.display_pushbox_axis ~= false then
	bad("display_pushbox_axis must ship false")
end

if fails == 0 then
	print(("test_release_defaults ok (%d Analysis toggles, all off)"):format(seen))
else
	print(fails .. " failure(s)")
	os.exit(1)
end
