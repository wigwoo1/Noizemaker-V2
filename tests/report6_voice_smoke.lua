local M={}
function M.start(args)
    local root,out=assert(args[2]),assert(args[3])
    local function save(name,data)local f=assert(io.open(out..'/'..name,'wb'));f:write(data);f:close()end
    love.errorhandler=function(message)
        save('report6-voice-error.txt',tostring(message)..'\n'..debug.traceback())
        return function()return 1 end
    end
    local App=require('ui.app');require('ui.theme').init()
    love.window.setMode(960,600);love.audio.setVolume(0)
    local app=App.new();app.game_root=root;app.config_path=out..'/report6-voice.ini';app:resize(960,600)
    app:load_report(6);app.active_view='reports';app.view_transition=nil
    local long,gap
    for _,row in ipairs(app.reports_tab.report.cpu_route) do
        if row.entry.name=='pd007y' then long=row end
        if row.entry.name=='ps003w' then gap=row end
    end
    assert(long and gap)
    local native=require('core.voice_report6_route_data')
    local key=native.phrases[long.event.file][long.entry.name].bindings[0].sample
    local stage,captured=0,false
    love.update=function(dt)
        app:update(dt)
        if stage==0 then
            app:open_report_entry(long.file,long.entry);app.view_transition=nil
            app:playback_action('play')
            local state=app.playback
            assert(state.source and state.source:isPlaying())
            assert(state.plan.events[1].command==key)
            local bank=app:command_audio_bank()
            assert(bank.samples[key] and bank.samples[key].info.duration>2.4)
            local warned=false
            for _,message in ipairs(state.plan.warnings) do
                if message:find('long Down',1,true) then warned=true end
            end
            assert(warned)
            stage=1
        elseif stage==1 and captured then
            app:playback_action('stop')
            app.selected_step_index=1;app:audition_command(13)
            assert(app.playback.audition and app.playback.audition:isPlaying())
            assert(app:replace_command(1,4),tostring(app.status_text))
            app:playback_action('play')
            assert(app.playback.plan.events[1].command=='RIGHT',
                'Changed code uses a new preview: '..tostring(app.playback.plan.events[1].command))
            app:undo();app:playback_action('stop')
            app:open_report_entry(gap.file,gap.entry);app.view_transition=nil
            app:playback_action('play')
            local plan=app.playback.plan
            assert(plan.events[5].command=='LEFT' and plan.events[6].command=='RIGHT',
                'Unobserved clock-gap calls stay provisional')
            app:playback_action('stop')
            save('report6-voice-result.txt',
                'PASS: Report 6 original long Down playback/audition, edited-code preview, gap-call provisional fallback and stop at 960x600.\n')
            app.allow_quit=true;love.event.quit(0);stage=2
        end
    end
    love.draw=function()
        app:draw()
        if stage==1 and not captured then
            love.graphics.captureScreenshot(function(img)
                save('report6-long-down.png',img:encode('png'):getString());captured=true
            end)
        end
    end
    return app
end
return M
