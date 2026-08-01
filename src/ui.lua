local UIManager = require("ui/uimanager")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local Geom = require("ui/geometry")
local ImageWidget = require("ui/widget/imagewidget")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local SpinWidget = require("ui/widget/spinwidget")
local Menu = require("ui/widget/menu")
local MultiConfirmBox = require("ui/widget/multiconfirmbox")
local NetworkMgr = require("ui/network/manager")
local RenderImage = require("ui/renderimage")
local Screen = require("device").screen
local Size = require("ui/size")
-- local logger = require("logger")
local T = require("ffi/util").template
local _ = require("gettext")

local statuses = {
    { text = _("Reading"),   value = "CURRENT" },
    { text = _("Planning"),  value = "PLANNING" },
    { text = _("Completed"), value = "COMPLETED" },
    { text = _("On hold"),   value = "PAUSED" },
    { text = _("Dropped"),   value = "DROPPED" },
}

local function getStatusLabel(value)
    for status_index = 1, #statuses do
        local status = statuses[status_index]
        if status.value == value then
            return status.text
        end
    end
    return value
end

---@class KanisyncUI
---@field plugin Kanisync
local KanisyncUI = {}
KanisyncUI.__index = KanisyncUI

function KanisyncUI:new(plugin)
    local obj = setmetatable({}, self)
    obj:init(plugin)
    return obj
end

---@param plugin Kanisync
function KanisyncUI:init(plugin)
    self.plugin = plugin
end

---@param anilist_data KanisyncEntry?
---@param username string
function KanisyncUI:main_menu(anilist_data, username)
    local is_token_provided = self.plugin:hasToken()

    local menu = {}
    if not is_token_provided then
        table.insert(menu, { text = "Token not found", enabled = false })
    else
        table.insert(menu, {
            text = _("Connected as ") .. username,
            enabled = false,
        })
        if anilist_data ~= nil then
            table.insert(menu, {
                text = T(_('Linked to "%1"'), anilist_data.title),
                sub_item_table = self:manageEntry(anilist_data)
            })
        else
            table.insert(menu, {
                text = _("Link book to AniList"),
                keep_menu_open = false,
                callback = function()
                    NetworkMgr:runWhenOnline(function()
                        self.plugin:linkBookToAniList()
                    end)
                end,
            })
        end
    end

    table.insert(menu, {
        text = _("About"),
        keep_menu_open = true,
        callback = function()
            self.about(self.plugin)
        end,
    })

    return menu
end

