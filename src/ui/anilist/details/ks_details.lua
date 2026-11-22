local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local Cover = require("ui/anilist/details/ks_cover_preview")
local Device = require("device")
local Editor = require("ui/anilist/details/ks_library_editor")
local FocusManager = require("ui/widget/focusmanager")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local Row = require("ui/anilist/browser/ks_result_row")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local Size = require("ui/size")
local Support = require("ui/anilist/details/ks_details_support")
local TagStrip = require("ui/anilist/details/ks_tag_strip")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local util = require("util")
local T = require("ffi/util").template
local _ = require("gettext")
local Screen = Device.screen

local Details = { _sessions = setmetatable({}, { __mode = "k" }) }
local ScreenWidget = FocusManager:extend { covers_fullscreen = true, stop_events_propagation = true }

local function text(value)
    return type(value) == "string" and value:match("%S") and value or nil
end

local function mediaTitle(media)
    local title = type(media.title) == "table" and media.title or {}
    return text(title.userPreferred) or text(title.romaji) or text(title.english) or text(title.native)
        or _("Untitled"), title
end

local function readableEnum(value)
    value = text(value)
    if not value then return end
    if value == "TV" or value == "OVA" or value == "ONA" then return value end
    return (value:gsub("_", " "):lower():gsub("^%l", string.upper))
end

local function fuzzyDate(date)
    if type(date) ~= "table" or type(date.year) ~= "number" then return end
    if type(date.month) ~= "number" then return tostring(date.year) end
    if type(date.day) ~= "number" then return string.format("%04d-%02d", date.year, date.month) end
    return string.format("%04d-%02d-%02d", date.year, date.month, date.day)
end

