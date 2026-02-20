-- Manage dwarf labors, skills, needs, attributes, and personality.
--[====[

gui/dwarf-therapist
===================

Tags: fort | inspection | interface | labors | units

Command: ``gui/dwarf-therapist``

  Manage dwarf labors, skills, needs, attributes, and personality.

Dwarf Therapist is a split-pane GUI for managing fortress citizens. The
dwarf list is on the left; detailed tabs for the selected dwarf are on the
right. The window is draggable, resizable, and remembers its position and
size between sessions (stored in ``dfhack-config/dwarf-therapist.json``).

A fortress map must be loaded. Running the command again while the window
is open will bring it to focus rather than opening a duplicate.

Usage
-----

::

    gui/dwarf-therapist

Optional keybinding — add to ``dfhack-config/init/dfhack.init``::

    keybinding add Ctrl+Shift+T gui/dwarf-therapist

Dwarf list (left pane)
----------------------

All active citizen dwarves are shown with their profession and current job.
Name color reflects stress level (cyan = ecstatic, red = miserable). Type
to filter by name or profession.

``Ctrl+S``
    Cycle sort order: Name / Profession / Unhappy first / Idle first.

``Ctrl+R``
    Refresh the list (picks up migrants, retirements, deaths, etc.).

Tabs (right pane)
-----------------

**Labors**
    Full list of assignable labors. ``Enter`` toggles the highlighted labor.
    Labor names are colored by the dwarf's skill rating for that labor; a
    coverage count shows how many dwarves hold each labor (red = zero,
    yellow = one or two).

    ``Ctrl+F``  Find best dwarf — jump the list to the citizen with the
    highest skill for the highlighted labor.

    ``Ctrl+Z``  Undo the last labor toggle.

    ``Ctrl+C``  Copy this dwarf's full labor set to the clipboard.

    ``Ctrl+V``  Paste the clipboard labor set onto this dwarf.

    ``Ctrl+P``  Save this dwarf's labor set as a new named preset.

    ``Ctrl+L``  Open the preset picker to load a saved preset onto this dwarf.

**Skills**
    All skills color-coded by rating. ``Ctrl+A`` toggles between learned
    skills only (default) and all skills.

**Needs**
    Overall mood and stress level at the top. All needs sorted worst-first,
    colored by fulfillment status (green = satisfied, red = badly distracted).

**Attrs**
    Physical and mental attributes color-coded by value (dark grey = poor,
    light green = exceptional).

**Persona**
    ``Ctrl+A`` toggles between two views:

    - *Traits* — personality facets (0–100), grey = neutral, red = extreme.
    - *Thoughts* — recent emotions sorted newest-first, green = positive,
      red = negative.

**Summary**
    Fortress-wide labor coverage showing assignment count and the top two
    most skilled dwarves for every labor. ``Ctrl+R`` to refresh.

**Military**
    Squad name and position for the selected dwarf (or "None"), plus
    combat skill ratings.

**Work**
    All work details defined in the fortress with ``[x]`` marking which
    ones this dwarf belongs to.

**Prefs**
    All personality preferences (liked/hated foods, materials, creatures,
    items, plants, etc.). Hated preferences are shown in red.

CSV export
----------

Press ``Ctrl+X`` on any tab to export data for all citizens to a CSV file
in the DF install directory. The full path is printed to the DFHack console.

Presets
-------

Named labor presets are saved to ``dfhack-config/dwarf-therapist.json``.
The same file stores the window position and size.

]====]

local gui     = require('gui')
local widgets = require('gui.widgets')
local utils   = require('utils')
local json    = require('json')

-- ============================================================
-- Config persistence
-- ============================================================

local CONFIG_FILE = 'dfhack-config/dwarf-therapist.json'
local _cfg

local function get_cfg()
    if not _cfg then
        _cfg = json.open(CONFIG_FILE)
        if not _cfg.data then _cfg.data = {} end
    end
    return _cfg
end

-- ============================================================
-- CSV export helpers
-- ============================================================

local function csv_escape(v)
    local s = tostring(v == nil and '' or v)
    if s:find('[,"\n\r]') then
        s = '"' .. s:gsub('"', '""') .. '"'
    end
    return s
end

local function write_csv(path, headers, rows)
    local f, err = io.open(path, 'w')
    if not f then
        dfhack.printerr('dwarf-therapist: cannot write ' .. path .. ': ' .. tostring(err))
        return false
    end
    local function line(t)
        local parts = {}
        for _, v in ipairs(t) do table.insert(parts, csv_escape(v)) end
        return table.concat(parts, ',') .. '\r\n'
    end
    f:write(line(headers))
    for _, row in ipairs(rows) do f:write(line(row)) end
    f:close()
    return true
end

local function export_path(tag)
    return dfhack.getDFPath() .. '/dwarf-therapist-' .. tag .. '.csv'
end

-- ============================================================
-- Data helpers
-- ============================================================

local function get_citizens()
    return dfhack.units.getCitizens(true)
end

local function unit_display_name(unit)
    return dfhack.units.getReadableName(unit)
end

-- Manual labor→skill mapping. df.unit_labor.attrs[id].skill doesn't exist
-- in the Steam DFHack version, so we maintain this table ourselves.
local LABOR_SKILL_MAP = {
    MINE             = 'MINING',
    CUTWOOD          = 'WOODCUTTING',
    CARPENTER        = 'CARPENTRY',
    STONECUTTER      = 'CUT_STONE',
    STONE_CARVER     = 'CARVE_STONE',
    ENGRAVER         = 'ENGRAVE_STONE',
    MASON            = 'MASONRY',
    ANIMALTRAIN      = 'ANIMALTRAIN',
    ANIMALCARE       = 'ANIMALCARE',
    DIAGNOSE         = 'DIAGNOSE',
    SURGERY          = 'SURGERY',
    BONE_SETTING     = 'SET_BONE',
    SUTURING         = 'SUTURE',
    DRESSING_WOUNDS  = 'DRESS_WOUNDS',
    BUTCHER          = 'BUTCHER',
    TRAPPER          = 'TRAPPING',
    DISSECT_VERMIN   = 'DISSECT_VERMIN',
    LEATHER          = 'LEATHERWORK',
    TANNER           = 'TANNER',
    BREWER           = 'BREWING',
    WEAVER           = 'WEAVING',
    CLOTHESMAKER     = 'CLOTHESMAKING',
    MILLER           = 'MILLING',
    PROCESS_PLANT    = 'PROCESSPLANTS',
    MAKE_CHEESE      = 'CHEESEMAKING',
    MILK             = 'MILK',
    COOK             = 'COOK',
    PLANT            = 'PLANT',
    HERBALIST        = 'HERBALISM',
    FISH             = 'FISH',
    CLEAN_FISH       = 'PROCESSFISH',
    DISSECT_FISH     = 'DISSECT_FISH',
    SMELT            = 'SMELT',
    FORGE_WEAPON     = 'FORGE_WEAPON',
    FORGE_ARMOR      = 'FORGE_ARMOR',
    FORGE_FURNITURE  = 'FORGE_FURNITURE',
    METAL_CRAFT      = 'METALCRAFT',
    CUT_GEM          = 'CUTGEM',
    ENCRUST_GEM      = 'ENCRUSTGEM',
    WOOD_CRAFT       = 'WOODCRAFT',
    STONE_CRAFT      = 'STONECRAFT',
    BONE_CARVE       = 'BONECARVE',
    GLASSMAKER       = 'GLASSMAKER',
    EXTRACT_STRAND   = 'EXTRACT_STRAND',
    SIEGECRAFT       = 'SIEGECRAFT',
    SIEGEOPERATE     = 'SIEGEOPERATE',
    BOWYER           = 'BOWYER',
    MECHANIC         = 'MECHANICS',
    DYER             = 'DYER',
    SHEARER          = 'SHEARING',
    SPINNER          = 'SPINNING',
    POTTERY          = 'POTTERY',
    GLAZING          = 'GLAZING',
    PRESSING         = 'PRESSING',
    BEEKEEPING       = 'BEEKEEPING',
    WAX_WORKING      = 'WAX_WORKING',
    PAPERMAKING      = 'PAPERMAKING',
    BOOKBINDING      = 'BOOKBINDING',
}

