local M={}
function M.start(args)
    local root,out=assert(args[2]),assert(args[3])
    local App=require('ui.app');local theme=require('ui.theme')
    local function save(name,data)local f=assert(io.open(out..'/'..name,'wb'));f:write(data);f:close()end
    love.errorhandler=function(message)
        save('dance-score-error.txt',tostring(message)..'\n'..debug.traceback());return function()return 1 end
    end
    theme.init();love.window.setMode(960,600);love.audio.setVolume(0)
    local app=App.new();app.game_root=root;app.config_path=out..'/dance-score.ini'
    app:resize(960,600);app:load_report('dance');app.active_view='reports';app.view_transition=nil
    app.update_hover_state=function()end
    local stage,frames,captured,started=0,0,false,0
    local cache,changed
    local function hit(kind)
        for _,item in ipairs(app.reports_tab.hits) do if item.kind==kind then
            app:mousepressed(item.rect.x+item.rect.w/2,item.rect.y+item.rect.h/2,1);return
        end end
        error('Missing Dance score control '..kind)
    end
    local function missing(path)local f=io.open(path,'rb');if f then f:close();return false end;return true end
    love.update=function(dt)
        app:update(dt);frames=frames+1;if frames<4 then return end
        if stage==0 and captured then
            hit('play_report')
            local job=assert(app.playback.report_job);job:step(0)
            assert(job.owned and not missing(job.path))
            app:playback_action('stop')
            assert(not app.playback.report_job and not app.reports_tab.report_preparing and missing(job.path))
            local row=app.reports_tab.report.cpu_route[89]
            app:open_report_entry(row.file,row.entry,false,89);app.view_transition=nil
            changed=app.current_work.steps[1].code==1 and 2 or 1
            assert(app:replace_command(1,changed))
            app.active_view='reports';stage,frames=1,0
        elseif stage==1 then
            hit('play_report')
            assert(app.playback.report_job and not app.modal)
            local plan=app.playback.plan;local found={}
            for _,e in ipairs(plan.events) do if e.index==1 and (e.phrase==87 or e.phrase==89) then
                assert(e.code==changed);found[e.phrase]=true
            end end
            assert(found[87] and found[89]);stage=2
        elseif stage==2 and app.playback.source then
            local state=app.playback;cache=state.report_cache.path
            assert(state.report_cache.status=='done' and state.source:getChannelCount()==2)
            assert(#state.plan.phrases==200 and #state.plan.clips==225 and #state.plan.events==966)
            assert(state.plan.frames==math.floor(1264.9017503277034*48000+.5))
            assert(math.abs(state.source:getDuration('seconds')-state.plan.duration)<1/48000)
            local f=assert(io.open(cache,'rb'));assert(f:seek('end')==44+state.plan.frames*4);f:close()
            assert(not state.plan.response_timing_checked and not state.plan.alignment_verified)
            for _,i in ipairs({1,49,87,89,100,101,149,189,200}) do
                local phrase=state.plan.phrases[i];local target=phrase.response+.02
                app:playback_action('seek',target/state.plan.duration);app:update(0)
                assert(math.abs(state.source:tell('seconds')-target)<.03)
                assert(state.report_order==i and app.recorded_route_order==i and state.report_tick>0)
                assert(app.selected_entry.name==phrase.row.entry.name and app.current_file_name:lower()=='r01_sh.bin')
            end
            app:playback_action('seek',(state.plan.phrases[89].response+.02)/state.plan.duration);app:update(0)
            assert(app.current_work.steps[1].code==changed)
            app:playback_action('next_phrase');app:update(0)
            assert(state.report_order==90 and app.selected_entry.name=='pd0910')
            app:playback_action('previous_phrase');app:update(0)
            assert(state.report_order==89 and app.selected_entry.name=='pd0909')
            local title=require('ui.playback_bar').report_descriptor(state)
            assert(title:find("Ulala's Dance",1,true) and title:find('89/200',1,true) and title:find('sync unverified',1,true))
            app:playback_action('play');assert(not state.playing)
            app:playback_action('play');assert(state.source:isPlaying())
            stage,frames,captured=3,0,false
        elseif stage==2 and not app.playback.report_job then error('Dance render failed: '..app.status_text)
        elseif stage==3 and captured then
            app:playback_action('loop');assert(app.playback.source:isLooping())
            app:playback_action('seek',(app.playback.plan.duration-.05)/app.playback.plan.duration)
            started=love.timer.getTime();stage=4
        elseif stage==4 and love.timer.getTime()-started>.4 then
            assert(app.playback.source:isPlaying() and app.playback.position<1,'Whole-mode loop wraps its clock')
            app:playback_action('stop')
            assert(not app.playback.source and not app.playback.report_job and not app.playback.report_cache and missing(cache))
            assert(not app.reports_tab.playing_report and not app.reports_tab.report_preparing)
            local row=app.reports_tab.report.cpu_route[89]
            app:open_report_entry(row.file,row.entry,false,89);app.view_transition=nil
            assert(app.current_work.steps[1].code==changed,'Draft survives route playback')
            app:playback_action('play');assert(app.playback.mode~='report' and app.playback.source:isPlaying())
            assert(app.playback.plan.music and app.playback.source:getChannelCount()==2)
            require('core.playback').stop(app.playback,true)
            save('dance-score-result.txt','PASS: complete 200-visit / 225-cue / 966-call stereo render, actual browser Play/Cancel, shared draft at both visits, seek/playhead, pause/resume, occurrence-aware Prev/Next, real whole-mode loop, cache cleanup, and return to edited phrase playback. Audible synchronization remains provisional.\n')
            app.allow_quit=true;love.event.quit(0);stage=5
        end
    end
    love.draw=function()
        app:draw()
        if (stage==0 or stage==3) and frames>1 and not captured then
            local name=stage==0 and 'dance-score-browser.png' or 'dance-score-playback.png'
            love.graphics.captureScreenshot(function(img)save(name,img:encode('png'):getString());captured=true end)
        end
    end
    return app
end
return M
