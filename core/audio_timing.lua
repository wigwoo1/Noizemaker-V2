-- Evidence is limited to recorded response positions, never the whole ending
-- or every game branch. Changed charts/assets cannot inherit its checked label.
local data=require('core.audio_timing_data')
local format=require('core.format')
local M={tolerance_seconds=data.tolerance_seconds}

function M.hash(bytes)
    if not (bytes and love and love.data and love.data.hash) then return nil end
    return (love.data.hash('sha256',bytes):gsub('.',function(c)return string.format('%02x',c:byte())end))
end

function M.phrase(stem,entry,buffer)
    local source=data.sources[stem]
    local fact=data.phrases[stem] and entry and data.phrases[stem][entry.name]
    if not source or not fact or M.hash(buffer)~=source.sha256 then return nil end
    if entry.timing~=fact.timing or not entry.flag or #entry.flag<2
        or format.u16(entry.flag,0)~=fact.bpm then return nil end
    return fact
end

function M.binding(stem,entry,buffer,binding,asset_hash)
    local fact=M.phrase(stem,entry,buffer)
    if not fact or not binding or binding.index~=fact.cue
        or math.abs(binding.offset_seconds-fact.offset)>0.5/48000 then return false end
    return data.music[stem][binding.index].sha256==asset_hash
end

function M.part(stem,part)
    if not data.music[stem] then return false end
    local ending=0
    for _,phrase in pairs(data.phrases[stem]) do
        ending=math.max(ending,data.music[stem][phrase.cue].seconds+phrase.offset+phrase.timing*30/phrase.bpm)
    end
    if part.duration+1/48000<ending then return false end
    local seen={}
    for _,cue in ipairs(part.cues) do
        local fact=data.music[stem][cue.index]
        if fact then
            if seen[cue.index] or cue.sha256~=fact.sha256 or math.abs(cue.seconds-fact.seconds)>0.5/48000 then return false end
            seen[cue.index]=true
        elseif cue.seconds<ending-1/48000 then return false end
    end
    for index in pairs(data.music[stem]) do if not seen[index] then return false end end
    return true
end

function M.voice(stem,command,sample)
    local fact=data.voices[stem] and data.voices[stem][command]
    return fact~=nil and sample~=nil and sample.name==fact.name and M.hash(sample.pcm)==fact.pcm_sha256
end

return M
