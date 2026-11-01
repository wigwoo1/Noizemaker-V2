-- English report import. No game files are written by this module.
local format = require("core.format")
local route = require("core.route")
local dance = require('core.dance')
local M = {}
function M.title(number) return number=='dance' and dance.title or ('Report '..tostring(number)) end
function M.belongs(filename,number)
    filename=tostring(filename or ''):gsub('\\','/'):lower():match('[^/]+$') or ''
    if number=='dance' then return filename=='r01_sh.bin' end
    return filename:match('^r'..tostring(number)..'[1-4]_sh')~=nil
end

local VARIANTS = {
    { suffix = "", label = "Main chart file" },
    { suffix = "2", label = "SH2 variant - mode unverified" },
    { suffix = "0", label = "SH0 variant - mode unverified" },
    { suffix = "20", label = "SH20 variant - mode unverified" },
}

-- Caption-grounded part labels. English caption files contain subjects and
-- callouts associated with each part; the precise scene boundaries still
-- need gameplay verification, so the UI marks these labels as provisional.
local SECTION_NAMES = {
    r11 = "Rhythm Rogues dance and rescue",
    r12 = "Kin Kon Kan and Purge showdown",
    r21 = "Tasty Cookin' and Shadow's broadcast",
    r22 = "Pudding, Padding, and impostors",
    r23 = "Pon Piriri showdown",
    r31 = "Space Police and Noize",
    r41 = "Rescue team under attack",
    r42 = "Space cheerleaders and security bot",
    r43 = "Purge and the Peace Carrier",
    r44 = "Final consecutive dance",
    r51 = "Emergency circuit and robot poses",
    r52 = "Robotic band and Jaguar",
    r61 = "Ballistic Groove Gun showdown",
    r62 = "Final dance and rescue",
}

local function read_binary(path)
    local fh = io.open(path, "rb")
    if not fh then return nil end
    local data = fh:read("*a")
    fh:close()
    return data
end

function M.command_summary(entry)
    local names = {}
    for i, code in ipairs(entry.steps) do
        names[i] = format.step_editor_display_name(code)
    end
    return table.concat(names, "  ")
end

function M.phrase_label(entry)
    if entry.dance then return entry.dance.label end
    if entry.route then return entry.route.label end
    if entry.route_parent then
        local variant=entry.name:match('(%a+)$') or '?'
        return entry.route_parent.label..' / alternate '..variant:upper()..' (unobserved)'
    end
    local prefix, number, variant = entry.name:match("^(%a+)(%d+)(%a*)$")
    local family = ({pd = "Dance", ps = "Shooting", pk = "Final"})[prefix]
    if not family then return "Command sequence " .. entry.name end
    local label = family .. " phrase " .. tostring(tonumber(number))
    if variant ~= "" then label = label .. " / alternate " .. variant:upper() end
    if entry.route_unobserved then label=label..' (unobserved)' end
    return label
end

function M.file_context(path)
    local name = tostring(path or ""):gsub("\\", "/"):match("([^/]+)$") or ""
    if name:lower()=='r01_sh.bin' then return dance.title,'Sets and branch alternatives' end
    local number, part = name:lower():match("^r([1-6])([1-4])_sh%d*%.bin$")
    if not number then return nil, nil end
    return "Report " .. number, SECTION_NAMES["r" .. number .. part] or ("Section " .. part .. " - name unverified")
end

