
local PitBull4 = _G.PitBull4
local L = PitBull4.L

local PitBull4_PhaseFader = PitBull4:NewModule("PhaseFader")

-- Forever reports the vanilla expansion level but ships the modern
-- UnitPhaseReason and no UnitInPhase, so pick by what the client provides
-- rather than by the expansion. The reason is secret for a unit outside the
-- group, but the API still returns a plain nil when the unit is not phased,
-- so the result is only ever used for its truthiness.
local phase_reason
if UnitPhaseReason and (ClassicExpansionAtLeast(LE_EXPANSION_SHADOWLANDS) or not UnitInPhase) then
	phase_reason = UnitPhaseReason
elseif UnitInPhase then
	phase_reason = function(unit)
		return not UnitInPhase(unit) or nil
	end
else
	phase_reason = function() return nil end
end

PitBull4_PhaseFader:SetModuleType("fader")
PitBull4_PhaseFader:SetName(L["Phase fader"])
PitBull4_PhaseFader:SetDescription(L["Make the unit frame fade if in a different phase."])
PitBull4_PhaseFader:SetDefaults({
	enabled = true,
	phased_opacity = 0.6,
})

function PitBull4_PhaseFader:OnEnable()
	self:RegisterEvent("UNIT_PHASE")
	self:RegisterEvent("UNIT_FLAGS", "UNIT_PHASE")
end

function PitBull4_PhaseFader:UNIT_PHASE(event, unit)
	self:UpdateForUnitID(unit)
end

function PitBull4_PhaseFader:GetOpacity(frame)
	local unit = frame.unit
	if not unit or (not UnitIsPlayer(unit) and not UnitInPartyIsAI(unit)) or not UnitExists(unit) or not UnitIsConnected(unit) then
		return nil
	end

	if not phase_reason(unit) then
		return nil
	end

	local layout_db = self:GetLayoutDB(frame)
	return layout_db.phased_opacity
end

PitBull4_PhaseFader:SetLayoutOptionsFunction(function(self)
	return 'phased_opacity', {
		type = 'range',
		name = L["Phased opacity"],
		desc = L["The opacity to display if the unit is in a different phase."],
		min = 0,
		max = 1,
		isPercent = true,
		get = function(info)
			local db = PitBull4.Options.GetLayoutDB(self)

			return db.phased_opacity
		end,
		set = function(info, value)
			local db = PitBull4.Options.GetLayoutDB(self)

			db.phased_opacity = value

			PitBull4.Options.UpdateFrames()
			PitBull4:RecheckAllOpacities()
		end,
		step = 0.01,
		bigStep = 0.05,
	}
end)
