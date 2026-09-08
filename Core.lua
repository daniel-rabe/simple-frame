-- SimpleFrame - Core
-- Addon table, saved variables, lifecycle events and slash commands.

local addonName, SF = ...

SF.frames = {}
SF.unlocked = false

-- Driven purely by PLAYER_REGEN_DISABLED/ENABLED plus InCombatLockdown on load,
-- so the indicator never depends on a value that could come back secret.
SF.inCombat = false

-- Set only when combat actually starts, so it stays nil after a reload mid-fight
-- rather than implying a start time we never saw.
SF.combatStart = nil
-- Bar fills are generated solid-color textures, not texture files - see
-- SetSolidFill in UnitFrame.lua.

-- Height of the cast bar, and the gap used between stacked elements.
SF.CAST_HEIGHT = 16
SF.GAP = 4

-- Height reserved above the target frame for the classification line. Whatever
-- is parked above the frame starts past it - see TopContentOffset.
SF.INFO_HEIGHT = 12

SF.defaults = {
	enablePlayer = true,
	enableTarget = true,
	enablePet = true,
	showToT = true,
	showCastBarPlayer = true,
	showTargetInfo = true,
	showQuestIcon = true,
	showGroupIcon = true,
	showGroupNumber = true,
	showLoadoutName = true,
	showCombatTime = true,
	showTopBackdrop = true,
	showHealPrediction = true,
	showCombatBorder = true,
	hideBlizzardPlayer = false,
	blizzAuraX = -25,
	blizzAuraY = 39,
	blizzAuraScale = 1.0,
	classColor = true,
	width = 200,
	height = 24,
	powerHeight = 10,
	scale = 1.0,
	healthTextMode = 3, -- 0 none, 1 value, 2 percent, 3 both
	pos = {},
}

SF.defaultPos = {
	player = { "CENTER", -280, -140 },
	target = { "CENTER", 180, -140 },
	pet = { "CENTER", -280, -215 }, -- below the player frame and its cast bar
}

-- Which side the target's buff row takes. Blizzard owns this outright: its Edit
-- Mode "Buffs on top" checkbox writes TargetFrame.buffsOnTop, and its own code
-- reads that to mirror the aura container and to place the cast bar.
--
-- SimpleFrame only reads it, so the target-of-target bar can park on the other
-- side. Writing it is not available to an addon - see the note in Blizzard.lua.
-- The fallback matches Blizzard's own default for a client that has not set the
-- field yet.
function SF.BuffsOnTop()
	local f = _G.TargetFrame
	if f and f.buffsOnTop ~= nil then
		return f.buffsOnTop and true or false
	end
	return true
end

function SF.ToTOnTop()
	return not SF.BuffsOnTop()
end

function SF:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99SimpleFrame|r: " .. tostring(msg))
end

-- Health and power values are formatted with the global AbbreviateNumbers,
-- which is secret-safe. Do not hand these values to string.format - see
-- Secrets.lua.

local function CopyDefaults(src, dst)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then dst[k] = {} end
			CopyDefaults(v, dst[k])
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
end

-- Keys left behind by earlier versions. CopyDefaults only ever adds, so these
-- would otherwise sit in the saved variables forever.
local OBSOLETE = {
	"showCastBar",    -- split into showCastBarPlayer / showCastBarTarget
	"showCombatIcon", -- renamed to showCombatBorder
	"showSpecText",   -- became showLoadoutName
	"auraDebug", "auraDebugCombat", "auraDebugOOC", "blizzDump", -- old diagnostics
	-- SimpleFrame no longer draws its own aura icons, so everything that only
	-- configured them is gone, along with the switch that chose between the two
	-- displays. Blizzard's target frame now serves them unconditionally, which
	-- also retires its own cast bar and the option to hide that frame.
	"showAuras", "auraSize", "aurasPerRow",
	"blizzardTargetAuras", "showCastBarTarget", "hideBlizzardTarget",
	-- The buff side is Blizzard's Edit Mode setting, read rather than stored.
	"buffsOnTop",
}

local function PruneObsolete(db)
	for _, key in ipairs(OBSOLETE) do
		db[key] = nil
	end
end

-- Layout work touches secure frames (RegisterUnitWatch, Show/Hide), so it is
-- deferred out of combat and replayed on PLAYER_REGEN_ENABLED.
local applyPending = false

