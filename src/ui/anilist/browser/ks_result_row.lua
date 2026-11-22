local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local MediaHelpers = require("ui/ks_media_helpers")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local StatusMenu = require("ui/menus/ks_status_menu")
local T = require("ffi/util").template
local _ = require("gettext")
local Screen = Device.screen

local Row = InputContainer:extend{}
local COVER_LIMITS = { bytes = 512 * 1024, timeout = 4 }

local formats = { NOVEL = _("Light novel"), MANGA = _("Manga"),
    ONE_SHOT = _("One-shot"), TV = _("TV"), TV_SHORT = _("TV short"),
    MOVIE = _("Movie"), SPECIAL = _("Special"), OVA = _("OVA"), ONA = _("ONA"), MUSIC = _("Music") }
local publishing_statuses = { FINISHED = _("Finished"), RELEASING = _("Releasing"),
    NOT_YET_RELEASED = _("Not yet released"), CANCELLED = _("Cancelled"), HIATUS = _("On hiatus") }

function Row.describe(media, score_max, relation)
    local title = media.title or {}
    local lines = {}
    local function addLine(...)
        local fields = {}
        for index = 1, select("#", ...) do
            local value = select(index, ...)
            if value then fields[#fields + 1] = value end
        end
        if #fields > 0 then lines[#lines + 1] = table.concat(fields, " · ") end
    end
    local is_anime = media.type == "ANIME"
    local total = is_anime and media.episodes or media.chapters
    local format = formats[media.format]
    local entry = media.mediaListEntry
    if entry then
        local score = entry.score and entry.score > 0 and (score_max and T(_("Score: %1/%2"), entry.score, score_max)
            or T(_("Score: %1"), entry.score))
        addLine(StatusMenu.getStatusLabel(entry.status, is_anime), format, score)
        local progress = entry.progress or 0
        if total then progress = T(_("%1/%2"), progress, total) end
        addLine(is_anime and T(_("Episodes: %1"), progress) or T(_("Chapters: %1"), progress),
            not is_anime and (media.volumes or (entry.progressVolumes or 0) > 0)
                and T(_("Volumes: %1"), media.volumes and T(_("%1/%2"), entry.progressVolumes or 0, media.volumes)
                    or entry.progressVolumes))
    else
        addLine(relation, format, media.startDate and media.startDate.year, publishing_statuses[media.status])
        addLine(total and (is_anime and T(_("Episodes: %1"), total) or T(_("Chapters: %1"), total)),
            not is_anime and media.volumes and T(_("Volumes: %1"), media.volumes),
            media.averageScore and T(_("Score: %1%"), media.averageScore))
    end
    return {
        text = title.userPreferred or title.romaji or title.english or title.native or _("Untitled"),
        metadata = lines, cover_url = media.coverImage and media.coverImage.medium,
    }
end

local function placeholder()
    return IconWidget:new { icon = "book.opened", width = Screen:scaleBySize(24), height = Screen:scaleBySize(24) }
end

function Row:init()
    local w, h = self.dimen.w, self.dimen.h
    local gap, border = Size.padding.default, Size.border.button
    local inner_w, inner_h = w - 4 * gap - 2 * border, h - gap - 2 * border
    local content = HorizontalGroup:new { align = "center" }
    local text_w = inner_w
    if self.entry.metadata then
        local cover_border = Size.border.thin
        local cover_h = inner_h - 2 * gap - 2 * cover_border
        local cover_w = math.floor(cover_h * 0.69)
        self.cover = CenterContainer:new {
            dimen = Geom:new { w = cover_w, h = cover_h },
            placeholder(),
        }
        content[1] = FrameContainer:new {
            bordersize = cover_border, padding = 0, radius = Size.radius.button,
            color = Blitbuffer.COLOR_DARK_GRAY, background = Blitbuffer.COLOR_LIGHT_GRAY, self.cover,
        }
        content[2] = HorizontalSpan:new { width = gap }
        text_w = inner_w - cover_w - 2 * cover_border - gap
    end

    local metadata = VerticalGroup:new { align = "left" }
    for index = 1, #(self.entry.metadata or {}) do
        metadata[index] = TextWidget:new {
            text = self.entry.metadata[index], face = Font:getFace("smallinfofont", 15),
            max_width = text_w, fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        }
    end
    local text = VerticalGroup:new {
        align = "left",
        TextBoxWidget:new {
            text = self.entry.text, width = text_w,
            face = Font:getFace("smallinfofont", 20), bold = true,
            height = inner_h - metadata:getSize().h - 2 * gap,
            height_adjust = true, height_overflow_show_ellipsis = true,
        },
        metadata,
    }
    content[#content + 1] = text
    self[1] = FrameContainer:new {
        margin = 0, bordersize = 0, padding = 0,
        padding_left = gap, padding_right = gap, padding_bottom = gap,
        FrameContainer:new {
            bordersize = border, padding = 0, padding_left = gap, padding_right = gap,
            radius = Size.radius.button, background = Blitbuffer.COLOR_WHITE,
            color = Blitbuffer.COLOR_DARK_GRAY, focusable = true, focus_inner_border = true,
            LeftContainer:new { dimen = Geom:new { w = inner_w, h = inner_h }, content },
        },
    }
    self.ges_events = { TapSelect = { GestureRange:new { ges = "tap", range = self.dimen } } }
end

function Row:onTapSelect()
    if self.menu then return self.menu:onMenuSelect(self.entry) end
    if self.entry.callback then self.entry.callback() end
    return true
end

function Row:loadCover(download)
    local url = self.entry.cover_url
    if type(url) ~= "string" or not url:match("^https://") then return end
    local cached = MediaHelpers.getCachedCover(url)
    local data = cached or (download and download(url, COVER_LIMITS))
    if type(data) ~= "string" or #data == 0 or #data > COVER_LIMITS.bytes then return end
    local size = self.cover.dimen
    local image, w, h = MediaHelpers.renderCover(data, size.w, size.h)
    if not image then return end
    if not cached then MediaHelpers.cacheCover(url, data) end
    self.cover[1]:free()
    self.cover[1] = ImageWidget:new { image = image, width = w, height = h }
    self.cover[1]:getSize() -- Take ownership of the buffer before this row can be freed.
    self.cover_loaded = true
    return true
end

function Row:unloadCover()
    if not self.cover_loaded then return end
    self.cover[1]:free()
    self.cover[1] = placeholder()
    self.cover_loaded = nil
end

return Row
