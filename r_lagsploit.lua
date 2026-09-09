local ui_ref, ui_get, ui_set, ui_set_visible, ui_set_callback =
    ui.reference,
    ui.get,
    ui.set,
    ui.set_visible,
    ui.set_callback
local ui_new_checkbox, ui_new_combobox, ui_new_color_picker, ui_new_hotkey =
    ui.new_checkbox,
    ui.new_combobox,
    ui.new_color_picker,
    ui.new_hotkey

local ent_local, ent_prop, ent_all, ent_players =
    entity.get_local_player,
    entity.get_prop,
    entity.get_all,
    entity.get_players

local cl_eye, cl_cam, cl_w2s, cl_screen =
    client.eye_position,
    client.camera_angles,
    client.world_to_screen,
    client.screen_size
local cl_line, cl_circle, cl_hitboxes = client.draw_line, client.draw_circle, client.draw_hitboxes
local cl_on_event, cl_unset_event, cl_exec = client.set_event_callback, client.unset_event_callback, client.exec

local rd_text, rd_measure = renderer.text, renderer.measure_text

local m_sqrt, m_sin, m_cos, m_rad, m_floor, m_min, m_max =
    math.sqrt,
    math.sin,
    math.cos,
    math.rad,
    math.floor,
    math.min,
    math.max

local R = {
    sv_ticks = ui_ref("MISC", "Settings", "sv_maxusrcmdprocessticks2"),
    fl_amount = ui_ref("AA", "Fake lag", "Amount"),
    fl_limit = ui_ref("AA", "Fake lag", "Limit"),
    fl_var = ui_ref("AA", "Fake lag", "Variance"),
    aa_enabled = ui_ref("AA", "Anti-aimbot angles", "Enabled"),
    air_duck = ui_ref("MISC", "Movement", "Air duck")
}
local dt_ref, dt_key = ui_ref("RAGE", "Aimbot", "Double tap")
R.dt = dt_ref
R.dt_key = dt_key

local UI = {}
UI.master = ui_new_checkbox("LUA", "A", "Enable LagSploit")
UI.hotkey = ui_new_hotkey("LUA", "B", "Exploit")
UI.show_pos = ui_new_combobox("LUA", "B", "Show position", "Off", "Hitboxes", "Point")
UI.pos_clr = ui_new_color_picker("LUA", "B", "Show position", 64, 73, 83, 255)
UI.move_fix = ui_new_checkbox("LUA", "B", "Movement Improved")

local CFG = {
    cross_size = 4,
    hitbox_time = 0.5,
    ticks_on = 19,
    ticks_off = 16,
    ticks_dt = 16,
    fl_limit_on = 18,
    fl_limit_off = 14,
    fl_limit_dt = 15,
    speed_threshold = 270,
    saved_main_text = "LC Break",
    saved_fast_text = "Ideal Break"
}

local S = {
    prev_hotkey = false,
    third_person = false,
    pos_x = nil,
    pos_y = nil,
    pos_z = nil,
    chokes_prev = 0,
    orig = {
        sv_ticks = nil,
        fl_limit = nil,
        fl_amount = nil,
        fl_var = nil,
        aa_enabled = nil,
        air_duck = nil
    }
}

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function is_alive(p)
    return p and ent_prop(p, "m_lifeState") == 0
end

local function get_speed(p)
    local vx, vy = ent_prop(p, "m_vecVelocity")
    if not vx or not vy then
        return 0
    end
    return m_sqrt(vx * vx + vy * vy)
end

local function detect_thirdperson(ctx)
    if not ctx then
        return false
    end
    local x, y, z = cl_eye()
    local pitch, yaw = cl_cam()
    yaw = yaw - 180
    pitch, yaw = m_rad(pitch), m_rad(yaw)
    x = x + m_cos(yaw) * 4
    y = y + m_sin(yaw) * 4
    z = z + m_sin(pitch) * 4
    local sx = cl_w2s(ctx, x, y, z)
    return sx ~= nil
end

local measure_cache = {}
local function cached_measure(ch)
    local w = measure_cache[ch]
    if not w then
        w = rd_measure(nil, ch)
        measure_cache[ch] = w
    end
    return w
end

local function rainbow_rgb(i, time)
    local phase = (m_sin(time * 2 + i * 0.35) + 1) * 0.5
    local r = m_floor(lerp(220, 255, phase))
    local g = m_floor(lerp(160, 255, phase))
    local b = m_floor(lerp(180, 255, phase))
    return r, g, b
end

local function draw_centered_rainbow(text, screen_w, y, time)
    -- total width
    local total = 0
    for i = 1, #text do
        total = total + cached_measure(text:sub(i, i))
    end
    local x = m_floor(screen_w * 0.5 - total * 0.5)
    for i = 1, #text do
        local c = text:sub(i, i)
        local w = cached_measure(c)
        local r, g, b = rainbow_rgb(i, time)
        rd_text(x, y, r, g, b, 255, nil, 0, c)
        x = x + w
    end
end

local function capture_originals()
    if S.orig.sv_ticks ~= nil then
        return
    end
    S.orig.sv_ticks = ui_get(R.sv_ticks)
    S.orig.fl_amount = ui_get(R.fl_amount)
    S.orig.fl_limit = ui_get(R.fl_limit)
    S.orig.fl_var = ui_get(R.fl_var)
    S.orig.aa_enabled = ui_get(R.aa_enabled)
    S.orig.air_duck = ui_get(R.air_duck)
end

