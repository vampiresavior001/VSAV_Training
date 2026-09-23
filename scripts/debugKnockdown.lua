-- debugKnockdown.lua
--
-- MEASUREMENT ONLY. Changes nothing about how the tool behaves.
--
-- Chasing the one symptom still left: a reversal that gets stuffed by a meaty
-- jump-in. On the frame after the poke, 0xFF8804 goes from 02 00 0E 00 to
-- 02 02 00 02 - the move is wiped before it ever starts.
--
-- That was written off as the hack being unable to reproduce a move's first
-- invincible frame. But clearing 0xFF8944 makes it stop happening, so the
-- outcome does depend on memory state, not only on timing. 0xFF8944 holds
-- something inherited from before the knockdown, which is why this records
-- from the ATTACK THAT CAUSED THE KNOCKDOWN rather than from the reversal.
--
-- What the per-reversal logs already showed, for context:
--
--   P2+0x144  01 in every failing reversal, 00 in every working one
--   P2+0x140  0A in every failing reversal, 00 in every working one
--   P2+0x1A7  reaches 1B in failing ones, only 19-1A in working ones
--
-- 0x1A7 looks like a stage counter for the knockdown, and the failures are
-- the ones that got further along it. So the question this logger is meant to
-- answer: what does the attacking move set, and does a different attack leave
-- a different value behind?
--
-- Recording starts when P2 is hit (0xFF8805 becomes non-zero) and runs long
-- enough to cover knockdown -> wakeup -> reversal -> recovery. Delta encoded,
-- so the window can be long without the file being huge.
--
-- Output: reversal_logs/kd_s01.json .. kd_s12.json (rotating)
-- The folder must already exist - io.open does not create directories.
--
-- REVISION - collection reliability. The invisibility case only shows up when
-- the two characters swap sides, so it is rare, and the first version of this
-- logger could not survive a long hunt for it:
--
--   * It stopped dead once 12 files existed, and it recorded EVERY hit -
--     including hits with no reversal in them. Twelve unrelated knockdowns
--     were enough to fill the folder and silently switch logging off, so a
--     rare bug occurring later was never written at all.
--
-- Two changes, both confined to this file:
--
--   1. A recording with no poke in it is discarded and does NOT consume a
--      slot. Only knockdowns where the script actually issued a reversal are
--      kept, which is the only case that can exhibit the bug.
--   2. The 12 files are a ring. Slot filenames are fixed (kd_s01 .. kd_s12)
--      and are overwritten oldest-first, so logging never stops and the most
--      recent 12 qualifying knockdowns are always on disk. Fixed names mean
--      no file deletion is needed, which keeps this working regardless of
--      whether os.remove is available in the emulator's Lua sandbox.
--
-- Ordering is recoverable from the JSON itself: every file carries "seq"
-- (monotonic, higher = more recent) and "session" (incremented each time the
-- emulator start callback fires), so leftovers from an earlier run cannot be
-- mistaken for the newest recording. File modification time agrees with seq.
--
-- STILL A CONSTRAINT, not fixable here: a recording is only written once its
-- full 260-frame window has elapsed. Resetting or closing the emulator the
-- instant the bug is seen throws that recording away. After reproducing the
-- invisibility, let the game run for ~5 more seconds before stopping.
--
-- REVISION - repeated reversals with no neutral in between. A recording used
-- to only START on a hit that followed an idle frame. That is wrong for a
-- reversal -> meaty -> reversal -> meaty sequence where the dummy never
-- reaches neutral: only the very first hit in the whole sequence qualified,
-- so once its window closed every later poke in the same sequence went
-- completely unlogged. The idle requirement is gone; a new window now opens
-- the moment the previous one closes, as long as the dummy is still hurt.
-- Safe to drop - the empty-recording discard above already does what the
-- idle check was there to do (stop unrelated hits from burning ring slots).

-- Bumped by hand on every meaningful edit to this file or guardCancel.lua's
-- reversal-timing experiments. Stamped into every JSON this module writes
-- (kd_*.json, rb_freq.json, rev4_freq.json) so a stale-script problem -
-- FBNeo/Fightcade not fully restarted after an edit, so the OLD bytecode is
-- still running - shows up immediately as an old version number in the next
-- batch of logs, instead of looking like a silent logic bug.
local SCRIPT_VERSION = "v11.7.11"

local LOG_DIR   = "reversal_logs"

-- P2 (the one being knocked down), P1 (whose attack caused it), and the
-- projectile pool, so a fireball-based knockdown is visible too.
local REGIONS = {
  -- P2 widened to 0x400: the invisibility case has not shown up in anything
  -- inside the first 0x200, so whatever drives it is likely further out -
  -- sprite/palette state rather than the action state already covered.
  { 0xFF8800, 256 },   -- 0xFF8800 .. 0xFF8BFF   P2, whole object
  { 0xFF8400, 256 },   -- 0xFF8400 .. 0xFF87FF   P1, whole object (was half)
  { 0xFF9400, 512 },   -- 32 projectile objects
  -- GLOBALS. Added because a search for whatever ends the long hit-stun
  -- sub-phase ($07 = 0x0C) came up empty, and it could not have found it: the
  -- phase lasts 3 to 37 ticks with nothing in either player object predicting
  -- it, and this range was never being recorded. A counter that runs the
  -- phase would show up here as a byte whose value at the start of the phase
  -- equals the ticks remaining.
  --
  -- 0xFF8000 is A5 - the global struct the engine keeps its match state in
  -- (0xFF8081 the tick counter, 0xFF8116 frameskip, 0xFF815D the freeze flag,
  -- and so on), so it is the obvious place for one.
  { 0xFF8000, 256 },   -- 0xFF8000 .. 0xFF83FF
}

local WINDOW    = 260    -- frames from the hit onwards
local MAX_FILES = 100    -- ring depth for ordinary recordings
local MARK_FILES = 60    -- separate, protected ring for MARKED recordings

local rec           = nil
local last_raw      = nil

-- Shared monotonic counter stamped on every writes/execs entry (TEMPORARY,
-- see the note above on_write below). Frame number alone cannot order two
-- events that land on the SAME frame - a write and an exec can both be
-- logged at f=100 with no way to tell which happened first in real CPU
-- execution order. This does: every hook invocation increments it once, in
-- true chronological order, regardless of which hook or which address.
local event_seq     = 0

-- Ring state. seq is monotonic for the whole Lua session so the newest file is
-- always identifiable; slot is seq wrapped into 1..MAX_FILES.
local seq           = 0
local session       = 0
local mark_seq      = 0

-- MARK KEY (Lua hotkey 2).
--
-- Everything measured so far had to guess which recording showed the symptom,
-- because nothing in RAM says "the player saw something wrong". Guessing is
-- what produced the disproven 0x140 theory: the analysis assumed exactly one
-- recording was affected, and a single byte duly separated it from the rest.
--
-- Press the key the moment something is seen on screen. The frame is stored in
-- the recording, which turns "which of these is the bad one" from an
-- assumption into data.
--
-- Two uses:
--   * flag a reversal that came out invisible / got stuffed
--   * flag a MANUALLY performed reversal, to capture what the game itself
--     writes when a real input starts the move. A manual reversal issues no
--     poke, so without a mark it would be discarded as uninteresting - marked
--     recordings are kept whether or not the script poked.
--
-- NO LONGER BOUND TO A HOTKEY.
--
-- This used to sit on Lua key 2, which is now position.lua's. The marking
-- path below is kept because it is the only way to keep a recording that the
-- script never poked, but nothing raises the flag any more, so marking is
-- effectively off. To bring it back for a measurement session, give it a key
-- the tool does not already claim (the master takes 1, 3, 4 and 5, and
-- position.lua takes 2) and set mark_pending from that callback - reading
-- globals.hotkeys_armed first, so it cannot fire before the match is running.
local mark_pending  = false

-- THE DIAGNOSTIC HOOKS COST SOMETHING EVEN WHEN NOTHING IS LOGGED.
--
-- Eight of them used to be registered at load time: write hooks on
-- 0xFF8922 (buttons), 0xFF8925 (lever) and 0xFF8806 (action), which the
-- game touches many times per tick, plus four instruction hooks. Every one
-- of those writes crossed into Lua and came straight back out again.
--
-- They are held here instead and attached only while the logger is on.
-- Passing nil to the same register call detaches them again.
local DIAG_HOOKS = {}
local diag_attached = nil

local function is_enabled()
  return globals and globals.options and globals.options.knockdown_logger_enable == true
end

local function sweep()
  local out = {}
  local n = 0
  for _, r in ipairs(REGIONS) do
    local base, count = r[1], r[2]
    for i = 0, count - 1 do
      n = n + 1
      out[n] = memory.readdword(base + i * 4)
    end
  end
  return out
end

local function row(full)
  local raw = sweep()
  local out = {
    f   = globals.current_frame,
    lg  = memory.readbyte(0xFF8081),
    -- Training tool's own speed setting (0 = Normal, 1-3 = Turbo 1-3 - see
    -- menu.lua's "Game Speed" item / vsav-test-menu.lua). Recorded per row
    -- so a batch of logs can be told apart by speed without having to ask.
    gs  = globals.options and globals.options.game_speed,
    -- Facing for both characters. The remaining "the character turns
    -- invisible" case is reported as happening more often when the two swap
    -- sides, so a side switch needs to be visible in the log even on frames
    -- where nothing else is recorded.
    fa1 = memory.readbyte(0xFF840B),
    fa2 = memory.readbyte(0xFF880B),
    -- X positions, so a crossover is identifiable independently of the
    -- facing bytes.
    x1  = memory.readword(0xFF8410),
    x2  = memory.readword(0xFF8810),
  }
  if full then
    out.base = raw
  else
    local d = {}
    for i = 1, #raw do
      if raw[i] ~= last_raw[i] then
        table.insert(d, i)
        table.insert(d, raw[i])
      end
    end
    out.d = d
  end
  last_raw = raw
  return out
end

