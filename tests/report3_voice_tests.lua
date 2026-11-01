local report=require('core.report')
local audio=require('core.game_audio')
local context=require('core.voice_context')
local playback=require('core.playback')
local score=require('core.score')
local level=report.load(TEST_GAME_ROOT,3)
local file=level.files[1]
local entries={};for _,e in ipairs(file.entries) do entries[e.name]=e end
local function plan(name,entry,first,last)
    entry=entry or entries[name]
    return playback.plan(entry,nil,first,last,'r31',context.resolve(entry,file.path,file.buffer,'r31'))
end
for _,name in ipairs({'pd016','pd017','pd018','pd019','pd020'}) do
    local found=false
    for _,event in ipairs(plan(name).events) do
        if event.code==9 then assert(event.command=='R31_HOLD_CHU_SHORT');found=true end
    end
    assert(found)
end
for _,name in ipairs({'pd021','pd022'}) do
    local found=false
    for _,event in ipairs(plan(name).events) do
        if event.code==10 then assert(event.command=='R31_HOLD_HEY_SHORT');found=true end
    end
    assert(found)
end
assert(plan('pd023').events[1].command=='R31_HOLD_CHU_LONG')
assert(audio.command_for_code(9,'r31')=='CHU','Unknown route does not borrow the bank schedule')
assert(not context.resolve(entries.pd023,file.path,file.buffer..'changed','r31'))
assert(not context.resolve(entries.pd023,TEST_GAME_ROOT..'/R31_SH.BIN',file.buffer,'r31'))
assert(not context.resolve(level.files[2].entries[1],level.files[2].path,level.files[2].buffer,'r31'))
local bank=audio.command_bank(TEST_GAME_ROOT,'r31')
local full=plan('pd023')
local wav,info=playback.render(full,bank)
local range=plan('pd023',nil,24,48)
local ranged=playback.render(range,bank)
local first,count=playback.sample_window(range,info.rate)
assert(ranged:sub(45)==wav:sub(45+first*2,44+(first+count)*2),'Long Chu range equals the complete-phrase PCM slice')
assert(#range.continuations==1 and range.continuations[1].command=='R31_HOLD_CHU_LONG')
local before=entries.pd023
local replacement={name=before.name,timing=before.timing,flag=before.flag,start_delay=before.start_delay,
    steps={10,1},hits=before.hits}
assert(plan('pd023',replacement).events[1].command=='R31_HOLD_HEY_LONG','Replacement follows native held-bank context')
local complete=score.plan(level)
local held=0
for _,event in ipairs(complete.events) do
    if event.code==9 or event.code==10 then
        held=held+1
        assert(event.command:match('^R31_HOLD_'))
        if complete.phrases[event.phrase].row.entry.name=='pd023' then
            assert(event.command=='R31_HOLD_CHU_LONG')
        end
    end
end
assert(held==10 and not complete.response_timing_checked)
print('PASS: R31 bank state, all ten held events, source/branch guards, native long-Hey replacement, and exact range continuations')
