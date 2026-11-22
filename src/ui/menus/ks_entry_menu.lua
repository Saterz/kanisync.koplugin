local UIManager = require("ui/uimanager")
local ConfirmBox = require("ui/widget/confirmbox")
local Request = require("ui/ks_foreground_request")
local ffiUtil = require("ffi/util")
local _ = require("gettext")
local T = ffiUtil.template

local NoteDialog = require("ui/dialogs/ks_note_dialog")
local ScoreDialog = require("ui/dialogs/ks_score_dialog")
local Progress = require("ui/dialogs/ks_progress")
local SearchDialog = require("ui/dialogs/ks_search_dialog")
local Messages = require("ui/ks_messages")
local DatesMenu = require("ui/menus/ks_dates_menu")
local StatusMenu = require("ui/menus/ks_status_menu")
local getStatusLabel = StatusMenu.getStatusLabel

local EntryMenu = {}

---@param plugin Kanisync
---@param anilist_data KanisyncEntry
function EntryMenu.manageEntry(plugin, anilist_data)
    local user_list_entry = anilist_data.user_list_entry
    local document = plugin.ui.document
    local function is_active()
        return document ~= nil and plugin.ui.document == document
    end

    local hasNotes = user_list_entry.notes ~= nil and user_list_entry.notes ~= ""

    return {
        {
            text = _("Pull changes"),
            callback = function()
                if not is_active() then return end
                local api = plugin.api
                local id = anilist_data.id
                Request.run(function()
                    return api:getMedia(id)
                end, function(media, error)
                    if not is_active() then return end
                    if error or not media then
                        Messages.ephemeralMessage(error or _("AniList returned an invalid response"))
                        return
                    end

                    plugin:saveBookAniListData(media)

                    Messages.ephemeralMessage(_("Changes pulled from AniList."))
                end, { text = _("Pulling changes from AniList..."), is_active = is_active })
            end
        },
        {
            text = _("Progress"),
            sub_item_table = Progress.progressMenu(plugin, anilist_data)
        },
        {
            text = user_list_entry.status and T(_("Reading status: %1"), getStatusLabel(user_list_entry.status)) or
                _("Reading status: Not in library"),
            sub_item_table = StatusMenu.updateStatusMenu(plugin, anilist_data)
        },
        {
            text = hasNotes and _("Edit note") or _("Add note"),
            callback = function()
                if not is_active() then return end
                NoteDialog.show(plugin, anilist_data, user_list_entry)
            end
        },
        {
            text = user_list_entry.score
                and T(
                    _("Score: %1 / %2"),
                    user_list_entry.score,
                    plugin.score_formats[
                    plugin.user.mediaListOptions.scoreFormat
                    ].maximum
                )
                or _("Score: Not rated"),
            callback = function()
                if not is_active() then return end
                ScoreDialog.show(plugin, anilist_data, user_list_entry)
            end
        },
        {
            text = _("Dates read"),
            sub_item_table = DatesMenu.datesReadMenu(plugin, anilist_data)
        },
        {
            text = _("Change linked book"),
            keep_menu_open = false,
            callback = function()
                if not is_active() then return end
                SearchDialog.searchDialog("", function(query)
                    if is_active() then plugin:linkBookToAniList(query) end
                end)
            end,
        },
        {
            text = _("Unlink book"),
            callback = function()
                UIManager:show(ConfirmBox:new {
                    text = T(
                        _(
                            'Unlink "%1" from this book?\n\nThis only removes the local link. The entry and reading progress on AniList will not be deleted.'),
                        anilist_data.title),
                    ok_text = _("Unlink"),
                    ok_callback = function()
                        plugin:unlinkBook()
                        Messages.ephemeralMessage(_("Book unlinked"))
                    end,
                })
            end
        },
    }
end

return EntryMenu
