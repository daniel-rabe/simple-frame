-- SimpleFrame - Blizzard
--
-- Two separate things live here:
--
--   1. Opt-in hiding of the default player frame.
--   2. Borrowing Blizzard's target frame: it is kept alive but stripped down to
--      its aura display alone, and parked over the SimpleFrame target frame.
--
-- The second is not optional. On 12.x this addon is refused access to a
-- target's auras once they are secret ("Auras cannot be accessed when secret
-- while tainted by ..."), which is every target in combat. Blizzard's own code
-- is not tainted, so its aura display keeps working, and borrowing it is the
-- only way to show enemy debuffs while fighting. Drawing our own icons was
-- offered for a while and only ever worked out of combat, which is when they
-- matter least.
--
-- Consequences of borrowing the whole frame: its spell bar comes along and
-- serves as the target cast bar, and the frame cannot also be hidden.

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
	if not f or not SimpleFrameDB.enableTarget then return end

	-- These are children of a protected frame, so hiding them in combat is a
	-- blocked action - and pcall does not suppress that, since it is a taint
	-- event rather than a Lua error. Defer, and let PLAYER_REGEN_ENABLED replay.
	if InCombatLockdown() then
		self.blizzPending = true
		return
	end

	-- The frame is invisible now but still mouse-enabled, and it is both larger
	-- than the SimpleFrame target frame and stacked above it - so it swallows
	-- clicks meant for our frames, including the top of the target-of-target bar
	-- underneath. The aura buttons are separate children and keep their own
	-- mouse handling, so tooltips still work.
	pcall(f.EnableMouse, f, false)

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
	if not f or not target or not SimpleFrameDB.enableTarget then return end

	if InCombatLockdown() then
		self.blizzPending = true
		return
	end

	-- A point's offset is measured in the coordinate space of the frame being
	-- positioned, so scaling the frame scales its offsets along with it and the
	-- icons would drift every time the slider moved. Dividing the offsets back
	-- out keeps the two nudge sliders reading in screen pixels, so a position
	-- tuned at one scale survives a change of scale.
	local scale = SimpleFrameDB.blizzAuraScale or 1
	if scale <= 0 then scale = 1 end
	f:SetScale(scale)

	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", target.anchor, "TOPLEFT",
		(SimpleFrameDB.blizzAuraX or 0) / scale,
		(SimpleFrameDB.blizzAuraY or 0) / scale)

	-- Blizzard's unit frames sit below ours, so without this the borrowed
	-- icons render behind the health and power bars.
	f:SetFrameStrata(target.anchor:GetFrameStrata())
	f:SetFrameLevel(target:GetFrameLevel() + 10)
end

-- Why nothing here writes TargetFrame.buffsOnTop or touches its aura container.
--
-- Both look harmless - a boolean field, and a container-level layout call that
-- reads no aura data. Both taint the container. Blizzard's next layout pass,
-- running from its own dirty-flag processing well after the call, then reaches
-- TargetFrame.lua's compare of numVisibleAuraRows, which is a secret, and
-- raises:
--
--   attempt to compare local 'numVisibleAuraRows' (a secret number value,
--   while execution tainted by 'SimpleFrame')
--
-- The throw lands inside ProcessDirtyFlags, which can leave the aura container
-- stuck for the rest of the session. So the buff side belongs to Blizzard's
-- Edit Mode checkbox alone, and SimpleFrame only reads it - see SF.BuffsOnTop.

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

	if db.enableTarget then
		self:StripBlizzardTarget()
		self:AnchorBlizzardTarget()
	elseif TargetFrame and TargetFrame:GetScale() ~= 1 then
		-- Give the scale back when the target frame is switched off, so
		-- Blizzard's own frame is not left stretched. Its position and the
		-- stripped elements still need a reload, as the README says.
		TargetFrame:SetScale(1)
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
		-- Leaving Edit Mode is where the buff side can have changed, which
		-- moves the target-of-target bar to the other side of the frame.
		SF:ApplyConfig()
	end
end)
