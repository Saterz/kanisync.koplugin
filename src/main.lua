--[[
A KOReader plugin to sync your reading progress with AniList

@module koplugin.Kanisync
]]

-- local Dispatcher = require("dispatcher")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local DataStorage = require("datastorage")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local LuaSettings = require("luasettings")
local NetworkMgr = require("ui/network/manager")
local ffiUtil = require("ffi/util")
local T = ffiUtil.template
local _ = require("gettext")

local KanisyncUI = require("ui")
local KanisyncApi = require("api")

local SETTINGS_FILE = DataStorage:getSettingsDir() .. "/kanisync_settings.lua"

local SCORE_FORMATS = {
    POINT_100 = {
        minimum = 0,
        maximum = 100,
        step = 1,
        label = "100-point",
    },
    POINT_10_DECIMAL = {
        minimum = 0,
        maximum = 10,
        step = 0.1,
        label = "10-point decimal",
    },
    POINT_10 = {
        minimum = 0,
        maximum = 10,
        step = 1,
        label = "10-point",
    },
    POINT_5 = {
        minimum = 0,
        maximum = 5,
        step = 1,
        label = "5-star",
    },
    POINT_3 = {
        minimum = 0,
        maximum = 3,
        step = 1,
        label = "3-point smiley",
    },
}

---@alias ReadingStatus string "Source: https://docs.anilist.co/reference/enum/medialiststatus#medialiststatus"
---| "CURRENT" Currently watching/reading
---| "PLANNING"	Planning to watch/read
---| "COMPLETED" Finished watching/reading
---| "DROPPED" Stopped watching/reading before completing
---| "PAUSED" Paused watching/reading
---| "REPEATING" Re-watching/reading

---@alias KanisyncEntry { id: number, title: string?, user_list_entry: { id: number?, status: ReadingStatus, score: number?, progress: number?, progress_volumes: number?, notes: string? }, fetched_at: number }

---@class Kanisync
---@field ui table KOReader UI instance injected by PluginLoader
---@field fullname string
---@field description string
---@field version string The plugin's version imported from the `_meta.lua` file
local Kanisync = WidgetContainer:extend {
    name = "kanisync",
    is_doc_only = true,
}

-- function Kanisync:onDispatcherRegisterActions()
--     Dispatcher:registerAction()
--

function Kanisync:init()
    -- self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
    self.settings = LuaSettings:open(SETTINGS_FILE)

    local token = self.settings:readSetting("anilist_token")
    if type(token) == "string" and token ~= "" then
        self.token = token
    else
        logger.warn("Kanisync | No token found in kanisync_settings.lua")
    end

    self.kanisync_ui = KanisyncUI:new(self)
    self.score_formats = SCORE_FORMATS

    local filter_adult_content =
        self.settings:readSetting("filter_adult_content")

    if filter_adult_content == nil then
        filter_adult_content = true
    end

    self.api = KanisyncApi:new(self.token, filter_adult_content)

    self.user = {}
    if self.token then
        NetworkMgr:runWhenOnline(function()
            local user, error = self.api:getUser()
            if error then
                logger.err("Kanisync | An error occurred while fetching user: ", error)
            end
            self.user = user or {}
        end)
    end
end

function Kanisync:addToMainMenu(menu_items)
    menu_items.kanisync = {
        text = _("Kanisync"),
        sorting_hint = "tools",
        sub_item_table_func = function()
            return self.kanisync_ui:main_menu(self:getCurrentBookAniListData(), self.user.name)
        end
    }
end

---@return boolean
function Kanisync:hasToken()
    return self.token ~= nil and self.token ~= ""
end

function Kanisync:getAutoLinkFolders()
    local folders = self.settings:readSetting("auto_link_folders")
    if type(folders) == "table" then
        return folders
    end

    return {}
end

