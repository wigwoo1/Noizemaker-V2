local report=require('core.report')
local audio=require('core.game_audio')
local context=require('core.voice_context')
local playback=require('core.playback')
local mode=report.load(TEST_GAME_ROOT,4)
local count=0
local bank=audio.command_bank(TEST_GAME_ROOT,'r43')
assert(math.abs(bank.samples.R43_HOLD_CHU.info.duration-.9200907029478458)<1e-9)
assert(bank.samples.R43_HOLD_HEY.name:find('dammy',1,true))
for _,file in ipairs(mode.files) do
    if file.stem=='r43' then
        for _,entry in ipairs(file.entries) do
            local ctx=assert(context.resolve(entry,file.path,file.buffer,'r43'))
            local plan=playback.plan(entry,nil,nil,nil,'r43',ctx)
            for _,event in ipairs(plan.events) do
                if event.code==9 then
                    count=count+1;assert(event.command=='R43_HOLD_CHU')
                end
            end
            assert(not context.resolve(entry,file.path,file.buffer..'changed','r43'))
            assert(not context.resolve(entry,TEST_GAME_ROOT..'/r43_sh.bin',file.buffer,'r43'))
            if entry.name=='pr004w' then
                local full,info=playback.render(plan,bank)
                local range=playback.plan(entry,nil,6,12,'r43',ctx)
                local sliced=playback.render(range,bank)
                local first,n=playback.sample_window(range,info.rate)
                assert(sliced:sub(45)==full:sub(45+first*2,44+(first+n)*2))
                assert(#range.continuations>0 and range.continuations[1].command=='R43_HOLD_CHU')
                local replacement={};for k,v in pairs(entry) do replacement[k]=v end
                replacement.steps={10,1}
                assert(playback.plan(replacement,nil,nil,nil,'r43',ctx).events[1].command=='R43_HOLD_HEY')
                replacement.timing=entry.timing+1
                assert(not context.resolve(replacement,file.path,file.buffer,'r43'))
            end
        end
    elseif file.stem~='r42' then
        assert(not context.resolve(file.entries[1],file.path,file.buffer,file.stem))
    end
end
assert(count==6)
assert(audio.command_for_code(9,'r43')=='CHU','Unknown source keeps a provisional short preview')
print('PASS: six R43 held-Chu events across English main/SH2, source/path/timing guards, native held-Hey dummy replacement and exact held range PCM')

local r42=audio.command_bank(TEST_GAME_ROOT,'r42')
local facts=require('core.voice_report42_data');local r42count=0
for _,file in ipairs(mode.files) do if file.stem=='r42' then
    for _,entry in ipairs(file.entries) do
        local ctx=assert(context.resolve(entry,file.path,file.buffer,'r42'))
        local plan=playback.plan(entry,nil,nil,nil,'r42',ctx)
        for _,event in ipairs(plan.events) do if event.code>=9 and event.code<=14 then
            r42count=r42count+1;assert(event.command==facts.bindings[tostring(event.code)])
        end end
        assert(not context.resolve(entry,file.path,file.buffer..'changed','r42'))
        assert(not context.resolve(entry,TEST_GAME_ROOT..'/r42_sh.bin',file.buffer,'r42'))
        assert(not context.resolve(entry,TEST_GAME_ROOT..'/afs_english/r43_sh.bin',file.buffer,'r42'))
        if entry.name=='pd010' then
            local original=entry.steps[1]
            for code=9,14 do
                entry.steps[1]=code
                local current=playback.plan(entry,nil,nil,nil,'r42',ctx)
                assert(current.events[1].command==facts.bindings[tostring(code)])
                local full,info=playback.render(current,r42)
                local range=playback.plan(entry,nil,6,12,'r42',ctx)
                local sliced=playback.render(range,r42)
                local first,n=playback.sample_window(range,info.rate)
                assert(sliced:sub(45)==full:sub(45+first*2,44+(first+n)*2))
                assert(#range.continuations>0 and range.continuations[1].command==facts.bindings[tostring(code)])
                assert(range.warnings[1]:find('audible timing',1,true))
            end
            entry.steps[1]=original
            local oldtiming=entry.timing;entry.timing=oldtiming+1
            assert(not context.resolve(entry,file.path,file.buffer,'r42'));entry.timing=oldtiming
            local oldflag=entry.flag;entry.flag=string.char(120,0)
            assert(not context.resolve(entry,file.path,file.buffer,'r42'));entry.flag=oldflag
        end
    end
end end
assert(r42count==32)
assert(audio.command_for_code(9,'r42')=='CHU','Unidentified source retains provisional fallback')
for key,fact in pairs(facts.samples) do assert(math.abs(r42.samples[key].info.duration-fact.duration)<1e-9) end
print('PASS: 32 R42 held events, all six native held samples, replacement and exact range PCM, source/path/tempo/length guards; no audible sync claim')
