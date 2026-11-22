local UIManager = require("ui/uimanager")
local SpinWidget = require("ui/widget/spinwidget")
local DoubleSpinWidget = require("ui/widget/doublespinwidget")
local Request = require("ui/ks_foreground_request")
local ffiUtil = require("ffi/util")
local _ = require("gettext")
local T = ffiUtil.template

local Messages = require("ui/ks_messages")

local Progress = {}
local MAX_PROGRESS = 2147483647 -- AniList uses a GraphQL Int for progress.

local function progressSpinWidget(title, unit, value, maximum, on_submit, ok_text, on_close)
    local submitted
    return SpinWidget:new {
        title_text = title,
        value = value,
        value_min = 0,
        value_max = maximum or MAX_PROGRESS,
        value_step = 1,
        value_hold_step = 10,
        precision = "%d",
        unit = unit,
        ok_text = ok_text or _("Set"),
        callback = function(spin) submitted = spin.value end,
        close_callback = function()
            if submitted ~= nil then
                -- KOReader's numeric input allows a bounds override; AniList still requires a non-negative Int.
                if submitted >= 0 and submitted <= MAX_PROGRESS and submitted % 1 == 0 then
                    on_submit(submitted)
                else
                    Messages.ephemeralMessage(_("Enter a valid non-negative whole number."))
                end
            end
            if on_close then on_close() end
        end,
    }
end

function Progress.edit(title, unit, value, maximum, on_submit)
    UIManager:show(progressSpinWidget(title, unit, value, maximum, on_submit))
end

local function progressUpdater(plugin, anilist_data)
    local document = plugin.ui.document
    local entry_id, media_id = anilist_data.user_list_entry.id, anilist_data.id
    local function is_active()
        return document ~= nil and plugin.ui.document == document
    end

    return function(values, success_message)
        if not is_active() then return end
        local api = plugin.api
        Request.run(function()
            return api:updateMediaList(entry_id, media_id, values)
        end, function(result, error)
            if not is_active() then return end
            if error or not result then
                Messages.ephemeralMessage(error or _("AniList returned an invalid response"))
                return
            end
            plugin:saveBookUserMetadata(result)
            Messages.ephemeralMessage(success_message)
        end, { text = _("Updating reading progress..."), mutation = true, is_active = is_active })
    end
end

---@param plugin Kanisync
function Progress.progressMenu(plugin, anilist_data)
    local user_list_entry = anilist_data.user_list_entry
    local updateProgress = progressUpdater(plugin, anilist_data)

    local chapter_text = anilist_data.chapters and T("Chapter %1 of %2", user_list_entry.progress, anilist_data.chapters) or
        T("Chapter %1", user_list_entry.progress)
    local volume_text = anilist_data.volumes and
        T("Volume %1 of %2", user_list_entry.progress_volumes, anilist_data.volumes) or
        T("Volume %1", user_list_entry.progress_volumes)


    local menu = {
        {
            text = _(chapter_text),
            callback = function()
                Progress.edit(_("Chapter progress"), _("chapters"), user_list_entry.progress,
                    anilist_data.chapters, function(value)
                        updateProgress({ progress = value }, _("Updated chapter progress"))
                    end)
            end
        },
        {
            text = _(volume_text),
            callback = function()
                Progress.edit(_("Volume progress"), _("volumes"), user_list_entry.progress_volumes,
                    anilist_data.volumes, function(value)
                        updateProgress({ progressVolumes = value }, _("Updated volume progress"))
                    end)
            end
        }
    }

    return menu
end

---@param plugin Kanisync
---@param anilist_data table
---@param progress_scope
---| "both"
---| "chapter"
---| "volume"
---@param close_callback? function
function Progress.progressUpdatePrompt(plugin, anilist_data, progress_scope, close_callback)
    local user_list_entry = anilist_data.user_list_entry

    local updateProgress = progressUpdater(plugin, anilist_data)
    local function submitProgress(values)
        updateProgress(values, _("Updated reading progress"))
    end

    local widget
    if progress_scope == "both" then
        widget = DoubleSpinWidget:new {
            title_text = T(_("Linked to %1. Update progress?"), anilist_data.title),

            left_text = _("Chapter progress"),
            left_value = user_list_entry.progress,
            left_min = 0,
            left_max = anilist_data.chapters or math.huge,
            left_step = 1,
            left_hold_step = 10,

            right_text = _("Volume progress"),
            right_value = user_list_entry.progress_volumes,
            right_min = 0,
            right_max = anilist_data.volumes or math.huge,
            right_step = 1,
            right_hold_step = 10,

            ok_text = _("Set"),

            callback = function(chapter_progress, volume_progress)
                submitProgress({ progress = chapter_progress, progressVolumes = volume_progress })
            end,
            close_callback = close_callback,
        }
    elseif progress_scope == "chapter" then
        widget = progressSpinWidget(_("Update chapter progress"), _("chapters"), user_list_entry.progress,
            anilist_data.chapters, function(value)
                submitProgress({ progress = value })
            end, _("Update"), close_callback)
    elseif progress_scope == "volume" then
        widget = progressSpinWidget(_("Update volume progress"), _("volumes"), user_list_entry.progress_volumes,
            anilist_data.volumes, function(value)
                submitProgress({ progressVolumes = value })
            end, _("Update"), close_callback)
    end
    if widget then
        UIManager:show(widget)
    end
end

return Progress