function SF:ApplyConfig()
	if InCombatLockdown() then
		applyPending = true
		return
	end
	applyPending = false

	local db = SimpleFrameDB
	for _, f in pairs(self.frames) do
		local enabled = true
		if f.opts.enableKey then enabled = db[f.opts.enableKey] and true or false end
		f:SetFrameEnabled(enabled)
		if enabled then
			f:ApplyLayout()
			f:UpdateAll()
		end
	end
	self:UpdateBlizzardFrames()
	self:UpdateCombatIndicator()
end

function SF:UpdateCombatIndicator()
	local player = self.frames.player
	if player then
		player:UpdateCombatIndicator()
	end
end

function SF:UpdateLoadoutText()
	local player = self.frames.player
	if player then
		player:UpdateLoadoutText()
	end
end

-- Ticks the combat timer once a second while fighting. A ticker rather than an
-- OnUpdate, so nothing runs at all out of combat.
local combatTicker

function SF:StartCombatTimer()
	self.combatStart = GetTime()
	if not combatTicker then
		combatTicker = C_Timer.NewTicker(1, function() SF:UpdateLoadoutText() end)
	end
	self:UpdateLoadoutText()
end

function SF:StopCombatTimer()
	self.combatStart = nil
	if combatTicker then
		combatTicker:Cancel()
		combatTicker = nil
	end
	self:UpdateLoadoutText()
end

function SF:CreateAllFrames()
	self:CreateUnitFrame("player", "player", {
		enableKey = "enablePlayer",
		showLevel = true,
		hideMaxLevel = true,
		castBar = true,
		castBarKey = "showCastBarPlayer",
		combatBorder = true,
		groupIcon = true,
		groupNumber = true,
		loadoutText = true,
	})

	-- No cast bar: borrowing Blizzard's target frame for its auras drags its
	-- spell bar along, and that one cannot be suppressed, so it serves as the
	-- target cast bar. See Blizzard.lua.
	self:CreateUnitFrame("target", "target", {
		enableKey = "enableTarget",
		showLevel = true,
		infoText = true,
		questIcon = true,
		groupIcon = true,
	})

	-- Pet: health and power, three quarters size, independently movable.
	-- "pet" is a real unit token, so it gets events like the player frame.
	self:CreateUnitFrame("pet", "pet", {
		enableKey = "enablePet",
		widthScale = 0.75,
		heightScale = 0.7,
	})

	-- Target of target: health only, stacked against the target frame at the
	-- same width, on whichever side the buff row is not using. UNIT_* events do
	-- not fire for the "targettarget" token, so this one polls.
	self:CreateUnitFrame("targettarget", "targettarget", {
		enableKey = "showToT",
		noPower = true,
		attached = true,
		attachTo = "target",
		heightScale = 0.7,
		poll = 0.2,
	})
end

function SF:SavePosition(anchor)
	local f = anchor.owner
	if not f or f.opts.attached then return end
	local point, _, relPoint, x, y = anchor:GetPoint(1)
	SimpleFrameDB.pos[f.key] = { point = point, relPoint = relPoint, x = x, y = y }
end

function SF:SetUnlocked(unlocked)
	if InCombatLockdown() then
		self:Print("Cannot move frames while in combat.")
		return
	end
	self.unlocked = unlocked

	for key, f in pairs(self.frames) do
		if not f.opts.attached then
			local anchor = f.anchor
			local overlay = anchor.dragOverlay
			if not overlay then
				overlay = CreateFrame("Frame", nil, anchor)
				overlay:SetAllPoints(anchor)
				overlay:SetFrameStrata("DIALOG")
				overlay:EnableMouse(true)
				overlay:RegisterForDrag("LeftButton")

				local tex = overlay:CreateTexture(nil, "BACKGROUND")
				tex:SetAllPoints()
				tex:SetColorTexture(0, 0.8, 0.2, 0.35)

				local label = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
				label:SetPoint("CENTER")
				label:SetText(key)

				overlay:SetScript("OnDragStart", function(self)
					self:GetParent():StartMoving()
				end)
				overlay:SetScript("OnDragStop", function(self)
					local a = self:GetParent()
					a:StopMovingOrSizing()
					SF:SavePosition(a)
				end)

				anchor.dragOverlay = overlay
			end
			overlay:SetShown(unlocked)
		end
	end

	if unlocked then
		self:Print("Frames unlocked - drag the green boxes, then /sf lock.")
	else
		self:Print("Frames locked.")
	end
