local ffi = require("ffi")

-- Cache Common API for maximum speed
local ui_get, ui_set, ui_set_visible = ui.get, ui.set, ui.set_visible
local renderer_world_to_screen = renderer.world_to_screen
local renderer_line, renderer_rect, renderer_circle = renderer.line, renderer.rectangle, renderer.circle_outline
local entity_get_local_player, entity_get_origin = entity.get_local_player, entity.get_origin
local entity_set_prop, entity_get_all = entity.set_prop, entity.get_all
local globals_realtime, globals_absoluteframetime = globals.realtime, globals.absoluteframetime
local client_trace_line = client.trace_line
local client_screen_size, client_exec, client_eye_position = client.screen_size, client.exec, client.eye_position
local math_random, math_abs, math_sin, math_cos, math_floor = math.random, math.abs, math.sin, math.cos, math.floor

ffi.cdef [[
    typedef void*(*create_client_class_fn)(int, int);
    typedef void*(*create_event_fn)();
    typedef struct { create_client_class_fn create_fn; create_event_fn ev_fn; char* network_name; void* recv_table; void* next; int class_id; } client_class_t;
    typedef struct { float x, y, z; } vec3_weather_t;
    typedef void(__thiscall* pre_data_update_fn)(void*, int);
    typedef void(__thiscall* pre_data_change_fn)(void*, int);
    typedef void***(__thiscall* get_collideable_fn)(void*);
    typedef vec3_weather_t*(__thiscall* get_collideable_mins_fn)(void*);
    typedef vec3_weather_t*(__thiscall* get_collideable_maxs_fn)(void*);
    typedef void(__thiscall* post_data_change_fn)(void*, int);
    typedef void(__thiscall* post_data_update_fn)(void*, int);
    typedef void(__thiscall* release_entity_fn)(void*);
    typedef void***(__thiscall* get_client_whatever_fn)(void*);
    
    typedef struct {
        int m_nType; void* m_pStartEnt; int m_nStartAttachment; void* m_pEndEnt; int m_nEndAttachment;
        float m_fStartPoint[3]; float m_fEndPoint[3]; int m_nModelIndex; int m_nHaloIndex; float m_fHaloScale;
        float m_fLife; float m_fWidth; float m_fEndWidth; float m_fFadeLength; float m_fAmplitude;
        float m_fBrightness; float m_fSpeed; int m_nStartFrame; float m_fFrameRate; float m_fRed; float m_fGreen; float m_fBlue;
        bool m_bRenderable; int m_nSegments; int m_bNojeeptest; float m_fFlags;
    } BeamInfo_t;
    typedef void*(__thiscall* CreateBeamPoints_t)(void*, BeamInfo_t*);

    struct dlight_weather_t {
        int flags; float origin[3]; float radius; uint8_t r, g, b; int8_t exponent; float die; float decay; float minlight; int key; int style; float direction[3]; float inner_angle; float outer_angle;
    };
]]

-- System Interfaces
local client_interface = ffi.cast("void***", client.create_interface("client.dll", "VClient018"))
local entlist_interface = ffi.cast("void***", client.create_interface("client.dll", "VClientEntityList003"))
local efx_interface = ffi.cast("void***", client.create_interface("engine.dll", "VEngineEffects001"))
local beam_interface_ptr =
    client.create_interface("client.dll", "VViewRenderBeams001") or
    client.create_interface("client.dll", "ProxyEntityList001")

local get_all_classes_fn =
    client_interface ~= nil and ffi.cast("client_class_t*(__thiscall*)(void*)", client_interface[0][8]) or nil
local get_entity_pointer_fn =
    entlist_interface ~= nil and ffi.cast("void*(__thiscall*)(void*, int)", entlist_interface[0][3]) or nil
local AllocDLight =
    efx_interface ~= nil and ffi.cast("struct dlight_weather_t*(__thiscall*)(void*, int)", efx_interface[0][4]) or nil
local beam_interface = nil
local CreateBeamPoints = nil
if beam_interface_ptr then
    beam_interface = ffi.cast("void***", beam_interface_ptr)
    CreateBeamPoints = ffi.cast("CreateBeamPoints_t", beam_interface[0][12])
end

