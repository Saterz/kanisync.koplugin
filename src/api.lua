local https = require("ssl.https")
local ltn12 = require("ltn12")
local JSON = require("rapidjson")

---@class KanisyncApi
---@field token string User provided AniList token
local KanisyncApi = {}
KanisyncApi.__index = KanisyncApi

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
---@return table|nil response
---@return string|nil error
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
    return normalizeJsonNull(decoded)
  else
    return nil, "Error decoding JSON. HTTP Code: " .. tostring(code)
  end
end

---@param search_query string
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
  if not result then
    return nil, "AniList returned an empty response"
  end
  if result.errors then
    return nil, result.errors[1] and result.errors[1].message or "AniList request failed"
  end
  if not result.data or not result.data.Page then
    return nil, "AniList returned an invalid response"
  end

  return result.data.Page.media or {}
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

return KanisyncApi
