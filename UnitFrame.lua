-- SimpleFrame - UnitFrame
-- Builds a secure unit button (health bar, power bar, texts, cast bar) sitting
-- inside a plain anchor frame that owns the saved position.

local addonName, SF = ...

local floor, max = math.floor, math.max

local MARKER_SIZE = 14

-- Horizontal inset shared by the bar text and the band above the frame, so the
-- loadout line starts on the same edge as the unit's level and name.
local TEXT_INSET = 4

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
-- Native icons
--------------------------------------------------------------------------------
-- Blizzard's own target frame carries these assets, so the first choice is to
-- read the atlas or file path straight off the live element - correct by
-- construction, whatever the client currently ships. Failing that, candidate
-- atlas names can be validated with C_Texture.GetAtlasInfo, which returns nil
-- for one that does not exist, and file paths with GetFileIDFromPath. Only a
-- verified asset is used; otherwise the caller falls back to a letter, which
-- cannot silently fail to render.

local function LiveAsset(path)
	local ok, element = pcall(function()
		local ctx = TargetFrame and TargetFrame.TargetFrameContent
			and TargetFrame.TargetFrameContent.TargetFrameContentContextual
		return ctx and ctx[path]
	end)
	if not ok or not element then return nil end

	local atlas = element.GetAtlas and element:GetAtlas()
	if atlas then return { atlas = atlas } end

	local file = element.GetTexture and element:GetTexture()
	if file then return { texture = file } end
end

local function ValidAtlas(names)
	if not (C_Texture and C_Texture.GetAtlasInfo) then return nil end
	for _, name in ipairs(names) do
		if C_Texture.GetAtlasInfo(name) then return { atlas = name } end
	end
end

local function ValidPath(paths)
	if not GetFileIDFromPath then return nil end
	for _, file in ipairs(paths) do
		if GetFileIDFromPath(file) then return { texture = file } end
	end
end

local ICON_SPECS = {
	quest = {
		live = "QuestIcon",
		atlases = { "QuestNormal", "questlog-questtypeicon-quest" },
		paths = { "Interface\\TargetingFrame\\PortraitQuestBadge" },
	},
	leader = {
		live = "LeaderIcon",
		atlases = { "UI-HUD-UnitFrame-Player-Group-LeaderIcon", "UI-LFG-RoleIcon-Leader" },
		paths = { "Interface\\GroupFrame\\UI-Group-LeaderIcon" },
	},
	assist = {
		-- No live source: Blizzard reuses LeaderIcon and swaps its texture by
		-- state, so reading it would give whichever role is current.
		atlases = { "UI-HUD-UnitFrame-Player-Group-AssistIcon", "UI-LFG-RoleIcon-Assist" },
		paths = { "Interface\\GroupFrame\\UI-Group-AssistantIcon" },
	},
}

-- Resolved on first use rather than at load: Blizzard's frames must exist, and
-- false is cached for a miss so the lookup is not retried every update.
local iconCache = {}

local function NativeIcon(key)
	local cached = iconCache[key]
	if cached ~= nil then return cached or nil end

	local spec = ICON_SPECS[key]
	local asset = (spec.live and LiveAsset(spec.live))
		or ValidAtlas(spec.atlases)
		or ValidPath(spec.paths)
		or false

	iconCache[key] = asset
	return asset or nil
end

-- A marker that prefers the native icon and falls back to a letter.
local function CreateMarker(parent, size)
	local m = CreateFrame("Frame", nil, parent)
	m:SetSize(size, size)

	m.tex = m:CreateTexture(nil, "OVERLAY")
	m.tex:SetAllPoints()
	m.tex:Hide()

	m.label = m:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	m.label:SetPoint("CENTER")
	m.label:Hide()

	m:Hide()
	return m
end

local function ShowMarker(m, key, letter, r, g, b)
	local asset = NativeIcon(key)
	if asset then
		if asset.atlas then m.tex:SetAtlas(asset.atlas) else m.tex:SetTexture(asset.texture) end
		m.tex:Show()
		m.label:Hide()
	else
		m.label:SetText(letter)
		m.label:SetTextColor(r, g, b)
		m.label:Show()
		m.tex:Hide()
	end
	m:Show()
end

