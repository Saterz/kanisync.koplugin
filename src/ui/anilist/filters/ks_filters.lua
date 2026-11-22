local Blitbuffer = require("ffi/blitbuffer")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local T = require("ffi/util").template
local _ = require("gettext")

local Filters = {}

local media_types = {
    { "MANGA", _("Manga") },
    { "ANIME", _("Anime") },
}

local formats = {
    MANGA = {
        { "MANGA", _("Manga") },
        { "NOVEL", _("Light novel") },
        { "ONE_SHOT", _("One-shot") },
    },
    ANIME = {
        { "TV", _("TV") },
        { "TV_SHORT", _("TV short") },
        { "MOVIE", _("Movie") },
        { "SPECIAL", _("Special") },
        { "OVA", _("OVA") },
        { "ONA", _("ONA") },
        { "MUSIC", _("Music") },
    },
}

local publishing_statuses = {
    { "RELEASING", _("Releasing") },
    { "FINISHED", _("Finished") },
    { "NOT_YET_RELEASED", _("Not yet released") },
    { "HIATUS", _("On hiatus") },
    { "CANCELLED", _("Cancelled") },
}

local function listStatuses(is_anime)
    return {
        { "CURRENT", is_anime and _("Watching") or _("Reading") },
        { "PLANNING", _("Planning") },
        { "COMPLETED", _("Completed") },
        { "PAUSED", _("Paused") },
        { "DROPPED", _("Dropped") },
        { "REPEATING", is_anime and _("Rewatching") or _("Rereading") },
    }
end

-- Catalog uses MediaSort; library uses MediaListSort.
local catalog_sorts = {
    { "POPULARITY_DESC", _("Most popular") },
    { "SCORE_DESC", _("Highest rated") },
    { "TRENDING_DESC", _("Trending") },
    { "START_DATE_DESC", _("Newest release first") },
    { "START_DATE", _("Oldest release first") },
    { "TITLE_ROMAJI", _("Romaji title (A–Z)") },
}

local library_sorts = {
    { "UPDATED_TIME_DESC", _("Recently updated") },
    { "ADDED_TIME_DESC", _("Recently added") },
    { "SCORE_DESC", _("Highest personal score") },
    { "PROGRESS_DESC", _("Most progress") },
    { "MEDIA_TITLE_ROMAJI", _("Romaji title (A–Z)") },
}

local genres = {
    { "Action", _("Action") },
    { "Adventure", _("Adventure") },
    { "Comedy", _("Comedy") },
    { "Drama", _("Drama") },
    { "Ecchi", _("Ecchi") },
    { "Fantasy", _("Fantasy") },
    { "Hentai", _("Hentai") },
    { "Horror", _("Horror") },
    { "Mahou Shoujo", _("Mahou Shoujo") },
    { "Mecha", _("Mecha") },
    { "Music", _("Music") },
    { "Mystery", _("Mystery") },
    { "Psychological", _("Psychological") },
    { "Romance", _("Romance") },
    { "Sci-Fi", _("Sci-Fi") },
    { "Slice of Life", _("Slice of Life") },
    { "Sports", _("Sports") },
    { "Supernatural", _("Supernatural") },
    { "Thriller", _("Thriller") },
}

local seasons = {
    { "WINTER", _("Winter") },
    { "SPRING", _("Spring") },
    { "SUMMER", _("Summer") },
    { "FALL", _("Fall") },
}

local function choiceLabel(choices, value, unset_label)
    if value == nil then return unset_label end
    for index = 1, #(choices or {}) do
        if choices[index][1] == value then return choices[index][2] end
    end
    return tostring(value)
end

