-- Run from scripts/: lua5.1 ../analysis/test_after_ground_dash.lua
-- After must wait until a ground dash can run, even when air attacks are
-- available. Air Dash is a separate action with the same input motion.
local P2, CLOCK, CEL = 0xFF8800, 0xFF8081, 0x1000
local ram = {}
memory = {
	readbyte = function(a) return ram[a] or 0 end,
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
local queued
function queue_input_sequence(d, s)
	queued = s
	d.pending_input_sequence = { sequence = s, current_frame = 1 }
end
local R = dofile("actionSequenceRunner.lua")
local fails = 0
local function want(label, actual, expected)
	if actual ~= expected then
		fails = fails + 1
		print("NG " .. label .. ": " .. tostring(actual) .. " / " .. tostring(expected))
	end
end
local function setup(action, loop, timing)
	ram = { [0xFF8B82] = 5, [P2 + 0x1C] = CEL, [CEL + 1] = 2 }
	queued = nil
	R.cancel()
	local step = { action = action, button = "MK", lever = "none", wait = -1, timing = timing }
	local head = { action = "atk", button = "LP", lever = "none", wait = 0 }
	training_settings = {
		action_steps_loop = loop,
		action_steps_loop_wait = timing == "landing" and -2 or -1,
		action_sequences = { reversal = { ["5"] = {
			version = 1, steps = loop and { step } or { head, step },
		} } },
	}
	R.arm("reversal")
	return {}
end
local function tick(d, air, state)
	ram[CLOCK] = ((ram[CLOCK] or 0) + 1) % 256
	ram[P2 + 0x38] = air
	ram[P2 + 0x06] = state or 0
	R.service(d)
end

for _, loop in ipairs({ false, true }) do
	for _, action in ipairs({ "dash.f", "dash.b", "dashc.f", "dashc.b", "dash" }) do
		local d = setup(action, loop)
		for i = 1, 8 do tick(d, 1, 0x14) end
		want(action .. " airborne, loop=" .. tostring(loop), queued, nil)
		tick(d, 0, 0x06)
		want(action .. " landing recovery", queued, nil)
		tick(d, 0, 0)
		want(action .. " grounded and free", queued ~= nil, true)
	end
end

for _, action in ipairs({ "atk", "air.f", "air.b" }) do
	local d = setup(action, false)
	tick(d, 1, 0x14)
	want(action .. " can still start in air", queued ~= nil, true)
end

-- Landing must still start the run-up in the air at its existing lead.
for _, loop in ipairs({ false, true }) do
	local d = setup("dash.f", loop, "landing")
	local step = R.schedule("reversal")[loop and 1 or 2]
	seq_ticks_to_landing = function() return step.lead + 3 end
	tick(d, 1, 0x14)
	want("Landing waits ahead of lead", queued, nil)
	seq_ticks_to_landing = function() return step.lead end
	tick(d, 1, 0x14)
	want("Landing keeps airborne run-up", queued ~= nil, true)
end

print(fails == 0 and "REP_OK" or (fails .. " REP_NG"))
os.exit(fails == 0 and 0 or 1)
