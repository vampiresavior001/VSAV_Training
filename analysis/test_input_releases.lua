-- THE RELEASE MARKER AND THE DECLUTTER ARE TWO SWITCHES, NOT ONE.
--
-- The input bar draws a hollow marker on the frame a button is let go, in a
-- column of its own. That column never has a newly pressed button, so
-- remove_nedge_events() - Hide Negative Edge Inputs - always read it as
-- clutter and took it out. One row therefore did two jobs, and the only way to
-- keep the markers was to accept every redundant column with them.
--
-- The N-Bee build this forked from had no release markers at all: a release
-- simply ended the column the button was held in, and Hide negative edge
-- inputs removed the leftover. Comparing the two is what surfaced this
-- (user, 2026-09-14).
--
-- Show Button Releases now owns the marker, Hide Negative Edge Inputs owns the
-- leftover, and neither touches the other's columns.
--
-- Run from scripts/ - inputHistory.lua loads its images by relative path.
--   cd scripts && lua5.1 ../analysis/test_input_releases.lua

-- gd is a C module in the emulator and is used through the GLOBAL, not the
-- value require returns, so both have to be in place before the load.
gd = { createFromPng = function() return { gdStr = function() return "" end } end }
package.preload["gd"] = function() return gd end

local ram = {}
memory = {
	readbyte = function(a) return ram[a] or 0 end,
	readword = function(a) return ram[a] or 0 end,
	readdword = function(a) return ram[a] or 0 end,
	writebyte = function(a, v) ram[a] = v end,
}
gui = { text = function() end, box = function() end, image = function() end }
emu = { framecount = function() return 1 end, screenwidth = function() return 384 end,
        screenheight = function() return 224 end }
joypad = { get = function() return {} end, set = function() end }
globals = {
	options = {},
	gc_event = "p1_gc_none",
	pb_event = "p1_pb_none",
}

-- Rx is a global the master script sets up with require. The real one loads
-- standalone, so it is used rather than stubbed - inputHistory builds two
-- ReplaySubjects at load time.
Rx = dofile("rx-lua/rx.lua")

dofile("inputHistory.lua")

local fails = 0
local function want(what, got, w)
	if got ~= w then
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(w) .. "]")
	else
		print("  ok " .. what)
	end
end

-- A history column as update_input_history() stores one. `released` is nil
-- when the switch is off, which is the whole mechanism.
local function col(dir, buttons, released)
	return {
		direction = dir,
		buttons = buttons,
		released = released,
		gc_event = "p1_gc_none",
		pb_event = "p1_pb_none",
	}
end
local NONE = { false, false, false, false, false, false }
local LP   = { true,  false, false, false, false, false }
local REL  = { true,  false, false, false, false, false }

print("-- スイッチが released を通すか止めるか")
globals.options.show_button_releases = false
local off = make_input_history_entry("P1", {})
want("OFF なら released が付かない", off.released, nil)
want("OFF でも buttons は付く", type(off.buttons), "table")

globals.options.show_button_releases = true
local on = make_input_history_entry("P1", {})
want("ON なら released が付く", type(on.released), "table")
want("6 ボタンぶん", #on.released, 6)

-- ...and a settings file written before the key existed keeps the ON default
-- from config.lua, so nil here would be a real regression in the wiring.
globals.options.show_button_releases = nil
want("未設定なら OFF 扱い", make_input_history_entry("P1", {}).released, nil)
globals.options.show_button_releases = true

print("-- 離しの列が前の列と結合しないこと")
-- Same direction, same (empty) buttons - only the release edge separates them.
-- Without the split, the release column absorbs every following frame and the
-- marker is drawn with a frame count of 100+ instead of 1.
want("ON: 離しの列は独立する",
	is_input_history_entry_equal(col(5, NONE, REL), col(5, NONE, NONE)), false)
-- With no release edge recorded at all, the two are the same column again -
-- which is exactly how the N-Bee build behaved.
want("OFF: 旧版どおり結合する",
	is_input_history_entry_equal(col(5, NONE, nil), col(5, NONE, nil)), true)

print("-- Hide が ON でも離しの列は残る (独立していることの本体)")
-- neutral -> LP down -> LP let go (release column) -> still neutral (leftover)
local history = {
	col(5, NONE, NONE),
	col(5, LP,   NONE),
	col(5, NONE, REL),
	col(5, NONE, NONE),
}
local kept = remove_nedge_events(history)
local function has(list, entry)
	for _, e in ipairs(list) do if e == entry then return true end end
	return false
end
want("押した列は残る", has(kept, history[2]), true)
want("離しの列は残る", has(kept, history[3]), true)
want("離しのあとの冗長な列は消える", has(kept, history[4]), false)

print("-- Hide は今までどおり間引く")
-- The same shape with no release edges: the column the release left behind is
-- indistinguishable from the release itself, and both go.
local old_style = {
	col(5, NONE, nil),
	col(5, LP,   nil),
	col(5, NONE, nil),
	col(5, NONE, nil),
}
local kept_old = remove_nedge_events(old_style)
want("押した列は残る", has(kept_old, old_style[2]), true)
want("離しで増えた列は消える", has(kept_old, old_style[3]), false)
want("その次も消える", has(kept_old, old_style[4]), false)

print("-- 方向が変われば残る")
-- The rule is "same direction AND nothing newly pressed", so a direction
-- change is never clutter even with no buttons at all.
local turned = {
	col(5, NONE, nil),
	col(6, NONE, nil),
	col(6, NONE, nil),
}
local kept_turn = remove_nedge_events(turned)
want("方向が変わった列は残る", has(kept_turn, turned[2]), true)
want("同じ方向の続きは消える", has(kept_turn, turned[3]), false)

print("-- 出荷値")
local shipped = dofile("config.lua").default_training_settings
want("show_button_releases は ON で出荷", shipped.show_button_releases, true)
-- ON since the release marker became its own switch: what is left for this to
-- remove is a column with nothing new on it, and a release, a press, a
-- direction change and anything carrying a GC or PB event are all kept.
want("skip_nedge_displays は ON で出荷", shipped.skip_nedge_displays, true)

if fails == 0 then
	print("test_input_releases ok")
else
	print(fails .. " 件 NG")
	os.exit(1)
end
