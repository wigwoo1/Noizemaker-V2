local M={}
function M.start(args)
    local App=require('ui.app')
    local theme=require('ui.theme')
    local root,out=assert(args[2]),assert(args[3])
    local function save(name,value)local f=assert(io.open(out..'/'..name,'wb'));f:write(value);f:close()end
    love.errorhandler=function(message)
        save('report3-audio-error.txt',tostring(message)..'\n'..debug.traceback())
        return function()return 1 end
    end
    theme.init();love.window.setMode(960,600)
    local app=App.new();app.game_root=root;app.config_path=out..'/report3-audio.ini'
    app:resize(960,600);app:load_report(3);app.active_view='reports';app.view_transition=nil
    app.update_hover_state=function()end
    local rows=app.reports_tab.report.cpu_route
    local stage,captured,started=0,false,0
    local held_captured=false
    love.update=function(dt)
        app:update(dt)
        if stage==0 then
            app:start_report_playback(false)
            assert(app.playback.report_job and app.playback.plan.report==3)
            app:playback_action('stop')
            assert(not app.playback.report_job and not app.reports_tab.report_preparing)
            app:start_report_playback(true)
            assert(not app.modal and app.playback.report_job,'Standard calls do not trigger unknown-code choice')
            stage=1
        elseif stage==1 and app.playback.source then
            local state=app.playback
            assert(state.report_cache.status=='done' and state.source:getChannelCount()==2)
            assert(state.plan.frames==math.floor(391.42212885154066*48000+.5))
            assert(#state.plan.clips==4 and #state.plan.phrases==56 and #state.plan.events>0)
            assert(not state.plan.response_timing_checked and not state.plan.alignment_verified)
            local title=require('ui.playback_bar').report_descriptor(state)
            assert(title:find('Report 3',1,true) and title:find('sync unverified',1,true))
            state.source:setVolume(0)
            for _,i in ipairs({1,14,29,51,56}) do
                local phrase=state.plan.phrases[i]
                local target=phrase.response+.05
                app:playback_action('seek',target/state.plan.duration);app:update(0)
                assert(math.abs(state.source:tell('seconds')-target)<.03)
                assert(app.selected_entry.name==phrase.row.entry.name and app.current_file_name=='r31_sh.bin')
            end
            app:playback_action('play');assert(not state.playing)
            app:playback_action('play');assert(state.source:isPlaying())
            app:playback_action('previous_phrase');assert(app.selected_entry.name=='pr032')
            app:playback_action('next_phrase');assert(app.selected_entry.name=='pk001')
            app:playback_action('loop');assert(state.source:isLooping())
            app:playback_action('seek',(state.plan.duration-.05)/state.plan.duration)
            started=love.timer.getTime();stage=2
        elseif stage==1 and not app.playback.report_job then
            error('Report 3 render failed: '..app.status_text)
        elseif stage==2 and love.timer.getTime()-started>.3 then
            assert(app.playback.source:isPlaying() and app.playback.position<1)
            app:playback_action('seek',.7);app:update(0);stage=3
        elseif stage==3 and captured then
            app:playback_action('stop')
            assert(not app.playback.source and not app.playback.report_job)
            app:open_report_entry(rows[1].file,rows[1].entry);app.view_transition=nil
            app:playback_action('play')
            assert(app.playback.source:isPlaying() and app.playback.source:getChannelCount()==2)
            assert(app.playback.plan.music and not app.playback.plan.music.timing_checked)
            started=love.timer.getTime();stage=4
        elseif stage==4 and love.timer.getTime()-started>.2 then
            local state=app.playback
            assert(state.position>0)
            app:playback_action('play');assert(not state.playing)
            app:playback_action('seek',.5)
            app:playback_action('play');assert(state.source:isPlaying())
            app:playback_action('stop');app:playback_action('music');app:playback_action('play')
            assert(not app.playback.plan.music and app.playback.source:getChannelCount()==1)
            app:playback_action('music');app:playback_action('play');assert(app.playback.plan.music)
            local old,gap=app.current_work.steps[1].code,app.current_work.steps[1].gap
            assert(app:replace_command(1,old==4 and 5 or 4))
            assert(not app.playback.source and app.current_work.steps[1].gap==gap)
            app:undo();assert(app.current_work.steps[1].code==old)
            app:playback_action('stop')
            stage=6
        elseif stage==6 then
            app:open_report_entry(rows[23].file,rows[23].entry);app.view_transition=nil
            assert(app.selected_entry.name=='pd023')
            app:playback_action('play')
            assert(app.playback.plan.events[1].command=='R31_HOLD_CHU_LONG')
            local bank=app:command_audio_bank()
            assert(bank.samples.R31_HOLD_CHU_LONG.info.duration>1.9)
            app.selected_step_index=1;app:audition_command(9)
            assert(app.playback.audition:isPlaying() and bank.samples.R31_HOLD_CHU_LONG.source)
            app:replace_command(1,10);app:playback_action('play')
            assert(app.playback.plan.events[1].command=='R31_HOLD_HEY_LONG')
            app:undo();app:playback_action('stop')
            app.playback.range_start=24;app.playback.range_end=48
            app:playback_action('play')
            assert(#app.playback.plan.continuations==1 and app.playback.plan.continuations[1].command=='R31_HOLD_CHU_LONG')
            stage=7
        elseif stage==7 and held_captured then
            app:playback_action('stop')
            save('report3-audio-result.txt','PASS: complete Report 3 stereo render and controls; native held-voice bank selection, long Chu audition, long Hey replacement/undo, range continuation, and audio cleanup.\n')
            app.allow_quit=true;love.event.quit(0);stage=8
        end
    end
    love.draw=function()
        app:draw()
        if stage==3 and not captured then
            love.graphics.captureScreenshot(function(img)save('report3-playback.png',img:encode('png'):getString());captured=true end)
        end
        if stage==7 and not held_captured then
            love.graphics.captureScreenshot(function(img)save('report3-held-playback.png',img:encode('png'):getString());held_captured=true end)
        end
    end
    return app
end
return M
