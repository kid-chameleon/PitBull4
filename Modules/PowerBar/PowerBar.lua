
local PitBull4 = _G.PitBull4
local UnitGUID = PitBull4.UnitGUID
local L = PitBull4.L

local EXAMPLE_VALUE = 0.6
local PowerBarColor = _G.PowerBarColor

-- Secret values (WoW: Forever): power is never readable, the bar takes
-- UnitPowerPercent directly.
local has_secrets = PitBull4.has_secrets
local issecretvalue = _G.issecretvalue or function() return false end

local PitBull4_PowerBar = PitBull4:NewModule("PowerBar")

PitBull4_PowerBar:SetModuleType("bar")
PitBull4_PowerBar:SetName(L["Power bar"])
PitBull4_PowerBar:SetDescription(L["Show a bar for your primary resource."])
PitBull4_PowerBar.allow_animations = true
PitBull4_PowerBar:SetDefaults({
	position = 2,
	hide_no_mana = false,
	hide_no_power = false,
	use_atlas = false,
	predict_cost = true,
})

local guids_to_update = {}
local type_to_token = {
	"MANA", "RAGE", "FOCUS", "ENERGY", "CHI",
	"RUNES", "RUNIC_POWER", "SOUL_SHARDS", "LUNAR_POWER",
	"HOLY_POWER", "MAELSTROM", "INSANITY", "FURY", "PAIN"
}
local power_bar_atlas = {}
for power_token, info in next, PowerBarColor do
	if info.atlas then
		power_bar_atlas[power_token] = info.atlas
	end
end

local timerFrame = CreateFrame("Frame")
timerFrame:Hide()

-- Spell cost prediction: while the player casts, the part of the bar that
-- the spell will consume is shaded (see Controls.lua). The cost comes from
-- the spell's cost table and is plain even where power values are secret;
-- the maximum may be secret, so the segment is sized by the engine.
local GetSpellPowerCost = C_Spell and C_Spell.GetSpellPowerCost or _G.GetSpellPowerCost

-- the cost, in the given power type, of the spell the player is casting, or
-- 0 when nothing is being cast or the cast does not spend that power
local function get_cast_cost(power_type)
	if not GetSpellPowerCost then
		return 0
	end
	local spell_id = select(9, UnitCastingInfo("player"))
	if not spell_id or issecretvalue(spell_id) then
		return 0
	end
	local costs = GetSpellPowerCost(spell_id)
	if not costs then
		return 0
	end
	for _, cost_info in ipairs(costs) do
		local cost_type, cost = cost_info.type, cost_info.cost
		if not issecretvalue(cost_type) and not issecretvalue(cost) and cost_type == power_type and cost > 0 then
			return cost
		end
	end
	return 0
end

local function clear_cost(frame)
	local cost_bar = frame.PowerBarCost
	if cost_bar then
		frame.PowerBarCost = cost_bar:Delete()
	end
end

local function update_cost(self, frame)
	local power_bar = frame[self.id]
	if not power_bar or frame.unit ~= "player" or not frame.guid or not self:GetLayoutDB(frame).predict_cost then
		return clear_cost(frame)
	end

	local power_type = UnitPowerType("player")
	local cost = get_cast_cost(power_type)
	local max = UnitPowerMax("player", power_type)
	if cost <= 0 or (not issecretvalue(max) and max <= 0) then
		return clear_cost(frame)
	end

	local cost_bar = frame.PowerBarCost
	if not cost_bar then
		cost_bar = PitBull4.Controls.MakePowerCostBar(power_bar)
		frame.PowerBarCost = cost_bar
	end
	cost_bar:Attach(power_bar)
	cost_bar:SetAppearance(power_bar)
	cost_bar:SetCost(cost, max)
	cost_bar:Show()
end

function PitBull4_PowerBar:OnEnable()
	self:RegisterEvent("UNIT_POWER_FREQUENT")
	self:RegisterEvent("UNIT_MAXPOWER", "UNIT_POWER_FREQUENT")
	self:RegisterEvent("UNIT_DISPLAYPOWER")
	self:RegisterEvent("UNIT_POWER_BAR_SHOW", "UNIT_DISPLAYPOWER")
	self:RegisterEvent("UNIT_POWER_BAR_HIDE", "UNIT_DISPLAYPOWER")

	-- the player's casts, for the spell cost prediction
	self:RegisterUnitEvent("UNIT_SPELLCAST_START", "UNIT_SPELLCAST", "player")
	self:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST", "player")
	self:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST", "player")
	self:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST", "player")
	self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST", "player")

	timerFrame:Show()
