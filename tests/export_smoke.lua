local M={}
function M.start(args)
    local root,out=assert(args[2]),assert(args[3])
    local App=require('ui.app')
    local theme=require('ui.theme')
    local function save(name,data)local f=assert(io.open(out..'/'..name,'wb'));f:write(data);f:close()end
    love.errorhandler=function(message)
        save('export-error.txt',tostring(message)..'\n'..debug.traceback())
        return function()return 1 end
    end
    io.popen=function()error('Report export attempted a shell')end
    os.execute=function()error('Report export attempted a shell')end
    local app=App.new();app.game_root=root;app.config_path=out..'/export-ui.ini'
    theme.init();love.window.setMode(960,600);app:resize(960,600);app:load_report(1)
    local r=app.reports_tab.report
    local main,variant,second=r.files[1]
    for _,file in ipairs(r.files) do
        if file.relative_path=='afs_english/r11_sh2.bin' then variant=file end
        if file.stem=='r12' and file.is_main then second=file end
    end
    app:open_report_entry(main,main.entries[1]);app:replace_command(1,4)
    app:open_report_entry(variant,variant.entries[1]);app:replace_command(1,4)
    app:open_report_entry(second,second.entries[1]);app:replace_command(1,6)
    app.view_transition=nil
    local work,undo=app.current_work,app.undo_stack
    local stage,frames,captured=0,0,false
    local function click(id)
        for _,hit in ipairs(app.modal_hits) do
            if hit.id==id then app:mousepressed(hit.rect.x+hit.rect.w/2,hit.rect.y+hit.rect.h/2,1);return end
        end
        error('Missing modal action '..id)
    end
    love.update=function(dt)
        app:update(dt);frames=frames+1
        if frames<4 then return end
        if stage==0 then
            for _,hit in ipairs(app.header_hits) do
                if hit.id=='project' then app:mousepressed(hit.rect.x+10,hit.rect.y+10,1);break end
            end
            assert(app.modal and app.modal.title=='Project','Project menu opens')
            stage,frames=1,0
        elseif stage==1 and captured then
            click('export')
            assert(app.modal.title=='Export Report 1' and app.modal.message:find('3 changed English files',1,true),'export summary lists correct file count and report')
            stage,frames=2,0
        elseif stage==2 then
            click('cancel')
            assert(not app.modal and app.current_work==work and app.current_work.steps[1].code==6,'cancel export retains edits')
            app:prompt_report_export()
            app.modal.input.text=root..'/forbidden-export'
            stage,frames=3,0
        elseif stage==3 then
            click('export')
            assert(app.modal and app.modal.input.error,'game-folder destination is rejected inside the panel')
            app.modal.input.text=out..'/report-1-bundle'
            app.modal.input.error=nil
            stage,frames,captured=4,0,false
        elseif stage==4 and captured then
            click('export')
            assert(app.modal and app.modal.title=='Report export complete','successful export has a completion panel')
            assert(app.current_work==work and app.undo_stack==undo and app:project_unsaved(),'export preserves editor history and unsaved project state')
            stage,frames,captured=5,0,false
        elseif stage==5 and captured then
            click('ok')
            app:prompt_report_export()
            app.modal.input.text=out..'/report-1-bundle'
            stage,frames=6,0
        elseif stage==6 then
            click('export')
            assert(app.modal and app.modal.input.error:find('already exists',1,true),'prior export cannot be overwritten')
            click('cancel')
            save('export-result.txt','PASS: actual Project/Export controls, report scope/count, cancel, game-folder rejection, three-file export, existing-folder protection, and preserved drafts/history. Shell calls forbidden.\n')
            require('core.playback').stop(app.playback,true)
            app.allow_quit=true;love.event.quit(0);stage=7
        end
    end
    love.draw=function()
        app:draw()
        if (stage==1 or stage==4 or stage==5) and frames>1 and not captured then
            captured=true
            local name=stage==1 and 'project-export-menu.png' or stage==4 and 'export-panel.png' or 'export-complete.png'
            love.graphics.captureScreenshot(function(img)save(name,img:encode('png'):getString())end)
        end
    end
    return app
end
return M
