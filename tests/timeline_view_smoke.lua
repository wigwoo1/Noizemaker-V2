local M={}
function M.start(args)
    local root,out,path=assert(args[2]),assert(args[3]),assert(args[4])
    local function save(name,data)local f=assert(io.open(out..'/'..name,'wb'));f:write(data);f:close()end
    love.errorhandler=function(message)
        save('timeline-view-error.txt',tostring(message)..'\n'..debug.traceback())
        return function()return 1 end
    end
    love.audio.setVolume(0)
    require('ui.theme').init();love.window.setMode(960,600)
    local app=require('ui.app').new();app.game_root=root;app.config_path=out..'/view-test.ini'
    app:resize(960,600)
    app:restore_project(app:stage_project(path),path);app.view_transition=nil
    local timeline=require('ui.timeline')
    local baseline=require('core.json').encode(app:capture_project())
    local stage,frames,captured=0,0,false
    local function control(kind)
        app:draw()
        for _,hit in ipairs(app.timeline_render.view_hits) do
            if hit.kind==kind then
                app:mousepressed(hit.rect.x+hit.rect.w/2,hit.rect.y+hit.rect.h/2,1)
                app:mousereleased(hit.rect.x+hit.rect.w/2,hit.rect.y+hit.rect.h/2,1)
                return
            end
        end
        error('Missing viewport control '..kind)
    end
    love.update=function(dt)
        app:update(dt);frames=frames+1
        if frames<3 then return end
        if stage==0 then
            app:draw()
            assert(#app.current_work.steps==20 and app.timeline_render.view.zoom==4,
                'Dense imported chart opens at readable zoom')
            local render=app.timeline_render
            assert(render.view.first==0 and render.view.last==24)
            assert(timeline.tick_from_x(render,render.plot.x+render.plot.w/2)==12)
            for _,hit in ipairs(render.hits) do assert(hit.node.tick<=24,'Hidden notes must not have hit targets') end
            -- Buttons must remain view-only while a palette command is armed.
            app:arm_insert_move({code=3,label='UP'});control('pan_right')
            assert(app.pending_insert and #app.current_work.steps==20,'Pan must not insert the armed command')
            app:clear_pending_insert();app:draw()
            render=app.timeline_render
            assert(render.view.first==12 and render.view.last==36)
            assert(timeline.tick_from_x(render,render.plot.x)==12)
            assert(timeline.tick_from_x(render,render.plot.x+render.plot.w/2)==24,
                'Panned coordinates map to absolute chart ticks')
            local target
            for _,hit in ipairs(render.hits) do if hit.node.tick==24 then target=hit;break end end
            assert(target,'Known note remains selectable in panned view')
            local original=app.current_work.steps[target.index].code
            local gap=app.current_work.steps[target.index].gap
            app:mousepressed(target.x,target.y,1);app:mousereleased(target.x,target.y,1)
            assert(app.selected_step_index==target.index)
            local start
            for _,hit in ipairs(app.controls_hits) do
                if hit.kind=='insert_move' and hit.move.code==4 then start=hit.rect;break end
            end
            app:mousepressed(start.x+10,start.y+10,1);app:mousemoved(target.x,target.y)
            app:mousereleased(target.x,target.y,1)
            assert(app.current_work.steps[target.index].code==4 and app.current_work.steps[target.index].gap==gap,
                'Palette drop replaces the correct absolute note without moving it')
            app:undo();assert(app.current_work.steps[target.index].code==original)
            app.palette_mode='place';app:arm_insert_move({code=3,label='UP'})
            local insert_x=render.plot.x+(21-render.view.first)*render.scale
            local saved_mouse=love.mouse.getPosition
            love.mouse.getPosition=function()return insert_x,target.y end
            assert(app:insert_preview_info().tick==21,'Placement marker uses the panned absolute tick')
            love.mouse.getPosition=saved_mouse
            app:mousepressed(insert_x,target.y,1);app:mousereleased(insert_x,target.y,1)
            local inserted=false
            for _,node in ipairs(timeline.build_nodes(app:current_preview_entry())) do
                if node.tick==21 and node.code==3 then inserted=true end
            end
            assert(inserted and #app.current_work.steps==21,'Panned choose-then-click inserts at absolute tick 21')
            app:undo();app:clear_pending_insert()
            app:draw()
            local fit_button=app.timeline_render.view_hits[2].rect
            app:mousepressed(start.x+10,start.y+10,1)
            app:mousemoved(fit_button.x+10,fit_button.y+10)
            app:mousereleased(fit_button.x+10,fit_button.y+10,1)
            assert(#app.current_work.steps==20,'Dropping onto viewport toolbar must cancel placement')
            control('fit');assert(app.timeline_view.zoom==1 and app.timeline_view.first_tick==0)
            control('zoom_in');control('zoom_in')
            assert(app.timeline_view.zoom==4)
            control('pan_left');assert(app.timeline_view.first_tick==0,'Left pan clamps at zero')
            for i=1,10 do control('pan_right') end
            assert(app.timeline_view.first_tick==72,'Right pan clamps at final window')
            local mouse=love.mouse.getPosition
            love.mouse.getPosition=function()return app.layout.timeline.x+50,app.layout.timeline.y+100 end
            app:wheelmoved(0,1);love.mouse.getPosition=mouse
            assert(app.timeline_view.first_tick==60,'Wheel pans over the timeline')
            local keys=love.keyboard.isDown
            love.mouse.getPosition=function()return app.layout.timeline.x+50,app.layout.timeline.y+100 end
            love.keyboard.isDown=function(key)return key=='lctrl'end
            app:wheelmoved(0,1);assert(app.timeline_view.zoom==8,'Ctrl+wheel zooms')
            app:wheelmoved(0,-1)
            love.keyboard.isDown=keys;love.mouse.getPosition=mouse
            assert(require('core.json').encode(app:capture_project())==baseline,
                'Viewport and replacement undo preserve the exact project edits')
            -- Simulate a moving audio clock without producing sound.
            app.timeline_view={zoom=4,first_tick=0,follow=true}
            app.playback.plan=require('core.playback').plan(app:current_preview_entry())
            app.playback.position=2.5;app.playback.playing=true
            app:draw();assert(app.timeline_render.view.first==48,'Playing cursor advances the viewport')
            app.playback.playing=false;app.playback.plan=nil
            app.timeline_view={zoom=4,first_tick=0}
            stage,frames,captured=1,0,false
        elseif stage==1 and captured then
            love.window.setMode(1280,720);app:resize(1280,720)
            stage,frames,captured=2,0,false
        elseif stage==2 and captured then
            save('timeline-view-result.txt','PASS: dense project auto zoom, pan/fit controls, armed palette safety, absolute-tick selection/drop/insertion, undo, bounds, wheel/Ctrl+wheel, playhead following, unchanged project data, and layouts at 960/1280.\n')
            app.allow_quit=true;love.event.quit(0);stage=3
        end
    end
    love.draw=function()
        app:draw()
        if (stage==1 or stage==2) and frames>2 and not captured then
            captured=true
            love.graphics.captureScreenshot(function(img)
                save(stage==1 and 'dense-zoom-960.png' or 'dense-zoom-1280.png',img:encode('png'):getString())
            end)
        end
    end
    return app
end
return M
