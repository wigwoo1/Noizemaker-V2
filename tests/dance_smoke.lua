local M={}
function M.start(args)
    local root,out=assert(args[2]),assert(args[3])
    local App=require('ui.app');local theme=require('ui.theme')
    local function save(name,data)local f=assert(io.open(out..'/'..name,'wb'));f:write(data);f:close()end
    love.errorhandler=function(message)
        save('dance-error.txt',tostring(message)..'\n'..debug.traceback());return function()return 1 end
    end
    theme.init();love.window.setMode(960,600)
    local app=App.new();app.game_root=root;app.config_path=out..'/dance.ini'
    app:resize(960,600);app:load_report(1);app.active_view='reports';app.view_transition=nil
    local state=app.reports_tab
    local stage,frames,captured,started=0,0,false,0
    local file,original_timing,original_count
    local function hit(list,kind,number)
        for _,item in ipairs(list) do
            if item.kind==kind and (not number or item.number==number) then
                app:mousepressed(item.rect.x+item.rect.w/2,item.rect.y+item.rect.h/2,1);return
            end
        end
        error('Missing Dance control '..kind)
    end
    local function modal(id)
        for _,item in ipairs(app.modal_hits) do
            if item.id==id then app:mousepressed(item.rect.x+item.rect.w/2,item.rect.y+item.rect.h/2,1);return end
        end
        error('Missing Dance modal control '..id)
    end
    love.update=function(dt)
        app:update(dt);frames=frames+1;if frames<4 then return end
        if stage==0 then
            hit(state.hits,'report','dance');stage,frames=1,0
        elseif stage==1 and captured then
            assert(state.report.mode_id=='ulala-dance' and state.content_height==200*66)
            local can_play=false;for _,item in ipairs(state.hits) do if item.kind=='play_report' then can_play=true end end
            assert(can_play,'Recorded Dance playback control is available')
            file=state.report.files[1];hit(state.hits,'order');stage,frames=1.5,0
        elseif stage==1.5 then
            assert(state.content_height==100*66)
            hit(state.hits,'variants');stage,frames=2,0
        elseif stage==2 then
            assert(state.content_height==200*66)
            hit(state.hits,'variants');hit(state.hits,'search');app:textinput('q0911')
            stage,frames=3,0
        elseif stage==3 then
            assert(state.content_height==66,'Shared question search has one base target')
            hit(state.hits,'entry');app.view_transition=nil
            assert(app.selected_entry.name=='pd0909' and #app.selected_entry.dance.uses==2)
            stage,frames,captured=4,0,false
        elseif stage==4 and captured then
            app:open_report_entry(file,file.entries[1]);app.view_transition=nil
            original_timing,original_count=app.current_work.timing,#app.current_work.steps
            stage,frames=5,0
        elseif stage==5 then
            local palette
            for _,item in ipairs(app.controls_hits) do if item.kind=='insert_move' and item.move.code==4 then palette=item.rect end end
            assert(palette and app.timeline_render.hits[1])
            local node=app.timeline_render.hits[1]
            app:mousepressed(palette.x+palette.w/2,palette.y+palette.h/2,1)
            app:mousemoved(node.x,node.y);app:mousereleased(node.x,node.y,1)
            assert(app.current_work.steps[1].code==4 and #app.current_work.steps==original_count and app.current_work.timing==original_timing)
            app:undo();app:redo();assert(app.current_work.steps[1].code==4)
            app:playback_action('play')
            assert(app.playback.source and app.playback.source:isPlaying() and app.playback.source:getChannelCount()==2)
            assert(app.playback.plan.music and not app.playback.plan.music.timing_checked and app.playback.plan.events[1].command:match('^DANCE_'))
            app:playback_action('stop')
            local by_name={};for _,entry in ipairs(file.entries) do by_name[entry.name]=entry end
            for _,case in ipairs({{'pd0301','DANCE_V4_M4',1},{'pd0501','DANCE_V1_M4',1},
                {'pd0701','DANCE_V2_M4',1},{'pd0801','DANCE_V3_M4',1},
                {'pd0603','DANCE_V10_M4',9},{'pd0604','DANCE_V11_M4',9}}) do
                app:open_report_entry(file,by_name[case[1]]);app.view_transition=nil
                app.selected_step_index=1;app:audition_command(case[3])
                local sample=app:command_audio_bank().samples[case[2]]
                assert(sample.source and app.playback.audition:isPlaying(),'Native special sample actually auditioned')
                app.playback.audition:stop()
                app:playback_action('play')
                assert(app.playback.source:isPlaying() and app.playback.source:getChannelCount()==2
                    and app.playback.plan.music and app.playback.plan.events[1].command:match('^DANCE_'))
                app:playback_action('seek',.5);app:playback_action('play');assert(not app.playback.playing)
                app:playback_action('play');assert(app.playback.source:isPlaying())
                app:playback_action('stop')
            end
            app:playback_action('music');app:playback_action('play')
            assert(not app.playback.plan.music and app.playback.source:getChannelCount()==1)
            app:playback_action('stop');app:playback_action('music')
            app:open_report_entry(file,by_name.pd0604);app.view_transition=nil
            app.playback.range_start,app.playback.range_end=6,12
            app:playback_action('loop');app:playback_action('play')
            assert(app.playback.plan.music and #app.playback.plan.continuations>0)
            assert(app.playback.source:isLooping() and app.playback.source:getChannelCount()==2)
            started=love.timer.getTime();stage,frames,captured=5.5,0,false
        elseif stage==5.5 and captured and love.timer.getTime()-started>.7 then
            assert(app.playback.source:isPlaying() and app.playback.position<app.playback.plan.duration)
            local tick=require('core.playback').tick(app.playback)
            assert(tick>=6 and tick<=12,'Loop playhead stays inside the selected music/held-call range')
            app:playback_action('stop');app:playback_action('loop');app:playback_action('range_all')
            app:open_report_entry(file,file.entries[1]);app.view_transition=nil
            stage,frames,captured=6,0,false
        elseif stage==6 and captured then
            app:show_project_menu();stage,frames=7,0
        elseif stage==7 then
            modal('save_as');assert(app.modal.title=='Save project')
            app.modal.input.text=out..'/ulala.sc5project';stage,frames=8,0
        elseif stage==8 then
            modal('save');assert(not app.modal and not app:project_unsaved())
            local other=App.new();other.game_root=root;other.config_path=out..'/restored.ini';other:resize(960,600)
            other:restore_project(other:stage_project(out..'/ulala.sc5project'),out..'/ulala.sc5project')
            app=other;state=app.reports_tab;app.view_transition=nil
            assert(state.number=='dance' and app.current_work.steps[1].code==4)
            app:prompt_report_export();stage,frames,captured=9,0,false
        elseif stage==9 and captured then
            assert(app.modal.title=="Export Ulala's Dance")
            app.modal.input.text=root..'/forbidden-dance-export';modal('export')
            assert(app.modal and app.modal.input.error,'Installed-game output is rejected')
            app.modal.input.text=out..'/dance-bundle';app.modal.input.error=nil
            stage,frames=10,0
        elseif stage==10 then
            modal('export');assert(app.modal.title=='Mode export complete')
            assert(not app:project_unsaved(),'Export does not change the saved project')
            stage,frames,captured=11,0,false
        elseif stage==11 and captured then
            save('dance-result.txt','PASS: mode controls, 100/200 branches, search/labels, palette editing/undo/redo, native special/held calls, stereo music with playback/pause/seek, actual repeated range-loop/playhead and music-off controls, project Save As/reopen and safe shared-file export.\n')
            require('core.playback').stop(app.playback,true);app.allow_quit=true;love.event.quit(0);stage=12
        end
    end
    love.draw=function()
        app:draw()
        if (stage==1 or stage==4 or stage==5.5 or stage==6 or stage==9 or stage==11) and frames>1 and not captured then
            local name=stage==1 and 'dance-browser.png' or stage==4 and 'dance-shared-entry.png' or
                stage==5.5 and 'dance-music-range.png' or stage==6 and 'dance-editor.png' or stage==9 and 'dance-export.png' or 'dance-complete.png'
            love.graphics.captureScreenshot(function(img)save(name,img:encode('png'):getString());captured=true end)
        end
    end
    return app
end
return M
