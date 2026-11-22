local UIManager = require("ui/uimanager")
local CenterContainer = require("ui/widget/container/centercontainer")
local Geom = require("ui/geometry")
local ImageWidget = require("ui/widget/imagewidget")
local Menu = require("ui/widget/menu")
local Trapper = require("ui/trapper")
local Device = require("device")
local Size = require("ui/size")
local ffiUtil = require("ffi/util")
local _ = require("gettext")
local Screen = Device.screen
local T = ffiUtil.template

local MediaHelpers = require("ui/ks_media_helpers")
local SearchDialog = require("ui/dialogs/ks_search_dialog")
local MediaPreview = require("ui/dialogs/ks_media_preview")
local getMediaTitle = MediaHelpers.getMediaTitle
local renderCover = MediaHelpers.renderCover

local MediaChooser = {}
local CoverSlot = CenterContainer:extend{}

function CoverSlot:paintTo(bb, x, y)
    if self[1] then
        CenterContainer.paintTo(self, bb, x, y)
    end
end

---@param media_list table
---@param search_query string
---@param select_callback fun(media: table): string|nil
---@param search_callback fun(search_query: string)
---@param cover_loader fun(url: string): string|nil
---@param is_active fun(): boolean
function MediaChooser.mediaChooser(media_list, search_query, select_callback, search_callback, cover_loader, is_active)
    if not is_active() then return end
    if #media_list == 0 then
        SearchDialog.searchDialog(search_query, search_callback, true)
        return
    end

    UIManager:nextTick(function()
        if not is_active() then return end
        local thumbnail_width = Screen:scaleBySize(48)
        local thumbnail_height = Screen:scaleBySize(68)

        local thumbnail_state_width = thumbnail_width + Size.span.horizontal_default
        local items = {
            {
                text = _("Adjust search..."),
                -- Cancel out the menu's state-w
                indent = -thumbnail_state_width,
                callback = function()
                    UIManager:nextTick(function()
                        if is_active() then
                            SearchDialog.searchDialog(search_query, search_callback)
                        end
                    end)
                end,
            },
        }

        for media_index = 1, #media_list do
            local media = media_list[media_index]

            local cover_widget
            local cover_url = type(media.coverImage) == "table"
                and type(media.coverImage.medium) == "string"
                and media.coverImage.medium
            if cover_url and cover_url ~= "" then
                cover_widget = CoverSlot:new {
                    dimen = Geom:new { w = thumbnail_width, h = thumbnail_height },
                }
            end

            table.insert(items, {
                text = getMediaTitle(media),
                mandatory = media.mediaListEntry and _("In Library") or nil,
                state = cover_widget,
                cover_url = cover_widget and cover_url or nil,
                callback = function()
                    UIManager:nextTick(function()
                        MediaPreview.previewMedia(media, function()
                            MediaChooser.mediaChooser(media_list, search_query, select_callback, search_callback,
                                cover_loader, is_active)
                        end, select_callback, cover_loader, is_active)
                    end)
                end,
            })
        end

        local chooser
        local closed, load_scheduled, active_download
        local scheduleCovers

        local function loadNextCover()
            load_scheduled = nil
            if closed then return end

            local page = chooser.page
            local first = (page - 1) * chooser.perpage + 1
            local last = math.min(first + chooser.perpage - 1, #items)
            for index = first, last do
                local item = items[index]
                if item.cover_url and not item.cover_attempted then
                    item.cover_attempted = true
                    local cached_data = MediaHelpers.getCachedCover(item.cover_url)
                    local cover_data = cached_data
                    if not cover_data then
                        -- A private trap lets us cancel on close without intercepting menu input.
                        active_download = {}
                        local completed, downloaded = Trapper:dismissableRunInSubprocess(function()
                            return cover_loader(item.cover_url)
                        end, active_download, true)
                        active_download = nil
                        if closed then return end
                        if completed then cover_data = downloaded end
                    end
                    local cover = renderCover(cover_data, thumbnail_width, thumbnail_height)
                    if cover then
                        if not cached_data then
                            MediaHelpers.cacheCover(item.cover_url, cover_data)
                        end
                        item.state[1] = ImageWidget:new { image = cover, image_disposable = false }
                        if chooser.page == page then
                            UIManager:setDirty(chooser, "ui", chooser.dimen)
                        end
                    end
                    scheduleCovers()
                    return
                end
            end
        end

        scheduleCovers = function()
            if not closed and not load_scheduled and not active_download then
                load_scheduled = UIManager:tickAfterNext(function()
                    Trapper:wrap(loadNextCover)
                end)
            end
        end

        chooser = Menu:new {
            title = T(_("AniList results for “%1”"), search_query),
            item_table = items,
            state_w = thumbnail_state_width,
            items_per_page = 6,
            multilines_forced = true,
            is_borderless = true,
            covers_fullscreen = true,
            dithered = true,
            updateItems = function(menu, ...)
                Menu.updateItems(menu, ...)
                if chooser then scheduleCovers() end
            end,
            close_callback = function()
                if not closed then UIManager:close(chooser) end
            end,
            onCloseWidget = function(menu)
                if closed then return end
                closed = true
                if load_scheduled then UIManager:unschedule(load_scheduled) end
                if active_download then active_download.dismiss_callback() end
                for index = 2, #items do
                    local slot = items[index].state
                    if slot and slot[1] then
                        slot[1]:free()
                        slot[1].image:free()
                        slot[1] = nil
                    end
                end
                Menu.onCloseWidget(menu)
            end,
        }
        UIManager:show(chooser)
        scheduleCovers()
    end)
end

return MediaChooser
