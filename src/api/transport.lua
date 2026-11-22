local https = require("ssl.https")
local ltn12 = require("ltn12")
local JSON = require("rapidjson")

local Transport = {}
local GRAPHQL_URL = "https://graphql.anilist.co"
local GRAPHQL_MAX_BYTES = 1024 * 1024
local IMAGE_MAX_BYTES = 2 * 1024 * 1024

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

local function receive(request, max_bytes, timeout)
    local chunks, size = {}, 0
    local too_large = false
    request.redirect = false
    request.sink = function(chunk)
        if chunk and #chunk > 0 then
            size = size + #chunk
            if size > max_bytes then
                too_large = true
                return nil, "Response is too large"
            end
            chunks[#chunks + 1] = chunk
        end
        return 1
    end

    -- LuaSec uses this module-level timeout for synchronous requests.
    local previous_timeout = https.TIMEOUT
    if timeout then https.TIMEOUT = timeout end
    local ok, res, code = pcall(https.request, request)
    if timeout then https.TIMEOUT = previous_timeout end
    if too_large then
        return nil, nil, "Response is too large"
    end
    local status = ok and res and tonumber(code)
    if not status then
        -- Do not propagate raw transport exceptions: callers may log these errors.
        return nil, nil, "Network error contacting AniList"
    end
    return table.concat(chunks), status
end

local function graphQLError(errors, token)
    local first = type(errors) == "table" and errors[1]
    local message = type(first) == "table" and first.message
    if type(message) == "string" and message ~= ""
            and not (token and token ~= "" and message:find(token, 1, true)) then
        return message
    end
    return "AniList request failed"
end

--- Sends a GraphQL request and returns its decoded envelope, or nil, error.
function Transport.request(self, query, variables)
    local ok, body = pcall(JSON.encode, { query = query, variables = variables })
    if not ok or type(body) ~= "string" then
        return nil, "Unable to encode AniList request"
    end

    local headers = {
        ["Content-Type"] = "application/json",
        ["Content-Length"] = #body,
        ["Accept"] = "application/json",
    }
    if self.token and self.token ~= "" then
        headers.Authorization = "Bearer " .. self.token
    end

    local response, status, err = receive({
        url = GRAPHQL_URL,
        method = "POST",
        headers = headers,
        source = ltn12.source.string(body),
    }, GRAPHQL_MAX_BYTES)
    if not response then
        return nil, err
    end
    if status == 429 then
        return nil, "AniList rate limit reached (HTTP 429)"
    end

    local decoded_ok, decoded = pcall(JSON.decode, response)
    if decoded_ok and type(decoded) == "table" then
        normalizeJsonNull(decoded)
        if decoded.errors then
            return nil, graphQLError(decoded.errors, self.token)
        end
    end
    if status < 200 or status >= 300 then
        return nil, "AniList request failed (HTTP " .. status .. ")"
    end
    if not decoded_ok or type(decoded) ~= "table" then
        return nil, "Error decoding AniList JSON (HTTP " .. status .. ")"
    end
    return decoded
end

--- Downloads one HTTPS image as bytes, without authorization; no caching is performed.
function Transport.downloadImage(image_url, limits)
    if type(image_url) ~= "string" or not image_url:match("^https://") then
        return nil, "Unable to download image"
    end
    local max_bytes = limits and math.min(limits.bytes, IMAGE_MAX_BYTES) or IMAGE_MAX_BYTES
    local body, status = receive({ url = image_url }, max_bytes, limits and limits.timeout)
    if status ~= 200 or body == "" then
        return nil, "Unable to download image"
    end
    return body
end

return Transport
