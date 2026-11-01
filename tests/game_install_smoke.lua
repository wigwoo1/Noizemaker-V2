local M={}
function M.start(args)
    local root,out=assert(args[2]),assert(args[3])
    assert(root:gsub('\\','/'):lower()==(out..'/game'):gsub('\\','/'):lower(),'Only install into the disposable QA game copy')
    local function read(path)local f=assert(io.open(path,'rb'));local data=f:read('*a');f:close();return data end
    local function save(name,data)local f=assert(io.open(out..'/'..name,'wb'));f:write(data);f:close()end
    love.errorhandler=function(message)save('game-install-error.txt',tostring(message)..'\n'..debug.traceback());return function()return 1 end end
    io.popen=function()error('Game Apply used a shell')end;os.execute=function()error('Game Apply used a shell')end
    local App=require('ui.app');local format=require('core.format');require('ui.theme').init();love.window.setMode(960,600)
    local app=App.new();app.game_root=root;app.install_base=out..'/backups';app.config_path=out..'/install.ini';app:resize(960,600)
    app:load_report(1);local r=app.reports_tab.report
    local first,second=r.files[1]
    for _,file in ipairs(r.files) do if file.stem=='r12' and file.is_main then second=file end end
    local changedAgain=first.entries[1].steps[1]==3 and 5 or 3
    local original1,original2=read(first.path),read(second.path)
    local dance_original=read(root..'/r01_sh.bin');local english_dance=read(root..'/afs_english/r01_sh.bin')
    app:open_report_entry(first,first.entries[1]);app:replace_command(1,4)
    app:select_entry(app.entries[2]);local other=app.current_work.steps[1].code==5 and 4 or 5;app:replace_command(1,other)
    app:open_report_entry(second,second.entries[1]);local ending=app.current_work.steps[1].code==6 and 4 or 6;app:replace_command(1,ending)
    app:open_report_entry(first,first.entries[1]);app.view_transition=nil
    local stage,frames,captured=0,0,false
    local function toolbar(name)local b=app:buttons()[name];app:mousepressed(b.x+b.w/2,b.y+b.h/2,1)end
    local function modal(id)
        for _,hit in ipairs(app.modal_hits) do if hit.id==id then app:mousepressed(hit.rect.x+hit.rect.w/2,hit.rect.y+hit.rect.h/2,1);return end end
        error('Missing Apply modal action '..id)
    end
    love.update=function(dt)
        app:update(dt);frames=frames+1;if frames<4 then return end
        if stage==0 then
            toolbar('apply_all');assert(app.modal.title=='Apply All to game')
            assert(app.modal.message:find('3 changed sequences in 2 file(s)',1,true))
            stage,frames=1,0
        elseif stage==1 and captured then
            modal('cancel');assert(read(first.path)==original1 and read(second.path)==original2)
            toolbar('apply_all');stage,frames=2,0
        elseif stage==2 then
            modal('apply');assert(app.modal.title=='Applied to game')
            assert(format.parse(read(first.path))[1].steps[1]==4 and format.parse(read(second.path))[1].steps[1]==ending)
            stage,frames,captured=3,0,false
        elseif stage==3 and captured then
            modal('ok');app:replace_command(1,changedAgain);toolbar('apply')
            assert(app.modal.title=='Apply file to game' and app.modal.message:find('1 changed sequences in 1 file(s)',1,true),app.modal.title..': '..tostring(app.modal.message))
            stage,frames=4,0
        elseif stage==4 then
            modal('apply');assert(app.modal.title=='Applied to game')
            assert(format.parse(read(first.path))[1].steps[1]==changedAgain and format.parse(read(second.path))[1].steps[1]==ending)
            stage,frames=4.5,0
        elseif stage==4.5 then
            modal('ok');assert(app:save_project(out..'/installed.sc5project'))
            local fresh=App.new();fresh.game_root=root;fresh.install_base=app.install_base;fresh.config_path=out..'/reopen.ini';fresh:resize(960,600)
            fresh:restore_project(fresh:stage_project(out..'/installed.sc5project'),out..'/installed.sc5project')
            app=fresh;app.view_transition=nil;assert(app.current_work.steps[1].code==changedAgain)
            app:show_project_menu();stage,frames,captured=5,0,false
        elseif stage==5 and captured then
            modal('restore_game');assert(app.modal.title=='Restore game files');stage,frames=6,0
        elseif stage==6 then
            modal('restore');assert(app.modal.title=='Game files restored')
            assert(read(first.path)==original1 and read(second.path)==original2)
            stage,frames=6.5,0
        elseif stage==6.5 then
            modal('ok');app:load_report('dance');local file=app.reports_tab.report.files[1]
            app:open_report_entry(file,file.entries[1]);app:replace_command(1,4);app.view_transition=nil
            love.window.setMode(1280,720);app:resize(1280,720);toolbar('apply_all')
            assert(app.modal.title=='Apply All to game' and app.modal.message:find('r01_sh.bin',1,true)
                and not app.modal.message:find('afs_english',1,true))
            stage,frames,captured=7,0,false
        elseif stage==7 and captured then
            modal('apply');assert(app.modal.title=='Applied to game')
            assert(read(root..'/r01_sh.bin')~=dance_original and read(root..'/afs_english/r01_sh.bin')==english_dance)
            stage,frames=7.5,0
        elseif stage==7.5 then
            modal('ok');app:prompt_game_restore();stage,frames=8,0
        elseif stage==8 then
            modal('restore');assert(app.modal.title=='Game files restored')
            assert(read(root..'/r01_sh.bin')==dance_original and read(root..'/afs_english/r01_sh.bin')==english_dance)
            save('game-install-result.txt','PASS: actual Apply All/Apply File, scope, cancel-before-write, game-copy installation, project reopen, Restore controls, Dance root-only destination, untouched English-folder copy and both window sizes. No real game files written.\n')
            app.allow_quit=true;love.event.quit(0);stage=9
        end
    end
    love.draw=function()
        app:draw()
        if (stage==1 or stage==3 or stage==5 or stage==7) and frames>1 and not captured then
            local name=stage==1 and 'apply-all-review.png' or stage==3 and 'apply-all-installed.png' or stage==5 and 'apply-restore-menu.png' or 'apply-dance-root.png'
            love.graphics.captureScreenshot(function(img)save(name,img:encode('png'):getString());captured=true end)
        end
    end
    return app
end
return M