end

function PitBull4_PowerBar:OnDisable()
	timerFrame:Hide()
end

timerFrame:SetScript("OnUpdate", function()
	if next(guids_to_update) then
		for frame in PitBull4:IterateFrames() do
			if guids_to_update[frame.guid] then
				PitBull4_PowerBar:Update(frame)
			end
		end
		wipe(guids_to_update)
	end
end)

-- the bar module's update and clear, plus the cost segment that rides on
-- the bar
local bar_UpdateFrame = PitBull4_PowerBar.UpdateFrame
function PitBull4_PowerBar:UpdateFrame(frame)
	local changed = bar_UpdateFrame(self, frame)
	update_cost(self, frame)
	return changed
end

local bar_ClearFrame = PitBull4_PowerBar.ClearFrame
function PitBull4_PowerBar:ClearFrame(frame)
	clear_cost(frame)
	return bar_ClearFrame(self, frame)
end

function PitBull4_PowerBar:GetValue(frame)
	local unit = frame.unit
	local layout_db = self:GetLayoutDB(frame)
	local max = UnitPowerMax(unit)

	if layout_db.hide_no_mana and UnitPowerType(unit) ~= 0 then
		return nil
	elseif layout_db.hide_no_power and not issecretvalue(max) and max <= 0 then
		return nil
	end

	if has_secrets then
		return UnitPowerPercent(unit)
	end

	if max == 0 then
		return 0
	end

	return UnitPower(unit) / max
end

function PitBull4_PowerBar:GetExampleValue(frame)
	return EXAMPLE_VALUE
end

function PitBull4_PowerBar:GetColor(frame, value)
	local unit = frame.unit
	local power_type, power_token, r, g, b = UnitPowerType(unit)
	local color = PitBull4.PowerColors[power_token]

	if not color then
		if not r then
			color = PitBull4.PowerColors[type_to_token[power_type]] or PitBull4.PowerColors.MANA
			r, g, b = color[1], color[2], color[3]
		end
	else
		r, g, b = color[1], color[2], color[3]
	end

	return r, g, b, nil, nil, self:GetLayoutDB(frame).use_atlas and power_bar_atlas[power_token]
end
function PitBull4_PowerBar:GetExampleColor(frame)
	return unpack(PitBull4.PowerColors.MANA)
end

function PitBull4_PowerBar:UNIT_POWER_FREQUENT(event, unit, power_type)
	if not unit then return end
	local _, power_token = UnitPowerType(unit)
	-- fix units that have a special power type but update as ENERGY
	if not PowerBarColor[power_token] then
		power_token = "ENERGY"
	end
	if power_token == power_type then
		local guid = UnitGUID(unit)
		if guid then
			guids_to_update[guid] = true
		end
	end
end

function PitBull4_PowerBar:UNIT_DISPLAYPOWER(event, unit)
	local guid = unit and UnitGUID(unit)
	if guid then
		guids_to_update[guid] = true
	end
end

function PitBull4_PowerBar:UNIT_SPELLCAST(event, unit)
	local guid = unit and UnitGUID(unit)
	if guid then
		guids_to_update[guid] = true
	end
end

PitBull4_PowerBar:SetLayoutOptionsFunction(function(self)
	local function get(info)
		return PitBull4.Options.GetLayoutDB(self)[info[#info]]
	end
	local function set(info, value)
		PitBull4.Options.GetLayoutDB(self)[info[#info]] = value
		PitBull4.Options.UpdateFrames()
	end

	return 'hide_no_mana', {
		name = L["Hide non-mana"],
		desc = L["Hides the power bar if the unit's current power is not mana."],
		type = "toggle",
		get = get,
		set = set,
	}, 'hide_no_power', {
		name = L["Hide non-power"],
		desc = L["Hides the power bar if the unit has no power."],
		type = "toggle",
		get = get,
		set = set,
	}, 'use_atlas', {
		name = L["Use power texture"],
		desc = L["Use the provided power-specific texture if available instead of the set texture."],
		type = "toggle",
		get = get,
		set = set,
	}, 'predict_cost', {
		name = L["Show spell cost"],
		desc = L["Shade the part of your power that the spell you are casting will consume."],
		type = "toggle",
		get = get,
		set = set,
	}
end)
