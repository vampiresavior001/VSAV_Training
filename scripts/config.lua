local default_training_settings = {
	infinite_time = true,
  gc_button = 1,
  gc_freq = 1,
  gc_delay = -1,   -- -1 = Auto (per-character dash attack timing)
  stage_position = 1,   -- 1 = Off; 2..7 place the two on the stage
  counter_attack_lever = 1,   -- 1 = As Is; 2 = Neutral; 3..10 = the eight directions
  gc_input_delay = 0,
  roll_direction = 1,
  guard_action = 1,
  pb_type = 1,
  dummy_neutral = 1,
  display_pushbox_axis = false,
  guard = 1,
  counter_attack = 1,
  counter_attack_random_upback = 1,
  enable_slot_3 = false,
  display_movelist = false,
  recording_slot = 1,
  random_playback = false,
  enable_slot_1 = false,
  p1_refill_timer = 1,
  p2_refill_timer = 1,
  show_hitboxes = false,
  enable_slot_2 = false,
  push_block_type=1,
  p1_max_life= 288,
  p2_max_life= 288,
  enable_slot_4=false,
  enable_slot_5=false,
  mo_enable_frame_data=false,
  -- 1 = P1, 2 = P2. A 1-based index into the list on the menu row, and P1 is
  -- how the readout has always behaved.
  mo_frame_data_side = 1,
  display_recording_gui= false,
  display_hitbox_default = true,
  display_hud=true,
  input_event_type = 0,
  inp_history_scroll = 0,
  graph_data_index = 0,
  counter_attack_button = 1,
  -- Bumped when a stored value changes meaning; utilities.lua migrates on
  -- load. 1 = pre-11.4 numbering of counter_attack_stick.
  settings_version = 5,
  counter_attack_stick = 1,
  delay_after = false,
  p1_reversal_list = 1,
  p1_reversal_strength = 1,
  p2_reversal_list = 1,
  p2_reversal_strength = 1,
  p1_infinite_df = false,
  p2_infinite_df = false,
  use_character_specific_slots = true,
  enable_custom_palette = true,
  p1_char_palette = 0,
  p2_char_palette = 0,
  -- Index into menu.lua p2_throw_tech_chance. 5 = 100%, which is what the
  -- old boolean true did.
  p2_throw_tech = 5,
  p2_block_chance = 1,
  looped_playback = false,
  pb_type_rec = 1,   -- 1 is None; 0 was out of range for the list
  anak_projectile = 1,
  lei_lei_stun_item = 0,
  -- THESE SHIP false, NOT 0.
  --
  -- Every one of them is read as `if globals.options.X then`, and IN LUA ZERO IS
  -- TRUE. Shipping 0 turned the whole Analysis tab on for anyone who unzipped a
  -- build without carrying a settings file over - which is the fresh install,
  -- and exactly the case nobody tests. Reported 2026-09-19 as "why do these
  -- lines appear after deleting scripts and setting up again".
  --
  -- The menu rows already declare false; only this table said 0.
  show_move_strength = false,
  show_pb_pushback_timer = false,
  show_pb_timer = false,
  show_throw_invuln_timer = false,
  show_mash_timer = false,
  show_pursuit_indicator = false,
  show_invuln_timer = false,
  display_airdash_trainer = 0,
  show_x_distance = 1,
  display_dash_interval_trainer = false,
  display_dash_length_trainer = false,
  display_short_hop_counter = false,
  display_dash_attack_cancel_trainer = false,
  display_attack_dash_gap_trainer = false,
  display_frame_trap_trainer = false,
  show_projectile_count_limiter = false,
  display_bishamon_ubk_trainer = false,
  use_recording_savestate = false,
  -- Per-trigger action sequences, keyed "guard"/"counter"/"reversal". Written
  -- by the action sequence editor, which stores motions and buttons as the
  -- strings make_input_sequence takes rather than as list indices.
  action_sequences = {},
  -- Whether an Action Steps list starts again when it ends. How long the
  -- gap is belongs to the Wait below.
  action_steps_loop = false,
  -- Game ticks from the last step to the next pass's first one. -1 is Auto,
  -- the same promise a step's own Wait makes.
  action_steps_loop_wait = -1,
  -- Pit of Blame. 1 = None, 2 = Normal, 3 = ES - list_menu_item indices, not
  -- values. The row only appears while the dummy is Anakaris.
  pit_of_blame = 1,
  loop_interval_before_frames = 0,
  loop_interval_after_frames = 0,
  restore_recorded_position = false,
  display_pb_stats = false,
  display_jump_in_trainer = false,
  game_speed = 3,
  bgm_on = false,
  -- Display/Etc defaults set from the maintainer's own working setup, so a
  -- fresh install comes up the way the tool is actually used. These three had
  -- no entry here at all and fell back to nil, which reads as off.
  display_pb_counter = true,
  -- Diagnostic readout for Guard Action Frequency. Off by default: it is
  -- there to settle a question, not to sit on screen.
  display_gc_freq_counter = false,
  show_scrolling_input = true,
  -- The dummy's input icons at the right edge. On, because that is what
  -- the tool has always drawn - the row is new, the behaviour is not.
  display_p2_inputs = true,
  show_curse_timer = false,
  lilith_gps = 0,
  min_pb_inputs = 1,
  -- ON since the release marker got its own switch. All this can remove now
  -- is a column carrying nothing new - a direction change, a new press, a
  -- release and anything holding a GC or PB event are all kept - and with
  -- columns per tick there are more of those leftovers to clear.
  skip_nedge_displays = true,
  -- ON, so the input bar looks the way it already did. A settings file written
  -- before this key existed keeps this value: load_training_data() lays the
  -- saved JSON OVER these defaults rather than replacing them.
  show_button_releases = true,
  -- Both of these were read but never declared here, so a fresh install had
  -- them as nil - off, but nowhere written down. Stated at the value the
  -- tool has always shipped with.
  show_damage_calc = false,
  show_gc_trainer = true,
  -- Measured Action Step waits, on the Trainer tab. Off: it is a readout
  -- for building a list, not something to train under.
  display_step_wait_ticks = false,
  -- OFF for a release. It writes a JSON trace per recovery into
  -- scripts/reversal_logs, which is what the timing work was built on and
  -- is pure cost for anyone just training. Toggle it in the Analysis tab.
  knockdown_logger_enable = false,
  -- The folder of the last ACCEPTED Export/Import dialog, remembered across
  -- sessions. One for the whole tool, not per character. Empty means no
  -- memory yet and the dialog opens where it always did; a folder that has
  -- since been deleted falls back the same way, inside the dialog itself.
  -- Written by the Action Pattern Library's file transfer, never shipped.
  pattern_dir = "",
}

local configModule = {
  ["default_training_settings"] = default_training_settings,
  ["registerBefore"] = function()
    local config_matrix = training_settings
    return config_matrix
  end
}

return configModule
