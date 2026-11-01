local report=require('core.report')
local playback=require('core.playback')
local music=require('core.music')
local audio=require('core.game_audio')
local question=require('core.question_voice')
local level=report.load(TEST_GAME_ROOT,1)
assert(#level.cpu_route==58)
local checked,combined_banks=0,{}
for _,row in ipairs(level.cpu_route) do
    local file,entry=row.file,row.entry
    local plan=playback.plan(entry,nil,nil,nil,file.stem)
    local event=assert(question.event(entry,entry,file.path,file.buffer,file.stem,plan),
        'Recorded English R1 phrase must resolve its enemy question: '..entry.name)
    assert(event.question==row.event.question)
    local question_bank=combined_banks[file.stem]
    if not question_bank then question_bank=question.bank(TEST_GAME_ROOT,file.stem);combined_banks[file.stem]=question_bank end
    local response_bank=combined_banks[file.stem..'_response']
    if not response_bank then response_bank=audio.command_bank(TEST_GAME_ROOT,file.stem);combined_banks[file.stem..'_response']=response_bank end
    local half=plan.duration
    local combined=assert(question.extend(plan,question_bank,response_bank))
    assert(#plan.events==2*#entry.steps and plan.question_duration==half and plan.duration==half*2)
    assert(plan.events[1].seconds<half and plan.events[#plan.events].seconds>=half)
    assert(combined.samples.QUESTION_UP and combined.samples.UP)
    checked=checked+1
    if row.event.order==1 or row.event.order==58 then
        local background=assert(music.prepare_full_question(TEST_GAME_ROOT,file.stem,entry,entry,plan,event,{}))
        assert(background.info.channels==2 and background.info.count==math.floor(plan.duration*48000+0.5))
        local wav,info=playback.render(plan,combined,background)
        assert(info.channels==2 and info.count==background.info.count and #wav==44+info.count*4)
        local quiet_wav,quiet_info=playback.render(plan,combined,nil)
        assert(quiet_info.channels==combined.channels and
            math.abs(quiet_info.duration-info.duration)<1/quiet_info.rate and
            #quiet_wav==44+quiet_info.count*quiet_info.channels*2,
            'Enemy and response calls play with music switched off')
        local state={plan=plan,position=half-0.1}
        assert(playback.tick(state)==nil)
        state.position=half+plan.seconds_per_tick*24
        assert(math.abs(playback.tick(state)-24)<1e-6)
    end
    if row.event.order==1 then
        assert(not question.event(entry,entry,file.path,file.buffer..'changed',file.stem,
            playback.plan(entry,nil,nil,nil,file.stem)))
        assert(not question.event(entry,entry,file.path,file.buffer,file.stem,
            playback.plan(entry,nil,6,48,file.stem)),'Selected response range remains response-only')
        local altered={};for key,value in pairs(entry) do altered[key]=value end
        altered.timing=entry.timing+1
        assert(not question.event(entry,altered,file.path,file.buffer,file.stem,
            playback.plan(entry,nil,nil,nil,file.stem)))
    end
end
assert(checked==58)
assert(question.command(33)=='CHU' and question.command(65)=='CHU')
assert(question.command(9)=='CHU' and question.command(0)==nil)
print('PASS: all 58 R1 questions paired with English enemy banks, source/range/length guards, real stereo full-phrase music and audio, response playhead offset')
