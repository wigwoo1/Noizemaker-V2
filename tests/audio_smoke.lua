local M = {}
function M.start(args)
    local App = require("ui.app")
    local theme = require("ui.theme")
    local root, out = assert(args[2]), assert(args[3])
    local function save(name, value)
        local f = assert(io.open(out .. "/" .. name, "wb")); f:write(value); f:close()
    end
    love.errorhandler = function(msg)
        save("audio-error.txt", tostring(msg) .. "\n" .. debug.traceback())
        return function() return 1 end
    end
    local app = App.new()
    app.game_root, app.config_path = root, out .. "/audio-test.ini"
    theme.init()
    love.window.setMode(1280,720)
    app:resize(1280,720)
    app:load_report(1)
    local file = assert(app.reports_tab.report).files[1]
    app:open_report_entry(file,file.entries[1])
    app.view_transition = nil
    app:playback_action("play")
    assert(app.playback.source and app.playback.source:isPlaying(), "actual audio source must start")
    assert(app.playback.plan.music and app.playback.plan.music.name=="r11 music cue 9","opening music is loaded")
    assert(app.playback.source:getChannelCount()==2,"actual music source remains stereo")
    app:playback_action("music")
    assert(not app.playback.source and not app.playback.music_enabled,"music toggle discards old preview")
    app:playback_action("play")
    assert(not app.playback.plan.music and app.playback.source:getChannelCount()==1,"voice-only preview works")
    app:playback_action("music")
    app:playback_action("play")
    assert(app.playback.plan.music and app.playback.source:isPlaying(),"music preview regenerates after toggle")
    local stage, elapsed, paused, captured = 1, 0, 0, false
    love.update = function(dt)
        app:update(dt)
        elapsed = elapsed + dt
        if stage == 1 and elapsed > 0.3 then
            assert(app.playback.position > 0, "audio clock must advance")
            app:playback_action("play")
            paused = app.playback.position
            assert(not app.playback.playing, "pause")
            stage,elapsed = 2,0
        elseif stage == 2 and elapsed > 0.15 then
            assert(math.abs(app.playback.position-paused)<0.002, "paused clock must remain stable")
            app:playback_action("seek",0.5)
            assert(math.abs(app.playback.position-2)<0.002,"seek to the middle of a four-second phrase")
            app:playback_action("play")
            stage,elapsed = 3,0
        elseif stage == 3 and elapsed > 0.2 then
            assert(app.playback.position > 2,"resume from seek")
            app:playback_action("loop")
            assert(app.playback.source:isLooping(),"actual audio loop mode")
            app:playback_action("stop")
            assert(not app.playback.source:isPlaying() and app.playback.position==0,"stop resets source")
            app.selected_step_index=2
            app:playback_action("range_start")
            app:playback_action("range_end")
            assert(app:prepare_playback(),"prepare selected loop range")
            assert(app.playback.plan.duration==1,"selected range has a one-second duration")
            assert(app.playback.plan.music.offset_seconds==13,"selected range seeks inside the opening response music")
            app:playback_action("play")
            stage,elapsed = 4,0
        elseif stage == 4 and elapsed > 1.3 then
            assert(app.playback.source:isPlaying() and app.playback.position<1,"selected range continues looping")
            local gap=app.current_work.steps[2].gap
            app.palette_mode="replace"
            app:arm_insert_move({code=4,label="RIGHT"})
            assert(app.current_work.steps[2].code==4 and app.current_work.steps[2].gap==gap,"replacement preserves timing")
            assert(not app.playback.source and not app.playback.playing,"old compiled preview is discarded after replacement")
            app:undo(); assert(app.current_work.steps[2].code==3,"replacement undo")
            app:redo(); assert(app.current_work.steps[2].code==4,"replacement redo")
            app:playback_action("range_all")
            app:playback_action("play")
            assert(app.playback.plan.music,"edited command retains matching phrase music")
            stage,elapsed=5,0
        elseif stage==5 and elapsed>0.6 then
            if captured then
                save("audio-result.txt","PASS: actual stereo music and voice-only sources, music toggle, audio clock, pause, seek, resume, phrase/range loops, stop, replacement, undo/redo, and regenerated preview.\n")
                require("core.playback").stop(app.playback,true)
                print("PASS: actual LÖVE audio playback and editor integration")
                love.event.quit(0)
            end
        end
    end
    love.draw=function()
        app:draw()
        if stage==5 and elapsed>0.3 and not captured then
            captured=true
            love.graphics.captureScreenshot(function(image) save("playback-editor.png",image:encode("png"):getString()) end)
        end
    end
end
return M
