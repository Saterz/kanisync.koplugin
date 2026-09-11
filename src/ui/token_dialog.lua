local UIManager = require("ui/uimanager")
local InputDialog = require("ui/widget/inputdialog")
local QRMessage = require("ui/widget/qrmessage")
local Device = require("device")
local _ = require("gettext")

local TokenDialog = {}

function TokenDialog:updateTokenDialog()
    local input
    input = InputDialog:new({
        title = _("Update AniList token"),
        input = "",
        text_type = "password",
        input_hint = _("Leave blank to delete"),
        description = _("Get your AniList token from the link in the QR code."),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(input)
                    end,
                },
                {
                    text = _("Show QR Code"),
                    callback = function()
                        UIManager:show(QRMessage:new {
                            text = "https://anilist.co/api/v2/oauth/authorize?client_id=40345&response_type=token",
                            width = Device.screen:getWidth(),
                            height = Device.screen:getHeight(),
                        })
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local value = input:getInputText()
                        UIManager:close(input)
                        self.plugin:setAniListToken(value)
                    end,
                },
            }
        },
    })
    UIManager:show(input)
    input:onShowKeyboard()
end

return TokenDialog
