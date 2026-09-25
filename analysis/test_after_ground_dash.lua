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
	-- The LP before it is out first: busy - no permission bit, not in air
	-- neutral. A free tick with nothing having happened since is a refused
	-- press, which After now waits out in the air (2026-09-25, below).
	ram[CEL + 1] = 0
	tick(d, 1, 0x14)
	want(action .. " waits while the move before it is out", queued, nil)
	ram[CEL + 1] = 2
	tick(d, 1, 0x14)
	want(action .. " can still start in air", queued ~= nil, true)
end

-- IN THE AIR, A REFUSED PRESS DOES NOT USE UP THE STEPS BEHIND IT.
--
-- Anakaris's float stops taking attacks before it lands. The press was
-- refused, the dummy stayed free in air neutral, and every After behind it
-- went out on the next ticks - refused too. Nothing was left for after the
-- landing (user, 2026-09-25). In the air an After now waits for the dummy to
-- have been busy since the step before it; the landing is that.
do
	local d = setup("atk", false)
	for _ = 1, 6 do tick(d, 1, 0x06) end   -- free in the air, nothing happened
	want("air: a refused press does not drain the next After", queued, nil)
	ram[CEL + 1] = 0
	ram[P2 + 0x07] = 0x04                  -- the landing cel: busy
	tick(d, 1, 0x06)
	want("air: not on the landing cel itself", queued, nil)
	ram[P2 + 0x07] = 0
	tick(d, 0, 0)                          -- down, and free
	want("fires on the ground after the landing", queued ~= nil, true)
end

-- On the ground free is still enough. Waiting for a busy spell there could
-- stop a list for good.
do
	local d = setup("atk", false)
	tick(d, 0, 0)
	want("ground: free is still enough", queued ~= nil, true)
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
