local UIManager = require("ui/uimanager")
local CenterContainer = require("ui/widget/container/centercontainer")
local Geom = require("ui/geometry")
local ImageWidget = require("ui/widget/imagewidget")
local Menu = require("ui/widget/menu")
local Device = require("device")
local Size = require("ui/size")
local ffiUtil = require("ffi/util")
local _ = require("gettext")
local Screen = Device.screen
local T = ffiUtil.template
local MediaHelpers = require("ui/media_helpers")
local getMediaTitle = MediaHelpers.getMediaTitle
local renderCover = MediaHelpers.renderCover

local MediaChooser = {}

---@param media_list table
---@param search_query string
---@param select_callback fun(media: table): string|nil
---@param search_callback fun(search_query: string)
---@param cover_loader fun(url: string): string|nil
---@param on_loading_complete fun()
function MediaChooser:mediaChooser(media_list, search_query, select_callback, search_callback, cover_loader,
                                 on_loading_complete)
    if #media_list == 0 then
        on_loading_complete()
        self.searchDialog(search_query, search_callback, true)
        return
    end

    UIManager:nextTick(function()
        local thumbnail_width = Screen:scaleBySize(48)
        local thumbnail_height = Screen:scaleBySize(68)
        local thumbnail_buffers = {}
        local thumbnail_state_width = thumbnail_width + Size.span.horizontal_default
        local items = {
            {
                text = _("Adjust search..."),
                -- Cancel out the menu's state-w
                indent = -thumbnail_state_width,
                callback = function()
                    UIManager:nextTick(function()
                        self.searchDialog(search_query, search_callback)
                    end)
                end,
            },
        }

        local chooser
        for media_index = 1, #media_list do
            local media = media_list[media_index]

            local cover_widget
            local cover_url = type(media.coverImage) == "table"
                and type(media.coverImage.medium) == "string"
                and media.coverImage.medium
            if cover_url then
                media._cover_data = media._cover_data or cover_loader(cover_url)
                local cover = renderCover(media._cover_data, thumbnail_width, thumbnail_height)
                if cover then
                    table.insert(thumbnail_buffers, cover)
                    cover_widget = CenterContainer:new {
                        dimen = Geom:new {
                            w = thumbnail_width,
                            h = thumbnail_height,
                        },
                        ImageWidget:new {
                            image = cover,
                            image_disposable = false,
                        },
                    }
                end
            end

            table.insert(items, {
                text = getMediaTitle(media),
                mandatory = media.mediaListEntry and _("In Library") or nil,
                state = cover_widget,
                callback = function()
                    UIManager:nextTick(function()
                        self:previewMedia(media, function()
                            self:mediaChooser(media_list, search_query, select_callback, search_callback, cover_loader,
                                on_loading_complete)
                        end, select_callback, cover_loader)
                    end)
                end,
            })
        end

        chooser = Menu:new {
            title = T(_("AniList results for “%1”"), search_query),
            item_table = items,
            state_w = thumbnail_state_width,
            items_per_page = 6,
            multilines_forced = true,
            dithered = true,
            close_callback = function()
                UIManager:close(chooser)
                for buffer_index = 1, #thumbnail_buffers do
                    thumbnail_buffers[buffer_index]:free()
                end
                thumbnail_buffers = {}
            end,
        }
        on_loading_complete()
        UIManager:show(chooser)
    end)
end

return MediaChooser
