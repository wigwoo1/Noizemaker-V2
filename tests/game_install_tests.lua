local App=require('ui.app')
local report=require('core.report')
local install=require('core.game_install')
local platform=require('core.platform')
local format=require('core.format')
local function read(path)local f=assert(io.open(path,'rb'));local v=f:read('*a');f:close();return v end
local function write(path,data)local f=assert(io.open(path,'wb'));assert(f:write(data));f:close()end
local root=TEST_SCRATCH..'/game';local store=TEST_SCRATCH..'/install'
assert(platform.ensure_dir(root..'/afs_english'))
for _,path in ipairs({'afs_english/r11_sh.bin','afs_english/r12_sh.bin','afs_english/r21_sh.bin','r01_sh.bin'}) do
    write(root..'/'..path,read(TEST_GAME_ROOT..'/'..path))
end
write(root..'/afs_english/r01_sh.bin','do not change the unused English-folder Dance copy')
local one=report.load(root,1);local two=report.load(root,2)
local app=App.new();app.game_root=root;app.install_base=store;app.config_path=TEST_SCRATCH..'/install.ini';app:resize(960,600)
local a,b=one.files[1],one.files[2];local originalA,originalB=read(a.path),read(b.path)
app:open_report_entry(a,a.entries[1]);app:replace_command(1,4)
app:select_entry(app.entries[2]);local changedB=app.current_work.steps[1].code==5 and 4 or 5;assert(app:replace_command(1,changedB))
app:open_report_entry(b,b.entries[1]);local changedC=app.current_work.steps[1].code==6 and 4 or 6;assert(app:replace_command(1,changedC))
app:open_report_entry(two.files[1],two.files[1].entries[1]);app:replace_command(1,4)
local outside=read(two.files[1].path)
app:open_report_entry(a,a.entries[1]);app.view_transition=nil
local work,undo=app.current_work,app.undo_stack
local plan=app:prepare_game_apply(true)
assert(plan.report==1 and #plan.files==2 and plan.phrases==3,'Apply scope/count: '..tostring(plan.report)..' / '..#plan.files..' / '..plan.phrases)
assert(read(a.path)==originalA and read(b.path)==originalB and not platform.directory_exists(store),'Review preparation never writes game/backups')
local running=platform.game_running;platform.game_running=function()return true end
assert(not pcall(install.install,plan),'Running game blocks Apply')
platform.game_running=running
local result=install.install(plan);assert(result.files==2 and result.phrases==3)
assert(format.parse(read(a.path))[1].steps[1]==4 and format.parse(read(a.path))[2].steps[1]==changedB)
assert(format.parse(read(b.path))[1].steps[1]==changedC and read(two.files[1].path)==outside,'Other reports remain unchanged')
assert(app.current_work==work and app.undo_stack==undo and app.current_work.steps[1].code==4)
assert(app:chart_source(a.path)==originalA and app:chart_source(b.path)==originalB,'Installed outputs retain verified original editor sources')
local path=TEST_SCRATCH..'/installed.sc5project';assert(app:save_project(path))
local fresh=App.new();fresh.game_root=root;fresh.install_base=store;fresh.config_path=TEST_SCRATCH..'/fresh-install.ini'
fresh:restore_project(fresh:stage_project(path),path)
assert(fresh.current_work.steps[1].code==4,'Saved project reopens after installation')
app:replace_command(1,3)
local second=app:prepare_game_apply(false);assert(#second.files==1 and second.files[1].path=='afs_english/r11_sh.bin')
install.install(second);assert(format.parse(read(a.path))[1].steps[1]==3 and format.parse(read(b.path))[1].steps[1]==changedC)
app:undo();install.install(app:prepare_game_apply(false));assert(format.parse(read(a.path))[1].steps[1]==4)
local exported,bundle=app:export_report(TEST_SCRATCH..'/after-install-export',1)
assert(exported,tostring(bundle))
assert(read(TEST_SCRATCH..'/after-install-export/afs_english/r11_sh.bin')==read(a.path),'Export still works after Apply')
app:replace_command(1,a.entries[1].steps[1])
local reverted=app:prepare_game_apply(false)
assert(#reverted.files==1 and reverted.phrases==1,'One reverted installed phrase counts as one change')
install.install(reverted)
assert(format.parse(read(a.path))[1].steps[1]==a.entries[1].steps[1] and format.parse(read(a.path))[2].steps[1]==changedB,'Partial revert preserves other installed edits')
app:select_entry(app.entries[2]);app:replace_command(1,a.entries[2].steps[1])
local all_reverted=app:prepare_game_apply(true)
assert(#all_reverted.files==1 and all_reverted.phrases==1,'A fully reverted file is included; unchanged installed files are skipped')
install.install(all_reverted)
assert(read(a.path)==originalA and format.parse(read(b.path))[1].steps[1]==changedC)
assert(not pcall(app.prepare_game_apply,app,true),'No-op Apply never rewrites already matching game files')
app:select_entry(app.entries[1]);app:replace_command(1,4)
app:select_entry(app.entries[2]);app:replace_command(1,changedB)
app:select_entry(app.entries[1]);install.install(app:prepare_game_apply(true))
install.install(install.restore_plan(root,store,1));assert(read(a.path)==originalA and read(b.path)==originalB)
assert(app.current_work.steps[1].code==4 and app:chart_source(a.path)==originalA,'Restore preserves drafts and baseline')
local beforeA,beforeB=read(a.path),read(b.path)
app:open_report_entry(b,b.entries[1]);app.current_work.timing=0;app:update_draft_from_current()
app:open_report_entry(a,a.entries[1]);assert(not pcall(app.prepare_game_apply,app,true),'An invalid inactive-file draft blocks the whole batch')
assert(read(a.path)==beforeA and read(b.path)==beforeB)
app:open_report_entry(b,b.entries[1]);app.current_work.timing=b.entries[1].timing;app:update_draft_from_current();app:open_report_entry(a,a.entries[1])
plan=app:prepare_game_apply(true)
local replace=platform.replace_file;local failed=false
platform.replace_file=function(from,to)
    if to==b.path and not failed then failed=true;return nil,'simulated second-file replacement failure' end
    return replace(from,to)
end
local ok,err=pcall(install.install,plan);platform.replace_file=replace
assert(not ok and tostring(err):find('Previous game files restored',1,true))
assert(read(a.path)==beforeA and read(b.path)==beforeB and not install.pending(root,store),'A mid-batch failure rolls back every target')
local interrupted=false
platform.replace_file=function(from,to)
    if to==b.path and not interrupted then interrupted=true;return nil,'simulated interruption' end
    if interrupted and to==a.path then return nil,'simulated rollback interruption' end
    return replace(from,to)
end
ok=pcall(install.install,plan);platform.replace_file=replace
assert(not ok and install.pending(root,store),'Interrupted rollback retains recovery metadata')
assert(app:chart_source(a.path)==originalA,'Pending mixed outputs still expose their guarded baseline')
assert(install.recover(root,store) and not install.pending(root,store))
assert(read(a.path)==beforeA and read(b.path)==beforeB,'Explicit recovery is complete and repeatable')
plan=app:prepare_game_apply(true);write(a.path,originalA..'external change')
assert(not pcall(install.install,plan),'Target changed after review cannot be overwritten')
assert(read(b.path)==beforeB);write(a.path,originalA)
local dance=report.load(root,'dance');local dance_original=read(root..'/r01_sh.bin')
app:open_report_entry(dance.files[1],dance.files[1].entries[1]);app:replace_command(1,4)
app:select_entry(app.entries[3]);app:replace_command(1,5)
local dance_plan=app:prepare_game_apply(true)
assert(dance_plan.report=='dance' and #dance_plan.files==1 and dance_plan.files[1].path=='r01_sh.bin')
install.install(dance_plan)
assert(read(root..'/r01_sh.bin')~=dance_original and read(root..'/afs_english/r01_sh.bin'):match('do not change'))
install.install(install.restore_plan(root,store,'dance'));assert(read(root..'/r01_sh.bin')==dance_original)
for number=2,6 do
    local relative='afs_english/r'..number..'1_sh.bin'
    local baseline=read(TEST_GAME_ROOT..'/'..relative)
    write(root..'/'..relative,baseline)
    local level=report.load(root,number);local file=level.files[1]
    app:open_report_entry(file,file.entries[1])
    local replacement=app.current_work.steps[1].code==4 and 5 or 4
    assert(app:replace_command(1,replacement))
    local scoped=app:prepare_game_apply(true)
    assert(scoped.report==number and #scoped.files==1 and scoped.files[1].path==relative,'Correct English destination for Report '..number)
    install.install(scoped)
    assert(format.parse(read(root..'/'..relative))[1].steps[1]==replacement)
    install.install(install.restore_plan(root,store,number))
    assert(read(root..'/'..relative)==baseline,'Report '..number..' restores byte-for-byte')
end
assert(read(a.path)==originalA and read(b.path)==originalB and read(two.files[1].path)==outside)
print('PASS: report/file/Dance Apply scope; validated originals; repeat apply, partial/full undo-to-baseline and project reopen; export after Apply; skip unchanged files; restore; running-game and stale-source guards; full rollback and interrupted recovery; game-copy tests only')
