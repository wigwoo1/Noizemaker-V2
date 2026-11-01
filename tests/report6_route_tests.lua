local report=require('core.report')
local route=require('core.route')
local level=report.load(TEST_GAME_ROOT,6)
local rows=report.cpu_rows(level)
assert(#rows==67 and #level.cpu_route==67,'Report 6 recorded route count')
assert(rows[1].file.stem=='r61' and rows[34].file.stem=='r61'
    and rows[35].file.stem=='r62' and rows[67].file.stem=='r62',
    'Report 6 two-part played order')
for i,row in ipairs(rows) do
    assert(row.event.order==i and row.entry.name==row.event.entry,
        'Report 6 chart/route match at visit '..i)
end
local first=rows[1].file
assert(not route.source(first.path,first.buffer..'changed'),
    'Changed English file cannot borrow the recorded route')
assert(level.cpu_route_note:find('67 reached phrases',1,true),'Report 6 scope note')
local facts=require('core.voice_report6_route_data')
local audio=require('core.game_audio')
local context=require('core.voice_context')
local playback=require('core.playback')
local long,gap
for _,row in ipairs(rows) do
    if row.entry.name=='pd007y' then long=row end
    if row.entry.name=='ps003w' then gap=row end
end
assert(long and gap,'R6 long Down and memory-gap phrases present')
local long_ctx=context.resolve(long.entry,long.file.path,long.file.buffer,long.file.stem)
local long_key=context.command(13,long_ctx,0)
assert(long_key and facts.samples[long_key]
    and facts.samples[long_key].name=='se/r61/bank02_ulala_tame/u144_604_pal.adx',
    'Long Down uses its observed English native sample')
assert(context.command(1,long_ctx,0)==nil,'An edited command cannot borrow the original call')
local long_plan=playback.plan(long.entry,nil,nil,nil,long.file.stem,long_ctx)
assert(long_plan.events[1].command==long_key,'Phrase playback selects original long Down')
local warned=false
for _,message in ipairs(long_plan.warnings) do
    if message:find('long Down',1,true) then warned=true end
end
assert(warned,'Long Down playback explains the unmodeled hold release')
local gap_ctx=context.resolve(gap.entry,gap.file.path,gap.file.buffer,gap.file.stem)
assert(gap_ctx and context.command(134,gap_ctx,48)==nil
    and context.command(132,gap_ctx,60)==nil
    and context.command(1,gap_ctx,72)==nil,
    'Three clock-gap calls remain provisional')
assert(not context.resolve(long.entry,long.file.path,long.file.buffer..'changed',long.file.stem),
    'Changed English source cannot borrow R6 voice selections')
local native_count,missing_count=0,0
for _,part in pairs(facts.events) do for _,event in pairs(part) do
    if event.sample then native_count=native_count+1 else missing_count=missing_count+1 end
end end
assert(native_count==268 and missing_count==3,'Only directly observed native calls are published')
local sample_count=0
for _,stem in ipairs({'r61','r62'}) do
    local bank=audio.command_bank(TEST_GAME_ROOT,stem)
    for key,fact in pairs(facts.samples) do
        if fact.stem==stem then
            assert(bank.samples[key] and bank.samples[key].name==fact.name)
            sample_count=sample_count+1
        end
    end
    if stem=='r61' then
        local voice=bank.samples[long_key]
        assert(voice.info.count/voice.info.rate>2.4,'Native long Down audio duration')
    end
end
assert(sample_count==20,'All 20 English native Report 6 samples decoded')
print('PASS: Report 6 67-phrase route; 268 original calls; three gap notes provisional; native long Down and 20 samples')
