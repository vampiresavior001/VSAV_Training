-- DO THE PROBES ACTUALLY RUN, NOT JUST COMPILE?
--
-- leverProbe.lua compiled and then died on its first frame with "attempt to
-- compare nil with number": a block of declarations had been left out, so the
-- counters it reads were globals resolving to nil. loadfile() cannot catch that
-- - Lua compiles a reference to an undeclared global happily - and the probe
-- was handed over broken (2026-09-12).
--
-- So: stub the emulator, load each probe, and CALL the callbacks it registered.
-- One frame and one draw is enough to catch a nil that a syntax check cannot.
--
-- ROM HOOKS COUNT AS CALLBACKS TOO. A probe that hangs its work on
-- memory.registerexec does nothing at all until the game reaches that address,
-- so a nil in there survives every frame and every draw - the same hole the
-- hotkeys had. Each registered address is called here, once per player object
-- and once for something that is neither, because the handlers branch on a6.
--
--   cd C:/fightcaVSAV-Debug/emulator/fbneo && lua5.1 analysis/test_probe_smoke.lua
local fails = 0
local function want(what, got, w)
	if got ~= w then
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(w) .. "]")
	else
		print("  ok " .. what)
	end
end

-- Every probe writes its log beside its own .lua (FBNeo resolves a relative
-- io.open against the script's folder), so the stub swallows the write
-- rather than leaving files behind.
local function sandbox()
	local ram = {}
	local execs = {}
	local a6 = 0xFF8400
	memory = {
		readbyte = function(a) return ram[a] or 0 end,
		readword = function(a) return ram[a] or 0 end,
		readdword = function(a) return ram[a] or 0 end,
		writebyte = function(a, v) ram[a] = v end,
		registerexec = function(addr, f) execs[addr] = f end,
		getregister = function() return a6 end,
	}
	local before, draw, exit = nil, nil, nil
	local hotkeys = {}
	emu = {
		framecount = function() return 1 end,
		registerbefore = function(f) before = f end,
		registerexit = function(f) exit = f end,
	}
	gui = { register = function(f) draw = f end, text = function() end }
	input = { registerhotkey = function(n, f) hotkeys[n] = f end, get = function() return {} end }
	joypad = { get = function() return {} end, set = function() end }
	savestate = { registerload = function() end, registersave = function() end }
	-- io.open is left alone: the probes append to a log and a nil file handle
	-- is a path they all have to survive anyway.
	local real_open = io.open
	io.open = function(name, mode)
		if mode == "a" or mode == "w" then return nil end
		-- The reply a stubbed PowerShell would have left behind.
		--
		-- dialogProbe and namingProbe both hand their work to an external
		-- process and then PARSE what it wrote: three lines of status, text and
		-- count. With io.popen stubbed that file never appears, so every one of
		-- those probes bailed out early and the parsing - the part that moves
		-- into the product - was reached by nothing. A mutation that replaced
		-- the non-ASCII check with a call to a nil was caught by no assertion
		-- at all until this existed.
		if type(name) == "string" and name:find("_out%.txt$") then
			local body = "OK\nname\n4"
			local served = false
			return {
				read = function()
					if served then return nil end
					served = true
					return body
				end,
				close = function() end,
			}
		end
		return real_open(name, mode)
	end
	-- io.popen MUST be stubbed, unlike io.open. dialogProbe.lua spawns
	-- PowerShell and waits for a file dialog, so the real thing would open a
	-- window on the grader's screen and block this test until someone clicked
	-- it. The empty read is also the cancel path, which is worth exercising.
	local popen_calls = {}
	local real_popen = io.popen
	io.popen = function(cmd)
		popen_calls[#popen_calls + 1] = cmd
		return { read = function() return "" end, close = function() end }
	end
	local real_remove = os.remove
	os.remove = function() return true end
	return {
		ram = ram, hotkeys = hotkeys, execs = execs, popen_calls = popen_calls,
		frame = function() if before then before() end end,
		drawn = function() if draw then draw() end end,
		quit = function() if exit then exit() end end,
		-- P1, P2, and an object that is neither - the third is the early
		-- return every one of these handlers starts with.
		as = function(v) a6 = v end,
		restore = function()
			io.open = real_open
			io.popen = real_popen
			os.remove = real_remove
		end,
	}
end

local PROBES = {
	"analysis/leverProbe.lua",
	"analysis/routeProbe.lua",
	"analysis/selectProbe.lua",
	"analysis/keyboardProbe.lua",
	"analysis/pbFlagProbe.lua",
	"analysis/gcSuccessProbe.lua",
	"analysis/landingPredictProbe.lua",
	"analysis/dialogProbe.lua",
	"analysis/namingProbe.lua",
}

for _, path in ipairs(PROBES) do
	local env = sandbox()
	local chunk, err = loadfile(path)
	want(path .. " が読める", chunk ~= nil, true)
	if chunk ~= nil then
		local ok, e = pcall(chunk)
		want(path .. " が走り出す", ok, true)
		if not ok then print("      " .. tostring(e)) end
		-- Three frames: the first sets up whatever "previous" state a probe
		-- keeps, and a probe that only fails on the second is still broken.
		for _ = 1, 3 do
			local ok2, e2 = pcall(env.frame)
			if not ok2 then
				want(path .. " のフレーム処理", false, true)
				print("      " .. tostring(e2))
				break
			end
		end
		local ok3, e3 = pcall(env.drawn)
		want(path .. " の描画", ok3, true)
		if not ok3 then print("      " .. tostring(e3)) end
		-- Hotkeys are the path that broke: nothing calls them until a human
		-- presses the key, so a nil in there survives every other check.
		--
		-- A FRAME AFTER EACH ONE, not after all of them. A hotkey that only
		-- sets a flag for the frame callback to act on - which is how
		-- dialogProbe defers its blocking work - shares that one flag with
		-- every other hotkey. Draining once at the end ran whichever key pairs()
		-- happened to yield last and never looked at the other two.
		--
		-- AND probe_error, for a probe that wraps its own work in pcall. That
		-- pcall is right - a broken job should not end a measuring session -
		-- but it swallows the runtime nil this whole file exists to find, so
		-- the convention is to publish the message there too. Probes that never
		-- set it leave it nil and nothing changes for them.
		for n, f in pairs(env.hotkeys) do
			probe_error = nil
			local ok4, e4 = pcall(f)
			want(path .. " の hotkey " .. tostring(n), ok4, true)
			if not ok4 then print("      " .. tostring(e4)) end
			local ok5, e5 = pcall(env.frame)
			want(path .. " hotkey " .. tostring(n) .. " の次のフレーム", ok5, true)
			if not ok5 then print("      " .. tostring(e5)) end
			want(path .. " hotkey " .. tostring(n) .. " が飲み込んだエラー無し",
				probe_error, nil)
			if probe_error ~= nil then print("      " .. tostring(probe_error)) end
		end
		-- The ROM hooks, for each side and for a third object that is neither -
		-- then one more frame, since a hook usually leaves state behind for the
		-- frame callback to read.
		for _, who in ipairs({ 0xFF8400, 0xFF8800, 0xFF8C00 }) do
			env.as(who)
			for addr, f in pairs(env.execs) do
				local ok6, e6 = pcall(f)
				want(path .. string.format(" hook %06X (a6=%X)", addr, who), ok6, true)
				if not ok6 then print("      " .. tostring(e6)) end
			end
		end
		local ok7, e7 = pcall(env.frame)
		want(path .. " frame after the hooks", ok7, true)
		if not ok7 then print("      " .. tostring(e7)) end
		pcall(env.quit)
	end
	env.restore()
end

if fails == 0 then print("全て通った") else print(fails .. " 件 NG") os.exit(1) end
