local report=require('core.report')
local project=require('core.project')
local exporter=require('core.export')
local rebuild=require('core.rebuild')
local format=require('core.format')
local json=require('core.json')
local dance=require('core.dance')
local App=require('ui.app')
local checks=0
local function check(value,message)checks=checks+1;assert(value,message)end
local calls={}
local function read(path)
    calls[#calls+1]=path
    local f=io.open(path,'rb');if not f then return nil end
    local data=f:read('*a');f:close();return data
end
local mode=report.load(TEST_GAME_ROOT,'dance',read)
local file=mode.files[1]
check(#calls==1 and calls[1]==TEST_GAME_ROOT..'/r01_sh.bin','explicit shared source; no English-folder or report-root fallback')
check(mode.mode_id=='ulala-dance' and mode.title=="Ulala's Dance" and #mode.cpu_route==200,'explicit mode identity and one source-bound recorded run')
check(#file.entries==200 and #report.rows(mode,false)==100 and #report.rows(mode,true)==200,'all stored branches accessible')
check(file.dance_source_checked and file.shared_source and file.language=='English','source annotations are checksum-bound')
check(#report.rows(mode,false,'q0911')==1 and report.rows(mode,false,'q0911')[1].entry.name=='pd0909','question search reaches the actual shared chart')
check(#report.rows(mode,false,'Set 9 phrase 11')==1,'friendly position search finds shared uses')
local by_name={};for _,entry in ipairs(file.entries) do by_name[entry.name]=entry end
check(by_name.pd0909.dance.label:find('9, 11',1,true) and #by_name.pd0909.dance.uses==2,'shared edit effects visible')
check(by_name.pd0911.dance.label:find('no question link',1,true),'stored unreferenced alternative is honest')
check(rebuild.apply_mods(file.buffer,file.entries,{})==file.buffer,'unchanged shared chart round-trip is byte identical')
local changed=report.load(TEST_GAME_ROOT,'dance',function(path)return read(path)..'changed' end)
check(not changed.files[1].dance_source_checked and not changed.files[1].entries[1].dance.uses,'unknown source cannot borrow question links')
check(not pcall(project.relative,'r11_sh.bin') and not pcall(project.relative,'r02_sh.bin'),'only the proven shared root source is allowed')
check(project.relative('R01_SH.BIN')=='r01_sh.bin','shared source has one canonical identity')
local groups=require('ui.tree').build_groups(file.entries,file.path,{}, {})
check(#groups==10 and groups[1].label=='Set 1','readable sidebar set groups')
local bank=require('core.game_audio').command_bank(TEST_GAME_ROOT,'r01')
check(bank.language=='English' and not bank.shared_source and bank.path:find('r0_sound_resource.bin',1,true),'own English mode bank; no Japanese or Report 1 fallback')
local preview=require('core.playback').plan(file.entries[1],nil,nil,nil,'r01')
check(preview.warnings[1]:find('provisional standard English',1,true),'unresolved preview scope is explicit')
local app=App.new();app.game_root=TEST_GAME_ROOT;app.config_path=TEST_SCRATCH..'/dance.ini'
app:load_report('dance');app:open_report_entry(file,file.entries[1])
local old=app.current_work.steps[1].code
check(app:replace_command(1,old==4 and 5 or 4),'mode command replacement')
local selected=app.current_work.steps[1].code
app:load_report(1)
local r1=app.reports_tab.report.files[1]
app:open_report_entry(r1,r1.entries[1]);check(app:replace_command(1,4),'mixed report edit')
app:load_report('dance');app:open_report_entry(file,file.entries[1])
check(app.current_work.steps[1].code==selected,'mode draft preserved across reports')
local document=app:capture_project()
check(document.report=='dance' and document.mode=='ulala-dance' and #document.files==2,'mode identity and mixed sessions persist')
local path=TEST_SCRATCH..'/ulala.sc5project'
check(app:save_project(path),'real project save')
local other=App.new();other.game_root=TEST_GAME_ROOT;other.config_path=TEST_SCRATCH..'/other.ini'
other:restore_project(other:stage_project(path),path)
check(other.reports_tab.number=='dance' and other.current_file_name=='r01_sh.bin','mode and selection reopen')
check(other.current_work.steps[1].code==selected and not other:project_unsaved(),'reopened edit is exact and saved')
local bad=json.decode(json.encode(document));bad.mode=nil
check(not pcall(project.restore,json.encode(bad),TEST_GAME_ROOT),'unidentified mode document rejected')
local plan=other:prepare_report_export('dance')
check(#plan.files==1 and plan.files[1].path=='r01_sh.bin' and plan.manifest.mode=='ulala-dance','mode export has exact shared file scope')
check(plan.manifest.report==nil and not plan.manifest.in_game_verified,'mode manifest is explicit and honest')
check(exporter.verify(file.buffer,file.entries,plan.files[1].binary,other.mods),'all untouched entries and edited timing survive reparse')
check(not pcall(exporter.destination,TEST_GAME_ROOT,TEST_GAME_ROOT..'/dance-export'),'game-folder output forbidden')
local ok,result=other:export_report(TEST_SCRATCH..'/dance-bundle','dance')
check(ok,result)
local output=assert(read(TEST_SCRATCH..'/dance-bundle/r01_sh.bin'))
check(project.hash(output)==result.manifest.files[1].output_sha256,'export exact read-back hash')
check(not require('core.platform').directory_exists(TEST_SCRATCH..'/dance-bundle/afs_english'),'shared-mode export has no misleading English subfolder')
local original=project.hash(file.buffer)
check(project.hash(read(file.path))==original,'installed shared source unchanged')
print('PASS: '..checks..' Dance import/branch/search/source guards, own English bank, mixed project save/reopen and safe shared-file export checks')
