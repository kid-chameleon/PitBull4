
local PitBull4 = _G.PitBull4
local L = PitBull4.L

local UnitGetTotalAbsorbs = _G.UnitGetTotalAbsorbs or nil  -- XXX UnitGetTotalAbsorbs was added in MoP but classic doesn't have the API?

local EPSILON = 1e-5

-- Secret values (WoW: Forever): heal and absorb amounts are unreadable. The
-- engine's heal prediction calculator yields every layer as an absolute
-- amount, clamps them by mode, and reports whether a layer was clamped, so
-- the bar takes the amounts with SetMaxValue(maximum health) and the
-- overheal colour is picked by SetVertexColorFromBoolean. Nothing is divided
-- or compared here.
local has_secrets = PitBull4.has_secrets
local calculator = has_secrets and _G.CreateUnitHealPredictionCalculator and CreateUnitHealPredictionCalculator()

local REVERSE_POINT = {
	LEFT = "RIGHT",
	RIGHT = "LEFT",
	TOP = "BOTTOM",
	BOTTOM = "TOP",
}

local PitBull4_VisualHeal = PitBull4:NewModule("VisualHeal")

PitBull4_VisualHeal:SetModuleType("custom")
PitBull4_VisualHeal:SetName(L["Visual heal"])
PitBull4_VisualHeal:SetDescription(L["Visualises healing done by you and your group members before it happens."])
PitBull4_VisualHeal:SetDefaults({
	show_overheal = true,
	show_overabsorb = true,
}, {
	incoming_color = { 0.4, 0.6, 0.4, 0.75 },
	outgoing_color = { 0, 1, 0, 1 },
	outgoing_color_overheal = { 1, 0, 0, 0.65 },
	absorb_color = { .4, .258, .619, 1},
	auto_luminance = true,
})

local function clamp(value, min, max)
	if value < min then
		return min
	elseif value > max then
		return max
	else
		return value
	end
end

function PitBull4_VisualHeal:OnEnable()
	self:RegisterEvent("UNIT_HEAL_PREDICTION")
	self:RegisterEvent("UNIT_HEALTH", "UNIT_HEAL_PREDICTION")
	self:RegisterEvent("UNIT_MAXHEALTH", "UNIT_HEAL_PREDICTION")
	if UnitGetTotalAbsorbs then
		self:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_HEAL_PREDICTION")
	end
end

