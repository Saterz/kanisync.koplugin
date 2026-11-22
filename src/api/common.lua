local Common = {
    PAGE_SIZE = 12,
    INVALID_RESPONSE = "AniList returned an invalid response",
}

function Common.isPositiveInt(value)
    return type(value) == "number" and value >= 1 and value <= 2147483647 and value % 1 == 0
end

function Common.dataField(result, field)
    if type(result) == "table" and type(result.data) == "table" and type(result.data[field]) == "table" then
        return result.data[field]
    end
    return nil, Common.INVALID_RESPONSE
end

function Common.page(result, field)
    local page = Common.dataField(result, "Page")
    if not page or type(page[field]) ~= "table" or type(page.pageInfo) ~= "table"
            or type(page.pageInfo.hasNextPage) ~= "boolean" then
        return nil, Common.INVALID_RESPONSE
    end
    return page
end

function Common.isVisible(api, media)
    return type(media) == "table" and (not api.filter_adult_content or media.isAdult == false)
end

return Common
