local M={}
function M.start(args)
    local root,out=assert(args[2]),assert(args[3])
    local function save(name,data)
        local f=assert(io.open(out..'/'..name,'wb'));f:write(data);f:close()
    end
    love.errorhandler=function(message)
        save('question-report2-error.txt',tostring(message)..'\n'..debug.traceback())
        return function()return 1 end
    end
    local App=require('ui.app');require('ui.theme').init()
    love.window.setMode(960,600);love.audio.setVolume(0)
    local app=App.new();app.game_root=root;app.config_path=out..'/question-report2.ini'
    app:resize(960,600);app:load_report(2);app.active_view='reports';app.view_transition=nil
    local rows=app.reports_tab.report.cpu_route
    assert(#rows==123)
    local selected={}
    for _,row in ipairs(rows) do
        if not selected[row.file.stem] then selected[row.file.stem]=row end
        if row.file.stem=='r23' and row.entry.name=='ps015' then selected.raw=row end
    end
    assert(selected.r21 and selected.r22 and selected.r23 and selected.raw)
    local checks={selected.r21,selected.r22,selected.r23,selected.raw}
    local index,stage=1,0
    love.update=function(dt)
        app:update(dt)
        if stage==0 then
            local row=checks[index]
            app:open_report_entry(row.file,row.entry);app.view_transition=nil
            app:playback_action('play')
            local state=app.playback
            assert(state.source and state.source:isPlaying(),'Report 2 full phrase starts')
            assert(state.plan.question_duration and state.plan.music and
                state.source:getChannelCount()==2,'Enemy, response and stereo music load')
            assert(state.plan.events[1].command:match('^QUESTION_'))
            assert(math.abs(state.plan.duration-state.plan.question_duration*2)<1e-6)
            if row==selected.r22 then
                assert(state.plan.question_bank_provisional,'Weak enemy bank is marked provisional')
            end
            if row==selected.raw then
                assert(state.plan.question_unmapped_count>0,'Raw calls remain unmapped')
                assert(app.status_text:find('raw call',1,true),'Raw call warning is visible')
            end
            app:playback_action('seek',.75)
            assert(require('core.playback').tick(state)>0,'Playhead reaches Ulala response')
            app:playback_action('stop')
            index=index+1
            if index>#checks then
                save('question-report2-result.txt',
                    'PASS: Report 2 enemy and response playback with stereo music across all three parts; weak bank and raw calls labeled; seek and stop work at 960x600.\n')
                app.allow_quit=true;love.event.quit(0);stage=1
            end
        end
    end
    love.draw=function()app:draw()end
    return app
end
return M
