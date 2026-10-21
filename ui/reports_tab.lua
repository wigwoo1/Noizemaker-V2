local widgets = require("ui.widgets")
local theme = require("ui.theme")
local report = require("core.report")
local M = {}

function M.new_state()
    return {number = 1, query = "", search_focus = false, include_variants = false, scroll = 0, hits = {},order_mode='cpu'}
end

local function text(value, x, y, color, font)
    love.graphics.setFont(theme.font(font or "small"))
    love.graphics.setColor(color or theme.colors.text)
    love.graphics.print(value, x, y)
end

function M.draw(state, rect)
    state.hits = {}
    local left, width = rect.x + 24, rect.w - 48
    text("English report browser", left, rect.y + 18, nil, "title")
    local available=state.report and state.report.cpu_route~=nil
    local ordered=available and state.order_mode~='files' and not state.include_variants
    local order_button={x=left+width-208,y=rect.y+20,w=208,h=30}
    widgets.draw_button(order_button,ordered and 'Order: CPU run' or 'Order: files',{disabled=not available})
    if available then state.hits[#state.hits+1]={kind='order',rect=order_button} end
    text("Find a section or command, then open its timeline. Original file names stay attached to every phrase.", left, rect.y + 62, theme.colors.text_dim)
    local y = rect.y + 92
    for number = 1, 6 do
        local button = {x = left + (number - 1) * 104, y = y, w = 96, h = 30}
        widgets.draw_button(button, "Report " .. number, {fill = state.number == number and theme.colors.selection_soft or theme.colors.button})
        state.hits[#state.hits + 1] = {kind = "report", number = number, rect = button}
    end
    local variant_button = {x = left + width - 208, y = y, w = 208, h = 30}
    widgets.draw_button(variant_button, state.include_variants and "Variants: shown" or "Variants: hidden")
    state.hits[#state.hits + 1] = {kind = "variants", rect = variant_button}
    local search = {x = left, y = y + 42, w = width, h = 32}
    widgets.draw_panel(search, {fill = theme.colors.panel, border = state.search_focus and theme.colors.selection or theme.colors.border})
    text(state.query ~= "" and ("Search: " .. state.query .. (state.search_focus and "|" or "")) or "Search section, phrase, file name, UP, CHU, HEY...", left + 12, search.y + 8, theme.colors.text_dim)
    state.hits[#state.hits + 1] = {kind = "search", rect = search}
    local title = state.report and state.report.title or state.error or "Choose a report to load its English files."
    text(title, left, search.y + 44)
    local note=ordered and 'Recorded CPU route; other branches differ. Handoff not continuously captured. Scene names provisional.' or
        'File order. Alternate phrases are choices, not a playlist. Scene names and unobserved locations are provisional.'
    text(note, left, search.y + 66, theme.colors.amber, "tiny")

    local list = {x = left, y = search.y + 92, w = width, h = math.max(40, rect.h - (search.y - rect.y) - 150)}
    local rows = ordered and report.cpu_rows(state.report,state.query) or report.rows(state.report, state.include_variants, state.query)
    state.content_height = #rows * 66
    state.list_height = list.h
    state.scroll = math.max(0, math.min(state.scroll, state.content_height - list.h))
    widgets.scissor_push(list)
    for i, row in ipairs(rows) do
        local box = {x = list.x, y = list.y + (i - 1) * 66 - state.scroll, w = list.w, h = 60}
        if box.y + box.h >= list.y and box.y <= list.y + list.h then
            widgets.draw_panel(box, {fill = theme.colors.panel_alt, border = theme.colors.border_soft, radius = 8})
            local button = {x = box.x + box.w - 100, y = box.y + 15, w = 88, h = 28}
            widgets.draw_button(button, "Edit phrase")
            text((row.event and (row.event.order..'. ') or '')..row.file.section .. " / " .. row.label, box.x + 12, box.y + 7)
            local details = row.file.variant .. " | " .. row.file.relative_path .. " | " .. row.entry.name
            if row.event then
                details=string.format('%s | %s | %s | recorded response %.2fs in this part',row.file.relative_path,row.entry.name,row.event.question,row.event.response_seconds)
                if #row.aliases>1 then details=details..' | identical SH2 alias' end
            end
            text(details, box.x + 12, box.y + 25, theme.colors.text_muted, "tiny")
            -- Clip command previews before the edit button on smaller windows.
            love.graphics.setFont(theme.font("tiny"))
            love.graphics.setColor(theme.colors.accent)
            local available = math.max(20, box.w - 130)
            local preview = row.commands
            while #preview > 0 and love.graphics.getFont():getWidth(preview) > available do
                preview = preview:sub(1, -2)
            end
            love.graphics.print(preview, box.x + 12, box.y + 42)
            local visible = {x = button.x, y = math.max(button.y, list.y), w = button.w,
                h = math.max(0, math.min(button.y + button.h, list.y + list.h) - math.max(button.y, list.y))}
            state.hits[#state.hits + 1] = {kind = "entry", row = row, rect = visible}
        end
    end
    widgets.scissor_pop()
    text(#rows .. " phrases shown. Scroll to browse. Use Project or Ctrl+S to save edits across files.", left, rect.y + rect.h - 50, theme.colors.text_muted, "tiny")
end

function M.mousepressed(state, x, y, button)
    if button ~= 1 then return nil end
    state.search_focus = false
    for _, hit in ipairs(state.hits) do
        if widgets.point_in_rect(x, y, hit.rect) then
            state.search_focus = hit.kind == "search"
            return hit
        end
    end
end

function M.wheelmoved(state, y)
    state.scroll = math.max(0, math.min(state.scroll - y * 66, (state.content_height or 0) - (state.list_height or 0)))
end

return M
