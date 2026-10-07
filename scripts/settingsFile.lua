-- WHERE THE SETTINGS LIVE, AND HOW THEY ARE WRITTEN.
--
-- <FBNeo>\training_data\training_settings.json, outside scripts\ (2026-10-07,
-- user). scripts\ is what an update replaces, and the settings sat in it.
-- Only the place moved: the JSON, its keys and its contents are as before.
--
-- THE FBNEO FOLDER IS FOUND, NOT ASSUMED. The candidates, in order, are the
-- folder above the master script's own path, the folder above this file's own
-- path, and "..", which is the same folder for as long as FBNeo runs a script
-- with the script's folder as the working directory - io.open has always
-- resolved relative paths that way (docs/development/CLAUDE.md). A candidate
-- counts only if scripts\vsav_training_master_script.lua is there, so a
-- launch from the batch file and a script loaded by hand land on one file.
-- If none does, nothing is saved anywhere else; the screen says so.
--
-- MOVING OVER FROM THE OLD PLACE (scripts\training_settings.json):
--   1. the new file exists: it is used; the old one is not read or merged;
--   2. only the old one exists: it is read and checked, copied byte for byte,
--      and the copy is read back; the old file stays where it was, as a
--      backup that is no longer updated;
--   3. neither exists: a first start, defaults;
--   4. a file that exists cannot be read or parsed: an error with its path,
--      defaults in memory, and NOTHING IS SAVED this session - not over it,
--      and not to the new place, where a file of defaults would shadow the
--      real settings from then on. The old file is not used instead of a
--      broken new one.
--
-- SAVING NEVER LEAVES AN EMPTY FILE. The text goes to a .tmp beside the file,
-- is closed and read back, and only then replaces it: the old file is renamed
-- to .bak first (Windows' rename will not overwrite), the .tmp takes its name,
-- and the .bak goes. If the second rename fails, the .bak is put back. A save
-- cut off between the two renames leaves the .bak, which the next start
-- takes back as the file.

local json = require './scripts/dkjson'

local M = {}

-- "\\" on Windows, "/" elsewhere (the Linux launchers). package.config's
-- first character is the directory separator Lua was built with.
local SEP = (package.config or "\\"):sub(1, 1)
local WINDOWS = SEP == "\\"
local FILE = "training_settings.json"
local DIR = "training_data"
local MASTER = "vsav_training_master_script.lua"

-- The source of this file, as loaded ("@<path>"). Taken here because it is
-- this file's; nil where debug is not there.
local own_source = (function()
	local ok, info = pcall(function() return debug.getinfo(1, "S") end)
	return ok and info and info.source or nil
end)()

local master_source = nil
local resolved = false
local base, dir_path, new_path, old_path = nil, nil, nil, nil
-- Why saving is refused for the rest of the session, or nil.
local locked = nil
-- What the screen shows: the lines of a load problem stay; a failed save
-- replaces its own lines and a later good save clears them.
local load_lines = {}
local save_lines = {}

-- ---------------------------------------------------------------------------
-- Files

-- The whole file, or nil and "missing" / "unreadable" and a message.
-- Lua 5.1's io.open gives the C errno third; 2 is "no such file".
local function read_all(path, mode)
	local f, msg, code = io.open(path, mode or "rb")
	if f == nil then
		if code == 2 then return nil, "missing", msg end
		return nil, "unreadable", msg
	end
	local ok, text = pcall(f.read, f, "*a")
	f:close()
	if not ok or type(text) ~= "string" then return nil, "unreadable", tostring(text) end
	return text
end

local function exists(path)
	local f = io.open(path, "rb")
	if f == nil then return false end
	f:close()
	return true
end

-- A JSON object, or nil and the reason.
local function decode(text)
	local ok, obj, _, err = pcall(json.decode, text)
	if not ok then return nil, tostring(obj) end
	if type(obj) ~= "table" then
		return nil, tostring(err or "not a JSON object")
	end
	return obj
end

-- Write, close, and read back. The read mode matches the write mode, so a
-- text-mode "\n" that went out as CRLF reads back as "\n".
local function write_checked(path, text, binary)
	local f, msg = io.open(path, binary and "wb" or "w")
	if f == nil then return false, tostring(msg) end
	local wok, werr = f:write(text)
	local cok, cerr = f:close()
	if not wok then return false, "write failed: " .. tostring(werr) end
	if not cok then return false, "close failed: " .. tostring(cerr) end
	local back, _, rmsg = read_all(path, binary and "rb" or "r")
	if back == nil then return false, "could not read it back: " .. tostring(rmsg) end
	if back ~= text then return false, "it read back different from what was written" end
	return true
end

-- Writes the .tmp, making training_data\ the first time. mkdir runs only when
-- the first open fails, which in practice is the first save on a machine.
local function write_tmp(tmp, text, binary)
	local ok, err = write_checked(tmp, text, binary)
	if ok then return true end
	if WINDOWS then
		os.execute('mkdir "' .. dir_path .. '" >nul 2>nul')
	else
		os.execute('mkdir -p "' .. dir_path .. '" >/dev/null 2>&1')
	end
	ok, err = write_checked(tmp, text, binary)
	if ok then return true end
	os.remove(tmp)
	return false, err
end

-- The .tmp becomes the file without the file ever being missing or empty
-- while there is nothing to take its place.
local function put_in_place(tmp, target)
	local bak = target .. ".bak"
	local had = exists(target)
	if had then
		-- A .bak beside an intact file is a leftover; the file is the truth.
		if exists(bak) then os.remove(bak) end
		local ok, err = os.rename(target, bak)
		if not ok then
			os.remove(tmp)
			return false, "could not set the old file aside: " .. tostring(err)
		end
	end
	local ok, err = os.rename(tmp, target)
	if not ok then
		if had then os.rename(bak, target) end
		os.remove(tmp)
		return false, "could not put the new file in place: " .. tostring(err)
	end
	if had then os.remove(bak) end
	return true
end

-- ---------------------------------------------------------------------------
-- Where

local function folder_of(path)
	return path and path:match("^(.*)[\\/][^\\/]*$") or nil
end

-- The folder above the scripts folder a "@...\scripts\x.lua" source names.
local function base_from_source(source)
	if type(source) ~= "string" or source:sub(1, 1) ~= "@" then return nil end
	return folder_of(folder_of(source:sub(2)))
end

local function resolve()
	if resolved then return end
	resolved = true
	local candidates = {}
	-- Not ipairs: it would stop at a nil master_source and skip own_source.
	local sources = { master_source, own_source }
	for i = 1, 2 do
		local b = base_from_source(sources[i])
		if b ~= nil and b ~= "" then candidates[#candidates + 1] = b end
	end
	candidates[#candidates + 1] = ".."
	for _, b in ipairs(candidates) do
		if exists(b .. SEP .. "scripts" .. SEP .. MASTER) then
			base = b
			break
		end
	end
	if base == nil then return end
	dir_path = base .. SEP .. DIR
	new_path = dir_path .. SEP .. FILE
	old_path = base .. SEP .. "scripts" .. SEP .. FILE
end

-- ---------------------------------------------------------------------------
-- Telling the player

local function say(lines, list)
	for _, l in ipairs(lines) do
		print("[settings] " .. l)
		list[#list + 1] = l
	end
end

local function lock(lines)
	locked = lines[1]
	lines[#lines + 1] = "Nothing will be saved until FBNeo is restarted."
	say(lines, load_lines)
end

-- ---------------------------------------------------------------------------
-- The API

-- The master script's own debug source ("@<path>"), before the first load.
function M.set_master_source(source)
	master_source = source
end

function M.paths()
	resolve()
	return { base = base, dir = dir_path, new = new_path, old = old_path }
end

-- The settings as a table to lay over the defaults: {} for a first start or
-- after an error (see the rules at the top).
function M.load()
	resolve()
	if base == nil then
		lock({ "Could not find the training folder (scripts" .. SEP .. MASTER .. ")." })
		return {}
	end

	local text, kind, msg = read_all(new_path)
	if text ~= nil then
		local obj, err = decode(text)
		if obj ~= nil then return obj end
		lock({ "Could not read the settings file (it was not changed):", new_path, tostring(err) })
		return {}
	end
	if kind == "unreadable" then
		lock({ "Could not open the settings file (it was not changed):", new_path, tostring(msg) })
		return {}
	end

	-- A save cut off between its two renames left the file as .bak.
	local bak = new_path .. ".bak"
	local btext = read_all(bak)
	if btext ~= nil then
		local obj, err = decode(btext)
		if obj ~= nil and os.rename(bak, new_path) then
			print("[settings] Restored " .. new_path .. " from the .bak an interrupted save left.")
			return obj
		end
		lock({ "An interrupted save left a backup that could not be restored:", bak,
			tostring(err or "rename failed") })
		return {}
	end

	local otext, okind, omsg = read_all(old_path)
	if otext == nil then
		if okind == "missing" then return {} end
		lock({ "Could not open the old settings file (it was not changed):", old_path, tostring(omsg) })
		return {}
	end
	local obj, err = decode(otext)
	if obj == nil then
		lock({ "Could not read the old settings file (it was not changed):", old_path, tostring(err) })
		return {}
	end

	-- Copied as it is, so nothing the current version does not know is lost.
	local tmp = new_path .. ".tmp"
	local ok, werr = write_tmp(tmp, otext, true)
	if ok then ok, werr = put_in_place(tmp, new_path) end
	if ok then
		local back = read_all(new_path)
		if back ~= otext or decode(back) == nil then
			ok, werr = false, "the copy read back different from the old file"
		end
	end
	if not ok then
		lock({ "Could not copy the settings to their new place (the old file is in use, unchanged):",
			new_path, tostring(werr) })
		return obj
	end
	print("[settings] Copied " .. old_path .. " to " .. new_path
		.. ". The old file stays as a backup and is no longer updated.")
	return obj
end

-- Writes the settings, or returns false and the reason (which is also shown).
function M.save(settings)
	resolve()
	if locked ~= nil then return false, locked end
	if new_path == nil then return false, "no settings path" end
	local ok, text = pcall(json.encode, settings, { indent = true })
	local err
	if not ok or type(text) ~= "string" then
		ok, err = false, "could not encode the settings: " .. tostring(text)
	else
		local tmp = new_path .. ".tmp"
		ok, err = write_tmp(tmp, text, false)
		if ok then ok, err = put_in_place(tmp, new_path) end
	end
	save_lines = {}
	if not ok then
		say({ "Could not save the settings (the previous file was kept):", new_path, tostring(err) },
			save_lines)
		return false, err
	end
	return true
end

-- The lines on screen, or nil.
function M.error_lines()
	local out = {}
	for _, l in ipairs(load_lines) do out[#out + 1] = l end
	for _, l in ipairs(save_lines) do out[#out + 1] = l end
	if #out == 0 then return nil end
	return out
end

-- Long paths wrapped to the screen: gui.text does not wrap, and a path cut
-- off at the right edge is the part that matters.
local WRAP = 94
local function wrapped(lines)
	local out = {}
	for _, l in ipairs(lines) do
		while #l > WRAP do
			out[#out + 1] = l:sub(1, WRAP)
			l = "  " .. l:sub(WRAP + 1)
		end
		out[#out + 1] = l
	end
	return out
end

-- Drawn for as long as the problem stands, below the run-ahead banner's
-- space at the top. A banner that went away on its own would let the player
-- change settings and lose them at the next start without knowing.
function M.draw()
	local lines = M.error_lines()
	if lines == nil then return end
	lines = wrapped(lines)
	local y = 34
	local w = emu.screenwidth()
	gui.box(0, y, w - 1, y + 3 + 9 * #lines, 0x600000D0, 0xFF0000FF)
	for i, l in ipairs(lines) do
		gui.text(4, y + 3 + 9 * (i - 1), l, i == 1 and 0xFFFF00FF or 0xFFFFFFFF)
	end
end

return M
