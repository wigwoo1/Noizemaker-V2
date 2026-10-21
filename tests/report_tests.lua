local report = require("core.report")
local format = require("core.format")
local rebuild = require("core.rebuild")
local App = require("ui.app")
local root = assert(TEST_GAME_ROOT, "Set TEST_GAME_ROOT to an installed game folder")
local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, message)
end

local r = report.load(root, 1)
check(r.language == "English", "report language")
check(r.title == "Report 1 - Ulala back in action!", "report title must match installed English captions")
check(#r.files == 6, "Report 1 must discover all six English chart files")
local main = report.rows(r, false)
check(#main == 99, "Report 1 main charts have 72 + 27 entries")
check(#report.rows(r, true) == 258, "all Report 1 variants remain accessible")
local seen = {}
for _, row in ipairs(report.rows(r, true)) do
    check(row.file.relative_path:match("^afs_english/") ~= nil, "must never import a root-language chart")
    local identity = row.file.relative_path .. "::" .. row.entry.name
    check(not seen[identity], "file and entry pair must be unique")
    seen[identity] = true
end
check(#report.rows(r, false, "Kin Kon Kan") == 27, "readable encounter search")
check(#report.rows(r, false, "chu") > 0, "command search")
check(#report.rows(r, false, "not-a-command") == 0, "empty search result")
check(not r.order_verified, "do not claim storage order is gameplay order")
local tree = require("ui.tree")
local before_name = main[1].entry.name
check(tree.entry_label(main[1].entry) == "Phrase 1", "matched CPU phrase has its section-relative label")
check(tree.entry_label({name = "pd002b"}, true) == "Alternate B", "variant remains distinct under its phrase")
check(main[1].entry.name == before_name, "readable labels must not rename export identities")
local report_label, section_label = report.file_context(main[1].file.path)
check(report_label == "Report 1" and section_label == "Rhythm Rogues encounters", "sidebar level context")
report_label, section_label = report.file_context("C:/game/afs_english/R12_SH20.BIN")
check(report_label == "Report 1" and section_label == "Kin Kon Kan encounter", "variant file keeps the correct encounter context")
report_label, section_label = report.file_context("C:/game/afs_english/r31_sh.bin")
check(report_label == "Report 3" and section_label:find("unverified", 1, true), "unknown scene must not receive a guessed name")

local root_reads = 0
local ok, err = pcall(report.load, root, 1, function(path)
    if not path:match("/afs_english/") and path:match("_sh") then root_reads = root_reads + 1 end
    return nil
end)
check(not ok and tostring(err):find("No English charts", 1, true), "missing English files need a useful error")
check(root_reads == 0, "missing English charts must not fall back to Japanese root files")
check(not pcall(report.load, root, 7), "invalid report number")
check(not report.export_path_allowed(root, root .. "/afs_english/r11_sh.bin"), "cannot overwrite installed English chart")
check(not report.export_path_allowed(root, root:upper() .. "/new.bin"), "game path matching ignores Windows case")
check(not report.export_path_allowed(root, root .. "/afs_english/../new.bin"), "dot segments cannot bypass original protection")
check(report.export_path_allowed(root, TEST_SCRATCH .. "/r11_sh_patched.bin"), "workspace export is allowed")
check(not report.export_path_allowed(root, TEST_SCRATCH .. "/original.bin", TEST_SCRATCH .. "/original.bin"), "outside-game source also protected")

for _, file in ipairs(r.files) do
    check(rebuild.apply_mods(file.buffer, file.entries, {}) == file.buffer, "unchanged English file round trip")
end
local first_file, first_entry = main[1].file, main[1].entry
local steps = first_entry:as_step_list()
steps[1].code = format.GAME_TO_INTERNAL.RIGHT
local mods = {[first_entry.name] = {steps = steps}}
local changed = rebuild.apply_mods(first_file.buffer, first_file.entries, mods)
local parsed = format.parse(changed)
check(#parsed == #first_file.entries, "replacement preserves entry count")
check(parsed[1].steps[1] == format.GAME_TO_INTERNAL.RIGHT, "replacement survives rebuilding and reparsing")
check(parsed[1].raw == first_entry.raw, "command replacement preserves meter, sequence length, and identity header")
local extended_steps = first_entry:as_step_list()
extended_steps[#extended_steps+1] = format.Step.new(format.GAME_TO_INTERNAL.LEFT, 24)
local extended = format.parse(rebuild.apply_mods(first_file.buffer, first_file.entries,
    {[first_entry.name] = {steps = extended_steps, timing = 24}}))[1]
check(extended.sc == 4, "command count is stored in the input packet")
check(format.u16(extended.raw, 8) == 4, "inserting notes preserves the original four-beat meter")
check(extended.timing == 24 and format.u16(extended.raw, 10) == 24, "length edit updates sequence and input together")
for i, entry in ipairs(parsed) do
    check(entry.name == first_file.entries[i].name, "replacement preserves every entry identity")
    check(entry.timing == first_file.entries[i].timing and entry.start_delay == first_file.entries[i].start_delay,
        "replacement preserves every entry's timing")
    if i > 1 then
        local source_entry = first_file.entries[i]
        check(changed:sub(entry.dp + 1, entry.np) == first_file.buffer:sub(source_entry.dp + 1, source_entry.np),
            "unmodified entry bytes are preserved")
    end
end

-- Exercise the real editor session switching with duplicate entry names in
-- different files. This guards against losing an edit or applying it to R12.
local app = App.new()
app.config_path = TEST_SCRATCH .. "/report-tests.ini"
app.game_root = root
app:open_report_entry(main[1].file, main[1].entry)
check(app.selected_entry.name == "pd001", "select requested phrase")
local original = app.current_work.steps[1].code
app.current_work.steps[1].code = format.GAME_TO_INTERNAL.RIGHT
app:update_draft_from_current()
check(app.current_dirty, "changed command should be marked edited")
local r12 = main[73]
app:open_report_entry(r12.file, r12.entry)
check(app.current_file_path == r12.file.path, "switch to R12")
check(not app.current_dirty, "R11 draft must not leak into same-named R12 entry")
app:open_report_entry(main[1].file, main[1].entry)
check(app.current_work.steps[1].code == format.GAME_TO_INTERNAL.RIGHT, "restore R11 draft on return")
check(app.selected_entry.steps[1] == original, "original parsed chart remains unchanged")
check(app.current_dirty, "restored draft remains marked edited")

local invalid = {path = TEST_SCRATCH .. "/missing.bin", section = "Missing file"}
app:show_info("test", "test")
app.modal = nil
app:open_report_entry(invalid, main[1].entry)
check(app.current_file_path == main[1].file.path, "failed import preserves the current edited file")
check(app.current_work.steps[1].code == format.GAME_TO_INTERNAL.RIGHT, "failed import preserves edited command")

app:select_entry(app.entries[2])
app.current_work.steps[1].code = format.INV.CHU
app:update_draft_from_current()
local all_mods, collect_error = app:collect_file_mods()
check(all_mods ~= nil, collect_error or "collect file edits")
local both = format.parse(rebuild.apply_mods(app.current_buffer, app.entries, all_mods))
check(both[1].steps[1] == format.GAME_TO_INTERNAL.RIGHT, "export includes a previously visited phrase draft")
check(both[2].steps[1] == format.INV.CHU, "export also includes the current phrase draft")

print("PASS: " .. checks .. " report import, search, language, identity, and draft checks")
return checks
