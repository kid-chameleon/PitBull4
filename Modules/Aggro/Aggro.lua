
local PitBull4 = _G.PitBull4
local UnitGUID = PitBull4.UnitGUID
local L = PitBull4.L

local issecretvalue = _G.issecretvalue or function() return false end

-- Threat colours
local DEFAULT_TANK_HOLDING_COLOR = {0.05882352941176471, 0.5882352941176471, 0.9019607843137256, 1}
local DEFAULT_TANK_LOSING_COLOR = {1, 0.6274509803921569, 0, 1}
local DEFAULT_TANK_NONE_COLOR = {0.8, 0, 0, 1}

-- UnitThreatSituation is secret for compound tokens (targettarget,
-- focustarget, ...) on clients with secret values; treat that as no aggro
-- rather than comparing it.
local function has_aggro(unit)
	local status = UnitThreatSituation(unit)
	if not status or issecretvalue(status) then
		return false
	end
	return status > 2
end

-- Whether the player counts as a tank: tank role or spec, or (Forever) a tank
-- aura such as Defensive Stance, Bear Form or Righteous Fury
-- (UnitHasEffectivelyTankAura). Blizzard's nameplates and compact frames ask
-- this same helper.
local function compute_is_tank()
	local is_effectively_tank = PlayerUtil and PlayerUtil.IsPlayerEffectivelyTank
	if not is_effectively_tank then
		return false
	end
	local result = is_effectively_tank()
	if issecretvalue(result) then
		return false
	end
	return result and true or false
end

local is_tank = false

local PitBull4_Aggro = PitBull4:NewModule("Aggro", "AceHook-3.0")

PitBull4_Aggro:SetModuleType("custom")
PitBull4_Aggro:SetName(L["Aggro"])
PitBull4_Aggro:SetDescription(L["Add aggro coloring to the unit frame."])
PitBull4_Aggro:SetDefaults({
	kind = "HealthBar",
	tank_threat = true,
},{
	aggro_color = {1, 0, 0, 1},
	tank_holding_color = {unpack(DEFAULT_TANK_HOLDING_COLOR)},
	tank_losing_color = {unpack(DEFAULT_TANK_LOSING_COLOR)},
	tank_none_color = {unpack(DEFAULT_TANK_NONE_COLOR)},
})

local PitBull4_HealthBar
local PitBull4_Border
local PitBull4_Background

local function set_hooks()
	if not PitBull4_HealthBar then
		PitBull4_HealthBar = PitBull4:GetModule("HealthBar", true)
		if PitBull4_HealthBar then
			PitBull4_Aggro:RawHook(PitBull4_HealthBar, "GetColor", "HealthBar_GetColor")
		end
	end

	if not PitBull4_Border then
		PitBull4_Border = PitBull4:GetModule("Border", true)
		if PitBull4_Border then
			PitBull4_Aggro:RawHook(PitBull4_Border, "GetTextureAndColor", "Border_GetTextureAndColor")
		end
	end

	if not PitBull4_Background then
		PitBull4_Background = PitBull4:GetModule("Background", true)
		if PitBull4_Background then
			PitBull4_Aggro:RawHook(PitBull4_Background, "GetColor", "Background_GetColor")
		end
	end
end

-- The tank's threat on an enemy
local function tank_threat_color(self, unit)
	if not UnitCanAttack("player", unit) or UnitIsPlayer(unit) or UnitIsDeadOrGhost(unit) then
		return nil
	end

	local status = UnitThreatSituation("player", unit)
	if issecretvalue(status) then
		return nil
	end
	if status == nil then
		-- Not on its threat list. Still "no aggro" when it is fighting the
		-- group (it went for the healer before the tank touched it);
		-- otherwise it is not in this fight and keeps its normal colour.
		if not UnitAffectingCombat(unit) then
			return nil
		end
		local victim_in_group = UnitInParty(unit .. "target")
		if issecretvalue(victim_in_group) or not victim_in_group then
			return nil
		end
		status = 0
	end

	local global = self.db.profile.global
	if status >= 3 then
		return global.tank_holding_color
	elseif status >= 1 then
		return global.tank_losing_color
	end
	return global.tank_none_color
end

-- The colour this module puts on the frame through `kind`, or nil to leave the
-- frame's normal colour alone.
local function get_aggro_color(self, frame, kind)
	local unit = frame.unit
	if not unit then
		return nil
	end
	local db = self:GetLayoutDB(frame)
	if not db.enabled or db.kind ~= kind then
		return nil
	end

	if UnitIsFriend("player", unit) then
		if has_aggro(unit) then
			return self.db.profile.global.aggro_color
		end
		return nil
	end

	if is_tank and db.tank_threat then
		return tank_threat_color(self, unit)
	end
	return nil
