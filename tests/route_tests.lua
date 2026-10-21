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
check(not report.load(TEST_GAME_ROOT,2).cpu_route,'other reports do not inherit Report 1 order')
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