function PitBull4_VisualHeal:UpdateFrame(frame)
	local health_bar = frame.HealthBar
	local unit = frame.unit
	local guid = frame.guid
	if not health_bar or not unit or not guid then
		return self:ClearFrame(frame)
	end

	if calculator then
		return self:UpdateSecretFrame(frame, health_bar, unit)
	end

	local player_healing = UnitGetIncomingHeals(unit, "player")
	local all_healing = UnitGetIncomingHeals(unit)
	local all_absorbs = UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit) or nil
	-- Bail out early if nothing going on for this unit
	if not player_healing and not all_healing and not all_absorbs then
		return self:ClearFrame(frame)
	end
	player_healing = player_healing or 0
	all_healing = all_healing or 0
	all_absorbs = all_absorbs or 0
	local others_healing = all_healing - player_healing


	local unit_health_max = UnitHealthMax(unit)
	local current_percent = 0
	local others_percent = 0
	local player_percent = 0
	local absorb_percent = 0
	if unit_health_max ~= 0 then
		current_percent = UnitHealth(unit) / unit_health_max
		others_percent = others_healing and others_healing / unit_health_max
		player_percent = player_healing and player_healing / unit_health_max
		absorb_percent = all_absorbs and all_absorbs / unit_health_max
	end

	if others_percent <= 0 and player_percent <= 0 and absorb_percent <= 0 then
		return self:ClearFrame(frame)
	end

	local bar = frame.VisualHeal
	if not bar then
		bar = PitBull4.Controls.MakeBetterStatusBar(health_bar)
		frame.VisualHeal = bar
		bar:SetBackgroundAlpha(0)
	end

	local show_overheal = self:GetLayoutDB(frame).show_overheal
	local show_overabsorb = self:GetLayoutDB(frame).show_overabsorb

	-- If the user has selected to not show overheal we make sure to not set a value that goes beyond 100%.
	if not show_overheal and ((others_percent+current_percent) > 1) then
		others_percent = 1 - current_percent
	end

	bar:SetValue(math.min(others_percent, 1))

	if not show_overheal and ((player_percent+others_percent+current_percent) > 1) then
		player_percent = 1 - (others_percent+current_percent)
	end

	bar:SetExtraValue(player_percent)

	if not show_overabsorb and ((player_percent+others_percent+current_percent+absorb_percent) > 1) then
		absorb_percent = 1 - (player_percent+others_percent+current_percent)
	end
	bar:SetExtra2Value(absorb_percent)

	bar:SetTexture(health_bar:GetTexture())

	local deficit = health_bar.deficit
	local orientation = health_bar.orientation
	local reverse = health_bar.reverse
	bar:SetOrientation(orientation)
	bar:SetReverse(deficit ~= reverse)
	bar:SetDeficit(false)

	bar:ClearAllPoints()
	local point, attach, attach_frame
	if orientation == "HORIZONTAL" then
		point, attach = "LEFT", "RIGHT"
		bar:SetWidth(health_bar:GetWidth())
		bar:SetHeight(0)
		bar:SetPoint("TOP", health_bar, "TOP")
		bar:SetPoint("BOTTOM", health_bar, "BOTTOM")
	else
		point, attach = "BOTTOM", "TOP"
		bar:SetHeight(health_bar:GetHeight())
		bar:SetWidth(0)
		bar:SetPoint("LEFT", health_bar, "LEFT")
		bar:SetPoint("RIGHT", health_bar, "RIGHT")
	end

	if deficit then
		point, attach = attach, point
		attach_frame = health_bar.bg
	else
		attach_frame = health_bar.fg
	end

	if reverse then
		point, attach = REVERSE_POINT[point], REVERSE_POINT[attach]
	end

	bar:SetPoint(point, attach_frame, attach)

	local db = self.db.profile.global

	if others_percent > 0 then
		local r, g, b, a = unpack(db.incoming_color)
		bar:SetColor(r, g, b)
		bar:SetNormalAlpha(a)
	end

	if player_percent > 0 then
		local waste = clamp((current_percent + others_percent + player_percent - 1) / player_percent, 0, 1)

		local r, g, b, a = unpack(db.outgoing_color)
		if waste > 0 then
			local r2, g2, b2, a2 = unpack(db.outgoing_color_overheal)

			local inverse_waste = 1 - waste
			r = r * inverse_waste + r2 * waste
			g = g * inverse_waste + g2 * waste
			b = b * inverse_waste + b2 * waste
			a = a * inverse_waste + a2 * waste
		end

		if db.auto_luminance then
			local high = math.max(r, g, b, EPSILON)
			r, g, b = r / high, g / high, b / high
		end

		bar:SetExtraColor(r, g, b)
		bar:SetExtraAlpha(a)
	end

	if absorb_percent > 0 then
		local r, g, b, a = unpack(db.absorb_color)
		bar:SetExtra2Color(r, g, b)
		bar:SetExtra2Alpha(a)
	end

	return true
end

