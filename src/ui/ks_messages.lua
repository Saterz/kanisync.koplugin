local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local ffiUtil = require("ffi/util")
local _ = require("gettext")
local T = ffiUtil.template

local Messages = {}

---@param plugin Kanisync
function Messages.about(plugin)
    Messages.showMessage(T(_("%1\n\n%2\n\nVersion: v%3"), plugin.fullname, plugin.description, plugin.version))
end

---@param message string
function Messages.ephemeralMessage(message, dialog)
    if dialog ~= nil then
        UIManager:close(dialog)
    end
    UIManager:show(InfoMessage:new {
        text = _(message),
        timeout = 3,
    })
end

---@param message string
function Messages.showMessage(message)
    local info_message_widget = InfoMessage:new({ text = message })
    UIManager:show(info_message_widget)
    return info_message_widget
end

return Messages
