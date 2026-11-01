local M={}
function M.start(args)
    local root,out=assert(args[2]),assert(args[3])
    local function save(name,data)
        local f=assert(io.open(out..'/'..name,'wb'));f:write(data);f:close()
    end
    love.errorhandler=function(message)
        save('question-voice-error.txt',tostring(message)..'\n'..debug.traceback())
        return function()return 1 end
    end
    local App=require('ui.app');require('ui.theme').init()
    love.window.setMode(960,600);love.audio.setVolume(0)
    local app=App.new();app.game_root=root;app.config_path=out..'/question-voice.ini'
    app:resize(960,600);app:load_report(1);app.active_view='reports';app.view_transition=nil
    local rows=app.reports_tab.report.cpu_route
    local indices={1,#rows}
    local stage,index=0,1
    love.update=function(dt)
        app:update(dt)
        if stage==0 then
            local row=rows[indices[index]]
            app:open_report_entry(row.file,row.entry);app.view_transition=nil
            app:playback_action('play')
            local state=app.playback
            assert(state.source and state.source:isPlaying(),'Report 1 phrase Play starts audio')
            assert(state.plan.question_duration and state.plan.music and
                state.source:getChannelCount()==2,'English enemy and stereo music load')
            assert(math.abs(state.plan.duration-state.plan.question_duration*2)<1e-6)
            assert(state.plan.events[1].command:find('^QUESTION_'),'Enemy call comes first')
            assert(require('core.playback').tick({plan=state.plan,position=0})==nil)
            app:playback_action('seek',.75)
            assert(require('core.playback').tick(state)>0,'Playhead follows the response')
            app:playback_action('stop')
            assert(not state.playing,'Stop ends the full phrase')
            index=index+1
            if index>#indices then
                state.music_enabled=false
                app:playback_action('play')
                assert(state.source and state.source:isPlaying() and
                    state.source:getChannelCount()==2 and not state.plan.music,
                    'Stereo enemy question plays with music switched off')
                app:playback_action('stop')
                save('question-voice-result.txt',
                    'PASS: First and last Report 1 phrases play enemy question, Ulala response and stereo music; seek, stop and music-off work at 960x600.\n')
                app.allow_quit=true;love.event.quit(0);stage=1
            end
        end
    end
    love.draw=function()app:draw()end
    return app
end
return M