-- Labor list: {name, id, skill_id} built once at load time.
local LABORS = (function()
    local list = {}
    for id, name in ipairs(df.unit_labor) do
        if id ~= df.unit_labor.NONE then
            local skill_name = LABOR_SKILL_MAP[name]
            local skill_id = (skill_name and df.job_skill[skill_name]) or df.job_skill.NONE
            table.insert(list, {name=name, id=id, skill_id=skill_id})
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end)()

-- Combat skills shown in Military tab.
local MILITARY_SKILLS = (function()
    local names = {
        'FIGHTER', 'SWORD', 'MACE', 'HAMMER', 'AXE', 'SPEAR', 'PIKE',
        'WHIP', 'CROSSBOW', 'BOW', 'BLOWGUN', 'THROWING', 'BITE',
        'SHIELD', 'ARMOR', 'DODGER', 'WRESTLER', 'STRIKER', 'KICKER',
    }
    local list = {}
    for _, name in ipairs(names) do
        local id = df.job_skill[name]
        if id and id ~= df.job_skill.NONE then
            local ok, cap = pcall(function()
                return df.job_skill.attrs[id].caption
            end)
            table.insert(list, {name=name, id=id, caption=ok and cap or name})
        end
    end
    return list
end)()

-- ============================================================
-- Shared color helpers
-- ============================================================

local function skill_pen(rating)
    if rating >= df.skill_rating.Legendary then return COLOR_LIGHTGREEN end
    if rating >= 9 then return COLOR_GREEN  end
    if rating >= 6 then return COLOR_YELLOW end
    if rating >= 3 then return COLOR_WHITE  end
    return COLOR_GREY
end

local function skill_rating_caption(rating)
    if rating < 0 then return '<unlearned>' end
    if rating > df.skill_rating.Legendary then
        local bonus = rating - df.skill_rating.Legendary
        return df.skill_rating.attrs[df.skill_rating.Legendary].caption .. '+' .. bonus
    end
    return df.skill_rating.attrs[rating].caption
end

-- Attribute value: typical range 500-1500, average ~1000.
local function attr_pen(value)
    if value >= 2000 then return COLOR_LIGHTGREEN end
    if value >= 1500 then return COLOR_GREEN  end
    if value >= 1250 then return COLOR_WHITE  end
    if value >= 750  then return COLOR_GREY   end
    return COLOR_DARKGREY
end

-- Personality facet: 0-100, 50 = neutral.
local function facet_pen(value)
    if value >= 91 or value <=  9 then return COLOR_LIGHTRED end
    if value >= 76 or value <= 24 then return COLOR_YELLOW   end
    if value >= 61 or value <= 39 then return COLOR_WHITE    end
    return COLOR_GREY
end

-- ============================================================
-- Stress / focus helpers
-- ============================================================

local STRESS_LEVELS = {
    {threshold = -500000, label = 'Ecstatic',    pen = COLOR_LIGHTCYAN},
    {threshold =       0, label = 'Happy',        pen = COLOR_LIGHTGREEN},
    {threshold =   25000, label = 'Content',      pen = COLOR_GREEN},
    {threshold =   50000, label = 'Fine',         pen = COLOR_WHITE},
    {threshold =  125000, label = 'Unhappy',      pen = COLOR_YELLOW},
    {threshold =  200000, label = 'Very unhappy', pen = COLOR_LIGHTRED},
}

local function stress_info(level)
    for _, s in ipairs(STRESS_LEVELS) do
        if level <= s.threshold then return s.label, s.pen end
    end
    return 'Miserable', COLOR_RED
end

local FOCUS_LEVELS = {
    {threshold =    300, label = 'Satisfied',    pen = COLOR_GREEN},
    {threshold =    100, label = 'Fine',         pen = COLOR_WHITE},
    {threshold =   -100, label = 'Okay',         pen = COLOR_GREY},
    {threshold =   -999, label = 'Unfulfilled',  pen = COLOR_YELLOW},
    {threshold =  -9999, label = 'Distracted',   pen = COLOR_LIGHTRED},
}

local function focus_info(focus_level)
    for _, f in ipairs(FOCUS_LEVELS) do
        if focus_level >= f.threshold then return f.label, f.pen end
    end
    return 'Badly distracted', COLOR_RED
end

-- ============================================================
-- NeedsPanel
-- ============================================================

NeedsPanel = defclass(NeedsPanel, widgets.Panel)
NeedsPanel.ATTRS{ unit = DEFAULT_NIL }

function NeedsPanel:init()
    self:addviews{
        widgets.Label{
            view_id  = 'header',
            frame    = {t=0, l=0, h=1},
            text     = 'Select a dwarf.',
            text_pen = COLOR_GREY,
        },
        widgets.Label{
            view_id = 'stress',
            frame   = {t=1, l=0, h=1},
            text    = '',
        },
        widgets.FilteredList{
            view_id          = 'list',
            frame            = {t=3, l=0, b=0},
            edit_ignore_keys = {'CUSTOM_CTRL_X'},
        },
    }
end

function NeedsPanel:set_unit(unit)
    self.unit = unit
    self.subviews.header:setText(unit and unit_display_name(unit) or 'Select a dwarf.')
    self:rebuild()
end

function NeedsPanel:rebuild()
    if not self.unit or not self.unit.status.current_soul then
        self.subviews.stress:setText('')
        self.subviews.list:setChoices({})
        return
    end
    local soul = self.unit.status.current_soul.personality
    local s_label, s_pen = stress_info(soul.stress)
    self.subviews.stress:setText{
        'Mood: ',
        {text = string.format('%-16s', s_label),           pen = s_pen},
        {text = string.format('(stress %d)', soul.stress), pen = COLOR_DARKGREY},
    }
    local needs = {}
    for _, need in ipairs(soul.needs) do
        local f_label, f_pen = focus_info(need.focus_level)
        table.insert(needs, {
            name        = df.need_type[need.id] or tostring(need.id),
            focus_level = need.focus_level,
            f_label     = f_label,
            f_pen       = f_pen,
        })
    end
    table.sort(needs, function(a, b) return a.focus_level < b.focus_level end)
    local choices = {}
    for _, n in ipairs(needs) do
        table.insert(choices, {
            text = {
                {text = string.format('%-28s', n.name), pen = n.f_pen},
                {text = n.f_label,                      pen = n.f_pen},
            },
            search_key = n.name:lower(),
        })
    end
    self.subviews.list:setChoices(choices)
