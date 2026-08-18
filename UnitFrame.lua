-- SimpleFrame - UnitFrame
-- Builds a secure unit button (health bar, power bar, texts, cast bar) sitting
-- inside a plain anchor frame that owns the saved position.

local addonName, SF = ...

local floor, max = math.floor, math.max

local UnitFrameMixin = {}
SF.UnitFrameMixin = UnitFrameMixin

-- Fills a bar with a generated solid-color texture. Using SetColorTexture
-- rather than a texture file means there is no gradient and no edge bleed from
-- stretching a small source image across the bar's width.
local function SetSolidFill(bar)
	local fill = bar:CreateTexture(nil, "ARTWORK")
	fill:SetColorTexture(1, 1, 1)
	bar:SetStatusBarTexture(fill)
end

local function CreateBar(parent)
	local bar = CreateFrame("StatusBar", nil, parent)
	SetSolidFill(bar)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(1)

	local bg = bar:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.6)
	bar.bg = bg

	return bar
end

-- Returns the max to hand to SetMinMaxValues. A secret max goes through
-- untouched; only a max we can actually read gets sanity-checked against zero.
local function SafeMax(max)
	local plain = SF.Plain(max)
	if plain and plain <= 0 then
		return 1
	end
	return max
end

--------------------------------------------------------------------------------
-- Element construction
--------------------------------------------------------------------------------

function UnitFrameMixin:BuildElements()
	local health = CreateBar(self)
	health:SetPoint("TOPLEFT")
	health:SetPoint("TOPRIGHT")
	self.health = health

	self.healthText = health:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	self.healthText:SetPoint("RIGHT", health, "RIGHT", -4, 0)
	self.healthText:SetJustifyH("RIGHT")

	self.nameText = health:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	self.nameText:SetPoint("LEFT", health, "LEFT", 4, 0)
	self.nameText:SetPoint("RIGHT", self.healthText, "LEFT", -4, 0)
	self.nameText:SetJustifyH("LEFT")
	self.nameText:SetWordWrap(false)

	if not self.opts.noPower then
		local power = CreateBar(self)
		power:SetPoint("TOPLEFT", health, "BOTTOMLEFT", 0, -1)
		power:SetPoint("TOPRIGHT", health, "BOTTOMRIGHT", 0, -1)
		self.power = power

		self.powerText = power:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		self.powerText:SetPoint("RIGHT", power, "RIGHT", -4, 0)
	end

	if self.opts.infoText then
		local info = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		info:SetPoint("BOTTOMLEFT", self, "TOPLEFT", 0, SF.GAP)
		info:SetPoint("BOTTOMRIGHT", self, "TOPRIGHT", 0, SF.GAP)
		info:SetJustifyH("LEFT")
		info:SetWordWrap(false)
		info:SetTextColor(0.9, 0.82, 0.55)
		self.infoText = info
	end

	if self.opts.combatBorder then
		self:BuildCombatBorder()
	end

	if self.opts.castBar then
		self:BuildCastBar()
	end
end

