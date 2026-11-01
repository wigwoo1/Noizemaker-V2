local adx = require("core.adx")
local format = require("core.format")
local M = {}

local function u32(s, at)
    local a, b, c, d = s:byte(at + 1, at + 4)
    assert(d, "Truncated sound resource table")
    return a + b * 256 + c * 65536 + d * 16777216
end

function M.parse_resource(data)
    assert(type(data) == "string" and #data >= 16, "Missing sound resource header")
    local count = u32(data, 0)
    assert(count > 0 and count < 10000 and 16 + count * 128 <= #data, "Invalid sound resource count")
    local entries, by_name = {}, {}
    for i = 0, count - 1 do
        local at = 16 + i * 128
        local name = data:sub(at + 1, at + 120):match("^[^%z]+")
        local size, offset = u32(data, at + 120), u32(data, at + 124)
        assert(name and offset >= 16 + count * 128 and offset + size <= #data, "Invalid sound resource member")
        name = name:gsub("\\", "/"):lower()
        assert(not by_name[name], "Duplicate sound resource name: " .. name)
        local entry = {name = name, size = size, offset = offset}
        entries[#entries + 1], by_name[name] = entry, entry
    end
    return {buffer = data, entries = entries, by_name = by_name}
end

function M.read(path)
    local f = assert(io.open(path, "rb"), "Could not read audio file: " .. path)
    local data = f:read("*a")
    f:close()
    return data
end

-- Command banks are organized per report section in the English resources.
-- These names come from the installed resource tables; the filenames within
-- each bank explicitly name the six standard calls. Keep selection local to
-- the requested section so one report does not silently borrow another's voice.
local COMMAND_BANKS = {
    r01 = 'bank00_nomal',
    r11 = "bank00_ulala1",
    r12 = "bank00u1",
    ["r21"] = "bank00u1  normal",
    ["r22"] = "bank00_ulala1",
    ["r23"] = "bank00_ulala1",
    ["r31"] = "bank00_u1",
    ["r41"] = "bank00_ulala1",
    ["r42"] = "bank00_ulala1",
    ["r43"] = "bank00u1  normal",
    ["r44"] = "bank00",
    ["r51"] = "bank00_ulala1",
    ["r52"] = "bank00u1",
    ["r61"] = "bank00_ulala_r61",
    ["r62"] = "bank00",
}

local COMMAND_FILES = {
    UP = {"00up.adx", "0uk_u.adx"},
    RIGHT = {"01right.adx", "1uk_r.adx"},
    LEFT = {"02left.adx", "2uk_l.adx"},
    DOWN = {"03down.adx", "3uk_d.adx"},
    CHU = {"04shoot.adx", "04chu.adx", "4uk_s.adx"},
    HEY = {"05hey.adx", "5uk_h.adx"},
}

function M.command_bank(root, stem, progress)
    stem = stem or "r11"
    assert(stem:match("^r%d%d$"), "Invalid report section for audio")
    local resource_stem=stem=='r01' and 'r0' or stem
    local voice_stem=stem=='r01' and 'r00' or stem
    local path = root:gsub("\\", "/"):gsub("/+$", "") .. "/sound_resource_bin/" .. resource_stem .. "_sound_resource.bin"
    -- The *_jp resource is never an automatic fallback for English preview.
    local resource_data=M.read(path)
    local recorded_native=(stem:match('^r4[1-4]$') and require('core.voice_report4_route_data'))
        or (stem:match('^r5[1-2]$') and require('core.voice_report5_route_data'))
        or (stem:match('^r6[1-2]$') and require('core.voice_report6_route_data')) or nil
    if recorded_native then
        local digest=love.data.hash('sha256',resource_data):gsub('.',function(c)return string.format('%02x',c:byte())end)
        assert(digest==recorded_native.resources[stem],'Recorded English sound resource changed: '..stem)
    end
    local resource = M.parse_resource(resource_data)
    local bank_name = COMMAND_BANKS[stem] or "bank00_ulala1"
    local bank = {path = path, stem = stem, language = "English", bank_name = bank_name,
        samples = {}, missing = {}}
    local shared
    for command, filenames in pairs(COMMAND_FILES) do
        local entry, name
        for _, filename in ipairs(filenames) do
            name = "se/" .. voice_stem .. "/" .. bank_name .. "/" .. filename
            entry = resource.by_name[name]
            if entry then break end
        end
        if entry then
            local encoded = resource.buffer:sub(entry.offset + 1, entry.offset + entry.size)
            local pcm, info = adx.decode(encoded, nil, progress)
            bank.samples[command] = {pcm = pcm, info = info, wav = adx.wav(pcm, info), name = name}
        else
            if stem ~= "r11" then
                shared = shared or M.command_bank(root, "r11", progress)
                bank.samples[command] = shared.samples[command]
                bank.shared_source = shared.path
            else
                bank.missing[#bank.missing + 1] = command
            end
        end
    end
    assert(#bank.missing == 0, "English command bank is incomplete for " .. stem .. ": " .. table.concat(bank.missing, ", "))
    if stem == "r11" then
        -- CPU response dispatch: table slot 25 -> sound 0x2204 -> bank 2,
        -- member 4. Three recorded held calls independently match this take.
        -- The ======== alternate is not the sample selected by that table.
        local name = "se/r11/bank02_r11/04shoottame.adx"
        local entry = assert(resource.by_name[name], "Missing English Report 1 held Chu")
        local encoded = resource.buffer:sub(entry.offset + 1, entry.offset + entry.size)
        local pcm, info = adx.decode(encoded, nil, progress)
        bank.samples.HOLDCHU = {pcm = pcm, info = info, wav = adx.wav(pcm, info), name = name}
    end
    if stem == 'r31' or stem=='r01' or stem=='r43' or stem=='r42' then
        local facts=require(({r01='core.dance_voice_data',r31='core.voice_report3_data',r43='core.voice_report4_data',r42='core.voice_report42_data'})[stem])
        for key,fact in pairs(facts.samples) do
            local entry=assert(resource.by_name[fact.name],'Missing checked command call: '..fact.name)
            local encoded=resource.buffer:sub(entry.offset+1,entry.offset+entry.size)
            local digest=love.data.hash('sha256',encoded):gsub('.',function(c)return string.format('%02x',c:byte())end)
            assert(digest==fact.sha256,'Command-call asset differs from the checked source: '..fact.name)
            local pcm,info=adx.decode(encoded,nil,progress)
            bank.samples[key]={pcm=pcm,info=info,wav=adx.wav(pcm,info),name=fact.name}
        end
    end
    if recorded_native then
        for key,fact in pairs(recorded_native.samples) do
            if fact.stem==stem then
                local entry=assert(resource.by_name[fact.name],'Missing recorded English call: '..fact.name)
                local encoded=resource.buffer:sub(entry.offset+1,entry.offset+entry.size)
                local digest=love.data.hash('sha256',encoded):gsub('.',function(c)return string.format('%02x',c:byte())end)
                assert(digest==fact.sha256,'Recorded English call changed: '..fact.name)
                local pcm,info=adx.decode(encoded,nil,progress)
                bank.samples[key]={pcm=pcm,info=info,wav=adx.wav(pcm,info),name=fact.name}
            end
        end
    end
    return bank
end

function M.command_for_code(code, stem, context, tick)
    if stem=='r31' or stem=='r01' or stem=='r43' or stem=='r42' or stem=='r61' or stem=='r62' then
        local contextual=require('core.voice_context').command(code,context,tick)
        if contextual then return contextual end
    end
    -- Audio aliases only; preserve the flagged bytes and their chart display.
    -- These exact R11 events were checked against native CPU dispatch and
    -- the continuous stock recording. Do not infer voices for arbitrary flags.
    if stem == "r11" then
        if code == 0x21 or code == 0x41 then return "CHU" end
        if code == 9 then return "HOLDCHU" end
    end
    local command = format.step_display_name(code)
    if command == "REST" then return nil end
    return command:gsub("^HOLD", ""):gsub("^Special ", "")
end

return M
