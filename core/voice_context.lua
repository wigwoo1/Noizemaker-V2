-- Bank state for one source-checked CPU route. Other branches stay provisional.
local facts=require('core.voice_report3_data')
local route=require('core.route')
local format=require('core.format')
local M={}
function M.resolve(entry,path,buffer,stem)
    if stem=='r01' then return require('core.dance_voice').resolve(entry,path,buffer) end
    if stem=='r61' or stem=='r62' then
        local data=require('core.voice_report6_route_data')
        local source=route.source(path,buffer)
        local phrase=source and data.phrases[source] and entry and data.phrases[source][entry.name]
        if not phrase or entry.timing~=phrase.timing or not entry.flag
            or format.u16(entry.flag,0)~=phrase.bpm then return nil end
        return {stem=stem,bindings=phrase.bindings}
    end
    if stem=='r43' or stem=='r42' then
        local data=require(stem=='r42' and 'core.voice_report42_data' or 'core.voice_report4_data')
        local normalized=tostring(path or ''):gsub('\\','/'):lower()
        local relative=normalized:match('(afs_english/'..stem..'_sh2?%.bin)$')
        local source=relative and data.sources[relative]
        local phrase=source and entry and source.phrases[entry.name]
        if not phrase or not buffer or entry.timing~=phrase.timing or not entry.flag
            or format.u16(entry.flag,0)~=phrase.bpm then return nil end
        local digest=love.data.hash('sha256',buffer):gsub('.',function(c)return string.format('%02x',c:byte())end)
        if digest==source.sha256 then return {stem=stem} end
        return nil
    end
    if stem~='r31' or not entry or route.source(path,buffer)~=facts.source then return nil end
    local phrase=facts.phrases[entry.name]
    if not phrase or entry.timing~=phrase.timing or not entry.flag
        or format.u16(entry.flag,0)~=phrase.bpm then return nil end
    return {stem=stem,response_beat=phrase.response_beat}
end
function M.command(code,context,tick)
    if context and context.stem=='r01' then return require('core.dance_voice').command(code,context) end
    if context and (context.stem=='r61' or context.stem=='r62') then
        local binding=context.bindings and context.bindings[tick]
        return binding and binding.code==code and binding.sample or nil
    end
    if context and context.stem=='r42' then return require('core.voice_report42_data').bindings[tostring(code)] end
    if context and context.stem=='r43' and (code==9 or code==10) then
        return code==9 and 'R43_HOLD_CHU' or 'R43_HOLD_HEY'
    end
    if not context or context.stem~='r31' or (code~=9 and code~=10) then return nil end
    local beat=context.response_beat+(tick or 0)/format.CHART_TICKS_PER_BEAT
    local variant=facts.initial_variant
    for _,change in ipairs(facts.changes) do
        if change.beat<=beat then variant=change.variant else break end
    end
    return 'R31_HOLD_'..(code==9 and 'CHU' or 'HEY')..'_'..variant
end
return M