-- Four 1px edges just outside the frame rather than one inset texture behind
-- it: a single backdrop would also show through the 1px seam between the health
-- and power bars, drawing a red line across the middle of the frame.
function UnitFrameMixin:BuildCombatBorder()
	local edges = {}

	local function Edge()
		local t = self:CreateTexture(nil, "OVERLAY")
		t:SetColorTexture(0.9, 0.15, 0.15, 1)
		t:Hide()
		edges[#edges + 1] = t
		return t
	end

	-- Top and bottom run 1px wide on each side so the corners close up.
	local top = Edge()
	top:SetPoint("BOTTOMLEFT", self, "TOPLEFT", -1, 0)
	top:SetPoint("BOTTOMRIGHT", self, "TOPRIGHT", 1, 0)
	top:SetHeight(1)

	local bottom = Edge()
	bottom:SetPoint("TOPLEFT", self, "BOTTOMLEFT", -1, 0)
	bottom:SetPoint("TOPRIGHT", self, "BOTTOMRIGHT", 1, 0)
	bottom:SetHeight(1)

	local left = Edge()
	left:SetPoint("TOPRIGHT", self, "TOPLEFT", 0, 0)
	left:SetPoint("BOTTOMRIGHT", self, "BOTTOMLEFT", 0, 0)
	left:SetWidth(1)

	local right = Edge()
	right:SetPoint("TOPLEFT", self, "TOPRIGHT", 0, 0)
	right:SetPoint("BOTTOMLEFT", self, "BOTTOMRIGHT", 0, 0)
	right:SetWidth(1)

	self.combatBorder = edges
end

function UnitFrameMixin:UpdateCombatIndicator()
	local edges = self.combatBorder
	if not edges then return end

	local show = SF.inCombat and SimpleFrameDB.showCombatBorder and true or false
	for i = 1, #edges do
		edges[i]:SetShown(show)
	end
end

function UnitFrameMixin:BuildCastBar()
	local cb = CreateFrame("StatusBar", nil, self)
	SetSolidFill(cb)
	cb:SetMinMaxValues(0, 1)
	cb:SetFrameLevel(self:GetFrameLevel() + 2)

	local bg = cb:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.6)

	cb.icon = cb:CreateTexture(nil, "ARTWORK")
	cb.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	cb.icon:SetPoint("RIGHT", cb, "LEFT", -2, 0)

	cb.time = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	cb.time:SetPoint("RIGHT", cb, "RIGHT", -4, 0)

	cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	cb.text:SetPoint("LEFT", cb, "LEFT", 4, 0)
	cb.text:SetPoint("RIGHT", cb.time, "LEFT", -4, 0)
	cb.text:SetJustifyH("LEFT")
	cb.text:SetWordWrap(false)

	cb:Hide()
	self.castBar = cb
end

--------------------------------------------------------------------------------
-- Updates
--------------------------------------------------------------------------------

function UnitFrameMixin:UpdateName()
	local unit = self.unit
	local name = UnitName(unit)

	-- The name itself may be secret, so it is only ever passed to a widget
	-- setter - never concatenated or run through string.format.
	local level = self.opts.showLevel and SF.Plain(UnitLevel(unit)) or nil

	if level and level > 0 then
		self.nameText:SetFormattedText("%d %s", level, name)
	elseif level == -1 then
		self.nameText:SetFormattedText("?? %s", name)
	else
		self.nameText:SetText(name or "")
	end
end

-- Plenty of NPCs genuinely report their creature type as "Not specified",
-- which is noise on the frame. Prefer the client's own localized constant so
-- this keeps working outside enUS, and fall back to the literal.
local NOT_SPECIFIED = _G.CREATURE_TYPE_NOT_SPECIFIED or "Not specified"

-- "normal" is deliberately absent: an ordinary mob contributes no label, so the
-- line reads just "Humanoid" rather than "Normal Humanoid".
local CLASSIFICATIONS = {
	worldboss = "Boss",
	rareelite = "Rare Elite",
	elite = "Elite",
	rare = "Rare",
	minus = "Minion",
}

