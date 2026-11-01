local score=require('core.score')
local report=require('core.report')
local playback=require('core.playback')
local adx=require('core.adx')
local format=require('core.format')
local level=report.load(TEST_GAME_ROOT,1)
local plan=score.plan(level)
assert(#plan.phrases==58 and #plan.clips==26 and #plan.events>100)
assert(math.abs(plan.duration-612.5542965763758)<1e-8)
assert(math.abs(plan.phrases[1].response-44)<1e-8)
assert(math.abs(plan.phrases[42].response-436.3899130147319)<1e-8)
assert(next(plan.unmapped_commands)==nil and #plan.unmapped_voice_events==0,
    'The recorded Report 1 route now has a verified sample for every response call')
assert(plan.response_timing_candidate and not plan.response_timing_checked,
    'Recorded response evidence is confirmed against the actual assets during rendering')
local seen={}
for _,event in ipairs(plan.events) do
    seen[event.code]=event.command
end
assert(seen[0x21]=='CHU' and seen[0x41]=='CHU' and seen[9]=='HOLDCHU',
    'Whole-report scheduling uses flagged Chu aliases and the long Chu sample')
local partial=score.plan(level,nil,true,true,true)
assert(partial.voices_enabled and partial.skip_unmapped_voices and #partial.omitted_voice_events==#plan.unmapped_voice_events,
    'Mapped-call playback omits only the unknown voice events')
for _,event in ipairs(partial.events) do
    assert(not event.command:match('^0x'), 'Unknown commands never receive a guessed voice sample')
end
for i,phrase in ipairs(plan.phrases) do
    local selected,tick=score.locate(plan,phrase.response+0.001)
    assert(selected==phrase and math.abs(tick-0.001/phrase.seconds_per_tick)<1e-7)
    local original=playback.plan(phrase.row.entry)
    for _,event in ipairs(plan.events) do
        if event.phrase==i then
            assert(math.abs(event.seconds-(phrase.response+original.events[event.index].seconds))<1e-7)
        end
    end
end
local _,before=score.locate(plan,43)
assert(before==nil,'No response playhead during the call or intro')
local _,after=score.locate(plan,plan.phrases[41].ending+0.5)
assert(after==nil,'No response playhead during a transition')
local edited=score.plan(level,function(_,entry)
    local copy={timing=entry.timing,flag=entry.flag,steps={},hits=entry.hits,start_delay=entry.start_delay}
    for i,c in ipairs(entry.steps) do copy.steps[i]=i==1 and 5 or c end
    return copy
end,false)
assert(#edited.clips==0 and edited.events[1].code==5 and edited.events[1].seconds==plan.events[1].seconds)
assert(not pcall(score.plan,level,function(_,e)return {timing=e.timing+1}end))
local report5=score.plan(report.load(TEST_GAME_ROOT,5))
assert(#report5.phrases==54 and #report5.clips==17,
    'Recorded Report 5 music is now mapped across its two sections')
local original_buffer=level.cpu_route[1].file.buffer
level.cpu_route[1].file.buffer=original_buffer..'changed'
assert(not pcall(score.plan,level),'Stale route annotations cannot bypass source verification')
level.cpu_route[1].file.buffer=original_buffer

local function le16(n)return string.char(n%256,math.floor(n/256)%256)end
local function be16(n)return string.char(math.floor(n/256)%256,n%256)end
local function be32(n)return be16(math.floor(n/65536))..be16(n%65536)end
local encoded=be16(0x8000)..be16(28)..string.char(3,18,4,2)..be32(48000)..be32(32)..be16(500)..string.char(4,0)
encoded=encoded..string.rep('\0',26-#encoded)..'(c)CRI'..(be16(32)..string.rep('\68',16)):rep(2)
local pcm,info=adx.decode(encoded)
local digest=(love.data.hash('sha256',encoded):gsub('.',function(c)return string.format('%02x',c:byte())end))
local mini={duration=128/48000,frames=128,rate=48000,events={{seconds=20/48000,command='UP',stem='r11',ending=1}},clips={}}
for _,f in ipairs({0,12}) do
    mini.clips[#mini.clips+1]={seconds=f/48000,index=0,stem='r11',ending=1,sha256=digest,count=32,rate=48000}
end
local options={read_member=function()return encoded end,command_bank=function()
    return {samples={UP={pcm=le16(1000):rep(16),info={channels=1,count=16,rate=24000}}}}
end}
local path=TEST_SCRATCH..'/score-small.wav'
local unknown_plan=score.plan(level,function(_,entry)
    return {timing=entry.timing,flag=entry.flag,steps={255},hits={},start_delay=0}
end)
assert(unknown_plan.unmapped_commands[255] and #unknown_plan.unmapped_voice_events==58,
    'Unverified events remain blocked instead of receiving an inferred voice')
local blocked=score.new_job(unknown_plan,TEST_GAME_ROOT,path)
blocked:step(0)
assert(blocked.status=='error' and blocked.message:match('0xFF') and not blocked.owned,
    'Unmapped full-report voice is rejected before writing or decoding')
local unknown_path=TEST_SCRATCH..'/score-unknown.wav'
local explicit_skip={rate=48000,frames=128,duration=128/48000,clips={},events={},
    unmapped_commands={[0x41]=true},skip_unmapped_voices=true,omitted_voice_events={{code=0x41}}}
local skipped=score.new_job(explicit_skip,TEST_GAME_ROOT,unknown_path)
skipped:step(0)
while skipped.status=='running' do skipped:step(0) end
assert(skipped.status=='done','An explicit skip choice can render with no guessed unknown call')
skipped:dispose()
local job=score.new_job(mini,TEST_GAME_ROOT,path,options)
job:step(0)
assert(job.status=='running' and job.progress==0,'ADX compilation yields before completion')
while job.status=='running' do job:step(0) end
assert(job.status=='done',job.message)
local f=assert(io.open(path,'rb'));local wav=f:read('*a');f:close()
assert(#wav==44+128*4 and format.u32(wav,40)==128*4)
local function signed(data,frame,ch)
    local v=format.u16(data,frame*4+(ch or 0)*2)
    return v>=32768 and v-65536 or v
end
for frame=0,127 do
    local expected=0
    for _,offset in ipairs({0,12}) do
        if frame>=offset and frame<offset+32 then expected=expected+signed(pcm,frame-offset)*0.5 end
    end
    if frame>=20 and frame<52 then
        expected=expected+1000*(frame==51 and 0.5 or 1)
    end
    expected=math.max(-32768,math.min(32767,math.floor(expected+0.5)))
    assert(signed(wav:sub(45),frame)==expected,'Exact overlap, voice onset, resampling and natural clip endings')
    assert(signed(wav:sub(45),frame,1)==expected,'Stereo channels match')
end
job:dispose();assert(not io.open(path,'rb'))
job=score.new_job(mini,TEST_GAME_ROOT,path,options);job:step(0);job:cancel()
assert(job.status=='cancelled' and not io.open(path,'rb'),'Cancel removes partial cache')
local bad={read_member=function()return encoded..'changed' end}
job=score.new_job(mini,TEST_GAME_ROOT,path,bad);job:step(0)
assert(job.status=='error' and job.message:match('Music source changed') and not io.open(path,'rb'))
local existing=assert(io.open(path,'wb'));existing:write('keep');existing:close()
job=score.new_job(mini,TEST_GAME_ROOT,path,options);job:step(0)
assert(job.status=='error' and not job.owned)
f=assert(io.open(path,'rb'));assert(f:read('*a')=='keep');f:close();os.remove(path)
print('PASS: recorded score schedule, edited calls, exact overlapping stereo PCM, resampling, cancellable preparation, source guards, and cache cleanup')
