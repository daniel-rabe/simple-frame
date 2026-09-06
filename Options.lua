-- SimpleFrame - Options
-- Native settings panel (Options -> AddOns -> SimpleFrame).
--
-- Sections follow where a setting shows up on screen rather than what kind of
-- control it is, so the size of a thing sits next to the switch that turns it
-- on.

local addonName, SF = ...

local PREFIX = "SimpleFrame_"

function SF:SetupOptions()
	local ok, err = pcall(function()
		local category, layout = Settings.RegisterVerticalLayoutCategory("SimpleFrame")
		SF.settingsCategory = category

		local function Header(text)
			layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
		end

		local function Register(key, name, varType)
			local default = SF.defaults[key]
			return Settings.RegisterAddOnSetting(category, PREFIX .. key, key, SimpleFrameDB,
				varType or type(default), name, default), PREFIX .. key
		end

		local function Checkbox(key, name, tooltip, onChange)
			local setting, uid = Register(key, name)
			Settings.SetOnValueChangedCallback(uid, onChange or function() SF:ApplyConfig() end)
			return Settings.CreateCheckbox(category, setting, tooltip), setting
		end

		local function Slider(key, name, tooltip, min, max, step, formatter)
			local setting, uid = Register(key, name, "number")
			Settings.SetOnValueChangedCallback(uid, function() SF:ApplyConfig() end)

			local options = Settings.CreateSliderOptions(min, max, step)
			options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right,
				formatter or function(value) return tostring(value) end)
			return Settings.CreateSlider(category, setting, options, tooltip), setting
		end

		local function Dropdown(key, name, tooltip, values)
			local setting, uid = Register(key, name, "number")
			Settings.SetOnValueChangedCallback(uid, function() SF:ApplyConfig() end)
			return Settings.CreateDropdown(category, setting, function()
				local container = Settings.CreateControlTextContainer()
				for _, entry in ipairs(values) do
					container:Add(entry[1], entry[2])
				end
				return container:GetData()
			end, tooltip), setting
		end

		local function TwoDecimals(value)
			return string.format("%.2f", value)
		end

		--------------------------------------------------------------------
		-- Which frames exist at all.
		Header("Frames")

		Checkbox("enablePlayer", "Player frame",
			"Show the SimpleFrame player health and power bars.")
		Checkbox("enableTarget", "Target frame",
			"Show the SimpleFrame target health and power bars.")
		Checkbox("enablePet", "Pet frame",
			"Show a health and power bar for your pet.")
		Checkbox("showToT", "Target of target",
			"Show a small health bar for your target's target, stacked against the "
			.. "target frame on whichever side the buff row is not using.")

		--------------------------------------------------------------------
		-- Shape and content of the bars themselves.
		Header("Bars")

		Slider("width", "Frame width", "Width of the player and target frames.", 100, 400, 5)
		Slider("height", "Health bar height", "Height of the health bar.", 10, 60, 1)
		Slider("powerHeight", "Power bar height", "Height of the power bar.", 4, 40, 1)
		Slider("scale", "Scale", "Overall scale of the frames.", 0.5, 2.0, 0.05, TwoDecimals)

		Dropdown("healthTextMode", "Health text", "What to display on the right of the health bar.", {
			{ 0, "None" },
			{ 1, "Value" },
			{ 2, "Percent" },
			{ 3, "Value and percent" },
		})

		Checkbox("classColor", "Class colored health",
			"Color player health bars by class instead of by reaction.")
		Checkbox("showHealPrediction", "Incoming heals and absorbs",
			"Overlay the health bars with incoming heals and damage absorb shields.")

		--------------------------------------------------------------------
		Header("Cast bar")

		Checkbox("showCastBarPlayer", "Player cast bar",
			"Show a cast bar below the player frame. The target's cast bar is "
			.. "Blizzard's own, which comes along with the aura display it "
			.. "borrows and cannot be suppressed.")

		--------------------------------------------------------------------
		-- Drawn over the bars.
		Header("On the frame")

		Checkbox("showCombatBorder", "Combat indicator",
			"Outline the player frame in red while you are in combat.")
		Checkbox("showGroupNumber", "Raid group number",
			"Show your raid subgroup number in the middle of the player frame.")

		--------------------------------------------------------------------
		-- The band between the frame and whatever is parked above it.
		Header("Above the frame")

		Checkbox("showTopBackdrop", "Top backdrop",
			"Draw a dark backing behind the band above the frame, where the combat "
			.. "timer, loadout name and leader marker are shown.")
		Checkbox("showLoadoutName", "Talent loadout",
			"Show the name of your selected talent loadout above the player frame, "
			.. "falling back to the specialization when no named loadout is active.")
		Checkbox("showCombatTime", "Combat timer",
			"While in combat, show the elapsed combat time in place of the talent loadout name.")
		Checkbox("showTargetInfo", "Target classification",
			"Show a line above the target frame with its rank and creature type, such as \"Rare Elite Beast\".")
		Checkbox("showQuestIcon", "Quest indicator",
			"Show a yellow exclamation mark above the target frame for enemies that count toward a quest.")
		Checkbox("showGroupIcon", "Leader and assist",
			"Mark the group leader with L and raid assistants with A, on the player and target frames.")

		--------------------------------------------------------------------
		-- The icons are Blizzard's own, borrowed whole - an addon cannot read a
		-- target's auras in combat, and Blizzard's code can. So these settings
		-- place that display rather than describing one of our own.
		--
		-- Which side the buffs take is deliberately absent. It is Blizzard's
		-- Edit Mode "Buffs on top" checkbox, which an addon cannot write
		-- without breaking the aura container - see Blizzard.lua. SimpleFrame
		-- follows it, and puts the target-of-target bar on the other side.
		Header("Target auras")

		Slider("blizzAuraScale", "Aura scale",
			"Size of the aura icons. The two offsets below stay in screen "
			.. "pixels, so changing this does not move them.", 0.5, 2.0, 0.05, TwoDecimals)
		Slider("blizzAuraX", "Aura offset X",
			"Horizontal nudge for the aura icons.", -400, 400, 1)
		Slider("blizzAuraY", "Aura offset Y",
			"Vertical nudge for the aura icons.", -400, 400, 1)

		--------------------------------------------------------------------
		-- Only the player frame is offered. Blizzard's target frame has to stay
		-- alive, stripped down to its aura icons - see Blizzard.lua.
		Header("Default Blizzard frames")

		Checkbox("hideBlizzardPlayer", "Hide Blizzard player frame",
			"Hide the default player frame. Turning this back off needs a UI reload.",
			function()
				SF:UpdateBlizzardFrames()
				if not SimpleFrameDB.hideBlizzardPlayer then
					SF:Print("Reload the UI (/reload) to bring the Blizzard player frame back.")
				end
			end)

		Settings.RegisterAddOnCategory(category)
	end)

	if not ok then
		SF:Print("Failed to build the settings panel: " .. tostring(err))
	end
end
