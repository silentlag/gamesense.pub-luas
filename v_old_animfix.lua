local ffi = require("ffi")

local function copy(dst, src, len)
    return ffi.copy(ffi.cast("void*", dst), ffi.cast("const void*", src), len)
end

local jmp_ecx = client.find_signature("engine.dll", "\xFF\xE1")
local get_proc_addr =
    ffi.cast(
    "uint32_t**",
    ffi.cast("uint32_t", client.find_signature("engine.dll", "\xFF\x15\xCC\xCC\xCC\xCC\xA3\xCC\xCC\xCC\xCC\xEB\x05")) +
        2
)[0][0]
local get_module_handle =
    ffi.cast(
    "uint32_t**",
    ffi.cast("uint32_t", client.find_signature("engine.dll", "\xFF\x15\xCC\xCC\xCC\xCC\x85\xC0\x74\x0B")) + 2
)[0][0]

local fn_get_proc_addr = ffi.cast("uint32_t(__fastcall*)(unsigned int, unsigned int, uint32_t, const char*)", jmp_ecx)
local fn_get_module_handle = ffi.cast("uint32_t(__fastcall*)(unsigned int, unsigned int, const char*)", jmp_ecx)

local function proc_bind(module_name, function_name, typedef)
    local ctype = ffi.typeof(typedef)
    local module_handle = fn_get_module_handle(get_module_handle, 0, module_name)
    local proc_address = fn_get_proc_addr(get_proc_addr, 0, module_handle, function_name)
    local call_fn = ffi.cast(ctype, jmp_ecx)

    return function(...)
        return call_fn(proc_address, 0, ...)
    end
end

local native_VirtualProtect =
    proc_bind(
    "kernel32.dll",
    "VirtualProtect",
    "int(__fastcall*)(unsigned int, unsigned int, void* lpAddress, unsigned long dwSize, unsigned long flNewProtect, unsigned long* lpflOldProtect)"
)

local function virtual_protect(lpAddress, dwSize, flNewProtect, lpflOldProtect)
    return native_VirtualProtect(ffi.cast("void*", lpAddress), dwSize, flNewProtect, lpflOldProtect)
end

local function contains(tbl, value)
    if tbl == nil then
        return false
    end
    if type(tbl) == "number" then
        tbl = ui.get(tbl)
    end
    for i = 0, #tbl do
        if tbl[i] == value then
            return true
        end
    end
    return false
end

local detour = {
    hooks = {}
}

function detour.new(typedef, callback, hook_addr, size)
    size = size or 5

    local hook = {
        call = ffi.cast(typedef, hook_addr),
        status = false
    }
    local old_prot = ffi.new("unsigned long[1]")
    local org_bytes = ffi.new("uint8_t[?]", size)

    copy(org_bytes, hook_addr, size)

    local detour_addr = tonumber(ffi.cast("intptr_t", ffi.cast("void*", ffi.cast(typedef, callback))))
    local hook_bytes = ffi.new("uint8_t[?]", size, 0x90)
    hook_bytes[0] = 0xE9
    ffi.cast("int32_t*", hook_bytes + 1)[0] = detour_addr - hook_addr - 5

    local function set_status(enable)
        hook.status = enable
        virtual_protect(hook_addr, size, 0x40, old_prot)
        copy(hook_addr, enable and hook_bytes or org_bytes, size)
        virtual_protect(hook_addr, size, old_prot[0], old_prot)
    end

    function hook.start()
        set_status(true)
    end
    function hook.stop()
        set_status(false)
    end

    hook:start()
    table.insert(detour.hooks, hook)

    return setmetatable(
        hook,
        {
            __call = function(self, ...)
                self:stop()
                local res = self.call(...)
                self:start()
                return res
            end
        }
    )
end

function detour.unhook_all()
    for _, hook in ipairs(detour.hooks) do
        hook:stop()
    end
end

client.set_event_callback("shutdown", detour.unhook_all)

local ClampBonesInBBox_pattern =
    client.find_signature(
    "client.dll",
    "\x55\x8B\xEC\x83\xE4\xCC\x83\xEC\xCC\x56\x57\x8B\xF9\x89\x7C\x24\xCC\x83\xBF\xCC\xCC\xCC\xCC\xCC\x75"
) or error("invalid pointer")

local ClampBonesInBBox_address = tonumber(ffi.cast("uintptr_t", ClampBonesInBBox_pattern)) or error("invalid cast")

--print(string.format("ClampBonesInBBox found at 0x%X", ClampBonesInBBox_address))

local ClampBonesInBBox_original = nil

local get_client_entity = vtable_bind("client.dll", "VClientEntityList003", 3, "void*(__thiscall*)(void*, int)")

local function get_address(idx)
    return ffi.cast("void***", get_client_entity(idx))
end

local function ClampBonesInBBox_hook(player, edx, matrix, mask)
    if player == nil or edx == nil or matrix == nil or mask == nil then
        return
    end

    local player_void_ptr = ffi.cast("void*", player)

    local local_nigga_index = entity.get_local_player()
    local local_player = get_address(local_nigga_index)

    if player_void_ptr ~= ffi.cast("void*", local_player) then
        return ClampBonesInBBox_original(player, edx, matrix, mask)
    end

    --local matrix_ptr = ffi.cast("matrix3x4_t*", matrix)

    --ClampBonesInBBox_original(player, edx, matrix, mask)
end

ClampBonesInBBox_original =
    detour.new("void(__fastcall*)(void*, void*, void*, int)", ClampBonesInBBox_hook, ClampBonesInBBox_address)

--[[
ffi.cdef[[
typedef struct {
    float m[3][4];
} matrix3x4_t;
]]
