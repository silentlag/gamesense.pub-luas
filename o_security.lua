local ffi = require("ffi")

local Security = {
    version = "2.0",
    whitelist = {
        ["DEFAULT_TEST_ID"] = "Developer"
    },
    last_heartbeat = 0,
    heartbeat_interval = 300,
    resolved = {}
}

local function read_u16(addr, offset)
    return ffi.cast("uint16_t*", ffi.cast("uint8_t*", addr) + offset)[0]
end
local function read_u32(addr, offset)
    return ffi.cast("uint32_t*", ffi.cast("uint8_t*", addr) + offset)[0]
end
local function read_i32(addr, offset)
    return ffi.cast("int32_t*", ffi.cast("uint8_t*", addr) + offset)[0]
end

local function is_pe_base(addr)
    local ok, result =
        pcall(
        function()
            local p = ffi.cast("uint8_t*", addr)
            if p[0] ~= 0x4D or p[1] ~= 0x5A then
                return false
            end
            local lfanew = read_i32(addr, 0x3C)
            if lfanew < 0 or lfanew > 0x1000 then
                return false
            end
            return read_u32(addr, lfanew) == 0x4550
        end
    )
    return ok and result
end

local function scan_back_for_base(addr)
    local page = tonumber(bit.band(tonumber(ffi.cast("uintptr_t", addr)), 0xFFFFF000))
    for i = 0, 500 do
        local candidate = page - (i * 0x1000)
        if candidate <= 0x10000 then
            break
        end
        if is_pe_base(candidate) then
            return candidate
        end
    end
    return nil
end

local function find_export(base, func_name)
    local result = nil
    pcall(
        function()
            local lfanew = read_i32(base, 0x3C)
            local nt = base + lfanew
            local export_rva = read_u32(nt, 0x78)
            local export_size = read_u32(nt, 0x7C)
            if export_size == 0 then
                return
            end
            local export_dir = base + export_rva
            local num_names = read_u32(export_dir, 0x18)
            local addr_funcs_rva = read_u32(export_dir, 0x1C)
            local addr_names_rva = read_u32(export_dir, 0x20)
            local addr_ords_rva = read_u32(export_dir, 0x24)
            for i = 0, num_names - 1 do
                local name_rva = read_u32(base, addr_names_rva + i * 4)
                local name = ffi.string(ffi.cast("char*", ffi.cast("uint8_t*", base) + name_rva))
                if name == func_name then
                    local ordinal = read_u16(base, addr_ords_rva + i * 2)
                    local func_rva = read_u32(base, addr_funcs_rva + ordinal * 4)
                    if not (func_rva >= export_rva and func_rva < export_rva + export_size) then
                        result = base + func_rva
                    end
                    return
                end
            end
        end
    )
    return result
end

local function init_resolver()
    local engine_ptr = client.create_interface("engine.dll", "VEngineClient014")
    if not engine_ptr then
        return false
    end
    local engine_base = scan_back_for_base(engine_ptr)
    if not engine_base then
        return false
    end

    local k32_any_addr = nil
    pcall(
        function()
            local lfanew = read_i32(engine_base, 0x3C)
            local nt = engine_base + lfanew
            local import_rva = read_u32(nt, 0x80)
            local import_size = read_u32(nt, 0x84)
            if import_size == 0 then
                return
            end
            local desc = engine_base + import_rva
            while true do
                local name_rva = read_u32(desc, 0x0C)
                if name_rva == 0 then
                    break
                end
                local dll_name = ffi.string(ffi.cast("char*", ffi.cast("uint8_t*", engine_base) + name_rva))
                if dll_name:lower() == "kernel32.dll" then
                    local ft_rva = read_u32(desc, 0x10)
                    k32_any_addr = read_u32(engine_base + ft_rva, 0)
                    break
                end
                desc = desc + 20
            end
        end
    )

    if not k32_any_addr then
        return false
    end
    local k32_base = scan_back_for_base(k32_any_addr)
    if not k32_base then
        return false
    end

    Security.resolved.GetVolumeInformationA = find_export(k32_base, "GetVolumeInformationA")
    Security.resolved.GetComputerNameA = find_export(k32_base, "GetComputerNameA")
    return Security.resolved.GetVolumeInformationA ~= nil and Security.resolved.GetComputerNameA ~= nil
end

local function get_volume_serial()
    if not Security.resolved.GetVolumeInformationA then
        return "0"
    end
    local serial = ffi.new("uint32_t[1]")
    local fn =
        ffi.cast(
        "int(__stdcall*)(const char*, char*, uint32_t, uint32_t*, uint32_t*, uint32_t*, char*, uint32_t)",
        Security.resolved.GetVolumeInformationA
    )
    if fn("C:\\", nil, 0, serial, nil, nil, nil, 0) ~= 0 then
        return tostring(serial[0])
    end
    return "0"
end

local function get_pc_name()
    if not Security.resolved.GetComputerNameA then
        return "unknown_pc"
    end
    local buffer = ffi.new("char[256]")
    local size = ffi.new("uint32_t[1]", 256)
    local fn = ffi.cast("int(__stdcall*)(char*, uint32_t*)", Security.resolved.GetComputerNameA)
    if fn(buffer, size) ~= 0 then
        return ffi.string(buffer)
    end
    return "unknown_pc"
end

local function get_steam_id()
    local ok, pan = pcall(require, "gamesense/panorama")
    if ok and pan then
        local user_info = pan.get_user_info()
        if user_info and user_info.xuid then
            return tostring(user_info.xuid)
        end
    end
    return "unknown"
end

local function get_raw_hash(str)
    local hash = 0
    for i = 1, #str do
        hash = (hash * 31 + str:byte(i)) % 0xFFFFFFFF
    end
    return hash
end

function Security.get_id()
    if not Security.initialized and not init_resolver() then
        return "RESOLVER_ERROR"
    end
    Security.initialized = true
    local serial = get_volume_serial()
    local steam = get_steam_id()
    local pc = get_pc_name()
    local raw = "G2S-" .. serial .. "-" .. steam .. "-" .. pc
    return string.format("%08X", get_raw_hash(raw))
end

function Security.xor(str)
    local my_id_hash = get_raw_hash(Security.get_id())
    local key = bit.band(my_id_hash, 0xFF)
    local res = {}
    for i = 1, #str do
        table.insert(res, string.char(bit.bxor(str:byte(i), key)))
    end
    return table.concat(res)
end

function Security.verify(auto_stop)
    local my_id = Security.get_id()
    local user_name = Security.whitelist[my_id]
    if user_name then
        Security.last_heartbeat = globals.realtime()
        return true
    else
        if auto_stop then
            error("Security: Auth Failed. ID: " .. my_id)
        end
        return false
    end
end

function Security.start_heartbeat()
    client.set_event_callback(
        "paint",
        function()
            local cur_time = globals.realtime()
            if cur_time - Security.last_heartbeat > Security.heartbeat_interval then
                if not Security.verify(false) then
                    error("Security: Session expired")
                end
            end
        end
    )
end

function Security.add_user(id, name)
    Security.whitelist[id] = name
end

return Security
