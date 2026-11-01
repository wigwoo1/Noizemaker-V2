local report=require('core.report')
local route=require('core.route')
local r=report.load(TEST_GAME_ROOT,3)
local rows=report.cpu_rows(r)
assert(#rows==56 and #report.rows(r,false)==137 and #report.rows(r,true)==274)
assert(rows[1].entry.name=='pd001' and rows[1].event.response_seconds==36)
assert(rows[56].entry.name=='pk001' and rows[56].label=='Final call / set 1 / phrase 1')
assert(not r.order_verified and #report.cpu_rows(r,'Space Police')==56)
for i,row in ipairs(rows) do
    assert(row.event.order==i and row.entry.route==row.event)
    assert(row.file.relative_path=='afs_english/r31_sh.bin')
    assert(row.event.bpm==require('core.playback').tempo(row.entry))
end
assert(not route.source(r.files[1].relative_path,r.files[1].buffer..'changed'))
assert(not route.source(TEST_GAME_ROOT..'/r31_sh.bin',r.files[1].buffer))
assert(not r.files[2].route_source,'distinct SH2 source has no recorded route')
local altered=report.load(TEST_GAME_ROOT,3,function(path)
    local f=io.open(path,'rb');if not f then return nil end
    local data=f:read('*a');f:close()
    return path:match('/r31_sh%.bin$') and data..'changed' or data
end)
assert(not altered.cpu_route and #report.rows(altered,false)==137)
local app=require('ui.app').new()
app.game_root=TEST_GAME_ROOT;app.config_path=TEST_SCRATCH..'/report3-route-config.ini'
app:load_report(3);app:open_report_entry(rows[1].file,rows[1].entry)
local old=app.current_work.steps[1].code
local replacement=old==4 and 5 or 4
app:replace_command(1,replacement)
app:playback_action('next_phrase');assert(app.selected_entry.name=='pd002')
app:playback_action('previous_phrase');assert(app.current_work.steps[1].code==replacement)
app:open_report_entry(rows[56].file,rows[56].entry)
app:playback_action('next_phrase');assert(app.selected_entry.name=='pk001' and app.status_text:find('End',1,true))
assert(require('core.score').available(4) and require('core.score').available(5)
    and not require('core.score').available(6),
    'Reports 4 and 5 have separate music schedules; unmapped Report 6 cannot borrow one')
print('PASS: Report 3 56/137/274 counts, source guards, tempo, search, endpoint, and draft navigation')
