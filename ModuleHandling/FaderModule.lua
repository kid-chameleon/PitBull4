local _G = _G
local PitBull4 = _G.PitBull4

local DEBUG = PitBull4.DEBUG
local expect = PitBull4.expect

-- Constants -----------------------------------------------------------------
-- how long in seconds it would take to go from 100% to 0% opacity (or the other way around)
local FADE_TIME = 0.5

-- how many opacity points can change in one second
local OPACITY_POINTS_PER_SECOND = 1 / FADE_TIME
------------------------------------------------------------------------------

local FaderModule = PitBull4:NewModuleType("fader", {
	enabled = true,
})

-- a dictionary of module to a dictionary of frame to final opacity level
local module_to_frame_to_opacity = {}
local module_to_frame_to_priority = {}

-- a set of frames that should be checked for opacity changes
local changing_frames = {}

--- Return how opaque a frame will be once animation completes.
-- @param frame the Unit Frame to check.
-- @usage local opacity = PitBull4:GetFinalFrameOpacity(frame)
-- @return a number within [0, 1]
function PitBull4:GetFinalFrameOpacity(frame)
	if DEBUG then
		expect(frame, 'typeof', 'frame')
	end

	local layout_db = frame.layout_db
	local unit = frame.unit

	local low = layout_db and layout_db.opacity_max or 1
	local max_priority
	for module, frame_to_opacity in pairs(module_to_frame_to_opacity) do
		local frame_to_priority = module_to_frame_to_priority[module]
		local priority = frame_to_priority[frame]
		local opacity = frame_to_opacity[frame]
		if priority and (not max_priority or priority > max_priority) then
			low = layout_db and layout_db.opacity_max or 1
			max_priority = priority
		end
		if opacity and opacity < low and (not priority or not max_priority or priority >= max_priority) then
			low = opacity
		end
	end
	return low
end

-- Secret values (WoW: Forever): a fader may have to derive its opacity from
-- something unreadable, such as whether a unit is in range or how much health
-- it has left. The engine can pick or compute the opacity, but the result
-- cannot be compared, so such a frame is set directly with no smoothing and
-- the pipeline keeps its own copy of what it set: once a secret alpha has
-- been applied, frame:GetAlpha() returns a secret for good.
local has_secrets = PitBull4.has_secrets
local issecretvalue = _G.issecretvalue or function() return false end

local frame_to_alpha = {}

--- Set a frame's opacity, remembering it so it can be read back.
-- @param frame the Unit Frame
-- @param alpha the opacity, which may be a secret
-- @usage PitBull4.ApplyFrameAlpha(frame, 0.5)
local function apply_alpha(frame, alpha)
	frame_to_alpha[frame] = alpha
	frame:SetAlpha(alpha)
	-- XXX Quick fix for model widgets not inheriting alpha https://github.com/Stanzilla/WoWUIBugs/issues/295
	if frame.Portrait and frame.Portrait.model then
		frame.Portrait.model:SetAlpha(alpha)
	end
end
PitBull4.ApplyFrameAlpha = apply_alpha

-- The frame's current opacity, or nil when it cannot be read.
local function current_alpha(frame)
	local alpha = frame_to_alpha[frame]
	if alpha == nil then
		alpha = frame:GetAlpha()
	end
	if issecretvalue(alpha) then
		return nil
	end
	return alpha
end

--- A fader module may declare :GetSecretAlpha(frame, alpha), which is called
-- only where secret values are enforced. It is given the opacity the ordinary
-- faders agreed on and returns the one to use instead, which may be a secret
-- from C_CurveUtil.EvaluateColorValueFromBoolean or from a curve the engine
-- evaluates against a unit's health or power. Modules are called in turn and
-- each is given the previous one's result, so several can apply, but one that
-- cannot fold an incoming secret into its own calculation will override it.
local function apply_secret_faders(frame, alpha)
	for _, module in PitBull4:IterateModulesOfType("fader") do
		if module.GetSecretAlpha then
			local layout_db = module:GetLayoutDB(frame)
			if layout_db and layout_db.enabled then
				local new_alpha = module:GetSecretAlpha(frame, alpha)
				if new_alpha ~= nil then
					alpha = new_alpha
				end
			end
		end
	end
	return alpha
end

