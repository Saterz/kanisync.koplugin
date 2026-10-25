local MainMenu = require("ui/ks_main_menu")
local Progress = require("ui/dialogs/ks_progress")
local MediaChooser = require("ui/dialogs/ks_media_chooser")
local MediaPreview = require("ui/dialogs/ks_media_preview")
local Messages = require("ui/ks_messages")

---@class KanisyncUI
---@field plugin Kanisync
local KanisyncUI = {}
KanisyncUI.__index = KanisyncUI

function KanisyncUI:new(plugin)
    local obj = setmetatable({}, self)
    obj:init(plugin)
    return obj
end

---@param plugin Kanisync
function KanisyncUI:init(plugin)
    self.plugin = plugin
end

---@param anilist_data KanisyncEntry?
function KanisyncUI:main_menu(anilist_data)
    return MainMenu.main_menu(self.plugin, anilist_data)
end

function KanisyncUI:progressUpdatePrompt(anilist_data, progress_scope, close_callback)
    return Progress.progressUpdatePrompt(self.plugin, anilist_data, progress_scope, close_callback)
end

KanisyncUI.mediaChooser = MediaChooser.mediaChooser
KanisyncUI.previewMedia = MediaPreview.previewMedia

KanisyncUI.ephemeralMessage = Messages.ephemeralMessage
KanisyncUI.showMessage = Messages.showMessage

return KanisyncUI
