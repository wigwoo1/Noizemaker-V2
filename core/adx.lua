-- Standard, unencrypted CRI ADX (encoding 3, 18-byte blocks, 4-bit residuals).
-- Mathematical format reference: FFmpeg libavcodec/adx.c and adxdec.c.
-- Decodes to interleaved signed 16-bit PCM without an external executable.
local M = {}
local function be16(s, p)
    local a, b = s:byte(p + 1, p + 2)
    assert(b, "Truncated ADX header or block")
    return a * 256 + b
end
local function be32(s, p)
    return be16(s, p) * 65536 + be16(s, p + 2)
end
local function le16(n)
    n = n % 65536
    return string.char(n % 256, math.floor(n / 256))
end
local function le32(n)
    return le16(n % 65536) .. le16(math.floor(n / 65536))
end

function M.header(data)
    assert(type(data) == "string" and #data >= 24, "ADX header is missing")
    assert(be16(data, 0) == 0x8000, "Not an ADX sample")
    local offset = be16(data, 2) + 4
    assert(offset >= 24 and offset <= #data, "Invalid ADX audio offset")
    assert(data:sub(offset - 5, offset) == "(c)CRI", "ADX marker is missing")
    assert(data:byte(5) == 3 and data:byte(6) == 18 and data:byte(7) == 4,
        "Unsupported ADX encoding; expected standard 4-bit blocks")
    local channels, rate, count = data:byte(8), be32(data, 8), be32(data, 12)
    assert(channels == 1 or channels == 2, "Only mono and stereo ADX are supported")
    assert(rate >= 8000 and rate <= 192000 and count > 0, "Invalid ADX sample format")
    assert(data:byte(20) == 0, "Encrypted ADX samples are not supported")
    assert(offset + math.ceil(count / 32) * 18 * channels <= #data, "ADX audio data is truncated")
    return {offset = offset, channels = channels, rate = rate, count = count, cutoff = be16(data, 16), duration = count / rate}
end

function M.decode(data, limit)
    local h = M.header(data)
    local count = limit and math.min(h.count, limit) or h.count
    assert(count > 0 and count == math.floor(count), "Invalid ADX decode limit")
    local a = math.sqrt(2) - math.cos(2 * math.pi * h.cutoff / h.rate)
    local b = math.sqrt(2) - 1
    local c = (a - math.sqrt((a + b) * (a - b))) / b
    local k1, k2 = math.floor(c * 8192 + 0.5), math.floor(-c * c * 4096 + 0.5)
    local history = {{0, 0}, {0, 0}}
    local blocks = {}
    for base = 0, count - 1, 32 do
        local decoded = {}
        for ch = 1, h.channels do
            local p = h.offset + (math.floor(base / 32) * h.channels + ch - 1) * 18
            local scale = be16(data, p)
            assert(scale < 32768, "Unexpected ADX end marker")
            local values, prev = {}, history[ch]
            for j = 0, 31 do
                local byte = data:byte(p + 3 + math.floor(j / 2))
                local residual = (j % 2 == 0) and math.floor(byte / 16) or (byte % 16)
                if residual >= 8 then residual = residual - 16 end
                local sample = residual * scale + math.floor((k1 * prev[1] + k2 * prev[2]) / 4096)
                sample = math.max(-32768, math.min(32767, sample))
                prev[2], prev[1] = prev[1], sample
                values[j + 1] = sample
            end
            decoded[ch] = values
        end
        local bytes = {}
        for j = 1, math.min(32, count - base) do
            for ch = 1, h.channels do bytes[#bytes + 1] = le16(decoded[ch][j]) end
        end
        blocks[#blocks + 1] = table.concat(bytes)
    end
    local pcm = table.concat(blocks)
    return pcm, {rate = h.rate, channels = h.channels, count = count, duration = count / h.rate}
end

function M.wav(pcm, info)
    return "RIFF" .. le32(36 + #pcm) .. "WAVEfmt " .. le32(16) .. le16(1) .. le16(info.channels)
        .. le32(info.rate) .. le32(info.rate * info.channels * 2) .. le16(info.channels * 2) .. le16(16)
        .. "data" .. le32(#pcm) .. pcm
end

return M
