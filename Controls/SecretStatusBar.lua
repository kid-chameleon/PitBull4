-- A status bar for clients that enforce secret values (WoW: Forever).
--
-- BetterStatusBar draws its layers out of textures whose sizes are computed
-- in Lua from the value, which is impossible when the value is a secret.
-- This control keeps BetterStatusBar's public surface but is built out of
-- real StatusBar widgets so the engine does every computation:
--
--   * the main bar takes the value directly (SetMinMaxValues(0, 1) + SetValue),
--   * "extra" and "extra2" are sibling StatusBars anchored to the end of the
--     main bar's fill texture, so they continue where the fill stops without
--     anyone adding values together,
--   * animation is the engine's own interpolation,
--   * "deficit" is reverse fill plus swapped foreground/background colours:
--     the unfilled part of a reversed bar is exactly the missing fraction,
--   * colours may be secret (a colour curve evaluated by the engine); the
--     derived background/extra colours BetterStatusBar computes from the
--     foreground colour cannot be derived from a secret, so a neutral grey is
--     used unless the module supplies them explicitly.
--
-- Getters return the values that were set, never what the widget reports:
-- once a widget has taken a secret its getters return secrets for good.
--
-- Only used when PitBull4.has_secrets is true; the other flavours keep
-- BetterStatusBar untouched.

local _G = _G
local PitBull4 = _G.PitBull4

local DEBUG = PitBull4.DEBUG
local expect = PitBull4.expect

local issecretvalue = _G.issecretvalue or function() return false end

local INTERPOLATION_IMMEDIATE = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate
local TIMER_ELAPSED = Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.ElapsedTime

-- A zero-length duration. There is no API to take a bar back out of timer
-- mode, so setting a plain value hands it this instead.
local ZERO_DURATION
if C_DurationUtil and C_DurationUtil.CreateDuration then
	local ok, duration = pcall(C_DurationUtil.CreateDuration)
	if ok and duration then
		ZERO_DURATION = duration
	end
end
local INTERPOLATION_SMOOTH = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut

local DEFAULT_TEXTURE = [[Interface\Buttons\WHITE8X8]]

-- everything in here will be added to the controls verbatim
local SecretStatusBar = {
	value = 1,
	max_value = 1,
	timer_duration = nil,
	extraValue = 0,
	extra2Value = 0,
	orientation = "HORIZONTAL",
	reverse = false,
	deficit = false,
	animated = false,
	anim_duration = 0.5,
	fade = false,
	fgR = 1,
	fgG = 1,
	fgB = 1,
	fgA = 1,
	bgR = false,
	bgG = false,
	bgB = false,
	bgA = false,
	extraR = false,
	extraG = false,
	extraB = false,
	extraA = false,
	extra2R = false,
	extra2G = false,
	extra2B = false,
	extra2A = false,
	icon_path = nil,
	icon_position = true,
	layer_width = nil,
	layer_height = nil,
	texture_path = nil,
	atlas = nil,
}

local function is_secret_color(r, g, b)
	return issecretvalue(r) or issecretvalue(g) or issecretvalue(b)
end

-- the same variations BetterStatusBar derives from the normal colour, with a
-- neutral fallback when the normal colour is a secret
local function normal_to_extra_color(r, g, b)
	if is_secret_color(r, g, b) then
		return 0.5, 0.5, 0.5
	end
	return (r + 0.25)/1.5, (g + 0.25)/1.5, (b + 0.25)/1.5
end

local function normal_to_extra2_color(r, g, b)
	if is_secret_color(r, g, b) then
		return 0.4, 0.4, 0.4
	end
	return (r + 0.25)/1.75, (g + 0.25)/1.75, (b + 0.25)/1.75
end

local function normal_to_bg_color(r, g, b)
	if is_secret_color(r, g, b) then
		return 0.2, 0.2, 0.2
	end
	return (r + 0.2)/3, (g + 0.2)/3, (b + 0.2)/3
end

local function get_interpolation(self)
	if self.animated or self.fade then
		return INTERPOLATION_SMOOTH
	end
	return INTERPOLATION_IMMEDIATE
end

