local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FocusManager = require("ui/widget/focusmanager")
local FrameContainer = require("ui/widget/container/framecontainer")
local GestureRange = require("ui/gesturerange")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local MediaHelpers = require("ui/ks_media_helpers")
local RenderImage = require("ui/renderimage")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local Screen = Device.screen

local Cover = {}
local thumbnail_limits = { bytes = 512 * 1024, timeout = 3 }
local preview_limits = { bytes = 2 * 1024 * 1024, timeout = 5 }

local function httpsUrl(url)
    return type(url) == "string" and url:match("^https://[^/%s]+") and url or nil
end

local function coverUrls(media, prefer_large)
    local cover = type(media) == "table" and media.coverImage
    if type(cover) ~= "table" then return {} end
    local medium = httpsUrl(cover.medium)
    local large = httpsUrl(cover.large) or httpsUrl(cover.extraLarge)
    if not medium or medium == large then return { large } end
    if not large then return { medium } end
    if prefer_large then return { large, medium } end
    return { medium, large }
end

local function renderImage(data, max_w, max_h, max_scale)
    if type(data) ~= "string" or #data < 2 or #data > preview_limits.bytes then return end
    local ok, buffer = pcall(RenderImage.renderImageData, RenderImage, data, #data, false)
    if not ok or not buffer then return end

    local w, h = buffer:getWidth(), buffer:getHeight()
    if w < 1 or h < 1 then
        buffer:free()
        return
    end
    local scale = math.min(max_w / w, max_h / h, max_scale)
    local target_w = math.max(1, math.floor(w * scale))
    local target_h = math.max(1, math.floor(h * scale))
    if target_w ~= w or target_h ~= h then
        -- Keep ownership of the source until scaling succeeds or fails.
        local scaled_ok, scaled = pcall(RenderImage.scaleBlitBuffer, RenderImage, buffer, target_w, target_h, false)
        if not scaled_ok or scaled ~= buffer then buffer:free() end
        if not scaled_ok or not scaled then return end
        buffer = scaled
    end
    local image = ImageWidget:new { image = buffer, image_disposable = true, width = target_w, height = target_h }
    -- Bind the disposable buffer now so free() works even before the first paint.
    image:getSize()
    return image
end

local function downloadImage(api, url, limits, render)
    local data = api.downloadImage(url, limits)
    if type(data) ~= "string" or #data > limits.bytes then return end
    local image = render(data)
    if image then MediaHelpers.cacheCover(url, data) end
    return image
end

local Thumbnail = InputContainer:extend { focusable = true }

function Thumbnail:init()
    self[1] = FrameContainer:new {
        focusable = true,
        focus_inner_border = true,
        color = Blitbuffer.COLOR_LIGHT_GRAY,
        bordersize = Size.border.button,
        padding = 0,
        self.image_widget,
    }
    self.dimen = self[1]:getSize()
    -- FocusManager also sends taps on devices without touch input.
    self.ges_events.TapCover = { GestureRange:new { ges = "tap", range = self.dimen } }
end

function Thumbnail:onTapCover()
    if not self.callback then return false end
    self.callback()
    return true
end

function Cover.thumbnail(api, media, max_width, on_tap, show_parent)
    local max_w = math.floor(max_width) - 2 * Size.border.button
    local max_h = math.floor(Screen:getHeight() * 0.28) - 2 * Size.border.button
    if max_w < 1 or max_h < 1 then return end
    local function render(data) return renderImage(data, max_w, max_h, 1) end
    local urls = coverUrls(media, false)
    for index = 1, #urls do
        local url = urls[index]
        local image = render(MediaHelpers.getCachedCover(url))
        if not image and api and type(api.downloadImage) == "function" then
            image = downloadImage(api, url, thumbnail_limits, render)
        end
        if image then
            return Thumbnail:new { image_widget = image, callback = on_tap, show_parent = show_parent }
        end
    end
end

local Preview = FocusManager:extend {
    name = "kanisync_cover_preview",
    modal = true,
    stop_events_propagation = true,
}

function Preview:init()
    local screen_size = Screen:getSize()
    self.close_button = Button:new {
        text = _("Close"),
        callback = function() self:onClosePreview() end,
        show_parent = self,
        max_width = math.floor(screen_size.w * 0.64),
    }
    self.layout = { { self.close_button } }
    self.frame = FrameContainer:new {
        background = Blitbuffer.COLOR_WHITE,
        radius = Size.radius.window,
        padding = Size.padding.default,
        VerticalGroup:new {
            align = "center",
            self.image_widget,
            VerticalSpan:new { width = Size.padding.default },
            self.close_button,
        },
    }
    self[1] = CenterContainer:new { dimen = screen_size, self.frame }
    self.ges_events.TapOutsidePreview = { GestureRange:new { ges = "tap", range = screen_size } }
    if Device:hasKeys() then
        self.key_events.ClosePreview = { { Device.input.group.Back } }
    end
end

function Preview:onShow()
    self:refocusWidget()
    UIManager:setDirty(self, function() return "ui", self.frame.dimen end)
end

function Preview:onClosePreview()
    UIManager:close(self, "ui", self.frame.dimen)
    return true
end

function Preview:onTapOutsidePreview(gesture_args, ges) -- luacheck: ignore 212/gesture_args
    if self.frame.dimen and ges.pos:notIntersectWith(self.frame.dimen) then
        self:onClosePreview()
    end
    return true
end

function Preview:onCloseWidget()
    self:free(true)
end

function Cover.show(controller, media, is_active_callback)
    local urls = coverUrls(media, true)
    local api = controller.api
    local function isActive() return not is_active_callback or is_active_callback() end
    local function render(data)
        -- Let even the medium asset grow beyond its thumbnail, within both screen and source limits.
        return renderImage(data, math.floor(Screen:getWidth() * 0.64), math.floor(Screen:getHeight() * 0.60), 3)
    end
    local function load(first, online)
        for index = first, #urls do
            if not isActive() then return end
            local url = urls[index]
            local image = render(MediaHelpers.getCachedCover(url))
            if not image and api and type(api.downloadImage) == "function" then
                if not online and controller.ensureOnline then
                    return controller:ensureOnline(function() return load(index, true) end)
                end
                image = downloadImage(api, url, preview_limits, render)
            end
            if image then
                if not isActive() then
                    image:free()
                    return
                end
                local widget = Preview:new { image_widget = image }
                UIManager:show(widget)
                return widget
            end
        end
    end
    return load(1, false)
end

return Cover