end

-- ============================================================
-- AttrsPanel: physical and mental attributes.
-- ============================================================

AttrsPanel = defclass(AttrsPanel, widgets.Panel)
AttrsPanel.ATTRS{ unit = DEFAULT_NIL }

function AttrsPanel:init()
    self:addviews{
        widgets.Label{
            view_id  = 'header',
            frame    = {t=0, l=0, h=1},
            text     = 'Select a dwarf.',
            text_pen = COLOR_GREY,
        },
        widgets.FilteredList{
            view_id          = 'list',
            frame            = {t=2, l=0, b=0},
            edit_ignore_keys = {'CUSTOM_CTRL_X'},
        },
    }
end

function AttrsPanel:set_unit(unit)
    self.unit = unit
    self.subviews.header:setText(unit and unit_display_name(unit) or 'Select a dwarf.')
    self:rebuild()
end

function AttrsPanel:rebuild()
    local choices = {}
    if not self.unit or not self.unit.status.current_soul then
        self.subviews.list:setChoices(choices)
        return
    end

    local function add_attrs(attrs, enum_type, section_label)
        table.insert(choices, {
            text       = {text = '-- ' .. section_label .. ' --', pen = COLOR_YELLOW},
            search_key = section_label:lower(),
        })
        for i, v in ipairs(attrs) do
            local raw_name = enum_type[i] or tostring(i)
            local name = raw_name:gsub('_', ' '):lower():gsub('^%l', string.upper)
            local pen  = attr_pen(v.value)
            table.insert(choices, {
                text = {
                    {text = string.format('%-22s', name), pen = pen},
                    {text = string.format('%5d', v.value), pen = pen},
                    {text = string.format(' / %d', v.max_value), pen = COLOR_DARKGREY},
                },
                search_key = name:lower(),
            })
        end
    end

    add_attrs(self.unit.body.physical_attrs,
              df.physical_attribute_type, 'Physical')
    add_attrs(self.unit.status.current_soul.mental_attrs,
              df.mental_attribute_type, 'Mental')

    self.subviews.list:setChoices(choices)
end

-- ============================================================
-- PersonalityPanel: facets/traits and recent thoughts.
-- ============================================================

PersonalityPanel = defclass(PersonalityPanel, widgets.Panel)
PersonalityPanel.ATTRS{ unit = DEFAULT_NIL }

function PersonalityPanel:init()
    self:addviews{
        widgets.Label{
            view_id  = 'header',
            frame    = {t=0, l=0, h=1},
            text     = 'Select a dwarf.',
            text_pen = COLOR_GREY,
        },
        widgets.CycleHotkeyLabel{
            view_id  = 'view_mode',
            frame    = {t=1, l=0, h=1},
            key      = 'CUSTOM_CTRL_A',
            label    = 'Show: ',
            options  = {
                {label = 'Traits',   value = 'traits'},
                {label = 'Thoughts', value = 'thoughts'},
            },
            on_change = function() self:rebuild() end,
        },
        widgets.FilteredList{
            view_id          = 'list',
            frame            = {t=3, l=0, b=0},
            edit_ignore_keys = {'CUSTOM_CTRL_A', 'CUSTOM_CTRL_X'},
        },
    }
end

function PersonalityPanel:set_unit(unit)
    self.unit = unit
    self.subviews.header:setText(unit and unit_display_name(unit) or 'Select a dwarf.')
    self:rebuild()
end

function PersonalityPanel:rebuild()
    local mode = self.subviews.view_mode:getOptionValue()
    if mode == 'traits' then
        self:rebuild_traits()
    else
        self:rebuild_thoughts()
    end
end

function PersonalityPanel:rebuild_traits()
    local choices = {}
    if self.unit and self.unit.status.current_soul then
        local traits = self.unit.status.current_soul.personality.traits
        for i, value in ipairs(traits) do
            local raw_name = df.personality_facet_type[i] or tostring(i)
            local name = raw_name:gsub('_', ' '):lower():gsub('^%l', string.upper)
            local pen  = facet_pen(value)
            table.insert(choices, {
                text = {
                    {text = string.format('%-28s', name), pen = pen},
                    {text = string.format('%3d', value),  pen = pen},
                },
                search_key = name:lower(),
            })
        end
    end
    self.subviews.list:setChoices(choices)
end

function PersonalityPanel:rebuild_thoughts()
    local choices = {}
    if self.unit and self.unit.status.current_soul then
        local emotions = self.unit.status.current_soul.personality.emotions
        local sorted = {}
        for _, e in ipairs(emotions) do table.insert(sorted, e) end
        table.sort(sorted, function(a, b)
            if a.year ~= b.year then return a.year > b.year end
            return a.year_tick > b.year_tick
        end)
        for _, e in ipairs(sorted) do
            local emo = df.emotion_type[e.type]        or '?'
            local tht = df.unit_thought_type[e.thought] or '?'
            local pen = (e.relative_strength or 0) >= 0 and COLOR_LIGHTGREEN or COLOR_LIGHTRED
            table.insert(choices, {
                text = {
                    {text = string.format('%-16s', emo), pen = pen},
                    {text = tht,                         pen = COLOR_GREY},
                },
                search_key = (emo .. ' ' .. tht):lower(),
            })
        end
    end
    self.subviews.list:setChoices(choices)
end

-- ============================================================
-- SkillsPanel
-- ============================================================

SkillsPanel = defclass(SkillsPanel, widgets.Panel)
SkillsPanel.ATTRS{ unit = DEFAULT_NIL }

function SkillsPanel:init()
    self:addviews{
        widgets.Label{
            view_id  = 'header',
            frame    = {t=0, l=0, h=1},
            text     = 'Select a dwarf.',
            text_pen = COLOR_GREY,
        },
        widgets.FilteredList{
            view_id          = 'list',
            frame            = {t=2, l=0, b=2},
            edit_ignore_keys = {'CUSTOM_CTRL_A', 'CUSTOM_CTRL_X'},
        },
        widgets.CycleHotkeyLabel{
            view_id   = 'filter_mode',
            frame     = {b=0, l=0},
            key       = 'CUSTOM_CTRL_A',
            label     = 'Show: ',
            options   = {
                {label='Learned only', value=false},
                {label='All skills',   value=true},
            },
            on_change = function() self:rebuild_list() end,
        },
    }
end

function SkillsPanel:set_unit(unit)
    self.unit = unit
    self.subviews.header:setText(unit and unit_display_name(unit) or 'Select a dwarf.')
    self:rebuild_list()
end

