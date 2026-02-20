-- gui/dwarf-therapist: Labor, skill, needs, attribute and personality manager.
-- Similar in spirit to Dwarf Therapist.
--
-- Usage:  gui/dwarf-therapist   (or Ctrl+Shift+T if keybinding is set)

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

-- Labor list: {name, id, skill_id} built once at load time.
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
-- Needs color helpers
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
            view_id = 'list',
            frame   = {t=3, l=0, b=0},
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
        {text = string.format('%-16s', s_label),        pen = s_pen},
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
            view_id = 'list',
            frame   = {t=2, l=0, b=0},
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
            -- Convert UPPER_CASE to Title Case
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
            key      = 'CUSTOM_A',
            label    = 'Show: ',
            options  = {
                {label = 'Traits',  value = 'traits'},
                {label = 'Thoughts', value = 'thoughts'},
            },
            on_change = function() self:rebuild() end,
        },
        widgets.FilteredList{
            view_id = 'list',
            frame   = {t=3, l=0, b=0},
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
            -- Only show non-neutral traits prominently; grey out near-50 ones.
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
        -- Sort most recent first.
        local sorted = {}
        for _, e in ipairs(emotions) do table.insert(sorted, e) end
        table.sort(sorted, function(a, b)
            if a.year ~= b.year then return a.year > b.year end
            return a.year_tick > b.year_tick
        end)
        for _, e in ipairs(sorted) do
            local emo  = df.emotion_type[e.type]    or '?'
            local tht  = df.unit_thought_type[e.thought] or '?'
            -- Positive relative_strength = good feeling, negative = bad.
            local pen  = (e.relative_strength or 0) >= 0 and COLOR_LIGHTGREEN or COLOR_LIGHTRED
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
            view_id = 'list',
            frame   = {t=2, l=0, b=2},
        },
        widgets.CycleHotkeyLabel{
            view_id   = 'filter_mode',
            frame     = {b=0, l=0},
            key       = 'CUSTOM_A',
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
-- and a "find best dwarf" hotkey.
-- ============================================================

LaborPanel = defclass(LaborPanel, widgets.Panel)
LaborPanel.ATTRS{
    unit         = DEFAULT_NIL,
    on_find_best = DEFAULT_NIL,   -- callback(unit) to select a dwarf externally
}

function LaborPanel:init()
    self:addviews{
        widgets.Label{
            view_id  = 'header',
            frame    = {t=0, l=0, h=1},
            text     = 'Select a dwarf.',
            text_pen = COLOR_GREY,
        },
        widgets.FilteredList{
            view_id   = 'list',
            frame     = {t=2, l=0, b=2},
            on_submit = function(_, choice) self:toggle_labor(choice.labor_id) end,
        },
        widgets.Label{
            frame = {b=0, l=0},
            text  = {
                {key='SELECT',    text=': Toggle  '},
                {key='CUSTOM_F',  text=': Find best dwarf'},
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
    -- Count assignments across all citizens.
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
            local enabled  = self.unit.status.labors[labor.id]
            local count    = counts[labor.id] or 0
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
    self.unit.status.labors[labor_id] = not self.unit.status.labors[labor_id]
    self:rebuild_list()
end

function LaborPanel:find_best_dwarf()
    local _, choice = self.subviews.list:getSelected()
    if not choice then return end

    -- Find the labor entry for this choice.
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
    if keys.CUSTOM_F then
        self:find_best_dwarf()
        return true
    end
    return LaborPanel.super.onInput(self, keys)
end

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
            view_id = 'list',
            frame   = {t=2, l=0, b=2},
        },
        widgets.HotkeyLabel{
            frame       = {b=0, l=0},
            label       = 'Refresh',
            key         = 'CUSTOM_R',
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
            if labor.skill_id ~= df.job_skill.NONE
               and u.status.current_soul then
                local entry  = utils.binsearch(
                    u.status.current_soul.skills, labor.skill_id, 'id')
                if entry and entry.rating >= 0 then
                    table.insert(skilled, {unit=u, rating=entry.rating})
                end
            end
        end

        table.sort(skilled, function(a, b) return a.rating > b.rating end)

        -- Build "top 2 skilled dwarves" string.
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
-- DwarfPanel: citizen list with profession and sort options.
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
            frame      = {t=2, l=0, b=4},
            row_height = 2,
            on_select  = function(_, choice)
                if self.on_select then self.on_select(choice.unit) end
            end,
        },
        widgets.CycleHotkeyLabel{
            view_id   = 'sort_mode',
            frame     = {b=2, l=0},
            key       = 'CUSTOM_S',
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
            key         = 'CUSTOM_R',
            on_activate = function() self:refresh() end,
        },
    }
    self:refresh()
end

function DwarfPanel:refresh()
    local sort = self.subviews.sort_mode:getOptionValue()
    local raw  = {}

    for _, unit in ipairs(get_citizens()) do
        local name  = unit_display_name(unit)
        local prof  = dfhack.units.getProfessionName(unit)
        local soul  = unit.status.current_soul
        local stress = soul and soul.personality.stress or 0
        local idle   = unit.job.current_job == nil

        -- Color the name by stress level.
        local _, name_pen = stress_info(stress)

        table.insert(raw, {
            text = {
                {text = name, pen = name_pen},
                NEWLINE,
                {text = '  ' .. prof, pen = COLOR_GREY},
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
        -- Most stressed first.
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

-- Select a specific unit in the list (used by "find best dwarf").
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
    resize_min  = {w=72, h=24},
}

function TherapistWindow:init()
    local DWARF_PANE_WIDTH = 28
    local RIGHT_LEFT       = DWARF_PANE_WIDTH + 1

    local labor_panel    = LaborPanel{     view_id='labors'      }
    local skill_panel    = SkillsPanel{    view_id='skills'      }
    local needs_panel    = NeedsPanel{     view_id='needs'       }
    local attrs_panel    = AttrsPanel{     view_id='attrs'       }
    local person_panel   = PersonalityPanel{ view_id='personality' }
    local summary_panel  = SummaryPanel{   view_id='summary'     }

    local function set_unit(unit)
        labor_panel:set_unit(unit)
        skill_panel:set_unit(unit)
        needs_panel:set_unit(unit)
        attrs_panel:set_unit(unit)
        person_panel:set_unit(unit)
        -- SummaryPanel is fortress-wide; no unit needed.
    end

    local dwarf_panel = DwarfPanel{
        view_id   = 'dwarves',
        frame     = {t=0, l=0, b=0, w=DWARF_PANE_WIDTH},
        on_select = set_unit,
    }

    -- Wire up "find best" so it navigates the dwarf list.
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
        -- h=4 gives room for two rows of 2-char-tall tabs.
        widgets.TabBar{
            view_id      = 'tabs',
            frame        = {t=0, l=RIGHT_LEFT, h=4, r=0},
            labels       = {'Labors','Skills','Needs','Attributes','Personality','Summary'},
            on_select    = function(idx) self.subviews.pages:setSelected(idx) end,
            get_cur_page = function() return self.subviews.pages:getSelected() end,
        },
        widgets.Pages{
            view_id  = 'pages',
            frame    = {t=4, l=RIGHT_LEFT, b=0, r=0},
            subviews = {
                labor_panel, skill_panel, needs_panel,
                attrs_panel, person_panel, summary_panel,
            },
        },
    }
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
    view = nil
end

-- ============================================================
-- Entry point
-- ============================================================

if not dfhack.isMapLoaded() then
    qerror('A fortress map must be loaded to use Dwarf Therapist.')
end

view = view and view:raise() or TherapistScreen{}:show()