--------------------------------------------------------------------------------
-- Element construction
--------------------------------------------------------------------------------

function UnitFrameMixin:BuildElements()
	local health = CreateBar(self)
	health:SetPoint("TOPLEFT")
	health:SetPoint("TOPRIGHT")
	self.health = health

	-- Text lives on its own layer above the heal-prediction overlays, which are
	-- drawn in the health bar's empty region and would otherwise cover it.
	local textLayer = CreateFrame("Frame", nil, self)
	textLayer:SetAllPoints(health)
	textLayer:SetFrameLevel(health:GetFrameLevel() + 3)
	self.textLayer = textLayer

	self.healthText = textLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	self.healthText:SetPoint("RIGHT", health, "RIGHT", -TEXT_INSET, 0)
	self.healthText:SetJustifyH("RIGHT")

	self.nameText = textLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	self.nameText:SetPoint("LEFT", health, "LEFT", TEXT_INSET, 0)
	self.nameText:SetPoint("RIGHT", self.healthText, "LEFT", -TEXT_INSET, 0)
	self.nameText:SetJustifyH("LEFT")
	self.nameText:SetWordWrap(false)

	if self.opts.groupNumber then
		local num = textLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		num:SetPoint("CENTER", health, "CENTER", 0, 0)
		num:SetTextColor(0.75, 0.82, 1)
		self.groupNumber = num
	end

	self:BuildHealthPrediction()

	if not self.opts.noPower then
		local power = CreateBar(self)
		power:SetPoint("TOPLEFT", health, "BOTTOMLEFT", 0, -1)
		power:SetPoint("TOPRIGHT", health, "BOTTOMRIGHT", 0, -1)
		self.power = power

		self.powerText = power:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		self.powerText:SetPoint("RIGHT", power, "RIGHT", -4, 0)

		-- The power bar hangs a pixel below the health bar so the two read as
		-- separate bars. Nothing covers that seam - the bars are child frames,
		-- so their own backgrounds stop at their edges - and the world shows
		-- through it. Fill it with the same tint the bar backgrounds use.
		local seam = self:CreateTexture(nil, "BACKGROUND")
		seam:SetPoint("TOPLEFT", health, "BOTTOMLEFT", 0, 0)
		seam:SetPoint("BOTTOMRIGHT", power, "TOPRIGHT", 0, 0)
		seam:SetColorTexture(0, 0, 0, 0.6)
		self.barSeam = seam
	end

	if self.opts.infoText then
		local info = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		info:SetPoint("BOTTOMLEFT", self, "TOPLEFT", TEXT_INSET, SF.GAP)
		info:SetPoint("BOTTOMRIGHT", self, "TOPRIGHT", -TEXT_INSET, SF.GAP)
		info:SetJustifyH("LEFT")
		info:SetWordWrap(false)
		info:SetTextColor(0.9, 0.82, 0.55)
		self.infoText = info
	end

	-- Backing for the band above the frame. Created for any frame that puts
	-- something up there, and on the BACKGROUND layer so the text sits on top;
	-- the markers are child frames and draw above it regardless.
	if self.opts.loadoutText or self.opts.infoText
		or self.opts.questIcon or self.opts.groupIcon then
		local band = self:CreateTexture(nil, "BACKGROUND")
		band:SetPoint("BOTTOMLEFT", self, "TOPLEFT", 0, 0)
		band:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, SF.GAP + MARKER_SIZE)
		band:SetColorTexture(0, 0, 0, 0.6)
		band:Hide()
		self.topBackdrop = band
	end

	if self.opts.loadoutText then
		local loadout = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		loadout:SetPoint("BOTTOMLEFT", self, "TOPLEFT", TEXT_INSET, SF.GAP)
		loadout:SetPoint("BOTTOMRIGHT", self, "TOPRIGHT", -TEXT_INSET, SF.GAP)
		loadout:SetJustifyH("LEFT")
		loadout:SetWordWrap(false)
		loadout:SetTextColor(0.9, 0.82, 0.55)
		self.loadoutText = loadout
	end

	if self.opts.questIcon then
		-- Shares the band above the frame with the classification line, which
		-- is left-justified, so the right end is free.
		self.questIcon = CreateMarker(self, MARKER_SIZE)
	end

	if self.opts.groupIcon then
		self.groupIcon = CreateMarker(self, MARKER_SIZE)
	end

	-- Right-to-left order in the corner. Positions are assigned by
	-- LayoutMarkers, since which of these is showing varies.
	self.markers = {}
	if self.groupIcon then self.markers[#self.markers + 1] = self.groupIcon end
	if self.questIcon then self.markers[#self.markers + 1] = self.questIcon end

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

-- Read rather than hardcoded, so this keeps working across expansions. Both
-- forms are present in 12.x; prefer the expansion-aware one.
local function MaxPlayerLevel()
	local get = GetMaxLevelForPlayerExpansion or GetMaxPlayerLevel
	if not get then return nil end

	local ok, level = pcall(get)
	return ok and SF.Plain(level) or nil
end

function UnitFrameMixin:UpdateName()
	local unit = self.unit
	local name = UnitName(unit)

	-- The name itself may be secret, so it is only ever passed to a widget
	-- setter - never concatenated or run through string.format.
	local level = self.opts.showLevel and SF.Plain(UnitLevel(unit)) or nil

	-- Your own level at the cap carries no information, so it is dropped. The
	-- target's is kept: there, the number still distinguishes one mob from
	-- another.
	if level and self.opts.hideMaxLevel and level == MaxPlayerLevel() then
		level = nil
	end

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

-- Incoming heals and damage absorbs, drawn in the empty part of the health bar.
--
-- Nothing here is computed in Lua. Secret numbers may be handed to a widget
-- setter but never added, compared or formatted, so the overlays are anchored
-- to the health fill's own texture - whose right edge already sits exactly
-- where the fill ends - and scaled against missing health, which the engine's
-- prediction calculator reports directly.
function UnitFrameMixin:BuildHealthPrediction()
	if not CreateUnitHealPredictionCalculator then return end

	local health = self.health
	local fill = health:GetStatusBarTexture()
	local base = health:GetFrameLevel()

	local function Overlay(level, r, g, b)
		local bar = CreateFrame("StatusBar", nil, self)
		SetSolidFill(bar)
		bar:SetFrameLevel(level)
		bar:SetStatusBarColor(r, g, b)
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(0)
		-- Starts at the fill edge and runs to the end of the bar, so its width
		-- is the missing-health region.
		bar:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0)
		bar:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
		bar:Hide()
		return bar
	end

	-- Both start at the fill edge; incoming heals draw over the shield, so a
	-- larger shield shows as blue continuing past the green.
	self.absorbBar = Overlay(base + 1, 0.60, 0.78, 1.00)
	self.incomingBar = Overlay(base + 2, 0.30, 0.85, 0.45)

	local calc = CreateUnitHealPredictionCalculator()
	calc:SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MaximumHealth)
	calc:SetHealAbsorbClampMode(Enum.UnitHealAbsorbClampMode.MaximumHealth)
	calc:SetHealAbsorbMode(Enum.UnitHealAbsorbMode.Total)
	calc:SetIncomingHealClampMode(Enum.UnitIncomingHealClampMode.MissingHealth)
	calc:SetIncomingHealOverflowPercent(1)
	self.healCalculator = calc
