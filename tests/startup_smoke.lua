local M = {}
function M.start(app, args)
    local out = assert(args[2])
    assert(app.active_view == "reports" and app.reports_tab.report,
        "normal packaged startup must open the English report browser")
    assert(app.reports_tab.report.language == "English", "English import on normal startup")
    app.config_path = out .. "/settings-test.ini"
    local platform = require("core.platform")
    platform.choose_folder = function() error("Settings attempted external folder dialog") end
    local stage, frames, captured = 0, 0, false
    local root, work, steps
    local function save(name, contents)
        local f = assert(io.open(out .. "/" .. name, "wb")); f:write(contents); f:close()
    end
    local function click_setting()
        local b = app:buttons().settings
        app:mousepressed(b.x+b.w/2, b.y+b.h/2, 1)
        assert(app.modal and app.modal.title == "Settings" and app.modal.input, "Settings opens in app")
    end
    love.update = function(dt)
        app:update(dt); frames = frames+1
        if stage == 1 then
            local file = app.reports_tab.report.files[1]
            app:open_report_entry(file, file.entries[1]); app.view_transition = nil
            app:replace_command(1, 4)
            root, work, steps = app.game_root, app.current_work, app.current_work.steps
            click_setting()
            stage, frames, captured = 2, 0, false
        elseif stage == 3 then
            app:keypressed("escape")
            assert(not app.modal and app.current_work == work and app.current_work.steps == steps,
                "Cancel preserves edited draft")
            click_setting()
            app.modal.input.text = "C:/this-folder-does-not-exist"
            app:dismiss_modal("save")
            assert(app.modal and app.modal.input.error and app.game_root == root,
                "invalid path stays in Settings with an explanation")
            app.modal.input.text = '"' .. root .. '"'
            app:dismiss_modal("save")
            assert(not app.modal and app.game_root == root and app.current_work == work,
                "Save accepts quoted paths and preserves draft")
            local f = assert(io.open(app.config_path, "r")); local cfg = f:read("*a"); f:close()
            assert(cfg:find(root, 1, true), "Settings persisted game folder")
            click_setting()
            app.modal.input.text, app.modal.input.replace_on_type = "folder", false
            app:keypressed("space"); app:textinput(" ")
            assert(app.modal and app.modal.input.text == "folder ", "spaces do not accidentally submit path")
            app:keypressed("escape")
            app:activate_main_menu_button("settings")
            assert(app.modal and app.modal.input, "menu Settings uses the same working panel")
            app:keypressed("escape")
            assert(not app.modal and app.current_work.steps[1].code == 4, "draft still intact")
            app:playback_action("tempo")
            assert(app.modal and app.modal.input, "tempo chooser opens")
            app.modal.input.text = "90"
            app:dismiss_modal("set")
            assert(not app.modal and app.playback.bpm == 90, "manual preview tempo")
            app:playback_action("tempo")
            app.modal.input.text = "0"
            app:dismiss_modal("set")
            assert(app.modal and app.modal.input.error and app.playback.bpm == 90, "invalid BPM keeps previous tempo")
            app:dismiss_modal("chart")
            assert(not app.modal and app.playback.bpm == nil, "Use chart restores automatic tempo")
            assert(require("core.playback").plan(app:current_preview_entry()).duration == 4, "corrected opening duration")
            save("packaged-startup-result.txt", "PASS: normal startup, English Report 1, Settings click/render/cancel/save, invalid path feedback, quoted paths, spaces, persisted configuration, preserved edits, manual BPM, invalid BPM, and Use chart reset. io.popen/os.execute forbidden throughout.\n")
            print("PASS: packaged startup and Settings without command shell")
            app.allow_quit=true -- This test deliberately leaves an unsaved edit.
            love.event.quit(0)
            stage = 4
        end
    end
    love.draw = function()
        app:draw()
        if (stage == 0 or stage == 2) and frames > 20 and not captured then
            captured = true
            local name = stage == 0 and "packaged-startup.png" or "settings-panel.png"
            love.graphics.captureScreenshot(function(image)
                save(name, image:encode("png"):getString()); stage = stage+1
            end)
        end
    end
end
return M
