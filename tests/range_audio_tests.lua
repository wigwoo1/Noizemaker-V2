local playback=require('core.playback')
local music=require('core.music')
local audio=require('core.game_audio')
local level=require('core.report').load(TEST_GAME_ROOT,1)
local file=level.files[1]
local held
for _,entry in ipairs(file.entries) do if entry.name=='pd006' then held=entry end end
assert(held and held.steps[1]==9 and held.hits[1]==24)
local bank=audio.command_bank(TEST_GAME_ROOT,'r11')
local full_plan=playback.plan(held,nil,nil,nil,'r11')
local full_music=assert(music.prepare(TEST_GAME_ROOT,'r11',held,held,full_plan,file.buffer,{}))
local full=playback.render(full_plan,bank,full_music)
local range_plan=playback.plan(held,nil,24,48,'r11')
local range_music=assert(music.prepare(TEST_GAME_ROOT,'r11',held,held,range_plan,file.buffer,{}))
local ranged=playback.render(range_plan,bank,range_music)
local first,count=playback.sample_window(range_plan,48000)
assert(ranged:sub(45)==full:sub(45+first*4,44+(first+count)*4),
    'A stock pd006 range must retain the held-Chu tail crossing its starting note')
assert(#range_plan.events==1 and range_plan.events[1].index==2,
    'The selected note list does not pretend the earlier call starts again')
assert(#range_plan.continuations==1 and range_plan.continuations[1].index==1
    and range_plan.continuations[1].sample_offset==-first,
    'The earlier held call keeps its original onset before the range')
assert(range_plan.music.timing_checked,'Original samples and positions retain the bounded timing check')

-- Starting inside a sample at an awkward tempo must use the same 44.1 kHz
-- grid as the complete phrase, including delay and single-frame rounding.
local delayed={steps={9},hits={},timing=16,start_delay=3}
local delayed_full=playback.render(playback.plan(delayed,137,nil,nil,'r11'),bank)
for _,bounds in ipairs({{6,18},{7,13},{13,19},{19,25},{48,72}}) do
    local piece=playback.plan(delayed,137,bounds[1],bounds[2],'r11')
    local output=playback.render(piece,bank)
    local start,frames=playback.sample_window(piece,44100)
    assert(output:sub(45)==delayed_full:sub(45+start*2,44+(start+frames)*2),
        'Range PCM preserves sample phase, start delay, fractional tempos and expired tails')
    if bounds[1]==48 then assert(#piece.continuations==0 and output:sub(45)==string.rep('\0',frames*2)) end
end

-- Small independent reference: at 16 kHz, the existing 8 kHz mono sample
-- interpolates to 1000,0,-1000,500,2000,... . A range beginning at frame 1
-- starts at 0, rather than retriggering 1000 or dropping the preceding voice.
local function pcm(values)
    local result={}
    for _,value in ipairs(values) do value=value%65536;result[#result+1]=string.char(value%256,math.floor(value/256)) end
    return table.concat(result)
end
local sample={pcm=pcm({1000,-1000,2000,-2000}),info={rate=8000,channels=1}}
local synthetic={events={},prior_events={{command='UP',tick=0}},first_tick=1,last_tick=4,
    seconds_per_tick=1/16000,duration=3/16000}
local background={pcm=pcm({200,-200,200,-200,200,-200}),info={rate=16000,channels=2,count=3},gain=1}
local clipped=playback.render(synthetic,{samples={UP=sample}},background)
assert(clipped:sub(45)==pcm({200,-200,-800,-1200,700,300}),
    'A preceding voice is clipped at the correct resampling phase and mixed into both stereo channels')

local unidentified={steps={255,3},hits={24},timing=16,start_delay=0}
local partial=playback.plan(unidentified,120,24,48,'r11')
local partial_wav=playback.render(partial,bank)
assert(#partial.warnings==1 and partial.warnings[1]:find('unidentified',1,true),
    'Unknown preceding tails receive an explicit warning instead of an invented voice')
assert(partial_wav:sub(45,44+#bank.samples.UP.pcm)==bank.samples.UP.pcm,
    'A missing earlier voice does not silence the known selected note')
assert(not pcall(playback.render,playback.plan(unidentified,120,0,24,'r11'),bank),
    'An unknown note starting inside the range still blocks unsupported playback')
print('PASS: range PCM equals the corresponding complete phrase, including the preceding held-Chu tail')
print('PASS: delayed/fractional range boundaries, expired tails, exact stereo resampling, unchanged note list, and unknown-event handling')
