local UIManager = require("ui/uimanager")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local Geom = require("ui/geometry")
local ImageWidget = require("ui/widget/imagewidget")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local NetworkMgr = require("ui/network/manager")
local RenderImage = require("ui/renderimage")
local Screen = require("device").screen
local Size = require("ui/size")
local T = require("ffi/util").template
local _ = require("gettext")

local KanisyncUI = {}
KanisyncUI.__index = KanisyncUI

function KanisyncUI:new()
    local obj = setmetatable({}, self)
    obj:init()
    return obj
end

function KanisyncUI:init()
    -- Doesn't do anything yet
end

---@param plugin Kanisync
function KanisyncUI:main_menu(plugin)
    local is_token_provided = plugin:hasToken()

    local no_token_menu = { text = "Token not found", enabled = false }

    local menu = {}
    if not is_token_provided then
        table.insert(menu, no_token_menu)
    else
        table.insert(menu, {
            text = _("Link book to AniList"),
            keep_menu_open = false,
            callback = function()
                NetworkMgr:runWhenOnline(function()
                    plugin:linkBookToAniList()
                end)
            end,
        })
    end

    table.insert(menu, {
        text = _("About"),
        keep_menu_open = true,
        callback = function()
            self:about(plugin)
        end,
    })

    return menu
end

function KanisyncUI:about(plugin)
    UIManager:show(InfoMessage:new({
        text = "Kanisync\n\nSync your reading progress with AniList\n\nVersion: v" .. plugin.version,
    }))
end

local function getMediaTitle(media)
    local title = type(media.title) == "table" and media.title or {}
    local candidates = { title.userPreferred, title.english, title.romaji, title.native }
    for title_index = 1, 4 do
        local value = candidates[title_index]
        if type(value) == "string" then return value end
    end
    return T(_("AniList entry #%1"), tostring(media.id))
end

local function renderCover(image_data, max_width, max_height)
    if not image_data then return end

    local cover = RenderImage:renderImageData(image_data, #image_data, false)
    if not cover then return end

    local cover_width, cover_height = cover:getWidth(), cover:getHeight()
    local scale = math.min(max_width / cover_width, max_height / cover_height, 1)
    if scale < 1 then
        cover_width = math.floor(cover_width * scale)
        cover_height = math.floor(cover_height * scale)
        cover = RenderImage:scaleBlitBuffer(cover, cover_width, cover_height, true)
    end
    return cover, cover_width, cover_height
end

---@param search_query string
---@param search_callback fun(search_query: string)
---@param no_results? boolean
function KanisyncUI:searchDialog(search_query, search_callback, no_results)
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

---@param media table
---@param select_callback fun(media: table)
---@param cover_loader fun(url: string): string|nil
function KanisyncUI:previewMedia(media, select_callback, cover_loader)
    local title = getMediaTitle(media)
    local details = {}
    if type(media.format) == "string" then table.insert(details, media.format) end
    if type(media.startDate) == "table" and type(media.startDate.year) == "number" then
        table.insert(details, tostring(media.startDate.year))
    end
    if type(media.volumes) == "number" then table.insert(details, T(_("%1 volumes"), media.volumes)) end
    if type(media.chapters) == "number" then table.insert(details, T(_("%1 chapters"), media.chapters)) end

    local confirm = ConfirmBox:new {
        text = title .. (#details > 0 and "\n" .. table.concat(details, " • ") or ""),
        ok_text = _("Link"),
        ok_callback = function()
            select_callback(media)
            UIManager:show(InfoMessage:new {
                text = T(_("Linked to %1."), title),
                timeout = 3,
            })
        end,
    }

    local cover_url = type(media.coverImage) == "table"
        and type(media.coverImage.medium) == "string"
        and media.coverImage.medium
    if cover_url then
        local max_width = confirm:getAddedWidgetAvailableWidth()
        local max_height = math.floor(Screen:getHeight() * 0.45)
        local cover, cover_width, cover_height = renderCover(
            media._cover_data or cover_loader(cover_url),
            max_width,
            max_height
        )
        if cover then
            confirm:addWidget(CenterContainer:new {
                dimen = Geom:new {
                    w = max_width,
                    h = cover_height,
                },
                ImageWidget:new {
                    image = cover,
                    width = cover_width,
                    height = cover_height,
                },
            })
        end
    end

    UIManager:show(confirm)
end

---@param media_list table
---@param search_query string
---@param select_callback fun(media: table)
---@param search_callback fun(search_query: string)
---@param cover_loader fun(url: string): string|nil
function KanisyncUI:mediaChooser(media_list, search_query, select_callback, search_callback, cover_loader)
    if #media_list == 0 then
        self:searchDialog(search_query, search_callback, true)
        return
    end

    local loading = InfoMessage:new { text = _("Loading cover images…") }
    UIManager:show(loading)
    UIManager:nextTick(function()
        local thumbnail_width = Screen:scaleBySize(48)
        local thumbnail_height = Screen:scaleBySize(68)
        local thumbnail_buffers = {}
        local items = {
            {
                text = _("Adjust search..."),
                callback = function()
                    UIManager:nextTick(function()
                        self:searchDialog(search_query, search_callback)
                    end)
                end,
            },
        }

        for media_index = 1, #media_list do
            local media = media_list[media_index]
            local metadata = {}
            if type(media.format) == "string" then table.insert(metadata, media.format) end
            if type(media.startDate) == "table" and type(media.startDate.year) == "number" then
                table.insert(metadata, tostring(media.startDate.year))
            end
            if type(media.volumes) == "number" then table.insert(metadata, T(_("%1 vol."), media.volumes)) end
            if type(media.chapters) == "number" then table.insert(metadata, T(_("%1 ch."), media.chapters)) end

            local cover_widget
            local cover_url = type(media.coverImage) == "table"
                and type(media.coverImage.medium) == "string"
                and media.coverImage.medium
            if cover_url then
                media._cover_data = cover_loader(cover_url)
                local cover = renderCover(media._cover_data, thumbnail_width, thumbnail_height)
                if cover then
                    table.insert(thumbnail_buffers, cover)
                    cover_widget = CenterContainer:new {
                        dimen = Geom:new {
                            w = thumbnail_width,
                            h = thumbnail_height,
                        },
                        ImageWidget:new {
                            image = cover,
                            image_disposable = false,
                        },
                    }
                end
            end

            local metadata_text = table.concat(metadata, " • ")
            table.insert(items, {
                text = getMediaTitle(media) .. (metadata_text ~= "" and " — " .. metadata_text or ""),
                state = cover_widget,
                callback = function()
                    UIManager:nextTick(function()
                        self:previewMedia(media, select_callback, cover_loader)
                    end)
                end,
            })
        end

        local chooser
        chooser = Menu:new {
            title = T(_("AniList results for “%1”"), search_query),
            item_table = items,
            state_w = thumbnail_width + Size.span.horizontal_default,
            items_per_page = 6,
            multilines_forced = true,
            dithered = true,
            close_callback = function()
                UIManager:close(chooser)
                for buffer_index = 1, #thumbnail_buffers do
                    thumbnail_buffers[buffer_index]:free()
                end
                thumbnail_buffers = {}
            end,
        }
        UIManager:close(loading)
        UIManager:show(chooser)
    end)
end

---@param error_message string
function KanisyncUI:errorMessage(error_message, dialog)
    if dialog ~= nil then
        UIManager:close(dialog)
    end
    UIManager:show(InfoMessage:new {
        text = _(error_message),
        timeout = 3,
    })
end

return KanisyncUI
