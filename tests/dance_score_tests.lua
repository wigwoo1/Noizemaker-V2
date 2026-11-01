local report=require('core.report')
local route=require('core.route')
local score=require('core.score')
local App=require('ui.app')
local mode=report.load(TEST_GAME_ROOT,'dance')
local file=mode.files[1]
assert(#mode.cpu_route==200 and #report.cpu_rows(mode)==200)
assert(#report.rows(mode,false)==100 and #report.rows(mode,true)==200)
assert(route.source(TEST_GAME_ROOT..'/R01_SH.BIN',file.buffer)=='r01_sh.bin')
assert(not route.source(TEST_GAME_ROOT..'/afs_english/r01_sh.bin',file.buffer))
assert(not route.source(TEST_GAME_ROOT..'/r11_sh.bin',file.buffer))
assert(not route.source(file.path,file.buffer..'changed'))
local plan=score.plan(mode)
assert(plan.report=='dance' and plan.title=="Ulala's Dance")
assert(#plan.phrases==200 and #plan.clips==225 and #plan.events==966)
assert(plan.frames==math.floor(1264.9017503277034*48000+.5))
assert(not plan.alignment_verified and not plan.response_timing_candidate and not plan.response_timing_checked)
assert(not next(plan.unmapped_commands))
local held=0;for _,e in ipairs(plan.events) do
    assert(e.stem=='r01' and e.command:match('^DANCE_'))
    if e.code==9 then held=held+1;assert(e.command=='DANCE_V10_M4' or e.command=='DANCE_V11_M4') end
end
assert(held==10)
assert(plan.phrases[87].row.entry.name=='pd0909' and plan.phrases[89].row.entry.name=='pd0909')
assert(plan.phrases[87].row.event.question=='q0909' and plan.phrases[89].row.event.question=='q0911')
assert(#plan.phrases[87].row.entry.route_visits==2 and plan.phrases[87].row.entry.route.order==87)
for _,i in ipairs({1,49,87,89,100,101,149,189,200}) do
    local phrase,tick=score.locate(plan,plan.phrases[i].response+.02)
    assert(phrase==plan.phrases[i] and tick>0)
end
local changed=report.load(TEST_GAME_ROOT,'dance',function()return file.buffer..'changed' end)
assert(not changed.cpu_route and not pcall(score.plan,changed))
local app=App.new();app.game_root=TEST_GAME_ROOT;app.config_path=TEST_SCRATCH..'/dance-score.ini'
app:load_report('dance')
app:open_report_entry(file,mode.cpu_route[89].entry,false,89)
assert(app.recorded_route_order==89)
app:navigate_cpu_route(1);assert(app.recorded_route_order==90 and app.selected_entry.name=='pd0910')
app:navigate_cpu_route(-1);assert(app.recorded_route_order==89 and app.selected_entry.name=='pd0909')
local old=app.current_work.steps[1].code
assert(app:replace_command(1,old==1 and 2 or 1))
local revised=score.plan(mode,function(f,e)return app:report_preview_entry(f,e)end)
local counts={}
for _,event in ipairs(revised.events) do
    if event.index==1 and (event.phrase==87 or event.phrase==89) then
        assert(event.code==app.current_work.steps[1].code);counts[event.phrase]=true
    end
end
assert(counts[87] and counts[89],'One shared edit reaches both actual visits')
app:undo()
app.current_work.timing=app.current_work.timing+1;app:update_draft_from_current()
assert(not pcall(score.plan,mode,function(f,e)return app:report_preview_entry(f,e)end),'Changed phrase duration cannot inherit the route')
local missing=0;for _,row in ipairs(mode.cpu_route) do if not row.event.native_schedule_observed then missing=missing+1 end end
assert(missing==3,'Capture gaps remain explicit in published route metadata')
print('PASS: Dance 200 visits / 196 unique targets / 225 cues / 966 calls, source/path guards, ten native held calls, repeated-visit navigation, shared draft playback, timing rejection and explicit capture limits')
