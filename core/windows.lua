-- Windows folder access for the LuaJIT runtime. Routine filesystem work
-- must not start cmd.exe or depend on a working command shell.
local ffi = require("ffi")
local bit = require("bit")
ffi.cdef[[
typedef struct { unsigned long low, high; } NM_FILETIME;
typedef struct {
    unsigned long attributes;
    NM_FILETIME created, accessed, written;
    unsigned long sizeHigh, sizeLow, reserved0, reserved1;
    unsigned short name[260], alternate[14];
} NM_FIND_DATA;
int __stdcall MultiByteToWideChar(unsigned int, unsigned long, const char *, int, unsigned short *, int);
int __stdcall WideCharToMultiByte(unsigned int, unsigned long, const unsigned short *, int, char *, int, const char *, int *);
unsigned long __stdcall GetFullPathNameW(const unsigned short *, unsigned long, unsigned short *, unsigned short **);
unsigned long __stdcall GetFileAttributesW(const unsigned short *);
int __stdcall CreateDirectoryW(const unsigned short *, void *);
int __stdcall RemoveDirectoryW(const unsigned short *);
void *__stdcall FindFirstFileW(const unsigned short *, NM_FIND_DATA *);
int __stdcall FindNextFileW(void *, NM_FIND_DATA *);
int __stdcall FindClose(void *);
int __stdcall MoveFileExW(const unsigned short *, const unsigned short *, unsigned long);
]]
local kernel = ffi.load("kernel32")
local M = {}
local INVALID = ffi.cast("void *", -1)

local function wide(text)
    text = tostring(text or "")
    if text:find("\0", 1, true) then error("A path or command contains a null character.") end
    local n = kernel.MultiByteToWideChar(65001, 8, text, #text, nil, 0)
    assert(n > 0 or text == "", "Invalid UTF-8 path or command.")
    local result = ffi.new("unsigned short[?]", n + 1)
    if n > 0 then assert(kernel.MultiByteToWideChar(65001, 8, text, #text, result, n) == n) end
    return result
end

local function utf8(value)
    local n = kernel.WideCharToMultiByte(65001, 0, value, -1, nil, 0, nil, nil)
    assert(n > 0, "Cannot read a Windows filename.")
    local result = ffi.new("char[?]", n)
    assert(kernel.WideCharToMultiByte(65001, 0, value, -1, result, n, nil, nil) > 0)
    return ffi.string(result, n - 1)
end

local function full_path(path)
    local result = ffi.new("unsigned short[32768]")
    local n = kernel.GetFullPathNameW(wide(path:gsub("/", "\\")), 32768, result, nil)
    assert(n > 0 and n < 32768, "Cannot resolve the folder path.")
    return utf8(result)
end

function M.replace_file(source, destination)
    -- Same-folder temporary file, atomic replacement, flush before returning.
    if kernel.MoveFileExW(wide(source),wide(destination),9)~=0 then return true end
    return nil,"Windows could not replace the project file. The previous save is unchanged."
end

function M.create_dir_exclusive(path)
    return kernel.CreateDirectoryW(wide(path),nil)~=0
end

function M.remove_empty_dir(path)
    return kernel.RemoveDirectoryW(wide(path))~=0
end

function M.rename_new(source,destination)
    if kernel.MoveFileExW(wide(source),wide(destination),8)~=0 then return true end
    return nil,"Could not finish export. Choose a new folder name and check folder permissions."
end

function M.directory_exists(path)
    if not path or path == "" then return false end
    local attr = tonumber(kernel.GetFileAttributesW(wide(path)))
    return attr ~= 0xffffffff and bit.band(attr, 0x10) ~= 0
end

function M.ensure_dir(path)
    if not path or path == "" then return false end
    path = full_path(path)
    if M.directory_exists(path) then return true end
    local parent = path:match("^(.*)\\[^\\]+\\?$")
    if parent and parent ~= path then
        if parent:match("^%a:$") then parent = parent .. "\\" end
        if not M.ensure_dir(parent) then return false end
    end
    return kernel.CreateDirectoryW(wide(path), nil) ~= 0 or M.directory_exists(path)
end

local function children(path)
    local data, result = ffi.new("NM_FIND_DATA[1]"), {}
    local handle = kernel.FindFirstFileW(wide(path:gsub("[/\\]+$", "") .. "\\*"), data)
    if handle == INVALID then return result end
    repeat
        local name = utf8(data[0].name)
        if name ~= "." and name ~= ".." then
            result[#result+1] = {name = name, directory = bit.band(data[0].attributes, 0x10) ~= 0,
                link = bit.band(data[0].attributes, 0x400) ~= 0}
        end
    until kernel.FindNextFileW(handle, data) == 0
    kernel.FindClose(handle)
    table.sort(result, function(a,b) return a.name:lower() < b.name:lower() end)
    return result
end

function M.list_directories(path)
    local result = {}
    for _, child in ipairs(children(path)) do
        if child.directory then result[#result+1] = child.name end
    end
    return result
end

function M.list_files_recursive(path)
    local result = {}
    local function visit(folder, prefix)
        for _, child in ipairs(children(folder)) do
            local relative = prefix .. child.name
            if child.directory then
                -- Do not follow junctions out of the tree or into cycles.
                if not child.link then visit(folder .. "/" .. child.name, relative .. "/") end
            else result[#result+1] = relative end
        end
    end
    visit(path, "")
    table.sort(result, function(a,b) return a:lower() < b:lower() end)
    return result
end

return M
