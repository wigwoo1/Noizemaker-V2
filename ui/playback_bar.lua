local widgets = require("ui.widgets")
local theme = require("ui.theme")
local playback = require("core.playback")
local format = require("core.format")
local M = {}

function M.draw(rect, state, entry)
    widgets.draw_panel(rect, {fill = theme.colors.panel_alt, border = theme.colors.border_soft, radius = 0})
    local hits = {}
    local first, last = state.range_start or 0, state.range_end or (entry and format.total_ticks(entry.timing) or 0)
    local buttons = {
        {"play", state.playing and "Pause" or "Play", 68}, {"stop", "Stop", 68},
        {"loop", state.looping and "Loop: on" or "Loop: off", 96},
        {"range_start", "From: " .. first .. "t", 94}, {"range_end", "To: " .. last .. "t", 94},
        {"range_all", "All", 60}, {"slower", "-", 32},
        {"tempo", tostring(state.bpm or (entry and playback.tempo(entry) or 120)) .. " BPM", 80}, {"faster", "+", 32},
        {"music", state.music_enabled and "Music: auto" or "Music: off", 96},
        {'previous_phrase','Prev',40},{'next_phrase','Next',40},
    }
    local x = rect.x + 16
    for _, item in ipairs(buttons) do
        local box = {x = x, y = rect.y + 6, w = item[3], h = 26}
        local navigation=item[1]=='previous_phrase' or item[1]=='next_phrase'
        local disabled=not entry or (navigation and not entry.route)
        widgets.draw_button(box, item[2], {disabled = disabled})
        if not disabled then hits[#hits + 1] = {kind = item[1], rect = box} end
        x = x + item[3] + 8
    end
    love.graphics.setFont(theme.font("tiny"))
    love.graphics.setColor(theme.colors.text_dim)
    if rect.w-x>110 then love.graphics.print("English voice", x + 4, rect.y + 12) end
    local slider = {x = rect.x + 18, y = rect.y + 42, w = rect.w - 302, h = 12}
    widgets.draw_panel(slider, {fill = theme.colors.track, border = theme.colors.border_soft, radius = 4})
    local duration = state.plan and state.plan.duration or (entry and (last - first) * 60 / ((state.bpm or playback.tempo(entry)) * format.CHART_TICKS_PER_BEAT) or 0)
    local fraction = duration > 0 and math.max(0, math.min(1, state.position / duration)) or 0
    love.graphics.setColor(theme.colors.accent)
    love.graphics.rectangle("fill", slider.x, slider.y, slider.w * fraction, slider.h, 4, 4)
    hits[#hits + 1] = {kind = "seek", rect = {x = slider.x, y = slider.y - 4, w = slider.w, h = 20}}
    love.graphics.setColor(theme.colors.amber)
    local _, source = playback.tempo(entry or {})
    local tempo_label = state.bpm and "manual BPM" or (source == "chart" and "chart BPM" or "fallback BPM")
    love.graphics.print(string.format("%.2f / %.2fs | %s", state.position, duration, tempo_label), slider.x + slider.w + 12, rect.y + 40)
    return hits
end
return M
