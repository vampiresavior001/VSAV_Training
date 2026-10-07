-- MUTE IDLE SOUNDS (scripts/idleSound.lua, 2026-10-06).
--
--   [1] the ROM path the hook relies on, read from the MAME disassembly
--   [2] the hook: one address, nobody else on it
--   [3] what is muted: a player, the right character AND the right cel, in a
--       match, with the setting on - and nothing else
--   [4] the log: gathered in the hook, written from the frame callback
--   [5] the hook-up: config default, Game tab row, start-up require
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_idle_sound.lua
local fails = 0
local function eq(what, got, want)
	if got == want then print("  ok " .. what)
	else
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(want) .. "]")
	end
end
local function slurp(path)
	local fh = io.open(path)
	assert(fh, path .. " が読めない")
	local s = fh:read("*a")
	fh:close()
	return s
end

-- ---------------------------------------------------------------------------
print("[1] ROM の経路 (analysis/mame_code/c20.txt)")
local c20 = slurp("../analysis/mame_code/c20.txt")
local function line(addr)
	return c20:match("\n" .. addr .. ":[^\n]*") or ""
end
eq("027EE8 でセルを $1C へ", line("027EE8"):find("move.l  A0, ($1c,A6)", 1, true) ~= nil, true)
eq("027F08 でセルの +0x16 を読む", line("027F08"):find("move.b  ($16,A0), D0", 1, true) ~= nil, true)
eq("027F0E でレジスタを退避 (0x330E)", line("027F0E"):find("jsr     $330e.l", 1, true) ~= nil, true)
eq("027F36 が D1 (音声番号) を試す", line("027F36"):find("tst.w   D1", 1, true) ~= nil, true)
eq("027F38 は 0 なら 027F68 へ", line("027F38"):find("beq     $27f68", 1, true) ~= nil, true)
eq("027F62 が発音要求 (0x4CE2)", line("027F62"):find("jsr     $4ce2.l", 1, true) ~= nil, true)
eq("027F68 は 0x3306 (復元して rts) へ", line("027F68"):find("jmp     $3306.l", 1, true) ~= nil, true)
local c00 = slurp("../analysis/mame_code/c00.txt")
eq("0x3306 は D0-D3/A3-A4 を戻して rts",
	(c00:match("\n003306:[^\n]*") or ""):find("movem.l (-$61ee,A5), D0-D3/A3-A4", 1, true) ~= nil
	and (c00:match("\n00330C:[^\n]*") or ""):find("rts", 1, true) ~= nil, true)
eq("0x330E は同じ場所へ退避",
	(c00:match("\n00330E:[^\n]*") or ""):find("movem.l D0-D3/A3-A4, (-$61ee,A5)", 1, true) ~= nil, true)

