local https = require("ssl.https")
local ltn12 = require("ltn12")
local JSON = require("rapidjson")
-- local logger = require("logger")

---@alias AniListFuzzyDateInput { year?: integer, month?: integer, day?: integer }

---@alias MediaListUpdateValues { progress?: integer, progressVolumes?: integer, score?: number, notes?: string, status?: ReadingStatus, repeat_count?: integer, priority?: integer, private?: boolean, hiddenFromStatusLists?: boolean, customLists?: string[], advancedScores?: number[], startedAt?: AniListFuzzyDateInput, completedAt?: AniListFuzzyDateInput }

---@class KanisyncApi
---@field token string User provided AniList token
local KanisyncApi = {}
KanisyncApi.__index = KanisyncApi

---@param value table
---@return table|nil
local function normalizeJsonNull(value)
    if value == JSON.null then
        return nil
    end
    if type(value) == "table" then
        for key, child in pairs(value) do
            value[key] = normalizeJsonNull(child)
        end
    end
    return value
end

function KanisyncApi:new(token, filter_adult_content)
    local obj = setmetatable({}, self)
    obj:init(token, filter_adult_content)
    return obj
end

---@param token string
---@param filter_adult_content boolean
function KanisyncApi:init(token, filter_adult_content)
    self.token = token
    self.filter_adult_content = filter_adult_content ~= false
end

---@param query string
---@param variables? table
---@return table response
---@return nil error
---@overload fun(query: string, variables?: table): nil, string
function KanisyncApi:request(query, variables)
    local url = "https://graphql.anilist.co"

    local payload = {
        query = query,
        variables = variables or {}
    }

    local body = JSON.encode(payload)
    local response_chunks = {}

    local headers = {
        ["Content-Type"] = "application/json",
        ["Content-Length"] = #body
    }

    if self.token ~= nil and self.token ~= "" then
        headers["Authorization"] = "Bearer " .. self.token
    end

    local res, code = https.request({
        url = url,
        method = "POST",
        headers = headers,
        source = ltn12.source.string(body),
        sink = ltn12.sink.table(response_chunks)
    })

    if not res then
        return nil, "Network error: " .. tostring(code)
    end

    local response_string = table.concat(response_chunks)
    local success, decoded = pcall(JSON.decode, response_string)

    if success and type(decoded) == "table" then
        local result = normalizeJsonNull(decoded)
        if not result then
            return nil, "AniList didn't send a response"
        end
        if result.errors then
            return nil, result.errors[1] and result.errors[1].message or "AniList request failed"
        end
        return result, nil
    else
        return nil, "Error decoding JSON. HTTP Code: " .. tostring(code)
    end
end

function KanisyncApi:getMedia(media_id)
    local query = [[
  query ($id: Int!, $isAdult: Boolean) {
    Media(id: $id, type: MANGA, isAdult: $isAdult) {
      id
      isAdult
      title {
        userPreferred
        romaji
        english
        native
      }
      format
      chapters
      volumes
      startDate {
        year
      }
      coverImage {
        medium
      }
      mediaListEntry {
        id
        mediaId
        status
        score
        progress
        progressVolumes
        repeat
        notes
        startedAt {
          year
          month
          day
        }
        completedAt {
          year
          month
          day
        }
        createdAt
        updatedAt
      }
    }
  }
  ]]

    local variables = {
        id = media_id
    }

    if self.filter_adult_content then
        variables.isAdult = false
    end

    local result, error = self:request(query, variables)

    if error then
        return nil, error
    end
    if not result.data or not result.data.Media then
        return nil, "AniList returned an invalid response"
    end

    return result.data.Media
end

