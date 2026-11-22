local UIManager = require("ui/uimanager")
local InputDialog = require("ui/widget/inputdialog")
local SpinWidget = require("ui/widget/spinwidget")
local Request = require("ui/ks_foreground_request")
local ffiUtil = require("ffi/util")
local _ = require("gettext")
local T = ffiUtil.template

local Messages = require("ui/ks_messages")

local ScoreDialog = {}

---Edit a score in the viewer's AniList format without deciding how it is saved.
function ScoreDialog.edit(score_format_name, score_format, score, on_submit)
    if not score_format then
        Messages.ephemeralMessage(_("Unable to determine your AniList score format."))
        return
    end
    local hasScore = score ~= nil and score ~= 0

    local function isValid(value)
        if value and value >= score_format.minimum and value <= score_format.maximum then
            local units = value / score_format.step
            if math.abs(units - math.floor(units + 0.5)) < 0.000001 then return true end
        end
        Messages.ephemeralMessage(T(_("Enter a score from %1 to %2 in increments of %3."),
            score_format.minimum, score_format.maximum, score_format.step))
        return false
    end

    local uses_spin_widget = score_format_name == "POINT_3"
        or score_format_name == "POINT_5"
        or score_format_name == "POINT_10"
    if uses_spin_widget then
        local submitted
        UIManager:show(SpinWidget:new {
            title_text = hasScore and _("Edit score") or _("Add score"),
            info_text = T(_("%1 (%2-%3)"), score_format.label, score_format.minimum, score_format.maximum),
            value = score or score_format.minimum,
            value_min = score_format.minimum,
            value_max = score_format.maximum,
            value_step = score_format.step,
            value_hold_step = score_format.step,
            precision = "%d",
            ok_text = _("Save"),
            callback = function(spin)
                submitted = spin.value
            end,
            close_callback = function()
                if submitted ~= nil and isValid(submitted) then on_submit(submitted) end
            end,
        })
        return
    end

    local dialog
    dialog = InputDialog:new {
        title = hasScore and _("Edit score") or _("Add score"),
        description = T(_("Enter a %1 score from %2 to %3."), score_format.label, score_format.minimum, score_format.maximum),
        input = hasScore and tostring(score) or "",
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
                        local value = tonumber(dialog:getInputText())
                        if not isValid(value) then return end
                        UIManager:close(dialog)
                        on_submit(value)
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

---@param plugin Kanisync
function ScoreDialog.show(plugin, anilist_data, user_list_entry)
    local options = plugin.user and plugin.user.mediaListOptions
    local name = options and options.scoreFormat
    local document = plugin.ui.document
    local function is_active()
        return document ~= nil and plugin.ui.document == document
    end

    ScoreDialog.edit(name, plugin.score_formats[name], user_list_entry.score, function(score)
        if not is_active() then return end
        local api = plugin.api
        local entry_id, media_id = user_list_entry.id, anilist_data.id
        Request.run(function()
            return api:updateMediaList(entry_id, media_id, { score = score })
        end, function(result, error)
            if not is_active() then return end
            if error or not result then
                Messages.ephemeralMessage(error or _("AniList returned an invalid response"))
                return
            end
            plugin:saveBookUserMetadata(result)
            Messages.ephemeralMessage(_("Updated score"))
        end, { text = _("Updating score..."), mutation = true, is_active = is_active })
    end)
end

return ScoreDialog
