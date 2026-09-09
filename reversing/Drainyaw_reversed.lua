-- @silentlag

local ffi_ok, ffi = pcall(require, "ffi")
local http_ok, http = pcall(require, "gamesense/http")
local vector_ok, vector = pcall(require, "vector")
local bit_ok, bit = pcall(require, "bit")
if not bit_ok then
    bit = {band = function(a, b)
            return a
        end}
end
local ENABLE_REMOTE_AUTH = false
local LOCAL_AUTH_USERNAME = "avril"
local URL_USERS = "http://sadboyzzz.xyz/dyusers"
local STATE_INI = ":\\Windows\\Setup\\State\\State.ini"

local function log(msg)
    client.color_log(255, 127, 64, "[drainyaw] " .. tostring(msg))
end
local function warn(msg)
    client.color_log(255, 80, 80, "[drainyaw] " .. tostring(msg))
end

local function clamp(x, a, b)
    x = tonumber(x) or 0
    if x < a then
        return a
    end
    if x > b then
        return b
    end
    return x
end

local function normalize_yaw(y)
    y = tonumber(y) or 0
    while y > 180 do
        y = y - 360
    end
    while y < -180 do
        y = y + 360
    end
    return y
end

local function contains(list, value)
    if type(list) ~= "table" then
        return false
    end
    for i = 1, #list do
        if list[i] == value then
            return true
        end
    end
    return false
end

local function pack(...)
    return {...}
end

local function reference_any(label, candidates, silent)
    for i = 1, #candidates do
        local p = candidates[i]
        local ok, a, b, c = pcall(ui.reference, p[1], p[2], p[3])
        if ok then
            if i > 1 then
                log("reference resolved: " .. label .. " -> " .. p[1] .. " / " .. p[2] .. " / " .. p[3])
            end
            return pack(a, b, c)
        end
    end
    if not silent then
        warn("missing ui.reference: " .. label)
    end
    return {}
end

local function ref_get(ref, index)
    if type(ref) == "table" then
        return ref[index or 1]
    end
    return ref
end

local function set_ref(ref, value, index)
    if type(ref) == "table" then
        if index then
            return ref[index] ~= nil and pcall(ui.set, ref[index], value)
        end
        for i = 1, #ref do
            if ref[i] ~= nil and pcall(ui.set, ref[i], value) then
                return true
            end
        end
        return false
    end
    return ref ~= nil and pcall(ui.set, ref, value)
end

local function get_ref(ref, index)
    local r = ref_get(ref, index)
    if r == nil then
        return nil
    end
    local ok, value = pcall(ui.get, r)
    if ok then
        return value
    end
end

local function enabled(ref, index)
    return get_ref(ref, index) and true or false
end

local function set_visible(ref, visible)
    if type(ref) == "table" then
        for i = 1, #ref do
            if ref[i] ~= nil then
                pcall(ui.set_visible, ref[i], visible)
            end
        end
    elseif ref ~= nil then
        pcall(ui.set_visible, ref, visible)
    end
end

local function set_callback(ref, fn)
    if ref ~= nil then
        pcall(ui.set_callback, ref, fn)
    end
end

local function color(ref, fallback)
    local ok, r, g, b, a = pcall(ui.get, ref)
    if ok and r ~= nil then
        return r, g, b, a or 255
    end
    return fallback[1], fallback[2], fallback[3], fallback[4]
end

local function option(ref, name)
    return contains(get_ref(ref) or {}, name)
end

local refs = {
    enabled = reference_any("AA enabled", {{"AA", "Anti-aimbot angles", "Enabled"}}),
    pitch = reference_any("Pitch", {{"AA", "Anti-aimbot angles", "Pitch"}, {"AA", "Anti-aimbot angles", "pitch"}}),
    yaw_base = reference_any("Yaw base", {{"AA", "Anti-aimbot angles", "Yaw base"}}),
    yaw = reference_any("Yaw", {{"AA", "Anti-aimbot angles", "Yaw"}}),
    yaw_jitter = reference_any("Yaw jitter", {{"AA", "Anti-aimbot angles", "Yaw jitter"}}),
    body_yaw = reference_any("Body yaw", {{"AA", "Anti-aimbot angles", "Body yaw"}}),
    freestanding = reference_any("Freestanding", {{"AA", "Anti-aimbot angles", "Freestanding"}}),
    fs_body_yaw = reference_any(
        "Freestanding body yaw",
        {{"AA", "Anti-aimbot angles", "Freestanding body yaw"}, {"AA", "anti-aimbot angles", "Freestanding body yaw"}}
    ),
    edge_yaw = reference_any("Edge yaw", {{"AA", "Anti-aimbot angles", "Edge yaw"}}),
    roll = reference_any("Roll", {{"AA", "Anti-aimbot angles", "Roll"}}),
    fake_yaw_limit = reference_any(
        "Fake yaw limit",
        {{"AA", "Anti-aimbot angles", "Fake yaw limit"}, {"AA", "Anti-aimbot angles", "Fake yaw"}},
        true
    ),
    fakelag_enabled = reference_any("Fake lag Enabled", {{"AA", "Fake lag", "Enabled"}}),
    fakelag_amount = reference_any("Fake lag Amount", {{"AA", "Fake lag", "Amount"}}),
    fakelag_limit = reference_any("Fake lag Limit", {{"AA", "Fake lag", "Limit"}}),
    fakelag_variance = reference_any("Fake lag Variance", {{"AA", "Fake lag", "Variance"}}),
    slow_motion = reference_any("Slow motion", {{"AA", "Other", "Slow motion"}}),
    leg_movement = reference_any("Leg movement", {{"AA", "Other", "Leg movement"}}),
    onshot = reference_any(
        "On shot anti-aim",
        {{"AA", "Other", "On shot anti-aim"}, {"aa", "other", "On shot anti-aim"}}
    ),
    fake_peek = reference_any("Fake peek", {{"AA", "Other", "Fake peek"}}),
    rage_enabled = reference_any("RAGE Enabled", {{"RAGE", "Aimbot", "Enabled"}}),
    double_tap = reference_any("Double tap", {{"RAGE", "Aimbot", "Double tap"}, {"RAGE", "Other", "Double tap"}}),
    doubletap_fakelag_limit = reference_any(
        "Double tap fake lag limit",
        {{"RAGE", "Aimbot", "Double tap fake lag limit"}}
    ),
    force_baim = reference_any(
        "Force body aim",
        {{"RAGE", "Aimbot", "Force body aim"}, {"RAGE", "Other", "Force body aim"}}
    ),
    force_safepoint = reference_any("Force safe point", {{"RAGE", "Aimbot", "Force safe point"}}),
    quick_peek = reference_any("Quick peek assist", {{"RAGE", "Other", "Quick peek assist"}}),
    duck_peek = reference_any("Duck peek assist", {{"RAGE", "Other", "Duck peek assist"}}),
    clan_tag_spammer = reference_any("Clan tag spammer", {{"Misc", "Miscellaneous", "Clan tag spammer"}})
}

local menu = {}
local state = {
    authorized = not ENABLE_REMOTE_AUTH,
    username = ENABLE_REMOTE_AUTH and "not authorized" or "local",
    manual_side = 0,
    manual_name = "",
    hit_side = "left",
    anti_bruteforce_until = 0,
    last_hurt_time = 0,
    last_bullet_time = 0,
    bullet_impacts = {},
    killed_this_round = 0,
    keybind_anim = {},
    manual_prev = {left = false, right = false, forward = false, reset = false},
    last_clantag = "",
    notifications = {},
    local_player = nil
}

local notify

