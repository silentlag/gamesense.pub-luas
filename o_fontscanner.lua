local ffi = require("ffi")
local base = ffi.cast("int*", 0x43479930)
local ptr = base[0]
client.log(string.format("[FontScan] Base ptr: 0x%X", ptr))

-- Dump readable strings from the font structure
for off = 0, 0x300, 1 do
    local byte = ffi.cast("uint8_t*", ptr + off)[0]
    if byte >= 0x41 and byte <= 0x7A then
        local prev = off > 0 and ffi.cast("uint8_t*", ptr + off - 1)[0] or 0
        if prev == 0 or prev < 0x20 or prev > 0x7E then
            local ok, s = pcall(ffi.string, ffi.cast("char*", ptr + off))
            if ok and #s >= 3 and #s < 30 then
                client.log(string.format('  +0x%X: "%s"', off, s))
            end
        end
    end
end

client.log("[FontScan] Done!")
