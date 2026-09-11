local UIManager = require("ui/uimanager")
local InputDialog = require("ui/widget/inputdialog")
local NetworkMgr = require("ui/network/manager")
local _ = require("gettext")

local SearchDialog = {}

---@param search_query string
---@param search_callback fun(search_query: string)
---@param no_results? boolean
function SearchDialog.searchDialog(search_query, search_callback, no_results)
    local dialog
    dialog = InputDialog:new {
        title = _("Search AniList"),
        description = no_results and _("No matches were found. Adjust the search query and try again.")
            or _("Adjust the search query."),
        input = search_query,
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
                    text = _("Search"),
                    is_enter_default = true,
                    callback = function()
                        local query = dialog:getInputText()
                        if query and not query:match("^%s*$") then
                            UIManager:close(dialog)
                            NetworkMgr:runWhenOnline(function()
                                search_callback(query)
                            end)
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

return SearchDialog
