
local ffiUtil = require("ffi/util")
local _ = require("gettext")
local T = ffiUtil.template

local Messages = require("ui/ks_messages")
local SettingsMenu = require("ui/menus/ks_settings_menu")
local TokenDialog = require("ui/dialogs/ks_token_dialog")
local EntryMenu = require("ui/menus/ks_entry_menu")
local AniListBrowser = require("ui/anilist/browser/ks_browser")

local MainMenu = {}

---@param plugin Kanisync
---@param anilist_data KanisyncEntry?
function MainMenu.main_menu(plugin, anilist_data)
    local user = plugin.user

    local menu = {}
    if not plugin:hasToken() then
        table.insert(menu, {
            text = _("Token not found"),
            callback = function()
                TokenDialog.updateTokenDialog(plugin)
            end,
        })
    else
        if user then
            table.insert(menu, {
                text = T(_("Connected as %1"), user.name),
                enabled = false,
            })
            if plugin:isBookOpen() then
                if anilist_data ~= nil then
                    table.insert(menu, {
                        text = T(_('Linked to "%1"'), anilist_data.title),
                        sub_item_table = EntryMenu.manageEntry(plugin, anilist_data)
                    })
                else
                    table.insert(menu, {
                        text = _("Link book to AniList"),
                        keep_menu_open = false,
                        callback = function()
                            plugin:linkBookToAniList()
                        end,
                    })
                end
            end
        else
            table.insert(menu, {
                text = _("Verify token"),
                callback = function()
                    plugin:refreshAniListUser()
                end,
            })
        end
    end

    table.insert(menu, {
        text = _("Open AniList"),
        keep_menu_open = false,
        callback = function()
            AniListBrowser.open(plugin)
        end,
    })
    table.insert(menu, {
        text = _("Settings"),
        sub_item_table = SettingsMenu.settingsMenu(plugin)
    })
    table.insert(menu, {
        text = _("About"),
        keep_menu_open = true,
        callback = function()
            Messages.about(plugin)
        end,
    })

    return menu
end

return MainMenu
