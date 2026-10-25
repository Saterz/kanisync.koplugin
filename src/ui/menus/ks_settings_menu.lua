local _ = require("gettext")

local TokenDialog = require("ui/dialogs/ks_token_dialog")
local AutoLinkFolders = require("ui/menus/ks_auto_link_folders")

local SettingsMenu = {}

---@param plugin Kanisync
function SettingsMenu.preferencesMenu(plugin)
    local menu = {}

    table.insert(menu, {
        text = _("Show 18+ content"),
        checked_func = function()
            return plugin.settings:isFalse("filter_adult_content")
        end,
        keep_menu_open = true,
        callback = function()
            plugin.settings:flipNilOrTrue("filter_adult_content")
            plugin.api.filter_adult_content = plugin.settings:nilOrTrue("filter_adult_content")
            plugin.settings:flush()
        end,
    })

    return menu
end

---@param plugin Kanisync
function SettingsMenu.settingsMenu(plugin)
    local menu = {}

    table.insert(menu, {
        text = _("Update AniList token"),
        keep_menu_open = true,
        callback = function()
            TokenDialog.updateTokenDialog(plugin)
        end
    })
    table.insert(menu, {
        text = _("Auto-link folders"),
        sub_item_table = AutoLinkFolders.autoLinkFoldersMenu(plugin),
        help_text = _(
            "Books opened from an auto-link folder or its subfolders will automatically be searched on AniList.")
    })
    table.insert(menu, {
        text = _("Preferences"),
        sub_item_table = SettingsMenu.preferencesMenu(plugin)
    })

    return menu
end

return SettingsMenu
