-- Fully Compatible Gamesense Library Loader
local function load_lib_safe(names, forums_id)
    if type(names) == "string" then
        names = {names}
    end
    local sub_paths = {[[gamesense\lib\]], [[gamesense\]], [[lib\]], [[]]}
    for _, name in ipairs(names) do
        for _, sub in ipairs(sub_paths) do
            local mod_path = (sub .. name):gsub("\\", "/"):gsub("%.lua$", "")
            local ok, res = pcall(require, mod_path)
            if ok then
                client.log("[LUA EXEC] Successfully loaded module: " .. mod_path)
                return true, res or {}
            elseif res and type(res) == "string" and not res:find("not found") then
                client.log("[LUA EXEC] Error in module " .. mod_path .. ": " .. res)
            end
        end
    end
    if forums_id then
        client.log(
            string.format(
                "~ Error: Could not load %s. Download: https://gamesense.pub/forums/viewtopic.php?id=%d",
                names[1],
                forums_id
            )
        )
    end
    return false, nil
end

local _, surface_lib = load_lib_safe({"surface", "gamesense/surface"})
local _, database_lib = load_lib_safe({"database", "gamesense/database", "lua_database"})
local _, clipboard_lib = load_lib_safe({"clipboard", "gamesense/clipboard"})

-- Robust Library Detection & Fallbacks
local surface = _G.surface or surface_lib or _G.renderer
local database = _G.database or database_lib or {read = function()
            return nil
        end, write = function()
        end}
local clipboard = _G.clipboard or clipboard_lib or {get = function()
            return ""
        end, set = function()
        end}

-- Robust JSON Loader
local json = _G.json
if not json then
    local ok, lib = load_lib_safe("json")
    if ok then
        json = lib
    end
end
if not json or not json.encode then
    json = {encode = function(v)
            return "{}"
        end, decode = function(v)
            return {}
        end}
end
_G.ide_json_ptr = json -- Global pointer to ensure longevity

-- Global Constants & Configuration
WINDOW_W, WINDOW_H = 850, 650
GUTTER_W, MINIMAP_W = 55, 120
TAB_HEIGHT, BAR_HEIGHT = 26, 28
FONT_UI = " "
FONT_MONO = ""
FONTS = {mono = FONT_MONO}

LUA_KEYWORDS = {
    ["and"] = 1,
    ["break"] = 1,
    ["do"] = 1,
    ["else"] = 1,
    ["elseif"] = 1,
    ["end"] = 1,
    ["false"] = 1,
    ["for"] = 1,
    ["function"] = 1,
    ["if"] = 1,
    ["in"] = 1,
    ["local"] = 1,
    ["nil"] = 1,
    ["not"] = 1,
    ["or"] = 1,
    ["repeat"] = 1,
    ["return"] = 1,
    ["then"] = 1,
    ["true"] = 1,
    ["until"] = 1,
    ["while"] = 1
}

LUA_BUILTINS = {
    ["print"] = 1,
    ["pairs"] = 1,
    ["ipairs"] = 1,
    ["type"] = 1,
    ["tostring"] = 1,
    ["tonumber"] = 1,
    ["client"] = 1,
    ["entity"] = 1,
    ["globals"] = 1,
    ["ui"] = 1,
    ["renderer"] = 1,
    ["surface"] = 1,
    ["database"] = 1
}

COLORS = {
    syntax = {
        keyword = {249, 38, 114},
        builtin = {102, 217, 239},
        string = {230, 219, 116},
        number = {174, 129, 255},
        comment = {117, 113, 94},
        normal = {248, 248, 242}
    },
    accent = {255, 50, 50}
}

-- UTF-8 Helpers
local function utf8_is_cont(b)
    return b and (b >= 0x80 and b < 0xC0)
end
local function utf8_prev(str, pos)
    if pos <= 1 then
        return 1
    end
    local p = pos - 1
    repeat
        p = p - 1
    until p <= 0 or not utf8_is_cont(str:byte(p + 1))
    return p + 1
end
local function utf8_next(str, pos)
    if not str or pos > #str then
        return #str + 1
    end
    local b = str:byte(pos)
    if not b then
        return pos
    end
    if b < 0x80 then
        return pos + 1
    elseif b < 0xE0 then
        return pos + 2
    elseif b < 0xF0 then
        return pos + 3
    else
        return pos + 4
    end
end

-- Universal Rendering Wrappers
local function get_text_size_safe(font, text)
    if type(font) == "number" and surface and surface.get_text_size then
        local w, h = surface.get_text_size(font, text)
        return w or 0, h or 0
    end
    return renderer.measure_text("", text)
end

local function is_inside(ix, iy, iw, ih)
    local mx, my = ui.mouse_position()
    return mx >= ix and mx <= ix + iw and my >= iy and my <= iy + ih
end

local function is_valid_context()
    return STATE.active and not ui.is_menu_open() and not CONSOLE.open
end

local function draw_text_safe(x, y, r, g, b, a, font, text, align)
    local flags = ""
    if align == "c" then
        flags = flags .. "c"
    end
    if align == "r" then
        flags = flags .. "r"
    end
    renderer.text(x, y, r, g, b, a, flags, 0, text)
end

local function draw_line_safe(x1, y1, x2, y2, r, g, b, a)
    if surface and surface.draw_line then
        surface.draw_line(x1, y1, x2, y2, r, g, b, a)
    else
        renderer.line(x1, y1, x2, y2, r, g, b, a)
    end
end

-- UI Logic & Core Features
local function ide_log(msg)
    table.insert(STATE.output, {t = globals.curtime(), m = tostring(msg)})
    if #STATE.output > 100 then
        table.remove(STATE.output, 1)
    end
end

