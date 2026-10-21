local App=require('ui.app')
local project=require('core.project')
local json=require('core.json')
local report=require('core.report')
local rebuild=require('core.rebuild')
local format=require('core.format')
local platform=require('core.platform')
local checks=0
local function check(value,message)checks=checks+1;assert(value,message)end
local function rejects(fn,expected)
    local ok,message=pcall(fn)
    check(not ok and (not expected or tostring(message):find(expected,1,true)),tostring(message))
end
local r=report.load(TEST_GAME_ROOT,1)
local f1,f2=r.files[1]
for _,file in ipairs(r.files) do if file.stem=='r12' and file.is_main then f2=file end end
check(f2 and f1.entries[1].name==f2.entries[1].name,'test covers duplicate phrase names in different files')
local app=App.new();app.game_root=TEST_GAME_ROOT;app.config_path=TEST_SCRATCH..'/project-config.ini'
check(not app:project_unsaved(),'empty editor starts clean')
app:open_report_entry(f1,f1.entries[1])
check(not app:project_unsaved(),'browsing an unchanged phrase is not an unsaved edit')
app.current_work.steps[1].code=4;app:update_draft_from_current()
app.current_work.timing=24;app.current_work.start_delay=6;app.current_work.steps[1].gap=12
app:update_draft_from_current()
app:select_entry(app.entries[2]);app.current_work.steps[1].code=10;app:update_draft_from_current()
app:open_report_entry(f2,f2.entries[1]);app.current_work.steps[1].code=6;app:update_draft_from_current()
check(app:project_unsaved(),'pending edits are detected across files')
local document=app:capture_project()
check(#document.files==2 and #document.files[1].edits==2 and #document.files[2].edits==1,
    'project captures previously visited and current phrases')
check(document.files[1].path=='afs_english/r11_sh.bin','only relative English source paths are stored')
local path=TEST_SCRATCH..'/roundtrip.sc5project'
local ok,message=app:save_project(path);check(ok,message)
check(not app:project_unsaved(),'successful save clears project dirty state')
local f=assert(io.open(path,'rb'));local raw=f:read('*a');f:close()
check(raw:find('"sha256"',1,true) and not raw:find('DGSH',1,true) and #raw<5000,
    'project stores edit data and source hashes, not game binaries')
check(json.encode(json.decode(raw))==json.encode(document),'project JSON survives encoding and decoding')
local fresh=App.new();fresh.game_root=TEST_GAME_ROOT;fresh.config_path=TEST_SCRATCH..'/fresh-config.ini'
fresh:restore_project(fresh:stage_project(path),path)
check(fresh.selected_entry.name=='pd001' and fresh.current_file_name=='r12_sh.bin','selected file/phrase is restored')
check(fresh.current_work.steps[1].code==6,'R12 edit is restored')
check(not fresh:project_unsaved() and fresh.current_dirty,'saved edits are clean projects but remain modified game phrases')
fresh:open_file(f1.path)
check(fresh.current_work and fresh.current_work.steps[1].code==4,'Open restores a previously inactive project file')
fresh:open_file(f1.path)
check(fresh.current_work.steps[1].code==4,'Open of the current file preserves its existing edits')
fresh:open_report_entry(f1,f1.entries[1])
check(fresh.current_work.steps[1].code==4,'R11 edit stays separate from matching R12 name')
fresh:select_entry(fresh.entries[2]);check(fresh.current_work.steps[1].code==10,'second R11 phrase restored')
local mods=assert(fresh:collect_file_mods())
local patched=format.parse(rebuild.apply_mods(fresh.current_buffer,fresh.entries,mods))
check(patched[1].steps[1]==4 and patched[2].steps[1]==10,'reopened project produces both R11 export edits')
check(patched[1].timing==24 and patched[1].start_delay==6 and patched[1].hits[1]==12,
    'reopened project preserves intentional phrase length, start delay, and note gaps through export')
fresh:open_report_entry(f2,f2.entries[1])
patched=format.parse(rebuild.apply_mods(fresh.current_buffer,fresh.entries,assert(fresh:collect_file_mods())))
check(patched[1].steps[1]==6,'reopened project exports R12 independently')

