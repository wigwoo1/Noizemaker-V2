-- Facts from one recorded CPU run, bound to the exact English source bytes.
-- Alternative scripts remain accessible; this is not a universal branch order.
local data=require('core.route_data')
local M={}
local function relative(path)
    path=tostring(path or ''):gsub('\\','/'):lower()
    return path:match('^(afs_english/[^/]+)$') or path:match('/(afs_english/[^/]+)$')
end
function M.source(path,buffer)
    local name=relative(path)
    if not name or not buffer or not (love and love.data and love.data.hash) then return nil end
    local hash
    for canonical,source in pairs(data.sources) do
        for _,alias in ipairs(source.aliases) do
            if alias==name then
                hash=hash or (love.data.hash('sha256',buffer):gsub('.',function(c)return string.format('%02x',c:byte())end))
                if hash==source.sha256 then return canonical end
            end
        end
    end
end
function M.annotate(entries,path,buffer)
    local source=M.source(path,buffer)
    local observed,parents={},{}
    if source then
        for _,event in ipairs(data.events) do
            if event.file==source then
                observed[event.entry]=event
                parents[event.entry:match('^(%a+%d+)')]=event
            end
        end
    end
    for _,entry in ipairs(entries or {}) do
        entry.route=observed[entry.name]
        entry.route_parent=not entry.route and parents[entry.base or entry.name:match('^(%a+%d+)')] or nil
        entry.route_unobserved=source~=nil and not entry.route
    end
    return source
end
function M.rows(report)
    if not report or report.number~=1 then return nil,'No recorded CPU route for this report yet.' end
    local files={}
    for _,file in ipairs(report.files) do
        if file.relative_path==file.route_source then files[file.route_source]=file end
    end
    for canonical in pairs(data.sources) do
        if not files[canonical] then return nil,'Recorded CPU route unavailable: source files do not match the capture.' end
    end
    local result={}
    for _,event in ipairs(data.events) do
        local file=files[event.file]
        local entry
        for _,candidate in ipairs(file.entries) do if candidate.name==event.entry then entry=candidate;break end end
        if not entry then return nil,'A recorded phrase is missing from its source file.' end
        result[#result+1]={file=file,entry=entry,event=event,aliases=data.sources[event.file].aliases}
    end
    return result
end
return M
