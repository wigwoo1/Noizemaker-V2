local M={}
function M.start(args)
    local App=require('ui.app')
    local theme=require('ui.theme')
    local playback=require('core.playback')
    local root,out=assert(args[2]),assert(args[3])
    local full=args[4]=='full'
    local function save(name,value)local f=assert(io.open(out..'/'..name,'wb'));f:write(value);f:close()end
    love.errorhandler=function(message)
        save('report2-audio-error.txt',tostring(message)..'\n'..debug.traceback())
        return function()return 1 end
    end
    theme.init();love.window.setMode(960,600)
    local app=App.new();app.game_root=root;app.config_path=out..'/report2-audio.ini'
    app:resize(960,600);app:load_report(2);app.active_view='reports';app.view_transition=nil
    app.update_hover_state=function()end
    local rows=app.reports_tab.report.cpu_route
    local stage,elapsed,captured=0,0,false
    local phrase_started,loop_started=0,0
    local indices={1,38,83}
    local index=1
    love.update=function(dt)
        app:update(dt);elapsed=elapsed+dt
        if stage==0 then
            if full then
                app:start_report_playback(true)
                assert(app.modal and app.modal.message:find('Report 2',1,true),'Unknown Report 2 calls are explicit')
                app:dismiss_modal('music')
                assert(app.playback.plan.report==2 and not app.playback.plan.voices_enabled,'Music-only choice stays on Report 2')
                app:playback_action('stop')
                assert(not app.playback.report_job and not app.reports_tab.report_preparing,'Cancel stops preparation')
                app:start_report_playback(true);assert(app.modal)
                app:dismiss_modal('mapped')
                assert(app.playback.plan.report==2 and #app.playback.plan.parts==3 and #app.playback.plan.clips==24)
                assert(app.playback.plan.skip_unmapped_voices and #app.playback.plan.omitted_voice_events>0)
                stage=1
            else
                local row=rows[indices[index]]
                app:open_report_entry(row.file,row.entry);app.view_transition=nil
                app:playback_action('play')
                assert(app.playback.source and app.playback.source:isPlaying(),'Report 2 phrase source starts')
                assert(app.playback.plan.music and app.playback.source:getChannelCount()==2,'All three parts play stereo music')
                assert(not app.playback.plan.music.timing_checked,'No false Report 1 timing label')
                stage,elapsed,phrase_started=10,0,love.timer.getTime()
            end
        elseif stage==1 and app.playback.source then
            local state=app.playback
            assert(state.report_cache.status=='done' and state.source:getChannelCount()==2)
            assert(state.plan.frames==math.floor(1064.763861622607*48000+.5),'Full Report 2 duration rendered')
            assert(not state.plan.response_timing_checked and not state.plan.alignment_verified)
            local title=require('ui.playback_bar').report_descriptor(state)
            assert(title:find('Report 2',1,true) and title:find('sync unverified',1,true) and title:find('unknown skipped',1,true))
            state.source:setVolume(0)
            for _,i in ipairs({1,37,38,82,83,123}) do
                local phrase=state.plan.phrases[i]
                local target=phrase.response+.05
                app:playback_action('seek',target/state.plan.duration);app:update(0)
                assert(math.abs(state.source:tell('seconds')-target)<.03,'Seek reaches native response position')
                assert(app.current_file_path==phrase.row.file.path and app.selected_entry.name==phrase.row.entry.name,
                    'Audio seek selects exact phrase across both part boundaries')
            end
            app:playback_action('play');assert(not state.playing)
            app:playback_action('play');assert(state.source:isPlaying())
            app:playback_action('previous_phrase');app:playback_action('next_phrase')
            app:playback_action('loop');assert(state.source:isLooping())
            app:playback_action('seek',(state.plan.duration-.05)/state.plan.duration)
            stage,elapsed,loop_started=2,0,love.timer.getTime()
        elseif stage==1 and not app.playback.report_job then
            error('Report 2 preparation failed: '..app.status_text)
        elseif stage==2 and love.timer.getTime()-loop_started>.3 then
            assert(app.playback.source:isPlaying() and app.playback.position<1,'Real report loop wraps to the opening')
            local phrase=app.playback.plan.phrases[83]
            app:playback_action('seek',(phrase.response+.1)/app.playback.plan.duration);app:update(0)
            assert(app.current_file_name=='r23_sh.bin','Seek returns to Pon Piriri')
            stage=20
        elseif stage==10 and love.timer.getTime()-phrase_started>.2 then
            local state=app.playback
            assert(state.position>0,'Real phrase music clock advances')
            app:playback_action('play');assert(not state.playing)
            app:playback_action('seek',.5);assert(math.abs(state.position-state.plan.duration/2)<.02)
            app:playback_action('play');assert(state.source:isPlaying())
            local previous_loop=state.looping
            app:playback_action('loop')
            assert(state.looping~=previous_loop and state.source:isLooping()==state.looping,'Loop setting persists across phrase changes')
            app:playback_action('stop')
            app:playback_action('music');app:playback_action('play')
            assert(not app.playback.plan.music and app.playback.source:getChannelCount()==1,'Music toggle enables voice-only preview')
            app:playback_action('music');app:playback_action('play')
            assert(app.playback.plan.music,'Music toggles back on')
            local gap=app.current_work.steps[1].gap
            local old=app.current_work.steps[1].code
            assert(app:replace_command(1,old==4 and 5 or 4))
            assert(not app.playback.source and app.current_work.steps[1].gap==gap,'Editing discards stale audio and preserves timing')
            app:undo();assert(app.current_work.steps[1].code==old)
            index=index+1
            if index<=#indices then stage=0 else stage=20 end
        elseif stage==20 and captured then
            app:playback_action('stop')
            if full then assert(not app.playback.source and not app.playback.report_job) end
            save('report2-audio-result.txt',full and
                'PASS: complete 1064.764-second Report 2 stereo render with 24 music cues, explicit unknown-call policy, native response seeking across all three parts, pause/resume, Prev/Next, real loop wrap, cancel, stop, and cleanup.\n' or
                'PASS: actual stereo phrase playback from all three Report 2 parts, audio clock, pause/seek/resume, loops, music toggle, timing-preserving replacement/undo, and stale-audio cleanup.\n')
            app.allow_quit=true;love.event.quit(0);stage=21
        end
    end
    love.draw=function()
        app:draw()
        if stage==20 and not captured then
            love.graphics.captureScreenshot(function(img)save('report2-playback.png',img:encode('png'):getString());captured=true end)
        end
    end
    return app
end
return M
