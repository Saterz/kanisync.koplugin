local UIManager = require("ui/uimanager")
local InputDialog = require("ui/widget/inputdialog")
local NetworkMgr = require("ui/network/manager")
local Messages = require("ui/ks_messages")
local _ = require("gettext")

local NoteDialog = {}

---Edit a note without deciding how it is saved.
function NoteDialog.edit(note, on_submit)
    local hasNotes = note ~= nil and note ~= ""
    local dialog
    dialog = InputDialog:new {
        title = hasNotes and _("Edit note") or _("Add note"),
        description = hasNotes and _("Edit your personal note for this AniList entry.") or _("Add a personal note to this AniList entry."),
        input = note or "",
        allow_newline = true,
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
                    callback = function()
                        local text = dialog:getInputText()
                        UIManager:close(dialog)
                        on_submit(text)
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

---@param plugin Kanisync
function NoteDialog.show(plugin, anilist_data, user_list_entry)
    NoteDialog.edit(user_list_entry.notes, function(note)
        NetworkMgr:runWhenOnline(function()
            local result, error = plugin.api:updateMediaList(user_list_entry.id, anilist_data.id, { notes = note })
            if error or not result then
                Messages.ephemeralMessage(error or _("AniList returned an invalid response"))
                return
            end
            plugin:saveBookUserMetadata(result)
            Messages.ephemeralMessage(_("Updated personal note"))
        end)
    end)
end

return NoteDialog
