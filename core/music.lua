-- Music for the Ulala response half of a phrase. Bindings come from script
-- music commands, not a guessed track number or a user-entered time offset.
local format = require("core.format")
local adx = require("core.adx")
local playback = require("core.playback")
local M = {}

local function packets(data, first, last)
    local result, at = {}, first or 0
    last = last or #data
    while at < last do
        if at+2 > last then return nil end
        local op, words = data:byte(at+1,at+2)
        if words == 0 or at+words*2 > last then return nil end
        local args = {}
        for i=1,words-1 do args[i]=format.u16(data,at+i*2) end
        result[#result+1]={op=op,words=words,args=args}
        at=at+words*2
    end
    return result
end

local function opening(entry, buffer, stem)
    -- The recorded Report 1 opening queues an intro and lead-in before the
    -- first chart. Derive its inherited cue and offset from that mov1 program.
    if stem~="r11" or entry.name~="pd001" or not buffer then return nil end
    local table_at=format.u32(buffer,32)
    local dp,np=format.u32(buffer,table_at),format.u32(buffer,table_at+4)
    local program=packets(buffer,dp,np)
    if not program or program[1].op~=0x0b or program[1].args[2]~=0 then return nil end
    local segments,cues,beat={}, {},0
    for _,p in ipairs(program) do
        if p.op==0x2b and p.words==4 then
            segments[#segments+1]={first=beat,last=beat+p.args[2],bpm=p.args[3]}
            beat=beat+p.args[2]
        elseif p.op==0x22 and p.words==3 then
            cues[#cues+1]={index=p.args[1],beat=p.args[2]/format.CHART_TICKS_PER_BEAT}
        elseif p.op==0x18 then break end
    end
    -- Guard the observed opening structure instead of extrapolating this rule
    -- to other sections, branches, or modified intros.
    if #segments~=2 or segments[1].last~=72 or segments[1].bpm~=135
        or segments[2].last~=88 or segments[2].bpm~=120 or playback.tempo(entry)~=120 then return nil end
    local response=beat+entry.timing/2
    local cue
    for _,item in ipairs(cues) do if item.beat<=response then cue=item end end
    if not cue or cue.beat<segments[2].first or cue.index>1023 then return nil end
    return {index=cue.index,offset_seconds=(response-cue.beat)*60/120,
        source="opening script",phase="Ulala response",alignment_verified=false}
end

function M.binding(entry, buffer, stem)
    if not entry or not entry.raw or #entry.raw<12 or entry.raw:sub(7,8)~="\43\4" then
        return nil,"Music mapping unavailable for this phrase."
    end
    local tail=packets(entry.rest_body or "")
    if not tail then return nil,"Music script layout is not mapped yet." end
    local cue
    for _,p in ipairs(tail) do
        if p.op==0x22 then
            if cue or p.words~=3 or p.args[2]~=0 or p.args[1]>1023 then
                return nil,"Music changes within this phrase are not mapped yet."
            end
            cue=p.args[1]
        elseif p.op==0x18 or p.op==0x19 or (p.op>=0x2c and p.op<=0x2f) then
            return nil,"This phrase's music depends on an unmapped script branch."
        end
    end
    if cue then
        local bpm,source=playback.tempo(entry)
        if source~="chart" then return nil,"The music cue has no supported chart tempo." end
        return {index=cue,offset_seconds=(entry.timing/2)*60/bpm,
            source="phrase script",phase="Ulala response",alignment_verified=false}
    end
    local inherited=opening(entry,buffer,stem)
    if inherited then return inherited end
    return nil,"Inherited level music is not mapped for this phrase yet."
end

function M.read_member(path, index)
    assert(type(index)=="number" and index>=0 and index==math.floor(index),"Invalid music member index")
    local f=assert(io.open(path,"rb"),"Could not open music archive: "..path)
    local ok,result=pcall(function()
        local header=assert(f:read(8),"Missing AFS header")
        assert(#header==8 and header:sub(1,4)=="AFS\0","Not an AFS music archive")
        local count=format.u32(header,4)
        assert(count>0 and count<=10000 and index<count,"Music cue is outside the archive")
        local length=assert(f:seek("end"))
        assert(8+count*8<=length,"Truncated music index")
        assert(f:seek("set",8+index*8))
        local record=assert(f:read(8),"Missing music index record")
        assert(#record==8,"Truncated music index record")
        local offset,size=format.u32(record,0),format.u32(record,4)
        assert(offset>=8+count*8 and size>0 and offset+size<=length,"Music member is outside the archive")
        assert(f:seek("set",offset))
        local data=assert(f:read(size),"Could not read music member")
        assert(#data==size,"Truncated music member")
        return data
    end)
    f:close()
    if not ok then error(result) end
    return result
end

function M.prepare(root, stem, original, preview, plan, buffer, cache)
    assert(stem and stem:match("^r[1-6][1-4]$"),"Invalid music section")
    local binding,reason=M.binding(original,buffer,stem)
    if not binding then return nil,reason end
    if preview.timing~=original.timing then return nil,"Music preview is unavailable after changing phrase length." end
    if plan.bpm~=playback.tempo(original) then return nil,"Use chart BPM to preview matching music." end
    local path=root:gsub("\\","/"):gsub("/+$","").."/"..stem.."music.afs"
    local key=path.."#"..binding.index
    local sample=cache[key]
    if not sample then
        local encoded=M.read_member(path,binding.index)
        local pcm,info=adx.decode(encoded)
        sample={pcm=pcm,info=info};cache[key]=sample
    end
    local rate,channels=sample.info.rate,sample.info.channels
    local range_first,count=playback.sample_window(plan,rate)
    local first=math.floor(binding.offset_seconds*rate+0.5)+range_first
    -- Some shipped clips end one sample before their nominal musical length.
    -- Permit a single zero-padded frame, never loop or shift an arbitrary clip.
    if first<0 or first+count>sample.info.count+1 then return nil,"The selected range extends beyond its music clip." end
    local pcm=sample.pcm:sub(first*channels*2+1,(first+count)*channels*2)
    if #pcm<count*channels*2 then pcm=pcm..string.rep("\0",count*channels*2-#pcm) end
    return {pcm=pcm,info={rate=rate,channels=channels,count=count,duration=count/rate},gain=0.5,
        name=stem.." music cue "..binding.index,phase=binding.phase,source=binding.source,
        offset_seconds=first/rate,alignment_verified=false},"Ulala response music; alignment is derived from the game script."
end

return M
