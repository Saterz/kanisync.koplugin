local UIManager = require("ui/uimanager")
local NetworkMgr = require("ui/network/manager")
local ffiUtil = require("ffi/util")
local _ = require("gettext")
local T = ffiUtil.template

local MainMenu = {}

---@param anilist_data KanisyncEntry?
function MainMenu:main_menu(anilist_data)
    local user = self.plugin.user

    local menu = {}
    if not self.plugin:hasToken() then
        table.insert(menu, {
            text = _("Token not found"),
            callback = function()
                self:updateTokenDialog()
            end,
        })
    else
        if user then
            table.insert(menu, {
                text = T(_("Connected as %1"), user.name),
                enabled = false,
            })
            if self.plugin:isBookOpen() then
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
        else
            table.insert(menu, {
                text = _("Verify token"),
                callback = function()
                    local loading = self.showMessage(_("Verifying token..."))
                    UIManager:tickAfterNext(function()
                        self.plugin:refreshAniListUser(function()
                            UIManager:close(loading)
                        end)
                    end)
                end,
            })
        end
    end

    table.insert(menu, {
        text = _("Settings"),
        sub_item_table = self:settingsMenu()
    })
    table.insert(menu, {
        text = _("About"),
        keep_menu_open = true,
        callback = function()
            self:about()
        end,
    })

    return menu
end

return MainMenu
