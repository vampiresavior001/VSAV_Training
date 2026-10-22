# VSAV Training Mode — Release Notes

日本語: [RELEASE_NOTES.ja.md](RELEASE_NOTES.ja.md)

Newest first. Older releases are kept below.

---

## v11.7.31

P1 can now guard while you record. During your own playback the dummy no
longer counters, and a Recording counter starts over when the dummy is hit.

### New: P1 guards while you record

- With `Recording > Recording P1 Guard = Auto Guard`, P1 (the side you are not
  controlling) guards with the game's Auto Guard while you record with Coin
  (Quick Recording) or Recording Wizard
- You can record strings against a blocking opponent, including against
  characters whose hurtboxes change when they are hit
- It sends no input, so P1's inputs stay out of the recording. P1 stops
  guarding when the recording ends
- The default is `Off`, as before
- Checked in play

### Fix: the dummy's counters mixed into your playback

- When the dummy blocked or was hit during a playback you started, Action Steps
  and other counters ran and mixed into the playback's inputs
- During a playback you started, including the gaps between loops and any
  start wait, the dummy no longer performs its Guard Action. Stopping the
  playback brings it back. Guarding is unchanged
- Checked in play

### Change: a Recording counter starts over when it is hit

- When the dummy was hit during `Reversal - Recording`, `Counter Attack -
  Recording` or `PB Recording`, the rest of its inputs were lost in hit stun and
  no further counter came out
- The playback now stops when the dummy is hit, and the recording restarts from
  the beginning on the next trigger, as Action Steps do
- Checked in play

### Manual

- Section 5.1 covers `Recording P1 Guard`; 5.3 covers counters during your
  playback and Recording counters starting over

---

## v11.7.30

A setting that plays the recording from its start after a state restore, and
one that puts each Coin recording straight into a slot. A state can now be
saved during recording playback and partway through Action Steps.

### New: play the recording from its start after a restore

- With `Recording > Play After Restore = yes`, restoring a state (`Volume Up`
  once, or `Restore State`) is followed by the recording you played last, from
  its start. Restore and play take one press
- What plays is the last of `Volume Down`, `Play Recording`, `Play Quick
  Recording` and the playback after a Coin recording. The dummy's Recording
  counters do not count
- The default is `no`, as before
- Checked in play

### New: put each Coin recording straight into a slot

- With `Coin Saves To = Playback Slot` (under `Recording > Quick Recording`),
  finishing a Coin recording also writes it to the slot chosen in `Playback
  Slot`. No `Copy to Slot` needed
- That slot's recording is replaced without asking. The default is `Own Slot`
  (as before: the dedicated slot only)
- Checked in play

### Change: save a state during playback or Action Steps

- Saving used to be refused during recording playback, partway through Action
  Steps or Specified actions, and while Auto Mash held a grab
- A restore stops whatever runs first, so the refusal protected nothing. A
  save now leaves whatever runs going
- The game is saved as it stands: a dummy in the middle of a move is saved in
  that pose
- Checked in play (during playback and during Action Steps)

### Change: save and restore results in Recording GUI

- Results of a save or restore (or why it did not happen) went to the
  emulator's message line, which Fightcade's FBNeo does not show
- With `Display > Recording GUI = yes`, they appear for about two seconds just
  under the recording status box at the top left. Quick Recording results
  appear there too. Set it to `no` once you no longer need them
- The notice that menu pausing was turned off (the game could not be stopped)
  appears there too, once the menu closes
- Checked on screen in play

### Manual

- Section 5.1 covers `Coin Saves To`; 5.5 covers `Play After Restore` and
  saving during playback
- Sections 2.1, 5.5 and 12.1 say where the results now appear

---

## v11.7.29.1

A counter waiting out `Random Start Wait` and the like no longer disappears
when the menu opens. The v11.7.29 notes and the manual's Mash Meter text are
rewritten more plainly.

### Fix: a counter waiting to start was lost at the menu

- Opening the menu while a counter waited out Specified's `Random Start Wait`,
  Action Steps' or Action Patterns' `Random Start Wait`, or the first step's
  `Random Delay` lost that counter
- A waiting counter is now kept. Neither the wait nor the chosen action
  changes, and it comes out on the same Tick as without the menu. Action Steps
  and Action Patterns that have started still end at the menu
- Checked in play (the counter after a Random Start Wait)

### Manual

- Section 2.1 says a counter waiting to start is kept too
- The Mash Meter text in 4.1 is shorter and plainer

---

## v11.7.29

A Mash Meter shows the remaining count over a grabbed character or one in a
hit that mashing shortens. `Grab Mashing` is renamed `Auto Mash`.

### New: Mash Meter

- `Display > Show Mash Meter` draws `Mash Escape` over a grabbed character and
  `Mash Recovery` over one in a hit that mashing shortens: a cyan bar and the
  count the game is using
- It shows with `Auto Mash` off, with P2 in your hands, during playback and
  under the menu, where it does not count down
- Checked in play

### Change: Grab Mashing is Auto Mash, Show Mash Timer moves to Display

- `Dummy > Grab Mashing` is now `Auto Mash`, and `Analysis > Show Mash Timer`
  is now `Display > Show Mash Meter`. Both keep their earlier settings
---

## v11.7.28.6

TECH HIT in the button history beside PB Stats now stays on the press that
granted the push block, instead of moving down with the presses made after it.

### Fix: TECH HIT moved to the last press

- With a push block granted on, say, the third press, pressing on to six moved
  `TECH HIT` from row 3 to rows 4, 5 and 6. The row was found by looking for
  the last press while the success flag was set
- timers.lua now records the granting Tick's position and the window it belongs
  to from the existing 0x027632 hook, for P1 and P2 separately. The display
  marks only the row at that position. Inputs with no row between it and the
  grant are followed, and a new window cannot inherit the old grant. If the
  position cannot be confirmed, nothing is shown rather than a guess
- Presses after the grant are still counted (the delayed-AG drill depends on
  six presses); PB Count, PB Stats, MultiPush and LateMash are unchanged
- Checked in play: granted on the third press, pressed to six, `TECH HIT`
  stayed on row 3

---

## v11.7.28.5

A Specified motion no longer goes missing with `Button = None` and
`Button Lever = Neutral` together.

### Fix: Button = None with Button Lever = Neutral lost the motion

- With `Button = None`, `Button Lever` replaces the motion's final direction.
  `Neutral` took that direction away, so `Input Motion = Up` did not jump and
  a dash lost its second forward
- With `Button = None`, `Neutral` is now ignored and the motion goes in as it
  is. `Neutral` with a button (a dash-neutral normal) and the other directions
  with no button (replacing the final direction) are unchanged
- Checked in play (`Input Motion = Up` jumps)

### Fix: Knockdown Logger cut its recordings into pieces under the menu

- With `Analysis > Knockdown Logger` on and the menu left open during a hit
  stun, the recording's length kept being counted while the game stood, so one
  scene turned into recording after recording. Nothing is counted while the
  game stands now. It is for investigation; the game itself is unchanged

### Manual

- Section 4.4 says how `Button Lever` works with `Button = None`, and so does
  the menu's help

---

## v11.7.28.4

On a wake-up that turns the dummy round, a Specified dash or dash cancel no
longer comes out as just its button, as a standing normal. Opening the menu no
longer loses the counter after a hit stun or a block.

### Fix: a Specified dash did not come out on a wake-up that turned the dummy

- When the dummy lay facing away from the opponent and turned round on waking
  up, a dash or dash cancel set in `Reversal - Specified` or
  `Counter Attack - Specified` did not come out, and only its button did, as a
  standing normal (a dash cancel + MP became a standing MP, for example)
- The game reads a dash's left and right against the dummy's facing, which
  stays the way it lay until the moment it gets up. The tool decided part of
  the input against another facing, so the first and second forward were read
  as opposite directions. v11.7.6 fixed the last press of a plain dash, but
  not the second forward or the dash cancel's back
- A dash's left and right are now decided against the same facing as the
  game's, and the second forward, the dash cancel's back and the last press are
  re-aimed at the facing of the moment they go in
- In the developer's recordings (Sasquatch, dash cancel + MP), wake-ups that
  turned failed 9 of 9 before and dashed 3 of 3 after. Wake-ups that did not
  turn are unchanged. Also checked in play
- A dash as the first step of Action Steps may share the same shape, but has
  no recordings yet, so it is unchanged

### Fix: opening the menu lost the counter after a hit stun (since v11.7.28.3)

- v11.7.28.3 made the menu end a counter still waiting to come out as well, so
  opening it during a hit stun and the like lost the counter that should have
  followed (during a knockdown it still came out, unless opened just before the
  wake-up)
- A waiting counter is no longer ended: it comes out as usual once the menu
  closes, at the same moment as without the menu, since the game stands still
  meanwhile. Change the counter's settings during a knockdown and that wake-up
  uses the new ones
- Action Steps or Action Patterns into their second step or later, and repeats
  by `Loop Steps` or Specified's `Loop`, still end at the menu. Recording
  playback, `Looped Playback` included, still pauses and carries on
- Checked in play (the counter after a hit stun the menu was opened in, and a
  wake-up with settings changed during the knockdown)

### Manual

- Section 2.1 and the Specified `Loop` explanation now describe this

---

## v11.7.28.3

A dash cancel's walk backwards and a Specified reversal no longer carry on
after the menu. The HUD's "Bubble" no longer shows up where it does not belong.

### Fix: opening the menu right after a dash cancel kept the dummy walking back

- An Action Steps dash cancel keeps holding back until the next step's button
  goes in. When v11.7.28.2 made the menu end the action, that hold was not
  cleared, so it went on after the menu closed. Step one's `Hold` was the same
- Ending the action at the menu now clears them too. Checked in play

### Fix: a Specified reversal still came out after the menu

- The v11.7.28.2 manual said the menu ends Specified actions as well, but a
  Specified action without `Loop` or `Random Start Wait` was not covered:
  opened and closed during a knockdown, the reversal still came out on that
  wake-up. Step one's press in Action Steps could also come out after the menu,
  depending on when it was opened
- Opening the menu now ends them, including one still waiting to come out. The
  same knockdown or hit does not bring it back; it starts again on the next
  trigger
- Not checked in play yet

### Fix: the HUD's "Bubble" could show on an ordinary hit

- "Bubble" under `Display > HUD (Life / Meter)` shows how much is left before
  P2 gets out of Aulbath's Water Jail (inherited from the original fork). It
  was decided by a value nobody had identified, so it showed now and then on an
  ordinary hit
- It is now decided by the game's own values: in a hit reaction, the move's
  hit type is the Water Jail's, and some of it is left. The Water Jail's value
  was checked in the developer's recordings

### Manual

- Section 2.1 says the menu also ends an action still waiting to come out

---

## v11.7.28.2

Opening the menu now ends Action Steps, Action Patterns and Specified actions
every time. The README and manual explanations match it.

### Fix: Action Steps and the like sometimes ended and sometimes carried on after the menu

- Opening the menu is meant to end an Action Steps, Action Patterns or
  Specified action, loops included. Since v11.7.28 paused the game under the
  menu, it ended only when one Tick of the game's processing was still left
  as the menu opened (9 of 29 opens in the developer's play). Otherwise the
  action carried on from the middle once the menu closed
- It now ends on every open. Closing the menu does not resume it; it starts
  again on the next trigger
- Found while checking the public documents against the code

### Manual

- Section 2.1 and the Specified `Loop` explanation now describe this
- The README's "Retry the same situation" mentions `Volume Up` as well as the
  menu
- The English Section 2.1 says "paused" throughout

---

## v11.7.28.1

Opening the menu no longer disrupts recording or playback. Loop waits and life refill timers also pause while the game is paused, then resume when the menu closes.

- Fixed skipped playback inputs and dashes failing after the menu closed.
- Strengthened pause checks. If the game cannot remain paused, a message appears and menu pausing is disabled for the rest of the session.
- Updated Section 2.1 of both player manuals to explain what pauses with the game.

<details>
<summary>Technical details and verification</summary>

### Change: stronger checks that the game remains paused

- Until now, the only check while the menu held the game was that the match's
  Tick did not move. Both characters' state, position and animation must not
  move either. If anything does, the game is no longer stopped for the rest of
  the session and the emulator's message area says so, as before
- The frame the menu closes on, and a position move started from the menu,
  are not checked: those writes are the tool's own. Neither is a state load
- With `Analysis > Knockdown Logger` on, it also writes where the memory
  changed while the game was paused (`scripts/reversal_logs/freeze_log.jsonl`).
  If the game could not be stopped, the reason and what had changed so far
  are written at once. It is for investigation

### Fix: recording and playback advanced while paused or resumed incorrectly

- In v11.7.28 the game was paused while the menu was open, but recording and
  recording playback still ran on the emulator's frames. Opening the menu
  during a playback skipped the inputs in between, so it carried on further
  along when the menu closed; opening it during recording put the menu's frames
  into the recording. The `Loop Interval (Frames)` wait also ran down under the menu
- With `Looped Playback` on, the playback was held for 30 frames after the
  menu closed and the dummy's inputs let go. The game runs again by then, so
  opening the menu in the middle of a forward, neutral, forward dash made the
  neutral long enough to miss the game's window, and no dash came out
- While the game is paused, recording adds no frames, a playback stays where it
  is and the loop wait does not run down. When the game was paused by the menu,
  the 30-frame hold is gone and they carry on as soon as it closes (when the
  game ran under the menu, outside a match for example, the hold stays)
- Recording, playback and the loop wait were found in a code review; the dash
  after closing the menu in play

### Fix: opening the menu could drop one Tick of both players' input

- Opening the menu set a flag in the game (`$3B4`) on both players, so that
  working the menu would not move them. With it set, the game skips that
  player's own input handling, the command and dash checks with it (checked
  in the ROM)
