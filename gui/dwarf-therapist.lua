-- gui/dwarf-therapist: Labor, skill, and needs manager for citizen dwarves.
-- Similar in spirit to Dwarf Therapist.
--
-- Usage (from DFHack console):
--   gui/dwarf-therapist
-- Or press Ctrl+Shift+T (set in dfhack-config/init/dfhack.init)

local gui     = require('gui')
local widgets = require('gui.widgets')
local utils   = require('utils')

-- ============================================================
-- Data helpers
-- ============================================================

local function get_citizens()
    return dfhack.units.getCitizens(true)
end

local function unit_display_name(unit)
    return dfhack.units.getReadableName(unit)
end

-- Build a sorted {name, id, skill_id} list from the unit_labor enum once at
-- load time. skill_id is df.job_skill.NONE for labors with no associated skill.
local LABORS = (function()
    local list = {}
    for id, name in ipairs(df.unit_labor) do
        if id ~= df.unit_labor.NONE then
            table.insert(list, {
                name     = name,
                id       = id,
                skill_id = df.unit_labor.attrs[id].skill,
            })
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end)()

-- ============================================================
-- Shared skill helpers (used by LaborPanel and SkillsPanel)
-- ============================================================

local function skill_pen(rating)
    if rating >= df.skill_rating.Legendary then return COLOR_LIGHTGREEN end
    if rating >= 9 then return COLOR_GREEN  end   -- Master / High Master
    if rating >= 6 then return COLOR_YELLOW end   -- Expert / Professional / Accomplished
    if rating >= 3 then return COLOR_WHITE  end   -- Competent / Skilled / Proficient
    return COLOR_GREY                             -- Dabbling / Novice / Adequate
end

local function skill_rating_caption(rating)
    if rating < 0 then
        return '<unlearned>'
    elseif rating > df.skill_rating.Legendary then
        local bonus = rating - df.skill_rating.Legendary
        return df.skill_rating.attrs[df.skill_rating.Legendary].caption .. '+' .. bonus
    else
        return df.skill_rating.attrs[rating].caption
    end
end

-- ============================================================
-- Needs helpers
-- ============================================================

-- Stress level: lower (more negative) = happier.
local STRESS_LEVELS = {
    {threshold = -500000, label = 'Ecstatic',      pen = COLOR_LIGHTCYAN},
    {threshold =       0, label = 'Happy',          pen = COLOR_LIGHTGREEN},
    {threshold =   25000, label = 'Content',        pen = COLOR_GREEN},
    {threshold =   50000, label = 'Fine',           pen = COLOR_WHITE},
    {threshold =  125000, label = 'Unhappy',        pen = COLOR_YELLOW},
    {threshold =  200000, label = 'Very unhappy',   pen = COLOR_LIGHTRED},
}

local function stress_info(level)
    for _, s in ipairs(STRESS_LEVELS) do
        if level <= s.threshold then return s.label, s.pen end
    end
    return 'Miserable', COLOR_RED
end

-- Need focus_level: higher = more satisfied. Threshold from allneeds.lua.
local FOCUS_LEVELS = {
    {threshold =    300, label = 'Satisfied',        pen = COLOR_GREEN},
    {threshold =    100, label = 'Fine',             pen = COLOR_WHITE},
    {threshold =   -100, label = 'Okay',             pen = COLOR_GREY},
    {threshold =   -999, label = 'Unfulfilled',      pen = COLOR_YELLOW},
    {threshold =  -9999, label = 'Distracted',       pen = COLOR_LIGHTRED},
}

local function focus_info(focus_level)
    for _, f in ipairs(FOCUS_LEVELS) do
        if focus_level >= f.threshold then return f.label, f.pen end
    end
    return 'Badly distracted', COLOR_RED
end

-- ============================================================
-- NeedsPanel: stress level + per-need fulfillment, worst first.
-- ============================================================

NeedsPanel = defclass(NeedsPanel, widgets.Panel)
NeedsPanel.ATTRS{ unit = DEFAULT_NIL }

