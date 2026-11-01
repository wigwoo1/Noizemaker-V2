local M={}
function M.start(args)
    local App=require('ui.app')
    local theme=require('ui.theme')
    local root,out=assert(args[2]),assert(args[3])
    local function save(name,data)local f=assert(io.open(out..'/'..name,'wb'));f:write(data);f:close()end
    love.errorhandler=function(message)
        save('report-audio-error.txt',tostring(message)..'\n'..debug.traceback())
        return function()return 1 end
    end
    local edit_mode=args[4]=='edit'
    if edit_mode then
        local route=require('core.route')
        local all_rows=route.rows
        route.rows=function(report)
            local rows,reason=all_rows(report)
            if not rows then return nil,reason end
            return {rows[1]}
        end
        local facts=require('core.score_data')
        local first=facts.parts[1]
        facts.parts={{stem=first.stem,file=first.file,duration=50.5,cues={}}}
        local score=require('core.score')
        local full_plan=score.plan
        score.plan=function(...)
            local plan=full_plan(...)
            plan.music_enabled=false
            return plan
        end
    end
    -- The runner redirects APPDATA into the workspace, so LOVE mounts this
    -- test's save directory without touching the user's normal app data.
    local app
    theme.init();love.window.setMode(960,600)
    app=App.new();app.game_root=root;app.config_path=out..'/report-audio-smoke.ini'
    app:resize(960,600);app:load_report(1);app.active_view='reports';app.view_transition=nil
    local stage,captured,seek_target=0,false,nil
    app.update_hover_state=function()end
    love.update=function(dt)
        app:update(dt)
        if stage==0 then
            app:start_report_playback(true)
            if edit_mode then
                assert(not app.modal and app.playback.mode=='report' and app.playback.report_job,
                    'Known first phrase starts without an unknown-call prompt')
                assert(require('ui.playback_bar').report_descriptor(app.playback):find('English calls only',1,true),
                    'Call-only report playback is labeled accurately')
            else
                assert(not app.modal,'Verified Report 1 calls start without an unknown-voice prompt')
                assert(app.playback.mode=='report' and app.playback.report_job and app.playback.plan.voices_enabled
                    and not app.playback.plan.skip_unmapped_voices and #app.playback.plan.omitted_voice_events==0
                    and next(app.playback.plan.unmapped_commands)==nil,
                    'All recorded response calls are included, without skipping flagged Chu')
                assert(require('ui.playback_bar').report_descriptor(app.playback):find('sync unverified',1,true),
                    'Mapped-call transport labels unverified game-audio alignment')
                app:playback_action('stop')
                assert(not app.playback.report_job and not app.playback.mode and not app.reports_tab.report_preparing,
                    'Stop cancels mapped-call report preparation')
                app:start_report_playback(false)
                assert(require('ui.playback_bar').report_descriptor(app.playback):find('music only · calls muted',1,true),
                    'Music-only transport identifies muted calls')
                assert(require('ui.playback_bar').report_descriptor(app.playback):find('sync unverified',1,true),
                    'Music-only transport labels unverified game-audio alignment')
                app:playback_action('stop')
                app:start_report_playback(true)
                assert(not app.modal and app.playback.report_job,'A fresh start includes all verified calls')
            end
            stage=1
        elseif stage==1 and app.playback.source then
            local state=app.playback
            assert(state.report_cache and state.report_cache.status=='done','Report WAV render completes')
            assert(state.playing and state.source:isPlaying(),'Report audio source starts playing')
            assert(state.source:getChannelCount()==2,'Report source streams stereo audio')
            if not edit_mode then
                assert(state.plan.response_timing_checked and state.plan.response_timing_tolerance_seconds==.06
                    and not state.plan.alignment_verified,'Full render checks response timing without asserting the outro')
                local descriptor=require('ui.playback_bar').report_descriptor(state)
                assert(descriptor:find('responses checked',1,true) and descriptor:find('ending provisional',1,true),
                    'Transport distinguishes checked responses from the provisional ending')
            end
            state.source:setVolume(0)
            seek_target=state.plan.phrases[1].response+0.1
            app:playback_action('seek',seek_target/state.plan.duration)
            assert(math.abs(state.source:tell('seconds')-seek_target)<0.02,'Whole-report seeking reaches a phrase response')
            app:update(0)
            assert(state.report_tick and state.report_tick>0,'Seek sets the active phrase playhead tick')
            assert(math.abs(require('core.playback').tick(state)-state.report_tick)<0.001,
                'Timeline playhead follows the report audio clock at the seek point')
            app:playback_action('loop')
            assert(state.looping,'Report loop control toggles on')
            stage=3
        elseif stage==3 and love.timer.getTime() > (app.report_audio_smoke_seeked_at or 0)+0.2 then
            local state=app.playback
            if not app.report_audio_smoke_seeked_at then
                app.report_audio_smoke_seeked_at=love.timer.getTime()
            else
                local phrase=state.plan.phrases[1]
                local audio_position=state.source:tell('seconds')
                assert(audio_position>seek_target,'Real audio clock advances after seek')
                assert(math.abs(state.position-audio_position)<0.05,'GUI playback position follows the real source clock')
                assert(app.selected_entry and app.selected_entry.name==phrase.row.entry.name,
                    'GUI selects the chart phrase active at the sought audio time')
                if state.report_tick then
                    assert(math.abs(require('core.playback').tick(state)-state.report_tick)<0.001,
                        'Timeline playhead follows the report audio clock while inside the phrase')
                end
                app:playback_action('play')
                assert(not state.playing,'Report pause control pauses the real source')
                app:playback_action('play')
                assert(state.playing and state.source:isPlaying(),'Report play control resumes the real source')
                if edit_mode then
                    local original=app.current_work.steps[1].code
                    local gap=app.current_work.steps[1].gap
                    local replacement=original==5 and 4 or 5
                    assert(app:replace_command(1,replacement),'Replace a command while Report 1 is playing')
                    assert(app.current_work.steps[1].code==replacement and app.current_work.steps[1].gap==gap,
                        'Report playback edit preserves the command timing')
                    assert(not app.playback.source and not app.playback.mode
                        and not app.reports_tab.playing_report and not app.reports_tab.report_preparing,
                        'Editing stops report playback and resets its browser indicator')
                    app:undo()
                    assert(app.current_work.steps[1].code==original and app.current_work.steps[1].gap==gap,
                        'Undo restores the original report command and timing')
                    app:redo()
                    assert(app.current_work.steps[1].code==replacement and app.current_work.steps[1].gap==gap,
                        'Redo restores the replacement without changing timing')
                end
                stage=2
            end
        elseif stage==1 and not app.playback.report_job and not app.playback.source then
            error('Report audio preparation stopped before playback: '..tostring(app.status_text))
        elseif stage==2 and captured then
            app:playback_action('stop')
            assert(not app.playback.source and not app.playback.mode,'Stop releases the source and cached render')
            assert(not app.playback.report_job and not app.reports_tab.report_preparing,'Cancel cleans up the in-progress render')
            local detail=edit_mode and 'short Report 1 edit, timing-preserving undo/redo, and transport reset'
                or 'full 612-second Report 1 render'
            save('report-audio-result.txt','PASS: actual LOVE '..detail..', streamed stereo Source, verified R11 voices, seek, loop, pause, resume, stop, cancel, and cleanup.\n')
            app.allow_quit=true
            love.event.quit(0);stage=4
        end
    end
    love.draw=function()
        app:draw()
        if stage==2 and not captured then
            love.graphics.captureScreenshot(function(img)
                save('report-audio-preparing.png',img:encode('png'):getString())
                captured=true
            end)
        end
    end
    return app
end
return M