local timerFrame = CreateFrame("Frame")
timerFrame:SetScript("OnUpdate", function(self, elapsed)
	local opacity_delta = elapsed * OPACITY_POINTS_PER_SECOND
	for frame in pairs(changing_frames) do
		if not frame:IsVisible() then
			changing_frames[frame] = nil
		else
			local final_opacity = PitBull4:GetFinalFrameOpacity(frame)
			if has_secrets then
				final_opacity = apply_secret_faders(frame, final_opacity)
			end
			local current_opacity = current_alpha(frame)

			if current_opacity == nil or issecretvalue(final_opacity) then
				apply_alpha(frame, final_opacity)
				changing_frames[frame] = nil
			elseif final_opacity ~= current_opacity then
				local result_opacity
				if not frame.layout_db.opacity_smooth then
					result_opacity = final_opacity
				elseif final_opacity < current_opacity then
					result_opacity = current_opacity - opacity_delta
					if result_opacity < final_opacity then
						result_opacity = final_opacity
					end
				else
					result_opacity = current_opacity + opacity_delta
					if result_opacity > final_opacity then
						result_opacity = final_opacity
					end
				end

				apply_alpha(frame, result_opacity)
				if result_opacity == final_opacity then
					changing_frames[frame] = nil
				end
			else
				changing_frames[frame] = nil
			end
		end
	end
	if not next(changing_frames) then
		timerFrame:Hide()
	end
end)
timerFrame:Hide()

function PitBull4:RecheckAllOpacities()
	timerFrame:Show()
	for frame in PitBull4:IterateFrames() do
		changing_frames[frame] = true
	end
end

--- Handle the frame being hidden
-- @param frame the Unit Frame hidden.
-- @usage MyModule:OnHide(frame)
function FaderModule:OnHide(frame)
	if DEBUG then
		expect(frame, 'typeof', 'frame')
	end

	-- No point in removing the opacity change, it'll be set anyway
	-- when the frame is shown.
	return
end

--- Remove any opacity value for this module.
-- @param frame the Unit Frame to clear
-- @usage MyModule:ClearFrame(frame)
-- @return false, since :UpdateLayout isn't required for this type of module
function FaderModule:ClearFrame(frame)
	if DEBUG then
		expect(frame, 'typeof', 'frame')
	end

	local frame_to_opacity = module_to_frame_to_opacity[self]
	local frame_to_priority = module_to_frame_to_priority[self]
	if not frame_to_opacity and not frame_to_priority then
		return false
	end

	local update = false

	if frame_to_opacity[frame] then
		frame_to_opacity[frame] = nil
		update = true
	end

	if frame_to_priority[frame] then
		frame_to_priority[frame] = nil
		update = true
	end

	if update then
		changing_frames[frame] = true
		timerFrame:Show()
	end

	return false
end

--- Call the :GetOpacity function on the fader module regarding the given frame.
-- The lowest opacity from the highest priority module will be used on the frame.
-- @param the module
-- @param frame the frame to get the opacity of
-- @usage local opacity, priority = call_opacity_function(MyModule, someFrame)
-- @return opacity nil or a number within [0, 1]
-- @return priority nil (treated as zero) or a number
local function call_opacity_function(self, frame)
	if not self.GetOpacity then
		return nil, nil
	end

	local layout_db = frame.layout_db

	local opacity_min = layout_db.opacity_min
	local opacity_max = layout_db.opacity_max

	local value, priority
	-- Extra frame.unit test here is a workaround for the same root issue
	-- as we have in BarModules.  See ticket 475.
	if frame.guid and frame.unit then
		value, priority = self:GetOpacity(frame)
	end
	if not value or value >= opacity_max or value ~= value then
		return opacity_max, priority
	elseif value < opacity_min then
		return opacity_min, priority
	else
		return value, priority
	end
end

--- Update the opacity value for the current module
-- @param frame the Unit Frame to update
-- @usage MyModule:UpdateStatusBar(frame)
-- @return false, since :UpdateLayout isn't required for this type of module
function FaderModule:UpdateFrame(frame)
	if DEBUG then
		expect(frame, 'typeof', 'frame')
	end

	local frame_to_opacity = module_to_frame_to_opacity[self]
	if not frame_to_opacity then
		frame_to_opacity = {}
		module_to_frame_to_opacity[self] = frame_to_opacity
	end
	local frame_to_priority = module_to_frame_to_priority[self]
	if not frame_to_priority then
		frame_to_priority = {}
		module_to_frame_to_priority[self] = frame_to_priority
	end

	-- a module with only :GetSecretAlpha contributes no comparable opacity,
	-- so the frame has to be rechecked whenever it is updated
	local recheck = has_secrets and self.GetSecretAlpha and frame:IsVisible()

	local opacity, priority = call_opacity_function(self, frame)
	if not opacity then
		local changed = self:ClearFrame(frame)
		if recheck then
			changing_frames[frame] = true
			timerFrame:Show()
		end
		return changed
	end
	if not priority then
		priority = 0
	end

	if recheck or frame_to_opacity[frame] ~= opacity or frame_to_priority[frame] ~= priority then
		frame_to_opacity[frame] = opacity
		frame_to_priority[frame] = priority
		changing_frames[frame] = true
		timerFrame:Show()
	end

	return false
end
