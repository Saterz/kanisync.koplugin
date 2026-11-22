local Cache = require("cache")
local RenderImage = require("ui/renderimage")

local MediaHelpers = {}

-- Keep compressed data so thumbnails and previews can share the same cache.
local cover_cache = Cache:new { size = 8 * 1024 * 1024, avg_itemsize = 64 * 1024 }

function MediaHelpers.getCachedCover(url)
    return cover_cache:get(url)
end

function MediaHelpers.cacheCover(url, image_data)
    if cover_cache:willAccept(#image_data) then
        cover_cache:insert(url, image_data, #image_data)
    end
end

local function getMediaTitle(media)
    local title = media.title
    return title.userPreferred or title.english or title.romaji or title.native
end

local function renderCover(image_data, max_width, max_height)
    if not image_data then return end

    local cover = RenderImage:renderImageData(image_data, #image_data, false)
    if not cover then return end

    local cover_width, cover_height = cover:getWidth(), cover:getHeight()
    local scale = math.min(max_width / cover_width, max_height / cover_height, 1)
    if scale < 1 then
        cover_width = math.floor(cover_width * scale)
        cover_height = math.floor(cover_height * scale)
        cover = RenderImage:scaleBlitBuffer(cover, cover_width, cover_height, true)
    end
    return cover, cover_width, cover_height
end

MediaHelpers.getMediaTitle = getMediaTitle
MediaHelpers.renderCover = renderCover

return MediaHelpers
