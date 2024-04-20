-- Modified by plusmouse for World of Warcraft addons
--
-- Concise Binary Object Representation (CBOR)
-- RFC 7049

local lib
if not LibStub then
  LibCBOR = {}
  lib = LibCBOR
else
  lib = LibStub:NewLibrary("LibCBOR-1.0", 3)
end

if not lib then
  return
end

local maxint = math.huge
local minint = -math.huge
local NaN = math.sin(math.huge)
local m_type = function (n) return n % 1 == 0 and n <= maxint and n >= minint and "integer" or "float" end;
local b_rshift = bit and bit.rshift or function (a, b) return math.max(0, math.floor(a / (2 ^ b))); end

local encoder = {};

-- Major types 0, 1 and length encoding for others
local function integer(num, m)
  if m == 0 and num < 0 then
    -- negative integer, major type 1
    num, m = - num - 1, 32;
  end
  if num < 24 then
    return string.char(m + num);
  elseif num < 2 ^ 8 then
    return string.char(m + 24, num);
  elseif num < 2 ^ 16 then
    return string.char(m + 25, b_rshift(num, 8), num % 0x100);
  elseif num < 2 ^ 32 then
    return string.char(m + 26,
      b_rshift(num, 24) % 0x100,
      b_rshift(num, 16) % 0x100,
      b_rshift(num, 8) % 0x100,
      num % 0x100);
  elseif num < 2 ^ 64 then
    local high = math.floor(num / 2 ^ 32);
    num = num % 2 ^ 32;
    return string.char(m + 27,
      b_rshift(high, 24) % 0x100,
      b_rshift(high, 16) % 0x100,
      b_rshift(high, 8) % 0x100,
      high % 0x100,
      b_rshift(num, 24) % 0x100,
      b_rshift(num, 16) % 0x100,
      b_rshift(num, 8) % 0x100,
      num % 0x100);
  end
  error "int too large";
end

local function encode(obj)
  return encoder[type(obj)](obj);
end

