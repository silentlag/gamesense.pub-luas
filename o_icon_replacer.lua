-- @silentlag

local ffi = require("ffi")
ffi.cdef(
    [[
    typedef struct {
        int x;
        int y;
    } Vec2;
    typedef struct {
        char            pad0[0x4];
        int             TextureId;
        int             TextureOffset;
        char            pad1[0x4];
        Vec2            Size;
    } IconTab;
]]
)

local TAB_NAMES = {"RAGE", "AA", "LEGIT", "VISUALS", "MISC", "SKINS", "PLIST", "CONFIG", "LUA"}
local icons_to_replace = {
    [1] = {file = "antiaim.png", w = 47, h = 47},
    [2] = {file = "legit.png", w = 42, h = 42},
    [3] = {file = "visuals.png", w = 47, h = 47},
    [5] = {file = "skins.png", w = 47, h = 47},
    [7] = {file = "config.png", w = 40, h = 40},
    [8] = {file = "lua.png", w = 42, h = 42}
}

local enabled = ui.new_checkbox("LUA", "A", "Icon Replacer")
local reset_btn =
    ui.new_button(
    "LUA",
    "A",
    "Reset Icons",
    function()
    end
)
local font_base = ffi.cast("int*", 0x43479930)
local font_size_ptr = ffi.cast("float*", font_base[0] + 0x100)
local font_size_default = font_size_ptr[0]
local font_slider =
    ui.new_slider("LUA", "A", "Font Size", 50, 200, math.floor(font_size_default * 100 + 0.5), true, "%", 1)
ui.set_callback(
    font_slider,
    function()
        font_size_ptr[0] = ui.get(font_slider) * 0.01
    end
)

local tabsptr = ffi.cast("intptr_t*", 0x434799AC + 0x54)
local tabsinfo = {}
local backup = {}
for i = 0, #TAB_NAMES - 1 do
    local tab = ffi.cast("int*", tabsptr[0])[i]
    local tabicon = ffi.cast("IconTab*", tab + 0x7C)
    backup[i] = {
        TextureId = tabicon.TextureId,
        TextureOffset = tabicon.TextureOffset,
        Size = {x = tabicon.Size.x, y = tabicon.Size.y}
    }
    tabsinfo[i] = tabicon
end

local base = ffi.cast("int*", 0x43479A04)
local lua_tabclass = ffi.cast("int*", base[0] - (0x20 - 0x4 * 7))
local lua_pos_y = ffi.cast("int*", lua_tabclass[0] + 0x24)
local lua_size_y = ffi.cast("int*", lua_tabclass[0] + 0x2C)
local menuh_ptr = ffi.cast("int*", 0x434799C4)
local menuact_ptr = ffi.cast("char*", 0x434799E0)

local loaded_textures = {}

local function load_icons()
    for tab_idx, info in pairs(icons_to_replace) do
        local filepath = "gsicons/" .. info.file
        local ok, data = pcall(readfile, filepath)
        if ok and data then
            local tex = renderer.load_png(data, info.w, info.h)
            if tex then
                loaded_textures[tab_idx] = {id = tex, w = info.w, h = info.h}
                client.log("[Icon Replacer] Loaded: " .. TAB_NAMES[tab_idx + 1])
            else
                client.log("[Icon Replacer] Failed to load: " .. info.file)
            end
        else
            client.log("[Icon Replacer] File not found: " .. filepath)
        end
    end
end

local function apply_icons()
    for tab_idx, tex in pairs(loaded_textures) do
        local info = tabsinfo[tab_idx]
        if info and tab_idx ~= 8 then
            info.TextureId = tex.id
            info.TextureOffset = 0
            info.Size.x = tex.w
            info.Size.y = tex.h
        end
    end
end

local function reset_icons()
    for i = 0, #TAB_NAMES - 1 do
        local info = tabsinfo[i]
        if info and backup[i] then
            info.TextureId = backup[i].TextureId
            info.TextureOffset = backup[i].TextureOffset
            info.Size.x = backup[i].Size.x
            info.Size.y = backup[i].Size.y
        end
    end
end

local function update()
    if ui.get(enabled) then
        if next(loaded_textures) == nil then
            load_icons()
        end
        apply_icons()
    else
        reset_icons()
    end
end

ui.set_callback(enabled, update)
ui.set_callback(
    reset_btn,
    function()
        reset_icons()
        loaded_textures = {}
        ui.set(enabled, false)
    end
)

client.set_event_callback(
    "paint_ui",
    function()
        if not ui.get(enabled) or not loaded_textures[8] then
            return
        end

        local info = tabsinfo[8]
        local menuh = menuh_ptr[0]
        local lua_bottom = lua_pos_y[0] + lua_size_y[0]

        if lua_bottom <= menuh then
            local tex = loaded_textures[8]
            info.TextureId = tex.id
            info.TextureOffset = 0
            info.Size.x = tex.w
            info.Size.y = tex.h
        else
            info.TextureId = -1
            info.TextureOffset = 0
            info.Size.x = 0
            info.Size.y = 0
        end
    end
)

defer(
    function()
        reset_icons()
        font_size_ptr[0] = font_size_default
    end
)

client.log("[Icon Replacer] Loaded! Place icons in Counter-Strike Global Offensive/gsicons/ folder.")
