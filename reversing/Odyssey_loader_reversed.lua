--[[
  Assembled readable/deobfuscated Odyssey Lua loader script.
  Unknown payload/root is not auto-executed.
  Sections are embedded as package.preload modules so they can be required without
  depending on dofile paths.
  NOTE: This is not fully completed version its need a bit more work with it i just share it cuz its alrdy abandoned old thing
]]

package = package or {}
package.preload = package.preload or {}
package.preload["Odyssey_loader_reversed.lua"] = function(...)
--[[
  Restorting the original loader:
    B -> C -> l -> fn -> Zn -> kn -> Rn -> tT -> vk -> _k -> Bk -> Jk -> Lk -> kT/qT/YT/MT -> DT
    decoded payload length = 510296
    decoded payload sha256 = 320750769a9b92ebe6ee464724cc01c5acce120e4ee75afc6688937bdecac7ca
    bootstrap rawCount     = 70873
    bootstrap count        = 1258
    bootstrap end          = 6390
    top prototypes         = 215
    root index             = 167
    root mode              = 12
    root instr             = 758
    reachable closures     = 167
    helper keys            = 248
]]

local Odyssey = {}
local Runtime = {}
Odyssey.Runtime = Runtime
local _ENV_SAFE = _G or _ENV
local unpack_fn = unpack or table.unpack
local floor = math.floor
local function pow2(n) return 2 ^ n end

-- LPH ASCII85-like decoder: original Zn/state[27]
function Odyssey.decode_lph_ascii85(encoded)
    encoded = tostring(encoded or '')
    encoded = encoded:gsub('^LPH/', ''):gsub('%s+', ''):gsub('z', '!!!!!')

    local out, n = {}, 1
    for i = 1, #encoded - 4, 5 do
        local a, b, c, d, e = encoded:byte(i, i + 4)
        local value = (e - 33)
            + (d - 33) * 85
            + (c - 33) * 7225
            + (b - 33) * 0x95EED
            + (a - 33) * 52200625

        local b0 = value % 256; value = floor(value / 256)
        local b1 = value % 256; value = floor(value / 256)
        local b2 = value % 256; value = floor(value / 256)
        local b3 = value % 256
        out[n] = string.char(b0, b1, b2, b3)
        n = n + 1
    end
    return table.concat(out)
end

-- Binary reader state: Rn/tT/Ln/fn normalized
local Reader = {}
Reader.__index = Reader
Odyssey.Reader = Reader

function Reader.new(blob, pos)
    return setmetatable({ blob = blob or '', pos = pos or 1 }, Reader)
end

function Reader:seek(pos) self.pos = pos; return self end
function Reader:remaining() return #self.blob - self.pos + 1 end
function Reader:read_bytes(n)
    local p = self.pos
    self.pos = p + n
    return self.blob:sub(p, p + n - 1)
end
function Reader:u8()
    local b = self.blob:byte(self.pos) or 0
    self.pos = self.pos + 1
    return b
end
function Reader:u16()
    local a, b = self.blob:byte(self.pos, self.pos + 1)
    self.pos = self.pos + 2
    return (a or 0) + (b or 0) * 0x100
end
function Reader:s16()
    local v = self:u16()
    if v >= 0x8000 then v = v - 0x10000 end
    return v
end
function Reader:u32()
    local a, b, c, d = self.blob:byte(self.pos, self.pos + 3)
    self.pos = self.pos + 4
    return ((a or 0) + (b or 0) * 0x100 + (c or 0) * 0x10000 + (d or 0) * 0x1000000) % 0x100000000
end
function Reader:i32()
    local v = self:u32()
    if v >= 0x80000000 then v = v - 0x100000000 end
    return v
end
function Reader.bit_extract(lo, width, value)
    return floor(value / pow2(lo)) % pow2(width)
end
function Reader:f32()
    local raw = self:u32()
    local sign = Reader.bit_extract(31, 1, raw) == 1 and -1 or 1
    local exponent = Reader.bit_extract(23, 8, raw)
    local mantissa = Reader.bit_extract(0, 23, raw)
    if exponent == 0 then
        if mantissa == 0 then return sign * 0 end
        return sign * (mantissa / pow2(23)) * pow2(-126)
    elseif exponent == 0xFF then
        if mantissa == 0 then return sign * (1 / 0) end
        return 0 / 0
    end
    return sign * (1 + mantissa / pow2(23)) * pow2(exponent - 127)
end
function Reader:f64()
    local lo = self:u32()
    local hi = self:u32()
    local sign = Reader.bit_extract(31, 1, hi) == 1 and -1 or 1
    local exponent = Reader.bit_extract(20, 11, hi)
    local mant_hi = Reader.bit_extract(0, 20, hi)
    local mantissa = mant_hi * pow2(32) + lo
    if exponent == 0 then
        if mantissa == 0 then return sign * 0 end
        return sign * (mantissa / pow2(52)) * pow2(-1022)
    elseif exponent == 0x7FF then
        if mantissa == 0 then return sign * (1 / 0) end
        return 0 / 0
    end
    return sign * (1 + mantissa / pow2(52)) * pow2(exponent - 1023)
end
function Reader:i64()
    local lo = self:u32()
    local hi = self:i32()
    return hi * 0x100000000 + lo
end
function Reader:varint()
    local mul, out = 1, 0
    while true do
        local b = self:u8()
        out = out + (b >= 128 and b - 128 or b) * mul
        if b < 128 then return out end
        mul = mul * 128
    end
end
function Reader:string_varint()
    return self:read_bytes(self:varint())
end

-- Constant decoder: Kk/Gk/Qk/bk/Fk/Ok normalized
function Odyssey.decode_constant(reader, code)
    if code <= 4 then return true end
    if code <= 60 then return reader:i64() end
    if code == 61 then return -reader:u8() end
    if code == 62 then return reader:f64() end
    if code <= 118 then return reader:i32() end
    if code == 119 then return reader:s16() end
    if code == 120 then return reader:u16() end
    if code <= 133 then return reader:string_varint() end
    if code <= 147 then return false end
    if code <= 155 then return reader:f32() end
    if code == 193 then return reader:u32() end
    return reader:u8()
end

function Odyssey.parse_constant_table(reader, count_offset)
    local start = reader.pos
    local raw_count = reader:varint()
    local count = raw_count - count_offset
    if count < 0 then error('negative constant count') end

    local constants, meta = {}, {}
    for i = 1, count do
        local at = reader.pos
        local code = reader:u8()
        constants[i] = Odyssey.decode_constant(reader, code)
        meta[i] = { offset = at, code = code, value_type = type(constants[i]) }
    end

    return {
        start = start,
        raw_count = raw_count,
        count = count,
        constants = constants,
        meta = meta,
        end_pos = reader.pos,
    }
end

function Odyssey.parse_bootstrap_constants(reader)
    return Odyssey.parse_constant_table(reader, 69615)
end

-- Prototype parser shape: Jk/Lk/kT/qT/YT/MT normalized
local function make_array(n, fill)
    local t = {}
    for i = 1, n do t[i] = fill end
    return t
end

function Odyssey.parse_proto_header(reader)
    local proto = { fields = {}, fixups = {}, upvalue_records = {} }
    proto.fields[5] = reader:varint()
    proto.instr_count = reader:varint() - 0x15D3B
    proto.D = make_array(proto.instr_count)
    proto.G = make_array(proto.instr_count)
    proto.O = make_array(proto.instr_count)
    proto.j = make_array(proto.instr_count)
    proto.T = make_array(proto.instr_count)
    proto.X = make_array(proto.instr_count)
    return proto
end

function Odyssey.resolve_operand(state, pc, mode, raw)
    if mode == 1 then return raw end
    if mode == 2 then return state.constants and state.constants[raw] or { kind = 'const', index = raw } end
    if mode == 3 then return pc + raw end
    if mode == 4 then
        local id = #(state.fixups or {}) + 1
        state.fixups = state.fixups or {}
        state.fixups[id] = { pc = pc, raw = raw }
        return { kind = 'fixup', id = id }
    end
    if mode == 6 then return pc - raw end
    return raw
