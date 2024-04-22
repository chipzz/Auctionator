local VERSION_8_3 = 6
local VERSION_SERIALIZED = 7
local POSTING_HISTORY_DB_VERSION = 1
local VENDOR_PRICE_CACHE_DB_VERSION = 1

function Auctionator.Variables.Initialize()
  Auctionator.Variables.InitializeSavedState()

  Auctionator.Config.InitializeData()
  Auctionator.Config.InitializeFrames()

  local GetAddOnMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
  Auctionator.State.CurrentVersion = GetAddOnMetadata("Auctionator", "Version")

  Auctionator.Variables.InitializeDatabase()
  Auctionator.Variables.InitializeShoppingLists()
  Auctionator.Variables.InitializePostingHistory()
  Auctionator.Variables.InitializeVendorPriceCache()

  Auctionator.Groups.Initialize()

  Auctionator.State.Loaded = true
end

function Auctionator.Variables.Commit()
  Auctionator.Variables.CommitDatabase()
end

function Auctionator.Variables.InitializeSavedState()
  if AUCTIONATOR_SAVEDVARS == nil then
    AUCTIONATOR_SAVEDVARS = {}
  end
  Auctionator.SavedState = AUCTIONATOR_SAVEDVARS
end

-- Attempt to import from other connected realms (this may happen if another
-- realm was connected or the databases are not currently shared)
--
-- Assumes rootRealm has no active database
local function ImportFromConnectedRealm(rootRealm)
  local connections = GetAutoCompleteRealms()

  if #connections == 0 then
    return false
  end

  for _, altRealm in ipairs(connections) do

    if AUCTIONATOR_PRICE_DATABASE[altRealm] ~= nil then

      AUCTIONATOR_PRICE_DATABASE[rootRealm] = AUCTIONATOR_PRICE_DATABASE[altRealm]
      -- Remove old database (no longer needed)
      AUCTIONATOR_PRICE_DATABASE[altRealm] = nil
      return true
    end
  end

  return false
end

local function ImportFromNotNormalizedName(target)
  local unwantedName = GetRealmName()

  if AUCTIONATOR_PRICE_DATABASE[unwantedName] ~= nil then

    AUCTIONATOR_PRICE_DATABASE[target] = AUCTIONATOR_PRICE_DATABASE[unwantedName]
    -- Remove old database (no longer needed)
    AUCTIONATOR_PRICE_DATABASE[unwantedName] = nil
    return true
  end

  return false
end
-- This is a deep compare on the values of the table (based on depth) but not a deep comparison
-- of the keys, as this would be an expensive check and won't be necessary in most cases.
local function tCompare(lhsTable, rhsTable, depth)
	depth = depth or 1;
	for key, value in pairs(lhsTable) do
		if type(value) == "table" then
			local rhsValue = rhsTable[key];
			if type(rhsValue) ~= "table" then
        print("not table", key, value, rhsTable[key])
				return false;
			end
			if depth > 1 then
				if not tCompare(value, rhsValue, depth - 1) then
          print(key, value)
					return false;
				end
			end
		elseif value ~= rhsTable[key] then
      print(key, value)
			return false;
		end
	end

	-- Check for any keys that are in rhsTable and not lhsTable.
	for key, value in pairs(rhsTable) do
		if lhsTable[key] == nil then
      print("missing", key)
			return false;
		end
	end

	return true;
end