function SkillsPanel:rebuild_list()
    local choices = {}
    if self.unit and self.unit.status.current_soul then
        local u_skills = self.unit.status.current_soul.skills
        local show_all = self.subviews.filter_mode:getOptionValue()
        for skill_id, _ in ipairs(df.job_skill) do
            if skill_id ~= df.job_skill.NONE then
                local entry  = utils.binsearch(u_skills, skill_id, 'id')
                local rating = entry and entry.rating or -1
                if show_all or rating >= 0 then
                    local caption    = df.job_skill.attrs[skill_id].caption
                    local rating_str = skill_rating_caption(rating)
                    local pen        = skill_pen(rating)
                    table.insert(choices, {
                        text = {
                            {text = string.format('%-30s', caption), pen = pen},
                            {text = rating_str,                      pen = pen},
                        },
                        search_key = caption:lower(),
                    })
                end
            end
        end
    end
    self.subviews.list:setChoices(choices)
end

-- ============================================================
-- LaborPanel: toggles with skill hints, coverage warnings,
-- find-best-dwarf, undo, copy/paste, and named presets.
-- ============================================================

local labor_clipboard = nil  -- shared in-memory copy

LaborPanel = defclass(LaborPanel, widgets.Panel)
LaborPanel.ATTRS{
    unit         = DEFAULT_NIL,
    on_find_best = DEFAULT_NIL,
}

function LaborPanel:init()
    self.undo_state = nil   -- {labor_id, was_enabled}
    self:addviews{
        widgets.Label{
            view_id  = 'header',
            frame    = {t=0, l=0, h=1},
            text     = 'Select a dwarf.',
            text_pen = COLOR_GREY,
        },
        widgets.FilteredList{
            view_id          = 'list',
            frame            = {t=2, l=0, b=4},
            on_submit        = function(_, choice) self:toggle_labor(choice.labor_id) end,
            edit_ignore_keys = {'CUSTOM_CTRL_F','CUSTOM_CTRL_Z','CUSTOM_CTRL_C','CUSTOM_CTRL_V','CUSTOM_CTRL_P','CUSTOM_CTRL_L','CUSTOM_CTRL_X'},
        },
        widgets.Label{
            frame = {b=2, l=0},
            text  = {
                {key='SELECT',        text=': Toggle  '},
                {key='CUSTOM_CTRL_F', text=': Find best  '},
                {key='CUSTOM_CTRL_Z', text=': Undo'},
            },
        },
        widgets.Label{
            frame = {b=0, l=0},
            text  = {
                {key='CUSTOM_CTRL_C', text=': Copy  '},
                {key='CUSTOM_CTRL_V', text=': Paste  '},
                {key='CUSTOM_CTRL_P', text=': Save preset  '},
                {key='CUSTOM_CTRL_L', text=': Load preset'},
            },
        },
    }
end

function LaborPanel:set_unit(unit)
    self.unit = unit
    self.subviews.header:setText(unit and unit_display_name(unit) or 'Select a dwarf.')
    self:rebuild_list()
end

function LaborPanel:rebuild_list()
    local counts = {}
    for _, u in ipairs(get_citizens()) do
        for _, labor in ipairs(LABORS) do
            if u.status.labors[labor.id] then
                counts[labor.id] = (counts[labor.id] or 0) + 1
            end
        end
    end

    local choices = {}
    if self.unit then
        local u_skills = self.unit.status.current_soul
            and self.unit.status.current_soul.skills or nil

        for _, labor in ipairs(LABORS) do
            local enabled   = self.unit.status.labors[labor.id]
            local count     = counts[labor.id] or 0
            local skill_str = string.rep(' ', 14)
            local name_pen  = COLOR_WHITE

            if labor.skill_id ~= df.job_skill.NONE and u_skills then
                local entry  = utils.binsearch(u_skills, labor.skill_id, 'id')
                local rating = entry and entry.rating or -1
                if rating >= 0 then
                    skill_str = string.format('%-14s', skill_rating_caption(rating))
                    name_pen  = skill_pen(rating)
                end
            end

            local count_pen = count == 0 and COLOR_LIGHTRED
                           or count <= 2  and COLOR_YELLOW
                           or COLOR_DARKGREY

            table.insert(choices, {
                text = {
                    {text = enabled and '[x] ' or '[ ] ',
                     pen  = enabled and COLOR_GREEN or COLOR_GREY},
                    {text = string.format('%-22s', labor.name), pen = name_pen},
                    {text = skill_str,                          pen = name_pen},
                    {text = string.format('(%d)', count),       pen = count_pen},
                },
                search_key = labor.name:lower(),
                labor_id   = labor.id,
            })
        end
    end
    self.subviews.list:setChoices(choices)
end

function LaborPanel:toggle_labor(labor_id)
    if not self.unit then return end
    local was = self.unit.status.labors[labor_id]
    self.undo_state = {labor_id=labor_id, was_enabled=was}
    self.unit.status.labors[labor_id] = not was
    self:rebuild_list()
end

function LaborPanel:undo_toggle()
    if not self.unit or not self.undo_state then return end
    self.unit.status.labors[self.undo_state.labor_id] = self.undo_state.was_enabled
    self.undo_state = nil
    self:rebuild_list()
end

function LaborPanel:copy_labors()
    if not self.unit then return end
    labor_clipboard = {}
    for _, labor in ipairs(LABORS) do
        labor_clipboard[labor.name] = self.unit.status.labors[labor.id] and true or false
    end
end

function LaborPanel:paste_labors()
    if not self.unit or not labor_clipboard then return end
    for _, labor in ipairs(LABORS) do
        self.unit.status.labors[labor.id] = labor_clipboard[labor.name] or false
    end
    self:rebuild_list()
end

function LaborPanel:save_preset()
    if not self.unit then return end
    local c = get_cfg()
    if not c.data.presets then c.data.presets = {} end
    local labors = {}
    for _, labor in ipairs(LABORS) do
        labors[labor.name] = self.unit.status.labors[labor.id] and true or false
    end
    local n = #c.data.presets + 1
    table.insert(c.data.presets, {name='Preset ' .. n, labors=labors})
    c:write()
end

function LaborPanel:load_preset_dialog()
    if not self.unit then return end
    local c = get_cfg()
    if not c.data.presets or #c.data.presets == 0 then return end
    local choices = {}
    for _, preset in ipairs(c.data.presets) do
        table.insert(choices, {
            text       = preset.name,
            preset     = preset,
            search_key = preset.name:lower(),
        })
    end
    local panel = self
    PresetDialog{
        choices   = choices,
        on_apply  = function(preset)
            for _, labor in ipairs(LABORS) do
                panel.unit.status.labors[labor.id] = preset.labors[labor.name] or false
            end
            panel:rebuild_list()
        end,
    }:show()
end

function LaborPanel:find_best_dwarf()
    local _, choice = self.subviews.list:getSelected()
    if not choice then return end
    local labor = nil
    for _, l in ipairs(LABORS) do
        if l.id == choice.labor_id then labor = l; break end
    end
    if not labor or labor.skill_id == df.job_skill.NONE then return end
    local best_unit, best_rating = nil, -1
    for _, u in ipairs(get_citizens()) do
        if u.status.current_soul then
            local entry  = utils.binsearch(u.status.current_soul.skills, labor.skill_id, 'id')
            local rating = entry and entry.rating or -1
            if rating > best_rating then
                best_rating = rating
                best_unit   = u
            end
        end
    end
    if best_unit and self.on_find_best then
        self.on_find_best(best_unit)
    end
end

