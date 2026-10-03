-- Engine-driven auras, for clients that enforce secret values (WoW: Forever).
--
-- Aura data cannot be read at all while restrictions are active: the scan in
-- Update.lua is refused outright, not merely returned as secrets. The only way
-- to show an aura is to describe what to watch and let the engine draw it, so
-- under secrets this file replaces the module's :UpdateFrame and :ClearFrame
-- with an AuraContainer per unit frame per kind.
--
-- Each container holds two aura groups, the player's own auras and everyone
-- else's, split by the PLAYER component of the filter string. They have to be
-- separate groups rather than one sorted list because every difference between
-- "my" and "other" auras in the profile -- size, border colour, cooldown,
-- text -- is per-group styling applied once when a button is created, not per
-- aura. Own auras are laid out first, as the module's own sort does.
--
-- Rules for engine-placed buttons, from the Bufflehead port (its
-- doc/forever-support.md §11.3):
--   * setters only, never read a button's geometry back: the flow layout
--     positions buttons through secretwrap, and the secrecy spreads down the
--     anchor chain even out of combat and even after an explicit SetSize;
--   * nothing outside may anchor to a container that holds an aura group;
--   * no BackdropTemplate on a button, since SetBackdrop does arithmetic on
--     the width;
--   * buttons may be restyled out of combat but not while auras are secret.

local _G = _G
local PitBull4 = _G.PitBull4

if not PitBull4.has_secrets then
	return
end

local L = PitBull4.L
local PitBull4_Aura = PitBull4:GetModule("Aura")

local BORDER_TEXTURE = [[Interface\AddOns\PitBull4\Modules\Aura\border]]
local ZOOMED = { 0.07, 0.93, 0.07, 0.93 }
local CANCEL_BUTTONS = "RightButtonUp"

-- kind -> the filter string it watches
local KIND_FILTER = { buff = "HELPFUL", debuff = "HARMFUL" }
-- which profile section a (kind, who) pair is configured by
local CATEGORY = {
	buff = { mine = "my_buffs", other = "other_buffs" },
	debuff = { mine = "my_debuffs", other = "other_debuffs" },
}
-- "cast by me" is the PLAYER component of the filter string
local WHO_FILTER = { mine = "PLAYER", other = "!PLAYER" }

-- The module anchors the grid by a corner of the frame and a side to sit on,
-- and the corner of the grid that meets them is the opposite one, so the grid
-- lies outside the frame. Same table as Layout.lua's.
local CONTROL_POINT = {
	TOPLEFT_TOP        = "BOTTOMLEFT",
	TOPRIGHT_TOP       = "BOTTOMRIGHT",
	TOPLEFT_LEFT       = "TOPRIGHT",
	TOPRIGHT_RIGHT     = "TOPLEFT",
	BOTTOMLEFT_BOTTOM  = "TOPLEFT",
	BOTTOMRIGHT_BOTTOM = "TOPRIGHT",
	BOTTOMLEFT_LEFT    = "BOTTOMRIGHT",
	BOTTOMRIGHT_RIGHT  = "BOTTOMLEFT",
}

local DISPEL_STYLE = Enum.CustomAuraButtonDispelTypeTextureStyle

-- every container this module has built, so they can be restyled together
-- once combat ends
local containers = {}

-----------------------------------------------------------------------------
-- Profile values
-----------------------------------------------------------------------------

local function icon_size(db, kind, who)
	local layout_db = db.layout[kind]
	if who == "mine" then
		return layout_db.my_size or layout_db.size
	end
	return layout_db.size
end

-- How long a line of icons may be, in pixels: the flow layout wraps by extent,
-- not by a count. The module gives it as a percentage of the side the line
-- runs along or as a fixed size. The frame's own rect is plain; only a placed
-- button's is not.
local function line_extent(frame, db, kind, vertical)
	local layout_db = db.layout[kind]
	local side = vertical and frame:GetHeight() or frame:GetWidth()
	local width
	if layout_db.width_type == "percent" then
		width = side * (layout_db.width_percent or 1)
	else
		width = layout_db.width or side
	end
	-- a pixel of slack, so a line that divides exactly still fits
	return width + 1
end

-- The module's growth option names the direction the grid fills; the flow
-- layout wants an axis, the corner the first icon sits in, and a direction
-- for each axis.
local GROWTH = {
	right_down = { h = "Right", v = "Down", horizontal = true },
	right_up = { h = "Right", v = "Up", horizontal = true },
	left_down = { h = "Left", v = "Down", horizontal = true },
	left_up = { h = "Left", v = "Up", horizontal = true },
	down_right = { h = "Right", v = "Down", horizontal = false },
	down_left = { h = "Left", v = "Down", horizontal = false },
	up_right = { h = "Right", v = "Up", horizontal = false },
	up_left = { h = "Left", v = "Up", horizontal = false },
}

