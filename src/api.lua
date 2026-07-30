local https = require("ssl.https")
local ltn12 = require("ltn12")
local JSON = require("rapidjson")
-- local logger = require("logger")

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

function KanisyncApi:new(token)
  local obj = setmetatable({}, self)
  obj:init(token)
  return obj
end

---@param token string
function KanisyncApi:init(token)
  self.token = token
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
  query ($id: Int!) {
    Media(id: $id, type: MANGA) {
      id
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
  query ($search: String!) {
    Page(page: 1, perPage: 15) {
      media(search: $search, type: MANGA, sort: SEARCH_MATCH) {
        id
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
function KanisyncApi.downloadCover(image_url)
  local chunks = {}
  local success, res, code = pcall(https.request, {
    url = image_url,
    sink = ltn12.sink.table(chunks),
  })

  if not success or not res or tonumber(code) ~= 200 then
    return nil, "Unable to download cover"
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

---Updates the reading status for a user's list entry
---@param list_entry_id number|nil
---@param media_id number|nil
---@param status ReadingStatus
---@return table|nil
---@return string|nil
function KanisyncApi:updateMediaListStatus(list_entry_id, media_id, status)
  local mutation = [[
  mutation ($listEntryId: Int, $mediaId: Int, $status: MediaListStatus) {
    SaveMediaListEntry(id: $listEntryId, mediaId: $mediaId, status: $status) {
      id
      status
    }
  }
  ]]

  local variables = {
    listEntryId = list_entry_id,
    mediaId = media_id,
    status = status,
  }

  local result, error = self:request(mutation, variables)

  if error then
    return nil, error
  end
  if not result.data or not result.data.SaveMediaListEntry then
    return nil, "AniList returned an invalid response"
  end

  return result.data.SaveMediaListEntry
end

---@param list_entry_id number|nil
---@param media_id number|nil
---@param note string
---@return table|nil
---@return string|nil
function KanisyncApi:updateMediaListNote(list_entry_id, media_id, note)
  local mutation = [[
  mutation ($listEntryId: Int, $mediaId: Int, $notes: String!) {
    SaveMediaListEntry(id: $listEntryId, mediaId: $mediaId, notes: $notes) {
        id
        notes
    }
  }
  ]]

  local variables = {
    listEntryId = list_entry_id,
    mediaId = media_id,
    notes = note,
  }

  local result, error = self:request(mutation, variables)

  if error then
    return nil, error
  end
  if not result.data or not result.data.SaveMediaListEntry then
    return nil, "AniList returned an invalid response"
  end

  return result.data.SaveMediaListEntry
end

---@param list_entry_id number|nil
---@param media_id number|nil
---@param score number
---@return table|nil result
---@return string|nil error
function KanisyncApi:updateMediaListScore(list_entry_id, media_id, score)
  local mutation = [[
  mutation ($listEntryId: Int, $mediaId: Int, $score: Float!) {
    SaveMediaListEntry(id: $listEntryId, mediaId: $mediaId, score: $score) {
        id
        score
    }
  }
  ]]

  local variables = {
    listEntryId = list_entry_id,
    mediaId = media_id,
    score = score
  }

  local result, error = self:request(mutation, variables)

  if error then
    return nil, error
  end
  if not result.data or not result.data.SaveMediaListEntry then
    return nil, "AniList returned an invalid response"
  end

  return result.data.SaveMediaListEntry
end

return KanisyncApi
