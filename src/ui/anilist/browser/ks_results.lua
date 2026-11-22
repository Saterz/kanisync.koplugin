local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Filters = require("ui/anilist/filters/ks_filters")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local Menu = require("ui/widget/menu")
local Row = require("ui/anilist/browser/ks_result_row")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local T = require("ffi/util").template
local _ = require("gettext")
local Screen = Device.screen

local FilterButton = InputContainer:extend{}

function FilterButton:init()
    self[1] = FrameContainer:new {
        padding = 0, radius = Size.radius.button, bordersize = Size.border.button,
        focusable = true, focus_inner_border = true,
        CenterContainer:new {
            dimen = Geom:new { w = self.side - 2 * Size.border.button, h = self.side - 2 * Size.border.button },
            IconWidget:new { file = self.file, width = Screen:scaleBySize(24), height = Screen:scaleBySize(24) },
        },
    }
    self.dimen = self[1]:getSize()
    self.ges_events = { TapSelect = { GestureRange:new { ges = "tap", range = self.dimen } } }
end

function FilterButton:onTapSelect()
    self.callback()
    return true
end

local Header = VerticalGroup:extend{}

function Header:getHeight()
    return self:getSize().h
end

function Header:generateVerticalLayout()
    local layout = self.title_bar:generateVerticalLayout()
    layout[#layout + 1] = { self.other_tab }
    for index = 1, #self.controls do
        layout[#layout + 1] = { self.controls[index] }
    end
    return layout
end

local Results = Menu:extend {
    covers_fullscreen = true, stop_events_propagation = true,
    is_borderless = true, is_popout = false, is_enable_shortcut = false,
    items_font_size = 20,
}

function Results:init()
    local width, height = Screen:getWidth(), Screen:getHeight()
    local controller = self.controller
    local gap = Size.padding.large
    local title_bar = TitleBar:new {
        width = width, fullscreen = true, align = "center",
        title = _("AniList"),
        close_callback = function() self:onClose() end, show_parent = self,
    }
    self.tabs = {}
    local other_tab
    local tab_width = math.floor((width - 3 * gap) / 2)
    local function tab(mode, label)
        local active = controller.mode == mode
        local button = Button:new {
            text = label, width = tab_width, radius = Size.radius.button,
            background = active and Blitbuffer.COLOR_LIGHT_GRAY or nil,
            show_parent = self, callback = function() controller:switchMode(mode) end,
        }
        if active then button:disableWithoutDimming()
        else other_tab = button end
        self.tabs[mode] = button
        return button
    end
    local catalog_tab = tab("catalog", _("Catalog"))
    local library_tab = tab("library", _("Library"))
    local navbar = HorizontalGroup:new {
        HorizontalSpan:new { width = gap }, catalog_tab,
        HorizontalSpan:new { width = gap }, library_tab,
    }
    self.search_button = Button:new {
        text = "", align = "left", width = width - 2 * gap, radius = Size.radius.button,
        avoid_text_truncation = false, show_parent = self, callback = function() controller:openSearch() end,
    }
    local side = self.search_button:getSize().h
    self.search_width = width - 3 * gap - side
    self.filter_button = FilterButton:new {
        side = side, file = controller.plugin.path .. "/ui/anilist/browser/sliders-horizontal.svg",
        callback = function() controller:openFilters() end,
    }
    local row = HorizontalGroup:new {
        HorizontalSpan:new { width = gap }, self.filter_button,
        HorizontalSpan:new { width = gap }, self.search_button,
    }
    local face = Font:getFace("smallinfofont", 15)
    self.filter_summary = TextBoxWidget:new {
        text = "", width = width - 2 * gap, face = face, fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        height = 2 * math.floor(1.15 * face.size + 0.5), line_height = 0.15,
        height_overflow_show_ellipsis = true,
    }
    local summary_row = HorizontalGroup:new {
        HorizontalSpan:new { width = gap }, self.filter_summary, HorizontalSpan:new { width = gap },
    }
    self.custom_title_bar = Header:new {
        align = "left", title_bar = title_bar, controls = { self.filter_button, self.search_button }, other_tab = other_tab,
        title_bar, navbar, VerticalSpan:new { width = gap }, row, VerticalSpan:new { width = Size.padding.small },
        summary_row, VerticalSpan:new { width = gap },
    }
    self.summary_row = summary_row
    self.search_row = row
    self:updateSearchLabel()
    local available = height - self.custom_title_bar:getHeight() - Screen:scaleBySize(55)
    self.items_per_page = math.max(1, math.min(8, math.floor(available / Screen:scaleBySize(110))))
    Menu.init(self)
end

function Results:updateItems(select_number, no_recalculate_dimen)
    self:cancelCoverLoad()
    self.item_group:clear()
    self.page_info:resetLayout()
    self.return_button:resetLayout()
    self.content_group:resetLayout()
    self.layout = {}
    self:_recalculateDimen(no_recalculate_dimen)

    local offset = (self.page - 1) * self.perpage
    for index = 1, self.perpage do
        local entry = self.item_table[offset + index]
        if not entry then break end
        local row = Row:new { entry = entry, dimen = self.item_dimen:copy(), menu = self }
        self.item_group[index] = row
        self.layout[index] = { row }
    end
    self:updatePageInfo(select_number)
    self:mergeTitleBarIntoLayout()
    self.next_cover = 1
    UIManager:setDirty(self, "ui")
end

function Results:cancelCoverLoad()
    if self.cover_task then
        UIManager:unschedule(self.cover_task)
        self.cover_task = nil
    end
end

function Results:scheduleCoverLoad()
    if self.cover_task or UIManager:getTopmostVisibleWidget() ~= self then return end
    while self.next_cover <= #self.item_group do
        local row = self.item_group[self.next_cover]
        self.next_cover = self.next_cover + 1
        if row.entry.cover_url then
            self.cover_task = function()
                self.cover_task = nil
                if UIManager:getTopmostVisibleWidget() ~= self then
                    -- Retry this row when the results are visible and repainted again.
                    self.next_cover = self.next_cover - 1
                    return
                end
                if row:loadCover(self.controller.api.downloadImage) then
                    UIManager:setDirty(self, "ui", row.dimen)
                end
                self:scheduleCoverLoad()
            end
            UIManager:scheduleIn(0.08, self.cover_task)
            return
        end
    end
end

function Results:paintTo(bb, x, y)
    Menu.paintTo(self, bb, x, y)
    self:scheduleCoverLoad()
end

function Results:updateSearchLabel()
    local options = self.controller.options
    self.search_button:setText(options.search or _("Search titles…"), self.search_width)
    self.filter_summary:setText(Filters.summary(self.controller.mode, options))
    self.search_row:resetLayout()
    self.summary_row:resetLayout()
    self.custom_title_bar:resetLayout()
end

function Results:updatePageInfo(select_number)
    Menu.updatePageInfo(self, select_number)
    local controller = self.controller
    self.page_info_first_chev:hide()
    self.page_info_last_chev:hide()
    self.page_info_left_chev:show()
    self.page_info_right_chev:show()
    self.page_info_left_chev:enableDisable(self.page > 1 or controller.page > 1)
    self.page_info_right_chev:enableDisable(self.page < self.page_num or controller.has_next)
    local page = controller.page
    local caption = self.page_num > 1 and T(_("Page %1 · %2/%3"), page, self.page, self.page_num)
        or T(_("Page %1"), page)
    self.page_info_text:setText(caption)
    self.page_info_text:disableWithoutDimming()
end

function Results:mergeTitleBarIntoLayout()
    if Device:hasSymKey() or Device:hasScreenKB() then
        -- The native title bar has shortcuts on these devices; our tabs still need focus.
        table.insert(self.layout, 1, { self.title_bar.other_tab })
        for index = 1, #self.title_bar.controls do
            table.insert(self.layout, index + 1, { self.title_bar.controls[index] })
        end
        self.selected.y = self.selected.y + 1 + #self.title_bar.controls
    else
        Menu.mergeTitleBarIntoLayout(self)
    end
    if self.page_info_left_chev.enabled then self.layout[#self.layout + 1] = { self.page_info_left_chev } end
    if self.page_info_right_chev.enabled then self.layout[#self.layout + 1] = { self.page_info_right_chev } end
end

function Results:onNextPage()
    if self.page < self.page_num then return self:onGotoPage(self.page + 1) end
    if self.controller.has_next then self.controller:loadPage(self.controller.page + 1) end
    return true
end

function Results:onPrevPage()
    if self.page > 1 then return self:onGotoPage(self.page - 1) end
    if self.controller.page > 1 then self.controller:loadPage(self.controller.page - 1, nil, true) end
    return true
end

function Results:onLeftButtonTap()
    self.controller:openFilters()
    return true
end

function Results.onShowGotoDialog()
    return true
end

function Results:onScreenResize(dimen)
    self:cancelCoverLoad()
    self.item_group:clear()
    return Menu.onScreenResize(self, dimen)
end

function Results:onCloseWidget()
    self:cancelCoverLoad()
    self.item_group:clear()
    self.controller:close(self)
    Menu.onCloseWidget(self)
end

return Results
