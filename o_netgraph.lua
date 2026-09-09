local success, surface = pcall(require, "gamesense/surface")
if not success then
    error("Surface library required")
end
local ffi = require("ffi")
local ffi_cast = ffi.cast

-- FFI / NetChannel access
local interface_ptr = ffi.typeof("void***")
local netc_bool = ffi.typeof("bool(__thiscall*)(void*)")
local netc_float = ffi.typeof("float(__thiscall*)(void*, int)")
local netc_int = ffi.typeof("int(__thiscall*)(void*, int)")
local net_fr_to = ffi.typeof("void(__thiscall*)(void*, float*, float*, float*)")
local pflFrameTime = ffi.new("float[1]")
local pflFrameTimeStdDev = ffi.new("float[1]")
local pflFrameStartStdDev = ffi.new("float[1]")
local rawiv = client.create_interface("engine.dll", "VEngineClient014") or error("VEngineClient014")
local iv = ffi_cast(interface_ptr, rawiv)
local get_net_channel_info = ffi_cast("void*(__thiscall*)(void*)", iv[0][78])
local is_in_game = ffi_cast("bool(__thiscall*)(void*)", iv[0][26])
local cl_interp_ratio = cvar.cl_interp_ratio
local cl_updaterate = cvar.cl_updaterate
local ping_spike_ref = {ui.reference("MISC", "Miscellaneous", "Ping spike")}
local function get_netchan()
    local p = get_net_channel_info(iv)
    if p == nil then
        return nil
    end
    local nc = ffi_cast("void***", p)
    local seq = ffi_cast(netc_int, nc[0][17])(nc, 1)
    return {
        seqNr_out = seq,
        is_loopback = ffi_cast(netc_bool, nc[0][6])(nc),
        is_timing_out = ffi_cast(netc_bool, nc[0][7])(nc),
        crn_out = ffi_cast(netc_float, nc[0][9])(nc, 0),
        crn_in = ffi_cast(netc_float, nc[0][9])(nc, 1),
        avg_latency = ffi_cast(netc_float, nc[0][10])(nc, 0),
        loss = ffi_cast(netc_float, nc[0][11])(nc, 1),
        choke = ffi_cast(netc_float, nc[0][12])(nc, 1),
        got_bytes = ffi_cast(netc_float, nc[0][13])(nc, 1),
        sent_bytes = ffi_cast(netc_float, nc[0][13])(nc, 0),
        _ptr = nc
    }
end

local function get_server_fps(nc)
    if not nc then
        return 0, 0
    end
    ffi_cast(net_fr_to, nc._ptr[0][25])(nc._ptr, pflFrameTime, pflFrameTimeStdDev, pflFrameStartStdDev)
    if pflFrameTime[0] > 0 then
        return pflFrameTime[0] * 1000, pflFrameStartStdDev[0] * 1000
    end
    return 0, 0
end

-- UI
local TAB, GROUP = "MISC", "Miscellaneous"

local ui_enable = ui.new_checkbox(TAB, GROUP, "Custom Netgraph")
local ui_theme = ui.new_combobox(TAB, GROUP, "Netgraph Theme", "Modern", "Classic", "Skeet")
local ui_metrics =
    ui.new_multiselect(
    TAB,
    GROUP,
    "Netgraph Metrics",
    "FPS",
    "Ping",
    "Lerp",
    "Variance",
    "Loss/Choke",
    "Traffic",
    "Tickrate",
    "Server FPS",
    "Choked Cmds",
    "Ping Graph"
)
local ui_position =
    ui.new_combobox(
    TAB,
    GROUP,
    "Netgraph Position",
    "Bottom Center",
    "Bottom Left",
    "Bottom Right",
    "Top Center",
    "Top Left",
    "Top Right",
    "Custom"
)
local ui_off_x = ui.new_slider(TAB, GROUP, "Netgraph Custom X", 0, 3840, 100, true, "px")
local ui_off_y = ui.new_slider(TAB, GROUP, "Netgraph Custom Y", 0, 2160, 100, true, "px")
local ui_layout = ui.new_combobox(TAB, GROUP, "Netgraph Layout", "Vertical", "Horizontal", "Compact")
local ui_font_size = ui.new_slider(TAB, GROUP, "Netgraph Font Size", 9, 18, 12, true, "px")
local ui_text_col = ui.new_color_picker(TAB, GROUP, "Netgraph Text Color", 255, 255, 255, 255)
local ui_accent = ui.new_color_picker(TAB, GROUP, "Netgraph Accent Color", 130, 200, 255, 255)
local ui_bg_col = ui.new_color_picker(TAB, GROUP, "Netgraph BG Color", 10, 10, 14, 180)
local ui_smooth = ui.new_slider(TAB, GROUP, "Netgraph Smoothing", 0, 100, 35, true, "%")
local ui_pulse = ui.new_checkbox(TAB, GROUP, "Netgraph Pulse on Spike")
local ui_icons = ui.new_checkbox(TAB, GROUP, "Netgraph Icons")
local ui_graph_w = ui.new_slider(TAB, GROUP, "Ping Graph Width", 60, 300, 140, true, "px")
local ui_graph_h = ui.new_slider(TAB, GROUP, "Ping Graph Height", 16, 80, 32, true, "px")
local function has_metric(name)
    local sel = ui.get(ui_metrics)
    if type(sel) ~= "table" then
        return false
    end
    for i = 1, #sel do
        if sel[i] == name then
            return true
        end
    end
    return false
end

-- Fonts cache
local font_cache = {}
local function get_font(size, bold)
    local key = size .. (bold and "b" or "")
    if not font_cache[key] then
        font_cache[key] = surface.create_font("Segoe UI", size, bold and 600 or 400, {0x010 --[[ AA ]]})
    end
    return font_cache[key]
end

-- State (smoothing, history)
local state = {
    fps = 0,
    ping = 0,
    var = 0,
    lerp = 0,
    srv_fps = 0,
    in_kbs = 0,
    out_kbs = 0,
    loss = 0,
    choke = 0
}
local ping_history = {}
local PING_HISTORY_MAX = 120
local last_history_t = 0
local choked_now = 0
client.set_event_callback(
    "setup_command",
    function(e)
        if e.chokedcommands ~= nil then
            choked_now = e.chokedcommands
        end
    end
)

local function lerp(a, b, t)
    return a + (b - a) * t
end