local cvars_el = {
    r_rainradius = cvar.r_rainradius,
    r_rainalpha = cvar.r_rainalpha,
    mat_ambient_r = cvar.mat_ambient_light_r,
    mat_ambient_g = cvar.mat_ambient_light_g,
    mat_ambient_b = cvar.mat_ambient_light_b,
    mat_specular = cvar.mat_specular,
    mat_tonemap = cvar.mat_force_tonemap_scale,
    mat_bumpmap = cvar.mat_bumpmap,
    cl_csm_rot_override = cvar.cl_csm_rot_override,
    cl_csm_rot_x = cvar.cl_csm_rot_x,
    cl_csm_rot_y = cvar.cl_csm_rot_y
}

-- UI Elements Table
local ui_el = {}
ui_el.checkbox = ui.new_checkbox("VISUALS", "Effects", "Weather Engine")
ui_el.system_mode = ui.new_combobox("VISUALS", "Effects", "System Mode", {"Built-in (Engine)", "Custom (Lua 3D)"})
ui_el.atm_preset =
    ui.new_combobox(
    "VISUALS",
    "Effects",
    "Atmosphere Preset",
    {"Custom", "Silent Hill", "London Drizzle", "Sandstorm", "Golden Hour", "Ghost Town", "Heavy Storm", "Morning Dew"}
)
ui_el.engine_effect = ui.new_combobox("VISUALS", "Effects", "Engine Effect", {"None", "Rain"})
ui_el.lua_effect =
    ui.new_combobox("VISUALS", "Effects", "Lua Effect", {"None", "Custom Rain", "Custom Snow", "Custom Ash"})
ui_el.effect_radius = ui.new_slider("VISUALS", "Effects", "Effect Radius", 300, 2000, 800)
ui_el.effect_opacity = ui.new_slider("VISUALS", "Effects", "Effect Opacity", 0, 100, 75, true, "%")
ui_el.lua_particle_count = ui.new_slider("VISUALS", "Effects", "Particle Count", 1, 300, 150)
ui_el.wind_strength = ui.new_slider("VISUALS", "Effects", "Wind Strength", 0, 150, 0, true, "px/s")
ui_el.screen_droplets = ui.new_checkbox("VISUALS", "Effects", "Screen Droplets 💧")
ui_el.ground_splashes = ui.new_checkbox("VISUALS", "Effects", "Ground Splashes 💦")
ui_el.wet_surfaces = ui.new_checkbox("VISUALS", "Effects", "Wet Map Surfaces")
ui_el.lightning_checkbox = ui.new_checkbox("VISUALS", "Effects", "Lightning Strike ⚡")
ui_el.lightning_freq = ui.new_slider("VISUALS", "Effects", "Strike Frequency", 1, 100, 50, true, "%")
ui_el.thunder_shake = ui.new_checkbox("VISUALS", "Effects", "Thunder Shake 🫨")
ui_el.custom_sound_enable = ui.new_checkbox("VISUALS", "Effects", "Custom Thunder Sound")
ui_el.custom_sound_path = ui.new_textbox("VISUALS", "Effects", "Sound Path (csgo/sound/...)")
ui_el.fog_checkbox = ui.new_checkbox("VISUALS", "Effects", "Atmospheric Fog")
ui_el.fog_color = ui.new_color_picker("VISUALS", "Effects", "Fog Color", 150, 150, 150, 255)
ui_el.fog_start = ui.new_slider("VISUALS", "Effects", "Fog Start", 0, 5000, 0)
ui_el.fog_end = ui.new_slider("VISUALS", "Effects", "Fog End", 0, 16384, 3000)
ui_el.fog_density = ui.new_slider("VISUALS", "Effects", "Fog Density", 0, 100, 100, true, nil, .01)
local flare_alpha, shake_time = 0, 0
local lua_particles, screen_drops, impact_particles = {}, {}, {}
local current_light = {r = 0, g = 0, b = 0}
local was_connected, fog_controller_cache, last_cache_time = false, nil, 0

