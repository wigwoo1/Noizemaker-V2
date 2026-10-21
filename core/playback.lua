local format = require("core.format")
local game_audio = require("core.game_audio")
local adx = require("core.adx")
local M = {}

function M.tempo(entry)
    if entry.flag and #entry.flag >= 2 then
        local value = format.u16(entry.flag, 0)
        if value >= 30 and value <= 400 then return value, "chart" end
    end
    return 120, "fallback"
end

function M.plan(entry, bpm, first_tick, last_tick)
    assert(entry and #entry.steps > 0, "Choose a phrase before playing")
    local automatic, source = M.tempo(entry)
    local tempo_source = bpm ~= nil and "manual" or source
    bpm = bpm or automatic
    assert(bpm >= 30 and bpm <= 400, "Preview tempo must be between 30 and 400 BPM")
    local total = format.total_ticks(entry.timing)
    first_tick, last_tick = first_tick or 0, last_tick or total
    assert(first_tick >= 0 and last_tick <= total and first_tick < last_tick, "Invalid playback range")
    local seconds_per_tick = 60 / (bpm * format.CHART_TICKS_PER_BEAT)
    local plan = {events = {}, bpm = bpm, first_tick = first_tick, last_tick = last_tick,
        duration = (last_tick - first_tick) * seconds_per_tick,
        seconds_per_tick = seconds_per_tick, tempo_source = tempo_source,
        alignment_verified = false, tempo_verified = false, warnings = {}}
    local tick = entry.start_delay or 0
    for index, code in ipairs(entry.steps) do
        assert(tick <= total, "A command falls after the end of the phrase")
        local command = game_audio.command_for_code(code)
        if command and tick >= first_tick and tick < last_tick then
            plan.events[#plan.events + 1] = {index = index, code = code, command = command, tick = tick,
                seconds = (tick - first_tick) * seconds_per_tick}
            if format.step_display_name(code):match("^HOLD") then
                plan.warnings[1] = "Hold preview currently plays the command attack only."
            end
        end
        if index < #entry.steps then tick = tick + (entry.hits[index] or 0) end
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
    local rate = music and music.info.rate or 44100
    local channels = music and music.info.channels or 1
    assert(channels == 1 or channels == 2, "Unsupported music channel count")
    local first_frame, count = M.sample_window(plan,rate)
    assert(count <= rate * 120, "Preview a range shorter than two minutes")
    local mixed = {}
    if music then
        assert(music.info.count == count, "Music window and phrase length differ")
        local background = values(music)
        for i = 1, count*channels do mixed[i] = (background[i] or 0)*(music.gain or 0.5) end
        plan.music = {name=music.name,phase=music.phase,offset_seconds=music.offset_seconds,
            alignment_verified=music.alignment_verified}
    else
        for i = 1, count do mixed[i] = 0 end
        plan.music = nil
    end
    for _, event in ipairs(plan.events) do
        local sample = assert(bank.samples[event.command], "No English sample for command " .. event.command)
        assert(sample.info.channels == 1, "Command sample format is unsupported")
        local offset = event.tick and math.floor(event.tick*plan.seconds_per_tick*rate+0.5)-first_frame
            or math.floor(event.seconds * rate + 0.5)
        local source = values(sample)
        local frames = math.ceil(#source*rate/sample.info.rate)
        for j = 0, math.min(frames, count - offset)-1 do
            local position = j*sample.info.rate/rate
            local index = math.floor(position)+1
            local fraction = position-math.floor(position)
            local first = source[index] or 0
            local value = first+((source[index+1] or 0)-first)*fraction
            for ch = 1, channels do
                local target = (offset+j)*channels+ch
                mixed[target] = mixed[target]+value
            end
        end
        event.sample_offset = offset
    end
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
        playing = false, source = nil, plan = nil}
end

function M.stop(state, clear)
    if state.source then state.source:stop() end
    if state.audition then state.audition:stop() end
    state.playing, state.position = false, 0
    if clear then state.source, state.plan, state.signature = nil, nil, nil end
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
    if not state.plan then return nil end
    return state.plan.first_tick + state.position / state.plan.seconds_per_tick
end

return M
