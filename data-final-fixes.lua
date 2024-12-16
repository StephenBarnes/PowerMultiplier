local electricalMult = settings.startup["PowerMultiplier-electrical"].value
local burnerMult = settings.startup["PowerMultiplier-burner"].value
local nutrientMult = settings.startup["PowerMultiplier-nutrient"].value
local heatingMult = settings.startup["PowerMultiplier-heating"].value
local solarMult = settings.startup["PowerMultiplier-solar"].value
---@cast electricalMult number
---@cast burnerMult number
---@cast nutrientMult number
---@cast heatingMult number
---@cast solarMult number

local blacklistString = settings.startup["PowerMultiplier-blacklist"].value
---@cast blacklistString string
-- Split by comma
---@type table<string, boolean>
local blacklistIds = {}
for blacklistStringPart in string.gmatch(blacklistString, "([^,]+)") do
	-- remove whitespace
	blacklistStringPart = blacklistStringPart:gsub("%s", "")
	blacklistIds[blacklistStringPart] = true
end

local ENERGY_KEYS = {
	-- Maps entity type to a list of fields that should be multiplied by their energy source's multiplier.
	-- List taken from https://lua-api.factorio.com/latest/types/EnergySource.html ; crafting-machine has subtypes assembling-machine, furnace, and rocket-silo.
	-- Not including types boiler, reactor.
	-- Also entity types from pages for BurnerEnergySource, ElectricEnergySource.
	-- Not including types burner-generator, fusion-reactor, generator-equipment, roboport-equipment, lightning-attractor.
	-- Not including cars, locomotives, spider-vehicles.
	["agricultural-tower"] = {"energy_usage", "crane_energy_usage"},
	["inserter"] = {"energy_per_movement", "energy_per_rotation"},
	["lab"] = {"energy_usage"},
	["mining-drill"] = {"energy_usage"},
	["offshore-pump"] = {"energy_usage"},
	["pump"] = {"energy_usage"},
	["radar"] = {"energy_usage", "energy_per_sector", "energy_per_nearby_scan"},
	["assembling-machine"] = {"energy_usage"},
	["furnace"] = {"energy_usage"},
	["rocket-silo"] = {"active_energy_usage", "lamp_energy_usage", "energy_usage"},
	["beacon"] = {"energy_usage"},
	["asteroid-collector"] = {"passive_energy_usage", "arm_energy_usage", "arm_slow_energy_usage"},
	["ammo-turret"] = {"energy_per_shot"},
	["electric-turret"] = {}, -- doesn't have any simple fields, though we still modify the electric energy source. For turrets we also modify the ammo_type.
	["lamp"] = {"energy_usage_per_tick"},
	["programmable-speaker"] = {"energy_usage_per_tick"},
	["arithmetic-combinator"] = {"active_energy_usage"},
	["decider-combinator"] = {"active_energy_usage"},
	["selector-combinator"] = {"active_energy_usage"},
	["constant-combinator"] = {}, -- Still including here for the heat energy.
	["loader"] = {"energy_per_item"},
	["loader-1x1"] = {"energy_per_item"},
	["roboport"] = {"energy_usage", "recharge_minimum", "charging_energy"},
	["logistic-robot"] = {"max_energy", "energy_per_move", "energy_per_tick"},
	["construction-robot"] = {"max_energy", "energy_per_move", "energy_per_tick"},
	["roboport-equipment"] = {"charging_energy", "spawn_minimum", "power"},

	-- Stuff included here only for heating:
	["pipe"] = {},
	["pipe-to-ground"] = {},
	["transport-belt"] = {},
	["underground-belt"] = {},
	["splitter"] = {},
	["storage-tank"] = {},
}
local ALWAYS_ELECTRIC = { -- Set of things that use electric power sources (so electric multiplier should apply), but don't have an electric energy source specified.
	["logistic-robot"] = true,
	["construction-robot"] = true,
}

---@param s nil | string
---@param x number
---@return nil | string
local function multWithUnits(s, x)
	-- Given a string `s` with a number and units, eg "100kW" or "50J" or "0.5kW", multiplies only the number part by the given real number `x`.
	-- Returns nil if the number is 0, so we can avoid changing 0 to 0 and thereby spamming the prototype change history.
	if s == nil then return nil end
	local num, units = s:match("^([%d.]+)([a-zA-Z]*)$")
	if num == 0 then return nil end
	return num * x .. units
end

------------------------------------------------------------------------
--- Functions for adjusting main energy fields of all entities.

local function isNutrientEnergySource(burner)
	if burner.fuel_category == "nutrients" then return true end
	if burner.fuel_category == "food" then return true end
	if burner.fuel_categories == nil or #burner.fuel_categories > 2 or #burner.fuel_categories == 0 then return false end
	for _, category in pairs(burner.fuel_categories) do
		if category ~= "nutrients" then return false end
		if category ~= "food" then return false end
	end
	return true
end