local function visibility_callback()
    local active = ui_get(ui_el.checkbox)
    local mode = ui_get(ui_el.system_mode)
    local is_engine = mode == "Built-in (Engine)"
    local is_lua = mode == "Custom (Lua 3D)"
    local engine_eff = ui_get(ui_el.engine_effect)
    local lua_eff = ui_get(ui_el.lua_effect)
    local is_rain = (is_engine and engine_eff == "Rain") or (is_lua and lua_eff == "Custom Rain")
    local fog_active = ui_get(ui_el.fog_checkbox) and active
    local lightning_active = ui_get(ui_el.lightning_checkbox) and active and is_rain
    ui_set_visible(ui_el.system_mode, active)
    ui_set_visible(ui_el.atm_preset, active)
    ui_set_visible(ui_el.engine_effect, active and is_engine)
    ui_set_visible(ui_el.lua_effect, active and is_lua)
    ui_set_visible(ui_el.effect_radius, active)
    ui_set_visible(ui_el.effect_opacity, active)
    ui_set_visible(ui_el.lua_particle_count, active and is_lua)
    ui_set_visible(ui_el.wind_strength, active and is_lua)
    ui_set_visible(ui_el.screen_droplets, active and is_rain)
    ui_set_visible(ui_el.ground_splashes, active and is_rain)
    ui_set_visible(ui_el.wet_surfaces, active and is_rain)
    ui_set_visible(ui_el.lightning_checkbox, active and is_rain)
    ui_set_visible(ui_el.lightning_freq, lightning_active)
    ui_set_visible(ui_el.thunder_shake, lightning_active)
    ui_set_visible(ui_el.custom_sound_enable, lightning_active)
    ui_set_visible(ui_el.custom_sound_path, lightning_active and ui_get(ui_el.custom_sound_enable))
    ui_set_visible(ui_el.fog_checkbox, active)
    ui_set_visible(ui_el.fog_color, fog_active)
    ui_set_visible(ui_el.fog_start, fog_active)
    ui_set_visible(ui_el.fog_end, fog_active)
    ui_set_visible(ui_el.fog_density, fog_active)
end

local presets = {
    ["Silent Hill"] = {
        fog = true,
        fc = {180, 180, 180, 255},
        fs = 0,
        fe = 1200,
        fden = 100,
        mode = "Custom (Lua 3D)",
        effect = "Custom Ash",
        pcount = 250,
        rad = 500,
        wind = 15,
        light = {0, 0, 0},
        wet = false
    },
    ["London Drizzle"] = {
        fog = true,
        fc = {200, 205, 210, 255},
        fs = 500,
        fe = 3500,
        fden = 40,
        mode = "Custom (Lua 3D)",
        effect = "Custom Rain",
        pcount = 100,
        rad = 800,
        wind = 5,
        light = {0, 0, 0},
        wet = true
    },
    ["Sandstorm"] = {
        fog = true,
        fc = {180, 140, 70, 255},
        fs = 0,
        fe = 1000,
        fden = 100,
        mode = "Custom (Lua 3D)",
        effect = "Custom Ash",
        pcount = 300,
        rad = 450,
        wind = 80,
        light = {0.1, 0.05, 0},
        wet = false
    },
    ["Golden Hour"] = {
        fog = true,
        fc = {255, 140, 40, 180},
        fs = 200,
        fe = 4000,
        fden = 60,
        mode = "Custom (Lua 3D)",
        effect = "Custom Rain",
        pcount = 80,
        rad = 800,
        wind = 5,
        light = {0.15, 0.05, 0},
        wet = false
    },
    ["Ghost Town"] = {
        fog = true,
        fc = {140, 160, 180, 255},
        fs = 0,
        fe = 2500,
        fden = 70,
        mode = "Custom (Lua 3D)",
        effect = "Custom Ash",
        pcount = 60,
        rad = 900,
        wind = 8,
        light = {0, 0, 0},
        wet = false
    },
    ["Heavy Storm"] = {
        fog = true,
        fc = {50, 50, 60, 255},
        fs = 0,
        fe = 1800,
        fden = 100,
        mode = "Custom (Lua 3D)",
        effect = "Custom Rain",
        pcount = 300,
        rad = 600,
        wind = 40,
        light = {0.08, 0.08, 0.12},
        wet = true
    },
    ["Morning Dew"] = {
        fog = true,
        fc = {220, 230, 240, 150},
        fs = 800,
        fe = 5000,
        fden = 30,
        mode = "Custom (Lua 3D)",
        effect = "Custom Rain",
        pcount = 50,
        rad = 1000,
        wind = 0,
        light = {0.1, 0.1, 0.1},
        wet = true
    }
}

