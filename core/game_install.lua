-- Explicit installation only. Export preparation/verification stays in core.export.
-- Content-addressed preimages and a persisted pending transaction support recovery.
local project=require('core.project')
local json=require('core.json')
local platform=require('core.platform')
local report=require('core.report')
local format=require('core.format')
local M={}
local serial=0
local function normalized(path)return tostring(path or ''):gsub('\\','/'):gsub('/+$',''):lower()end
local function read(path)local f=io.open(path,'rb');if not f then return nil end;local data=f:read('*a');f:close();return data end
local function write(path,data)
    local f=assert(io.open(path,'wb'),'Cannot write '..path..'. Check folder permissions.')
    local ok,err=f:write(data);local closed=f:close();assert(ok and closed,err or 'Could not finish writing '..path)
end
local function digest(data)return project.hash(data)end
local function hash_valid(value)return type(value)=='string' and #value==64 and value:match('^[0-9a-f]+$')end
local function records(files)
    assert(type(files)=='table','Invalid game edit records.')
    for path,item in pairs(files) do
        project.relative(path)
        assert(type(item)=='table' and hash_valid(item.source_sha256) and hash_valid(item.installed_sha256),'Invalid game edit checksum.')
    end
end
local function load(root,store)
    local raw=read(store..'/state.json')
    local state=raw and json.decode(raw) or {version=1,root=normalized(root),files={}}
    assert(state.version==1 and state.root==normalized(root),'This backup belongs to a different game installation.')
    records(state.files)
    if state.pending then
        records(state.pending.before_files)
        for _,file in ipairs(state.pending.files) do
            project.relative(file.path);assert(hash_valid(file.before_sha256) and hash_valid(file.output_sha256),'Invalid pending game edit.')
        end
    end
    return state
end
local function save(store,state)
    assert(platform.ensure_dir(store),'Could not create the game backup folder.')
    local temporary=store..'/state.json.tmp'
    write(temporary,json.encode(state))
    local ok,err=platform.replace_file(temporary,store..'/state.json')
    if not ok then os.remove(temporary);error(err) end
end
local function object(store,hash)
    assert(hash_valid(hash))
    local data=assert(read(store..'/objects/'..hash..'.bin'),'A required game backup is missing.')
    assert(digest(data)==hash,'A game backup checksum changed.');return data
end
local function keep(store,data)
    local hash=digest(data);local path=store..'/objects/'..hash..'.bin'
    assert(platform.ensure_dir(store..'/objects'),'Could not create game backups.')
    local existing=read(path)
    if existing then assert(existing==data,'Backup contents changed.');return hash end
    write(path,data);assert(read(path)==data,'Game backup verification failed.');return hash
end
local function stopped(root)
    local running,err=platform.game_running(root..'/Space Channel 5 Part 2.exe')
    assert(running~=nil,err)
    assert(not running,'Close Space Channel 5 Part 2 before applying or restoring game files, then try again.')
end
local function outside(root,store)
    assert(normalized(root)~='','Choose the game installation first.')
    local allowed,reason=report.export_path_allowed(root,store..'/state.json');assert(allowed,reason)
end
function M.read_source(root,store,path)
    local data=read(path);if not data then return nil end
    local ok,relative=pcall(project.relative_to,root,path)
    if not ok then return data end
    local state=load(root,store);local item=state.files[relative]
    if not item then return data end
    local hash=digest(data);local accepted=hash==item.installed_sha256 or hash==item.source_sha256
    if state.pending then for _,file in ipairs(state.pending.files) do
        if file.path==relative and (hash==file.before_sha256 or hash==file.output_sha256) then accepted=true end
    end end
    if accepted then return object(store,item.source_sha256) end
    -- An external change is a new source; never hide it with an old backup.
    return data
