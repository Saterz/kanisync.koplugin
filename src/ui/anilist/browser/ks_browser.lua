local Details = require("ui/anilist/details/ks_details")
local Filters = require("ui/anilist/filters/ks_filters")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Request = require("ui/ks_foreground_request")
local Results = require("ui/anilist/browser/ks_results")
local Row = require("ui/anilist/browser/ks_result_row")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

-- AniList cannot search titles in a MediaList request. Skip a few empty pages per
-- action, then let the user continue so very large libraries don't block the UI.
local MAX_LIBRARY_SEARCH_PAGES = 4

local Browser = {}
Browser.__index = Browser

function Browser.open(plugin, mode, options, parent, tab_options)
    mode = mode or "catalog"
    if mode == "library" and not plugin:hasToken() then
        UIManager:show(InfoMessage:new { text = _("Configure an AniList access token to open your library.") })
        return
    end
    local self = setmetatable({
        plugin = plugin, api = plugin.api, mode = mode, parent = parent,
        options = options or (tab_options and tab_options[mode]) or { type = "MANGA" }, page = 1,
        tab_options = tab_options or {},
    }, Browser)
    self.widget = Results:new {
        controller = self,
        item_table = { { text = _("Load entries"), callback = function() self:loadPage(1) end } },
    }
    UIManager:show(self.widget)
    self:loadPage(1)
end


function Browser:reportError(message) -- luacheck: ignore self
    UIManager:show(InfoMessage:new { text = message })
end

function Browser:close(widget)
    if self.widget == widget then
        self.widget = nil
        self.request, self.details_request = nil, nil
        if self.parent then self.parent:detailsClosed() end
    end
end

function Browser:switchMode(mode)
    if not self.widget or self.mode == mode then return end
    if mode == "library" and not self.plugin:hasToken() then
        self:reportError(_("Configure an AniList access token to open your library."))
        return
    end
    -- A tag view sits above the original results; switching tabs dismisses it first.
    local root = self.parent or self
    if self.parent then UIManager:close(self.widget) end
    if root.mode == mode then return end
    root.tab_options[root.mode] = root.options
    UIManager:close(root.widget)
    Browser.open(root.plugin, mode, nil, nil, root.tab_options)
end

function Browser:loadPage(page, options, last_local_page)
    local widget = self.widget
    if not widget then return end
    local query = {}
    for key, value in pairs(options or self.options) do query[key] = value end
    local api, mode, cached_viewer = self.api, self.mode, self.viewer
    local request = {}
    self.request = request
    self.details_request = nil
    local function isActive() return self.widget == widget and self.request == request end
    local function clearRequest()
        if isActive() then self.request = nil end
    end
    local browse_query = query
    if mode == "catalog" and not query.sort and not query.search then
        browse_query = setmetatable({ sort = "POPULARITY_DESC" }, { __index = query })
    end
    Request.run(function()
        if mode ~= "library" then
            local data = api:browse(browse_query, page)
            return data, page
        end
        -- Resolve the viewer and scan the requested pages in the same operation.
        local viewer = cached_viewer or api:getUser()
        if not viewer or not viewer.id then return end
        local data, target_page = nil, page
        local direction = last_local_page and -1 or 1
        local limit = query.search and MAX_LIBRARY_SEARCH_PAGES or 1
        for attempt = 1, limit do
            data = api:library(viewer.id, query, target_page)
            if not data or #data.items > 0 or attempt == limit then break end
            if direction == 1 and not data.has_next or direction == -1 and target_page == 1 then break end
            target_page = target_page + direction
        end
        return data, target_page, viewer
    end, function(data, loaded_page, viewer)
        if not isActive() then return end
        clearRequest()
        if mode == "library" then
            if not viewer then
                self:reportError(_("Could not verify your AniList account. Check your access token and try again."))
                return
            end
            self.viewer = viewer
        end
        if not data then
            self:reportError(_("Could not load entries from AniList. Try again shortly."))
            return
        end
        self.options, self.page, self.has_next = query, loaded_page, data.has_next
        self.dirty = false
        local rows = {}
        local list_options = self.viewer and self.viewer.mediaListOptions
        local score_format = list_options and self.plugin.score_formats[list_options.scoreFormat]
        for index, media in ipairs(data.items) do
            local id = media.id
            local entry = Row.describe(media, score_format and score_format.maximum)
            entry.callback = function() self:openDetails(id, entry.cover_url) end
            rows[index] = entry
        end
        if #rows == 0 then
            local message = _("No entries on this page")
            if mode == "library" and query.search then
                message = _("No matching titles on the pages checked.")
                if data.has_next then message = _("No matches yet. Go to the next page to keep searching.") end
            end
            rows[1] = { text = message, select_enabled = false }
        end
        widget:updateSearchLabel()
        widget:switchItemTable(nil, rows, last_local_page and #rows or nil)
    end, { text = _("Loading AniList…"), is_active = isActive, on_cancel = clearRequest })
end

function Browser:openSearch()
    local dialog
    dialog = InputDialog:new {
        title = self.mode == "library" and _("Search your library") or _("Search AniList titles"),
        input = self.options.search or "",
        description = _("Leave blank to browse without a title search."),
        buttons = { {
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("Search"), is_enter_default = true, callback = function()
                local search = (dialog:getInputText() or ""):match("^%s*(.-)%s*$")
                UIManager:close(dialog)
                local options = {}
                for key, value in pairs(self.options) do options[key] = value end
                options.search = search ~= "" and search or nil
                self:loadPage(1, options)
            end },
        } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Browser:openFilters()
    Filters.show(self.mode, self.options, function(options) self:loadPage(1, options) end)
end

function Browser:openDetails(id, cover_url)
    local widget = self.widget
    if not widget then return end
    local request = {}
    self.request = nil
    self.details_request = request
    Details:show(self, id, cover_url, function()
        return self.widget == widget and self.details_request == request
    end)
end

function Browser:openTag(tag, media_type)
    local options = { tag = tag, type = media_type == "ANIME" and "ANIME" or "MANGA" }
    -- Keep the source results available, but reuse the tag screen for successive tags.
    if self.parent then
        self:loadPage(1, options)
    else
        Browser.open(self.plugin, "catalog", options, self)
    end
end

function Browser:libraryChanged(media_id, entry)
    self.dirty = true
    if self.parent then self.parent.dirty = true end
    local linked_book = self.plugin:getBookAniListData()
    if linked_book and linked_book.id == media_id then
        -- Preserve the local book link even when the remote list entry is removed.
        self.plugin:saveBookUserMetadata(entry or {})
    end
end

function Browser:detailsClosed()
    if self.widget and self.mode == "library" and self.dirty then
        self:loadPage(1)
    end
end

return Browser
