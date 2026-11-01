local M={}
function M.start(args)
    local root,out=assert(args[2]),assert(args[3])
    local function save(name,data)local f=assert(io.open(out..'/'..name,'wb'));f:write(data);f:close()end
    love.errorhandler=function(message)
        save('report4-music-error.txt',tostring(message)..'\n'..debug.traceback())
        return function()return 1 end
    end
    local App=require('ui.app');require('ui.theme').init()
    love.window.setMode(960,600);love.audio.setVolume(0)
    local app=App.new();app.game_root=root;app.config_path=out..'/report4-music.ini';app:resize(960,600)
    app:load_report(4);app.active_view='reports';app.view_transition=nil
    local stage,captured=0,false
    love.update=function(dt)
        app:update(dt)
        if stage==0 then
            local button
            app:draw()
            for _,hit in ipairs(app.reports_tab.hits) do if hit.kind=='play_report' then button=hit.rect end end
            assert(button,'Report 4 Play music button is available')
            app:mousepressed(button.x+button.w/2,button.y+button.h/2,1)
            assert(app.playback.report_job and app.playback.plan.report==4 and not app.playback.plan.voices_enabled)
            assert(#app.playback.plan.clips==58 and #app.playback.plan.phrases==134 and #app.playback.plan.events==0)
            stage=1
        elseif stage==1 and app.playback.source then
            local state=app.playback
            assert(state.report_cache.status=='done' and state.source:getChannelCount()==2)
            assert(not state.plan.response_timing_checked and not state.plan.alignment_verified)
            assert(state.plan.duration>1100 and state.source:getDuration('seconds')>1100)
            local descriptor=require('ui.playback_bar').report_descriptor(state)
            assert(descriptor:find('Report 4',1,true) and descriptor:find('music only',1,true)
                and descriptor:find('sync unverified',1,true))
            for _,i in ipairs({1,20,21,57,58,110,111,134}) do
                local phrase=state.plan.phrases[i]
                local target=phrase.response+.05
                app:playback_action('seek',target/state.plan.duration);app:update(0)
                assert(math.abs(state.source:tell('seconds')-target)<.04)
                assert(app.selected_entry.name==phrase.row.entry.name and app.current_file_name==phrase.row.file.stem..'_sh.bin')
            end
            app:playback_action('play');assert(not state.playing)
            app:playback_action('play');assert(state.source:isPlaying())
            app:playback_action('previous_phrase');assert(app.selected_entry.name=='ps011a')
            app:playback_action('next_phrase');assert(app.selected_entry.name=='ps012a')
            app:playback_action('loop');assert(state.source:isLooping())
            love.window.setMode(1280,720);app:resize(1280,720)
            stage=2
        elseif stage==1 and not app.playback.report_job then
            error('Report 4 music render failed: '..tostring(app.status_text))
        elseif stage==2 and captured then
            app:playback_action('stop')
            assert(not app.playback.source and not app.playback.report_job)
            save('report4-music-result.txt',
                'PASS: complete four-part Report 4 music-only stereo render, 58 cues, 134 phrases, real browser button, cross-part seek, play/pause, loop, stop and both layouts. No game files written.\n')
            app.allow_quit=true;love.event.quit(0);stage=3
        end
    end
    love.draw=function()
        app:draw()
        if stage==2 and not captured then
            love.graphics.captureScreenshot(function(img)save('report4-music-playing.png',img:encode('png'):getString());captured=true end)
        end
    end
    return app
end
return M