local function apply_preset()
    local name = ui_get(ui_el.atm_preset)
    if name == "Custom" then
        return
    end
    local p = presets[name]
    if not p then
        return
    end
    ui_set(ui_el.fog_checkbox, p.fog)
    ui_set(ui_el.fog_color, p.fc[1], p.fc[2], p.fc[3], p.fc[4])
    ui_set(ui_el.fog_start, p.fs)
    ui_set(ui_el.fog_end, p.fe)
    ui_set(ui_el.fog_density, p.fden)
    ui_set(ui_el.system_mode, p.mode)
    if p.mode == "Custom (Lua 3D)" then
        ui_set(ui_el.lua_effect, p.effect)
    else
        ui_set(ui_el.engine_effect, "Rain")
    end
    if p.pcount then
        ui_set(ui_el.lua_particle_count, p.pcount)
    end
    ui_set(ui_el.effect_radius, p.rad)
    ui_set(ui_el.wind_strength, p.wind)
    ui_set(ui_el.wet_surfaces, p.wet)
    if p.light then
        current_light = {r = p.light[1], g = p.light[2], b = p.light[3]}
    else
        current_light = {r = 0, g = 0, b = 0}
    end
    cvars_el.mat_ambient_r:set_float(current_light.r)
    cvars_el.mat_ambient_g:set_float(current_light.g)
    cvars_el.mat_ambient_b:set_float(current_light.b)
    visibility_callback()
end

local precipitation_handler = {
    created = false,
    net = nil,
    ent = nil,
    class = nil,
    current_id = -1,
    release = function(self)
        if self.net then
            local unk = ffi.cast("get_client_whatever_fn", self.net[0][0])(self.net)
            local think = ffi.cast("get_client_whatever_fn", unk[0][8])(unk)
            if think then
                ffi.cast("release_entity_fn", think[0][4])(think)
            end
        end
        self.created, self.net, self.ent, self.current_id = false, nil, nil, -1
    end,
    update = function(self, id)
        if not self.class and get_all_classes_fn then
            local c = get_all_classes_fn(client_interface)
            while (c) do
                if ffi.string(c.network_name) == "CPrecipitation" then
                    self.class = c
                    break
                end
                c = ffi.cast("client_class_t*", c.next)
                if not c then
                    break
                end
            end
        end
        if self.created and self.current_id ~= id then
            self:release()
        end
        if not self.created and self.class then
            self.net = ffi.cast("void***", self.class.create_fn(2047, 0))
            if self.net then
                self.ent = ffi.cast("void***", get_entity_pointer_fn(entlist_interface, 2047))
                entity_set_prop(2047, "m_nPrecipType", id)
                ffi.cast("pre_data_update_fn", self.net[0][6])(self.net, 0)
                ffi.cast("pre_data_change_fn", self.net[0][4])(self.net, 0)
                local coll = ffi.cast("get_collideable_fn", self.ent[0][3])(self.ent)
                if coll then
                    local mn, mx =
                        ffi.cast("get_collideable_mins_fn", coll[0][1])(coll),
                        ffi.cast("get_collideable_maxs_fn", coll[0][2])(coll)
                    mn.x, mn.y, mn.z, mx.x, mx.y, mx.z = -16384, -16384, -16384, 16384, 16384, 16383
                end
                ffi.cast("post_data_change_fn", self.net[0][5])(self.net, 0)
                ffi.cast("post_data_update_fn", self.net[0][7])(self.net, 0)
                self.created, self.current_id = true, id
            end
        end
    end
}

local function create_native_bolt(start_pos, end_pos, width, life)
    if not CreateBeamPoints then
        return
    end
    local m_idx = model_info.get_model_index("sprites/purpleglow1.vmt")
    if m_idx == -1 then
        m_idx = model_info.get_model_index("sprites/physbeam.vmt")
    end
    if m_idx == -1 then
        return
    end
    local info = ffi.new("BeamInfo_t")
    info.m_nType = 0
    info.m_nModelIndex = m_idx
    info.m_nHaloIndex = -1
    info.m_fHaloScale = 0
    info.m_fLife = life
    info.m_fWidth = width
    info.m_fEndWidth = width
    info.m_fFadeLength = 0
    info.m_fAmplitude = 30
    info.m_fBrightness = 255
    info.m_fSpeed = 0.2
    info.m_nStartFrame = 0
    info.m_fFrameRate = 0
    info.m_fRed = 255
    info.m_fGreen = 255
    info.m_fBlue = 255
    info.m_nSegments = 16
    info.m_bRenderable = true
    info.m_fFlags = 0
    info.m_fStartPoint[0], info.m_fStartPoint[1], info.m_fStartPoint[2] = start_pos[1], start_pos[2], start_pos[3]
    info.m_fEndPoint[0], info.m_fEndPoint[1], info.m_fEndPoint[2] = end_pos[1], end_pos[2], end_pos[3]
    CreateBeamPoints(beam_interface, info)
