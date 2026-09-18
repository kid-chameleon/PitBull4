-- Tag texts: a text provider that never touches a value in Lua.
--
-- A text is a string of literal text and [tags], e.g. "[name] [hp(both)]".
-- It is compiled once into a format string that contains only "%s"
-- placeholders plus one function per tag. On every update the tag functions
-- fetch their (possibly secret) values and the engine substitutes them
-- through FontString:SetFormattedText, which accepts secrets. Nothing is
-- compared, added or concatenated here, so the module works on clients
-- that enforce secret values (WoW: Forever) as well as everywhere else.
--
-- Tags may take arguments, "[hp(percent)]", and modifiers that wrap the
-- result, "[name:classcolor]", "[missinghp:paren]". A modifier applied to
-- an empty result stays empty, so "[afkdnd:angle]" shows nothing unless the
-- unit is away. The tag library lives in Tags.lua.

local _G = _G
local PitBull4 = _G.PitBull4
local L = PitBull4.L

local DEBUG = PitBull4.DEBUG
local expect = PitBull4.expect

local PitBull4_TagTexts = PitBull4:NewModule("TagTexts")

PitBull4_TagTexts:SetModuleType("text_provider")
PitBull4_TagTexts:SetName(L["Tag texts"])
PitBull4_TagTexts:SetDescription(L["Text provider using tags such as [name] and [hp]. Works with secret values."])
PitBull4_TagTexts:SetDefaults({
	elements = {
		['**'] = {
			size = 1,
			attach_to = "root",
			location = "edge_top_left",
			position = 1,
			exists = false,
			code = "",
			enabled = true,
		},
	},
	first = true,
})

-- font_string -> true for every font string we drive
local texts = {}
-- event -> { font_string = true }
local event_cache = {}
-- code -> compiled text
local compiled_cache = {}
-- tag name (lower case) -> { fn = function(unit, frame, ...), events = { EVENT = "unit" | "all" } }
local tags = {}
-- modifier name (lower case) -> function(value, unit, frame, ...)
local modifiers = {}
-- errors already reported, so a broken text does not spam
local reported = {}

PitBull4_TagTexts.tags = tags
PitBull4_TagTexts.modifiers = modifiers

