local report=require('core.report')
local score=require('core.score')
local route=require('core.route')
local level=report.load(TEST_GAME_ROOT,5)
local rows=report.cpu_rows(level)
assert(#rows==54 and #level.cpu_route==54,'Report 5 recorded route count')
assert(rows[1].file.stem=='r51' and rows[20].file.stem=='r51'
    and rows[21].file.stem=='r52' and rows[54].file.stem=='r52',
    'Report 5 two-part played order')
local plan=score.plan(level,nil,true,false)
assert(plan.report==5 and #plan.parts==2 and #plan.phrases==54 and #plan.clips==17)
assert(#plan.events==0 and not plan.voices_enabled and not plan.response_timing_candidate)
assert(not plan.response_timing_checked and not plan.alignment_verified)
assert(math.abs(plan.duration-648.66)<.1,'Both section durations are retained')
assert(plan.parts[1].first==0 and plan.parts[1].last==plan.parts[2].first
    and plan.parts[2].last==plan.duration,'Report 5 section handoff is continuous in the preview')
for _,phrase in ipairs(plan.phrases) do
    assert(score.locate(plan,phrase.response+.001)==phrase,'Phrase seek identity')
end
for _,clip in ipairs(plan.clips) do
    assert(clip.sha256 and #clip.sha256==64 and clip.seconds<plan.duration)
end
local first=rows[1].file
assert(not route.source(first.path,first.buffer..'changed'),'Changed file cannot borrow recorded route')
local original=first.buffer;first.buffer=original..'changed'
assert(not pcall(score.plan,level),'Changed file cannot borrow Report 5 music')
first.buffer=original
local voices=score.plan(level,nil,true,true,true)
assert(#voices.events==327 and #voices.omitted_voice_events==0
    and #voices.unmapped_voice_events==0,'All original native Report 5 calls have named English samples')
assert(not voices.response_timing_candidate and not voices.response_timing_checked,
    'Native sample identity alone does not prove precise audible alignment')
local changed=score.plan(level,function(_,entry)
    if entry==rows[1].entry then
        local replacement={timing=entry.timing,flag=entry.flag,steps={},hits=entry.hits,start_delay=entry.start_delay}
        for i,code in ipairs(entry.steps) do replacement.steps[i]=i==1 and (code==3 and 4 or 3) or code end
        return replacement
    end
    return entry
end,true,true,true)
assert(#changed.events==326 and #changed.omitted_voice_events==1,
    'An edited command must not silently borrow its old native voice sample')
local facts=require('core.voice_report5_route_data')
local audio=require('core.game_audio')
local count=0
for _,stem in ipairs({'r51','r52'}) do
    local bank=audio.command_bank(TEST_GAME_ROOT,stem)
    for key,fact in pairs(facts.samples) do
        if fact.stem==stem then
            local sample=assert(bank.samples[key],'Missing checked native sample '..key)
            assert(sample.name==fact.name and sample.info.channels==1)
            count=count+1
        end
    end
end
assert(count==16,'All 16 named native Report 5 samples decode from guarded resources')
print('PASS: Report 5 exact English source guards, 54 phrases, 17 music cues, 327 original calls, 16 decoded samples, edited-call guard and cross-part seek')
