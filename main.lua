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
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")

local KanisyncUi = require("kanisync_ui")
local AnilistApi = require("anilist_api")
local KanisyncConfig = require("config")

local CLIENT_ID = "40345"
local SETTINGS_FILE = DataStorage:getSettingsDir() .. "/kanisync_settings.lua"

local Kanisync = WidgetContainer:extend {
    name = "kanisync",
    is_doc_only = false,
    client_id = CLIENT_ID
}

-- function Kanisync:onDispatcherRegisterActions()
--     Dispatcher:registerAction()
--

function Kanisync:init()
    -- self:onDispatcherRegisterActions()
    self.settings = LuaSettings:open(SETTINGS_FILE)

    if KanisyncConfig and KanisyncConfig.anilist_token ~= "" then
        self.token = KanisyncConfig.anilist_token
    else
        logger.warn("Kanisync | No token found in config.lua")
    end

    self.api = AnilistApi:new(self.token)
    self.kani_ui = KanisyncUi:new()

    self.ui.menu:registerToMainMenu(self)
end

function Kanisync:addToMainMenu(menu_items)
    menu_items.kanisync = {
        text = _("Kanisync"),
        sorting_hint = "tools",
        sub_item_table = self.kani_ui:main_menu(self)
    }
end

function Kanisync:hasToken()
    return self.token ~= nil and self.token ~= ""
end

function Kanisync:syncLibrary()
    logger.dbg("Kanisync | Starting library sync")
    local sync_msg = InfoMessage:new {
        text = _("Syncing AniList library..."),
    }
    UIManager:show(sync_msg)

    UIManager:scheduleIn(0.1, function()
        local query = [[
        query {
          Viewer {
            id
          }
        }
        ]]
        local res, err = self.api:request(query)

        if err or not res or not res.data or not res.data.Viewer then
            logger.warn("Kanisync | sync failed: " .. tostring(err))
            UIManager:close(sync_msg)
            UIManager:show(InfoMessage:new {
                text = _("Failed to fetch Viewer ID."),
                timeout = 3,
            })
            return
        end

        local user_id = res.data.Viewer.id
        logger.dbg("Kanisync | Fetched Viewer ID: " .. tostring(user_id))
        local list_query = [[
        query ($type: MediaType!, $userId: Int!) {
          MediaListCollection(type: $type, userId: $userId) {
            lists {
              name
              entries {
                id
                media {
                  id
                  title {
                    english,
                    romaji
                  }
                }
              }
            }
          }
        }
        ]]
        local list_res, list_err = self.api:request(list_query, { type = "MANGA", userId = user_id })

        UIManager:close(sync_msg)

        if list_err or not list_res then
            logger.warn("Kanisync | sync list failed: " .. tostring(list_err))
            UIManager:show(InfoMessage:new {
                text = _("Failed to sync AniList library."),
                timeout = 3,
            })
            return
        end

        logger.dbg("Kanisync | Library synced successfully")
        self.settings:saveSetting("manga_library", list_res.data.MediaListCollection)
        self.settings:flush()

        UIManager:show(InfoMessage:new {
            text = _("AniList library synced successfully."),
            timeout = 3,
        })
    end)
end

return Kanisync
