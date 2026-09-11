local UIManager = require("ui/uimanager")
local ConfirmBox = require("ui/widget/confirmbox")
local PathChooser = require("ui/widget/pathchooser")
local Device = require("device")
local ffiUtil = require("ffi/util")
local _ = require("gettext")
local T = ffiUtil.template

local AutoLinkFolders = {}

function AutoLinkFolders:autoLinkFoldersMenu()
    local folders = self.plugin:getAutoLinkFolders()
    local menu = {
        {
            text = _("Add auto-link folder"),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                UIManager:show(PathChooser:new {
                    path = G_reader_settings:readSetting("home_dir") or Device.home_dir,
                    select_directory = true,
                    select_file = false,
                    show_files = false,
                    onConfirm = function(path)
                        for folder_index = 1, #folders do
                            if folders[folder_index] == path then return end
                        end
                        table.insert(folders, path)
                        self.plugin.settings:saveSetting("auto_link_folders", folders):flush()
                        touchmenu_instance.item_table = self:autoLinkFoldersMenu()
                        touchmenu_instance:updateItems()
                    end,
                })
            end,
        }
    }

    for folder_index = 1, #folders do
        local selected_folder = folders[folder_index]
        table.insert(menu, {
            text = ffiUtil.basename(selected_folder),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                UIManager:show(ConfirmBox:new {
                    text = T(_("Remove auto-link folder?\n%1"), selected_folder),
                    ok_text = _("Remove"),
                    ok_callback = function()
                        for current_index = 1, #folders do
                            if folders[current_index] == selected_folder then
                                table.remove(folders, current_index)
                                self.plugin.settings:saveSetting("auto_link_folders", folders):flush()
                                touchmenu_instance.item_table = self:autoLinkFoldersMenu()
                                touchmenu_instance:updateItems()
                                return
                            end
                        end
                    end,
                })
            end,
        })
    end

    return menu
end

return AutoLinkFolders