end

local function spawn_dlight(x, y, z, r, g, b, radius, life)
    if not AllocDLight then
        return
    end
    local dl = AllocDLight(efx_interface, -1)
    if dl then
        dl.key = -1
        dl.origin[0], dl.origin[1], dl.origin[2] = x, y, z
        dl.radius = radius
        dl.r, dl.g, dl.b = r, g, b
        dl.die = globals_realtime() + life
        dl.decay = radius / life
        dl.minlight = 0.0
    end
end

local function renderer_circle_3d(x, y, z, r, g, b, a, radius)
    local segments = 16
    local step = 6.28318 / segments
    local last_sx, last_sy
    for i = 0, segments do
        local angle = i * step
        local sx, sy = renderer_world_to_screen(x + math.cos(angle) * radius, y + math.sin(angle) * radius, z)
        if sx and last_sx then
            renderer_line(last_sx, last_sy, sx, sy, r, g, b, a)
        end
        last_sx, last_sy = sx, sy
    end
end

local function draw_bolt_native(bx, by, bz, tx, ty, tz)
    create_native_bolt({bx, by, bz}, {tx, ty, tz}, 35, 0.45)
    spawn_dlight(bx, by, bz, 255, 255, 255, 4000, 0.35)
    for i = 1, 2 do
        local fx, fy, fz = bx + math.random(-1000, 1000), by + math.random(-1000, 1000), bz - 2000
        create_native_bolt({bx, by, bz}, {fx, fy, fz}, 15, 0.25)
    end
end

