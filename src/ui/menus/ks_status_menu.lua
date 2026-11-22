local Request = require("ui/ks_foreground_request")
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
    local document = plugin.ui.document
    local function is_active()
        return document ~= nil and plugin.ui.document == document
    end

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
            if not is_active() then return end
            local api = plugin.api
            local entry_id, media_id = anilist_data.user_list_entry.id, anilist_data.id
            local status = selected_status
            Request.run(function()
                return api:updateMediaList(entry_id, media_id, { status = status })
            end, function(result, error)
                if not is_active() then return end
                if error or not result then
                    Messages.ephemeralMessage(error or _("AniList returned an invalid response"))
                    return
                end
                plugin:saveBookUserMetadata(result)
                Messages.ephemeralMessage(_("Updated reading status"))
            end, { text = _("Updating reading status..."), mutation = true, is_active = is_active })
        end
    })

    return status_items
end

StatusMenu.getStatusLabel = getStatusLabel

return StatusMenu