--- Register a tag.
-- @param name the tag name, matched case-insensitively
-- @param events a dictionary of event -> "unit" (update frames showing the event's unit) or "all" (update every text using the tag)
-- @param fn function(unit, frame, ...) returning a string, a number or nil; the value may be a secret
-- @param help a one-line description for the options
-- @usage PitBull4_TagTexts:RegisterTag("level", { UNIT_LEVEL = "all" }, function(unit) return UnitLevel(unit) end, "unit level")
function PitBull4_TagTexts:RegisterTag(name, events, fn, help)
	if DEBUG then
		expect(name, 'typeof', 'string')
		expect(events, 'typeof', 'table')
		expect(fn, 'typeof', 'function')
	end
	tags[name:lower()] = { name = name, events = events, fn = fn, help = help }
end

--- Register a modifier.
-- @param name the modifier name, matched case-insensitively
-- @param fn function(value, unit, frame, ...) returning the wrapped value; value may be a secret and must only be passed through secret-safe calls
-- @param help a one-line description for the options
function PitBull4_TagTexts:RegisterModifier(name, fn, help)
	if DEBUG then
		expect(name, 'typeof', 'string')
		expect(fn, 'typeof', 'function')
	end
	modifiers[name:lower()] = { name = name, fn = fn, help = help }
end

-----------------------------------------------------------------------------
-- Compiler
-----------------------------------------------------------------------------

local function parse_args(str)
	local args = {}
	if not str or str == "" then
		return args
	end
	for arg in (str .. ","):gmatch("([^,]*),") do
		local quoted = arg:match("^%s*'(.*)'%s*$") or arg:match('^%s*"(.*)"%s*$')
		if quoted then
			arg = quoted
		end
		args[#args + 1] = tonumber(arg) or arg
	end
	return args
end

local function report(key, message)
	if reported[key] then
		return
	end
	reported[key] = true
	geterrorhandler()(message)
end

-- Build the function for one [tag] body. Returns nil if the tag is unknown.
local function build_tag(body, code)
	local name, argstr, rest = body:match("^%s*([%a_][%w_]*)%s*%(([^)]*)%)(.*)$")
	if not name then
		name, rest = body:match("^%s*([%a_][%w_]*)(.*)$")
	end
	if not name then
		return nil
	end
	local tag = tags[name:lower()]
	if not tag then
		report(code .. "\1" .. name, ("PitBull4_TagTexts: unknown tag [%s] in %q"):format(name, code))
		return nil
	end
	local args = parse_args(argstr)

	local mods, nmods = {}, 0
	for mod_name, mod_argstr in (rest or ""):gmatch(":%s*([%a_][%w_]*)%(?([^:()]*)%)?") do
		local mod = modifiers[mod_name:lower()]
		if mod then
			nmods = nmods + 1
			mods[nmods] = { fn = mod.fn, args = parse_args(mod_argstr) }
		else
			report(code .. "\1:" .. mod_name, ("PitBull4_TagTexts: unknown modifier :%s in %q"):format(mod_name, code))
		end
	end

	local fn = tag.fn
	local unpack = _G.unpack
	local a1, a2, a3 = args[1], args[2], args[3]
	return function(unit, frame)
		local value = fn(unit, frame, a1, a2, a3)
		if value == nil then
			return nil
		end
		for i = 1, nmods do
			local mod = mods[i]
			value = mod.fn(value, unit, frame, unpack(mod.args))
			if value == nil then
				return nil
			end
		end
		return value
	end, tag.events
end

-- Compile a text into { format = "...", funcs = {...}, n = #funcs, events = {...} }
local function compile(code)
	local c = compiled_cache[code]
	if c then
		return c
	end

	local funcs, events = {}, {}
	local parts = {}
	local pos = 1
	while true do
		local s, e, body = code:find("%[(.-)%]", pos)
		if not s then
			parts[#parts + 1] = (code:sub(pos)):gsub("%%", "%%%%")
			break
		end
		parts[#parts + 1] = (code:sub(pos, s - 1)):gsub("%%", "%%%%")
		local fn, tag_events = build_tag(body, code)
		if fn then
			funcs[#funcs + 1] = fn
			parts[#parts + 1] = "%s"
			for event, kind in pairs(tag_events) do
				if events[event] ~= "all" then
					events[event] = kind
				end
			end
		else
			-- leave unknown tags visible so the user can see the typo
			parts[#parts + 1] = ("[%s]"):format(body:gsub("%%", "%%%%"))
		end
		pos = e + 1
	end

	c = {
		format = table.concat(parts),
		funcs = funcs,
		n = #funcs,
		events = events,
	}
	compiled_cache[code] = c
	return c
end
PitBull4_TagTexts.compile = compile

-----------------------------------------------------------------------------
-- Rendering
-----------------------------------------------------------------------------

local buffer = {}
local function render(font_string, unit, frame, c)
	local funcs = c.funcs
	for i = 1, c.n do
		local value = funcs[i](unit, frame)
		if value == nil then
			value = ""
		end
		buffer[i] = value
	end
	font_string:SetFormattedText(c.format, unpack(buffer, 1, c.n))
end

local function update_text(font_string)
	if not texts[font_string] then
		return
	end
	local frame = font_string.frame
	local unit = frame.unit
	local name = font_string.tagtexts_name

	if (frame.force_show and not frame.guid) or not unit then
		font_string:SetFormattedText("{%s}", name)
		return
	end

	local ok, err = pcall(render, font_string, unit, frame, font_string.compiled)
	if not ok then
		report(font_string.db.code .. "\1render", ("PitBull4_TagTexts:%s:%s caused the following error:\n%s"):format(frame.layout, name, tostring(err)))
		font_string:SetText("{err}")
	end
end

-----------------------------------------------------------------------------
-- Events
-----------------------------------------------------------------------------

-- events that do not exist on this client are skipped, not fatal
local test_frame = CreateFrame("Frame")
local valid_events = {}
local function is_valid_event(event)
	local valid = valid_events[event]
	if valid == nil then
		valid = pcall(test_frame.RegisterEvent, test_frame, event)
		if valid then
			test_frame:UnregisterEvent(event)
		end
		valid_events[event] = valid
	end
	return valid
end

local function event_cache_insert(event, font_string)
	if not is_valid_event(event) then
		return
	end
	local entry = event_cache[event]
	if not entry then
		entry = {}
		event_cache[event] = entry
		PitBull4_TagTexts:RegisterEvent(event, "OnEvent")
	end
	entry[font_string] = true
end

function PitBull4_TagTexts:OnEvent(event, unit)
	local entry = event_cache[event]
	if not entry then
		return
	end
	local guid = unit and PitBull4.UnitGUID(unit)
	for font_string in pairs(entry) do
		local kind = font_string.compiled.events[event]
		local frame = font_string.frame
		if kind == "all" or not unit or frame.unit == unit or (guid and frame.guid == guid) then
			update_text(font_string)
		end
	end
end

-----------------------------------------------------------------------------
-- Text provider contract
-----------------------------------------------------------------------------

function PitBull4_TagTexts:AddFontString(frame, font_string, name, data)
	font_string:Show()

	local compiled = compile(data.code or "")
	if texts[font_string] and font_string.compiled == compiled then
		-- already ours, the frame just wants a refresh
		update_text(font_string)
		return true
	end

	if texts[font_string] then
		self:RemoveFontString(font_string)
	end

	texts[font_string] = true
	font_string.frame = frame
	font_string.tagtexts_name = name
	font_string.compiled = compiled
	for event in pairs(compiled.events) do
		event_cache_insert(event, font_string)
	end

	update_text(font_string)
	return true
end

function PitBull4_TagTexts:RemoveFontString(font_string)
	for event, entry in pairs(event_cache) do
		entry[font_string] = nil
		if not next(entry) then
			self:UnregisterEvent(event)
			event_cache[event] = nil
		end
	end
	font_string.frame = nil
	font_string.tagtexts_name = nil
	font_string.compiled = nil
	texts[font_string] = nil
end

function PitBull4_TagTexts:OnDisable()
	for event in pairs(event_cache) do
		self:UnregisterEvent(event)
		event_cache[event] = nil
	end
	for font_string in pairs(texts) do
		self:RemoveFontString(font_string)
	end
end

-----------------------------------------------------------------------------
-- Defaults and options
-----------------------------------------------------------------------------

local PROVIDED_CODES = {
	[L["Health"]] = {
		[L["Absolute"]] = "[hp]",
		[L["Percent"]] = "[hp(percent)]",
		[L["Difference"]] = "[hp(missing)]",
		[L["Smart"]] = "[hp(smart)]",
		[L["Absolute and percent"]] = "[hp(both)]",
		[L["Informational"]] = "[hp(info)]",
	},
	[L["Name"]] = {
		[L["Standard"]] = "[name] [afkdnd:angle]",
		[L["Hostility-colored"]] = "[name:hostilecolor] [afkdnd:angle]",
		[L["Class-colored"]] = "[name:classcolor] [afkdnd:angle]",
		[L["Long"]] = "[level] [name:classcolor] [afkdnd:angle]",
	},
	[L["Class"]] = {
		[L["Standard"]] = "[classification:suffix( )][level:difficultycolor] [class:classcolor] [race]",
		[L["Short level and race"]] = "[level:difficultycolor] [race]",
		[L["Short"]] = "[class:classcolor]",
	},
	[L["Power"]] = {
		[L["Absolute"]] = "[pp]",
		[L["Percent"]] = "[pp(percent)]",
		[L["Difference"]] = "[pp(missing)]",
		[L["Smart"]] = "[pp(smart)]",
		[L["Absolute and percent"]] = "[pp(both)]",
	},
	[L["Druid mana"]] = {
		[L["Absolute"]] = "[druidmana]",
	},
	[L["Threat"]] = {
		[L["Percent"]] = "[threat]",
	},
	[L["Cast"]] = {
		[L["Standard name"]] = "[castname]",
	},
	[L["Combo points"]] = {
		[L["Standard"]] = "[combos]",
	},
	[L["Experience"]] = {
		[L["Standard"]] = "[xp]",
	},
	[L["Reputation"]] = {
		[L["Standard"]] = "[rep]",
	},
}
PitBull4_TagTexts.PROVIDED_CODES = PROVIDED_CODES

function PitBull4_TagTexts:OnNewLayout(layout)
	local layout_db = self.db.profile.layouts[layout]
	if not layout_db.first then
		return
	end
	layout_db.first = false

	local elements = layout_db.elements
	for k in pairs(elements) do
		elements[k] = nil
	end
	for name, data in pairs {
		["Tag:" .. L["Name"]] = {
			code = PROVIDED_CODES[L["Name"]][L["Standard"]],
			attach_to = "HealthBar",
			location = "left",
		},
		["Tag:" .. L["Health"]] = {
			code = PROVIDED_CODES[L["Health"]][L["Absolute and percent"]],
			attach_to = "HealthBar",
			location = "right",
		},
		["Tag:" .. L["Class"]] = {
			code = PROVIDED_CODES[L["Class"]][L["Standard"]],
			attach_to = "PowerBar",
			location = "left",
		},
		["Tag:" .. L["Power"]] = {
			code = PROVIDED_CODES[L["Power"]][L["Absolute"]],
			attach_to = "PowerBar",
			location = "right",
		},
		["Tag:" .. L["Experience"]] = {
			code = PROVIDED_CODES[L["Experience"]][L["Standard"]],
			attach_to = "ExperienceBar",
			location = "center",
		},
		["Tag:" .. L["Reputation"]] = {
			code = PROVIDED_CODES[L["Reputation"]][L["Standard"]],
			attach_to = "ReputationBar",
			location = "center",
		},
		["Tag:" .. L["Cast"]] = {
			code = PROVIDED_CODES[L["Cast"]][L["Standard name"]],
			attach_to = "CastBar",
			location = "left",
		},
		["Tag:" .. L["Threat"]] = {
			code = PROVIDED_CODES[L["Threat"]][L["Percent"]],
			attach_to = "ThreatBar",
			location = "center",
		},
		["Tag:" .. L["Druid mana"]] = {
			code = PROVIDED_CODES[L["Druid mana"]][L["Absolute"]],
			attach_to = "AltManaBar",
			location = "center",
		},
	} do
		local text_db = elements[name]
		text_db.exists = true
		for k, v in pairs(data) do
			text_db[k] = v
		end
	end
end

-- Handle updating after a config change
local function update()
	local layout = PitBull4.Options.GetCurrentLayout()
	for frame in PitBull4:IterateFramesForLayout(layout) do
		PitBull4_TagTexts:ForceTextUpdate(frame)
	end
end

local function tag_help()
	local names = {}
	for _, tag in pairs(tags) do
		names[#names + 1] = tag
	end
	table.sort(names, function(a, b) return a.name < b.name end)
	local lines = {}
	for _, tag in ipairs(names) do
		lines[#lines + 1] = ("|cffffff7f[%s]|r %s"):format(tag.name, tag.help or "")
	end
	local mod_names = {}
	for _, mod in pairs(modifiers) do
		mod_names[#mod_names + 1] = mod
	end
	table.sort(mod_names, function(a, b) return a.name < b.name end)
	lines[#lines + 1] = ""
	for _, mod in ipairs(mod_names) do
		lines[#lines + 1] = ("|cffffff7f:%s|r %s"):format(mod.name, mod.help or "")
	end
	return table.concat(lines, "\n")
end

PitBull4_TagTexts:SetLayoutOptionsFunction(function(self)
	local values = {}
	local value_key_to_code = {}
	values[""] = L["Custom"]
	value_key_to_code[""] = ""
	for base, codes in pairs(PROVIDED_CODES) do
		for name, code in pairs(codes) do
			local key = ("%s: %s"):format(base, name)
			values[key] = key
			value_key_to_code[key] = code
		end
	end
	return 'default_codes', {
		type = 'select',
		name = L["Code"],
		desc = L["Some codes provided for you."],
		get = function(info)
			local code = PitBull4.Options.GetTextLayoutDB().code
			for k, v in pairs(value_key_to_code) do
				if v == code then
					return k
				end
			end
			return ""
		end,
		set = function(info, value)
			PitBull4.Options.GetTextLayoutDB().code = value_key_to_code[value]
			update()
		end,
		values = values,
		width = 'double',
	}, 'code', {
		type = 'input',
		name = L["Code"],
		desc = L["Enter a text made of literal text and [tags]. Tags take arguments, [hp(percent)], and modifiers, [name:classcolor]."],
		get = function(info)
			return PitBull4.Options.GetTextLayoutDB().code
		end,
		set = function(info, value)
			PitBull4.Options.GetTextLayoutDB().code = value
			update()
		end,
		multiline = true,
		width = 'full',
	}, 'help', {
		type = 'description',
		name = tag_help,
		fontSize = 'medium',
	}
end)
