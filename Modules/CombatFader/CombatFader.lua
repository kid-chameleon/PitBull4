
local PitBull4 = _G.PitBull4
local L = PitBull4.L

local PitBull4_CombatFader = PitBull4:NewModule("CombatFader")

PitBull4_CombatFader:SetModuleType("fader")
PitBull4_CombatFader:SetName(L["Combat fader"])
PitBull4_CombatFader:SetDescription(L["Make the unit frame fade if out of combat."])
PitBull4_CombatFader:SetDefaults({
	enabled = false,
	hurt_opacity = 0.75,
	in_combat_opacity = 1,
	out_of_combat_opacity = 0.25,
	target_opacity = 0.75,
})

local state = 'out_of_combat'

-- Secret values (WoW: Forever): whether the player is missing health or power
-- cannot be decided here. The combat and target states still can be, and for
-- the rest the engine evaluates a step curve against the player's health, so
-- the power condition is dropped.
local has_secrets = PitBull4.has_secrets
local issecretvalue = _G.issecretvalue or function() return false end
local SECRET_STATE = "secret_health"

local timerFrame = CreateFrame("Frame")
timerFrame:Hide()

timerFrame:SetScript("OnUpdate", function(self)
	self:Hide()

	PitBull4_CombatFader:RecalculateState()
	PitBull4_CombatFader:UpdateAll()
end)

function PitBull4_CombatFader:OnEnable()
	self:RegisterEvent("PLAYER_REGEN_ENABLED")
	self:RegisterEvent("PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED")
	self:RegisterEvent("PLAYER_TARGET_CHANGED", "PLAYER_REGEN_ENABLED")
	self:RegisterUnitEvent("UNIT_HEALTH", nil, "player")
	self:RegisterUnitEvent("UNIT_POWER_UPDATE", "UNIT_HEALTH", "player")
	self:RegisterUnitEvent("UNIT_DISPLAYPOWER", "UNIT_HEALTH", "player")

	self:RecalculateState()
	timerFrame:Show()
end

local power_check
do
	local function not_full()
		return UnitPower("player") < UnitPowerMax("player")
	end
	local function not_empty()
		return UnitPower("player") > 0
	end
	local function lunar_not_empty()
		if IsPlayerSpell(202430) then -- Nature's Balance
			local power = UnitPower("player")
			return power < 50 or power > 51
		end
		return UnitPower("player") > 0
	end
	power_check = {
		MANA = not_full,
		RAGE = not_empty,
		FOCUS = not_full,
		ENERGY = not_full,
		RUNIC_POWER = not_empty,
		LUNAR_POWER = lunar_not_empty,
		MAELSTROM = not_empty,
		INSANITY = not_empty,
		FURY = not_empty,
		PAIN = not_empty,
	}
end

function PitBull4_CombatFader:RecalculateState()
	if UnitAffectingCombat("player") then
		state = "in_combat"
	elseif UnitExists("target") then
		state = "target"
	elseif has_secrets then
		state = SECRET_STATE
	elseif UnitHealth("player") < UnitHealthMax("player") then
		state = "hurt"
	else
		local _, power_token = UnitPowerType("player")
		local func = power_check[power_token]
		if func and func() then
			state = "hurt"
		else
			state = "out_of_combat"
		end
	end
end

function PitBull4_CombatFader:PLAYER_REGEN_ENABLED()
	-- this is handled through a timer because PLAYER_TARGET_CHANGED looks funny otherwise
	timerFrame:Show()
end

function PitBull4_CombatFader:UNIT_HEALTH(event, unit)
	if unit ~= "player" then
		return
	end

	return self:PLAYER_REGEN_ENABLED()
end

function PitBull4_CombatFader:GetOpacity(frame)
	if state == SECRET_STATE then
		return nil
	end

	local layout_db = self:GetLayoutDB(frame)

	return layout_db[state .. "_opacity"]
end

if has_secrets then
	local curve, curve_key

	--- Return the opacity to use, letting the engine pick between the hurt and
	-- out-of-combat opacities by the player's health. Only applies while
	-- neither the combat nor the target state does.
	-- @param frame the unit frame
	-- @param alpha the opacity the other faders agreed on
	-- @return the opacity to use, which may be a secret
	function PitBull4_CombatFader:GetSecretAlpha(frame, alpha)
		if state ~= SECRET_STATE then
			return nil
		end

		local layout_db = self:GetLayoutDB(frame)
		local hurt, full = layout_db.hurt_opacity, layout_db.out_of_combat_opacity
		if not issecretvalue(alpha) then
			if hurt > alpha then hurt = alpha end
			if full > alpha then full = alpha end
		end

		local key = ("%s,%s"):format(hurt, full)
		if key ~= curve_key then
			curve_key = key
			-- a step curve holds the hurt opacity for any missing health and
			-- changes only at exactly full
			curve = C_CurveUtil.CreateCurve()
			curve:SetType(Enum.LuaCurveType.Step)
			curve:AddPoint(0, hurt)
			curve:AddPoint(1, full)
		end
		return UnitHealthPercent("player", true, curve)
	end
end

PitBull4_CombatFader:SetLayoutOptionsFunction(function(self)
	return 'hurt', {
		type = 'range',
		name = L["Hurt opacity"],
		desc = L["The opacity to display if the player is missing health or mana."],
		min = 0,
		max = 1,
		isPercent = true,
		get = function(info)
			local db = PitBull4.Options.GetLayoutDB(self)

			return db.hurt_opacity
		end,
		set = function(info, value)
			local db = PitBull4.Options.GetLayoutDB(self)

			db.hurt_opacity = value

			PitBull4.Options.UpdateFrames()
			PitBull4:RecheckAllOpacities()
		end,
		step = 0.01,
		bigStep = 0.05,
	}, 'in_combat', {
		type = 'range',
		name = L["In-combat opacity"],
		desc = L["The opacity to display if the player is in combat."],
		min = 0,
		max = 1,
		isPercent = true,
		get = function(info)
			local db = PitBull4.Options.GetLayoutDB(self)

			return db.in_combat_opacity
		end,
		set = function(info, value)
			local db = PitBull4.Options.GetLayoutDB(self)

			db.in_combat_opacity = value

			PitBull4.Options.UpdateFrames()
			PitBull4:RecheckAllOpacities()
		end,
		step = 0.01,
		bigStep = 0.05,
	}, 'out_of_combat', {
		type = 'range',
		name = L["Out-of-combat opacity"],
		desc = L["The opacity to display if the player is out of combat."],
		min = 0,
		max = 1,
		isPercent = true,
		get = function(info)
			local db = PitBull4.Options.GetLayoutDB(self)

			return db.out_of_combat_opacity
		end,
		set = function(info, value)
			local db = PitBull4.Options.GetLayoutDB(self)

			db.out_of_combat_opacity = value

			PitBull4.Options.UpdateFrames()
			PitBull4:RecheckAllOpacities()
		end,
		step = 0.01,
		bigStep = 0.05,
	}, 'target', {
		type = 'range',
		name = L["Target-selected opacity"],
		desc = L["The opacity to display if the player is selecting a target."],
		min = 0,
		max = 1,
		isPercent = true,
		get = function(info)
			local db = PitBull4.Options.GetLayoutDB(self)

			return db.target_opacity
		end,
		set = function(info, value)
			local db = PitBull4.Options.GetLayoutDB(self)

			db.target_opacity = value

			PitBull4.Options.UpdateFrames()
			PitBull4:RecheckAllOpacities()
		end,
		step = 0.01,
		bigStep = 0.05,
	}
end)
