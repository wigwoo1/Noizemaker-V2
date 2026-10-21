-- Versioned edit-only projects. Never deserialize executable Lua or embed game
-- archives. Source hashes bind each set of edits to its exact English binary.
local json=require('core.json')
local format=require('core.format')
local rules=require('core.rules')
local rebuild=require('core.rebuild')
local report=require('core.report')
local platform=require('core.platform')
local M={MAX_BYTES=8*1024*1024}

local function integer(value,low,high,label)
    assert(type(value)=='number' and value==math.floor(value) and value>=low and value<=high,
        'Invalid '..label..' in project.')
    return value
end
local function array(value,max,label)
    assert(type(value)=='table' and #value<=max,'Invalid '..label..' in project.')
    local count=0
    for k in pairs(value) do
        assert(type(k)=='number' and k>=1 and k<=#value and k==math.floor(k),'Invalid '..label..' list.')
        count=count+1
    end
    assert(count==#value,'Incomplete '..label..' list.')
    return value
end
function M.relative(path)
    assert(type(path)=='string' and not path:find('\0',1,true),'Invalid chart path.')
    path=path:gsub('\\','/'):lower()
    local suffix=path:match('^afs_english/r[1-6][1-4]_sh(%d*)%.bin$')
    assert(suffix=='' or suffix=='0' or suffix=='2' or suffix=='20',
        'Projects support English report charts from afs_english only.')
    return path
end
function M.relative_to(root,path)
    root=(root or ''):gsub('\\','/'):gsub('/+$',''):lower()
    path=(path or ''):gsub('\\','/'):lower()
    assert(root~='' and path:sub(1,#root+1)==root..'/',
        'Open an English chart from the selected game installation before saving a project.')
    return M.relative(path:sub(#root+2))
end
function M.hash(data)
    assert(love and love.data and love.data.hash,'Project saving requires the app hash service.')
    return (love.data.hash('sha256',data):gsub('.',function(c)return string.format('%02x',c:byte())end))
end
local function clean_mod(value,entry)
    assert(type(value)=='table','Invalid phrase edit.')
    local work={steps={},anim_indices={},
        timing=integer(value.timing,1,65535,'phrase length'),
        start_delay=integer(value.start_delay,0,65535,'start delay')}
    for i,step in ipairs(array(value.steps,100,'commands')) do
        assert(type(step)=='table','Invalid command in project.')
        work.steps[i]=format.Step.new(integer(step.code,0,255,'command'),integer(step.gap,0,65535,'gap'))
    end
    assert(#work.steps>0,'A project phrase needs at least one command.')
    for i,n in ipairs(array(value.anim_indices,1000,'animation indices')) do
        work.anim_indices[i]=integer(n,0,65535,'animation index')
    end
    if entry then
        local validation=rules.validate_mod(entry,work.steps,work)
        assert(validation.ok,entry.name..': '..table.concat(validation.errors,'; '))
    end
    return work
end

function M.capture(root,sessions,selection,report_number)
    local document={format='sc5-visual-project',version=1,language='English',files={},
        report=integer(report_number or 1,1,6,'report number')}
    local seen={}
    for _,session in ipairs(sessions) do
        local relative=M.relative_to(root,session.current_file_path)
        assert(not seen[relative],'Duplicate chart session.');seen[relative]=true
        local lookup,edits={},{}
        for _,entry in ipairs(session.entries) do lookup[entry.name]=entry end
        local merged={}
        for name,value in pairs(session.mods) do merged[name]=value end
        for name,draft in pairs(session.drafts) do merged[name]=draft.modified and draft or nil end
        local names={};for name in pairs(merged) do names[#names+1]=name end;table.sort(names)
        for _,name in ipairs(names) do
            local entry=assert(lookup[name],'Project edit refers to a missing phrase.')
            local work=clean_mod(merged[name],entry)
            edits[#edits+1]={name=name,steps=work.steps,anim_indices=work.anim_indices,
                timing=work.timing,start_delay=work.start_delay}
        end
        document.files[#document.files+1]={path=relative,sha256=M.hash(session.current_buffer),edits=edits}
    end
    table.sort(document.files,function(a,b)return a.path<b.path end)
    if selection and selection.file then
        document.selection={file=M.relative_to(root,selection.file),entry=selection.entry}
        assert(seen[document.selection.file],'Selected chart is not saved in the project.')
    end
    return document
end

function M.edit_signature(document)
    local files={}
    for _,file in ipairs(document.files) do if #file.edits>0 then files[#files+1]=file end end
    return json.encode(files)
end

local function read(path,limit)
    local f=assert(io.open(path,'rb'),'Could not open '..path)
    local data=f:read(limit and limit+1 or '*a');f:close()
    assert(data and (not limit or #data<=limit),'Project file is too large.')
    return data
end

function M.restore(text,root,reader)
    assert(type(text)=='string' and #text<=M.MAX_BYTES,'Project file is too large.')
    local document=json.decode(text)
    assert(type(document)=='table' and document.format=='sc5-visual-project' and document.version==1,
        'Unsupported project format or version.')
    assert(document.language=='English','This editor opens English projects only.')
    integer(document.report,1,6,'report number')
    root=(root or ''):gsub('\\','/'):gsub('/+$','')
    assert(root~='','Choose the game installation in Settings before opening a project.')
    local sessions,seen={},{}
    for _,file in ipairs(array(document.files,96,'chart files')) do
        assert(type(file)=='table','Invalid chart file record.')
        local relative=M.relative(file.path)
        assert(not seen[relative],'Duplicate chart file in project.');seen[relative]=true
        assert(type(file.sha256)=='string' and #file.sha256==64 and file.sha256:match('^[0-9a-f]+$'),
            'Missing source checksum in project.')
        local path=root..'/'..relative
        local buffer=(reader or read)(path)
        assert(buffer,'Missing English chart: '..relative)
        assert(M.hash(buffer)==file.sha256,'Source chart changed: '..relative..'. Restore the matching game files before reopening this project.')
        local entries=format.parse(buffer)
        local lookup,mods={},{}
        for _,entry in ipairs(entries) do lookup[entry.name]=entry end
        for _,edit in ipairs(array(file.edits,10000,'phrase edits')) do
            assert(type(edit)=='table' and type(edit.name)=='string','Invalid phrase identity.')
            local entry=assert(lookup[edit.name],'Missing phrase: '..edit.name)
            assert(not mods[edit.name],'Duplicate phrase edit: '..edit.name)
            mods[edit.name]=clean_mod(edit,entry)
        end
        -- Exercise rebuilding before committing any restored app state.
        rebuild.apply_mods(buffer,entries,mods)
        sessions[#sessions+1]={current_file_path=path,current_file_name=relative:match('[^/]+$'),
            current_file_dir=root..'/afs_english',current_buffer=buffer,entries=entries,
            entry_lookup=lookup,mods=mods,drafts={},undo_stack={},redo_stack={}}
    end
    if document.selection then
        local selection=document.selection
        assert(type(selection)=='table','Invalid project selection.')
        local relative=M.relative(selection.file)
        selection.file=relative
        local found
        for _,session in ipairs(sessions) do
            if M.relative_to(root,session.current_file_path)==relative then found=session end
        end
        assert(found and found.entry_lookup[selection.entry],'Saved phrase selection is missing.')
    end
    return {document=document,sessions=sessions}
end
function M.load(path,root,reader)
    return M.restore(read(path,M.MAX_BYTES),root,reader)
end

function M.save(path,document,root)
    assert(type(path)=='string' and path:lower():match('%.sc5project$'),'Use a .sc5project filename.')
    local allowed,reason=report.export_path_allowed(root,path)
    assert(allowed,reason)
    local text=json.encode(document)..'\n'
    assert(#text<=M.MAX_BYTES,'Project file is too large.')
    local temporary=path..'.tmp'
    local f=assert(io.open(temporary,'wb'),'Could not create project. Check the destination folder.')
    local ok,message=f:write(text)
    local closed,close_error=f:close()
    if not ok or not closed then os.remove(temporary);error(message or close_error or 'Could not finish project save.') end
    local replaced,replace_error=platform.replace_file(temporary,path)
    if not replaced then os.remove(temporary);error(replace_error or 'Could not replace project. Previous save is unchanged.') end
    return text
end

return M
