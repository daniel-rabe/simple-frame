-- SimpleFrame - Options
-- Native settings panel (Options -> AddOns -> SimpleFrame).

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
			Settings.CreateCheckbox(category, setting, tooltip)
		end

		local function Slider(key, name, tooltip, min, max, step, formatter)
			local setting, uid = Register(key, name, "number")
			Settings.SetOnValueChangedCallback(uid, function() SF:ApplyConfig() end)

			local options = Settings.CreateSliderOptions(min, max, step)
			options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right,
				formatter or function(value) return tostring(value) end)
			Settings.CreateSlider(category, setting, options, tooltip)
		end

		local function Dropdown(key, name, tooltip, values)
			local setting, uid = Register(key, name, "number")
			Settings.SetOnValueChangedCallback(uid, function() SF:ApplyConfig() end)
			Settings.CreateDropdown(category, setting, function()
				local container = Settings.CreateControlTextContainer()
				for _, entry in ipairs(values) do
					container:Add(entry[1], entry[2])
				end
				return container:GetData()
			end, tooltip)
		end

		--------------------------------------------------------------------
		Header("Frames")

		Checkbox("enablePlayer", "Player frame",
			"Show the SimpleFrame player health and power bars.")
		Checkbox("enableTarget", "Target frame",
			"Show the SimpleFrame target health and power bars.")
		Checkbox("enablePet", "Pet frame",
			"Show a health and power bar for your pet.")
		Checkbox("showToT", "Target of target",
			"Show a small health bar for your target's target.")
		Checkbox("showCastBarPlayer", "Player cast bar",
			"Show a cast bar below the player frame.")
		Checkbox("showCastBarTarget", "Target cast bar",
			"Show a cast bar below the target frame.")
		Checkbox("showAuras", "Target auras",
			"Show buff icons above and your own debuff icons below the target frame.")
		Checkbox("showTargetInfo", "Target classification",
			"Show a line above the target frame with its rank and creature type, such as \"Rare Elite Beast\".")
		Checkbox("showCombatBorder", "Combat indicator",
			"Outline the player frame in red while you are in combat.")
		Checkbox("showHealPrediction", "Incoming heals and absorbs",
			"Overlay the health bars with incoming heals and damage absorb shields.")
		Checkbox("classColor", "Class colored health",
			"Color player health bars by class instead of by reaction.")

		--------------------------------------------------------------------
		Header("Size")

		Slider("width", "Frame width", "Width of the player and target frames.", 100, 400, 5)
		Slider("height", "Health bar height", "Height of the health bar.", 10, 60, 1)
		Slider("powerHeight", "Power bar height", "Height of the power bar.", 4, 40, 1)
		Slider("scale", "Scale", "Overall scale of the frames.", 0.5, 2.0, 0.05,
			function(value) return string.format("%.2f", value) end)

		Dropdown("healthTextMode", "Health text", "What to display on the right of the health bar.", {
			{ 0, "None" },
			{ 1, "Value" },
			{ 2, "Percent" },
			{ 3, "Value and percent" },
		})

		--------------------------------------------------------------------
		Header("Auras")

		Slider("auraSize", "Aura icon size", "Size of the target buff and debuff icons.", 12, 48, 1)
		Slider("aurasPerRow", "Auras per row", "How many aura icons fit in one row.", 4, 16, 1)

		--------------------------------------------------------------------
		Header("Target auras from Blizzard")

		Checkbox("blizzardTargetAuras", "Use Blizzard target auras",
			"Strip Blizzard's target frame down to just its aura icons and park "
			.. "it on the SimpleFrame target frame. Blizzard's code can read aura "
			.. "data in combat that addons are refused, so this is the only way "
			.. "to see enemy debuffs while fighting. Overrides \"Hide Blizzard "
			.. "target frame\", and replaces the SimpleFrame target cast bar "
			.. "with Blizzard's.")

		Slider("blizzAuraX", "Blizzard aura offset X",
			"Horizontal nudge for the borrowed aura icons.", -400, 400, 1)
		Slider("blizzAuraY", "Blizzard aura offset Y",
			"Vertical nudge for the borrowed aura icons.", -400, 400, 1)

		--------------------------------------------------------------------
		Header("Default Blizzard frames")

		Checkbox("hideBlizzardPlayer", "Hide Blizzard player frame",
			"Hide the default player frame. Turning this back off needs a UI reload.",
			function()
				SF:UpdateBlizzardFrames()
				if not SimpleFrameDB.hideBlizzardPlayer then
					SF:Print("Reload the UI (/reload) to bring the Blizzard player frame back.")
				end
			end)

		Checkbox("hideBlizzardTarget", "Hide Blizzard target frame",
			"Hide the default target frame. Turning this back off needs a UI reload.",
			function()
				SF:UpdateBlizzardFrames()
				if not SimpleFrameDB.hideBlizzardTarget then
					SF:Print("Reload the UI (/reload) to bring the Blizzard target frame back.")
				end
			end)

		Settings.RegisterAddOnCategory(category)
	end)

	if not ok then
		SF:Print("Failed to build the settings panel: " .. tostring(err))
	end
end
