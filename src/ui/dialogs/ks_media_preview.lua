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
local getMediaTitle = MediaHelpers.getMediaTitle
local renderCover = MediaHelpers.renderCover

local MediaPreview = {}

---@param media table
---@param back_callback function
---@param select_callback fun(media: table): string|nil
---@param cover_loader fun(url: string): string|nil
function MediaPreview.previewMedia(media, back_callback, select_callback, cover_loader)
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

    local confirm
    confirm = ConfirmBox:new {
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

    local cover_url = type(media.coverImage) == "table"
        and type(media.coverImage.medium) == "string"
        and media.coverImage.medium
    if cover_url then
        local max_width = confirm:getAddedWidgetAvailableWidth()
        local max_height = math.floor(Screen:getHeight() * 0.45)
        local cover, cover_width, cover_height = renderCover(
            media._cover_data or cover_loader(cover_url),
            max_width,
            max_height
        )
        if cover then
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

return MediaPreview