-- push the shadow colours and alphas onto the widgets
local function apply_colors(self)
	local r, g, b, a = self.fgR, self.fgG, self.fgB, self.fgA
	local br, bgg, bb, ba = self.bgR, self.bgG, self.bgB, self.bgA
	if not br then
		br, bgg, bb = normal_to_bg_color(r, g, b)
	end
	if not ba then
		ba = a
	end
	local er, eg, eb, ea = self.extraR, self.extraG, self.extraB, self.extraA
	if not er then
		er, eg, eb = normal_to_extra_color(r, g, b)
	end
	if not ea then
		ea = a
	end
	local e2r, e2g, e2b, e2a = self.extra2R, self.extra2G, self.extra2B, self.extra2A
	if not e2r then
		e2r, e2g, e2b = normal_to_extra2_color(r, g, b)
	end
	if not e2a then
		e2a = a
	end

	if self.deficit then
		-- the unfilled part of the reversed bar is the deficit, so it gets
		-- the normal colour and the fill gets the background colour
		r, g, b, a, br, bgg, bb, ba = br, bgg, bb, ba, r, g, b, a
	end

	if self.atlas and not self.deficit then
		self.bar:SetStatusBarColor(1, 1, 1)
	else
		self.bar:SetStatusBarColor(r, g, b)
	end
	self.fg:SetAlpha(a)
	self.bg:SetVertexColor(br, bgg, bb)
	self.bg:SetAlpha(ba)
	self.extra:SetStatusBarColor(er, eg, eb)
	self.extra_fg:SetAlpha(ea)
	self.extra2:SetStatusBarColor(e2r, e2g, e2b)
	self.extra2_fg:SetAlpha(e2a)
end

local function fix_icon_size(self)
	local icon = self.icon
	if not icon then
		return
	end

	local size = self.orientation == "VERTICAL" and self:GetWidth() or self:GetHeight()
	icon:SetWidth(size)
	icon:SetHeight(size)
end

-- the extra bars must be as long as the main bar so their fill fraction
-- means the same thing; anchoring alone cannot express that. A control
-- anchored to another bar's fill texture has a secret rect, so its owner
-- has to supply the size through SetLayerSize.
local function fix_extra_sizes(self)
	local width, height = self.layer_width, self.layer_height
	if not width then
		local bar = self.bar
		width, height = bar:GetWidth(), bar:GetHeight()
		if issecretvalue(width) or issecretvalue(height) then
			return
		end
	end
	self.extra:SetSize(width, height)
	self.extra2:SetSize(width, height)
end

-- readjust where everything is positioned, in case any settings have changed
local function fix_orientation(self)
	local bar, extra, extra2, bg, icon = self.bar, self.extra, self.extra2, self.bg, self.icon
	bar:ClearAllPoints()
	extra:ClearAllPoints()
	extra2:ClearAllPoints()
	bg:ClearAllPoints()

	local side_a, side_b, edge_start, edge_end
	if self.orientation == "VERTICAL" then
		side_a, side_b, edge_start, edge_end = "LEFT", "RIGHT", "BOTTOM", "TOP"
	else
		side_a, side_b, edge_start, edge_end = "BOTTOM", "TOP", "LEFT", "RIGHT"
	end
	if self.reverse then
		edge_start, edge_end = edge_end, edge_start
	end

	-- the fill grows from edge_start; deficit flips it so the unfilled part
	-- (the deficit) sits at edge_start instead
	local fill_from_end = self.reverse ~= self.deficit
	bar:SetOrientation(self.orientation)
	bar:SetReverseFill(fill_from_end)
	extra:SetOrientation(self.orientation)
	extra:SetReverseFill(fill_from_end)
	extra2:SetOrientation(self.orientation)
	extra2:SetReverseFill(fill_from_end)

	if icon then
		icon:ClearAllPoints()
		fix_icon_size(self)
		icon:SetPoint(side_a)
		icon:SetPoint(side_b)
		if self.icon_position then
			-- icon is fixed to the starting edge, the bar attaches to it
			icon:SetPoint(edge_start)
			bar:SetPoint(edge_start, icon, edge_end)
			bar:SetPoint(edge_end)
		else
			icon:SetPoint(edge_end)
			bar:SetPoint(edge_start)
			bar:SetPoint(edge_end, icon, edge_start)
		end
	else
		bar:SetPoint(edge_start)
		bar:SetPoint(edge_end)
	end
	bar:SetPoint(side_a)
	bar:SetPoint(side_b)
	bg:SetAllPoints(bar)

	-- extra starts where the fill stops, extra2 where extra stops. In terms
	-- of the (possibly swapped) edges the fill grows from edge_start unless
	-- deficit flipped it.
	local fill_end = self.deficit and edge_start or edge_end
	local fill_start = self.deficit and edge_end or edge_start
	extra:SetPoint(side_a, bar, side_a)
	extra:SetPoint(side_b, bar, side_b)
	extra:SetPoint(fill_start, self.fg, fill_end)
	extra2:SetPoint(side_a, bar, side_a)
	extra2:SetPoint(side_b, bar, side_b)
	extra2:SetPoint(fill_start, self.extra_fg, fill_end)
	fix_extra_sizes(self)

	apply_colors(self)
