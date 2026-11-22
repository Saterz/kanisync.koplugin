local Common = require("api/common")
local Fields = require("api/fields")

---@alias CatalogOptions { type?: string, format?: string, status?: string, sort?: string, search?: string, tag?: string, genre?: string, season?: string, year?: integer }
---@alias AniListMediaPage { items: table[], has_next: boolean }

local Catalog = {}

local BROWSE = [[
query Browse($page: Int!, $perPage: Int!, $type: MediaType!, $format: MediaFormat,
    $status: MediaStatus, $sort: [MediaSort], $search: String, $tag: String, $genre: String,
    $season: MediaSeason, $startDateLike: String, $isAdult: Boolean) {
  Page(page: $page, perPage: $perPage) {
    pageInfo { hasNextPage }
    media(type: $type, format: $format, status: $status, sort: $sort, search: $search,
        tag: $tag, genre: $genre, season: $season, startDate_like: $startDateLike, isAdult: $isAdult) {
      ...MediaSummary
      averageScore
    }
  }
}
]] .. Fields.media

local GET_DETAILS = [[
query MediaDetails($id: Int!, $isAdult: Boolean) {
  Media(id: $id, isAdult: $isAdult) {
    ...MediaSummary
    description(asHtml: false)
    synonyms
    genres
    tags { id name description category rank isGeneralSpoiler isMediaSpoiler isAdult }
    source(version: 3)
    countryOfOrigin
    isLicensed
    endDate { year month day }
    season
    seasonYear
    duration
    averageScore
    meanScore
    popularity
    favourites
    bannerImage
    coverImage { extraLarge color }
    studios(isMain: true) { nodes { id name } }
    relations {
      edges {
        relationType(version: 2)
        node {
          ...MediaSummary
          averageScore
        }
      }
    }
    mediaListEntry {
      ...ListEntryFields
      userId
      priority
      private
      hiddenFromStatusLists
      customLists
      advancedScores
    }
  }
}
]] .. Fields.media .. Fields.list_entry

local GET_MANGA = [[
query GetManga($id: Int!, $isAdult: Boolean) {
  Media(id: $id, type: MANGA, isAdult: $isAdult) {
    ...MediaSummary
    mediaListEntry { ...ListEntryFields }
  }
}
]] .. Fields.media .. Fields.list_entry

local SEARCH_MANGA = [[
query SearchManga($search: String!, $isAdult: Boolean) {
  Page(page: 1, perPage: 15) {
    media(search: $search, type: MANGA, isAdult: $isAdult, sort: SEARCH_MATCH) {
      ...MediaSummary
      mediaListEntry { ...ListEntryFields }
    }
  }
}
]] .. Fields.media .. Fields.list_entry

local function adultArgument(api)
    if api.filter_adult_content then
        return false
    end
end

local function visibleItems(api, items)
    local visible = {}
    for index = 1, #items do
        local media = items[index]
        if Common.isVisible(api, media) then
            visible[#visible + 1] = media
        end
    end
    return visible
end

---@param options? CatalogOptions
---@param page? integer One-based AniList page (default 1)
---@return AniListMediaPage|nil, string?
function Catalog:browse(options, page)
    options = options or {}
    page = page or 1
    if not Common.isPositiveInt(page) then
        return nil, "A positive page number is required"
    end
    local year = options.year
    if year ~= nil and (not Common.isPositiveInt(year) or year > 9999) then
        return nil, "A publication year from 1 to 9999 is required"
    end
    local search = options.search ~= "" and options.search or nil
    local sort = options.sort or (search and "SEARCH_MATCH")
    local result, err = self:request(BROWSE, {
        page = page,
        perPage = Common.PAGE_SIZE,
        type = options.type or "MANGA",
        format = options.format,
        status = options.status,
        sort = sort and { sort } or nil,
        search = search,
        tag = options.tag,
        genre = options.genre,
        season = options.season,
        startDateLike = year and string.format("%04d%%", year) or nil,
        isAdult = adultArgument(self),
    })
    if not result then
        return nil, err
    end
    local data, page_err = Common.page(result, "media")
    if not data then
        return nil, page_err
    end
    return { items = visibleItems(self, data.media), has_next = data.pageInfo.hasNextPage }
end

local function getSingleMedia(api, query, media_id)
    if not Common.isPositiveInt(media_id) then
        return nil, "A positive media ID is required"
    end
    local result, err = api:request(query, { id = media_id, isAdult = adultArgument(api) })
    if not result then
        return nil, err
    end
    local media, media_err = Common.dataField(result, "Media")
    if not media then
        return nil, media_err
    end
    if not Common.isVisible(api, media) then
        return nil, "AniList media not found"
    end
    return media
end

--- Fetches one anime or manga by ID; mediaListEntry belongs to the authenticated viewer.
function Catalog:getMediaDetails(media_id)
    local media, err = getSingleMedia(self, GET_DETAILS, media_id)
    if not media then
        return nil, err
    end
    -- AniList cannot apply isAdult to a media's nested relations or tags.
    if self.filter_adult_content then
        if type(media.relations) == "table" and type(media.relations.edges) == "table" then
            local visible = {}
            for index = 1, #media.relations.edges do
                local edge = media.relations.edges[index]
                if type(edge) == "table" and Common.isVisible(self, edge.node) then
                    visible[#visible + 1] = edge
                end
            end
            media.relations.edges = visible
        end
        if type(media.tags) == "table" then
            local visible = {}
            for index = 1, #media.tags do
                local tag = media.tags[index]
                if type(tag) == "table" and tag.isAdult == false then
                    visible[#visible + 1] = tag
                end
            end
            media.tags = visible
        end
    end
    return media
end

function Catalog:getMedia(media_id)
    return getSingleMedia(self, GET_MANGA, media_id)
end

function Catalog:searchMedia(search_query)
    local result, err = self:request(SEARCH_MANGA, {
        search = search_query,
        isAdult = adultArgument(self),
    })
    if not result then
        return nil, err
    end
    local data = Common.dataField(result, "Page")
    if not data or type(data.media) ~= "table" then
        return nil, Common.INVALID_RESPONSE
    end
    return visibleItems(self, data.media)
end

return Catalog