local function update_all()
    local weather_active = ui_get(ui_el.checkbox)
    local lp = entity_get_local_player()
    if not weather_active or not lp then
        precipitation_handler:release()
        lua_particles, impact_particles, screen_drops = {}, {}, {}
        if was_connected then
            cvars_el.mat_ambient_r:set_float(0.0)
            cvars_el.mat_ambient_g:set_float(0.0)
            cvars_el.mat_ambient_b:set_float(0.0)
            if cvars_el.mat_specular then
                cvars_el.mat_specular:set_int(1)
            end
            if cvars_el.mat_tonemap then
                cvars_el.mat_tonemap:set_float(1.0)
            end
            was_connected = false
        end
        return
    end
    was_connected = true
    local cur_time, ft = globals_realtime(), globals_absoluteframetime()
    local lp_x, lp_y, lp_z = entity_get_origin(lp)
    if not lp_x then
        return
    end
    local eye_x, eye_y, eye_z = client_eye_position()
    if not eye_x then
        return
    end

    local mode, radius, opacity =
        ui_get(ui_el.system_mode),
        ui_get(ui_el.effect_radius),
        ui_get(ui_el.effect_opacity) / 100
    local wind_s = ui_get(ui_el.wind_strength)
    local r, g, b, a = 255, 255, 255, math.floor(opacity * 255)

    -- Optimized CVar management for Wet Surfaces
    if ui_get(ui_el.wet_surfaces) then
        if cvars_el.mat_specular:get_int() ~= 1 then
            cvars_el.mat_specular:set_int(1)
        end
        if cvars_el.mat_bumpmap:get_int() ~= 1 then
            cvars_el.mat_bumpmap:set_int(1)
        end
    end

    if mode == "Built-in (Engine)" then
        lua_particles = {}
        local id = ({["Rain"] = 1})[ui_get(ui_el.engine_effect)] or -1
        if id ~= -1 then
            precipitation_handler:update(id)
            cvars_el.r_rainradius:set_int(radius)
            cvars_el.r_rainalpha:set_float(opacity)
        else
            precipitation_handler:release()
        end
    else
        precipitation_handler:release()
        local type = ui_get(ui_el.lua_effect)
        if type ~= "None" then
            local p_count = ui_get(ui_el.lua_particle_count)
            if #lua_particles ~= p_count then
                lua_particles = {}
                for i = 1, p_count do
                    table.insert(
                        lua_particles,
                        {
                            x = lp_x + math.random(-radius, radius),
                            y = lp_y + math.random(-radius, radius),
                            z = lp_z + math.random(0, 550),
                            vz = math.random(150, 250),
                            seed = math.random(0, 100)
                        }
                    )
                end
            end
            if type == "Custom Ash" then
                r, g, b = 155, 155, 155
            end
            for i = 1, #lua_particles do
                local p = lua_particles[i]
                if type == "Custom Snow" then
                    p.z = p.z - (p.vz * 0.3 * ft)
                    p.x = p.x + (math.sin(cur_time + p.seed) * 18 * ft) + wind_s * ft
                elseif type == "Custom Rain" then
                    p.z = p.z - (p.vz * 3.5 * ft)
                    p.x = p.x + wind_s * ft
                else
                    p.z = p.z - (p.vz * 0.15 * ft)
                    p.x = p.x + (math.cos(cur_time + p.seed) * 12 * ft) + wind_s * ft
                end
                if p.z < lp_z - 180 or math.abs(p.x - lp_x) > radius or math_abs(p.y - lp_y) > radius then
                    p.x, p.y, p.z = lp_x + math.random(-radius, radius), lp_y + math_random(-radius, radius), lp_z + 550
                end
                local sx, sy = renderer_world_to_screen(p.x, p.y, p.z)
                if sx then
                    if type == "Custom Rain" then
                        local sx2, sy2 = renderer_world_to_screen(p.x + wind_s * 0.05, p.y, p.z + 18)
                        if sx2 then
                            renderer_line(sx, sy, sx2, sy2, r, g, b, a)
                        end
                    else
                        renderer_rect(sx, sy, 2, 2, r, g, b, a)
                    end
                end
            end
        end
    end

    if
        ui_get(ui_el.ground_splashes) and
            ((mode == "Built-in (Engine)" and ui_get(ui_el.engine_effect) == "Rain") or
                (mode == "Custom (Lua 3D)" and ui_get(ui_el.lua_effect) == "Custom Rain"))
     then
        if math.random(1, 100) < 65 and #impact_particles < 50 then
            local rx, ry = lp_x + math.random(-radius, radius), lp_y + math.random(-radius, radius)
            local fr_g, ent_g = client_trace_line(lp, rx, ry, lp_z + 800, rx, ry, lp_z - 3000)
            if fr_g and fr_g < 1.0 and (ent_g == 0 or ent_g == -1) then
                local hz = (lp_z + 800) - (fr_g * 3800)
                table.insert(impact_particles, {x = rx, y = ry, z = hz, life = 1.5})
            end
        end
        for i = #impact_particles, 1, -1 do
            local ip = impact_particles[i]
            ip.life = ip.life - 1.2 * ft
            local v_fr, v_ent = client_trace_line(lp, eye_x, eye_y, eye_z, ip.x, ip.y, ip.z + 5)
            if v_fr and v_fr > 0.98 then
                local ratio = ip.life / 1.5
                local inv_ratio = 1.0 - ratio
                renderer_circle_3d(ip.x, ip.y, ip.z, 200, 230, 255, 60 * ratio, inv_ratio * 35)
                if ratio < 0.7 then
                    renderer_circle_3d(ip.x, ip.y, ip.z, 180, 210, 255, 30 * ratio, (0.7 - ratio) * 45)
                end
            end
            if ip.life <= 0 then
                table.remove(impact_particles, i)
            end
        end
    end

    if
        ui_get(ui_el.screen_droplets) and
            ((mode == "Built-in (Engine)" and ui_get(ui_el.engine_effect) == "Rain") or
                (mode == "Custom (Lua 3D)" and ui_get(ui_el.lua_effect) == "Custom Rain"))
     then
        local sw, sh = client_screen_size()
        if math.random(1, 100) < 5 and #screen_drops < 40 then
            table.insert(
                screen_drops,
                {
                    x = math_random(0, sw),
                    y = math_random(0, sh / 2),
                    vel = math_random(20, 60),
                    size = math_random(1, 4),
                    a = math_random(50, 150)
                }
            )
        end
        for i = #screen_drops, 1, -1 do
            local d = screen_drops[i]
            d.y = d.y + d.vel * ft
            d.a = d.a - 15 * ft
            renderer_rect(d.x, d.y, d.size, d.size + 2, 200, 220, 255, math.floor(d.a))
            if d.y > sh or d.a <= 0 then
                table.remove(screen_drops, i)
            end
        end
    end
    if (cur_time - last_cache_time) > 2 then
        local cnt = entity_get_all("CEnvFogController")
        if #cnt == 0 then
            cnt = entity_get_all("CFogController")
        end
        if #cnt > 0 then
            fog_controller_cache = cnt[1]
        end
        last_cache_time = cur_time
    end
    if fog_controller_cache and ui_get(ui_el.fog_checkbox) then
        local fr_f, fg_f, fb_f = ui_get(ui_el.fog_color)
        local fst, fen, fden = ui_get(ui_el.fog_start), ui_get(ui_el.fog_end), ui_get(ui_el.fog_density)
        local pk = fr_f + fg_f * 256 + fb_f * 65536
        entity_set_prop(fog_controller_cache, "m_fog.enable", 1)
        entity_set_prop(fog_controller_cache, "m_fog.start", fst)
        entity_set_prop(fog_controller_cache, "m_fog.end", fen)
        entity_set_prop(fog_controller_cache, "m_fog.maxdensity", fden / 100)
        entity_set_prop(fog_controller_cache, "m_fog.colorPrimary", pk)
        entity_set_prop(fog_controller_cache, "m_fog.colorSecondary", pk)
        entity_set_prop(lp, "m_skybox3d.fog.enable", 1)
        entity_set_prop(lp, "m_skybox3d.fog.start", fst)
        entity_set_prop(lp, "m_skybox3d.fog.end", fen)
        entity_set_prop(lp, "m_skybox3d.fog.maxdensity", fden / 100)
        entity_set_prop(lp, "m_skybox3d.fog.colorPrimary", pk)
    end

    if
        ui_get(ui_el.lightning_checkbox) and
            ((mode == "Built-in (Engine)" and ui_get(ui_el.engine_effect) == "Rain") or
                (mode == "Custom (Lua 3D)" and ui_get(ui_el.lua_effect) == "Custom Rain"))
     then
        if flare_alpha <= 0 and math.random(1, 1500) <= ui_get(ui_el.lightning_freq) then
            flare_alpha = 255
            if ui_get(ui_el.thunder_shake) then
                shake_time = 0.6
            end
            local dist = math.random(8000, 12000)
            local ang = math.random(0, 360) * (3.1415 / 180)
            local bx, by, bz = lp_x + math.cos(ang) * dist, lp_y + math_sin(ang) * dist, lp_z + math.random(4000, 6000)
            draw_bolt_native(bx, by, bz, bx + math.random(-1000, 1000), by + math.random(-1000, 1000), lp_z - 3000)
            local sound_val = math.random(1, 4)
            local sound_path =
                ui_get(ui_el.custom_sound_enable) and ui_get(ui_el.custom_sound_path) or
                ("ambient/weather/thunder" .. sound_val)
            if sound_path ~= "" then
                client_exec("playvol " .. sound_path .. " 1")
            end
        end
    end

    if (flare_alpha or 0) > 0 then
        flare_alpha = flare_alpha - (ft * 600)
    end
