local MainMenu = require("ui/main_menu")
local TokenDialog = require("ui/token_dialog")
local EntryMenu = require("ui/entry_menu")
local NoteDialog = require("ui/note_dialog")
local ScoreDialog = require("ui/score_dialog")
local StatusMenu = require("ui/status_menu")
local Progress = require("ui/progress")
local DatesMenu = require("ui/dates_menu")
local SettingsMenu = require("ui/settings_menu")
local AutoLinkFolders = require("ui/auto_link_folders")
local SearchDialog = require("ui/search_dialog")
local MediaChooser = require("ui/media_chooser")
local MediaPreview = require("ui/media_preview")
local Messages = require("ui/messages")

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

KanisyncUI.main_menu = MainMenu.main_menu
KanisyncUI.updateTokenDialog = TokenDialog.updateTokenDialog
KanisyncUI.manageEntry = EntryMenu.manageEntry
KanisyncUI._editNote = NoteDialog.show
KanisyncUI._editScore = ScoreDialog.show
KanisyncUI.updateStatusMenu = StatusMenu.updateStatusMenu
KanisyncUI.progressMenu = Progress.progressMenu
KanisyncUI.progressUpdatePrompt = Progress.progressUpdatePrompt
KanisyncUI.datesReadMenu = DatesMenu.datesReadMenu
KanisyncUI.settingsMenu = SettingsMenu.settingsMenu
KanisyncUI.preferencesMenu = SettingsMenu.preferencesMenu
KanisyncUI.autoLinkFoldersMenu = AutoLinkFolders.autoLinkFoldersMenu
KanisyncUI.searchDialog = SearchDialog.searchDialog
KanisyncUI.mediaChooser = MediaChooser.mediaChooser
KanisyncUI.previewMedia = MediaPreview.previewMedia
KanisyncUI.ephemeralMessage = Messages.ephemeralMessage
KanisyncUI.showMessage = Messages.showMessage
KanisyncUI.about = Messages.about

return KanisyncUI