---@param anilist_data KanisyncEntry
function KanisyncUI:manageEntry(anilist_data)
    local user_list_entry = anilist_data.user_list_entry

    local hasNotes = user_list_entry.notes ~= nil and user_list_entry.notes ~= ""
    local hasScore = user_list_entry.score ~= nil
    return {
        {
            text = _("Pull changes"),
            callback = function()
                NetworkMgr:runWhenOnline(function()
                    local id = anilist_data.id
                    local media, error = self.plugin.api:getMedia(id)
                    if error or not media then
                        self.ephemeralMessage(error or _("AniList returned an invalid response"))
                        return
                    end

                    self.ephemeralMessage(_("Changes pulled from AniList."))

                    self.plugin:saveCurrentBookAniListData(media)
                end)
            end
        },
        {
            text = _("Progress"),
            sub_item_table = self:progressMenu(anilist_data)
        },
        {
            text = T(_("Status: %1"), getStatusLabel(user_list_entry.status)),
            sub_item_table = self:updateStatusMenu(anilist_data)
        },
        {
            text = hasNotes and _("Edit note") or _("Add note"),
            callback = function()
                local search_query = user_list_entry.notes
                local dialog
                dialog = InputDialog:new {
                    title = hasNotes and _("Edit note") or _("Add note"),
                    description = hasNotes and _("Edit your personal note for this AniList entry.") or _("Add a personal note to this AniList entry."),
                    input = search_query,
                    buttons = {
                        {
                            {
                                text = _("Cancel"),
                                id = "close",
                                callback = function()
                                    UIManager:close(dialog)
                                end,
                            },
                            {
                                text = _("Submit"),
                                is_enter_default = true,
                                callback = function()
                                    local query = dialog:getInputText()
                                    UIManager:close(dialog)
                                    NetworkMgr:runWhenOnline(function()
                                        local result, error = self.plugin.api:updateMediaList(user_list_entry.id,
                                            anilist_data.id, { notes = query })
                                        if error or not result then
                                            self.ephemeralMessage(error or _("AniList returned an invalid response"))
                                            return
                                        end
                                        self.plugin:updateCurrentBookUserMetadata("notes", result.notes)
                                    end)
                                end,
                            },
                        },
                    },
                }
                UIManager:show(dialog)
                dialog:onShowKeyboard()
            end
        },
        {
            text = user_list_entry.score
                and T(
                    _("Score: %1 / %2"),
                    user_list_entry.score,
                    self.plugin.score_formats[
                    self.plugin.user.mediaListOptions.scoreFormat
                    ].maximum
                )
                or _("Score: Not rated"),
            callback = function()
                local score_format_name = self.plugin.user.mediaListOptions.scoreFormat
                local score_format = self.plugin.score_formats[score_format_name]
                if not score_format then
                    self.ephemeralMessage(_("Unable to determine your AniList score format."))
                    return
                end

                local function saveScore(score)
                    NetworkMgr:runWhenOnline(function()
                        local result, error = self.plugin.api:updateMediaList(user_list_entry.id, anilist_data.id,
                            { score = score })
                        if error or not result then
                            self.ephemeralMessage(error or _("AniList returned an invalid response"))
                            return
                        end
                        self.plugin:updateCurrentBookUserMetadata("score", result.score)
                    end)
                end

                local uses_spin_widget = score_format_name == "POINT_3"
                    or score_format_name == "POINT_5"
                    or score_format_name == "POINT_10"
                if uses_spin_widget then
                    UIManager:show(SpinWidget:new {
                        title_text = hasScore and _("Edit score") or _("Add score"),
                        info_text = T(_("%1 (%2-%3)"), score_format.label, score_format.minimum, score_format.maximum),
                        value = user_list_entry.score or score_format.minimum,
                        value_min = score_format.minimum,
                        value_max = score_format.maximum,
                        value_step = score_format.step,
                        value_hold_step = score_format.step,
                        precision = "%d",
                        ok_text = _("Save"),
                        callback = function(spin)
                            saveScore(spin.value)
                        end,
                    })
                    return
                end

                local dialog
                dialog = InputDialog:new {
                    title = hasScore and _("Edit score") or _("Add score"),
                    description = T(_("Enter a %1 score from %2 to %3."), score_format.label, score_format.minimum, score_format.maximum),
                    input = hasScore and tostring(user_list_entry.score) or "",
                    input_type = "number",
                    buttons = {
                        {
                            {
                                text = _("Cancel"),
                                id = "close",
                                callback = function()
                                    UIManager:close(dialog)
                                end,
                            },
                            {
                                text = _("Save"),
                                is_enter_default = true,
                                callback = function()
                                    local score = tonumber(dialog:getInputText())
                                    local valid_step = score and math.abs(score / score_format.step
                                        - math.floor(score / score_format.step + 0.5)) < 0.000001
                                    if not valid_step or score < score_format.minimum or score > score_format.maximum then
                                        self.ephemeralMessage(T(_("Enter a score from %1 to %2 in increments of %3."),
                                            score_format.minimum, score_format.maximum, score_format.step))
                                        return
                                    end
                                    UIManager:close(dialog)
                                    saveScore(score)
                                end,
                            },
                        },
                    },
                }
                UIManager:show(dialog)
                dialog:onShowKeyboard()
            end
        },
        {
            text = _("Change linked book"),
            keep_menu_open = false,
            callback = function()
                NetworkMgr:runWhenOnline(function()
                    self.plugin:linkBookToAniList()
                end)
            end,
        },
        {
            text = _("Unlink book"),
            callback = function()
                self.plugin:unlinkBook()
            end
        },
    }
end

---@param anilist_data KanisyncEntry
function KanisyncUI:updateStatusMenu(anilist_data)
    ---@type table
    local status_items = {}
    ---@type ReadingStatus
    local selected_status = anilist_data.user_list_entry.status
    for status_index = 1, #statuses do
        local status = statuses[status_index]
        table.insert(status_items, {
            text = _(status.text),
            radio = true,
            checked_func = function()
                return selected_status == status.value
            end,
            callback = function()
                selected_status = status.value
            end
        })
    end

    table.insert(status_items, {
        text = _("Save"),
        callback = function()
            NetworkMgr:runWhenOnline(function()
                local result, error = self.plugin.api:updateMediaList(anilist_data.user_list_entry.id, anilist_data.id,
                    { status = selected_status })
                if error or not result then
                    self.ephemeralMessage(error or _("AniList returned an invalid response"))
                    return
                end
                self.plugin:updateCurrentBookUserMetadata("status", result.status)
            end)
        end
    })

    return status_items
end