end

-- Repaint whatever this layout shows aggro on.
local function refresh_frame(self, frame)
	local db = self:GetLayoutDB(frame)
	if not db.enabled then
		return
	end
	local module
	if db.kind == "HealthBar" then
		module = PitBull4_HealthBar
	elseif db.kind == "Border" then
		module = PitBull4_Border
	elseif db.kind == "Background" then
		module = PitBull4_Background
	end
	if module and module:IsEnabled() then
		module:UpdateFrame(frame)
	end
end

local function refresh_unit(self, unit)
	local guid = UnitGUID(unit)
	if not guid then
		return
	end
	for frame in PitBull4:IterateFramesForGUID(guid) do
		refresh_frame(self, frame)
	end
end

-- Every frame currently showing an enemy, plus friendly units when `all`.
local function refresh_frames(self, all)
	for frame in PitBull4:IterateFrames() do
		local unit = frame.unit
		if unit and (all or UnitCanAttack("player", unit)) then
			refresh_frame(self, frame)
		end
	end
end

local function update_tank_state(self)
	local new_is_tank = compute_is_tank()
	if new_is_tank ~= is_tank then
		is_tank = new_is_tank
		refresh_frames(self)
	end
end

-- UNIT_AURA filtered to the player for aura-based tank state (Righteous Fury);
-- AceEvent cannot register unit events.
local tank_aura_watcher = CreateFrame("Frame")
tank_aura_watcher:SetScript("OnEvent", function()
	update_tank_state(PitBull4_Aggro)
end)

function PitBull4_Aggro:OnModuleLoaded(module)
	if not self.db.profile.global.enabled then return end
	local id = module.id
	if id == "HealthBar" or id == "Border" or id == "Background" then
		set_hooks()
	end
end

function PitBull4_Aggro:OnEnable()
	self:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
	self:RegisterEvent("UNIT_THREAT_LIST_UPDATE", "EnemyChanged")
	self:RegisterEvent("UNIT_FLAGS", "EnemyChanged")
	self:RegisterEvent("UNIT_TARGET", "EnemyChanged")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "CombatChanged")
	self:RegisterEvent("PLAYER_REGEN_DISABLED", "CombatChanged")

	self:RegisterEvent("PLAYER_ENTERING_WORLD", "TankStateChanged")
	self:RegisterEvent("UPDATE_SHAPESHIFT_FORM", "TankStateChanged")
	self:RegisterEvent("PLAYER_ROLES_ASSIGNED", "TankStateChanged")
	self:RegisterEvent("GROUP_ROSTER_UPDATE", "TankStateChanged")
	self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "TankStateChanged")
	tank_aura_watcher:RegisterUnitEvent("UNIT_AURA", "player")

	set_hooks()
	update_tank_state(self)
end

function PitBull4_Aggro:OnDisable()
	tank_aura_watcher:UnregisterAllEvents()
	is_tank = false
end

function PitBull4_Aggro:HealthBar_GetColor(module, frame, value)
	local color = get_aggro_color(self, frame, "HealthBar")
	if color then
		return color[1], color[2], color[3], nil, true
	end

	return self.hooks[module].GetColor(module, frame, value)
end

function PitBull4_Aggro:Border_GetTextureAndColor(module, frame)
	local texture, r, g, b, a
	if module:GetLayoutDB(frame).enabled then
		-- Only call GetTextureAndColor if the Border is enabled for the layout already.
		-- This allows the border to enable for the aggro display and then disable back
		-- to the normal settings
		texture, r, g, b, a = self.hooks[module].GetTextureAndColor(module, frame)
	end

	local color = get_aggro_color(self, frame, "Border")
	if color then
		r, g, b, a = unpack(color)
		if not texture or texture == "None" then
			texture = "Blizzard Tooltip"
		end
	end

	return texture, r, g, b, a
end

function PitBull4_Aggro:Background_GetColor(module, frame)
	local r, g, b, a
	if module:GetLayoutDB(frame).enabled then
		-- Only call GetColor if the Background is enabled for the layout already.
		-- This allows the background to enable for the aggro display and then disable back
		-- to the normal settings
		r, g, b, a = self.hooks[module].GetColor(module, frame)
	end

	local color = get_aggro_color(self, frame, "Background")
	if color then
		local a2
		r, g, b, a2 = unpack(color)
		if a then
			a = a * a2
		else
			a = a2
		end
	end

	return r, g, b, a
