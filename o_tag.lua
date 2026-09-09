local ffi = require("ffi")

local ptr_1 = ffi.cast("char*", 0x4339DC6F)
local ptr_2 = ffi.cast("char*", 0x4339DC76)
local ptr_3 = ffi.cast("char*", 0x4339DC7F)

local orig_1 = ffi.string(ptr_1, 3)
local orig_2 = ffi.string(ptr_2, 4)
local orig_3 = ffi.string(ptr_3, 4)

local MAX_LEN = 9

local function setstr(str)
    if #str > MAX_LEN then
        str = string.sub(str, 1, MAX_LEN)
        client.log("[Tag] Max " .. MAX_LEN .. " characters! Truncated to: " .. str)
    end

    local payload = str .. "] "
    while #payload < 11 do
        payload = payload .. "\0"
    end

    ffi.copy(ptr_1, payload:sub(1, 3), 3)
    ffi.copy(ptr_2, payload:sub(4, 7), 4)
    ffi.copy(ptr_3, payload:sub(8, 11), 4)
end

ui.new_label("LUA", "B", "Logs prefix (max 9 chars)")
local tbox = ui.new_textbox("LUA", "B", "Logs prefix")

ui.new_button(
    "LUA",
    "B",
    "Apply",
    function()
        setstr(ui.get(tbox))
    end
)

defer(
    function()
        ffi.copy(ptr_1, orig_1, 3)
        ffi.copy(ptr_2, orig_2, 4)
        ffi.copy(ptr_3, orig_3, 4)
    end
)
