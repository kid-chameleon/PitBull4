
local PitBull4 = _G.PitBull4
local L = PitBull4.L

local PitBull4_RaidTargetIcon = PitBull4:NewModule("RaidTargetIcon")

-- Secret values (WoW: Forever): GetRaidTargetIndex always returns a secret,
-- which cannot pick a texture by name or index a table, but can pick a cell
-- out of the 4x4 sheet of all eight markers. Choosing which markers to show
-- is therefore not possible, and those options are disabled.
local has_secrets = PitBull4.has_secrets
local SHEET = [[Interface\TargetingFrame\UI-RaidTargetingIcons]]

PitBull4_RaidTargetIcon:SetModuleType("indicator")
PitBull4_RaidTargetIcon:SetName(L["Raid target icon"])
PitBull4_RaidTargetIcon:SetDescription(L["Show an icon on the unit frame based on which Raid Target it is."])
PitBull4_RaidTargetIcon:SetDefaults({
	attach_to = "root",
	location = "edge_top",
	position = 1,
	[1] = true, -- Star
	[2] = true, -- Circle
	[3] = true, -- Diamond
	[4] = true, -- Triangle
	[5] = true, -- Moon
	[6] = true, -- Square
	[7] = true, -- Cross
	[8] = true, -- Skull
})

function PitBull4_RaidTargetIcon:OnEnable()
	self:RegisterEvent("RAID_TARGET_UPDATE")
	self:RegisterEvent("GROUP_ROSTER_UPDATE")
end

function PitBull4_RaidTargetIcon:GetTexture(frame)
	local unit = frame.unit

	local index = GetRaidTargetIndex(unit)

	if not index then
		return nil
	end

	if has_secrets then
		-- the marker is picked out of the sheet by :GetSpriteSheetCell
		return SHEET
	end

	-- Disabled
	if not self:GetLayoutDB(frame)[index] then
		return nil
	end

	return [[Interface\TargetingFrame\UI-RaidTargetingIcon_]] .. index
end

if has_secrets then
	--- Return the cell of the marker sheet to show, with its dimensions.
	-- @param frame the unit frame
	-- @return the cell index, which may be a secret, or nil
	-- @return the number of rows in the sheet
	-- @return the number of columns in the sheet
	function PitBull4_RaidTargetIcon:GetSpriteSheetCell(frame, texture)
		-- In config mode the frame has no unit and the texture came from
		-- :GetExampleTexture, which is a single marker rather than the sheet,
		-- so it is placed with tex coords like every other indicator.
		if texture ~= SHEET or not frame.unit then
			return nil
		end
		local index = GetRaidTargetIndex(frame.unit)
		if not index then
			return nil
		end
		return index, 4, 4
	end
end

function PitBull4_RaidTargetIcon:GetExampleTexture(frame)
	local unit = frame.unit or frame:GetName()

	local index = unit:match(".*(%d+)")
	if index then
		index = index+0
	else
		index = 0
	end
	index = index + #unit + unit:byte()

	index = (index % 8) + 1

	-- Disabled
	if not self:GetLayoutDB(frame)[index] then
		return nil
	end

	return [[Interface\TargetingFrame\UI-RaidTargetingIcon_]] .. index
end

function PitBull4_RaidTargetIcon:RAID_TARGET_UPDATE()
	self:UpdateAll()
end

function PitBull4_RaidTargetIcon:GROUP_ROSTER_UPDATE()
	self:ScheduleTimer("UpdateAll", 0.1)
end

PitBull4_RaidTargetIcon:SetLayoutOptionsFunction(function(self)
	local function get(info)
		return PitBull4.Options.GetLayoutDB(self)[info[#info]+0]
	end

	local function set(info,value)
		PitBull4.Options.GetLayoutDB(self)[info[#info]+0] = value

		PitBull4.Options.UpdateFrames()
	end

	-- which marker a unit carries is unreadable, so all of them show
	local function disabled()
		return has_secrets
	end

	return '1',{
		type = 'toggle',
		name = [[|TInterface\TargetingFrame\UI-RaidTargetingIcons:0:0:0:0:256:256:0:64:0:64|t |cfffff200]]..RAID_TARGET_1,
		desc = L["Show this raid target icon for this layout."],
		get = get,
		set = set,
		disabled = disabled,
	}, '2', {
		type = 'toggle',
		name = [[|TInterface\TargetingFrame\UI-RaidTargetingIcons:0:0:0:0:256:256:64:128:0:64|t |cfff99100]]..RAID_TARGET_2,
		desc = L["Show this raid target icon for this layout."],
		get = get,
		set = set,
		disabled = disabled,
	}, '3', {
		type = 'toggle',
		name = [[|TInterface\TargetingFrame\UI-RaidTargetingIcons:0:0:0:0:256:256:128:192:0:64|t |cffd338e5]]..RAID_TARGET_3,
		desc = L["Show this raid target icon for this layout."],
		get = get,
		set = set,
		disabled = disabled,
	}, '4', {
		type = 'toggle',
		name = [[|TInterface\TargetingFrame\UI-RaidTargetingIcons:0:0:0:0:256:256:192:256:0:64|t |cff0af200]]..RAID_TARGET_4,
		desc = L["Show this raid target icon for this layout."],
		get = get,
		set = set,
		disabled = disabled,
	}, '5', {
		type = 'toggle',
		name = [[|TInterface\TargetingFrame\UI-RaidTargetingIcons:0:0:0:0:256:256:0:64:64:128|t |cffb2d1df]]..RAID_TARGET_5,
		desc = L["Show this raid target icon for this layout."],
		get = get,
		set = set,
		disabled = disabled,
	}, '6', {
		type = 'toggle',
		name = [[|TInterface\TargetingFrame\UI-RaidTargetingIcons:0:0:0:0:256:256:64:128:64:128|t |cff00b5ff]]..RAID_TARGET_6,
		desc = L["Show this raid target icon for this layout."],
		get = get,
		set = set,
		disabled = disabled,
	}, '7', {
		type = 'toggle',
		name = [[|TInterface\TargetingFrame\UI-RaidTargetingIcons:0:0:0:0:256:256:128:192:64:128|t |cffff3d2a]]..RAID_TARGET_7,
		desc = L["Show this raid target icon for this layout."],
		get = get,
		set = set,
		disabled = disabled,
	}, '8', {
		type = 'toggle',
		name = [[|TInterface\TargetingFrame\UI-RaidTargetingIcons:0:0:0:0:256:256:192:256:64:128|t |cfff9f9f9]]..RAID_TARGET_8,
		desc = L["Show this raid target icon for this layout."],
		get = get,
		set = set,
		disabled = disabled,
	}
end)
