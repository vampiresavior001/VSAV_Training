# VSAV_Training - The Warlord's Secret

**A Vampire Savior training mode for Fightcade 2.**

See what the Warlord sees, and practice what the Warlord practices.

English | [日本語](README.ja.md)

**Make expert-level execution your training partner.** This Vampire Savior training mode for Fightcade 2 / FBNeo makes the dummy reproduce your opponent's actions precisely, then shows your own inputs and timing on screen so you can see what to improve.

This fork extends [VSAV_Training's fc2 branch](https://github.com/NBeing/VSAV_Training/tree/fc2). This README covers **v11.7.32.1**.

**[Download the latest release](https://github.com/vampiresavior001/VSAV_Training/releases/latest)** · [Installation](#windows-installation) · [First drill](#first-pb-drill) · [English manual](docs/PLAYER_MANUAL.en.md) · [Discord](https://discord.gg/5fwSewN33p)

## What this training mode does

- **Reproduce the earliest possible actions, even at Turbo 3.** The dummy's inputs are controlled on internal frames ([Ticks](#why-ticks)). Make it perform reversals on wake-up, after blocking and after landing, attacks out of the earliest possible dash, and light-attack or throw challenges exactly when you want them.
- **See whether your PB fit six presses inside the window.** The display shows where and how many times you pressed within the 14-Tick window, flags simultaneous presses and presses after the window, and tracks your success rate ([PB practice](docs/PLAYER_MANUAL.en.md#08-pb)).
- **See which GC input broke off, and where.** The tool follows the directions and buttons the game accepted and the intervals between them, and shows where an attempt failed. It also tracks your success rate on each side ([GC practice](docs/PLAYER_MANUAL.en.md#09-gc)).

Randomness affects PB activation and GC input windows, so one successful attempt does not mean your inputs are consistent. This tool shows what to improve even when you succeed.

![Pushblocking Sasquatch's short-dash LP twice. The second fits six presses inside the window and PB activates. PB Count and PB Stats update](docs/images/pb_demo.gif)

Pushblocking Sasquatch's short-dash LP twice. The second fits six presses inside the window and PB activates. Where you pressed, how many times and your success rate appear on screen at once.

**Start practicing PB and GC with the included Sasquatch pattern—no need to build a sequence first.** After [installation](#windows-installation), go to the [first drill](#first-pb-drill).

## Build your training opponent

The dummy performs the action you set when something triggers it, such as blocking, being hit or waking up ([how the dummy works](docs/PLAYER_MANUAL.en.md#dummy-model)). Expand your options in this order as you need them:

1. **Start by recording with Coin.** Press `P1 Coin`, control the dummy, then press it again. The dummy plays back what you did right away ([Quick Recording](docs/PLAYER_MANUAL.en.md#quick-recording)).
2. **Use Action Steps when you need precision.** Define actions and timing in Ticks to reproduce sequences such as the earliest possible dash into an attack, or crouching medium kick canceled into Tenraiha, the same way every time ([Action Steps](docs/PLAYER_MANUAL.en.md#06-steps)). Recording and playback operate in displayed frames, so build actions that need Tick-level precision here.
3. **Use Action Patterns to mix several attacks.** Save sequences by name and have the dummy pick one at random from those you select ([Action Patterns](docs/PLAYER_MANUAL.en.md#07-patterns)).

To have the dummy perform a single move, [Specified](docs/PLAYER_MANUAL.en.md#dummy-guard-action) sets it by command and button.

## Test your offense and measure moves

| Goal | How to use the tool |
|---|---|
| **Check wake-up pressure** | [Meaty Timing](docs/PLAYER_MANUAL.en.md#meaty-timing) shows how many Ticks after the opponent's reversal Tick your attack connected, and on which of its active Ticks |
| **See move data in numbers and colored bars** | [Tick Data](docs/PLAYER_MANUAL.en.md#tick-data) measures startup, active time, recovery and advantage in internal frames; [Frame Meter](docs/PLAYER_MANUAL.en.md#frame-meter) lays out both players' states, one tile per Tick |
| **Check whether a combo connects** | With `Dummy > Guard` set to [After Hit Guard](docs/PLAYER_MANUAL.en.md#dummy-guard-mode), the dummy blocks from the second hit on, so any gap in the combo gets blocked |
| **Check chain and link timing** | [Chain Trainer](docs/PLAYER_MANUAL.en.md#chain-trainer) compares when you pressed with the input window |
| **Retry the same situation** | [Save and restore a state](docs/PLAYER_MANUAL.en.md#save-state) with `Volume Up` (an FBNeo input entry) or the menu. Opening the menu pauses the game, so you can save the paused scene too |

![After Demitri's heavy Demon Cradle, a jumping LP from a forward jump meets Morrigan's in-place wake-up. Meaty Timing reads Wake-up Reversal +0t Active 2t](docs/images/meaty_safe_jump.png)

Example: Demitri's jumping LP meets Morrigan's wake-up, and he lands in time to block a reversal special ([setup and verification steps](docs/PLAYER_MANUAL.en.md#safe-jump-example)).

You can also practice [interrupts after air guarding](docs/PLAYER_MANUAL.en.md#air-guard-gaps), [sequence supers](docs/PLAYER_MANUAL.en.md#command-trainer), [mashing out of grabs](docs/PLAYER_MANUAL.en.md#grab-mashing) and [option selects on a cross-up](docs/PLAYER_MANUAL.en.md#side-switch-os). To find a feature by goal, see [Choose what to practice](docs/PLAYER_MANUAL.en.md#01-purpose) in the manual.

## Windows installation

The target game is **Vampire Savior - the lord of vampire (970519 Japan / `vsavj`)**.

**ROMs are not included. Supply your own files and first make sure the game runs in FBNeo.**

**Set FBNeo's `Video > Runahead` to `Disabled`.** With Runahead enabled, the dummy cannot reproduce reversal timing correctly. If you also play matches through Fightcade, copy the entire FBNeo folder for training so you never have to switch the setting. Launch matches through Fightcade and training through the copied batch file.

1. Close Fightcade and FBNeo.
2. Copy Fightcade's entire `emulator/fbneo` folder to another location, for example `C:/VSAV_Training/fbneo`.
3. Download and extract the [latest release zip](https://github.com/vampiresavior001/VSAV_Training/releases/latest). Put `run_vsav_training.bat` and the entire `scripts` folder in the **copied fbneo folder**, with the batch file next to `fcadefbneo.exe`.
4. Launch the copied batch file and select **`Video > Runahead > Disabled`** in FBNeo itself. Copying the folder also copies settings; it does not disable Runahead by itself.
5. Fully close FBNeo and relaunch through the same batch file. Confirm that `Disabled` is selected under `Video > Runahead`. If `RUN-AHEAD DETECTED` appears during a match, recheck the setting and which FBNeo installation you launched.
6. Use `Input > Map Game Inputs` to configure game controls and the training functions. Configure P2 game inputs too.

**Always assign `Lua Hotkey 1` (open/close the menu) and `P1 Coin` (start/finish a recording): neither has a menu equivalent.** The other shortcuts and their menu alternatives are listed in [manual 1.2](docs/PLAYER_MANUAL.en.md#02-install).

Open the menu with `Lua Hotkey 1`. With a tab name selected, use Left/Right to switch tabs, then Up/Down to select an item. LP means light punch. `>` means “tab > item.”

To play in full screen, check `Video > Blitter options > Windowed Fullscreen` first. The older full-screen mode cannot show the windows used to name, export and import patterns.

Use a short path without Japanese characters; spaces are fine. Before updating an existing installation, make a [backup](#updates-and-backups).

<a id="first-ag-drill"></a>
<a id="first-pb-drill"></a>

## First drill: Practice PB and GC against Sasquatch

Make Sasquatch perform short-dash LP, then practice PB (Push Block) and GC (Guard Cancel) against it. The included pattern lets you start practicing before building your own sequence.

Start by trying either PB or GC; looping and building your own actions can wait until you are comfortable. The steps below outline the drill. Follow the [illustrated tutorial](docs/PLAYER_MANUAL.en.md#sasquatch-pb-tutorial) for the settings and controls.

1. **Import it.** Choose Sasquatch as the dummy and set `Dummy > Guard Action Type = Reversal - Action Patterns`. Open `Reversal Action Patterns` and use `Import from a File` to load `scripts/patterns/Sasquatch_Short_LP.json` from the release. Select only `Short LP` for use.
2. **Practice PB.** Make the dummy block your attack to trigger short-dash LP, then use PB against it. Use PB Counter and PB Stats to check, for example, whether you delayed your first press and still fit six valid presses within the window.
3. **Try GC too.** Block the same LP and enter your character's GC command. Check the success indicator, accepted directions and buttons, and input intervals. Use [GC Stats](docs/PLAYER_MANUAL.en.md#gc-stats) to compare your success rate on the left and right sides.

   ![Demitri guard-cancels Sasquatch's short-dash LP. The trace reads → 4t, ↓ 4t, ↘ 4t, button 0t, Success 11t](docs/images/gc_demo.gif)

   A successful GC with Demitri. The trace shows the directions and button the game accepted, the intervals between them and `Success 11t`.

4. **Repeat it.** Set `Loop Steps = yes` and `Loop Wait = Auto (Landing)` to repeat short-dash LP as soon as the dummy lands.
5. **Expand your practice.** The imported pattern is ready to use next time. When comfortable, build other attacks in Action Steps and save them in Action Patterns to practice against randomly selected sequences.

![Practicing PB (left) and GC (right), with each display numbered](docs/images/screen_map.png)

Left: check whether you still fit six presses when delaying PB. Right: see which GC directions and button presses the game accepted. See [how to read the screen](docs/PLAYER_MANUAL.en.md#screen-map) for each display.

See [PB practice](docs/PLAYER_MANUAL.en.md#08-pb) and [GC practice](docs/PLAYER_MANUAL.en.md#09-gc) for how to read the input displays and decide what to adjust.

## Why Ticks

A Tick is an internal game frame. At Turbo 3, four Ticks pass in three displayed frames, so counting in displayed frames can throw off both input timing and move measurements. This fork controls the dummy's inputs on that internal clock.

| Game speed | Displayed frames and internal frames |
|---|---|
| Normal | One displayed frame = one Tick |
| Turbo 3 | Three displayed frames = four Ticks |

Action Steps and measurements such as Tick Data use Ticks; recording and playback use displayed frames. Some older readouts, such as the dash trainers, still count displayed frames. See the list in [manual 11.1](docs/PLAYER_MANUAL.en.md#ticks-and-frames) for which unit each display uses.

## Manual

The **[English player manual](docs/PLAYER_MANUAL.en.md)** covers controls, settings and how to interpret the readouts. If you are new, start with the [Section 3 tutorial](docs/PLAYER_MANUAL.en.md#sasquatch-pb-tutorial).

- **Set up your training opponent:** [Dummy defense, recovery and counter actions](docs/PLAYER_MANUAL.en.md#04-dummy), [Recording and looping](docs/PLAYER_MANUAL.en.md#05-recording), [Action Steps](docs/PLAYER_MANUAL.en.md#06-steps), [Action Patterns](docs/PLAYER_MANUAL.en.md#07-patterns), [Auto Mash and Mash Meter](docs/PLAYER_MANUAL.en.md#grab-mashing)
- **Practice:** [PB practice](docs/PLAYER_MANUAL.en.md#08-pb), [GC practice](docs/PLAYER_MANUAL.en.md#09-gc), [Practice recipes](docs/PLAYER_MANUAL.en.md#11-drills), [Save and restore states](docs/PLAYER_MANUAL.en.md#save-state)
- **Analyze:** [Tick Data](docs/PLAYER_MANUAL.en.md#tick-data), [Meaty Timing](docs/PLAYER_MANUAL.en.md#meaty-timing), [Frame Meter](docs/PLAYER_MANUAL.en.md#frame-meter), [Air Guard Gaps](docs/PLAYER_MANUAL.en.md#air-guard-gaps), [Chain Trainer](docs/PLAYER_MANUAL.en.md#chain-trainer), [Troubleshooting](docs/PLAYER_MANUAL.en.md#14-troubleshooting)

### Scope

These installation instructions target Windows. Linux launch scripts are included, but not every feature has been verified on Linux or macOS. Action Patterns naming and file dialogs are implemented for Windows.

## Updates and backups

Save your edits before closing FBNeo, then back up:

| Content | Location |
|---|---|
| Settings, Action Steps and Action Patterns | `training_data/training_settings.json` |
| Recordings | Entire `scripts/macro` folder |

The settings file is in the `training_data` folder, outside `scripts`. When you first start a version that uses `training_data`, an existing `scripts/training_settings.json` is copied there automatically. The old file stays where it was as a copy and is no longer updated. Recordings are still in `scripts/macro`, so back up both.

Update the separate training installation. The downloaded files may include recordings, so take care not to overwrite your own. Fully restart FBNeo afterward and confirm that `Disabled` is selected under `Video > Runahead`.

## Release history and reports

- [Release notes](docs/RELEASE_NOTES.md) (starting with a summary of recent highlights)
- [日本語リリースノート](docs/RELEASE_NOTES.ja.md)
- [This fork's Issues](https://github.com/vampiresavior001/VSAV_Training/issues)
- [Discord](https://discord.gg/5fwSewN33p): questions, bug reports and feature requests are welcome here too

When reporting a problem, include the version, P1/P2 characters, which character is on each side, screenshots of your settings and steps to reproduce the problem. Confirm that `Disabled` is selected under `Video > Runahead`, and mention any red Runahead warning in your report.

## Original project and credits

This project is based on [VSAV_Training's fc2 branch](https://github.com/NBeing/VSAV_Training/tree/fc2). The original already includes recording, reversal settings, a PB counter and a GC-window display. This fork builds on them with more precise action reproduction and more detailed feedback; see the [feature comparison](docs/PLAYER_MANUAL.en.md#fork-comparison). Thanks to the creators and contributors of the original training mode and its scripts, and to the VSAV community.

The Frame Meter comes from tirsod's [VSAV_FrameMeter](https://github.com/tirsod/VSAV_FrameMeter).

Reverse engineering of the game (disassembling the ROM) was guided by VMP_MBD's [CPS2 research notes](https://publish.obsidian.md/mbd/Projects/CPS2/CPS2+Projects), which include notes on Vampire Savior. The earliest-possible reversals and this fork's other improvements grew out of analysis that started from these notes. Many thanks. Tick Data counts frames the same way as the [Darkstalkers Frame Data](http://darkstalkers.web.fc2.com/savior/savior.html) tables.

<details>
<summary>Credits from the original README</summary>

Shoutouts to: Dammit and Jed for their wizardry, Grouflon (Stole their 3s training mode menu, and settings workflow!) and the VSAV Community.

BIGGEST SHOUTOUT to KyleW! This definitely would not have happened or continued without you.

`N-Bee`

</details>