local function dispel_color_map()
	local colors = PitBull4_Aura.db.profile.global.colors
	colors = colors and colors.type
	if not colors then
		return nil
	end
	local map = {}
	for key, name in pairs({ Magic = "Magic", Curse = "Curse", Disease = "Disease", Poison = "Poison", None = "nil" }) do
		local color = colors[name]
		if color then
			map[key] = CreateColor(color[1], color[2], color[3], color[4] or 1)
		end
	end
	return map
end

-----------------------------------------------------------------------------
-- Buttons
-----------------------------------------------------------------------------

-- Build one aura button. Runs inside initializeFrame, which the engine calls
-- when it needs another button, possibly in combat, and which is the only
-- place a button may be given regions and anchors.
local function build_button(button, frame, kind, who)
	-- everything but the colour table is per layout
	local db = PitBull4_Aura:GetLayoutDB(frame)
	local colors = PitBull4_Aura.db.profile.global.colors
	local category = CATEGORY[kind][who]
	local size = icon_size(db, kind, who)
	-- which border settings apply depends on whether the unit is friendly,
	-- which is never secret
	local friendly = UnitIsFriend("player", frame.unit) and "friend" or "enemy"

	button:SetSize(size, size)

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints(button)
	if db.zoom_aura then
		icon:SetTexCoord(unpack(ZOOMED))
	end
	button:SetIcon(icon)
	button.pb4_icon = icon

	-- Border. Colouring by dispel type is the engine's to do, since the type
	-- cannot be read; colouring by caster is one colour for the whole group,
	-- because the group is defined by who cast its auras.
	local border_db = db.borders and db.borders[category]
	if border_db then
		local friend_db = border_db[friendly] or border_db
		if friend_db.enabled then
			local border = button:CreateTexture(nil, "OVERLAY")
			border:SetTexture(BORDER_TEXTURE)
			border:SetPoint("TOPLEFT", button, "TOPLEFT", -1, 1)
			border:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, -1)
			button.pb4_border = border

			local color_type = friend_db.color_type
			if color_type == "type" and button.AddDispelTypeTexture then
				button:AddDispelTypeTexture(border, {
					style = DISPEL_STYLE and DISPEL_STYLE.PreserveAsset,
					customDispelColorMap = dispel_color_map(),
					showWithoutDispelType = true,
				})
			elseif color_type == "custom" and friend_db.custom_color then
				border:SetVertexColor(unpack(friend_db.custom_color))
			else
				local caster = colors and colors.caster
				local color = caster and (caster[who == "mine" and "my" or "other"] or caster[who])
				if color then
					border:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
				end
			end
		end
	end

	local texts_db = db.texts and db.texts[category]

	-- The swipe, driven by the engine from the aura's duration. An aura's
	-- swipe is reversed: it grows as the aura runs out, where an ability's
	-- unwinds as the cooldown passes. The module's own aura control does the
	-- same (Controls.lua).
	local cooldown
	if db.cooldown and db.cooldown[category] then
		cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
		cooldown:SetAllPoints(button)
		cooldown:SetReverse(true)
		cooldown:SetHideCountdownNumbers(true)
		button:SetDurationCooldown(cooldown)
	end

	-- Text belongs above the swipe. Hanging it off the cooldown puts it there
	-- without reading a frame level back off a button whose geometry is not
	-- readable.
	local text_parent = cooldown or button

	local function make_text(text_db, default_anchor)
		local text = text_parent:CreateFontString(nil, "OVERLAY")
		local font, font_size = frame:GetFont(text_db.font, text_db.size)
		text:SetFont(font, font_size, "OUTLINE")
		local anchor = text_db.anchor or default_anchor
		text:SetPoint(anchor, button, anchor, text_db.offset_x or 0, text_db.offset_y or 0)
		local color = text_db.color
		if color then
			text:SetTextColor(color[1], color[2], color[3], color[4] or 1)
		end
		return text
	end

	-- Stack count. The engine writes it, and only when it is above one.
	if texts_db and texts_db.count then
		button:SetApplicationCount(make_text(texts_db.count, "BOTTOMRIGHT"))
	end

	if db.cooldown_text and db.cooldown_text[category] and texts_db and texts_db.cooldown then
		button:SetDurationText(make_text(texts_db.cooldown, "TOP"))
	end

	if db.click_through then
		button:EnableMouse(false)
	else
		button:SetTooltipAnchorPoint("ANCHOR_BOTTOMRIGHT", 0, 0)
		-- cancelling is only ever offered for the player's own buffs, and the
		-- engine does it without the addon seeing the aura
		if kind == "buff" and who == "mine" and frame.unit == "player" then
			button:SetCancelAuraButtons(CANCEL_BUTTONS)
		end
	end
