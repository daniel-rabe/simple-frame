-- SimpleFrame - Blizzard
-- Opt-in hiding of the default player and target frames.
--
-- Reparenting to a permanently hidden frame (rather than repeatedly calling
-- Hide) is what keeps Blizzard's own code from putting them back, and avoids
-- fighting the Edit Mode layout pass.

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

	if db.hideBlizzardTarget then
		HideFrame(TargetFrame)
		HideFrame(TargetFrameToT)
	end
end

-- Edit Mode reapplies its layout to Blizzard unit frames; re-run afterwards.
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
watcher:SetScript("OnEvent", function()
	SF:UpdateBlizzardFrames()
end)
