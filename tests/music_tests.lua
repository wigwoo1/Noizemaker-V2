local music = require("core.music")
local playback = require("core.playback")
local report = require("core.report")
local audio = require("core.game_audio")
local r = report.load(TEST_GAME_ROOT,1)
local file,cache = r.files[1],{}
local first,down = file.entries[1],file.entries[2]
local binding = assert(music.binding(first,file.buffer,"r11"))
assert(binding.index==9 and binding.offset_seconds==12 and binding.phase=="Ulala response",
    "opening cue inherits the intro's lead-in and previews the response half")
local own = assert(music.binding(down,file.buffer,"r11"))
assert(own.index==10 and math.abs(own.offset_seconds-48/13)<0.000001,
    "DOWN phrase uses its own music command and eight-beat response offset")
assert(not own.alignment_verified,"script-derived alignment must not claim a completed listening check")
local plan = playback.plan(down)
local background = assert(music.prepare(TEST_GAME_ROOT,"r11",down,down,plan,file.buffer,cache))
assert(background.info.rate==48000 and background.info.channels==2,"real stereo music format")
assert(background.info.count==177231 and #background.pcm==177231*4,"exact response music window")
assert(math.abs(background.offset_seconds-177231/48000)<0.000001,"sample-aligned music seek")
local range = playback.plan(down,nil,24,48)
local slice = assert(music.prepare(TEST_GAME_ROOT,"r11",down,down,range,file.buffer,cache))
local delta = math.floor(24*plan.seconds_per_tick*48000+0.5)
assert(slice.pcm==background.pcm:sub(delta*4+1,delta*4+#slice.pcm),
    "selected range seeks to the same music samples as full-phrase playback")
local adjacent=playback.plan(down,nil,48,96)
local remainder=assert(music.prepare(TEST_GAME_ROOT,"r11",down,down,adjacent,file.buffer,cache))
assert(remainder.info.count==177231-88615,"adjacent range ends on the full phrase sample boundary")
assert(remainder.pcm==background.pcm:sub(88615*4+1),"adjacent range preserves the full phrase samples")
local third,unmapped
for _,entry in ipairs(file.entries) do
    if entry.name=="pd003" then third=entry end
    if entry.name=="pk001" then unmapped=entry end
end
assert(third,"installed chart contains the one-frame clip-boundary example")
assert(music.prepare(TEST_GAME_ROOT,"r11",third,third,playback.plan(third),file.buffer,cache),
    "nominal phrase length tolerates the shipped clip's one-frame rounding difference")
assert(unmapped,"installed chart contains the inherited-cue example")
assert(music.binding(unmapped,file.buffer,"r11").index==3,
    "the final call inherits its verified-source recorded-route music cue")
local count=0;for _ in pairs(cache) do count=count+1 end
assert(count==2,"repeated range playback reuses decoded music; third phrase adds one member")
local unavailable,reason=music.prepare(TEST_GAME_ROOT,"r11",down,down,playback.plan(down,90),file.buffer,cache)
assert(not unavailable and reason:find("chart BPM",1,true),"manual tempo cannot silently misalign music")
unavailable,reason=music.prepare(TEST_GAME_ROOT,"r11",down,{timing=24},plan,file.buffer,cache)
assert(not unavailable and reason:find("phrase length",1,true),"length changes cannot silently reuse unrelated music")
assert(not pcall(music.read_member,TEST_GAME_ROOT.."/r11music.afs",9999),"invalid AFS cue is rejected")

-- Independent little synthetic example: preserve stereo background while
-- resampling a mono voice at half the music rate and mixing it into both ears.
local function pcm(values)
    local out={}
    for i,value in ipairs(values) do value=value%65536;out[i]=string.char(value%256,math.floor(value/256)) end
    return table.concat(out)
end
local stereo={}
for i=1,8 do stereo[#stereo+1]=200;stereo[#stereo+1]=-200 end
local synthetic_music={pcm=pcm(stereo),info={count=8,rate=16000,channels=2},gain=1}
local synthetic_bank={samples={UP={pcm=pcm({1000,-1000}),info={rate=8000,channels=1}}}}
local synthetic_plan={duration=8/16000,events={{command="UP",seconds=0}}}
local wav,info=playback.render(synthetic_plan,synthetic_bank,synthetic_music)
assert(info.channels==2 and info.count==8 and #wav==44+32,"stereo WAV dimensions")
assert(wav:sub(45,60)==pcm({1200,800,200,-200,-800,-1200,-300,-700}),"mono interpolation and stereo mixing")
assert(wav:sub(61)==pcm({200,-200,200,-200,200,-200,200,-200}),"background continues after the voice ends")

local bank=audio.command_bank(TEST_GAME_ROOT,"r11")
local mixed,mixed_info=playback.render(plan,bank,background)
assert(mixed_info.channels==2 and plan.music.name=="r11 music cue 10","real music is attached to rendered preview")
assert(plan.events[2].sample_offset==44308,"voice onset uses the stereo output sample rate")
local output=assert(io.open(TEST_OUTPUT.."/english-response-music-preview.wav","wb"));output:write(mixed);output:close()
output=assert(io.open(TEST_SCRATCH.."/music-response-window.pcm","wb"));output:write(background.pcm);output:close()
print("PASS: script music cues, response phase, exact range seek, cache, stereo mixing, voice resampling, and explicit unmapped/changed-tempo behavior")

-- Regression: shooting animation tails are not packet streams and contain no
-- local music cue. The preceding mov2c music continues across these phrases.
local shooting,following
local shooting_count=0
for _,source in ipairs(r.files) do
    if source.route_source==source.relative_path then
        local stem=source.relative_path:match('/(r%d%d)')
        for _,entry in ipairs(source.entries) do
            if entry.route and entry.name:match('^ps') then
                assert(music.binding(entry,source.buffer,stem),entry.name.." must retain response music")
                shooting_count=shooting_count+1
            end
            if source==file and entry.name=='ps001' then shooting=entry end
            if source==file and entry.name=='ps002' then following=entry end
        end
    end
end
assert(shooting_count==38,"all 38 recorded shooting phrases retain music across both report parts")
local inherited=assert(music.binding(shooting,file.buffer,'r11'))
assert(inherited.index==25 and math.abs(inherited.offset_seconds-7.5)<0.000001,
    "first shooting response is exactly 7.5 seconds into mov2c cue 25")
assert(inherited.source=='recorded route script' and not inherited.alignment_verified)
assert(not music.binding(shooting,file.buffer:sub(1,-2)..'X','r11'),
    "a changed source cannot inherit the captured route's music")
assert(not music.binding(shooting,file.buffer,'r12'),"same phrase name cannot borrow another part's cue")
local shooting_cache={}
local shooting_plan=playback.plan(shooting)
local shooting_music=assert(music.prepare(TEST_GAME_ROOT,'r11',shooting,shooting,shooting_plan,file.buffer,shooting_cache))
local decoded,metadata=require('core.adx').decode(music.read_member(TEST_GAME_ROOT..'/r11music.afs',25))
assert(shooting_music.info.count==72000 and shooting_music.offset_seconds==7.5,
    "first shooting response has 1.5 seconds of stereo music")
assert(shooting_music.pcm==decoded:sub(360000*4+1,432000*4),
    "shooting response PCM matches the exact inherited archive window")
assert(shooting_music.pcm:find('[^%z]'),"shooting music window must not be silent")
local shooting_range=playback.plan(shooting,nil,24,48)
local shooting_slice=assert(music.prepare(TEST_GAME_ROOT,'r11',shooting,shooting,shooting_range,file.buffer,shooting_cache))
assert(shooting_slice.pcm==shooting_music.pcm:sub(36000*4+1),"shooting range preview seeks inside the inherited track")
local next_music=assert(music.prepare(TEST_GAME_ROOT,'r11',following,following,playback.plan(following),file.buffer,shooting_cache))
assert(next_music.offset_seconds==10.5 and next_music.name==shooting_music.name,
    "the next shooting phrase advances within the same track")
local shooting_wav,shooting_info=playback.render(shooting_plan,bank,shooting_music)
assert(shooting_plan.music and shooting_info.channels==2,"shooting preview mixes inherited music with voices")
local preview=assert(io.open(TEST_OUTPUT..'/report1-shooting-preview.wav','wb'))
preview:write(shooting_wav);preview:close()
print('PASS: all 38 recorded shooting bindings, exact cue-25 PCM, non-silent stereo mix, range/next-phrase seek, and source guards')