function KanisyncUI:progressMenu(anilist_data)
    local user_list_entry = anilist_data.user_list_entry

    local chapter_text = anilist_data.chapters and T("Chapter %1 of %2", user_list_entry.progress, anilist_data.chapters) or
        T("Chapter %1", user_list_entry.progress)
    local volume_text = anilist_data.volumes and
        T("Volume %1 of %2", user_list_entry.progress_volumes, anilist_data.volumes) or
        T("Volume %1", user_list_entry.progress_volumes)
    local menu = {
        {
            text = _(chapter_text),
            callback = function()
                UIManager:show(SpinWidget:new {
                    title_text = _("Chapter progress"),
                    value = user_list_entry.progress,
                    value_min = 0,
                    value_max = anilist_data.chapters or math.huge,
                    value_step = 1,
                    value_hold_step = 10,
                    unit = _("chapters"),
                    ok_text = _("Set"),
                    callback = function(spin)
                        NetworkMgr:runWhenOnline(function()
                            local result, error = self.plugin.api:updateMediaList(user_list_entry.id, anilist_data.id,
                                { progress = spin.value })
                            if error or not result then
                                self.ephemeralMessage(error or _("AniList returned an invalid response"))
                                return
                            end
                            self.plugin:updateCurrentBookUserMetadata("progress", result.progress)
                        end)
                    end
                })
            end
        },
        {
            text = _(volume_text),
            callback = function()
                UIManager:show(SpinWidget:new {
                    title_text = _("Volume progress"),
                    value = user_list_entry.progress_volumes,
                    value_min = 0,
                    value_max = anilist_data.volumes or math.huge,
                    value_step = 1,
                    value_hold_step = 10,
                    unit = _("volumes"),
                    ok_text = _("Set"),
                    callback = function(spin)
                        NetworkMgr:runWhenOnline(function()
                            local result, error = self.plugin.api:updateMediaList(user_list_entry.id, anilist_data.id,
                                { progressVolumes = spin.value })
                            if error or not result then
                                self.ephemeralMessage(error or _("AniList returned an invalid response"))
                                return
                            end
                            self.plugin:updateCurrentBookUserMetadata("progress_volumes", result.progressVolumes)
                        end)
                    end
                })
            end
        }
    }

    return menu
end

function KanisyncUI.about(plugin)
    UIManager:show(InfoMessage:new({
        text = "Kanisync\n\nSync your reading progress with AniList\n\nVersion: v" .. plugin.version,
    }))
end

function KanisyncUI:progressUpdatePrompt(anilist_data)
    local user_list_entry = anilist_data.user_list_entry

    local next_chapter = user_list_entry.progress + 1
    local next_volume = user_list_entry.progress_volumes + 1
    UIManager:show(MultiConfirmBox:new {
        text = T(_("Linked to %1. Update progress?"), anilist_data.title),
        choice1_text = T(_("Set chapter to %1"), next_chapter),
        choice1_enabled = next_chapter <= (anilist_data.chapters or math.huge),
        choice1_callback = function()
            NetworkMgr:runWhenOnline(function()
                local result, error = self.plugin.api:updateMediaList(user_list_entry.id, anilist_data.id,
                    { progress = user_list_entry.progress + 1 })
                if error or not result then
                    self.ephemeralMessage(error or _("AniList returned an invalid response"))
                    return
                end
                self.plugin:updateCurrentBookUserMetadata("progress", result.progress)
            end)
        end,
        choice2_text = T(_("Set volume to %1"), next_volume),
        choice2_enabled = next_volume <= (anilist_data.volumes or math.huge),
        choice2_callback = function()
            NetworkMgr:runWhenOnline(function()
                local result, error = self.plugin.api:updateMediaList(user_list_entry.id, anilist_data.id,
                    { progressVolumes = user_list_entry.progress_volumes + 1 })
                if error or not result then
                    self.ephemeralMessage(error or _("AniList returned an invalid response"))
                    return
                end
                self.plugin:updateCurrentBookUserMetadata("progress_volumes", result.progressVolumes)
            end)
        end,
    })
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

