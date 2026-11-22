local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local NoteDialog = require("ui/dialogs/ks_note_dialog")
local Progress = require("ui/dialogs/ks_progress")
local Request = require("ui/ks_foreground_request")
local ScoreDialog = require("ui/dialogs/ks_score_dialog")
local StatusMenu = require("ui/menus/ks_status_menu")
local Support = require("ui/anilist/details/ks_details_support")
local UIManager = require("ui/uimanager")
local T = require("ffi/util").template
local _ = require("gettext")

local Editor = {}


function Editor.show(controller, media, entry, on_changed, is_parent_active)
    local api = controller.api
    local media_id = media.id
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
    local dialog, showDialog, score_format_name, request

    local function isActive(active_dialog)
        return active_dialog ~= nil and dialog == active_dialog and (not is_parent_active or is_parent_active())
    end

    local function run(task, on_complete, message, mutation)
        local active_dialog = dialog
        if not isActive(active_dialog) then return end
        local current = {}
        request = current
        local function isCurrent() return request == current and isActive(active_dialog) end
        local function clearRequest()
            if request == current then request = nil end
        end
        Request.run(task, function(...)
            if not isCurrent() then return end
            clearRequest()
            on_complete(...)
        end, { text = message, mutation = mutation, is_active = isCurrent, on_cancel = clearRequest })
    end

    local function update(field, value)
        if not isActive(dialog) then return end
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
        if not isActive(active_dialog) then return end
        local function showScore(format)
            score_format_name = format
            ScoreDialog.edit(format, controller.plugin.score_formats[format], draft.score, function(value)
                if isActive(active_dialog) then update("score", value) end
            end)
        end
        local viewer = controller.viewer
        local options = viewer and viewer.mediaListOptions
        if score_format_name or options and options.scoreFormat then
            showScore(score_format_name or options.scoreFormat)
            return
        end
        run(function()
            local user = api:getUser()
            local list_options = user and user.mediaListOptions
            return list_options and list_options.scoreFormat
        end, showScore, _("Loading AniList score settings…"))
    end

    local function finish(entry_after_change)
        UIManager:close(dialog)
        on_changed(entry_after_change)
        controller:libraryChanged(media_id, entry_after_change)
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
        run(function()
            local result, err = api:updateMediaList(entry_id, media_id, values)
            if not err and type(result) == "table" and result.id then return result end
        end, function(result)
            if not result then
                Support.error(controller, _("Could not save this AniList entry."))
                return
            end
            finish(result)
        end, _("Saving AniList entry…"), true)
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
                if not isActive(active_dialog) then return end
                run(function()
                    local result, err = api:deleteMediaList(entry_id)
                    if type(result) == "table" then result = result.deleted end
                    return not err and result == true
                end, function(deleted)
                    if not deleted then
                        Support.error(controller, _("Could not remove this AniList entry."))
                        return
                    end
                    finish(nil)
                end, _("Removing AniList entry…"), true)
            end,
        }
        UIManager:show(confirmation)
    end

    local DraftDialog = ButtonDialog:extend {}
    function DraftDialog:onCloseWidget()
        if dialog == self then dialog, request = nil, nil end
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
