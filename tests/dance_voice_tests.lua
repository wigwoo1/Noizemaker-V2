local mode=require('core.report').load(TEST_GAME_ROOT,'dance')
local file=mode.files[1]
local facts=require('core.dance_voice_data')
local context=require('core.voice_context')
local audio=require('core.game_audio')
local playback=require('core.playback')
local entries={};for _,e in ipairs(file.entries) do entries[e.name]=e end
local function ctx(e,path,buffer)return context.resolve(e,path or file.path,buffer or file.buffer,'r01')end
local count=0
for _,entry in ipairs(file.entries) do
    local c=ctx(entry)
    if c then
        for _,code in ipairs(entry.steps) do
            local key=audio.command_for_code(code,'r01',c)
            assert(key and facts.samples[key],entry.name..':'..code)
            count=count+1
        end
    else assert(not facts.contexts[entry.name]) end
end
assert(count==962)
for _,case in ipairs({{'pd0101',1,0},{'pd0301',1,4},{'pd0501',1,1},
    {'pd0701',1,2},{'pd0801',1,3},{'pd0603',9,10},{'pd0604',9,11},
    {'pd0603g',9,10},{'pd0604g',9,11}}) do
    assert(audio.command_for_code(case[2],'r01',ctx(entries[case[1]]))=='DANCE_V'..case[3]..'_M4')
end
assert(not ctx(entries.pd0301,nil,file.buffer..'changed'))
assert(not ctx(entries.pd0301,TEST_GAME_ROOT..'/afs_english/r01_sh.bin'))
local edited={};for k,v in pairs(entries.pd0604) do edited[k]=v end
edited.timing=edited.timing+1;assert(not ctx(edited))
assert(not context.command(9,ctx(entries.pd0101g)),'Ambiguous inserted held Chu never borrows one branch')
assert(not context.command(10,ctx(entries.pd0604)),'Nonexistent sixth held member is not read across bank bounds')
assert(not context.command(12,ctx(entries.pd0604)),'Misspelled native dummy member is not silently repaired')
local bank=audio.command_bank(TEST_GAME_ROOT,'r01')
local samples=0;for key,fact in pairs(facts.samples) do
    local sample=assert(bank.samples[key]);samples=samples+1
    assert(sample.name==fact.name and math.abs(sample.info.duration-fact.duration)<1e-9)
end
assert(samples==34)
local e=entries.pd0604
local full=playback.plan(e,nil,nil,nil,'r01',ctx(e))
local wav,info=playback.render(full,bank)
local range=playback.plan(e,nil,6,12,'r01',ctx(e))
local sliced=playback.render(range,bank)
local first,n=playback.sample_window(range,info.rate)
assert(sliced:sub(45)==wav:sub(45+first*2,44+(first+n)*2))
assert(#range.continuations>0 and range.continuations[1].command=='DANCE_V11_M4')
assert(not full.alignment_verified and not full.tempo_verified)
print('PASS: 962 original commands, native normal/dog/cat/car/mixed/held banks, source and timing guards, ambiguous/missing replacement guards, 34 decoded samples and exact held range PCM')
