local ffi = require "ffi"
local HOOKLIB_PATHS = {
    "gamesense/lib/hook",
    "gamesense/lib/hook.lua",
    "gamesense/hook",
    "gamesense/hook.lua",
    "lib/hook",
    "hook"
}

local HookLib
local load_errors = {}
for _, path in ipairs(HOOKLIB_PATHS) do
    local ok, mod = pcall(require, path)
    if ok and type(mod) == "table" and mod.initialize then
        HookLib = mod
        client.color_log(120, 255, 180, "[anim] ")
        client.log('HookLib loaded from "' .. path .. '"')
        break
    else
        load_errors[#load_errors + 1] = path .. " -> " .. tostring(mod)
    end
end

if not HookLib then
    client.color_log(255, 80, 80, "[anim] ")
    client.log("FATAL: hook.lua not found. Tried:")
    for _, e in ipairs(load_errors) do
        client.color_log(200, 200, 200, "  ")
        client.log(e)
    end
    error("[anim] hook.lua (HookLib) not found in any known path")
end

do
    local required = {
        "initialize",
        "cleanup_all",
        "hook_frame_stage_notify",
        "create_detour",
        "find_pattern"
    }
    local missing = {}
    for _, name in ipairs(required) do
        if type(HookLib[name]) ~= "function" then
            missing[#missing + 1] = name
        end
    end
    if #missing > 0 then
        error("[anim] HookLib missing functions: " .. table.concat(missing, ", "))
    end
end

HookLib.config.debug = false
HookLib.initialize()

-- UI
local ref = {
    master = ui.new_checkbox("LUA", "B", "Animation helper"),
    anim_fix = ui.new_checkbox("LUA", "B", "  force UpdateClientSideAnimation"),
    simfix = ui.new_checkbox("LUA", "B", "  simulation time fix"),
    bone_inval = ui.new_checkbox("LUA", "B", "  invalidate bone cache"),
    pose_fix = ui.new_checkbox("LUA", "B", "  override pose parameters"),
    pitch_mode = ui.new_combobox("LUA", "B", "    body pitch", "eye angles", "zero", "down", "up"),
    move_yaw = ui.new_slider("LUA", "B", "    move_yaw bias", -180, 180, 0, true, "°"),
    lean = ui.new_slider("LUA", "B", "    lean bias", -60, 60, 0, true, "°"),
    setup_bones = ui.new_checkbox("LUA", "B", "  SetupBones detour (danger)"),
    debug_log = ui.new_checkbox("LUA", "B", "  debug log")
}

local function log(...)
    if ui.get(ref.debug_log) then
        client.color_log(120, 200, 255, "[anim] ")
        client.log(...)
    end
end

local function enabled()
    return ui.get(ref.master)
end

-- FFI helper
local function vtable(this)
    return ffi.cast("void***", this)[0]
end

local function as_u32(p)
    return tonumber(ffi.cast("uintptr_t", p))
end

-- Auto-finding of correct vtables and offsets | ClientEntityList::GetClientEntity
local ent_list =
    client.create_interface("client.dll", "VClientEntityList003") or error("[anim] VClientEntityList003 not found")

local GetClientEntity_raw = ffi.cast("void*(__thiscall*)(void*, int)", vtable(ent_list)[3])
local function GetClientEntity(idx)
    return GetClientEntity_raw(ent_list, idx)
end
local OFF_POSE_PARAMETER = 0x2774
local UPDATE_CLIENTSIDE_ANIM_IDX = 224
local UPDATE_SIGS = {
    "\x55\x8B\xEC\x83\xE4\xF8\x83\xEC\x64\x56\x8B\xF1\x8B\x86",
    "\x55\x8B\xEC\x83\xE4\xF8\x83\xEC\x58\x56\x8B\xF1",
    "\x55\x8B\xEC\x83\xE4\xF8\x83\xEC\x2C\x56\x8B\xF1"
}

local UpdateClientSideAnimation_fn

local function resolve_update_anim_fn()
    if UpdateClientSideAnimation_fn then
        return UpdateClientSideAnimation_fn
    end
    local try_ent = entity.get_local_player()
    if not try_ent then
        local players = entity.get_players(false)
        try_ent = players and players[1]
    end
    if try_ent then
        local ptr = GetClientEntity(try_ent)
        if ptr ~= nil then
            local ok, fn =
                pcall(
                function()
                    return vtable(ptr)[UPDATE_CLIENTSIDE_ANIM_IDX]
                end
            )
            if ok and fn ~= nil then
                UpdateClientSideAnimation_fn = ffi.cast("void(__thiscall*)(void*)", fn)
                log(
                    "UpdateClientSideAnimation via vtable[" ..
                        UPDATE_CLIENTSIDE_ANIM_IDX .. "] = 0x" .. bit.tohex(as_u32(fn))
                )
                return UpdateClientSideAnimation_fn
            end
        end
    end

    -- fallback signatures
    for _, sig in ipairs(UPDATE_SIGS) do
        local addr = client.find_signature("client.dll", sig)
        if addr then
            UpdateClientSideAnimation_fn = ffi.cast("void(__thiscall*)(void*)", addr)
            log("UpdateClientSideAnimation via signature = 0x" .. bit.tohex(as_u32(addr)))
            return UpdateClientSideAnimation_fn
        end
    end

    return nil
end

if not resolve_update_anim_fn() then
    client.color_log(255, 200, 80, "[anim] ")
    client.log("UpdateClientSideAnimation will be resolved later (no entities yet)")
end
local OFF_MOSTRECENT_MODELBONECTR = 0x2924 -- m_iMostRecentModelBoneCounter

local function invalidate_bone_cache(ent_ptr)
    return pcall(
        function()
            local p = ffi.cast("uintptr_t", ent_ptr) + OFF_MOSTRECENT_MODELBONECTR
            ffi.cast("uint32_t*", p)[0] = 0xFFFFFFFF
        end
    )
end

-- Indexes (CS:GO PlayerAnimState):
--   0 = lean_yaw          6 = aim_blend_stand_idle
--   1 = speed             7 = aim_blend_stand_walk
--   2 = ladder_speed      8 = aim_blend_stand_run
--   3 = ladder_yaw        9 = aim_blend_crouch_idle
--   4 = move_yaw         10 = aim_blend_crouch_walk
--   5 = stand            11 = body_pitch
--                        12 = body_yaw
--                        13 = death_yaw

local POSE = {
    lean_yaw = 0,
    move_yaw = 4,
    body_pitch = 11,
    body_yaw = 12
}

-- class checking
local function is_valid_player(idx)
    if not entity.is_alive(idx) then
        return false
    end
    if entity.is_dormant(idx) then
        return false
    end
    local cls = entity.get_classname(idx)
    return cls == "CCSPlayer"
end

local function set_pose(entity_ptr, idx, v01)
    if v01 < 0 then
        v01 = 0
    elseif v01 > 1 then
        v01 = 1
    end
    return pcall(
        function()
            local addr = ffi.cast("uintptr_t", entity_ptr) + OFF_POSE_PARAMETER + idx * 4
            ffi.cast("float*", addr)[0] = v01
        end
    )
end

local function deg_to_01(deg, min, max)
    local t = (deg - min) / (max - min)
    if t < 0 then
        t = 0
    elseif t > 1 then
        t = 1
    end
    return t
end

local OFF_SIM_TIME = 0x268 -- m_flSimulationTime

local function simtime_fix(ent_ptr)
    return pcall(
        function()
            local base = ffi.cast("uintptr_t", ent_ptr) + OFF_SIM_TIME
            local sim = ffi.cast("float*", base)
            local osim = ffi.cast("float*", base + 4) -- m_flOldSimulationTime
            if sim[0] > 0 then
                osim[0] = sim[0] - globals.tickinterval()
            end
        end
    )
end

local FRAME_NET_UPDATE_END = 6

HookLib.hook_frame_stage_notify(
    function(stage)
        if not enabled() then
            return
        end
        if stage == 5 and ui.get(ref.simfix) then
            local ps = entity.get_players(true)
            for i = 1, #ps do
                local idx = ps[i]
                if is_valid_player(idx) then
                    local ep = GetClientEntity(idx)
                    if ep ~= nil then
                        simtime_fix(ep)
                    end
                end
            end
            return
        end

        if stage ~= FRAME_NET_UPDATE_END then
            return
        end

        local me = entity.get_local_player()
        if not me then
            return
        end

        local players = entity.get_players(true)
        for i = 1, #players do
            local idx = players[i]
            if is_valid_player(idx) then
                local ent_ptr = GetClientEntity(idx)
                if ent_ptr ~= nil then
                    if ui.get(ref.anim_fix) then
                        local fn = resolve_update_anim_fn()
                        if fn then
                            pcall(fn, ent_ptr)
                        end
                    end

                    if ui.get(ref.bone_inval) then
                        invalidate_bone_cache(ent_ptr)
                    end
                -- pose override makes into SetupBones detour
                end
            end
        end
    end
)

-- SetupBones detour
-- typedef: bool C_BaseAnimating::SetupBones(matrix3x4_t* out, int maxbones, int boneMask, float currentTime)
-- singatures into client.dll:
local SETUP_BONES_SIG = "\x55\x8B\xEC\x83\xE4\xF0\xB8\xCC\xCC\xCC\xCC\xE8\xCC\xCC\xCC\xCC\x56\x8B\xF1"

local setup_bones_hook
local function install_setup_bones()
    if setup_bones_hook then
        return
    end
    local ok, err =
        pcall(
        function()
            setup_bones_hook =
                HookLib.create_detour(
                "bool(__fastcall*)(void*, void*, void*, int, int, float)",
                function(thisptr, edx, out_matrix, maxbones, bone_mask, cur_time)
                    if enabled() then
                        local ent_addr = as_u32(thisptr)
                        if ui.get(ref.setup_bones) then
                            local sim = ffi.cast("float*", ent_addr + OFF_SIM_TIME)[0]
                            if sim and sim > 0 then
                                cur_time = sim
                            end
                        end

                        if ui.get(ref.pose_fix) then
                            local me_ptr = nil
                            local me_idx = entity.get_local_player()
                            if me_idx then
                                me_ptr = GetClientEntity(me_idx)
                            end

                            if thisptr ~= me_ptr then
                                local mode = ui.get(ref.pitch_mode)
                                if mode == "zero" then
                                    set_pose(thisptr, POSE.body_pitch, 0.5)
                                elseif mode == "down" then
                                    set_pose(thisptr, POSE.body_pitch, 1.0)
                                elseif mode == "up" then
                                    set_pose(thisptr, POSE.body_pitch, 0.0)
                                elseif mode == "eye angles" then
                                    -- m_angEyeAngles[0] reading from game memory
                                    local ok_p, pitch =
                                        pcall(
                                        function()
                                            return ffi.cast("float*", ent_addr + 0xB3C0)[0]
                                        end
                                    )
                                    if ok_p and pitch and pitch == pitch then -- NaN guard
                                        set_pose(thisptr, POSE.body_pitch, (pitch + 90) / 180)
                                    end
                                end

                                local lean = ui.get(ref.lean)
                                if lean ~= 0 then
                                    set_pose(thisptr, POSE.lean_yaw, deg_to_01(lean, -60, 60))
                                end

                                local my = ui.get(ref.move_yaw)
                                if my ~= 0 then
                                    set_pose(thisptr, POSE.move_yaw, deg_to_01(my, -180, 180))
                                end
                            end
                        end
                    end
                    return setup_bones_hook:call_original(thisptr, edx, out_matrix, maxbones, bone_mask, cur_time)
                end,
                SETUP_BONES_SIG,
                "client.dll",
                5,
                true
            )
            setup_bones_hook:enable()
        end
    )
    if ok then
        log("SetupBones detour installed")
    else
        log("SetupBones install failed: " .. tostring(err))
    end
end

local function sync_subsystems()
    -- pose_fix needs SetupBones detour now
    if ui.get(ref.setup_bones) or ui.get(ref.pose_fix) then
        install_setup_bones()
    end
end

ui.set_callback(ref.setup_bones, sync_subsystems)
ui.set_callback(ref.pose_fix, sync_subsystems)
sync_subsystems()

-- UI visibility
local function refresh_visibility()
    local m = ui.get(ref.master)
    local p = ui.get(ref.pose_fix)
    ui.set_visible(ref.anim_fix, m)
    ui.set_visible(ref.simfix, m)
    ui.set_visible(ref.bone_inval, m)
    ui.set_visible(ref.pose_fix, m)
    ui.set_visible(ref.pitch_mode, m and p)
    ui.set_visible(ref.move_yaw, m and p)
    ui.set_visible(ref.lean, m and p)
    ui.set_visible(ref.setup_bones, m)
    ui.set_visible(ref.debug_log, m)
end
ui.set_callback(ref.master, refresh_visibility)
ui.set_callback(ref.pose_fix, refresh_visibility)
refresh_visibility()

client.set_event_callback(
    "shutdown",
    function()
        pcall(HookLib.cleanup_all)
    end
)
client.color_log(120, 255, 180, "[anim] ")
client.log("animation helper loaded")