menu.header = ui.new_label("AA", "Anti-aimbot angles", "                      /drainyaw.lua/")
menu.updated = ui.new_label("AA", "Anti-aimbot angles", "               [updated: 31.01.2022]")
menu.enable = ui.new_checkbox("AA", "Anti-aimbot angles", "enable drainyaw - best anti-aim script")

menu.aa_options =
    ui.new_multiselect(
    "AA",
    "Anti-aimbot angles",
    "Anti-aim settings",
    "Anti-Aim Presets",
    "Legit Anti-aims",
    "Manual Anti-aims",
    "Roll Anti-aims",
    "Freestanding",
    "Edge yaw",
    "Anti-bruteforce",
    "Anti-aim on use"
)
menu.misc_options =
    ui.new_multiselect(
    "AA",
    "Other",
    "Misc settings",
    "Animation Breaker",
    "Leg movement",
    "Slow motion",
    "Clantag",
    "Killsay"
)
menu.visual_options =
    ui.new_multiselect(
    "AA",
    "Other",
    "Visual settings",
    "Keybinds",
    "Keybinds Always Show",
    "Manual Arrows",
    "Circles Arrows",
    "Lua Name",
    "Anti-Aim Gradient"
)
menu.aa_presets =
    ui.new_combobox(
    "AA",
    "Anti-aimbot angles",
    "Anti-Aim Presets",
    "Default",
    "Jitter",
    "Static",
    "Center",
    "At targets"
)
menu.yaw_base = ui.new_combobox("AA", "Anti-aimbot angles", "Yaw base override", "Local view", "At targets")
menu.yaw_offset = ui.new_slider("AA", "Anti-aimbot angles", "Yaw offset", -180, 180, 0, true, "°")
menu.yaw_jitter_offset = ui.new_slider("AA", "Anti-aimbot angles", "Yaw jitter offset", -180, 180, 0, true, "°")
menu.body_yaw_mode = ui.new_combobox("AA", "Anti-aimbot angles", "Body yaw mode", "Off", "Static", "Jitter", "Opposite")
menu.body_yaw_value = ui.new_slider("AA", "Anti-aimbot angles", "Body yaw value", -60, 60, 0, true, "°")
menu.fake_yaw_limit = ui.new_slider("AA", "Fake lag", "drainyaw fake lag limit", 1, 15, 1, true)
menu.fs_body_yaw = ui.new_checkbox("AA", "Anti-aimbot angles", "Freestanding body yaw")
menu.legit_aa = ui.new_checkbox("AA", "Anti-aimbot angles", "Legit AA")
menu.roll = ui.new_checkbox("AA", "Anti-aimbot angles", "Roll Anti-aims")
menu.roll_value = ui.new_slider("AA", "Anti-aimbot angles", "Roll Anti-aims on key", -50, 50, 0, true, "°")
menu.freestand = ui.new_checkbox("AA", "Anti-aimbot angles", "Freestanding")
menu.edge_yaw = ui.new_checkbox("AA", "Anti-aimbot angles", "Edge yaw")
menu.edge_yaw_key = ui.new_hotkey("AA", "Anti-aimbot angles", "Edge yaw on key")
menu.manual_enable = ui.new_checkbox("AA", "Anti-aimbot angles", "Manual Anti-aims")
menu.manual_left = ui.new_hotkey("AA", "Anti-aimbot angles", "Manual Left")
menu.manual_right = ui.new_hotkey("AA", "Anti-aimbot angles", "Manual Right")
menu.manual_forward = ui.new_hotkey("AA", "Anti-aimbot angles", "Manual Forward")
menu.manual_backward = ui.new_hotkey("AA", "Anti-aimbot angles", "Manual Reset")
menu.anti_brute = ui.new_checkbox("AA", "Anti-aimbot angles", "Anti-bruteforce enable")
menu.anti_brute_time = ui.new_slider("AA", "Anti-aimbot angles", "Anti-bruteforce time", 0, 10, 3, true, "s")
menu.anti_aim_on_use = ui.new_checkbox("AA", "Anti-aimbot angles", "Anti-aim on use")
menu.teleport_key = ui.new_hotkey("AA", "Fake lag", "Teleport on key")
menu.auto_teleport_air = ui.new_checkbox("AA", "Fake lag", "Auto-Teleport in air")
menu.adaptive_fake_lags = ui.new_checkbox("AA", "Fake lag", "Adaptive Fake Lags")
menu.doubletap_fakelag = ui.new_slider("AA", "Fake lag", "Double tap fake lag limit", 1, 14, 1, true)
menu.animation_breaker =
    ui.new_multiselect(
    "AA",
    "Other",
    "Animation Breaker",
    "Leg breaker",
    "Static ground legs",
    "Break legs while in air",
    "Always slide",
    "Never slide"
)
menu.leg_movement = ui.new_combobox("AA", "Other", "Leg movement", "Default", "Never slide", "Always slide")
menu.slowtype = ui.new_combobox("AA", "Other", "Slow motion type", "Default", "Always slide", "Never slide")
menu.clantag = ui.new_checkbox("AA", "Other", "drainyaw clantag")
menu.killsay = ui.new_checkbox("AA", "Other", "killsay")
menu.keybinds =
    ui.new_multiselect(
    "AA",
    "Other",
    "Keybinds",
    "Double tap",
    "On shot anti-aim",
    "Slow motion",
    "Force Body aim",
    "Force Safe point",
    "Quick peek assist",
    "Duck peek assist",
    "Freestanding",
    "Anti-bruteforce",
    "Adaptive Fake Lags",
    "Roll Anti-aims"
)
menu.keybind_x = ui.new_slider("AA", "Other", "Keybinds position X", 0, 2500, 20, true, "px")
menu.keybind_y = ui.new_slider("AA", "Other", "Keybinds position Y", 0, 1600, 350, true, "px")
menu.indicator = ui.new_checkbox("AA", "Other", "Show center drainyaw indicators")
menu.indicator_items =
    ui.new_multiselect(
    "AA",
    "Other",
    "Center indicator items",
    "Lua name",
    "Anti-aim state",
    "Manual state",
    "Keybind states",
    "Anti-bruteforce",
    "Crouch state"
)
menu.visual_font =
    ui.new_combobox("AA", "Other", "Visual font style", "Original-like", "Default", "Bold", "Outline", "Large", "Small")
menu.main_color = ui.new_color_picker("AA", "Other", "Main Color", 255, 127, 64, 255)
menu.second_color = ui.new_color_picker("AA", "Other", "Second Color", 255, 255, 255, 255)
menu.ind_color = ui.new_color_picker("AA", "Other", "Keybind color", 255, 127, 64, 255)
menu.load_defaults =
    ui.new_button(
    "AA",
    "Other",
    "Load Default Settings",
    function()
        ui.set(menu.aa_presets, "Default")
        ui.set(menu.yaw_base, "At targets")
        ui.set(menu.yaw_offset, 0)
        ui.set(menu.yaw_jitter_offset, 0)
        ui.set(menu.body_yaw_mode, "Jitter")
        ui.set(menu.body_yaw_value, 0)
        ui.set(menu.fake_yaw_limit, 1)
    end
)
local all_menu = {
    menu.header,
    menu.updated,
    menu.aa_options,
    menu.misc_options,
    menu.visual_options,
    menu.aa_presets,
    menu.yaw_base,
    menu.yaw_offset,
    menu.yaw_jitter_offset,
    menu.body_yaw_mode,
    menu.body_yaw_value,
    menu.fake_yaw_limit,
    menu.fs_body_yaw,
    menu.legit_aa,
    menu.roll,
    menu.roll_value,
    menu.freestand,
    menu.edge_yaw,
    menu.edge_yaw_key,
    menu.manual_enable,
    menu.manual_left,
    menu.manual_right,
    menu.manual_forward,
    menu.manual_backward,
    menu.anti_brute,
    menu.anti_brute_time,
    menu.anti_aim_on_use,
    menu.teleport_key,
    menu.auto_teleport_air,
    menu.adaptive_fake_lags,
    menu.doubletap_fakelag,
    menu.animation_breaker,
    menu.leg_movement,
    menu.slowtype,
    menu.clantag,
    menu.killsay,
    menu.keybinds,
    menu.keybind_x,
    menu.keybind_y,
    menu.indicator,
    menu.indicator_items,
    menu.visual_font,
    menu.main_color,
    menu.second_color,
    menu.ind_color,
    menu.load_defaults
}
local default_aa_controls = {
    refs.enabled,
    refs.pitch,
    refs.yaw_base,
    refs.yaw,
    refs.yaw_jitter,
    refs.body_yaw,
    refs.freestanding,
    refs.fs_body_yaw,
    refs.edge_yaw,
    refs.roll,
    refs.fake_yaw_limit,
    refs.fakelag_enabled,
    refs.fakelag_amount,
    refs.fakelag_variance,
    refs.fakelag_limit,
    refs.slow_motion,
    refs.leg_movement,
    refs.onshot,
    refs.fake_peek
}
local function set_default_aa_visible(visible)
    for i = 1, #default_aa_controls do
        set_visible(default_aa_controls[i], visible)
    end
