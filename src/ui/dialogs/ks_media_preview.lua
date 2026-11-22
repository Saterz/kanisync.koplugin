local UIManager = require("ui/uimanager")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local Geom = require("ui/geometry")
local ImageWidget = require("ui/widget/imagewidget")
local Device = require("device")
local ffiUtil = require("ffi/util")
local _ = require("gettext")
local Screen = Device.screen
local T = ffiUtil.template

local MediaHelpers = require("ui/ks_media_helpers")
local Messages = require("ui/ks_messages")
local Request = require('ui/ks_foreground_request')
local getMediaTitle = MediaHelpers.getMediaTitle
local renderCover = MediaHelpers.renderCover

local MediaPreview = {}

---@param media table
---@param back_callback function
---@param select_callback fun(media: table): string|nil
---@param cover_url? string
---@param cover_data? string
---@param cache_cover? boolean
local function showPreview(media, back_callback, select_callback, cover_url, cover_data, cache_cover)
    local title = getMediaTitle(media)
    local details = {}
    if media.format then
        table.insert(details, media.format)
    end
    if media.startDate and media.startDate.year then
        table.insert(details, tostring(media.startDate.year))
    end
    if media.chapters then
        table.insert(details, T(_("%1 chapters"), media.chapters))
    end
    if media.volumes then
        table.insert(details, T(_("%1 volumes"), media.volumes))
    end

    local confirm = ConfirmBox:new {
        text = title .. (#details > 0 and "\n" .. table.concat(details, " • ") or ""),
        ok_text = _("Link"),
        ok_callback = function()
            local error = select_callback(media)
            if error then
                Messages.ephemeralMessage(error)
                return
            end
        end,
        cancel_text = _("Back"),
        cancel_callback = back_callback
    }

    if cover_data then
        local max_width = confirm:getAddedWidgetAvailableWidth()
        local max_height = math.floor(Screen:getHeight() * 0.45)
        local cover, cover_width, cover_height = renderCover(cover_data, max_width, max_height)
        if cover then
            if cache_cover then
                MediaHelpers.cacheCover(cover_url, cover_data)
            end
            confirm:addWidget(CenterContainer:new {
                dimen = Geom:new {
                    w = max_width,
                    h = cover_height,
                },
                ImageWidget:new {
                    image = cover,
                    width = cover_width,
                    height = cover_height,
                },
            })
        end
    end

    UIManager:show(confirm)
end

---@param media table
---@param back_callback function
---@param select_callback fun(media: table): string|nil
---@param cover_loader fun(url: string): string|nil
---@param is_active fun(): boolean
function MediaPreview.previewMedia(media, back_callback, select_callback, cover_loader, is_active)
    if not is_active() then return end
    local cover_url = type(media.coverImage) == "table" and media.coverImage.medium
    if type(cover_url) ~= "string" or cover_url == "" then
        showPreview(media, back_callback, select_callback)
        return
    end
    local cached_data = MediaHelpers.getCachedCover(cover_url)
    if cached_data then
        showPreview(media, back_callback, select_callback, cover_url, cached_data)
        return
    end

    Request.run(function()
        return cover_loader(cover_url)
    end, function(cover_data)
        if is_active() then
            showPreview(media, back_callback, select_callback, cover_url, cover_data, true)
        end
    end, {
        text = _("Loading cover..."),
        is_active = is_active,
        on_cancel = function()
            if is_active() then back_callback() end
        end,
    })
end

return MediaPreview