- Opened in the middle of the game's processing, the one Tick left of it ran
  with the flag set: 9 of 29 menu opens in the developer's play. When the
  first forward of a dash fell on that Tick, the dash after the menu did not
  come out and turned into a walk and a standing move (dash MK, dash became a
  walk and a standing MK)
- While the game is paused, the flag is no longer set. When the game runs under
  the menu (a position move, outside a match and the like), it is set as before

### Fix: life refilled while the game was paused

- The `Refill Timer (seconds)` refill counted emulator frames too, so it
  could fire under the menu while the game was paused. `Recording > Save State`
  from the menu could then save the refilled scene
- Under the menu it does not fire, and the rest of the wait is kept: once the
  menu closes, it waits out what was left and then refills
- Found in a code review

### Manual

- Section 2.1 says recording, playback, the loop wait and the life refill
  pause under the menu too, and how you are told if the game cannot remain paused

</details>

---

## v11.7.28

`P1 Coin` now records the dummy's action and plays it back at once (Quick
Recording), and `Volume Up` saves and restores the state. The game stands
still while the menu is open.

### New: Quick Recording (record with Coin)

- During a match, press `P1 Coin` to take control of the dummy (P2) and start
  recording. Press it again to finish: you are back on P1 and the take plays
  from where things stand. `Looped Playback`, `Random Start Wait` and
  `Reset Distance Each Loop` apply as they do to normal playback
- The take is kept in a place of its own for each dummy character
  (`quick_recording.mis`) and does not overwrite `Slot 1`–`Slot 5`. To keep
  it in a slot, use `Copy to Slot` under `Recording > Quick Recording` and
  choose the slot in the window that opens. `Play Quick Recording` also plays
  it
- With `Auto Trim` (default `yes`), the time before the first input and after
  the last is cut. `Reset Distance Each Loop` returns to the spacing at the
  moment of the first input
- The `P1 Coin` presses that start and finish a take are not recorded. A take
  with no input is not saved, and the previous one stays
- While recording, the dummy's automatic actions such as guarding and counters
  are off. If the dummy character changes or the match ends during a take, the
  take is discarded and you are back on P1
- The HUD shows `Quick` while recording and while the take plays

### New: save and restore a state (Volume Up)

- Press `Volume Up` twice in a row to save the current state. Press it once to
  return to the saved state a moment later (about 0.25 seconds).
  `Recording > Save State` on the menu also saves (it asks: `Yes` saves), and
  `Recording > Restore State` restores
- There is one saved state. Choosing characters again makes it unusable. A
  state saved with other characters or at another game speed is not restored
- Nothing is saved during recording playback, while Action Steps or Specified
  actions are still to come, or while Grab Mashing has the dummy grabbed.
  Restoring first stops whatever is running, such as playback
- A restore from the menu (`Restore State`, or `Volume Up` once) closes the
  menu first, then loads
- Neither happens while recording, during Recording Wizard and so on. When
  nothing is saved or restored, the emulator's message line shows why

### New: the game stands still while the menu is open

- While the menu is open during a match, the game now stands still:
  characters, projectiles, the round timer and stun do not advance, and
  closing the menu carries on from there. Until now only both players' inputs
  were taken away and the game ran on
- FBNeo itself is not paused; only the game's task manager (in the ROM) stops
  handing out work, so the menu still works from an arcade stick or
  controller. The music keeps playing
- During a position reset the game runs until the characters are in place.
  `Save State` from the menu saves the scene as it stands
- If it does not hold (the match's Tick moves), it is switched off for the
  session and the emulator's message line says so

### New: Grab Mashing also works in hits that mashing shortens

- Besides the grab, the ROM has two routines that read mashing: one takes
  time off a hit reaction, the other plays its motion further. Both are used
  by special hit reactions, such as from projectiles. When the dummy takes
  one, it now mashes as `Grab Mashing` is set
- In a special hit reaction, queued counteractions are kept. While a
  counteraction's input for getting out is being sent, or Action Steps are
  still to come, mashing pauses and the counteraction goes first
- Confirmed in the developer's recordings (`Fastest`). The time left goes
  down by at least 1 a Tick, so with no mashing a reaction lasts "time left +
  1" Ticks
  - Demitri's Chaos Flare: 17 to 37 left, out in 1 to 4 Ticks (4 times)
  - Bishamon's Karame Dama: 119 left, out in 5 to 13 Ticks (2 times)
  - Sasquatch's Big Branch: 39 or 79 left, out in 2 to 9 Ticks (21 times, and
    3 more cut short by the next attack)
  - Aulbath's Water Jail: 417 left, out in 27 Ticks (once)
  - Q-Bee's `QJ`: the motion routine, with a new press every Tick for 61
    Ticks (twice). How long it lasts without mashing was not measured
- Aulbath's poison gas (hit type 32) is not shortened by mashing. In the
  developer's recordings neither routine that reads mashing ran during its
  hit reaction, and the dummy did not mash
- Other moves are not checked yet

### New: a line to learn Bishamon's unblockable spacing from the shadows

- With `Trainer > Show Bishamon UBK Trainer` on, besides the words above P2,
  a line on the ground, at your own shadow's height, marks where the shadow's
  edge facing the opponent has to be - there while you are still far away, so
  it shows how close to come: blue standing, yellow crouching, green both.
  While the tip of your shadow is on the line, its ends turn white. The line
  is placed while you stand and stays there while you walk or attack. Use it
  to learn the gap between the two shadows, then make the same gap with the
  aid off
- Where the shadow is and how wide it looks come from the ROM's shadow
  routine and the decoded graphics (54 shapes). It is worked out from the same
  frame as the push boxes, so it points at the same spacing as the words above
  P2 and the box display
- The words above P2 take the line's colours: `Standing` blue, `Crouching`
  yellow (green up to v11.7.27)

### Change: an Auto (After) ground dash behind the dummy's own move is the fastest

- A ground dash on `Auto (After)` placed after the dummy's own move on the
  ground (a special, a normal and so on) now starts its input as the move
  ends and comes out on the first Tick the dummy can act. It used to start its
  input only once the dummy was free, and came out a few Ticks late (5 after
  Sasquatch's Big Branch)
- It is the fastest from the second time a move is used: how many animations
  the move is made of is learnt from how it ended (for this session). The
  first time is as before
- What is left of the move is counted from the game's animation data (the
  cels' lengths). The last input is pressed on the Tick the dummy is free,
  once the game's dash recognition is confirmed to be still running; if it is
  not, the input is entered again, as late as before

### Change: P1 Coin records by default

- `Quick Recording` is `yes` by default. To have `P1 Coin` only switch which
  character you control, as before, set `Recording > Quick Recording = no`

### Change: no more recording with Volume Up, Use Savestate Upon Recording removed

- `Volume Up` no longer starts recording. Record with `P1 Coin` or Recording
  Wizard
- `Use Savestate Upon Recording` (save a state when recording starts and load
  it on every playback) is removed. To repeat from the same situation, use
  `Volume Up` to save and restore

### Change: Grab Mashing alternates PPP + up and KKK + down

- `Grab Mashing` now presses PPP + up and KKK + down by turns. With no
  forward or back, the medium and heavy buttons do not tech the grab. It
  switches every 7 Ticks with `Normal`, every 4 with `Fast` and every Tick
  with `Fastest`
- Each time the game checks the grab, it counts one new direction press and
  one new button press (confirmed in the ROM). Three buttons at once count the
  same as one. The `Normal` and `Fast` intervals were worked out from how the
  ROM counts, to keep about the pace of v11.7.27 (not measured on the
  emulator)

### Change: Recording Slot is now Playback Slot

- The setting that picks the slot to play is now `Playback Slot`, and
  `Last Recording` is no longer in its list: with `Volume Up` no longer
  recording, nothing writes `last_recording.mis`
- A settings file that had `Last Recording` selected moves to `Slot 1`; any
  other choice keeps the same slot
- An existing `last_recording.mis` stays but cannot be played. To keep using
  it, close FBNeo and rename it to a free name from `slot_1.mis` to
  `slot_5.mis`

### Fix: a hit could drop the rest of the Action Steps, or frames of a recording

- Depending on the state of the one it hit, the dummy's remaining Action
  Steps were thrown away as if the match had stopped (after Sasquatch's Big
  Branch connected, the dash and MK after it did not come out). As during a
  transformation, the match now counts as running while either character is
  active
- Recording skipped those frames for the same reason: the take came out
  shorter than the play, and on playback what came after the hit played
  early (the combo after Big Branch did not connect). Takes made up to
  v11.7.27.1 that include such a hit should be recorded again

### Fix: loading a state could change the centre spacing

- The centre arrangements of `Lua Hotkey 2` (`Dummy > Position`) return to the
  spacing at the start of the round. Loading a state moves both characters a
  long way at once, which was taken for a round starting, so the spacing became
  wherever the state was loaded. A load no longer resets it
- Found while building the restore. Going by the code, earlier versions could
  do the same when loading an emulator state or with
  `Use Savestate Upon Recording`

### Fix: P2's input display cut off a third button

- P2's input column left room for three icons from the right edge, so a line
  with a direction and three buttons drew the third button (HP or HK) off the
  screen. It now leaves room for four

### Manual

- Section 5 gains "5.1 Record with Coin" and "5.5 Save and restore a state";
  Recording Wizard and the sections after it move down one number
- Grab Mashing in 4.1 covers the new inputs and the special hit reactions
- 11.8 gains the steps for learning Bishamon's unblockable spacing from the
  shadows
- 2.1 says the game stands still while the menu is open
- The hotkey table (1.2), 2.2, the save locations in Section 13,
  troubleshooting in Section 14 and the README's controls table follow the
  changes above

---

## v11.7.27.1

Chain Trainer no longer shows a hit on the opponent's reversal Tick itself as
a `LINK`. The README and manual names and explanations are reviewed.

### Fix: a hit on the reversal Tick could read as LINK

- A hit landing once the opponent has reached the reversal Tick is not a
  combo. A hit on that very Tick, though, still sees the opponent in hitstun,
  so it could show as a `LINK`. As with special cancels, it is now a `GAP`
  when the opponent reached the reversal Tick and was not hit again
- Not seen in the developer's recordings: all 424 hits after a reversal Tick
  were already `GAP`, and replaying 20 recorded sessions shows the same lines
  as before

### Manual

- The README uses the current names, `GC Command Trainer` and
  `Seq. Command Trainer`, and now points to Chain Trainer
- Chain Trainer's `MULTI` also happens with two or more different buttons
  pressed on separate Ticks of hit stop, not only together. A link's `/Mt` is
  the last press that lands before the opponent's reversal Tick
- Grab Mashing is explained in the order purpose, settings, when it stops; how
  the inputs are chosen is folded
- English wording reviewed

---

## v11.7.27

New Grab Mashing makes the dummy mash while it grabs or is grabbed.

### New: Grab Mashing

- `Dummy > Grab Mashing` (`Off` / `Normal` / `Fast` / `Fastest`, default
  `Off`). While the dummy grabs or is grabbed, it mashes directions and
  buttons. Only grabs where the game reads mashing are covered (the routine
  was confirmed through ROM analysis); ordinary throws and hitstun are not
- `Normal` and `Fast` use preset rhythms; `Fastest` makes a new direction
  press and a new button press every Tick. The buttons are LP and LK only:
  medium and heavy ones can tech the grab. The game counts a press the same
  whatever its strength, so nothing is lost
- When the dummy is grabbed, the reversal plans it had before (Action Steps,
  Specified and so on) are canceled. When it grabs, its own action keeps
  running and only its input during the grab is replaced. The throw-tech input
  from `Random Throw Tech %` is also replaced during the grab
- It does nothing while you control P2, while a recording plays or is being
  made, or during the Recording Wizard
- Checked on the developer's side with Demitri's grab. With the dummy
  grabbed, a grab that lasts 121 Ticks with nothing pressed was escaped in 23
  to 34 Ticks with `Fastest`, and in 66 to 74 with `Normal` and `Fast` (the
  amounts are random), with no throw tech. With the dummy grabbing, input went
  in on 120 of the grab's 121 Ticks (the first reads input made before the
  grab began). Other characters' grabs have not been checked yet

### Manual

- Grab Mashing added to 4.1

---

## v11.7.26

New Chain Trainer shows, Tick by Tick, whether your chains and links
connected. Reversal and Counter Attack's Specified gain Loop, and GC Command
Trace and Command Trainer are renamed.

### New: Chain Trainer

- `Trainer > Chain Trainer` (`Off` / `P1` / `P2`). After a normal attack hits,
  it shows whether the next move chained and whether a link was in time, one
  line per hit at one character per Tick, as Air Guard Gaps does
- For a chain it draws the presses held during hit stop and the window, with
  results such as `CHAIN 4t`, `LATE 2t` and `NO CHAIN`. It reads the game's
  own cancel check (the check was confirmed through ROM analysis)
- A link counts from the first Tick you could act after the first move ended.
  `LINK 3t/5t`: pressed on Tick 3 and linked; a press up to Tick 5 would have
  linked. `GAP` when it was too late, and `EARLY 3t/1t` when you pressed while
  the first move was still running and nothing came out. Links out of dash
  attacks are covered too
- Cancels into specials, ES, EX and Dark Force are named, with whether they
  combo'd and the deadline, as in `SP 8t/10t`
- Checked on the developer's side by replaying recorded play: on 414 of the
  415 lines where a window was worked out, the prediction matched the game's
  result (linked or not). The one that did not (a link into a projectile
  special) shows no window. The Ticks to the opponent's reversal Tick come
  from 77 hits of Anakaris's normals on Morrigan; other matchups have not been
  checked yet
- While it is on, GC Command Trainer and Seq. Command Trainer, which share its
  space, are not drawn

### New: Loop for Specified

- `Reversal - Specified` and `Counter Attack - Specified` gain `Loop` (below
  `Random Delay`). With `yes`, the dummy does the set action again each time it
  finishes, so dash-and-attack pressure can be repeated for PB and GC practice
  without building it in Action Steps
