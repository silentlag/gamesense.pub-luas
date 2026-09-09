local ffi = require "ffi"
local HookLib = require "gamesense/hook"
HookLib.initialize()

-- UI
local enabled = ui.new_checkbox("LUA", "B", "Anim fix (enemies)")
local force_pitch = ui.new_checkbox("LUA", "B", "  force body pitch")

-- vtable helpers
local function vtable(this)
    return ffi.cast("void***", this)[0]
end

-- CVClientEntityList003::GetClientEntity
local ent_list = client.create_interface("client.dll", "VClientEntityList003")
local GetClientEntity = ffi.cast("void*(__thiscall*)(void*, int)", vtable(ent_list)[3])

-- C_BaseAnimating::UpdateClientSideAnimation — index into vtable player
-- client.dll: "55 8B EC 83 E4 F8 83 EC 64 56 8B F1 8B 86 ? ? ? ? 85 C0 75 ? 5E 8B E5 5D C3"
local UPDATE_CLIENTSIDE_ANIM_IDX = 224
local UpdateClientSideAnimation_t = ffi.typeof("void(__thiscall*)(void*)")
local function update_anims(entity_ptr)
    local fn = ffi.cast(UpdateClientSideAnimation_t, vtable(entity_ptr)[UPDATE_CLIENTSIDE_ANIM_IDX])
    fn(entity_ptr)
end

-- m_flPoseParameter — massive from 24 floats. 11 = body_pitch, 12 = body_yaw.
-- Offset m_flPoseParameter into C_BaseAnimating default one is 0x2774 (can be different).
local OFF_POSE_PARAMETER = 0x2774

local function set_pose_parameter(entity_ptr, idx, value)
    local addr = ffi.cast("uintptr_t", entity_ptr) + OFF_POSE_PARAMETER + idx * 4
    ffi.cast("float*", addr)[0] = value
end

-- Hook FrameStageNotify
local FRAME_NET_UPDATE_END = 6
local me_cache

HookLib.hook_frame_stage_notify(
    function(stage)
        if stage ~= FRAME_NET_UPDATE_END then
            return
        end
        if not ui.get(enabled) then
            return
        end
        local me = entity.get_local_player()
        if not me then
            return
        end
        local players = entity.get_players(true)
        for i = 1, #players do
            local idx = players[i]
            if entity.is_alive(idx) and not entity.is_dormant(idx) then
                local ent_ptr = GetClientEntity(idx)
                if ent_ptr ~= nil then
                    local ok = pcall(update_anims, ent_ptr)
                    if ok and ui.get(force_pitch) then
                        local _, pitch = entity.get_prop(idx, "m_angEyeAngles")
                        if pitch then
                            local v = (pitch + 90) / 180
                            set_pose_parameter(ent_ptr, 11, v)
                        end
                    end
                end
            end
        end
    end
)

client.set_event_callback(
    "shutdown",
    function()
        HookLib.cleanup_all()
    end
)