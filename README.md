# Dwarf Therapist

A [DFHack](https://github.com/DFHack/dfhack) GUI script for [Dwarf Fortress (Steam)](https://store.steampowered.com/app/975370/Dwarf_Fortress/) that lets you manage dwarf labors, view skills, and monitor needs — all without leaving the game.

![screenshot placeholder]

## Requirements

- Dwarf Fortress (Steam edition)
- DFHack (included with the Steam version)

## Installation

Copy `gui/dwarf-therapist.lua` into your `dfhack-config/scripts/gui/` folder:

```
<DF install dir>/dfhack-config/scripts/gui/dwarf-therapist.lua
```

**Optional keybinding:** add this line to `dfhack-config/init/dfhack.init` to open it with `Ctrl+Shift+T`:

```
keybinding add Ctrl+Shift+T gui/dwarf-therapist
```

## Usage

Open the DFHack console and run:

```
gui/dwarf-therapist
```

A fortress map must be loaded. Running the command again while the window is open will bring it to focus rather than opening a duplicate.

## Features

### Dwarf list (left pane)

- All active citizen dwarves, with their profession shown below their name
- Type to filter by name or profession
- `r` — refresh the list (picks up migrants, deaths, etc.)

### Labors tab

- Full list of assignable labors for the selected dwarf
- `Enter` — toggle a labor on or off
- Type to filter by labor name
- **Skill hints:** if a labor has an associated skill, the labor name is colored by the dwarf's rating in that skill (grey → white → yellow → green → light green as skill increases), and the rating is shown inline
- **Coverage warnings:** each labor shows how many dwarves are currently assigned to it — red if zero, yellow if one or two

### Skills tab

- All skills for the selected dwarf, color-coded by rating
- Type to filter by skill name
- `a` — toggle between learned skills only (default) and all skills

### Needs tab

- Overall mood and stress level at the top
- All needs listed sorted worst-first, colored by fulfillment status (green → white → yellow → red)
- Type to filter by need name

## License

MIT