end
function M.prepare(root,store,export_plan)
    outside(root,store);stopped(root)
    local state=load(root,store)
    assert(not state.pending,'A previous Apply was interrupted. Use Project > Restore game files to recover it first.')
    local plan={root=root,store=store,report=export_plan.report,files={},phrases=0}
    local seen={}
    for _,file in ipairs(export_plan.files) do
        local path=project.relative(file.path)
        assert(report.belongs(path,plan.report) and not seen[path],'Apply scope contains an unrelated or duplicate chart.');seen[path]=true
        assert(project.relative_to(root,file.source_path)==path,'Apply target differs from the selected game source.')
        local before=assert(read(root..'/'..path),'Game chart is missing: '..path)
        local source=assert(M.read_source(root,store,root..'/'..path))
        local source_hash=digest(source);local before_hash=digest(before)
        assert(source_hash==file.metadata.source_sha256,'Source changed: '..path..'. Reopen the matching project before applying.')
        local prior=state.files[path]
        assert(before_hash==source_hash or (prior and prior.source_sha256==source_hash and prior.installed_sha256==before_hash),
            'Another program changed '..path..'. No files were applied.')
        assert(digest(file.binary)==file.metadata.output_sha256,'Prepared game output changed.')
        if before~=file.binary then
            -- Count changes against what is installed, including edits undone
            -- back to the baseline. Unchanged visited files need no replacement.
            local previous= format.parse(before)
            local desired= format.parse(file.binary)
            assert(#previous==#desired,'Installed phrase identities changed.')
            for i,entry in ipairs(previous) do
                local target=desired[i]
                assert(entry.name==target.name,'Installed phrase identity changed.')
                if before:sub(entry.dp+1,entry.np)~=file.binary:sub(target.dp+1,target.np) then
                    plan.phrases=plan.phrases+1
                end
            end
            plan.files[#plan.files+1]={path=path,binary=file.binary,source=source,before=before,
                before_sha256=before_hash,output_sha256=digest(file.binary),source_sha256=source_hash}
        end
    end
    assert(#plan.files>0,'No changed sequences to apply.');return plan
end
local function replace(path,data,tag)
    local temporary=path..'.noizemaker-'..tag
    assert(not read(temporary),'A game edit temporary file already exists.')
    local ok,err=pcall(function()
        write(temporary,data);assert(read(temporary)==data,'Staged game file differs from the prepared output.')
        local moved,reason=platform.replace_file(temporary,path);assert(moved,reason)
        assert(read(path)==data,'Installed game file verification failed.')
    end)
    os.remove(temporary);assert(ok,err)
end
function M.recover(root,store)
    outside(root,store);stopped(root)
    local state=load(root,store);if not state.pending then return false end
    -- Check every live target before restoring any of them.
    for _,file in ipairs(state.pending.files) do
        local data=assert(read(root..'/'..file.path),'A pending game file is missing.')
        local hash=digest(data)
        assert(hash==file.before_sha256 or hash==file.output_sha256,'An interrupted Apply target was changed externally: '..file.path..'. Backups remain in '..store)
        object(store,file.before_sha256)
    end
    for _,file in ipairs(state.pending.files) do replace(root..'/'..file.path,object(store,file.before_sha256),'recover') end
    state.files=state.pending.before_files;state.pending=nil;save(store,state);return true
end
function M.install(plan)
    outside(plan.root,plan.store);stopped(plan.root)
    local state=load(plan.root,plan.store);assert(not state.pending,'Recover the interrupted Apply first.')
    local before_files=json.decode(json.encode(state.files));local pending={before_files=before_files,files={}}
    -- All originals/preimages are verified and persisted before touching the game.
    for _,file in ipairs(plan.files) do
        project.relative(file.path)
        assert(read(plan.root..'/'..file.path)==file.before,'Game file changed after review: '..file.path)
        assert(digest(file.binary)==file.output_sha256 and digest(file.source)==file.source_sha256,'Apply plan changed after review.')
        keep(plan.store,file.before);keep(plan.store,file.source)
        state.files[file.path]={source_sha256=file.source_sha256,installed_sha256=file.output_sha256}
        pending.files[#pending.files+1]={path=file.path,before_sha256=file.before_sha256,output_sha256=file.output_sha256}
    end
    state.pending=pending;save(plan.store,state)
    serial=serial+1;local tag=tostring(os.time())..'-'..serial
    local ok,err=pcall(function()
        for _,file in ipairs(plan.files) do
            assert(read(plan.root..'/'..file.path)==file.before,'Game file changed during Apply: '..file.path)
            replace(plan.root..'/'..file.path,file.binary,tag)
        end
        state.pending=nil;save(plan.store,state)
    end)
    if not ok then
        local recovered,why=pcall(M.recover,plan.root,plan.store)
        error(tostring(err)..(recovered and '\nPrevious game files restored.' or '\nRecovery is pending: '..tostring(why)))
    end
    return {files=#plan.files,phrases=plan.phrases,backup=plan.store}
end
function M.restore_plan(root,store,number)
    outside(root,store);stopped(root)
    local state=load(root,store);assert(not state.pending,'Recover the interrupted Apply first.')
    local plan={root=root,store=store,report=number,files={},phrases=0}
    for path,item in pairs(state.files) do if report.belongs(path,number) then
        local before=assert(read(root..'/'..path));local hash=digest(before)
        assert(hash==item.installed_sha256 or hash==item.source_sha256,'Game file changed outside Noizemaker: '..path)
        local original=object(store,item.source_sha256)
        if before~=original then plan.files[#plan.files+1]={path=path,binary=original,source=original,before=before,
            before_sha256=hash,output_sha256=item.source_sha256,source_sha256=item.source_sha256} end
    end end
    assert(#plan.files>0,'No applied game files to restore for '..report.title(number)..'.');return plan
end
function M.pending(root,store)return load(root,store).pending end
return M
