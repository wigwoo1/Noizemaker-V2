local report=require('core.report')
local route=require('core.route')
local App=require('ui.app')
local tree=require('ui.tree')
local checks=0
local function check(v,message)checks=checks+1;assert(v,message)end
local r=report.load(TEST_GAME_ROOT,1)
local rows=report.cpu_rows(r)
check(#rows==58,'recorded CPU schedule has 58 input phrases, not 99 stored entries')
check(not r.order_verified,'one recorded route does not prove all branches')
check(rows[1].entry.name=='pd001' and rows[1].event.response_seconds==44,'opening response position is the engine schedule, not early question observation')
check(rows[41].entry.name=='pk001' and rows[42].file.stem=='r12','route crosses the checked file boundary in order')
check(#rows[42].aliases==2,'identical SH/SH2 data are explicit aliases, not extra consecutive scenes')
check(rows[58].entry.name=='ps008a','final observed input retains its alternate identity')
check(#report.cpu_rows(r,'Kin Kon Kan')==17,'encounter search works in CPU order')
check(#report.cpu_rows(r,'q411a')==1,'recorded question identity is searchable')
check(rows[28].label:find('Shooting 2',1,true) and not rows[28].label:find('2001',1,true),
    'technical ps2001 gets encounter/set/phrase context')
for index,row in ipairs(rows) do
    check(row.event.order==index and row.entry.route==row.event,'row identity matches its source-bound event')
    check(row.event.bpm==require('core.playback').tempo(row.entry),'route tempo matches its chart')
end
local file=r.files[1]
check(route.source(file.relative_path,file.buffer..'changed')==nil,'changed source cannot borrow recorded order')
check(route.source(TEST_GAME_ROOT..'/r11_sh.bin',file.buffer)==nil,'root-language file cannot borrow English route labels')
local altered=report.load(TEST_GAME_ROOT,1,function(path)
    local f=io.open(path,'rb');if not f then return nil end
    local data=f:read('*a');f:close()
    return path:match('/r11_sh%.bin$') and data..'changed' or data
end)
check(not altered.cpu_route and #report.rows(altered,false)==99,'unknown source falls back to honest file order')
local alt
for _,entry in ipairs(file.entries) do if entry.name=='pd002b' then alt=entry end end
check(alt and alt.route_parent and not alt.route,'unobserved alternate has family context without a recorded visit')
check(tree.entry_label(alt,true):find('unseen',1,true),'unobserved sidebar branch is labeled')
local r5=report.load(TEST_GAME_ROOT,5)
local r5rows=report.cpu_rows(r5)
check(#r5rows==54,'Report 5 has 54 observed CPU visits across two English sections')
check(r5rows[1].file.stem=='r51' and r5rows[1].entry.name=='pd001','Report 5 opening phrase matches the captured route')
check(r5rows[20].file.stem=='r51' and r5rows[21].file.stem=='r52','Report 5 section transition matches the capture')
check(r5rows[54].file.stem=='r52' and r5rows[54].entry.name=='ps010','Report 5 route ends at the recorded shooting phrase')
check(not r5.order_verified and r5.cpu_route_note:find('sync',1,true),'one CPU run does not claim all branches or music sync')
for _,row in ipairs(r5rows) do
    check(row.event.order and row.entry.route==row.event,'Report 5 event remains bound to its exact source entry')
end
local changed_r5=report.load(TEST_GAME_ROOT,5,function(path)
    local f=io.open(path,'rb');if not f then return nil end
    local data=f:read('*a');f:close()
    return path:match('/r52_sh%.bin$') and data..'changed' or data
end)
check(not changed_r5.cpu_route,'changing a Report 5 source disables the recorded combined order')
local app=App.new();app.game_root=TEST_GAME_ROOT;app.config_path=TEST_SCRATCH..'/route-config.ini';app:load_report(1)
rows=app.reports_tab.report.cpu_route
app:open_report_entry(rows[1].file,rows[1].entry)
app.current_work.steps[1].code=4;app:update_draft_from_current()
app:playback_action('next_phrase');check(app.selected_entry.name=='pd002','Next follows the recorded route')
app:playback_action('previous_phrase');check(app.current_work.steps[1].code==4,'Prev restores an edited draft')
app:open_report_entry(rows[41].file,rows[41].entry)
app:playback_action('next_phrase');check(app.current_file_name=='r12_sh.bin' and app.selected_entry.name=='pd001','Next crosses files without confusing duplicate IDs')
app:playback_action('previous_phrase');check(app.selected_entry.name=='pk001','Prev crosses back to the final R11 call')
app:open_report_entry(rows[58].file,rows[58].entry)
app:playback_action('next_phrase');check(app.selected_entry.name=='ps008a' and app.status_text:find('End',1,true),'route endpoint is explicit')
print('PASS: '..checks..' CPU-route identity, source guards, search, labels, aliases, and navigation checks')

local r2=report.load(TEST_GAME_ROOT,2)
local r2rows=report.cpu_rows(r2)
check(#r2rows==123,'Report 2 has 123 observed visits across three parts')
check(r2rows[1].entry.name=='ps001' and r2rows[1].file.stem=='r21','Report 2 starts with its shooting sequence')
check(r2rows[37].entry.name=='pk001' and r2rows[38].file.stem=='r22','first Report 2 part boundary')
check(r2rows[82].entry.name=='pk001' and r2rows[83].file.stem=='r23','second Report 2 part boundary')
check(r2rows[123].entry.name=='pd019a','last observed Pon Piriri alternate retains its identity')
check(#report.cpu_rows(r2,'Pon Piriri')==41,'readable final-section search')
check(r2rows[1].label=='Shooting 1 / set 1 / phrase 1','Report 2 uses readable section and phrase names')
check(not r2.order_verified and r2.cpu_route_note:find('Music sync',1,true),'observed order does not claim all branches or music sync')
for _,row in ipairs(r2rows) do
    check(row.entry.route==row.event and row.file.relative_path==row.event.file,'Report 2 event identity stays attached to exact source')
    check(row.event.bpm==require('core.playback').tempo(row.entry),'Report 2 tempo comes from its chart')
end
local changed_r2=report.load(TEST_GAME_ROOT,2,function(path)
    local f=io.open(path,'rb');if not f then return nil end
    local data=f:read('*a');f:close()
    return path:match('/r23_sh%.bin$') and data..'changed' or data
end)
check(not changed_r2.cpu_route,'one changed Report 2 source disables the combined observed route')
local sh2=r2.files[2]
check(sh2.relative_path=='afs_english/r21_sh2.bin' and not sh2.route_source,'different SH2 bytes cannot borrow the main-file evidence')
check(not route.source(TEST_GAME_ROOT..'/r21_sh.bin',r2.files[1].buffer),'Japanese/root path cannot borrow Report 2 evidence')
app:load_report(2)
check(app.status_text:find('Report 2',1,true),'loading Report 2 status names the correct report')
app:open_report_entry(r2rows[37].file,r2rows[37].entry)
app.current_work.steps[1].code=4;app:update_draft_from_current()
app:playback_action('next_phrase')
check(app.current_file_name=='r22_sh.bin' and app.selected_entry.name=='pd001','Report 2 Next crosses the first file boundary')
app:playback_action('previous_phrase')
check(app.current_file_name=='r21_sh.bin' and app.current_work.steps[1].code==4,'Report 2 Prev preserves the earlier edit')
app:open_report_entry(r2rows[82].file,r2rows[82].entry)
app:playback_action('next_phrase')
check(app.current_file_name=='r23_sh.bin' and app.selected_entry.name=='ps001','Report 2 Next crosses into Pon Piriri')
app:open_report_entry(r2rows[123].file,r2rows[123].entry)
app:playback_action('next_phrase')
check(app.selected_entry.name=='pd019a' and app.status_text:find('End',1,true),'Report 2 endpoint remains explicit')
local r2score=require('core.score').plan(r2)
check(r2score.report==2 and #r2score.parts==3 and #r2score.clips==24,'Report 2 uses its own three-part music schedule')
print('PASS: Report 1 regression plus Report 2 source guards, search, alternate identity, tempo, navigation, and draft preservation ('..checks..' checks)')
