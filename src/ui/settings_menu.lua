local _ = require("gettext")

local SettingsMenu = {}

function SettingsMenu:preferencesMenu()
    local menu = {}

    table.insert(menu, {
        text = _("Show 18+ content"),
        checked_func = function()
            return self.plugin.settings:isFalse("filter_adult_content")
        end,
        keep_menu_open = true,
        callback = function()
            self.plugin.settings:flipNilOrTrue("filter_adult_content")
            self.plugin.api.filter_adult_content = self.plugin.settings:nilOrTrue("filter_adult_content")
            self.plugin.settings:flush()
        end,
    })

    return menu
end

function SettingsMenu:settingsMenu()
    local menu = {}

    table.insert(menu, {
        text = _("Update AniList token"),
        keep_menu_open = true,
        callback = function()
            self:updateTokenDialog()
        end
    })
    table.insert(menu, {
        text = _("Auto-link folders"),
        sub_item_table = self:autoLinkFoldersMenu(),
        help_text = _(
            "Books opened from an auto-link folder or its subfolders will automatically be searched on AniList.")
    })
    table.insert(menu, {
        text = _("Preferences"),
        sub_item_table = self:preferencesMenu()
    })

    return menu
end

return SettingsMenu
