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

function M.command_bank(root, stem)
    stem = stem or "r11"
    assert(stem:match("^r%d%d$"), "Invalid report section for audio")
    local path = root:gsub("\\", "/"):gsub("/+$", "") .. "/sound_resource_bin/" .. stem .. "_sound_resource.bin"
    -- The *_jp resource is never an automatic fallback for English preview.
    local resource = M.parse_resource(M.read(path))
    local bank = {path = path, stem = stem, language = "English", samples = {}, missing = {}}
    local shared
    local files = {UP = "00up.adx", RIGHT = "01right.adx", LEFT = "02left.adx", DOWN = "03down.adx", CHU = "04shoot.adx", HEY = "05hey.adx"}
    for command, filename in pairs(files) do
        local name = "se/" .. stem .. "/bank00_ulala1/" .. filename
        local entry = resource.by_name[name]
        if entry then
            local encoded = resource.buffer:sub(entry.offset + 1, entry.offset + entry.size)
            local pcm, info = adx.decode(encoded)
            bank.samples[command] = {pcm = pcm, info = info, wav = adx.wav(pcm, info), name = name}
        else
            if stem ~= "r11" then
                shared = shared or M.command_bank(root, "r11")
                bank.samples[command] = shared.samples[command]
                bank.shared_source = shared.path
            else
                bank.missing[#bank.missing + 1] = command
            end
        end
    end
    assert(#bank.missing == 0, "English command bank is incomplete for " .. stem .. ": " .. table.concat(bank.missing, ", "))
    return bank
end

function M.command_for_code(code)
    local command = format.step_display_name(code)
    if command == "REST" then return nil end
    return command:gsub("^HOLD", ""):gsub("^Special ", "")
end

return M
