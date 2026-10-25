local UIManager = require("ui/uimanager")
local InputDialog = require("ui/widget/inputdialog")
local SpinWidget = require("ui/widget/spinwidget")
local NetworkMgr = require("ui/network/manager")
local ffiUtil = require("ffi/util")
local _ = require("gettext")
local T = ffiUtil.template

local Messages = require("ui/ks_messages")

local ScoreDialog = {}

---@param plugin Kanisync
function ScoreDialog.show(plugin, anilist_data, user_list_entry, hasScore)
    local score_format_name = plugin.user.mediaListOptions.scoreFormat
    local score_format = plugin.score_formats[score_format_name]
    if not score_format then
        Messages.ephemeralMessage(_("Unable to determine your AniList score format."))
        return
    end

    local function saveScore(score)
        NetworkMgr:runWhenOnline(function()
            local result, error = plugin.api:updateMediaList(user_list_entry.id, anilist_data.id,
                { score = score })
            if error or not result then
                Messages.ephemeralMessage(error or _("AniList returned an invalid response"))
                return
            end
            plugin:saveBookUserMetadata(result)
            Messages.ephemeralMessage(_("Updated score"))
        end)
    end

    local uses_spin_widget = score_format_name == "POINT_3"
        or score_format_name == "POINT_5"
        or score_format_name == "POINT_10"
    if uses_spin_widget then
        UIManager:show(SpinWidget:new {
            title_text = hasScore and _("Edit score") or _("Add score"),
            info_text = T(_("%1 (%2-%3)"), score_format.label, score_format.minimum, score_format.maximum),
            value = user_list_entry.score or score_format.minimum,
            value_min = score_format.minimum,
            value_max = score_format.maximum,
            value_step = score_format.step,
            value_hold_step = score_format.step,
            precision = "%d",
            ok_text = _("Save"),
            callback = function(spin)
                saveScore(spin.value)
            end,
        })
        return
    end

    local dialog
    dialog = InputDialog:new {
        title = hasScore and _("Edit score") or _("Add score"),
        description = T(_("Enter a %1 score from %2 to %3."), score_format.label, score_format.minimum, score_format.maximum),
        input = hasScore and tostring(user_list_entry.score) or "",
        input_type = "number",
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
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local score = tonumber(dialog:getInputText())
                        local valid_step = score and math.abs(score / score_format.step
                            - math.floor(score / score_format.step + 0.5)) < 0.000001
                        if not valid_step or score < score_format.minimum or score > score_format.maximum then
                            Messages.ephemeralMessage(T(_("Enter a score from %1 to %2 in increments of %3."),
                                score_format.minimum, score_format.maximum, score_format.step))
                            return
                        end
                        UIManager:close(dialog)
                        saveScore(score)
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

return ScoreDialog
