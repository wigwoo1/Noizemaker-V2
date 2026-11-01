local report=require('core.report')
local playback=require('core.playback')
local music=require('core.music')
local audio=require('core.game_audio')
local question=require('core.question_voice_report2')
local level=report.load(TEST_GAME_ROOT,2)
assert(#level.cpu_route==123)
local banks,covered,muted={},0,0
local selected={r21=false,r22=false,r23=false}
for _,row in ipairs(level.cpu_route) do
    local file,entry,event=row.file,row.entry,row.event
    local stem=file.stem
    local plan=playback.plan(entry,nil,nil,nil,stem)
    assert(question.event(entry,entry,file.path,file.buffer,stem,plan)==event,
        'Report 2 English source and route identity must match: '..entry.name)
    local bank_name=question.bank_key(event)
    local key=stem..'/'..bank_name
    if not banks[key] then banks[key]=question.bank(TEST_GAME_ROOT,stem,event) end
    if not banks[stem..'/response'] then
        banks[stem..'/response']=audio.command_bank(TEST_GAME_ROOT,stem)
    end
    local half=plan.duration
    local mixed,reason=question.extend(plan,banks[key],banks[stem..'/response'],event)
    assert(mixed,entry.name..': '..tostring(reason))
    assert(plan.question_duration==half and plan.duration==2*half)
    assert(plan.events[1].command:match('^QUESTION_'))
    assert(#plan.events>0 and #plan.events<=2*#entry.steps)
    muted=muted+(plan.question_unmapped_count or 0)
    covered=covered+1
    if not selected[stem] then
        local background=assert(music.prepare_full_question(TEST_GAME_ROOT,stem,entry,entry,
            plan,event,{}))
        assert(background.info.channels==2 and not background.timing_checked)
        local wav,info=playback.render(plan,mixed,background)
        assert(#wav==44+info.count*info.channels*2 and info.channels==2)
        selected[stem]=true
    end
    if event.order==1 then
        assert(not question.event(entry,entry,file.path,file.buffer..'changed',stem,
            playback.plan(entry,nil,nil,nil,stem)))
        assert(not question.event(entry,entry,file.path,file.buffer,stem,
            playback.plan(entry,nil,6,48,stem)))
    end
end
assert(covered==123)
assert(selected.r21 and selected.r22 and selected.r23)
assert(muted>0,'Unknown raw command bytes must stay explicitly silent')
print('PASS: 123 source-bound Report 2 questions, section banks, unmapped raw-call guards, and real stereo full-phrase audio across three parts; muted raw calls='..muted)