-- Anchor the overlay bar to the end of the health bar's fill.
local function attach_overlay(bar, health_bar)
	bar:SetTexture(health_bar:GetTexture())

	local deficit = health_bar.deficit
	local orientation = health_bar.orientation
	local reverse = health_bar.reverse
	bar:SetOrientation(orientation)
	bar:SetReverse(deficit ~= reverse)
	bar:SetDeficit(false)

	bar:ClearAllPoints()
	local point, attach, attach_frame
	if orientation == "HORIZONTAL" then
		point, attach = "LEFT", "RIGHT"
		bar:SetWidth(health_bar:GetWidth())
		bar:SetHeight(0)
		bar:SetPoint("TOP", health_bar, "TOP")
		bar:SetPoint("BOTTOM", health_bar, "BOTTOM")
	else
		point, attach = "BOTTOM", "TOP"
		bar:SetHeight(health_bar:GetHeight())
		bar:SetWidth(0)
		bar:SetPoint("LEFT", health_bar, "LEFT")
		bar:SetPoint("RIGHT", health_bar, "RIGHT")
	end

	if deficit then
		point, attach = attach, point
		attach_frame = health_bar.bg
	else
		attach_frame = health_bar.fg
	end

	if reverse then
		point, attach = REVERSE_POINT[point], REVERSE_POINT[attach]
	end

	bar:SetPoint(point, attach_frame, attach)
end

local function luminance(r, g, b, auto)
	if not auto then
		return r, g, b
	end
	local high = math.max(r, g, b, EPSILON)
	return r / high, g / high, b / high
end

local outgoing_color = CreateColor(0, 1, 0, 1)
local overheal_color = CreateColor(1, 0, 0, 0.65)

function PitBull4_VisualHeal:UpdateSecretFrame(frame, health_bar, unit)
	local layout_db = self:GetLayoutDB(frame)
	local MISSING = Enum.UnitIncomingHealClampMode.MissingHealth
	local display_mode = layout_db.show_overheal and Enum.UnitIncomingHealClampMode.MaximumHealth or MISSING
	calculator:SetDamageAbsorbClampMode(layout_db.show_overabsorb and Enum.UnitDamageAbsorbClampMode.MaximumHealth or Enum.UnitDamageAbsorbClampMode.MissingHealth)

	-- "some of this heal is wasted" is only reported as clamped while the
	-- boundary is missing health, so read the flag in that mode first. The
	-- player's layer is drawn last, so any excess belongs to it.
	calculator:SetIncomingHealClampMode(MISSING)
	UnitGetDetailedHealPrediction(unit, "player", calculator)
	local _, _, _, heal_clamped = calculator:GetIncomingHeals()

	-- then take the amounts under the boundary the user asked to see: with
	-- overheal shown the layers are clamped only by maximum health, so they
	-- extend past the end of the health bar by their real size
	if display_mode ~= MISSING then
		calculator:SetIncomingHealClampMode(display_mode)
		UnitGetDetailedHealPrediction(unit, "player", calculator)
	end

	local max = calculator:GetMaximumHealth()
	local _, player_healing, others_healing = calculator:GetIncomingHeals()
	local absorbs = calculator:GetDamageAbsorbs()

	local bar = frame.VisualHeal
	local made = not bar
	if made then
		bar = PitBull4.Controls.MakeSecretStatusBar(health_bar)
		frame.VisualHeal = bar
		bar:SetBackgroundAlpha(0)
	end

	attach_overlay(bar, health_bar)
	-- the overlay hangs off the fill texture, so its own rect is secret;
	-- the health bar's rect is plain
	bar:SetLayerSize(health_bar:GetWidth(), health_bar:GetHeight())

	-- the layers are zero-length when nothing is incoming; the bar stays
	-- since whether anything is incoming cannot be decided
	bar:SetMaxValue(max)
	bar:SetValue(others_healing)
	bar:SetExtraValue(player_healing)
	bar:SetExtra2Value(absorbs)

	local db = self.db.profile.global
	local r, g, b, a = unpack(db.incoming_color)
	bar:SetColor(r, g, b)
	bar:SetNormalAlpha(a)

	r, g, b, a = unpack(db.outgoing_color)
	r, g, b = luminance(r, g, b, db.auto_luminance)
	outgoing_color:SetRGBA(r, g, b, a)
	r, g, b, a = unpack(db.outgoing_color_overheal)
	r, g, b = luminance(r, g, b, db.auto_luminance)
	overheal_color:SetRGBA(r, g, b, a)
	bar:SetExtraColor(1, 1, 1)
	bar:SetExtraAlpha(1)
	-- last, after every control call that would reset the layer's colour
	bar.extra_fg:SetVertexColorFromBoolean(heal_clamped, overheal_color, outgoing_color)

	r, g, b, a = unpack(db.absorb_color)
	bar:SetExtra2Color(r, g, b)
	bar:SetExtra2Alpha(a)

	return made
