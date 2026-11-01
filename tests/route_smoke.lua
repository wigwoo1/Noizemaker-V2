local M={}
function M.start(args)
    local App=require('ui.app')
    local theme=require('ui.theme')
    local root,out=assert(args[2]),assert(args[3])
    local second=args[4]=='report2'
    local number=second and 2 or 1
    local count,stored,variants=second and 123 or 58,second and 193 or 99,second and 386 or 258
    local first_file,first_entry=second and 'r21_sh.bin' or 'r11_sh.bin',second and 'ps001' or 'pd001'
    local next_entry=second and 'ps002' or 'pd002'
    local search,search_count=second and 'Pon Piriri' or 'Kin Kon Kan',second and 41 or 17
    local search_file,search_entry=second and 'r23_sh.bin' or 'r12_sh.bin',second and 'ps001' or 'pd001'
    local previous_file=second and 'r22_sh.bin' or 'r11_sh.bin'
    local previous_entry='pk001'
    if args[4]=='report3' then
        number,count,stored,variants=3,56,137,274
        first_file,first_entry,next_entry='r31_sh.bin','pd001','pd002'
        search,search_count='Final call',1
        search_file,search_entry='r31_sh.bin','pk001'
        previous_file,previous_entry='r31_sh.bin','pr032'
    end
    if args[4]=='report5' then
        number,count,stored,variants=5,54,75,150
        first_file,first_entry,next_entry='r51_sh.bin','pd001','pd002'
        search,search_count='Robotic band',34
        search_file,search_entry='r52_sh.bin','pr001'
        previous_file,previous_entry='r51_sh.bin','ps010'
    end
    if args[4]=='report6' then
        number,count,stored,variants=6,67,70,140
        first_file,first_entry,next_entry='r61_sh.bin','ps001','ps002'
        search,search_count='Final call',1
        search_file,search_entry='r62_sh.bin','pk001'
        previous_file,previous_entry='r62_sh.bin','pr007p'
    end
    local replacement
    local function save(name,data)local f=assert(io.open(out..'/'..name,'wb'));f:write(data);f:close()end
    love.errorhandler=function(message)
        save('route-error.txt',tostring(message)..'\n'..debug.traceback())
        return function()return 1 end
    end
    local app=App.new();app.game_root=root;app.config_path=out..'/route-ui.ini'
    theme.init();love.window.setMode(960,600);app:resize(960,600);app:load_report(number)
    app.active_view='reports';app.view_transition=nil
    local state=app.reports_tab
    assert(state.report.cpu_route and #state.report.cpu_route==count,'actual runtime recognizes source hashes and recorded order')
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
            assert(state.content_height==count*66,'default browser shows observed route entries')
            if second then
                local play
                for _,hit in ipairs(state.hits) do if hit.kind=='play_report' then play=true end end
                assert(play,'Report 2 has its own report playback control')
            end
            click('order');assert(state.order_mode=='files','Order switches to files')
            stage,frames=1,0
        elseif stage==1 then
            assert(state.content_height==stored*66,'file order retains all stored main entries')
            click('variants');stage,frames=2,0
        elseif stage==2 then
            assert(state.content_height==variants*66,'all file variants remain accessible')
            click('order');stage,frames=3,0
        elseif stage==3 then
            assert(state.content_height==count*66 and not state.include_variants,'CPU order separates alternatives again')
            click('entry');app.view_transition=nil
            assert(app.current_file_name==first_file and app.selected_entry.name==first_entry,'first CPU route row opens its exact file/phrase')
            replacement=app.current_work.steps[1].code==4 and 5 or 4
            app:replace_command(1,replacement)
            stage,frames=4,0
        elseif stage==4 then
            navigate('next_phrase');assert(app.selected_entry.name==next_entry,'Next button follows recorded order')
            stage,frames=5,0
        elseif stage==5 then
            navigate('previous_phrase');assert(app.selected_entry.name==first_entry and app.current_work.steps[1].code==replacement,'Prev preserves the earlier edit')
            app:switch_view('reports');app.view_transition=nil
            state.query=search;state.scroll=0
            stage,frames=6,0
        elseif stage==6 then
            assert(state.content_height==search_count*66,'search filters recorded route without duplicate aliases')
            click('entry');app.view_transition=nil
            assert(app.current_file_name==search_file and app.selected_entry.name==search_entry,'encounter search opens the correct section')
            stage,frames=7,0
        elseif stage==7 then
            navigate('previous_phrase');assert(app.current_file_name==previous_file and app.selected_entry.name==previous_entry,'Prev reaches the correct preceding route phrase')
            stage,frames,captured=8,0,false
        elseif stage==8 and captured then
            navigate('next_phrase');assert(app.current_file_name==search_file,'Next crosses back without confusing duplicate IDs')
            save('route-result.txt','PASS: Report '..number..' source-bound CPU route, '..count..'/'..stored..'/'..variants..' mode counts, variant separation, search, exact file identity, Prev/Next clicks, draft preservation, and cross-part navigation at 960x600.\n')
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