- The first time still starts on the usual trigger. After that, an action that
  leaves the ground goes again on landing, and one that ends on the ground
  goes again once the dummy can act

### Fix: Specified dashes did not come out

- When a Specified action starts with a dash and `Pose` includes forward (down
  forward, say), the dash almost never came out on a response after being
  hit. Forward stayed held, so the first forward was not a fresh press. A
  neutral now goes in before the dash in that case, on Loop's later rounds
  (after landing) too
- Sasquatch's `Forward Dash Cancel` with `Button Wait` on `Auto` now waits 8
  Ticks instead of 7. At 7 the button came before the cancel could take it, and
  no short dash came out. Loop's later rounds use the same Tick as the first

### Change: names on screen

- `Show GC Command Trace` is now `Show GC Command Trainer`, and `Command
  Trainer` is now `Seq. Command Trainer`. Both show the inputs the game's
  command reader took, so the names now pair. Saved settings carry over

### Manual

- Chain Trainer added as 11.7 (the old 11.7 Other trainers is now 11.8)
- Specified's Loop added as 4.5
- The new names are used throughout, and the Meaty Timing menu screenshot is
  retaken
- The introductions now say this is a Vampire Savior training mode for
  Fightcade 2 (the README too)
- Troubleshooting covers GC Command Trainer and Seq. Command Trainer not
  appearing

---

## v11.7.25.2

Frame Meter now draws a dash attack or special made right out of a jump
attack's landing as a move of its own. The manual's screenshots now sit inside
the steps they show, and the wording is reviewed.

### Fix: dash attacks and specials right after a jump attack's landing

- When a dash or a special cancelled a jump attack's landing motion, the move
  that followed was drawn as doing nothing except its red active tiles, and
  the numbers and Advantage were the jump attack's
- The landing motion now ends where the dash or special starts. The dash is
  drawn as a dash, and the dash attack or special as a new move, measured on
  its own
- Checked on the developer's side with Lilith's jump attacks into a dash attack
  and into a projectile special. The special's Advantage matched the game's
  value (+2) all 15 times

### Manual

