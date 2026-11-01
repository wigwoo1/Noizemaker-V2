local timing=require('core.audio_timing')
local report=require('core.report')
local music=require('core.music')
local audio=require('core.game_audio')
local playback=require('core.playback')
local facts=require('core.audio_timing_data')
local level=report.load(TEST_GAME_ROOT,1)
local count=0
for _,row in ipairs(level.cpu_route) do
    local stem=row.file.relative_path:match('/(r%d%d)')
    local binding=assert(music.binding(row.entry,row.file.buffer,stem))
    local fact=assert(timing.phrase(stem,row.entry,row.file.buffer))
    assert(timing.binding(stem,row.entry,row.file.buffer,binding,facts.music[stem][fact.cue].sha256),
        'Every recorded response binds to its independently checked source/cue/offset')
    assert(not timing.binding(stem,row.entry,row.file.buffer,binding,'changed'),
        'Changed music cannot inherit a checked label')
    assert(not timing.phrase(stem,row.entry,row.file.buffer..'changed'),
        'Changed charts cannot inherit a checked label')
    local moved={index=binding.index,offset_seconds=binding.offset_seconds+1/12}
    assert(not timing.binding(stem,row.entry,row.file.buffer,moved,facts.music[stem][fact.cue].sha256),
        'An offset moved by a chart tick is not the recorded response position')
    count=count+1
end
assert(count==58)
for _,part in ipairs(require('core.score_data').parts) do
    assert(timing.part(part.stem,part),'Recorded response music schedule agrees with independent evidence')
    local shifted={duration=part.duration,cues={}}
    for i,cue in ipairs(part.cues) do
        local copy={};for k,v in pairs(cue) do copy[k]=v end;shifted.cues[i]=copy
    end
    shifted.cues[1].seconds=shifted.cues[1].seconds+1/30
    assert(not timing.part(part.stem,shifted),'Changing a cue time drops the report timing claim')
end
for _,stem in ipairs({'r11','r12'}) do
    local bank=audio.command_bank(TEST_GAME_ROOT,stem)
    for command,sample in pairs(bank.samples) do
        assert(timing.voice(stem,command,sample),'Only original, checked English PCM gets the timing label')
        assert(not timing.voice(stem,command,{name=sample.name,pcm=sample.pcm..'changed'}),
            'Changed voice PCM cannot reuse the checked label')
    end
end
local file=level.files[1]
local entry=file.entries[1]
local plan=playback.plan(entry,nil,nil,nil,'r11')
local bank=audio.command_bank(TEST_GAME_ROOT,'r11')
local background=assert(music.prepare(TEST_GAME_ROOT,'r11',entry,entry,plan,file.buffer,{}))
playback.render(plan,bank,background)
assert(plan.music.timing_checked and plan.music.timing_tolerance_seconds==.06 and not plan.music.alignment_verified,
    'Checked response positions keep their empirical tolerance and do not assert full alignment')
local changed=assert(music.prepare(TEST_GAME_ROOT,'r11',entry,entry,plan,file.buffer..'changed',{}))
assert(not changed.timing_checked,'An unrecognized source can preview without claiming recorded timing')
print('PASS: 58 recorded response bindings, 13 voice hashes, music/chart/offset/schedule guards, empirical tolerance, and provisional-source fallback')