-- ---------------------------------------------------------------------------
-- Stand-ins for FBNeo.
local ram, regs, hooks = {}, {}, {}
memory = {
	readbyte = function(a) return ram[a] or 0 end,
	readword = function(a) return ram[a] or 0 end,
	readdword = function(a) return ram[a] or 0 end,
	getregister = function(r) return regs[r] or 0 end,
	setregister = function(r, v) regs[r] = v end,
	registerexec = function(a, f) hooks[#hooks + 1] = { a = a, f = f } end,
}
local fc = 0
emu = { framecount = function() return fc end }
local running = true
globals = {
	options = { mute_idle_sounds = false, knockdown_logger_enable = false },
	match_running = function() return running end,
}
-- The log file is caught here, never written: a real log in reversal_logs
-- must not get test output mixed into it.
local written = nil
local in_hook, opened_in_hook = false, 0
local real_open = io.open
io.open = function(path, mode)
	-- FBNeo cannot write a file from inside an exec hook (VSAV_MEMORY_NOTES /
	-- CLAUDE.md), so any open while the hook runs is a fault here.
	if in_hook then opened_in_hook = opened_in_hook + 1 end
	if path == "reversal_logs/idle_sound.json" then
		local buf = {}
		return { write = function(_, s) buf[#buf + 1] = s end,
		         close = function() written = table.concat(buf) end }
	end
	return real_open(path, mode)
end
local M = dofile("idleSound.lua")

print("[2] フック")
M.registerStart()
eq("1 か所だけ登録", #hooks, 1)
eq("0x027F36 に", hooks[1] and hooks[1].a, 0x027F36)
local others = {}
for _, name in ipairs({ "guardCancel.lua", "debugKnockdown.lua", "autoguard.lua", "airGuardLog.lua",
                        "cps2-hitboxes.lua", "gcStats.lua", "throwTech.lua", "position.lua",
                        "vsav_training_master_script.lua", "framemeter.lua", "tickDataVsav.lua" }) do
	local fh = real_open(name)
	if fh then
		local s = fh:read("*a") ; fh:close()
		if s:find("27F36", 1, true) or s:find("27f36", 1, true) then others[#others + 1] = name end
	end
end
eq("ほかのスクリプトは 0x027F36 を使っていない", table.concat(others, ","), "")

-- ---------------------------------------------------------------------------
print("[3] 何を止めるか")
local P1, P2 = 0xFF8400, 0xFF8800
local function request(a6, char, cel)
	regs["m68000.a6"] = a6
	regs["m68000.d1"] = 0x01CC
	ram[a6 + 0x382] = char
	ram[a6 + 0x1C] = cel
	in_hook = true
	hooks[1].f()
	in_hook = false
	return regs["m68000.d1"]
end
eq("OFF: ガロンの待機でもそのまま", request(P1, 0x02, 0x13B926), 0x01CC)
globals.options.mute_idle_sounds = true
eq("ON: P1 ガロンの立ち待機を止める (D1 = 0)", request(P1, 0x02, 0x13B926), 0)
eq("ON: P2 でも", request(P2, 0x02, 0x13B926), 0)
eq("ON: ダークガロン (同じ待機)", request(P1, 0x12, 0x13B926), 0)
eq("ON: ジェダの立ち待機", request(P1, 0x0F, 0x2490D4), 0)
eq("ON: ビクトルの立ち待機", request(P2, 0x03, 0x150AF4), 0)
eq("ON: バレッタのしゃがみ待機", request(P1, 0x00, 0x112E62), 0)
eq("ON: ガロンの別のセルはそのまま", request(P1, 0x02, 0x13B940), 0x01CC)
eq("ON: ジェダのセルでもキャラがガロンならそのまま", request(P1, 0x02, 0x2490D4), 0x01CC)
eq("ON: プレイヤー以外 (飛び道具など) はそのまま", request(0xFF9400, 0x02, 0x13B926), 0x01CC)
running = false
eq("ON: 試合中でなければそのまま", request(P1, 0x02, 0x13B926), 0x01CC)
running = true

-- ---------------------------------------------------------------------------
print("[4] ログ")
eq("Knockdown Logger が OFF なら集めない", #M._events(), 0)
globals.options.knockdown_logger_enable = true
ram[0xFF8081] = 7
ram[P1 + 0x04] = 0x02000000
ram[0x13B926 + 0x16] = 0x05
request(P1, 0x02, 0x13B926)
request(P1, 0x02, 0x13B940)
local ev = M._events()
eq("2 件集めた", #ev, 2)
eq("1 件目は止めた", ev[1] and ev[1].muted, true)
eq("2 件目は止めていない", ev[2] and ev[2].muted, false)
eq("音声番号は止める前の値", ev[1] and ev[1].sound, 0x01CC)
eq("セルの +0x16", ev[1] and ev[1].spec, 0x05)
fc = 100
M.registerAfter()
eq("フレーム側で書く", written ~= nil, true)
eq("中身にセルと状態", written ~= nil and written:find('"cel": "0x13B926"', 1, true) ~= nil
	and written:find('"state": "0x02000000"', 1, true) ~= nil, true)
written = nil
M.registerAfter()
eq("新しいものが無ければ書かない", written, nil)
eq("フックの中ではファイルを開かない", opened_in_hook, 0)

-- ---------------------------------------------------------------------------
print("[5] つなぎ込み")
local cfg = dofile("config.lua").default_training_settings
eq("mute_idle_sounds の初期値は OFF", cfg.mute_idle_sounds, false)
local menu = slurp("menu.lua")
local bgm = menu:find('"BGM On", training_settings, "bgm_on"', 1, true)
local mute = menu:find('"Mute Idle Sounds", training_settings, "mute_idle_sounds", false,', 1, true)
local pb = menu:find('"P1 Min PB Presses"', 1, true)
eq("Game タブ、BGM On のすぐ後", bgm ~= nil and mute ~= nil and pb ~= nil and bgm < mute and mute < pb, true)
local master = slurp("vsav_training_master_script.lua")
eq("起動時に require", master:find('= require "./scripts/idleSound"', 1, true) ~= nil, true)
eq("registerStart を呼ぶ", master:find("idleSoundModule.registerStart()", 1, true) ~= nil, true)
eq("registerAfter を呼ぶ", master:find("idleSoundModule.registerAfter()", 1, true) ~= nil, true)

io.open = real_open
print(fails == 0 and "\n全て通った" or ("\n" .. fails .. " 件 NG"))
os.exit(fails == 0 and 0 or 1)