end

function PitBull4_VisualHeal:UNIT_HEAL_PREDICTION(_, unit)
	if not unit then return end
	self:UpdateForUnitID(unit)
end

function PitBull4_VisualHeal:ClearFrame(frame)
	if not frame.VisualHeal then
		return false
	end

	frame.VisualHeal = frame.VisualHeal:Delete()
	return true
end

PitBull4_VisualHeal.OnHide = PitBull4_VisualHeal.ClearFrame

PitBull4_VisualHeal:SetColorOptionsFunction(function(self)
	local function get(info)
		return unpack(self.db.profile.global[info[#info]])
	end
	local function set(info, r, g, b, a)
		local color = self.db.profile.global[info[#info]]
		color[1], color[2], color[3], color[4] = r, g, b, a
		self:UpdateAll()
	end
	return 'incoming_color', {
		type = 'color',
		name = L["Incoming color"],
		desc = L["The color of the bar that shows incoming heals from other players."],
		get = get,
		set = set,
		hasAlpha = true,
		width = 'double',
	},
	'outgoing_color', {
		type = 'color',
		name = L["Outgoing color (no overheal)"],
		desc = L["The color of the bar that shows your own heals, when no overhealing is due."],
		get = get,
		set = set,
		hasAlpha = true,
		width = 'double',
	},
	'outgoing_color_overheal', {
		type = 'color',
		name = L["Outgoing color (overheal)"],
		desc = L["The color of the bar that shows your own heals, when full overhealing is due."],
		get = get,
		set = set,
		hasAlpha = true,
		width = 'double',
	},
	'absorb_color', {
		type = 'color',
		name = L["Absorb color"],
		desc = L["The color of the bar that shows absorption shields."],
		get = get,
		set = set,
		hasAlpha = true,
		width = 'double',
	},
	'auto_luminance', {
		type = 'toggle',
		name = L["Auto-luminance"],
		desc = L["Automatically adjust the luminance of the color of the outgoing heal bar to max."],
		get = function(info)
			return self.db.profile.global.auto_luminance
		end,
		set = function(info, value)
			self.db.profile.global.auto_luminance = value
			self:UpdateAll()
		end,
		width = 'double',
	},
	function(info)
		self.db.profile.global.incoming_color = { 0.4, 0.6, 0.4, 0.75 }
		self.db.profile.global.outgoing_color = { 0, 1, 0, 1 }
		self.db.profile.global.outgoing_color_overheal = { 1, 0, 0, 0.65 }
		self.db.profile.global.absorb_color = { .4, .258, .619, 1}
		self.db.profile.global.auto_luminance = true
	end
end)

PitBull4_VisualHeal:SetLayoutOptionsFunction(function(self)
	local function disabled(info)
		return not PitBull4.Options.GetLayoutDB(self).enabled
	end

	return 'show_overheal', {
		type = 'toggle',
		name = L["Show overheals"],
		desc = L["Show overheals past the end of the health bar."],
		get = function(info)
			return PitBull4.Options.GetLayoutDB(self).show_overheal
		end,
		set = function(info, value)
			PitBull4.Options.GetLayoutDB(self).show_overheal = value
		end,
		disabled = disabled,
	}, 'show_overabsorb', {
		type = 'toggle',
		name = L["Show overabsorb"],
		desc = L["Show absorb past the end of the health bar."],
		get = function(info)
			return PitBull4.Options.GetLayoutDB(self).show_overabsorb
		end,
		set = function(info, value)
			PitBull4.Options.GetLayoutDB(self).show_overabsorb = value
		end,
		hidden = not UnitGetTotalAbsorbs,
		disabled = disabled,
	}

end)