end

--- Set the value of the bar
-- @param value a number within [0, 1], possibly a secret
-- @usage bar:SetValue(0.5)
function SecretStatusBar:SetValue(value)
	if self.timer_duration then
		-- leave timer mode, or the engine keeps recomputing the value from
		-- the duration and overwrites this one
		self.timer_duration = nil
		if ZERO_DURATION then
			self.bar:SetTimerDuration(ZERO_DURATION, INTERPOLATION_IMMEDIATE, TIMER_ELAPSED)
		end
	end
	self.value = value
	self.bar:SetValue(value, get_interpolation(self))
end

--- Have the engine drive the bar from a duration object, so it animates
-- against the clock with no per-frame work and without anyone reading the
-- times, which may be secret. Setting a plain value leaves this mode again.
-- @param duration a LuaDurationObject
-- @param interpolation an Enum.StatusBarInterpolation value, or nil for Immediate
-- @param direction an Enum.StatusBarTimerDirection value, or nil for ElapsedTime
-- @usage bar:SetTimerDuration(UnitCastingDuration(unit))
function SecretStatusBar:SetTimerDuration(duration, interpolation, direction)
	self.timer_duration = duration
	self.bar:SetTimerDuration(duration, interpolation or INTERPOLATION_IMMEDIATE, direction or TIMER_ELAPSED)
end

--- Get the duration object driving the bar, if it is in timer mode
function SecretStatusBar:GetTimerDuration()
	return self.timer_duration
end

--- Set the maximum of the bar and its layers. Values are then absolute
-- amounts in [0, max] instead of fractions; max may be a secret.
-- @param max the maximum value
-- @usage bar:SetMaxValue(UnitHealthMax(unit))
function SecretStatusBar:SetMaxValue(max)
	self.max_value = max
	self.bar:SetMinMaxValues(0, max)
	self.extra:SetMinMaxValues(0, max)
	self.extra2:SetMinMaxValues(0, max)
end

--- Set the size of the bar area explicitly, for a control whose own rect
-- cannot be read because it is anchored to a secret-sized region.
-- @param width the width of the bar area, or nil to read it from the widget
-- @param height the height of the bar area
-- @usage bar:SetLayerSize(health_bar:GetWidth(), health_bar:GetHeight())
function SecretStatusBar:SetLayerSize(width, height)
	self.layer_width, self.layer_height = width, height
	fix_extra_sizes(self)
end

--- Get the value of the bar, as it was last set
-- @usage local value = bar:GetValue()
-- @return a number within [0, 1], possibly a secret
function SecretStatusBar:GetValue()
	return self.value
end

--- Set the extra value of the bar, which continues where the value stops
-- @param extraValue a number within [0, 1 - value], possibly a secret
-- @usage bar:SetExtraValue(0.2)
function SecretStatusBar:SetExtraValue(extraValue)
	self.extraValue = extraValue
	self.extra:SetValue(extraValue, get_interpolation(self))
end

--- Get the extra value of the bar, as it was last set
-- @usage local extraValue = bar:GetExtraValue()
-- @return a number within [0, 1], possibly a secret
function SecretStatusBar:GetExtraValue()
	return self.extraValue
end

--- Set the second extra value of the bar, which continues where the extra value stops
-- @param extra2Value a number within [0, 1 - value - extraValue], possibly a secret
-- @usage bar:SetExtra2Value(0.1)
function SecretStatusBar:SetExtra2Value(extra2Value)
	self.extra2Value = extra2Value
	self.extra2:SetValue(extra2Value, get_interpolation(self))
end

function SecretStatusBar:GetExtra2Value()
	return self.extra2Value
end
SecretStatusBar.GetExtra2Value2 = SecretStatusBar.GetExtra2Value

