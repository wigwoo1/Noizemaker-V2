local music=require('core.music')
local playback=require('core.playback')
local format=require('core.format')
local mode=require('core.report').load(TEST_GAME_ROOT,'dance')
local file=mode.files[1]
local cache,by_name={},{}
local count=0
for _,entry in ipairs(file.entries) do
    by_name[entry.name]=entry
    local plan=playback.plan(entry,nil,nil,nil,'r01')
    local sample,reason=music.prepare(TEST_GAME_ROOT,'r01',entry,entry,plan,file.buffer,cache)
    assert(sample,entry.name..':'..tostring(reason));count=count+1
    assert(sample.info.channels==2 and sample.info.rate==48000)
    assert(not sample.timing_checked and not sample.alignment_verified)
    assert(sample.offset_seconds>=0 and #sample.pcm==sample.info.count*4)
    local source=cache[TEST_GAME_ROOT..'/r01music.afs#'..music.binding(entry,file.buffer,'r01').index]
    assert(source)
    local first=math.floor(entry.timing*30/plan.bpm*48000+.5)
    local expected=source.pcm:sub(first*4+1,(first+sample.info.count)*4)
    if #expected<#sample.pcm then expected=expected..string.rep('\0',#sample.pcm-#expected) end
    assert(sample.pcm==expected,'Exact response half of declared clip: '..entry.name)
end
assert(count==200)
local clips=0;for _ in pairs(cache) do clips=clips+1 end;assert(clips==100)
for _,name in ipairs({'pd0101','pd0604','pd0706','pd0808','pd0909','pd1010g'}) do
    local e=by_name[name]
    local full=playback.plan(e,nil,nil,nil,'r01')
    local background=assert(music.prepare(TEST_GAME_ROOT,'r01',e,e,full,file.buffer,cache))
    local first,last=1,math.min(13,format.total_ticks(e.timing))
    local range=playback.plan(e,nil,first,last,'r01')
    local slice=assert(music.prepare(TEST_GAME_ROOT,'r01',e,e,range,file.buffer,cache))
    local at,n=playback.sample_window(range,48000)
    assert(slice.pcm==background.pcm:sub(at*4+1,(at+n)*4),'Range music uses the full phrase PCM grid')
end
local e=by_name.pd0101
assert(not music.binding(e,file.buffer..'changed','r01'))
local edited={};for k,v in pairs(e) do edited[k]=v end
edited.timing=e.timing+1
assert(not music.prepare(TEST_GAME_ROOT,'r01',e,edited,playback.plan(edited,nil,nil,nil,'r01'),file.buffer,cache))
assert(not music.prepare(TEST_GAME_ROOT,'r01',e,e,playback.plan(e,120,nil,nil,'r01'),file.buffer,cache))
local bank=require('core.game_audio').command_bank(TEST_GAME_ROOT,'r01')
local ctx=require('core.voice_context').resolve(by_name.pd0604,file.path,file.buffer,'r01')
local plan=playback.plan(by_name.pd0604,nil,nil,nil,'r01',ctx)
local background=assert(music.prepare(TEST_GAME_ROOT,'r01',by_name.pd0604,by_name.pd0604,plan,file.buffer,cache))
local full,info=playback.render(plan,bank,background)
local range=playback.plan(by_name.pd0604,nil,6,12,'r01',ctx)
local range_bg=assert(music.prepare(TEST_GAME_ROOT,'r01',by_name.pd0604,by_name.pd0604,range,file.buffer,cache))
local clipped=playback.render(range,bank,range_bg)
local at,n=playback.sample_window(range,info.rate)
assert(clipped:sub(45)==full:sub(45+at*4,44+(at+n)*4),'Stereo music plus held cat continuation is sample-exact')
assert(#range.continuations>0 and not plan.music.timing_checked)
print('PASS: all 200 Dance phrase bindings and 100 stereo clips, exact response/range PCM, source/length/BPM guards and mixed held-cat continuation; audible sync remains unverified')
