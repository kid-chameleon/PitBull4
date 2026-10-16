
local PitBull4 = _G.PitBull4

-- A shaded segment laid over the end of a power bar's fill, showing the part
-- of the current power that the spell being cast will consume, as the default
-- player frame does.
--
-- The segment is a StatusBar as long as the power bar, anchored by one edge
-- to the boundary between current and missing power and filling away from it
-- into the current power. The engine sizes the fill from the cost and the
-- bar's maximum, so neither is read in Lua; that is what lets it work when the
-- maximum is a secret value (WoW: Forever). The control itself is a clipping
-- frame over the power bar, so a cost larger than the current power does not
-- draw past the bar's start.

local DEFAULT_TEXTURE = [[Interface\Buttons\WHITE8X8]]

local issecretvalue = _G.issecretvalue or function() return false end

-- SecretStatusBar draws deficit mode with the fill as the current power at
-- the far end of the bar; BetterStatusBar draws the fill as the deficit at
-- the start. BarModules picks the control by this flag.
local fill_is_current_in_deficit = PitBull4.has_secrets

-- the two sides and the start and end edges of a bar, by orientation
local EDGES = {
	HORIZONTAL = { "TOP", "BOTTOM", "LEFT", "RIGHT" },
	VERTICAL = { "LEFT", "RIGHT", "BOTTOM", "TOP" },
}

local PowerCostBar = {}

--- Lay the segment over the given power bar, following its orientation,
-- reverse and deficit settings. Call again whenever the bar may have changed.
-- @param power_bar the bar control (BetterStatusBar or SecretStatusBar)
-- @usage cost_bar:Attach(frame.PowerBar)
function PowerCostBar:Attach(power_bar)
	local orientation = power_bar:GetOrientation()
	local reverse = power_bar:GetReverse()
	local deficit = power_bar:GetDeficit()
	local side_a, side_b, edge_start, edge_end = unpack(EDGES[orientation])
	if reverse then
		edge_start, edge_end = edge_end, edge_start
	end

	self:ClearAllPoints()
	self:SetAllPoints(power_bar)
	self:SetFrameLevel(power_bar:GetFrameLevel() + 2)

	local bar = self.bar
	bar:ClearAllPoints()
	bar:SetOrientation(orientation)
	bar:SetPoint(side_a, power_bar, side_a)
	bar:SetPoint(side_b, power_bar, side_b)
	if orientation == "HORIZONTAL" then
		bar:SetWidth(power_bar:GetWidth())
	else
		bar:SetHeight(power_bar:GetHeight())
	end

	-- The fill texture is the current power growing from the start edge, so
	-- the boundary is its end and the segment grows back from there. In
	-- deficit mode the current power lies on the far side of the boundary:
	-- past the end of a fill that draws the deficit, or before the start of
	-- a fill that draws the current power from the far end.
	local fg = power_bar.fg
	if not deficit then
		bar:SetPoint(edge_end, fg, edge_end)
		bar:SetReverseFill(not reverse)
	elseif fill_is_current_in_deficit then
		bar:SetPoint(edge_start, fg, edge_start)
		bar:SetReverseFill(reverse)
	else
		bar:SetPoint(edge_start, fg, edge_end)
		bar:SetReverseFill(reverse)
	end
end

--- Take the power bar's texture, and a shade halfway between its fill and
-- background colours.
-- @param power_bar the bar control
-- @usage cost_bar:SetAppearance(frame.PowerBar)
function PowerCostBar:SetAppearance(power_bar)
	local bar = self.bar
	bar:SetStatusBarTexture(power_bar:GetTexture() or DEFAULT_TEXTURE)
	local atlas = power_bar:GetAtlas()
	if atlas then
		bar:GetStatusBarTexture():SetAtlas(atlas)
	end

	local r, g, b = power_bar:GetColor()
	local br, bg, bb = power_bar:GetBackgroundColor()
	if issecretvalue(r) or issecretvalue(g) or issecretvalue(b) or issecretvalue(br) or issecretvalue(bg) or issecretvalue(bb) then
		r, g, b = 0.5, 0.5, 0.5
	else
		r, g, b = (r + br) / 2, (g + bg) / 2, (b + bb) / 2
	end
	bar:SetStatusBarColor(r, g, b, power_bar:GetNormalAlpha() or 1)
end

--- Set the cost to show, out of the bar's maximum. The maximum may be a
-- secret value.
-- @param cost the cost in power
-- @param max the maximum power
-- @usage cost_bar:SetCost(cost, UnitPowerMax("player"))
function PowerCostBar:SetCost(cost, max)
	local bar = self.bar
	bar:SetMinMaxValues(0, max)
	bar:SetValue(cost)
end

PitBull4.Controls.MakeNewControlType("PowerCostBar", "Frame", function(control)
	-- onCreate
	control:SetClipsChildren(true)
	local bar = CreateFrame("StatusBar", nil, control)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	bar:SetStatusBarTexture(DEFAULT_TEXTURE)
	control.bar = bar

	for k, v in pairs(PowerCostBar) do
		control[k] = v
	end
end, function(control)
	-- onRetrieve
	control.bar:SetMinMaxValues(0, 1)
	control.bar:SetValue(0)
end, function(control)
	-- onDelete
	control.bar:ClearAllPoints()
end)
