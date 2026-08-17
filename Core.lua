-- SimpleFrame - Core
-- Addon table, saved variables, lifecycle events and slash commands.

local addonName, SF = ...

SF.frames = {}
SF.unlocked = false

-- Driven purely by PLAYER_REGEN_DISABLED/ENABLED plus InCombatLockdown on load,
-- so the indicator never depends on a value that could come back secret.
SF.inCombat = false
-- Bar fills are generated solid-color textures, not texture files - see
-- SetSolidFill in UnitFrame.lua.

-- Height of the cast bar, and the gap used between stacked elements. Auras.lua
-- needs both to know how far below the frame the debuff rows start.
SF.CAST_HEIGHT = 16
SF.GAP = 4

SF.defaults = {
	enablePlayer = true,
	enableTarget = true,
	showToT = true,
	showCastBarPlayer = true,
	showCastBarTarget = true,
	showAuras = true,
	showCombatIcon = true,
	hideBlizzardPlayer = false,
	hideBlizzardTarget = false,
	classColor = true,
	width = 200,
	height = 24,
	powerHeight = 10,
	scale = 1.0,
	healthTextMode = 3, -- 0 none, 1 value, 2 percent, 3 both
	auraSize = 22,
	aurasPerRow = 8,
	pos = {},
}

SF.defaultPos = {
	player = { "CENTER", -280, -140 },
	target = { "CENTER", 180, -140 },
}

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

function SF:CreateAllFrames()
	self:CreateUnitFrame("player", "player", {
		enableKey = "enablePlayer",
		showLevel = true,
		castBar = true,
		castBarKey = "showCastBarPlayer",
		combatIcon = true,
	})

	self:CreateUnitFrame("target", "target", {
		enableKey = "enableTarget",
		showLevel = true,
		castBar = true,
		castBarKey = "showCastBarTarget",
		auras = true,
	})

	-- Target of target: health only, attached to the right of the target frame.
	-- UNIT_* events do not fire for the "targettarget" token, so this one polls.
	self:CreateUnitFrame("targettarget", "targettarget", {
		enableKey = "showToT",
		noPower = true,
		attached = true,
		attachTo = "target",
		widthScale = 0.5,
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

	-- Swap the real aura icons for placeholders (or back), so the aura rows are
	-- part of the footprint you are positioning against.
	for _, f in pairs(self.frames) do
		if f.opts.auras then
			self:UpdateAuras(f)
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

eventFrame:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= addonName then return end
		SimpleFrameDB = SimpleFrameDB or {}
		CopyDefaults(SF.defaults, SimpleFrameDB)
		SF:SetupOptions()

	elseif event == "PLAYER_LOGIN" then
		SF:CreateAllFrames()
		SF:ApplyConfig()

	elseif event == "PLAYER_ENTERING_WORLD" then
		SF.inCombat = InCombatLockdown() and true or false
		SF:UpdateBlizzardFrames()
		SF:UpdateCombatIndicator()
		for _, f in pairs(SF.frames) do
			f:UpdateAll()
		end

	elseif event == "PLAYER_REGEN_DISABLED" then
		SF.inCombat = true
		SF:UpdateCombatIndicator()

	elseif event == "PLAYER_REGEN_ENABLED" then
		SF.inCombat = false
		SF:UpdateCombatIndicator()
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
