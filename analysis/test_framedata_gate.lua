-- A TRANSFORMATION MUST NOT STOP THE MEASUREMENT.
--
-- gameState's match_begun is 0xFF8401 and 0xFF8801 both reading 1, and those
-- drop to 0 while a character is transformed. framedata used it, so Demitri's
-- Bat Spin reset the whole measurement and the readout stayed empty for the
-- entire special - reported as "some specials produce nothing".
--
-- The master script already carries the conservative test for exactly this
-- (see match_actually_running and the note above it). This pins that framedata
-- asks it rather than match_begun, and that it still stops when the match
-- really is over.
--
-- Run from the package root - framedata requires ./scripts/tickData.
--   cd C:/fightcaVSAV-Debug/emulator/fbneo && lua5.1 analysis/test_framedata_gate.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local fails = 0
local function want(what, got, w)
	if got ~= w then
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(w) .. "]")
	else
		print("  ok " .. what)
	end
end

-- The ticker is an Rx subject in the real thing; all framedata does is
-- subscribe, so the callback is captured here and driven by hand.
local captured
local resets = {}
local fd_result = ""
package.loaded["./scripts/tickData"] = {
	reset = function(reason) resets[#resets + 1] = reason end,
	update = function() end,
	formatResult = function() return fd_result end,
	isMeasuring = function() return false end,
	getAbortReason = function() return nil end,
}
-- 測る側は本物と同じく「倒れたら true」。framedata はその true を見て読み手を
-- 白紙に戻す。
local side_now = "P1"
local vsav = {
	capture = function(tick) return { tick = tick, p1 = {}, p2 = {} } end,
	set_side = function(s)
		if s == side_now then return false end
		side_now = s
		return true
	end,
	side = function() return side_now end,
}
package.loaded["./scripts/tickDataVsav"] = vsav

memory = { readbyte = function() return 0 end, readdword = function() return 0 end }
globals = {
	options = { mo_enable_frame_data = true },
	show_menu = false,
	game_state = { match_begun = true },
	truth = { ticker = { subscribe = function(_, fn) captured = fn end } },
	set_last_data = function() end,
	set_last_route = function() end,
}

local fd = dofile("scripts/framedata.lua")
fd.registerStart()
want("購読した", type(captured), "function")

local function tick(n) resets = {} captured(n) return table.concat(resets, ",") end

tick(1)
-- 変身中: 両バイトが 0 になるので match_begun は false。conservative test は
-- true を返す。
globals.match_running = function() return true end
globals.game_state.match_begun = false
want("変身中でも測定を止めない", tick(2), "")

-- 本当に試合が終わったときは止める。
globals.match_running = function() return false end
want("試合が終われば止める", tick(3), "match_not_running")

-- 登場中は測らない。match_running は入場の時点でもう true なので、これだけでは
-- ラウンドが始まる前の行が出てしまう (user, 2026-09-10)。hotkeys_armed が
-- マスタースクリプト側の「ラウンドが生きているか」で、メニューと位置ショート
-- カットが既にこの後ろにいる。
globals.match_running = function() return true end
globals.hotkeys_armed = true
tick(6)
globals.hotkeys_armed = false
want("登場中は止める", tick(7), "round_not_ready")
globals.hotkeys_armed = true
want("ラウンドが始まれば測る", tick(8), "")
-- 試合そのものが終わったときは、理由が別であること。
globals.match_running = function() return false end
want("試合終了は別の理由", tick(9), "match_not_running")
globals.match_running = function() return true end
globals.hotkeys_armed = nil
tick(10)
want("hotkeys_armed が無い環境では今までどおり", tick(11), "")

-- 公開されていない古い環境では match_begun に落ちる。
globals.match_running = nil
globals.hotkeys_armed = nil
globals.game_state.match_begun = true
tick(4)
globals.game_state.match_begun = false
want("未公開なら match_begun を見る", tick(5), "match_not_running")

-- 測る側を倒したら読み手を白紙に戻すこと。倒す前のティックと後のティックが
-- 1 本の道筋として繋がると、誰もやっていない行動が 1 行として出る。
globals.game_state.match_begun = true
tick(12)
want("既定は P1", vsav.side(), "P1")
want("指定が無ければ何も起きない", tick(13), "")
globals.options.mo_frame_data_side = 2
want("側が倒れたら作り直す", tick(14), "side_changed")
want("倒れたあとは P2", vsav.side(), "P2")
want("同じままなら作り直さない", tick(15), "")
globals.options.mo_frame_data_side = 1
want("戻したときも作り直す", tick(16), "side_changed")
want("戻ったら P1", vsav.side(), "P1")
-- 一覧の外の値は P1 として読む。この行が無かった頃の設定ファイルがそれ。
globals.options.mo_frame_data_side = 0
want("一覧の外は P1 のまま", tick(17), "")
globals.options.mo_frame_data_side = nil
want("値が無くても P1 のまま", tick(18), "")

-- 画面に出る行は、どちらを測っているかを自分で名乗ること。スクリーンショット
-- だけで判断できるようにするため。P1 では今までどおり何も足さない。
local shown_data, shown_route = nil, nil
globals.set_last_data = function(v) shown_data = v end
globals.set_last_route = function(v) shown_route = v end
fd_result = "Startup 5t"
globals.options.mo_frame_data_side = 1
tick(19)
fd.registerAfter()
want("P1 では何も足さない", shown_data, "Startup 5t")
globals.options.mo_frame_data_side = 2
tick(20)
fd.registerAfter()
want("P2 では側を名乗る", shown_data, "P2  Startup 5t")
-- 何も測れていない行に印だけ出しても読めない。
fd_result = ""
fd.registerAfter()
want("空の行には印も足さない", shown_data, "")
want("道筋の行も空のまま", shown_route, "")

if fails == 0 then print("全て通った") else print(fails .. " 件 NG") os.exit(1) end
