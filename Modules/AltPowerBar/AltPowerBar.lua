
local PitBull4 = _G.PitBull4
local L = PitBull4.L

local EXAMPLE_VALUE = 0.6

-- Under secret values (retail 12.x, WoW: Forever) the alternate power of a
-- unit outside the group is secret, so the engine computes the percentage.
local has_secrets = PitBull4.has_secrets
local issecretvalue = _G.issecretvalue or function() return false end

-- UnitInRaid/UnitInParty are secret for a unit whose identity is restricted,
-- and such a unit is never in the player's group.
local function in_group(unit)
	local in_raid = UnitInRaid(unit)
	if issecretvalue(in_raid) then return false end
	if in_raid then return true end
	local in_party = UnitInParty(unit)
	if issecretvalue(in_party) then return false end
	return in_party and true or false
end

-- A bar with a non-zero minimum fills from that minimum: a linear curve maps
-- [min/max, 1] onto [0, 1]. One curve per distinct fraction, as CombatFader
-- does, since curves cannot be cleared.
local min_curve
do
	local curves = {}
	function min_curve(min_fraction)
		local curve = curves[min_fraction]
		if not curve then
			curve = C_CurveUtil.CreateCurve()
			curve:SetType(Enum.LuaCurveType.Linear)
			curve:AddPoint(min_fraction, 0)
			curve:AddPoint(1, 1)
			curves[min_fraction] = curve
		end
		return curve
	end
end

local PitBull4_AltPowerBar = PitBull4:NewModule("AltPowerBar")

PitBull4_AltPowerBar:SetModuleType("bar")
PitBull4_AltPowerBar:SetName(L["Alternate power bar"])
PitBull4_AltPowerBar:SetDescription(L["Show a bar for the alternate power bar as used in some quests and boss encounters."])
PitBull4_AltPowerBar.allow_animations = true
PitBull4_AltPowerBar:SetDefaults({
	position = 3,
})

function PitBull4_AltPowerBar:OnEnable()
	self:RegisterEvent("UNIT_POWER_BAR_SHOW")
	self:RegisterEvent("UNIT_POWER_BAR_HIDE", "UNIT_POWER_BAR_SHOW")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "UpdateAll")
	self:RegisterEvent("UNIT_POWER_FREQUENT")
	self:RegisterEvent("UNIT_MAXPOWER", "UNIT_POWER_FREQUENT")
end

function PitBull4_AltPowerBar:GetValue(frame)
	local unit = frame.unit
	local bar_info = GetUnitPowerBarInfo(unit)
	if not bar_info then return end

	local visible = false
	if bar_info.barType then
		if (unit == "player" or unit == "vehicle" or unit == "pet") or not bar_info.hideFromOthers then
			visible = true
		elseif bar_info.showOnRaid and in_group(unit) then
			visible = true
		end
	end
	if not visible then return nil end

	local max_power = UnitPowerMax(unit, ALTERNATE_POWER_INDEX)
	local min_power = bar_info.minPower

	if has_secrets then
		-- The minimum is only honoured when the maximum is plain (player,
		-- vehicle, pet and group units); a secret maximum fills from zero.
		if min_power and min_power > 0 and not issecretvalue(max_power) and max_power > min_power then
			return UnitPowerPercent(unit, ALTERNATE_POWER_INDEX, false, min_curve(min_power / max_power))
		end
		return UnitPowerPercent(unit, ALTERNATE_POWER_INDEX)
	end

	if max_power == 0 then
		return 0
	end

	local current_power = UnitPower(unit, ALTERNATE_POWER_INDEX)
	if min_power > current_power then
		current_power = min_power
	end
	if max_power < current_power then
		current_power = max_power
	end

	return (current_power - min_power) / (max_power - min_power)
end

function PitBull4_AltPowerBar:GetExampleValue(frame)
	return EXAMPLE_VALUE
end

function PitBull4_AltPowerBar:GetColor(frame, value)
	return unpack(PitBull4.PowerColors.PB4_ALTERNATE)
end
PitBull4_AltPowerBar.GetExampleColor = PitBull4_AltPowerBar.GetColor

function PitBull4_AltPowerBar:UNIT_POWER_BAR_SHOW(event, unit)
	self:UpdateForUnitID(unit)
end

function PitBull4_AltPowerBar:UNIT_POWER_FREQUENT(event, unit, power_type)
	if power_type ~= "ALTERNATE" then
		return
	end

	self:UpdateForUnitID(unit)
end