function Filters.summary(mode, options)
    local media_type = options.type or "MANGA"
    local is_catalog = mode == "catalog"
    local default_sort = _("Default")
    if is_catalog then default_sort = options.search and _("Relevance") or _("Most popular") end
    local values = {
        choiceLabel(media_types, media_type),
        T(_("Sort: %1"), choiceLabel(is_catalog and catalog_sorts or library_sorts, options.sort, default_sort)),
    }
    local function add(label, value, choices)
        if value then values[#values + 1] = T(_("%1: %2"), label, choiceLabel(choices, value)) end
    end
    if is_catalog then
        add(_("Format"), options.format, formats[media_type])
        add(_("Status"), options.status, publishing_statuses)
        add(_("Genre"), options.genre, genres)
        add(_("Tag"), options.tag)
        add(_("Year"), options.year)
        if media_type == "ANIME" then add(_("Season"), options.season, seasons) end
    else
        add(_("Status"), options.status, listStatuses(media_type == "ANIME"))
    end
    return table.concat(values, " · ")
end

local function fullscreenMenu(title, items)
    return Menu:new {
        title = title,
        title_shrink_font_to_fit = true,
        item_table = items,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
    }
end

local function choose(title, choices, current, unset_label, on_choice)
    local items = {}
    local menu
    local function add(value, label)
        local selected = current == value
        items[#items + 1] = {
            text = label,
            mandatory = selected and _("Selected") or nil,
            callback = function()
                UIManager:close(menu)
                on_choice(value)
            end,
        }
        if selected then items.current = #items end
    end
    if unset_label then add(nil, unset_label) end
    for index = 1, #choices do add(choices[index][1], choices[index][2]) end
    menu = fullscreenMenu(title, items)
    UIManager:show(menu)
end

local function editText(title, value, is_year, on_choice)
    local dialog
    local year_hint = _("Enter a whole year from 1 to 9999.")
    local function finish(new_value)
        UIManager:close(dialog)
        on_choice(new_value)
    end
    dialog = InputDialog:new {
        title = title,
        description = is_year and year_hint or _("Enter the tag name as it appears on AniList."),
        input = value and tostring(value) or "",
        input_type = is_year and "number" or nil,
        buttons = { {
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("Clear"), callback = function() finish(nil) end },
            {
                text = _("Done"),
                background = Blitbuffer.COLOR_LIGHT_GRAY,
                is_enter_default = true,
                callback = function()
                    local text = dialog:getInputText():match("^%s*(.-)%s*$")
                    if text == "" then
                        finish(nil)
                    elseif not is_year then
                        finish(text)
                    else
                        local year = text:match("^%d+$") and tonumber(text)
                        if year and year >= 1 and year <= 9999 then
                            finish(year)
                        else
                            UIManager:show(InfoMessage:new { text = year_hint, modal = true })
                        end
                    end
                end,
            },
        } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

---@param mode 'catalog'|'library'
---@param options? CatalogOptions|LibraryOptions
---@param on_apply fun(options: CatalogOptions|LibraryOptions)
function Filters.show(mode, options, on_apply)
    assert(mode == "catalog" or mode == "library", "Unknown AniList filter mode")
    local is_catalog = mode == "catalog"
    local draft = {}
    for field, value in pairs(options or {}) do draft[field] = value end

    local menu
    local function buildItems()
        local media_type = draft.type or "MANGA" -- Default in both API methods.
        local is_anime = media_type == "ANIME"
        local items = { {
            text = _("Apply filters"),
            bold = true,
            callback = function()
                if is_catalog and not is_anime then draft.season = nil end
                UIManager:close(menu)
                on_apply(draft)
            end,
        } }

        local function add(field, title, choices, unset_label)
            local current = field == "type" and media_type or draft[field]
            local label = choiceLabel(choices, current, unset_label)

            local row = #items + 1
            local function update(value)
                if is_catalog and field == "type" and value ~= media_type then
                    -- Formats do not overlap, and seasons only apply to anime.
                    draft.format = nil
                    if value ~= "ANIME" then draft.season = nil end
                end
                draft[field] = value
                menu:switchItemTable(nil, buildItems(), row)
            end
            items[row] = {
                text = T(_("%1: %2"), title, label),
                callback = function()
                    if choices then
                        choose(title, choices, current, unset_label, update)
                    else
                        editText(title, current, field == "year", update)
                    end
                end,
            }
        end

        add("type", _("Media type"), media_types)
        if is_catalog then
            add("format", _("Format"), formats[media_type], _("Any"))
            add("status", _("Publishing status"), publishing_statuses, _("Any"))
            add("sort", _("Sort by"), catalog_sorts, _("Default"))
            add("genre", _("Genre"), genres, _("Any"))
            add("tag", _("Tag"), nil, _("Any"))
            add("year", _("Release year"), nil, _("Any"))
            if is_anime then add("season", _("Season"), seasons, _("Any")) end
        else
            add("status", _("List status"), listStatuses(is_anime), _("Any"))
            add("sort", _("Sort by"), library_sorts, _("Default"))
        end

        items[#items + 1] = { text = _("Cancel"), callback = function() UIManager:close(menu) end }
        return items
    end

    menu = fullscreenMenu(is_catalog and _("Catalog filters") or _("Library filters"), buildItems())
    UIManager:show(menu)
end

return Filters
