local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local logger = require("logger")
local _ = require("gettext")

local KanisyncUi = {}
KanisyncUi.__index = KanisyncUi

function KanisyncUi:new()
    local obj = setmetatable({}, self)
    obj:init()
    return obj
end

function KanisyncUi:init()
    -- to-do (or maybe not)
end

function KanisyncUi:library(plugin)
    -- to-do
end


function KanisyncUi:main_menu(plugin)
    local is_token_provided = plugin:hasToken()

    local no_token_indication = { text = "Token not found", enabled = false }

    local menu = {}
    if not is_token_provided then
        table.insert(menu, no_token_indication)
    else
        table.insert(menu, {
            text = _("Sync library"),
            keep_menu_open = false,
            callback = function()
                logger.dbg("KanisyncUi | Triggered library sync")
                NetworkMgr:runWhenOnline(function()
                    plugin:syncLibrary()
                end)
            end,
        })
    end

    table.insert(menu, {
        text = _("About"),
        keep_menu_open = true,
        callback = function()
            UIManager:show(InfoMessage:new({
                text = "Kanisync\n\nSync your reading progress with AniList\n\nVersion: v" .. plugin.version,
            }))
        end,
    })

    return menu
end

return KanisyncUi