---@param search_query string
---@param search_callback fun(search_query: string)
---@param no_results? boolean
function KanisyncUI.searchDialog(search_query, search_callback, no_results)
    local dialog
    dialog = InputDialog:new {
        title = _("Search AniList"),
        description = no_results and _("No matches were found. Adjust the search query and try again.")
            or _("Adjust the search query."),
        input = search_query,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Search"),
                    is_enter_default = true,
                    callback = function()
                        local query = dialog:getInputText()
                        if query and not query:match("^%s*$") then
                            UIManager:close(dialog)
                            NetworkMgr:runWhenOnline(function()
                                search_callback(query)
                            end)
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

---@param media table
---@param select_callback fun(media: table): string|nil
---@param cover_loader fun(url: string): string|nil
function KanisyncUI:previewMedia(media, select_callback, cover_loader)
    local title = getMediaTitle(media)
    local details = {}
    if media.format then
        table.insert(details, media.format)
    end
    if media.startDate and media.startDate.year then
        table.insert(details, tostring(media.startDate.year))
    end
    if media.chapters then
        table.insert(details, T(_("%1 chapters"), media.chapters))
    end
    if media.volumes then
        table.insert(details, T(_("%1 volumes"), media.volumes))
    end

    local confirm = ConfirmBox:new {
        text = title .. (#details > 0 and "\n" .. table.concat(details, " • ") or ""),
        ok_text = _("Link"),
        ok_callback = function()
            local error = select_callback(media)
            if error then
                self.ephemeralMessage(error)
                return
            end
        end,
    }

    local cover_url = type(media.coverImage) == "table"
        and type(media.coverImage.medium) == "string"
        and media.coverImage.medium
    if cover_url then
        local max_width = confirm:getAddedWidgetAvailableWidth()
        local max_height = math.floor(Screen:getHeight() * 0.45)
        local cover, cover_width, cover_height = renderCover(
            media._cover_data or cover_loader(cover_url),
            max_width,
            max_height
        )
        if cover then
            confirm:addWidget(CenterContainer:new {
                dimen = Geom:new {
                    w = max_width,
                    h = cover_height,
                },
                ImageWidget:new {
                    image = cover,
                    width = cover_width,
                    height = cover_height,
                },
            })
        end
    end

    UIManager:show(confirm)
end

---@param media_list table
---@param search_query string
---@param select_callback fun(media: table): string|nil
---@param search_callback fun(search_query: string)
---@param cover_loader fun(url: string): string|nil
function KanisyncUI:mediaChooser(media_list, search_query, select_callback, search_callback, cover_loader)
    if #media_list == 0 then
        self.searchDialog(search_query, search_callback, true)
        return
    end

    local loading = InfoMessage:new { text = _("Loading cover images…") }
    UIManager:show(loading)
    UIManager:nextTick(function()
        local thumbnail_width = Screen:scaleBySize(48)
        local thumbnail_height = Screen:scaleBySize(68)
        local thumbnail_buffers = {}
        local items = {
            {
                text = _("Adjust search..."),
                callback = function()
                    UIManager:nextTick(function()
                        self.searchDialog(search_query, search_callback)
                    end)
                end,
            },
        }

        for media_index = 1, #media_list do
            local media = media_list[media_index]

            local cover_widget
            local cover_url = type(media.coverImage) == "table"
                and type(media.coverImage.medium) == "string"
                and media.coverImage.medium
            if cover_url then
                media._cover_data = cover_loader(cover_url)
                local cover = renderCover(media._cover_data, thumbnail_width, thumbnail_height)
                if cover then
                    table.insert(thumbnail_buffers, cover)
                    cover_widget = CenterContainer:new {
                        dimen = Geom:new {
                            w = thumbnail_width,
                            h = thumbnail_height,
                        },
                        ImageWidget:new {
                            image = cover,
                            image_disposable = false,
                        },
                    }
                end
            end

            table.insert(items, {
                text = getMediaTitle(media),
                mandatory = media.mediaListEntry and _("In Library") or nil,
                state = cover_widget,
                callback = function()
                    UIManager:nextTick(function()
                        self:previewMedia(media, select_callback, cover_loader)
                    end)
                end,
            })
        end

        local chooser
        chooser = Menu:new {
            title = T(_("AniList results for “%1”"), search_query),
            item_table = items,
            state_w = thumbnail_width + Size.span.horizontal_default,
            items_per_page = 6,
            multilines_forced = true,
            dithered = true,
            close_callback = function()
                UIManager:close(chooser)
                for buffer_index = 1, #thumbnail_buffers do
                    thumbnail_buffers[buffer_index]:free()
                end
                thumbnail_buffers = {}
            end,
        }
        UIManager:close(loading)
        UIManager:show(chooser)
    end)
end

---@param error_message string
function KanisyncUI.ephemeralMessage(error_message, dialog)
    if dialog ~= nil then
        UIManager:close(dialog)
    end
    UIManager:show(InfoMessage:new {
        text = _(error_message),
        timeout = 3,
    })
end

return KanisyncUI
