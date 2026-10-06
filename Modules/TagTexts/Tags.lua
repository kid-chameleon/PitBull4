-- The tag library for TagTexts. Every tag returns a string, a number or nil.
-- The value may be a secret: it is only ever handed to string.format,
-- C_StringUtil and FontString:SetFormattedText, all of which accept secrets.
-- Branching happens only on values that are never secret (connection,
-- death, unit type, power type, levels of the player's own group).
--
-- Two more things turn secret in instances: the identity of a unit outside
-- the group (class, race, creature type, PvP flag, honour level...), and the
-- AFK and DND flags of everyone, which Blizzard ties to a "chat messaging
-- lockdown". A tag that would have to branch on one of those gives nothing
-- or uses the engine to do the branching.

local _G = _G
local PitBull4 = _G.PitBull4
local L = PitBull4.L

local PitBull4_TagTexts = PitBull4:GetModule("TagTexts")

local issecretvalue = _G.issecretvalue or function() return false end
local format = string.format

-- Secret-safe string helpers, with plain fallbacks for clients without them.
local WrapString = C_StringUtil and C_StringUtil.WrapString or function(infix, prefix, suffix)
	if infix == nil or infix == "" then
		return ""
	end
	return (prefix or "") .. infix .. (suffix or "")
end
local TruncateWhenZero = C_StringUtil and C_StringUtil.TruncateWhenZero or function(number)
	if number == 0 then
		return ""
	end
	return format("%d", number)
end

-- Percentages are produced by the engine through a curve; the ready-made
-- one scales [0, 1] to [0, 100].
local ScaleTo100 = CurveConstants and CurveConstants.ScaleTo100
if not ScaleTo100 and C_CurveUtil then
	ScaleTo100 = C_CurveUtil.CreateCurve()
	ScaleTo100:AddPoint(0, 0)
	ScaleTo100:AddPoint(1, 100)
end

local UnitHealthPercent = _G.UnitHealthPercent or function(unit)
	local max = UnitHealthMax(unit)
	if max == 0 then return 0 end
	return UnitHealth(unit) / max * 100
end
local UnitHealthMissing = _G.UnitHealthMissing or function(unit)
	return UnitHealthMax(unit) - UnitHealth(unit)
end
local UnitPowerPercent = _G.UnitPowerPercent or function(unit, power_type)
	local max = UnitPowerMax(unit, power_type)
	if max == 0 then return 0 end
	return UnitPower(unit, power_type) / max * 100
end
local UnitPowerMissing = _G.UnitPowerMissing or function(unit, power_type)
	return UnitPowerMax(unit, power_type) - UnitPower(unit, power_type)
end

local function health_percent(unit)
	if ScaleTo100 then
		return UnitHealthPercent(unit, true, ScaleTo100)
	end
	return UnitHealthPercent(unit)
end

local function power_percent(unit, power_type)
	if ScaleTo100 then
		return UnitPowerPercent(unit, power_type, false, ScaleTo100)
	end
	return UnitPowerPercent(unit, power_type)
end

local function is_player(unit)
	return UnitIsPlayer(unit) or UnitInPartyIsAI(unit)
end

local GetQuestDifficultyColor = _G.GetQuestDifficultyColor or function() return { r = 1, g = 1, b = 1 } end

local function hex(r, g, b)
	return format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end

-- On this client a character may have a surname, and UnitName returns it as
-- its second value rather than a realm. Blizzard joins the two with a
-- client-side constant (Blizzard_FrameXMLUtil/Camelot/NameUtil.lua).
local SURNAME_SEPARATOR = Constants and Constants.CharacterNameSeparatorConsts
	and Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR or " "

local UNIT_EVENTS_HEALTH = { UNIT_HEALTH = "unit", UNIT_MAXHEALTH = "unit", UNIT_CONNECTION = "unit", UNIT_FLAGS = "unit" }
local UNIT_EVENTS_POWER = { UNIT_POWER_FREQUENT = "unit", UNIT_MAXPOWER = "unit", UNIT_DISPLAYPOWER = "unit" }

-----------------------------------------------------------------------------
-- Status
-----------------------------------------------------------------------------

-- Offline, feigning death, ghost or dead: all plain booleans.
local function status(unit)
	if not UnitIsConnected(unit) then
		return _G.PLAYER_OFFLINE
	elseif UnitIsFeignDeath(unit) then
		return L["Feigned Death"]
	elseif UnitIsGhost(unit) then
		return L["Ghost"]
	elseif UnitIsDead(unit) then
		return L["Dead"]
	end
	return nil
end

PitBull4_TagTexts:RegisterTag("status", UNIT_EVENTS_HEALTH, status, L["Offline, Feigned Death, Ghost or Dead, otherwise nothing"])

-----------------------------------------------------------------------------
-- Health
-----------------------------------------------------------------------------

PitBull4_TagTexts:RegisterTag("curhp", UNIT_EVENTS_HEALTH, function(unit)
	return format("%d", UnitHealth(unit))
end, L["current health"])

PitBull4_TagTexts:RegisterTag("maxhp", UNIT_EVENTS_HEALTH, function(unit)
	return format("%d", UnitHealthMax(unit))
end, L["maximum health"])

PitBull4_TagTexts:RegisterTag("perhp", UNIT_EVENTS_HEALTH, function(unit)
	return format("%d", health_percent(unit))
end, L["health percentage, without the % sign"])

PitBull4_TagTexts:RegisterTag("missinghp", UNIT_EVENTS_HEALTH, function(unit)
	return TruncateWhenZero(UnitHealthMissing(unit))
end, L["missing health, nothing when full"])

-- [hp], [hp(percent)], [hp(missing)], [hp(smart)], [hp(both)], [hp(info)]:
-- the status when the unit is dead or offline, otherwise the chosen style
PitBull4_TagTexts:RegisterTag("hp", UNIT_EVENTS_HEALTH, function(unit, frame, style)
	local s = status(unit)
	if s then
		return s
	end
	if style == "percent" then
		return format("%d%%", health_percent(unit))
	elseif style == "missing" then
		return WrapString(TruncateWhenZero(UnitHealthMissing(unit)), "-", "")
	elseif style == "smart" then
		if UnitIsFriend("player", unit) then
			return WrapString(TruncateWhenZero(UnitHealthMissing(unit)), "|cffff7f7f", "|r")
		end
		return format("%d/%d", UnitHealth(unit), UnitHealthMax(unit))
	elseif style == "both" then
		return format("%d/%d || %d%%", UnitHealth(unit), UnitHealthMax(unit), health_percent(unit))
	elseif style == "info" then
		local missing = ""
		if UnitIsFriend("player", unit) then
			missing = WrapString(TruncateWhenZero(UnitHealthMissing(unit)), "|cffff7f7f", "|r || ")
		end
		return format("%s%d/%d || %d%%", missing, UnitHealth(unit), UnitHealthMax(unit), health_percent(unit))
	end
	return format("%d/%d", UnitHealth(unit), UnitHealthMax(unit))
end, L["health as current/maximum, or the status; styles: percent, missing, smart, both, info"])

-----------------------------------------------------------------------------
-- Power
-----------------------------------------------------------------------------

-- Whether the unit has the power at all: plain maximum where readable,
-- UnitHasPowerType and a plain UnitPower elsewhere (see Utils.UnitHasPower).
local has_power = PitBull4.Utils.UnitHasPower

PitBull4_TagTexts:RegisterTag("curpp", UNIT_EVENTS_POWER, function(unit)
	return format("%d", UnitPower(unit))
end, L["current power"])

PitBull4_TagTexts:RegisterTag("maxpp", UNIT_EVENTS_POWER, function(unit)
	return format("%d", UnitPowerMax(unit))
end, L["maximum power"])

PitBull4_TagTexts:RegisterTag("perpp", UNIT_EVENTS_POWER, function(unit)
	return format("%d", power_percent(unit))
end, L["power percentage, without the % sign"])

PitBull4_TagTexts:RegisterTag("missingpp", UNIT_EVENTS_POWER, function(unit)
	return TruncateWhenZero(UnitPowerMissing(unit))
end, L["missing power, nothing when full"])

PitBull4_TagTexts:RegisterTag("pp", UNIT_EVENTS_POWER, function(unit, frame, style)
	if not has_power(unit) then
		return nil
	end
	if style == "percent" then
		return format("%d%%", power_percent(unit))
	elseif style == "missing" then
		return WrapString(TruncateWhenZero(UnitPowerMissing(unit)), "-", "")
	elseif style == "smart" then
		return WrapString(TruncateWhenZero(UnitPowerMissing(unit)), "|cff7f7fff", "|r")
	elseif style == "both" then
		return format("%d/%d || %d%%", UnitPower(unit), UnitPowerMax(unit), power_percent(unit))
	end
	return format("%d/%d", UnitPower(unit), UnitPowerMax(unit))
end, L["power as current/maximum, nothing for units without power; styles: percent, missing, smart, both"])

PitBull4_TagTexts:RegisterTag("druidmana", UNIT_EVENTS_POWER, function(unit)
	if UnitPowerType(unit) == 0 then
		return nil
	end
	return format("%d/%d", UnitPower(unit, 0), UnitPowerMax(unit, 0))
end, L["mana while in a form that uses another power"])

PitBull4_TagTexts:RegisterTag("combos", { UNIT_POWER_FREQUENT = "all", UNIT_POWER_UPDATE = "all", PLAYER_TARGET_CHANGED = "all" }, function(unit)
	if unit ~= "player" and unit ~= "target" then
		return nil
	end
	return TruncateWhenZero(GetComboPoints("player", "target"))
end, L["combo points on the target, nothing at zero"])

-----------------------------------------------------------------------------
-- Identity
-----------------------------------------------------------------------------

PitBull4_TagTexts:RegisterTag("name", { UNIT_NAME_UPDATE = "unit" }, function(unit, frame, style)
	local name, surname = UnitName(unit)
	-- WrapString will not take a nil, and most units have no surname.
	-- Comparing against nil is safe even when the value is secret: a secret
	-- compares as plainly not nil, and a unit without a surname returns a
	-- plain nil.
	if style == "first" or surname == nil then
		return name
	end
	-- the separator is added only when the surname is not empty, and a secret
	-- surname passes through as happily as a plain one
	return format("%s%s", name, WrapString(surname, SURNAME_SEPARATOR, ""))
end, L["unit name with surname; [name(first)] for the first name alone"])

PitBull4_TagTexts:RegisterTag("surname", { UNIT_NAME_UPDATE = "unit" }, function(unit)
	return (select(2, UnitName(unit)))
end, L["unit surname, if it has one"])

PitBull4_TagTexts:RegisterTag("level", { UNIT_LEVEL = "all" }, function(unit)
	local level = UnitLevel(unit)
	if level <= 0 then
		return "??"
	end
	return level
end, L["unit level, ?? when unknown"])

-- UnitClass's first value is whatever the unit calls its class, and on this
-- client a creature often reports its own name there, so a frame ends up
-- saying "Hippogryph Protector Hippogryph Protector". Its third value is a
-- class id, and only a real class has one that resolves, which is the test
-- the module's own Lua text provider used. Creatures that do map to a class
-- still show it, as they do on the classic clients.
PitBull4_TagTexts:RegisterTag("class", {}, function(unit, frame, style)
	local class, _, class_id = UnitClass(unit)
	if style == "any" then
		return class
	end
	if issecretvalue(class_id) then
		-- The id cannot be tested, and inside an instance every unit outside
		-- the group is restricted, creatures included, so the first value may
		-- again be the creature's own name. Nor can it be compared with the
		-- name, which is just as secret. Whether the unit is a player is
		-- plain, and a player's class is always a real one.
		if is_player(unit) then
			return class
		end
		return nil
	end
	if class_id then
		local info = C_CreatureInfo.GetClassInfo(class_id)
		if info and info.className then
			return info.className
		end
	end
	return nil
end, L["class name, nothing for a creature without one; [class(any)] for whatever the unit reports"])

-- Every value here is secret for a unit whose identity is restricted, so
-- only nil tests, which stay plain, decide which one is shown.
PitBull4_TagTexts:RegisterTag("race", {}, function(unit)
	if UnitIsPlayer(unit) then
		local race = UnitRace(unit)
		if race == nil then
			return UNKNOWN
		end
		return race
	end
	local family = UnitCreatureFamily(unit)
	if family ~= nil then
		return family
	end
	local creature_type = UnitCreatureType(unit)
	if creature_type ~= nil then
		return creature_type
	end
	return UNKNOWN
end, L["race for players, creature type otherwise"])

local classification_lookup = {
	rare = L["Rare"],
	rareelite = L["Rare-Elite"],
	elite = L["Elite"],
	worldboss = L["Boss"],
	minus = L["Minus"],
	trivial = L["Trivial"],
}
PitBull4_TagTexts:RegisterTag("classification", { UNIT_CLASSIFICATION_CHANGED = "unit" }, function(unit)
	return classification_lookup[PitBull4.Utils.BetterUnitClassification(unit)]
end, L["Elite, Rare, Boss, ... or nothing"])

-- UnitIsAFK and UnitIsDND return a secret boolean while chat messaging is
-- locked down, which is the case inside instances even for the player's own
-- party. There is no engine call that turns a boolean into a string, so the
-- flag is simply unknown then and the tag says nothing.
local function is_afk(unit)
	local afk = UnitIsAFK(unit)
	return not issecretvalue(afk) and afk
end

local function is_dnd(unit)
	local dnd = UnitIsDND(unit)
	return not issecretvalue(dnd) and dnd
end

PitBull4_TagTexts:RegisterTag("afk", { PLAYER_FLAGS_CHANGED = "unit" }, function(unit)
	if is_afk(unit) then
		return _G.AFK
	end
	return nil
end, L["AFK when the unit is away"])

PitBull4_TagTexts:RegisterTag("dnd", { PLAYER_FLAGS_CHANGED = "unit" }, function(unit)
	if is_dnd(unit) then
		return _G.DND
	end
	return nil
end, L["DND when the unit does not want to be disturbed"])

PitBull4_TagTexts:RegisterTag("afkdnd", { PLAYER_FLAGS_CHANGED = "unit" }, function(unit)
	if is_afk(unit) then
		return _G.AFK
	elseif is_dnd(unit) then
		return _G.DND
	end
	return nil
end, L["AFK or DND"])

-----------------------------------------------------------------------------
-- Casting
-----------------------------------------------------------------------------

local CAST_EVENTS = {
	UNIT_SPELLCAST_START = "unit", UNIT_SPELLCAST_STOP = "unit",
	UNIT_SPELLCAST_FAILED = "unit", UNIT_SPELLCAST_INTERRUPTED = "unit",
	UNIT_SPELLCAST_SUCCEEDED = "unit", UNIT_SPELLCAST_DELAYED = "unit",
	UNIT_SPELLCAST_CHANNEL_START = "unit", UNIT_SPELLCAST_CHANNEL_UPDATE = "unit",
	UNIT_SPELLCAST_CHANNEL_STOP = "unit", PLAYER_TARGET_CHANGED = "all",
}

-- The name is secret for anything but the player and its pet, which the
-- engine will still render. There is no tag for the remaining time: that
-- needs a duration text binding the engine writes into continuously, which
-- a format string cannot express.
PitBull4_TagTexts:RegisterTag("castname", CAST_EVENTS, function(unit)
	local name = UnitCastingInfo(unit)
	if name ~= nil then
		return name
	end
	return (UnitChannelInfo(unit))
end, L["the spell being cast"])

-----------------------------------------------------------------------------
-- Threat, experience, reputation
-----------------------------------------------------------------------------

PitBull4_TagTexts:RegisterTag("threat", { UNIT_THREAT_LIST_UPDATE = "all", UNIT_THREAT_SITUATION_UPDATE = "all" }, function(unit)
	local _, _, scaled_percent = UnitDetailedThreatSituation(unit, "target")
	if not scaled_percent then
		return nil
	end
	return format("%d%%", scaled_percent)
end, L["threat percentage against the target"])

PitBull4_TagTexts:RegisterTag("xp", { PLAYER_XP_UPDATE = "all", UNIT_PET_EXPERIENCE = "all", UPDATE_EXHAUSTION = "all" }, function(unit)
	local cur, max, rest
	if unit == "player" then
		cur, max, rest = UnitXP(unit), UnitXPMax(unit), GetXPExhaustion()
	elseif unit == "pet" and GetPetExperience then
		cur, max = GetPetExperience()
	else
		return nil
	end
	if not max or max == 0 then
		return nil
	end
	if rest and rest > 0 then
		return format("%d/%d (%d%%) R: %d%%", cur, max, cur / max * 100, rest / max * 100)
	end
	return format("%d/%d (%d%%)", cur, max, cur / max * 100)
end, L["experience as current/maximum (percent) and rested"])

local function watched_faction()
	if C_Reputation and C_Reputation.GetWatchedFactionData then
		local data = C_Reputation.GetWatchedFactionData()
		if not data then
			return nil
		end
		return data.name, data.reaction, data.currentReactionThreshold, data.nextReactionThreshold, data.currentStanding
	elseif GetWatchedFactionInfo then
		return GetWatchedFactionInfo()
	end
	return nil
end

PitBull4_TagTexts:RegisterTag("rep", { UPDATE_FACTION = "all" }, function(unit)
	local name, _, min, max, cur = watched_faction()
	if not name then
		return nil
	end
	cur, max = cur - min, max - min
	if max <= 0 then
		return name
	end
	return format("%d/%d (%d%%)", cur, max, cur / max * 100)
end, L["watched reputation as current/maximum (percent)"])

PitBull4_TagTexts:RegisterTag("repname", { UPDATE_FACTION = "all" }, function(unit)
	return (watched_faction())
end, L["watched reputation name"])

-----------------------------------------------------------------------------
-- Modifiers
-----------------------------------------------------------------------------

PitBull4_TagTexts:RegisterModifier("paren", function(value)
	return WrapString(value, "(", ")")
end, L["wrap in parentheses"])

PitBull4_TagTexts:RegisterModifier("angle", function(value)
	return WrapString(value, "<", ">")
end, L["wrap in angle brackets"])

PitBull4_TagTexts:RegisterModifier("bracket", function(value)
	return WrapString(value, "[", "]")
end, L["wrap in square brackets"])

PitBull4_TagTexts:RegisterModifier("prefix", function(value, unit, frame, text)
	return WrapString(value, text or "", "")
end, L["add text before, unless empty"])

PitBull4_TagTexts:RegisterModifier("suffix", function(value, unit, frame, text)
	return WrapString(value, "", text or "")
end, L["add text after, unless empty"])

PitBull4_TagTexts:RegisterModifier("color", function(value, unit, frame, rrggbb)
	if not rrggbb then
		return value
	end
	return WrapString(value, "|cff" .. tostring(rrggbb), "|r")
end, L["colour with a hex code, e.g. color(ff7f7f)"])

PitBull4_TagTexts:RegisterModifier("red", function(value)
	return WrapString(value, "|cffff0000", "|r")
end)
PitBull4_TagTexts:RegisterModifier("green", function(value)
	return WrapString(value, "|cff00ff00", "|r")
end)
PitBull4_TagTexts:RegisterModifier("blue", function(value)
	return WrapString(value, "|cff0000ff", "|r")
end)
PitBull4_TagTexts:RegisterModifier("white", function(value)
	return WrapString(value, "|cffffffff", "|r")
end)

PitBull4_TagTexts:RegisterModifier("classcolor", function(value, unit)
	local _, class = UnitClass(unit)
	local color
	if class and issecretvalue(class) then
		-- Only Blizzard's colours can be looked up with a secret class, and
		-- the colour that comes back carries secret components, so the hex
		-- code cannot be built here either: the engine wraps the text
		-- (C_ColorUtil.WrapTextInColor, which takes secrets).
		if C_ClassColor and C_ClassColor.GetClassColor then
			color = C_ClassColor.GetClassColor(class)
			if color and color.WrapTextInColorCode then
				return color:WrapTextInColorCode(value)
			end
		end
		return value
	end
	local t = PitBull4.ClassColors[class] or PitBull4.ClassColors.UNKNOWN
	return WrapString(value, hex(t[1], t[2], t[3]), "|r")
end, L["colour by class"])

local HOSTILE_REACTION = 2
local NEUTRAL_REACTION = 4
local FRIENDLY_REACTION = 5

local function hostile_color(unit)
	local colors = PitBull4.ReactionColors
	if is_player(unit) or UnitPlayerControlled(unit) then
		if UnitCanAttack(unit, "player") then
			if UnitCanAttack("player", unit) then
				return colors[HOSTILE_REACTION]
			end
			return colors.civilian
		elseif UnitCanAttack("player", unit) then
			return colors[NEUTRAL_REACTION]
		end
		-- the flag is secret for a unit whose identity is restricted; it is
		-- a friendly player either way, and gets the friendly colour
		local pvp = UnitIsPVP(unit)
		if issecretvalue(pvp) or pvp then
			return colors[FRIENDLY_REACTION]
		end
		return colors.civilian
	elseif UnitIsTapDenied(unit) or UnitIsDead(unit) then
		return colors.tapped
	end
	local reaction = UnitReaction(unit, "player")
	if not reaction then
		return colors.unknown
	elseif reaction >= 5 then
		return colors[FRIENDLY_REACTION]
	elseif reaction == 4 then
		return colors[NEUTRAL_REACTION]
	end
	return colors[HOSTILE_REACTION]
end

PitBull4_TagTexts:RegisterModifier("hostilecolor", function(value, unit)
	local t = hostile_color(unit)
	return WrapString(value, hex(t[1], t[2], t[3]), "|r")
end, L["colour by hostility"])

PitBull4_TagTexts:RegisterModifier("difficultycolor", function(value, unit)
	local level = UnitLevel(unit)
	if level <= 0 then
		level = 99
	end
	local color = GetQuestDifficultyColor(level)
	return WrapString(value, hex(color.r, color.g, color.b), "|r")
end, L["colour by level difficulty"])

PitBull4_TagTexts:RegisterModifier("aggrocolor", function(value, unit)
	local r, g, b = UnitSelectionColor(unit)
	return WrapString(value, hex(r, g, b), "|r")
end, L["colour by selection colour"])
