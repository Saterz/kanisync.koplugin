local BD = require("ui/bidi")
local Button = require("ui/widget/button")
local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local Screen = Device.screen

local TagStrip = InputContainer:extend{}

function TagStrip:init()
    local arrow_width = Screen:scaleBySize(38)
    local gap = Size.padding.small
    local min_chip_width = Screen:scaleBySize(118)
    local slots = math.max(1, math.floor((self.width + gap) / (min_chip_width + gap)))
    self.paged = #self.tags > slots
    local available = self.width
    if self.paged then
        available = available - 2 * (arrow_width + gap)
        slots = math.max(1, math.floor((available + gap) / (min_chip_width + gap)))
    end
    self.slots = math.min(slots, #self.tags)
    self.chip_width = math.floor((available - (self.slots - 1) * gap) / self.slots)
    self.arrow_width = arrow_width
    self.page = 1
    self.focus_row = {}
    self.dimen = Geom:new{}
    self.ges_events = { TagSwipe = { GestureRange:new { ges = "swipe", range = self.dimen } } }
    self:buildRow()
end

function TagStrip:buildRow()
    if self[1] then self[1]:free() end
    local row = HorizontalGroup:new { align = "center" }
    self[1] = row
    for index = #self.focus_row, 1, -1 do self.focus_row[index] = nil end
    local function add(button)
        if #row > 0 then row[#row + 1] = HorizontalSpan:new{ width = Size.padding.small } end
        row[#row + 1] = button
        self.focus_row[#self.focus_row + 1] = button
    end
    local function arrow(direction, enabled)
        local previous = direction < 0
        local icon = previous ~= BD.mirroredUILayout() and "chevron.left" or "chevron.right"
        return Button:new {
            icon = icon, icon_width = Screen:scaleBySize(18), icon_height = Screen:scaleBySize(18),
            width = self.arrow_width, padding_h = Size.padding.small, enabled = enabled,
            height = Screen:scaleBySize(22), radius = Size.radius.button, show_parent = self.show_parent,
            callback = function() self:turn(direction) end,
        }
    end
    if self.paged then add(arrow(-1, self.page > 1)) end
    local first = (self.page - 1) * self.slots + 1
    for index = first, math.min(first + self.slots - 1, #self.tags) do
        local tag = self.tags[index]
        add(Button:new {
            text = tag, width = self.chip_width, height = Screen:scaleBySize(22),
            text_font_size = 16, radius = Size.radius.button, show_parent = self.show_parent,
            callback = function() self.on_select(tag) end,
        })
    end
    if self.paged then add(arrow(1, first + self.slots <= #self.tags)) end
    local size = row:getSize()
    self.dimen.w, self.dimen.h = self.width, size.h
end

function TagStrip:turn(direction)
    local page = self.page + direction
    if page < 1 or page > math.ceil(#self.tags / self.slots) then return end
    self.page = page
    self:buildRow()
    self.show_parent:refocusInlineRow(self.focus_row)
    UIManager:setDirty(self.show_parent, "ui")
end

function TagStrip:onTagSwipe(_, ges)
    if not self.paged then return end
    local direction = BD.flipDirectionIfMirroredUILayout(ges.direction)
    if direction == "west" then self:turn(1)
    elseif direction == "east" then self:turn(-1)
    else return end
    return true
end

return TagStrip
