-- native interpolation port from neverlose (by @silentlag)
local ffi = require "ffi"
ffi.cdef [[
    typedef struct {
        unsigned short type;
        unsigned short needs_interpolate;
        void* data;
        void* watcher;
    } varmap_entry_t;
]]

-- UI
local slider = ui.new_slider("LUA", "B", "Interpolation amount", 1, 14, 1, true, "x")
local function get_vtable(this)
    return ffi.cast("void***", this)[0]
end

local function get_vfunc_from_interface(module_name, interface_name, index, typedef)
    local iface = client.create_interface(module_name, interface_name)
    if iface == nil then
        error(("Cannot find interface %s в %s"):format(interface_name, module_name))
    end
    local iface_ptr = ffi.cast("void***", iface)
    local fn = ffi.cast(typedef, iface_ptr[0][index])
    return fn, iface
end

-- VClientEntityList003::GetClientEntity (index 3)
local native_GetClientEntity_fn, entity_list_iface =
    get_vfunc_from_interface("client.dll", "VClientEntityList003", 3, "void*(__thiscall*)(void*, int)")

local function native_GetClientEntity(idx)
    return native_GetClientEntity_fn(entity_list_iface, idx)
end

-- CInterpolatedVar<>::SetInterpolationAmount — vtable[2] objects watcher.
local SetInterpolationAmount_typedef = ffi.typeof("void(__thiscall*)(void*, float)")

local function native_SetInterpolationAmount(watcher, amount)
    local vt = get_vtable(watcher)
    local fn = ffi.cast(SetInterpolationAmount_typedef, vt[2])
    fn(watcher, amount)
end

-- Main logic
local function interpolation(index, amount)
    local entity_ptr = native_GetClientEntity(index)
    if entity_ptr == nil then
        return
    end

    local entity_addr = ffi.cast("uintptr_t", entity_ptr)
    if entity_addr == nil then
        return
    end

    local entries_ptr = ffi.cast("void**", entity_addr + 0x24)[0]
    if entries_ptr == nil then
        return
    end

    local interp_count = ffi.cast("int32_t*", entity_addr + 0x24 + 0x14)[0]
    local entries = ffi.cast("varmap_entry_t*", entries_ptr)

    local tickinterval = globals.tickinterval()

    for i = 0, interp_count do
        local entry = entries[i]
        local data_offset = ffi.cast("uintptr_t", entry.data) - entity_addr

        -- m_vecOrigin = 0xAC = 172
        if data_offset == 172 and entry.watcher ~= nil then
            native_SetInterpolationAmount(entry.watcher, tickinterval * amount)
            return
        end
    end
end

client.set_event_callback(
    "net_update_end",
    function()
        local me = entity.get_local_player()
        if me == nil then
            return
        end
        local amount = ui.get(slider)
        local players = entity.get_players(false)
        for i = 1, #players do
            local idx = players[i]
            if idx ~= me then
                interpolation(idx, amount)
            end
        end
    end
)