-- Drawing helpers
local function draw_bg(x, y, w, h)
    local r, g, b, a = ui.get(ui_bg_col)
    if a <= 0 then
        return
    end -- alpha=0 acts as "background off"
    local ar, ag, ab, aa = ui.get(ui_accent)

    -- Use surface.draw_filled_rect so the background sits on the same layer as
    -- surface.draw_text (renderer.* draws on a layer ABOVE surface.*, which
    -- would cover the metric text).
    local fill = surface.draw_filled_rect
    if not fill then
        for i = 1, 3 do
            local k = math.floor(a * (0.06 + i * 0.04))
            renderer.rectangle(x - 2 - i, y - 2 - i, w + 4 + i * 2, h + 4 + i * 2, 0, 0, 0, k)
        end
        renderer.rectangle(x - 2, y - 2, w + 4, h + 4, r, g, b, a)
        renderer.rectangle(
            x - 2,
            y - 2,
            w + 4,
            1,
            math.min(255, r + 25),
            math.min(255, g + 25),
            math.min(255, b + 25),
            math.floor(a * 0.6)
        )
        renderer.rectangle(x - 2, y - 2, 2, h + 4, ar, ag, ab, aa)
        return
    end

    -- Soft outer shadow (3 layered low-alpha rects)
    for i = 1, 3 do
        local k = math.floor(a * (0.06 + i * 0.04))
        fill(x - 2 - i, y - 2 - i, w + 4 + i * 2, h + 4 + i * 2, 0, 0, 0, k)
    end

    -- Main panel
    fill(x - 2, y - 2, w + 4, h + 4, r, g, b, a)

    -- Subtle top highlight
    fill(
        x - 2,
        y - 2,
        w + 4,
        1,
        math.min(255, r + 25),
        math.min(255, g + 25),
        math.min(255, b + 25),
        math.floor(a * 0.6)
    )

    -- Left accent bar
    fill(x - 2, y - 2, 2, h + 4, ar, ag, ab, aa)
end

local function get_anchor(layout_w, layout_h)
    local sw, sh = client.screen_size()
    local pos = ui.get(ui_position)
    if pos == "Bottom Center" then
        return math.floor(sw / 2 - layout_w / 2), sh - layout_h - 60
    elseif pos == "Bottom Left" then
        return 30, sh - layout_h - 60
    elseif pos == "Bottom Right" then
        return sw - layout_w - 30, sh - layout_h - 60
    elseif pos == "Top Center" then
        return math.floor(sw / 2 - layout_w / 2), 30
    elseif pos == "Top Left" then
        return 30, 30
    elseif pos == "Top Right" then
        return sw - layout_w - 30, 30
    else
        return ui.get(ui_off_x), ui.get(ui_off_y)
    end
end

-- Real SVG icons per metric. Rendered once to a texture per (name,size) and
-- tinted with the metric color via renderer.texture.
-- NOTE: NanoSVG (used by gamesense) requires explicit width/height on the
-- root <svg> element, otherwise the rasterizer produces an empty texture.
local function svg_wrap(inner)
    return '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">' .. inner .. "</svg>"
end

-- All icons use solid fill (no stroke) so they tint to full brightness.
local icon_svgs = {
    -- FPS: monitor screen with play triangle (frames-per-second)
    FPS = svg_wrap(
        -- monitor body
        '<path d="M2 4 L22 4 L22 17 L2 17 Z" fill="white"/>' .. -- screen cutout
            '<path d="M4 6 L20 6 L20 15 L4 15 Z" fill="black"/>' .. -- play triangle on screen
                '<path d="M10 8.5 L15 10.5 L10 12.5 Z" fill="white"/>' .. -- stand
                    '<path d="M9 20 L15 20 L14 22 L10 22 Z" fill="white"/>'
    ),
    -- Ping: signal bars
    Ping = svg_wrap(
        '<rect x="3"  y="15" width="3" height="6"  fill="white"/>' ..
            '<rect x="8"  y="11" width="3" height="10" fill="white"/>' ..
                '<rect x="13" y="7"  width="3" height="14" fill="white"/>' ..
                    '<rect x="18" y="3"  width="3" height="18" fill="white"/>'
    ),
    -- Lerp: filled clock (outer disc + punched-out inner + hands as filled rects)
    Lerp = svg_wrap(
        '<circle cx="12" cy="12" r="10" fill="white"/>' ..
            '<circle cx="12" cy="12" r="8"  fill="black"/>' ..
                '<rect x="11.2" y="6"  width="1.6" height="6.5" fill="white"/>' ..
                    '<rect x="11.2" y="11.2" width="5"   height="1.6" fill="white"/>'
    ),
    -- Variance: zigzag as a filled polygon
    Variance = svg_wrap(
        '<path d="M1 17 L5 9 L9 17 L13 9 L17 17 L21 9 L23 9 L23 11 L21 11 L17 19 L13 11 L9 19 L5 11 L1 11 Z" fill="white"/>'
    ),
    -- Loss/Choke: solid warning triangle with black !
    Loss = svg_wrap(
        '<path d="M12 2 L23 22 L1 22 Z" fill="white"/>' ..
            '<rect x="11" y="9"  width="2" height="7" fill="black"/>' ..
                '<rect x="11" y="17.5" width="2" height="2" fill="black"/>'
    ),
    -- Traffic: filled up/down arrows
    Traffic = svg_wrap(
        -- up arrow (left)
        '<path d="M7 2 L2 8 L5 8 L5 22 L9 22 L9 8 L12 8 Z" fill="white"/>' .. -- down arrow (right)
            '<path d="M17 22 L22 16 L19 16 L19 2 L15 2 L15 16 L12 16 Z" fill="white"/>'
    ),
    -- Tick: filled pulse silhouette
    Tick = svg_wrap(
        '<path d="M1 11 L7 11 L9 4 L11 4 L13 20 L15 11 L23 11 L23 13 L16 13 L13 22 L11 22 L9 8 L8 13 L1 13 Z" fill="white"/>'
    ),
    -- Server FPS: two stacked filled bars with LED dots punched out
    SrvFPS = svg_wrap(
        '<rect x="2" y="4"  width="20" height="7" fill="white"/>' ..
            '<rect x="2" y="13" width="20" height="7" fill="white"/>' ..
                '<circle cx="6" cy="7.5"  r="1" fill="black"/>' .. '<circle cx="6" cy="16.5" r="1" fill="black"/>'
    ),
    -- Choked Cmds: three stacked bars
    Cmd = svg_wrap(
        '<rect x="2" y="4"  width="20" height="4" fill="white"/>' ..
            '<rect x="2" y="10" width="20" height="4" fill="white"/>' ..
                '<rect x="2" y="16" width="20" height="4" fill="white"/>'
    )
}

local icon_tex_cache = {}
local icon_svg_warned = false
local function get_icon_tex(name, size)
    local svg = icon_svgs[name]
    if not svg then
        return nil
    end
    local key = name .. "_" .. size
    local cached = icon_tex_cache[key]
    if cached ~= nil then
        return cached or nil
    end
    local ok, tex = pcall(renderer.load_svg, svg, size, size)
    if not ok or not tex then
        icon_tex_cache[key] = false
        if not icon_svg_warned then
            client.color_log(255, 120, 120, "[netgraph] renderer.load_svg failed for " .. name .. ": " .. tostring(tex))
            icon_svg_warned = true
        end
        return nil
    end
    icon_tex_cache[key] = tex
    return tex
end

-- kept for backwards compat with build_metrics; references above table keys
local icon_map = {
    FPS = "FPS",
    Ping = "Ping",
    Lerp = "Lerp",
    Variance = "Variance",
    Loss = "Loss",
    Traffic = "Traffic",
    Tick = "Tick",
    SrvFPS = "SrvFPS",
    Cmd = "Cmd"
}

-- Build metric list (label, value_text, color_rgb)
local function ping_color(p)
    if p < 40 then
        return 120, 230, 140
    end
    if p < 80 then
        return 200, 230, 120
    end
    if p < 130 then
        return 255, 200, 90
    end
    return 255, 90, 90
