local report=require('core.report')
local score=require('core.score')
local route=require('core.route')
local music=require('core.music')
local level=report.load(TEST_GAME_ROOT,4)
local rows=report.cpu_rows(level)
assert(#rows==134 and #level.cpu_route==134,'Report 4 recorded route count')
local counts={0,0,0,0}
for order,row in ipairs(rows) do
    assert(row.event.order==order and row.entry.route==row.event,'Source-bound phrase and route order')
    assert(row.file.route_source==row.event.file and row.event.bpm==require('core.playback').tempo(row.entry))
    counts[tonumber(row.file.stem:sub(3))]=counts[tonumber(row.file.stem:sub(3))]+1
end
assert(counts[1]==20 and counts[2]==37 and counts[3]==53 and counts[4]==24)
assert(rows[1].entry.name=='ps001' and rows[134].entry.name=='ps012a')
local plan=score.plan(level,nil,true,false)
assert(plan.report==4 and #plan.parts==4 and #plan.phrases==134 and #plan.clips==58)
assert(#plan.events==0 and not plan.voices_enabled and not plan.response_timing_candidate)
assert(not plan.response_timing_checked and not plan.alignment_verified)
local last=0
for _,part in ipairs(plan.parts) do
    assert(part.first==last and part.last>part.first)
    last=part.last
end
assert(math.abs(last-plan.duration)<1e-8 and plan.duration>1100)
for _,phrase in ipairs(plan.phrases) do
    assert(score.locate(plan,phrase.response+.001)==phrase,'Phrase seek position')
end
for _,clip in ipairs(plan.clips) do
    assert(clip.sha256 and #clip.sha256==64 and clip.seconds<plan.duration)
end
local first=rows[1].file
assert(not route.source(first.path,first.buffer..'changed'),'A changed source must not inherit the recorded order')
local original=first.buffer;first.buffer=original..'changed'
assert(not pcall(score.plan,level),'A changed source must not inherit Report 4 music')
first.buffer=original
local unmapped=score.plan(level,nil,false,false)
assert(#unmapped.clips==0 and #unmapped.events==0 and unmapped.duration==plan.duration)
local voices=score.plan(level,nil,true,true,true)
assert(#voices.events==605 and #voices.omitted_voice_events==26 and #voices.unmapped_voice_events==26,
    'Only source-checked original native calls with named English samples are played')
assert(not voices.response_timing_candidate and not voices.response_timing_checked,
    'Native sample selection does not prove precise audible alignment')
assert(voices.events[1].command=='R41_P72eaa0_M2' and voices.events[1].code==6)
local edited=score.plan(level,function(_,entry)
    if entry==rows[1].entry then
        local replacement={timing=entry.timing,flag=entry.flag,steps={},hits=entry.hits,start_delay=entry.start_delay}
        for i,code in ipairs(entry.steps) do replacement.steps[i]=i==1 and 3 or code end
        return replacement
    end
    return entry
end,true,true,true)
assert(#edited.events==604 and #edited.omitted_voice_events==27,
    'An edited code cannot silently inherit the original recorded voice')
local facts=require('core.voice_report4_route_data')
local audio=require('core.game_audio')
local count=0
for _,stem in ipairs({'r41','r42','r43','r44'}) do
    local bank=audio.command_bank(TEST_GAME_ROOT,stem)
    for key,fact in pairs(facts.samples) do
        if fact.stem==stem then
            local sample=assert(bank.samples[key],'Missing checked native sample '..key)
            assert(sample.name==fact.name and sample.info.channels==1)
            count=count+1
        end
    end
end
assert(count==42,'All 42 named native sample bindings are decoded from English resources')
local app=require('ui.app').new();app.game_root=TEST_GAME_ROOT;app.config_path=TEST_SCRATCH..'/report4-music.ini'
app:load_report(4);app:start_report_playback(true,true)
assert(app.playback.report_job and #app.playback.plan.events==605)
app:playback_action('stop')
app:start_report_playback(false)
assert(app.playback.report_job and app.playback.plan.report==4 and not app.playback.plan.voices_enabled,tostring(app.status_text))
app:playback_action('stop')
assert(not app.playback.report_job)
print('PASS: 134 source-guarded Report 4 phrases, four sections, 58 music cues, 605 named native calls, 26 unavailable calls, edited-call guard, sample decoding, music-only and mapped-call render preparation')