function LaborPanel:onInput(keys)
    if keys.CUSTOM_CTRL_F then self:find_best_dwarf();     return true end
    if keys.CUSTOM_CTRL_Z then self:undo_toggle();          return true end
    if keys.CUSTOM_CTRL_C then self:copy_labors();          return true end
    if keys.CUSTOM_CTRL_V then self:paste_labors();         return true end
    if keys.CUSTOM_CTRL_P then self:save_preset();          return true end
    if keys.CUSTOM_CTRL_L then self:load_preset_dialog();  return true end
    return LaborPanel.super.onInput(self, keys)
end

-- ============================================================
-- PresetDialog: modal window to pick and apply a saved preset.
-- ============================================================

PresetDialog = defclass(PresetDialog, gui.ZScreen)
PresetDialog.ATTRS{
    focus_path = 'dwarf-therapist/preset-dialog',
    choices    = DEFAULT_NIL,
    on_apply   = DEFAULT_NIL,
}

function PresetDialog:init()
    local dlg = self
    self:addviews{
        widgets.Window{
            frame_title = 'Load Preset',
            frame       = {t=4, l=8, b=4, r=8},
            resizable   = false,
            subviews    = {},
        },
    }
    local win = self.subviews[1]
    win:addviews{
        widgets.FilteredList{
            view_id   = 'list',
            frame     = {t=0, b=2, l=0, r=0},
            choices   = self.choices,
            on_submit = function(_, choice)
                if dlg.on_apply then dlg.on_apply(choice.preset) end
                dlg:dismiss()
            end,
        },
        widgets.HotkeyLabel{
            frame       = {b=0, l=0},
            label       = 'Cancel',
            key         = 'LEAVESCREEN',
            on_activate = function() dlg:dismiss() end,
        },
    }
end

function PresetDialog:onDismiss() end

-- ============================================================
-- SummaryPanel: fortress-wide labor coverage at a glance.
-- ============================================================

SummaryPanel = defclass(SummaryPanel, widgets.Panel)

function SummaryPanel:init()
    self:addviews{
        widgets.Label{
            frame    = {t=0, l=0, h=1},
            text     = 'Fortress labor coverage',
            text_pen = COLOR_YELLOW,
        },
        widgets.FilteredList{
            view_id          = 'list',
            frame            = {t=2, l=0, b=2},
            edit_ignore_keys = {'CUSTOM_CTRL_R', 'CUSTOM_CTRL_X'},
        },
        widgets.HotkeyLabel{
            frame       = {b=0, l=0},
            label       = 'Refresh',
            key         = 'CUSTOM_CTRL_R',
            on_activate = function() self:rebuild() end,
        },
    }
    self:rebuild()
end

