-- SimpleFrame - Secrets
--
-- WoW 12.0 (Midnight) hides combat-relevant numbers behind "secret values".
-- A secret is truthy and can be handed straight to a widget setter
-- (StatusBar:SetValue, StatusBar:SetMinMaxValues, FontString:SetFormattedText,
-- AbbreviateNumbers, ...), but any Lua comparison, arithmetic, table-index-by-key
-- or string.format on it raises
--     "attempt to compare local 'x' (a secret number value ...)"
--
-- Rules the rest of the addon follows:
--   * Never compare or format a Unit* return in Lua. Pass it to the widget.
--   * Guard any value you must branch on with SF.Plain().
--   * Aura enumeration THROWS in restricted contexts rather than returning a
--     secret, so it needs pcall - see SF.CollectAuras.

local addonName, SF = ...

local issecretvalue = issecretvalue

SF.HAS_SECRETS = issecretvalue ~= nil

function SF.IsSecret(v)
	return (issecretvalue and issecretvalue(v)) and true or false
end

-- Returns v when it is safe to compare / do arithmetic on, otherwise nil.
-- Branch on the result, never on the raw value.
function SF.Plain(v)
	if issecretvalue and issecretvalue(v) then
		return nil
	end
	return v
end

-- A health percentage safe to hand to SetFormattedText("%d").
-- UnitHealthPercent evaluates the ratio engine-side, which is the only way to
-- get a percentage out of two secret numbers.
function SF.HealthPercent(unit)
	if UnitHealthPercent and CurveConstants then
		return UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)
	end

	-- Pre-Midnight clients: plain numbers, plain maths.
	local cur, max = UnitHealth(unit), UnitHealthMax(unit)
	if max and max > 0 then
		return cur / max * 100
	end
	return 0
end

-- Aura enumeration.
--
-- On 12.x both of the older enumeration APIs - GetAuraDataByIndex and
-- GetAuraSlots - raise outright once a unit's auras are secret:
--
--     Auras cannot be accessed when secret while tainted by 'SimpleFrame'
--
-- which in practice means every target, in combat. C_UnitAuras.GetUnitAuras is
-- the Midnight-era replacement that works from tainted code and returns the
-- aura list directly. The slot walk is kept only for clients predating it.
local GetUnitAuras = C_UnitAuras and C_UnitAuras.GetUnitAuras
local GetAuraSlots = C_UnitAuras and C_UnitAuras.GetAuraSlots
local GetAuraDataBySlot = C_UnitAuras and C_UnitAuras.GetAuraDataBySlot

local SORT_UNSORTED = Enum and Enum.UnitAuraSortRule and Enum.UnitAuraSortRule.Unsorted

-- Takes the results of pcall(GetAuraSlots, ...) as varargs. The slot list can
-- contain nils, so it is walked with select("#") rather than table length.
local function Harvest(unit, out, count, maxCount, ok, continuationToken, ...)
	if not ok then
		return count, nil
	end

	for i = 1, select("#", ...) do
		local slot = select(i, ...)
		if slot then
			local good, aura = pcall(GetAuraDataBySlot, unit, slot)
			if good and aura then
				count = count + 1
				out[count] = aura
				if count >= maxCount then
					return count, nil
				end
			end
		end
	end

	return count, continuationToken
end

local function CollectViaSlots(unit, filter, maxCount, out)
	local count, token = 0, nil
	repeat
		count, token = Harvest(unit, out, count, maxCount,
			pcall(GetAuraSlots, unit, filter, maxCount, token))
	until not token

	return count
end

-- The list itself can come back secret, in which case indexing or taking its
-- length would raise; SF.Plain turns that into "no auras" instead.
local function CollectViaList(unit, filter, maxCount, out)
	local ok, list = pcall(GetUnitAuras, unit, filter, nil, SORT_UNSORTED)
	list = ok and SF.Plain(list) or nil
	if type(list) ~= "table" then return 0 end

	local count = 0
	for i = 1, #list do
		local aura = list[i]
		if aura then
			count = count + 1
			out[count] = aura
			if count >= maxCount then break end
		end
	end

	return count
end

-- Fills `out` with up to maxCount auras and returns how many. Zero means either
-- no auras or a context where enumeration is refused; callers treat both the
-- same and show no icons.
function SF.CollectAuras(unit, filter, maxCount, out)
	if GetUnitAuras then
		return CollectViaList(unit, filter, maxCount, out)
	end

	if GetAuraSlots and GetAuraDataBySlot then
		return CollectViaSlots(unit, filter, maxCount, out)
	end

	return 0
end
