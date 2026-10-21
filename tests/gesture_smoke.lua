local M = {}
function M.start(args)
    local App = require("ui.app")
    local theme = require("ui.theme")
    local root,out=assert(args[2]),assert(args[3])
    local function save(name,data)
        local f=assert(io.open(out.."/"..name,"wb"));f:write(data);f:close()
    end
    love.errorhandler=function(msg)
        save("gesture-error.txt",tostring(msg).."\n"..debug.traceback())
        return function() return 1 end
    end
    theme.init()
    love.window.setMode(1280,720)
    local app=App.new()
    app.game_root,app.config_path=root,out.."/gesture-test.ini"
    app:resize(1280,720);app:load_report(1)
    local file=assert(app.reports_tab.report).files[1]
    app:open_report_entry(file,file.entries[1]);app.view_transition=nil
    local frame,done,captured=0,false,false
    local function palette(code)
        app:draw()
        for _,hit in ipairs(app.controls_hits) do
            if hit.kind=="insert_move" and hit.move.code==code then return hit.rect.x+hit.rect.w/2,hit.rect.y+hit.rect.h/2 end
        end
        error("Palette command missing")
    end
    local function point(tick)
        app:draw()
        return app.timeline_render.plot.x+tick*app.timeline_render.scale, app.timeline_render.hits[1].y
    end
    local function drag(code,x,y)
        local sx,sy=palette(code)
        app:mousepressed(sx,sy,1);app:mousemoved(x,y);app:mousereleased(x,y,1)
    end
    love.update=function()
        frame=frame+1
        if frame==3 then
            local initial=#app.current_work.steps
            app.palette_mode="place"
            local x,y=palette(6)
            app:mousepressed(x,y,1);app:mousereleased(x,y,1)
            assert(app.pending_insert and app.pending_insert.code==6,"click must arm LEFT")
            assert(#app.current_work.steps==initial,"arming alone must not edit chart")
            x,y=point(12);app:mousepressed(x,y,1);app:mousereleased(x,y,1)
            assert(#app.current_work.steps==initial+1 and app.current_work.steps[2].code==6,"choose-then-click inserts LEFT")
            assert(app.current_work.steps[1].gap==12 and app.current_work.steps[2].gap==12,"insertion preserves later note times")
            app:undo()
            local gap=app.current_work.steps[2].gap
            x,y=point(24);drag(4,x,y)
            assert(#app.current_work.steps==initial and app.current_work.steps[2].code==4,"drop onto existing note replaces it")
            assert(app.current_work.steps[2].gap==gap,"replacement preserves spacing")
            app:undo();assert(app.current_work.steps[2].code==3,"drop replacement undo")
            app:redo();assert(app.current_work.steps[2].code==4,"drop replacement redo")
            x,y=point(36);drag(1,x,y)
            assert(#app.current_work.steps==initial+1 and app.current_work.steps[3].code==1,"drag to empty position inserts CHU")
            assert(app.current_work.steps[2].gap==12 and app.current_work.steps[3].gap==12,"drop preserves later note timing")
            app:undo()
            drag(5,10,10)
            assert(#app.current_work.steps==initial,"drop outside timeline cancels")
            x,y=palette(6);app:mousepressed(x,y,1)
            x,y=point(36);app:mousemoved(x,y)
            assert(app.palette_drag and app.palette_drag.moved,"drag preview remains visible while held")
            done=true
        end
    end
    love.draw=function()
        app:draw()
        if done and not captured then
            captured=true
            love.graphics.captureScreenshot(function(image)
                save("gesture-drag-preview.png",image:encode("png"):getString())
                app:mousereleased(10,10,1)
                require("core.playback").stop(app.playback,true)
                save("gesture-result.txt","PASS: choose then click, drag insert, drop replace, timing, undo, redo, outside cancellation, and drag preview.\n")
                print("PASS: real palette and timeline gesture handlers")
                love.event.quit(0)
            end)
        end
    end
end
return M
