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
        {name = "unmapped-command-960", w = 960, h = 600, editor = "unmapped"},
        {name = "command-symbols-1280", w = 1280, h = 720, editor = true, symbols = true},
        {name = "command-symbols-960", w = 960, h = 600, editor = true, symbols = true},
    }
    -- A display-only fixture exercises every symbol without changing a draft
    -- or implying this sequence occurs in the game.
    local codes = {3,4,6,5,1,2,11,12,14,13,9,10,0,0x41}
    local hits = {}; for i=1,#codes-1 do hits[i]=12 end
    local gallery = require('core.format').Entry.new('symbol_gallery',0,0,0,#codes,codes,28,hits,
        '',string.char(120,0),string.char(0,0),0,'')
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
        if case.editor == "unmapped" then
            local selected_file, selected_entry
            for _, file in ipairs(app.reports_tab.report.files) do
                for _, entry in ipairs(file.entries) do
                    for _, code in ipairs(entry.steps) do
                        if code == 0x41 then selected_file, selected_entry = file, entry; break end
                    end
                    if selected_entry then break end
                end
                if selected_entry then break end
            end
            assert(selected_entry, "English Report 1 must contain the documented unmapped command 0x41")
            app:open_report_entry(selected_file, selected_entry)
            local found = false
            for _, node in ipairs(require("ui.timeline").build_nodes(selected_entry)) do
                if node.code == 0x41 then
                    assert(node.label == "Unmapped 0x41", "timeline must display the explicit unknown-command label")
                    found = true
                end
            end
            assert(found, "selected Report 1 timeline must retain the 0x41 node")
        elseif case.editor then
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
        if cases[index].symbols then
            love.graphics.setColor(theme.colors.bg_top)
            love.graphics.rectangle('fill',10,194,cases[index].w-20,cases[index].h-204)
            love.graphics.setFont(theme.font('small'))
            love.graphics.setColor(theme.colors.text)
            love.graphics.print('Command symbols (display test sequence)',20,204)
            require('ui.timeline').draw({x=20,y=230,w=cases[index].w-40,h=cases[index].h-250},gallery,1)
        end
        if frame >= 3 and not capturing then
            capturing = true
            love.graphics.captureScreenshot(function(image)
                save(cases[index].name .. ".png", image:encode("png"):getString())
                print("PASS rendered " .. cases[index].name)
                index = index + 1
                if index > #cases then
                    save("result.txt", "PASS: report browser at 1280x720 and 960x600; variants and editor rendered; unmapped Report 1 command label retained; all direction/hold/call/rest symbols rendered at both sizes.\n")
                    love.event.quit(0)
                else
                    prepare()
                end
            end)
        end
    end
end
return M
