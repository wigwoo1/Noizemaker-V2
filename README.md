# Noizemaker V2 — Visual Chart Editor

An in-development Windows visual chart editor for Space Channel 5 Part 2,
based on [Hyonk-Tea's Noizemaker](https://github.com/Hyonk-Tea/Noizemaker).
The original editor and patcher remain the foundation of this project.

This repository contains the current visual preview source: English report
loading, drag-and-drop command editing, English voice previews, partial music
mapping, project saving, and report exports. Automatic whole-report playback,
complete music/extended-call mapping, and in-game export verification are still
unfinished. Report 1's recorded CPU route is supported; other routes and scene
names remain provisional. Game assets and audio are read from your own game
installation at runtime.

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
4. Press `Apply` to store that entry in the pending patch set.
5. Press `Patch` to write a patched copy.

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
underneath. **Prev/Next** selects adjacent recorded phrases across chart files,
stopping the current preview. Automatic whole-report playback remains unfinished.
This is one CPU-run route: the cross-file handoff was not continuously recorded,
other performance branches remain unverified, and exact scene names are still
provisional. Changed source files fall back to file order. Displayed response
times are engine positions within a part, rather than measured audio onsets.

The editor supports:

- clicking a node to inspect it
- dragging steps left and right on the timeline
- placing new steps by arming a move and clicking the timeline
- editing move type, RAW byte, gap, tick, timing, and start delay
- undo / redo

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
