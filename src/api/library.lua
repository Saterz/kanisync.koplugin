local Common = require("api/common")
local Fields = require("api/fields")

---@alias LibraryOptions { type?: string, status?: string, sort?: string }
---@alias AniListFuzzyDateInput { year?: integer, month?: integer, day?: integer }
---@alias MediaListUpdateValues { progress?: integer, progressVolumes?: integer, score?: number, notes?: string, status?: ReadingStatus, repeat_count?: integer, priority?: integer, private?: boolean, hiddenFromStatusLists?: boolean, customLists?: string[], advancedScores?: number[], startedAt?: AniListFuzzyDateInput, completedAt?: AniListFuzzyDateInput }

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

function Library.getUser(self)
    local result, err = self:request(GET_USER)
    if not result then
        return nil, err
    end
    return Common.dataField(result, "Viewer")
end

--- The embedded mediaListEntry belongs to user_id, which need not be the viewer.
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
    local items = {}
    for index = 1, #data.mediaList do
        local entry = data.mediaList[index]
        local media = type(entry) == "table" and entry.media
        if Common.isVisible(self, media) then
            entry.media = nil -- Move the entry onto the media without creating a reference cycle.
            media.mediaListEntry = entry
            items[#items + 1] = media
        end
    end
    -- Page.mediaList has no isAdult argument. Don't backfill; even an empty page can have a successor.
    return { items = items, has_next = data.pageInfo.hasNextPage }
end

--- Creates or updates an AniList entry, preferring the list-entry ID when both IDs are supplied.
---@param list_entry_id? integer
---@param media_id? integer
---@param values MediaListUpdateValues
---@return table|nil, string?
function Library.updateMediaList(self, list_entry_id, media_id, values)
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
function Library.deleteMediaList(self, list_entry_id)
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