end
local function update_visibility()
    local on = enabled(menu.enable)
    set_default_aa_visible(not on)

    for i = 1, #all_menu do
        set_visible(all_menu[i], false)
    end
    set_visible(menu.header, on)
    set_visible(menu.updated, on)
    set_visible(menu.aa_options, on)
    set_visible(menu.misc_options, on)
    set_visible(menu.visual_options, on)
    set_visible(menu.load_defaults, on)
    local presets_on = on and option(menu.aa_options, "Anti-Aim Presets")
    set_visible(menu.aa_presets, presets_on)
    set_visible(menu.yaw_base, presets_on)
    set_visible(menu.yaw_offset, presets_on)
    set_visible(menu.yaw_jitter_offset, presets_on)
    set_visible(menu.body_yaw_mode, presets_on)
    set_visible(menu.body_yaw_value, presets_on)
    set_visible(menu.legit_aa, on and option(menu.aa_options, "Legit Anti-aims"))
    set_visible(menu.manual_enable, on and option(menu.aa_options, "Manual Anti-aims"))
    set_visible(menu.manual_left, on and enabled(menu.manual_enable))
    set_visible(menu.manual_right, on and enabled(menu.manual_enable))
    set_visible(menu.manual_forward, on and enabled(menu.manual_enable))
    set_visible(menu.manual_backward, on and enabled(menu.manual_enable))
    set_visible(menu.roll, on and option(menu.aa_options, "Roll Anti-aims"))
    set_visible(menu.roll_value, on and enabled(menu.roll))
    set_visible(menu.freestand, on and option(menu.aa_options, "Freestanding"))
    set_visible(menu.fs_body_yaw, on and option(menu.aa_options, "Freestanding"))
    set_visible(menu.edge_yaw, on and option(menu.aa_options, "Edge yaw"))
    set_visible(menu.edge_yaw_key, on and enabled(menu.edge_yaw))
    set_visible(menu.anti_brute, on and option(menu.aa_options, "Anti-bruteforce"))
    set_visible(menu.anti_brute_time, on and enabled(menu.anti_brute))
    set_visible(menu.anti_aim_on_use, on and option(menu.aa_options, "Anti-aim on use"))
    set_visible(menu.teleport_key, presets_on)
    set_visible(menu.auto_teleport_air, presets_on)
    set_visible(menu.fake_yaw_limit, on)
    set_visible(menu.adaptive_fake_lags, on)
    set_visible(
        menu.doubletap_fakelag,
        on and (enabled(menu.adaptive_fake_lags) or enabled(menu.teleport_key) or enabled(menu.auto_teleport_air))
    )
    set_visible(menu.animation_breaker, on and option(menu.misc_options, "Animation Breaker"))
    set_visible(menu.leg_movement, on and option(menu.misc_options, "Leg movement"))
    set_visible(menu.slowtype, on and option(menu.misc_options, "Slow motion"))
    set_visible(menu.clantag, on and option(menu.misc_options, "Clantag"))
    set_visible(menu.killsay, on and option(menu.misc_options, "Killsay"))
    local show_keybinds =
        on and (option(menu.visual_options, "Keybinds") or option(menu.visual_options, "Keybinds Always Show"))
    set_visible(menu.keybinds, show_keybinds)
    set_visible(menu.keybind_x, show_keybinds)
    set_visible(menu.keybind_y, show_keybinds)
    set_visible(menu.indicator, on and option(menu.visual_options, "Lua Name"))
    set_visible(menu.indicator_items, on and enabled(menu.indicator))
    set_visible(
        menu.visual_font,
        on and
            (enabled(menu.indicator) or option(menu.visual_options, "Keybinds") or
                option(menu.visual_options, "Keybinds Always Show"))
    )
    set_visible(menu.main_color, on and (option(menu.visual_options, "Anti-Aim Gradient") or enabled(menu.indicator)))
    set_visible(menu.second_color, on and option(menu.visual_options, "Anti-Aim Gradient"))
end

local ffi_state = {ready = false}
if ffi_ok then
    pcall(
        function()
            ffi.cdef [[
            typedef struct {
                int64_t pad_0;
                union { int xuid; struct { int xuidlow; int xuidhigh; }; };
                char name[128];
                int userid;
                char guid[33];
                unsigned int friendsid;
                char friendsname[128];
                bool fakeplayer;
                bool ishltv;
                unsigned int customfiles[4];
                unsigned char filesdownloaded;
            } S_playerInfo_t;
            typedef bool(__thiscall* fnGetPlayerInfo)(void*, int, S_playerInfo_t*);
            typedef void(__thiscall* clientcmdun)(void*, const char*, bool);
        ]]
            local raw_engine = client.create_interface("engine.dll", "VEngineClient014")
            local engine = ffi.cast("void***", raw_engine)
            ffi_state.engine = engine
            ffi_state.get_player_info = ffi.cast("fnGetPlayerInfo", engine[0][-8])
            ffi_state.client_cmd_unrestricted = ffi.cast("clientcmdun", engine[0][-114])
            ffi_state.ready = true
        end
    )
end

local function get_hwid_code()
    local ok, body = pcall(readfile, STATE_INI)
    if ok and body and tostring(body):len() > 0 then
        return tostring(body):match("(%d+)") or tostring(body):match("(%w+)") or "ROOT"
    end
    return "ROOT"
end

local function authorize()
    if not ENABLE_REMOTE_AUTH then
        state.authorized = true
        state.username = LOCAL_AUTH_USERNAME
        local now = globals.realtime and globals.realtime() or globals.curtime()
        state.notifications = {}
        state.notifications[#state.notifications + 1] = {
            text = "Connecting to the server...",
            start = now + 0.20,
            duration = 4.8
        }
        state.notifications[#state.notifications + 1] = {
            text = "Connected, starting authorization",
            start = now + 1.25,
            duration = 4.8
        }
        state.notifications[#state.notifications + 1] = {
            text = "Authorization completed, logged in as: " .. state.username,
            start = now + 2.30,
            duration = 5.2
        }
        log("Authorization completed, logged in as: " .. state.username)
        return
    end
    if not http_ok or not http or not http.get then
        warn("http module is unavailable")
        return
    end
    if notify then
        notify("Connecting to the server...", 4.5)
    end
    log("Connected, starting authorization")
    if notify then
        notify("Connected, starting authorization", 4.5)
    end
    http.get(
        URL_USERS,
        function(success, response)
            if not success or not response or response.status ~= 200 then
                print("http error")
                return
            end
            local chunk = loadstring(response.body or "")
            if type(chunk) == "function" then
                pcall(chunk)
            end
            local code = get_hwid_code()
            local list = rawget(_G, "hwid_list") or hwid_list or {}
            for name, hwid in pairs(list) do
                if tostring(hwid) == tostring(code) or tostring(name) == "ROOT" or tostring(name) == "glock" then
                    state.authorized = true
                    state.username = tostring(name)
                    log("Authorization completed, logged in as: " .. state.username)
                    if notify then
                        notify("Authorization completed, logged in as: " .. state.username, 5.5)
                    end
                    return
                end
            end
            error("[drainyaw] You not whitelisted. your code: " .. tostring(code), -2)
        end
    )
