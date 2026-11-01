local report=require('core.report')
local score=require('core.score')
local music=require('core.music')
local playback=require('core.playback')
local root=TEST_GAME_ROOT
local level=report.load(root,2)
local plan=score.plan(level,nil,true,true,true)
assert(plan.report==2 and #plan.parts==3 and #plan.phrases==123 and #plan.clips==24)
assert(math.abs(plan.duration-1064.763861622607)<1e-8)
assert(not plan.response_timing_candidate and not plan.response_timing_checked,'Report 2 never borrows Report 1 audible timing evidence')
assert(#plan.omitted_voice_events>0,'Unidentified special calls remain explicit, not guessed')
assert(plan.clips[1].stem=='r21' and plan.clips[1].index==2,'Report 2 opening soundtrack is its own cue')
assert(plan.phrases[38].row.file.stem=='r22' and plan.phrases[83].row.file.stem=='r23')
for i,phrase in ipairs(plan.phrases) do
    local found=score.locate(plan,phrase.response+.001)
    assert(found==phrase,'Audio-clock seeking selects the correct Report 2 phrase')
    local row=phrase.row
    local binding,reason=music.binding(row.entry,row.file.buffer,row.file.stem)
    assert(binding,row.entry.name..': '..tostring(reason))
    assert(not binding.alignment_verified)
    local cues=require('core.score_catalog')[2].parts
    local part=assert(cues[row.file.stem=='r21' and 1 or row.file.stem=='r22' and 2 or 3])
    local cue
    for _,c in ipairs(part.cues) do if c.index==binding.index then cue=c;break end end
    assert(cue and math.abs(binding.offset_seconds-(row.event.response_seconds-cue.seconds))<1e-8,
        'Phrase music position matches the captured native response schedule')
end
local seen={}
for _,row in ipairs(level.cpu_route) do
    if row.file.stem=='r22' and (row.entry.name=='pr014' or row.entry.name=='ps016') then
        seen[row.entry.name]=true
        assert(music.binding(row.entry,row.file.buffer,'r22'),'Next cue exactly at the exclusive end must not count as overlap')
    end
end
assert(seen.pr014 and seen.ps016)
local file=level.files[1]
local saved=file.buffer
file.buffer=saved..'changed'
assert(not pcall(score.plan,level),'Changed Report 2 source cannot borrow the recorded schedule')
file.buffer=saved
local edited=score.plan(level,function(_,e)
    return {timing=e.timing,flag=e.flag,steps={4},hits={},start_delay=e.start_delay}
end,false,true,true)
assert(#edited.clips==0 and edited.events[1].code==4 and edited.events[1].seconds==plan.events[1].seconds)
print('PASS: all 123 Report 2 phrase bindings, three-part score, exact cue boundaries, seek identity, edit timing, special-call policy, and source guards')

local App=require('ui.app')
local app=App.new();app.game_root=root;app.config_path=TEST_SCRATCH..'/report2-loop.ini';app:load_report(2)
app.playback.mode='report';app.playback.plan=plan;app.playback.looping=true;app.playback.playing=true
app.playback.source={tell=function()return plan.duration+.25 end,isPlaying=function()return true end}
app:update_report_playback(0)
assert(math.abs(app.playback.position-.25)<1e-7 and app.current_file_name=='r21_sh.bin',
    'Cumulative streamed clock wraps GUI to the opening report file')
assert(not app.playback.report_tick,'No response playhead during the looped intro')
app.playback.source.tell=function()return plan.duration*3+plan.phrases[83].response+.1 end
app:update_report_playback(0)
assert(app.current_file_name=='r23_sh.bin' and math.abs(app.playback.report_tick-.1/plan.phrases[83].seconds_per_tick)<1e-6,
    'Later loop iterations select the exact phrase and tick')
print('PASS: cumulative streamed-source clocks select the correct file, phrase, and playhead on later report loops')
