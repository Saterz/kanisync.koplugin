local UIManager = require("ui/uimanager")
local InputDialog = require("ui/widget/inputdialog")
local NetworkMgr = require("ui/network/manager")
local Messages = require("ui/ks_messages")
local _ = require("gettext")

local NoteDialog = {}

---@param plugin Kanisync
function NoteDialog.show(plugin, anilist_data, user_list_entry, hasNotes)
    local search_query = user_list_entry.notes
    local dialog
    dialog = InputDialog:new {
        title = hasNotes and _("Edit note") or _("Add note"),
        description = hasNotes and _("Edit your personal note for this AniList entry.") or _("Add a personal note to this AniList entry."),
        input = search_query,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Submit"),
                    is_enter_default = true,
                    callback = function()
                        local query = dialog:getInputText()
                        UIManager:close(dialog)
                        NetworkMgr:runWhenOnline(function()
                            local result, error = plugin.api:updateMediaList(user_list_entry.id,
                                anilist_data.id, { notes = query })
                            if error or not result then
                                Messages.ephemeralMessage(error or _("AniList returned an invalid response"))
                                return
                            end
                            plugin:saveBookUserMetadata(result)
                            Messages.ephemeralMessage(_("Updated personal note"))
                        end)
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

return NoteDialog
