-- SimpleFrame - Blizzard
--
-- Two separate things live here:
--
--   1. Opt-in hiding of the default player and target frames.
--   2. "Blizzard target auras" mode, which keeps TargetFrame alive but strips
--      it down to just its aura display and parks it over the SimpleFrame
--      target frame.
--
-- The second exists because on 12.x this addon is refused access to a target's
-- auras once they are secret ("Auras cannot be accessed when secret while
-- tainted by ..."), which is every target in combat. Blizzard's own code is not
-- tainted, so its aura display keeps working. Borrowing it is the only way to
-- show enemy debuffs in combat.

local addonName, SF = ...

local hider = CreateFrame("Frame", "SimpleFrameHider", UIParent)
hider:Hide()

local hidden = {}

local function HideFrame(frame)
	if not frame or hidden[frame] then return end
	hidden[frame] = true
	frame:UnregisterAllEvents()
	frame:Hide()
	frame:SetParent(hider)
end

-- Bars keep their own event registrations, so silence them separately even
-- though they ride along with the reparented parent frame.
local function Silence(frame)
	if frame and frame.UnregisterAllEvents then
		frame:UnregisterAllEvents()
	end
end

--------------------------------------------------------------------------------
-- Blizzard target auras
--------------------------------------------------------------------------------

-- Structure confirmed on 12.1:
--   TargetFrame
--     TargetFrameContainer          Portrait, FrameTexture, Flash
--     TargetFrameContent
--       TargetFrameContentMain      Name, LevelText, ManaBar, HealthBarsContainer
--       TargetFrameContentContextual  ... and Auras
--     TargetFrameToT, TargetFrameSpellBar
-- Alpha as well as Hide: if Blizzard re-shows one of these during combat, when
-- we are not allowed to touch it, a zero alpha keeps it invisible anyway.
local function Strip(element)
	if not element then return end
	if element.SetAlpha then pcall(element.SetAlpha, element, 0) end
	if element.Hide then pcall(element.Hide, element) end
end

-- Blizzard re-shows these whenever the target changes, so this is re-run from
-- the events below rather than applied once.
function SF:StripBlizzardTarget()
	local f = _G.TargetFrame
	if not f or not SimpleFrameDB.blizzardTargetAuras then return end

	-- These are children of a protected frame, so hiding them in combat is a
	-- blocked action - and pcall does not suppress that, since it is a taint
	-- event rather than a Lua error. Defer, and let PLAYER_REGEN_ENABLED replay.
	if InCombatLockdown() then
		self.blizzPending = true
		return
	end

	-- Portrait and border art.
	Strip(f.TargetFrameContainer)

	local content = f.TargetFrameContent
	if content then
		-- Name, level, health and mana: the layout being replaced.
		Strip(content.TargetFrameContentMain)

		-- Everything contextual except the aura container itself.
		local ctx = content.TargetFrameContentContextual
		if ctx then
			for key, child in pairs(ctx) do
				if key ~= "Auras" and type(child) == "table" and child.Hide then
					pcall(child.Hide, child)
				end
			end
		end
	end

	-- Elements SimpleFrame already draws itself. The cast bar is deliberately
	-- left alone: it animates its own alpha while fading, so it overwrites any
	-- hiding we do and reappears in combat. SimpleFrame drops its own target
	-- cast bar instead - see UnitFrameMixin:CastBarEnabled.
	Strip(f.totFrame)
	Strip(f.powerBarAlt)
	Strip(f.threatIndicator)
	Strip(f.threatNumericIndicator)
	Strip(f.Selection)
	Strip(f.healAbsorbBar)
	Strip(f.myHealPredictionBar)
	Strip(f.otherHealPredictionBar)
	Strip(f.totalAbsorbBar)
	Strip(f.overAbsorbGlow)
	Strip(f.overHealAbsorbGlow)
	Strip(f.tempMaxHealthLossBar)
end

-- TargetFrame is protected, so this only runs out of combat. Blizzard keeps
-- positioning the Auras child relative to TargetFrame, so moving the whole
-- frame is what puts the icons where we want them.
function SF:AnchorBlizzardTarget()
	local f = _G.TargetFrame
	local target = self.frames and self.frames.target
	if not f or not target or not SimpleFrameDB.blizzardTargetAuras then return end

	if InCombatLockdown() then
		self.blizzPending = true
		return
	end

	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", target.anchor, "TOPLEFT",
		SimpleFrameDB.blizzAuraX or 0, SimpleFrameDB.blizzAuraY or 0)

	-- Blizzard's unit frames sit below ours, so without this the borrowed
	-- icons render behind the health and power bars.
	f:SetFrameStrata(target.anchor:GetFrameStrata())
	f:SetFrameLevel(target:GetFrameLevel() + 10)
end

--------------------------------------------------------------------------------

function SF:UpdateBlizzardFrames()
	local db = SimpleFrameDB
	if not db then return end

	if InCombatLockdown() then
		self.blizzPending = true
		return
	end
	self.blizzPending = false

	if db.hideBlizzardPlayer and PlayerFrame then
		Silence(PlayerFrame.healthbar)
		Silence(PlayerFrame.manabar)
		HideFrame(PlayerFrame)
	end

	-- Borrowing Blizzard's aura display needs that frame alive, so the two
	-- settings are mutually exclusive and this one wins.
	if db.hideBlizzardTarget and not db.blizzardTargetAuras then
		HideFrame(TargetFrame)
		HideFrame(TargetFrameToT)
	end

	if db.blizzardTargetAuras then
		self:StripBlizzardTarget()
		self:AnchorBlizzardTarget()
	end
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
watcher:RegisterEvent("PLAYER_TARGET_CHANGED")
watcher:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_TARGET_CHANGED" then
		-- Blizzard re-shows the stripped elements on every target change.
		-- StripBlizzardTarget defers itself while in combat.
		SF:StripBlizzardTarget()
	else
		SF:UpdateBlizzardFrames()
	end
end)
