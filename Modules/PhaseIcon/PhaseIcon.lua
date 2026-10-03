
local PitBull4 = _G.PitBull4
local UnitGUID = PitBull4.UnitGUID
local L = PitBull4.L

local PitBull4_PhaseIcon = PitBull4:NewModule("PhaseIcon")

local issecretvalue = _G.issecretvalue or function() return false end

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

PitBull4_PhaseIcon:SetModuleType("indicator")
PitBull4_PhaseIcon:SetName(L["Phase icon"])
PitBull4_PhaseIcon:SetDescription(L["Show an icon on the unit frame if the unit is out of phase with you."])
PitBull4_PhaseIcon:SetDefaults({
	attach_to = "root",
	location = "edge_top_left",
	position = 1,
	click_through = false,
})

function PitBull4_PhaseIcon:OnEnable()
	self:RegisterEvent("UNIT_PHASE")
	self:RegisterEvent("UNIT_FLAGS", "UNIT_PHASE")
	self:RegisterEvent("PARTY_MEMBER_ENABLE")
	self:RegisterEvent("PARTY_MEMBER_DISABLE", "PARTY_MEMBER_ENABLE")
end


function PitBull4_PhaseIcon:GetEnableMouse(frame)
	local db = self:GetLayoutDB(frame)
	return not db.click_through
end

function PitBull4_PhaseIcon:OnEnter()
	local tooltip = _G.PARTY_PHASED_MESSAGE
	if ClassicExpansionAtLeast(LE_EXPANSION_SHADOWLANDS) then
		local unit = self:GetParent().unit
		local phaseReason = UnitPhaseReason(unit)
		local tooltip = PartyUtil.GetPhasedReasonString(phaseReason, unit) or _G.PARTY_PHASED_MESSAGE
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(tooltip, nil, nil, nil, nil, true)
	GameTooltip:Show()
end

function PitBull4_PhaseIcon:OnLeave()
	GameTooltip:Hide()
end

function PitBull4_PhaseIcon:GetTexture(frame)
	local unit = frame.unit
	-- Note the UnitInPhase function doesn't work for pets.
	if not unit or not UnitIsPlayer(unit) or not UnitExists(unit) or not UnitIsConnected(unit) then
		return nil
	end

	-- the reason is secret for a player whose identity is restricted, but a
	-- unit that is not phased gets a plain nil, so a secret means phased
	local reason = phase_reason(unit)
	if not issecretvalue(reason) and not reason then
		return nil
	end

	return [[Interface\TargetingFrame\UI-PhasingIcon]]
end

function PitBull4_PhaseIcon:GetExampleTexture(frame)
	return [[Interface\TargetingFrame\UI-PhasingIcon]]
end

function PitBull4_PhaseIcon:UNIT_PHASE(_, unit)
	-- UNIT_PHASE fires for some units at different points than for others.
	-- So we update by GUID rather than by unit id to increase accuracy
	self:UpdateForGUID(UnitGUID(unit))
end

function PitBull4_PhaseIcon:PARTY_MEMBER_ENABLE(_, unit)
	self:UpdateAll()
end


PitBull4_PhaseIcon:SetLayoutOptionsFunction(function(self)
	return "click_through", {
		type = "toggle",
		name = L["Click-through"],
		desc = L["Disable capturing clicks on icons, allowing the click to fall through to the window underneath the icon."],
		get = function(info)
			return PitBull4.Options.GetLayoutDB(self).click_through
		end,
		set = function(info, value)
			PitBull4.Options.GetLayoutDB(self).click_through = value

			for frame in PitBull4:IterateFrames() do
				self:Clear(frame)
				self:Update(frame)
			end
		end,
		order = 100,
	}
end)
