local App=require('ui.app')
local exporter=require('core.export')
local project=require('core.project')
local report=require('core.report')
local format=require('core.format')
local json=require('core.json')
local platform=require('core.platform')
local rules=require('core.rules')
local checks=0
local function check(v,message)checks=checks+1;assert(v,message)end
local function reject(fn,expected)
    local ok,message=pcall(fn)
    check(not ok and tostring(message):find(expected,1,true),tostring(message))
end
local function read(path)local f=assert(io.open(path,'rb'));local s=f:read('*a');f:close();return s end
local function write(path,data)local f=assert(io.open(path,'wb'));assert(f:write(data));f:close()end
local function no_stage()
    for _,name in ipairs(platform.list_directories(TEST_SCRATCH)) do
        check(not name:find('.sc5-export-staging-',1,true),'failed export cleans its own staging folder')
    end
end
local r=report.load(TEST_GAME_ROOT,1)
local f1,f2,variant=r.files[1]
for _,file in ipairs(r.files) do
    if file.stem=='r12' and file.is_main then f2=file end
    if file.relative_path=='afs_english/r11_sh2.bin' then variant=file end
end
local app=App.new();app.game_root=TEST_GAME_ROOT;app.config_path=TEST_SCRATCH..'/export-config.ini'
app:open_report_entry(f1,f1.entries[1]);app.current_work.steps[1].code=4;app:update_draft_from_current()
app:select_entry(app.entries[2]);app.current_work.steps[1].code=10;app:update_draft_from_current()
app:open_report_entry(variant,variant.entries[1]);app.current_work.steps[1].code=4;app:update_draft_from_current()
app:open_report_entry(f2,f2.entries[1]);app.current_work.steps[1].code=6;app:update_draft_from_current()
local plan=app:prepare_report_export(1)
check(#plan.files==3,'report export includes every edited main/variant file')
check(#plan.manifest.files[1].phrases==2,'manifest includes edits to previously visited phrases')
check(plan.manifest.in_game_verified==false,'binary checks do not claim in-game verification')
check(plan.files[2].path=='afs_english/r11_sh2.bin','file variant identity remains distinct')
check(plan.files[3].path=='afs_english/r12_sh.bin','duplicate phrase IDs keep their source file identity')
local destination=TEST_SCRATCH..'/report-1-export'
local work,undo=app.current_work,app.undo_stack
local ok,result=app:export_report(destination,1);check(ok,result)
check(result.path==destination and result.count==3,'app returns completed export folder and affected count')
check(app.current_work==work and app.undo_stack==undo and app:project_unsaved(),
    'export preserves editor/undo state and does not pretend to save the project')
local manifest=json.decode(read(destination..'/export-manifest.json'))
check(manifest.report==1 and manifest.language=='English' and #manifest.files==3,'manifest identifies report and English outputs')
for _,file in ipairs(manifest.files) do
    local binary=read(destination..'/'..file.path)
    check(#binary==file.bytes and project.hash(binary)==file.output_sha256,'manifest output size and checksum match disk')
    check(project.hash(read(TEST_GAME_ROOT..'/'..file.path))==file.source_sha256,'manifest source checksum matches installed original')
end
local original_export=read(destination..'/afs_english/r11_sh.bin')
local p=format.parse(original_export)
check(p[1].steps[1]==4 and p[2].steps[1]==10,'batch export retains both edited R11 phrases')
check(format.parse(read(destination..'/afs_english/r11_sh2.bin'))[1].steps[1]==4,'batch export retains variant edit')
check(format.parse(read(destination..'/afs_english/r12_sh.bin'))[1].steps[1]==6,'batch export retains R12 edit')
check(read(destination..'/READ-ME.txt'):find('in-game verification is pending',1,true),'export explains its verification limit')
check(#platform.list_files_recursive(destination)==5,'only affected binaries, manifest, and readme are written')
reject(function()exporter.write(plan,destination,TEST_GAME_ROOT)end,'already exists')
check(read(destination..'/afs_english/r11_sh.bin')==original_export,'existing export is never overwritten')
reject(function()exporter.write(plan,TEST_GAME_ROOT..'/bad-export',TEST_GAME_ROOT)end,'outside the game')
reject(function()exporter.write(plan,TEST_GAME_ROOT..'/afs_english/../bad-export',TEST_GAME_ROOT)end,'outside the game')
reject(function()exporter.write(plan,'relative-export',TEST_GAME_ROOT)end,'full file path')
reject(function()exporter.write(plan,TEST_SCRATCH..'/missing-parent/child',TEST_GAME_ROOT)end,'existing folder')
reject(function()exporter.prepare(app:capture_project(),TEST_GAME_ROOT,6)end,'No edited English charts')

-- A source mismatch is tested with an alternate read, never by changing game files.
reject(function()exporter.prepare(app:capture_project(),TEST_GAME_ROOT,1,function(path)return read(path)..'changed'end)end,'Source chart changed')
local source_path=plan.files[1].source_path
local simulated=TEST_SCRATCH..'/changed-source.bin';write(simulated,'changed source')
plan.files[1].source_path=simulated
reject(function()exporter.write(plan,TEST_SCRATCH..'/changed-source-export',TEST_GAME_ROOT)end,'Source chart changed')
plan.files[1].source_path=source_path
check(not platform.directory_exists(TEST_SCRATCH..'/changed-source-export'),'source failure creates no destination folder')

local rename=platform.rename_new
platform.rename_new=function()return nil,'simulated finish failure'end
reject(function()exporter.write(plan,TEST_SCRATCH..'/finish-failure',TEST_GAME_ROOT)end,'simulated finish failure')
platform.rename_new=rename
check(not platform.directory_exists(TEST_SCRATCH..'/finish-failure'),'failed commit never leaves a completed export')
no_stage()
local original_open=io.open
io.open=function(path,mode)
    if mode=='wb' and path:find('/afs_english/r12_sh.bin',1,true) then return nil,'simulated disk write failure' end
    return original_open(path,mode)
end
local success,message=pcall(exporter.write,plan,TEST_SCRATCH..'/write-failure',TEST_GAME_ROOT)
io.open=original_open
check(not success and tostring(message):find('Could not create export file',1,true),'failed file write stops the bundle')
check(not platform.directory_exists(TEST_SCRATCH..'/write-failure'),'partial file write creates no completed folder')
no_stage()
check(read(destination..'/afs_english/r11_sh.bin')==original_export,'failures preserve the earlier successful export')

-- Negative verification: changing an untouched phrase is rejected even when
-- the output is still parseable.
local original=f1.entries[3]
local at=original.dp+8
local bad=original_export:sub(1,at)..string.char(3)..original_export:sub(at+2)
local current=project.restore(json.encode(app:capture_project(1)),TEST_GAME_ROOT).sessions[1]
reject(function()exporter.verify(f1.buffer,f1.entries,bad,current.mods)end,'untouched phrase')

local other=report.load(TEST_GAME_ROOT,2).files[1]
app:open_report_entry(other,other.entries[1]);app.current_work.steps[1].code=999;app:update_draft_from_current()
check(#app:prepare_report_export(1).files==3,'another report with an invalid draft does not block this report')
check(app:export_report_number()==2,'editor export uses the active chart report')
app.active_view='reports';app.reports_tab.number=1
check(app:export_report_number()==1,'report browser export uses the selected report')
check(not pcall(app.prepare_report_export,app,2),'invalid target-report edits block export')
local coverage={}
for number=1,6 do
    local level=report.load(TEST_GAME_ROOT,number)
    local editor=App.new();editor.game_root=TEST_GAME_ROOT;editor.config_path=TEST_SCRATCH..'/coverage-config.ini'
    local phrases={}
    for _,file in ipairs(level.files) do
        local candidate,code
        for _,entry in ipairs(file.entries) do
            if entry.timing>0 and #entry.steps<=100 then
                for _,replacement in ipairs({3,4,5,6}) do
                    if entry.steps[1]~=replacement then
                        local steps=entry:as_step_list();steps[1].code=replacement
                        local validation=rules.validate_mod(entry,steps,{timing=entry.timing,start_delay=entry.start_delay,anim_indices=entry:get_anim_indices()})
                        if validation.ok then candidate,code=entry,replacement;break end
                    end
                end
            end
            if candidate then break end
        end
        check(candidate~=nil,'a supported representative edit exists for '..file.relative_path)
        editor:open_report_entry(file,candidate)
        editor.current_work.steps[1].code=code;editor:update_draft_from_current()
        phrases[file.relative_path]={entry=candidate.name,replacement=code}
    end
    local full=editor:prepare_report_export(number)
    check(#full.files==#level.files,'all changed files in Report '..number..' are included')
    local path=TEST_SCRATCH..'/coverage-report-'..number
    exporter.write(full,path,TEST_GAME_ROOT)
    coverage[#coverage+1]={report=number,files=full.manifest.files,representative_edits=phrases,in_game_verified=false}
end
EXPORT_COVERAGE_JSON=json.encode(coverage)
print('PASS: '..checks..' report export, identity, manifest, preservation, scope, failure cleanup, and source checks')
