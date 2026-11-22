local Common = require("api/common")
local Fields = require("api/fields")

---@alias LibraryOptions { type?: string, status?: string, sort?: string, search?: string }
---@alias AniListFuzzyDateInput { year?: integer, month?: integer, day?: integer }
---@alias MediaListUpdateValues { progress?: integer, progressVolumes?: integer, score?: number, notes?: string, status?: ReadingStatus, repeat_count?: integer, priority?: integer, private?: boolean, hiddenFromStatusLists?: boolean, customLists?: string[], advancedScores?: number[], startedAt?: AniListFuzzyDateInput, completedAt?: AniListFuzzyDateInput }

-- KOReader supplies UTF-8 case folding; standalone callers may not have it.
local has_util, util = pcall(require, "util")
local lowercase_utf8 = has_util and type(util) == "table"
    and type(util.stringLower) == "function" and util.stringLower
local title_fields = { "userPreferred", "romaji", "english", "native" }

local function lowercase(text)
    -- The native helper uses NUL-terminated strings. Also avoid turning a
    -- nonempty search into an empty needle if case folding removes characters.
    if lowercase_utf8 and not text:find("\0", 1, true) then
        local folded = lowercase_utf8(text)
        if folded and folded ~= "" then
            return folded
        end
    end
    return text:lower()
end

local function titleMatches(title, needle)
    if type(title) ~= "table" then
        return false
    end
    for index = 1, #title_fields do
        local name = title[title_fields[index]]
        if type(name) == "string" and lowercase(name):find(needle, 1, true) then
            return true
        end
    end
    return false
end

local Library = {}

local GET_USER = [[
query ViewerAccount {
  Viewer {
    id
    name
    mediaListOptions { scoreFormat }
  }
}
]]

local GET_LIBRARY = [[
query Library($userId: Int!, $type: MediaType!, $status: MediaListStatus,
    $sort: [MediaListSort], $page: Int!, $perPage: Int!) {
  Page(page: $page, perPage: $perPage) {
    pageInfo { hasNextPage }
    mediaList(userId: $userId, type: $type, status: $status, sort: $sort) {
      ...ListEntryFields
      media { ...MediaSummary }
    }
  }
}
]] .. Fields.media .. Fields.list_entry

local UPDATE = [[
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
  ) { ...ListEntryFields }
}
]] .. Fields.list_entry

local DELETE = [[
mutation RemoveListEntry($id: Int!) {
  DeleteMediaListEntry(id: $id) { deleted }
}
]]

function Library:getUser()
    local result, err = self:request(GET_USER)
    if not result then
        return nil, err
    end
    return Common.dataField(result, "Viewer")
end

--- The embedded mediaListEntry belongs to user_id, which need not be the viewer.
--- A nonempty options.search filters titles on this server page only; has_next is unchanged.
---@param user_id integer
---@param options? LibraryOptions
---@param page? integer One-based AniList page (default 1)
---@return AniListMediaPage|nil, string?
function Library:library(user_id, options, page)
    options = options or {}
    page = page or 1
    if not Common.isPositiveInt(user_id) then
        return nil, "A positive user ID is required"
    end
    if not Common.isPositiveInt(page) then
        return nil, "A positive page number is required"
    end
    local result, err = self:request(GET_LIBRARY, {
        userId = user_id,
        type = options.type or "MANGA",
        status = options.status,
        sort = options.sort and { options.sort } or nil,
        page = page,
        perPage = Common.PAGE_SIZE,
    })
    if not result then
        return nil, err
    end
    local data, page_err = Common.page(result, "mediaList")
    if not data then
        return nil, page_err
    end
    local needle = type(options.search) == "string" and options.search ~= "" and lowercase(options.search)
    local items = {}
    for index = 1, #data.mediaList do
        local entry = data.mediaList[index]
        local media = type(entry) == "table" and entry.media
        if Common.isVisible(self, media) and (not needle or titleMatches(media.title, needle)) then
            entry.media = nil -- Move the entry onto the media without creating a reference cycle.
            media.mediaListEntry = entry
            items[#items + 1] = media
        end
    end
    -- Page.mediaList supports neither title search nor isAdult. Don't backfill;
    -- even an empty filtered page can have a successor.
    return { items = items, has_next = data.pageInfo.hasNextPage }
end

--- Creates or updates an AniList entry, preferring the list-entry ID when both IDs are supplied.
---@param list_entry_id? integer
---@param media_id? integer
---@param values MediaListUpdateValues
---@return table|nil, string?
function Library:updateMediaList(list_entry_id, media_id, values)
    if list_entry_id == nil and media_id == nil then
        return nil, "A list entry ID or media ID is required"
    end
    if type(values) ~= "table" then
        return nil, "Update values are required"
    end

    local result, err = self:request(UPDATE, {
        listEntryId = list_entry_id,
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
    })
    if not result then
        return nil, err
    end
    return Common.dataField(result, "SaveMediaListEntry")
end

--- Deletes an entry by mediaListEntry.id (not the media ID).
---@param list_entry_id integer
---@return true|nil, string?
function Library:deleteMediaList(list_entry_id)
    if not Common.isPositiveInt(list_entry_id) then
        return nil, "A positive list entry ID is required"
    end
    local result, err = self:request(DELETE, { id = list_entry_id })
    if not result then
        return nil, err
    end
    local deletion, deletion_err = Common.dataField(result, "DeleteMediaListEntry")
    if not deletion then
        return nil, deletion_err
    end
    if deletion.deleted ~= true then
        return nil, "AniList did not delete the entry"
    end
    return true
end

return Library
