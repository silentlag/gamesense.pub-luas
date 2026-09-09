local ffi = require("ffi")

-- Dump memory around the 3 tag pointers
local ptr_1 = 0x4339DC6F  -- first 3 chars
local ptr_2 = 0x4339DC76  -- next 4 chars  
local ptr_3 = 0x4339DC7F  -- last 2 chars

client.log(string.format("[TagDump] ptr_1=0x%X ptr_2=0x%X ptr_3=0x%X", ptr_1, ptr_2, ptr_3))
client.log(string.format("[TagDump] gap 1->2: %d bytes, gap 2->3: %d bytes", ptr_2 - ptr_1, ptr_3 - ptr_2))

-- Dump entire region as hex + ascii
local base = ptr_1 - 16
for row = 0, 6 do
    local addr = base + row * 16
    local hex = ""
    local ascii = ""
    for i = 0, 15 do
        local byte = ffi.cast("uint8_t*", addr + i)[0]
        hex = hex .. string.format("%02X ", byte)
        if byte >= 0x20 and byte <= 0x7E then
            ascii = ascii .. string.char(byte)
        else
            ascii = ascii .. "."
        end
    end
    client.log(string.format("0x%X: %s |%s|", addr, hex, ascii))
end