end

-----------------------------------------------------------------------------
-- Containers
-----------------------------------------------------------------------------

local function group_options(frame, kind, who, db)
	return {
		maxFrameCount = kind == "buff" and db.max_buffs or db.max_debuffs,
		initializeFrame = function(button)
			build_button(button, frame, kind, who)
		end,
	}
end

local function create_container(frame, kind)
	local db = PitBull4_Aura:GetLayoutDB(frame)
	local container = CreateFrame("AuraContainer", nil, frame, "CustomAuraContainerTemplate")
	container.pb4_frame = frame
	container.pb4_kind = kind
	container:SetUnit(frame.unit)

	for who in pairs(WHO_FILTER) do
		container:AddAuraGroup(who, KIND_FILTER[kind], group_options(frame, kind, who, db))
	end

	containers[container] = true
	return container
end

-- Everything here is allowed in combat: it goes through the container's
-- secure inbound mixin rather than touching a placed button.
local function update_container(container, frame, kind)
	local db = PitBull4_Aura:GetLayoutDB(frame)
	local layout_db = db.layout[kind]
	local growth = GROWTH[layout_db.growth] or GROWTH.right_down
	local anchor = layout_db.anchor or "BOTTOMLEFT"
	local side = layout_db.side or "BOTTOM"
	-- the grid's own corner, which both pins it outside the frame and holds
	-- the first icon
	local point = CONTROL_POINT[anchor .. "_" .. side] or anchor

	container:ClearAllPoints()
	container:SetPoint(point, frame, anchor, layout_db.offset_x or 0, layout_db.offset_y or 0)
	container:SetFrameLevel(frame:GetFrameLevel() + (layout_db.frame_level or 9))

	container:SetFlowLayoutAxis(growth.horizontal and AnchorUtil.FlowLayoutAxis.Horizontal or AnchorUtil.FlowLayoutAxis.Vertical)
	container:SetFlowLayoutAnchorPoint(point)
	container:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection[growth.h], AnchorUtil.FlowDirection[growth.v])

	-- these are globals from Blizzard_AuraContainer, looked up when needed
	local methods, directions = _G.AuraContainerSortMethod, _G.AuraContainerSortDirection
	local sort_method = layout_db.sort and methods.Name or methods.AuraInstanceIDOnly
	local sort_direction = layout_db.reverse and directions.Reverse or directions.Normal
	local max_frames = kind == "buff" and db.max_buffs or db.max_debuffs

	local spacing, line_spacing = layout_db.col_spacing or 0, layout_db.row_spacing or 0
	if not growth.horizontal then
		spacing, line_spacing = line_spacing, spacing
	end

	for who, who_filter in pairs(WHO_FILTER) do
		local size = icon_size(db, kind, who)
		container:SetAuraGroupFilterString(who, ("%s|%s"):format(KIND_FILTER[kind], who_filter))
		container:SetAuraGroupLayout(who, {
			elementSpacing = spacing,
			lineSpacing = line_spacing,
			groupSpacing = spacing,
			groupLineSpacing = line_spacing,
			elementWidth = size,
			elementHeight = size,
			-- the player's own auras first, as the module's own sort does
			layoutIndex = who == "mine" and 1 or 2,
		})
		container:SetAuraGroupMaxFrameCount(who, max_frames)
		container:SetAuraGroupSortMethod(who, sort_method, sort_direction)
	end

	container:SetFlowLayoutMaximumLineSize(line_extent(frame, db, kind, not growth.horizontal))
	container:Show()

	-- A container watches UNIT_AURA for its own unit, but nothing tells it
	-- that the unit behind an unchanged token has changed: SetUnit returns
	-- early when the token is the same, and changing target fires no aura
	-- event. Without this a frame keeps the previous unit's auras until that
	-- unit's auras happen to change, which for a long buff is never.
	container:UpdateAllAuras()
end