local function write_out()
  local r = rec
  rec = nil
  last_raw = nil
  if not r then return end

  -- Nothing to learn from a knockdown with no scripted reversal AND no mark.
  -- Drop it without advancing either ring, so ordinary knockdowns cannot push
  -- the interesting ones out. A mark alone is enough to keep a recording:
  -- that is how a manually performed reversal gets captured.
  --
  -- FIX: BUG FOUND. guardCancel.lua's reversal timing (on_reversal_window_write/
  -- service_held_reversal) only ever calls mark_hold() - never mark_poke()/
  -- mark_queue() - so every recording of an actual reversal attempt had
  -- holds populated but pokes/queues empty, and this discarded ALL of them
  -- silently. No kd_s*.json files were ever written despite reversal
  -- attempts genuinely happening - the mechanism could have been working
  -- perfectly and there was still no way to see it.
   local has_kept_write = false
   for _, w in ipairs(r.writes or {}) do
     -- KEEP THE ONES WHERE NOTHING CAME OUT (v300).
     --
     -- The discard below throws away a recording with no poke, mark, queue or
     -- hold in it - which is precisely the shape of a recovery where the
     -- reversal never fired at all. That is the case worth looking at, so the
     -- arm's own diagnostics count as a reason to keep: hs_armthrow21 (the
     -- throw escape arm), arm_edge/arm_result, and the sequence walker.
     if w.addr and (w.addr:find("csp") or w.addr:find("blk_neutral")
                    or w.addr:find("armthrow") or w.addr:find("arm_")
                    or w.addr:find("seq")) then has_kept_write = true; break end
   end
   if #r.pokes == 0 and #r.marks == 0 and #r.queues == 0 and #r.holds == 0 and not has_kept_write then return end

  -- Marked recordings go to their own ring so an unmarked knockdown can never
  -- overwrite the one the player actually flagged.
  -- THE RING IS PER CHARACTER.
  --
  -- seq is a Lua local, so it resets to 0 on every restart and the ring starts
  -- writing kd_s01 again. A Lua change needs a full restart, and so does
  -- changing character, which meant testing a second character silently
  -- overwrote the first one's recordings from slot 1 up.
  --
  -- Putting P2's character id in the filename gives each character its own
  -- ring, so a character swap cannot destroy the previous batch. Restarting
  -- with the SAME character still overwrites - that is unavoidable without
  -- reading the directory, which this Lua has no way to do - but that case is
  -- the one where the recordings are comparable anyway.
  --
  -- $382 is the character id, not the current move: charMoves.lua resolves
  -- base+0x382 to the character name, and 0x024E8A indexes the per-character
  -- handler table at $bd47a with it. P2's object is at 0xFF8800.
  -- ROM DATA TABLES, READ THROUGH THE CPU MAP.
  --
  -- The mame_code/ listings are an OPCODE-space dump. CPS2 encrypts the program
  -- ROM and MAME decrypts opcodes only, so code disassembles correctly but every
  -- DATA table in those listings is garbage. Verified against the known attack
  -- table at 0x0764EA, whose +5 byte is the $59 stun class and can only be 0, 1
  -- or 2 - in the listing it reads 226/126/253.
  --
  -- memory.readbyte goes through the CPU map and sees the decrypted data, so the
  -- tables are dumped from here instead. A few hundred bytes per recording.
  --
  --   0x0764EA  attack data, 8 bytes/entry. Correctness check: +5 must be 0/1/2
  --   0x0BD47A  the per-character handler table that 0x024E90 indexes with
  --             character id * 4 - this identifies each character's wake-up code
  --   0x0283C4  random amounts a DIRECTION press takes off the stun timer
  --   0x028404  the same for a BUTTON press (section 8.6.87)
  local function rom_dump(base, n)
    local t = {}
    for i = 0, n - 1 do t[i + 1] = memory.readbyte(base + i) end
    return t
  end

  -- WHERE THE WAKE-UP LENGTH ACTUALLY COMES FROM (ROM, section 8.6.206).
  --
  --   027EC0  movea.l #$bcf7a, A0     per-character animation script list
  --   027ECE  move.b ($382,A6), D1 / lsl.w #2 / movea.l (A0,D1.w), A0
  --   027EDA  andi.w #$ff, D0 / add.w D0, D0 / move.w (A0,D0.w), D0
  --   027EE4  lea (A0,D0.w), A0       the script for animation D0
  --   027EE8  move.l A0, ($1c,A6)
  --   027EEC  move.l (A0), ($20,A6)   $20 := cel duration, $21 := cel flags
  -- and the stepper at 0x027F70:
  --   027F70  subq.b #1, ($20,A6) / bne     count the current cel down
  --   027F7A  move.b ($1,A0), D0            flags: 0 plain, bit7 jump, bit6 END
  --   027F88  st ($21,A6)                   bit6 -> $21 = 0xFF, script finished
  --   027F96  lea ($18,A0), A0              THE NEXT CEL IS 24 BYTES ON
  -- The wake-up handler (generic 0x024EA4, or the character's own) then does
  --   024F02  tst.b ($21,A6) / bpl $27f70
  --   024F0A  move.l #$2020400, ($4,A6)     <- the free-1 signature
  --
  -- So the terminal value of $1a7 is THE SUM OF THE CEL DURATIONS of the
  -- wake-up animation. That is why it cannot be a constant, and why $21 == 0x40
  -- (bit 6, the END flag of the cel currently playing) sits a different number
  -- of ticks before free for every character - Gallon one, Morrigan three.
  --
  -- Dumped from here because animation data is DATA space: the mame_code
  -- listings are an opcode-space dump and read it as garbage. 0x44 is the
  -- ordinary wake-up, 0x45/0x47 the roll, 0x46/0x48 the get-up after a roll.
  --
  -- Collecting this turns the measured KD_END_1A7 table into a derived one,
  -- for all 16 characters instead of the 8 that have been played.
  local function anim_script(cid, anim)
    local ok, out = pcall(function()
      local function rb(a) return memory.readbyte(a) end
      local function rw(a) return rb(a) * 256 + rb(a + 1) end
      local function rl(a) return rw(a) * 65536 + rw(a + 2) end
      local base = rl(0x0BCF7A + cid * 4)
      if base > 0x3FFFFF then return { base = base, err = "range" } end
      local scr = base + rw(base + anim * 2)
      local cels, total, seen = {}, 0, {}
      for _ = 1, 48 do
        if scr > 0x3FFFFF or seen[scr] then break end
        seen[scr] = true
        local dur, flg = rb(scr), rb(scr + 1)
        table.insert(cels, dur)
        table.insert(cels, flg)
        total = total + dur
        if flg >= 0x80 then scr = rl(scr + 0x18)
        elseif flg % 128 >= 64 then break
        else scr = scr + 0x18 end
      end
      return { base = base, total = total, cels = cels }
    end)
    return ok and out or { err = "pcall" }
  end

  local cid = memory.readbyte(0xFF8B82)
  local path
  if #r.marks > 0 then
    mark_seq = mark_seq + 1
    path = LOG_DIR .. string.format("/kd_c%02X_m%02d.json", cid,
                                    ((mark_seq - 1) % MARK_FILES) + 1)
  else
    seq = seq + 1
    path = LOG_DIR .. string.format("/kd_c%02X_s%02d.json", cid,
                                    ((seq - 1) % MAX_FILES) + 1)
  end

  write_object_to_json_file({
    rom = {
      attack_0764EA    = rom_dump(0x0764EA, 64),
      -- TWO per-character tables, not one.
      --
      -- 0x0BD47A is the WAKE-UP handler table (0x024E90 indexes it). Using it
      -- to decide which address range belongs to which character was wrong:
      -- command recognition is dispatched from a DIFFERENT table at 0x0BD3FA,
      --
      --     026144  move.b ($382,A6), D0     character id
      --     02614A  lsl.w  #2, D0
      --     02614C  movea.l #$bd3fa, A0
      --     026152  movea.l (A0,D0.w), A0
      --     026156  jsr (A0)                 per-character command checks
      --
      -- so the lea/jsr/bne blocks that list a character's specials live
      -- wherever THAT points, and reading the range after the wake-up handler
      -- picked up a different character's moves entirely. Dumping from 0x0BD3FA
      -- covers both tables in one go (0x80 apart, 16 longs each).
      chartable_0BD3FA = rom_dump(0x0BD3FA, 192),
      -- The wake-up animations of the character being knocked down, with the
      -- cel durations summed. anim44 is the ordinary wake-up; 45/47 the roll
      -- and 46/48 the get-up that follows it.
      anim44 = anim_script(cid, 0x44),
      anim45 = anim_script(cid, 0x45),
      anim46 = anim_script(cid, 0x46),
      anim47 = anim_script(cid, 0x47),
      anim48 = anim_script(cid, 0x48),
      anim_list_0BCF7A = rom_dump(0x0BCF7A, 64),
      -- EVERY character's ordinary wake-up, not just the one being played.
      --
      -- The script list at 0x0BCF7A is indexed by character id and the data is
      -- in ROM whoever is loaded, so one recording yields the whole roster.
      -- Measured on the v131 batch, terminal $1a7 = this total + 2 for all
      -- eight characters that have been played; collecting the other eight
      -- fills the table without anyone having to play them.
      -- The BLOCK animations, for every character. 0x02397A picks 0x0C when
      -- standing and 0x0D when crouching ($121); 0x0E is the air block the
      -- $38 branch at 0x023954 leads to. Measured block recovery is 24, 29 or
      -- 33 ticks from the blocked hit, and $158 is a fixed 14, so the rest has
      -- to come from the animation - these are what to check that against.
      anim0C_all = (function()
        local t = {}
        for _c = 0, 15 do t[_c + 1] = (anim_script(_c, 0x0C) or {}).total end
        return t
      end)(),
      anim0D_all = (function()
        local t = {}
        for _c = 0, 15 do t[_c + 1] = (anim_script(_c, 0x0D) or {}).total end
        return t
      end)(),
      anim0E_all = (function()
        local t = {}
        for _c = 0, 15 do t[_c + 1] = (anim_script(_c, 0x0E) or {}).total end
        return t
      end)(),
      anim44_all = (function()
        local t = {}
        for _c = 0, 15 do t[_c + 1] = (anim_script(_c, 0x44) or {}).total end
        return t
      end)(),
      anim45_all = (function()
        local t = {}
        for _c = 0, 15 do t[_c + 1] = (anim_script(_c, 0x45) or {}).total end
        return t
      end)(),
      anim46_all = (function()
        local t = {}
        for _c = 0, 15 do t[_c + 1] = (anim_script(_c, 0x46) or {}).total end
        return t
      end)(),
      -- HIT-STUN LENGTH TABLES, indexed by $54.
      --
      -- 0x027D2C picks one of three by $1a8 and $a, then
      --     027D46  move.b ($54,A6), D0
      --     027D4A  move.b (A0,D0.w), ($26,A6)
      -- and 0x024CA4 counts $26 down; when it hits zero the velocities decide
      -- whether 0x027D52 runs, which is the only place $140 becomes 0x0A.
      --
      -- $54 comes from the attack's own data at hit time, and measured over
      -- 77 spans it separates the outcome perfectly: 4 air, 5 knockdown,
      -- 64 hit stun, 73 knockdown. Reading these tables turns that from four
      -- observed constants into the rule the game actually applies, which is
      -- what a per-character-safe implementation needs.
      stun_28be0 = rom_dump(0x028BE0, 96),
      stun_28c40 = rom_dump(0x028C40, 96),
      stun_28ca0 = rom_dump(0x028CA0, 96),
      mash_dir_0283C4  = rom_dump(0x0283C4, 64),
      -- Two small tables that sit INSIDE code and are therefore read as
      -- garbage in the mame_code listings. Both currently rest on the
      -- listing's own bytes, which happen to look semantically right - the
      -- point of dumping them is to stop that being an assumption.
      --   0x0221C8  the lever bit0/bit1 swap used by the facing flip at
      --             0x022194 (expected 00 02 01 03)
      --   0x02A55A  the command recogniser's per-step timeout, picked with a
      --             5-bit random index at 0x02A52E (expected 0x0E..0x13)
      swap_0221C8      = rom_dump(0x0221C8, 4),
      steptmo_02A55A   = rom_dump(0x02A55A, 32),
      mash_btn_028404  = rom_dump(0x028404, 64),
      -- PUSH BLOCK probability, one LONG per press count, read at 0x027616
      -- with the count shifted left 2. The count is capped at 7 there because
      -- 8 or more short-circuits to a guaranteed hit at 0x02760E, so only
      -- entries 1..7 are ever indexed. This is a DATA table, so the listings
      -- cannot be trusted for it - the bytes have to come from the machine.
      pb_prob_028D50   = rom_dump(0x028D50, 32),
      -- GUARD STUN IS A PUSHBACK SCRIPT, NOT A COUNTER.
      --
      -- 0x024A22 dispatches guard on $07. Step 2 (0x024A3A) calls 0x027DE4
      -- every tick, and guard ends the instant that returns nonzero:
      --
      --     027DEA  move.b ($59,A6), D0     <- reaction type from 0x0764EA+5
      --     027DF0  lea    ($285de,PC), A0  <- table of word offsets
      --     027DF8  lea    (A0,D0.w), A0    <- this type's script
      --     027DFC  move.w ($164,A6), D0    <- cursor, one byte per tick
      --     027E00  move.b (A0,D0.w), D0
      --     027E04  bmi    $27e2a           <- negative byte = script over
      --     027E22  add.w  D0, ($10,A6)     <- otherwise it is X pushback
      --
      -- So stun length == number of non-negative bytes in the script, and the
      -- pushback distance and the stun length are the same data. That is why
      -- sweeping P1 and P2 for a countdown found nothing: there is no counter,
      -- only a cursor ($164, logged as pbk) walking a list.
      --
      -- The table is DATA, so the mame_code listings show the wrong bytes for
      -- it (CPS2 decrypts opcode fetches only, section 8.6.108). Read here,
      -- from the running machine, where the bytes are what the game sees.
      guard_push_raw   = rom_dump(0x0285DE, 64),
      guard_scripts    = (function()
        local _out = {}
        for _s = 0, 15 do
          local _off = memory.readword(0x0285DE + _s * 2) % 0x10000
          if _off >= 0x8000 then _off = _off - 0x10000 end
          local _a = 0x0285DE + _off
          local _b = {}
          for _i = 0, 63 do
            local _v = memory.readbyte(_a + _i) % 0x100
            _b[#_b + 1] = string.format("%02x", _v)
            if _v >= 0x80 then break end
          end
          _out[_s + 1] = string.format("%d:%+d:%s", _s, _off, table.concat(_b))
        end
        return table.concat(_out, " ")
      end)(),
      -- COMMAND DEFINITIONS.
      --
      -- The recogniser's per-command routines at 0x29DC2..0x29FXX do nothing
      -- but load a pointer and jump to a shared matcher:
      --
      --     029DEA  lea ($2a636,PC), A3     <- DPF's data
      --     029DEE  bra $29f4a              <- the matcher
      --
      -- so the actual accepted input list for every command lives in a table
      -- from 0x02A610, roughly 8 bytes per entry, 44 commands. That is DATA,
      -- so it cannot be read from the listings (section 8.6.108) - dumping it
      -- here settles what each motion really requires instead of relying on
      -- the hand-written table in controller.lua.
      -- 512, not 256: there are TWO matchers. 0x29DEA and friends branch to
      -- $29f4a with data from 0x2A610, but 0x29EDA..0x29F0A branch to $2a2ea
      -- with data from 0x2A738 - and that second group is what Victor's $318
      -- and $300 use, which is where a 360 would live. 256 bytes stopped at
      -- 0x2A710 and missed all of it.
      commands_02A610  = rom_dump(0x02A610, 512),
    },
    note = "From the hit that knocked P2 down through the reversal. regions " ..
           "lists the swept ranges in order; index n in base/d maps to them " ..
           "consecutively. First row carries base (everything), later rows " ..
           "carry d = flat {index, value, ...} of CHANGED dwords only. " ..
           "pokes = frames the script wrote a reversal, marks = frames the " ..
           "player pressed the mark key. Unmarked recordings rotate through " ..
           "kd_s01..kd_s" .. tostring(MAX_FILES) .. ", marked ones through " ..
           "kd_m01..kd_m" .. tostring(MARK_FILES) .. " so they cannot be " ..
           "overwritten by ordinary knockdowns. Compare seq/session to order " ..
           "them, highest seq within the highest session is the newest. " ..
           "pokes empty + marks non-empty = a MANUALLY performed reversal, " ..
           "recorded as a reference for what the game writes by itself. " ..
           "holds = TEMPORARY, one entry per frame from service_held_reversal " ..
           "in guardCancel.lua, the SCRIPT's own view of the 'reversal' " ..
           "pre-buffer (pending_input_sequence) - not from the memory sweep. " ..
           "writes = TEMPORARY, one entry per WRITE to 0xFF8974/0xFF89A7/" ..
           "0xFF8922/0xFF8806 via memory.registerwrite - sub-frame, can have " ..
           "several entries on the same f as each other and as a rows/holds " ..
           "entry for that frame. execs = TEMPORARY, one entry per EXECUTION " ..
           "of PC 0x26D7A via memory.registerexec (the instruction shared by " ..
           "both the MOVE and NOTHING 0xFF8806-write chains, right before " ..
           "they fork to 0x29854 vs 0x26D5C) - full d0-d7 and sr at that PC.",
    script_version = SCRIPT_VERSION,
    -- EXPERIMENT: snapshot of the relevant training-menu settings at the
    -- moment this recording was written out, so a batch can be checked
    -- against what the user INTENDED to have set instead of trusting
    -- memory - a session reported as "direct memory poke was on" showed
    -- zero poked_direct_mem events, and this settled whether the toggle
    -- really was on without needing another round-trip to ask.
    -- FIX: dropped the reversal_btn_delay/sync_check/direct_poke/sync_lg_poke/
    -- direct_mem_poke/raw_hw_poke/hold_2f fields that used to be here - those
    -- menu settings no longer exist (this session's revert to the v9
    -- baseline removed them along with the rest of that experimental code),
    -- so they would only ever read back nil now.
    settings = {
      guard_action          = globals.dummy and globals.dummy.guard_action,
      -- Read from globals.options, not globals.dummy. dummy is rebuilt per
      -- frame and was nil at write time, so every recording said "None" for
      -- the motion - which made a batch impossible to interpret, since the
      -- success rate depends entirely on which command was configured.
      -- options holds the menu value itself (11 = DPF, 9 = HCF, ...).
      counter_attack_stick  = globals.options and globals.options.counter_attack_stick,
      counter_attack_button2 = globals.options and globals.options.counter_attack_button,
      counter_attack_stick_dummy = globals.dummy and globals.dummy.counter_attack_stick,
      game_speed            = globals.options and globals.options.game_speed,
      -- THE DELAY, SO A BATCH CAN BE READ WITHOUT ASKING WHAT IT WAS SET TO.
      -- Its absence cost a whole analysis: "dash attack works at 4 and not at
      -- 5" could not be checked against the traces because nothing in them
      -- said which span was which delay.
      gc_delay              = globals.options and globals.options.gc_delay,
      gc_input_delay        = globals.options and globals.options.gc_input_delay,
      guard_action          = globals.options and globals.options.guard_action,
      -- Which push block was asked for. Its absence meant the last batch had
      -- to infer "same button" vs "ascending" from the button bits in $394.
      pb_type               = globals.options and globals.options.pb_type,
      min_pb_inputs         = globals.options and globals.options.min_pb_inputs,
      -- DIAGNOSTIC: a roll (Wakeup != None) adds ~40 extra frames of
      -- recovery the dummy cannot act during, which would explain 0xFF8805
      -- staying "Hurt or Block" long after the knockdown clock (0xFF89A7)
      -- plateaus - see the note above service_held_reversal in guardCancel.lua.
      roll_direction        = globals.options and globals.options.roll_direction,
    },
    regions    = REGIONS,
    session    = session,
    seq        = seq,
    mark_seq   = mark_seq,
    hit_frame  = r.hit_frame,
    pokes      = r.pokes,
    queues     = r.queues,
    marks      = r.marks,
    holds      = r.holds,
    writes     = r.writes,
    execs      = r.execs,
    ticks      = r.ticks,
    -- Test-condition check, see mark_tick(). 0 = no tick re-execution seen
    -- in this recording (run-ahead effectively off); nonzero = it happened,
    -- and rewind_depth is the deepest single jump backwards in ticks.
    lg_rewinds     = r.rewinds,
    lg_rewind_depth = r.rewind_depth,
    tick_count     = #r.ticks,
    -- Run-ahead, measured from 0xFF8081 rather than from any setting - see
    -- guardcancel_runahead_state(). active=false means no tick was ever seen
    -- being re-run, i.e. the recording was made without it.
    runahead       = (type(guardcancel_runahead_state) == "function")
                     and guardcancel_runahead_state() or nil,
    -- Emulator pacing. The motion is delivered one entry per Lua frame
    -- callback, so if a callback covers more game ticks than usual the motion
    -- stretches - see guardcancel_lag_state().
    lag            = (type(guardcancel_lag_state) == "function")
                     and guardcancel_lag_state() or nil,
    -- Columns inputHistory.lua actually committed for P2 during this window
    -- (see trace_history_entry there). d = direction 1..9 numpad, b = button
    -- bitmask. Lets a column that was never created be distinguished from one
    -- that was created and drawn wrong.
    hist           = (function()
      local out = {}
      if type(globals.hist_trace) == "table" then
        for i = (r.hist_from or 0) + 1, #globals.hist_trace do
          out[#out + 1] = globals.hist_trace[i]
        end
      end
      return out
    end)(),
    rows       = r.rows,
  }, path)
end

-- Called from the master script AFTER process_pending_input_sequence has
-- written this frame's sequence entry into globals._input, and BEFORE
-- joypad.set hands it to the emulator.
--
-- Why this exists: the delivered inputs read back from P2+0x122 / P2+0x125
-- showed the button landing one frame BEFORE the final down-forward, which
-- should not happen. Two explanations fit equally well - the sequence really
-- is delivered a frame out of step, or those addresses simply lag the input by
-- a frame. Reading only the game side cannot tell them apart.
--
-- So record what the script actually SET on this frame. Lining that up against
-- what the game reports on the same frame gives the lag directly, and any
-- remaining mismatch is a real ordering fault.
--
-- Stored as a bitmask on the current row, ~10 boolean lookups per frame:
--   bit0 Left  bit1 Right  bit2 Up  bit3 Down
--   bit4 LP    bit5 MP     bit6 HP  bit7 LK   bit8 MK  bit9 HK
local INPUT_BITS = {
  { "P2 Left",          1 },
  { "P2 Right",         2 },
  { "P2 Up",            4 },
  { "P2 Down",          8 },
  { "P2 Weak Punch",   16 },
  { "P2 Medium Punch", 32 },
  { "P2 Strong Punch", 64 },
  { "P2 Weak Kick",   128 },
  { "P2 Medium Kick", 256 },
  { "P2 Strong Kick", 512 },
}

local function record_input(inp)
  if not is_enabled() then return end
  if not rec then return end
  local n = #rec.rows
  if n == 0 or inp == nil then return end
  local mask = 0
  for i = 1, #INPUT_BITS do
    if inp[INPUT_BITS[i][1]] then mask = mask + INPUT_BITS[i][2] end
  end
  -- Only stored when something is held, so idle frames cost nothing in the file.
  if mask ~= 0 then rec.rows[n].inp = mask end
end

-- EXPERIMENT: builds a ground-truth encoding table for 0xFF8525 (P1's
-- lever)/0xFF8522 (P1's button) by cross-referencing them against P1's OWN
-- raw joypad state - unlike P2's mirror (0xFF8925/0xFF8922, which this
-- session found does NOT reliably reflect a just-delivered input on any
-- short, predictable timescale), P1 is a live human player, so whatever
-- combination of Up/Down/Left/Right/buttons globals._input currently shows
-- for P1 is by definition exactly what they are pressing RIGHT NOW - no
-- capture-timing guesswork needed. Assumes the encoding scheme itself is the
-- same for P1 and P2 (a reasonable guess, unconfirmed) - if lever/button
-- values line up cleanly with recognizable P1 input combos here, the same
-- values can be reused for P2's direct-memory poke instead of relying on
-- P2's own poorly-behaved mirror.
local P1_INPUT_BITS = {
  { "P1 Left",          1 },
  { "P1 Right",         2 },
  { "P1 Up",             4 },
  { "P1 Down",           8 },
  { "P1 Weak Punch",    16 },
  { "P1 Medium Punch",  32 },
  { "P1 Strong Punch",  64 },
  { "P1 Weak Kick",    128 },
  { "P1 Medium Kick",  256 },
  { "P1 Strong Kick",  512 },
}
local p1_encoding_samples = {}
local p1_encoding_dirty = false
local function audit_p1_encoding()
  local _inp = globals._input
  if _inp == nil then return end
  local _mask = 0
  local _names = {}
  for i = 1, #P1_INPUT_BITS do
    if _inp[P1_INPUT_BITS[i][1]] then
      _mask = _mask + P1_INPUT_BITS[i][2]
      table.insert(_names, P1_INPUT_BITS[i][1])
    end
  end
  if _mask == 0 then return end
  local _key = tostring(_mask)
  local _lv = memory.readbyte(0xFF8525)
  local _bv = memory.readbyte(0xFF8522)
  local _existing = p1_encoding_samples[_key]
  if _existing == nil or _existing.lever ~= _lv or _existing.button ~= _bv then
    p1_encoding_samples[_key] = { keys = table.concat(_names, "+"), lever = _lv, button = _bv }
    p1_encoding_dirty = true
  end
end

-- EXPERIMENT: user asked whether 0x804000 is a (raw hardware) input address -
-- unverified in this codebase so far, everything used until now
-- (0xFF8522/0xFF8525 etc.) is well inside work RAM (0xFF0000+), while
-- 0x804000 would be a completely different region (typically where CPS2's
-- own port-read hardware sits, upstream of any game-side processing). Same
-- correlation method as audit_p1_encoding() above: dump a small range of
-- raw bytes around 0x804000 every time P1's real joypad state changes, so a
-- byte offset that visibly tracks known keypresses would confirm or rule
-- this out directly instead of guessing.
local HW_PROBE_BASE = 0x803FE0
local HW_PROBE_LEN  = 64
local hw_probe_samples = {}
local hw_probe_dirty = false
local prev_p1_mask_for_hw = nil
local prev_p2_mask_for_hw = nil
-- EXPERIMENT: P1's own directions correlated cleanly and consistently with
-- 0x804001, confirming the documented "IN0, byte 1 = directions" hardware
-- port. But that byte is documented as carrying BOTH players' directions
-- packed together, and P2 (the side guardCancel.lua actually needs to poke)
-- has not been isolated yet - P1-only samples can't tell P1's bits apart
-- from P2's. Tracks P2's own mask the same way, on its own change events, so
-- the two can be told apart directly from the log instead of guessing which
-- nibble/bits belong to which player.
local P2_INPUT_BITS = {
  { "P2 Left",          1 },
  { "P2 Right",         2 },
  { "P2 Up",             4 },
  { "P2 Down",           8 },
  { "P2 Weak Punch",    16 },
  { "P2 Medium Punch",  32 },
  { "P2 Strong Punch",  64 },
  { "P2 Weak Kick",    128 },
  { "P2 Medium Kick",  256 },
  { "P2 Strong Kick",  512 },
}
local function compute_mask(_inp, _bits)
  local _mask = 0
  local _names = {}
  for i = 1, #_bits do
    if _inp[_bits[i][1]] then
      _mask = _mask + _bits[i][2]
      table.insert(_names, _bits[i][1])
    end
  end
  return _mask, _names
end
local function audit_hw_input_probe()
  local _inp = globals._input
  if _inp == nil then return end
  local _p1_mask, _p1_names = compute_mask(_inp, P1_INPUT_BITS)
  local _p2_mask, _p2_names = compute_mask(_inp, P2_INPUT_BITS)
  if _p1_mask == prev_p1_mask_for_hw and _p2_mask == prev_p2_mask_for_hw then return end
  prev_p1_mask_for_hw = _p1_mask
  prev_p2_mask_for_hw = _p2_mask
  local _bytes = {}
  for i = 0, HW_PROBE_LEN - 1 do
    _bytes[i + 1] = memory.readbyte(HW_PROBE_BASE + i)
  end
  table.insert(hw_probe_samples, {
    p1_keys = (#_p1_names > 0) and table.concat(_p1_names, "+") or "(none)",
    p1_mask = _p1_mask,
    p2_keys = (#_p2_names > 0) and table.concat(_p2_names, "+") or "(none)",
    p2_mask = _p2_mask,
    bytes   = _bytes,
  })
  if #hw_probe_samples > 40 then table.remove(hw_probe_samples, 1) end
  hw_probe_dirty = true
end

-- Called from guardCancel.lua the moment an input sequence is queued, i.e. the
-- "Reversal - Specified" / "Counter - Specified" path.
--
-- Unlike the poke path this writes no memory: the sequence is fed to the game
-- as real button presses over the following frames. What we need to know is
-- when playback started relative to the reversal window, and the answer to
-- that is already in the sweep - P2+0x122 (buttons) and P2+0x125 (lever) show
-- exactly what the game received on each frame. This only records the moment
-- the sequence was handed over, so those input frames can be lined up against
-- the trigger.
local function mark_queue(kind, seq_len, attack_frame)
  if not is_enabled() then return end
  if not rec then return end
  table.insert(rec.queues, {
    f      = globals.current_frame,
    kind   = kind,
    len    = seq_len,
    -- attack_frame as the script computed it, to confirm whether it is ever a
    -- future frame (measurement so far says it never is).
    af     = attack_frame,
    rev    = memory.readbyte(0xFF8974),
    act    = memory.readbyte(0xFF8806),
    st     = memory.readbyte(0xFF8805),
    btn    = memory.readbyte(0xFF8922),
    lever  = memory.readbyte(0xFF8925),
  })
end

-- Called from guardCancel.lua at the moment of the poke.
local function mark_poke(move_value, move_strength)
  if not is_enabled() then return end
  if not rec then return end
  table.insert(rec.pokes, {
    f     = globals.current_frame,
    mv    = move_value,
    str   = move_strength,
    -- The three that separated working from failing reversals.
    b144  = memory.readbyte(0xFF8944),
    b140  = memory.readbyte(0xFF8940),
    b1A7  = memory.readbyte(0xFF89A7),
    rev   = memory.readbyte(0xFF8974),
    fa2   = memory.readbyte(0xFF880B),
  })
end

-- TEMPORARY: investigating why the 'reversal' guard action's pre-buffer
-- (queue_input_sequence(..., true) + release_input_sequence in
-- service_held_reversal) sometimes fails to release into the early
-- hurt/block-stun reversal window (0xFF8974 becomes 5, 0xFF89A7 == 0x1B) and
-- instead falls through to the later wake-up-only window (0xFF8974 becomes
-- 9, 0xFF89A7 == 0). The memory sweep above shows what the GAME did, but not
-- what the SCRIPT's own pending_input_sequence bookkeeping was doing at the
-- same time - whether a sequence was held at all, how long, and whether
-- HOLD_LIMIT dropped it. Delete this block (down through mark_hold), the
-- "holds" field in write_out()'s output, and its call site in
-- guardCancel.lua's service_held_reversal(), once this is resolved.
--
-- Called every frame from service_held_reversal(), same cadence as the main
-- per-frame sweep above, so the cost is comparable to what registerBefore()
-- already does every frame.
local function mark_hold(info)
  if not is_enabled() then return end
  if not rec then return end
  event_seq = event_seq + 1
  info.seq = event_seq
  info.f = globals.current_frame
  table.insert(rec.holds, info)
end

-- TEMPORARY: sub-frame timing via memory.registerwrite. Section 9 of the
-- handoff doc established this fires on every WRITE to a RAM address -
-- potentially several times within one displayed frame, unlike the sweep
-- above and mark_hold(), both of which only see one snapshot per Lua
-- callback (i.e. per DISPLAYED frame). Confirmed real-hardware-working at
-- the time (0xFF8081 fired 179/180 frames with multiple hits per frame),
-- but not exercised further back then. Now usable during real Fightcade
-- netplay per a Fightcade version update, not just standalone FBNeo.
--
-- Originally watching 0xFF8974 (reversal counter) and 0xFF89A7 (knockdown
-- clock) to settle whether the once-per-frame sweep's "0xFF8974 goes
-- straight from 0 to 8/9" on some knockdowns was real or a polling artifact.
-- It was a polling artifact: writes logged 0 -> 5 -> 4 -> 9 within a SINGLE
-- frame. guardCancel.lua now has a registerwrite hook of its own on
-- 0xFF8974 that releases the held reversal input the instant it sees 4/5,
-- instead of waiting for the next once-per-frame poll - confirmed working,
-- every release in a batch of 20 now lands on the correct window.
--
-- New question the fix exposed: about half of those correctly-windowed
-- releases still produce no move at all. One paired trace (good vs bad,
-- same release condition) showed the button landing 2 frames after the
-- window opened when the move came out, and on the SAME frame the window
-- opened when it did not - matching the documented "an early button press
-- destroys buffered motion" behaviour, except now our own release is the
-- one arriving early. But 0xFF8922 (button) turned out to have the SAME
-- multiple-writes-per-frame behaviour as 0xFF8974: several MOVE cases show
-- the button never visible as nonzero anywhere in the once-per-frame sweep
-- at all, even though the move clearly started. The once-per-frame view of
-- when the button actually lands cannot be trusted any more than 0xFF8974's
-- could - hence watching writes to it too, to measure the true gap between
-- the window opening and the button actually being written, sub-frame.
--
-- registerwrite's callback is not passed the value - read it back with
-- memory.readbyte after the write has happened, same pattern as everywhere
-- else in this file.
--
-- Next question, now that a batch of ~25 result-classified episodes at a
-- fixed release condition (0xFF8974 == 4, kd == 0x1B) still splits roughly
-- 50/50 MOVE vs NOTHING with no memory-sweep byte found to explain it (a
-- full-region sweep at hit+1 only turned up continuously-varying fields -
-- X position, what looks like a free-running counter - which trivially
-- "fully separate" any two small groups by chance and were discarded, not
-- treated as findings): which CODE is doing each write. memory.getregister
-- reads CPU registers inside a hook exactly like memory.registerexec's own
-- callback does (see tech-hit-inputs.lua's use of "m68000.sr") - the PC at
-- the moment of a registerwrite callback is the instruction that just
-- executed the write. If MOVE and NOTHING episodes are landing on
-- DIFFERENT PCs for the same address, that is the branch to put a
-- registerexec hook on next and inspect directly, instead of continuing to
-- guess from RAM contents alone.
local function on_write(addr_str, addr)
  return function()
    if not is_enabled() then return end
    if not rec then return end
    event_seq = event_seq + 1
    table.insert(rec.writes, {
      seq  = event_seq,
      f    = globals.current_frame,
      addr = addr_str,
      val  = memory.readbyte(addr),
      pc   = memory.getregister("m68000.pc"),
      lg   = memory.readbyte(0xFF8081),
    })
  end
end
-- EXPERIMENT: BUG FOUND. This used to also do
-- memory.registerwrite(0xFF8974, 1, on_write("0xFF8974", 0xFF8974)) here, but
-- a real batch showed ZERO 0xFF8974 entries in "writes" despite the other
-- watched addresses (0xFF89A7/0xFF8922/0xFF8806/0xFF8925) all logging
-- normally. guardCancel.lua requires this module first thing (so THIS
-- registration runs first), but guardCancel.lua's own
-- memory.registerwrite(0xFF8974, ...) for on_reversal_window_write() runs
-- later and - matching the single-slot-per-address behavior already found
-- for registerexec (see the note above the 0x26D64 sweep) - silently took
-- the slot over. mark_write() below is exported so on_reversal_window_write()
-- can log directly from inside the hook that actually fires, instead of
-- registering a second one here that would just lose the race again.
-- TICK-RESOLUTION TRACE.
--
-- Everything above samples once per DISPLAYED frame. Measured on the v31
-- batch, 0x02211A - the instruction that copies the input word into $122,
-- i.e. the game's own input-consumption point - runs 2, 3 or 4 times per
-- displayed frame (mean 3.004, n=1560). So a per-frame sample cannot say
-- which tick anything happened on, and a release decided on one tick lands
-- an unknown 0..3 ticks away from where a per-frame log appears to put it.
--
-- That ambiguity is exactly what is blocking the reversal timing now: the
-- release fires from a state condition that is identical in all 45 attempts
-- (kd=26, $7=2, $20=0), yet the outcome varies, so the variance has to be
-- in ticks that per-frame logging cannot see.
--
-- One row per P2 input-consumption tick, only around a knockdown, so the
-- volume stays small (~40-80 rows per attempt). Short keys because there
-- are many rows:
--   s  event_seq (global chronological order, shared with holds/writes)
--   f  displayed frame        g  0xFF8081 (lg)
--   a  $05 status_1           b  $06 status_2      c  $07 sub-state
--   n  $20 animation counter  k  $1a7 knockdown clock
--   i  $122/$123 input word the game is about to act on (facing-corrected
--      downstream, so this is pre-correction)
--   e  $126 press-edge word computed from the PREVIOUS tick
--   j  $394/$395 raw input word (what injection writes)
--
-- REWIND COUNTER. 0xFF8081 increments once per tick at 0x008E10, so between
-- two consecutive ticks it can only go up by one. Measured on the v33 batch
-- it went BACKWARD by 1 or 2 on 6635 of 23040 tick pairs - the emulator was
-- re-running about one displayed frame's worth of ticks and throwing the
-- first pass away (run-ahead / rollback). Emulator RAM is restored by that;
-- Lua state is not, which is what broke v33's timing.
--
-- Counted here so the condition is visible in the log itself rather than
-- inferred: lg_rewinds = 0 means the recording was made with no re-execution
-- happening, any other number means it was.
-- Shared with inputHistory.lua's trace_history_entry(). Created here so the
-- trace is inert unless this logger is loaded.
if globals ~= nil and globals.hist_trace == nil then globals.hist_trace = {} end

local last_tick_lg = nil
local function mark_tick(t)
  if not is_enabled() then return end
  if not rec then return end
  if last_tick_lg ~= nil then
    local _d = t.g - last_tick_lg
    if _d < 0 then _d = _d + 256 end
    if _d ~= 1 and _d ~= 0 then
      rec.rewinds = rec.rewinds + 1
      if _d > 128 then rec.rewind_depth = math.max(rec.rewind_depth, 256 - _d) end
    end
  end
  last_tick_lg = t.g
  event_seq = event_seq + 1
  t.s = event_seq
  t.f = globals.current_frame
  table.insert(rec.ticks, t)
end

local function mark_write(addr_str, val, pc)
  if not is_enabled() then return end
  if not rec then return end
  event_seq = event_seq + 1
  table.insert(rec.writes, {
    seq  = event_seq,
    f    = globals.current_frame,
    addr = addr_str,
    val  = val,
    pc   = pc,
    lg   = memory.readbyte(0xFF8081),
  })
end
DIAG_HOOKS.w89A7 = on_write("0xFF89A7", 0xFF89A7)

-- EXPERIMENT: caches the lever/button values seen at the exact instant a
-- reversal actually commits, so guardCancel.lua's direct-memory poke (see
-- the note above on_lg_tick()) can reuse the game's own real byte encoding
-- for the currently configured motion/button instead of guessing one. The
-- encoding is not otherwise documented in this codebase (only
-- "down-forward = lever 6" was ever confirmed, from an old paired-sample
-- comparison). Captured below, at the 0xFF8806 hook, not here - see the FIX
-- note there for why "last nonzero write to this address" was too broad.
local last_nonzero_lever = nil
local last_nonzero_button = nil
-- EXPERIMENT: FIX, second cut. First cut captured on ANY nonzero write - too
-- broad (caught unrelated holds like plain "down"). Second cut captured only
-- AT the instant 0xFF8806 becomes a move value - too NARROW: this session's
-- own lg-tagged trace showed 0xFF8922 (button) lands ONE lg tick after the
-- commit and 0xFF8925 (lever) lands TWO ticks after, in the same sample - at
-- the commit instant itself both were still their pre-commit (often zero)
-- values, so the "only nonzero" guard silently never fired and the cache
-- stayed nil forever despite 7/9 confirmed real MOVEs in the batch that
-- exposed this. Fix: open a short grace window (by event_seq, a few events
-- wide) when 0xFF8806 commits, and let the NEXT nonzero write to either
-- address within that window populate the cache, wherever in the window it
-- actually lands.
local _capture_until_seq = -1
local function maybe_capture_lever(v) if event_seq <= _capture_until_seq and v ~= 0 then last_nonzero_lever = v end end
local function maybe_capture_button(v) if event_seq <= _capture_until_seq and v ~= 0 then last_nonzero_button = v end end

DIAG_HOOKS.wFF8922 = function()
  on_write("0xFF8922", 0xFF8922)()
  maybe_capture_button(memory.readbyte(0xFF8922))
end
-- FOUND: the button (0xFF8922) always writes AFTER both the first AND the
-- last instruction of the check block (0x26D64..0x26D80), in EVERY sample,
-- MOVE and NOTHING alike (true seq-ordered, not just same-frame guessing).
-- So the fork is not gated on button timing at all - it must be reading the
-- DIRECTION history, already fully delivered much earlier via lever writes.
-- Watching 0xFF8925 (lever) with PC too, to see its delivery timing against
-- the same check block the same way this already ruled out the button.
DIAG_HOOKS.wFF8925 = function()
  on_write("0xFF8925", 0xFF8925)()
  maybe_capture_lever(memory.readbyte(0xFF8925))
end
-- The write to 0xFF8806 (action byte) IS the MOVE-vs-idle decision itself -
-- 0x0E/0x10/0x12 committed the special, 0x00 returned to idle instead. PC
-- tracing at 0xFF8974/0xFF8922 found the exact same instruction writing
-- both regardless of outcome, so whatever decides it is downstream of
-- those. If a DIFFERENT PC writes 0x00 than the one that writes 0x0E here,
-- that PC is where to put the next registerexec hook and read registers
-- directly, instead of continuing to infer from RAM alone.
DIAG_HOOKS.wFF8806 = function()
  on_write("0xFF8806", 0xFF8806)()
  local _v = memory.readbyte(0xFF8806)
  if _v == 0x0E or _v == 0x10 or _v == 0x12 then
    -- +6 events of slack - the 1-2 lg-tick gap above is usually only a
    -- handful of writes away in event_seq terms, this just needs to not be
    -- exactly zero-width.
    _capture_until_seq = event_seq + 6
  end
end

-- FOUND: 0xFF8806 writes split cleanly by PC. Every MOVE episode's last
-- write before the special starts comes from 0x29854; every NOTHING
-- episode's comes from 0x26D5C. Both groups share the same instruction
-- immediately before that fork, 0x26D7A - so the branch between "commit the
-- special" (0x29854) and "reject it, back to idle" (0x26D5C) is decided
-- somewhere at or after 0x26D7A.
--
-- First attempt: dumped registers at 0x26D7A itself. Inconclusive - it
-- executes roughly 10 times per 260-frame recording (not once per reversal
-- attempt), so most register snapshots landed nowhere near an actual fork,
-- and the "nearest exec before the fork" match was too loose to trust.
--
-- Hooking 0x29854 and 0x26D5C directly instead: each of THOSE only executes
-- when that specific outcome happens, so every logged snapshot is exactly
-- and unambiguously tied to MOVE or NOTHING - no nearest-match guessing.
local D68K = { "d0", "d1", "d2", "d3", "d4", "d5", "d6", "d7",
  "a0", "a1", "a2", "a3", "a4", "a5", "a6", "a7" }
local function dump_regs_at(pc_val)
  return function()
    if not is_enabled() then return end
    if not rec then return end
    event_seq = event_seq + 1
    local regs = { seq = event_seq, f = globals.current_frame, pc = pc_val, sr = memory.getregister("m68000.sr"),
      lg = memory.readbyte(0xFF8081) }
    for _, r in ipairs(D68K) do
      regs[r] = memory.getregister("m68000." .. r)
    end
    rec.execs = rec.execs or {}
    table.insert(rec.execs, regs)
  end
end
DIAG_HOOKS.x26D7A = dump_regs_at(0x26D7A)
DIAG_HOOKS.x29854 = dump_regs_at(0x29854)
DIAG_HOOKS.x26D5C = dump_regs_at(0x26D5C)
-- EXPERIMENT: the blind sweep below found 0x26D36-0x26D60 executes on EVERY
-- NOTHING episode and NEVER on a MOVE one (9 MOVE / 9 NOTHING samples, no
-- exceptions) - a whole block the MOVE path skips entirely. d0 alone (what
-- the sweep records) reads 0 there regardless, same as everywhere else in
-- this range, so it is not the discriminator by itself - full registers at
-- the block's entry point might show an address register pointing at
-- whatever this block is actually reading instead of just d0.
DIAG_HOOKS.x26D36 = dump_regs_at(0x26D36)

-- THE DASH CHECK ITSELF (0x02D3F2).
--
-- Sampling these four bytes once per tick showed 0 everywhere, on the attempts
-- that produced a dash as well as the ones that did not - so the sample point
-- is wrong, not the bytes. The decision is made inside the frame and the
-- values are transient.
--
-- Hooked at the check instead, the way the guard script was found: recorded at
-- the instant the game reads them, with no guessing about when that is.
--
--     02D3F2  tst.b ($23a,A6) / beq  -> no dash
--     02D3FC  tst.b ($11f,A4) / bne  -> no dash   (the opponent's byte)
--     02D402  move.b ($243,A6)       -> the tap step
--     02D426  tst.w ($208,A6) / beq  -> DASH
DIAG_HOOKS.x2D3F2 = function()
  if not is_enabled() then return end
  if not rec then return end
  if memory.getregister("m68000.a6") ~= 0xFF8800 then return end
  local _a4 = memory.getregister("m68000.a4") % 0x1000000
  event_seq = event_seq + 1
  table.insert(rec.writes, {
    seq = event_seq, f = globals.current_frame, addr = "dash_check",
    val = memory.readbyte(0xFF8A3A) * 256 + memory.readbyte(0xFF8A43),
    pc  = memory.readword(0xFF8A08),
    lg  = memory.readbyte(0xFF8081),
    o11f = (_a4 >= 0xFF0000) and memory.readbyte(_a4 + 0x11F) or nil,
  })
end


-- WHO REACHES THE free-1 SIGNATURE, AND WHEN.
--
-- 0x024F02 tests $21 and falls into the signature at 0x024F0A when it is
-- negative. During a BLOCK $21 reads 0xFF for several ticks before free, yet
-- the signature only appears on free-1 - so the gate is not $21, it is
-- whatever decides to reach 0x024F02 at all. Sweeping for that gate failed:
-- P2 $000-$3FF and P1 $000-$1FF hold no byte that counts to free.
--
-- So instead of hunting the state, follow the code. The 68000 pushes return
-- addresses, so the longs at A7 name the callers. Logged with the tick counter
-- so the ticks that DID NOT reach here can be told apart from the one that
-- did.
DIAG_HOOKS.x24F02 = function()
  if not is_enabled() then return end
  if not rec then return end
  if memory.getregister("m68000.a6") ~= 0xFF8800 then return end
  local _a7 = memory.getregister("m68000.a7")
  local _ret = {}
  for _i = 0, 5 do
    _ret[_i + 1] = string.format("%06X", memory.readdword(_a7 + _i * 4) % 0x1000000)
  end
  event_seq = event_seq + 1
  table.insert(rec.writes, {
    seq = event_seq, f = globals.current_frame, addr = "sig_callers",
    val = memory.readbyte(0xFF8821), pc = table.concat(_ret, " "),
    lg = memory.readbyte(0xFF8081),
  })
end

-- Filled in below, with the sweep itself - declared here so sync_diag_hooks
-- can name them without turning them into globals.
local SWEEP_ADDRS, SWEEP_HOOK

-- Attach the eight only while the logger is on, detach when it goes off.
-- Called once per frame; the `diag_attached` compare keeps it to a single
-- branch on every frame that does not change state.
function sync_diag_hooks()
  local _want = is_enabled()
  if _want == diag_attached then return end
  diag_attached = _want
  local function pick(fn) if _want then return fn end return nil end
  memory.registerwrite(0xFF89A7, 1, pick(DIAG_HOOKS.w89A7))
  memory.registerwrite(0xFF8922, 1, pick(DIAG_HOOKS.wFF8922))
  memory.registerwrite(0xFF8925, 1, pick(DIAG_HOOKS.wFF8925))
  memory.registerwrite(0xFF8806, 1, pick(DIAG_HOOKS.wFF8806))
  memory.registerexec(0x26D7A, pick(DIAG_HOOKS.x26D7A))
  memory.registerexec(0x29854, pick(DIAG_HOOKS.x29854))
  memory.registerexec(0x26D5C, pick(DIAG_HOOKS.x26D5C))
  memory.registerexec(0x26D36, pick(DIAG_HOOKS.x26D36))
  memory.registerexec(0x02D3F2, pick(DIAG_HOOKS.x2D3F2))
  memory.registerexec(0x024F02, pick(DIAG_HOOKS.x24F02))
  for _, _a in ipairs(SWEEP_ADDRS) do
    memory.registerexec(_a, _want and SWEEP_HOOK(_a) or nil)
  end
end

-- FOUND (with 0x29854/0x26D5C confirmed samples, 34 MOVE + 111 NOTHING):
-- d0 is 4 on every single MOVE sample and 0 on every single NOTHING sample -
-- clean and exceptionless. But at 0x26D7A itself d0 reads 0 regardless of
-- eventual outcome, so it is not decided there - it is decided somewhere
-- between 0x26D7A and whichever of 0x29854/0x26D5C actually runs.
--
-- 0x26D5C sits only 0x1E (30) bytes BEFORE 0x26D7A, not after - despite
-- being the "NOTHING" outcome's PC. Scanning every word-aligned address in a
-- window around both, on the theory that whatever sets d0 to 4-or-0 lives in
-- that narrow gap. No disassembly available, so this is a blind sweep -
-- registerexec on an address that never happens to be a genuine instruction
-- boundary simply never fires (the CPU does not jump there), so this is
-- read-only and safe, not a guess that can crash anything.
--
-- Lighter payload than dump_regs_at (d0 only) - this covers ~48 addresses
-- and some of them will legitimately fire every frame of the whole
-- recovery, unlike the three specific PCs above.
-- EXPERIMENT: tracks the last displayed frame 0x26D64 (the shared
-- MOVE/NOTHING decision block's entry point) executed, exposed below via
-- get_last_check_block_frame() so guardCancel.lua's adaptive reversal delay
-- can use it without registering its own second exec hook on the same PC -
-- memory.registerexec appears to be single-slot per address (see
-- dummyState.lua's registerexec(addr, nil)-then-reregister pattern), so a
-- second hook here would silently steal this address away from the sweep
-- below instead of adding to it. Updated unconditionally (not gated on
-- is_enabled()/rec) so the adaptive delay still works with logging off.
local last_check_block_frame = -1

-- EXPERIMENT: extended the low end from 0x26D30 to 0x26D00 - 0x26D36 (see
-- the dedicated full-register hook above) turned out to be a NOTHING-only
-- block (never executes on a MOVE episode), meaning whatever branches into
-- it vs around it is upstream of where this sweep used to start. Widening
-- the net to find that branch instruction, same blind/safe methodology as
-- before (registerexec on a non-instruction-boundary address simply never
-- fires).
-- ATTACHED ONLY WHILE THE LOGGER IS ON.
--
-- This is about seventy exec hooks on a block the CPU runs constantly. They
-- used to be registered at load and simply return early when the setting is
-- off, which still pays for every one of them on every execution. They are
-- listed here instead and attached and detached with the rest, in
-- sync_diag_hooks.
--
-- 0x26D64 is the exception and stays attached always: it is the only one that
-- feeds anything outside an investigation.
SWEEP_ADDRS = {}
for _addr = 0x26D00, 0x26D90, 2 do
  if _addr ~= 0x26D7A and _addr ~= 0x26D5C and _addr ~= 0x26D36 and _addr ~= 0x26D64 then
    table.insert(SWEEP_ADDRS, _addr)
  end
end

SWEEP_HOOK = function(_a)
  return function()
    if not rec then return end
    event_seq = event_seq + 1
    rec.execs = rec.execs or {}
    table.insert(rec.execs, { seq = event_seq, f = globals.current_frame, pc = _a, d0 = memory.getregister("m68000.d0"),
      lg = memory.readbyte(0xFF8081) })
  end
end

memory.registerexec(0x26D64, function()
  last_check_block_frame = globals.current_frame
end)

-- EXPERIMENT: one-shot raw code dump for OFFLINE disassembly. No debugger is
-- available in Fightcade's bundled FBNeo build, but the CPU's program space
-- is readable through the same memory.readbyte() already used everywhere
-- else in this file (proven safe - memory.registerexec already confirms the
-- CPU genuinely executes real instructions in this range). Dumping the raw
-- bytes around the check block lets a real m68k disassembler (capstone,
-- installed separately) read actual instruction mnemonics instead of
-- continuing to infer control flow from register-value correlations alone.
-- Runs once, at script load, not gated on is_enabled() - this is a
-- correctness/setup step, not part of the knockdown-specific measurement.
local _code_dump_done = false
local function dump_code_range(start_addr, length, path)
  local _bytes = {}
  for i = 0, length - 1 do
    _bytes[i + 1] = memory.readbyte(start_addr + i)
  end
  write_object_to_json_file({
    script_version = SCRIPT_VERSION,
    start_addr = start_addr,
    length = length,
    bytes = _bytes,
  }, path)
end
-- Deliberately NOT called here at module-load time - the ROM/game memory
-- may not be mapped yet when this file is first required, so this would
-- risk dumping zeros/garbage. Triggered instead from registerBefore() below
-- (once), by which point a match is confirmed running.

-- EXPERIMENT: "コマ" (frame) call-frequency audit. Chasing whether
-- emu.registerbefore() - and therefore joypad.set(), called once per
-- registerbefore in vsav_training_master_script.lua - really fires exactly
-- once per displayed frame, or whether (as macro.lua's own comment warns:
-- "framediff check is necessary for emus where registerbefore runs multiple
-- times per frame") it can fire more than once for the same
-- emu.framecount() value, e.g. under turbo speed. Matters directly for the
-- "direct poke" experiment in guardCancel.lua: if registerbefore already
-- fires more than once per displayed frame on its own, the single-call-per-
-- frame ceiling described there is not as hard as assumed. Unconditional
-- (not gated on is_enabled()) - this is a cheap correctness check, not part
-- of the knockdown-specific measurement.
local rb_call_count = 0
local rb_distinct_frame_count = 0
local rb_dup_count = 0
local rb_last_frame = nil
local rb_dup_examples = {}
local function audit_registerbefore_frequency()
  rb_call_count = rb_call_count + 1
  local _fc = globals.current_frame
  if _fc == rb_last_frame then
    rb_dup_count = rb_dup_count + 1
    if #rb_dup_examples < 20 then
      table.insert(rb_dup_examples, { f = _fc, gs = globals.options and globals.options.game_speed })
    end
  else
    rb_distinct_frame_count = rb_distinct_frame_count + 1
    rb_last_frame = _fc
  end
  -- Written to a file instead of print() so it can be parsed the same way
  -- as the rest of this module's output - overwritten each time (this is a
  -- running cumulative snapshot, not a per-event ring buffer like kd_*.json).
  if rb_call_count % 600 == 0 then
    write_object_to_json_file({
      script_version      = SCRIPT_VERSION,
      calls               = rb_call_count,
      distinct_frames     = rb_distinct_frame_count,
      dup_calls           = rb_dup_count,
      game_speed          = globals.options and globals.options.game_speed,
      dup_examples        = rb_dup_examples,
    }, LOG_DIR .. "/rb_freq.json")
  end
end

-- EXPERIMENT: how many times per DISPLAYED frame does 0xFF8974 write the
-- value 4 (the reversal window opening)? guardCancel.lua's
-- on_reversal_window_write() (the write hook this feeds) reacts to every one
-- of these unconditionally in the "direct poke" path - if several land on
-- the same displayed frame, or several consecutive frames each get one, that
-- would mean the poke code runs (and calls joypad.set()) more than once per
-- attempt, which changes how the multi-frame "Left+Down+MP" persistence seen
-- in a recent batch should be read. Broken down by game_speed so turbo
-- settings can be compared directly. Unconditional (not gated on
-- is_enabled()).
local rev4_call_count = 0
local rev4_last_frame = nil
-- Per-game_speed breakdown, so switching turbo mid-session still gives a
-- directly comparable answer without needing separate runs:
--   calls               total times this hook saw rev==4
--   distinct_frames     distinct displayed frames that happened on
--   same_frame_repeats  additional hits on a frame already counted (>1 write
--                       of rev==4 within one displayed frame)
--   consecutive_frames  hits whose frame is exactly the previous hit's + 1
--                       (the window staying open/rev==4 across neighboring
--                       frames, not a same-frame repeat)
local rev4_by_speed = {}
local rev4_dirty = false
-- EXPERIMENT: FIX. This used to call write_object_to_json_file() right here
-- - but this function is invoked from guardCancel.lua's
-- on_reversal_window_write(), itself a memory.registerwrite callback, i.e. a
-- context that runs mid-frame, nested inside the game's own CPU execution,
-- not the ordinary once-per-frame registerbefore context every other write
-- in this module happens from. Despite 100+ calls confirmed reaching this
-- function (poked_preview/armed_delayed_release counts in the same batch),
-- rev4_freq.json never once appeared on disk, while rb_freq.json - written
-- from audit_registerbefore_frequency(), which runs from the ordinary
-- registerbefore context - wrote fine every time in the same session. That
-- points at file I/O not being reliable (or not being flushed/visible) from
-- inside a registerwrite callback specifically. So this only updates
-- in-memory counters now; the actual write happens from registerBefore()
-- below, the same known-good context rb_freq.json already uses.
local function mark_rev4_tick()
  rev4_call_count = rev4_call_count + 1
  local _fc = globals.current_frame
  local _gs = tostring(globals.options and globals.options.game_speed)
  local _s = rev4_by_speed[_gs]
  if _s == nil then
    _s = { calls = 0, distinct_frames = 0, same_frame_repeats = 0, consecutive_frames = 0 }
    rev4_by_speed[_gs] = _s
  end
  _s.calls = _s.calls + 1
  if _fc == rev4_last_frame then
    _s.same_frame_repeats = _s.same_frame_repeats + 1
  else
    _s.distinct_frames = _s.distinct_frames + 1
    if rev4_last_frame ~= nil and _fc == rev4_last_frame + 1 then
      _s.consecutive_frames = _s.consecutive_frames + 1
    end
    rev4_last_frame = _fc
  end
  rev4_dirty = true
end

local function registerBefore()
  -- THE GATE GOES FIRST.
  --
  -- It used to sit below the audits, so rb_freq, rev4_freq, p1_encoding,
  -- hw_input_probe and the one-shot code_dump were all written whatever the
  -- Etc setting said - the switch turned off the traces and left the audits
  -- running. Nothing below this line is wanted by anything but an
  -- investigation.
  if not is_enabled() then return end
  audit_registerbefore_frequency()
  if rev4_dirty then
    rev4_dirty = false
    write_object_to_json_file({
      script_version = SCRIPT_VERSION,
      total_calls    = rev4_call_count,
      by_game_speed  = rev4_by_speed,
    }, LOG_DIR .. "/rev4_freq.json")
  end
  audit_p1_encoding()
  if p1_encoding_dirty then
    p1_encoding_dirty = false
    write_object_to_json_file({
      script_version = SCRIPT_VERSION,
      samples        = p1_encoding_samples,
    }, LOG_DIR .. "/p1_encoding.json")
  end
  audit_hw_input_probe()
  if hw_probe_dirty then
    hw_probe_dirty = false
    write_object_to_json_file({
      script_version = SCRIPT_VERSION,
      base           = HW_PROBE_BASE,
      length         = HW_PROBE_LEN,
      samples        = hw_probe_samples,
    }, LOG_DIR .. "/hw_input_probe.json")
  end
  if not _code_dump_done then
    -- Safe to run here specifically: the master script returns before ever
    -- reaching this call unless a match is confirmed running (see
    -- match_begun / match_actually_running() at the top of
    -- vsav_training_master_script.lua's registerbefore), so game memory is
    -- guaranteed mapped by this point.
    _code_dump_done = true
    -- EXPERIMENT: FIX. Was 0x26C000 - an extra hex digit, six digits instead
    -- of five, landing nowhere near the actual check block (0x26D30-0x26D90
    -- is ~0x159024 in decimal; 0x26C000 is ~16x further out, a completely
    -- unrelated region). Confirmed by the resulting dump disassembling to
    -- nothing recognizable. 0x26800 is the same digit-count/magnitude as the
    -- known addresses, with plenty of margin on both sides.
    dump_code_range(0x26800, 0x4000, LOG_DIR .. "/code_dump.json")
  end
  -- No file-count cutoff any more: write_out() rotates through the ring, so
  -- logging stays on for the whole session however long the hunt takes.

  local hurt = memory.readbyte(0xFF8805) ~= 0

  if not rec then
    -- FIX: dropped the "was_idle" requirement (a prior idle frame before
    -- this hit) for starting a new recording. That gate meant a repeated
    -- reversal -> meaty -> reversal -> meaty sequence, where the dummy never
    -- reaches true neutral in between, could only ever open ONE recording
    -- for the whole sequence - the moment that window closed at WINDOW
    -- frames, nothing was hurt->idle->hurt to restart it, so every poke
    -- after the first went completely unlogged. Safe to drop: write_out()
    -- already discards a recording with no poke/mark/queue in it without
    -- consuming a ring slot, which is what was_idle was there to prevent in
    -- the first place. Now a new window opens the instant the previous one
    -- closes, as long as the dummy is still hurt - which is exactly the case
    -- this was failing on.
    if hurt then
      rec = {
        hit_frame = globals.current_frame,
        rows      = {},
        pokes     = {},
        queues    = {},
        marks     = {},
        holds     = {},
        writes    = {},
        execs     = {},
        ticks     = {},
        hist_from = (globals.hist_trace and #globals.hist_trace) or 0,
        rewinds      = 0,
        rewind_depth = 0,
        remaining = WINDOW,
      }
      table.insert(rec.rows, row(true))
      -- EXPERIMENT: chronological-order check. Stamped with the SAME
      -- event_seq counter as mark_hold()'s other events (poked_preview,
      -- armed_delayed_release, etc.) via mark_hold() itself, so the next
      -- kd_*.json batch shows directly whether registerbefore-context events
      -- and on_reversal_window_write()'s mid-frame ones interleave the way
      -- assumed (registerbefore first, always, for a given displayed frame)
      -- or not. lg = 0xFF8081, already confirmed elsewhere to double-tick at
      -- turbo-3 - cross-referencing it against mid-frame events tests
      -- whether 0xFF8974 tracks that same doubling or not.
      mark_hold({ event = "frame_start", lg = memory.readbyte(0xFF8081) })
    else
      -- A key press with nothing being recorded would be silently lost, and
      -- the player would have no way to know. Say so instead.
      if mark_pending then
        print("[knockdown log] mark ignored - no recording running. " ..
              "The window is " .. tostring(WINDOW) .. " frames from the hit; " ..
              "press it sooner after the knockdown.")
      end
    end
    mark_pending = false
    return
  end

  if mark_pending then
    table.insert(rec.marks, globals.current_frame)
    print("[knockdown log] mark at frame " .. tostring(globals.current_frame))
    mark_pending = false
  end

  table.insert(rec.rows, row(false))
  mark_hold({ event = "frame_start", lg = memory.readbyte(0xFF8081) })
  rec.remaining = rec.remaining - 1
  if rec.remaining <= 0 then write_out() end
end

-- TEMPORARY (round 2): watch P1 through a knockdown so a HUMAN performing
-- Pit of Blame can be measured. Delete this block (down through p1_watch),
-- and its call in the exported registerBefore below, once the timing
-- question in the handoff doc is settled.
--
-- Round 1 of this only started recording at the 0xFF8580 edge (the same one
-- Pit of Blame's own trigger fires on), on the assumption that whatever
-- happened before it did not matter. That produced a clean answer for when
-- the move visibly STARTS (10-12 frames after the edge, consistently), but
-- said nothing about when the button was actually PRESSED - which could be
-- well before the edge, during the knockback itself. This version starts at
-- the HIT instead (same trigger the main logger above uses), so the whole
-- input can be seen relative to both the hit and the edge.
--
-- P1 is base 0xFF8400, i.e. every P2 address used elsewhere minus 0x400.
local P1_WINDOW    = 280
local p1_rec       = nil
local p1_prev180   = 0
local p1_was_idle  = true
local p1_files     = 0

local function registerStart()
  rec = nil
  last_raw = nil
  mark_pending = false
  p1_rec = nil
  p1_prev180 = 0
  p1_was_idle = true
  -- seq is NOT reset: it has to stay monotonic so the newest file is
  -- identifiable even after a ROM reset (which fires this without reloading
  -- the Lua state). session is bumped instead, which is what distinguishes
  -- files left over from an earlier run.
  session = session + 1
end

local function p1_watch()
  if not is_enabled() then return end
  if p1_files >= 8 then return end

  local hurt = memory.readbyte(0xFF8405) ~= 0
  local b180 = memory.readbyte(0xFF8580)

  if not p1_rec then
    if hurt and p1_was_idle then
      p1_rec = { hit_frame = globals.current_frame, edge_frame = nil, rows = {}, remaining = P1_WINDOW }
    end
    p1_was_idle = not hurt
    p1_prev180 = b180
    return
  end
  p1_was_idle = not hurt

  if p1_rec.edge_frame == nil and b180 ~= 0 and p1_prev180 == 0 then
    p1_rec.edge_frame = globals.current_frame
  end
  p1_prev180 = b180

  table.insert(p1_rec.rows, {
    f    = globals.current_frame,
    kd   = memory.readbyte(0xFF85A7),
    b180 = b180,
    st1  = memory.readbyte(0xFF8405),
    act  = memory.readbyte(0xFF8406),
    mv   = memory.readbyte(0xFF8506),
    str  = memory.readbyte(0xFF8502),
    btn  = memory.readbyte(0xFF8522),
    lev  = memory.readbyte(0xFF8525),
    y    = memory.readword(0xFF8414),
  })
  p1_rec.remaining = p1_rec.remaining - 1
  if p1_rec.remaining > 0 then return end

  local r = p1_rec
  p1_rec = nil

  local saw_special = false
  for _, s in ipairs(r.rows) do
    if s.act == 0x0E or s.act == 0x10 or s.act == 0x12 then saw_special = true break end
  end
  if not saw_special then return end

  p1_files = p1_files + 1
  write_object_to_json_file({
    note = "P1 through one knockdown, from the hit. edge_frame = the " ..
           "0xFF8580 0->1 edge Pit of Blame's own trigger fires on (nil if " ..
           "the window ended before it). act 0x0E special / 0x10 ES / 0x12 " ..
           "EX. mv = move id at 0xFF8506. btn/lev = 0xFF8522/0xFF8525.",
    hit_frame  = r.hit_frame,
    edge_frame = r.edge_frame,
    rows       = r.rows,
  }, LOG_DIR .. string.format("/p1_manual_%02d.json", p1_files))
  print("[p1 watch] wrote p1_manual_" .. string.format("%02d", p1_files) .. ".json")
end

return {
  ["registerStart"]  = registerStart,
  ["mark_queue"]     = mark_queue,
  ["record_input"]   = record_input,
  ["registerBefore"] = function()
    sync_diag_hooks()
    registerBefore()
    p1_watch()
  end,
  ["enabled"] = is_enabled,
  ["mark_poke"]      = mark_poke,
  ["mark_hold"]      = mark_hold,
  ["get_last_check_block_frame"] = function() return last_check_block_frame end,
  ["mark_rev4_tick"] = mark_rev4_tick,
  ["mark_write"]     = mark_write,
  ["mark_tick"]      = mark_tick,
  ["get_last_nonzero_lever"]  = function() return last_nonzero_lever end,
  ["get_last_nonzero_button"] = function() return last_nonzero_button end,
}
