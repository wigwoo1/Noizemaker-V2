local widgets = require("ui.widgets")
local theme = require("ui.theme")
local playback = require("core.playback")
local format = require("core.format")
local M = {}

function M.report_descriptor(state)
    local title=state.plan.title or ('Report '..tostring(state.plan.report or 1))
    if state.report_order and state.plan.phrases then title=title..' · '..state.report_order..'/'..#state.plan.phrases end
    local omitted=#(state.plan.omitted_voice_events or {})>0
    local sync=state.plan.response_timing_checked and " · responses checked · ending provisional"
        or (state.plan.alignment_verified and "" or " · sync unverified")
    local music=state.plan.music_enabled~=false
    if state.plan.voices_enabled then
        if state.plan.report==4 or state.plan.report==5 then
            return string.format('%s · music + %d/%d original calls · sync unverified',
                title,#state.plan.events,#state.plan.events+#(state.plan.omitted_voice_events or {}))
        end
        local mode=music and "music + calls" or "English calls only"
        return omitted and (title.." · "..mode.." · unknown skipped"..sync)
            or (title.." · "..mode..sync)
    end
    return (music and (title.." · music only · calls muted") or (title.." · audio muted"))..sync
end

function M.draw(rect, state, entry)
    widgets.draw_panel(rect, {fill = theme.colors.panel_alt, border = theme.colors.border_soft, radius = 0})
    local hits = {}
    if state.mode == "report" then
        local buttons={{"play",state.playing and "Pause" or "Play",66},
            {"stop",state.report_job and "Cancel" or "Stop",70},
            {"loop",state.looping and "Loop: on" or "Loop: off",92},
            {"previous_phrase","Prev",44},{"next_phrase","Next",44},{"phrase_preview","Phrase",68}}
        local x=rect.x+16
        for _,item in ipairs(buttons) do
            local box={x=x,y=rect.y+6,w=item[3],h=26}
            local disabled=(item[1]=='play' and state.report_job~=nil and not state.source)
                or ((item[1]=='previous_phrase' or item[1]=='next_phrase') and not entry)
            widgets.draw_button(box,item[2],{disabled=disabled})
            if not disabled then hits[#hits+1]={kind=item[1],rect=box} end
            x=x+item[3]+8
        end
        love.graphics.setFont(theme.font("tiny"));love.graphics.setColor(theme.colors.text_dim)
        local descriptor=M.report_descriptor(state)
        love.graphics.print(descriptor,x+4,rect.y+12)
        local slider={x=rect.x+18,y=rect.y+42,w=rect.w-236,h=12}
        widgets.draw_panel(slider,{fill=theme.colors.track,border=theme.colors.border_soft,radius=4})
        local duration=state.plan.duration or 0
        local fraction=duration>0 and math.max(0,math.min(1,state.position/duration)) or 0
        love.graphics.setColor(theme.colors.accent)
        love.graphics.rectangle("fill",slider.x,slider.y,slider.w*fraction,slider.h,4,4)
        hits[#hits+1]={kind="seek",rect={x=slider.x,y=slider.y-4,w=slider.w,h=20}}
        love.graphics.setColor(theme.colors.amber)
        love.graphics.print(string.format("%.2f / %.2fs",state.position,duration),slider.x+slider.w+12,rect.y+40)
        return hits
    end
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
    if state.plan and state.plan.question_duration then
        tempo_label=(state.position<state.plan.question_duration and 'enemy call' or 'Ulala response')..' · '..tempo_label
    end
    if state.plan and state.plan.music and state.plan.music.timing_checked then tempo_label="timing checked" end
    love.graphics.print(string.format("%.2f / %.2fs | %s", state.position, duration, tempo_label), slider.x + slider.w + 12, rect.y + 40)
    return hits
end
return M