local function names(items)
    local result = {}
    for index = 1, #(items or {}) do
        local name = text(items[index])
        if name then result[#result + 1] = name end
    end
    if #result > 0 then return table.concat(result, ", ") end
end

local function labeled(label, value)
    return T(_("%1: %2"), label, value)
end


local function textbox(value, width, face, bold, color)
    return TextBoxWidget:new {
        text = value, width = width, face = Font:getFace(face), bold = bold, fgcolor = color,
    }
end

local function space()
    return VerticalSpan:new { width = Size.padding.large }
end

local function card(group)
    return FrameContainer:new {
        radius = Size.radius.window, padding = Size.padding.large, bordersize = Size.border.button,
        color = Blitbuffer.COLOR_LIGHT_GRAY, background = Blitbuffer.COLOR_WHITE, group,
    }
end

local function detailsContent(screen, media, inner_width)
    local pad = Size.padding.large
    local function section(title, value)
        return card(VerticalGroup:new {
            align = "left",
            textbox(title, inner_width, "smallinfofont", true),
            space(),
            textbox(value, inner_width, "smallinfofont"),
        })
    end

    local title, alternatives = mediaTitle(media)
    local cover = Cover.thumbnail(screen.controller.api, media, math.floor(inner_width * 0.32), function()
        Cover.show(screen.controller, media, function() return screen.session.widget == screen end)
    end, screen)
    if cover then screen.layout[#screen.layout + 1] = { cover } end
    local title_width = inner_width - (cover and cover:getSize().w + pad or 0)
    local title_group = VerticalGroup:new {
        align = "left", textbox(title, title_width, "tfont", true),
    }
    local shown = { [title] = true }
    local title_fields = { "romaji", "english", "native" }
    for index = 1, #title_fields do
        local alternate = text(alternatives[title_fields[index]])
        if alternate and not shown[alternate] then
            shown[alternate] = true
            title_group[#title_group + 1] = textbox(alternate, title_width, "smallinfofont", false,
                Blitbuffer.COLOR_DARK_GRAY)
        end
    end
    local hero = cover and HorizontalGroup:new {
        align = "top", cover, HorizontalSpan:new { width = pad }, title_group,
    } or title_group
    local content = VerticalGroup:new { align = "left", space(), card(hero), space() }
    local description = text(media.description)
    content[#content + 1] = section(_("Description"),
        description and text(util.htmlToPlainText(description)) or _("No description available."))

    local facts = {}
    local function fact(label, value)
        if type(value) == "number" or text(value) then facts[#facts + 1] = labeled(label, value) end
    end
    fact(_("Mean score"), type(media.meanScore) == "number" and T(_("%1%"), media.meanScore) or nil)
    fact(_("Popularity"), media.popularity)
    fact(_("Favorites"), media.favourites or media.favorites)
    fact(_("Format"), readableEnum(media.format))
    fact(_("Status"), readableEnum(media.status))
    fact(_("Start date"), fuzzyDate(media.startDate))
    fact(_("End date"), fuzzyDate(media.endDate))
    fact(_("Episodes"), media.episodes)
    fact(_("Chapters"), media.chapters)
    fact(_("Volumes"), media.volumes)
    fact(_("Episode duration"), type(media.duration) == "number" and T(_("%1 min"), media.duration) or nil)
    fact(_("Source"), readableEnum(media.source))
    fact(_("Country of origin"), media.countryOfOrigin)
    local studios = {}
    for index, studio in ipairs(media.studios and media.studios.nodes or {}) do studios[index] = studio.name end
    if #studios == 0 then
        local edges = media.studios and media.studios.edges or {}
        for index = 1, #edges do
            local edge = edges[index]
            if edge and edge.node and text(edge.node.name) then studios[#studios + 1] = edge.node.name end
        end
    end
    fact(_("Studios"), names(studios))
    fact(_("Genres"), names(media.genres))
    if #facts > 0 then
        content[#content + 1] = space()
        content[#content + 1] = section(_("Information"), table.concat(facts, "\n"))
    end
    content[#content + 1] = space()
    return content
end

local function tagItems(media)
    local items, seen = {}, {}
    local tags = media.tags or {}
    for index = 1, #tags do
        local name = tags[index] and text(tags[index].name)
        if name and not seen[name] then
            seen[name] = true
            items[#items + 1] = name
        end
    end
    return items
end

local function relationItems(media, hide_adult)
    local items = {}
    local edges = media.relations and media.relations.edges or {}
    for index = 1, #edges do
        local edge = edges[index]
        local node = edge and edge.node
        if node and type(node.id) == "number" and node.id ~= media.id and not (hide_adult and node.isAdult) then
            local entry = Row.describe(node, nil, readableEnum(edge.relationType))
            entry.id = node.id
            items[#items + 1] = entry
        end
    end
    return items
end

function ScreenWidget:init()
    local width, height = Screen:getWidth(), Screen:getHeight()
    local gap = Size.padding.default
    local controller, media = self.controller, self.media
    local body_width = width - 2 * gap - ScrollableContainer:getScrollbarWidth()
    local inner_width = body_width - 2 * (Size.padding.large + Size.border.button)
    self.layout = {}
    local body = detailsContent(self, media, inner_width)
    local tags = tagItems(media)
    if #tags > 0 then
        local strip = TagStrip:new {
            width = inner_width, tags = tags, show_parent = self,
            on_select = function(tag)
                self:onCloseDetails()
                controller:openTag(tag, media.type)
            end,
        }
        body[#body + 1] = card(VerticalGroup:new {
            align = "left", textbox(_("Tags"), inner_width, "smallinfofont", true), space(), strip,
        })
        body[#body + 1] = space()
        self.layout[#self.layout + 1] = strip.focus_row
    end
    local relations = relationItems(media, controller.api.filter_adult_content)
    self.relation_rows = {}
    if #relations > 0 then
        local items = VerticalGroup:new {
            align = "left", textbox(_("Relations"), inner_width, "smallinfofont", true),
        }
        for index = 1, #relations do
            local relation = relations[index]
            relation.callback = function()
                self:onCloseDetails()
                controller:openDetails(relation.id)
            end
            local row = Row:new { entry = relation, dimen = Geom:new {
                w = inner_width, h = Screen:scaleBySize(110),
            } }
            items[#items + 1] = row
            self.layout[#self.layout + 1] = { row }
            self.relation_rows[index] = row
        end
        body[#body + 1] = card(items)
        body[#body + 1] = space()
    end
    self.inline_rows = #self.layout
    local footer = VerticalGroup:new { VerticalSpan:new { width = gap } }
    local function addRow(actions)
        local row = HorizontalGroup:new {}
        local focus_row = {}
        local row_width = math.floor((width - 2 * gap - (#actions - 1) * gap) / #actions)
        for index, action in ipairs(actions) do
            if index > 1 then row[#row + 1] = HorizontalSpan:new { width = gap } end
            local button = Button:new {
                text = action[1], callback = action[2], width = row_width,
                radius = Size.radius.window, show_parent = self,
            }
            row[#row + 1] = button
            focus_row[index] = button
        end
        self.layout[#self.layout + 1] = focus_row
        footer[#footer + 1] = row
        footer[#footer + 1] = VerticalSpan:new { width = gap }
        return focus_row
    end
    local function editLabel()
        return self.entry and _("Edit list entry") or _("Add to AniList")
    end
    local edit_button
    edit_button = addRow {
        { _("Back"), function() self:onCloseDetails() end },
        { editLabel(), function()
            Editor.show(controller, self.media, self.entry, function(entry)
                if self.session.widget ~= self then return end
                self.entry = entry
                edit_button:setText(editLabel(), edit_button.width)
                self:refocusWidget()
                UIManager:setDirty(self, "ui")
            end)
        end },
    }[2]


    -- Keep paging reachable even on non-touch devices without page buttons.
    if not Device:isTouchDevice() and body:getSize().h > height - footer:getSize().h then
        footer:resetLayout()
        addRow {
            { _("Page up"), function() self.cropping_widget:onScrollPageUp() end },
            { _("Page down"), function() self.cropping_widget:onScrollPageDown() end },
        }
    end
    self.cropping_widget = ScrollableContainer:new {
        dimen = Geom:new { w = width - 2 * gap, h = height - footer:getSize().h },
        show_parent = self,
        body,
    }
    self[1] = FrameContainer:new {
        padding = 0, bordersize = 0, background = Blitbuffer.COLOR_WHITE,
        width = width, height = height,
        VerticalGroup:new { FrameContainer:new {
            padding = 0, padding_left = gap, padding_right = gap, bordersize = 0, self.cropping_widget,
        }, footer },
    }
    if Device:hasKeys() then
        self.key_events.CloseDetails = { { Device.input.group.Back } }
    end
end

function ScreenWidget:relationViewport()
    local crop = self.cropping_widget
    return crop._is_scrollable and crop:getCropRegion() or crop.dimen
end

function ScreenWidget:scheduleRelationCover()
    if self.relation_cover_task or UIManager:getTopmostVisibleWidget() ~= self then return end
    local viewport = self:relationViewport()
    for index = 1, #self.relation_rows do
        local row = self.relation_rows[index]
        if row.entry.cover_url and not row.cover_loaded and not row.cover_failed and row.dimen:intersectWith(viewport) then
            self.relation_cover_task = function()
                self.relation_cover_task = nil
                local current_viewport = self:relationViewport()
                if UIManager:getTopmostVisibleWidget() ~= self or not row.dimen:intersectWith(current_viewport) then return end
                if row:loadCover(self.controller.api.downloadImage) then
                    UIManager:setDirty(self, "ui", row.dimen:intersect(current_viewport))
                else
                    row.cover_failed = true
                end
                self:scheduleRelationCover()
            end
            UIManager:scheduleIn(0.08, self.relation_cover_task)
            return
        end
    end
end

function ScreenWidget:paintTo(bb, x, y)
    FocusManager.paintTo(self, bb, x, y)
    -- Retain decoded covers only for rows intersecting the current viewport.
    local viewport = self:relationViewport()
    for index = 1, #self.relation_rows do
        local row = self.relation_rows[index]
        if row.cover_loaded and row.dimen:notIntersectWith(viewport) then row:unloadCover() end
    end
    self:scheduleRelationCover()
end

function ScreenWidget:refocusInlineRow(row)
    if self.layout[self.selected.y] == row then
        self.selected.x = math.min(self.selected.x, #row)
        self:refocusWidget()
    end
end

function ScreenWidget:onFocusMove(args)
    local handled = FocusManager.onFocusMove(self, args)
    if self.selected.y <= self.inline_rows then
        local button = self:getFocusItem()
        local crop = self.cropping_widget
        if button and button.dimen and crop._is_scrollable then
            local y = button.dimen.y - crop.dimen.y
            local bottom = y + button.dimen.h
            if y < 0 then crop:_scrollBy(0, y)
            elseif bottom > crop.dimen.h then crop:_scrollBy(0, bottom - crop.dimen.h) end
        end
    end
    return handled
end

function ScreenWidget:onShow()
    self:refocusWidget()
    UIManager:setDirty(self, "ui")
end

function ScreenWidget:onCloseDetails()
    self.session.request = nil
    UIManager:close(self)
    if self.controller.detailsClosed then self.controller:detailsClosed() end
    return true
end

function ScreenWidget:onCloseWidget()
    if self.relation_cover_task then
        UIManager:unschedule(self.relation_cover_task)
        self.relation_cover_task = nil
    end
    if self.session.widget == self then self.session.widget = nil end
    self.cropping_widget:onCloseWidget()
    self:free(true)
    UIManager:setDirty(nil, "ui")
end

function Details:show(controller, media_id)
    local session = self._sessions[controller] or {}
    self._sessions[controller] = session
    local request = {}
    session.request = request
    Support.online(controller, function()
        if session.request ~= request then return end
        session.request = nil
        local media, err = controller.api:getMediaDetails(media_id)
        if err or type(media) ~= "table" or not media.id then
            Support.error(controller, _("Could not load AniList details."))
            return
        end
        if session.widget then session.widget:onCloseDetails() end
        local entry = media.mediaListEntry
        local widget = ScreenWidget:new {
            session = session, controller = controller, media = media,
            entry = type(entry) == "table" and entry.id and entry or nil,
        }
        session.widget = widget
        UIManager:show(widget)
    end)
end

return Details
