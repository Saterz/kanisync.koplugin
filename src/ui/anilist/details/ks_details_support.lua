local ButtonDialog = require("ui/widget/buttondialog")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local Support = {}


function Support.error(controller, message)
    -- Use local messages, not raw transport errors that might contain request data.
    if controller.reportError then
        controller:reportError(message)
    else
        UIManager:show(InfoMessage:new { text = message })
    end
end


function Support.choose(title, items, callback)
    local dialog
    local buttons = {}
    for index, item in ipairs(items) do
        buttons[index] = { {
            text = item.text,
            callback = function()
                UIManager:close(dialog)
                callback(item.value)
            end,
        } }
    end
    buttons[#buttons + 1] = { { text = _("Back"), callback = function() UIManager:close(dialog) end } }
    dialog = ButtonDialog:new { title = title, use_info_style = false, buttons = buttons }
    UIManager:show(dialog)
end

return Support
