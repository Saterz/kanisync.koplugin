local NetworkMgr = require("ui/network/manager")
local _ = require("gettext")

local StatusMenu = {}

local statuses = {
    { text = _("Reading"),   value = "CURRENT" },
    { text = _("Planning"),  value = "PLANNING" },
    { text = _("Completed"), value = "COMPLETED" },
    { text = _("On hold"),   value = "PAUSED" },
    { text = _("Dropped"),   value = "DROPPED" },
}

local function getStatusLabel(value)
    for status_index = 1, #statuses do
        local status = statuses[status_index]
        if status.value == value then
            return status.text
        end
    end
    return value
end

---@param anilist_data KanisyncEntry
function StatusMenu:updateStatusMenu(anilist_data)
    ---@type table
    local status_items = {}
    ---@type ReadingStatus
    local selected_status = anilist_data.user_list_entry.status
    for status_index = 1, #statuses do
        local status = statuses[status_index]
        table.insert(status_items, {
            text = _(status.text),
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
                local result, error = self.plugin.api:updateMediaList(anilist_data.user_list_entry.id, anilist_data.id,
                    { status = selected_status })
                if error or not result then
                    self.ephemeralMessage(error or _("AniList returned an invalid response"))
                    return
                end
                self.plugin:saveBookUserMetadata(result)
                self.ephemeralMessage(_("Updated reading status"))
            end)
        end
    })

    return status_items
end

StatusMenu.getStatusLabel = getStatusLabel

return StatusMenu
