local ButtonDialog = require("ui/widget/buttondialog")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local Request = {}
local RequestDialog = ButtonDialog:extend { name = "kanisync_foreground_request", modal = true }
local CONNECTION_TIMEOUT = 60

function RequestDialog:onShow()
    ButtonDialog.onShow(self)
    self:refocusWidget()
end

function RequestDialog:onClose()
    self.cancel_request()
    return true
end

function RequestDialog:onCloseWidget()
    ButtonDialog.onCloseWidget(self)
    self.cancel_request(true)
end

--- Run a network-only task in a killable worker and apply its result on the UI thread.
--- task and its return values must not depend on changes to the parent process.
function Request.run(task, on_complete, options)
    options = options or {}
    local function isActive()
        return not options.is_active or options.is_active()
    end
    if not isActive() then return end

    local dialog, wifi_timeout
    local finished, running = false, false
    local function finish(already_closed)
        if finished then return false end
        finished = true
        if wifi_timeout then UIManager:unschedule(wifi_timeout) end
        if not already_closed then UIManager:close(dialog) end
        return true
    end

    local function cancel(already_closed)
        local interrupt = dialog.dismiss_callback
        if not finish(already_closed) then return end
        -- Trapper kills and reaps the in-flight worker when its dismiss callback runs.
        if interrupt then interrupt() end
        if not isActive() then return end
        if options.on_cancel then options.on_cancel() end
        if running and options.mutation and not already_closed then
            UIManager:show(InfoMessage:new {
                text = _("Stopped waiting. AniList may already have applied the change. Refresh the entry before trying again."),
            })
        end
    end

    dialog = RequestDialog:new {
        title = options.text or _("Contacting AniList…"),
        title_align = "center", width_factor = 0.75, cancel_request = cancel,
        buttons = { { { text = _("Cancel"), callback = function() cancel() end } } },
    }
    UIManager:show(dialog)

    wifi_timeout = function()
        if finish() and isActive() then on_complete(nil, _("Could not connect to AniList.")) end
    end
    UIManager:scheduleIn(CONNECTION_TIMEOUT, wifi_timeout)
    NetworkMgr:runWhenOnline(function()
        if finished or running then return end
        if not isActive() then finish(); return end
        UIManager:unschedule(wifi_timeout)
        wifi_timeout = nil
        running = true
        Trapper:wrap(function()
            local reply = table.pack(Trapper:dismissableRunInSubprocess(function()
                local result = table.pack(pcall(task))
                if not result[1] then return nil, _("AniList request failed.") end
                return unpack(result, 2, result.n)
            end, dialog))
            dialog.dismiss_callback = nil
            if not finish() or not isActive() then return end
            if not reply[1] or reply.n == 1 then
                on_complete(nil, _("AniList request failed."))
            else
                on_complete(unpack(reply, 2, reply.n))
            end
        end)
    end)
end

return Request