function NeedsPanel:init()
    self:addviews{
        widgets.Label{
            view_id  = 'header',
            frame    = {t=0, l=0, h=1},
            text     = 'Select a dwarf to view their needs.',
            text_pen = COLOR_GREY,
        },
        widgets.Label{
            view_id = 'stress',
            frame   = {t=1, l=0, h=1},
            text    = '',
        },
        widgets.FilteredList{
            view_id = 'list',
            frame   = {t=3, l=0, b=0},
        },
    }
end

function NeedsPanel:set_unit(unit)
    self.unit = unit
    self.subviews.header:setText(
        unit and unit_display_name(unit) or 'Select a dwarf to view their needs.')
    self:rebuild()
end

function NeedsPanel:rebuild()
    if not self.unit or not self.unit.status.current_soul then
        self.subviews.stress:setText('')
        self.subviews.list:setChoices({})
        return
    end

    local soul   = self.unit.status.current_soul.personality
    local s_label, s_pen = stress_info(soul.stress)

    self.subviews.stress:setText{
        'Mood: ',
        {text = string.format('%-16s', s_label), pen = s_pen},
        {text = string.format('(stress %d)', soul.stress), pen = COLOR_DARKGREY},
    }

    -- Collect needs and sort worst-first by focus_level.
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
-- SkillsPanel: read-only view of a dwarf's skill levels.
-- ============================================================

SkillsPanel = defclass(SkillsPanel, widgets.Panel)
SkillsPanel.ATTRS{ unit = DEFAULT_NIL }

function SkillsPanel:init()
    self:addviews{
        widgets.Label{
            view_id  = 'header',
            frame    = {t=0, l=0, h=1},
            text     = 'Select a dwarf to view their skills.',
            text_pen = COLOR_GREY,
        },
        widgets.FilteredList{
            view_id = 'list',
            frame   = {t=2, l=0, b=2},
        },
        widgets.CycleHotkeyLabel{
            view_id  = 'filter_mode',
            frame    = {b=0, l=0},
            key      = 'CUSTOM_A',
            label    = 'Show: ',
            options  = {
                {label='Learned only', value=false},
                {label='All skills',   value=true},
            },
            on_change = function() self:rebuild_list() end,
        },
    }
end

function SkillsPanel:set_unit(unit)
    self.unit = unit
    self.subviews.header:setText(
        unit and unit_display_name(unit) or 'Select a dwarf to view their skills.')
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
-- LaborPanel: filterable, togglable list of labors.
-- Shows skill hints and per-labor assignment counts.
-- ============================================================

LaborPanel = defclass(LaborPanel, widgets.Panel)
LaborPanel.ATTRS{ unit = DEFAULT_NIL }

function LaborPanel:init()
    self:addviews{
        widgets.Label{
            view_id  = 'header',
            frame    = {t=0, l=0, h=1},
            text     = 'Select a dwarf to view their labors.',
            text_pen = COLOR_GREY,
        },
        widgets.FilteredList{
            view_id   = 'list',
            frame     = {t=2, l=0, b=2},
            on_submit = function(_, choice)
                self:toggle_labor(choice.labor_id)
            end,
        },
        widgets.HotkeyLabel{
            frame = {b=0, l=0},
            label = 'Toggle labor',
            key   = 'SELECT',
        },
    }
end

function LaborPanel:set_unit(unit)
    self.unit = unit
    self.subviews.header:setText(
        unit and unit_display_name(unit) or 'Select a dwarf to view their labors.')
    self:rebuild_list()
end

function LaborPanel:rebuild_list()
    -- Precompute how many citizens have each labor enabled.
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
            local enabled = self.unit.status.labors[labor.id]
            local count   = counts[labor.id] or 0

            -- Skill hint: if this labor has an associated skill, show the
            -- dwarf's rating in that skill and color the labor name by it.
            local skill_str = '              '  -- 14 chars of padding
            local name_pen  = COLOR_WHITE
            if labor.skill_id ~= df.job_skill.NONE and u_skills then
                local entry  = utils.binsearch(u_skills, labor.skill_id, 'id')
                local rating = entry and entry.rating or -1
                if rating >= 0 then
                    skill_str = string.format('%-14s', skill_rating_caption(rating))
                    name_pen  = skill_pen(rating)
                end
            end

            -- Coverage warning: 0 dwarves assigned → red count.
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
    self.unit.status.labors[labor_id] = not self.unit.status.labors[labor_id]
    self:rebuild_list()
