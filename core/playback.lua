local format = require("core.format")
local game_audio = require("core.game_audio")
local adx = require("core.adx")
local M = {}

local function warning(plan,message)
    for _,existing in ipairs(plan.warnings) do if existing==message then return end end
    plan.warnings[#plan.warnings+1]=message
end

local function hold_warning(plan,code,command)
    if command=="HOLDCHU" then
        warning(plan,"Original long Chu sample; hold stretching/release is not modeled.")
    elseif command and command:match('^R31_HOLD_') then
        warning(plan,'Original Report 3 held-call sample; hold stretching/release is not modeled.')
    elseif command and command:match('^R42_HOLD_') then
        warning(plan,'Original Report 4 held-call sample; audible timing and hold stretching/release are unverified.')
    elseif command=='R43_HOLD_CHU' then
        warning(plan,'Original Peace Carrier held Chu; audible timing and hold stretching/release are unverified.')
    elseif command=='R43_HOLD_HEY' then
        warning(plan,'Peace Carrier held Hey selects a native dummy take; a voiced held Hey is not verified.')
    elseif command and command:match('^DANCE_') then
        if code and format.step_display_name(code):match('^HOLD') then
            warning(plan,"Original Dance held-call sample; hold stretching/release is not modeled.")
        end
    elseif command and command:match('^R6[12]_') and code==13 then
        warning(plan,"Original Report 6 long Down sample; hold stretching/release is not modeled.")
    elseif code and format.step_display_name(code):match("^HOLD") then
        warning(plan,"Other holds currently play only the short command sample.")
    end
end

function M.tempo(entry)
    if entry.flag and #entry.flag >= 2 then
        local value = format.u16(entry.flag, 0)
        if value >= 30 and value <= 400 then return value, "chart" end
    end
    return 120, "fallback"
end

function M.plan(entry, bpm, first_tick, last_tick, stem, voice_context)
    assert(entry and #entry.steps > 0, "Choose a phrase before playing")
    local automatic, source = M.tempo(entry)
    local tempo_source = bpm ~= nil and "manual" or source
    bpm = bpm or automatic
    assert(bpm >= 30 and bpm <= 400, "Preview tempo must be between 30 and 400 BPM")
    local total = format.total_ticks(entry.timing)
    first_tick, last_tick = first_tick or 0, last_tick or total
    assert(first_tick >= 0 and last_tick <= total and first_tick < last_tick, "Invalid playback range")
    local seconds_per_tick = 60 / (bpm * format.CHART_TICKS_PER_BEAT)
    local plan = {events = {}, prior_events = {}, bpm = bpm, first_tick = first_tick, last_tick = last_tick,
        duration = (last_tick - first_tick) * seconds_per_tick,
        seconds_per_tick = seconds_per_tick, tempo_source = tempo_source,
        alignment_verified = false, tempo_verified = false, warnings = {}}
    local tick = entry.start_delay or 0
    for index, code in ipairs(entry.steps) do
        assert(tick <= total, "A command falls after the end of the phrase")
        local command = game_audio.command_for_code(code, stem, voice_context, tick)
        if stem=='r01' and command and not command:match('^DANCE_') then
            warning(plan,"Some Dance calls use provisional standard English samples; their bank context is unavailable.")
        end
        if command and tick < last_tick then
            local event={index = index, code = code, command = command, tick = tick,
                seconds = (tick - first_tick) * seconds_per_tick}
            if tick < first_tick then
                -- Duration depends on the decoded voice. Keep candidates out
                -- of the range's note list and clip only audible tails later.
                plan.prior_events[#plan.prior_events+1]=event
            else
                plan.events[#plan.events+1]=event
                hold_warning(plan,code,command)
            end
        end
        if index < #entry.steps then tick = tick + (entry.hits[index] or 0) end
    end
    if stem=='r01' then warning(plan,"Ulala's Dance bank selection follows checked scripts; audible sync is unverified.") end
    if (stem=='r61' or stem=='r62') and voice_context then
        warning(plan,"Report 6 original calls use recorded English banks where observed. Three gap notes and edited commands use provisional short previews; audible sync is unverified.")
    end
    return plan
end

local function values(sample)
    if sample.values then return sample.values end
    local out = {}
    for i = 1, #sample.pcm, 2 do
        local a, b = sample.pcm:byte(i, i + 1)
        local value = a + b * 256
        if value >= 32768 then value = value - 65536 end
        out[#out + 1] = value
    end
    sample.values = out
    return out
end

-- Keep range playback on the full phrase's sample grid. Rounding a range's
-- relative start and duration separately can otherwise shift it by one frame.
function M.sample_window(plan, rate)
    if plan.first_tick and plan.last_tick and plan.seconds_per_tick then
        local first = math.floor(plan.first_tick*plan.seconds_per_tick*rate+0.5)
        local last = math.floor(plan.last_tick*plan.seconds_per_tick*rate+0.5)
        return first, math.max(1,last-first)
    end
    return 0, math.max(1,math.floor(plan.duration*rate+0.5))
end

function M.render(plan, bank, music)
    plan.warnings=plan.warnings or {}
    local rate = music and music.info.rate or 44100
    local channels = music and music.info.channels or (bank.channels or 1)
    assert(channels == 1 or channels == 2, "Unsupported music channel count")
    local first_frame, count = M.sample_window(plan,rate)
    assert(count <= rate * 120, "Preview a range shorter than two minutes")
    local mixed = {}
    if music then
        assert(music.info.count == count, "Music window and phrase length differ")
        local background = values(music)
        for i = 1, count*channels do mixed[i] = (background[i] or 0)*(music.gain or 0.5) end
        plan.music = {name=music.name,phase=music.phase,offset_seconds=music.offset_seconds,
            alignment_verified=music.alignment_verified,timing_checked=music.timing_checked,
            timing_tolerance_seconds=music.timing_tolerance_seconds}
    else
        for i = 1, count*channels do mixed[i] = 0 end
        plan.music = nil
    end
    plan.continuations={}
    local function mix(event,prior)
        local sample=bank.samples[event.command]
        if not sample and prior then
            warning(plan,"A preceding unidentified command's audio tail is unavailable.")
            if plan.music then plan.music.timing_checked=false;plan.music.timing_tolerance_seconds=nil end
            return
        end
        assert(sample, "No English sample for command " .. event.command)
        assert(sample.info.channels == 1 or sample.info.channels == 2, "Command sample format is unsupported")
        assert(channels == 2 or sample.info.channels == 1, "Stereo command requires stereo output")
        local offset = event.tick and math.floor(event.tick*plan.seconds_per_tick*rate+0.5)-first_frame
            or math.floor(event.seconds * rate + 0.5)
        local source = values(sample)
        local frames = math.ceil((sample.info.count or #source/sample.info.channels)*rate/sample.info.rate)
        local first,last=math.max(0,-offset),math.min(frames,count-offset)
        if first>=last then return end
        if prior then
            event.sample_offset=offset
            plan.continuations[#plan.continuations+1]=event
            hold_warning(plan,event.code,event.command)
        end
        if plan.music and plan.music.timing_checked
            and not require('core.audio_timing').voice(bank.stem,event.command,sample) then
            plan.music.timing_checked=false;plan.music.timing_tolerance_seconds=nil
        end
        for j = first,last-1 do
            local position = j*sample.info.rate/rate
            local index = math.floor(position)+1
            local fraction = position-math.floor(position)
            for ch = 1, channels do
                local source_ch=sample.info.channels==1 and 1 or ch
                local first_index=(index-1)*sample.info.channels+source_ch
                local first = source[first_index] or 0
                local value = first+((source[first_index+sample.info.channels] or 0)-first)*fraction
                local target = (offset+j)*channels+ch
                mixed[target] = mixed[target]+value
            end
        end
        event.sample_offset = offset
    end
    for _,event in ipairs(plan.prior_events or {}) do mix(event,true) end
    for _,event in ipairs(plan.events) do mix(event,false) end
    local chunks = {}
    for i = 1, count*channels, 256 do
        local bytes = {}
        for j = i, math.min(i + 255, count*channels) do
            local value = math.max(-32768, math.min(32767, math.floor(mixed[j]+0.5))) % 65536
            bytes[#bytes + 1] = string.char(value % 256, math.floor(value / 256))
        end
        chunks[#chunks + 1] = table.concat(bytes)
    end
    local pcm = table.concat(chunks)
    local info = {rate = rate, channels = channels, count = count, duration = count / rate}
    return adx.wav(pcm, info), info
end

function M.signature(entry, bpm)
    local key = {tostring(bpm or M.tempo(entry)), tostring(entry.timing), tostring(entry.start_delay or 0)}
    for i, code in ipairs(entry.steps) do
        key[#key + 1] = tostring(code) .. ":" .. tostring(entry.hits[i] or 0)
    end
    return table.concat(key, ",")
end

function M.new()
    return {position = 0, looping = false, banks = {}, music_cache = {}, music_enabled = true,
        playing = false, source = nil, plan = nil, mode = nil, report_job = nil, report_cache = nil}
end

function M.stop(state, clear)
    if state.report_job then state.report_job:cancel();state.report_job=nil end
    if state.source then
        state.source:stop()
        if clear then if state.source.release then state.source:release() end;state.source=nil end
    end
    if state.audition then state.audition:stop() end
    state.playing, state.position = false, 0
    if clear then
        state.plan,state.signature,state.mode,state.report_tick=nil,nil,nil,nil
        if state.report_cache then state.report_cache:dispose();state.report_cache=nil end
    end
end

function M.update(state)
    if not state.source then return end
    if state.playing then
        state.position = state.source:tell("seconds")
        if not state.source:isPlaying() then
            state.playing = false
            state.position = state.plan and state.plan.duration or 0
        end
    end
end

function M.tick(state)
    if state.mode=="report" then return state.report_tick end
    if not state.plan then return nil end
    if state.plan.question_duration then
        if state.position<state.plan.question_duration then return nil end
        return (state.position-state.plan.question_duration)/state.plan.seconds_per_tick
    end
    return state.plan.first_tick + state.position / state.plan.seconds_per_tick
end

return M