---@param search_query string
---@return table response
---@return nil error
---@overload fun(query: string, variables?: table): nil, string
function KanisyncApi:searchMedia(search_query)
    local query = [[
  query ($search: String!, $isAdult: Boolean) {
    Page(page: 1, perPage: 15) {
      media(search: $search, type: MANGA, isAdult: $isAdult, sort: SEARCH_MATCH) {
        id
        isAdult
        title {
          userPreferred
          romaji
          english
          native
        }
        format
        chapters
        volumes
        startDate {
          year
        }
        coverImage {
          medium
        }
        mediaListEntry {
          id
          mediaId
          status
          score
          progress
          progressVolumes
          repeat
          notes
          startedAt {
            year
            month
            day
          }
          completedAt {
            year
            month
            day
          }
          createdAt
          updatedAt
        }
      }
    }
  }
  ]]

    local variables = {
        search = search_query
    }

    if self.filter_adult_content then
        variables.isAdult = false
    end

    local result, error = self:request(query, variables)

    if error then
        return nil, error
    end
    if not result.data or not result.data.Page then
        return nil, "AniList returned an invalid response"
    end

    return result.data.Page.media
end

---@param image_url string
---@return string|nil image_data
---@return string|nil error
function KanisyncApi.downloadImage(image_url)
    local chunks = {}
    local success, res, code = pcall(https.request, {
        url = image_url,
        sink = ltn12.sink.table(chunks),
    })

    if not success or not res or tonumber(code) ~= 200 then
        return nil, "Unable to download image"
    end

    return table.concat(chunks)
end

---@return table response
---@return nil error
---@overload fun(query: string, variables?: table): nil, string
function KanisyncApi:getUser()
    local query = [[
  query {
    Viewer {
      id
      name
      mediaListOptions {
        scoreFormat
      }
    }
  }
  ]]

    local result, error = self:request(query)
    if error then
        return nil, error
    end
    if not result.data or not result.data.Viewer then
        return nil, "AniList returned an invalid response"
    end

    return result.data.Viewer
end

---Creates or updates an AniList media-list entry.
---@param list_entry_id? integer Existing MediaList entry ID
---@param media_id? integer AniList media ID, used when no entry ID is available
---@param values MediaListUpdateValues Fields to update
---@return table|nil result Updated MediaList entry
---@return string|nil error_message Request or response error
function KanisyncApi:updateMediaList(list_entry_id, media_id, values)
    if list_entry_id == nil and media_id == nil then
        return nil, "A list entry ID or media ID is required"
    end

    if type(values) ~= "table" then
        return nil, "Update values are required"
    end

    local mutation = [[
  mutation UpdateMediaListEntry(
    $listEntryId: Int
    $mediaId: Int
    $status: MediaListStatus
    $score: Float
    $progress: Int
    $progressVolumes: Int
    $repeat: Int
    $priority: Int
    $private: Boolean
    $notes: String
    $hiddenFromStatusLists: Boolean
    $customLists: [String]
    $advancedScores: [Float]
    $startedAt: FuzzyDateInput
    $completedAt: FuzzyDateInput
  ) {
    SaveMediaListEntry(
      id: $listEntryId
      mediaId: $mediaId
      status: $status
      score: $score
      progress: $progress
      progressVolumes: $progressVolumes
      repeat: $repeat
      priority: $priority
      private: $private
      notes: $notes
      hiddenFromStatusLists: $hiddenFromStatusLists
      customLists: $customLists
      advancedScores: $advancedScores
      startedAt: $startedAt
      completedAt: $completedAt
    ) {
      id
      mediaId
      status
      score
      progress
      progressVolumes
      repeat
      priority
      private
      notes
      hiddenFromStatusLists
      customLists
      advancedScores
      startedAt {
        year
        month
        day
      }
      completedAt {
        year
        month
        day
      }
      updatedAt
    }
  }
  ]]

    local variables = {
        listEntryId = list_entry_id,

        -- Use mediaId only when an entry ID is unavailable.
        mediaId = list_entry_id == nil and media_id or nil,

        status = values.status,
        score = values.score,
        progress = values.progress,
        progressVolumes = values.progressVolumes,
        ["repeat"] = values.repeat_count,
        priority = values.priority,
        private = values.private,
        notes = values.notes,
        hiddenFromStatusLists = values.hiddenFromStatusLists,
        customLists = values.customLists,
        advancedScores = values.advancedScores,
        startedAt = values.startedAt,
        completedAt = values.completedAt,
    }

    local result, error = self:request(mutation, variables)

    if error then
        return nil, error
    end
    if not result.data or not result.data.SaveMediaListEntry then
        return nil, "AniList returned an invalid response"
    end

    return result.data.SaveMediaListEntry, nil
end

return KanisyncApi
