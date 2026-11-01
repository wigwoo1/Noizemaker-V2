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
                local shooting
                for _,entry in ipairs(file.entries) do if entry.name=='ps001' then shooting=entry end end
                app:open_report_entry(file,assert(shooting))
                app:playback_action('play')
                assert(app.playback.source:isPlaying() and app.playback.source:getChannelCount()==2,
                    'first shooting phrase starts a stereo music source')
                assert(app.playback.plan.music.name=='r11 music cue 25'
                    and app.playback.plan.music.offset_seconds==7.5,'shooting preview inherits scene music')
                assert(app.playback.plan.music.timing_checked and app.playback.plan.music.timing_tolerance_seconds==.06,
                    'Shooting source/cue/voice checks enable the bounded recorded-timing label')
                stage,elapsed,captured=6,0,false
            end
        elseif stage==6 and elapsed>0.3 and captured then
                assert(app.playback.position>0,'shooting music playback clock advances')
                app:playback_action('next_phrase')
                app:playback_action('play')
                assert(app.selected_entry.name=='ps002' and app.playback.plan.music.offset_seconds==10.5,
                    'Next keeps the following shooting phrase on the inherited track')
                local by_name={}
                for _,entry in ipairs(file.entries) do by_name[entry.name]=entry end
                for _,check in ipairs({{'pd005',9,'HOLDCHU'},{'ps017',0x41,'CHU'},{'ps2013',0x21,'CHU'}}) do
                    app:open_report_entry(file,assert(by_name[check[1]]))
                    assert(app:prepare_playback(),'Prepare the verified R11 call phrase')
                    local found
                    for _,event in ipairs(app.playback.plan.events) do
                        if event.code==check[2] then found=event.command end
                    end
                    assert(found==check[3],'GUI phrase playback uses its section-specific verified voice')
                    app:audition_command(check[2])
                    assert(app.playback.audition and app.playback.audition:isPlaying(),'Command audition starts the verified sample')
                    if check[2]==9 then
                        assert(app.playback.audition:getDuration()>0.89 and app.playback.audition:getDuration()<0.91,
                            'Held-Chu audition uses the 0.9-second sample')
                    end
                end
                app:open_report_entry(file,assert(by_name.pd006))
                app.selected_step_index=2
                app:playback_action('range_start');app:playback_action('range_end')
                app:playback_action('play')
                assert(app.playback.range_start==24 and app.playback.range_end==48,
                    'From/To controls select the note after the held Chu')
                assert(#app.playback.plan.events==1 and app.playback.plan.events[1].index==2
                    and #app.playback.plan.continuations==1 and app.playback.plan.continuations[1].index==1,
                    'The real app preserves the held-Chu tail without adding a new earlier attack')
                assert(app.playback.source:getChannelCount()==2 and app.playback.source:isLooping()
                    and app.playback.plan.music.timing_checked,'The stock range loops with checked stereo music')
                stage,elapsed,captured=7,0,false
        elseif stage==7 and elapsed>1.1 and captured then
                assert(app.playback.source:isPlaying() and app.playback.position<app.playback.plan.duration,
                    'The held-tail range continues through a complete loop')
                app:playback_action('play')
                assert(not app.playback.playing,'The continuation range can pause')
                app:playback_action('seek',0.5);app:playback_action('play')
                assert(app.playback.playing and app.playback.position>0,'Seek/resume keeps the selected audio range')
                save("audio-result.txt","PASS: stereo music, voice-only sources, audio clock, pause/seek/resume/loops, stop, timing-preserving replacement/undo/redo, shooting music, verified R11 voices, and stock pd006 From/To held-tail range playback.\n")
                require("core.playback").stop(app.playback,true)
                print("PASS: actual LÖVE audio playback and editor integration")
                love.event.quit(0)
                stage=8
        end
    end
    love.draw=function()
        app:draw()
        if stage==5 and elapsed>0.3 and not captured then
            captured=true
            love.graphics.captureScreenshot(function(image) save("playback-editor.png",image:encode("png"):getString()) end)
        end
        if stage==6 and not captured then
            captured=true
            love.graphics.captureScreenshot(function(image) save('shooting-music-editor.png',image:encode('png'):getString()) end)
        end
        if stage==7 and not captured then
            captured=true
            love.graphics.captureScreenshot(function(image) save('held-chu-range-editor.png',image:encode('png'):getString()) end)
        end
    end
end
return M