local function restore_originals()
    if S.orig.sv_ticks == nil then
        return
    end
    ui_set(R.sv_ticks, S.orig.sv_ticks)
    ui_set(R.fl_amount, S.orig.fl_amount)
    ui_set(R.fl_limit, S.orig.fl_limit)
    ui_set(R.fl_var, S.orig.fl_var)
    ui_set(R.aa_enabled, S.orig.aa_enabled)
    ui_set(R.air_duck, S.orig.air_duck)
    cl_exec("-use")
end

local function refresh_visibility()
    local on = ui_get(UI.master)
    ui_set_visible(UI.hotkey, on)
    ui_set_visible(UI.show_pos, on)
    ui_set_visible(UI.pos_clr, on)
    ui_set_visible(UI.move_fix, on)

    if on then
        capture_originals()
        ui_set(R.fl_amount, "Maximum")
        ui_set(R.fl_var, 0)
    end

    ui_set_visible(R.fl_amount, not on)
    ui_set_visible(R.fl_limit, not on)
    ui_set_visible(R.fl_var, not on)
end
ui_set_callback(UI.master, refresh_visibility)
refresh_visibility()

local function on_run_command(e)
    local choked = e.chokedcommands
    if S.chokes_prev >= choked or choked == 0 then
        if S.chokes_prev > 1 and ui_get(UI.hotkey) then
            local mode = ui_get(UI.show_pos)
            if mode ~= "Off" then
                local lp = ent_local()
                if lp then
                    S.pos_x, S.pos_y, S.pos_z = ent_prop(lp, "m_vecOrigin")
                    if mode == "Hitboxes" and S.third_person then
                        local r, g, b = ui_get(UI.pos_clr)
                        cl_hitboxes(lp, CFG.hitbox_time, 19, r, g, b)
                    end
                end
            end
        end
    end
    S.chokes_prev = choked
end

local function enter_exploit()
    ui_set(R.sv_ticks, CFG.ticks_on)
    ui_set(R.fl_limit, CFG.fl_limit_on)
    ui_set(R.aa_enabled, false)
    cl_exec("+use")
    if ui_get(UI.move_fix) then
        ui_set(R.air_duck, "Spam")
    end
end

local function exit_exploit()
    ui_set(R.sv_ticks, CFG.ticks_off)
    ui_set(R.fl_limit, CFG.fl_limit_off)
    ui_set(R.aa_enabled, true)
    cl_exec("-use")
    if ui_get(UI.move_fix) then
        ui_set(R.air_duck, "Off")
    end
end

local function draw_position_marker(ctx)
    if S.pos_x == nil then
        return
    end
    local r, g, b, a = ui_get(UI.pos_clr)
    local cs = CFG.cross_size
    local x, y, z = S.pos_x, S.pos_y, S.pos_z

    local x1, y1 = cl_w2s(ctx, x - cs, y, z)
    local x2, y2 = cl_w2s(ctx, x + cs, y, z)
    if x1 and x2 then
        cl_line(ctx, x1, y1, x2, y2, r, g, b, a)
    end

    x1, y1 = cl_w2s(ctx, x, y - cs, z)
    x2, y2 = cl_w2s(ctx, x, y + cs, z)
    if x1 and x2 then
        cl_line(ctx, x1, y1, x2, y2, r, g, b, a)
    end

    local cx, cy = cl_w2s(ctx, x, y, z)
    if cx then
        cl_circle(ctx, cx, cy, 16, 16, 16, 255, 2, 0, 1)
    end
end

local function on_paint(ctx)
    if not ui_get(UI.master) then
        return
    end

    local lp = ent_local()
    if not is_alive(lp) then
        return
    end
    if ui_get(R.dt) and ui_get(R.dt_key) then
        ui_set(R.sv_ticks, CFG.ticks_dt)
        ui_set(R.fl_limit, CFG.fl_limit_dt)
        return
    end

    local active = ui_get(UI.hotkey)

    if active ~= S.prev_hotkey then
        if active then
            enter_exploit()
        else
            exit_exploit()
        end
        S.prev_hotkey = active
    end

    if not active then
        return
    end

    S.third_person = detect_thirdperson(ctx)

    local sw, sh = cl_screen()
    local time = (globals.realtime and globals.realtime()) or 0
    local speed = get_speed(lp)

    local base_h = select(2, rd_measure(nil, CFG.saved_main_text)) or 0
    local y1 = sh - base_h - 30
    draw_centered_rainbow(CFG.saved_main_text, sw, y1, time)

    if speed > CFG.speed_threshold then
        local h2 = select(2, rd_measure(nil, CFG.saved_fast_text)) or 0
        draw_centered_rainbow(CFG.saved_fast_text, sw, y1 - h2 - 8, time)
    end

    if ui_get(UI.show_pos) == "Point" and S.third_person then
        draw_position_marker(ctx)
    end
end

local function round_active()
    local rules = ent_all("CCSGameRulesProxy")[1]
    if not rules then
        return true
    end
    if ent_prop(rules, "m_bFreezePeriod") == 1 then
        return false
    end
    local over = ent_prop(rules, "m_iRoundWinStatus") ~= 0
    if over and #ent_players(true) == 0 then
        return false
    end
    return true
end

local function paint_wrapper(ctx)
    if not round_active() then
        return
    end
    on_paint(ctx)
end

cl_on_event("run_command", on_run_command)
cl_on_event("paint", paint_wrapper)
cl_on_event(
    "shutdown",
    function()
        restore_originals()
    end
)