--- Set the orientation of the bar
-- @param orientation "HORIZONTAL" or "VERTICAL"
-- @usage bar:SetOrientation("VERTICAL")
function SecretStatusBar:SetOrientation(orientation)
	if DEBUG then
		expect(orientation, 'inset', {HORIZONTAL=true, VERTICAL=true})
	end

	if self.orientation == orientation then
		return
	end
	self.orientation = orientation
	fix_orientation(self)
end

function SecretStatusBar:GetOrientation()
	return self.orientation
end

--- Set whether the bar is reversed, i.e. fills from the right or top
-- @param reverse a boolean
-- @usage bar:SetReverse(true)
function SecretStatusBar:SetReverse(reverse)
	if DEBUG then
		expect(reverse, 'typeof', 'boolean')
	end

	if self.reverse == reverse then
		return
	end
	self.reverse = reverse
	fix_orientation(self)
end

function SecretStatusBar:GetReverse()
	return self.reverse
end

--- Set whether the bar shows the deficit, i.e. 1 - value, instead of the value
-- @param deficit a boolean
-- @usage bar:SetDeficit(true)
function SecretStatusBar:SetDeficit(deficit)
	if DEBUG then
		expect(deficit, 'typeof', 'boolean')
	end

	if self.deficit == deficit then
		return
	end
	self.deficit = deficit
	fix_orientation(self)
end

function SecretStatusBar:GetDeficit()
	return self.deficit
end

--- Set whether value changes are animated. The engine interpolates; the
-- duration is not configurable.
function SecretStatusBar:SetAnimated(animated)
	if DEBUG then
		expect(animated, 'typeof', 'boolean')
	end
	self.animated = animated
end

function SecretStatusBar:GetAnimated()
	return self.animated
end

--- Fading the changed region is not possible on a real StatusBar; it is
-- treated as animation.
function SecretStatusBar:SetFade(fade)
	if DEBUG then
		expect(fade, 'typeof', 'boolean')
	end
	self.fade = fade
end

function SecretStatusBar:GetFade()
	return self.fade
end

function SecretStatusBar:SetAnimDuration(anim_duration)
	if DEBUG then
		expect(anim_duration, 'typeof', 'number')
	end
	self.anim_duration = anim_duration
end

function SecretStatusBar:GetAnimDuration()
	return self.anim_duration
end

--- Set the texture of the bar and its layers
-- @param texture the texture path
-- @usage bar:SetTexture([[Interface\TargetingFrame\UI-StatusBar]])
function SecretStatusBar:SetTexture(texture)
	if DEBUG then
		expect(texture, 'typeof', 'string;number;nil')
	end

	if texture then
		local new_texture = texture
		if type(new_texture) == "string" then
			new_texture = new_texture:gsub("%.tga$", ""):gsub("%.blp$", "")
		end
		if self.texture_path == new_texture then
			return
		end
		self.texture_path = new_texture
	else
		self.texture_path = nil
	end

	self.bar:SetStatusBarTexture(texture or DEFAULT_TEXTURE)
	self.fg = self.bar:GetStatusBarTexture()
	self.extra:SetStatusBarTexture(texture or DEFAULT_TEXTURE)
	self.extra_fg = self.extra:GetStatusBarTexture()
	self.extra2:SetStatusBarTexture(texture or DEFAULT_TEXTURE)
	self.extra2_fg = self.extra2:GetStatusBarTexture()
	self.bg:SetTexture(texture or DEFAULT_TEXTURE)
	if self.atlas then
		self.fg:SetAtlas(self.atlas)
	end
	-- the extra layers are anchored to the fill textures, which may have
	-- been replaced
	fix_orientation(self)
end

--- Get the texture that the bar is using, as it was last set
-- @return the path to the texture
function SecretStatusBar:GetTexture()
	return self.texture_path
end
SecretStatusBar.GetStatusBarTexture = SecretStatusBar.GetTexture

function SecretStatusBar:SetAtlas(atlas)
	self.atlas = atlas
	if atlas then
		self.fg:SetAtlas(atlas)
	elseif self.texture_path then
		self.fg:SetTexture(self.texture_path)
	end
	apply_colors(self)
end
SecretStatusBar.SetStatusBarAltas = SecretStatusBar.SetAtlas

function SecretStatusBar:GetAtlas()
	return self.atlas
end
SecretStatusBar.GetStatusBarAltas = SecretStatusBar.GetAtlas

