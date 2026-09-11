local UIManager = require("ui/uimanager")
local SpinWidget = require("ui/widget/spinwidget")
local DoubleSpinWidget = require("ui/widget/doublespinwidget")
local NetworkMgr = require("ui/network/manager")
local ffiUtil = require("ffi/util")
local _ = require("gettext")
local T = ffiUtil.template

local Progress = {}

function Progress:progressMenu(anilist_data)
    local user_list_entry = anilist_data.user_list_entry

    local chapter_text = anilist_data.chapters and T("Chapter %1 of %2", user_list_entry.progress, anilist_data.chapters) or
        T("Chapter %1", user_list_entry.progress)
    local volume_text = anilist_data.volumes and
        T("Volume %1 of %2", user_list_entry.progress_volumes, anilist_data.volumes) or
        T("Volume %1", user_list_entry.progress_volumes)

    local function updateProgressSpinWidget(title_text, unit, value, value_max, callback)
        return SpinWidget:new {
            title_text = _(title_text),
            value = value,
            value_min = 0,
            value_max = value_max or math.huge,
            value_step = 1,
            value_hold_step = 10,
            unit = _(unit),
            ok_text = _("Set"),
            callback = callback
        }
    end

    local menu = {
        {
            text = _(chapter_text),
            callback = function()
                local dialog = updateProgressSpinWidget("Chapter progress", "chapters", user_list_entry.progress,
                    anilist_data.chapters, function(spin)
                        NetworkMgr:runWhenOnline(function()
                            local result, error = self.plugin.api:updateMediaList(user_list_entry.id, anilist_data.id,
                                { progress = spin.value })
                            if error or not result then
                                self.ephemeralMessage(error or _("AniList returned an invalid response"))
                                return
                            end
                            self.plugin:saveBookUserMetadata(result)
                            self.ephemeralMessage(_("Updated chapter progress"))
                        end)
                    end)
                UIManager:show(dialog)
            end
        },
        {
            text = _(volume_text),
            callback = function()
                local dialog = updateProgressSpinWidget("Volume progress", "volumes", user_list_entry.progress_volumes,
                    anilist_data.volumes, function(spin)
                        NetworkMgr:runWhenOnline(function()
                            local result, error = self.plugin.api:updateMediaList(user_list_entry.id, anilist_data.id,
                                { progressVolumes = spin.value })
                            if error or not result then
                                self.ephemeralMessage(error or _("AniList returned an invalid response"))
                                return
                            end
                            self.plugin:saveBookUserMetadata(result)
                            self.ephemeralMessage(_("Updated volume progress"))
                        end)
                    end)
                UIManager:show(dialog)
            end
        }
    }

    return menu
end

---@param anilist_data table
---@param progress_scope
---| "both"
---| "chapter"
---| "volume"
---@param close_callback? function
function Progress:progressUpdatePrompt(anilist_data, progress_scope, close_callback)
    local user_list_entry = anilist_data.user_list_entry

    local function updateProgress(values)
        NetworkMgr:runWhenOnline(function()
            local result, error = self.plugin.api:updateMediaList(user_list_entry.id, anilist_data.id,
                values)
            if error or not result then
                self.ephemeralMessage(error or _("AniList returned an invalid response"))
                return
            end
            self.plugin:saveBookUserMetadata(result)
            self.ephemeralMessage(_("Updated reading progress"))
        end)
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
                updateProgress({ progress = chapter_progress, progressVolumes = volume_progress })
            end,
            close_callback = close_callback,
        }
    elseif progress_scope == "chapter" then
        widget = SpinWidget:new {
            title_text = _("Update chapter progress"),

            value = user_list_entry.progress,
            value_min = 0,
            value_max = anilist_data.chapters or math.huge,
            value_step = 1,
            value_hold_step = 10,
            precision = "%d",
            unit = _("chapters"),

            ok_text = _("Update"),

            callback = function(spin)
                updateProgress({ progress = spin.value })
            end,
            close_callback = close_callback,
        }
    elseif progress_scope == "volume" then
        widget = SpinWidget:new {
            title_text = _("Update volume progress"),

            value = user_list_entry.progress_volumes,
            value_min = 0,
            value_max = anilist_data.volumes or math.huge,
            value_step = 1,
            value_hold_step = 10,
            precision = "%d",
            unit = _("volumes"),

            ok_text = _("Update"),

            callback = function(spin)
                updateProgress({ progressVolumes = spin.value }, _("Updated volume progress"))
            end,
            close_callback = close_callback,
        }
    end
    if widget then
        UIManager:show(widget)
    end
end

return Progress
