local format=require('core.format')
local facts=require('core.dance_data')
local M={id='dance',title="Ulala's Dance",source='r01_sh.bin'}
function M.annotate(entries,path,buffer)
    local relative=tostring(path or ''):gsub('\\','/'):lower()
    local recognized=(relative:match('/r01_sh%.bin$') or relative=='r01_sh.bin')
        and not relative:match('afs_english/r01_sh%.bin$')
    local checked=false
    if recognized and buffer and love and love.data and love.data.hash then
        local digest=love.data.hash('sha256',buffer):gsub('.',function(c)return string.format('%02x',c:byte())end)
        checked=digest==facts.sha256
    end
    for _,entry in ipairs(entries or {}) do
        entry.dance=nil
        if recognized then
            local set,phrase,variant=entry.name:match('^pd(%d%d)(%d%d)(g?)$')
            if set then
                local uses=checked and facts.uses[entry.name] or nil
                local label='Set '..tonumber(set)..' / phrase '..tonumber(phrase)
                if uses and #uses>1 then
                    local numbers={};for _,use in ipairs(uses) do numbers[#numbers+1]=use.phrase end
                    label='Set '..tonumber(set)..' / phrases '..table.concat(numbers,', ')
                end
                label=label..(variant=='g' and ' / G branch' or ' / base branch')
                if checked and not uses then label='Stored '..label..' (no question link)' end
                local names,search={},{}
                for _,use in ipairs(uses or {}) do
                    names[#names+1]=use.question
                    search[#search+1]='Set '..use.set..' phrase '..use.phrase
                end
                entry.dance={label=label,set=tonumber(set),variant=variant=='g',
                    checked=checked,uses=uses,uses_text=table.concat(names,', '),search_text=table.concat(search,' ')}
            end
        end
    end
    return checked
end
function M.load(root,read)
    local path=root..'/'..M.source
    local buffer=assert(read(path),"Ulala's Dance shared chart is missing: r01_sh.bin")
    local entries=format.parse(buffer)
    assert(#entries>0,"Ulala's Dance chart could not be read. Its source must be the shared root chart.")
    local checked=M.annotate(entries,path,buffer)
    local route=require('core.route')
    local mode={number=M.id,mode_id='ulala-dance',title=M.title,language='English',order_verified=false,
        order_note='One recorded CPU run; other paths and complete audible timing remain unverified.',
        files={{path=path,relative_path=M.source,stem='r01',section=M.title,
            variant='Shared chart used by English mode',is_main=true,buffer=buffer,entries=entries,
            language='English',shared_source=true,dance_source_checked=checked}}}
    mode.files[1].route_source=route.annotate(entries,path,buffer)
    mode.cpu_route,mode.cpu_route_reason=route.rows(mode)
    mode.cpu_route_note=route.note(M.id)
    return mode
end
return M
