local ffi = require("ffi")

ffi.cdef [[
    typedef void(__fastcall* clantag_t)(const char*, const char*);
]]

local send_clantag_ptr = client.find_signature("engine.dll", "\x53\x56\x57\x8B\xDA\x8B\xF9\xFF\x15")
local set_clantag = ffi.cast("clantag_t", send_clantag_ptr)

local separator = ui.new_label("MISC", "Miscellaneous", "--- Clantag Changer ---")
local ref_clantag_group = ui.new_checkbox("MISC", "Miscellaneous", "Enable Clantag Changer")
local ref_clantag = ui.new_textbox("MISC", "Miscellaneous", "Enter Clantag")
local ref_custom_sequence = ui.new_textbox("MISC", "Miscellaneous", "Custom Sequence (sep by |)")
local ref_animation =
    ui.new_combobox("MISC", "Miscellaneous", "Animation", {"Static", "Typing", "Blink", "Typing v2", "Custom"})
local ref_interval = ui.new_slider("MISC", "Miscellaneous", "Tag Change Interval", 100, 2000, 500, true, "ms")
local ref_static_on_end = ui.new_checkbox("MISC", "Miscellaneous", "Set static clantag on round end")

local function typing_animation(text)
    local frames = {}
    for i = 1, #text do
        table.insert(frames, text:sub(1, i))
    end
    return frames
end

local function typing_v2_animation(text)
    local frames = {}
    for i = 1, #text do
        table.insert(frames, text:sub(1, #text - i + 1))
    end
    table.insert(frames, "")
    for i = 1, #text do
        table.insert(frames, text:sub(1, i))
    end
    return frames
end

local function split_string(inputstr, sep)
    if sep == nil then
        sep = "%s"
    end
    local t = {}
    for str in string.gmatch(inputstr, "([^" .. sep .. "]+)") do
        table.insert(t, str)
    end
    return t
end

local function get_animation_frames(clantag, custom_seq, anim_type)
    if anim_type == "Static" then
        return {clantag}
    elseif anim_type == "Typing" then
        return typing_animation(clantag)
    elseif anim_type == "Blink" then
        return {clantag, ""}
    elseif anim_type == "Typing v2" then
        return typing_v2_animation(clantag)
    elseif anim_type == "Custom" then
        local frames = split_string(custom_seq, "|")
        return #frames > 0 and frames or {""}
    end
    return {""}
end

local tag_list = {""}
local index = 1
local last_update_time = 0
local last_clantag = ""
local last_custom_seq = ""
local last_anim_type = ""

local function handle_ui()
    local enabled = ui.get(ref_clantag_group)
    local anim_type = ui.get(ref_animation)
    ui.set_visible(ref_clantag, enabled and anim_type ~= "Custom")
    ui.set_visible(ref_custom_sequence, enabled and anim_type == "Custom")
    ui.set_visible(ref_animation, enabled)
    ui.set_visible(ref_interval, enabled)
    ui.set_visible(ref_static_on_end, enabled)
end

ui.set_callback(ref_clantag_group, handle_ui)
ui.set_callback(ref_animation, handle_ui)
handle_ui()

client.set_event_callback(
    "paint",
    function()
        if not ui.get(ref_clantag_group) then
            return
        end

        local clantag = ui.get(ref_clantag)
        local custom_seq = ui.get(ref_custom_sequence)
        local anim_type = ui.get(ref_animation)
        local interval = ui.get(ref_interval) / 1000

        if clantag ~= last_clantag or custom_seq ~= last_custom_seq or anim_type ~= last_anim_type then
            tag_list = get_animation_frames(clantag, custom_seq, anim_type)
            index = 1
            last_update_time = 0
            last_clantag = clantag
            last_custom_seq = custom_seq
            last_anim_type = anim_type
        end

        if globals.realtime() - last_update_time >= interval then
            local current_tag = tag_list[index] or ""
            set_clantag(current_tag, "")
            index = (index % #tag_list) + 1
            last_update_time = globals.realtime()
        end
    end
)

client.set_event_callback(
    "round_end",
    function()
        if ui.get(ref_clantag_group) and ui.get(ref_static_on_end) then
            local clantag = ui.get(ref_clantag)
            if clantag and clantag ~= "" then
                set_clantag(clantag, "")
            end
        end
    end
)