local function encode2(root)
  if type(root) == "table" then
    local keychain = {}
    --local rootsInKeychain = {}
    local current
    while true do
      local obj = root
      if current then
        obj = current.root[current.keys[current.index]]
      end
      local objType = type(obj)
      if objType == "table" then
        local keys = {}
        for key in pairs(obj) do
          keys[#keys + 1] = key
        end
        keychain[#keychain + 1] = {root = obj, keys = keys, index = 1, results = {}}
        --rootsInKeychain[obj] = true
        current = keychain[#keychain]
      elseif obj ~= nil then
        current.results[current.index] = encoder[objType](obj)
        current.index = current.index + 1
      else
        keychain[#keychain] = nil
        local isArray = true
        for index = 1, #current.results do
          if index ~= current.keys[index] then
            isArray = false
            break
          end
        end
        local result
        if isArray then
          local results = current.results
          table.insert(results, 1, integer(#results, 128))
          result = table.concat(results)
        else
          local results, keys = current.results, current.keys
          local tmp = { integer(#results, 160) }
          for index = 1, #results do
            local position = index * 2
            local key = keys[index]
            tmp[position] = encoder[type(key)](key)
            local r = current.results[index]
            tmp[position + 1] = r
          end
          result = table.concat(tmp)
        end
        --rootsInKeychain[current.root] = nil
        current = keychain[#keychain]
        if current == nil then
          return result
        else
          current.results[current.index] = result
          current.index = current.index + 1
        end
      end
    end
  else
    return encoder[type(root)](root)
  end
end

local simple_mt = {};
function simple_mt:__tostring() return self.name or ("simple(%d)"):format(self.value); end
function simple_mt:__tocbor() return self.cbor or integer(self.value, 224); end

local function simple(value, name, cbor)
  assert(value >= 0 and value <= 255, "bad argument #1 to 'simple' (integer in range 0..255 expected)");
  return setmetatable({ value = value, name = name, cbor = cbor }, simple_mt);
end

local BREAK = simple(31, "break", "\255");

-- Number types dispatch
function encoder.number(num)
  return encoder[m_type(num)](num);
end

-- Major types 0, 1
function encoder.integer(num)
  if num < 0 then
    return integer(-1 - num, 32);
  end
  return integer(num, 0);
end

-- Major type 7
function encoder.float(num)
  if (num < 0) == (num >= 0) then -- NaN shortcut
    return "\249\255\255";
  end
  local sign = (num > 0 or 1 / num > 0) and 0 or 1;
  num = math.abs(num)
  if num == math.huge then
    return string.char(251, sign * 128 + 128 - 1) .. "\240\0\0\0\0\0\0";
  end
  local fraction, exponent = math.frexp(num)
  if fraction == 0 then
    return string.char(251, sign * 128) .. "\0\0\0\0\0\0\0";
  end
  fraction = fraction * 2;
  exponent = exponent + 1024 - 2;
  if exponent <= 0 then
    fraction = fraction * 2 ^ (exponent - 1)
    exponent = 0;
  else
    fraction = fraction - 1;
  end
  return string.char(251,
    sign * 2 ^ 7 + math.floor(exponent / 2 ^ 4) % 2 ^ 7,
    exponent % 2 ^ 4 * 2 ^ 4 +
    math.floor(fraction * 2 ^ 4 % 0x100),
    math.floor(fraction * 2 ^ 12 % 0x100),
    math.floor(fraction * 2 ^ 20 % 0x100),
    math.floor(fraction * 2 ^ 28 % 0x100),
    math.floor(fraction * 2 ^ 36 % 0x100),
    math.floor(fraction * 2 ^ 44 % 0x100),
    math.floor(fraction * 2 ^ 52 % 0x100)
  )
end


-- Major type 2 - byte strings
function encoder.bytestring(s)
  return integer(#s, 64) .. s;
end

-- Major type 3 - UTF-8 strings
function encoder.utf8string(s)
  return integer(#s, 96) .. s;
end

-- Modern Lua strings are UTF-UTF-8
encoder.string = encoder.utf8string;

function encoder.boolean(bool)
  return bool and "\245" or "\244";
end

encoder["nil"] = function() return "\246"; end

function encoder.table(t)
  -- the table is encoded as an array iff when we iterate over it,
  -- we see successive integer keys starting from 1.  The lua
  -- language doesn't actually guarantee that this will be the case
  -- when we iterate over a table with successive integer keys, but
  -- due an implementation detail in PUC Rio Lua, this is what we
  -- usually observe.  See the Lua manual regarding the # (length)
  -- operator.  In the case that this does not happen, we will fall
  -- back to a map with integer keys, which becomes a bit larger.
  local array, map, i = { integer(#t, 128) }, { "\191" }, 1
  local is_array = true;
  for k, v in pairs(t) do
    is_array = is_array and i == k;
    i = i + 1;

    local encoded_v = encode(v);
    array[i] = encoded_v;

    table.insert(map, encode(k))
    table.insert(map, encoded_v)
  end
  --map[#map + 1] = "\255";
  map[1] = integer(i - 1, 160);
  return table.concat(is_array and array or map);
end

encoder["function"] = function ()
  error "can't encode function";
end

local function read_length(fh, mintyp)
  if mintyp < 24 then
    return mintyp;
  elseif mintyp < 28 then
    local out = 0;
    for _ = 1, 2 ^ (mintyp - 24) do
      out = out * 256 + fh.readbyte();
    end
    return out;
  else
    error "invalid length";
  end
end

local decoder = {};

local function read_type(fh)
  local byte = fh.readbyte();
  return b_rshift(byte, 5), byte % 32;
end

local function read_object(fh)
  local typ, mintyp = read_type(fh);
  return decoder[typ](fh, mintyp);
end

local function read_integer(fh, mintyp)
  return read_length(fh, mintyp);
end

local function read_negative_integer(fh, mintyp)
  return -1 - read_length(fh, mintyp);
end

local function read_string(fh, mintyp)
  if mintyp ~= 31 then
    return fh.read(read_length(fh, mintyp));
  end
  local out = {};
  local i = 1;
  local v = read_object(fh);
  while v ~= BREAK do
    out[i], i = v, i + 1;
    v = read_object(fh);
  end
  return table.concat(out);
end

local function read_unicode_string(fh, mintyp)
  return read_string(fh, mintyp);
  -- local str = read_string(fh, mintyp);
  -- if have_utf8 and not utf8.len(str) then
    -- TODO How to handle this?
  -- end
  -- return str;
end

local function read_array(fh, mintyp)
  local out = {};
  if mintyp == 31 then
    local i = 1;
    local v = read_object(fh);
    while v ~= BREAK do
      out[i], i = v, i + 1;
      v = read_object(fh);
    end
  else
    local len = read_length(fh, mintyp);
    for i = 1, len do
      out[i] = read_object(fh);
    end
  end
  return out;
end

local function read_map(fh, mintyp)
  local out = {};
  local k;
  if mintyp == 31 then
    local i = 1;
    k = read_object(fh);
    while k ~= BREAK do
      out[k], i = read_object(fh), i + 1;
      k = read_object(fh);
    end
  else
    local len = read_length(fh, mintyp);
    for _ = 1, len do
      k = read_object(fh);
      out[k] = read_object(fh);
    end
  end
  return out;
end

local tagged_decoders = {};

local function read_semantic(fh, mintyp)
  local tag = read_length(fh, mintyp);
  local value = read_object(fh);
  local postproc = tagged_decoders[tag];
  if postproc then
    return postproc(value);
  end
  return tagged(tag, value);
end

local function read_half_float(fh)
  local exponent = fh.readbyte();
  local fraction = fh.readbyte();
  local sign = exponent < 128 and 1 or -1; -- sign is highest bit

  fraction = fraction + (exponent * 256) % 1024; -- copy two(?) bits from exponent to fraction
  exponent = b_rshift(exponent, 2) % 32; -- remove sign bit and two low bits from fraction;

  if exponent == 0 then
    return sign * math.ldexp(fraction, -24);
  elseif exponent ~= 31 then
    return sign * math.ldexp(fraction + 1024, exponent - 25);
  elseif fraction == 0 then
    return sign * math.huge;
  else
    return NaN;
  end
end

local function read_float(fh)
  local exponent = fh.readbyte();
  local fraction = fh.readbyte();
  local sign = exponent < 128 and 1 or -1; -- sign is highest bit
  exponent = exponent * 2 % 256 + b_rshift(fraction, 7);
  fraction = fraction % 128;
  fraction = fraction * 256 + fh.readbyte();
  fraction = fraction * 256 + fh.readbyte();

  if exponent == 0 then
    return sign * math.ldexp(exponent, -149);
  elseif exponent ~= 0xff then
    return sign * math.ldexp(fraction + 2 ^ 23, exponent - 150);
  elseif fraction == 0 then
    return sign * math.huge;
  else
    return NaN;
  end
end

local function read_double(fh)
  local exponent = fh.readbyte();
  local fraction = fh.readbyte();
  local sign = exponent < 128 and 1 or -1; -- sign is highest bit

  exponent = exponent %  128 * 16 + b_rshift(fraction, 4);
  fraction = fraction % 16;
  fraction = fraction * 256 + fh.readbyte();
  fraction = fraction * 256 + fh.readbyte();
  fraction = fraction * 256 + fh.readbyte();
  fraction = fraction * 256 + fh.readbyte();
  fraction = fraction * 256 + fh.readbyte();
  fraction = fraction * 256 + fh.readbyte();

  if exponent == 0 then
    return sign * math.ldexp(exponent, -149);
  elseif exponent ~= 0xff then
    return sign * math.ldexp(fraction + 2 ^ 52, exponent - 1075);
  elseif fraction == 0 then
    return sign * math.huge;
  else
    return NaN;
  end
end

local function read_simple(fh, value)
  if value == 24 then
    value = fh.readbyte();
  end
  if value == 20 then
    return false;
  elseif value == 21 then
    return true;
  elseif value == 22 then
    return nil;
  elseif value == 23 then
    return nil;
  elseif value == 25 then
    return read_half_float(fh);
  elseif value == 26 then
    return read_float(fh);
  elseif value == 27 then
    return read_double(fh);
  elseif value == 31 then
    return BREAK;
  end
  return simple(value);
end

decoder[0] = read_integer;
decoder[1] = read_negative_integer;
decoder[2] = read_string;
decoder[3] = read_unicode_string;
decoder[4] = read_array;
decoder[5] = read_map;
decoder[6] = read_semantic;
decoder[7] = read_simple;

local function decode(s)
  local fh = {};
  local pos = 1;

  local more = nil
  if type(more) ~= "function" then
    more = function()
      error "input too short";
    end
  end

  function fh.read(bytes)
    local ret = string.sub(s, pos, pos + bytes - 1);
    if #ret < bytes then
      ret = more(bytes - #ret, fh);
      if ret then self.write(ret); end
      return self.read(bytes);
    end
    pos = pos + bytes;
    return ret;
  end

  function fh.readbyte()
    pos = pos + 1
    return string.byte(s, pos - 1)
  end

  function fh.write(bytes) -- luacheck: no self
    s = s .. bytes;
    if pos > 256 then
      s = string.sub(s, pos + 1);
      pos = 1;
    end
    return #bytes;
  end

  return read_object(fh);
end

for key, val in pairs({
  encode = encode;
  encode2 = encode2;
  decode = decode;
  Serialize = function(_, ...) return encode2(...) end;
  Deserialize = function(_, ...) return decode(...) end;
}) do
  lib[key] = val
end
