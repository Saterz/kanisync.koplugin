--[[--
A KOReader plugin to sync your reading progress with AniList

@module koplugin.Kanisync
--]] --

-- local Dispatcher = require("dispatcher")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local DataStorage = require("datastorage")
local logger = require("logger")
local LuaSettings = require("luasettings")
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

---@alias KanisyncEntry { id: number, title: string?, user_metadata: { id: number?, status: ReadingStatus, score: number?, progress: number?, progress_volumes: number?, notes: string? }, fetched_at: number }

---@class Kanisync
---@field ui table KOReader UI instance injected by PluginLoader
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

    local _, KanisyncConfig = pcall(require, "config")
    if KanisyncConfig and KanisyncConfig.anilist_token ~= "" then
        self.token = KanisyncConfig.anilist_token
    else
        logger.warn("Kanisync | No token found in config.lua")
    end

    self.kanisync_ui = KanisyncUI:new(self)
    self.score_formats = SCORE_FORMATS
    self.api = KanisyncApi:new(self.token)

    self.user = {}
    if self.token then
        local user, error = self.api:getUser()
        if error then
            logger.err("Kanisync | An error occurred while fetching user: ", error)
        end
        self.user = user
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
    self.ui.doc_settings:delSetting("kanisync")
    self.ui.doc_settings:flush()
    self.ui.doc_settings:saveSetting("kanisync", {
        id = media.id,
        title = title,

        user_metadata = {
            id = user_list_entry.id or nil,
            ---@type ReadingStatus
            status = user_list_entry.status or "CURRENT",
            score = user_list_entry.score or nil,
            progress = user_list_entry.progress,
            progress_volumes = user_list_entry.progressVolumes,
            notes = user_list_entry.notes
        },

        fetched_at = os.time()
    })
    self.ui.doc_settings:flush()
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
    anilist_data.user_metadata[key] = value

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
        self.kanisync_ui.errorMessage(_("No title was found in the book metadata."))
        return
    end

    local media_list, error = self.api:searchMedia(search_query)

    if not media_list then
        self.kanisync_ui.errorMessage(error or _("An error occurred while fetching the media list."))
        return
    end

    self.kanisync_ui:mediaChooser(
        media_list,
        search_query,
        function(media)
            self:saveCurrentBookAniListData(media)
        end,
        function(refined_query)
            self:linkBookToAniList(refined_query)
        end,
        function(cover_url)
            return self.api.downloadCover(cover_url)
        end
    )
end

function Kanisync:unlinkBook()
    self.ui.doc_settings:delSetting("kanisync")
    self.ui.doc_settings:flush()
end

return Kanisync
