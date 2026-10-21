local M={}
function M.start(args)
    local App=require('ui.app')
    local theme=require('ui.theme')
    local root,out=assert(args[2]),assert(args[3])
    local function save(name,data)local f=assert(io.open(out..'/'..name,'wb'));f:write(data);f:close()end
    love.errorhandler=function(message)
        save('route-error.txt',tostring(message)..'\n'..debug.traceback())
        return function()return 1 end
    end
    local app=App.new();app.game_root=root;app.config_path=out..'/route-ui.ini'
    theme.init();love.window.setMode(960,600);app:resize(960,600);app:load_report(1)
    app.active_view='reports';app.view_transition=nil
    local state=app.reports_tab
    assert(state.report.cpu_route and #state.report.cpu_route==58,'actual runtime recognizes source hashes and recorded order')
    local stage,frames,captured=0,0,false
    local function click(kind)
        for _,hit in ipairs(state.hits) do
            if hit.kind==kind then app:mousepressed(hit.rect.x+hit.rect.w/2,hit.rect.y+hit.rect.h/2,1);return end
        end
        error('Missing browser control '..kind)
    end
    local function navigate(kind)
        for _,hit in ipairs(app.playback_hits) do
            if hit.kind==kind then app:mousepressed(hit.rect.x+hit.rect.w/2,hit.rect.y+hit.rect.h/2,1);app.view_transition=nil;return end
        end
        error('Missing route transport control '..kind)
    end
    love.update=function(dt)
        app:update(dt);frames=frames+1
        if frames<4 then return end
        if stage==0 and captured then
            assert(state.content_height==58*66,'default browser shows 58 ordered route entries')
            click('order');assert(state.order_mode=='files','Order switches to files')
            stage,frames=1,0
        elseif stage==1 then
            assert(state.content_height==99*66,'file order retains all stored main entries')
            click('variants');stage,frames=2,0
        elseif stage==2 then
            assert(state.content_height==258*66,'all file variants remain accessible')
            click('order');stage,frames=3,0
        elseif stage==3 then
            assert(state.content_height==58*66 and not state.include_variants,'CPU order separates alternatives again')
            click('entry');app.view_transition=nil
            assert(app.current_file_name=='r11_sh.bin' and app.selected_entry.name=='pd001','first CPU route row opens its exact file/phrase')
            app:replace_command(1,4)
            stage,frames=4,0
        elseif stage==4 then
            navigate('next_phrase');assert(app.selected_entry.name=='pd002','Next button follows recorded order')
            stage,frames=5,0
        elseif stage==5 then
            navigate('previous_phrase');assert(app.selected_entry.name=='pd001' and app.current_work.steps[1].code==4,'Prev preserves the earlier edit')
            app:switch_view('reports');app.view_transition=nil
            state.query='Kin Kon Kan';state.scroll=0
            stage,frames=6,0
        elseif stage==6 then
            assert(state.content_height==17*66,'search filters recorded route without duplicate aliases')
            click('entry');app.view_transition=nil
            assert(app.current_file_name=='r12_sh.bin' and app.selected_entry.name=='pd001','encounter search opens the first R12 input')
            stage,frames=7,0
        elseif stage==7 then
            navigate('previous_phrase');assert(app.current_file_name=='r11_sh.bin' and app.selected_entry.name=='pk001','Prev crosses part boundary to final R11 call')
            stage,frames,captured=8,0,false
        elseif stage==8 and captured then
            navigate('next_phrase');assert(app.current_file_name=='r12_sh.bin','Next crosses back without confusing duplicate IDs')
            save('route-result.txt','PASS: actual source-bound CPU route, 58/99/258 mode counts, variant separation, search, exact file identity, Prev/Next clicks, draft preservation, and cross-part navigation at 960x600.\n')
            require('core.playback').stop(app.playback,true);app.allow_quit=true;love.event.quit(0);stage=9
        end
    end
    love.draw=function()
        app:draw()
        if (stage==0 or stage==8) and frames>1 and not captured then
            captured=true
            local name=stage==0 and 'cpu-route-browser.png' or 'cpu-route-editor.png'
            love.graphics.captureScreenshot(function(img)save(name,img:encode('png'):getString())end)
        end
    end
    return app
end
return M