end

function UnitFrameMixin:UpdateHealthPrediction()
	local calc = self.healCalculator
	if not calc then return end

	local incoming, absorb = self.incomingBar, self.absorbBar

	if not SimpleFrameDB.showHealPrediction or not UnitExists(self.unit) then
		incoming:Hide()
		absorb:Hide()
		return
	end

	UnitGetDetailedHealPrediction(self.unit, nil, calc)

	local missing = calc:GetMissingHealth()
	local heals = calc:GetTotalIncomingHeals()
	local shield = calc:GetDamageAbsorbs()

	-- Scaled against missing health because the bars occupy exactly that space.
	-- A zero amount handed to SetAlpha resolves to 0 and hides the bar, while
	-- any positive amount clamps to 1: that is how an unreadable value is
	-- tested for "is there any" without comparing it.
	absorb:SetMinMaxValues(0, missing)
	absorb:SetValue(shield)
	absorb:SetAlpha(shield)
	absorb:Show()

	incoming:SetMinMaxValues(0, missing)
	incoming:SetValue(heals)
	incoming:SetAlpha(heals)
	incoming:Show()
end

-- The exclamation mark Blizzard shows for units that count toward a quest.
-- UnitIsQuestBoss is the same call its own target frame uses.
-- The talent loadout name, as shown in the loadout dropdown. The chosen loadout
-- is tracked by GetLastSelectedSavedConfigID; GetActiveConfigID is the fallback,
-- and yields an unnamed config while on a starter or unsaved build.
local function ConfigName(id)
	if not id or not (C_Traits and C_Traits.GetConfigInfo) then return nil end

	local ok, info = pcall(C_Traits.GetConfigInfo, id)
	if not ok or not info then return nil end

	local name = SF.Plain(info.name)
	if name and name ~= "" then return name end
