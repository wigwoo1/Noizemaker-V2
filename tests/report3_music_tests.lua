local report=require('core.report')
local score=require('core.score')
local music=require('core.music')
local level=report.load(TEST_GAME_ROOT,3)
local plan=score.plan(level)
assert(plan.report==3 and #plan.parts==1 and #plan.phrases==56 and #plan.clips==4)
assert(math.abs(plan.duration-391.42212885154066)<1e-8)
assert(not plan.response_timing_candidate and not plan.response_timing_checked and not plan.alignment_verified)
assert(not next(plan.unmapped_commands),'Report 3 uses named standard/hold codes; sample identity is a separate check')
for _,phrase in ipairs(plan.phrases) do
    local row=phrase.row
    assert(score.locate(plan,phrase.response+.001)==phrase)
    local binding,reason=music.binding(row.entry,row.file.buffer,row.file.stem)
    assert(binding,row.entry.name..': '..tostring(reason))
    assert(not binding.timing_checked and not binding.alignment_verified)
    local cue
    for _,c in ipairs(require('core.score_catalog')[3].parts[1].cues) do
        if c.index==binding.index then cue=c end
    end
    assert(cue and math.abs(binding.offset_seconds-(row.event.response_seconds-cue.seconds))<1e-8)
end
local file=level.files[1];local original=file.buffer
file.buffer=original..'changed'
assert(not pcall(score.plan,level),'Changed sources cannot borrow recorded score timing')
file.buffer=original
local silent=score.plan(level,nil,false,false)
assert(#silent.clips==0 and #silent.events==0 and silent.duration==plan.duration)
print('PASS: all 56 Report 3 phrase music bindings, four cues, seek identity, source guards, and honest sync labels')
