local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local NoteDialog = require("ui/dialogs/ks_note_dialog")
local Progress = require("ui/dialogs/ks_progress")
local ScoreDialog = require("ui/dialogs/ks_score_dialog")
local StatusMenu = require("ui/menus/ks_status_menu")
local Support = require("ui/anilist/details/ks_details_support")
local UIManager = require("ui/uimanager")
local T = require("ffi/util").template
local _ = require("gettext")

local Editor = {}


function Editor.show(controller, media, entry, on_changed)
    local api = controller.api
    local is_anime = media.type == "ANIME"
    local entry_id = entry and entry.id


    local original = {
        status = entry and entry.status or "PLANNING",
        progress = entry and entry.progress or 0,
        progressVolumes = entry and entry.progressVolumes or 0,
        score = entry and entry.score or 0,
        notes = entry and entry.notes or "",
    }
    local draft = {}
    for field, value in pairs(original) do draft[field] = value end
    local dialog, showDialog, score_format_name

    local function update(field, value)
        draft[field] = value
        UIManager:close(dialog)
        showDialog()
    end

    local function progressRow(field, label, unit)
        return { { text = T(_("%1: %2"), label, draft[field]), callback = function()
            -- Catalog totals may be unknown or out of date.
            Progress.edit(label, unit, draft[field], nil, function(value) update(field, value) end)
        end } }
    end

    local function editScore()
        local active_dialog = dialog
        Support.online(controller, function()
            if dialog ~= active_dialog then return end
            if not score_format_name then
                local user = controller.viewer or api:getUser()
                local options = user and user.mediaListOptions
                score_format_name = options and options.scoreFormat
            end
            ScoreDialog.edit(score_format_name, controller.plugin.score_formats[score_format_name], draft.score,
                function(value) update("score", value) end)
        end)
    end

    local function finish(entry_after_change)
        UIManager:close(dialog)
        on_changed(entry_after_change)
        controller:libraryChanged(media.id, entry_after_change)
    end

    local function save()
        local values = {}
        for field, value in pairs(draft) do
            if value ~= original[field] then values[field] = value end
        end
        if not entry_id then values.status = draft.status end
        if next(values) == nil then
            UIManager:close(dialog)
            return
        end
        local active_dialog = dialog
        Support.online(controller, function()
            if dialog ~= active_dialog then return end
            local result, err = api:updateMediaList(entry_id, media.id, values)
            if err or type(result) ~= "table" or not result.id then
                Support.error(controller, _("Could not save this AniList entry."))
                return
            end
            finish(result)
        end)
    end

    local function remove()
        local active_dialog = dialog
        local confirmation
        confirmation = ConfirmBox:new {
            text = _("Remove this entry and its progress, score, and notes from your AniList list?"),
            ok_text = _("Remove"),
            keep_dialog_open = true,
            ok_callback = function()
                UIManager:close(confirmation)
                Support.online(controller, function()
                    if dialog ~= active_dialog then return end
                    local result, err = api:deleteMediaList(entry_id)
                    if type(result) == "table" then result = result.deleted end
                    if err or result ~= true then
                        Support.error(controller, _("Could not remove this AniList entry."))
                        return
                    end
                    finish(nil)
                end)
            end,
        }
        UIManager:show(confirmation)
    end

    local DraftDialog = ButtonDialog:extend {}
    function DraftDialog:onCloseWidget()
        if dialog == self then dialog = nil end
        ButtonDialog.onCloseWidget(self)
    end

    showDialog = function()
        local buttons = {
            { { text = T(_("Status: %1"), StatusMenu.getStatusLabel(draft.status, is_anime)), callback = function()
                Support.choose(_("List status"), StatusMenu.choices(is_anime), function(value) update("status", value) end)
            end } },
            progressRow("progress", is_anime and _("Episodes watched") or _("Chapters read"),
                is_anime and _("episodes") or _("chapters")),
        }
        if not is_anime then buttons[#buttons + 1] = progressRow("progressVolumes", _("Volumes read"), _("volumes")) end
        buttons[#buttons + 1] = { {
            text = T(_("Score: %1"), draft.score == 0 and _("Not scored") or draft.score), callback = editScore,
        } }
        buttons[#buttons + 1] = { {
            text = draft.notes == "" and _("Add notes") or _("Edit notes"), callback = function()
                NoteDialog.edit(draft.notes, function(value) update("notes", value) end)
            end,
        } }
        if entry_id and type(api.deleteMediaList) == "function" then
            buttons[#buttons + 1] = { { text = _("Remove from AniList"), callback = remove } }
        end
        buttons[#buttons + 1] = {
            { text = _("Cancel"), callback = function() UIManager:close(dialog) end },
            { text = _("Save"), callback = save },
        }
        dialog = DraftDialog:new {
            title = entry_id and _("Edit AniList entry") or _("Add to AniList"),
            use_info_style = false,
            buttons = buttons,
        }
        UIManager:show(dialog)
    end
    showDialog()
end

return Editor