--- Set the color of the bar. If the background, extra or extra2 color is
-- not set, they take on a variation of this color, or a neutral grey when
-- this color is a secret.
-- @param r the red value [0, 1], possibly a secret
-- @param g the green value [0, 1], possibly a secret
-- @param b the blue value [0, 1], possibly a secret
-- @usage bar:SetColor(1, 0.82, 0)
function SecretStatusBar:SetColor(r, g, b)
	self.fgR, self.fgG, self.fgB = r, g, b
	apply_colors(self)
end

--- Get the color of the bar, as it was last set
-- @return the red, green and blue values, possibly secrets
function SecretStatusBar:GetColor()
	return self.fgR, self.fgG, self.fgB
end
SecretStatusBar.GetStatusBarColor = SecretStatusBar.GetColor

--- Set the alpha value of the bar. Layers without their own alpha follow it.
-- @param a the alpha value [0, 1]
-- @usage bar:SetNormalAlpha(0.7)
function SecretStatusBar:SetNormalAlpha(a)
	if DEBUG then
		expect(a, 'typeof', 'number')
	end
	self.fgA = a
	apply_colors(self)
end

function SecretStatusBar:GetNormalAlpha()
	return self.fgA
end

--- Set the background color of the bar, or nil to derive it from the normal color
-- @usage bar:SetBackgroundColor(0.5, 0.41, 0)
-- @usage bar:SetBackgroundColor()
function SecretStatusBar:SetBackgroundColor(br, bg, bb)
	if br then
		self.bgR, self.bgG, self.bgB = br, bg, bb
	else
		self.bgR, self.bgG, self.bgB = false, false, false
	end
	apply_colors(self)
end

function SecretStatusBar:GetBackgroundColor()
	if self.bgR then
		return self.bgR, self.bgG, self.bgB
	end
	return normal_to_bg_color(self.fgR, self.fgG, self.fgB)
end

--- Set the background alpha of the bar, or nil to follow the normal alpha
function SecretStatusBar:SetBackgroundAlpha(a)
	if DEBUG then
		expect(a, 'typeof', 'number;nil')
	end
	self.bgA = a or false
	apply_colors(self)
end

function SecretStatusBar:GetBackgroundAlpha()
	return self.bgA or self.fgA
end

--- Set the extra color of the bar, or nil to derive it from the normal color
function SecretStatusBar:SetExtraColor(er, eg, eb)
	if er then
		self.extraR, self.extraG, self.extraB = er, eg, eb
	else
		self.extraR, self.extraG, self.extraB = false, false, false
	end
	apply_colors(self)
end

function SecretStatusBar:GetExtraColor()
	if self.extraR then
		return self.extraR, self.extraG, self.extraB
	end
	return normal_to_extra_color(self.fgR, self.fgG, self.fgB)
end

function SecretStatusBar:SetExtraAlpha(a)
	if DEBUG then
		expect(a, 'typeof', 'number;nil')
	end
	self.extraA = a or false
	apply_colors(self)
end

function SecretStatusBar:GetExtraAlpha()
	return self.extraA or self.fgA
end

--- Set the extra2 color of the bar, or nil to derive it from the normal color
function SecretStatusBar:SetExtra2Color(er, eg, eb)
	if er then
		self.extra2R, self.extra2G, self.extra2B = er, eg, eb
	else
		self.extra2R, self.extra2G, self.extra2B = false, false, false
	end
	apply_colors(self)
end

function SecretStatusBar:GetExtra2Color()
	if self.extra2R then
		return self.extra2R, self.extra2G, self.extra2B
	end
	return normal_to_extra2_color(self.fgR, self.fgG, self.fgB)
end

function SecretStatusBar:SetExtra2Alpha(a)
	if DEBUG then
		expect(a, 'typeof', 'number;nil')
	end
	self.extra2A = a or false
	apply_colors(self)
end

function SecretStatusBar:GetExtra2Alpha()
	return self.extra2A or self.fgA
end

function SecretStatusBar:GetMinMaxValues()
	return 0, self.max_value
end

--- Return the icon's texture path of the bar
-- @return the texture path or nil
function SecretStatusBar:GetIcon()
	return self.icon_path
end

