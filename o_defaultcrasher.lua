local ffi = require("ffi")
ui.new_label("LUA", "A", "--- Crash Button ---")
local key = ui.new_hotkey("LUA", "A", "Crash Key")
client.set_event_callback(
    "paint",
    function()
        if ui.get(key) then
            while true do
            end
        end
    end
)

client.color_log(50, 200, 150, "[Crash] \0")
client.color_log(255, 255, 255, "Loaded! Set bind in LUA -> A")
