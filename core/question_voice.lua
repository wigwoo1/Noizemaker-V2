-- The recorded Report 1 enemy-question half uses separate English banks.
-- Bank choices are supported by representative stock-recording matches, but
-- precise synchronization and every branch/held take are not established.
local adx=require('core.adx')
local format=require('core.format')
local audio=require('core.game_audio')
local route=require('core.route')
local facts=require('core.question_voice_report1_data')
local M={}

local function hash(data)
    return love.data.hash('sha256',data):gsub('.',function(c)return string.format('%02x',c:byte())end)
end

function M.command(code)
    if code==0x21 or code==0x41 then return 'CHU' end
    local name=format.step_display_name(code)
    if name=='REST' then return nil end
    name=name:gsub('^HOLD',''):gsub('^Special ','')
    return (name=='UP' or name=='RIGHT' or name=='LEFT' or name=='DOWN'
        or name=='CHU' or name=='HEY') and name or nil
end

function M.event(original,preview,path,buffer,stem,plan)
    if not original or not preview or not plan or not facts.resources[stem]
        or plan.first_tick~=0 or plan.last_tick~=format.total_ticks(preview.timing)
        or preview.timing~=original.timing then return nil end
    local source=route.source(path,buffer)
    if source~='afs_english/'..stem..'_sh.bin' then return nil end
    local event=route.event(source,original.name)
    local bpm=original.flag and format.u16(original.flag,0)
    if not event or event.bpm~=bpm or original.timing~=event.length_beats then return nil end
    return event
end

function M.bank(root,stem)
    assert(facts.resources[stem],'No checked enemy bank for this section')
    local path=root:gsub('\\','/'):gsub('/+$','')..'/sound_resource_bin/'..stem..'_sound_resource.bin'
    local raw=audio.read(path)
    assert(hash(raw)==facts.resources[stem],'English enemy resource changed: '..stem)
    local resource=audio.parse_resource(raw)
    local bank={stem=stem,samples={},channels=1}
    for command,fact in pairs(facts.samples[stem]) do
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

function M.extend(plan,question_bank,response_bank)
    assert(plan and plan.first_tick==0 and plan.last_tick and plan.seconds_per_tick)
    local question_duration=plan.duration
    local question={}
    for _,response in ipairs(plan.events) do
        local name=M.command(response.code)
        if not name or not question_bank.samples[name] or not response_bank.samples[response.command] then
            return nil,'A command in this phrase has no matching English question or response sample.'
        end
        question[#question+1]={index=response.index,code=response.code,
            command='QUESTION_'..name,seconds=response.seconds}
    end
    local combined={stem=response_bank.stem,channels=question_bank.channels,
        samples=setmetatable({},{__index=response_bank.samples})}
    for name,sample in pairs(question_bank.samples) do combined.samples['QUESTION_'..name]=sample end
    for _,response in ipairs(plan.events) do
        response.seconds=response.seconds+question_duration
        response.tick=nil -- the full preview uses seconds from the question start
    end
    for _,event in ipairs(question) do plan.events[#plan.events+1]=event end
    table.sort(plan.events,function(a,b)return a.seconds<b.seconds end)
    plan.first_tick=nil
    plan.last_tick=nil
    plan.duration=question_duration*2
    plan.question_duration=question_duration
    plan.warnings[#plan.warnings+1]='Enemy bank is a recorded-route candidate; exact audible sync and held-call behavior remain unverified.'
    return combined
end

return M
