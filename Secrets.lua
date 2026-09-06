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

-- Aura enumeration used to live here. It is gone: on 12.x every enumeration API
-- - GetAuraDataByIndex, GetAuraSlots, GetUnitAuras - is refused once a unit's
-- auras are secret ("Auras cannot be accessed when secret while tainted by
-- 'SimpleFrame'"), which is every target in combat. Blizzard's own code is not
-- tainted, so SimpleFrame borrows its target aura display whole rather than
-- reading aura data at all. See Blizzard.lua.
