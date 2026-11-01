-- One source-guarded, recorded CPU route. The two script parts are joined
-- without a loading pause; this is not a recording of game dialogue or effects.
local route = require('core.route')
local catalog = require('core.score_catalog')
local playback = require('core.playback')
local music = require('core.music')
local audio = require('core.game_audio')
local adx = require('core.adx')
local timing = require('core.audio_timing')
local M = {}

local function frame(seconds, rate) return math.floor(seconds * rate + 0.5) end
local function hash(data)
    return (love.data.hash('sha256', data):gsub('.', function(c) return string.format('%02x', c:byte()) end))
end

function M.plan(report, resolve, with_music, with_voices, skip_unmapped_voices)
    local facts=report and catalog[report.number]
    assert(facts, 'Whole-report music is not mapped for this report yet')
    local rows, reason = route.rows(report)
    assert(rows, reason)
    local checked={}
    for _, row in ipairs(rows) do
        if not checked[row.file] then
            assert(route.source(row.file.path,row.file.buffer)==row.event.file,
                'Recorded report source no longer matches its timing evidence')
            checked[row.file]=true
        end
    end
    local plan = {mode='report', report=report.number,title=report.number=='dance' and report.title or ('Report '..report.number), phrases={}, events={}, clips={}, parts={}, rate=48000,
        duration=0, music_enabled=with_music~=false, voices_enabled=with_voices~=false,
        warnings={}, unmapped_commands={}, unmapped_voice_events={}, omitted_voice_events={},
        skip_unmapped_voices=skip_unmapped_voices==true, alignment_verified=false,
        response_timing_candidate=with_music~=false and with_voices~=false,response_timing_checked=false}
    local recorded_native=plan.voices_enabled and (
        (report.number==4 and require('core.voice_report4_route_data')) or
        (report.number==5 and require('core.voice_report5_route_data'))) or nil
    if recorded_native then plan.response_timing_candidate=false end
    local offsets, endings = {}, {}
    for _, part in ipairs(facts.parts) do
        if not timing.part(part.stem,part) then plan.response_timing_candidate=false end
        offsets[part.file] = plan.duration
        endings[part.file] = plan.duration+part.duration
        plan.parts[#plan.parts+1] = {stem=part.stem, first=plan.duration, last=plan.duration+part.duration}
        if plan.music_enabled then
            for _, cue in ipairs(part.cues) do
                plan.clips[#plan.clips+1] = {stem=part.stem, index=cue.index, sha256=cue.sha256,
                    rate=cue.rate, count=cue.count, channels=cue.channels,
                    seconds=plan.duration+cue.seconds, ending=plan.duration+part.duration}
            end
        end
        plan.duration = plan.duration + part.duration
    end
    for _, row in ipairs(rows) do
        local entry = resolve and resolve(row.file,row.entry) or row.entry
        assert(entry.timing==row.entry.timing, 'Report playback requires the original phrase length: '..row.entry.name)
        local stem = row.file.stem or row.file.relative_path:match('/(r%d%d)')
        if not timing.phrase(stem,row.entry,row.file.buffer) then plan.response_timing_candidate=false end
        local voice_context=require('core.voice_context').resolve(entry,row.file.path,row.file.buffer,stem)
        local phrase = playback.plan(entry,nil,nil,nil,stem,voice_context)
        assert(phrase.tempo_source=='chart' and phrase.bpm==row.event.bpm, 'Report playback requires the recorded chart tempo')
        local offset = assert(offsets[row.event.file], 'Unmapped report part')
        local first = offset + row.event.start_seconds
        local response = offset + row.event.response_seconds
        plan.phrases[#plan.phrases+1] = {row=row, first=first, response=response,
            ending=response+phrase.duration, seconds_per_tick=phrase.seconds_per_tick}
        if plan.voices_enabled then for _, event in ipairs(phrase.events) do
            local command=event.command
            local mapped=not command:match('^0x')
            if recorded_native then
                local source=recorded_native.sources[row.event.file]
                local native=source and recorded_native.events[row.event.order]
                native=native and native[event.index]
                mapped=native and native.code==event.code and native.sample~=false or false
                command=mapped and native.sample or string.format('0x%02X',event.code)
            end
            if not mapped then
                plan.unmapped_commands[event.code] = true
            end
            local planned={seconds=response+event.seconds, command=command,
                code=event.code, index=event.index, phrase=row.event.order,
                stem=stem, ending=endings[row.event.file]}
            if not mapped then plan.unmapped_voice_events[#plan.unmapped_voice_events+1]=planned end
            if mapped or not plan.skip_unmapped_voices then
                plan.events[#plan.events+1]=planned
            else
                plan.omitted_voice_events[#plan.omitted_voice_events+1]=planned
            end
        end end
        for _, warning in ipairs(phrase.warnings) do plan.warnings[warning]=true end
    end
    table.sort(plan.clips, function(a,b) return a.seconds<b.seconds end)
    table.sort(plan.events, function(a,b) return a.seconds<b.seconds end)
    if next(plan.unmapped_commands) then plan.response_timing_candidate=false end
    plan.frames = frame(plan.duration,plan.rate)
    return plan
end
function M.available(number) return catalog[number]~=nil end

function M.locate(plan, seconds)
    local selected
    for _, phrase in ipairs(plan.phrases) do
        if seconds >= phrase.first then selected=phrase else break end
    end
    if not selected then return plan.phrases[1],nil end
    local tick
    if seconds>=selected.response and seconds<selected.ending then
        tick=(seconds-selected.response)/selected.seconds_per_tick
    end
    return selected,tick
end

local function sample(pcm, index)
    local a,b=pcm:byte(index*2+1,index*2+2)
    if not b then return 0 end
    local v=a+b*256
    return v>=32768 and v-65536 or v
end

-- Bounded PCM chunks and yielding ADX decoding keep preparation cancellable.
-- Only currently overlapping music clips are kept decoded in memory. The
-- resulting WAV is streamed by LOVE, so playback has one seekable audio clock.
function M.new_job(plan, root, path, options)
    options=options or {}
    local job={status='queued',progress=0,message='Preparing English report audio',path=path,plan=plan}
    local handle
    function job:dispose()
        if handle then pcall(function()handle:close()end);handle=nil end
        if self.owned then os.remove(self.path);self.owned=false end
    end
    function job:cancel()
        self:dispose();self.thread=nil;self.status='cancelled'
    end
    job.thread=coroutine.create(function()
        if not plan.skip_unmapped_voices then
            for code in pairs(plan.unmapped_commands or {}) do
                error(string.format('Report command 0x%02X has no verified English voice mapping yet',code))
            end
        end
        local previous=io.open(path,'rb')
        if previous then previous:close();error('Report cache path already exists') end
        handle=assert(io.open(path,'wb'),'Could not create report audio cache')
        job.owned=true
        assert(handle:write(adx.wav_header({rate=plan.rate,channels=2,count=plan.frames})))
        local banks,active_clips,active_voices={},{},{}
        local responses_checked=plan.response_timing_candidate and plan.music_enabled~=false and plan.voices_enabled~=false
        local ci,vi=1,1
        local function pause(message)
            job.message=message
            coroutine.yield()
        end
        for first=0,plan.frames-1,4096 do
            local last=math.min(plan.frames,first+4096)
            local mixed={}
            for i=1,(last-first)*2 do mixed[i]=0 end
            while plan.clips[ci] and frame(plan.clips[ci].seconds,plan.rate)<last do
                local clip=plan.clips[ci]
                local encoded=(options.read_member or music.read_member)(root..'/'..clip.stem..'music.afs',clip.index)
                assert(hash(encoded)==clip.sha256,'Music source changed: '..clip.stem..' cue '..clip.index)
                local pcm,info=adx.decode(encoded,nil,function()
                    pause('Decoding music '..ci..' / '..#plan.clips)
                end)
                assert(info.rate==clip.rate and info.channels==2 and info.count==clip.count, 'Unsupported report music format')
                active_clips[#active_clips+1]={pcm=pcm,info=info,first=frame(clip.seconds,plan.rate),
                    last=math.min(frame(clip.ending,plan.rate),frame(clip.seconds,plan.rate)+math.ceil(info.count*plan.rate/info.rate)),gain=0.5}
                ci=ci+1
            end
            while plan.events[vi] and frame(plan.events[vi].seconds,plan.rate)<last do
                local event=plan.events[vi]
                banks[event.stem]=banks[event.stem] or (options.command_bank or audio.command_bank)(root,event.stem,function()
                    pause('Decoding English commands')
                end)
                local voice=assert(banks[event.stem].samples[event.command],'No English sample for '..event.command)
                if responses_checked and not timing.voice(event.stem,event.command,voice) then responses_checked=false end
                assert(voice.info.channels==1,'Unsupported command audio')
                active_voices[#active_voices+1]={pcm=voice.pcm,info=voice.info,first=frame(event.seconds,plan.rate),
                    last=math.min(frame(event.ending,plan.rate),frame(event.seconds,plan.rate)+math.ceil(voice.info.count*plan.rate/voice.info.rate))}
                vi=vi+1
            end
            for i=#active_clips,1,-1 do
                local clip=active_clips[i]
                for f=math.max(first,clip.first),math.min(last,clip.last)-1 do
                    local target=(f-first)*2+1
                    local position=(f-clip.first)*clip.info.rate/plan.rate
                    local whole=math.floor(position)
                    local fraction=position-whole
                    local source=whole*2
                    local left=sample(clip.pcm,source)
                    local right=sample(clip.pcm,source+1)
                    mixed[target]=mixed[target]+(left+(sample(clip.pcm,source+2)-left)*fraction)*clip.gain
                    mixed[target+1]=mixed[target+1]+(right+(sample(clip.pcm,source+3)-right)*fraction)*clip.gain
                end
                if clip.last<=last then table.remove(active_clips,i) end
            end
            for i=#active_voices,1,-1 do
                local voice=active_voices[i]
                for f=math.max(first,voice.first),math.min(last,voice.last)-1 do
                    local p=(f-voice.first)*voice.info.rate/plan.rate
                    local whole=math.floor(p)
                    local a=sample(voice.pcm,whole)
                    local value=a+(sample(voice.pcm,whole+1)-a)*(p-whole)
                    local target=(f-first)*2+1
                    mixed[target]=mixed[target]+value;mixed[target+1]=mixed[target+1]+value
                end
                if voice.last<=last then table.remove(active_voices,i) end
            end
            local bytes={}
            for i,v in ipairs(mixed) do
                local n=math.max(-32768,math.min(32767,math.floor(v+0.5)))%65536
                bytes[i]=string.char(n%256,math.floor(n/256))
            end
            assert(handle:write(table.concat(bytes)), 'Could not write report audio cache')
            job.progress=last/plan.frames
            pause(string.format('Building report audio: %d%%',math.floor(job.progress*100)))
        end
        assert(handle:close());handle=nil
        plan.response_timing_checked=responses_checked==true
        plan.response_timing_tolerance_seconds=plan.response_timing_checked and timing.tolerance_seconds or nil
        job.status='done';job.message='Report audio ready'
    end)
    function job:step(budget)
        if self.status=='done' or self.status=='error' or self.status=='cancelled' then return end
        self.status='running'
        local clock=love and love.timer and love.timer.getTime or os.clock
        local until_time=clock()+(budget or 0.006)
        repeat
            local ok,err=coroutine.resume(self.thread)
            if not ok then
                self:dispose();self.thread=nil;self.status='error';self.message=tostring(err)
            end
        until self.status~='running' or clock()>=until_time or budget==0
    end
    return job
end
return M
