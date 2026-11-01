-- Resolve only samples common to every conservatively reachable bank state.
local facts=require('core.dance_voice_data')
local format=require('core.format')
local M={}
function M.resolve(entry,path,buffer)
    path=tostring(path or ''):gsub('\\','/'):lower()
    if not (path=='r01_sh.bin' or path:match('/r01_sh%.bin$'))
        or path:match('afs_english/r01_sh%.bin$') or not entry or not buffer then return nil end
    local fields=facts.phrase_fields[entry.name]
    if not fields or entry.timing~=fields.timing or not entry.flag
        or format.u16(entry.flag,0)~=fields.bpm then return nil end
    local digest=love.data.hash('sha256',buffer):gsub('.',function(c)return string.format('%02x',c:byte())end)
    if digest~=facts.sha256 or not facts.contexts[entry.name] then return nil end
    return {stem='r01',states=facts.contexts[entry.name]}
end
function M.command(code,context)
    if not context or context.stem~='r01' then return nil end
    local binding=facts.bindings[tostring(code)]
    if not binding then return nil end
    local selected
    for _,state in ipairs(context.states) do
        local key='DANCE_V'..state[binding.bank+1]..'_M'..binding.member
        if not facts.samples[key] or (selected and selected~=key) then return nil end
        selected=key
    end
    return selected
end
return M