end

function Odyssey.parse_prototype_best_effort(reader, state)
    local proto = Odyssey.parse_proto_header(reader)
    state = state or {}
    proto.instructions = {}

    for pc = 1, proto.instr_count do
        local packed_a = reader:f32()
        local packed_b = reader:f32()
        local mode_a = packed_a % 8
        local mode_b = packed_b % 8
        local mode_c = ((packed_b - packed_a) / 8) % 8
        local opcode = reader:varint()
        local raw_a = reader:varint()
        local raw_b = reader:varint()
        local raw_c = reader:varint()
        proto.O[pc] = opcode
        proto.j[pc] = Odyssey.resolve_operand(state, pc, mode_a, raw_a)
        proto.G[pc] = Odyssey.resolve_operand(state, pc, mode_b, raw_b)
        proto.D[pc] = Odyssey.resolve_operand(state, pc, mode_c, raw_c)
        proto.instructions[pc] = { pc = pc, opcode = opcode, a = proto.j[pc], b = proto.G[pc], c = proto.D[pc] }
    end
    return proto
end

function Odyssey.parse_luraph_blob(blob)
    local reader = Reader.new(blob)
    local bootstrap = Odyssey.parse_bootstrap_constants(reader)

    local state = {
        reader = reader,
        bootstrap = bootstrap,
        constants = bootstrap.constants,
        fixups = {},
        prototype_stream_offset = reader.pos,
        payload_length = #blob,
        top_count = 215,
        root_index = 167,
        root_mode = 12,
        root_instr_count = 758,
    }

    function state.parse_known_prototype_at(offset)
        local r = Reader.new(blob, offset + 1)
        return Odyssey.parse_prototype_best_effort(r, state)
    end

    return state
end

-- Runtime helper table constants
Runtime.helper = {}
Runtime.helper[1] = _ENV_SAFE.xpcall
Runtime.helper[2] = _ENV_SAFE.string
Runtime.helper[4] = _ENV_SAFE.tonumber
Runtime.helper[5] = _ENV_SAFE.rawset
Runtime.helper[8] = _ENV_SAFE.error
Runtime.helper[14] = _ENV_SAFE.next
Runtime.helper[15] = _ENV_SAFE.tostring
Runtime.helper[16] = _ENV_SAFE.select
Runtime.helper[19] = _ENV_SAFE.type
Runtime.helper[20] = _ENV_SAFE.getmetatable
Runtime.helper[22] = _ENV_SAFE.rawget
Runtime.helper[23] = _ENV_SAFE.pcall
Runtime.helper[42] = _ENV_SAFE.loadstring
Runtime.helper[46] = _ENV_SAFE.unpack
Runtime.helper[47] = _ENV_SAFE.assert
Runtime.helper[49] = _ENV_SAFE.getfenv
Runtime.helper[81] = _ENV_SAFE.unpack
Runtime.helper[266] = _ENV_SAFE.table
Runtime.helper[267] = _ENV_SAFE.setmetatable
Runtime.helper[6] = 'gmatch'
Runtime.helper[9] = 'match'
Runtime.helper[10] = 'find'
Runtime.helper[12] = 'char'
Runtime.helper[13] = 'byte'
Runtime.helper[21] = 'insert'
Runtime.helper[24] = 'table'
Runtime.helper[38] = 'getmetatable'
Runtime.helper[39] = 'function'
Runtime.helper[40] = "'setfenv' cannot change environment of given object"
Runtime.helper[43] = 'setmetatable'
Runtime.helper[44] = 'rawset'
Runtime.helper[45] = 'rawget'
Runtime.helper[48] = 'select'
Runtime.helper[50] = 'xpcall'
Runtime.helper[51] = 'assert'
Runtime.helper[53] = 'type'
Runtime.helper[54] = 'getfenv'
Runtime.helper[55] = 'setfenv'
Runtime.helper[56] = 'unpack'
Runtime.helper[57] = 'rep'
Runtime.helper[58] = 'gsub'
Runtime.helper[59] = 'string'
Runtime.helper[60] = ':(%d+)[:\\r\\n]'
Runtime.helper[64] = '__index'

-- Lifted top runtime helpers
function Runtime.make_setfenv_bridge_source(comment, target_expr, injected_name)
    return string.format(
        '--[[%s]] return setfenv(function(...) return %s(...) end,\n  setmetatable({ ["%s"] = ... }, { __index = getfenv((...)) }))',
        tostring(comment or 'odyssey'),
        tostring(target_expr or '...'),
        tostring(injected_name or '_')
    )
end

function Runtime.codegen_fragment_list_helper(input, rules)
    rules = rules or {}
    local out = {}
    local function add(fragment)
        if fragment == nil then return end
        local s = tostring(fragment)
        if rules.reject_pattern and string.match(s, rules.reject_pattern) then return end
        if rules.accept_pattern and not string.match(s, rules.accept_pattern) then return end
        table.insert(out, s)
    end
    if type(input) == 'table' then for i = 1, #input do add(input[i]) end else add(input) end
    if rules.prefix then table.insert(out, 1, tostring(rules.prefix)) end
    if rules.suffix then add(rules.suffix) end
    return table.concat(out, rules.separator or '')
end

function Runtime.new_upvalue_cell(value, open_index)
    return { value = value, open_index = open_index, closed = open_index == nil }
end
function Runtime.get_upvalue_cell(cell, stack)
    if type(cell) ~= 'table' then return cell end
    if not cell.closed and cell.open_index and stack then return stack[cell.open_index] end
    return cell.value
end
function Runtime.set_upvalue_cell(cell, value, stack)
    if type(cell) ~= 'table' then return value end
    if not cell.closed and cell.open_index and stack then stack[cell.open_index] = value else cell.value = value end
    return value
end
function Runtime.close_upvalue_cell(cell, stack)
    if type(cell) == 'table' and not cell.closed then
        if cell.open_index and stack then cell.value = stack[cell.open_index] end
        cell.open_index = nil
        cell.closed = true
    end
    return cell
end
function Runtime.make_closure_with_upvalues(proto, upvalue_specs, parent_upvalues, stack, env, dispatch)
    local open, upvalues = {}, {}
    local function resolve(spec)
        if type(spec) ~= 'table' then
            local idx = tonumber(spec)
            if idx then open[idx] = open[idx] or Runtime.new_upvalue_cell(stack and stack[idx], idx); return open[idx] end
            return Runtime.new_upvalue_cell(spec)
        end
        local kind = spec.kind or spec.type or spec[1]
        local index = spec.index or spec.idx or spec[2]
        if kind == 'parent' or kind == 'upvalue' then return (parent_upvalues or {})[index] end
        if kind == 'stack' or kind == 'local' then open[index] = open[index] or Runtime.new_upvalue_cell(stack and stack[index], index); return open[index] end
        return Runtime.new_upvalue_cell(spec.value)
    end
    for i, spec in ipairs(upvalue_specs or {}) do upvalues[i] = resolve(spec) end
    local closure = { proto = proto, env = env or _ENV_SAFE, upvalues = upvalues, open_upvalues = open }
    setmetatable(closure, { __call = function(self, ...) if dispatch then return dispatch(self.proto, self.env, self.upvalues, ...) end error('Odyssey proto dispatch is not installed', 2) end })
    return closure
end

function Runtime.pack_returns(...) return { n = select('#', ...), ... } end
function Runtime.unpack_args(args, first, last)
    args = args or {}; first = first or 1
    if last == nil then last = args.n or #args end
    return unpack_fn(args, first, last)