local function getEntityMult(entity)
	-- Gets the multiplier applicable to an entity, by checking its energy source type (electrical, burner, nutrient).
	if ALWAYS_ELECTRIC[entity.type] then return electricalMult end
	local energySource = entity.energy_source
	if energySource == nil then return end
	if energySource.type == "electric" then
		return electricalMult
	elseif energySource.type == "burner" then
		if isNutrientEnergySource(energySource) then
			return nutrientMult
		else
			-- Assumes burner if there's more than 1 fuel category.
			return burnerMult
		end
	else
		-- Ignoring energy source types: "heat", "fluid", "void".
		return nil
	end
end

local function adjustElectricEnergySource(energySource, mult)
	-- For the given entity, adjusts the extra fields of the electric energy source -- drain, buffer capacity, I/O flow limits.
	energySource.buffer_capacity = multWithUnits(energySource.buffer_capacity, mult)
	energySource.input_flow_limit = multWithUnits(energySource.input_flow_limit, mult)
	energySource.output_flow_limit = multWithUnits(energySource.output_flow_limit, mult)
	energySource.drain = multWithUnits(energySource.drain, mult)
end

local function adjustEnergyFields(entity, energyKeys)
	-- For the given entity, adjusts all fields that are energy-related.
	local mult = getEntityMult(entity)
	if mult == nil or mult == 1 then return end
	for _, key in pairs(energyKeys) do
		if entity[key] then
			--log("Adjusting " .. key .. " of " .. entity.name .. " by " .. mult)
			entity[key] = multWithUnits(entity[key], mult)
		end
	end
	if entity.energy_source and entity.energy_source.type == "electric" then
		--log("Adjusting electric energy source of " .. entity.name .. " with drain " .. (entity.energy_source.drain or "nil"))
		adjustElectricEnergySource(entity.energy_source, mult)
	end
end

local function adjustTurretElectricAmmo(entity)
	if entity.energy_source and entity.energy_source.type == "electric" then
		if entity.attack_parameters and entity.attack_parameters.ammo_type then
			entity.attack_parameters.ammo_type.energy_consumption = multWithUnits(entity.attack_parameters.ammo_type.energy_consumption, electricalMult)
		end
	end
end

local function adjustAllEnergyFields()
	-- Adjust all energy usage fields of all applicable entities.
	for typeName, energyKeys in pairs(ENERGY_KEYS) do
		for entityName, entity in pairs(data.raw[typeName]) do
			---@diagnostic disable-next-line: undefined-field
			if not blacklistIds[entityName] and not entity.PowerMultiplier_ignore then
				--log("Adjusting " .. typeName .. " " .. entity.name)
				adjustEnergyFields(entity, energyKeys)
			end
		end
	end
	-- Adjust electric ammo of turrets.
	for _, typeName in pairs({"electric-turret", "ammo-turret", "fluid-turret"}) do
		for entityName, entity in pairs(data.raw[typeName]) do
			---@diagnostic disable-next-line: undefined-field
			if not blacklistIds[entityName] and not entity.PowerMultiplier_ignore then
				--log("Adjusting turret ammo: " .. typeName .. " " .. entity.name)
				adjustTurretElectricAmmo(entity)
			end
		end
	end
end

------------------------------------------------------------------------
--- Functions for adjusting heating energies.

local function adjustHeatingEnergy(entity)
	-- For the given entity, adjusts heating energy (needed on Aquilo).
	if entity.heating_energy then
		local newHeatingEnergy = multWithUnits(entity.heating_energy, heatingMult)
		if newHeatingEnergy ~= nil then
			-- Avoid setting it if it's nil. This ensures that entities that are self-heating don't get this mod in the prototype change history.
			entity.heating_energy = newHeatingEnergy
		end
	end
end

local function adjustAllHeatingFields()
	-- Adjust energy required to heat all entities.
	if heatingMult == 1 then return end
	for typeName, _ in pairs(ENERGY_KEYS) do
		for entityName, entity in pairs(data.raw[typeName]) do
			if not blacklistIds[entityName] and not entity.PowerMultiplier_ignore then
				--log("Adjusting heating energy of " .. entity.name)
				adjustHeatingEnergy(entity)
			end
		end
	end
end

------------------------------------------------------------------------

local function adjustAllSolarPanels()
	if solarMult == nil or solarMult == 1 then return end
	for entityName, entity in pairs(data.raw["solar-panel"]) do
		---@diagnostic disable-next-line: undefined-field
		if not blacklistIds[entityName] and not entity.PowerMultiplier_ignore then
			--log("Adjusting solar panel " .. entity.name)
			local newProduction = multWithUnits(entity.production, solarMult)
			if newProduction == nil then
				log("Warning: solar panel " .. entity.name .. " had 0 or nil production.")
			else
				entity.production = newProduction
			end
		end
	end
end

------------------------------------------------------------------------

adjustAllEnergyFields()
adjustAllHeatingFields()
adjustAllSolarPanels()