-- Deserialize current realm when not already deserialized in the saved
-- variables and serialize any other realms.
-- We keep the current realm deserialized in the saved variables to speed up
-- /reloads and logging in/out when only using one realm.
function Auctionator.Variables.InitializeDatabase()
  Auctionator.Debug.Message("Auctionator.Database.Initialize()")
  -- Auctionator.Utilities.TablePrint(AUCTIONATOR_PRICE_DATABASE, "AUCTIONATOR_PRICE_DATABASE")

  -- First time users need the price database initialized
  if AUCTIONATOR_PRICE_DATABASE == nil then
    AUCTIONATOR_PRICE_DATABASE = {
      ["__dbversion"] = VERSION_8_3
    }
  end

  local LibSerialize = LibStub("LibSerialize")

  if AUCTIONATOR_PRICE_DATABASE["__dbversion"] == VERSION_8_3 then
    AUCTIONATOR_PRICE_DATABASE["__dbversion"] = VERSION_SERIALIZED
  end

  -- If we changed how we record item info we need to reset the DB
  if AUCTIONATOR_PRICE_DATABASE["__dbversion"] ~= VERSION_SERIALIZED then
    AUCTIONATOR_PRICE_DATABASE = {
      ["__dbversion"] = VERSION_SERIALIZED
    }
  end

  local realm = Auctionator.Variables.GetConnectedRealmRoot()
  Auctionator.State.CurrentRealm = realm

  -- Check for current realm and initialize if not present
  if AUCTIONATOR_PRICE_DATABASE[realm] == nil then
    if not ImportFromNotNormalizedName(realm) and not ImportFromConnectedRealm(realm) then
      AUCTIONATOR_PRICE_DATABASE[realm] = {}
    end
  end

  --[[
  -- Serialize and other unserialized realms so their data doesn't contribute to
  -- a constant overflow when the client parses the saved variables.
  for key, data in pairs(AUCTIONATOR_PRICE_DATABASE) do
    -- Convert one realm at a time, no need to hold up a login indefinitely
    if key ~= "__dbversion" and key ~= realm and type(data) == "table" then
      AUCTIONATOR_PRICE_DATABASE[key] = LibSerialize:Serialize(data)
      break
    end
  end

  -- Only deserialize the current realm and save the deserialization in the
  -- saved variables to speed up reloads or changing character on the same
  -- realm.
  --]]
  -- Deserialize the current realm if it was left serialized by a previous
  -- version of Auctionator
  local raw = AUCTIONATOR_PRICE_DATABASE[realm]
  if type(raw) == "string" then
    local success, data = LibSerialize:Deserialize(raw)
    AUCTIONATOR_PRICE_DATABASE[realm] = data
  end

  Auctionator.Variables.Simulate = function()
    print("----")
    local ls, e0
    C_Timer.After(0, function()
      collectgarbage()
      local start = debugprofilestop()
      ls = LibSerialize:Serialize(AUCTIONATOR_PRICE_DATABASE[realm])
      e0 = debugprofilestop() - start
      print("LibSerialize Serialize", e0)
      print("LibSerialize Length", #ls)
    end)

    C_Timer.After(0.1, function()
      local cbor = LibStub("LibCBOR-1.0")
      local e1, e2
      collectgarbage()
      local start = debugprofilestop()
      CBOR = cbor:Serialize(AUCTIONATOR_PRICE_DATABASE[realm])
      e2 = debugprofilestop() - start
      print("LibCBOR Serialize", e2)
      print("LibCBOR Length", #CBOR)
      print("Perf Boost", (e0 - e2) / e0)
    end)

    C_Timer.After(0.2, function()
      local e1, e2, e3
      local start = debugprofilestop()
      LibSerialize:Deserialize(ls)
      e1 = debugprofilestop() - start
      print("LibSerialize Deserialize", e1)
      C_Timer.After(1, function()
        local cbor = LibStub("LibCBOR-1.0")
        collectgarbage()
        local start = debugprofilestop()
        local res = cbor.decode(CBOR)
        e2 = debugprofilestop() - start
        print("LibCBOR1 Deserialize", e2, tCompare(res, AUCTIONATOR_PRICE_DATABASE[realm]))
        collectgarbage()
        start = debugprofilestop()
        res = cbor.decode2(CBOR)
        e3 = debugprofilestop() - start
        print("LibCBOR2 Deserialize", e3, tCompare(res, AUCTIONATOR_PRICE_DATABASE[realm]))
        print("CBOR Perf Boost", (e2 - e3) / e2)
        print("Perf Boost", (e1 - e2) / e1)
        print("Perf Boost", (e1 - e3) / e1)
      end)
    end)
  end

  C_Timer.After(5, Auctionator.Variables.Simulate)

  Auctionator.Database = CreateAndInitFromMixin(Auctionator.DatabaseMixin, AUCTIONATOR_PRICE_DATABASE[realm])
  Auctionator.Database:Prune()
end

function Auctionator.Variables.InitializePostingHistory()
  Auctionator.Debug.Message("Auctionator.Variables.InitializePostingHistory()")

  if AUCTIONATOR_POSTING_HISTORY == nil  or
     AUCTIONATOR_POSTING_HISTORY["__dbversion"] ~= POSTING_HISTORY_DB_VERSION then
    AUCTIONATOR_POSTING_HISTORY = {
      ["__dbversion"] = POSTING_HISTORY_DB_VERSION
    }
  end

  Auctionator.PostingHistory = CreateAndInitFromMixin(Auctionator.PostingHistoryMixin, AUCTIONATOR_POSTING_HISTORY)
end

function Auctionator.Variables.InitializeShoppingLists()
  Auctionator.Shopping.ListManager = CreateAndInitFromMixin(
    AuctionatorShoppingListManagerMixin,
    function() return AUCTIONATOR_SHOPPING_LISTS end,
    function(newVal) AUCTIONATOR_SHOPPING_LISTS = newVal end
  )

  AUCTIONATOR_RECENT_SEARCHES = AUCTIONATOR_RECENT_SEARCHES or {}
end

function Auctionator.Variables.InitializeVendorPriceCache()
  Auctionator.Debug.Message("Auctionator.Variables.InitializeVendorPriceCache()")

  if AUCTIONATOR_VENDOR_PRICE_CACHE == nil  or
     AUCTIONATOR_VENDOR_PRICE_CACHE["__dbversion"] ~= VENDOR_PRICE_CACHE_DB_VERSION then
    AUCTIONATOR_VENDOR_PRICE_CACHE = {
      ["__dbversion"] = VENDOR_PRICE_CACHE_DB_VERSION
    }
  end
end