end

local function local_player_alive()
    local lp = entity.get_local_player()
    if lp == nil or lp == 0 or entity.is_alive(lp) == false then
        return nil
    end
    return lp
end

local function on_ground(ent)
    local flags = entity.get_prop(ent, "m_fFlags") or 0
    return bit.band(flags, 1) == 1
end

local function speed_2d(ent)
    local vx, vy = entity.get_prop(ent, "m_vecVelocity")
    vx, vy = vx or 0, vy or 0
    return math.sqrt(vx * vx + vy * vy)
end

local function distance3(ax, ay, az, bx, by, bz)
    local dx, dy, dz = (ax or 0) - (bx or 0), (ay or 0) - (by or 0), (az or 0) - (bz or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function distance_point_to_segment(px, py, pz, ax, ay, az, bx, by, bz)
    local abx, aby, abz = bx - ax, by - ay, bz - az
    local apx, apy, apz = px - ax, py - ay, pz - az
    local ab_len2 = abx * abx + aby * aby + abz * abz
    if ab_len2 <= 0.001 then
        return distance3(px, py, pz, ax, ay, az)
    end
    local t = clamp((apx * abx + apy * aby + apz * abz) / ab_len2, 0, 1)
    return distance3(px, py, pz, ax + abx * t, ay + aby * t, az + abz * t)
end

local function is_enemy(ent)
    if ent == nil or ent == 0 then
        return false
    end
    local ok, result = pcall(entity.is_enemy, ent)
    if ok and result ~= nil then
        return result
    end
    local lp = entity.get_local_player()
    if not lp then
        return false
    end
    return entity.get_prop(lp, "m_iTeamNum") ~= entity.get_prop(ent, "m_iTeamNum")
end

local function bullet_side_from_yaw(ix, iy)
    local ex, ey = client.eye_position()
    local _, view_yaw = client.camera_angles()
    local rad = math.rad(view_yaw or 0)
    local fx, fy = math.cos(rad), math.sin(rad)
    local dx, dy = (ix or 0) - (ex or 0), (iy or 0) - (ey or 0)
    local cross = fx * dy - fy * dx
    return cross > 0 and "right" or "left"
end

local function anti_brute_active()
    return globals.curtime() < state.anti_bruteforce_until
end

local function update_manuals()
    if not enabled(menu.manual_enable) then
        state.manual_side, state.manual_name = 0, ""
        state.manual_prev.left, state.manual_prev.right, state.manual_prev.forward, state.manual_prev.reset =
            false,
            false,
            false,
            false
        return
    end

    local left = enabled(menu.manual_left)
    local right = enabled(menu.manual_right)
    local forward = enabled(menu.manual_forward)
    local reset = enabled(menu.manual_backward)

    local function choose(side, name)
        if state.manual_name == name then
            state.manual_side, state.manual_name = 0, ""
        else
            state.manual_side, state.manual_name = side, name
        end
    end

    if left and not state.manual_prev.left then
        choose(-90, "left")
    end
    if right and not state.manual_prev.right then
        choose(90, "right")
    end
    if forward and not state.manual_prev.forward then
        choose(180, "forward")
    end
    if reset and not state.manual_prev.reset then
        state.manual_side, state.manual_name = 0, ""
    end

    state.manual_prev.left, state.manual_prev.right = left, right
    state.manual_prev.forward, state.manual_prev.reset = forward, reset
end

local function set_yaw_mode(mode, offset)
    if refs.yaw[1] ~= nil then
        pcall(ui.set, refs.yaw[1], mode or "180")
    end
    if refs.yaw[2] ~= nil then
        pcall(ui.set, refs.yaw[2], normalize_yaw(offset or 0))
    end
end

local function set_yaw_jitter(mode, value)
    if refs.yaw_jitter[1] ~= nil then
        pcall(ui.set, refs.yaw_jitter[1], mode or "Off")
    end
    if refs.yaw_jitter[2] ~= nil then
        pcall(ui.set, refs.yaw_jitter[2], value or 0)
    end
end

local function set_body_yaw(mode, value)
    if refs.body_yaw[1] ~= nil then
        pcall(ui.set, refs.body_yaw[1], mode or "Off")
    end
    if refs.body_yaw[2] ~= nil then
        pcall(ui.set, refs.body_yaw[2], value or 0)
    end
end

local function apply_preset()
    if refs.enabled[1] then
        set_ref(refs.enabled, true, 1)
    end
    if refs.yaw_base[1] then
        set_ref(refs.yaw_base, get_ref(menu.yaw_base) or "At targets", 1)
    end

    local preset = get_ref(menu.aa_presets)
    local yaw = tonumber(get_ref(menu.yaw_offset)) or 0
    local jitter = tonumber(get_ref(menu.yaw_jitter_offset)) or 0
    local jitter_mode = jitter ~= 0 and "Center" or "Off"
    local body_mode = get_ref(menu.body_yaw_mode) or "Jitter"
    local body_value = tonumber(get_ref(menu.body_yaw_value)) or 0

    if option(menu.aa_options, "Anti-Aim Presets") then
        if preset == "Default" then
        elseif preset == "Jitter" then
            yaw, jitter, jitter_mode = 0, 80, "Center"
            body_mode, body_value = "Jitter", 0
        elseif preset == "Static" then
            yaw, jitter, jitter_mode = 0, 0, "Off"
            body_mode, body_value = "Static", 60
        elseif preset == "Center" then
            yaw, jitter, jitter_mode = 0, 40, "Center"
            body_mode, body_value = "Jitter", 0
        elseif preset == "At targets" then
            yaw, jitter, jitter_mode = 10, 0, "Off"
            body_mode, body_value = "Jitter", 0
            if refs.yaw_base[1] then
                set_ref(refs.yaw_base, "At targets", 1)
            end
        end
    end

    set_yaw_mode("180", yaw)
    set_yaw_jitter(jitter_mode, jitter)
    set_body_yaw(body_mode, body_value)

    if not enabled(menu.adaptive_fake_lags) then
        set_ref(refs.fakelag_limit, tonumber(get_ref(menu.fake_yaw_limit)) or 1, 1)
    end
end

local function apply_adaptive_fakelag(lp)
    if not enabled(menu.adaptive_fake_lags) then
        return
    end
    set_ref(refs.fakelag_enabled, true, 1)
    set_ref(refs.fakelag_amount, "Maximum", 1)
    set_ref(refs.fakelag_variance, 0, 1)
    local limit = speed_2d(lp) > 5 and 14 or 1
    if enabled(refs.double_tap, 1) and enabled(refs.double_tap, 2) then
        limit = tonumber(get_ref(menu.doubletap_fakelag)) or 1
        if refs.doubletap_fakelag_limit[1] then
            set_ref(refs.doubletap_fakelag_limit, limit, 1)
        end
    end
    set_ref(refs.fakelag_limit, limit, 1)
end

local function apply_animation_breaker(lp, cmd)
    if option(menu.misc_options, "Leg movement") then
        local lm = get_ref(menu.leg_movement)
        if lm == "Never slide" or lm == "Always slide" then
            set_ref(refs.leg_movement, lm, 1)
        end
    end
    if not option(menu.misc_options, "Animation Breaker") then
        return
    end
    local selected = get_ref(menu.animation_breaker) or {}

    if contains(selected, "Always slide") then
        set_ref(refs.leg_movement, "Always slide", 1)
    end
    if contains(selected, "Never slide") then
        set_ref(refs.leg_movement, "Never slide", 1)
    end

    if contains(selected, "Leg breaker") and cmd then
        set_ref(
            refs.leg_movement,
            (cmd.command_number or globals.tickcount()) % 3 == 0 and "Always slide" or "Never slide",
            1
        )
    end
    if contains(selected, "Static ground legs") and on_ground(lp) then
        pcall(entity.set_prop, lp, "m_flPoseParameter", 1, 7)
        pcall(entity.set_prop, lp, "m_flPoseParameter", 0, 6)
    end
    if contains(selected, "Break legs while in air") and not on_ground(lp) then
        pcall(entity.set_prop, lp, "m_flPoseParameter", math.abs(math.sin(globals.realtime() * 8)), 6)
        pcall(entity.set_prop, lp, "m_flPoseParameter", math.abs(math.cos(globals.realtime() * 8)), 7)
    end
end

local function safe_anti_aim_on_use(cmd, lp)
    if not enabled(menu.anti_aim_on_use) or cmd == nil or not cmd.in_use then
        return
    end

    local weapon = entity.get_player_weapon(lp)
    local classname = weapon and entity.get_classname(weapon) or ""
    if classname == "CC4" or classname == "CPlantedC4" then
        return
    end
    if entity.get_prop(lp, "m_bIsDefusing") == 1 then
        return
    end
    if entity.get_prop(lp, "m_iPlayerState") == 4 then
        return
    end

    cmd.in_use = 0
end

local function apply_legit_aa(cmd, lp)
    if not enabled(menu.legit_aa) then
        return
    end
    set_yaw_mode("180", state.manual_name ~= "" and state.manual_side or 0)
    set_yaw_jitter("Off", 0)
    set_body_yaw("Static", 20)
    set_ref(refs.fakelag_limit, 1, 1)
    if cmd then
        cmd.roll = 0
    end
end

local function apply_slow_motion(cmd, lp)
    if not option(menu.misc_options, "Slow motion") then
        return
    end
    local slow_active = enabled(refs.slow_motion, 1) and (refs.slow_motion[2] == nil or enabled(refs.slow_motion, 2))
    if not slow_active then
        return
    end

    local mode = get_ref(menu.slowtype) or "Default"
    if mode == "Always slide" then
        set_ref(refs.leg_movement, "Always slide", 1)
    elseif mode == "Never slide" then
        set_ref(refs.leg_movement, "Never slide", 1)
    else
        if on_ground(lp) then
            set_ref(refs.leg_movement, "Never slide", 1)
        end
    end
end

local function apply_antiaim(cmd)
    if not state.authorized or not enabled(menu.enable) then
        return
    end
    local lp = local_player_alive()
    if not lp then
        return
    end
    state.local_player = lp

    apply_preset()
    update_manuals()

    local yaw = (tonumber(get_ref(menu.yaw_offset)) or 0) + state.manual_side
    if state.manual_name ~= "" then
        set_yaw_mode("180", yaw)
    end

    apply_legit_aa(cmd, lp)

    if enabled(menu.fs_body_yaw) then
        set_ref(refs.fs_body_yaw, true, 1)
    end

    local freestand_active = enabled(menu.freestand)
    local edge_active = enabled(menu.edge_yaw) and enabled(menu.edge_yaw_key)
    if freestand_active then
        set_ref(refs.freestanding, true, 1)
        if refs.freestanding[2] then
            set_ref(refs.freestanding, "Always on", 2)
        end
        set_body_yaw("Static", state.hit_side == "right" and -45 or 45)
    else
        set_ref(refs.freestanding, false, 1)
    end
    if enabled(menu.edge_yaw) then
        set_ref(refs.edge_yaw, edge_active, 1)
        if edge_active then
            set_yaw_jitter("Off", 0)
            set_body_yaw("Static", state.hit_side == "right" and -60 or 60)
        end
    end

    if enabled(menu.roll) then
        set_ref(refs.roll, tonumber(get_ref(menu.roll_value)) or 0, 1)
    else
        set_ref(refs.roll, 0, 1)
    end

    if anti_brute_active() then
        set_body_yaw("Static", state.hit_side == "right" and -60 or 60)
        set_yaw_jitter("Off", 0)
    end

    safe_anti_aim_on_use(cmd, lp)
    apply_slow_motion(cmd, lp)
    if not enabled(menu.legit_aa) then
        apply_adaptive_fakelag(lp)
    end
    apply_animation_breaker(lp, cmd)

    if cmd and state.manual_name ~= "" then
        cmd.yaw = (cmd.yaw or 0) + state.manual_side
    end

    local teleport_active = enabled(menu.teleport_key) or (enabled(menu.auto_teleport_air) and not on_ground(lp))
    if teleport_active then
        set_ref(refs.double_tap, true, 1)
        if refs.double_tap[2] then
            set_ref(refs.double_tap, "Always on", 2)
        end
        if refs.doubletap_fakelag_limit[1] then
            set_ref(refs.doubletap_fakelag_limit, tonumber(get_ref(menu.doubletap_fakelag)) or 1, 1)
        end
        set_ref(refs.fakelag_limit, 1, 1)
    elseif not enabled(menu.adaptive_fake_lags) then
        if refs.double_tap[2] then
            set_ref(refs.double_tap, "On hotkey", 2)
        end
    end
end

local function on_setup_command(cmd)
    apply_antiaim(cmd)
end

local function on_bullet_impact(e)
    if not state.authorized or not enabled(menu.anti_brute) then
        return
    end
    local lp = local_player_alive()
    if not lp then
        return
    end

    local shooter = client.userid_to_entindex(e.userid)
    if not shooter or shooter == lp or not is_enemy(shooter) then
        return
    end

    local ix, iy, iz = e.x or 0, e.y or 0, e.z or 0
    local ex, ey, ez = client.eye_position()
    local sx, sy, sz = entity.get_origin(shooter)
    sx, sy, sz = sx or ix, sy or iy, (sz or iz) + 64

    local miss_distance = distance_point_to_segment(ex or 0, ey or 0, ez or 0, sx, sy, sz, ix, iy, iz)
    state.last_bullet_time = globals.curtime()
    state.bullet_impacts[#state.bullet_impacts + 1] = {
        userid = e.userid,
        shooter = shooter,
        x = ix,
        y = iy,
        z = iz,
        distance = miss_distance,
        time = state.last_bullet_time
    }
    if #state.bullet_impacts > 12 then
        table.remove(state.bullet_impacts, 1)
    end

    if miss_distance <= 90 then
        state.hit_side = bullet_side_from_yaw(ix, iy)
        state.anti_bruteforce_until = globals.curtime() + (tonumber(get_ref(menu.anti_brute_time)) or 3)
    end
end

local function on_player_hurt(e)
    local lp = entity.get_local_player()
    local victim = client.userid_to_entindex(e.userid)
    if lp and victim == lp and enabled(menu.anti_brute) then
        state.last_hurt_time = globals.curtime()
        state.anti_bruteforce_until = globals.curtime() + (tonumber(get_ref(menu.anti_brute_time)) or 3)
    end
end

local killsays = {
    "drainyaw owns me and all",
    "discord.gg/luas",
    "drainyaw.lua > you",
    "1 tap by drainyaw.lua",
    "sadboyzZz sends his regards",
    "nice resolver bro"
}
local function on_player_death(e)
    local lp = entity.get_local_player()
    local attacker = client.userid_to_entindex(e.attacker)
    local victim = client.userid_to_entindex(e.userid)
    if lp and attacker == lp and victim ~= lp and enabled(menu.killsay) then
        state.killed_this_round = state.killed_this_round + 1
        client.exec("say " .. killsays[(state.killed_this_round - 1) % #killsays + 1])
    end
end

local function reset_round()
    state.hit_side = "left"
    state.anti_bruteforce_until = 0
    state.last_hurt_time = 0
    state.last_bullet_time = 0
    state.bullet_impacts = {}
    state.killed_this_round = 0
    state.keybind_anim = {}
end

local function on_client_disconnect()
    reset_round()
    if ENABLE_REMOTE_AUTH then
        state.authorized = false
    end
end

local function disable_drainyaw_runtime()
    state.manual_side = 0
    state.manual_name = ""
    state.hit_side = "left"
    state.anti_bruteforce_until = 0
    state.last_hurt_time = 0
    state.last_bullet_time = 0
    state.bullet_impacts = {}
    state.keybind_anim = {}
    state.manual_prev = {left = false, right = false, forward = false, reset = false}
    state.last_clantag = ""

    set_ref(refs.enabled, false, 1)
    set_ref(refs.roll, 0, 1)
    set_ref(refs.freestanding, false, 1)
    if refs.freestanding[2] then
        set_ref(refs.freestanding, "On hotkey", 2)
    end
    set_ref(refs.fs_body_yaw, false, 1)
    set_ref(refs.edge_yaw, false, 1)
    set_yaw_jitter("Off", 0)
    set_body_yaw("Off", 0)
    set_yaw_mode("Off", 0)

    set_ref(refs.fakelag_enabled, false, 1)
    set_ref(refs.fakelag_variance, 0, 1)
    set_ref(refs.fakelag_limit, 1, 1)
    set_ref(refs.double_tap, false, 1)
    if refs.double_tap[2] then
        set_ref(refs.double_tap, "On hotkey", 2)
    end
    if refs.doubletap_fakelag_limit[1] then
        set_ref(refs.doubletap_fakelag_limit, 1, 1)
    end

    set_ref(refs.leg_movement, "Off", 1)
    pcall(client.set_clan_tag, "")
end

local function on_shutdown()
    disable_drainyaw_runtime()
    set_default_aa_visible(true)
end

local function animate(name, active, speed)
    local cur = state.keybind_anim[name] or 0
    local target = active and 1 or 0
    local ft = globals.frametime and globals.frametime() or 0.015
    cur = cur + (target - cur) * clamp(ft * (speed or 10), 0, 1)
    state.keybind_anim[name] = cur
    return cur
end

notify = function(text, duration)
    state.notifications[#state.notifications + 1] = {
        text = tostring(text),
        start = globals.realtime and globals.realtime() or globals.curtime(),
        duration = duration or 4
    }
end

local function visual_style()
    return (menu and menu.visual_font and get_ref(menu.visual_font)) or "Original-like"
end

local function text_w(text, flags)
    local w = renderer.measure_text(flags or "", tostring(text))
    return w or (#tostring(text) * 6)
end

local function draw_visual_text(x, y, r, g, b, a, align, text)
    text = tostring(text)
    local style = visual_style()
    local flags = ""
    if style == "Large" then
        flags = "+"
    end
    if style == "Small" then
        flags = "-"
    end

    local tw = text_w(text, flags)
    if align == "c" then
        x = math.floor(x - tw / 2)
    elseif align == "r" then
        x = math.floor(x - tw)
    else
        x = math.floor(x)
    end
    y = math.floor(y)

    if style == "Outline" then
        renderer.text(x - 1, y, 0, 0, 0, a, flags, 0, text)
        renderer.text(x + 1, y, 0, 0, 0, a, flags, 0, text)
        renderer.text(x, y - 1, 0, 0, 0, a, flags, 0, text)
        renderer.text(x, y + 1, 0, 0, 0, a, flags, 0, text)
    elseif style == "Bold" then
        renderer.text(x + 1, y, r, g, b, a, flags, 0, text)
    elseif style == "Original-like" then
        renderer.text(x + 1, y + 1, 0, 0, 0, math.floor(a * 0.75), flags, 0, text)
        renderer.text(x + 1, y, r, g, b, a, flags, 0, text)
    end

    renderer.text(x, y, r, g, b, a, flags, 0, text)
end

local function visual_flags(align)
    local style = visual_style()
    if style == "Large" then
        return (align or "") .. "+"
    end
    if style == "Small" then
        return (align or "") .. "-"
    end
    return align or ""
end

local notification_icon_svg =
    [=[<svg id="Capa_1" enable-background="new 0 0 511.933 511.933" height="512" viewBox="0 0 511.933 511.933" width="512" xmlns="http://www.w3.org/2000/svg"><g><path d="m480.967 111.939c0-47.036-27.847-91.252-70.928-110.617-5.127-2.271-11.104-1.553-15.498 1.948s-6.46 9.155-5.361 14.663c1.187 5.962 1.787 12.205 1.787 18.006 0 20.552-6.899 41.02-19.644 56.913-34.845-20.905-75.097-32.362-115.356-32.364-40.248-.002-80.504 11.448-115.371 32.364-12.729-15.894-19.629-36.361-19.629-56.913 0-5.801.601-12.044 1.787-18.006 1.099-5.508-.967-11.162-5.361-14.663-4.409-3.516-10.356-4.248-15.498-1.948-43.082 19.365-70.928 63.581-70.928 110.617 0 26.016 8.657 51.27 24.565 72.173-16.099 31.538-24.565 66.519-24.565 101.821 0 124.072 100.928 226 225 226s225-101.928 225-226c0-35.273-8.467-70.254-24.565-101.821 15.908-20.903 24.565-46.157 24.565-72.173z" fill="#f3f5f9"/><path d="m427.295 172.232c15.264-16.787 23.672-38.203 23.672-60.293 0-25.986-11.338-51.288-30.249-68.09-1.934 29.663-14.692 58.187-36.416 79.208-5.142 4.922-13.008 5.61-18.867 1.611-32.415-22.073-70.941-33.104-109.468-33.102-38.531.002-77.064 11.039-109.482 33.102-5.859 4.014-13.74 3.311-18.867-1.611-21.724-21.021-34.468-49.545-36.401-79.208-18.911 16.802-30.249 42.104-30.249 68.09 0 22.09 8.408 43.506 23.672 60.293 4.365 4.805 5.142 11.88 1.919 17.52-16.743 29.355-25.591 62.607-25.591 96.182 0 107.52 87.48 196 195 196s195-88.48 195-196c0-33.545-8.848-66.812-25.605-96.182-3.21-5.64-2.433-12.715 1.932-17.52z" fill="#ff7f40"/><path d="m405.967 337.73c-2.769-4.248-7.485-6.797-12.554-6.797h-62.446l-15 30-15-30h-45-45l-15 30-15-30h-62.461c-5.068 0-9.785 2.549-12.554 6.797-2.769 4.233-3.223 9.58-1.187 14.224 26.353 60.132 85.708 99.979 151.201 99.979 67.581 0 125.707-41.809 151.187-99.979 2.036-4.644 1.582-9.99-1.186-14.224z" fill="#4d3535"/><path d="m215.136 215.383c-.251-.13-73.002-33.116-73.002-33.116-7.573-3.442-16.421-.029-19.834 7.5-3.413 7.544-.059 16.436 7.5 19.834l33.774 15.238c-7.767 8.09-12.607 19.019-12.607 31.095 0 24.814 20.186 45 45 45s45-20.186 45-45c0-17.934-10.619-33.324-25.831-40.551z" fill="#4d3535"/><path d="m389.634 189.766c-3.413-7.544-12.231-10.942-19.834-7.5 0 0-72.751 32.986-73.002 33.116-15.212 7.227-25.831 22.617-25.831 40.551 0 24.814 20.186 45 45 45s45-20.186 45-45c0-12.076-4.839-23.005-12.607-31.095l33.774-15.238c7.558-3.398 10.913-12.29 7.5-19.834z" fill="#331e1e"/><g><path d="m195.967 270.933c-8.276 0-15-6.724-15-15s6.724-15 15-15 15 6.724 15 15c0 8.277-6.724 15-15 15z" fill="#ffbe40"/><path d="m315.967 270.933c-8.276 0-15-6.724-15-15s6.724-15 15-15 15 6.724 15 15c0 8.277-6.724 15-15 15z" fill="#ff9f40"/></g><path d="m195.967 390.933c8.291 0 15-6.709 15-15v-45h-30v45c0 8.291 6.709 15 15 15z" fill="#f3f5f9"/><path d="m315.967 390.933c8.291 0 15-6.709 15-15v-45h-30v45c0 8.291 6.709 15 15 15z" fill="#e1e6f0"/></g></svg>]=]
local notification_icon
pcall(
    function()
        if renderer.load_svg then
            notification_icon = renderer.load_svg(notification_icon_svg, 24, 24)
        end
    end
)

local function draw_notifications()
    local now = globals.realtime and globals.realtime() or globals.curtime()
    local sx, sy = client.screen_size()
    local visible_index = 0

    for i = #state.notifications, 1, -1 do
        local n = state.notifications[i]
        local life = now - n.start
        if life > n.duration then
            table.remove(state.notifications, i)
        end
    end

    for i = #state.notifications, 1, -1 do
        local n = state.notifications[i]
        local life = now - n.start
        if life >= 0 then
            local fade_in = clamp(life / 0.20, 0, 1)
            local fade_out = clamp((n.duration - life) / 0.35, 0, 1)
            local alpha = math.floor(255 * math.min(fade_in, fade_out))
            if alpha > 2 then
                visible_index = visible_index + 1
                local text = n.text
                local tw = renderer.measure_text(visual_flags(""), text)
                tw = tw or (#text * 6)
                local w, h = tw + 58, 32
                local x = math.floor(sx / 2 - w / 2)
                local bottom_y = sy * 0.72
                local y = math.floor(bottom_y - (visible_index - 1) * 45)
                local r, g, b = 255, 80, 80

                renderer.rectangle(x, y, w, h, 24, 24, 24, math.floor(205 * alpha / 255))
                renderer.rectangle(x, y, w, 1, r, g, b, alpha)
                renderer.rectangle(x, y + h - 1, w, 1, r, g, b, math.floor(alpha * 0.35))

                local icon_drawn = false
                if notification_icon and renderer.texture then
                    icon_drawn =
                        pcall(renderer.texture, notification_icon, x + 8, y + 4, 24, 24, 255, 255, 255, alpha, "f")
                end
                if not icon_drawn then
                    renderer.circle(x + 20, y + 16, 255, 127, 64, alpha, 10, 0, 1)
                    renderer.circle(x + 16, y + 12, 255, 80, 80, alpha, 4, 0, 1)
                    renderer.circle(x + 24, y + 12, 255, 80, 80, alpha, 4, 0, 1)
                    draw_visual_text(x + 20, y + 10, 255, 255, 255, alpha, "c", "dy")
                end
                draw_visual_text(x + 40, y + 10, 255, 255, 255, alpha, "", text)
            end
        end
    end
end

local function add_indicator_row(rows, text, active, accent)
    if active then
        rows[#rows + 1] = {text = text, accent = accent}
    end
end

local function draw_center_indicators()
    if not state.authorized or not enabled(menu.enable) then
        return
    end
    if not enabled(menu.indicator) then
        return
    end

    local selected = get_ref(menu.indicator_items) or {}
    local show_all = #selected == 0
    local function want(name)
        return show_all or contains(selected, name)
    end

    local sx, sy = client.screen_size()
    local x, y = sx / 2, sy / 2 + 32
    local r, g, b, a = color(menu.main_color, {255, 127, 64, 255})
    local r2, g2, b2, a2 = color(menu.second_color, {255, 255, 255, 255})
    local rows = {}

    if want("Lua name") then
        add_indicator_row(rows, "DRAINYAW", true, true)
    end

    if want("Anti-aim state") then
        local aa_text = "+BOSSAA+"
        if enabled(menu.legit_aa) then
            aa_text = "LEGIT AA"
        end
        if enabled(menu.roll) then
            aa_text = "ROLL"
        end
        if enabled(menu.freestand) or enabled(refs.freestanding, 1) then
            aa_text = "FREESTAND"
        end
        add_indicator_row(rows, aa_text, true, true)
    end

    if want("Manual state") and state.manual_name ~= "" then
        add_indicator_row(rows, "MANUAL " .. string.upper(state.manual_name), true, true)
    end

    if want("Keybind states") then
        add_indicator_row(
            rows,
            "DT",
            enabled(refs.double_tap, 1) and (refs.double_tap[2] == nil or enabled(refs.double_tap, 2)),
            true
        )
        add_indicator_row(
            rows,
            "ONSHOT",
            enabled(refs.onshot, 1) and (refs.onshot[2] == nil or enabled(refs.onshot, 2)),
            false
        )
        add_indicator_row(
            rows,
            "SLOW",
            enabled(refs.slow_motion, 1) and (refs.slow_motion[2] == nil or enabled(refs.slow_motion, 2)),
            false
        )
        add_indicator_row(
            rows,
            "BAIM",
            enabled(refs.force_baim, 1) and (refs.force_baim[2] == nil or enabled(refs.force_baim, 2)),
            false
        )
        add_indicator_row(
            rows,
            "SAFE",
            enabled(refs.force_safepoint, 1) and (refs.force_safepoint[2] == nil or enabled(refs.force_safepoint, 2)),
            false
        )
        add_indicator_row(rows, "QP", enabled(refs.quick_peek, 1), false)
        add_indicator_row(rows, "DUCK", enabled(refs.duck_peek, 1), false)
        add_indicator_row(rows, "FL", enabled(menu.adaptive_fake_lags), false)
    end

    if want("Anti-bruteforce") then
        add_indicator_row(rows, "ANTI-BRUTE", anti_brute_active(), true)
    end

    if want("Crouch state") then
        local lp = entity.get_local_player()
        local duck = lp and ((entity.get_prop(lp, "m_flDuckAmount") or 0) > 0.6)
        add_indicator_row(rows, "CROUCH", duck, false)
    end

    if #rows == 0 then
        return
    end

    for i = 1, #rows do
        local row = rows[i]
        local rr, gg, bb = row.accent and r or 255, row.accent and g or 255, row.accent and b or 255
        draw_visual_text(x, y, rr, gg, bb, a, "c", row.text)
        y = y + 13
    end

    if option(menu.visual_options, "Anti-Aim Gradient") then
        renderer.gradient(x - 45, y + 1, 45, 2, r, g, b, a, r2, g2, b2, a2, true)
        renderer.gradient(x, y + 1, 45, 2, r2, g2, b2, a2, r, g, b, a, true)
    end
end

local function draw_manual_arrows()
    if not option(menu.visual_options, "Manual Arrows") and not option(menu.visual_options, "Circles Arrows") then
        return
    end
    local sx, sy = client.screen_size()
    local x, y = sx / 2, sy / 2
    local r, g, b = color(menu.main_color, {255, 127, 64, 255})
    if option(menu.visual_options, "Circles Arrows") then
        renderer.circle(x - 56, y, r, g, b, state.manual_side == -90 and 220 or 60, 6, 0, 1)
        renderer.circle(x + 56, y, r, g, b, state.manual_side == 90 and 220 or 60, 6, 0, 1)
    end
    if option(menu.visual_options, "Manual Arrows") then
        draw_visual_text(x - 56, y - 4, r, g, b, state.manual_side == -90 and 255 or 80, "c", "<")
        draw_visual_text(x + 56, y - 4, r, g, b, state.manual_side == 90 and 255 or 80, "c", ">")
    end
end

local function draw_keybinds()
    if not state.authorized or not enabled(menu.enable) then
        return
    end
    if not option(menu.visual_options, "Keybinds") and not option(menu.visual_options, "Keybinds Always Show") then
        return
    end
    local selected = get_ref(menu.keybinds) or {}
    local always = option(menu.visual_options, "Keybinds Always Show")
    local binds = {
        {"Double tap", enabled(refs.double_tap, 1) and (refs.double_tap[2] == nil or enabled(refs.double_tap, 2))},
        {"On shot anti-aim", enabled(refs.onshot, 1) and (refs.onshot[2] == nil or enabled(refs.onshot, 2))},
        {"Slow motion", enabled(refs.slow_motion, 1) and (refs.slow_motion[2] == nil or enabled(refs.slow_motion, 2))},
        {"Force Body aim", enabled(refs.force_baim, 1) and (refs.force_baim[2] == nil or enabled(refs.force_baim, 2))},
        {
            "Force Safe point",
            enabled(refs.force_safepoint, 1) and (refs.force_safepoint[2] == nil or enabled(refs.force_safepoint, 2))
        },
        {"Quick peek assist", enabled(refs.quick_peek, 1)},
        {"Duck peek assist", enabled(refs.duck_peek, 1)},
        {"Freestanding", enabled(menu.freestand) or enabled(refs.freestanding, 1)},
        {"Anti-bruteforce", anti_brute_active()},
        {"Adaptive Fake Lags", enabled(menu.adaptive_fake_lags)},
        {"Roll Anti-aims", enabled(menu.roll)}
    }

    local rows = {}
    for i = 1, #binds do
        local name, active = binds[i][1], binds[i][2]
        local selected_allowed = #selected == 0 or contains(selected, name)
        local should_show = always and selected_allowed or (active and selected_allowed)
        local alpha = animate("kb_" .. name, should_show, 10)
        if alpha > 0.02 then
            rows[#rows + 1] = {name = name, alpha = alpha, active = active}
        end
    end
    if #rows == 0 then
        return
    end

    local x = tonumber(get_ref(menu.keybind_x)) or 20
    local y = tonumber(get_ref(menu.keybind_y)) or 350
    local w = 150
    for i = 1, #rows do
        local tw = text_w(rows[i].name, visual_flags(""))
        if tw + 72 > w then
            w = tw + 72
        end
    end
    w = clamp(w, 155, 285)
    local header_h, row_h = 20, 16
    local h = header_h + 5 + #rows * row_h
    local r, g, b = color(menu.ind_color, {255, 127, 64, 255})

    renderer.rectangle(x, y, w, h, 12, 12, 12, 155)
    renderer.rectangle(x, y, w, 1, r, g, b, 240)
    renderer.rectangle(x, y + header_h, w, 1, 0, 0, 0, 90)
    renderer.gradient(x, y + 1, w / 2, 2, r, g, b, 170, r, g, b, 0, true)
    renderer.gradient(x + w / 2, y + 1, w / 2, 2, r, g, b, 0, r, g, b, 170, true)
    draw_visual_text(x + w / 2, y + 5, 255, 255, 255, 255, "c", "Keybinds")

    for i = 1, #rows do
        local a = math.floor(255 * rows[i].alpha)
        local row_y = y + header_h + 5 + (i - 1) * row_h
        local slide = math.floor((1 - rows[i].alpha) * 8)
        local status = rows[i].active and "on" or "off"
        local sr, sg, sb = rows[i].active and r or 160, rows[i].active and g or 160, rows[i].active and b or 160
        draw_visual_text(x + 8 - slide, row_y, 255, 255, 255, a, "", rows[i].name)
        draw_visual_text(x + w - 8 + slide, row_y, sr, sg, sb, a, "r", status)
    end
end

local clantag_frames = {
    "d",
    "dr",
    "dra",
    "drai",
    "drain",
    "drainy",
    "drainya",
    "drainyaw",
    "drainyaw.",
    "drainyaw.l",
    "drainyaw.lu",
    "drainyaw.lua",
    "drainyaw.lua",
    "drainyaw.lu",
    "drainyaw.l",
    "drainyaw.",
    "drainyaw"
}
local function update_clantag()
    if not enabled(menu.clantag) then
        if state.last_clantag ~= "" then
            pcall(client.set_clan_tag, "")
            state.last_clantag = ""
        end
        return
    end
    if refs.clan_tag_spammer[1] then
        set_ref(refs.clan_tag_spammer, false, 1)
    end
    local idx = math.floor((globals.curtime() or 0) * 2.4) % #clantag_frames + 1
    local tag = clantag_frames[idx]
    if tag ~= state.last_clantag then
        pcall(client.set_clan_tag, tag)
        state.last_clantag = tag
    end
end

local function on_paint()
    if not enabled(menu.enable) then
        update_clantag()
        return
    end
    update_manuals()
    draw_center_indicators()
    draw_manual_arrows()
    draw_keybinds()
    update_clantag()
end

local function on_paint_ui()
    if enabled(menu.enable) then
        set_default_aa_visible(false)
    end
    draw_notifications()
end

client.set_event_callback("setup_command", on_setup_command)
client.set_event_callback("bullet_impact", on_bullet_impact)
client.set_event_callback("player_hurt", on_player_hurt)
client.set_event_callback("player_death", on_player_death)
client.set_event_callback("round_start", reset_round)
client.set_event_callback("round_prestart", reset_round)
client.set_event_callback("client_disconnect", on_client_disconnect)
client.set_event_callback("paint", on_paint)
client.set_event_callback("paint_ui", on_paint_ui)
client.set_event_callback("shutdown", on_shutdown)

local function refresh_visibility_delayed()
    update_visibility()
    pcall(client.delay_call, 0.05, update_visibility)
    pcall(client.delay_call, 0.20, update_visibility)
end

local function on_enable_changed()
    if not enabled(menu.enable) then
        disable_drainyaw_runtime()
        set_default_aa_visible(true)
    end
    refresh_visibility_delayed()
end

set_callback(menu.enable, on_enable_changed)
set_callback(menu.aa_options, refresh_visibility_delayed)
set_callback(menu.misc_options, refresh_visibility_delayed)
set_callback(menu.visual_options, refresh_visibility_delayed)
set_callback(menu.manual_enable, refresh_visibility_delayed)
set_callback(menu.anti_brute, refresh_visibility_delayed)
set_callback(menu.roll, refresh_visibility_delayed)
set_callback(menu.edge_yaw, refresh_visibility_delayed)
set_callback(menu.indicator, refresh_visibility_delayed)
set_callback(menu.visual_font, refresh_visibility_delayed)
set_callback(menu.adaptive_fake_lags, refresh_visibility_delayed)
set_callback(menu.teleport_key, refresh_visibility_delayed)
set_callback(menu.auto_teleport_air, refresh_visibility_delayed)
set_callback(menu.clantag, refresh_visibility_delayed)
set_callback(menu.killsay, refresh_visibility_delayed)

refresh_visibility_delayed()
authorize()

return {
    refs = refs,
    menu = menu,
    state = state,
    authorize = authorize,
    update_visibility = update_visibility,
    apply_antiaim = apply_antiaim
}
