-- Two real app processes run save, then reopen the same on-disk project.
local M={}
function M.start(args)
    local root,out,mode=assert(args[2]),assert(args[3]),assert(args[4])
    local App=require('ui.app')
    local theme=require('ui.theme')
    local function save(name,value)
        local f=assert(io.open(out..'/'..name,'wb'));assert(f:write(value));f:close()
    end
    love.errorhandler=function(message)
        save('project-'..mode..'-error.txt',tostring(message)..'\n'..debug.traceback())
        return function()return 1 end
    end
    io.popen=function()error('Project UI attempted io.popen')end
    os.execute=function()error('Project UI attempted os.execute')end
    local app=App.new();app.game_root=root;app.config_path=out..'/project-ui.ini'
    theme.init();love.window.setMode(960,600);app:resize(960,600);app:load_report(1)
    local r=app.reports_tab.report
    local f1,f2=r.files[1]
    for _,file in ipairs(r.files) do if file.stem=='r12' and file.is_main then f2=file end end
    app:open_report_entry(f1,f1.entries[1]);app.view_transition=nil
    local path=out..'/persistent.sc5project'
    if mode=='save' then
        app:replace_command(1,4)
        app:open_report_entry(f2,f2.entries[1]);app.view_transition=nil
        app:replace_command(1,6)
    else assert(not app:project_unsaved(),'fresh process starts without edits')end
    local stage,frames,captured=0,0,false
    local function click_modal(id)
        for _,hit in ipairs(app.modal_hits) do
            if hit.id==id then app:mousepressed(hit.rect.x+hit.rect.w/2,hit.rect.y+hit.rect.h/2,1);return end
        end
        error('Missing modal button '..id)
    end
    love.update=function(dt)
        app:update(dt);frames=frames+1
        if frames<3 then return end
        if stage==0 then
            for _,hit in ipairs(app.header_hits) do
                if hit.id=='project' then app:mousepressed(hit.rect.x+10,hit.rect.y+10,1);break end
            end
            assert(app.modal and app.modal.title=='Project','Project button opens its in-app menu')
            stage,frames=1,0
        elseif stage==1 then
            click_modal(mode=='save' and 'save' or 'open')
            assert(app.modal and app.modal.input,'Project action opens in-app path input')
            app.modal.input.text=mode=='save' and out..'/wrong.bin' or out..'/missing.sc5project'
            stage,frames=2,0
        elseif stage==2 then
            click_modal(mode=='save' and 'save' or 'open')
            assert(app.modal and app.modal.input.error,'Invalid path gives feedback without losing the dialog')
            app.modal.input.text=path
            stage,frames=3,0
        elseif stage==3 and captured then
            click_modal(mode=='save' and 'save' or 'open')
            assert(not app.modal and not app:project_unsaved(),'successful operation leaves a clean project')
            assert(app.current_file_name=='r12_sh.bin' and app.current_work.steps[1].code==6,
                'selected R12 phrase and edit survive save/reopen')
            stage,frames,captured=4,0,false
        elseif stage==4 then
            if mode=='load' then
                app:open_report_entry(f1,f1.entries[1]);app.view_transition=nil
                assert(app.current_work.steps[1].code==4,'previous process R11 edit is restored separately')
                app:replace_command(1,5)
                assert(app:project_unsaved(),'new edit is unsaved')
                local original=love.keyboard.isDown
                love.keyboard.isDown=function(key)return key=='lctrl'end
                app:keypressed('s')
                love.keyboard.isDown=original
                assert(not app:project_unsaved(),'Ctrl+S saves the reopened project in place')
                app:replace_command(1,3)
                love.event.quit(0) -- Exercise main.lua's real love.quit callback.
                stage,frames,captured=5,0,false
            else stage,frames=7,0 end
        elseif stage==5 and captured then
            click_modal('cancel')
            assert(not app.modal and app.current_work.steps[1].code==3,'Cancel close keeps pending edit')
            assert(app:request_quit(),'second close is also protected')
            stage,frames=6,0
        elseif stage==6 then
            local quit=love.event.quit
            local requested=false
            love.event.quit=function()requested=true end
            click_modal('save')
            love.event.quit=quit
            assert(requested and app.allow_quit and not app:project_unsaved(),'Save first saves successfully before requesting exit')
            stage,frames=7,0
        elseif stage==7 and frames>5 then
            save('project-'..mode..'-result.txt','PASS: Project menu/path validation, '..
                (mode=='save' and 'two-file save with real SHA-256.' or
                'fresh-process restore, duplicate names, Ctrl+S overwrite, and cancel/save-before-close.')..' Shell calls forbidden.\n')
            require('core.playback').stop(app.playback,true)
            love.event.quit(0);stage=8
        end
    end
    love.draw=function()
        app:draw()
        if (stage==3 or stage==5) and frames>1 and not captured then
            captured=true
            local name=stage==3 and ('project-'..mode..'-panel.png') or 'project-unsaved-close.png'
            love.graphics.captureScreenshot(function(img)save(name,img:encode('png'):getString())end)
        end
    end
    return app
end
return M