-----------------------------------------------------------------------------
-- Highlight
-----------------------------------------------------------------------------
-- The module colours the whole frame when an aura passes one of the layout's
-- highlight filters. The filters cannot run here, but what the highlight
-- needs is presence without values, and that is what an aura slot gives: the
-- engine assigns the preferred matching aura to the slot's frame and shows
-- it, or hides it when nothing matches. The slot's frame is laid over the
-- unit frame carrying the highlight texture, coloured by dispel type through
-- the same mechanism as the icon borders.
--
-- Only the built-in highlight filters that reduce to a side of the player
-- and a set of dispel types can be expressed:
--   !H dispellable by me debuffs   friend, HARMFUL, what the class can dispel
--   !G dispellable debuffs         friend, HARMFUL, every dispel type
--   !L purgeable by me buffs       enemy, HELPFUL, what the class can purge
--   !K purgeable buffs             enemy, HELPFUL, Magic and Enrage
-- !I and !J match aura names from a user list and a custom filter can be
-- anything; the engine can do neither, so those are skipped.
--
-- A side gets one slot. Each dispel type is claimed by the first filter in
-- the list that covers it, which decides whether it is coloured by type or
-- with that filter's custom colour. When a unit carries auras of several
-- claimed types the engine's default order picks the one shown, where the
-- module would have gone by filter order.

local HIGHLIGHT_TEXTURE = {
	border = [[Interface\AddOns\PitBull4\Modules\Aura\HighlightBorder]],
	thinborder = [[Interface\AddOns\PitBull4\Modules\Aura\HighlightThinBorder]],
	normal = [[Interface\AddOns\PitBull4\Modules\Aura\HighlightNormal]],
}

local DISPELLABLE_TYPES = { Magic = true, Curse = true, Disease = true, Poison = true, Enrage = true }
local PURGEABLE_TYPES = { Magic = true, Enrage = true }

local HIGHLIGHT_FILTERS = {
	["!H"] = { side = "friend", filter = "HARMFUL", types = function() return PitBull4_Aura.can_dispel.player end },
	["!G"] = { side = "friend", filter = "HARMFUL", types = DISPELLABLE_TYPES },
	["!L"] = { side = "enemy", filter = "HELPFUL", types = function() return PitBull4_Aura.can_purge.player end },
	["!K"] = { side = "enemy", filter = "HELPFUL", types = PURGEABLE_TYPES },
}

-- The engine reports an enrage effect with an empty dispel name; the module
-- calls it Enrage, and the type colours are keyed that way.
local ENGINE_TYPE = { Enrage = "" }

-- What each side watches for a layout: the filter string, the dispel types
-- to admit and a colour for each. nil when no filter can be expressed.
local function highlight_sides(db)
	local type_colors = PitBull4_Aura.db.profile.global.colors.type
	local filters = db.highlight_filters
	local sides
	for id = 1, #filters do
		local spec = HIGHLIGHT_FILTERS[filters[id]]
		if spec then
			local types = spec.types
			if type(types) == "function" then
				types = types()
			end
			local custom = not db.highlight_filters_color_by_type[id] and db.highlight_filters_custom_color[id]
			for name, enabled in pairs(types or {}) do
				if enabled then
					sides = sides or {}
					local side = sides[spec.side]
					if not side then
						side = { filter = spec.filter, types = {}, colors = {} }
						sides[spec.side] = side
					end
					if not side.types[name] then
						local color = custom or type_colors[name] or type_colors["nil"]
						color = CreateColor(color[1], color[2], color[3], color[4] or 1)
						side.types[name] = true
						side.colors[name] = color
						local engine_name = ENGINE_TYPE[name]
						if engine_name then
							side.types[engine_name] = true
							side.colors[engine_name] = color
						end
					end
				end
			end
		end
	end
	return sides
end

