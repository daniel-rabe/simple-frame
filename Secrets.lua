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
--     secret, so it needs pcall - see SF.GetAura.

local addonName, SF = ...

local issecretvalue = issecretvalue

SF.HAS_SECRETS = issecretvalue ~= nil

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

-- C_UnitAuras.GetAuraDataByIndex raises in restricted contexts (in combat, and
-- in Mythic+ even out of combat) instead of returning a secret, so there is no
-- value for issecretvalue to inspect. A throw means "cannot enumerate here";
-- callers treat nil as end-of-list and simply show no icons.
function SF.GetAura(unit, index, filter)
	local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, filter)
	if ok then
		return data
	end
	return nil
end