-- Native Windows atomic replacement must overwrite the project, not append.
fresh.current_work.steps[1].code=3;fresh:update_draft_from_current()
check(fresh:project_unsaved(),'further edit becomes unsaved')
ok,message=fresh:save_project(path);check(ok,message)
local second=project.load(path,TEST_GAME_ROOT)
check(second.sessions[2].mods.pd001.steps[1].code==3,'second save atomically replaces the existing project')
check(not fresh:project_unsaved(),'second save clears dirty state')
local original_replace=platform.replace_file
platform.replace_file=function()return nil,'simulated replacement failure'end
fresh.current_work.steps[1].code=5;fresh:update_draft_from_current()
ok,message=fresh:save_project(path)
platform.replace_file=original_replace
check(not ok and message:find('simulated',1,true),'replacement failure reaches the user')
check(fresh:project_unsaved(),'failed save never clears unsaved state')
check(project.load(path,TEST_GAME_ROOT).sessions[2].mods.pd001.steps[1].code==3,'previous save survives a failed replacement')
check(not io.open(path..'.tmp','rb'),'temporary file is cleaned after a failed save')

local before=fresh.current_work
local changed=json.decode(raw);changed.files[2].sha256=string.rep('0',64)
rejects(function()project.restore(json.encode(changed),TEST_GAME_ROOT)end,'Source chart changed')
check(fresh.current_work==before and fresh.current_work.steps[1].code==5,'failed restore cannot alter live edits')
local function bad(change,expected)
    local d=json.decode(raw);change(d)
    rejects(function()project.restore(json.encode(d),TEST_GAME_ROOT)end,expected)
end
bad(function(d)d.files[1].path='../r11_sh.bin'end,'English report charts')
bad(function(d)d.files[1].path='r11_sh.bin'end,'English report charts')
bad(function(d)d.files[1].edits[1].name='not-a-phrase'end,'Missing phrase')
bad(function(d)d.files[1].edits[1].steps[1].code=256 end,'Invalid command')
bad(function(d)d.files[1].edits[1].timing=0 end,'Invalid phrase length')
bad(function(d)d.files[1].edits[1].steps[1].gap=-1 end,'Invalid gap')
bad(function(d)d.files[1].edits[1].anim_indices={999}end,'new_anim_indices')
bad(function(d)d.files[3]=d.files[1]end,'Duplicate chart file')
bad(function(d)d.files[1].edits[2]=d.files[1].edits[1]end,'Duplicate phrase edit')
bad(function(d)d.selection.entry='missing'end,'Saved phrase selection')
bad(function(d)d.language='Japanese'end,'English projects only')
bad(function(d)d.version=999 end,'Unsupported project')
rejects(function()project.restore('{bad json',TEST_GAME_ROOT)end,'JSON decode error')
rejects(function()project.restore(string.rep(' ',project.MAX_BYTES+1),TEST_GAME_ROOT)end,'too large')
rejects(function()project.save(TEST_GAME_ROOT..'/test.sc5project',document,TEST_GAME_ROOT)end,'outside the game')
rejects(function()project.save(TEST_SCRATCH..'/not-a-project.bin',document,TEST_GAME_ROOT)end,'.sc5project')
rejects(function()project.restore(raw,TEST_GAME_ROOT,function()return nil end)end,'Missing English chart')
check(json.decode(json.encode({text='backslash \\ quote "\n café'})).text=='backslash \\ quote "\n café','JSON escaping preserves paths and labels')

check(fresh:request_quit() and fresh.modal.title=='Unsaved project edits','unsaved close is intercepted')
fresh:dismiss_modal('cancel');check(not fresh.modal and fresh.current_work==before,'cancel close preserves the editor')
check(not app:request_quit(),'saved project can close normally')
fresh:prompt_project_open();fresh.modal.input.text=path;fresh:dismiss_modal('open')
check(fresh.modal and fresh.modal.title=='Unsaved project edits','opening another project protects pending edits')
fresh:dismiss_modal('cancel')
check(fresh.current_work==before and fresh.current_work.steps[1].code==5,'cancel project replacement preserves edits')
fresh:prompt_project_open();fresh.modal.input.text=path;fresh:dismiss_modal('open');fresh:dismiss_modal('save')
check(not fresh.modal and fresh.current_work.steps[1].code==5 and not fresh:project_unsaved(),
    'Save first then reopen the same project reads its newly saved data, not a stale snapshot')
print('PASS: '..checks..' project save/reopen, source identity, validation, export, atomic-save failure, and close checks')
