local M={}
function M.start(args)
    local root,out=assert(args[2]),assert(args[3])
    local function save(name,data)
        local f=assert(io.open(out..'/'..name,'wb'));f:write(data);f:close()
    end
    love.errorhandler=function(message)
        save('question-report4-error.txt',tostring(message)..'\n'..debug.traceback())
        return function()return 1 end
    end
    local App=require('ui.app');require('ui.theme').init()
    love.window.setMode(960,600);love.audio.setVolume(0)
    local app=App.new();app.game_root=root;app.config_path=out..'/question-report4.ini'
    app:resize(960,600);app:load_report(4);app.active_view='reports';app.view_transition=nil
    local wanted={['r41:s11']=true,['r42:s13']=true,['r42:s31']=true,['r42:s41']=true}
    local rows={}
    for _,row in ipairs(app.reports_tab.report.cpu_route) do
        local key=row.event.group_key
        if wanted[key] and not rows[key] then rows[key]=row end
    end
    local keys={'r41:s11','r42:s13','r42:s31','r42:s41'}
    local index,stage=1,0
    love.update=function(dt)
        app:update(dt)
        if stage==0 then
            local key=keys[index]
            local row=assert(rows[key],'Missing recorded '..key)
            app:open_report_entry(row.file,row.entry);app.view_transition=nil
            app:playback_action('play')
            local state=app.playback
            assert(state.source and state.source:isPlaying(),'Report 4 full phrase starts: '..key)
            assert(state.plan.question_duration,'Enemy question is present: '..key)
            assert(state.plan.music and state.source:getChannelCount()==2,'Stereo music is present: '..key)
            assert(state.plan.events[1].command:match('^QUESTION_'),'Enemy call comes first: '..key)
            app:playback_action('seek',.75)
            assert(require('core.playback').tick(state)>0,'Seek reaches response: '..key)
            app:playback_action('stop')
            index=index+1
            if index>#keys then
                save('question-report4-result.txt',
                    'PASS: Four recorded Report 4 bank groups play enemy question, Ulala response and stereo music; seek and stop work.\n')
                app.allow_quit=true;love.event.quit(0);stage=1
            end
        end
    end
    love.draw=function()app:draw()end
    return app
end
return M
