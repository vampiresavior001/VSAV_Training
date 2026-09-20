-- Run from scripts/: lua5.1 ../analysis/test_landing_ground_recovery.lua
-- A failed dash can leave a grounded normal and stale falling physics.
-- Landing must wait for that normal to recover, then continue like After.
local P2, CLOCK, CEL = 0xFF8800, 0xFF8081, 0x1000
local ram = {}
memory = {
	readbyte = function(a) return ram[a] or 0 end,
	readword = function(a) return ram[a] or 0 end,
	readdword = function(a) return ram[a] or 0 end,
}
gui = { text = function() end, box = function() end }
emu = { framecount = function() return 1 end }
globals = { dummy = { guard_action = "sequence" }, options = {} }
function mark_training_settings_dirty() end
function dash_attack_ticks_for() return nil end
local csrc = assert(io.open("controller.lua")):read("*a")
local first = assert(csrc:find("function make_input_sequence", 1, true))
local last = assert(csrc:find("\nend", csrc:find("return _sequence", first, true), true))
assert(loadstring(csrc:sub(first, last + 3)))()

-- Use the production predictor for the recorded grounded values, rather than
-- assuming that it returns nil when $38 says the character is on the floor.
local gsrc = assert(io.open("guardCancel.lua")):read("*a")
first = assert(gsrc:find("local function ticks_to_landing()", 1, true))
last = assert(gsrc:find("\nend", first, true))
local predict = assert(loadstring(gsrc:sub(first, last + 3)
	.. "\nreturn ticks_to_landing"))()

local queued, gate
function queue_input_sequence(d, s)
	queued = s
	d.pending_input_sequence = { sequence = s, current_frame = 1 }
end
-- Diagnostics stay in memory; offline tests never write emulator logs.
seq_debug = { mark_write = function(name, val)
	if name == "land_gate" then gate = math.floor(val / 100000) end
end }
local fails = 0
local function want(label, actual, expected)
	if actual ~= expected then
		fails = fails + 1
		print("NG " .. label .. ": " .. tostring(actual) .. " / " .. tostring(expected))
	end
end
local function tick(R, d, air, action, freeze)
	ram[CLOCK] = ((ram[CLOCK] or 0) + 1) % 256
	ram[P2 + 0x38] = air
	ram[P2 + 0x06] = action or 0
	ram[P2 + 0x5C] = freeze or 0
	R.service(d)
end
local function setup(loop, cid)
	ram = { [0xFF8B82] = cid, [P2 + 0x1C] = CEL, [CEL + 1] = 2 }
	seq_ticks_to_landing = predict
	local dash = { action = "dash.f", wait = 0 }
	local normal = { action = "atk", button = "MK", lever = "forward", wait = 1 }
	if not loop then dash.wait, dash.timing = -1, "landing" end
	training_settings = {
		action_steps_loop = loop,
		action_steps_loop_wait = -2,
		action_sequences = { reversal = { [tostring(cid)] = {
			version = 1, steps = loop and { dash, normal } or { normal, dash },
		} } },
	}
	local R, d = dofile("actionSequenceRunner.lua"), {}
	R.arm("reversal")
	if loop then
		-- Complete the last normal's input, so service refills the loop with
		-- the first dash and applies Loop Wait: Landing on the next tick.
		tick(R, d, 0, 0)
		assert(queued ~= nil, "last normal should be delivered")
		d.pending_input_sequence = nil
	end
	queued, gate = nil, nil
	return R, d, R.schedule("reversal")[loop and 1 or 2].lead
end

for _, loop in ipairs({ false, true }) do
	local label = loop and "Loop Landing" or "Step Landing"
	local R, d = setup(loop, 5)
	-- kd_c05_s02, frames 3536..3706, archived before the grounded fix:
	-- y=40, floor=40, but the old falling velocity/acceleration remain.
	ram[P2 + 0x14] = 2621440
	ram[P2 + 0x44] = -135168
	ram[P2 + 0x4C] = -24576
	ram[P2 + 0x3A] = 40
	want(label .. " real predictor returns stale 1", predict(), 1)
	tick(R, d, 0, 0)
	want(label .. " does not skip straight past the previous press", queued, nil)
	for i = 1, 12 do tick(R, d, 0, 0x0A, i < 5 and 11 or 0) end
	want(label .. " waits throughout standing MK", queued, nil)
	tick(R, d, 0, 0x04)
	want(label .. " waits for full ground recovery", queued, nil)
	tick(R, d, 0, 0)
	want(label .. " sends the next dash on recovery", queued ~= nil, true)
	want(label .. " uses the recovery gate", gate, 2)
end

-- The working Morrigan and Sasquatch landing run-up must still win over the
-- deadline, including when the airborne attack becomes free before landing.
for _, cid in ipairs({ 5, 10 }) do
	for _, loop in ipairs({ false, true }) do
		local R, d, lead = setup(loop, cid)
		ram[CEL + 1] = 0
		local to_land = lead + 3
		seq_ticks_to_landing = function() return to_land end
		tick(R, d, 1, 0x14)
		ram[CEL + 1] = 2
		for i = 1, 4 do tick(R, d, 1, 0x14) end
		want("airborne deadline must not release early", queued, nil)
		to_land = lead
		tick(R, d, 1, 0x14, 11)
		want("frozen landing waits", queued, nil)
		tick(R, d, 1, 0x14)
		want("unchanged landing run-up", queued ~= nil, true)
		want("uses predicted landing gate", gate, 1)
	end
end

-- No jump and no prediction must still recover; that was the original
-- deadline's purpose and remains distinct from stale grounded physics.
do
	local R, d = setup(true, 8)
	seq_ticks_to_landing = function() return nil end
	tick(R, d, 0, 0x0A)
	want("no-jump pattern waits for the normal", queued, nil)
	tick(R, d, 0, 0)
	want("no-jump pattern continues", queued ~= nil, true)
end

print(fails == 0 and "REP_OK" or (fails .. " REP_NG"))
os.exit(fails == 0 and 0 or 1)
