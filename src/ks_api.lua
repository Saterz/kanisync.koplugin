local Catalog = require("api/catalog")
local Library = require("api/library")
local Transport = require("api/transport")

---@class KanisyncApi
---@field token string|nil User-provided AniList token
---@field filter_adult_content boolean
local KanisyncApi = {
    request = Transport.request,
    downloadImage = Transport.downloadImage,
    getMedia = Catalog.getMedia,
    searchMedia = Catalog.searchMedia,
    browse = Catalog.browse,
    getMediaDetails = Catalog.getMediaDetails,
    getUser = Library.getUser,
    library = Library.library,
    updateMediaList = Library.updateMediaList,
    deleteMediaList = Library.deleteMediaList,
}
KanisyncApi.__index = KanisyncApi

function KanisyncApi:new(token, filter_adult_content)
    local obj = setmetatable({}, self)
    obj:init(token, filter_adult_content)
    return obj
end

---@param token? string
---@param filter_adult_content? boolean
function KanisyncApi:init(token, filter_adult_content)
    self.token = token
    self.filter_adult_content = filter_adult_content ~= false
end

return KanisyncApi
