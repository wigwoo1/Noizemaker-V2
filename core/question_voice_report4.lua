-- Recorded Report 4 enemy voices for sections with identifiable English banks.
local adx=require('core.adx')
local audio=require('core.game_audio')
local format=require('core.format')
local route=require('core.route')
local shared=require('core.question_voice')
local facts=require('core.question_voice_report4_data')
local M={}

local function hash(data)
    return love.data.hash('sha256',data):gsub('.',function(c)return string.format('%02x',c:byte())end)
end

function M.event(original,preview,path,buffer,stem,plan)
    if not original or not preview or not plan or not facts.resources[stem]
        or plan.first_tick~=0 or plan.last_tick~=format.total_ticks(preview.timing)
        or preview.timing~=original.timing then return nil end
    local source=route.source(path,buffer)
    if source~='afs_english/'..stem..'_sh.bin' then return nil end
    local event=route.event(source,original.name)
    local bpm=original.flag and format.u16(original.flag,0)
    if not event or event.bpm~=bpm or original.timing~=event.length_beats
        or not facts.groups[event.group_key] then return nil end
    return event
end

function M.bank_key(event)
    return assert(facts.groups[event.group_key],'No Report 4 enemy bank for recorded section')
end

function M.bank(root,stem,event)
    local selected=M.bank_key(event)
    local path=root:gsub('\\','/'):gsub('/+$','')..'/sound_resource_bin/'..stem..'_sound_resource.bin'
    local raw=audio.read(path)
    assert(hash(raw)==facts.resources[stem],'English enemy resource changed: '..stem)
    local resource=audio.parse_resource(raw)
    local bank={stem=stem,samples={},channels=1,bank_name=selected}
    for command,fact in pairs(facts.samples[stem][selected]) do
        local member=assert(resource.by_name[fact.name],'Missing English enemy command: '..fact.name)
        local encoded=raw:sub(member.offset+1,member.offset+member.size)
        assert(hash(encoded)==fact.sha256,'English enemy command changed: '..fact.name)
        local pcm,info=adx.decode(encoded)
        assert(info.channels==1 or info.channels==2,'Unsupported English enemy voice format: '..fact.name)
        bank.channels=math.max(bank.channels,info.channels)
        bank.samples[command]={pcm=pcm,info=info,name=fact.name}
    end
    return bank
end

function M.extend(plan,question_bank,response_bank,event)
    local skipped=0
    for i=#plan.events,1,-1 do
        local response=plan.events[i]
        local name=shared.command(response.code)
        if (response.code==0x21 or response.code==0x41) and response_bank.samples.CHU then
            response.command='CHU'
        end
        if not name or not question_bank.samples[name]
            or not response_bank.samples[response.command] then
            table.remove(plan.events,i)
            skipped=skipped+1
        end
    end
    if #plan.events==0 then return nil,'No mapped English enemy calls in this Report 4 phrase.' end
    local combined,reason=shared.extend(plan,question_bank,response_bank)
    if not combined then return nil,reason end
    plan.question_unmapped_count=skipped
    if skipped>0 then
        plan.warnings[#plan.warnings+1]=tostring(skipped)..' unmapped raw call(s) are silent in both halves.'
    end
    plan.question_bank_provisional=true
    plan.warnings[#plan.warnings+1]='Report 4 enemy-bank choice and audible timing are provisional.'
    return combined
end

return M
