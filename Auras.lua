-- SimpleFrame - Auras
-- Buff and debuff icon grid for the target frame. Buffs grow upward above the
-- frame, debuffs downward below it (clearing the cast bar).

local addonName, SF = ...

local floor = math.floor

-- Plain filters only. The compound "HARMFUL|PLAYER" form returns nothing
-- through the slot API on 12.x, so "only my debuffs" is applied afterwards by
-- checking isFromPlayerOrPlayerPet on each aura.
local BUFF_FILTER = "HELPFUL"
local DEBUFF_FILTER = "HARMFUL"
local MAX_ICONS = 32
local ICON_GAP = 2

-- Blizzard's DebuffTypeColor global was removed in 12.0; the engine-side
-- replacement (C_UnitAuras.GetAuraDispelTypeColor with a color curve) exists for
-- cases where dispelName is secret. Aura enumeration is refused outright in
-- those contexts, so any aura we can actually see here has a readable
-- dispelName and a plain lookup is enough. These are the classic values.
local DISPEL_COLORS = {
	Magic   = { r = 0.20, g = 0.60, b = 1.00 },
	Curse   = { r = 0.60, g = 0.00, b = 1.00 },
	Disease = { r = 0.60, g = 0.40, b = 0.00 },
	Poison  = { r = 0.00, g = 0.60, b = 0.00 },
}

local DEBUFF_DEFAULT_COLOR = { r = 0.80, g = 0.10, b = 0.10 }
local STEALABLE_COLOR = { r = 0.30, g = 0.60, b = 1.00 }

local PLACEHOLDER_BUFF_COLOR = { r = 0.00, g = 0.00, b = 0.00 }
local PLACEHOLDER_TEXTURE = "Interface\\Icons\\INV_Misc_QuestionMark"

-- Reused between the buff and debuff passes, which never run concurrently.
local auraScratch = {}

local function OnAuraEnter(self)
	if not self.auraInstanceID then return end

	GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
	if self.isHarmful then
		GameTooltip:SetUnitDebuffByAuraInstanceID(self.unit, self.auraInstanceID)
	else
		GameTooltip:SetUnitBuffByAuraInstanceID(self.unit, self.auraInstanceID)
	end
	GameTooltip:Show()
end