end

function SF:ResetPositions()
	wipe(SimpleFrameDB.pos)
	self:ApplyConfig()
	self:Print("Positions reset.")
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("UNIT_TARGET")
eventFrame:RegisterEvent("UNIT_PET")
eventFrame:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PARTY_LEADER_CHANGED")
-- TRAIT_CONFIG_UPDATED only fires when a loadout's contents are saved. Picking
-- a different saved loadout fires ACTIVE_COMBAT_CONFIG_CHANGED instead, so both
-- are needed to keep the name on the player frame current. This is the pair
-- LibSpecialization registers on retail.
eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
eventFrame:RegisterEvent("ACTIVE_COMBAT_CONFIG_CHANGED")

eventFrame:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= addonName then return end
		SimpleFrameDB = SimpleFrameDB or {}
		CopyDefaults(SF.defaults, SimpleFrameDB)
		PruneObsolete(SimpleFrameDB)
		SF:SetupOptions()

	elseif event == "PLAYER_LOGIN" then
		SF:CreateAllFrames()
		SF:ApplyConfig()

	elseif event == "PLAYER_ENTERING_WORLD" then
		SF.inCombat = InCombatLockdown() and true or false
		-- A full re-apply as well as the refresh below: TargetFrame.buffsOnTop
		-- may only have been filled in after login, and it decides which side
		-- the target-of-target bar sits on. ApplyConfig stands down in combat,
		-- so the refresh has to run on its own account.
		SF:ApplyConfig()
		SF:UpdateCombatIndicator()
		for _, f in pairs(SF.frames) do
			f:UpdateAll()
		end

	elseif event == "PLAYER_REGEN_DISABLED" then
		SF.inCombat = true
		SF:UpdateCombatIndicator()
		SF:StartCombatTimer()

	elseif event == "PLAYER_REGEN_ENABLED" then
		SF.inCombat = false
		SF:UpdateCombatIndicator()
		SF:StopCombatTimer()
		if applyPending then SF:ApplyConfig() end
		if SF.blizzPending then SF:UpdateBlizzardFrames() end

	elseif event == "PLAYER_TARGET_CHANGED" then
		local target = SF.frames.target
		local tot = SF.frames.targettarget
		if target then target:UpdateAll() end
		if tot then tot:UpdateAll() end

	elseif event == "UNIT_TARGET" then
		if arg1 == "target" then
			local tot = SF.frames.targettarget
			if tot then tot:UpdateAll() end
		end

	elseif event == "TRAIT_CONFIG_UPDATED" or event == "ACTIVE_COMBAT_CONFIG_CHANGED" then
		-- Read a frame later: both events land before C_ClassTalents reports
		-- the new selection, so reading now would just re-show the old name.
		C_Timer.After(0, function() SF:UpdateLoadoutText() end)

	elseif event == "GROUP_ROSTER_UPDATE" or event == "PARTY_LEADER_CHANGED" then
		-- Neither carries a unit, so refresh both frames that can show a marker.
		for _, key in ipairs({ "player", "target" }) do
			local f = SF.frames[key]
			if f then
				f:UpdateGroupIcon()
				f:UpdateGroupNumber()
			end
		end

	elseif event == "UNIT_QUEST_LOG_CHANGED" then
		-- Fires on the player when quest progress changes, so the marker clears
		-- once the target stops counting toward anything.
		local target = SF.frames.target
		if target then target:UpdateQuestIcon() end

	elseif event == "UNIT_PET" then
		-- Fires on the owner, not the pet, when the pet is summoned or swapped.
		if arg1 == "player" then
			local pet = SF.frames.pet
			if pet then pet:UpdateAll() end
		end
	end
end)

SLASH_SIMPLEFRAME1 = "/sf"
SLASH_SIMPLEFRAME2 = "/simpleframe"
SlashCmdList["SIMPLEFRAME"] = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")

	if msg == "unlock" then
		SF:SetUnlocked(true)
	elseif msg == "lock" then
		SF:SetUnlocked(false)
	elseif msg == "reset" then
		SF:ResetPositions()
	elseif msg == "help" then
		SF:Print("/sf - open settings | /sf unlock | /sf lock | /sf reset")
	else
		if SF.settingsCategory then
			Settings.OpenToCategory(SF.settingsCategory:GetID())
		else
			SF:Print("Settings are not registered yet.")
		end
	end
end
