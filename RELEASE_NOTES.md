# VSAV Training Mode — Release Notes

日本語: [RELEASE_NOTES.ja.md](RELEASE_NOTES.ja.md)

Newest first. Older releases are kept below.

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
is a plain `Guard`, as before.

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

Everything on the Player tab is the DUMMY's behaviour. It is now called
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
Action Steps — is the DUMMY's behaviour. It is now called **Dummy**.

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
above is not the fastest for them either. That is the game's own behaviour - **a human
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

### The menu has been reorganised

**The tabs have changed.** The 38 rows that were crammed into `Display` and
`Etc` are now split four ways by what they are for.

```
Recording / Gauge / Player / Display / Trainer / Game / Analysis
```

- **Display** — things you leave on screen
- **Trainer** — things you practise against and read a number off (Tick Data,
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
cannot happen. The count and the colour come from one place now.

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
behaviour the cheat route produced does not happen.

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
that cannot act**, and reproduces nothing. The row is greyed out and reads
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

Blocking the second hit of a chain-cancelled light attack left the input
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
- **`Back to menu` added to the slot list.** Cancelling with `Lua Hotkey 1` now reopens the menu too.
- **The stick alone drives it.** Slot selection and the save prompt are both lists: up and down to move, LP or Right to take it. The save prompt reads Save / Record again / Play again down the screen. The buttons still work as direct shortcuts.
- **Right also enters Play Recording and Recording Wizard.** Right is how you go into things elsewhere in the menu, so it does here as well.
- **Reset Distance Each Loop** added. Puts both characters back to the distance the recording was made from at the start of every loop. Without it the two drift apart over the passes and the setup you were practising stops happening. Works on recordings made from v11.4.1 on — the distance is stored in the recording itself.
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
- Run-ahead is not supported. It stops the fastest actions from being reliable, so it is detected and warned about on screen.