local function CreateAuraIcon(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(22, 22)

	b.border = b:CreateTexture(nil, "BACKGROUND")
	b.border:SetPoint("TOPLEFT", -1, 1)
	b.border:SetPoint("BOTTOMRIGHT", 1, -1)

	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	b.cd:SetAllPoints()
	b.cd:SetDrawEdge(false)

	b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	b.count:SetPoint("BOTTOMRIGHT", 1, 0)

	b:SetScript("OnEnter", OnAuraEnter)
	b:SetScript("OnLeave", GameTooltip_Hide)

	return b
end

-- Places one icon in the grid. `index` is 0-based within its own group, and
-- `relativeTo` is whatever the group hangs off - the unit button for real
-- auras, the anchor for placeholders.
local function PositionIcon(b, relativeTo, index, size, perRow, growUp, yOffset)
	local step = size + ICON_GAP
	local col, row = index % perRow, floor(index / perRow)

	b:ClearAllPoints()
	if growUp then
		b:SetPoint("BOTTOMLEFT", relativeTo, "TOPLEFT", col * step, yOffset + row * step)
	else
		b:SetPoint("TOPLEFT", relativeTo, "BOTTOMLEFT", col * step, -yOffset - row * step)
	end
end

-- Distance from the top of the frame to the first row above it, leaving room
-- for the classification line. The space is reserved whenever the feature is
-- on, even for a target with no label, so the rows do not jump between targets.
local function AboveOffset(frame)
	if frame.infoText and SimpleFrameDB.showTargetInfo then
		return SF.GAP + SF.INFO_HEIGHT + SF.GAP
	end
	return SF.GAP
end

-- Distance from the bottom of the frame to the first debuff row, leaving room
-- for the cast bar so the rows do not shift when a cast starts.
local function DebuffOffset(frame)
	-- Clear the target-of-target bar stacked underneath, then the cast bar.
	local offset = SF.GAP + frame:AttachedHeight()
	if frame.castBar and frame:CastBarEnabled() then
		offset = offset + SF.CAST_HEIGHT + SF.GAP
	end
	return offset
end

-- Fills `pool` from the unit's aura list and lays the icons out in rows.
-- `mineOnly` keeps just the auras you cast; `yOffset` is the distance from the
-- frame edge to the first row.
local function LayoutGroup(frame, pool, filter, isHarmful, mineOnly, growUp, yOffset)
	local db = SimpleFrameDB
	local unit = frame.unit
	local size, perRow = db.auraSize, db.aurasPerRow

	-- Zero means no auras, or a context where enumeration is refused. Both end
	-- up showing nothing, which is all this code can do about it.
	local total = SF.CollectAuras(unit, filter, MAX_ICONS, auraScratch)
	local shown = 0

	for index = 1, total do
		local aura = auraScratch[index]

		-- Fails open: an unreadable source shows the aura rather than hiding
		-- it, so your DoTs cannot vanish in the contexts that matter most.
		local keep = not mineOnly or SF.Plain(aura.isFromPlayerOrPlayerPet) ~= false

		if keep then
			shown = shown + 1

			local b = pool[shown]
			if not b then
				b = CreateAuraIcon(frame)
				pool[shown] = b
			end

			b.unit = unit
			b.isHarmful = isHarmful
			b.auraInstanceID = aura.auraInstanceID
			b.icon:SetTexture(aura.icon)
			b:SetSize(size, size)

			-- Every field below is branched on, so each one needs to be
			-- readable. Secret timings mean no swipe rather than an error.
			local duration = SF.Plain(aura.duration)
			local expires = SF.Plain(aura.expirationTime)
			if duration and expires and duration > 0 and expires > 0 then
				b.cd:SetCooldown(expires - duration, duration)
			else
				b.cd:Clear()
			end

			local stacks = SF.Plain(aura.applications)
			b.count:SetText(stacks and stacks > 1 and stacks or "")

			local color
			if isHarmful then
				local dispel = SF.Plain(aura.dispelName) -- used as a table key
				color = (dispel and DISPEL_COLORS[dispel]) or DEBUFF_DEFAULT_COLOR
			elseif SF.Plain(aura.isStealable) then
				color = STEALABLE_COLOR
			end

			if color then
				b.border:SetColorTexture(color.r, color.g, color.b, 1)
			else
				b.border:SetColorTexture(0, 0, 0, 1)
			end

			PositionIcon(b, frame, shown - 1, size, perRow, growUp, yOffset)
			b:Show()
		end
	end

	for i = shown + 1, #pool do
		pool[i]:Hide()
	end
end

local function HideGroup(pool)
	for i = 1, #pool do
		pool[i]:Hide()
	end
end

-- Dummy icons shown while the frames are unlocked, so the space the aura rows
-- will occupy is visible while positioning. They hang off the anchor rather
-- than the unit button: the button is hidden by RegisterUnitWatch when there is
-- no target, which is exactly when you are most likely to be moving things.
local function LayoutPlaceholders(frame)
	local db = SimpleFrameDB
	local pool = frame.auras.placeholders
	local anchor = frame.anchor
	local size, perRow = db.auraSize, db.aurasPerRow
	local shown = 0

	for group = 1, 2 do
		local growUp = (group == 1)
		local color = growUp and PLACEHOLDER_BUFF_COLOR or DEBUFF_DEFAULT_COLOR
		local yOffset = growUp and AboveOffset(frame) or DebuffOffset(frame)

		for i = 1, perRow do
			shown = shown + 1

			local b = pool[shown]
			if not b then
				b = CreateAuraIcon(anchor)
				b:EnableMouse(false) -- purely decorative, never eat a click
				pool[shown] = b
			end

			b.auraInstanceID = nil -- keeps the tooltip handler inert
			b:SetSize(size, size)
			b:SetAlpha(0.55)
			b.icon:SetTexture(PLACEHOLDER_TEXTURE)
			b.cd:Clear()
			b.count:SetText("")
			b.border:SetColorTexture(color.r, color.g, color.b, 1)

			PositionIcon(b, anchor, i - 1, size, perRow, growUp, yOffset)
			b:Show()
		end
	end

	for i = shown + 1, #pool do
		pool[i]:Hide()
	end
end

function SF:UpdateAuras(frame)
	if not frame.opts.auras then return end

	local auras = frame.auras
	if not auras then
		auras = { buffs = {}, debuffs = {}, placeholders = {} }
		frame.auras = auras
	end

	local db = SimpleFrameDB

	-- Blizzard's own aura display is being used instead, so draw nothing here.
	if db.blizzardTargetAuras then
		HideGroup(auras.buffs)
		HideGroup(auras.debuffs)
		HideGroup(auras.placeholders)
		return
	end

	-- While unlocked the placeholders stand in for the real icons, so the
	-- footprint is the same whether or not anything is targeted.
	if SF.unlocked and db.showAuras then
		HideGroup(auras.buffs)
		HideGroup(auras.debuffs)
		LayoutPlaceholders(frame)
		return
	end
	HideGroup(auras.placeholders)

	if not db.showAuras or not UnitExists(frame.unit) then
		HideGroup(auras.buffs)
		HideGroup(auras.debuffs)
		return
	end

	-- On a friendly target the debuffs are the ones you act on, so they take the
	-- top row and the buffs move below. A unit we cannot read reliably falls
	-- through to the hostile arrangement.
	local friendly = SF.Plain(UnitIsFriend("player", frame.unit)) and true or false

	local above, below = AboveOffset(frame), DebuffOffset(frame)

	-- On enemies, only the debuffs you applied (your DoTs). On friendly targets
	-- that would be empty in practice - you do not debuff your own side - so the
	-- promoted top row shows every debuff, which is what you would dispel.
	local mineOnly = not friendly

	--          frame, pool,           filter,         isHarmful, mineOnly, growUp, yOffset
	if friendly then
		LayoutGroup(frame, auras.debuffs, DEBUFF_FILTER, true,  mineOnly, true,  above)
		LayoutGroup(frame, auras.buffs,   BUFF_FILTER,   false, false,    false, below)
	else
		LayoutGroup(frame, auras.buffs,   BUFF_FILTER,   false, false,    true,  above)
		LayoutGroup(frame, auras.debuffs, DEBUFF_FILTER, true,  mineOnly, false, below)
	end
end
