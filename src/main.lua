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
local KanisyncConfig = require("config")

local SETTINGS_FILE = DataStorage:getSettingsDir() .. "/kanisync_settings.lua"

---@alias ReadingStatus string "Source: https://docs.anilist.co/reference/enum/medialiststatus#medialiststatus"
---| "CURRENT" Currently watching/reading
---| "PLANNING"	Planning to watch/read
---| "COMPLETED" Finished watching/reading
---| "DROPPED" Stopped watching/reading before completing
---| "PAUSED" Paused watching/reading
---| "REPEATING" Re-watching/reading

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

    if KanisyncConfig and KanisyncConfig.anilist_token ~= "" then
        self.token = KanisyncConfig.anilist_token
    else
        logger.warn("Kanisync | No token found in config.lua")
    end

    self.kanisync_ui = KanisyncUI:new()
    self.api = KanisyncApi:new(self.token)
end

function Kanisync:addToMainMenu(menu_items)
    menu_items.kanisync = {
        text = _("Kanisync"),
        sorting_hint = "tools",
        sub_item_table = self.kanisync_ui:main_menu(self)
    }
end

function Kanisync:hasToken()
    return self.token ~= nil and self.token ~= ""
end

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
            local titles = media.title or {}
            local title = titles.userPreferred
                or titles.english
                or titles.romaji
                or titles.native
                or tostring(media.id)
            local user_list_entry = media.mediaListEntry or {}
            self.ui.doc_settings:saveSetting("kanisync", {
                id = media.id,
                title = title,

                ---@type ReadingStatus
                status = user_list_entry.status or "CURRENT",

                fetched_at = os.time()
            })
            self.ui.doc_settings:flush()
        end,
        function(refined_query)
            self:linkBookToAniList(refined_query)
        end,
        function(cover_url)
            return self.api.downloadCover(cover_url)
        end
    )
end

return Kanisync