-- Classification and creature type above the frame, e.g. "Rare Elite Beast" or
-- "Night Elf Druid". Every read goes through SF.Plain, so only values that are
-- actually readable reach the concat - a secret contributes nothing instead of
-- raising.
function UnitFrameMixin:UpdateInfoText()
	local fs = self.infoText
	if not fs then return end

	if not SimpleFrameDB.showTargetInfo or not UnitExists(self.unit) then
		fs:SetText("")
		return
	end

	local unit = self.unit
	local parts = {}

	local classification = SF.Plain(UnitClassification(unit))
	local label = classification and CLASSIFICATIONS[classification]
	if label then parts[#parts + 1] = label end

	if SF.Plain(UnitIsPlayer(unit)) then
		local race = SF.Plain(UnitRace(unit))
		if race then parts[#parts + 1] = race end

		local class = SF.Plain(UnitClass(unit))
		if class then parts[#parts + 1] = class end
	else
		local creatureType = SF.Plain(UnitCreatureType(unit))
		if creatureType and creatureType ~= NOT_SPECIFIED then
			parts[#parts + 1] = creatureType
		end
	end

	fs:SetText(table.concat(parts, " "))
end

function UnitFrameMixin:UpdateHealthColor()
	local unit = self.unit
	local r, g, b

	-- These are compared explicitly against true/false: a secret reads as nil
	-- here and falls through to the normal reaction/class coloring rather than
	-- being mistaken for "disconnected".
	local connected = SF.Plain(UnitIsConnected(unit))
	local dead = SF.Plain(UnitIsDeadOrGhost(unit))
	local isPlayer = SF.Plain(UnitIsPlayer(unit))

	if connected == false then
		r, g, b = 0.5, 0.5, 0.5
	elseif dead == true then
		r, g, b = 0.35, 0.35, 0.35
	elseif SimpleFrameDB.classColor and isPlayer then
		local _, class = UnitClass(unit)
		class = SF.Plain(class) -- used as a table key, so it must be readable
		local color = class and C_ClassColor.GetClassColor(class)
		if color then
			r, g, b = color.r, color.g, color.b
		end
	else
		r, g, b = UnitSelectionColor(unit, true)
	end

	if not r then r, g, b = 0.2, 0.75, 0.2 end
	self.health:SetStatusBarColor(r, g, b)
end

-- Health text goes through the widget's own formatter. AbbreviateNumbers and
-- SetFormattedText both accept secret numbers; string.format does not.
function UnitFrameMixin:UpdateHealthText()
	local mode = SimpleFrameDB.healthTextMode
	local fs = self.healthText

	if mode == 0 then
		fs:SetText("")
		return
	end

	local unit = self.unit
	if mode == 1 then
		fs:SetText(AbbreviateNumbers(UnitHealth(unit)))
	elseif mode == 2 then
		fs:SetFormattedText("%d%%", SF.HealthPercent(unit))
	else
		fs:SetFormattedText("%s  %d%%", AbbreviateNumbers(UnitHealth(unit)), SF.HealthPercent(unit))
	end
end

function UnitFrameMixin:UpdateHealth()
	local unit = self.unit

	-- Hand the raw values to the status bar. Comparing them here is what
	-- raises "attempt to compare a secret number value".
	self.health:SetMinMaxValues(0, SafeMax(UnitHealthMax(unit)))
	self.health:SetValue(UnitHealth(unit))

	self:UpdateHealthText()
	self:UpdateHealthColor()
end

function UnitFrameMixin:UpdatePowerColor()
	local power = self.power
	if not power then return end

	local _, token, altR, altG, altB = UnitPowerType(self.unit)
	local color = token and PowerBarColor[token]

	if color then
		power:SetStatusBarColor(color.r, color.g, color.b)
	elseif altR then
		power:SetStatusBarColor(altR, altG, altB)
	else
		power:SetStatusBarColor(0.3, 0.4, 0.9)
	end
end

function UnitFrameMixin:UpdatePower()
	local power = self.power
	if not power then return end

	local unit = self.unit
	local cur, max = UnitPower(unit), UnitPowerMax(unit)

	power:SetMinMaxValues(0, SafeMax(max))
	power:SetValue(cur)

	if self.powerText then
		-- A readable maximum of zero means the unit has no power bar at all.
		-- A secret maximum reads as nil here, so the value is shown.
		if SF.Plain(max) == 0 then
			self.powerText:SetText("")
		else
			self.powerText:SetText(AbbreviateNumbers(cur))
		end
	end
end

function UnitFrameMixin:UpdateDisplayPower()
	self:UpdatePower()
	self:UpdatePowerColor()
end

--------------------------------------------------------------------------------
-- Cast bar
--------------------------------------------------------------------------------

local function StopCast(cb)
	cb:SetScript("OnUpdate", nil)
	cb:Hide()
end

local function CastBarOnUpdate(cb)
	local now = GetTime()

	if cb.channeling then
		local remaining = cb.endTime - now
		if remaining <= 0 then return StopCast(cb) end
		cb:SetValue(remaining)
		cb.time:SetFormattedText("%.1f", remaining)
	else
		if now >= cb.endTime then return StopCast(cb) end
		cb:SetValue(now - cb.startTime)
		cb.time:SetFormattedText("%.1f", cb.endTime - now)
	end
end

-- Whether this frame's cast bar is turned on. Each frame carries its own
-- setting key, so the player and target bars toggle independently.
function UnitFrameMixin:CastBarEnabled()
	local key = self.opts.castBarKey
	return (key and SimpleFrameDB[key]) and true or false
end

function UnitFrameMixin:UpdateCast()
	local cb = self.castBar
	if not cb then return end

	if not self:CastBarEnabled() or not UnitExists(self.unit) then
		return StopCast(cb)
	end

	local unit = self.unit
	local channeling = false
	local name, text, texture, startMS, endMS, _, _, notInterruptible = UnitCastingInfo(unit)

	if not name then
		-- UnitChannelInfo has no castID return, so notInterruptible shifts left.
		local nInterruptible
		name, text, texture, startMS, endMS, _, nInterruptible = UnitChannelInfo(unit)
		notInterruptible = nInterruptible
		channeling = name ~= nil
	end

	-- The OnUpdate handler compares these against GetTime(), so timings we
	-- cannot read mean no cast bar rather than an error.
	startMS, endMS = SF.Plain(startMS), SF.Plain(endMS)
	if not name or not startMS or not endMS then
		return StopCast(cb)
	end

	cb.channeling = channeling
	cb.startTime = startMS / 1000
	cb.endTime = endMS / 1000

	local duration = cb.endTime - cb.startTime
	cb:SetMinMaxValues(0, duration > 0 and duration or 1)
	cb:SetValue(channeling and (cb.endTime - GetTime()) or (GetTime() - cb.startTime))

	cb.text:SetText(text or name)
	cb.icon:SetTexture(texture)

	if notInterruptible then
		cb:SetStatusBarColor(0.6, 0.6, 0.6)
	elseif channeling then
		cb:SetStatusBarColor(0.2, 0.7, 0.9)
	else
		cb:SetStatusBarColor(0.9, 0.7, 0.2)
	end

	cb:SetScript("OnUpdate", CastBarOnUpdate)
	cb:Show()
end

--------------------------------------------------------------------------------
-- Aggregate update
--------------------------------------------------------------------------------

function UnitFrameMixin:UpdateAll()
	if not UnitExists(self.unit) then
		if self.castBar then StopCast(self.castBar) end
		if self.opts.auras then SF:UpdateAuras(self) end
		self:UpdateInfoText()
		return
	end

	self:UpdateName()
	self:UpdateHealth()
	self:UpdateDisplayPower()
	self:UpdateCast()
	self:UpdateInfoText()

	if self.opts.auras then
		SF:UpdateAuras(self)
	end
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

function UnitFrameMixin:RestorePosition()
	local anchor = self.anchor
	anchor:ClearAllPoints()

	if self.opts.attached then
		local parent = SF.frames[self.opts.attachTo]
		if parent then
			anchor:SetPoint("LEFT", parent.anchor, "RIGHT", 6, 0)
		else
			anchor:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
		end
		return
	end

	local saved = SimpleFrameDB.pos[self.key]
	if saved and saved.point then
		anchor:SetPoint(saved.point, UIParent, saved.relPoint or saved.point, saved.x or 0, saved.y or 0)
	else
		local d = SF.defaultPos[self.key] or { "CENTER", 0, 0 }
		anchor:SetPoint(d[1], UIParent, d[1], d[2], d[3])
	end
end

function UnitFrameMixin:ApplyLayout()
	local db = SimpleFrameDB
	local opts = self.opts

	local heightScale = opts.heightScale or 1
	local width = db.width * (opts.widthScale or 1)
	local barHeight = db.height * heightScale
	-- Scaled alongside the health bar, so a shrunken frame keeps its
	-- proportions instead of pairing a small health bar with a full-size one.
	local powerHeight = self.power and max(1, floor(db.powerHeight * heightScale + 0.5)) or 0
	local total = barHeight + (powerHeight > 0 and powerHeight + 1 or 0)

	self.anchor:SetSize(width, total)
	self.anchor:SetScale(db.scale)
	self.health:SetHeight(barHeight)

	if self.power then
		self.power:SetHeight(powerHeight)
	end

	if self.castBar then
		self.castBar:SetSize(width, SF.CAST_HEIGHT)
		self.castBar:ClearAllPoints()
		self.castBar:SetPoint("TOP", self, "BOTTOM", 0, -SF.GAP)
		self.castBar.icon:SetSize(SF.CAST_HEIGHT, SF.CAST_HEIGHT)
	end

	self:RestorePosition()
end

-- Named SetFrameEnabled rather than SetEnabled so it does not shadow the
-- Button:SetEnabled method the mixin is applied on top of.
function UnitFrameMixin:SetFrameEnabled(enabled)
	if self.unit == "player" then
		self:SetShown(enabled)
	else
		-- A unit-watched frame's visibility belongs to the state driver, so
		-- unregister before hiding it by hand.
		if enabled then
			if not self.watched then
				RegisterUnitWatch(self)
				self.watched = true
			end
		else
			if self.watched then
				UnregisterUnitWatch(self)
				self.watched = false
			end
			self:Hide()
		end
	end

	self.anchor:SetShown(enabled)
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local HANDLERS = {
	UNIT_HEALTH = "UpdateHealth",
	UNIT_MAXHEALTH = "UpdateHealth",
	UNIT_POWER_UPDATE = "UpdatePower",
	UNIT_MAXPOWER = "UpdatePower",
	UNIT_DISPLAYPOWER = "UpdateDisplayPower",
	UNIT_NAME_UPDATE = "UpdateName",
	UNIT_LEVEL = "UpdateName",
	-- Full update, not just a recolor: friendliness also decides whether the
	-- buff or the debuff row sits above the frame.
	UNIT_FACTION = "UpdateAll",
	UNIT_CONNECTION = "UpdateAll",
	UNIT_CLASSIFICATION_CHANGED = "UpdateInfoText",
}

local CAST_EVENTS = {
	"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
	"UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED",
	"UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE",
	"UNIT_SPELLCAST_CHANNEL_STOP",
	"UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_UPDATE",
	"UNIT_SPELLCAST_EMPOWER_STOP",
	"UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
}

local function OnEvent(self, event)
	local method = HANDLERS[event]
	if method then
		self[method](self)
	elseif event == "UNIT_AURA" then
		SF:UpdateAuras(self)
	else
		self:UpdateCast()
	end
end

function UnitFrameMixin:RegisterEvents()
	local unit = self.unit

	-- "targettarget" is not a token the UNIT_* events fire for, so polled
	-- frames get an OnUpdate refresh instead of event registration.
	if self.opts.poll then
		local interval, elapsed = self.opts.poll, 0
		self:SetScript("OnUpdate", function(frame, delta)
			elapsed = elapsed + delta
			if elapsed >= interval then
				elapsed = 0
				frame:UpdateAll()
			end
		end)
		return
	end

	self:SetScript("OnEvent", OnEvent)

	for event in pairs(HANDLERS) do
		self:RegisterUnitEvent(event, unit)
	end

	if self.opts.castBar then
		for _, event in ipairs(CAST_EVENTS) do
			self:RegisterUnitEvent(event, unit)
		end
	end

	if self.opts.auras then
		self:RegisterUnitEvent("UNIT_AURA", unit)
	end
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

function SF:CreateUnitFrame(key, unit, opts)
	local anchor = CreateFrame("Frame", "SimpleFrame" .. key .. "Anchor", UIParent)
	anchor:SetMovable(true)
	anchor:SetClampedToScreen(true)
	anchor:SetSize(SimpleFrameDB.width, SimpleFrameDB.height)

	local f = CreateFrame("Button", "SimpleFrame" .. key, anchor, "SecureUnitButtonTemplate")
	f:SetAllPoints(anchor)
	f:RegisterForClicks("AnyUp")
	f:SetAttribute("unit", unit)
	f:SetAttribute("*type1", "target")
	f:SetAttribute("*type2", "togglemenu")

	f.unit = unit
	f.key = key
	f.opts = opts or {}
	f.anchor = anchor
	anchor.owner = f

	Mixin(f, SF.UnitFrameMixin)

	f:BuildElements()
	f:RegisterEvents()

	f:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetUnit(self.unit)
		GameTooltip:Show()
	end)
	f:HookScript("OnLeave", GameTooltip_Hide)

	-- Click-casting addons (Clique, and anything using the same convention)
	-- pick frames up from this global registry. Setting the key is the whole
	-- protocol and works in either load order: if Clique is already loaded its
	-- metatable registers the frame now, and if it loads later it re-registers
	-- everything it finds already in the table.
	--
	-- Clique writes specific attributes (type1, ctrl-type1, ...), which outrank
	-- the *type1 / *type2 wildcards set above. Bound buttons run the binding,
	-- unbound ones fall through to target and unit menu.
	ClickCastFrames = ClickCastFrames or {}
	ClickCastFrames[f] = true

	SF.frames[key] = f
	return f
end