end

local function CurrentLoadoutName()
	if not C_ClassTalents then return nil end

	local specID = PlayerUtil and PlayerUtil.GetCurrentSpecID and PlayerUtil.GetCurrentSpecID()

	if specID and C_ClassTalents.GetLastSelectedSavedConfigID then
		local ok, savedID = pcall(C_ClassTalents.GetLastSelectedSavedConfigID, specID)
		local name = ok and ConfigName(savedID)
		if name then return name end
	end

	if C_ClassTalents.GetActiveConfigID then
		local ok, activeID = pcall(C_ClassTalents.GetActiveConfigID)
		if ok then return ConfigName(activeID) end
	end
end

-- Both the namespaced and the older global forms of these are current in 12.x,
-- so prefer the namespaced one and fall back.
local function CurrentSpecName()
	local getIndex = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization)
		or GetSpecialization
	local getInfo = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo)
		or GetSpecializationInfo
	if not (getIndex and getInfo) then return nil end

	local ok, index = pcall(getIndex)
	index = ok and SF.Plain(index) or nil
	if not index then return nil end

	-- Returns id, name, description, icon, role, primaryStat.
	local gotInfo, _, name = pcall(getInfo, index)
	return gotInfo and SF.Plain(name) or nil
end

-- The band above the player frame carries the elapsed combat time while
-- fighting, and the talent loadout name otherwise - falling back to the
-- specialization when no named loadout is active, which covers a starter or
-- unsaved build and any character below the spec-unlock level.
--
-- SF.combatStart is only set by PLAYER_REGEN_DISABLED, so reloading mid-fight
-- leaves it unknown. That shows the loadout name rather than a timer counting
-- from the reload, which would be a plausible-looking wrong number.
function UnitFrameMixin:UpdateLoadoutText()
	local fs = self.loadoutText
	if not fs then return end

	if SimpleFrameDB.showCombatTime and SF.inCombat and SF.combatStart then
		local elapsed = GetTime() - SF.combatStart
		fs:SetFormattedText("%d:%02d", floor(elapsed / 60), floor(elapsed % 60))
		return
	end

	if not SimpleFrameDB.showLoadoutName then
		fs:SetText("")
		return
	end

	fs:SetText(CurrentLoadoutName() or CurrentSpecName() or "")
end

-- Raid subgroup, shown in the middle of the health bar. Parties have no
-- subgroups, so this only ever appears in a raid.
function UnitFrameMixin:UpdateGroupNumber()
	local fs = self.groupNumber
	if not fs then return end

	if not SimpleFrameDB.showGroupNumber or not IsInRaid() then
		fs:SetText("")
		return
	end

	-- Walking the roster rather than using UnitInRaid, whose index is zero-based
	-- while GetRaidRosterInfo expects one-based - an easy off-by-one to inherit.
	for i = 1, GetNumGroupMembers() do
		if SF.Plain(UnitIsUnit("raid" .. i, self.unit)) == true then
			local _, _, subgroup = GetRaidRosterInfo(i)
			fs:SetText(SF.Plain(subgroup) or "")
			return
		end
	end

	fs:SetText("")
end

-- Packs the visible markers right-to-left from the frame's top-right corner.
-- Anchoring them to each other at build time left a gap where a hidden marker
-- would have been, pushing the visible one away from the corner.
function UnitFrameMixin:LayoutMarkers()
	local previous

	for _, marker in ipairs(self.markers) do
		if marker:IsShown() then
			marker:ClearAllPoints()
			if previous then
				marker:SetPoint("BOTTOMRIGHT", previous, "BOTTOMLEFT", -4, 0)
			else
				marker:SetPoint("BOTTOMRIGHT", self, "TOPRIGHT", 0, SF.GAP)
			end
			previous = marker
		end
	end