end

client.set_event_callback(
    "setup_command",
    function(cmd)
        if cmd and (shake_time or 0) > 0 then
            cmd.roll = cmd.roll + math.random(-12, 12)
            shake_time = shake_time - 0.015
        end
    end
)
client.set_event_callback("paint", update_all)
client.set_event_callback(
    "level_init",
    function()
        fog_controller_cache = nil
        lua_particles, impact_particles, screen_drops = {}, {}, {}
        precipitation_handler:release()
    end
)
client.set_event_callback(
    "shutdown",
    function()
        precipitation_handler:release()
        cvars_el.mat_ambient_r:set_float(0.0)
        cvars_el.mat_ambient_g:set_float(0.0)
        cvars_el.mat_ambient_b:set_float(0.0)
        if cvars_el.mat_specular then
            cvars_el.mat_specular:set_int(1)
        end
        if cvars_el.mat_tonemap then
            cvars_el.mat_tonemap:set_float(1.0)
        end
    end
)
ui.set_callback(ui_el.atm_preset, apply_preset)
ui.set_callback(ui_el.checkbox, visibility_callback)
ui.set_callback(ui_el.system_mode, visibility_callback)
ui.set_callback(ui_el.engine_effect, visibility_callback)
ui.set_callback(ui_el.lua_effect, visibility_callback)
ui.set_callback(ui_el.lightning_checkbox, visibility_callback)
ui.set_callback(ui_el.fog_checkbox, visibility_callback)
ui.set_callback(ui_el.custom_sound_enable, visibility_callback)
visibility_callback()
client.log("--- Weather Engine Restored ---")