- Screenshots that show a step now sit inside that step (on GitHub they looked
  like the last step's)
- The safe-jump example in Section 10.B now says it is timed for Morrigan's
  in-place wake-up and needs `Wakeup = None`
- In 11.2 Tick Data, the frame data tables' details and limits are folded. The
  link to the tables and the note that their values are not guaranteed to
  match stay in the text
- Wording reviewed in both languages

---

## v11.7.25.1

In Action Steps, Lei-Lei's crouching MK canceled into Tenraiha now combos. Fixed
an issue that prevented special-move input sequences from advancing during
hitstop.

### Fix: delayed special moves with Wait set to Cancel

- During hitstop, a special-move step kept holding the current input instead
  of advancing through the sequence. After a long freeze, it restarted the
  sequence from the beginning. With Wait set to `Cancel`, input begins on
  contact, so most of the sequence overlaps hitstop. This delayed the special
  too much to combo, as with Lei-Lei's crouching MK into Tenraiha
- Specials (the specials under `Action`, and command inputs in Custom) now keep
  going through hitstop, because the game accepts special commands during it.
  Dashes and normals are unchanged, because the game does not use inputs made
  during hitstop for them. Mashed moves (SxP) and Pit of Blame are also
  unchanged, as they have not been checked
- In testing, crouching MK into Tenraiha comboed in all seven attempts with
  Wait set to `Cancel`. Tenraiha activated during hitstop; before the fix, it
  activated 6 Ticks after hitstop ended. Motion specials have not been tested yet

### Fix: GC Command Trace not shown

- In v11.7.25, GC Command Trace was not shown while Command Trainer was on,
  even for a character without a sequence super. It is now hidden only while
  Command Trainer is displayed for a supported character

---

## v11.7.25

Command Trainer is new: see, step by step, which inputs of a sequence super the
game accepted. Ten moves, Darkness Illusion among them.

### New: Command Trainer (sequence supers, step by step)

- Pick a move under `Trainer > Command Trainer` (below `Show Air Guard Gaps`)
  and it shows at the top right. Left and right go through `Off` and P1's
  character's moves only, and changing characters switches to that
  character's move. Nothing is shown for a character without one. P1 only
- Moves: Darkness Illusion, Finishing Shower and Cryptic Needle (Morrigan),
  Luminous Illusion (Lilith), Midnight Pleasure (Demitri), Moment Slice
  (Gallon), Pharaoh Magic, Pharaoh Salvation and Pharaoh Decoration
  (Anakaris), Tenraiha (Lei-Lei)
- Each row is an input the game accepted, with the Ticks since the one before.
  A step accepted 14 or more Ticks later is orange (the random window ran
  long), an input that was not accepted is written beside the row (such as
  `LK+F`), and the step the command expired on gets a red `x`. The last line
  is `Success` (Ticks from the first input to the last), `Expired` (Ticks
  since the last accepted input), `Not started` (the command was complete but
  the move did not come out) or `Interrupted` (cleared partway)
- How the game accepts the inputs was confirmed by ROM analysis
  for all ten moves. Only the input being waited for, pressed on that Tick, is
  accepted: another input started on the same Tick, or a held one, does not
  count. Each accepted input rolls the window for the next: within 13 Ticks
  always works, 14 to 18 depends on the roll, and 19 or more never does
- GC Command Trace is not shown while this is on (the two would overlap). This
  tool keeps the super meter stock at 99, so a move never fails for lack of
  meter

### Change: Knockdown Logger

- With `Analysis > Knockdown Logger` on, it also writes the sequence command
  log (`scripts/reversal_logs/command_log.jsonl`), for investigation

### Manual

- New section 10.G, "Perform sequence supers consistently (Command Trainer)"
- The Dummy and Trainer tab screenshots are retaken from the current menus
- The safe-jump and Meaty Timing screenshots are replaced, and the frame data
  tables the tool follows (darkstalkers.web.fc2.com) are named
- Section 11.2 explains how the tables' jump-attack recovery differs from Tick
  Data's
- Wording reviewed in both languages

---

## v11.7.24.2

Frame Meter now draws recovery the way the frame data time charts on the site
below do. The numbers do not change.

http://darkstalkers.web.fc2.com/savior/savior.html

### Change: the move's last Tick is blue

- The Tick a move ends (the Tick `$105` drops to 0; for a jump normal, the Tick
  it lands) is now drawn blue, as the last recovery tile. Demitri's close
  standing LP reads 3 green, 3 red and 7 blue, the same as the table's time
  chart, 3 | 3 | 7. Midnight Pleasure, which ends right after its active
  frames, now shows one blue tile
- Recovery is now the blue count (it was one more than the blue tiles).
  Recovery, Total and Advantage read the same values as before
- The gap between the attacker's last blue tile and the defender's tile with a
  magenta top (the Tick it comes out of stun) is the Advantage
- The tables count recovery as the move's follow-through frames, and their time
  charts draw it up to the frame the move ends

### Manual

- The Frame Meter section's description of Recovery and the blue tiles is
  corrected, with how to read Advantage from the tiles

---

## v11.7.24.1

A jump normal's recovery and total now end when it lands, and Tick Data
reports advantage for a meaty that lands right on the reversal Tick.

### Change: a jump normal ends on landing

- Its landing motion can be canceled into a grounded normal, so it is no
  longer counted in Tick Data's Recovery and Total or in Frame Meter's
  Recovery, Total and Advantage. The Tick it lands is counted as the last
  Tick of recovery. Until now only advantage was measured to the landing, and Recovery
  and Total ran through the landing motion
- Frame Meter draws the landing motion as doing nothing (dark gray)
- A move that ends in the air ends there. An air special's landing recovery is
  counted as before. A landing motion canceled into a grounded normal is
  counted as a new move
- On the developer's machine, Demitri's jumping LP on Morrigan's wake-up read
  the same in Tick Data and Frame Meter (Recovery 1, Total 6 and 8)

### Fix: no advantage for a hit right on the reversal Tick

- With Meaty Timing at `Reversal +0t`, Tick Data showed `--` for Advantage and
  Hitstun. A waking opponent goes into hit stun without passing through a free
  state, so the hit was missed. The game's own strike confirmation now counts
  as a hit too. On the developer's machine a meaty at `Reversal +0t` now reads
  Advantage +13t, the same as Frame Meter's 13
- A meaty on a waking opponent read `Wakeup` instead of `Hitstun` for the
  opponent's recovery: the knockdown flag from before the hit was picked up.
  Only the flag from the hit on counts now. The value is unchanged (in the
  developer's logs the flag was set only before the hit, and the recovery
  ended on the same Tick either way)

### Manual

- The description of turning Auto-Flip off is corrected: it does not hold one
  direction, it runs the whole input from the orientation at its first input
  (the menu help too)
- The safe-jump example in recipe 10.B now has steps to check both the meaty
  timing and the landing block, and a screenshot of the reversal Shadow Blade
  blocked on landing
- The Tick Data and Frame Meter sections say that a jump normal ends on landing

---

## v11.7.24

You can now see, on the dummy, what the same input turns into after a
cross-up. The README and the manual are reorganized so the feature you are
after is easier to find.

### New: study option selects on a side switch

- Set `Auto-Flip Inputs on Side Switch = no` on the Dummy or Recording tab, and
  the dummy uses the orientation at the first input for the entire sequence,
  without automatically swapping left and right after a side switch. Direction
  changes within the recording or Steps still occur as defined. The default
  remains `yes`, preserving the existing behavior
- Applies to recording playback, Action Steps, Action Patterns and the
  Specified reversal and counter. See
  [10.F](PLAYER_MANUAL.en.md#side-switch-os) for how to use it and the details

### Manual and README

- The README now opens with what the tool does and what you can test and
  practice. Demitri's safe jump, with a screenshot, shows how to examine your
  offense (also in manual recipe 10.B)
- Some manual section numbers changed. Section 11 now runs 11.3 Meaty Timing,
  11.4 Frame Meter, 11.5 Action Timeline, 11.6 Air Guard Gaps and 11.7 Other
  trainers, and Sections 12 to 15 form an appendix. Existing links still work
- Part 2 opens with how the dummy works, and "Choose what to practice" uses the
  README's four groups: defense, offense, examining moves and building the
  opponent

---

## v11.7.23.1

### Meaty Timing: the opponent's answer, and Q-Bee's wake-up

- When the opponent's attack struck you first (an invulnerable reversal, for
  example), the row now reads `Wake-up  Reversal +4t  P2 Hit First`, with their
  side. Their attack used to count as your meaty, with your active Tick,
  whenever your own attack box was out. Which side struck is now taken from the
  game's own strike check; in the developer's logs it told Morrigan's Shadow
  Blade reversal apart both times
- A projectile's contact reads `Active -` even while your own attack box is out
- Q-Bee's wake-up, which has no reversal Tick, is now measured:
  `Wake-up  Actionable +Nt`, counted from the first Tick she can start
  anything, specials and normals alike. See
  [Q-Bee's wake-up](PLAYER_MANUAL.en.md#meaty-timing-qbee)

### Frame Meter

- The meter now omits white invulnerability marks and throw-invulnerability
  stripes during hit stun, block stun, knockdown and wake-up, on the ground
  and in the air. This makes invulnerability during actionable periods easier
  to see; it does not mean those states are always invulnerable. Previously,
  white marks continued through the end of wake-up, up to the reversal Tick
- Q-Bee's head shake at the end of her wake-up is drawn white from the first
  Tick she can act (`Actionable +0t`): ordinary strikes are still turned away
  there for 2 or 3 Ticks
- Loading a state no longer joins the log from before it to the one after it,
  and no longer draws a reversal mark or a throw from comparing the two sides
  of the load. The log on screen stays to be read; the next action starts a new
  one

### Settings file

- A settings file with text after its closing brace, or a list instead of
  settings, is now treated as unreadable: its path is shown and nothing is
  saved until FBNeo is restarted. Such a file used to load in part and be saved
  over

### Manual

- How to choose the timing for the response you expect, with a `+0t` to `+6t`
  reference ([11.2](PLAYER_MANUAL.en.md#meaty-timing-strategy)), and Meaty
  Timing in the wake-up pressure recipe
  ([10.B](PLAYER_MANUAL.en.md#wakeup-pressure-drill))
- GC tips: the arcade stick's position for slow 1P-side inputs
- Frame Meter: the number on a run leaves out the gray-topped Ticks

---

## v11.7.23

### New: Mute Idle Sounds

- `Game > Mute Idle Sounds` (off by default) stops the voice and sound effects a
  character repeats while idle: Gallon, Dark Gallon, Jedah, Victor and B.B. Hood
  (crouching idle). The idle animation still plays, and attack, guard and hit
  sounds and BGM stay. Both P1 and P2. See
  [12. Display and game settings](PLAYER_MANUAL.en.md#12-options)

### New: Meaty Timing

- `Show Meaty Timing` under `Trainer > Tick Data` (on by default; a saved off
  stays off). After a wake-up, block stun, hit stun or air recovery, one row
  between the Tick Data rows and the Action Timeline shows when your attack
  touched the opponent, counted from their reversal Tick, and on which active
  Tick: `Wake-up  Reversal +0t  Active 3t`
- The reversal Tick is the first Tick the opponent can act again, when only
  blocking and specials are available (Frame Meter's magenta bar). The first hit
  or block from +0 to +30 Ticks is recorded. `Active 2:3t` is the third Tick of
  the second active period; `Active -` is a projectile or a throw
- It does not judge whether a setup worked. See
  [11.2 Tick Data](PLAYER_MANUAL.en.md#meaty-timing)

### Frame Meter: the numbers no longer change with the display settings

- **Gray bar along the top: frozen in hitstop.** A Tick a character spent frozen
  is left out of its numbers and run counts. Demitri's close LP, blocked, reads
  Startup 4 / Total 13 / Recovery 7 with `Show P1 Inputs` on or off, and the
  defender's yellow run now matches Tick Data's Hitstun (13 for that LP, 14 for
  a LK that hits). Checked in the game
- **Magenta bar along the top: reversal-only tick.** The first Tick a character can
  act after a wake-up, block stun, hit stun or an air recovery, when only blocking
  and special moves are available. Both P1 and P2. Checked in the game: a special
  comes out from the marked Tick, a dash from the next. Q-Bee's wake-up has none
- `Log Hitstop Frames` is gone. Hitstop Ticks and the PB window are shown while
  `Show P1 Inputs` is on: inputs are accepted during hitstop, and this is for
  seeing when yours went in. A PB success is always shown
- Throw invulnerability is drawn as red and white stripes on the lower half of
  the tile, over its own color, instead of replacing startup, active and
  recovery. `Show Throw Invulnerability` no longer changes the numbers, and is
  on by default (a saved setting keeps its value)
- `Show Movement Data` is now `Include Jumps / Dashes`, on by default (a saved
  setting keeps its value)
- The count on a run of tiles is shown from 5 tiles (was 6)
- A move that can act again right after its active period read Recovery 0;
  the Tick it becomes free counts, as in the tables and Tick Data (Demitri's
  Midnight Pleasure whiffed: 2 / 29 / 1, Total 31)
- Invulnerability is drawn as solid white on the lower half of the tile, over
  its own color, instead of a white tile, so a move whose invulnerability ends
  during startup shows where it ends, and Startup is no longer counted from
  there. It follows the hitbox display: moves invulnerable because their
  hurtboxes disappear, such as Bishamon's Kirisute Gomen, are shown too.
  Dark Force activation, which the white tile used to cover, is green
- Throws are shown. A throw has no attack box, so a whole throw used to be
  drawn as startup and the one thrown as doing nothing. The Ticks the game
  tries the grab (whiffs included) and the Tick the opponent is grabbed are now
  red, so a throw's Startup ends there; being thrown is yellow
- See [11.6 Frame Meter](PLAYER_MANUAL.en.md#frame-meter), with new screenshots

### Settings moved out of `scripts`

- The settings file (settings, Action Steps and Action Patterns) is now
  `training_data/training_settings.json` in the FBNeo folder, outside `scripts`,
  which an update replaces. Its format and contents are unchanged
- On the first start, an existing `scripts/training_settings.json` is copied
  there automatically. If both exist, the one in `training_data` is used. The
  old file stays where it was as a copy and is no longer updated
- Recordings stay in `scripts/macro`: back up both `training_data` and
  `scripts/macro`
- A save is written to a temporary file and checked before it replaces the
  file, so a failed save no longer leaves an empty file
- If a settings file cannot be read, a red message at the top of the screen
  shows its path. Nothing is saved until FBNeo is restarted, and the file is not
  overwritten. See [13. Saving, backups and updates](PLAYER_MANUAL.en.md#13-save)

### Launcher: the training folder's path may contain spaces

- `run_vsav_training.bat` now hands the savestate and the script to FBNeo
  relative to its own folder, so a path with spaces in it (such as
  `C:\Fight cade\...`) works. Japanese characters in the path may still cause
  problems
- Run from a console, it no longer closes that console

### Fix: negative count in the scrolling input bar

- Right after starting the script, the oldest column of `Show Scrolling Input`
  could show a large negative count (such as -25593). A column recorded before
  the first game Tick was counted against a different clock. Such columns are now
  dropped, and a count is never drawn negative

### Fix: Tick Data's throws

- A command throw's Startup ended on the range check the game makes when the
  command is entered, not on the grab. A dash into Demitri's Negative Stolen
  read Startup 1 and two active periods; it is the grab, five Ticks later, as
  in the frame data tables (発生 6, 持続 1)
- Tick Data now counts the Ticks the game tries a grab, in every way it can:
  standing, airborne and in hit stun. Air throws were not measured before

### Fix: Pharaoh Salvation and Pharaoh Decoration

- Anakaris's two supers had each other's move ID. Choosing `P. Salvation` as a
  Character Specific Reversal wrote Pharaoh Decoration's ID, and Tick Data
  named each one as the other. The Action Steps commands were already right
  and are unchanged

---

## v11.7.22.3

### Fix: Frame Meter during hitstop

- With `Log Hitstop Frames` off, a move that connected showed fewer tiles than
  the same move whiffed. The first Tick after hitstop was dropped (Demitri's
  close LP, blocked: 2 red tiles instead of 3), and a move that keeps animating
  through hitstop lost those Ticks too (crouching HK, blocked: 1 red instead
  of 4). A Tick is now skipped only when no attacking character moved. Checked
  on Demitri's 12 standing and crouching normals: Startup / Total / Recovery /
  Advantage match the whiff and Tick Data
- The defender's yellow run can be a few tiles longer than Tick Data's Hitstun:
  the contact Tick, and Ticks where only the attacker moved, take a column too

### New: Show Action Timeline

- `Show Action Timeline` under `Tick Data` on the Trainer tab (on by default).
  Off hides the green Action Timeline row and keeps the Tick Data rows.
  `Timeline Cut (Free Ticks)` now sits under it. See
  [11.3 Action Timeline](PLAYER_MANUAL.en.md#action-timeline)

### Manual

- Frame Meter screenshots in [11.6](PLAYER_MANUAL.en.md#frame-meter), with how
  the numbers on the tiles relate to Startup and Recovery

---

## v11.7.22.2

### New: Long LP > MP for the Sasquatch tutorial

- `scripts/patterns/Sasquatch_Long_LP_MP.json` is now included: a full forward
  dash (no cancel) into LP, then MP 26 Ticks later - a gap set to make jumping
  out difficult. Import it next to `Short LP` and mark both `[x]` to have the
  dummy pick one at random. See
  [Have the dummy choose between two attacks](PLAYER_MANUAL.en.md#tutorial-mixed-patterns)

### Manual

- An overview of what the Frame Meter shows, and that its settings change what
  it records: with `Show Throw Invulnerability` on, those Ticks count as throw
  invulnerability rather than active frames
- Clearer roles for Action Steps (build one sequence) and Action Patterns
  (save several and run them at random), and what to try after the tutorial
- The first step's numeric Wait goes up to 30; the example now uses 30

---

## v11.7.22.1

### New: Frame Meter marks Ticks within the same displayed frame

- Black dots mark a pair of Ticks processed within the same displayed frame.
  At Turbo 3, four Ticks pass in three displayed frames. Those two tiles get
  a black dot each side of the border between them, so the pair reads as joined
  by a small "+". Idle tiles get no dot, and at normal speed there are none. See
  [11.6 Frame Meter](PLAYER_MANUAL.en.md#frame-meter)

### New: Timeline Cut (Free Ticks)

- A row under `Tick Data` on the Trainer tab, shown while Tick Data is on: how
  many Ticks of standing free end an Action Timeline row. 0-60, default 10 -
  the fixed value it used until now. Set it longer than a pause to keep a setup
  in one row. See [11.3 Action Timeline](PLAYER_MANUAL.en.md#action-timeline)

### Changed: rows that belong to another row are indented

- On every tab, a row that belongs to the row above it is indented under it:
  the Frame Meter's four rows, the Scrolling Input rows, everything Guard Action
  Type opens on the Dummy tab, the slots under `Use Random Recording Slot`, and
  so on. `Random Delay` and `Loop Wait` sit one level deeper
- `Show Character Specific` moved up under the HUD row, next to `Show Tech Hit Mash`
- On the Dummy tab, `Reversal/Counter Input Motion`, `Reversal/Counter Button`
  and `Reversal/Counter Button Lever` are now `Input Motion`, `Button` and
  `Button Lever`. Indented under Guard Action Type, the prefix only repeated it,
  and the Lever row ran past the menu's right edge. Saved settings carry over

---

## v11.7.22

### New: Frame Meter

- `Frame Meter`, the last row on the Display tab (off by default), draws both
  players' states along the bottom of the screen, one tile per Tick, with the
  Startup / Total / Recovery / Advantage of each player's last action. See
  [11.6 Frame Meter](PLAYER_MANUAL.en.md#frame-meter) in the manual
- Turning it on opens four rows right under it: `Show Throw Invulnerability`,
  `Show Movement Data`, `Show P1 Inputs` and `Log Hitstop Frames`. All start off
- It comes from tirsod's [VSAV_FrameMeter](https://github.com/tirsod/VSAV_FrameMeter).
  It counts differently from Tick Data. Display settings can also affect the
  measured values, so keep settings the same when comparing results. Its numbers
  have not been checked against the game

### Changed

- `Show Pushbox Distance` on the Display tab is now `Pushbox Distance`, so it
  no longer runs into the menu's second column. The saved setting carries over

---

## v11.7.21.3

### Fix: settings on hidden rows no longer act

Three settings kept working while their rows were hidden, so a value left over
from an earlier session changed what the dummy did:

- `Reversal/Counter Button Lever` (shown for Specified only) also replaced the
  direction in Action Steps and Action Patterns. Left on `Neutral`, it took the
  second tap out of a dash: the tutorial's Short LP walked forward instead of
  dashing
- `Pit of Blame` (shown for Anakaris only) fired for any dummy. Left on Random,
  it put his DPF + kick on Sasquatch about 22 Ticks after each launch
- With Action Steps or Action Patterns selected but nothing to run (an empty
  list, or no pattern ticked), the dummy used the Specified motion and button
  instead. It now does nothing, as the manual says

### Manual

- The tutorial starts by importing the included `Short LP` pattern; building
  it in Action Steps is an optional section. Step 2 has a screenshot of the
  Dummy tab after the import
- Runahead: check `Video > Runahead` for `Disabled` in the menu. The red warning
  is inferred from re-run Ticks and does not appear right after launch
- Shorter README, clearer settings for the fastest response, GC Stats and PB
  guidance separated from reference details, and fixes to the Copy, Button
  Wait and timing-drill explanations

---

## v11.7.21.2

### Button Wait, and a Random Delay on the button

- `Guard Action Delay (Ticks)` is now called `Button Wait`. For Reversal /
  Counter Attack - Specified it is the wait between the motion and the button;
  the motion still comes out at the earliest moment. For Push Block and PB
  Recording it is the wait before the presses start. Saved values carry over
- Its ceiling is 60 Ticks. The menu used to go to 50 while 31-50 actually ran
  as 30
- A new `Random Delay` row, indented under it (game Ticks, 0 to 60; 0 is off).
  Every reversal or counter adds a fresh random 0 up to the setting to the
  Button Wait, so a dash attack or jump attack is pressed at a different point
  each time. It rides on Auto too: `Forward Dash` + `HP`, Auto, `0-5` spreads
  the fastest dash attack over five Ticks
- Too late and the game decides: a special's command is kept 14-19 Ticks, then
  a normal comes out; after a dash or jump is over there is no dash or jump
  attack. The direction stays held while the button waits, so a jump may jump
  again after landing

### Fix: a counter after being hit pressed its button twice when it waited long

- With the button more than about 12 Ticks after the dummy could act, a
  clean-up step sent the motion's last entry, button included, before the
  real press: a dash-cancel LP came out as a dash LP and then a standing LP. It
  now waits for the real press. Earlier versions had the same problem with a
  long Guard Action Delay (read from the code, not tested on those versions)

### Manual

- Random Start Wait and Random Delay are now covered everywhere they apply:
  the Tick table, loops, pattern files, troubleshooting and the recipes that
  assume the fastest timing
- New section 4.4 for Button Lever, Button Wait and Random Delay, with the dash
  attack and jump attack examples
- The tutorial's Dummy tab screenshots are retaken with the Random Start Wait
  row (five images)

---

## v11.7.21.1

### Random Delay: a random extra on top of each step's Wait

- Each Action Steps step has a new `Random Delay` row, indented under `Wait`
  (game Ticks, 0 to 60; 0 is off). Every time the step runs, a fresh random
  number from 0 up to the setting is added to the timing its Wait gives
- It rides on any Wait: a number, After, a measured Auto, Landing, or a
  Chain/Cancel window. On a connection a large value can miss the window and
  the step comes out on its own, like a human missing the link
- Typical use: `0-5` on a fastest input to reproduce human wobble, larger
  values to vary the gaps in a pressure string
- The step list shows it after the Wait, as in `+6t +0-5t`. Step one's value
  is drawn together with `Random Start Wait`. Action Patterns export and import
  carry it; an older version simply ignores it

---

## v11.7.21

### Random Start Wait: a random delay before the dummy acts

- New `Random Start Wait` setting, in game Ticks from 0 to 60. It is on the
  Dummy tab under `Random Guard Action %` and on the Recording tab under
  `Loop Interval (Frames)`; the two rows are the same setting
- Each time the dummy starts an action of its own, it first waits a fresh
  random number of Ticks from 0 up to the setting: every Reversal and Counter
  Attack type, each `Loop Steps` pass (after `Loop Wait`), and every recording
  playback, including each `Looped Playback` pass (after `Loop Interval`)
- `0` is off: the fastest timing, as before. Defense never waits (guard,
  Push Block, guard cancel, throw tech), and neither does the Recording
  Wizard's check playback
- A response that waits starts its input once the dummy can act, so it never
  comes out sooner than its input takes
- When playback waits, the Lua console shows the number drawn

### Fixed: a looped dash could go missing after a blocked attack

- With `Loop Wait = Auto (Landing)`, a dash that was being entered when the
  dummy's own attack was blocked could fail to come out, leaving only the next
  attack where the dummy stood. Seen with Morrigan (dash > MK > LP) and
  Sasquatch (dash cancel > HK, dash cancel > HP)
- The tool now reads the game's own dash input state and finishes or
  re-enters the dash only on a tick the dummy can actually dash on, instead of
  re-entering it in the air during the hit stop

---

## v11.7.20.4

### GC: earlier is better, with two tips for a faster GC

- A GC is better the earlier it comes out, as long as it succeeds. GC Stats
  now reads that way: smaller `GC t` and `Input t` mean a faster GC. The
  in-game description of `Show GC Stats` says so too
- Section 9.1 of the manual has two tips for getting a GC out faster after a
  single block: start the dragon-punch motion as soon as you block, using
  guard persistence (`G-Persist n` / `GP n`) to return to neutral early
  (holding forward during persistence makes you walk and drops your guard),
  and press the button together with the last down-forward, then release it
- The PB and GC "what to try next" tables no longer name a single cause where
  the readout cannot tell one apart

### Clearer guided practice and README

- After importing the bundled `Short LP`, the tutorial says to skip the manual
  build and go straight to the check, and that Step 6 is not needed
- The README's caption under the two screens is shorter and points to the
  manual's "The screen" section

---

## v11.7.20.3

### Reorganized manuals with a map of the screen

- The player manuals now run in four parts: get started, build the opponent,
  practice, and analyze and configure. Building the opponent comes before
  practice, since every drill needs one. Section numbers changed; existing
  links still work
- A new "Start here" section shows the screen while practicing PB and while
  practicing GC, with each display numbered and explained. The README opens
  with the same two screens
- PB and GC each have a "what to try next" table that turns a readout into
  the next adjustment
- Runahead is explained once, with the red warning the tool shows while it is
  enabled (`RUN-AHEAD DETECTED`): if the warning appears, set
  `Video > Runahead` to `Disabled` and restart
- The download link points to the latest release

### Short LP ships as a pattern file

`scripts/patterns/Sasquatch_Short_LP.json` holds the guided practice's
short-dash LP. To try the drill before building it, import the file with
`Import from a File` in Action Patterns while the dummy is Sasquatch. The
tutorial still shows how to build it yourself.

---

## v11.7.20.2

### GC Stats: Input t and the per-step averages now cover the same successes

- `Input t` and the three per-step averages are now calculated from the same
  successful attempts: those whose three directions were all measured. They
  were previously counted under separate conditions, so the two averages could
  have covered different attempts (no such difference was found in the
  recorded logs or on screen)
- Before rounding, the three per-step averages add up to the `Input t`
  average. Each is rounded to two decimals for display, so their sum may
  differ slightly
- A success whose input could not be measured from its start still counts as
  a `Pass` but is left out of these averages. `GC t` is calculated as before

### Manual updates

- Shorter first practice steps, with a clearer path from the results to the
  next improvement: compare both sides and review failed attempts in the trace
- Links to GC Stats from the README and the guided practice
- Section 9.4 explains which successes the averages cover and the rounding

---

## v11.7.20.1

### GC Stats: per-step averages and automatic display placement

- Under the table, one row per side averages each step of the command over
  `Pass` attempts. With the GC Command Trace's arrows, the second and third
  directions and the buttons each show the average number of Ticks since the
  previous input. These values are averages of the input intervals shown in
  the trace, and the three add up to `Input t`
- When `PB Stats`, `Tick Data`, `Air Guard Gaps` and `Recording GUI` are all
  OFF, GC Stats sits at the top left, left of the GC Command Trace. When any of
  them is ON, it stays at the bottom right. The settings decide the position,
  so the box does not move during practice
- The screenshot in Section 9.4 of the manual shows the new display

---

## v11.7.20

### GC Stats

`Trainer > Show GC Stats` tracks your GC success rate, split into the 1P side
and the 2P side. It appears at the bottom right, just above the input bar.

- One attempt is one blocked string. A string counts once the game accepts a
  direction of your GC command during it: `Pass` if a GC came out anywhere in
  it, `Fail` if it ended without one. `Cmd Expired` or `GC Expired` partway
  through does not finalize the result
- The 1P side and the 2P side are where your character stood: the left or the
  right of the screen
- `GC t` is the Ticks from the opening of the GC window to the GC (the same
  number as `SUCCESS Nt` in the input bar); `Input t` is the Ticks from the
  first direction of the command that produced the GC to the GC itself. Both
  are averaged over `Pass` attempts only, and neither is a score where smaller
  is better
- The notation, the colors, the stop at 99999 and starting again from zero
  when toggled OFF then ON all work as in PB Stats
- Only P1 is measured. Switching the side you control, including during a
  Recording Wizard take, does not clear the counts
- A blocked string you walked forward into also counts as an attempt. See
  Section 9.4 of the manual

### Manual updates

- Clearer paths into your first practice session and better section links
- Consistent recording and playback terms, and the exact way to turn
  Runahead off (`Video > Runahead > Disabled`)
- The English documents now use Push Block / PB throughout, with smoother
  wording and American spelling
- A new section on GC Stats (9.4), with a screenshot from the game

---

## v11.7.19

### Reorganized manuals and a guided practice session against Sasquatch

- The English README is the entry point; the Japanese README and both player
  manuals now run from installation to basic controls to practice
- **New guided practice: PB and GC against Sasquatch.** Build a short-dash LP,
  try PB and GC against it, repeat it and save it in Action Patterns, with
  screenshots from the game
- Development documents moved to `docs/development/`, release notes to `docs/`

### The naming and file windows no longer stay hidden behind FBNeo

The Action Patterns naming window and the Export / Import file window could
slip behind FBNeo and stay there. While open, they now come back in front on
their own. Click the window to type.

### For full screen, use Windowed Fullscreen

FBNeo's older full-screen mode cannot show those windows. To play in full
screen, check `Video > Blitter options > Windowed Fullscreen` (toggle full
screen with `Alt+Enter`).

### Other

- The release zip can be built from a plain clone of the repository (the IPS
  patches are included only when present)
- Manual corrections: an Action Steps step with `Attack` and `Neutral` has no
  Hold row, and step one's Wait already defaults to `Auto (Fastest)`

---

## v11.7.18

### Screenshots in the manuals

The Japanese and English player manuals now show seven screens from the game,
each with a note on how to read its numbers.

- The 0% warning (the orange row and the reason on the bottom line)
- The Action Patterns list
- The PB Counter line, the pressed-button list and PB Stats
- GC Command Trace and the `G` / `GC` / `SUCCESS` marks on the input bar
- Tick Data (a dash, then Demon Cradle)
- Air Guard Gaps

The images are in `docs/images` and ship in the release zip.

### Descriptions corrected

- `Random Guard %` / `Random Guard Action %`: the row is orange **when the
  cursor is on another row**. The row under the cursor shows the cursor
  color, and the description now says so
- `Guard Action Type` set to `Reversal - Action Patterns` has its own
  description (it showed a generic line)
- `Reversal Action Patterns`: no longer calls the Action Steps row "below" -
  the two rows are never shown together

---

## v11.7.17

### The three rate rows have matching names, and None reads 0%

These are the three rows on the `Dummy` tab where you set a percentage.

| Before | Now |
|---|---|
| `P2 Random Guard %` | `Random Guard %` |
| `Guard Action Frequency` | `Random Guard Action %` |
| `Tech Throws` | `Random Throw Tech %` |

All three show `None` as `0%`. Only the wording changes; saved settings keep
their meaning. `Guard Action Frequency Check` on the `Analysis` tab is now
`Random Guard Action % Check`.

### A 0% that stops what you picked turns orange

- `Guard` is `Stand Block` / `All Guard` / `Push Block (All …)` and
  `Random Guard %` is 0%
- a `Guard Action Type` is selected and `Random Guard Action %` is 0%

The rate row turns orange. With the cursor on one of the rows involved, the
right side of the bottom line says why (for example `Random Guard % is 0%: the
dummy never blocks.`). The value is not changed for you: 0% can be intentional.

### Random Guard Action % Check read 71% at 100%

One blocked hit was counted as two chances. It is now one. The dummy acts
exactly as often as before. The readout also shows the setting as
`Random Guard Action 100%` instead of its index (`freq=5`).

### Each Wait choice in Action Steps explains itself

With the cursor on a Wait choice (After / Landing / Chain / Cancel and so on),
a one-line description appears below the list.

- **After**: starts the inputs once the dummy can act. Nothing is entered early
- **Landing**: enters the motion during the fall so its last input lands on
  touchdown

The Wait and Hold descriptions no longer run into the legend below them.

### Wrong descriptions corrected

- **Startup console message**: names Lua Hotkey 1-4 instead of Start and
  Alt + 3 / 4
- **Push Block**: "eight presses guarantee it" was wrong. Presses 1-2 never
  push, the 3rd, 4th and 5th push at 25%, 50% and 75%, and **the 6th always
  pushes** (read from the game's probability table while it ran)
- **Tick Data**: startup and active share the tick the box appears
  (4 + 3 + 7 - 1 = 13). Total includes gaps between the hits of a multi-hit move
- The old name `Reversal Sequence` is now `Reversal Action Steps`

### Manuals in the zip

The player manuals in Japanese and English (`docs/PLAYER_MANUAL.ja.md` /
`.en.md`), the Japanese README and the release notes now ship in the release
zip. The README explains the ROM patches in `support/ips` again.

---

## v11.7.16.1

### Show PB Stats, rebuilt

**`Show PB Stats`** on the `Trainer` tab now keeps the values of the `PB Count`
line above it and averages them.

```
Count Total 20
      Pass 14  Fail 6
      Success 70.00%
Avg   PB 4.22  at 5.89-11.50t
      Multi 1.44  Late 0.33
```

- **Total** is the times the other side reached you on the ground **and you
  pressed a button**. A touch without a press is not counted. A blocked string
  is one touch
- **Pass**: you pressed and it pushed. **Fail**: you pressed and it did not, or
  you were hit meanwhile. **Success** is Pass over Total
- **A guard cancel that came out is not counted**
- **Avg** averages the `PB Count` line's own values - the count, the first and
  last tick of `at`, `MultiPush` and `LateMash` - over the touches you pressed
  in and guarded
- Counts go up to 99999. Turning it off in the menu, or picking characters
  again, starts it from 0
- The list of pressed buttons moved up a little and has a background.
  `TECH HIT` is the same green as Pass

### GC Command Trace sits beside PB Stats

No title, a dark background and a little further left, so it can be shown with
PB Stats and push block and guard cancel practiced together.

### GC Frequency Counter moved to the Analysis tab

It checks whether the dummy's `Guard Action Frequency` acts as often as set, so
it is now **`Guard Action Frequency Check`** on the `Analysis` tab (off by
default).

---

## v11.7.16

### New: `Show Air Guard Gaps`

Turn on **`Show Air Guard Gaps`** on the `Trainer` tab and, whenever you block an
air chain, a table shows **how much room there was to interrupt** and **where you
pressed and what came of it**.

```
AirGap                               Gap  Press>Hit
Jump > 6t J.LP(5t)                        PreJump(3t) > Guard 9t
J.LP(5t) > J.LK     --|               2t
J.LK(5t) > J.MP     ---|P             3t  In Blockstun 14t at 14t
J.MP(6t) > J.HP     ----------|PP    10t  In Blockstun 14t at 2,12t
J.HP(8t) > J.HK     ------|           6t
J.HK(9t) > Land     --------------L  14t
Landing Advantage P2 +15t
```

- **The first line is how they came in.** `Jump > 6t J.LP(5t)`: their J.LP
  (startup 5) came out on the sixth tick of their jump. A dash reads the same way,
  `Dash > 12t J.LK(5t)`. On the right, your own jump startup and when you blocked
- **Each row is a move you blocked and the next one.** The bar is the gap you
  could act in: `|` is the next hit, `L` a landing (P1 blue, P2 orange), `Gap`
  its length
- **Press>Hit is your answer.** `LP 2t>6t (5t) WIN`: pressed on tick 2 of the
  gap, hit on tick 6, startup 5. `LATE 4t` is 4 ticks past the last press that
  wins; `NO GAP` means that move cannot make it even at its fastest
- **Presses during blockstun are thrown away.** They show on the row whose hit
  began that stun - `In Blockstun 14t at 9,13t`, pressed on ticks 9 and 13 of a
  14-tick stun - and the buttons also follow that row's `|`. The stun is
  measured every time, so a move with a different hitstop shows its own length
- **The last line is the advantage on landing.** `Landing Advantage P2 +15t`:
  after the last contact, they could act 15 ticks before you. Blocked, hit or
  traded, it is counted the way Tick Data counts Advantage
- Button letters and move names are in their strength's color (light, medium,
  heavy). Every tick count carries its `t`
- A move made by an Action Steps `Auto (N)` shows as `N + 2` on the first line:
  Action Steps counts the tick the input is sent from 0, and the game takes it
  one tick later (a dash LK on `Auto (10)` reads `Dash > 12t`)

### Picking characters again clears the last match's displays

Entering character select clears the input history and the icons down both
edges, `PB Count`, `PB Stats` and `GC Command Trace`, so the next match starts
on a clean screen without restarting.

### `Knockdown Logger` records air guards too

With `Knockdown Logger` on the `Analysis` tab turned on, air guards are also
saved to `reversal_logs/airg_sNN.json`.

---

## v11.7.15.2

### LateMash counts for fourteen ticks

**`LateMash`** in `Show PB Counter` now counts the buttons pressed in the
**fourteen ticks** after the window closes (it was sixty) - **the same
fourteen as the push block window itself**.

- `(+Nt)` goes up to `+14t`. Presses from the fifteenth tick on are not counted
- Inside the window it still stays at 0, however much you press

---

## v11.7.15.1

### Pit of Blame can be Random

With Anakaris as the dummy, the **`Pit of Blame`** row on the `Dummy` tab now
has **`Random`**. Each knockdown picks one of `None` (not used), `Normal` and
`ES`, so **whether it comes at all is part of the guess.**

- The pick is made once per knockdown
- When `Guard Action Frequency` rolls it away, it is not used, as before

---

## v11.7.15

### All Guard blocks at the height each attack needs

`All Guard` used to crouch only when the attacker's "crouching normal" flag was
set. So the dummy **crouched under specials a standing guard takes**, and with
a crouching `Pose` **overheads went straight through**.

It now reads what the game itself checks in its hit routine - whether the
attack can be blocked standing, crouching, or either - and picks the height
from that.

| Attack | Dummy |
|---|---|
| Low | Crouches, whatever the `Pose` |
| Overhead or jump attack | Stands, even from a crouching `Pose` |
| Blockable either way | Keeps the `Pose` |

- `Push Block (All ...)` behaves the same. `Stand Block` is unchanged
- Projectiles and other objects are read the same way
- Fixed: while you played P2 with the dummy on P1, the dummy's crouch pressed
  your own down

### GC Command Trace: a late button turns its empty dots orange

On a button row with a gap of `12t` or more, only the number at the far end
turned orange, and a late button was easy to miss. Like the arrows, **the empty
dots now turn orange**; the pressed ones keep their strength color.

### Action Steps read the way they run

`30 Ticks  Crouch : Neutral (Hold)` read as "crouch for thirty ticks". It meant
"crouch thirty ticks in, and hold until the next step".

- **The list writes a numbered Wait as `+30t`** - the gap from the step before
  (from the trigger on step one). `Auto (...)` conditions are unchanged
- **A Hold shows how long it lasts** when the next step's Wait is a number:
  `Crouch : Neutral (Hold 60t)`
- **The step screen puts `Wait` on top**, so it reads "when, then what". The
  cursor still opens on `Action`

```
1  Auto (Fastest)  Crouch : Neutral (Hold 60t)
2  +60t            Stand : Neutral
```

### A setting that stops the steps from running now says so

With `Guard Action Frequency` at `None`, every guard action is rolled away and
the steps never go out. While it is, the Action Steps and Action Patterns
screens show `Guard Action Frequency is None, so this never runs (Dummy tab).`
in orange along the bottom.

---

## v11.7.14.2

### Guard persistence is counted from 1

**`G-Persist n`** in the GC Command Trace and **`GP n`** in the input viewer's
bar say **which tick** of the guard pose's persistence the block landed on.
Like an attack's active frames, **the tick back is let go is now tick 1**.

**The numbers read one higher than before** (`G-Persist 0` -> `G-Persist 1`,
`GP5` -> `GP6`). A `0` read as "no persistence at all". In the bar, the IDLE
ticks from letting go of back up to and including the marked column now add up
to n.

```
                GP6   GC
  <- 6  IDLE 5  IDLE 1  -> 1
```

The bracketed numbers (`(2t)` and so on) are **gaps** between inputs, so they
are unchanged - `0t` still means the same tick.

---

## v11.7.14.1

### The input viewer's bar marks the tick the block landed

The cancel window opens **one tick after** the block lands. The bar's `GC`
label sits on the tick the window opened, so **that column read as the guard
tick**, and the tick you actually blocked on was buried inside a longer column
such as `IDLE 6`.

The tick the block landed on is now **a column of its own**, marked one to the
left of `GC`:

- **`G`** - a block with back held
- **`GP n`** - a block that landed on tick n of the guard pose's persistence
  (the same number as `G-Persist n` in the GC Command Trace)

```
Before                        v11.7.14.1
                GC                            GP5   GC
  <- 6  IDLE 6  -> 1            <- 6  IDLE 5  IDLE 1  -> 1
```

- **The lever in the marked column is the one the block was judged on** - the
  pose had just processed it when the attack arrived
- A hit leaves the bar as it was
- Shown while **`Show GC Trainer`** on the `Display` tab is on (default on),
  and kept even with `Hide Negative Edge Inputs` on

---

## v11.7.14

### GC Command Trace: which tick of the guard persistence you blocked on

The trick to guard cancels is **guard pose persistence**. Letting go of back
does not drop the guard pose at once - it stays up for a few ticks, and a hit
inside that span is still blocked. That is what covers the part of the motion
that leaves the guard direction.

A block that landed while the pose was persisting now reads **`G-Persist n`**
instead of `Guard`, where **n is how many ticks after the lever left the guard
direction the hit landed**. A block with back still held (cross-ups included)
is a plain `Guard`, as before. **Standing and crouching blocks both count**,
and a hit that lands on the very tick back is let go reads `G-Persist 0`.

```
GC Command Trace
  ->
  G-Persist 2  (2t)   <- 2 ticks after letting go of back, 2 after the ->
  v             4t
  v>            5t
  [HP]          0t
  Success       6t
```

### The guard row sits on the tick the block landed

The cancel window opens **one tick after** the block lands. The guard row used
to sit on the tick the window opened, so a direction entered right after the
block was drawn above the guard at `(0t)` - and **read as blocking with the
lever already forward**.

The guard row now sits on the tick the block landed, and every row is in the
order things happened. When a direction and the guard share a tick, the
direction comes first.

```
Before                   v11.7.14
  ->                       G-Persist 5
  G-Persist 5 (0t)         ->            1t
  v             5t         v             5t
```

**`Success` is still counted from the tick the window opened**, so it is the
same number as the input viewer's `SUCCESS`.

### GC Command Trace: the warning color is now orange

The warning on gaps of `12t` or more is orange instead of amber - amber was
too close to the gold of `Success`. **The arrow on that row is drawn orange
too.**

### GC Command Trace: a blockstring carries the command to the next guard

Guarding a string, the first hit's window can run out halfway through the
motion and the cancel come out off the second guard. The trace started over at
the second guard, so only the last direction and the button were left and it
**looked like a guard cancel off a single direction**. The directions of a
command that is still alive now carry over to the next guard.

### Action Steps: an attack after a jump can be `Auto`

An attack after a jump was `Auto (Not Measured)`, and a low jump attack meant
typing the Ticks in by hand. The "before attack" column of the published jump
table now gives a value for **every character**, shown as a number such as
`Auto (4)`. It is the table value minus one, because the jump input is held
for two ticks. Checked on hardware: Aulbath's and Jedah's forward jumps.

### Action Steps: in the air, `Auto (After)` lets the game decide

- **The tool no longer stops the same button being pressed again.** Anakaris's
  repeated air attacks while floating stopped at the second one. If the game
  takes the press, it comes out
- **A press the game refuses in the air no longer uses up the steps behind
  it.** After a step, the next one waits until the dummy has been busy once -
  the landing counts

### MP on the step list removes a step

Pressing **MP** on a row of the step list opens the remove confirmation, and
the help line says `MP: Remove`. Opening the step and choosing
`Remove This Step` still works.

---

## v11.7.13

### Air chains, and cancels out of jumps and dashes, now come out

Action Steps' **`Auto (Chain)`** and **`Auto (Cancel)` / `Late Cancel`** almost
never connected when the move before them was a jump attack or a dash attack.
Air normals into air normals, air normals into specials and supers, and cancels
out of a dash attack were all affected.

The tool decided "a normal is out" from a value **the game itself never
checks**. During a jump or a dash that value still reads as the jump or the
dash, so the step sat waiting for a window that never opened and went out late
on its deadline. It now uses **only what the game uses** - contact, and the
cancel window.

Rapid-fire cancels are ground normals into ground normals only, so they are
unchanged.

### A step that missed its connection now says why

With **`Show Step Wait Ticks`** on the `Trainer` tab, an `Auto (Chain)`,
`Auto (Cancel)` or `Late Cancel` step that went out on its deadline carries
**the condition it was still waiting on**.

```
Step.3 Wait:29 Act:7 ?hit
```

| Tag | Meaning |
|---|---|
| `?hit` | The step before it did not hit |
| `?spent` | That contact was already used by an earlier step |
| `?chain` | The move started from a chain, so `Late Cancel` is refused |
| `?win9` | The cancel window is still nine ticks away |
| `?inhib` / `?rank` / `?str` | The chain rules refused it |

**A step that did connect carries nothing.** When `Wait` is large, you can tell
"connected late" from "never connected at all".

### Fixed: character select, including problems v11.7.12 introduced

Picking P2's character with the same arcade stick had three problems.

- **Picking Bulleta with light punch did not hand control to P2** - v11.7.12
  meant to fix this, but the fix caused the two below
- **On the second character select, P2 could not be controlled** - introduced
  in v11.7.12
- **Pressing a button before the screen accepted picks let one stick move both
  cursors at once** - introduced in v11.7.12

All three came from treating "a button was pressed" as "a character was
confirmed". **The game's own "confirmed" state was found by measurement, and
the tool now reads that.** Bulleta, light punch, and early presses are all
judged correctly.

---

## v11.7.12

### The guard cancel command, in the order the game took it

**GC Command Trace** lists the inputs the game ACCEPTED on the way to a guard
cancel, with the tick each was taken on. **Not everything you pressed.**

```
GC Command Trace
  Guard
  ->        3t
  v         1t
  v>        1t
  [LP]      7t
  Success  12t
```

- **The arrows and buttons are the input viewer's own artwork**, so the two
  read against each other
- **A number is the gap from the input above it.** As fast as the engine can
  take it reads `1t` on every direction, and a button on the same tick as the
  last direction reads `0t`
- **Twelve or more between two inputs is amber.** The wait the game allows
  between two inputs of a special is rolled, not fixed, and **eleven is still
  inside what comes up often**. Past that the input only landed because the
  roll was generous, and the same input drops on a worse one. It is a
  **warning, not an error** - the cancel did come out. **Numbers measured
  against the guard or the expiry never get it** - the `Guard` row, and the
  first number below it - since neither end of those is an input
- **Only the `Guard` row is bracketed.** A guard is not an input, so its
  number alone is set apart. `Guard (8t)` is eight ticks after your last
  input, or eight ticks after the expiry once the command has died.
  **Numbers measured from the guard are not bracketed** - the guard is where
  the count starts again, so they are part of the chain
- **Success counts from the Guard** - the same number the input viewer
  already draws beside SUCCESS

**Nothing is drawn until a guard happens**, and the motion is followed before
that - so a command started early still shows.

**The two ways it fails are told apart.**

- **`GC Expired`** - the fourteen tick window ran out. **The motion was fine**
- **`Cmd Expired`** - the motion did not stay together: a neutral broke it, or
  a step came too late

**A motion that dies and is input again while the window is still open stays
in the same trace.** The window outlasts one go at the motion, so dropping it
and starting over still cancels off the same guard.

**A guard that lands within sixteen ticks of a dead command is kept in the
same trace.** Sixteen is one past the widest wait a player gets, so the
guard is still inside the reach of the motion that just died - and the inputs
that were too slow, followed by the guard, is exactly the pair worth seeing.
The expiry stays as a row, so the lines above it are still marked as belonging
to the attempt that died.

```
GC Command Trace
  ->
  v            4t
  Cmd Expired 15t     <- how long after your last input it died
  Guard       (2t)    <- how long it was dead before you blocked
  ->           3t     <- how long after the guard you started again
  v            4t
```

**The count restarts at `Cmd Expired`.** Everything below it belongs to a
second go, so counting from the first one's inputs would add three spans
together and read as a single wait.

**A motion restarted after the window has closed starts a new trace**, and
counts from scratch. No number is ever the sum of two attempts' waits.

`Show GC Command Trace` on the `Trainer` tab, off by default.

### Fixed: picking Bulleta with light punch left P2 unreachable

Choosing P2's character with the same stick did not work **when Bulleta was
picked with LP, and only then**. It needed both, which is why it came and went.

Every byte the tool was reading is zero for that pair: the character number is
**zero for Bulleta**, and the number of the button a pick was confirmed with is
**zero for LP**. The character was chosen; the tool could not tell.

### The character specific readouts have a switch of their own

Aulbath's `Direct Scissors` and Anakaris's `Ate Projectile` appeared with
nothing to say what they were. They are now `Show Character Specific` on the
`Display` tab, **off by default** - so they will not appear after this update.
Turn it on if you want them.

---
## v11.7.11

### A tick count on the guard cancel trainer

Next to **SUCCESS** in the input viewer, **how many ticks into the window the
cancel came out**. The window is fourteen ticks, so it reads 1 to 14 - lower
is faster.

```
GC ████ SUCCESS 1t
```

**A cancel done on the guard itself sometimes drew no SUCCESS at all.** The
cancel was coming out; only the label was lost. Fixed.

### Menu tidied up, and a reset per tab

- **`Reset This Tab` at the end of Display, Trainer and Analysis.** It puts
  that tab's rows back to what they ship with. **Right, LP and MP all ask
  first** with an OK / Cancel box, and the box works from the stick alone
- **The `Game` tab moved to the right of `Dummy`**, so everything left of it
  decides what happens and everything right of it decides what is drawn
- **The `Timer` / `Mash` pair by the characters' feet has its own row now**
  (`Display`, under `HUD (Life / Meter)`, **off by default**). The same
  values are already in `Show PB Counter`

### Diagonals no longer steer the menu

**Up and down move the row, left and right change the value on it**, so a
diagonal did **both on the same frame** - the list walked and a setting
changed with it.

While one stick holds one of each axis, **none of the four directions count**.
Return to a cardinal and it works again. **Buttons are unaffected**: confirm
and cancel still answer with the stick on a diagonal.

---

## v11.7.10

### PB Count now warns about the mashing that leaks a normal

The push block window is **fourteen ticks**. **Press after that and a normal
comes out the moment guard stun ends** - right next to the opponent, with you
in its recovery.

**LateMash** warns you when you are pressing that way.

```
PB Count: 6   Guard ----21--21-11-|   at:5-13t   MultiPush: 2   LateMash: 18 (+60t)
```

- **LateMash: 18** — buttons pressed after the window's fourteen ticks
- **(+60t)** — how far past the end the last of them landed
- **It stops at sixty ticks**, so holding the buttons down cannot make it climb

**Inside the window it stays 0 however hard you press.** You cannot see the
grant, so pressing on in there is not a mistake.

The end-of-window marker is now **`|`** rather than `|Expired`.

---

## v11.7.9

### PB Count now shows whether your delayed push block came out as intended

A skilled push block is **one button per tick, spaced across the window,
starting a few ticks after the guard**. Two buttons on one tick buy one count
(the ROM's addq runs once per tick) where a spaced pair would have bought two.

To the right of PB Count, a **tick timeline of the last window** now shows:

```
PB Count: 6   Guard|----1-1-1-1-1-1|Expired   at:9-14t   MultiPush: 0
```

- **Guard** — the block that opens the window
- **Digits** — how many buttons edge on that tick (**1 = clean single · white, 2-6 = simultaneous · red**)
- **-** — no press on that tick
- **Expired** — the window closed (14 ticks elapsed)
- **at:9-14t** — the head and tail of your presses. The ideal is `at:9-14t` with PB Count: 6 (six presses on the last six ticks, none wasted)
- **MultiPush** — how many ticks had 2+ buttons at once (**red = mistake**). Zero is the goal

**With the dummy set to Push Block, P2's MultiPush should always read 0.**
A number there means this tool delivered a simultaneous press - a bug.

### The tab is called Dummy

Everything on the Player tab is the DUMMY's behavior. It is now called
**Dummy**.

---## v11.7.8

### A shortcut to re-place, on the Position row

The Position row applies the arrangement only when the value CHANGES — so
going back to the arrangement already stored meant picking another one and
back. With the cursor on the Position row:

- **LP** — **re-places** the pair at this setting (the value stays). One
  press puts them back when practice has walked them out of it
- **HP** — re-places and **closes the menu**, so you are back in the fight
  at once
- **MP** — resets to Off (unchanged)
- With **Off** selected, neither LP nor HP does anything

### The tab is called Dummy

Everything on the Player tab — Position, Pose, Guard, Guard Action Type,
Action Steps — is the DUMMY's behavior. It is now called **Dummy**.

---

## v11.7.7

### Export a single Action Pattern

One pattern can now be written to a file on its own, without the whole
library. The entry point is **`Export this Pattern`** on the item screen
(the one with Edit).

- The save dialog suggests `vsav_action_pattern(<character>-<pattern>).json`
  (characters a file name cannot carry are dropped automatically)
- The file uses the same schema as a whole-library export, so **Import from
  a File takes it unchanged** (additive, and what arrives starts unticked)
- `Export to a File` on the list — the whole library — is unchanged

### Export/Import remember the last folder

The file window now opens in **the folder last accepted with OK**.

- One memory for the whole tool. A cancel does not move it (the Windows
  standard: looking is not choosing)
- A folder that has since been deleted falls back to the default, inside the
  dialog itself
- The location is saved in `training_settings.json` (never shipped)

### Import refuses a crossed file

An exported file carries whose patterns these are. Opening one on another
character's library used to add them silently - patterns that cannot resolve
the other character's motions and will not run. It is refused outright, one
file at a time:

\ERROR: that file is for Morrigan, not Sasquatch. Nothing was added.
\
A file with no character field - hand-made, from before the field existed -
passes as before.

### A failed import says why

When a file could not be read, the message used to be only "that is not a
pattern file", with no way to tell **an unreadable file from a broken one**.
Fixed:

```
ERROR: could not read the chosen file (<reason>)
```

A wrong pick is visible on the spot.

---

## v11.7.6

### Action Pattern Library — save Action Steps under a name, pick and run them

Dummy Action Steps (step lists) can now be **saved under a name, as many as
you like, and picked when needed**. The library is **per character** and
covers Reversal.

`Trainer` -> `Guard Action Type` gains **`Reversal - Action Patterns`**.

- The `[x]`-ticked patterns are what runs
- **The number of ticks is the play mode.** One tick runs it every time;
  several pick **one of them at random each lap**. Tick Sasquatch's
  "short dash / long dash / low" all three and they loop as a set
- **MP** toggles the tick right in the list. New / Copy / Move / Delete are
  there too
- **New** starts from empty, and **Add from current Steps** imports the whole
  current Action Steps list. Editing uses the existing Action Steps editor
  (opened via Edit)
- **Export to a File / Import from a File** writes and reads one JSON file.
  **Import adds, nothing is replaced** — hand your practice set to someone as
  a file

Only name typing uses a Windows input window (PowerShell); the emulator is
temporarily frozen while it is open.

### Dashes no longer run backwards mid-cross-up

During a crossover the two taps of a dash could come out as opposite screen
directions. The game has two left/right correction rules reading different
bytes (confirmed in the ROM). Sequences made of raw directions only — dashes
and walking — now resolve against the facing byte, and the dash taps wait
until the turn has finished. The same fix closes a hole where the dummy kept
receiving inputs while a menu was open.

### The wake-up dash now comes out of a crossed knockdown

With a dash set as the Guard Action reversal, a knockdown whose dummy was
lying facing away ate the wake-up dash: the configured button came out alone
as a plain normal. The dummy turns around on the free tick, and the dash's
second tap was resolved against the old facing.

The deferred press now follows the turn. Measured: 15 of 15 wake-up dashes
failed before the fix; 35 of 35 come out after it.

### Action Steps After / Landing adjustments

- **After** keeps a ground dash grounded: it does not send the input while
  the dummy is airborne. Air and ground dashes share one input string, so
  this is decided at run time, not from the motion
- **Landing** follows the landing prediction while one exists. The deadline
  used to open before the prediction, dropping the press in mid-air (11 of
  13 measured)
- When a failed dash leaves a standing normal behind, the next step starts on
  that normal's recovery instead of waiting on the landing forever

**Defaults are unchanged.** Leave it alone and it behaves as before.

---

## v11.7.5

### Tick Data and the Action Timeline can measure the dummy

All three rows only ever measured YOUR move. What the dummy did had to be
guessed from the input display, so **there was no way to read what a recorded
Action Steps pattern actually came out as.**

`Trainer` -> `Tick Data` now has **`Tick Data Side`** under it. Set it to **P2**
and

- startup / active / recovery describe the DUMMY's move
- advantage is from the DUMMY's side
- the Action Timeline follows what the DUMMY did

The rows say `P2` while it is on, so **a screenshot tells you which side it is.**

```
P2  Startup 6t  Active 7 / 3t (Anime 7 / 3t)  Recovery 4t
    Total 27t  Advantage +14t  Hitstun 24t  Hitfreeze 24t
P2  1t Walk > 2t Dash > 6t Air > 12t LP > 14t MK >
    19t Hit > 37t LP > 41t Hit > 53t Landing > 62t Crouch
```

**P1 is the default.** Leave it alone and nothing changes.

---

## v11.7.4

### A fresh install came up with the diagnostic overlays on

Unzipping over a deleted `scripts` folder put four lines in the top left

```
P1 Last Got Hit By       : ...
P2 Last Got Hit By       : ...
P1 Push Back Timer Value : ...
P2 Push Back Timer Value : ...
```

and a `Projectile Allocation Value` near the top of the screen.

**Seven rows on the Analysis tab shipped switched on.** Saving your settings once
cleared it, so it only ever happened to people without a settings file - which is
to say, on a first install.

### The `Wait` screen now shows what picking it will do

An attack after a dash comes out **inside** the dash, not after it. The row said
`Auto (11)` - the measured tick - while the menu you picked from still said
`After`, so the two disagreed and neither told you the number.

**It now reads `Fastest (11)`.** Combinations nobody has measured read
`Fastest (Not Measured)`. After an attack it still says `After`, because there the
step really does wait for the dummy to finish and the word is right.

### Dark Gallon can be chosen for P2

The secret characters are picked by holding Start and pressing two punches or two
kicks. The mirror that lets one stick choose P2 did not pass Start, so **Dark
Gallon could not be chosen at all.**

Start is mirrored now. Coin still stays on P1, so stage select is unchanged.

His dash attack timings are in as well - his dash is the same as regular Gallon's,
so he uses Gallon's values.

---

## v11.7.3

### `Loop Wait` now offers `Auto (Landing)`

`Auto (After)` **starts the input once the dummy can act.** Anything that takes more
than one input - a dash, say - is then late by its own run-up (3 ticks for a dash).
Fine for a blocking drill, but not the fastest.

**`Auto (Landing)` predicts the touchdown and buffers the command ahead of it**, so the
final input lands on the tick the dummy first becomes actionable. That is what lets a
landing action loop at full speed.

A step could already be set to `Auto (Landing)`; **the loop restart could not.** That
gap is closed.

### Jedah's infinite reproduces as-is

The infinite on Demitri and Bishamon comes out **without tuning `Loop Wait` to a
number.**

```
Dummy tab
  Guard Action Type      : Reversal - Action Steps
  Guard Action Frequency : 100%
  P2 Random Guard %      : 100%
  Guard                  : Stand Block
  Loop Steps             : yes
  Loop Wait              : Auto (Landing)

Reversal Action Steps : Jedah : 2 steps
  1  Auto (Fastest)  Dash   : Forward
  2  Auto (10)       Attack : Forward + HP
```

### Fixed

**Going from a dash attack into a landing dash, the command did not come out for some
moves.** The slower the move (dash HP or HK, say) the more likely it was; light attacks
were fine. 

Hit stop overlapping the input delivery was the cause, and **it broke in a different
way depending on where the overlap fell.** All three are fixed.

- Ticks spent in hit stop were counted as delivered. The game does not take a press
  made during hit stop, so **an input that never arrived was treated as done** and the
  schedule moved on.
- The wait was also applied to neutral - the gap where the stick is released. There is
  nothing there for the game to take, so **waiting gained nothing and spent the command
  window.**
- A long hit stop cannot be waited out at all: the window closes first. **The command
  is now entered again from the top** instead.

### Known, not fixed

**Gallon and Felicia cannot cancel their landing motion with a dash**, so the setup
above is not the fastest for them either. That is the game's own behavior - **a human
playing them hits the same wall.**

---

## v11.7.2

### The input bar now runs on the game's ticks

It could only add **one column per displayed frame**, which left the one-tick input
that completes a command nowhere to go. Measured over 19 guard cancels, the press or
release that completed it was drawn **3 times**. The other 16 were lost, and 10 of
those had no input column at all. **The cancels themselves came out every time - only
the drawing lost them.**

**The GC Trainer's (`Show GC Trainer`) `SUCCESS` now lands on the tick the cancel came
out on.** Finish with a press and it is the next tick; finish with a release and it is
the same column. The press case is the game's own doing: nothing has started yet on the
tick the button goes down.

**The number under each column is now Ticks**, not displayed frames - about 1.33x the
old figure at turbo 3.

### Button releases have their own switch

**`Show Button Releases`** is new (on by default). `Hide Negative Edge Inputs` used to
double as the on/off for the release markers, so tidying the bar cost you the markers.
**They are independent now: Hide leaves the release columns alone.**

**`Hide Negative Edge Inputs` now ships on.** All it can remove is a column carrying
nothing new.

**Changed defaults only apply to a fresh install.** An existing
`training_settings.json` keeps its saved values.

---

## v11.7.1

### The menu has been reorganized

**The tabs have changed.** The 38 rows that were crammed into `Display` and
`Etc` are now split four ways by what they are for.

```
Recording / Gauge / Player / Display / Trainer / Game / Analysis
```

- **Display** — things you leave on screen
- **Trainer** — things you practice against and read a number off (Tick Data,
  the dash trainers, PB stats)
- **Game** — the game's own settings (Game Speed, BGM, the minimum push block
  press count) and going back to character select
- **Analysis** — raw internal timers and the logger. Not for everyday use

**A row hides while its parent is off.** Turning off `Display Hitboxes` takes
`Display Pushbox X Center` with it; turning off `Show Scrolling Input` takes the
three rows under it. Settings that cannot do anything no longer sit there.

**Going back to character select is a row now**, on the Game tab. Until now it
only existed for people who had found Lua Hotkey 4 in the startup text.

**Descriptions were being drawn off the screen.** Four lines fit in the panel
and the `Tick Data` description had twelve. **Everything from line five was
drawn over the legend and past the bottom edge, unreadable, with nothing to say
it was there.** The panel is taller, six lines fit, and the eleven descriptions
that ran over have been rewritten.

**All eleven rows that had no description now have one.** The Analysis rows name
the memory address they read and the label they draw on screen.

### Fixed

**The push block counter showed a different number from the game's.** It reset
to zero on the second hit of a blocked string; **the game does not** ($170 is
cleared when guard stun ends, nothing else). Seven of eleven granted push blocks
disagreed, the worst reading `1` while the game counted `4`. It follows the
game's own count now, so it is right after a savestate load too.

**`PB Count: 0` was sometimes drawn green** - granted with no presses, which
cannot happen. The count and the color come from one place now.

**`Use Character Specific Slots` wrote nowhere.** Its arguments were in the
wrong order, so it **read "no" while the feature was on**.

**`Show P2 Inputs` only worked while the HUD was on.** Nothing in the menu said
so. It stands on its own now.

**`Push Block Type (PB Recording)` displayed `: nil`**, because its default sat
outside its own list. Pressing Left walked it further outside without limit.

**`P2 Infinite Dark Force` could do nothing.** It shared an `if/elseif` with P1's,
so **while P1's was on, P2's was ignored** - and both shipped on, which is the
state a fresh install started in. Both ship off now and the branch is split.

### Corrected descriptions

**The push block window is 14 Ticks, not 12.** Confirmed in ROM (`0x023966`
writes 14 to `$1AB`). It was wrong in eight places.

**`P1 Min PB Presses` did not describe what it does.** It does not "use the
lowest chance" - it **rewrites the press count to zero**, so the game rolls as
if you had not pressed at all.

**Two dash rows named each other's on-screen heading**, one of which does not
exist.

**`BGM On` was written in a way that invited the wrong reading.**

### Renamed rows

| Was | Now |
|---|---|
| HUD | HUD (Life / Meter) |
| Scroll Input Viewer | Scrolling Input History |
| Show Pushblock Counter | Show PB Counter |
| Show Push Block Timer | Show PB Timer |
| Show Push Block Push Back Timer | Show PB PushBack Timer |
| Show Throw Invulnerability Timer | Show Throw Invuln Timer |
| Show Short Hop Counter | Show Short Hop Counter (Sas) |
| Show Damage Calc | Show Damage Calc (on P2) |
| Minimum PB Inputs | P1 Min PB Presses |
| Testing: PB Delayed Pushback Bug | Show Hit Strength + PB PushBack |
| Testing: Projectile Count Limiter | Show Projectile Allocation |

**No setting key changed.** An existing `training_settings.json` still loads.

### Known and not fixed

**`Show Pursuit Indicator` is incomplete.** Two of its three lines have never
been drawn, and the labels on the other two disagree about which side they
describe. What was found is written up in
`analysis/ISSUE-PURSUIT-INDICATOR-001.md`.

---

## v11.6.2

### Fixed

**Push block sometimes never came out.** With `Guard` set to
`Push Block (All ...)`, the guard itself still follows `P2 Random Guard %` -
but that row was only shown for `Stand Block` and `All Guard`, so on push
block it applied while being invisible. The shipped default is `None`, so
anyone who had never set it got no guard, and therefore no push.

Hiding the row did not remove the dependency, so **the row is now shown
wherever the value is read.** Thinning it out by chance still works, and at the
default the row is visible enough to notice.

**The position shortcut (Lua Hotkey 2) did nothing for the two sideways
arrangements.** Holding the lever left or right and pressing produced nothing;
only down-left and down-right worked.

The "can this player act" test was `$06 == 0x00` and nothing else. **Walking is
`$06 = 0x04`**, and this shortcut is worked by holding a direction while
pressing the key - so holding left or right walks the character, and the act of
asking broke the test. Crouching stays at `0x00`, which is why the diagonals
were fine. Walking is now accepted.

Also: **holding the key down now acts once.** A Lua hotkey is called again for
every frame the key is held, and the arrangement was being rebuilt each time.

---

## v11.6.1

### Fixed

**Choosing Bulleta never handed control over to the P2 side.** The one-stick
flow - P1 character, then stage, then P2 character - stopped at the first step,
**and only for her**.

"Has this player chosen yet" was being read from `$3BD`, and what sits there is
**the character id itself**. Bulleta is `0x00`, so "chose Bulleta" and "chose
nobody" are the same byte. She is the only character numbered zero, which is
why she was the only one it happened to.

A second byte, written the moment a choice is locked in and measured on the
select screen, is now read alongside it. Nothing that worked before changes.

**Stage select had the same bug**, from the same test: with Bulleta taking over
the P2 side, the stage cursor read P1's side instead. Fixed with it.

---

## v11.6

### New

**Action Timeline - the third row of Tick Data.** One whole action laid out on
a clock. It is drawn in green.

```
1t PreJump >  4t Air >  10t MP >  15t Hit >  30t Landing >  45t Free
```

**Each number is the tick that entry happened on, counted from the first tick
of the action.** Lengths are a subtraction: above, the jump touched on its
15th tick, and the MP touched 5 ticks after it came out.

- **Moves are named the way Action Steps names them.** Normals by button
  (LP..HK), specials with the same spelling the step list uses
- **Hit and Guard are told apart**, from the defender's `$140`
- **Walks, crouches, jumps, landings, dashes and throws** are on it too
- **A rapid-fire cancel reads as two entries.** Same LP twice, split where the
  game actually started the move again
- **It fills in as it happens** - an entry appears the moment it is certain,
  not when the action is over
- A row closes after 10 ticks of standing still

### Fixed

Found by checking the Action Timeline against traces of the real thing.

- **Air attack advantage read short.** It is now measured from the landing
- **Walking never appeared.** The walking state is `0x04`, not `0x00`
- **Repeated jumps and repeated dashes** showed as one
- **Dash attacks** had the dash run-up folded into their startup
- **A dash throw** read as if an HP had come out before the throw
- **One-frame throws** (Victor's 360 and 720) showed no move name at all
- **The rows were being built during the character entrance**, before the
  round had started

---

## v11.5.2

### Changes

**Tick Data (was Frame Data) has been rebuilt.** Two rows, counted the way the
frame tables count.

```
Startup 9t  Active 2 / 2 / 2t (Anime 2 / 2 / 2t)  Recovery 38t
Total 62t  Advantage -14t  Hitstun 22t  Hitfreeze 12t
```

- **Startup, active and recovery are read from the attack hitbox.** They used
  to be "until it first connected", so standing further away made the startup
  longer
- **Multi-hit moves are listed per hit**, `2 / 2 / 2`. Two hits with no gap in
  the box are still split
- **Moves whose animation runs during hitfreeze are detected by measurement**
  and shown as `(Anime 4t)`. There is no per-move table behind it
- **Throws and projectiles are measured too**, including moves that carry no
  damage on the body itself
- **Knockdowns and throws are measured to the wake-up**, shown as `Wakeup`
- **Measurement used to stop during a transformation**, which is why Demitri's
  Bat Spin produced nothing

---

## v11.5.0

### New

**REVERSAL - Action Steps.** Build a list of steps and have the dummy perform
normals, specials, jumps and dashes in order.

The join between steps is a choice, not a wait you have to tune by hand.

- `Auto (Chain)` - the first point a chain connects
- `Auto (Cancel)` - the first point a special cancel is allowed
- `Auto (Late Cancel)` - the last point of that cancel
- `Auto (Rapid Fire)` - the rapid-fire cancel (offered after light attacks only)
- `Auto (Landing)` - the moment of landing
- `Auto (After)` - where the previous move ended

A tick count can be given instead, and the list can loop.

**Specials are entered as commands, not poked in as cheats**, so the odd
behavior the cheat route produced does not happen.

**Hold** keeps a direction held across a step, so charge moves can be built.

**Show Step Wait Ticks** (Display) - how many ticks each step actually waited.

```
Step.1 Act:3 / Step.2 Wait:13 Act:1 / Loop Wait:11 / Step.1 Act:3
```

**Show P2 Inputs** (Display) - hide the dummy's input icons at the right edge.

### Changes

**Tech Throws is now a rate**: `None` / `25%` / `50%` / `75%` / `100%`. The
roll is made **once per throw**, not per frame - rolled every frame, a tech
input landing on any single frame would pass, so 50% would behave as 100%. A
saved "on" becomes `100%`.

### Fixed

**Opening the menu now ends any Action Steps run in progress.** The game does
not stop while the menu is up, so the list kept running behind it: directions
stayed held, the dummy moved on its own while you edited, and a loop kept going
with the old list. Closing the menu does not restart it by itself - guard or
hit the dummy once and it goes out with the edited list.

---

## v11.4.2

### Changes

**The wait between loop passes is now two settings, Before and After.**

The parent row reads `Loop Interval (Frames) : (Before/After)`. Right or LP
opens a child menu you can work **entirely with the stick** - Left lowers,
Right raises, Up and Down change row, and `Back` at the bottom returns. MP
still resets to zero.

- **After** is counted once the previous pass has ended and the dummy can act
  again. That is where the old Loop Interval sat, so **a saved value carries
  over to After on its own.**
- **Before** is counted after the distance is restored, just before the next
  pass goes out.

With only one wait there was no way to tell "pause before putting them back"
from "pause after putting them back". Now you can have a beat after
`Reset Distance Each Loop` warps the two into place.

**Looped playback holds for 30 frames after you close the menu.**

Otherwise the next pass arrives the instant you leave the menu, with no time to
get ready. Nothing from the recording is delivered during the hold, and
playback resumes from the same recorded frame rather than racing to catch up.
Single playbacks are unaffected.

**`Play again` cannot be taken until the dummy has finished moving.**

A recording ends when the inputs stop, but the character is still committed to
whatever the last one started. Replaying from there **restarts against a dummy
that cannot act**, and reproduces nothing. The row is grayed out and reads
`(still moving)` until it can be taken.

**It is the only choice that waits.** `Save to this slot` and `Record again`
answer immediately whatever the dummy is doing, so nothing holds up the next
take.

A button held during the playback no longer answers the prompt either.

**Only `Lua Hotkey 1` (cancel) works while the recording wizard is up.**

`Lua 3` (loop toggle) and `Lua 4` (return to character select) reach past the
wizard and break a recording or playback in progress. Cancel is left alone.

**`Play Recording` responds once per press, not while Right is held.**

Right auto-repeats, so holding it started and stopped playback over and over.

**Changing the character position now brings the view with it.**

The camera used to chase on its own, so the move finished with the characters
in place and the screen still catching up. The move itself is a little quicker
too.

### Fixes

**The recording wizard's check playback and `Reset Distance Each Loop` now put
the framing back where it was recorded, as well as the positions.**

The two characters went back but **the scrolling did not**, and a character
placed outside the old view could be dragged back into it. It showed up worst
on recordings that moved a long way with the sides swapped, such as Gallon's
kick throw.

**Settings saved by v11.3.x now carry over properly.**

The migration was skipped, which could **leave the chosen reversal one entry
off** and lose the saved loop interval.

**Reversals and counter-action specials now come out after a multi-hit guard.**

Blocking the second hit of a chain-canceled light attack left the input
un-queued, and nothing came out.

**Turning `Knockdown Logger` off now stops the diagnostic recording
completely.**

Part of it kept running with the setting off, writing files into
`reversal_logs` and slowing the game down.

---

## v11.4.1

The Recording Wizard from v11.4, with everything that turned up once it was actually used.

### Changed

- Renamed to **Super Jump**. v11.4 called it High Jump. The order and the indices are unchanged, so your settings are unaffected.
- **Saving returns you to the wizard's slot list.** The result stays up for a second first, and then you can record the next slot straight away. The characters go back to the distance the take started from as the list comes back.
- **`Back to menu` added to the slot list.** Canceling with `Lua Hotkey 1` now reopens the menu too.
- **The stick alone drives it.** Slot selection and the save prompt are both lists: up and down to move, LP or Right to take it. The save prompt reads Save / Record again / Play again down the screen. The buttons still work as direct shortcuts.
- **Right also enters Play Recording and Recording Wizard.** Right is how you go into things elsewhere in the menu, so it does here as well.
- **Reset Distance Each Loop** added. Puts both characters back to the distance the recording was made from at the start of every loop. Without it the two drift apart over the passes and the setup you were practicing stops happening. Works on recordings made from v11.4.1 on — the distance is stored in the recording itself.
- The wizard's headings are heavier, and the slot list has more room and lines up properly.

### Fixed

- **The script halting on a savestate load.** With `Use Savestate Upon Recording` on, a looped playback or the playback hotkey could take it down.
- Savestates are now **only valid inside the match they were taken in**. Reselect the characters and the state is not loaded. A savestate restores the whole machine, so loading one from a different pairing swapped the entire match back.
- **Coin no longer swaps control while a playback is running.** The playback is already driving the dummy, and both writing to it means neither comes out cleanly.
- **`Lua Hotkey 1` and `2` are ignored until the round is under way.** Moving the characters during the entrance left the arrangement shredded, and opening the menu over it left both of them frozen partway through.
- The wizard always hands control back to P1 when it finishes. Recording two takes in a row could leave it on the dummy.

---

## v11.4

Everything below is the change from v11.3.1.

### New

**Recording Wizard**

Guided dummy recording. Start it from `Recording Wizard` on the Recording tab.

Pick a slot and control switches to the dummy; recording begins the moment you move. It stops on its own after two seconds of standing still, then plays the take back once so you can look at it. From there you can save it, record it again, or watch it again.

Both characters return to where they stood when the take began before each playback, so you check it at the distance it was recorded from. `Lua Hotkey 1` leaves at any point, and nothing is saved when it does.

**Jumps added**

Forward, neutral and back versions of the jump are now dummy actions, listed after Back Dash Cancel in `Reversal/Counter Input Motion`. Down, then up — with the direction on the up.

**Play Recording**

Plays the current slot straight from the top of the Recording tab. Same as the playback hotkey; press it again to stop.

**Character select on one stick**

P1 character, then stage, then P2 character, all without reaching for the keyboard.

**Loop Interval (Frames) (Before/After)**

Puts a gap between loops. The wait starts once the dummy can act again, so the gap is the same length whatever the recovery was.

### Improved

- Slots show when they were recorded, in the menu and in the wizard, on a 24-hour clock.
- Playback is mirrored automatically when P1 and P2 have swapped sides. Which side the take was recorded from is stored with it and compared on playback.
- Looped playback waits for the dummy to be able to act before starting the next pass. The first input of a pass no longer lands during the previous one's recovery, where it would simply not come out.
- A recording now ends two seconds after the move finishes, rather than two seconds after the stick goes neutral. Long moves are no longer cut off partway through.
- The menu palette is easier to read.
- Wake-up reversals have ordinary invulnerability. Command throws get self-direction. The menu no longer stutters as you move through it.

### Fixed

- **Guard cancel back dash failing.** This was listed as a known issue in v11.3.1. It is now reliable against light, medium and heavy.
- **The wizard's recording stopping partway through.** With `Use Savestate Upon Recording` on, the savestate loaded at the end of a loop was cutting off a recording in progress.
- Playback continuing after returning to character select.
- `Lua Hotkey 1` and `2` are ignored until the match is running.

### Notes

- Your settings file migrates itself on first launch. Saved settings keep their meaning.
- The Display and Etc tabs have new defaults. These apply to a fresh install only and leave an existing settings file alone.

---

## Known limitations

- The Dash Interval / Dash Time / Dash Attack Cancel / Attack Dash Gap / Jump In trainers still count displayed frames.
- Jump In Trainer has a bug: landing without hitting anything can still record a gap.
- The Recording Wizard does not capture a savestate. The check playback restores position and facing, but not health or meter.
- Runahead is not supported. Select `Video > Runahead > Disabled` in FBNeo itself. Leaving it enabled makes the earliest actions unreliable, so the script detects it and displays a warning.