end

local function build_metrics(nc, srv_fps, srv_var)
    local list = {}
    local tr, tg, tb = ui.get(ui_text_col)
    local ar, ag, ab = ui.get(ui_accent)

    if has_metric("FPS") then
        local r, g, b = tr, tg, tb
        if state.fps < 60 then
            r, g, b = 255, 100, 100
        elseif state.fps < 144 then
            r, g, b = 255, 220, 120
        end
        list[#list + 1] = {
            icon = icon_map.FPS,
            label = "fps",
            value = string.format("%d", state.fps),
            r = r,
            g = g,
            b = b
        }
    end

    if has_metric("Ping") then
        local r, g, b = ping_color(state.ping)
        list[#list + 1] = {
            icon = icon_map.Ping,
            label = "ping",
            value = string.format("%dms", state.ping),
            r = r,
            g = g,
            b = b
        }
    end

    if has_metric("Variance") then
        list[#list + 1] = {
            icon = icon_map.Variance,
            label = "var",
            value = string.format("%.1fms", state.var),
            r = tr,
            g = tg,
            b = tb
        }
    end

    if has_metric("Lerp") then
        local tickrate = 1 / globals.tickinterval()
        local lerp_ms = cl_interp_ratio:get_float() * (1000 / tickrate)
        state.lerp = lerp(state.lerp, lerp_ms, 0.2)
        local r, g, b = tr, tg, tb
        if state.lerp / 1000 < 2 / cl_updaterate:get_int() then
            r, g, b = 255, 150, 100
        end
        list[#list + 1] = {
            icon = icon_map.Lerp,
            label = "lerp",
            value = string.format("%.1fms", state.lerp),
            r = r,
            g = g,
            b = b
        }
    end

    if has_metric("Loss/Choke") then
        local loss = state.loss * 100
        local choke = state.choke * 100
        local r, g, b = tr, tg, tb
        if loss > 0 or choke > 0 then
            r, g, b = 255, 100, 100
        end
        list[#list + 1] = {
            icon = icon_map.Loss,
            label = "loss/choke",
            value = string.format("%.1f%% / %.1f%%", loss, choke),
            r = r,
            g = g,
            b = b
        }
    end

    if has_metric("Traffic") then
        list[#list + 1] = {
            icon = icon_map.Traffic,
            label = "net",
            value = string.format("%.1f \xE2\x86\x93 / %.1f \xE2\x86\x91 k/s", state.in_kbs, state.out_kbs),
            r = tr,
            g = tg,
            b = tb
        }
    end

    if has_metric("Tickrate") then
        local tr_val = math.floor(1 / globals.tickinterval() + 0.5)
        list[#list + 1] = {
            icon = icon_map.Tick,
            label = "tick",
            value = string.format("%d", tr_val),
            r = ar,
            g = ag,
            b = ab
        }
    end

    if has_metric("Server FPS") then
        list[#list + 1] = {
            icon = icon_map.SrvFPS,
            label = "srv",
            value = string.format("%.1fms", state.srv_fps),
            r = tr,
            g = tg,
            b = tb
        }
    end

    if has_metric("Choked Cmds") then
        local r, g, b = tr, tg, tb
        if choked_now > 8 then
            r, g, b = 255, 200, 90
        end
        list[#list + 1] = {
            icon = icon_map.Cmd,
            label = "choke",
            value = string.format("%d", choked_now),
            r = r,
            g = g,
            b = b
        }
    end

    return list
end

-- Layout & render
local PADDING_X = 12
local PADDING_Y = 8
local LINE_PAD = 5
local COL_PAD = 22

local function render_ping_graph(x, y, w, h)
    if #ping_history < 2 then
        return
    end
    local r, g, b, a = ui.get(ui_accent)

    -- BG (surface layer so it stays below labels drawn via surface.draw_text)
    local fill = surface.draw_filled_rect
    if fill then
        fill(x, y, w, h, 0, 0, 0, 100)
        fill(x, y, w, 1, r, g, b, math.floor(a * 0.6))
        fill(x, y + h - 1, w, 1, r, g, b, math.floor(a * 0.6))
    else
        renderer.rectangle(x, y, w, h, 0, 0, 0, 100)
        renderer.rectangle(x, y, w, 1, r, g, b, math.floor(a * 0.6))
        renderer.rectangle(x, y + h - 1, w, 1, r, g, b, math.floor(a * 0.6))
    end

    local mn, mx = math.huge, 0
    for i = 1, #ping_history do
        if ping_history[i] < mn then
            mn = ping_history[i]
        end
        if ping_history[i] > mx then
            mx = ping_history[i]
        end
    end
    if mx - mn < 5 then
        mx = mn + 5
    end

    local n = #ping_history
    local step = w / (PING_HISTORY_MAX - 1)
    local prev_x, prev_y
    for i = 1, n do
        local px = x + (i - 1) * step
        local norm = (ping_history[i] - mn) / (mx - mn)
        local py = y + h - 2 - math.floor(norm * (h - 4))
        if prev_x then
            renderer.line(prev_x, prev_y, px, py, r, g, b, a)
        end
        prev_x, prev_y = px, py
    end

    local font = get_font(math.max(9, ui.get(ui_font_size) - 2))
    surface.draw_text(x + 4, y + 2, 180, 180, 190, 200, font, string.format("%dms", math.floor(mx)))
    surface.draw_text(x + 4, y + h - 12, 180, 180, 190, 200, font, string.format("%dms", math.floor(mn)))
end

