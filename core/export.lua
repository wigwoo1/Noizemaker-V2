-- Export changed English charts for one report. Installed game files are read
-- only; a staged bundle becomes visible only after every file passes checks.
local project=require('core.project')
local json=require('core.json')
local format=require('core.format')
local rebuild=require('core.rebuild')
local report=require('core.report')
local platform=require('core.platform')
local M={}
local serial=0

local function read(path)
    local f=assert(io.open(path,'rb'),'Could not read '..path)
    local data=f:read('*a');f:close();return assert(data,'Could not read '..path)
end
local function write(path,data)
    local f=assert(io.open(path,'wb'),'Could not create export file: '..path)
    local ok,message=f:write(data)
    local closed,close_error=f:close()
    assert(ok and closed,message or close_error or 'Could not finish export file.')
end
local function exists(path)
    if platform.directory_exists(path) then return true end
    local f=io.open(path,'rb');if f then f:close();return true end
    return false
end

function M.verify(source,entries,output,mods)
    local parsed=format.parse(output)
    assert(#parsed==#entries,'Export changed the number of phrases.')
    for i,entry in ipairs(entries) do
        local result=parsed[i]
        assert(result.name==entry.name,'Export changed a phrase identity.')
        local mod=mods[entry.name]
        if mod then
            assert(result.timing==mod.timing and format.u16(result.raw,10)==mod.timing,
                'Export phrase length mismatch: '..entry.name)
            assert(result.start_delay==mod.start_delay,'Export start delay mismatch: '..entry.name)
            assert(format.u16(result.raw,8)==format.u16(entry.raw,8),'Export meter changed: '..entry.name)
            assert(#result.steps==#mod.steps,'Export command count mismatch: '..entry.name)
            for index,step in ipairs(mod.steps) do
                assert(result.steps[index]==step.code,'Export command mismatch: '..entry.name)
                if index<#mod.steps then assert(result.hits[index]==step.gap,'Export gap mismatch: '..entry.name) end
            end
        else
            assert(output:sub(result.dp+1,result.np)==source:sub(entry.dp+1,entry.np),
                'Export changed an untouched phrase: '..entry.name)
        end
    end
    return true
end

function M.prepare(document,root,number,reader)
    assert(type(number)=='number' and number==math.floor(number) and number>=1 and number<=6,'Choose Report 1 to 6.')
    local scoped={format=document.format,version=document.version,language=document.language,report=number,files={}}
    for _,file in ipairs(document.files) do
        local relative=project.relative(file.path)
        if relative:match('^afs_english/r'..number..'[1-4]_sh') and #file.edits>0 then
            scoped.files[#scoped.files+1]=file
        end
    end
    assert(#scoped.files>0,'No edited English charts to export for Report '..number..'.')
    local restored=project.restore(json.encode(scoped),root,reader)
    local plan={report=number,files={},manifest={format='sc5-english-report-export',version=1,
        language='English',report=number,in_game_verified=false,files={}}}
    for _,session in ipairs(restored.sessions) do
        local binary=rebuild.apply_mods(session.current_buffer,session.entries,session.mods)
        M.verify(session.current_buffer,session.entries,binary,session.mods)
        local relative=project.relative_to(root,session.current_file_path)
        local phrases={}
        for name in pairs(session.mods) do phrases[#phrases+1]=name end;table.sort(phrases)
        local metadata={path=relative,source_sha256=project.hash(session.current_buffer),
            output_sha256=project.hash(binary),bytes=#binary,phrases=phrases}
        plan.files[#plan.files+1]={path=relative,binary=binary,source_path=session.current_file_path,metadata=metadata}
        plan.manifest.files[#plan.manifest.files+1]=metadata
    end
    table.sort(plan.files,function(a,b)return a.path<b.path end)
    table.sort(plan.manifest.files,function(a,b)return a.path<b.path end)
    return plan
end

function M.destination(root,path)
    assert(type(path)=='string' and not path:find('\0',1,true),'Choose a valid export folder.')
    path=path:gsub('\\','/'):gsub('/+$','')
    local allowed,reason=report.export_path_allowed(root,path)
    assert(allowed,reason)
    local parent=path:match('^(.*)/[^/]+$')
    assert(parent and platform.directory_exists(parent),'Choose a new folder inside an existing folder.')
    assert(not exists(path),'That export folder already exists. Choose a new folder name.')
    return path,parent
end

function M.write(plan,destination,root)
    local target,parent=M.destination(root,destination)
    assert(#plan.files>0,'There are no files to export.')
    -- Recheck sources immediately before writing, including a plan retained
    -- while the user was choosing the destination.
    for _,file in ipairs(plan.files) do
        project.relative(file.path)
        assert(project.hash(read(file.source_path))==file.metadata.source_sha256,
            'Source chart changed: '..file.path..'. Export stopped; your drafts are unchanged.')
        assert(project.hash(file.binary)==file.metadata.output_sha256,'Export data changed before writing.')
    end
    local stage
    for attempt=1,20 do
        serial=serial+1
        local candidate=parent..'/.sc5-export-staging-'..os.time()..'-'..serial
        if platform.create_dir_exclusive(candidate) then stage=candidate;break end
    end
    assert(stage,'Could not create an export folder. Check folder permissions.')
    local paths,created_data={},false
    local ok,message=pcall(function()
        assert(platform.create_dir_exclusive(stage..'/afs_english'),'Could not create the English output folder.')
        created_data=true
        local function output(relative,data)
            local path=stage..'/'..relative;paths[#paths+1]=path
            write(path,data)
            assert(read(path)==data,'Export file read-back failed: '..relative)
        end
        for _,file in ipairs(plan.files) do output(file.path,file.binary) end
        output('export-manifest.json',json.encode(plan.manifest)..'\n')
        local lines={'Space Channel 5 Part 2 - English Report '..plan.report..' export','',
            'Changed files only. Installed game files were not modified.',
            'Keep your .sc5project file to continue editing.',
            'These exports have passed rebuild/reparse checks; in-game verification is pending.','',
            'Affected English files:'}
        for _,file in ipairs(plan.files) do
            lines[#lines+1]=file.path..' | phrases: '..table.concat(file.metadata.phrases,', ')
        end
        output('READ-ME.txt',table.concat(lines,'\r\n')..'\r\n')
        local moved,move_error=platform.rename_new(stage,target)
        assert(moved,move_error or 'Could not finish export.')
    end)
    if not ok then
        -- Only remove known files from the exclusively created staging folder.
        -- Never recursively delete a user-selected path or prior export.
        for _,path in ipairs(paths) do os.remove(path) end
        if created_data then platform.remove_empty_dir(stage..'/afs_english') end
        local cleaned=platform.remove_empty_dir(stage)
        error(tostring(message)..(cleaned and '' or (' Incomplete staging files remain at '..stage)))
    end
    return target,plan.manifest
end

return M
