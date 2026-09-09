-- @silentlag

local ffi = require("ffi")
local grad1 = ffi.cast("uint8_t*", 0x43384950)
local grad2 = ffi.cast("uint8_t*", 0x43384940)
local grad3 = ffi.cast("uint8_t*", 0x4338496D)
local function save(ptr)
    return {ptr[0], ptr[1], ptr[2], ptr[3]}
end
local o1, o2, o3 = save(grad1), save(grad2), save(grad3)
local function restore(ptr, o)
    ptr[0] = o[1]
    ptr[1] = o[2]
    ptr[2] = o[3]
    ptr[3] = o[4]
end
local function write_rgba(ptr, r, g, b, a)
    ptr[0] = b
    ptr[1] = g
    ptr[2] = r
    ptr[3] = a
end

ui.new_label("LUA", "A", "--- Gradient Line Colors ---")
local enabled = ui.new_checkbox("LUA", "A", "Enable Gradient Colors")
local preset = ui.new_combobox("LUA", "A", "Gradient Preset", {"Custom", "Default", "Transcolor"})
local picker1 = ui.new_color_picker("LUA", "A", "Gradient Line 1", 0xF6, 0xF6, 0x83, 0xFF)
local picker2 = ui.new_color_picker("LUA", "A", "Gradient Line 2", 0xB8, 0x9C, 0xFF, 0xFF)
local picker3 = ui.new_color_picker("LUA", "A", "Gradient Line 3", 0xFF, 0xFF, 0xFF, 0xFF)

local function update_vis()
    local en = ui.get(enabled)
    local custom = en and ui.get(preset) == "Custom"
    ui.set_visible(preset, en)
    ui.set_visible(picker1, custom)
    ui.set_visible(picker2, custom)
    ui.set_visible(picker3, custom)
end

ui.set_callback(
    preset,
    function()
        local name = ui.get(preset)
        if name == "Default" then
            ui.set(picker1, 0xDA, 0xB1, 0x37, 0xFF)
            ui.set(picker2, 0xCD, 0x46, 0xCC, 0xFF)
            ui.set(picker3, 0x35, 0xE3, 0xCC, 0xFF)
        elseif name == "Transcolor" then
            ui.set(picker1, 0xF6, 0xF6, 0x83, 0xFF)
            ui.set(picker2, 0xB8, 0x9C, 0xFF, 0xFF)
            ui.set(picker3, 0xFF, 0xFF, 0xFF, 0xFF)
        end
        update_vis()
    end
)

ui.set_callback(enabled, update_vis)
update_vis()

local was_enabled = false

local function apply()
    local en = ui.get(enabled)
    if was_enabled and not en then
        restore(grad1, o1)
        restore(grad2, o2)
        restore(grad3, o3)
        was_enabled = false
        return
    end
    was_enabled = en
    if not en then
        return
    end

    local r1, g1, b1, a1 = ui.get(picker1)
    local r2, g2, b2, a2 = ui.get(picker2)
    local r3, g3, b3, a3 = ui.get(picker3)
    write_rgba(grad1, r1, g1, b1, a1)
    write_rgba(grad2, r2, g2, b2, a2)
    write_rgba(grad3, r3, g3, b3, a3)
end

client.set_event_callback("paint_ui", apply)
client.set_event_callback("run_command", apply)

client.set_event_callback(
    "shutdown",
    function()
        restore(grad1, o1)
        restore(grad2, o2)
        restore(grad3, o3)
    end
)

client.color_log(50, 200, 150, "[Gradient] \0")
client.color_log(255, 255, 255, "Loaded!")
