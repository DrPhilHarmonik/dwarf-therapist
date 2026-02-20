# Dwarf Therapist

A [DFHack](https://github.com/DFHack/dfhack) GUI script for [Dwarf Fortress (Steam)](https://store.steampowered.com/app/975370/Dwarf_Fortress/) that lets you manage dwarf labors, view skills, monitor needs, and inspect attributes, personality, military status, work details, and preferences — all without leaving the game.

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

A fortress map must be loaded. Running the command again while the window is open will bring it to focus rather than opening a duplicate. The window is draggable and resizable. Window position and size are saved to `dfhack-config/dwarf-therapist.json` and restored on next open.

## Dwarf list (left pane)

- All active citizen dwarves with profession and current job shown below their name
- Name color reflects current stress level (cyan = ecstatic → red = miserable)
- Current job is shown in dark grey when idle, white when working
- Type to filter by name or profession
- `Ctrl+O` — cycle sort order: Name / Profession / Unhappy first / Idle first
- `Ctrl+E` — refresh the list (picks up migrants, deaths, etc.)

## Tabs (right pane)

### Labors

- Full list of assignable labors for the selected dwarf
- `Enter` — toggle a labor on or off
- `Ctrl+Z` — undo the last labor toggle
- `Ctrl+F` — **Find best dwarf**: jumps the dwarf list to the citizen with the highest skill for the highlighted labor
- `Ctrl+C` — copy this dwarf's full labor set to the clipboard
- `Ctrl+V` — paste the clipboard labor set onto this dwarf
- `Ctrl+P` — save this dwarf's labor set as a new named preset (stored in `dfhack-config/dwarf-therapist.json`)
- `Ctrl+L` — open the preset picker to load a saved preset onto this dwarf
- Type to filter by labor name
- **Skill hints:** if a labor has an associated skill, the labor name is colored by the dwarf's rating in that skill and the rating is shown inline (grey → white → yellow → green → light green)
- **Coverage count:** each labor shows how many dwarves are currently assigned — red if zero, yellow if one or two

### Skills

- All skills for the selected dwarf, color-coded by rating
- Type to filter by skill name
- `Ctrl+A` — toggle between learned skills only (default) and all skills

### Needs

- Overall mood and stress level at the top
- All needs listed sorted worst-first, colored by fulfillment status (green → yellow → red)
- Type to filter by need name

### Attrs

- Physical and mental attributes, color-coded by value
- Dark grey = poor, grey = below average, white = average, green = above average, light green = exceptional
- Type to filter by attribute name

### Persona

- `Ctrl+A` — toggle between two views:
  - **Traits:** personality facets (0–100), colored by how extreme they are — grey = neutral, white = notable, yellow = strong, red = extreme
  - **Thoughts:** recent emotions sorted newest-first, green = positive feeling, red = negative
- Type to filter

### Summary

- Fortress-wide labor coverage: every labor with its total assignment count and the top two most skilled dwarves for that labor
- Assignment count is red if zero, yellow if one or two
- Type to filter by labor name
- `Ctrl+E` — refresh

### Military

- Squad name and position for the selected dwarf, or "None" if not enlisted
- Combat skills listed with color-coded ratings (fighter, weapon skills, shield, armor, dodger, wrestler, etc.)
- Type to filter by skill name

### Work

- All work details defined in the fortress, with `[x]` marking the ones this dwarf is assigned to
- Type to filter by work detail name

### Prefs

- All personality preferences for the selected dwarf (liked/hated foods, materials, creatures, items, plants, etc.)
- Hated preferences shown in red
- Type to filter

## CSV export

Press `Ctrl+X` on any tab to export all citizens for that view to a CSV file in the DF install directory. The full path is printed to the DFHack console on success.

| Tab | File | Contents |
|-----|------|----------|
| Labors | `dwarf-therapist-labors.csv` | dwarves × labors matrix (0/1) |
| Skills | `dwarf-therapist-skills.csv` | dwarves × skills matrix (rating) |
| Needs | `dwarf-therapist-needs.csv` | dwarves × needs matrix (focus level) |
| Attrs | `dwarf-therapist-attributes.csv` | dwarves × attributes (value) |
| Persona | `dwarf-therapist-traits.csv` | dwarves × personality facets (0–100) |
| Summary | `dwarf-therapist-summary.csv` | labor coverage table |
| Military | `dwarf-therapist-military.csv` | dwarves × combat skills + squad info |
| Work | `dwarf-therapist-work-details.csv` | dwarves × work details (0/1) |
| Prefs | `dwarf-therapist-preferences.csv` | one row per preference per dwarf |

## License

MIT