local function on_paint()
    if not ui.get(ui_enable) then
        return
    end
    if ui.get(ui_theme) ~= "Modern" then
        return
    end
    if not is_in_game(iv) then
        return
    end
    local me = entity.get_local_player()
    if not me then
        return
    end
    local nc = get_netchan()
    if not nc then
        return
    end

    -- Update state with smoothing
    local smooth = 1.0 - (ui.get(ui_smooth) / 100.0) * 0.95
    local sfps, svar = get_server_fps(nc)
    state.fps = lerp(state.fps, 1 / globals.frametime(), smooth)
    state.ping = lerp(state.ping, nc.avg_latency * 1000, smooth)
    state.var = lerp(state.var, svar / 2, smooth)
    state.srv_fps = lerp(state.srv_fps, sfps, smooth)
    state.in_kbs = lerp(state.in_kbs, nc.got_bytes / 1024, smooth)
    state.out_kbs = lerp(state.out_kbs, nc.sent_bytes / 1024, smooth)
    state.loss = lerp(state.loss, nc.loss, smooth)
    state.choke = lerp(state.choke, nc.choke, smooth)

    -- Ping history (sampled ~10x/sec)
    local now = globals.realtime()
    if now - last_history_t > 0.1 then
        last_history_t = now
        ping_history[#ping_history + 1] = state.ping
        while #ping_history > PING_HISTORY_MAX do
            table.remove(ping_history, 1)
        end
    end

    local font_size = ui.get(ui_font_size)
    local font = get_font(font_size)
    local layout = ui.get(ui_layout)
    local show_icons = ui.get(ui_icons)
    local show_graph = has_metric("Ping Graph")
    local metrics = build_metrics(nc)
    local pulse_mult = 1.0
    if ui.get(ui_pulse) and (state.loss > 0.001 or state.choke > 0.001 or state.ping > 130) then
        pulse_mult = 0.6 + 0.4 * math.abs(math.sin(now * 6))
    end

    -- Calculate bounds
    local line_h = font_size + LINE_PAD
    local font_b_meas = get_font(font_size, true)
    local total_w, total_h = 0, 0
    local widths = {}
    for i = 1, #metrics do
        local m = metrics[i]
        local lw = surface.get_text_size(font, m.label)
        local vw = surface.get_text_size(font_b_meas, m.value)
        local iw = show_icons and (math.max(10, font_size + 2) + 6) or 0
        widths[i] = iw + lw + 6 + vw
    end

    if layout == "Vertical" then
        for i = 1, #metrics do
            if widths[i] > total_w then
                total_w = widths[i]
            end
        end
        total_h = #metrics * line_h
    elseif layout == "Horizontal" then
        for i = 1, #metrics do
            total_w = total_w + widths[i] + COL_PAD
        end
        total_w = total_w - COL_PAD
        total_h = line_h
    else
        local cols = 2
        local rows = math.ceil(#metrics / cols)
        local col_w = 0
        for i = 1, #widths do
            if widths[i] > col_w then
                col_w = widths[i]
            end
        end
        total_w = col_w * cols + COL_PAD
        total_h = rows * line_h
    end

    if show_graph then
        local gw, gh = ui.get(ui_graph_w), ui.get(ui_graph_h)
        if layout == "Horizontal" then
            total_w = total_w + COL_PAD + gw
            if gh > total_h then
                total_h = gh
            end
        else
            if gw > total_w then
                total_w = gw
            end
            total_h = total_h + gh + LINE_PAD
        end
    end

    local x, y = get_anchor(total_w + PADDING_X * 2, total_h + PADDING_Y * 2)

    draw_bg(x, y, total_w + PADDING_X * 2, total_h + PADDING_Y * 2)

    local cx, cy = x + PADDING_X, y + PADDING_Y

    local font_b = get_font(font_size, true)
    local label_alpha = math.floor(160 * pulse_mult)
    local val_alpha = math.floor(255 * pulse_mult)

    local icon_size = math.max(10, font_size + 2)
    local ic_r, ic_g, ic_b, ic_a = ui.get(ui_accent)
    local function draw_metric(mx, my, m)
        local px = mx
        if show_icons then
            local tex = get_icon_tex(m.icon, icon_size)
            local a = math.floor(ic_a * pulse_mult)
            if tex then
                local iy = my + math.floor((font_size - icon_size) / 2)
                renderer.texture(tex, px, iy, icon_size, icon_size, ic_r, ic_g, ic_b, a)
                px = px + icon_size + 6
            else
                local dot_r = math.max(2, math.floor(font_size / 4))
                renderer.circle(px + dot_r, my + math.floor(font_size / 2) + 1, ic_r, ic_g, ic_b, a, dot_r, 0, 1)
                px = px + dot_r * 2 + 6
            end
        end
        local label = m.label
        local val = m.value
        local tr, tg, tb = ui.get(ui_text_col)
        -- Per-label vertical offset:
        local mid = {
            ["srv"] = true,
            ["net"] = true,
            ["choke"] = true,
            ["tick"] = true,
            ["loss/choke"] = true,
            ["var"] = true,
            ["lerp"] = true
        }
        local ty = mid[label] and my or (my - 1)
        surface.draw_text(px, ty, tr, tg, tb, label_alpha, font, label)
        local lw = surface.get_text_size(font, label)
        surface.draw_text(px + lw + 6, ty, m.r, m.g, m.b, val_alpha, font_b, val)
    end

    local metric_widths = {}
    for i = 1, #metrics do
        local m = metrics[i]
        local lw = surface.get_text_size(font, m.label)
        local vw = surface.get_text_size(font_b, m.value)
        local iw = show_icons and (math.max(10, font_size + 2) + 6) or 0
        metric_widths[i] = iw + lw + 6 + vw
    end

    if layout == "Vertical" then
        for i = 1, #metrics do
            draw_metric(cx, cy, metrics[i])
            cy = cy + line_h
        end
    elseif layout == "Horizontal" then
        local hx = cx
        for i = 1, #metrics do
            draw_metric(hx, cy, metrics[i])
            hx = hx + metric_widths[i] + COL_PAD
            -- thin separator dot
            if i < #metrics then
                surface.draw_text(hx - COL_PAD / 2 - 2, cy - 1, 120, 120, 130, label_alpha, font, "\xC2\xB7")
            end
        end
        cy = cy + line_h
    else
        local col_w = (total_w - COL_PAD) / 2
        for i = 1, #metrics do
            local col = (i - 1) % 2
            local row = math.floor((i - 1) / 2)
            draw_metric(cx + col * (col_w + COL_PAD), cy + row * line_h, metrics[i])
        end
        cy = cy + math.ceil(#metrics / 2) * line_h
    end

    if show_graph then
        local gw, gh = ui.get(ui_graph_w), ui.get(ui_graph_h)
        if layout == "Horizontal" then
            render_ping_graph(x + PADDING_X + total_w - gw, y + PADDING_Y, gw, gh)
        else
            render_ping_graph(cx, cy, gw, gh)
        end
    end
end

client.set_event_callback("paint", on_paint)

-- Skeet / gamesense classic theme
local skeet_font_cache = {}
local function skeet_draw(x, y, r, g, b, a, font, text)
    if not text then
        return
    end
    local sa = math.floor((a or 255) * 0.7)
    surface.draw_text(x + 1, y + 1, 0, 0, 0, sa, font, text)
    surface.draw_text(x, y, r, g, b, a, font, text)
end

local function get_skeet_font(size)
    if not skeet_font_cache[size] then
        local ok, f = pcall(surface.create_font, "Tahoma", size, 400, {0x200})
        if not ok or not f then
            ok, f = pcall(surface.create_font, "Verdana", size, 400, {0x200})
        end
        if not ok or not f then
            f = surface.create_font("Verdana", size, 400, {})
        end
        skeet_font_cache[size] = f
    end
    return skeet_font_cache[size]
end
local skeet_warn_icon =
    renderer.load_rgba(
    "\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x02\xFF\xFF\xFF\x00\xFF\xFF\xFF\x6B\xFF\xFF\xFF\xFC\xFF\xFF\xFF\xFD\xFF\xFF\xFF\x6F\xFF\xFF\xFF\x00\xFF\xFF\xFF\x02\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x02\xFF\xFF\xFF\x00\xFF\xFF\xFF\x3C\xFF\xFF\xFF\xFF\xFF\xFF\xFF\x6A\xFF\xFF\xFF\x70\xFF\xFF\xFF\xFF\xFF\xFF\xFF\x40\xFF\xFF\xFF\x00\xFF\xFF\xFF\x03\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x01\xFF\xFF\xFF\x00\xFF\xFF\xFF\xCA\xFF\xFF\xFF\xA1\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\xB6\xFF\xFF\xFF\xCE\xFF\xFF\xFF\x00\xFF\xFF\xFF\x01\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x03\xFF\xFF\xFF\x00\xFF\xFF\xFF\x4D\xFF\xFF\xFF\xFC\xFF\xFF\xFF\x20\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x31\xFF\xFF\xFF\xFF\xFF\xFF\xFF\x50\xFF\xFF\xFF\x00\xFF\xFF\xFF\x03\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\xD8\xFF\xFF\xFF\x94\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\xAA\xFF\xFF\xFF\xDC\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x03\xFF\xFF\xFF\x00\xFF\xFF\xFF\x5E\xFF\xFF\xFF\xF7\xFF\xFF\xFF\x15\xFF\xFF\xFF\x00\xFF\xFF\xFF\x52\xFF\xFF\xFF\x56\xFF\xFF\xFF\x00\xFF\xFF\xFF\x24\xFF\xFF\xFF\xFF\xFF\xFF\xFF\x61\xFF\xFF\xFF\x00\xFF\xFF\xFF\x03\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x01\xFF\xFF\xFF\xE5\xFF\xFF\xFF\x83\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\xDA\xFF\xFF\xFF\xE3\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x99\xFF\xFF\xFF\xE9\xFF\xFF\xFF\x03\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x03\xFF\xFF\xFF\x00\xFF\xFF\xFF\x70\xFF\xFF\xFF\xF0\xFF\xFF\xFF\x0A\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\xD1\xFF\xFF\xFF\xD9\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x17\xFF\xFF\xFF\xFE\xFF\xFF\xFF\x73\xFF\xFF\xFF\x00\xFF\xFF\xFF\x03\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x01\xFF\xFF\xFF\x00\xFF\xFF\xFF\x09\xFF\xFF\xFF\xEF\xFF\xFF\xFF\x72\xFF\xFF\xFF\x00\xFF\xFF\xFF\x03\xFF\xFF\xFF\x00\xFF\xFF\xFF\xD2\xFF\xFF\xFF\xDB\xFF\xFF\xFF\x00\xFF\xFF\xFF\x03\xFF\xFF\xFF\x00\xFF\xFF\xFF\x86\xFF\xFF\xFF\xF4\xFF\xFF\xFF\x0B\xFF\xFF\xFF\x00\xFF\xFF\xFF\x01\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x03\xFF\xFF\xFF\x00\xFF\xFF\xFF\x82\xFF\xFF\xFF\xE7\xFF\xFF\xFF\x02\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\xD2\xFF\xFF\xFF\xDB\xFF\xFF\xFF\x00\xFF\xFF\xFF\x01\xFF\xFF\xFF\x00\xFF\xFF\xFF\x0C\xFF\xFF\xFF\xF5\xFF\xFF\xFF\x84\xFF\xFF\xFF\x00\xFF\xFF\xFF\x03\xFF\xFF\xFF\x00\xFF\xFF\xFF\x01\xFF\xFF\xFF\x00\xFF\xFF\xFF\x13\xFF\xFF\xFF\xF8\xFF\xFF\xFF\x61\xFF\xFF\xFF\x00\xFF\xFF\xFF\x04\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\xD2\xFF\xFF\xFF\xDB\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x04\xFF\xFF\xFF\x00\xFF\xFF\xFF\x73\xFF\xFF\xFF\xFE\xFF\xFF\xFF\x16\xFF\xFF\xFF\x00\xFF\xFF\xFF\x01\xFF\xFF\xFF\x03\xFF\xFF\xFF\x00\xFF\xFF\xFF\x94\xFF\xFF\xFF\xDB\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x01\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\xD0\xFF\xFF\xFF\xD8\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x01\xFF\xFF\xFF\x00\xFF\xFF\xFF\x03\xFF\xFF\xFF\xE9\xFF\xFF\xFF\x97\xFF\xFF\xFF\x00\xFF\xFF\xFF\x03\xFF\xFF\xFF\x00\xFF\xFF\xFF\x1F\xFF\xFF\xFF\xFE\xFF\xFF\xFF\x51\xFF\xFF\xFF\x00\xFF\xFF\xFF\x03\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\xE0\xFF\xFF\xFF\xE9\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x03\xFF\xFF\xFF\x00\xFF\xFF\xFF\x61\xFF\xFF\xFF\xFF\xFF\xFF\xFF\x22\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\xA6\xFF\xFF\xFF\xCD\xFF\xFF\xFF\x00\xFF\xFF\xFF\x01\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x01\xFF\xFF\xFF\x00\xFF\xFF\xFF\x6D\xFF\xFF\xFF\x72\xFF\xFF\xFF\x00\xFF\xFF\xFF\x01\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\xDC\xFF\xFF\xFF\xA9\xFF\xFF\xFF\x00\xFF\xFF\xFF\x2D\xFF\xFF\xFF\xFF\xFF\xFF\xFF\x41\xFF\xFF\xFF\x00\xFF\xFF\xFF\x03\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x01\xFF\xFF\xFF\x00\xFF\xFF\xFF\x7D\xFF\xFF\xFF\x82\xFF\xFF\xFF\x00\xFF\xFF\xFF\x01\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x03\xFF\xFF\xFF\x00\xFF\xFF\xFF\x4F\xFF\xFF\xFF\xFF\xFF\xFF\xFF\x30\xFF\xFF\xFF\xBC\xFF\xFF\xFF\xBC\xFF\xFF\xFF\x00\xFF\xFF\xFF\x02\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x02\xFF\xFF\xFF\x00\xFF\xFF\xFF\xA7\xFF\xFF\xFF\xAE\xFF\xFF\xFF\x00\xFF\xFF\xFF\x02\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x01\xFF\xFF\xFF\x00\xFF\xFF\xFF\xCC\xFF\xFF\xFF\xBB\xFF\xFF\xFF\xFF\xFF\xFF\xFF\x3E\xFF\xFF\xFF\x00\xFF\xFF\xFF\x01\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x00\xFF\xFF\xFF\x02\xFF\xFF\xFF\x00\xFF\xFF\xFF\x40\xFF\xFF\xFF\xF7\xFF\xFF\xFF\xE0\xFF\xFF\xFF\x7D\xFF\xFF\xFF\x00\xFF\xFF\xFF\x07\xFF\xFF\xFF\x04\xFF\xFF\xFF\x04\xFF\xFF\xFF\x04\xFF\xFF\xFF\x04\xFF\xFF\xFF\x04\xFF\xFF\xFF\x04\xFF\xFF\xFF\x04\xFF\xFF\xFF\x04\xFF\xFF\xFF\x04\xFF\xFF\xFF\x04\xFF\xFF\xFF\x04\xFF\xFF\xFF\x04\xFF\xFF\xFF\x06\xFF\xFF\xFF\x00\xFF\xFF\xFF\x8A\xFF\xFF\xFF\xDC\xFF\xFF\xFF\x3F\xFF\xFF\xFF\xE7\xFF\xFF\xFF\xE4\xFF\xFF\xFF\xE1\xFF\xFF\xFF\xE2\xFF\xFF\xFF\xE2\xFF\xFF\xFF\xE2\xFF\xFF\xFF\xE2\xFF\xFF\xFF\xE2\xFF\xFF\xFF\xE3\xFF\xFF\xFF\xE3\xFF\xFF\xFF\xE2\xFF\xFF\xFF\xE2\xFF\xFF\xFF\xE2\xFF\xFF\xFF\xE2\xFF\xFF\xFF\xE2\xFF\xFF\xFF\xE1\xFF\xFF\xFF\xE5\xFF\xFF\xFF\xF0\xFF\xFF\xFF\x43",
    20,
    19
)
-- SVG warning icon
local SKEET_WARN_SVG =
    '<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32">' ..
    '<path d="M16 3 L29 27 L3 27 Z" fill="white" stroke="white" stroke-width="1" stroke-linejoin="round"/>' ..
        '<rect x="14.5" y="11" width="3" height="9" rx="1.5" fill="black"/>' ..
            '<rect x="14.5" y="22" width="3" height="3" rx="1.5" fill="black"/>' .. "</svg>"
local skeet_warn_cache = {}
local function get_skeet_warn(size)
    if not skeet_warn_cache[size] then
        skeet_warn_cache[size] = renderer.load_svg(SKEET_WARN_SVG, size, size)
    end
    return skeet_warn_cache[size]
end

local SK_ALPHA = 1

local function ping_color_skeet(p)
    if p < 40 then
        return {255, 255, 255}
    end
    if p < 100 then
        return {255, 125, 95}
    end
    return {255, 60, 80}
end

local function on_paint_skeet()
    if not ui.get(ui_enable) then
        return
    end
    if ui.get(ui_theme) ~= "Classic" then
        return
    end
    if not is_in_game(iv) then
        return
    end
    local me = entity.get_local_player()
    if not me then
        return
    end

    local nc = get_netchan()
    if not nc then
        return
    end
    local sfps, svar = get_server_fps(nc)

    local sw, sh = client.screen_size()
    local pos = ui.get(ui_position)
    local x, y
    if pos == "Custom" then
        x, y = ui.get(ui_off_x), ui.get(ui_off_y)
    else
        x, y = sw / 2 + 1, sh - 155
    end

    local alpha = math.min(math.floor(math.sin((globals.realtime() % 3) * 4) * 125 + 200), 255)
    local color = {255, 200, 95, 255}
    local net_state = 0
    local net_data_text = {[0] = "clock syncing", [1] = "packet choke", [2] = "packet loss", [3] = "lost connection"}
    if nc.choke > 0 then
        net_state = 1
    end
    if nc.loss > 0 then
        net_state = 2
    end
    if nc.is_timing_out then
        net_state = 3
        nc.loss = 1
        SK_ALPHA = math.max(0.05, SK_ALPHA - globals.frametime())
    else
        SK_ALPHA = math.min(1, SK_ALPHA + globals.frametime() * 2)
    end

    local right_text =
        net_state ~= 0 and string.format("%.1f%% (%.1f%%)", nc.loss * 100, nc.choke * 100) or
        string.format("%.1fms", svar / 2)

    if net_state ~= 0 then
        color = {255, 50, 50, alpha}
    end

    local fs = ui.get(ui_font_size)
    local skeet_font = get_skeet_font(fs)
    local _, text_h = surface.get_text_size(skeet_font, "Aj")
    text_h = text_h or fs
    local line_h = text_h + math.max(4, math.floor(fs * 0.6))

    -- Icon scales with text height
    local icon_size = math.max(12, text_h + 4)
    local icon_tex = get_skeet_warn(icon_size)
    local icon_pad = math.floor(icon_size * 0.35)

    local ccor_text = net_data_text[net_state]
    local ccor_w = surface.get_text_size(skeet_font, ccor_text)
    -- Layout: [status text][gap=icon_pad][ICON][gap=icon_pad][+- value]
    -- sp_x is left edge of status text, x is icon center
    local sp_x = x - ccor_w - icon_pad - icon_size / 2
    local sp_y = y
    local cn = 1

    -- Left text (status), aligned to icon center on y-axis
    skeet_draw(sp_x, sp_y, 255, 255, 255, net_state ~= 0 and 255 or alpha, skeet_font, ccor_text)
    if icon_tex then
        renderer.texture(
            icon_tex,
            math.floor(x - icon_size / 2),
            math.floor(sp_y + (text_h - icon_size) / 2),
            icon_size,
            icon_size,
            color[1],
            color[2],
            color[3],
            color[4]
        )
    end
    -- Right text starts after the icon + small padding
    skeet_draw(
        math.floor(x + icon_size / 2 + icon_pad),
        sp_y,
        255,
        255,
        255,
        255,
        skeet_font,
        string.format("+- %s", right_text)
    )

    local bytes_in_text = string.format("in: %.2fk/s    ", nc.got_bytes / 1024)
    local bi_w = surface.get_text_size(skeet_font, bytes_in_text)
    local tickrate = 1 / globals.tickinterval()
    local lerp_ms = cl_interp_ratio:get_float() * (1000 / tickrate)
    local lerp_clr = (lerp_ms / 1000 < 2 / cl_updaterate:get_int()) and {255, 125, 95} or {255, 255, 255}

    skeet_draw(sp_x, sp_y + line_h * cn, 255, 255, 255, SK_ALPHA * 255, skeet_font, bytes_in_text)
    skeet_draw(
        sp_x + bi_w,
        sp_y + line_h * cn,
        lerp_clr[1],
        lerp_clr[2],
        lerp_clr[3],
        SK_ALPHA * 255,
        skeet_font,
        string.format("lerp: %.1fms", lerp_ms)
    )
    cn = cn + 1
    skeet_draw(
        sp_x,
        sp_y + line_h * cn,
        255,
        255,
        255,
        SK_ALPHA * 255,
        skeet_font,
        string.format("out: %.2fk/s", nc.sent_bytes / 1024)
    )
    cn = cn + 1
    skeet_draw(
        sp_x,
        sp_y + line_h * cn,
        255,
        255,
        255,
        SK_ALPHA * 255,
        skeet_font,
        string.format("sv: %.2f +- %.2fms    var: %.3f ms", sfps, svar, svar)
    )
    cn = cn + 1

    local outgoing, incoming = nc.crn_out, nc.crn_in
    local ping = outgoing * 1000
    local avg_ping = nc.avg_latency * 1000
    local ps_val = (ui.get(ping_spike_ref[1]) and ui.get(ping_spike_ref[2])) and ui.get(ping_spike_ref[3]) or 1
    local lat_int = (outgoing + incoming) / (ps_val - globals.tickinterval())
    local extra_lat = math.min(lat_int * 1000, 1) * 100
    local pc = ping_color_skeet(avg_ping)
    local nd_text = string.format("delay: %dms (+- %dms)    ", avg_ping, math.abs(avg_ping - ping))
    local nd_w = surface.get_text_size(skeet_font, nd_text)
    local in_lat = math.max(0, (incoming - outgoing) * 1000)
    local fl_pre = (ps_val ~= 1 and in_lat > 1) and string.format(": %dms", in_lat) or ""
    local fl_text = string.format("datagram%s", fl_pre)

    skeet_draw(sp_x, sp_y + line_h * cn, pc[1], pc[2], pc[3], SK_ALPHA * 255, skeet_font, nd_text)
    skeet_draw(
        sp_x + nd_w,
        sp_y + line_h * cn,
        255,
        255 / 100 * extra_lat,
        255 / 100 * extra_lat,
        SK_ALPHA * 255,
        skeet_font,
        fl_text
    )
end

client.set_event_callback("paint", on_paint_skeet)

-- Skeet theme (gamesense menu style)
local gs_font_cache = {}
local gs_font_warned = false
local function gs_get_font(size, weight)
    local key = size .. "_" .. weight
    local f = gs_font_cache[key]
    if f == nil then
        local ok, res = pcall(surface.create_font, "Tahoma", size, weight, {})
        if ok and res then
            gs_font_cache[key] = res
            f = res
        else
            gs_font_cache[key] = false
            if not gs_font_warned then
                client.color_log(255, 100, 100, "[netgraph] surface.create_font failed: " .. tostring(res))
                gs_font_warned = true
            end
        end
    end
    return f or nil
end

local function gs_text(x, y, r, g, b, a, fs, weight, text)
    local font = gs_get_font(fs, weight or 400)
    if font then
        surface.draw_text(math.floor(x), math.floor(y), r, g, b, a, font, text)
    else
        local flags = (weight and weight >= 600) and "b" or ""
        renderer.text(math.floor(x), math.floor(y), r, g, b, a, flags, 0, text)
    end
end

local function gs_text_size(fs, weight, text)
    local font = gs_get_font(fs, weight or 400)
    if font then
        return surface.get_text_size(font, text)
    end
    local flags = (weight and weight >= 600) and "b" or ""
    return renderer.measure_text(flags, text)
end

local function gs_font(size, weight)
    return nil
end

-- Checkered background pattern (matches gamesense menu/watermark)
local gs_bg_tex =
    renderer.load_rgba(
    "\x14\x14\x14\xFF" ..
        "\x14\x14\x14\xFF" ..
            "\x14\x14\x14\xFF" ..
                "\x0c\x0c\x0c\xFF" ..
                    "\x14\x14\x14\xFF" ..
                        "\x0c\x0c\x0c\xFF" ..
                            "\x14\x14\x14\xFF" ..
                                "\x0c\x0c\x0c\xFF" ..
                                    "\x14\x14\x14\xFF" ..
                                        "\x0c\x0c\x0c\xFF" ..
                                            "\x14\x14\x14\xFF" ..
                                                "\x14\x14\x14\xFF" ..
                                                    "\x14\x14\x14\xFF" ..
                                                        "\x0c\x0c\x0c\xFF" .. "\x14\x14\x14\xFF" .. "\x0c\x0c\x0c\xFF",
    4,
    4
)

local function gs_outline(x, y, w, h, r, g, b, a, t)
    t = t or 1
    renderer.rectangle(x, y, w, t, r, g, b, a)
    renderer.rectangle(x, y + h - t, w, t, r, g, b, a)
    renderer.rectangle(x, y + t, t, h - t * 2, r, g, b, a)
    renderer.rectangle(x + w - t, y + t, t, h - t * 2, r, g, b, a)
end

local function gs_gradient_bar(x, y, w, alpha)
    local half_l = math.floor(w / 2)
    local half_r = math.ceil(w / 2)
    local mult = 1
    for row = 0, 1 do
        renderer.gradient(
            x,
            y + row,
            half_l,
            1,
            59 * mult,
            175 * mult,
            222 * mult,
            alpha,
            202 * mult,
            70 * mult,
            205 * mult,
            alpha,
            true
        )
        renderer.gradient(
            x + half_l,
            y + row,
            half_r,
            1,
            202 * mult,
            70 * mult,
            205 * mult,
            alpha,
            201 * mult,
            227 * mult,
            58 * mult,
            alpha,
            true
        )
        mult = mult * 0.5
    end
end

local function draw_gs_panel(x, y, w, h, title)
    local border_w = 2
    local title_h = 0
    if title and title ~= "" then
        local _, th = renderer.measure_text("d", title)
        title_h = (th or 13) + 2
    end

    -- Frame layers
    gs_outline(x, y, w, h, 18, 18, 18, 255, 1)
    gs_outline(x + 1, y + 1, w - 2, h - 2, 62, 62, 62, 255, 1)
    gs_outline(x + 2, y + title_h + 1, w - 4, h - title_h - 3, 44, 44, 44, 255, border_w)
    gs_outline(
        x + border_w + 2,
        y + title_h + border_w + 1,
        w - border_w * 2 - 4,
        h - title_h - border_w * 2 - 3,
        62,
        62,
        62,
        255,
        1
    )

    -- Title bar
    if title_h > 0 then
        renderer.gradient(x + 2, y + 2, w - 4, title_h - 1, 56, 56, 56, 255, 44, 44, 44, 255, false)
        renderer.text(x + 5, y + 4, 255, 255, 255, 255, "d", 0, title)
    end

    local ix = x + border_w + 3
    local iy = y + title_h + border_w + 2
    local iw = w - (border_w + 3) * 2
    local ih = h - title_h - (border_w + 3) * 2 + 2 -- extend bg down to cover gap at bottom
    renderer.rectangle(ix, iy, iw, 1, 16, 16, 16, 255)
    renderer.rectangle(ix, iy + 3, iw, 1, 25, 25, 25, 255)
    gs_gradient_bar(ix, iy + 1, iw, 255)
    iy = iy + 4
    ih = ih - 4
    if surface.draw_filled_rect then
        surface.draw_filled_rect(ix, iy, iw, ih, 20, 20, 20, 255)
    else
        renderer.rectangle(ix, iy, iw, ih, 20, 20, 20, 255)
    end
    return ix, iy, iw, ih
end

local function gs_ping_color(p)
    if p < 40 then
        return 120, 220, 130
    end
    if p < 80 then
        return 200, 220, 120
    end
    if p < 130 then
        return 255, 190, 90
    end
    return 255, 90, 90
end

local function on_paint_gs()
    if not ui.get(ui_enable) then
        return
    end
    if ui.get(ui_theme) ~= "Skeet" then
        return
    end
    if not is_in_game(iv) then
        return
    end
    local me = entity.get_local_player()
    if not me then
        return
    end

    local nc = get_netchan()
    if not nc then
        return
    end
    local sfps, svar = get_server_fps(nc)

    local menu_r, menu_g, menu_b = ui.get(ui_accent)
    if menu_r == 130 and menu_g == 200 and menu_b == 255 then
        menu_r, menu_g, menu_b = ui.get(ui.reference("MISC", "Settings", "Menu color"))
    end

    local tickrate = 1 / globals.tickinterval()
    local lerp_ms = cl_interp_ratio:get_float() * (1000 / tickrate)
    local ping = nc.avg_latency * 1000
    local var = svar / 2
    local fps = 1 / globals.frametime()
    local loss = nc.loss * 100
    local choke = nc.choke * 100
    local in_kbs = nc.got_bytes / 1024
    local out_kbs = nc.sent_bytes / 1024

    local pr, pg, pb = gs_ping_color(ping)
    local rows = {
        {label = "ping", value = string.format("%dms", math.floor(ping + 0.5)), r = pr, g = pg, b = pb},
        {label = "variance", value = string.format("%.1fms", var), r = 220, g = 220, b = 230},
        {
            label = "fps",
            value = string.format("%d", math.floor(fps + 0.5)),
            r = (fps < 60 and 255 or 220),
            g = (fps < 60 and 100 or 220),
            b = (fps < 60 and 100 or 230)
        },
        {label = "tick", value = string.format("%d", math.floor(tickrate + 0.5)), r = menu_r, g = menu_g, b = menu_b},
        {label = "lerp", value = string.format("%.1fms", lerp_ms), r = 220, g = 220, b = 230},
        {
            label = "loss",
            value = string.format("%.1f%% / %.1f%%", loss, choke),
            r = (loss + choke) > 0 and 255 or 220,
            g = (loss + choke) > 0 and 90 or 220,
            b = (loss + choke) > 0 and 90 or 230
        },
        {label = "net", value = string.format("%.1f / %.1f k/s", in_kbs, out_kbs), r = 200, g = 200, b = 210},
        {label = "sv", value = string.format("%.1fms", sfps), r = 180, g = 180, b = 190}
    }

    local fs = ui.get(ui_font_size)
    local f_label = get_skeet_font(fs)
    local f_value = get_skeet_font(fs)

    local title = "net graph"
    local PAD_X = 6
    local PAD_Y = 4
    local _, row_h = surface.get_text_size(f_label, "Aj")
    if not row_h or row_h < 6 then
        row_h = fs
    end
    row_h = row_h + 3
    local GAP = 14
    local COL_GAP = 18
    local layout = ui.get(ui_layout)

    local item_lw, item_vw, item_total = {}, {}, {}
    local max_label_w, max_value_w = 0, 0
    for i = 1, #rows do
        local lw = surface.get_text_size(f_label, rows[i].label) or 0
        local vw = surface.get_text_size(f_value, rows[i].value) or 0
        item_lw[i] = lw
        item_vw[i] = vw
        item_total[i] = lw + GAP + vw
        if lw > max_label_w then
            max_label_w = lw
        end
        if vw > max_value_w then
            max_value_w = vw
        end
    end
    local title_w = surface.get_text_size(f_value, title) or 0

    -- Compute content size based on layout
    local content_w, content_h
    if layout == "Horizontal" then
        local total = 0
        for i = 1, #rows do
            total = total + item_total[i] + (i < #rows and COL_GAP or 0)
        end
        content_w = math.max(total, title_w)
        content_h = row_h
    elseif layout == "Compact" then
        local cols = 2
        local col_w = 0
        for i = 1, #rows do
            if item_total[i] > col_w then
                col_w = item_total[i]
            end
        end
        content_w = math.max(col_w * 2 + COL_GAP, title_w)
        content_h = math.ceil(#rows / 2) * row_h
    else -- Vertical
        content_w = math.max(max_label_w + GAP + max_value_w, title_w)
        content_h = #rows * row_h
    end

    local panel_w = content_w + PAD_X * 2 + 14
    local panel_h = content_h + PAD_Y * 2 + 14 + 13

    local sw, sh = client.screen_size()
    local pos = ui.get(ui_position)
    local px, py
    if pos == "Custom" then
        px, py = ui.get(ui_off_x), ui.get(ui_off_y)
    elseif pos == "Bottom Center" then
        px, py = math.floor(sw / 2 - panel_w / 2), sh - panel_h - 60
    elseif pos == "Bottom Left" then
        px, py = 30, sh - panel_h - 60
    elseif pos == "Bottom Right" then
        px, py = sw - panel_w - 30, sh - panel_h - 60
    elseif pos == "Top Center" then
        px, py = math.floor(sw / 2 - panel_w / 2), 30
    elseif pos == "Top Left" then
        px, py = 30, 30
    else
        px, py = sw - panel_w - 30, 30
    end

    local ix, iy, iw, ih = draw_gs_panel(px, py, panel_w, panel_h, title)

    if layout == "Horizontal" then
        local cx = ix + PAD_X
        local cy = iy + PAD_Y
        for i = 1, #rows do
            local r = rows[i]
            surface.draw_text(cx, cy, 200, 200, 200, 255, f_label, r.label)
            surface.draw_text(cx + item_lw[i] + GAP, cy, r.r, r.g, r.b, 255, f_value, r.value)
            cx = cx + item_total[i] + COL_GAP
            if i < #rows then
                renderer.rectangle(cx - COL_GAP / 2 - 1, iy + 2, 1, ih - 4, 60, 60, 60, 255)
            end
        end
    elseif layout == "Compact" then
        local col_w = 0
        for i = 1, #rows do
            if item_total[i] > col_w then
                col_w = item_total[i]
            end
        end
        for i = 1, #rows do
            local col = (i - 1) % 2
            local row = math.floor((i - 1) / 2)
            local r = rows[i]
            local cx = ix + PAD_X + col * (col_w + COL_GAP)
            local cy = iy + PAD_Y + row * row_h
            surface.draw_text(cx, cy, 200, 200, 200, 255, f_label, r.label)
            local right_x = cx + col_w - item_vw[i]
            surface.draw_text(right_x, cy, r.r, r.g, r.b, 255, f_value, r.value)
        end
    else -- Vertical
        local ry = iy + PAD_Y
        for i = 1, #rows do
            local r = rows[i]
            surface.draw_text(ix + PAD_X, ry, 200, 200, 200, 255, f_label, r.label)
            local right_x = ix + PAD_X + max_label_w + GAP + max_value_w - item_vw[i]
            surface.draw_text(right_x, ry, r.r, r.g, r.b, 255, f_value, r.value)
            ry = ry + row_h
        end
    end
end

client.set_event_callback("paint", on_paint_gs)

-- Visibility sync
local function sync_vis()
    local on = ui.get(ui_enable)
    local theme = ui.get(ui_theme)
    local modern = on and theme == "Modern"
    local skeet = on and theme == "Skeet"
    local classic = on and theme == "Classic"
    ui.set_visible(ui_theme, on)
    for _, ref in ipairs({ui_metrics, ui_smooth, ui_pulse, ui_icons, ui_text_col}) do
        ui.set_visible(ref, modern)
    end
    ui.set_visible(ui_layout, modern or skeet)
    ui.set_visible(ui_position, modern or skeet)
    ui.set_visible(ui_font_size, on)
    ui.set_visible(ui_accent, modern or skeet)
    ui.set_visible(ui_bg_col, modern)

    local pos = ui.get(ui_position)
    ui.set_visible(ui_off_x, (modern or skeet) and pos == "Custom")
    ui.set_visible(ui_off_y, (modern or skeet) and pos == "Custom")

    local has_g = modern and has_metric("Ping Graph")
    ui.set_visible(ui_graph_w, has_g)
    ui.set_visible(ui_graph_h, has_g)
end
ui.set_callback(ui_enable, sync_vis)
ui.set_callback(ui_theme, sync_vis)
ui.set_callback(ui_position, sync_vis)
ui.set_callback(ui_metrics, sync_vis)
sync_vis()
