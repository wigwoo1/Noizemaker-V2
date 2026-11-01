local M={}
function M.start(args)
    local root,out=assert(args[2]),assert(args[3])
    local function save(name,data)local f=assert(io.open(out..'/'..name,'wb'));f:write(data);f:close()end
    love.errorhandler=function(message)
        save('report4-audio-error.txt',tostring(message)..'\n'..debug.traceback());return function()return 1 end
    end
    local App=require('ui.app');require('ui.theme').init();love.window.setMode(960,600);love.audio.setVolume(0)
    local app=App.new();app.game_root=root;app.config_path=out..'/report4.ini';app:resize(960,600)
    app:load_report(4);app.view_transition=nil
    local stage,started,captured=0,0,false
    local selected,entry
    love.update=function(dt)
        app:update(dt)
        if stage==0 then
            local checked=0
            for _,file in ipairs(app.reports_tab.report.files) do
                if file.stem=='r43' then
                    for _,e in ipairs(file.entries) do
                        if e.name=='pr004w' or e.name=='pr001w' or e.name=='pr010w' then
                            checked=checked+1
                            app:open_report_entry(file,e);app.view_transition=nil
                            app:playback_action('play');assert(app.playback.source:isPlaying())
                            local held=false
                            for _,event in ipairs(app.playback.plan.events) do
                                if event.code==9 then assert(event.command=='R43_HOLD_CHU');held=true end
                            end
                            assert(held and not app.playback.plan.alignment_verified)
                            local bank=app:command_audio_bank()
                            app:audition_command(9);assert(bank.samples.R43_HOLD_CHU.source and app.playback.audition:isPlaying())
                            app.playback.audition:stop();app:playback_action('stop')
                            if file.is_main and e.name=='pr004w' then selected,entry=file,e end
                        end
                    end
                end
            end
            assert(checked==6 and selected)
            app:open_report_entry(selected,entry);app.view_transition=nil
            assert(app.current_work.steps[1].code==9)
            app:replace_command(1,10);app:playback_action('play')
            assert(app.playback.plan.events[1].command=='R43_HOLD_HEY' and app.playback.plan.warnings[1]:find('dummy',1,true))
            app:undo();app:playback_action('stop')
            app.playback.range_start,app.playback.range_end=6,12
            app:playback_action('loop');app:playback_action('play')
            assert(#app.playback.plan.continuations>0 and app.playback.plan.continuations[1].command=='R43_HOLD_CHU')
            started=love.timer.getTime();stage=1
        elseif stage==1 and captured and love.timer.getTime()-started>.7 then
            assert(app.playback.source:isPlaying() and app.playback.position<app.playback.plan.duration)
            app:playback_action('play');assert(not app.playback.playing)
            app:playback_action('seek',.5);app:playback_action('play');assert(app.playback.source:isPlaying())
            app:playback_action('stop');assert(not app.playback.playing)
            local held=0;local source,target
            local bindings=require('core.voice_report42_data').bindings
            for _,file in ipairs(app.reports_tab.report.files) do if file.stem=='r42' then
                for _,e in ipairs(file.entries) do
                    local has_hold=false;for _,code in ipairs(e.steps) do if bindings[tostring(code)] then has_hold=true end end
                    if has_hold then
                        app:open_report_entry(file,e);app.view_transition=nil;app:playback_action('play')
                        assert(app.playback.source:isPlaying())
                        for _,event in ipairs(app.playback.plan.events) do if bindings[tostring(event.code)] then
                            held=held+1;assert(event.command==bindings[tostring(event.code)])
                        end end
                        app:playback_action('stop')
                    end
                    if file.is_main and e.name=='pd010' then source,target=file,e end
                end
            end end
            assert(held==32 and target)
            app:open_report_entry(source,target);app.view_transition=nil
            for code=9,14 do
                if app.current_work.steps[1].code~=code then assert(app:replace_command(1,code)) end
                app:playback_action('play');assert(app.playback.plan.events[1].command==bindings[tostring(code)])
                app.selected_step_index=1;app:audition_command(code)
                assert(app.playback.audition:isPlaying() and app.status_text:find('audible timing',1,true))
                app.playback.audition:stop();app:playback_action('stop')
            end
            app:replace_command(1,9);app:playback_action('play');app:playback_action('play')
            assert(not app.playback.playing)
            app:playback_action('seek',.5);app:playback_action('play');assert(app.playback.source:isPlaying())
            app:playback_action('stop');app.playback.range_start,app.playback.range_end=6,12
            if not app.playback.looping then app:playback_action('loop') end
            app:playback_action('play');assert(app.playback.source:isLooping())
            assert(#app.playback.plan.continuations>0 and app.playback.plan.continuations[1].command=='R42_HOLD_CHU')
            started=love.timer.getTime();stage,captured=2,false
        elseif stage==2 and captured and love.timer.getTime()-started>.7 then
            assert(app.playback.source:isPlaying() and app.playback.position<app.playback.plan.duration)
            local tick=require('core.playback').tick(app.playback);assert(tick>=6 and tick<=12)
            require('core.playback').stop(app.playback,true)
            save('report4-audio-result.txt','PASS: R43 six held-Chu previews, dummy-Hey replacement/undo and held-tail loop; R42 all 32 original held events, six held replacement previews/auditions, pause/seek/resume and actual held-tail range looping/playhead. Audible alignment remains unverified.\n')
            app.allow_quit=true;love.event.quit(0);stage=3
        end
    end
    love.draw=function()
        app:draw()
        if (stage==1 or stage==2) and not captured then
            local name=stage==1 and 'report4-held-range.png' or 'report42-held-range.png'
            love.graphics.captureScreenshot(function(img)save(name,img:encode('png'):getString());captured=true end)
        end
    end
    return app
end
return M