end

function UnitFrameMixin:UpdateQuestIcon()
	local icon = self.questIcon
	if not icon then return end

	if not SimpleFrameDB.showQuestIcon or not UnitExists(self.unit) then
		icon:Hide()
		self:LayoutMarkers()
		return
	end

	-- A secret reads as nil here and simply shows nothing, rather than raising.
	if SF.Plain(UnitIsQuestBoss(self.unit)) == true then
		ShowMarker(icon, "quest", "!", 1, 0.85, 0.1)
	else
		icon:Hide()
	end

	self:LayoutMarkers()
end

-- Group leader and raid assistant, the equivalent of Blizzard's crown and star.
-- Assistants only exist in raids, so in a party this only ever marks the leader.
function UnitFrameMixin:UpdateGroupIcon()
	local fs = self.groupIcon
	if not fs then return end

	if not SimpleFrameDB.showGroupIcon or not UnitExists(self.unit) or not IsInGroup() then
		fs:Hide()
		self:LayoutMarkers()
		return
	end

	-- Compared against true explicitly: a secret reads as nil here and simply
	-- marks nothing, rather than raising.
	local unit = self.unit
	if SF.Plain(UnitIsGroupLeader(unit)) == true then
		ShowMarker(fs, "leader", "L", 1, 0.82, 0)
	elseif SF.Plain(UnitIsGroupAssistant(unit)) == true then
		ShowMarker(fs, "assist", "A", 0.65, 0.78, 1)
	else
		fs:Hide()
	end

	self:LayoutMarkers()
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
	self:UpdateHealthPrediction()
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
	if not key or not SimpleFrameDB[key] then return false end

	-- Borrowing Blizzard's target frame brings its cast bar along, and that one
	-- animates its own alpha while fading, so it overwrites any attempt to hide
	-- it and cannot be suppressed in combat. Rather than stack two cast bars,
	-- ours stands down and Blizzard's serves as the target cast bar.
	if self.unit == "target" and SimpleFrameDB.blizzardTargetAuras then
		return false
	end

	return true
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
		self:UpdateQuestIcon()
		self:UpdateGroupIcon()
		self:UpdateGroupNumber()
		self:UpdateLoadoutText()
		return
	end

	self:UpdateName()
	self:UpdateHealth()
	self:UpdateDisplayPower()
	self:UpdateCast()
	self:UpdateInfoText()
	self:UpdateQuestIcon()
	self:UpdateGroupIcon()
	self:UpdateGroupNumber()
	self:UpdateLoadoutText()

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
			anchor:SetPoint("TOPLEFT", parent.anchor, "BOTTOMLEFT", 0, -SF.GAP)
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

-- Vertical space consumed directly under this frame by an attached child (the
-- target-of-target bar), including the gap above it. Everything else that sits
-- below the frame - cast bar, debuff rows - starts past this.
function UnitFrameMixin:AttachedHeight()
	local db = SimpleFrameDB
	for _, other in pairs(SF.frames) do
		if other.opts.attached and other.opts.attachTo == self.key then
			local enableKey = other.opts.enableKey
			if not enableKey or db[enableKey] then
				return db.height * (other.opts.heightScale or 1) + SF.GAP
			end
		end
	end
	return 0
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

	if self.topBackdrop then
		self.topBackdrop:SetShown(db.showTopBackdrop and true or false)
	end

	if self.castBar then
		self.castBar:SetSize(width, SF.CAST_HEIGHT)
		self.castBar:ClearAllPoints()
		self.castBar:SetPoint("TOP", self, "BOTTOM", 0, -(SF.GAP + self:AttachedHeight()))
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
	PLAYER_SPECIALIZATION_CHANGED = "UpdateLoadoutText",
	UNIT_HEAL_PREDICTION = "UpdateHealthPrediction",
	UNIT_ABSORB_AMOUNT_CHANGED = "UpdateHealthPrediction",
	UNIT_HEAL_ABSORB_AMOUNT_CHANGED = "UpdateHealthPrediction",
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