local function lex_lua(line)
    local tokens = {}
    local i = 1
    local len = #line
    while i <= len do
        local b = line:byte(i)
        local c = line:sub(i, i)

        if b == 45 and line:sub(i, i + 1) == "--" then
            table.insert(tokens, {type = "comment", val = line:sub(i)})
            break
        elseif b == 34 or b == 39 then
            local q = string.char(b)
            local s, e = line:find(q .. ".-" .. q, i)
            if s and e then
                table.insert(tokens, {type = "string", val = line:sub(s, e)})
                i = e + 1
            else
                table.insert(tokens, {type = "string", val = line:sub(i)})
                break
            end
        elseif b >= 48 and b <= 57 then
            local s, e = line:find("[%d%.]+", i)
            if s and e then
                table.insert(tokens, {type = "number", val = line:sub(s, e)})
                i = e + 1
            else
                i = i + 1
            end
        elseif (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 95 then
            local start = i
            while i <= len and line:sub(i, i):match("[%w_]") do
                i = i + 1
            end
            local word = line:sub(start, i - 1)
            local type = LUA_KEYWORDS[word] and "keyword" or (LUA_BUILTINS[word] and "builtin" or "normal")
            table.insert(tokens, {type = type, val = word})
        elseif b < 128 then
            table.insert(tokens, {type = "operator", val = c})
            i = i + 1
        else
            local next_idx = utf8_next(line, i)
            table.insert(tokens, {type = "normal", val = line:sub(i, next_idx - 1)})
            i = next_idx
        end
    end
    return tokens
end

local function draw_tokenized_line(x, y, line, alpha)
    if #line == 0 then
        return
    end
    local tokens = lex_lua(line)
    local cur_x = x
    for _, t in ipairs(tokens) do
        local c = COLORS.syntax[t.type] or COLORS.syntax.normal
        local tw, th = get_text_size_safe(FONTS.mono, t.val)
        draw_text_safe(cur_x, y, c[1], c[2], c[3], alpha * 255, FONTS.mono, t.val, "l")
        cur_x = cur_x + tw
    end
end

local function draw_circle_safe(x, y, radius, r, g, b, a)
    if surface and surface.draw_filled_circle then
        surface.draw_filled_circle(x, y, radius, r, g, b, a)
    else
        renderer.circle(x, y, r, g, b, a, radius, 0, 1)
    end
end

-- Safe Font Factory
local function create_safe_font(name, sz, weight, flags)
    if not surface or not surface.create_font then
        return nil
    end
    local ok, res = pcall(surface.create_font, name, sz, weight, flags)
    return ok and res or nil
end

-- -- Global Editor State
local STATE = {
    active = false,
    anim_alpha = 0,
    clicked = false,
    workspace = {
        scripts = {},
        active_idx = nil,
        sidebar_open = false,
        sidebar_anim = 0,
        scroll = 0,
        renaming_idx = nil,
        rename_buf = ""
    },
    -- Editor Tabs
    tabs = {
        {
            name = "Untitled",
            lines = {""},
            cursor = {line = 1, col = 1},
            scroll = {line = 0, col = 0},
            s_line = 1,
            s_col = 1
        }
    },
    active_tab = 1,
    selection = {s_line = 1, s_col = 1, active = false},
    -- HUD & UI
    pos = {x = 150, y = 150},
    dragging = false,
    drag_off = {x = 0, y = 0},
    search = {active = false, query = "", replace = "", mode = "find"},
    key_states = {},
    key_timers = {},
    last_toggle = 0,
    last_suppress = 0,
    hk_clicked = false, -- Hotkey Debounce
    orig_cvals = {yaw = 0.022, pit = 0.022, sens = 1.0},
    cvars_locked = false
}

-- Persistence Layer
local DB_KEY = "master_lua_executor_db"
local function workspace_save_all()
    local data = {
        tabs = {},
        active_tab = STATE.active_tab,
        library = STATE.workspace.scripts or {}
    }
    for _, t in ipairs(STATE.tabs) do
        table.insert(
            data.tabs,
            {
                name = t.name,
                lines = t.lines,
                cursor = t.cursor,
                scroll = t.scroll
            }
        )
    end
    local encoded = json.encode(data)
    if not encoded or encoded == "{}" then
        return
    end
    database.write(DB_KEY, encoded)
end

local function workspace_load_all()
    local data_raw = database.read(DB_KEY)
    if not data_raw or data_raw == "" then
        client.log("[LUA EXEC] No saved session found.")
        return
    end

    local ok, data = pcall(json.decode, data_raw)
    if not ok or not data then
        client.log("[LUA EXEC] Failed to decode saved session.")
        return
    end

    -- Restore Library (Sidebar)
    if data.library then
        STATE.workspace.scripts = data.library
    end

    -- Restore Editor Tabs (Priority Source)
    if data.tabs and #data.tabs > 0 then
        STATE.tabs = {}
        for _, t in ipairs(data.tabs) do
            table.insert(
                STATE.tabs,
                {
                    name = t.name or "Untitled",
                    lines = t.lines or {""},
                    cursor = t.cursor or {line = 1, col = 1},
                    scroll = t.scroll or {line = 0, col = 0},
                    s_line = 1,
                    s_col = 1
                }
            )
        end
        STATE.active_tab = math.min(data.active_tab or 1, #STATE.tabs)
        client.log(string.format("[LUA EXEC] Restored %d tabs and library.", #STATE.tabs))
    end
end

-- Console & Output Logic
local CONSOLE = {logs = {}, open = false, last_err = nil}
local function log_error(err)
    CONSOLE.open = true
    CONSOLE.last_err = tostring(err)
    client.log("[LUA EXEC ERROR] " .. tostring(err))
end

local function execute_lua()
    local tab = STATE.tabs[STATE.active_tab]
    local code = table.concat(tab.lines, "\n")
    if code == "" or code == " " then
        return
    end
    local header =
        "local print = function(...) local args = {...}; local s = ''; for i,v in ipairs(args) do s = s .. tostring(v) .. ' ' end; _G.ide_log_ptr(s) end\n"
    _G.ide_log_ptr = ide_log

    local f, err = load(header .. code)
    if not f then
        log_error(err)
        return
    end
    local ok, res = pcall(f)
    if not ok then
        log_error(res)
    end
end

-- Tooltip State
local TOOLTIP = {text = nil, x = 0, y = 0, timer = 0}
local function set_tooltip(text, x, y)
    TOOLTIP.text, TOOLTIP.x, TOOLTIP.y = text, x, y
    if TOOLTIP.timer == 0 then
        TOOLTIP.timer = globals.realtime()
    end
end

-- Icon Helpers
local function draw_icon_warning_triangle(x, y, sz, color, a)
    local sz2 = sz / 2
    local r, g, b = color[1], color[2], color[3]
    renderer.line(x, y - sz2, x - sz2, y + sz2, r, g, b, a)
    renderer.line(x, y - sz2, x + sz2, y + sz2, r, g, b, a)
    renderer.line(x - sz2, y + sz2, x + sz2, y + sz2, r, g, b, a)

    local bar_w = 1.6
    local bar_h = math.max(1, sz * 0.4)
    local dot_sz = math.max(1.5, sz * 0.1)

    -- Vertical Group Centering
    local total_h = bar_h + (sz * 0.1) + dot_sz
    local group_y_start = y - (total_h / 2.2)

    renderer.rectangle(x - (bar_w / 2), group_y_start, bar_w, bar_h, 255, 255, 255, a)
    renderer.rectangle(x - (dot_sz / 2), group_y_start + bar_h + (sz * 0.1), dot_sz, dot_sz, 255, 255, 255, a)
end

local function draw_icon_play(x, y, sz, color, a)
    local sz2 = sz / 2
    renderer.triangle(x, y - sz2, x, y + sz2, x + sz, y, color[1], color[2], color[3], a)
end

local function draw_icon_edit(x, y, sz, color, a)
    local sz2 = sz / 2
    -- Linear Pencil Body
    draw_line_safe(x - sz2 + 2, y + sz2 - 2, x + sz2 - 2, y - sz2 + 2, color[1], color[2], color[3], a)
    renderer.triangle(x - sz2, y + sz2, x - sz2 + 3, y + sz2, x - sz2, y + sz2 - 3, color[1], color[2], color[3], a)
end

local function draw_icon_trash(x, y, sz, color, a)
    local sz2 = sz / 2
    surface.draw_outlined_rect(x - sz2 + 1, y - sz2 + 2, sz - 2, sz - 2, color[1], color[2], color[3], a)
    surface.draw_line(x - sz2, y - sz2 + 1, x + sz2, y - sz2 + 1, color[1], color[2], color[3], a)
    surface.draw_line(x - sz2 + 2, y - sz2, x + sz2 - 2, y - sz2, color[1], color[2], color[3], a)
end

-- UI Setup
ui_master_switch = ui.new_checkbox("LUA", "A", "Lua Executor")
ui_hotkey = ui.new_hotkey("LUA", "A", "Toggle IDE", false)
ui_accent_color = ui.new_color_picker("LUA", "A", "Accent", 150, 210, 120, 255)
ui_layout = ui.new_combobox("LUA", "A", "Keyboard Layout", {"English", "Russian"})

local function sync_menu_visibility()
    local enabled = ui.get(ui_master_switch)
    ui.set_visible(ui_hotkey, enabled)
    ui.set_visible(ui_accent_color, enabled)
    ui.set_visible(ui_layout, enabled)
end
ui.set_callback(ui_master_switch, sync_menu_visibility)
sync_menu_visibility() -- Init

-- Panorama Helper
local PANORAMA_ACTIVE = false
local function set_chat_enabled(enabled)
    local loader = pan or _G.panorama
    if not loader or not loader.loadstring then
        return
    end
    local js =
        [[
        return function(enabled) {
            window.g_LuaExecutorActive = !enabled;
            var root = $.GetContextPanel(); while (root.GetParent() != null) { root = root.GetParent(); }
            if (root) {
                var scan = function(el) {
                    if (!el) return;
                    var id = el.id || "";
                    if (id.match(/Menu|Sidebar|SideBar|Radial|TeamSelection|Container|HudMenu/i)) {
                        el.style.opacity = enabled ? "1.0" : "0.0";
                        el.style.visibility = enabled ? "visible" : "collapse";
                        el.hittest = enabled;
                        el.enabled = enabled;
                        el.visible = enabled;
                        if (!enabled) { el.style.display = "none"; }
                        else { el.style.display = "block"; }
                        if (typeof el.SetAcceptsFocus === 'function') el.SetAcceptsFocus(enabled);
                    }
                    var children = el.Children();
                    for (var i=0; i < children.length; i++) { scan(children[i]); }
                };
                scan(root);
                if (!window.g_LuaHooked) {
                    $.RegisterEventHandler("Cancelled", root, function() { 
                        if (window.g_LuaExecutorActive) { return true; } 
                        return false; 
                    });
                    window.g_LuaHooked = true;
                }
            }
        }
    ]]
    local js_loader = loader.loadstring(js, "CSGOHud")
    if type(js_loader) == "function" then
        pcall(js_loader, enabled)
    elseif type(js_loader) == "table" and js_loader[0] then
        pcall(js_loader[0], enabled)
    end
end

-- Immediate Cleanup Callback
ui.set_callback(
    ui_master_switch,
    function(s)
        sync_menu_visibility() -- V102
        if not ui.get(s) then
            STATE.active = false
            if PANORAMA_ACTIVE then
                set_chat_enabled(true)
                client.exec(
                    "-lookspin; -showscores; cl_drawhud 1; bind y messagemode; bind u messagemode2; bind m teammenu; bind tab +showscores; cl_chatfilters 63"
                )
                client.set_cvar("hud_saytext_time", 12)
                if STATE.cvars_locked then
                    client.set_cvar("m_yaw", STATE.orig_cvals.yaw or 0.022)
                    client.set_cvar("m_pitch", STATE.orig_cvals.pit or 0.022)
                    client.set_cvar("cl_mousegrab", 0)
                    STATE.cvars_locked = false
                end
                PANORAMA_ACTIVE = false
            end
        end
    end
)

-- Blur Implementation
local PAN_BLUR = {id = "v_lua_blur", created = false}
function PAN_BLUR.init()
    if not pan_ok then
        return
    end
    pcall(
        function()
            pan.loadstring(
                [[
        var parent = $.GetContextPanel().FindChildTraverse("v_hud_root") || $.GetContextPanel();
        var blur = parent.FindChildTraverse("v_lua_blur") || $.CreatePanel("Panel", parent, "v_lua_blur");
        blur.style.backdropFilter = "blur(16px) brightness(0.6)"; blur.style.borderRadius = "12px";
        blur.style.backgroundColor = "rgba(0, 0, 0, 0.45)"; blur.style.opacity = "0";
    ]]
            )()
            PAN_BLUR.created = true
        end
    )
end
function PAN_BLUR.update(x, y, w, h, a)
    if not pan_ok or not PAN_BLUR.created then
        return
    end
    pcall(
        function()
            pan.loadstring(
                string.format(
                    [[
        var blur = $.GetContextPanel().FindChildTraverse("v_lua_blur");
        if (blur) { blur.style.x = "%dpx"; blur.style.y = "%dpx"; blur.style.width = "%dpx"; blur.style.height = "%dpx"; blur.style.opacity = "%f"; }
    ]],
                    x,
                    y,
                    w,
                    h,
                    a
                )
            )()
        end
    )
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

-- Drawing Primitives
local function draw_gs_header(x, y, w, alpha)
    local r1, g1, b1, r2, g2, b2, r3, g3, b3, r4, g4, b4, r5, g5, b5 =
        59,
        175,
        222,
        202,
        70,
        205,
        201,
        227,
        58,
        255,
        140,
        50,
        255,
        50,
        50
    local seg = w / 4
    local alp = alpha * 255
    surface.draw_filled_gradient_rect(x, y, seg, 1, r1, g1, b1, alp, r2, g2, b2, alp, true)
    surface.draw_filled_gradient_rect(x + seg, y, seg, 1, r2, g2, b2, alp, r3, g3, b3, alp, true)
    surface.draw_filled_gradient_rect(x + seg * 2, y, seg, 1, r3, g3, b3, alp, r4, g4, b4, alp, true)
    surface.draw_filled_gradient_rect(x + seg * 3, y, w - (seg * 3), 1, r4, g4, b4, alp, r5, g5, b5, alp, true) -- Fixed End (V95)
    draw_text_safe(x + 13, y + 8, 240, 240, 240, alp, "b", "LUA EXECUTOR", "l")
end

-- Selection Logic
local function get_selection_range()
    if not STATE.selection.active then
        return nil
    end
    local tab = STATE.tabs[STATE.active_tab]
    local s_l, s_c, e_l, e_c = STATE.selection.s_line, STATE.selection.s_col, tab.cursor.line, tab.cursor.col
    if s_l > e_l or (s_l == e_l and s_c > e_c) then
        return e_l, e_c, s_l, s_c
    else
        return s_l, s_c, e_l, e_c
    end
end

local function get_line_indent(str)
    return str:match("^%s*") or ""
end

local function should_indent_extra(str)
    local s = str:lower():gsub("%s*$", "") -- strip trailing
    return s:find("then$") or s:find("do$") or s:find("repeat$") or s:find("function%s*%(.*%)$") or s:find("{$")
end

local function delete_selection()
    local tab = STATE.tabs[STATE.active_tab]
    local s_l, s_c, e_l, e_c = get_selection_range()
    if not s_l then
        return
    end
    if s_l == e_l then
        tab.lines[s_l] = tab.lines[s_l]:sub(1, s_c - 1) .. tab.lines[s_l]:sub(e_c)
    else
        local first, last = tab.lines[s_l]:sub(1, s_c - 1), tab.lines[e_l]:sub(e_c)
        tab.lines[s_l] = first .. last
        for i = e_l, s_l + 1, -1 do
            table.remove(tab.lines, i)
        end
    end
    tab.cursor.line, tab.cursor.col = s_l, s_c
    STATE.selection.active = false
end

local function get_selection_text()
    local tab = STATE.tabs[STATE.active_tab]
    local s_l, s_c, e_l, e_c = get_selection_range()
    if not s_l then
        return nil
    end
    if s_l == e_l then
        return tab.lines[s_l]:sub(s_c, e_c - 1)
    end
    local res = {tab.lines[s_l]:sub(s_c)}
    for i = s_l + 1, e_l - 1 do
        table.insert(res, tab.lines[i])
    end
    table.insert(res, tab.lines[e_l]:sub(1, e_c - 1))
    return table.concat(res, "\n")
end

-- Key Processing
local function insert_char(char)
    if not char or char == "" then
        return
    end
    local tab = STATE.tabs[STATE.active_tab]
    if not tab then
        return
    end
    if STATE.selection.active then
        delete_selection()
    end
    local line = tab.lines[tab.cursor.line]
    tab.lines[tab.cursor.line] = line:sub(1, tab.cursor.col - 1) .. char .. line:sub(tab.cursor.col)
    tab.cursor.col = tab.cursor.col + #char
end

client.set_event_callback(
    "character",
    function(char)
        if not is_valid_context() or not char then
            return
        end

        -- Routing for Search UI
        if STATE.search.active then
            STATE.search.query = STATE.search.query .. char
            return
        end

        local tab = STATE.tabs[STATE.active_tab]
        -- Auto-Closing Bracket Logic
        local PAIRS = {["("] = ")", ["["] = "]", ["{"] = "}", ['"'] = '"', ["'"] = "'"}
        if PAIRS[char] and not STATE.selection.active then
            local line = tab.lines[tab.cursor.line]
            tab.lines[tab.cursor.line] =
                line:sub(1, tab.cursor.col - 1) .. char .. PAIRS[char] .. line:sub(tab.cursor.col)
            tab.cursor.col = tab.cursor.col + 1
            return
        end

        if STATE.selection.active then
            delete_selection()
        end
        insert_char(char)
        workspace_save_all() -- Auto-save
    end
)

local function draw_tabs(x, y, w, alpha)
    local th = 24 -- Compact Height
    surface.draw_filled_gradient_rect(x, y, w, th, 15, 15, 15, alpha * 200, 10, 10, 10, alpha * 150, false)
    surface.draw_line(x, y + th - 1, x + w, y + th - 1, 45, 45, 45, alpha * 255)

    local tx = x
    for i, tab in ipairs(STATE.tabs) do
        local tw, _ = get_text_size_safe(FONT_UI, tab.name)
        local tab_w = tw + 35 -- Compact Padding
        local is_act = (STATE.active_tab == i)
        local hov = is_inside(tx, y, tab_w, th)

        if is_act then
            surface.draw_filled_gradient_rect(
                tx,
                y,
                tab_w,
                th - 1,
                35,
                35,
                35,
                alpha * 255,
                25,
                25,
                25,
                alpha * 255,
                false
            )
            surface.draw_filled_rect(
                tx,
                y + th - 2,
                tab_w,
                2,
                COLORS.accent[1],
                COLORS.accent[2],
                COLORS.accent[3],
                alpha * 255
            )
        elseif hov then
            surface.draw_filled_rect(tx, y + 2, tab_w, th - 4, 25, 25, 25, alpha * 150)
        end

        local tc = is_act and 255 or 160
        draw_text_safe(tx + tab_w / 2 - 5, y + 8, tc, tc, tc, alpha * 255, FONT_UI, tab.name, "c")
        local cx, cy = tx + tab_w - 12, y + th / 2 - 4
        local hov_close = is_inside(cx - 6, cy - 6, 12, 12)
        local cc = hov_close and {240, 50, 50} or {80, 80, 80}
        if hov_close or is_act then
            local sz = 2
            surface.draw_line(cx - sz, cy - sz, cx + sz, cy + sz, cc[1], cc[2], cc[3], alpha * 255)
            surface.draw_line(cx + sz, cy - sz, cx - sz, cy + sz, cc[1], cc[2], cc[3], alpha * 255)
        end

        if hov and client.key_state(0x01) and not STATE.clicked then
            if hov_close and #STATE.tabs > 1 then
                table.remove(STATE.tabs, i)
                STATE.active_tab = math.min(STATE.active_tab, #STATE.tabs)
                workspace_save_all()
            else
                STATE.active_tab = i
            end
            STATE.clicked = true
        end
        tx = tx + tab_w + 2
    end
end

local function draw_ide(x, y, w, h, alpha)
    local tab = STATE.tabs[STATE.active_tab]
    if not tab then
        return
    end

    local line_h = 15
    local visible_lines = math.floor(h / line_h)

    -- Draw Gutter
    surface.draw_filled_rect(x, y, GUTTER_W, h, 20, 20, 20, alpha * 255)
    surface.draw_line(x + GUTTER_W, y, x + GUTTER_W, y + h, 40, 40, 40, alpha * 200)
    surface.draw_line(x + GUTTER_W + 1, y, x + GUTTER_W + 1, y + h, 80, 80, 80, alpha * 20)

    -- Render Lines
    for i = 1, visible_lines do
        local line_idx = i + tab.scroll.line
        if line_idx > #tab.lines then
            break
        end

        local ly = y + (i - 1) * line_h
        local line_str = tab.lines[line_idx]

        -- Current Line Highlight (Subtle Glass)
        if line_idx == tab.cursor.line then
            surface.draw_filled_rect(x + GUTTER_W + 2, ly, w - GUTTER_W - 2, line_h, 255, 255, 255, alpha * 10)
        end

        -- Line Number (Elegant Fade)
        draw_text_safe(x + GUTTER_W - 12, ly + 1, 80, 80, 80, alpha * 255, FONT_UI, tostring(line_idx), "r")

        -- Selection Drawing
        local s_l, s_c, e_l, e_c = get_selection_range()
        if s_l and line_idx >= s_l and line_idx <= e_l then
            local str = tab.lines[line_idx]
            local start_c = (line_idx == s_l) and s_c or 1
            local end_c = (line_idx == e_l) and e_c or (#str + 1)
            local p1w, _ = get_text_size_safe(FONTS.mono, str:sub(1, start_c - 1))
            local p2w, _ = get_text_size_safe(FONTS.mono, str:sub(1, end_c - 1))
            surface.draw_filled_rect(
                x + GUTTER_W + 5 + p1w,
                ly,
                p2w - p1w,
                line_h,
                COLORS.accent[1],
                COLORS.accent[2],
                COLORS.accent[3],
                alpha * 60
            )
        end

        local max_chars = math.floor((w - GUTTER_W - 30) / 8)
        local clipped_str = line_str:len() > max_chars and line_str:sub(1, max_chars) or line_str
        draw_tokenized_line(x + GUTTER_W + 5, ly + 1, clipped_str, alpha)

        if line_idx == tab.cursor.line and STATE.active and (globals.realtime() % 1.0 > 0.5) then
            local pre = line_str:sub(1, tab.cursor.col - 1)
            local pw, _ = get_text_size_safe(FONTS.mono, pre)
            surface.draw_filled_rect(x + GUTTER_W + 5 + pw, ly + 2, 1, line_h - 4, 255, 255, 255, alpha * 255)
        end
    end
end

local function handle_backspace()
    local tab = STATE.tabs[STATE.active_tab]
    if STATE.selection.active then
        delete_selection()
        return
    end
    local line = tab.lines[tab.cursor.line]
    if tab.cursor.col > 1 then
        local p = utf8_prev(line, tab.cursor.col)
        tab.lines[tab.cursor.line] = line:sub(1, p - 1) .. line:sub(tab.cursor.col)
        tab.cursor.col = p
    elseif tab.cursor.line > 1 then
        local prev = tab.lines[tab.cursor.line - 1]
        local new_c = #prev + 1
        tab.lines[tab.cursor.line - 1] = prev .. line
        table.remove(tab.lines, tab.cursor.line)
        tab.cursor.line, tab.cursor.col = tab.cursor.line - 1, new_c
    end
    workspace_save_all()
end

local function handle_enter()
    local tab = STATE.tabs[STATE.active_tab]
    if STATE.selection.active then
        delete_selection()
    end
    local current_line = tab.lines[tab.cursor.line]
    local indent = get_line_indent(current_line)
    if should_indent_extra(current_line:sub(1, tab.cursor.col - 1)) then
        indent = indent .. "    "
    end

    local remaining = current_line:sub(tab.cursor.col)
    tab.lines[tab.cursor.line] = current_line:sub(1, tab.cursor.col - 1)
    table.insert(tab.lines, tab.cursor.line + 1, indent .. remaining)

    tab.cursor.line = tab.cursor.line + 1
    tab.cursor.col = #indent + 1
    workspace_save_all()
end

local function move_cursor(dl, dc, shift)
    local tab = STATE.tabs[STATE.active_tab]
    if shift and not STATE.selection.active then
        STATE.selection.s_line, STATE.selection.s_col, STATE.selection.active = tab.cursor.line, tab.cursor.col, true
    elseif not shift then
        STATE.selection.active = false
    end

    if dl ~= 0 then
        tab.cursor.line = math.max(1, math.min(#tab.lines, tab.cursor.line + dl))
        tab.cursor.col = math.min(#tab.lines[tab.cursor.line] + 1, tab.cursor.col)
    end
    if dc < 0 then
        if tab.cursor.col == 1 and tab.cursor.line > 1 then
            tab.cursor.line, tab.cursor.col = tab.cursor.line - 1, #tab.lines[tab.cursor.line - 1] + 1
        else
            tab.cursor.col = utf8_prev(tab.lines[tab.cursor.line], tab.cursor.col)
        end
    elseif dc > 0 then
        if tab.cursor.col > #tab.lines[tab.cursor.line] and tab.cursor.line < #tab.lines then
            tab.cursor.line, tab.cursor.col = tab.cursor.line + 1, 1
        else
            tab.cursor.col = utf8_next(tab.lines[tab.cursor.line], tab.cursor.col)
        end
    end
end

local KEY_MAP = {
    EN = {
        [0x30] = {")", "0"},
        [0x31] = {"!", "1"},
        [0x32] = {"@", "2"},
        [0x33] = {"#", "3"},
        [0x34] = {"$", "4"},
        [0x35] = {"%", "5"},
        [0x36] = {"^", "6"},
        [0x37] = {"&", "7"},
        [0x38] = {"*", "8"},
        [0x39] = {"(", "9"},
        [0x41] = {"A", "a"},
        [0x42] = {"B", "b"},
        [0x43] = {"C", "c"},
        [0x44] = {"D", "d"},
        [0x45] = {"E", "e"},
        [0x46] = {"F", "f"},
        [0x47] = {"G", "g"},
        [0x48] = {"H", "h"},
        [0x49] = {"I", "i"},
        [0x4A] = {"J", "j"},
        [0x4B] = {"K", "k"},
        [0x4C] = {"L", "l"},
        [0x4D] = {"M", "m"},
        [0x4E] = {"N", "n"},
        [0x4F] = {"O", "o"},
        [0x50] = {"P", "p"},
        [0x51] = {"Q", "q"},
        [0x52] = {"R", "r"},
        [0x53] = {"S", "s"},
        [0x54] = {"T", "t"},
        [0x55] = {"U", "u"},
        [0x56] = {"V", "v"},
        [0x57] = {"W", "w"},
        [0x58] = {"X", "x"},
        [0x59] = {"Y", "y"},
        [0x5A] = {"Z", "z"},
        [0xBA] = {":", ";"},
        [0xBB] = {"+", "="},
        [0xBC] = {"<", ","},
        [0xBD] = {"_", "-"},
        [0xBE] = {">", "."},
        [0xBF] = {"?", "/"},
        [0xC0] = {"~", "`"},
        [0xDB] = {"{", "["},
        [0xDC] = {"|", "\\"},
        [0xDD] = {"}", "]"},
        [0xDE] = {'"', "'"},
        [0x20] = {" ", " "}
    },
    RU = {
        [0x41] = {"Ф", "ф"},
        [0x42] = {"И", "и"},
        [0x43] = {"С", "с"},
        [0x44] = {"В", "в"},
        [0x45] = {"У", "у"},
        [0x46] = {"А", "а"},
        [0x47] = {"П", "п"},
        [0x48] = {"Р", "р"},
        [0x49] = {"Ш", "ш"},
        [0x4A] = {"О", "о"},
        [0x4B] = {"Л", "л"},
        [0x4C] = {"Д", "д"},
        [0x4D] = {"Ь", "ь"},
        [0x4E] = {"Т", "т"},
        [0x4F] = {"Щ", "щ"},
        [0x50] = {"З", "з"},
        [0x51] = {"Й", "й"},
        [0x52] = {"К", "к"},
        [0x53] = {"Ы", "ы"},
        [0x54] = {"Е", "е"},
        [0x55] = {"Г", "г"},
        [0x56] = {"М", "м"},
        [0x57] = {"Ц", "ц"},
        [0x58] = {"Ч", "ч"},
        [0x59] = {"Н", "н"},
        [0x5A] = {"Я", "я"},
        [0xBA] = {"Ж", "ж"},
        [0xDE] = {"Э", "э"},
        [0xBC] = {"Б", "б"},
        [0xBE] = {"Ю", "ю"},
        [0xDB] = {"Х", "х"},
        [0xDD] = {"Ъ", "ъ"},
        [0xC0] = {"Ё", "ё"},
        [0xBF] = {",", "."},
        [0x20] = {" ", " "}
    }
}

local function handle_key_action(vk)
    if STATE.workspace.active_search then
        if vk == 0x08 then
            STATE.workspace.search = (STATE.workspace.search or ""):sub(1, -2)
        elseif vk == 0x0D then
            STATE.workspace.active_search = false
        else
            local m = KEY_MAP["EN"][vk]
            if m then
                STATE.workspace.search = (STATE.workspace.search or "") .. m[2]
            end
        end
        return
    end
    if STATE.workspace.renaming_idx then
        if vk == 0x08 then
            STATE.workspace.rename_buf = (STATE.workspace.rename_buf or ""):sub(1, -2)
        elseif client.key_state(0x0D) then -- ENTER to finish
            STATE.workspace.scripts[STATE.workspace.renaming_idx].name = STATE.workspace.rename_buf
            STATE.workspace.renaming_idx = nil
            workspace_save_all() -- Persist
        elseif client.key_state(0x1B) then -- ESC to cancel
            STATE.workspace.renaming_idx = nil
        else
            local m = KEY_MAP["EN"][vk]
            if m then
                STATE.workspace.rename_buf = (STATE.workspace.rename_buf or "") .. m[2]
            end
        end
        return
    end
    local shift, ctrl, alt = client.key_state(0x10), client.key_state(0x11), client.key_state(0x12)
    local lay = (ui.get(ui_layout) == "English") and "EN" or "RU"
    if vk == 0x08 then
        handle_backspace()
    elseif vk == 0x0D then
        handle_enter()
    elseif vk == 0x25 then
        move_cursor(0, -1, shift)
    elseif vk == 0x27 then
        move_cursor(0, 1, shift)
    elseif vk == 0x26 then
        move_cursor(-1, 0, shift)
    elseif vk == 0x28 then
        move_cursor(1, 0, shift)
    elseif (vk == 0x12 and shift) or (vk == 0x10 and alt) then
        ui.set(ui_layout, lay == "EN" and "Russian" or "English")
    elseif ctrl and vk == 0x41 then -- Ctrl+A
        local tab = STATE.tabs[STATE.active_tab]
        STATE.selection.s_line, STATE.selection.s_col, STATE.selection.active = 1, 1, true
        tab.cursor.line, tab.cursor.col = #tab.lines, #tab.lines[#tab.lines] + 1
    elseif ctrl and vk == 0x46 then -- Ctrl+F: Search
        if STATE.search.active then
            STATE.search.mode = "find"
        end
    elseif ctrl and vk == 0x43 then -- Ctrl+C
        if clipboard then
            local txt = get_selection_text()
            if txt then
                clipboard.set(txt)
            end
        end
    elseif ctrl and vk == 0x56 then -- Ctrl+V Robust Paste
        if clipboard then
            local p = tostring(clipboard.get() or ""):sub(1, 10000)
            if #p > 0 then
                local tab = STATE.tabs[STATE.active_tab]
                local lines = {}
                local from = 1
                local d_f, d_t = p:find("\n", from)
                while d_f do
                    table.insert(lines, (p:sub(from, d_f - 1):gsub("\r", "")))
                    from = d_t + 1
                    d_f, d_t = p:find("\n", from)
                end
                table.insert(lines, (p:sub(from):gsub("\r", "")))
                insert_char(lines[1] or "")

                if #lines > 1 then
                    local suffix = tab.lines[tab.cursor.line]:sub(tab.cursor.col)
                    tab.lines[tab.cursor.line] = tab.lines[tab.cursor.line]:sub(1, tab.cursor.col - 1)
                    for i = 2, #lines do
                        local content = lines[i] .. (i == #lines and suffix or "")
                        table.insert(tab.lines, tab.cursor.line + i - 1, content)
                    end
                    tab.cursor.line = tab.cursor.line + #lines - 1
                    tab.cursor.col = #lines[#lines] + 1
                end
                workspace_save_all()
            end
        end
    else
        local m = KEY_MAP[lay] and KEY_MAP[lay][vk]
        if m then
            insert_char(shift and m[1] or m[2])
            workspace_save_all()
        end
    end
end

local CHECK_KEYS = {
    0x08,
    0x0D,
    0x25,
    0x27,
    0x26,
    0x28,
    0x12,
    0x10,
    0x41,
    0x42,
    0x43,
    0x44,
    0x45,
    0x46,
    0x47,
    0x48,
    0x49,
    0x4A,
    0x4B,
    0x4C,
    0x4D,
    0x4E,
    0x4F,
    0x50,
    0x51,
    0x52,
    0x53,
    0x54,
    0x55,
    0x56,
    0x57,
    0x58,
    0x59,
    0x5A,
    0xBA,
    0xBB,
    0xBC,
    0xBD,
    0xBE,
    0xBF,
    0xC0,
    0xDB,
    0xDC,
    0xDD,
    0xDE,
    0x20,
    0x30,
    0x31,
    0x32,
    0x33,
    0x34,
    0x35,
    0x36,
    0x37,
    0x38,
    0x39
}
local REPEAT_BLACK = {[0x41] = true, [0x43] = true, [0x56] = true, [0x58] = true} -- A, C, V, X (Commands)
local function poll_keyboard()
    if not STATE.active or STATE.anim_alpha < 0.5 then
        return
    end

    local menu_open = ui.is_menu_open()
    if STATE.workspace.renaming_idx then
        local idx = STATE.workspace.renaming_idx
        local buf = STATE.workspace.rename_buf or ""

        if client.key_state(0x08) then -- BACKSPACE
            local t = globals.realtime()
            if t > (STATE.key_timers[0x08] or 0) then
                STATE.workspace.rename_buf = buf:sub(1, -2)
                STATE.key_timers[0x08] = t + 0.1
            end
            return
        elseif client.key_state(0x0D) then -- ENTER
            if STATE.workspace.scripts[idx] then
                STATE.workspace.scripts[idx].name = buf
                workspace_save_all() -- Persist
            end
            STATE.workspace.renaming_idx = nil
            return
        elseif client.key_state(0x1B) then -- ESC
            STATE.workspace.renaming_idx = nil
            return
        end
    end

    local allow_input = not menu_open or STATE.workspace.renaming_idx or STATE.search.active
    if not allow_input then
        return
    end

    local t = globals.realtime()
    for _, vk in ipairs(CHECK_KEYS) do
        local cur = client.key_state(vk)
        local prev = STATE.key_states[vk] or false
        if cur then
            if not prev then
                handle_key_action(vk)
                STATE.key_timers[vk] = t + 0.4
            elseif t > (STATE.key_timers[vk] or 0) and not REPEAT_BLACK[vk] then
                handle_key_action(vk)
                STATE.key_timers[vk] = t + 0.035
            end
        end
        STATE.key_states[vk] = cur
    end
end

local function draw_sidebar(rx, ry, sw, total_h, alpha)
    local sa = alpha * STATE.workspace.sidebar_anim
    local m_down = client.key_state(0x01)

    -- Fixed Sidebar Glass (Total Height Sync)
    surface.draw_filled_gradient_rect(rx, ry, sw, total_h, 25, 25, 25, sa * 180, 15, 15, 15, sa * 220, false)
    surface.draw_line(rx + sw - 1, ry, rx + sw - 1, ry + total_h, 60, 60, 60, sa * 100)
    surface.draw_line(rx + sw, ry, rx + sw, ry + total_h, 10, 10, 10, sa * 200)

    local query = STATE.workspace.search or ""
    if sa > 0.2 then
        local sx, sy, sw_bar, sh = rx, ry, sw, 24 -- Flush Top & Sides (V98)
        surface.draw_filled_rect(sx, sy, sw_bar, sh, 10, 10, 10, sa * 150)
        surface.draw_line(sx, sy + sh - 1, sx + sw_bar, sy + sh - 1, 60, 60, 60, sa * 100)

        local hov_search = is_inside(sx, sy, sw_bar, sh)
        if hov_search and m_down and not STATE.clicked then
            STATE.workspace.active_search = true
            STATE.clicked = true
        elseif not hov_search and m_down then
            STATE.workspace.active_search = false
        end

        local color_a = STATE.workspace.active_search and 255 or (query == "" and 100 or 200)
        draw_text_safe(
            sx + 12,
            sy + 6,
            160,
            160,
            160,
            sa * color_a,
            FONT_UI,
            query == "" and "Filter..." or (query .. (STATE.workspace.active_search and "_" or "")),
            "l"
        )
    end

    -- Script Library
    local visible_idx = 0
    for i, script in ipairs(STATE.workspace.scripts) do
        if query == "" or script.name:lower():find(query:lower()) then
            local sy_item = ry + 24 + (visible_idx * 26) -- Snapped to Search (V100)
            if sy_item > ry + total_h - 52 then
                break
            end
            visible_idx = visible_idx + 1

            local is_sel = (STATE.workspace.active_idx == i)
            local is_ren = (STATE.workspace.renaming_idx == i)
            local hov_scr = is_inside(rx, sy_item, sw, 26) -- Flush (V100)

            if hov_scr or is_sel then
                local bg_a = is_sel and (sa * 255) or (sa * 80)
                surface.draw_filled_gradient_rect(rx, sy_item, sw, 26, 45, 45, 45, bg_a, 25, 25, 25, bg_a, true)
                if is_sel then
                    surface.draw_filled_rect(
                        rx,
                        sy_item,
                        2,
                        26,
                        COLORS.accent[1],
                        COLORS.accent[2],
                        COLORS.accent[3],
                        sa * 255
                    )
                end
            end

            if sa > 0.5 then
                local display_name = is_ren and (STATE.workspace.rename_buf .. "_") or script.name:sub(1, 18)
                local tc = is_sel and 255 or (hov_scr and 220 or 150)
                local icon_clicked = false
                if hov_scr and not is_ren then
                    local hov_del = is_inside(rx + sw - 40, sy_item, 40, 26)
                    local hov_edit = is_inside(rx + sw - 80, sy_item, 40, 26)

                    if hov_del then
                        draw_icon_trash(rx + sw - 20, sy_item + 13, 10, {255, 60, 60}, sa * 255)
                        if m_down and not STATE.clicked then
                            table.remove(STATE.workspace.scripts, i)
                            workspace_save_all()
                            STATE.clicked = true
                            icon_clicked = true
                        end
                    else
                        draw_icon_trash(rx + sw - 20, sy_item + 13, 9, {120, 120, 120}, sa * 200)
                    end

                    if hov_edit and not icon_clicked then
                        draw_icon_edit(rx + sw - 45, sy_item + 13, 10, COLORS.accent, sa * 255)
                        if m_down and not STATE.clicked then
                            STATE.workspace.renaming_idx = i
                            STATE.workspace.rename_buf = script.name
                            STATE.clicked = true
                            icon_clicked = true
                            STATE.key_timers[0x08] = 0
                        end
                    else
                        draw_icon_edit(rx + sw - 45, sy_item + 13, 9, {120, 120, 120}, sa * 200)
                    end
                end

                -- Now check row selection ONLY if no icon was clicked (V75)
                draw_text_safe(rx + 20, sy_item + 6, tc, tc, tc, sa * 255, FONT_UI, display_name, "l")

                if hov_scr and m_down and not is_ren and not STATE.clicked and not icon_clicked then
                    local already_open = false
                    for tidx, tab in ipairs(STATE.tabs) do
                        if tab.name == script.name then
                            STATE.active_tab = tidx
                            already_open = true
                            break
                        end
                    end
                    if not already_open then
                        local lines = {}
                        for s in (script.content .. "\n"):gmatch("([^\r\n]*)[\r\n]") do
                            table.insert(lines, s)
                        end
                        table.insert(
                            STATE.tabs,
                            {
                                name = script.name,
                                lines = lines,
                                cursor = {line = 1, col = 1},
                                scroll = {line = 0, col = 0}
                            }
                        )
                        STATE.active_tab = #STATE.tabs
                    end
                    STATE.workspace.active_idx = i
                    STATE.clicked = true
                end
            end
        end
    end

    -- Flush-Bottom Sidebar Button (V98)
    if sa > 0.2 then
        local btn_x, btn_y, btn_w, btn_h = rx, ry + total_h - 26, sw, 26
        local hov_save = is_inside(btn_x, btn_y, btn_w, btn_h)
        surface.draw_filled_gradient_rect(
            btn_x,
            btn_y,
            btn_w,
            btn_h,
            30,
            30,
            30,
            sa * (hov_save and 255 or 150),
            20,
            20,
            20,
            sa * (hov_save and 255 or 150),
            false
        )
        surface.draw_line(btn_x, btn_y, btn_x + btn_w, btn_y, 60, 60, 60, sa * 100)

        if sa > 0.7 then
            draw_text_safe(
                btn_x + btn_w / 2,
                btn_y + btn_h / 2 - 3,
                220,
                220,
                220,
                sa * 255,
                FONT_UI,
                "+ New Concept",
                "c"
            )
        end
        if hov_save and m_down and not STATE.clicked then
            local tab = STATE.tabs[STATE.active_tab]
            table.insert(
                STATE.workspace.scripts,
                {name = "Script " .. (#STATE.workspace.scripts + 1), content = table.concat(tab.lines, "\n")}
            )
            workspace_save_all()
            STATE.clicked = true
        end
    end
end

-- Main Loop
client.set_event_callback(
    "paint_ui",
    function()
        if ui_master_switch == nil then
            return
        end
        local master = ui.get(ui_master_switch)
        if not master then
            STATE.active = false
            STATE.anim_alpha = lerp(STATE.anim_alpha, 0, globals.frametime() * 12)
            if STATE.anim_alpha < 0.01 then
                if PANORAMA_ACTIVE then
                    set_chat_enabled(true)
                    client.exec("cl_drawhud 1; -lookspin; -showscores; bind tab +showscores; cl_chatfilters 63")
                    PANORAMA_ACTIVE = false
                end
                PAN_BLUR.update(0, 0, 0, 0, 0)
                return
            end
        else
            -- Hotkey Toggle Implementation (V106)
            if ui.get(ui_hotkey) and not STATE.hk_clicked then
                STATE.active = not STATE.active
                STATE.hk_clicked = true
            elseif not ui.get(ui_hotkey) then
                STATE.hk_clicked = false
            end

            local target_a = STATE.active and 1 or 0
            STATE.anim_alpha = lerp(STATE.anim_alpha, target_a, globals.frametime() * 12)

            if STATE.anim_alpha > 0.5 and not STATE.cvars_locked then
                STATE.orig_cvals.yaw, STATE.orig_cvals.pit = client.get_cvar("m_yaw"), client.get_cvar("m_pitch")
                client.set_cvar("m_yaw", 0)
                client.set_cvar("m_pitch", 0)
                STATE.cvars_locked = true
            elseif STATE.anim_alpha < 0.1 and STATE.cvars_locked then
                client.set_cvar("m_yaw", STATE.orig_cvals.yaw or 0.022)
                client.set_cvar("m_pitch", STATE.orig_cvals.pit or 0.022)
                STATE.cvars_locked = false
                set_chat_enabled(true)
                if PANORAMA_ACTIVE then
                    client.exec("cl_drawhud 1; -lookspin; -showscores; bind tab +showscores; cl_chatfilters 63")
                    PANORAMA_ACTIVE = false
                end
            end
        end

        local x, y, alpha = STATE.pos.x, STATE.pos.y, STATE.anim_alpha
        local w, h = WINDOW_W or 850, WINDOW_H or 550
        if not COLORS then
            return
        end
        COLORS.accent = {ui.get(ui_accent_color)}
        local m_pos = {ui.mouse_position()}
        local m_down = client.key_state(0x01)

        if m_down and not STATE.dragging and is_inside(x, y, w, TAB_HEIGHT) then
            STATE.dragging = true
            STATE.drag_off = {x = m_pos[1] - x, y = m_pos[2] - y}
        elseif not m_down then
            STATE.dragging = false
        end
        if STATE.dragging then
            STATE.pos.x, STATE.pos.y = m_pos[1] - STATE.drag_off.x, m_pos[2] - STATE.drag_off.y
            x, y = STATE.pos.x, STATE.pos.y
        end

        PAN_BLUR.update(x, y, w, h, alpha)
        surface.draw_filled_gradient_rect(x, y, w, h, 20, 20, 20, alpha * 170, 10, 10, 10, alpha * 190, false)

        -- Glass Outlines (Outer Dark, Inner Light Highlight)
        surface.draw_outlined_rect(x, y, w, h, 0, 0, 0, alpha * 255)
        surface.draw_outlined_rect(x + 1, y + 1, w - 2, h - 2, 80, 80, 80, alpha * 60)
        for i = 1, 3 do
            surface.draw_outlined_rect(
                x - i,
                y - i,
                w + i * 2,
                h + i * 2,
                COLORS.accent[1],
                COLORS.accent[2],
                COLORS.accent[3],
                alpha * (20 / (i * 2))
            )
        end

        draw_gs_header(x, y, w, alpha)

        -- Sidebar Animation Logic
        local sw_max = 180
        local sw = sw_max * STATE.workspace.sidebar_anim
        if STATE.workspace.sidebar_open then
            STATE.workspace.sidebar_anim = math.min(1, STATE.workspace.sidebar_anim + 0.1)
        else
            STATE.workspace.sidebar_anim = math.max(0, STATE.workspace.sidebar_anim - 0.1)
        end

        -- Main Tabbed Layout
        local tab_bar_h = 24 -- Sync with draw_tabs (V90)
        local console_h = STATE.show_console and 100 or 0
        local ed_h_adj = h - TAB_HEIGHT - BAR_HEIGHT - tab_bar_h - console_h
        local ax, ay = x + w - 15, y + 13
        local hov_toggle = is_inside(ax - 10, y, 25, 26)
        local tc = hov_toggle and {255, 255, 255} or {150, 150, 150}
        local sz = 3
        if STATE.workspace.sidebar_open then
            surface.draw_line(ax + sz / 2, ay - sz, ax - sz / 2, ay, tc[1], tc[2], tc[3], alpha * 255)
            surface.draw_line(ax - sz / 2, ay, ax + sz / 2, ay + sz, tc[1], tc[2], tc[3], alpha * 255)
        else
            surface.draw_line(ax - sz / 2, ay - sz, ax + sz / 2, ay, tc[1], tc[2], tc[3], alpha * 255)
            surface.draw_line(ax + sz / 2, ay, ax - sz / 2, ay + sz, tc[1], tc[2], tc[3], alpha * 255)
        end

        if hov_toggle and client.key_state(0x01) then
            local t = globals.realtime()
            if t > (STATE.workspace.last_toggle or 0) then
                STATE.workspace.sidebar_open = not STATE.workspace.sidebar_open
                STATE.workspace.last_toggle = t + 0.3
            end
        end

        local rx, ry = x, y + TAB_HEIGHT

        -- Render Main Components
        if sw > 1 then
            draw_sidebar(rx, ry, sw, h - TAB_HEIGHT - BAR_HEIGHT, alpha)
        end
        draw_tabs(rx + sw, ry, w - sw, alpha)
        draw_ide(rx + sw, ry + tab_bar_h, w - sw, ed_h_adj, alpha)

        if STATE.search.active then
            local sx, sy, sw, sh = rx + sw + 10, ry + tab_bar_h + ed_h_adj - 40, w - sw - 20, 32
            surface.draw_filled_gradient_rect(sx, sy, sw, sh, 25, 25, 25, alpha * 240, 15, 15, 15, alpha * 250, false)
            surface.draw_outlined_rect(sx, sy, sw, sh, 80, 80, 80, alpha * 60)
            surface.draw_outlined_rect(sx + 1, sy + 1, sw - 2, sh - 2, 255, 255, 255, alpha * 5)

            local label = (STATE.search.mode == "find") and "FIND:" or "REPLACE:"
            draw_text_safe(sx + 12, sy + 9, 240, 50, 50, alpha * 255, FONT_UI, label, "l")

            local q = STATE.search.query .. "_"
            draw_text_safe(sx + 65, sy + 9, 220, 220, 220, alpha * 255, FONTS.mono, q, "l")
            draw_text_safe(sx + sw - 12, sy + 9, 80, 80, 80, alpha * 255, FONT_UI, "[ESC] Close  [ENTER] Next", "r")
        end

        if STATE.show_console then
            local cx, cy, cw = rx + sw, ry + tab_bar_h + ed_h_adj, w - sw
            surface.draw_line(cx, cy, x + w, cy, 45, 45, 45, alpha * 255)
            surface.draw_filled_gradient_rect(
                cx,
                cy + 1,
                cw,
                console_h - 1,
                10,
                10,
                10,
                alpha * 200,
                5,
                5,
                5,
                alpha * 230,
                false
            )
            draw_text_safe(cx + 15, cy + 6, 80, 80, 80, alpha * 255, FONT_UI, "OUTPUT CONSOLE", "l")

            local log_y = cy + 28
            for i = math.max(1, #STATE.output - 5), #STATE.output do
                local log = STATE.output[i]
                draw_text_safe(cx + 20, log_y, 160, 160, 160, alpha * 255, FONTS.mono, "» " .. log.m, "l")
                log_y = log_y + 15
            end
        end

        if CONSOLE.open then
            surface.draw_filled_rect(x, y, w, h, 0, 0, 0, alpha * 200) -- Dark Back

            local mw, mh = 440, 150
            local mx, my = x + (w - mw) / 2, y + (h - mh) / 2

            for i = 1, 8 do
                surface.draw_outlined_rect(mx - i, my - i, mw + i * 2, mh + i * 2, 255, 40, 40, alpha * (10 / i))
            end
            surface.draw_filled_gradient_rect(mx, my, mw, mh, 25, 15, 15, alpha * 255, 15, 10, 10, alpha * 255, false)
            surface.draw_filled_rect(mx, my, mw, 28, 10, 5, 5, alpha * 200)
            surface.draw_line(mx, my + 28, mx + mw, my + 28, 255, 50, 50, alpha * 40)

            local pulse = (0.7 + 0.3 * math.sin(globals.realtime() * 6))
            surface.draw_filled_rect(mx, my, 3, mh, 255, 40, 40, alpha * (255 * pulse))
            draw_icon_warning_triangle(mx + 30, my + 15, 18, {255, 100, 100}, alpha * 255)
            draw_text_safe(mx + 55, my + 10, 255, 100, 100, alpha * 255, "b", "SYSTEM ERROR", "l")

            local hov_close = is_inside(mx + mw - 25, my + 5, 20, 20)
            draw_text_safe(
                mx + mw - 12,
                my + 6,
                (hov_close and 255 or 150),
                (hov_close and 255 or 150),
                (hov_close and 255 or 150),
                alpha * 255,
                FONT_UI,
                "x",
                "r"
            )
            if hov_close and client.key_state(0x01) then
                CONSOLE.open = false
            end

            -- Error Text (Body)
            if CONSOLE.last_err then
                local wrapped_err = CONSOLE.last_err:sub(1, 140) .. (CONSOLE.last_err:len() > 140 and "..." or "")
                draw_text_safe(mx + 20, my + 45, 220, 220, 220, alpha * 255, FONT_UI, wrapped_err, "l")
            end

            local abx, aby, abw, abh = mx + (mw - 130) / 2, my + mh - 35, 130, 26
            local hov_ok = is_inside(abx, aby, abw, abh)
            surface.draw_filled_gradient_rect(
                abx,
                aby,
                abw,
                abh,
                40,
                20,
                20,
                alpha * (hov_ok and 200 or 100),
                20,
                10,
                10,
                alpha * 150,
                false
            )
            surface.draw_outlined_rect(abx, aby, abw, abh, 255, 60, 60, alpha * (hov_ok and 180 or 80))

            local btw, bth = get_text_size_safe(FONT_UI, "DISMISS")
            draw_text_safe(
                abx + (abw - btw) / 2,
                aby + (abh - bth) / 2,
                240,
                240,
                240,
                alpha * 255,
                FONT_UI,
                "DISMISS",
                "l"
            )
            if hov_ok and m_down then
                CONSOLE.open = false
            end
        end

        -- Global Tooltip Render (Last Layer)
        if TOOLTIP.text and globals.realtime() - TOOLTIP.timer > 0.4 then
            local tw, th = get_text_size_safe(FONT_UI, TOOLTIP.text)
            local tx, ty = TOOLTIP.x - tw / 2, TOOLTIP.y - 20
            surface.draw_filled_rect(tx - 4, ty - 2, tw + 8, th + 4, 30, 30, 30, alpha * 230)
            surface.draw_outlined_rect(tx - 4, ty - 2, tw + 8, th + 4, 255, 255, 255, alpha * 20)
            draw_text_safe(tx, ty, 220, 220, 220, alpha * 255, FONT_UI, TOOLTIP.text, "l")
        end
        TOOLTIP.text = nil

        local mm_x = x + w - MINIMAP_W
        local tab = STATE.tabs[STATE.active_tab]
        surface.draw_filled_rect(mm_x, ry + tab_bar_h, MINIMAP_W - 1, ed_h_adj, 25, 25, 25, alpha * 80)

        local total_lines = #tab.lines
        if total_lines > 1 then
            local visible_lines = math.floor(ed_h_adj / 15)
            local sb_h = math.max(10, math.min(ed_h_adj, (ed_h_adj / total_lines) * visible_lines))
            local sb_y = ry + tab_bar_h + (tab.scroll.line / total_lines) * ed_h_adj
            surface.draw_filled_rect(
                x + w - 3,
                sb_y,
                2,
                sb_h,
                COLORS.accent[1],
                COLORS.accent[2],
                COLORS.accent[3],
                alpha * 180
            )
        end

        local bar_y = y + h - BAR_HEIGHT
        local bar_ty = bar_y + 8
        surface.draw_line(x, bar_y, x + w, bar_y, 45, 45, 45, alpha * 255)
        surface.draw_filled_gradient_rect(
            x,
            bar_y + 1,
            w,
            BAR_HEIGHT - 1,
            15,
            15,
            15,
            alpha * 220,
            10,
            10,
            10,
            alpha * 240,
            false
        )

        local function draw_sep(sx)
            surface.draw_line(sx, bar_y + 6, sx, bar_y + BAR_HEIGHT - 6, 80, 80, 80, alpha * 40)
        end
        local lx = x + 15
        draw_text_safe(lx, bar_ty, 140, 140, 140, alpha * 255, FONT_UI, "LUA", "l")
        local cur_x = lx + 45
        draw_sep(cur_x - 10)

        local pulse = (0.7 + 0.3 * math.sin(globals.realtime() * 4))
        draw_circle_safe(cur_x, bar_y + BAR_HEIGHT / 2, 2.5, 0, 255, 120, alpha * 255 * pulse)
        draw_text_safe(cur_x + 10, bar_ty, 120, 120, 120, alpha * 255, FONT_UI, "STABLE", "l")

        local stat_text = string.format("LN %d, COL %d  |  UTF-8", tab.cursor.line, tab.cursor.col)
        draw_text_safe(x + (w + sw) / 2, bar_y + 13, 150, 150, 150, alpha * 255, FONT_UI, stat_text, "c")

        local r_btn_w = 100
        local r_btn_x = x + w - r_btn_w
        local hov_run = is_inside(r_btn_x, bar_y, r_btn_w, BAR_HEIGHT)

        if hov_run then
            surface.draw_filled_rect(
                r_btn_x,
                bar_y + 1,
                r_btn_w,
                BAR_HEIGHT - 1,
                COLORS.accent[1],
                COLORS.accent[2],
                COLORS.accent[3],
                alpha * 20
            )
            surface.draw_filled_rect(
                r_btn_x,
                bar_y + BAR_HEIGHT - 2,
                r_btn_w,
                2,
                COLORS.accent[1],
                COLORS.accent[2],
                COLORS.accent[3],
                alpha * 255
            )
        end

        local run_color = hov_run and COLORS.accent or {220, 220, 220}
        draw_icon_play(r_btn_x + 25, bar_y + BAR_HEIGHT / 2, 8, run_color, alpha * 255)
        draw_text_safe(r_btn_x + 42, bar_ty, run_color[1], run_color[2], run_color[3], alpha * 255, "b", "Run", "l")

        if hov_run and client.key_state(0x01) and not STATE.clicked then
            STATE.clicked = true
            execute_lua()
        elseif not m_down then
            STATE.clicked = false
        end

        if STATE.active then
            client.set_cvar("cl_mousegrab", 1)
            client.set_cvar("m_yaw", 0)
            client.set_cvar("m_pitch", 0)

            -- AGGRESSIVE MOP UP V4
            if ui.is_menu_open() then
                client.exec("-showscores; -lookspin; cancelselect")
            end

            -- High Frequency Deep Scan Pulse
            local t = globals.realtime()
            if t > (STATE.last_suppress or 0) then
                set_chat_enabled(false)
                STATE.last_suppress = t + 0.1
            end

            -- ESC Closure (Debounced)
            if client.key_state(0x1B) then
                local prev_esc = STATE.key_states[0x1B] or false
                if not prev_esc then
                    ui.set(ui_master_switch, false)
                    client.exec("-showscores; -lookspin; cancelselect")
                end
            end
            STATE.key_states[0x1B] = client.key_state(0x1B)

            if not PANORAMA_ACTIVE then
                client.exec(
                    "cl_drawhud 0; unbind y; unbind u; unbind tab; unbind m; cl_chatfilters 0; -showscores; -lookspin"
                )
                PANORAMA_ACTIVE = true
            end
        end
        poll_keyboard()
    end
)

client.set_event_callback(
    "input",
    function(e)
        if not ui.get(ui_master_switch) or not STATE.active or STATE.anim_alpha < 0.05 then
            return false
        end
        if e.vk == 0x1B then
            return true
        end
        return not ui.is_menu_open()
    end
)
client.set_event_callback(
    "shutdown",
    function()
        workspace_save_all()
        client.set_cvar("m_yaw", 0.022)
        client.set_cvar("m_pitch", 0.022)
        client.set_cvar("cl_mousegrab", 0)
        client.set_cvar("hud_saytext_time", 12)
        client.exec(
            "cl_drawhud 1; bind y messagemode; bind u messagemode2; bind tab +showscores; bind m teammenu; cl_chatfilters 63; -showscores; -lookspin"
        )
        set_chat_enabled(true)
    end
)
client.set_event_callback(
    "setup_command",
    function(cmd)
        if STATE.active and STATE.anim_alpha > 0.01 then
            cmd.forwardmove, cmd.sidemove, cmd.buttons = 0, 0, 0
        end
    end
)
-- Initialize Master Session
workspace_load_all()
PAN_BLUR.init()