function SummaryPanel:rebuild()
    local citizens = get_citizens()
    local choices  = {}

    for _, labor in ipairs(LABORS) do
        local assigned = 0
        local skilled  = {}

        for _, u in ipairs(citizens) do
            if u.status.labors[labor.id] then
                assigned = assigned + 1
            end
            if labor.skill_id ~= df.job_skill.NONE and u.status.current_soul then
                local entry = utils.binsearch(
                    u.status.current_soul.skills, labor.skill_id, 'id')
                if entry and entry.rating >= 0 then
                    table.insert(skilled, {unit=u, rating=entry.rating})
                end
            end
        end

        table.sort(skilled, function(a, b) return a.rating > b.rating end)

        local top_str = ''
        for i = 1, math.min(2, #skilled) do
            if i > 1 then top_str = top_str .. ', ' end
            top_str = top_str
                .. dfhack.units.getReadableName(skilled[i].unit)
                .. ' [' .. skill_rating_caption(skilled[i].rating) .. ']'
        end

        local count_pen = assigned == 0 and COLOR_LIGHTRED
                       or assigned <= 2  and COLOR_YELLOW
                       or COLOR_GREY

        table.insert(choices, {
            text = {
                {text = string.format('%-22s', labor.name), pen = COLOR_WHITE},
                {text = string.format('(%2d) ', assigned),  pen = count_pen},
                {text = top_str,                            pen = COLOR_GREY},
            },
            search_key = labor.name:lower(),
        })
    end

    self.subviews.list:setChoices(choices)
end

-- ============================================================
-- MilitaryPanel: squad membership and combat skill summary.
-- ============================================================

MilitaryPanel = defclass(MilitaryPanel, widgets.Panel)
MilitaryPanel.ATTRS{ unit = DEFAULT_NIL }

function MilitaryPanel:init()
    self:addviews{
        widgets.Label{
            view_id  = 'header',
            frame    = {t=0, l=0, h=1},
            text     = 'Select a dwarf.',
            text_pen = COLOR_GREY,
        },
        widgets.Label{
            view_id = 'squad_info',
            frame   = {t=1, l=0, h=1},
            text    = '',
        },
        widgets.FilteredList{
            view_id          = 'list',
            frame            = {t=3, l=0, b=0},
            edit_ignore_keys = {'CUSTOM_CTRL_X'},
        },
    }
end

function MilitaryPanel:set_unit(unit)
    self.unit = unit
    self.subviews.header:setText(unit and unit_display_name(unit) or 'Select a dwarf.')
    self:rebuild()
end

function MilitaryPanel:rebuild()
    if not self.unit then
        self.subviews.squad_info:setText('')
        self.subviews.list:setChoices({})
        return
    end

    local u = self.unit

    -- Squad info
    local squad_str = 'Squad: None'
    if u.military.squad_id ~= -1 then
        local ok, squad = pcall(function() return df.squad.find(u.military.squad_id) end)
        if ok and squad then
            local name = dfhack.translation.translateName(squad.name, true)
            if squad.alias ~= '' then
                name = name .. ' (' .. squad.alias .. ')'
            end
            squad_str = 'Squad: ' .. name
                .. '  Pos: ' .. (u.military.squad_position + 1)
        end
    end
    self.subviews.squad_info:setText({text = squad_str, pen = COLOR_WHITE})

    -- Combat skills
    local choices = {}
    if u.status.current_soul then
        local u_skills = u.status.current_soul.skills
        for _, sk in ipairs(MILITARY_SKILLS) do
            local entry  = utils.binsearch(u_skills, sk.id, 'id')
            local rating = entry and entry.rating or -1
            local pen    = rating >= 0 and skill_pen(rating) or COLOR_DARKGREY
            local rstr   = rating >= 0 and skill_rating_caption(rating) or 'unlearned'
            table.insert(choices, {
                text = {
                    {text = string.format('%-22s', sk.caption), pen = pen},
                    {text = rstr,                               pen = pen},
                },
                search_key = sk.caption:lower(),
            })
        end
    end
    self.subviews.list:setChoices(choices)
end

-- ============================================================
-- WorkDetailsPanel: which work details this dwarf belongs to.
-- ============================================================

WorkDetailsPanel = defclass(WorkDetailsPanel, widgets.Panel)
WorkDetailsPanel.ATTRS{ unit = DEFAULT_NIL }

function WorkDetailsPanel:init()
    self:addviews{
        widgets.Label{
            view_id  = 'header',
            frame    = {t=0, l=0, h=1},
            text     = 'Select a dwarf.',
            text_pen = COLOR_GREY,
        },
        widgets.FilteredList{
            view_id          = 'list',
            frame            = {t=2, l=0, b=0},
            edit_ignore_keys = {'CUSTOM_CTRL_X'},
        },
    }
end

function WorkDetailsPanel:set_unit(unit)
    self.unit = unit
    self.subviews.header:setText(unit and unit_display_name(unit) or 'Select a dwarf.')
    self:rebuild()
end

function WorkDetailsPanel:rebuild()
    local choices = {}
    if not self.unit then
        self.subviews.list:setChoices(choices)
        return
    end
    local uid = self.unit.id
    local ok, work_details = pcall(function()
        return df.global.plotinfo.labor_info.work_details
    end)
    if not ok or not work_details then
        self.subviews.list:setChoices(choices)
        return
    end
    for _, wd in ipairs(work_details) do
        local assigned = false
        for _, wuid in ipairs(wd.assigned_units) do
            if wuid == uid then assigned = true; break end
        end
        table.insert(choices, {
            text = {
                {text = assigned and '[x] ' or '[ ] ',
                 pen  = assigned and COLOR_GREEN or COLOR_GREY},
                {text = wd.name, pen = COLOR_WHITE},
            },
            search_key = wd.name:lower(),
        })
    end
    self.subviews.list:setChoices(choices)
end

-- ============================================================
-- PreferencesPanel: food, material, creature and other likes.
-- ============================================================

PreferencesPanel = defclass(PreferencesPanel, widgets.Panel)
PreferencesPanel.ATTRS{ unit = DEFAULT_NIL }

local function pref_describe(pref)
    local ptype = df.unitpref_type[pref.type] or tostring(pref.type)
    local detail = ''
    local ok, result = pcall(function()
        if pref.type == df.unitpref_type.LikeCreature then
            local cr = df.creature_raw.find(pref.creature_id)
            if cr then return cr.name[0] end
        elseif pref.type == df.unitpref_type.LikePlant then
            local pl = df.plant_raw.find(pref.plant_id)
            if pl then return pl.name end
        elseif pref.type == df.unitpref_type.LikeItem then
            local idef = dfhack.items.getSubtypeDef(pref.item_type, pref.item_subtype)
            if idef then return idef.name end
            return df.item_type[pref.item_type] or ''
        elseif pref.type == df.unitpref_type.LikeMaterial then
            local mi = dfhack.matinfo.decode(pref.mattype, pref.matindex)
            if mi then
                local sn = mi.material.state_name
                return sn and (sn.Solid or sn.Liquid or '') or ''
            end
        elseif pref.type == df.unitpref_type.LikeFood
            or pref.type == df.unitpref_type.HateFood then
            local mi = dfhack.matinfo.decode(pref.mattype, pref.matindex)
            if mi then
                local sn = mi.material.state_name
                return sn and (sn.Liquid or sn.Solid or '') or ''
            end
            return df.item_type[pref.item_type] or ''
        end
        return ''
    end)
    if ok and result then detail = result end
    return ptype, detail
end

function PreferencesPanel:init()
    self:addviews{
        widgets.Label{
            view_id  = 'header',
            frame    = {t=0, l=0, h=1},
            text     = 'Select a dwarf.',
            text_pen = COLOR_GREY,
        },
        widgets.FilteredList{
            view_id          = 'list',
            frame            = {t=2, l=0, b=0},
            edit_ignore_keys = {'CUSTOM_CTRL_X'},
        },
    }
end

function PreferencesPanel:set_unit(unit)
    self.unit = unit
    self.subviews.header:setText(unit and unit_display_name(unit) or 'Select a dwarf.')
    self:rebuild()
end

function PreferencesPanel:rebuild()
    local choices = {}
    if self.unit and self.unit.status.current_soul then
        for _, pref in ipairs(self.unit.status.current_soul.preferences) do
            local ptype, detail = pref_describe(pref)
            local text_str = detail ~= '' and (ptype .. ': ' .. detail) or ptype
            local pen = ptype:find('Hate') and COLOR_LIGHTRED or COLOR_WHITE
            table.insert(choices, {
                text = {{text = text_str, pen = pen}},
                search_key = text_str:lower(),
            })
        end
    end
    self.subviews.list:setChoices(choices)
end

-- ============================================================
-- DwarfPanel: citizen list with profession, job, and sort.
-- ============================================================

DwarfPanel = defclass(DwarfPanel, widgets.Panel)
DwarfPanel.ATTRS{ on_select = DEFAULT_NIL }

function DwarfPanel:init()
    self:addviews{
        widgets.Label{
            frame    = {t=0, l=0, h=1},
            text     = 'Dwarves',
            text_pen = COLOR_YELLOW,
        },
        widgets.FilteredList{
            view_id          = 'list',
            frame            = {t=2, l=0, b=4},
            row_height       = 3,
            edit_ignore_keys = {
                'CUSTOM_CTRL_S', 'CUSTOM_CTRL_R',
                'CUSTOM_CTRL_F', 'CUSTOM_CTRL_Z', 'CUSTOM_CTRL_C', 'CUSTOM_CTRL_V',
                'CUSTOM_CTRL_P', 'CUSTOM_CTRL_L', 'CUSTOM_CTRL_A', 'CUSTOM_CTRL_X',
            },
            on_select        = function(_, choice)
                if self.on_select then self.on_select(choice.unit) end
            end,
        },
        widgets.CycleHotkeyLabel{
            view_id   = 'sort_mode',
            frame     = {b=2, l=0},
            key       = 'CUSTOM_CTRL_S',
            label     = 'Sort: ',
            options   = {
                {label = 'Name',       value = 'name'},
                {label = 'Profession', value = 'prof'},
                {label = 'Unhappy',    value = 'stress'},
                {label = 'Idle first', value = 'idle'},
            },
            on_change = function() self:refresh() end,
        },
        widgets.HotkeyLabel{
            frame       = {b=0, l=0},
            label       = 'Refresh list',
            key         = 'CUSTOM_CTRL_R',
            on_activate = function() self:refresh() end,
        },
    }
    self:refresh()
end

function DwarfPanel:refresh()
    local sort = self.subviews.sort_mode:getOptionValue()
    local raw  = {}

    for _, unit in ipairs(get_citizens()) do
        local name   = unit_display_name(unit)
        local prof   = dfhack.units.getProfessionName(unit)
        local soul   = unit.status.current_soul
        local stress = soul and soul.personality.stress or 0
        local job    = unit.job.current_job
        local idle   = job == nil

        local _, name_pen = stress_info(stress)
        local job_str = idle and 'Idle'
            or (df.job_type.attrs[job.job_type] and df.job_type.attrs[job.job_type].caption or 'Working')
        local job_pen = idle and COLOR_DARKGREY or COLOR_WHITE

        table.insert(raw, {
            text = {
                {text = name,          pen = name_pen},
                NEWLINE,
                {text = '  ' .. prof,  pen = COLOR_GREY},
                NEWLINE,
                {text = '  ' .. job_str, pen = job_pen},
            },
            search_key  = (name .. ' ' .. prof):lower(),
            unit        = unit,
            sort_name   = name:lower(),
            sort_prof   = prof:lower(),
            sort_stress = stress,
            sort_idle   = idle,
        })
    end

    if sort == 'name' then
        table.sort(raw, function(a,b) return a.sort_name < b.sort_name end)
    elseif sort == 'prof' then
        table.sort(raw, function(a,b)
            if a.sort_prof ~= b.sort_prof then return a.sort_prof < b.sort_prof end
            return a.sort_name < b.sort_name
        end)
    elseif sort == 'stress' then
        table.sort(raw, function(a,b) return a.sort_stress > b.sort_stress end)
    elseif sort == 'idle' then
        table.sort(raw, function(a,b)
            if a.sort_idle ~= b.sort_idle then return a.sort_idle end
            return a.sort_name < b.sort_name
        end)
    end

    self.subviews.list:setChoices(raw)
    if #raw > 0 and self.on_select then
        self.on_select(raw[1].unit)
    end
end

function DwarfPanel:select_unit(unit)
    local choices = self.subviews.list:getChoices()
    for i, choice in ipairs(choices) do
        if choice.unit == unit then
            self.subviews.list.list:setSelected(i)
            if self.on_select then self.on_select(unit) end
            return
        end
    end
end

-- ============================================================
-- TherapistWindow
-- ============================================================

TherapistWindow = defclass(TherapistWindow, widgets.Window)
TherapistWindow.ATTRS{
    frame_title = 'Dwarf Therapist',
    frame       = {t=2, l=2, r=2, b=2},
    resizable   = true,
    resize_min  = {w=72, h=28},
}

function TherapistWindow:init()
    -- Restore saved window position if available.
    local c = get_cfg()
    if c.data.frame then
        for k, v in pairs(c.data.frame) do
            self.frame[k] = v
        end
    end

    local DWARF_PANE_WIDTH = 28
    local RIGHT_LEFT       = DWARF_PANE_WIDTH + 1

    local labor_panel   = LaborPanel{      view_id='labors'      }
    local skill_panel   = SkillsPanel{     view_id='skills'      }
    local needs_panel   = NeedsPanel{      view_id='needs'       }
    local attrs_panel   = AttrsPanel{      view_id='attrs'       }
    local person_panel  = PersonalityPanel{view_id='personality' }
    local summary_panel = SummaryPanel{    view_id='summary'     }
    local mil_panel     = MilitaryPanel{   view_id='military'    }
    local work_panel    = WorkDetailsPanel{view_id='work'        }
    local pref_panel    = PreferencesPanel{view_id='prefs'       }

    local function set_unit(unit)
        self.current_unit = unit
        labor_panel:set_unit(unit)
        skill_panel:set_unit(unit)
        needs_panel:set_unit(unit)
        attrs_panel:set_unit(unit)
        person_panel:set_unit(unit)
        mil_panel:set_unit(unit)
        work_panel:set_unit(unit)
        pref_panel:set_unit(unit)
    end

    local dwarf_panel = DwarfPanel{
        view_id   = 'dwarves',
        frame     = {t=0, l=0, b=0, w=DWARF_PANE_WIDTH},
        on_select = set_unit,
    }

    labor_panel.on_find_best = function(unit)
        dwarf_panel:select_unit(unit)
        set_unit(unit)
    end

    self:addviews{
        dwarf_panel,
        widgets.Divider{
            frame       = {t=0, l=DWARF_PANE_WIDTH, b=0, w=1},
            frame_style = gui.FRAME_INTERIOR,
            interior    = true,
        },
        widgets.TabBar{
            view_id      = 'tabs',
            frame        = {t=0, l=RIGHT_LEFT, h=4, r=0},
            labels       = {
                'Labors','Skills','Needs','Attrs',
                'Persona','Summary','Military','Work','Prefs',
            },
            on_select    = function(idx) self.subviews.pages:setSelected(idx) end,
            get_cur_page = function() return self.subviews.pages:getSelected() end,
        },
        widgets.Pages{
            view_id  = 'pages',
            frame    = {t=4, l=RIGHT_LEFT, b=0, r=0},
            subviews = {
                labor_panel, skill_panel, needs_panel,
                attrs_panel, person_panel, summary_panel,
                mil_panel, work_panel, pref_panel,
            },
        },
    }
end

function TherapistWindow:export_tab()
    local tab    = self.subviews.pages:getSelected()
    local citizens = get_citizens()

    local function base(u)
        return {unit_display_name(u), dfhack.units.getProfessionName(u)}
    end

    local label, headers, rows, path

    -- ---- Tab 1: Labors ----------------------------------------
    if tab == 1 then
        label   = 'labors'
        headers = {'Name', 'Profession'}
        for _, labor in ipairs(LABORS) do table.insert(headers, labor.name) end
        rows = {}
        for _, u in ipairs(citizens) do
            local row = base(u)
            for _, labor in ipairs(LABORS) do
                table.insert(row, u.status.labors[labor.id] and 1 or 0)
            end
            table.insert(rows, row)
        end

    -- ---- Tab 2: Skills ----------------------------------------
    elseif tab == 2 then
        label = 'skills'
        local skill_list = {}
        for skill_id, _ in ipairs(df.job_skill) do
            if skill_id ~= df.job_skill.NONE then
                table.insert(skill_list, {
                    id      = skill_id,
                    caption = df.job_skill.attrs[skill_id].caption,
                })
            end
        end
        headers = {'Name', 'Profession'}
        for _, sk in ipairs(skill_list) do table.insert(headers, sk.caption) end
        rows = {}
        for _, u in ipairs(citizens) do
            local row = base(u)
            if u.status.current_soul then
                local u_skills = u.status.current_soul.skills
                for _, sk in ipairs(skill_list) do
                    local entry = utils.binsearch(u_skills, sk.id, 'id')
                    table.insert(row, entry and entry.rating or '')
                end
            else
                for _ in ipairs(skill_list) do table.insert(row, '') end
            end
            table.insert(rows, row)
        end

    -- ---- Tab 3: Needs -----------------------------------------
    elseif tab == 3 then
        label = 'needs'
        local need_ids, need_set = {}, {}
        for _, u in ipairs(citizens) do
            if u.status.current_soul then
                for _, need in ipairs(u.status.current_soul.personality.needs) do
                    if not need_set[need.id] then
                        need_set[need.id] = true
                        table.insert(need_ids, need.id)
                    end
                end
            end
        end
        table.sort(need_ids)
        headers = {'Name', 'Stress'}
        for _, nid in ipairs(need_ids) do
            table.insert(headers, df.need_type[nid] or tostring(nid))
        end
        rows = {}
        for _, u in ipairs(citizens) do
            local soul = u.status.current_soul
            local row  = {unit_display_name(u), soul and soul.personality.stress or ''}
            local fmap = {}
            if soul then
                for _, need in ipairs(soul.personality.needs) do
                    fmap[need.id] = need.focus_level
                end
            end
            for _, nid in ipairs(need_ids) do
                table.insert(row, fmap[nid] ~= nil and fmap[nid] or '')
            end
            table.insert(rows, row)
        end

    -- ---- Tab 4: Attributes ------------------------------------
    elseif tab == 4 then
        label = 'attributes'
        local phys_cols, ment_cols = {}, {}
        for i, raw in ipairs(df.physical_attribute_type) do
            table.insert(phys_cols, {i=i, name=raw:gsub('_',' '):lower():gsub('^%l',string.upper)})
        end
        for i, raw in ipairs(df.mental_attribute_type) do
            table.insert(ment_cols, {i=i, name=raw:gsub('_',' '):lower():gsub('^%l',string.upper)})
        end
        headers = {'Name', 'Profession'}
        for _, a in ipairs(phys_cols) do table.insert(headers, a.name) end
        for _, a in ipairs(ment_cols) do table.insert(headers, a.name) end
        rows = {}
        for _, u in ipairs(citizens) do
            local row = base(u)
            for _, a in ipairs(phys_cols) do
                local v = u.body.physical_attrs[a.i]
                table.insert(row, v and v.value or '')
            end
            if u.status.current_soul then
                for _, a in ipairs(ment_cols) do
                    local v = u.status.current_soul.mental_attrs[a.i]
                    table.insert(row, v and v.value or '')
                end
            else
                for _ in ipairs(ment_cols) do table.insert(row, '') end
            end
            table.insert(rows, row)
        end

    -- ---- Tab 5: Personality (traits) --------------------------
    elseif tab == 5 then
        label = 'traits'
        local facet_cols = {}
        for i, raw in ipairs(df.personality_facet_type) do
            table.insert(facet_cols, {i=i, name=raw:gsub('_',' '):lower():gsub('^%l',string.upper)})
        end
        headers = {'Name', 'Profession'}
        for _, f in ipairs(facet_cols) do table.insert(headers, f.name) end
        rows = {}
        for _, u in ipairs(citizens) do
            local row = base(u)
            if u.status.current_soul then
                local traits = u.status.current_soul.personality.traits
                for _, f in ipairs(facet_cols) do
                    table.insert(row, traits[f.i] ~= nil and traits[f.i] or '')
                end
            else
                for _ in ipairs(facet_cols) do table.insert(row, '') end
            end
            table.insert(rows, row)
        end

    -- ---- Tab 6: Summary ---------------------------------------
    elseif tab == 6 then
        label   = 'summary'
        headers = {'Labor', 'Assigned', 'Top1 Name', 'Top1 Rating', 'Top2 Name', 'Top2 Rating'}
        rows    = {}
        for _, labor in ipairs(LABORS) do
            local assigned, skilled = 0, {}
            for _, u in ipairs(citizens) do
                if u.status.labors[labor.id] then assigned = assigned + 1 end
                if labor.skill_id ~= df.job_skill.NONE and u.status.current_soul then
                    local entry = utils.binsearch(u.status.current_soul.skills, labor.skill_id, 'id')
                    if entry and entry.rating >= 0 then
                        table.insert(skilled, {unit=u, rating=entry.rating})
                    end
                end
            end
            table.sort(skilled, function(a,b) return a.rating > b.rating end)
            local row = {labor.name, assigned}
            for i = 1, 2 do
                if skilled[i] then
                    table.insert(row, unit_display_name(skilled[i].unit))
                    table.insert(row, skill_rating_caption(skilled[i].rating))
                else
                    table.insert(row, ''); table.insert(row, '')
                end
            end
            table.insert(rows, row)
        end

    -- ---- Tab 7: Military --------------------------------------
    elseif tab == 7 then
        label   = 'military'
        headers = {'Name', 'Profession', 'Squad', 'Squad Position'}
        for _, sk in ipairs(MILITARY_SKILLS) do table.insert(headers, sk.caption) end
        rows = {}
        for _, u in ipairs(citizens) do
            local sq_name, sq_pos = '', ''
            if u.military.squad_id ~= -1 then
                local ok2, sq = pcall(function() return df.squad.find(u.military.squad_id) end)
                if ok2 and sq then
                    sq_name = dfhack.translation.translateName(sq.name, true)
                    if sq.alias ~= '' then sq_name = sq_name .. ' (' .. sq.alias .. ')' end
                    sq_pos  = u.military.squad_position + 1
                end
            end
            local row = {unit_display_name(u), dfhack.units.getProfessionName(u), sq_name, sq_pos}
            if u.status.current_soul then
                local u_skills = u.status.current_soul.skills
                for _, sk in ipairs(MILITARY_SKILLS) do
                    local entry = utils.binsearch(u_skills, sk.id, 'id')
                    table.insert(row, entry and entry.rating or '')
                end
            else
                for _ in ipairs(MILITARY_SKILLS) do table.insert(row, '') end
            end
            table.insert(rows, row)
        end

    -- ---- Tab 8: Work Details ----------------------------------
    elseif tab == 8 then
        label = 'work-details'
        local ok2, wds = pcall(function()
            return df.global.plotinfo.labor_info.work_details
        end)
        if not ok2 or not wds then
            dfhack.printerr('dwarf-therapist: cannot access work details')
            return
        end
        headers = {'Name', 'Profession'}
        for _, wd in ipairs(wds) do table.insert(headers, wd.name) end
        rows = {}
        for _, u in ipairs(citizens) do
            local row = base(u)
            local uid = u.id
            for _, wd in ipairs(wds) do
                local assigned = false
                for _, wuid in ipairs(wd.assigned_units) do
                    if wuid == uid then assigned = true; break end
                end
                table.insert(row, assigned and 1 or 0)
            end
            table.insert(rows, row)
        end

    -- ---- Tab 9: Preferences (one row per pref) ----------------
    elseif tab == 9 then
        label   = 'preferences'
        headers = {'Name', 'Profession', 'Type', 'Detail'}
        rows    = {}
        for _, u in ipairs(citizens) do
            if u.status.current_soul then
                local prefs = u.status.current_soul.preferences
                if #prefs == 0 then
                    table.insert(rows, {unit_display_name(u), dfhack.units.getProfessionName(u), '', ''})
                else
                    for _, pref in ipairs(prefs) do
                        local ptype, detail = pref_describe(pref)
                        table.insert(rows, {unit_display_name(u), dfhack.units.getProfessionName(u), ptype, detail})
                    end
                end
            end
        end
    end

    if not label then return end
    path = export_path(label)
    if write_csv(path, headers, rows) then
        dfhack.print('dwarf-therapist: exported ' .. label .. ' -> ' .. path .. '\n')
    end
end

function TherapistWindow:onInput(keys)
    if keys.CUSTOM_CTRL_X then
        self:export_tab()
        return true
    end
    return TherapistWindow.super.onInput(self, keys)
end

-- ============================================================
-- TherapistScreen
-- ============================================================

TherapistScreen = defclass(TherapistScreen, gui.ZScreen)
TherapistScreen.ATTRS{ focus_path = 'dwarf-therapist' }

function TherapistScreen:init()
    self:addviews{ TherapistWindow{} }
end

function TherapistScreen:onDismiss()
    -- Save window position.
    local win = self.subviews[1]
    if win then
        local c = get_cfg()
        c.data.frame = {
            t = win.frame.t, l = win.frame.l,
            r = win.frame.r, b = win.frame.b,
        }
        c:write()
    end
    view = nil
end

-- ============================================================
-- Entry point
-- ============================================================

if not dfhack.isMapLoaded() then
    qerror('A fortress map must be loaded to use Dwarf Therapist.')
end

view = view and view:raise() or TherapistScreen{}:show()
