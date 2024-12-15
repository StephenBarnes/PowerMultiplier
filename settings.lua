local nextOrderNum = 0
local function nextOrder()
	nextOrderNum = nextOrderNum + 1
	return string.format("%03d", nextOrderNum)
end

data:extend({
    {
        order = nextOrder(),
        type = "double-setting",
        name = "PowerMultiplier-electrical",
        setting_type = "startup",
        default_value = 1.0,
        minimum_value = 0.0,
    },
    {
        order = nextOrder(),
        type = "double-setting",
        name = "PowerMultiplier-burner",
        setting_type = "startup",
        default_value = 1.0,
        minimum_value = 0.0,
    },
    {
        order = nextOrder(),
        type = "double-setting",
        name = "PowerMultiplier-nutrient",
        setting_type = "startup",
        default_value = 1.0,
        minimum_value = 0.0,
    },
    {
        order = nextOrder(),
        type = "double-setting",
        name = "PowerMultiplier-heating",
        setting_type = "startup",
        default_value = 1.0,
        minimum_value = 0.0,
    },
    {
        order = nextOrder(),
        type = "double-setting",
        name = "PowerMultiplier-solar",
        setting_type = "startup",
        default_value = 1.0,
        minimum_value = 0.0,
    },
    {
        order = nextOrder(),
        type = "string-setting",
        name = "PowerMultiplier-blacklist",
        setting_type = "startup",
        default_value = "",
        allow_blank = true,
    },
})