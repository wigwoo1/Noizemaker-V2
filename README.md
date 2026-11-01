# Noizemaker V2 — Visual Chart Editor

An in-development Windows visual chart editor for Space Channel 5 Part 2,
based on [Hyonk-Tea's Noizemaker](https://github.com/Hyonk-Tea/Noizemaker).
The original editor and patcher remain the foundation of this project.

This repository contains the current visual preview source: English report
loading, drag-and-drop command editing, English voice previews, partial music
mapping, project saving, and report exports. Report 1 can play its full
script-derived music with a moving chart playhead and every response call in the
recorded route. Report 1's flagged 0x21/0x41 calls use the normal English Chu;
its held Chu uses the original longer sample. These sample selections were
checked against the game's response dispatch and a stock CPU recording.
The 58 recorded responses, their 201 command onsets, and 24 music cues have now
been checked against the continuous stock recording, using a 60 ms comparison
tolerance. The app shows checked timing only for matching chart, music, and voice
assets. The ending, loading pauses, complete extended-call behavior, other
routes, and in-game export verification remain unfinished. Game assets and
audio are read from your own game installation at runtime.

For a selected Report 1 phrase, **Play** now includes the English enemy question,
then Ulala's response, over the matching music cue. This covers the 58 phrases
in the recorded CPU route when their original timing and source files match.
The enemy bank choices have representative stock-recording support; exact
audible alignment and all held takes have not been checked. A selected From/To
range still plays only the response. Other reports still use response-only
phrase previews while their enemy voice banks are mapped.

Selected Report 2 CPU-route phrases now play the enemy question, Ulala response,
and their mapped music cue across all three English sections. The enemy bank
assignments are supported by representative stock-recording comparisons. Three
groups have weak matches and are labeled provisional. Twenty-eight occurrences
of unmapped raw chart bytes remain silent in both halves; the app labels these
phrases when played. Other Report 2 branches and exact audible sync remain
unverified. Report 4's first two sections now include enemy questions where
the recorded CPU route identifies robot, cheerleader, Shadow, Fuse, or Michael
banks. Play follows each enemy call with Ulala's response and the mapped music.
Unmapped calls remain silent in both halves, and the app labels the bank choice
and audible alignment provisional. Report 4's later sections and Reports 3,
5, and 6 still use response-only phrase previews while their enemy voices are
being mapped.

Report 4 now has a recorded CPU phrase order across its four sections.
**Play R4 music** renders its stereo music cues. **R4 original calls** adds the
English samples selected on the recorded CPU path: 605 original notes have a
named native sample; 26 unnamed native members or edited commands are muted.
Both choices support play, pause, seek, loop, and stop. Precise audible
alignment and unvisited bank branches remain unverified. Individual held-call
previews are also available. Report 5 has a source-checked 54-phrase CPU order
across its two English sections, with readable set and phrase labels. **Play R5
music** renders its 17 stereo music cues without command calls. **R5 original
calls** adds the 327 named English samples selected at the original note
positions in the recorded CPU run. Changed command codes are muted in this
whole-level mode until their new native bank selections are mapped. Fifteen
music cues have independent recorded stereo-window support; two have script
and route support but ambiguous audio windows. The two branch cues were
distinguished by three recorded stereo windows each. A separate waveform
comparison found candidates for 145 of 327 original calls; precise audible
alignment remains unverified. Report 6's stock CPU run reached 67 phrases
across two English sections; the app offers that source-checked order, section
labels, search, and Prev/Next editing. A later final chart was queued in the
game but never reached in the captured run, so it remains in file-order browsing
only. Individual Report 6 phrase previews now use the recorded English response
bank samples for 268 original calls, including the long Down in `pd007y`.
Three calls inside a game-memory recording gap and edited commands use
provisional short previews. Report 6 whole-level music and voice playback,
game dialogue and loading pauses remain unfinished.

## Running the app

Use LOVE 11.5 to run this preview from source. A source download from GitHub
does not include the LOVE runtime. Select your own PC game installation in
Settings, then choose **Reports** to browse the English charts in `afs_english`.

From the repository root, with LOVE available on your command path:

```powershell
love .
```

On first launch, Noizemaker looks for `config.ini`. If `game_root` is missing or invalid, it will prompt you for your Space Channel 5 Part 2 install folder.

On supported platforms, Noizemaker also registers the `noize:` URL scheme so GameBanana 1-click install links can reopen the app.

## Editing a sequence

The normal flow is:

1. Open a DGSH `.bin` file.
2. Pick an entry from the left panel.
3. Edit the working copy in the timeline or inspector.
4. Save your work with **Project > Save**.
5. Close the game, then click **Apply File** for the current file or **Apply All**
   for all changed sequences in the current report. Review the affected paths
   and click **Apply to game**, then restart the report or mode in the game.

Apply selects the English report files automatically. Ulala's Dance instead
uses the shared **R01_SH.BIN directly in the main game folder**. You do not need
to copy exported files yourself. Undoing an installed edit and applying again
also updates the game; files that already match are skipped.

The app saves verified backups before replacing files. **Project > Restore game**
restores the current report's files to their baseline before the first Apply,
while keeping your editor drafts. If an Apply is interrupted, that same action
offers recovery. Backups live in the app's Windows save folder and are kept
separately for each game installation. External file changes are checked before
applying. A baseline can already contain manually installed mods; Restore does
not download or recreate stock files.

**Patch** still writes a separate patched copy. Ordinary editing, saving and
exporting do not change the installed game. Installation and recovery have been
tested on disposable game copies; gameplay confirmation remains separate.

In the visual preview, use **Project** at the top right or `Ctrl+S` to save all
open English chart edits to a `.sc5project` file. `Ctrl+Shift+S` saves as a new
project; `Ctrl+O` reopens one. Project panels accept a full file path without
launching a Windows helper dialog. Projects contain edit data and source
checksums; they require matching game files when reopened. Closing with
unsaved edits offers Save first, Discard & exit, or Cancel. Undo history starts
fresh when a project is reopened.

Choose **Project > Export report** to export all changed English chart files
for one report together. In the editor this uses the active chart's report;
in the report browser it uses the selected report. Choose a new folder outside
the game installation. The export keeps the `afs_english` layout and required
filenames, and includes a manifest listing affected phrases and source/output
checksums. Existing export folders are protected. Exports do not install changes
or save your project; keep using Project Save for editable work. In-game
verification of exported charts remains pending.

Matching English Report 1 source files open in **Order: CPU run**, a list of 58
input phrases corroborated by captured engine queues and question stacks.
Switch to **Order: files** or show Variants for other entries and branches.
The sidebar uses matching encounter/set/phrase locations and keeps original IDs
underneath. Choose **Play Report 1** in Reports to hear music and English calls.
The report transport
provides Play/Pause, Stop/Cancel, Loop, Prev/Next, and whole-report seeking;
the selected chart follows the recorded route. After audio preparation, the
transport distinguishes **responses checked** from **ending provisional**.
Individual recorded phrases show **timing checked** when their chart, cue,
offset, and voice samples match the evidence. Changed or unobserved sources
retain a provisional label.
This is one CPU-run route: the preview joins the two parts without the game's loading pause,
other performance branches remain unverified, and exact scene names are still
provisional. Changed source files fall back to file order. Displayed response
times are engine positions within a part, rather than measured audio onsets.
Flagged command bytes keep their original chart labels and values. Voice aliases
are limited to R11; other extended calls and hold stretching/release remain
unfinished. Unknown events still require an explicit skip or music-only choice.
The 60 ms tolerance describes this recording comparison, not a timing guarantee
for every computer or branch. The largest measured voice/music difference was
54.3 ms. No device-specific output delay has been added to the preview. Original
chart tempos and sample positions remain the playback clock.

For a phrase loop, select a note and use **From** and **To**, then enable
**Loop** and press **Play**. If an earlier call in that phrase is still sounding
at the range start, its remaining audio continues from the correct point.
It does not restart the earlier command. This includes the long Chu's short
overlap into the following note. Unidentified earlier tails receive a warning;
held-note stretching and game release behavior remain unfinished.

The editor supports:

- clicking a node to inspect it
- dragging steps left and right on the timeline
- placing new steps by arming a move and clicking the timeline
- editing move type, RAW byte, gap, tick, timing, and start delay
- undo / redo

Dense phrases open at 4x timeline zoom. Use the timeline's **+**, **-**, **Fit**,
and **< / >** controls to inspect another part of the phrase. The mouse wheel
over the timeline pans; Ctrl+wheel changes zoom. Playback follows the moving
cursor until you pan manually. Starting playback again resumes following.
Zoom changes only the view: placement and dragging still use absolute chart
ticks, and it does not change your project or exported timing.

At smaller window sizes, scroll over the right-hand details panel to reach all
selected-step controls and validation messages. A scrollbar and footer show
when more details are available.

Modified entries are marked in the entry list. Invalid edits are blocked before apply or patch, and the UI will show the validation reason.

## Shortcuts

- `Delete` / `Backspace`: delete selected step
- `Ctrl+Z`: undo
- `Ctrl+Y` or `Ctrl+Shift+Z`: redo
- `Ctrl+S`: save project
- `Ctrl+Shift+S`: save project as
- `Ctrl+O`: open project
- `Escape`: clear step selection or cancel move placement

## Mods

The `Mods` button opens the built-in mod manager. It can:

- install `.zip` Noizemaker mods
- accept drag-and-drop zip installs
- open `noize:` GameBanana install links
- enable and disable installed mods
- uninstall mods
- restore backed-up original files

Installed mods unpack into:

```text
mods/
  mod_name/
    noizemaker.yaml
    files/
      r11_sh.bin
      r11cap_e.bin
      R1.BIN
```

Original files are backed up separately:

```text
backups/
  original/
    r11_sh.bin
    r11cap_e.bin
```

That backup tree mirrors the game root relative file layout.

## Mod manifest

Each mod zip needs a `noizemaker.yaml` at the archive root, or inside a single top-level folder.

Example:

```yaml
name: Example Mod Name
version: 1.0.0
description: Short description of the mod.
author: Example Author
game_version: Steam
homepage: https://example.com/noizemaker-mod
changed_files:
  - r11_sh.bin
  - r11cap_e.bin
```

Required fields:

- `name`
- `version`
- `description`
- `changed_files`

Optional fields currently supported:

- `author`
- `game_version`
- `homepage`

## Notes

- This tool does not support macOS. If you have it running there, you are on your own.