-- Slot frames cannot be restyled once the engine owns them, so a container
-- is built for one configuration and replaced when that changes.
local function highlight_key(db, sides)
	local parts = { db.highlight_style or "normal" }
	for _, side_name in ipairs({ "friend", "enemy" }) do
		local side = sides[side_name]
		if side then
			parts[#parts + 1] = side_name .. ":" .. side.filter
			local names = {}
			for name in pairs(side.types) do
				names[#names + 1] = name
			end
			table.sort(names)
			for _, name in ipairs(names) do
				parts[#parts + 1] = name .. "=" .. side.colors[name]:GenerateHexColor()
			end
		end
	end
	return table.concat(parts, "/")
end

-- Runs inside initializeFrame, like build_button.
local function build_highlight(button, frame, style, colors)
	-- the unit frame beneath takes the clicks
	button:EnableMouse(false)
	button:SetAllPoints(frame)

	local texture = button:CreateTexture(nil, "OVERLAY")
	texture:SetTexture(HIGHLIGHT_TEXTURE[style] or HIGHLIGHT_TEXTURE.normal)
	texture:SetBlendMode("ADD")
	texture:SetAlpha(0.75)
	texture:SetAllPoints(button)
	button:AddDispelTypeTexture(texture, {
		style = DISPEL_STYLE and DISPEL_STYLE.PreserveAsset,
		customDispelColorMap = colors,
		showWhenHarmful = true,
		showWhenHelpful = true,
		showWithoutDispelType = true,
	})
end

local function create_highlight(frame, db, sides, key)
	-- parented to the overlay so it draws above the bars, as the module's
	-- own highlight texture does; the slot frames anchor to the unit frame,
	-- the container's own rect is irrelevant
	local container = CreateFrame("AuraContainer", nil, frame.overlay, "CustomAuraContainerTemplate")
	container.pb4_key = key
	container.pb4_sides = sides
	container:SetPoint("TOPLEFT", frame, "TOPLEFT")
	container:SetUnit(frame.unit)

	local style = db.highlight_style
	for side_name, side in pairs(sides) do
		container:AddAuraSlot(side_name, side.filter, {
			candidateFilters = { includeDispelTypes = side.types },
			initializeFrame = function(button)
				build_highlight(button, frame, style, side.colors)
			end,
		})
	end
	return container
end

local function update_highlight(frame, db)
	local container = frame.aura_highlight_container
	local sides = db.highlight and highlight_sides(db)
	local key = sides and highlight_key(db, sides)
	if container and container.pb4_key ~= key then
		container:Hide()
		container = nil
	end
	if not key then
		return
	end
	if not container then
		container = create_highlight(frame, db, sides, key)
		frame.aura_highlight_container = container
	end

	container:SetUnit(frame.unit)
	-- only the side the unit is on watches; whether it is a friend is never
	-- secret
	local friend = UnitIsFriend("player", frame.unit) and true or false
	if container.pb4_friend ~= friend then
		container.pb4_friend = friend
		for side_name in pairs(container.pb4_sides) do
			container:SetAuraSlotEnabled(side_name, (side_name == "friend") == friend)
		end
	end
	container:Show()
	container:UpdateAllAuras()
end

-- Learning a dispel changes what the friend slot admits.
local talent_update = PitBull4_Aura.PLAYER_TALENT_UPDATE
function PitBull4_Aura:PLAYER_TALENT_UPDATE(...)
	talent_update(self, ...)
	self:UpdateAll()
end

-----------------------------------------------------------------------------
-- Module contract
-----------------------------------------------------------------------------

local function each_kind(frame, func)
	local db = PitBull4_Aura:GetLayoutDB(frame)
	local wanted = { buff = db.enabled_buffs, debuff = db.enabled_debuffs }
	for kind in pairs(KIND_FILTER) do
		func(kind, wanted[kind])
	end
end

function PitBull4_Aura:UpdateFrame(frame)
	if not frame.unit or not frame.guid then
		return self:ClearFrame(frame)
	end

	local frame_containers = frame.aura_containers
	each_kind(frame, function(kind, wanted)
		local container = frame_containers and frame_containers[kind]
		if not wanted then
			if container then
				container:Hide()
			end
			return
		end
		if not container then
			container = create_container(frame, kind)
			frame_containers = frame_containers or {}
			frame_containers[kind] = container
		end
		container:SetUnit(frame.unit)
		update_container(container, frame, kind)
	end)
	frame.aura_containers = frame_containers

	update_highlight(frame, PitBull4_Aura:GetLayoutDB(frame))
end

function PitBull4_Aura:ClearFrame(frame)
	local highlight = frame.aura_highlight_container
	if highlight then
		highlight:Hide()
	end
	local frame_containers = frame.aura_containers
	if not frame_containers then
		return
	end
	for _, container in pairs(frame_containers) do
		container:Hide()
	end
end

PitBull4_Aura.OnHide = PitBull4_Aura.ClearFrame

-- The module registers this event and its own handler reads aura data, which
-- is impossible here. Each container registers UNIT_AURA for its own unit and
-- refreshes itself, so there is nothing to do.
function PitBull4_Aura:UNIT_AURA(event, unit)
end

-- The module's other entry points read aura values, which is impossible here.
function PitBull4_Aura:UpdateAuras(frame)
end
function PitBull4_Aura:ClearAuras(frame)
end
function PitBull4_Aura:LayoutAuras(frame)
end
function PitBull4_Aura:UpdateSkin(frame)
end
function PitBull4_Aura:UpdateWeaponEnchants(force)
end
function PitBull4_Aura:UpdateCooldownTexts(elapsed)
	return nil
end
function PitBull4_Aura:OnUpdate()
end
