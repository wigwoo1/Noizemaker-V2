-- Render the real report browser and existing editor using a local game copy.
-- Writes screenshots only to the explicitly supplied QA folder.
local M = {}
function M.start(args)
    local App = require("ui.app")
    local theme = require("ui.theme")
    local game_root, out = assert(args[2]), assert(args[3])
    local function save(name, data)
        local fh = assert(io.open(out .. "/" .. name, "wb"))
        fh:write(data)
        fh:close()
    end
    love.errorhandler = function(msg)
        save("error.txt", tostring(msg) .. "\n" .. debug.traceback())
        return function() return 1 end
    end
    local app = App.new()
    app.game_root = game_root
    app.config_path = out .. "/test-config.ini"
    theme.init()
    app:load_report(1)
    assert(app.reports_tab.report, app.reports_tab.error)
    local cases = {
        {name = "reports-1280", w = 1280, h = 720},
        {name = "reports-960", w = 960, h = 600},
        {name = "variants-960", w = 960, h = 600, variants = true, query = "Kin Kon Kan"},
        {name = "editor-1280", w = 1280, h = 720, editor = true},
        {name = "editor-960", w = 960, h = 600, editor = true},
    }
    local index, frame, capturing = 1, 0, false
    local function prepare()
        local case = cases[index]
        love.window.setMode(case.w, case.h, {resizable = false})
        app:resize(case.w, case.h)
        app.active_view = "reports"
        app.reports_tab.include_variants = case.variants or false
        app.reports_tab.order_mode=case.variants and 'files' or 'cpu'
        app.reports_tab.query = case.query or ""
        app.reports_tab.scroll = 0
        if case.editor then
            local file = app.reports_tab.report.files[1]
            app:open_report_entry(file, file.entries[1])
        end
        app.view_transition = nil
        frame, capturing = 0, false
    end
    prepare()
    love.update = function()
        if capturing then return end
        frame = frame + 1
    end
    love.draw = function()
        app:draw()
        if frame >= 3 and not capturing then
            capturing = true
            love.graphics.captureScreenshot(function(image)
                save(cases[index].name .. ".png", image:encode("png"):getString())
                print("PASS rendered " .. cases[index].name)
                index = index + 1
                if index > #cases then
                    save("result.txt", "PASS: report browser at 1280x720 and 960x600; variants and editor rendered.\n")
                    love.event.quit(0)
                else
                    prepare()
                end
            end)
        end
    end
end
return M