function Kanisync:onReaderReady()
    local document = self.ui.document
    local file = document and ffiUtil.realpath(document.file)
    if not self:hasToken() or self:getCurrentBookAniListData() or not file then
        return
    end

    local should_auto_link = false
    local folders = self:getAutoLinkFolders()
    for folder_index = 1, #folders do
        local folder = folders[folder_index]
        if type(folder) == "string"
            and (folder == "/" or file:sub(1, #folder + 1) == folder .. "/") then
            should_auto_link = true
            break
        end
    end
    if not should_auto_link then return end

    UIManager:nextTick(function()
        NetworkMgr:runWhenOnline(function()
            if not self.ui.document or self.ui.document ~= document or self:getCurrentBookAniListData() then
                return
            end
            self:linkBookToAniList()
        end)
    end)
end

---@return KanisyncEntry?
function Kanisync:getCurrentBookAniListData()
    return self.ui.doc_settings:readSetting("kanisync")
end

function Kanisync:saveCurrentBookAniListData(media)
    local titles = media.title or {}
    local title = titles.userPreferred
        or titles.english
        or titles.romaji
        or titles.native
    local user_list_entry = media.mediaListEntry or {}

    local saved_setting = {
        id = media.id,
        title = title,
        format = media.format,
        chapters = media.chapters,
        volumes = media.volumes,

        user_list_entry = {
            id = user_list_entry.id,
            status = user_list_entry.status,
            score = user_list_entry.score,
            notes = user_list_entry.notes,
            --[[
            We are setting the progress and volume progress values to 0 if they don't exist
            as it's exactly what AniList does to new additions to the user's library
            ]]
            progress = user_list_entry.progress or 0,
            progress_volumes = user_list_entry.progressVolumes or 0
        },

        fetched_at = os.time()
    }

    self.ui.doc_settings:delSetting("kanisync")
    self.ui.doc_settings:flush()
    self.ui.doc_settings:saveSetting("kanisync", saved_setting)
    self.ui.doc_settings:flush()

    return saved_setting
end

---@param key string
---@param value any
function Kanisync:updateCurrentBookAniListData(key, value)
    local anilist_data = self.ui.doc_settings:readSetting("kanisync")
    anilist_data[key] = value

    self.ui.doc_settings:saveSetting("kanisync", anilist_data)
    self.ui.doc_settings:flush()
end

---Updates the user metadata of the current book.
---@param key string
---@param value any
function Kanisync:updateCurrentBookUserMetadata(key, value)
    local anilist_data = self.ui.doc_settings:readSetting("kanisync")
    anilist_data.user_list_entry[key] = value

    self.ui.doc_settings:saveSetting("kanisync", anilist_data)
    self.ui.doc_settings:flush()
end

---@return { title: string?, metadata_title: string?, authors: string?, series: string?, series_index: number?, language: string?, keywords: string?, description: string?, filepath: string, pages: number }
function Kanisync:getCurrentBookDetails()
    local props = self.ui.doc_props
    local file = self.ui.document.file

    return {
        title = props.display_title,
        metadata_title = props.title,
        authors = props.authors,
        series = props.series,
        series_index = props.series_index,
        language = props.language,
        keywords = props.keywords,
        description = props.description,
        filepath = file,
        pages = self.ui.document:getPageCount(),
    }
end

---@param search_query? string
function Kanisync:linkBookToAniList(search_query)
    local book_details = self:getCurrentBookDetails()

    search_query = search_query
        or book_details.series
        or book_details.metadata_title
        or book_details.title

    if not search_query or search_query:match("^%s*$") then
        self.kanisync_ui.ephemeralMessage(_("No title was found in the book metadata."))
        return
    end

    local media_list, error = self.api:searchMedia(search_query)

    if not media_list then
        self.kanisync_ui.ephemeralMessage(error or _("An error occurred while fetching the media list."))
        return
    end

    self.kanisync_ui:mediaChooser(
        media_list,
        search_query,
        function(media)
            --[[
            We assume that if the media entry doesn't have a user status then the entry is not present in its library.
            Updating its status will add it in its library.
            ]]
            -- if not media.mediaListEntry or not media.mediaListEntry.status then
            --     local list_entry_id = media.mediaListEntry and media.mediaListEntry.id
            --     local result, updateError = self.api:updateMediaList(list_entry_id, media.id, { status = "CURRENT" })
            --     if updateError or not result then
            --         return updateError or _("AniList returned an invalid response")
            --     end
            --     media.mediaListEntry = result
            -- end
            local anilist_data = self:saveBookAniListData(media)
            self.kanisync_ui:progressUpdatePrompt(anilist_data)
        end,
        function(refined_query)
            self:linkBookToAniList(refined_query)
        end,
        function(cover_url)
            return self.api.downloadImage(cover_url)
        end
    )
end

function Kanisync:unlinkBook()
    self.ui.doc_settings:delSetting("kanisync")
    self.ui.doc_settings:flush()
end

return Kanisync