end

function PitBull4_Aggro:UNIT_THREAT_SITUATION_UPDATE(_, unit)
	unit = unit or "player"
	refresh_unit(self, unit)

	-- The player's standing changed on some enemy.
	if is_tank and unit == "player" then
		refresh_frames(self)
	end
end

-- An enemy's threat list, combat state or target changed.
function PitBull4_Aggro:EnemyChanged(_, unit)
	if not is_tank or not unit or not UnitCanAttack("player", unit) then
		return
	end
	refresh_unit(self, unit)
end

function PitBull4_Aggro:CombatChanged()
	if is_tank then
		refresh_frames(self)
	end
end

function PitBull4_Aggro:TankStateChanged()
	update_tank_state(self)
end

PitBull4_Aggro:SetLayoutOptionsFunction(function(self)
	local function is_kind_allowed(kind)
		if kind == "HealthBar" then
			return PitBull4_HealthBar and PitBull4_HealthBar:IsEnabled() and PitBull4.Options.GetLayoutDB(PitBull4_HealthBar.id).enabled
		elseif kind == "Border" then
			return PitBull4_Border and PitBull4_Border:IsEnabled()
		elseif kind == "Background" then
			return PitBull4_Background and PitBull4_Background:IsEnabled()
		elseif kind == "" then
			return true
		else
			return false
		end
	end

	return 'kind', {
		type = 'select',
		name = L["Display"],
		desc = L["How to display the aggro indication."],
		get = function(info)
			local kind = PitBull4.Options.GetLayoutDB(self).kind
			if not is_kind_allowed(kind) then
				return ""
			end
			return kind
		end,
		set = function(info, value)
			PitBull4.Options.GetLayoutDB(self).kind = value

			PitBull4.Options.UpdateFrames()
		end,
		values = function(info)
			local t = {}
			t[""] = L["None"]
			if is_kind_allowed("HealthBar") then
				t.HealthBar = L["Health bar"]
			end
			if is_kind_allowed("Border") then
				t.Border = L["Border"]
			end
			if is_kind_allowed("Background") then
				t.Background = L["Background"]
			end
			return t
		end
	},
	'tank_threat', {
		type = 'toggle',
		name = L["Tank threat on enemies"],
		desc = L["While you are a tank (tank role or spec, or a tank stance, form or aura such as Defensive Stance, Bear Form or Righteous Fury), color enemies by your threat on them: holding aggro, losing aggro, or no aggro. Enemies that are not fighting you or your group keep their normal color."],
		get = function(info)
			return PitBull4.Options.GetLayoutDB(self).tank_threat
		end,
		set = function(info, value)
			PitBull4.Options.GetLayoutDB(self).tank_threat = value

			PitBull4.Options.UpdateFrames()
		end,
	}
end)

PitBull4_Aggro:SetColorOptionsFunction(function(self)
	local function get(info)
		return unpack(self.db.profile.global[info[#info]])
	end
	local function set(info, r, g, b, a)
		self.db.profile.global[info[#info]] = {r, g, b, a}
		refresh_frames(self, true)
	end
	return 'aggro_color', {
		type = 'color',
		name = L["Aggro"],
		desc = L["Sets which color to use on the health bar of units that have aggro."],
		get = get,
		set = set,
	},
	'tank_holding_color', {
		type = 'color',
		name = L["Tank: holding aggro"],
		desc = L["Color for an enemy that is attacking you while you are a tank."],
		get = get,
		set = set,
	},
	'tank_losing_color', {
		type = 'color',
		name = L["Tank: losing aggro"],
		desc = L["Color for an enemy whose aggro you are about to lose, or about to win back, while you are a tank."],
		get = get,
		set = set,
	},
	'tank_none_color', {
		type = 'color',
		name = L["Tank: no aggro"],
		desc = L["Color for an enemy that is fighting your group but not attacking you while you are a tank."],
		get = get,
		set = set,
	},
	function(info)
		local global = self.db.profile.global
		global.aggro_color = {1, 0, 0, 1}
		global.tank_holding_color = {unpack(DEFAULT_TANK_HOLDING_COLOR)}
		global.tank_losing_color = {unpack(DEFAULT_TANK_LOSING_COLOR)}
		global.tank_none_color = {unpack(DEFAULT_TANK_NONE_COLOR)}
	end
end)
