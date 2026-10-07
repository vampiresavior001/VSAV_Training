-- THE LAUNCHERS: WHERE THEY STAND, AND HOW THEY HAND THE EMULATOR ITS FILES.
--
-- run_vsav_training.bat and the probe launchers under analysis\.
--
-- THE ARGUMENTS TO fcadefbneo.exe ARE NEVER QUOTED. It does not read quoted
-- arguments: given "savestates\vsavj_fbneo.fs" it reported
-- "savestates\vsavj_fbneo.f is not supported by Fightcade FBNeo" and loaded
-- nothing, from a folder with spaces and from one without (2026-10-07, in the
-- game). A stand-in exe built on the C runtime had passed the quoted form - it
-- reads quotes the standard way and FBNeo does not - so only the game counts
-- here. The exe itself is quoted: that is read by start, not by FBNeo.
--
-- AND THEY ARE RELATIVE, so the folder's spaces never reach them. Run from
-- "space test (x86)\fbneo" with the script given as scripts\..., the game and
-- the script loaded, and the script still ran in scripts\: inputHistory.lua
-- opened images\ there on load, and training_data\ was written beside it
-- (2026-10-07, in the game).
--
-- Pinned here, for every .bat this finds:
--   - it stands in its own folder (the probes in the folder above) and stops
--     if it cannot;
--   - start gets an empty title "" - start takes its first quoted argument as
--     the window title, which would swallow the quoted exe;
--   - the exe quoted, then vsavj, the savestate and the script, unquoted
--     and relative;
--   - exit /b, not exit, which closed the console it was called from.
--
--   lua5.1 analysis/test_launchers_args.lua

local fails = 0
local function want(what, got, w)
	if got ~= w then
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(w) .. "]")
	else
		print("  ok " .. what)
	end
end

local function slurp(p)
	local f = assert(io.open(p, "rb"))
	local s = f:read("*a")
	f:close()
	return s
end

-- Found, not listed: a new launcher is checked the moment it exists.
local bats = { "run_vsav_training.bat" }
for name in io.popen([[dir /b analysis\*.bat]]):lines() do
	bats[#bats + 1] = "analysis\\" .. name
end
want("launcher が 10 本ある (本体 1 + プローブ 9)", #bats, 10)

for _, p in ipairs(bats) do
	print("-- " .. p)
	local s = slurp(p)
	local probe = p:find("^analysis\\") ~= nil
	local cd = probe and 'cd /d "%~dp0.." || exit /b 1' or 'cd /d "%~dp0" || exit /b 1'
	want("自分の置き場所 (プローブはその上) へ移り、失敗したら止める",
		s:find("\n" .. cd .. "\n", 1, true) ~= nil, true)
	local start = s:match("\n(start [^\n]*)\n")
	local lua = probe and 'analysis\\[%w_]+%.lua' or 'scripts\\vsav_training_master_script%.lua'
	want("start の行: 空のタイトル、exe は引用符、ステートとスクリプトは引用符なしの相対",
		start ~= nil and start:match('^start "" "%%cd%%\\fcadefbneo%.exe" vsavj savestates\\vsavj_fbneo%.fs '
			.. lua .. '$') ~= nil, true)
	local args = start and start:match('fcadefbneo%.exe" (.*)$') or ""
	want("FBNeo へ渡す引数に引用符が無い", args:find('"', 1, true), nil)
	want("FBNeo へ渡す引数に %cd% (空白が入りうる) が無い", args:find("%cd%", 1, true), nil)
	local starts = 0
	for _ in s:gmatch("\nstart ") do starts = starts + 1 end
	want("start は 1 回だけ", starts, 1)
	want("最後は exit /b", s:match("\n(exit[^\n]*)%s*$"), "exit /b")
end

if fails == 0 then
	print("test_launchers_args ok")
else
	print(fails .. " 件 NG")
	os.exit(1)
end