--- Set the icon's texture path of the bar, or remove it.
-- @param path the texture path or nil
-- @usage bar:SetIcon([[Interface\Icons\Ability_Parry]])
-- @usage bar:SetIcon(nil)
function SecretStatusBar:SetIcon(path)
	if DEBUG then
		expect(path, 'typeof', 'string;number;nil')
	end

	local old_icon_path = self.icon_path
	if not issecretvalue(path) and not issecretvalue(old_icon_path) and old_icon_path == path then
		return
	end

	self.icon_path = path
	if path then
		if not self.icon then
			self.icon = PitBull4.Controls.MakeTexture(self, "ARTWORK")
			self.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
			fix_orientation(self)
		end
		self.icon:SetTexture(path)
	else
		if self.icon then
			self.icon = self.icon:Delete()
			fix_orientation(self)
		end
	end
end

--- Return whether the icon is on the left or bottom.
-- @return true if the icon is on left or top, otherwise, false.
function SecretStatusBar:GetIconPosition()
	return self.icon_position
end

--- Set whether the icon is on the left or bottom.
-- @param value a boolean
function SecretStatusBar:SetIconPosition(value)
	if DEBUG then
		expect(value, 'typeof', 'boolean')
	end

	if value == self.icon_position then
		return
	end

	self.icon_position = value
	fix_orientation(self)
end

local function control_OnSizeChanged(self)
	fix_icon_size(self)
end

local function bar_OnSizeChanged(bar)
	fix_extra_sizes(bar:GetParent())
end

local function make_layer(control, level_offset)
	local bar = CreateFrame("StatusBar", nil, control)
	bar:SetFrameLevel(control:GetFrameLevel() + level_offset)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	bar:SetStatusBarTexture(DEFAULT_TEXTURE)
	return bar
end

--- Make a status bar that accepts secret values
-- @class function
-- @name PitBull4.Controls.MakeSecretStatusBar
-- @param parent frame the status bar is parented to
-- @usage local bar = PitBull4.Controls.MakeSecretStatusBar(someFrame)
-- @return a SecretStatusBar object
PitBull4.Controls.MakeNewControlType("SecretStatusBar", "Button", function(control)
	-- onCreate
	control:EnableMouse(false)
	-- Layers are deliberately NOT clipped to the control. The engine clamps
	-- each layer's value to [0, max] but not the sum, so a layer whose value
	-- starts where the one before it ended can run past the control's edge.
	-- That overflow is the point for VisualHeal, which anchors an overlay bar
	-- to the end of the health bar's fill and lets incoming heals extend
	-- beyond the health bar to show their full size. A control that instead
	-- needs its layers contained can call SetClipsChildren(true) on itself.

	-- the layers sit above the control's own textures (the background)
	-- and below its font strings and indicators, which the layout parents
	-- to the unit frame, not to the bar
	local bar = make_layer(control, 1)
	control.bar = bar
	control.fg = bar:GetStatusBarTexture()
	bar:SetScript("OnSizeChanged", bar_OnSizeChanged)

	local extra = make_layer(control, 1)
	control.extra = extra
	control.extra_fg = extra:GetStatusBarTexture()

	local extra2 = make_layer(control, 1)
	control.extra2 = extra2
	control.extra2_fg = extra2:GetStatusBarTexture()

	local bg = control:CreateTexture(nil, "BACKGROUND")
	control.bg = bg
	bg:SetTexture(DEFAULT_TEXTURE)

	for k, v in pairs(SecretStatusBar) do
		control[k] = v
	end
	control:SetScript("OnSizeChanged", control_OnSizeChanged)
end, function(control)
	-- onRetrieve
	control:SetMaxValue(1)
	control:SetTexture(nil)
	control:SetAtlas(nil)
	control:SetColor(1, 1, 1)
	control:SetNormalAlpha(1)
	control:SetBackgroundColor()
	control:SetBackgroundAlpha(nil)
	control:SetExtraColor()
	control:SetExtraAlpha(nil)
	control:SetExtra2Color()
	control:SetExtra2Alpha(nil)
	control:SetValue(1)
	control:SetExtraValue(0)
	control:SetExtra2Value(0)
	control:SetIcon(nil)
	control:SetIconPosition(true)
	fix_orientation(control)
end, function(control)
	-- onDelete
	control.timer_duration = nil
	control.layer_width, control.layer_height = nil, nil
	control.animated = false
	control.fade = false
	control.anim_duration = 0.5
	control.reverse = false
	control.deficit = false
	control.orientation = "HORIZONTAL"
end)
