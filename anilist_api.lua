local https = require("ssl.https")
local ltn12 = require("ltn12")
local JSON = require("rapidjson")
local logger = require("logger")
local dump = require("dump")

local KanisyncApi = {}
KanisyncApi.__index = KanisyncApi

function KanisyncApi:new(token)
  local obj = setmetatable({}, self)
  obj:init(token)
  return obj
end

function KanisyncApi:init(token)
  self.token = token or ""
end

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
    ["Content-Length"] = dump(#body)
  }
  
  -- Attach the Bearer token if the user is logged in
  if self.token and self.token ~= "" then
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
  
  -- Safely decode the JSON response in case the server returns HTML (e.g., Cloudflare errors)
  local success, decoded = pcall(JSON.decode, response_string)

  logger.dbg("KanisyncApi | response: " .. dump(decoded))

  if success then
    return decoded
  else
    return nil, "Error decoding JSON. HTTP Code: " .. tostring(code)
  end
end

return KanisyncApi
