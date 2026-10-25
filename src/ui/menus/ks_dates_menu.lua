local UIManager = require("ui/uimanager")
local NetworkMgr = require("ui/network/manager")
local ffiUtil = require("ffi/util")
local DateTimeWidget = require("ui/widget/datetimewidget")
local datetime = require("datetime")
local _ = require("gettext")
local T = ffiUtil.template

local Messages = require("ui/ks_messages")

local DatesMenu = {}

---@param plugin Kanisync
---@param anilist_data KanisyncEntry
function DatesMenu.datesReadMenu(plugin, anilist_data)
    local user_list_entry = anilist_data.user_list_entry

    local menu = {}

    local current_date = os.date("*t")

    local function updateDate(values, success_message)
        NetworkMgr:runWhenOnline(function()
            local result, error = plugin.api:updateMediaList(user_list_entry.id, anilist_data.id,
                values)
            if error or not result then
                Messages.ephemeralMessage(error or _("AniList returned an invalid response"))
                return
            end
            plugin:saveBookUserMetadata(result)
            Messages.ephemeralMessage(success_message)
        end)
    end

    local function displayDate(date)
        if not date or not date.year or not date.month or not date.day then
            return _("Not set")
        end

        local timestamp = os.time {
            year = date.year,
            month = date.month,
            day = date.day,
            -- Avoid date changes around DST boundaries.
            hour = 12,
        }

        return datetime.secondsToDate(timestamp, true)
    end

    local function datesReadDateTimeWidget(title_text, date, callback, unset_callback)
        date = date or {}

        return DateTimeWidget:new {
            title_text = _(title_text),

            year = date.year or current_date.year,
            month = date.month or current_date.month,
            day = date.day or current_date.day,

            -- Required because DateTimeWidget defaults year_min to 2021.
            year_min = anilist_data.start_date.year or 1900,
            year_max = current_date.year,

            ok_text = _("Save"),
            callback = callback,

            extra_text = date.year and _("Unset") or nil,
            extra_callback = function(widget)
                UIManager:close(widget)
                unset_callback()
            end
        }
    end

    table.insert(menu, {
        text = T(_("Started on: %1"), displayDate(user_list_entry.started_at)),
        callback = function()
            local modal = datesReadDateTimeWidget("Started on", user_list_entry.started_at, function(selected_date)
                    updateDate({
                        startedAt = {
                            day = selected_date.day,
                            month = selected_date.month,
                            year = selected_date.year,
                        }
                    }, _("Updated started on date"))
                end,
                function()
                    updateDate({
                        startedAt = {}
                    }, _("Cleared started on date"))
                end)
            UIManager:show(modal)
        end
    })

    table.insert(menu, {
        text = T(_("Completed on: %1"), displayDate(user_list_entry.completed_at)),
        callback = function()
            local modal = datesReadDateTimeWidget("Completed on", user_list_entry.completed_at, function(selected_date)
                    updateDate({
                        completedAt = {
                            day = selected_date.day,
                            month = selected_date.month,
                            year = selected_date.year,
                        }
                    }, _("Updated completed on date"))
                end,
                function()
                    updateDate({
                        completedAt = {}
                    }, _("Cleared completed on date"))
                end)
            UIManager:show(modal)
        end
    })

    return menu
end

return DatesMenu