function M.load(root, number, read)
    if number=='dance' then
        root=(root or ''):gsub('\\','/'):gsub('/+$','')
        assert(root~='', 'Choose the game installation folder first.')
        return dance.load(root,read or read_binary)
    end
    assert(type(number) == "number" and number == math.floor(number) and number >= 1 and number <= 6,
        "Choose a report from 1 to 6.")
    read = read or read_binary
    root = (root or ""):gsub("\\", "/"):gsub("/+$", "")
    assert(root ~= "", "Choose the game installation folder first.")
    local report = {
        number = number, title = "Report " .. number, language = "English", files = {},
        order_verified = false,
        order_note = "Grouped by file and stored phrase order. Gameplay order and branch conditions are not yet verified.",
        label_note = "Part names are based on English captions; exact scene boundaries are provisional.",
    }
    -- rN0cap_e.bin contains the English report introduction and its title.
    local caption = read(root .. "/r" .. number .. "0cap_e.bin")
    if caption and caption:sub(1, 4) == "DGCP" then
        local last
        for s in caption:gmatch("[ -~]+") do
            if #s >= 4 then last = s end
        end
        if last and not last:match("^DGCP") then
            report.title = report.title .. " - " .. last
        end
    end
    for part = 1, 4 do
        local stem = "r" .. number .. part
        for _, variant in ipairs(VARIANTS) do
            local relative = "afs_english/" .. stem .. "_sh" .. variant.suffix .. ".bin"
            local path = root .. "/" .. relative
            local data = read(path)
            -- Deliberately do not fall back to similarly named root charts:
            -- that could silently select the Japanese version.
            if data then
                local ok, entries = pcall(format.parse, data)
                assert(ok, "Could not read English chart " .. relative .. ": " .. tostring(entries))
                report.files[#report.files + 1] = {
                    path = path, relative_path = relative, stem = stem,
                    section = SECTION_NAMES[stem] or ("Report " .. number .. " section " .. part .. " - name unverified"),
                    variant = variant.label, is_main = variant.suffix == "",
                    buffer = data, entries = entries, language = "English",
                    route_source = route.annotate(entries,relative,data),
                }
            end
        end
    end
    assert(#report.files > 0, "No English charts were found for Report " .. number .. ". Check the game folder.")
    report.cpu_route,report.cpu_route_reason=route.rows(report)
    report.cpu_route_note=route.note(number)
    return report
end

function M.cpu_rows(report,query)
    local result={}
    query=tostring(query or ''):lower()
    for _,row in ipairs(report and report.cpu_route or {}) do
        local label=row.entry.dance and row.event.label or M.phrase_label(row.entry)
        local commands=M.command_summary(row.entry)
        local search=(row.file.section..' '..label..' '..commands..' '..row.file.relative_path..' '..
            row.entry.name..' '..row.event.question..' '..row.event.section):lower()
        if query=='' or search:find(query,1,true) then
            result[#result+1]={file=row.file,entry=row.entry,label=label,commands=commands,
                event=row.event,aliases=row.aliases}
        end
    end
    return result
end

function M.rows(report, include_variants, query)
    local rows = {}
    query = (query or ""):lower()
    for _, file in ipairs(report and report.files or {}) do
        if include_variants or file.is_main then
            for _, entry in ipairs(file.entries) do
                if not report.mode_id or include_variants or not (entry.dance and entry.dance.variant) then
                local label = M.phrase_label(entry)
                local commands = M.command_summary(entry)
                local search = (file.section .. " " .. file.relative_path .. " " .. label .. " " .. entry.name .. " " .. commands..' '..(entry.dance and (entry.dance.uses_text..' '..entry.dance.search_text) or '')):lower()
                if query == "" or search:find(query, 1, true) then
                    rows[#rows + 1] = {file = file, entry = entry, label = label, commands = commands}
                end
                end
            end
        end
    end
    return rows
end

local function canonical_path(path)
    path = tostring(path or ""):gsub("\\", "/"):lower()
    if not path:match("^[a-z]:/") and not path:match("^//") then return nil end
    local prefix = path:match("^[a-z]:") or "/"
    local segments = {}
    for segment in path:gsub("^[a-z]:", ""):gmatch("[^/]+") do
        if segment == ".." then
            if #segments == 0 then return nil end
            table.remove(segments)
        elseif segment ~= "." then
            segments[#segments + 1] = segment
        end
    end
    return prefix .. "/" .. table.concat(segments, "/")
end

function M.export_path_allowed(root, destination, source)
    local game, path, original = canonical_path(root), canonical_path(destination), canonical_path(source)
    if not game or not path then return false, "Choose a full file path outside the game installation." end
    if path == original then return false, "Choose a new file; the source chart must stay unchanged." end
    if path == game or path:sub(1, #game + 1) == game .. "/" then
        return false, "Export to a folder outside the game installation. Installing edits is a separate step."
    end
    return true
end

return M
