local electricalMult = settings.startup["PowerMultiplier-electrical"].value
local burnerMult = settings.startup["PowerMultiplier-burner"].value
local nutrientMult = settings.startup["PowerMultiplier-nutrient"].value
local heatingMult = settings.startup["PowerMultiplier-heating"].value
local solarMult = settings.startup["PowerMultiplier-solar"].value

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
}

local function multWithUnits(s, x)
	-- Given a string `s` with a number and units, eg "100kW" or "50J" or "0.5kW", multiplies only the number part by the given real number `x`.
	if s == nil then return nil end
	local num, units = s:match("^([%d.]+)([a-zA-Z]*)$")
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
	if entity.energy_source.type == "electric" then
		--log("Adjusting electric energy source of " .. entity.name .. " with drain " .. (entity.energy_source.drain or "nil"))
		adjustElectricEnergySource(entity.energy_source, mult)
		--log("drain is now " .. (entity.energy_source.drain or "nil"))
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
		for _, entity in pairs(data.raw[typeName]) do
			--log("Adjusting " .. typeName .. " " .. entity.name)
			adjustEnergyFields(entity, energyKeys)
		end
	end
	-- Adjust electric ammo of turrets.
	for _, typeName in pairs({"electric-turret", "ammo-turret", "fluid-turret"}) do
		for _, entity in pairs(data.raw[typeName]) do
			--log("Adjusting turret ammo: " .. typeName .. " " .. entity.name)
			adjustTurretElectricAmmo(entity)
		end
	end
end

------------------------------------------------------------------------
--- Functions for adjusting heating energies.

local function adjustHeatingEnergy(entity)
	-- For the given entity, adjusts heating energy (needed on Aquilo).
	if heatingMult == 1 then return end
	if entity.heating_energy then entity.heating_energy = multWithUnits(entity.heating_energy, heatingMult) end
end

local function adjustAllHeatingFields()
	-- Adjust energy required to heat all entities.
	if heatingMult == 1 then return end
	for typeName, _ in pairs(ENERGY_KEYS) do
		for _, entity in pairs(data.raw[typeName]) do
			--log("Adjusting heating energy of " .. entity.name)
			adjustHeatingEnergy(entity)
		end
	end
end

------------------------------------------------------------------------

local function adjustAllSolarPanels()
	if solarMult == nil or solarMult == 1 then return end
	for _, entity in pairs(data.raw["solar-panel"]) do
		--log("Adjusting solar panel " .. entity.name)
		entity.production = multWithUnits(entity.production, solarMult)
	end
end

------------------------------------------------------------------------

adjustAllEnergyFields()
adjustAllHeatingFields()
adjustAllSolarPanels()