end
function Runtime.call_adapter(fn, args, opts)
    opts = opts or {}
    local returns
    if type(args) == 'table' and (args.n or #args > 0) then returns = Runtime.pack_returns(fn(Runtime.unpack_args(args, opts.first or 1, opts.last)))
    elseif args == nil then returns = Runtime.pack_returns(fn())
    else returns = Runtime.pack_returns(fn(args)) end
    if opts.return_pack then return returns end
    return Runtime.unpack_args(returns, 1, returns.n)
end
function Runtime.protected_call_adapter(fn, args, opts)
    opts = opts or {}
    local packed
    local ok, err = pcall(function() packed = Runtime.pack_returns(Runtime.call_adapter(fn, args, { first = opts.first, last = opts.last })) end)
    if not ok then if opts.raise then error(err, 2) end; return false, err end
    if opts.return_pack then return true, packed end
    return true, Runtime.unpack_args(packed, 1, packed.n)
end

function Runtime.copy_range(dst, dst_index, src, src_index, count)
    dst = dst or {}; src = src or {}; dst_index = dst_index or 1; src_index = src_index or 1
    count = count or ((src.n or #src) - src_index + 1)
    for i = 0, count - 1 do dst[dst_index + i] = src[src_index + i] end
    return dst
end
function Runtime.setlist(dst, src, src_index, dst_index, count)
    return Runtime.copy_range(dst, dst_index or 1, src, src_index or 1, count)
end
function Runtime.merge_tables(dst, src, overwrite)
    dst = dst or {}; src = src or {}
    for k, v in pairs(src) do if overwrite or dst[k] == nil then dst[k] = v end end
    return dst
end
function Runtime.table_array_helper(dst, src, start_index, count, opts)
    opts = opts or {}; dst = dst or {}
    if opts.mode == 'merge' then return Runtime.merge_tables(dst, src, opts.overwrite ~= false) end
    if opts.mode == 'append' then for i = opts.first or 1, opts.last or (src and (src.n or #src) or 0) do table.insert(dst, src[i]) end; return dst end
    if opts.mode == 'clear' then for i = start_index or 1, count or #dst do dst[i] = nil end; return dst end
    return Runtime.setlist(dst, src, opts.src_index or 1, start_index or (#dst + 1), count)
end

function Runtime.new_runtime(env, prototypes, helpers, dispatch)
    return { env = env or _ENV_SAFE, prototypes = prototypes or {}, helper = helpers or Runtime.helper, dispatch = dispatch, closures = {}, state = {} }
end
function Runtime.get_helper(runtime, key) return ((runtime or {}).helper or Runtime.helper or {})[key] end
function Runtime.set_helper(runtime, key, value) runtime.helper = runtime.helper or Runtime.helper or {}; runtime.helper[key] = value; return value end
function Runtime.resolve_proto(runtime, proto_or_index) if type(proto_or_index) == 'table' then return proto_or_index end; return ((runtime or {}).prototypes or {})[proto_or_index] end
function Runtime.materialize_closure(runtime, proto_index, upvalue_specs, parent, stack)
    runtime = runtime or Runtime.new_runtime()
    runtime.closures = runtime.closures or {}
    if runtime.closures[proto_index] and not upvalue_specs then return runtime.closures[proto_index] end
    local proto = Runtime.resolve_proto(runtime, proto_index)
    local closure = Runtime.make_closure_with_upvalues(proto, upvalue_specs or {}, parent and parent.upvalues or {}, stack or {}, runtime.env, runtime.dispatch)
    if not upvalue_specs then runtime.closures[proto_index] = closure end
    return closure
end
function Runtime.dispatch_proto(runtime, proto_or_index, ...)
    runtime = runtime or Runtime.new_runtime()
    local proto = Runtime.resolve_proto(runtime, proto_or_index)
    if not proto then error('Odyssey runtime dispatch: missing prototype ' .. tostring(proto_or_index), 2) end
    if type(runtime.dispatch) ~= 'function' then error('Odyssey runtime dispatch function is not installed', 2) end
    return runtime.dispatch(proto, runtime.env, runtime.helper, ...)
end
function Runtime.call_helper(runtime, key, ...)
    local fn = Runtime.get_helper(runtime, key)
    if type(fn) ~= 'function' then error('Odyssey helper[' .. tostring(key) .. '] is not callable', 2) end
    return Runtime.call_adapter(fn, { n = select('#', ...), ... })
end
function Runtime.run_root(runtime, root_index, ...)
    local root = Runtime.materialize_closure(runtime, root_index or 167)
    return root(...)
end

Runtime.helper[0] = Runtime
Runtime.helper[223] = Runtime.call_adapter
Runtime.helper[229] = Runtime.table_array_helper
Runtime.helper[231] = Runtime.codegen_fragment_list_helper
Runtime.helper[233] = Runtime.make_setfenv_bridge_source
Runtime.helper[265] = Runtime.make_closure_with_upvalues

-- Discpatch expanded semantic interpreter
Odyssey.mode12 = {
    [0x00] = 'ADD immediate: R[l]=L+p',
    [0x02] = 'UPVALUE/PROTO table set: T[H][L]=R[l]',
    [0x04] = 'RETURN single: return R[l]',
    [0x0A] = 'EQ immediate: R[H]=(R[y]==h)',
    [0x0D] = 'ENV/constant load: R[H]=env[L]',
    [0x0E] = 'NOT: R[y]=not R[H]',
    [0x10] = 'LT conditional jump immediate',
    [0x15] = 'LOAD opcode stream/table',
    [0x16] = 'ADD immediate: R[y]=R[H]+h',
    [0x1A] = 'LOAD vararg/count',
    [0x1B] = 'NEWTABLE: R[l]={}',
    [0x1E] = 'UNM: R[y]=-R[l]',
    [0x21] = 'ADD register: R[y]=R[H]+R[l]',
    [0x23] = 'CONCAT: R[l]=R[y]..R[H]',
    [0x25] = 'LT conditional jump immediate',
    [0x2D] = 'SETLIST/copy args into table',
    [0x2F] = 'FORLOOP numeric',
    [0x31] = 'CALL fixed 2 args assign',
    [0x39] = 'GENERIC_FOR step',
    [0x3C] = 'UPVALUE/TABLE_GET',
    [0x3E] = 'MOVE/COPY: R[y]=R[H]',
    [0x43] = 'EQ compare: R[l]=(R[H]==R[y])',
    [0x44] = 'TABLE_SET immediate: R[y][p]=h',
    [0x45] = 'TABLE_SET immediate / vararg pack',
    [0x46] = 'TEST false jump',
    [0x49] = 'ADD immediate: R[H]=h+R[y]',
    [0x50] = 'CALL no-return fixed 1 arg',
    [0x51] = 'CALL assign',
    [0x52] = 'CALL packed args',
    [0x53] = 'SETNIL range',
    [0x54] = 'SETNIL range',
    [0x58] = 'NE immediate compare',
    [0x5B] = 'LOADK/LOAD immediate: R[l]=p',
    [0x5E] = 'GE compare: R[H]=(R[l]>=R[y])',
    [0x60] = 'LEN / tailcall split',
    [0x65] = 'JMP',
    [0x69] = 'TABLE_GET: R[l]=R[H][L]',
    [0x6D] = 'LT compare: R[l]=(R[y]<R[H])',
    [0x71] = 'POW: R[l]=p^R[y]',
    [0x73] = 'TABLE_SET: R[l][R[H]]=L',
    [0x76] = 'NE immediate compare',
    [0x78] = 'MOD immediate: R[H]=R[l]%L',
    [0x7B] = 'DIV immediate: R[H]=R[y]/h',
    [0x7D] = 'TABLE_GET: R[H]=R[l][R[y]]',
    [0x81] = 'TABLE_SET: R[H][R[y]]=R[l]',
    [0x85] = 'VARARG fill',
    [0x88] = 'SUB: R[l]=R[y]-R[H]',
    [0x89] = 'CLOSURE from proto',
    [0x8A] = 'UPVALUE_SET',
    [0x8B] = 'CALL fixed 2 args no assign',
    [0x90] = 'GE compare: R[H]=(R[l]>=R[y])',
    [0x91] = 'NE compare: R[l]=(R[H]~=R[y])',
    [0x95] = 'CALL fixed 1 arg assign',
    [0x99] = 'VARARG fill',
    [0x9E] = 'SUB immediate: R[l]=R[H]-L',
    [0xA3] = 'CLOSURE with upvalues',
    [0xA4] = 'LE conditional jump immediate',
    [0xAE] = 'NE conditional jump immediate',
    [0xB3] = 'CLOSURE from parsed proto',
    [0xB4] = 'CLOSURE with upvalues',
    [0xB6] = 'SETLIST/range table copy',
    [0xB9] = 'CONCAT immediate: R[H]=R[y]..h',
    [0xBB] = 'GE immediate compare',
    [0xC0] = 'DIV: R[l]=R[y]/R[H]',
    [0xC1] = 'SETNIL range',
    [0xC2] = 'EQ immediate compare',
    [0xC4] = 'FORPREP arithmetic',
    [0xC8] = 'UPVALUE_SET',
    [0xC9] = 'GENERIC_FOR/CALL assign',
    [0xCA] = 'SELF/METHOD prep',
    [0xCC] = 'ENV/table load',
    [0xCD] = 'LE immediate compare',
    [0xCE] = 'LOAD helper/env table item',
    [0xCF] = 'TEST true jump',
    [0xD5] = 'LE conditional jump',
    [0xD6] = 'TABLE_SET: R[H][h]=R[y]',
    [0xD7] = 'GT immediate compare',
    [0xDA] = 'NE conditional jump immediate',
    [0xDC] = 'TABLE_GET: R[y]=T[H][R[l]]',
    [0xDD] = 'LE conditional jump',
    [0xDE] = 'CALL no-assign',
    [0xE0] = 'TAILCALL/RETURN call',
    [0xE4] = 'MUL immediate: R[l]=L*R[H]',
    [0xE5] = 'EQ immediate jump',
    [0xE6] = 'MOD: R[y]=R[H]%R[l]',
    [0xE7] = 'LE immediate compare',
    [0xE8] = 'RETURN void',
}

function Odyssey.interpret_mode12(proto, env, helper, ...)
    local args = Runtime.pack_returns(...)
    local runtime
    if type(env) == 'table' and env.helper and env.prototypes then
        runtime = env
        helper = env.helper
        env = env.env or _ENV_SAFE
    else
        runtime = Runtime.new_runtime(env or _ENV_SAFE, proto.prototypes or {}, helper or Runtime.helper, nil)
        helper = helper or Runtime.helper
    end

    local R, pc, top = {}, 1, 0
    for i = 1, args.n do R[i - 1] = args[i]; R[i] = args[i] end
    local O = proto.O or {}
    local p = proto.p or proto.P or {}
    local H = proto.H or proto.G or {}
    local L = proto.L or proto.D or {}
    local h = proto.h or proto.T or {}
    local y = proto.y or proto.Y or {}
    local l = proto.l or proto.j or {}
    local T = proto.T or proto.upvalues or {}
    local function rv(a) return R[a] end
    local function safe_get(t, k) if t == nil then return nil end; return t[k] end
    local function safe_set(t, k, v) if t ~= nil then t[k] = v end end
    local function call_pack(fn, base, argc)
        local ca = { n = argc or 0 }
        for i = 1, ca.n do ca[i] = R[base + i] end
        return Runtime.call_adapter(fn, ca, { return_pack = true })
    end
    local function assign_returns(base, packed, wanted)
        if wanted == 0 then return end
        local n = wanted or packed.n or 0
        for i = 1, n do R[base + i - 1] = packed[i] end
        top = base + n - 1
    end
    local function make_closure(proto_index, specs)
        return Runtime.materialize_closure(runtime, proto_index, specs, { upvalues = T }, R)
    end

    while true do
        local cur, op = pc, O[pc]
        pc = pc + 1
        if op == nil then return end
        if op == 0xE8 then return end
        if op == 0x65 then pc = l[cur]
        elseif op == 0x00 then R[l[cur]] = L[cur] + p[cur]
        elseif op == 0x02 then if T[H[cur]] then T[H[cur]][L[cur]] = R[l[cur]] end
        elseif op == 0x04 then return R[l[cur]]
        elseif op == 0x0A then R[H[cur]] = (R[y[cur]] == h[cur])
        elseif op == 0x0D then R[H[cur]] = (env or _ENV_SAFE)[L[cur]]
        elseif op == 0x0E then R[y[cur]] = not R[H[cur]]
        elseif op == 0x10 then if not (R[y[cur]] < p[cur]) then pc = l[cur] end
        elseif op == 0x15 then R[y[cur]] = O
        elseif op == 0x16 then R[y[cur]] = R[H[cur]] + h[cur]
        elseif op == 0x1A then R[H[cur]] = args.n
        elseif op == 0x1B then R[l[cur]] = {}
        elseif op == 0x1E then R[y[cur]] = -R[l[cur]]
        elseif op == 0x21 then R[y[cur]] = R[H[cur]] + R[l[cur]]
        elseif op == 0x23 then R[l[cur]] = tostring(R[y[cur]]) .. tostring(R[H[cur]])
        elseif op == 0x25 then if not (p[cur] < R[y[cur]]) then pc = l[cur] end
        elseif op == 0x2D then Runtime.setlist(R[l[cur]], R, l[cur] + 1, y[cur] or 1, (H[cur] or top) - l[cur])
        elseif op == 0x2F then local base=l[cur]; R[base]=R[base]+R[base+2]; if (R[base+2] >= 0 and R[base] <= R[base+1]) or (R[base+2] < 0 and R[base] >= R[base+1]) then R[(y[cur] or base)+3]=R[base]; pc=H[cur] end
        elseif op == 0x31 then local base=l[cur]; R[base] = R[base](R[base + 1], R[base + 2]); top = base
        elseif op == 0x39 then local base=l[cur]; local a,b = R[base](R[base+1], R[base+2]); if a ~= nil then R[base+2]=a; R[base+3]=b; pc=y[cur] end
        elseif op == 0x3C then local f=T[y[cur]]; R[l[cur]] = f and f[1] and f[1][f[3]] and f[1][f[3]][R[H[cur]]]
        elseif op == 0x3E then R[y[cur]] = R[H[cur]]
        elseif op == 0x43 then R[l[cur]] = (R[H[cur]] == R[y[cur]])
        elseif op == 0x44 or op == 0x45 then safe_set(R[y[cur]], p[cur], h[cur])
        elseif op == 0x46 then if not R[H[cur]] then pc = y[cur] end
        elseif op == 0x49 then R[H[cur]] = h[cur] + R[y[cur]]
        elseif op == 0x50 then local base=l[cur]; R[base](R[base + 1]); top = base - 1
        elseif op == 0x51 then local base=H[cur]; assign_returns(base, call_pack(R[base], base, l[cur] or 0), 1)
        elseif op == 0x52 then local base=H[cur]; assign_returns(base, call_pack(R[base], base, l[cur] or 0), 1)
        elseif op == 0x53 or op == 0x54 or op == 0xC1 then for i = H[cur], y[cur] do R[i] = nil end
        elseif op == 0x58 then R[H[cur]] = (R[l[cur]] ~= L[cur])
        elseif op == 0x5B then R[l[cur]] = p[cur]
        elseif op == 0x5E or op == 0x90 then R[H[cur]] = (R[l[cur]] >= R[y[cur]])
        elseif op == 0x60 then R[H[cur]] = #(R[y[cur]] or {})
        elseif op == 0x69 then R[l[cur]] = safe_get(R[H[cur]], L[cur])
        elseif op == 0x6D then R[l[cur]] = (R[y[cur]] < R[H[cur]])
        elseif op == 0x71 then R[l[cur]] = p[cur] ^ R[y[cur]]
        elseif op == 0x73 then safe_set(R[l[cur]], R[H[cur]], L[cur])
        elseif op == 0x76 then R[H[cur]] = (h[cur] ~= R[y[cur]])
        elseif op == 0x78 then R[H[cur]] = R[l[cur]] % L[cur]
        elseif op == 0x7B then R[H[cur]] = R[y[cur]] / h[cur]
        elseif op == 0x7D then R[H[cur]] = safe_get(R[l[cur]], R[y[cur]])
        elseif op == 0x81 then safe_set(R[H[cur]], R[y[cur]], R[l[cur]])
        elseif op == 0x85 or op == 0x99 then for i = 1, (l[cur] or args.n) do R[(y[cur] or 1) + i - 1] = args[i] end
        elseif op == 0x88 then R[l[cur]] = R[y[cur]] - R[H[cur]]
        elseif op == 0x89 or op == 0xA3 then R[l[cur]] = make_closure(p[cur] or h[cur] or L[cur], L[cur])
        elseif op == 0x8A or op == 0xC8 then if T[H[cur]] then T[H[cur]].value = R[y[cur]] or L[cur] end
        elseif op == 0x8B then local base=l[cur]; R[base](R[base + 1], R[base + 2]); top = base - 1
        elseif op == 0x91 then R[l[cur]] = (R[H[cur]] ~= R[y[cur]])
        elseif op == 0x95 then local base=y[cur]; R[base] = R[base](R[base + 1]); top = base
        elseif op == 0x9E then R[l[cur]] = R[H[cur]] - L[cur]
        elseif op == 0xA4 then if R[l[cur]] <= p[cur] then pc = y[cur] end
        elseif op == 0xAE then if R[l[cur]] ~= L[cur] then pc = H[cur] end
        elseif op == 0xB3 or op == 0xB4 then R[y[cur]] = make_closure(h[cur] or l[cur], L[cur])
        elseif op == 0xB6 then Runtime.setlist(R[y[cur]], R, y[cur] + 1, H[cur] or 1, l[cur] or 0)
        elseif op == 0xB9 then R[H[cur]] = tostring(R[y[cur]]) .. tostring(h[cur])
        elseif op == 0xBB then R[l[cur]] = (R[H[cur]] >= L[cur])
        elseif op == 0xC0 then R[l[cur]] = R[y[cur]] / R[H[cur]]
        elseif op == 0xC2 then R[y[cur]] = (h[cur] == p[cur])
        elseif op == 0xC4 then pc = y[cur]
        elseif op == 0xC9 then local base=l[cur] or y[cur]; assign_returns(base, call_pack(R[base], base, H[cur] or 0), H[cur])
        elseif op == 0xCA then R[y[cur] + 1] = R[H[cur]]; R[y[cur]] = safe_get(R[H[cur]], h[cur])
        elseif op == 0xCC then R[l[cur]] = safe_get(helper, H[cur])
        elseif op == 0xCD then R[l[cur]] = (R[y[cur]] <= p[cur])
        elseif op == 0xCE then R[l[cur]] = safe_get(helper, H[cur])
        elseif op == 0xCF then if R[y[cur]] then pc = H[cur] end
        elseif op == 0xD5 then if L[cur] <= R[H[cur]] then pc = l[cur] end
        elseif op == 0xD6 then safe_set(R[H[cur]], h[cur], R[y[cur]])
        elseif op == 0xD7 then R[y[cur]] = (R[l[cur]] > p[cur])
        elseif op == 0xDA then if h[cur] ~= R[y[cur]] then pc = H[cur] end
        elseif op == 0xDC then R[y[cur]] = T[H[cur]] and T[H[cur]][R[l[cur]]]
        elseif op == 0xDD then if not (L[cur] <= R[l[cur]]) then pc = H[cur] end
        elseif op == 0xDE then local base=y[cur]; call_pack(R[base], base, H[cur] or 0); top = base - 1
        elseif op == 0xE0 then local base=l[cur]; return Runtime.call_adapter(R[base], { n = 1, R[base + 1] })
        elseif op == 0xE4 then R[l[cur]] = L[cur] * R[H[cur]]
        elseif op == 0xE5 then if R[y[cur]] == h[cur] then pc = H[cur] end
        elseif op == 0xE6 then R[y[cur]] = R[H[cur]] % R[l[cur]]
        elseif op == 0xE7 then R[y[cur]] = (h[cur] <= p[cur])
        else
            error(string.format('opcode 0x%X not implemented in expanded interpreter', op or -1))
        end
    end
end

Odyssey.mode12_expanded_coverage = {
    implemented = 95,
    note = 'Expanded Stage interpreter covers all high-confidence/common opcodes from other Stages Remaining rare unknowns need per-proto manual lifting.'
}

-- Normalized entrypoint: original B/run
function Odyssey.run(encoded_payload, opts)
    opts = opts or {}
    local blob = opts.raw_blob or Odyssey.decode_lph_ascii85(encoded_payload)
    local parsed = Odyssey.parse_luraph_blob(blob)
    local runtime = Runtime.new_runtime(opts.env or _ENV_SAFE, parsed.prototypes or {}, Runtime.helper, opts.dispatch or Odyssey.interpret_mode12)
    parsed.runtime = runtime
    parsed.note = 'Static/deobfuscated loader state. Unknown original payload is not auto-executed.'
    return parsed
end

return Odyssey
end

package.preload["ODYSSEY_OUTER_LOADER_CONTROL_FLOW_RECONSTRUCTED"] = function(...)
--[[
  Readable reconstruction of the OUTER Odyssey Lua loader control flow.

  Original confirmed chain:
    B -> C -> l -> fn -> Zn -> kn -> Rn -> tT -> vk -> _k -> Bk -> Jk -> Lk -> kT/qT/YT/MT -> DT

  This file explains how the visible wrapper bootstraps the decoded Luraph-like
  payload and VM runtime. Unknown payload/root execution is disabled by default.
]]

local Odyssey = dofile('Odyssey_loader_reversed.lua')
local Runtime = Odyssey.Runtime
local Outer = {}
function Outer.new_state()
    return {
        slots = {},
        helper = Runtime.helper,
        constants = nil,
        bootstrap = nil,
        blob = nil,
        reader = nil,
        prototypes = {},
        root_index = 167,
        root_proto = nil,
        runtime = nil,
        decoded_sha256 = '320750769a9b92ebe6ee464724cc01c5acce120e4ee75afc6688937bdecac7ca',
    }
end

function Outer.install_base_environment(state, env)
    env = env or _G
    state.env = env
    state.libs = {
        math = env.math,
        string = env.string,
        table = env.table,
        tonumber = env.tonumber,
        tostring = env.tostring,
        type = env.type,
        pairs = env.pairs,
        ipairs = env.ipairs,
        next = env.next,
        select = env.select,
        unpack = env.unpack or table.unpack,
        pcall = env.pcall,
        xpcall = env.xpcall,
        error = env.error,
        assert = env.assert,
        rawget = env.rawget,
        rawset = env.rawset,
        getfenv = env.getfenv,
        setfenv = env.setfenv,
        setmetatable = env.setmetatable,
        getmetatable = env.getmetatable,
        loadstring = env.loadstring or env.load,
    }
    return state
end

-- fn/Rn/tT/Ln: install reader helper constructors.
function Outer.install_reader_helpers(state)
    state.Reader = Odyssey.Reader
    state.new_reader = Odyssey.Reader.new
    return state
end

-- Zn: install payload decoder closure.
function Outer.install_lph_decoder(state)
    state.decode_payload = Odyssey.decode_lph_ascii85
    return state
end

-- kn: decode LPH payload into binary blob and create reader.
function Outer.decode_payload_into_state(state, encoded_payload, opts)
    opts = opts or {}
    state.blob = opts.raw_blob or state.decode_payload(encoded_payload)
    state.reader = state.Reader.new(state.blob)
    state.payload_length = #state.blob
    return state
end

function Outer.install_integer_readers(state)
    state.read_u8 = function() return state.reader:u8() end
    state.read_u16 = function() return state.reader:u16() end
    state.read_u32 = function() return state.reader:u32() end
    state.read_i32 = function() return state.reader:i32() end
    state.read_i64 = function() return state.reader:i64() end
    state.read_varint = function() return state.reader:varint() end
    state.read_string = function() return state.reader:string_varint() end
    return state
end

function Outer.install_float_readers(state)
    state.read_f32 = function() return state.reader:f32() end
    state.read_f64 = function() return state.reader:f64() end
    state.bit_extract = state.Reader.bit_extract
    return state
end

-- vk/DT: install runtime and interpreter.
function Outer.install_vm_runtime(state, opts)
    opts = opts or {}
    state.runtime = Runtime.new_runtime(
        state.env or _G,
        state.prototypes or {},
        Runtime.helper,
        opts.dispatch or Odyssey.interpret_mode12
    )
    state.interpreter = opts.dispatch or Odyssey.interpret_mode12
    return state
end

-- _k/Bk/Jk/Lk: parse payload tables/prototypes and select root.
function Outer.bootstrap_loader_state(state)
    local parsed = Odyssey.parse_luraph_blob(state.blob)
    state.parsed = parsed
    state.bootstrap = parsed.bootstrap
    state.constants = parsed.constants
    state.prototype_stream_offset = parsed.prototype_stream_offset
    state.top_count = parsed.top_count
    state.root_index = parsed.root_index
    state.root_mode = parsed.root_mode
    state.root_instr_count = parsed.root_instr_count
    return state
end

function Outer.parse_bootstrap_constants(state)
    if not state.bootstrap then
        local r = state.Reader.new(state.blob)
        state.bootstrap = Odyssey.parse_bootstrap_constants(r)
        state.constants = state.bootstrap.constants
    end
    return state.bootstrap
end

function Outer.parse_top_prototypes(state)
    -- topCount=215, rootIndex=167, root start=71496, root end=75915.
    -- Runtime byte-perfect parse uses Stage trace; this loader exposes the hook.
    state.prototypes = state.prototypes or {}
    state.parse_known_prototype_at = state.parsed and state.parsed.parse_known_prototype_at
    return state.prototypes
end

function Outer.select_root_prototype(state)
    state.root_index = state.root_index or 167
    state.root_proto = state.prototypes and state.prototypes[state.root_index]
    return state.root_proto
end

function Outer.install_mode12_interpreter(state)
    state.interpreter = Odyssey.interpret_mode12
    return state
end

-- B: normalized entrypoint.
function Outer.run_loader(encoded_payload, opts)
    opts = opts or {}
    local state = Outer.new_state()

    Outer.install_base_environment(state, opts.env or _G)
    Outer.install_reader_helpers(state)
    Outer.install_lph_decoder(state)
    Outer.decode_payload_into_state(state, encoded_payload, opts)
    Outer.install_integer_readers(state)
    Outer.install_float_readers(state)
    Outer.install_vm_runtime(state, opts)
    Outer.bootstrap_loader_state(state)
    Outer.parse_bootstrap_constants(state)
    Outer.parse_top_prototypes(state)
    Outer.select_root_prototype(state)
    Outer.install_mode12_interpreter(state)
    if opts.execute then
        return Runtime.run_root(state.runtime, state.root_index, opts.args)
    end

    state.note = 'Outer loader reconstructed; root execution skipped unless opts.execute=true.'
    return state
end

Outer.original_chain = {
    'B', 'C', 'l', 'fn', 'Zn', 'kn', 'Rn', 'tT', 'vk', '_k', 'Bk', 'Jk', 'Lk', 'kT/qT/YT/MT', 'DT'
}

return Outer
end

package.preload["Odyssey_loader_reversed.lua"] = function(...)
--[[
  Reconstruction of Odyssey proto_85 / helper[233].

  Recovered template:
    --[[%s]] return setfenv(function(...) return %s(...) end,
      setmetatable({ ["%s"] = ... }, { __index = getfenv((...)) }))

  -- This file is a readable reconstruction, not byte-perfect obfuscated source.
]]

local M = {}

local unpack_fn = unpack or table.unpack

local function default_loadstring(src, chunkname)
    local loader = loadstring or load
    if not loader then
        error('loadstring/load is not available in this Lua runtime', 2)
    end
    return loader(src, chunkname)
end

-- Exact payload of proto_85/helper[233].
function M.make_setfenv_bridge_source(comment, target_expr, injected_name)
    comment = tostring(comment or 'odyssey')
    target_expr = tostring(target_expr or '...')
    injected_name = tostring(injected_name or '_')
    return string.format(
        '--[[%s]] return setfenv(function(...) return %s(...) end,\n  setmetatable({ ["%s"] = ... }, { __index = getfenv((...)) }))',
        comment,
        target_expr,
        injected_name
    )
end

-- Safe compiler around the reconstructed source factory.
-- Original runtime most likely used helper[42]=loadstring and then executed
-- the returned chunk to obtain the bridge function.
function M.compile_setfenv_bridge(comment, target_expr, injected_name, load_fn)
    local source = M.make_setfenv_bridge_source(comment, target_expr, injected_name)
    local loader = load_fn or default_loadstring
    local chunk, err = loader(source, '@odyssey_proto_085_env_bridge')
    if not chunk then
        return nil, err, source
    end
    return chunk, nil, source
end

-- Convenience helper: compile and execute the generated wrapper chunk.
function M.instantiate_setfenv_bridge(comment, target_expr, injected_name, load_fn, ...)
    local chunk, err, source = M.compile_setfenv_bridge(comment, target_expr, injected_name, load_fn)
    if not chunk then
        return nil, err, source
    end

    local ok, result = pcall(chunk, ...)
    if not ok then
        return nil, result, source
    end
    return result, nil, source
end

-- Direct non-source equivalent of what the generated string means.
-- This is useful for understanding and testing without loadstring.
function M.make_direct_env_bridge(target_fn, injected_name, injected_value, base_env)
    if type(target_fn) ~= 'function' then
        error('target_fn must be a function', 2)
    end

    injected_name = tostring(injected_name or '_')
    base_env = base_env or (getfenv and getfenv(target_fn)) or _G

    local env = setmetatable({ [injected_name] = injected_value }, { __index = base_env })

    local wrapper = function(...)
        return target_fn(...)
    end

    if setfenv then
        return setfenv(wrapper, env), env
    end

    return wrapper, env
end

-- helper[233] = M.make_setfenv_bridge_source
M.helper_key = 233
M.proto_index = 85
M.recovered_template = [[--[[%s]] return setfenv(function(...) return %s(...) end,
  setmetatable({ ["%s"] = ... }, { __index = getfenv((...)) }))]]

return M
end

package.preload["Odyssey_loader_reversed.lua"] = function(...)
--[[
  Reconstruction of Odyssey proto_151 / helper[231].
  This is a semantic reconstruction, not byte-perfect obfuscated source.
]]

local M = {}

local table_insert = table.insert
local table_concat = table.concat
local string_match = string.match
local tostring_fn = tostring

local function is_array(t)
    if type(t) ~= 'table' then return false end
    local n = 0
    for k in pairs(t) do
        if type(k) ~= 'number' then return false end
        if k > n then n = k end
    end
    return n >= 0
end

function M.normalize_fragment(fragment, rules)
    rules = rules or {}

    if fragment == nil then
        return nil, 'nil-fragment'
    end

    local fragment_type = type(fragment)

    if fragment_type == 'string' then
        if rules.reject_pattern and string_match(fragment, rules.reject_pattern) then
            return nil, 'rejected-by-pattern'
        end
        if rules.accept_pattern and not string_match(fragment, rules.accept_pattern) then
            return nil, 'not-matching-accept-pattern'
        end
        return fragment
    end

    if fragment_type == 'number' or fragment_type == 'boolean' then
        return tostring_fn(fragment)
    end

    if fragment_type == 'table' then
        if fragment.raw ~= nil then
            return M.normalize_fragment(fragment.raw, rules)
        end
        if fragment.value ~= nil then
            return M.normalize_fragment(fragment.value, rules)
        end
        if fragment.text ~= nil then
            return M.normalize_fragment(fragment.text, rules)
        end
        if is_array(fragment) then
            return M.emit_fragments(fragment, rules.separator or '')
        end
        return tostring_fn(fragment)
    end

    if rules.stringify_unknown ~= false then
        return tostring_fn(fragment)
    end

    return nil, 'unsupported-fragment-type:' .. fragment_type
end

-- Append one normalized fragment to a parts array.
function M.append_fragment(parts, fragment, rules)
    parts = parts or {}
    local normalized, reason = M.normalize_fragment(fragment, rules)
    if normalized ~= nil then
        table_insert(parts, normalized)
        return parts, true, normalized
    end
    return parts, false, reason
end

-- Append many fragments
function M.append_many(parts, input, rules)
    parts = parts or {}
    if input == nil then return parts end

    if type(input) == 'table' and is_array(input) then
        for i = 1, #input do
            M.append_fragment(parts, input[i], rules)
        end
    else
        M.append_fragment(parts, input, rules)
    end

    return parts
end

function M.emit_fragments(parts, separator)
    return table_concat(parts or {}, separator or '')
end

function M.codegen_fragment_list_helper(input, rules)
    rules = rules or {}
    local parts = {}

    M.append_many(parts, input, rules)

    if rules.suffix then
        M.append_fragment(parts, rules.suffix, rules)
    end
    if rules.prefix then
        table_insert(parts, 1, tostring_fn(rules.prefix))
    end

    return M.emit_fragments(parts, rules.separator or '')
end

function M.new_builder(rules)
    local builder = { parts = {}, rules = rules or {} }

    function builder:add(fragment)
        M.append_fragment(self.parts, fragment, self.rules)
        return self
    end

    function builder:add_many(items)
        M.append_many(self.parts, items, self.rules)
        return self
    end

    function builder:match(fragment, pattern)
        return string_match(tostring_fn(fragment), pattern or self.rules.accept_pattern or '.*')
    end

    function builder:emit(separator)
        return M.emit_fragments(self.parts, separator or self.rules.separator or '')
    end

    return builder
end

-- helper[231] = M.codegen_fragment_list_helper
M.helper_key = 231
M.proto_index = 151
M.observed_strings = { 'insert', 'concat', 'match' }

return M
end

package.preload["Odyssey_loader_reversed.lua"] = function(...)
--[[
  This is a semantic reconstruction, not byte-perfect obfuscated source.
]]

local M = {}

-- Upvalues in Lua 5.1/Luraph-like VMs are usually represented as cells.
-- Open cells point into a VM stack slot; closed cells keep a copied value.
function M.new_cell(value, open_index)
    return {
        value = value,
        open_index = open_index,
        closed = open_index == nil,
    }
end

function M.cell_get(cell, stack)
    if type(cell) ~= 'table' then return cell end
    if not cell.closed and cell.open_index and stack then
        return stack[cell.open_index]
    end
    return cell.value
end

function M.cell_set(cell, value, stack)
    if type(cell) ~= 'table' then
        return value
    end
    if not cell.closed and cell.open_index and stack then
        stack[cell.open_index] = value
    else
        cell.value = value
    end
    return value
end

function M.close_cell(cell, stack)
    if type(cell) ~= 'table' then return cell end
    if not cell.closed then
        if cell.open_index and stack then
            cell.value = stack[cell.open_index]
        end
        cell.open_index = nil
        cell.closed = true
    end
    return cell
end

function M.close_open_upvalues(open_upvalues, from_stack_index, stack)
    for _, cell in pairs(open_upvalues or {}) do
        if type(cell) == 'table' and not cell.closed then
            if not from_stack_index or (cell.open_index and cell.open_index >= from_stack_index) then
                M.close_cell(cell, stack)
            end
        end
    end
end

function M.resolve_upvalue(spec, parent, stack, open_upvalues)
    parent = parent or {}
    open_upvalues = open_upvalues or {}

    if type(spec) ~= 'table' then
        -- Treat a raw number as stack index capture.
        local idx = tonumber(spec)
        if idx then
            open_upvalues[idx] = open_upvalues[idx] or M.new_cell(stack and stack[idx], idx)
            return open_upvalues[idx]
        end
        return M.new_cell(spec)
    end

    local kind = spec.kind or spec.type or spec[1]
    local index = spec.index or spec.idx or spec[2]

    if kind == 'parent' or kind == 'upvalue' then
        return parent[index]
    end

    if kind == 'stack' or kind == 'local' then
        open_upvalues[index] = open_upvalues[index] or M.new_cell(stack and stack[index], index)
        return open_upvalues[index]
    end

    if kind == 'const' then
        return M.new_cell(spec.value)
    end

    return M.new_cell(spec.value)
end

function M.resolve_upvalue_list(specs, parent, stack, open_upvalues)
    local resolved = {}
    for i, spec in ipairs(specs or {}) do
        resolved[i] = M.resolve_upvalue(spec, parent, stack, open_upvalues)
    end
    return resolved
end

-- Main high-level equivalent of proto_36/helper[265].
-- It creates a callable VM closure object around a parsed proto and resolved upvalues.
function M.make_closure_with_upvalues(proto, upvalue_specs, parent_upvalues, stack, env, dispatch)
    local open_upvalues = {}
    local upvalues = M.resolve_upvalue_list(upvalue_specs, parent_upvalues, stack, open_upvalues)

    local closure = {
        proto = proto,
        env = env,
        upvalues = upvalues,
        open_upvalues = open_upvalues,
    }

    setmetatable(closure, {
        __call = function(self, ...)
            if not dispatch then
                error('Odyssey VM dispatch function is required to execute reconstructed closure', 2)
            end
            return dispatch(self.proto, self.env, self.upvalues, ...)
        end
    })

    return closure
end

-- Nested helper equivalents inferred from proto_36 closure refs.
-- These are intentionally small and named by behaviour, not by obfuscated opcode.
function M.nested_proto_006_get_cell(cell, stack)
    return M.cell_get(cell, stack)
end

function M.nested_proto_025_set_cell(cell, value, stack)
    return M.cell_set(cell, value, stack)
end

function M.nested_proto_101_close_cell(cell, stack)
    return M.close_cell(cell, stack)
end

function M.nested_proto_047_make_child(proto, specs, parent_closure, stack, dispatch)
    parent_closure = parent_closure or {}
    return M.make_closure_with_upvalues(
        proto,
        specs,
        parent_closure.upvalues or {},
        stack,
        parent_closure.env,
        dispatch
    )
end

-- helper[265] = M.make_closure_with_upvalues
M.helper_key = 265
M.proto_index = 36
M.nested_protos = { 6, 25, 101, 47 }

return M
end

package.preload["Odyssey_loader_reversed.lua"] = function(...)
--[[
  Reconstruction of Odyssey proto_96 / helper[223].
]]

local M = {}

local unpack_fn = unpack or table.unpack

function M.pack_returns(...)
    return { n = select('#', ...), ... }
end

function M.unpack_args(args, first, last)
    args = args or {}
    first = first or 1
    if last == nil then last = args.n or #args end
    return unpack_fn(args, first, last)
end

function M.normalize_args(...)
    return { n = select('#', ...), ... }
end

-- Main call adapter. It supports both direct varargs and packed argument arrays.
function M.call_adapter(fn, args, opts)
    opts = opts or {}
    if type(fn) ~= 'function' and type(fn) ~= 'table' then
        error('call_adapter expected callable target', 2)
    end

    local first = opts.first or 1
    local last = opts.last
    local returns

    if type(args) == 'table' and (args.n or #args > 0) then
        returns = M.pack_returns(fn(M.unpack_args(args, first, last)))
    elseif args == nil then
        returns = M.pack_returns(fn())
    else
        returns = M.pack_returns(fn(args))
    end

    if opts.return_pack then
        return returns
    end

    return M.unpack_args(returns, 1, returns.n)
end

function M.protected_call_adapter(fn, args, opts)
    opts = opts or {}
    local packed

    local ok, result_or_err = pcall(function()
        packed = M.pack_returns(M.call_adapter(fn, args, { first = opts.first, last = opts.last, return_pack = false }))
    end)

    if not ok then
        if opts.raise then error(result_or_err, 2) end
        return false, result_or_err
    end

    if opts.return_pack then
        return true, packed
    end

    return true, M.unpack_args(packed, 1, packed.n)
end

function M.xprotected_call_adapter(fn, err_handler, args, opts)
    opts = opts or {}
    local packed

    local ok, result_or_err = xpcall(function()
        packed = M.pack_returns(M.call_adapter(fn, args, { first = opts.first, last = opts.last, return_pack = false }))
    end, err_handler or debug.traceback)

    if not ok then
        if opts.raise then error(result_or_err, 2) end
        return false, result_or_err
    end

    if opts.return_pack then
        return true, packed
    end

    return true, M.unpack_args(packed, 1, packed.n)
end

function M.tailcall_adapter(fn, args, opts)
    return M.call_adapter(fn, args, opts)
end

-- VM-style helper: call a function in register frame R at base with arg_count.
-- This models CALL opcodes observed throughout mode12 helpers.
function M.call_from_registers(R, base, arg_count, ret_count)
    local fn = R[base]
    local args = { n = arg_count or 0 }
    for i = 1, args.n do
        args[i] = R[base + i]
    end

    local returns = M.call_adapter(fn, args, { return_pack = true })

    if ret_count == 0 then
        return R, returns
    end

    local n = ret_count or returns.n
    for i = 1, n do
        R[base + i - 1] = returns[i]
    end
    return R, returns
end

-- helper[223] = M.call_adapter
M.helper_key = 223
M.proto_index = 96

return M
end

package.preload["Odyssey_loader_reversed.lua"] = function(...)
--[[
  Reconstruction of Odyssey proto_139 / helper[229].
]]

local M = {}

local unpack_fn = unpack or table.unpack
local table_insert = table.insert

function M.pack_array(...)
    return { n = select('#', ...), ... }
end

function M.unpack_array(t, first, last)
    t = t or {}
    first = first or 1
    if last == nil then last = t.n or #t end
    return unpack_fn(t, first, last)
end

function M.copy_range(dst, dst_index, src, src_index, count)
    dst = dst or {}
    src = src or {}
    dst_index = dst_index or 1
    src_index = src_index or 1
    count = count or ((src.n or #src) - src_index + 1)

    for i = 0, count - 1 do
        dst[dst_index + i] = src[src_index + i]
    end
    return dst
end

-- SETLIST-like operation used by Lua VM/Luraph VMs:
--   for i=1,count: dst[dst_index+i-1] = src[src_index+i-1]
function M.setlist(dst, src, src_index, dst_index, count)
    return M.copy_range(dst, dst_index or 1, src, src_index or 1, count)
end

function M.append_range(dst, src, first, last)
    dst = dst or {}
    src = src or {}
    first = first or 1
    last = last or src.n or #src

    for i = first, last do
        table_insert(dst, src[i])
    end
    return dst
end

function M.merge_tables(dst, src, overwrite)
    dst = dst or {}
    src = src or {}
    for k, v in pairs(src) do
        if overwrite or dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

function M.clone_table(src)
    local dst = {}
    for k, v in pairs(src or {}) do dst[k] = v end
    return dst
end

function M.clear_range(t, first, last)
    t = t or {}
    first = first or 1
    last = last or #t
    for i = first, last do t[i] = nil end
    return t
end

-- Main helper equivalent for helper[229]/proto_139.
function M.table_array_helper(dst, src, start_index, count, opts)
    opts = opts or {}
    dst = dst or {}

    if opts.mode == 'merge' then
        return M.merge_tables(dst, src, opts.overwrite ~= false)
    end

    if opts.mode == 'append' then
        return M.append_range(dst, src, opts.first or 1, opts.last)
    end

    if opts.mode == 'clear' then
        return M.clear_range(dst, start_index or 1, count)
    end

    return M.setlist(dst, src, opts.src_index or 1, start_index or (#dst + 1), count)
end

-- helper[229] = M.table_array_helper
M.helper_key = 229
M.proto_index = 139

return M
end

package.preload["Odyssey_loader_reversed.lua"] = function(...)
--[[
  Reconstruction of Odyssey proto_94 / helper[0].
]]

local M = {}

local unpack_fn = unpack or table.unpack

function M.new_runtime(env, prototypes, helpers, dispatch)
    local runtime = {
        env = env or _G,
        prototypes = prototypes or {},
        helper = helpers or {},
        dispatch = dispatch,
        closures = {},
        state = {},
    }
    return runtime
end

function M.get_helper(runtime, key)
    runtime = runtime or {}
    local helper = runtime.helper or {}
    return helper[key]
end

function M.set_helper(runtime, key, value)
    runtime.helper = runtime.helper or {}
    runtime.helper[key] = value
    return value
end

function M.resolve_proto(runtime, proto_or_index)
    if type(proto_or_index) == 'table' then return proto_or_index end
    runtime = runtime or {}
    return (runtime.prototypes or {})[proto_or_index]
end

function M.materialize_closure(runtime, proto_index, upvalue_specs, parent, stack)
    runtime = runtime or M.new_runtime()
    runtime.closures = runtime.closures or {}

    local cached = runtime.closures[proto_index]
    if cached and not upvalue_specs then return cached end

    local proto = M.resolve_proto(runtime, proto_index)
    local factory = M.get_helper(runtime, 265) -- proto_36 closure/upvalue factory

    local closure
    if type(factory) == 'function' then
        closure = factory(proto, upvalue_specs or {}, parent and parent.upvalues or {}, stack or {}, runtime.env, runtime.dispatch)
    else
        closure = function(...)
            return M.dispatch(runtime, proto, ...)
        end
    end

    if not upvalue_specs then runtime.closures[proto_index] = closure end
    return closure
end

function M.call_helper(runtime, key, ...)
    local fn = M.get_helper(runtime, key)
    if type(fn) ~= 'function' then
        error('Odyssey helper[' .. tostring(key) .. '] is not callable', 2)
    end

    local adapter = M.get_helper(runtime, 223) -- proto_96 call adapter
    if type(adapter) == 'function' then
        return adapter(fn, { n = select('#', ...), ... })
    end
    return fn(...)
end

function M.dispatch(runtime, proto_or_index, ...)
    runtime = runtime or M.new_runtime()
    local proto = M.resolve_proto(runtime, proto_or_index)
    if not proto then
        error('Odyssey runtime dispatch: missing prototype ' .. tostring(proto_or_index), 2)
    end
    if type(runtime.dispatch) ~= 'function' then
        error('Odyssey runtime dispatch function is not installed', 2)
    end
    return runtime.dispatch(proto, runtime.env, runtime.helper, ...)
end

function M.install_standard_helpers(runtime, helpers)
    runtime = runtime or M.new_runtime()
    helpers = helpers or {}
    for k, v in pairs(helpers) do runtime.helper[k] = v end
    return runtime
end

-- Core entry used by the deobfuscated root: materialize root closure and run it.
function M.run_root(runtime, root_index, ...)
    root_index = root_index or 167
    local root = M.materialize_closure(runtime, root_index)
    if type(root) == 'function' then return root(...) end
    if type(root) == 'table' then return root(...) end
    return M.dispatch(runtime, root_index, ...)
end

-- helper[0] = M
M.helper_key = 0
M.proto_index = 94

return M
end

package.preload["Odyssey_loader_reversed.lua"] = function(...)
local Rare = require and nil 
local closures = {}
return closures
end

-- Public assembled entry
local Assembled = {}
Assembled.Odyssey = require("Odyssey_loader_reversed.lua")
Assembled.Runtime = Assembled.Odyssey.Runtime
function Assembled.parse(encoded_payload, opts)
  opts = opts or {}; opts.execute = false
  return Assembled.Odyssey.run(encoded_payload, opts)
end
function Assembled.run(encoded_payload, opts)
  opts = opts or {}
  if not opts.execute then error("Refusing to execute unknown Odyssey payload without opts.execute=true", 2) end
  return Assembled.Odyssey.run(encoded_payload, opts)
end
return Assembled