end

-- ============================================================
-- DwarfPanel: filterable list of citizens with profession.
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
            view_id    = 'list',
            frame      = {t=2, l=0, b=2},
            row_height = 2,
            on_select  = function(_, choice)
                if self.on_select then self.on_select(choice.unit) end
            end,
        },
        widgets.HotkeyLabel{
            frame       = {b=0, l=0},
            label       = 'Refresh list',
            key         = 'CUSTOM_R',
            on_activate = function() self:refresh() end,
        },
    }
    self:refresh()
end

function DwarfPanel:refresh()
    local choices = {}
    for _, unit in ipairs(get_citizens()) do
        local name = unit_display_name(unit)
        local prof = dfhack.units.getProfessionName(unit)
        table.insert(choices, {
            text = {
                name,
                NEWLINE,
                {text = '  ' .. prof, pen = COLOR_GREY},
            },
            search_key = (name .. ' ' .. prof):lower(),
            unit       = unit,
        })
    end
    self.subviews.list:setChoices(choices)
    if #choices > 0 and self.on_select then
        self.on_select(choices[1].unit)
    end
end

-- ============================================================
-- TherapistWindow: left = dwarf list, right = tabbed panels.
-- ============================================================

TherapistWindow = defclass(TherapistWindow, widgets.Window)
TherapistWindow.ATTRS{
    frame_title = 'Dwarf Therapist',
    frame       = {t=2, l=2, r=2, b=2},
    resizable   = true,
    resize_min  = {w=70, h=20},
}

function TherapistWindow:init()
    local DWARF_PANE_WIDTH = 28
    local RIGHT_LEFT       = DWARF_PANE_WIDTH + 1

    local labor_panel = LaborPanel{ view_id='labors' }
    local skill_panel = SkillsPanel{ view_id='skills' }
    local needs_panel = NeedsPanel{ view_id='needs' }

    local function set_unit(unit)
        labor_panel:set_unit(unit)
        skill_panel:set_unit(unit)
        needs_panel:set_unit(unit)
    end

    self:addviews{
        DwarfPanel{
            view_id   = 'dwarves',
            frame     = {t=0, l=0, b=0, w=DWARF_PANE_WIDTH},
            on_select = set_unit,
        },
        widgets.Divider{
            frame       = {t=0, l=DWARF_PANE_WIDTH, b=0, w=1},
            frame_style = gui.FRAME_INTERIOR,
            interior    = true,
        },
        widgets.TabBar{
            view_id      = 'tabs',
            frame        = {t=0, l=RIGHT_LEFT, h=2, r=0},
            labels       = {'Labors', 'Skills', 'Needs'},
            on_select    = function(idx) self.subviews.pages:setSelected(idx) end,
            get_cur_page = function() return self.subviews.pages:getSelected() end,
        },
        widgets.Pages{
            view_id  = 'pages',
            frame    = {t=2, l=RIGHT_LEFT, b=0, r=0},
            subviews = {labor_panel, skill_panel, needs_panel},
        },
    }
end

-- ============================================================
-- TherapistScreen: ZScreen overlay wrapper.
-- ============================================================

TherapistScreen = defclass(TherapistScreen, gui.ZScreen)
TherapistScreen.ATTRS{ focus_path = 'dwarf-therapist' }

function TherapistScreen:init()
    self:addviews{ TherapistWindow{} }
end

function TherapistScreen:onDismiss()
    view = nil
end

-- ============================================================
-- Entry point
-- ============================================================

if not dfhack.isMapLoaded() then
    qerror('A fortress map must be loaded to use Dwarf Therapist.')
end

view = view and view:raise() or TherapistScreen{}:show()
