local M={}
function M.start(args)
    local root,out=assert(args[2]),assert(args[3])
    local function save(name,data)local f=assert(io.open(out..'/'..name,'wb'));f:write(data);f:close()end
    love.errorhandler=function(message)
        save('inspector-error.txt',tostring(message)..'\n'..debug.traceback())
        return function()return 1 end
    end
    love.audio.setVolume(0)
    require('ui.theme').init();love.window.setMode(960,600)
    local app=require('ui.app').new();app.game_root=root;app.config_path=out..'/inspector-test.ini'
    app:resize(960,600);app:load_report(1)
    local file=app.reports_tab.report.files[1]
    app:open_report_entry(file,file.entries[1]);app.view_transition=nil;app.selected_step_index=2
    local original=require('core.json').encode(app:capture_project())
    local stage,frames,captured=0,0,false
    local function hit(kind)
        for _,item in ipairs(app.inspector_hits) do if item.kind==kind then return item end end
    end
    local function scroll(amount)
        local mouse=love.mouse.getPosition
        love.mouse.getPosition=function()return app.layout.right.x+50,app.layout.right.y+100 end
        app:wheelmoved(0,amount);love.mouse.getPosition=mouse
    end
    love.update=function(dt)
        app:update(dt);frames=frames+1
        if frames<4 then return end
        if stage==0 then
            assert(app.inspector_scroll_max>0,'Selected step inspector overflows at 960x600')
            assert(not hit('delete'),'Offscreen Delete must have no clickable hit region')
            local count=#app.current_work.steps
            app:mousepressed(app.layout.right.x+140,app.layout.right.y+app.layout.right.h+5,1)
            assert(#app.current_work.steps==count,'Click below the panel cannot delete a step')
            scroll(-100);assert(app.inspector_scroll==app.inspector_scroll_max,'Scroll clamps to content end')
            stage,frames,captured=1,0,false
        elseif stage==1 and captured then
            local button=assert(hit('delete'),'Delete becomes reachable after scrolling')
            local viewport=app.inspector_viewport
            assert(button.rect.y>=viewport.y and button.rect.y+button.rect.h<=viewport.y+viewport.h)
            app:mousepressed(button.rect.x+button.rect.w/2,button.rect.y+button.rect.h/2,1)
            assert(#app.current_work.steps==2,'Scrolled Delete acts on the selected step')
            app:undo();assert(#app.current_work.steps==3 and app.current_validation.ok)
            assert(require('core.json').encode(app:capture_project())==original,
                'Scrolling and Delete undo preserve the original project data')
            -- A display-only long warning checks actual wrapping and content
            -- height; it is not a game-compatibility or validation fixture.
            app.current_validation.warnings={'Display layout test: '..string.rep('A long explanation must remain readable when wrapped. ',9)}
            stage,frames=2,0
        elseif stage==2 then
            assert(app.inspector_scroll_max>150,'Wrapped warning extends scrollable content')
            scroll(-100);stage,frames,captured=3,0,false
        elseif stage==3 and captured then
            scroll(100);assert(app.inspector_scroll==0,'Upward scroll clamps at zero')
            app.current_validation=app:validate_work(app.selected_entry,app.current_work)
            love.window.setMode(1280,720);app:resize(1280,720)
            stage,frames,captured=4,0,false
        elseif stage==4 and captured then
            assert(app.inspector_scroll==0)
            app:load_work_for_entry(file.entries[2]);assert(app.inspector_scroll==0,'Changing phrase resets details scroll')
            save('inspector-result.txt','PASS: 960x600 clipping, offscreen-hit rejection, wheel/bounds, reachable Delete and undo, unchanged project data, wrapped warnings, resize, and phrase scroll reset.\n')
            app.allow_quit=true;love.event.quit(0);stage=5
        end
    end
    love.draw=function()
        app:draw()
        if (stage==1 or stage==3 or stage==4) and frames>2 and not captured then
            captured=true
            local filename=stage==1 and 'inspector-scrolled-960.png' or stage==3 and 'inspector-warning-960.png' or 'inspector-1280.png'
            love.graphics.captureScreenshot(function(img)save(filename,img:encode('png'):getString())end)
        end
    end
    return app
end
return M
