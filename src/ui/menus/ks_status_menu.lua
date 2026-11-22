local NetworkMgr = require("ui/network/manager")
local _ = require("gettext")

local Messages = require("ui/ks_messages")

local StatusMenu = {}

function StatusMenu.choices(is_anime)
    return {
        { text = is_anime and _("Watching") or _("Reading"), value = "CURRENT" },
        { text = is_anime and _("Plan to watch") or _("Planning"), value = "PLANNING" },
        { text = _("Completed"), value = "COMPLETED" },
        { text = _("On hold"), value = "PAUSED" },
        { text = _("Dropped"), value = "DROPPED" },
        { text = is_anime and _("Rewatching") or _("Rereading"), value = "REPEATING" },
    }
end

local function getStatusLabel(value, is_anime)
    local statuses = StatusMenu.choices(is_anime)
    for status_index = 1, #statuses do
        local status = statuses[status_index]
        if status.value == value then
            return status.text
        end
    end
    return value
end

---@param plugin Kanisync
---@param anilist_data KanisyncEntry
function StatusMenu.updateStatusMenu(plugin, anilist_data)
    ---@type table
    local status_items = {}
    ---@type ReadingStatus
    local selected_status = anilist_data.user_list_entry.status
    local statuses = StatusMenu.choices(false)
    for status_index = 1, #statuses do
        local status = statuses[status_index]
        table.insert(status_items, {
            text = status.text,
            radio = true,
            checked_func = function()
                return selected_status == status.value
            end,
            callback = function()
                selected_status = status.value
            end
        })
    end

    table.insert(status_items, {
        text = _("Save"),
        callback = function()
            NetworkMgr:runWhenOnline(function()
                local result, error = plugin.api:updateMediaList(anilist_data.user_list_entry.id, anilist_data.id,
                    { status = selected_status })
                if error or not result then
                    Messages.ephemeralMessage(error or _("AniList returned an invalid response"))
                    return
                end
                plugin:saveBookUserMetadata(result)
                Messages.ephemeralMessage(_("Updated reading status"))
            end)
        end
    })

    return status_items
end

StatusMenu.getStatusLabel = getStatusLabel

return StatusMenu
