-- Questie for World of Warcraft 3.3.5a (build 12340)
--
-- First file of the addon. It adds the parts of the newer WoW API that Questie and its embedded
-- libraries use but the 3.3.5a client does not have.
--
-- Rules followed here, because other addons share the global environment:
--   * nothing that the client already provides is replaced; every shim checks first;
--   * only complete, behaviour-correct shims go into _G (C_Timer, Mixin, SetShown, ...);
--   * partial modern namespaces (C_Map, C_QuestLog, C_ChatInfo, Enum, ...) are NOT created globally,
--     since other 3.3.5a addons may test for them to pick a code path. Questie reaches those through
--     its own QuestieCompat335 table instead.

local _G = _G
local type, select, pairs, ipairs, tostring = type, select, pairs, ipairs, tostring
local floor, format = math.floor, string.format
local tinsert, tremove = table.insert, table.remove

---@class QuestieCompat335
QuestieCompat335 = QuestieCompat335 or {}
local QuestieCompat335 = QuestieCompat335

local _, buildNumber, _, interfaceVersion = GetBuildInfo()
QuestieCompat335.build = tonumber(buildNumber) or 0
QuestieCompat335.interface = tonumber(interfaceVersion) or 30300
--- True on the original Wrath client (and any other pre-3.4 build this port is run on).
QuestieCompat335.isLegacyClient = QuestieCompat335.interface < 30400

-------------------------------------------------------------------------------------------------
-- Project identification
-------------------------------------------------------------------------------------------------
-- The 3.3.5a client has no WOW_PROJECT_* constants. Questie and several libraries compare
-- WOW_PROJECT_ID with these; when both sides are nil such a comparison is true, so they must exist.
-- The values are Blizzard's. This client is reported as Wrath, which is the content it runs.
WOW_PROJECT_MAINLINE = WOW_PROJECT_MAINLINE or 1
WOW_PROJECT_CLASSIC = WOW_PROJECT_CLASSIC or 2
WOW_PROJECT_BURNING_CRUSADE_CLASSIC = WOW_PROJECT_BURNING_CRUSADE_CLASSIC or 5
WOW_PROJECT_WRATH_CLASSIC = WOW_PROJECT_WRATH_CLASSIC or 11
WOW_PROJECT_CATACLYSM_CLASSIC = WOW_PROJECT_CATACLYSM_CLASSIC or 14
WOW_PROJECT_MISTS_CLASSIC = WOW_PROJECT_MISTS_CLASSIC or 19
WOW_PROJECT_ID = WOW_PROJECT_ID or WOW_PROJECT_WRATH_CLASSIC

LE_PARTY_CATEGORY_HOME = LE_PARTY_CATEGORY_HOME or 1
LE_PARTY_CATEGORY_INSTANCE = LE_PARTY_CATEGORY_INSTANCE or 2

-------------------------------------------------------------------------------------------------
-- Frame templates
-------------------------------------------------------------------------------------------------
-- Later clients need BackdropTemplate for SetBackdrop; on 3.3.5a every frame has it already.
-- CreateFrame(..., QuestieCompat335.BackdropTemplate) works on both. Some 3.3.5a addons (CompactRaidFrame's
-- WotLKCompat.lua among them) add a BackdropTemplateMixin table but no BackdropTemplate XML template, so on this
-- client that table says nothing and CreateFrame with the template fails.
QuestieCompat335.BackdropTemplate = (not QuestieCompat335.isLegacyClient) and BackdropTemplateMixin and "BackdropTemplate" or nil
-- Dialog borders of later clients (Compat335.xml has this client's versions)
QuestieCompat335.DialogBorderOpaqueTemplate = QuestieCompat335.isLegacyClient and "QuestieCompat335DialogBorderOpaqueTemplate" or "DialogBorderOpaqueTemplate"
QuestieCompat335.DialogBorderDarkTemplate = QuestieCompat335.isLegacyClient and "QuestieCompat335DialogBorderDarkTemplate" or "DialogBorderDarkTemplate"

-------------------------------------------------------------------------------------------------
-- Strings
-------------------------------------------------------------------------------------------------
-- Key binding header (Bindings.xml); the binding names are set by the modules that own them.
BINDING_HEADER_QUESTIE = BINDING_HEADER_QUESTIE or "Questie"

-- Blizzard_Calendar keeps these two tables local on 3.3.5a; the strings themselves are global.
QuestieCompat335.CALENDAR_WEEKDAY_NAMES = CALENDAR_WEEKDAY_NAMES or {
    WEEKDAY_SUNDAY, WEEKDAY_MONDAY, WEEKDAY_TUESDAY, WEEKDAY_WEDNESDAY, WEEKDAY_THURSDAY, WEEKDAY_FRIDAY, WEEKDAY_SATURDAY,
}
QuestieCompat335.CALENDAR_FULLDATE_MONTH_NAMES = CALENDAR_FULLDATE_MONTH_NAMES or {
    FULLDATE_MONTH_JANUARY, FULLDATE_MONTH_FEBRUARY, FULLDATE_MONTH_MARCH, FULLDATE_MONTH_APRIL, FULLDATE_MONTH_MAY,
    FULLDATE_MONTH_JUNE, FULLDATE_MONTH_JULY, FULLDATE_MONTH_AUGUST, FULLDATE_MONTH_SEPTEMBER, FULLDATE_MONTH_OCTOBER,
    FULLDATE_MONTH_NOVEMBER, FULLDATE_MONTH_DECEMBER,
}

-------------------------------------------------------------------------------------------------
-- Error reporting helpers
-------------------------------------------------------------------------------------------------

-- Errors in callbacks are reported by xpcall to the current error handler directly. 3.3.5a's error frame
-- (Blizzard_DebugTools) reads the local variables 4 stack levels up from where it runs; with a function of
-- ours between it and the error, that level is error() itself, which has none, and the frame then fails on
-- every error that follows ("bad argument #6 to 'format'", then "C stack overflow").
if not CallErrorHandler then
    function CallErrorHandler(...)
        return geterrorhandler()(...)
    end
end

if not securecallfunction then
    local unpack = unpack
    local function _Return(ok, ...)
        if ok then
            return ...
        end
    end
    --- Calls func(...); an error is reported to the error handler instead of being raised.
    function securecallfunction(func, ...)
        local n = select("#", ...)
        if n == 0 then
            return _Return(xpcall(func, geterrorhandler()))
        end
        local args = {...}
        return _Return(xpcall(function() return func(unpack(args, 1, n)) end, geterrorhandler()))
    end
end

-------------------------------------------------------------------------------------------------
-- C_Timer (After, NewTimer, NewTicker)
-------------------------------------------------------------------------------------------------

-- Another addon may have added a partial C_Timer (often only After): the missing functions are added.
if not (C_Timer and C_Timer.After and C_Timer.NewTimer and C_Timer.NewTicker) then
    local GetTime = GetTime
    local timerFrame = CreateFrame("Frame")
    timerFrame:Hide()

    local active = {}    -- timers that are scheduled
    local incoming = {}  -- timers scheduled while the active list is being processed
    local processing = false

    local TimerMethods = {}
    local TimerMeta = {__index = TimerMethods}

    function TimerMethods:Cancel()
        self._cancelled = true
    end

    function TimerMethods:IsCancelled()
        return self._cancelled == true
    end

    local function _Schedule(timer)
        if processing then
            incoming[#incoming + 1] = timer
        else
            active[#active + 1] = timer
        end
        timerFrame:Show()
    end

    local function _Fire(timer)
        local callback = timer._callback
        if timer._passSelf then
            xpcall(function() callback(timer) end, geterrorhandler())
        else
            xpcall(callback, geterrorhandler())
        end
    end

    timerFrame:SetScript("OnUpdate", function(self)
        local now = GetTime()
        processing = true
        local count = #active
        local i = 1
        while i <= count do
            local timer = active[i]
            local remove = false
            if timer._cancelled then
                remove = true
            elseif now >= timer._due then
                if timer._ticker then
                    if timer._remaining then
                        timer._remaining = timer._remaining - 1
                        if timer._remaining <= 0 then
                            timer._cancelled = true
                            remove = true
                        end
                    end
                    if not remove then
                        timer._due = now + timer._duration
                    end
                else
                    remove = true
                end
                _Fire(timer)
            end
            if remove then
                active[i] = active[count]
                active[count] = nil
                count = count - 1
            else
                i = i + 1
            end
        end
        processing = false
        if #incoming > 0 then
            for index = 1, #incoming do
                active[#active + 1] = incoming[index]
                incoming[index] = nil
            end
        end
        if #active == 0 then
            self:Hide()
        end
    end)

    local function _Validate(duration, callback, usage)
        if type(duration) ~= "number" or type(callback) ~= "function" then
            error(usage, 3)
        end
        if duration < 0 then
            duration = 0
        end
        return duration
    end

    local timerApi = {}

    --- Calls callback() once after `duration` seconds (0 means the next frame).
    function timerApi.After(duration, callback)
        duration = _Validate(duration, callback, "Usage: C_Timer.After(seconds, callback)")
        _Schedule(setmetatable({_due = GetTime() + duration, _callback = callback}, TimerMeta))
    end

    --- Calls callback(timer) once after `duration` seconds; the returned timer can be cancelled.
    function timerApi.NewTimer(duration, callback)
        duration = _Validate(duration, callback, "Usage: C_Timer.NewTimer(seconds, callback)")
        local timer = setmetatable({_due = GetTime() + duration, _callback = callback, _passSelf = true}, TimerMeta)
        _Schedule(timer)
        return timer
    end

    --- Calls callback(ticker) every `duration` seconds, `iterations` times or until cancelled.
    function timerApi.NewTicker(duration, callback, iterations)
        duration = _Validate(duration, callback, "Usage: C_Timer.NewTicker(seconds, callback[, iterations])")
        local timer = setmetatable({
            _due = GetTime() + duration,
            _duration = duration,
            _callback = callback,
            _passSelf = true,
            _ticker = true,
            _remaining = (type(iterations) == "number" and iterations > 0) and iterations or nil,
        }, TimerMeta)
        _Schedule(timer)
        return timer
    end

    C_Timer = C_Timer or {}
    for name, func in pairs(timerApi) do
        if type(C_Timer[name]) ~= "function" then
            C_Timer[name] = func
        end
    end
end

-------------------------------------------------------------------------------------------------
-- Mixins
-------------------------------------------------------------------------------------------------

if not Mixin then
    function Mixin(object, ...)
        for i = 1, select("#", ...) do
            local mixin = select(i, ...)
            for key, value in pairs(mixin) do
                object[key] = value
            end
        end
        return object
    end
end

if not CreateFromMixins then
    function CreateFromMixins(...)
        return Mixin({}, ...)
    end
end

if not CreateAndInitFromMixin then
    function CreateAndInitFromMixin(mixin, ...)
        local object = CreateFromMixins(mixin)
        object:Init(...)
        return object
    end
end

-------------------------------------------------------------------------------------------------
-- Small utility functions from later clients
-------------------------------------------------------------------------------------------------

if not Lerp then
    function Lerp(startValue, endValue, amount)
        return (1 - amount) * startValue + amount * endValue
    end
end

if not Clamp then
    function Clamp(value, min, max)
        if value > max then
            return max
        elseif value < min then
            return min
        end
        return value
    end
end

if not CreateVector2D then
    local VectorMethods = {}
    local VectorMeta = {__index = VectorMethods}
    function VectorMethods:GetXY()
        return self.x, self.y
    end
    function VectorMethods:SetXY(x, y)
        self.x, self.y = x, y
    end
    function CreateVector2D(x, y)
        return setmetatable({x = x, y = y}, VectorMeta)
    end
end

if not FormatLargeNumber then
    --- 1234567 -> "1,234,567"
    function FormatLargeNumber(amount)
        local text = tostring(floor(tonumber(amount) or 0))
        local sign, digits = text:match("^(-?)(%d+)$")
        if not digits then
            return text
        end
        local formatted = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
        if formatted:sub(1, 1) == "," then
            formatted = formatted:sub(2)
        end
        return sign .. formatted
    end
end

if not GetCoinTextureString then
    local GOLD = "|TInterface\\MoneyFrame\\UI-GoldIcon:%d:%d:2:0|t"
    local SILVER = "|TInterface\\MoneyFrame\\UI-SilverIcon:%d:%d:2:0|t"
    local COPPER = "|TInterface\\MoneyFrame\\UI-CopperIcon:%d:%d:2:0|t"
    --- Money amount in copper -> "1[g] 20[s] 5[c]" with coin icons.
    function GetCoinTextureString(money, fontHeight)
        money = floor(tonumber(money) or 0)
        local size = fontHeight or 14
        local gold = floor(money / 10000)
        local silver = floor((money % 10000) / 100)
        local copper = money % 100
        local parts = {}
        if gold > 0 then
            parts[#parts + 1] = gold .. format(GOLD, size, size)
        end
        if silver > 0 then
            parts[#parts + 1] = silver .. format(SILVER, size, size)
        end
        if copper > 0 or #parts == 0 then
            parts[#parts + 1] = copper .. format(COPPER, size, size)
        end
        return table.concat(parts, " ")
    end
end

if not GetClassColor then
    --- Returns r, g, b and the "ffrrggbb" hex string of a class (by class file name, e.g. "MAGE").
    function GetClassColor(classFilename)
        local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFilename]
        if color then
            return color.r, color.g, color.b, format("ff%02x%02x%02x", color.r * 255, color.g * 255, color.b * 255)
        end
        return 1, 1, 1, "ffffffff"
    end
end

if not GetMaxPlayerLevel then
    function GetMaxPlayerLevel()
        local expansion = GetAccountExpansionLevel and GetAccountExpansionLevel() or 2
        return (MAX_PLAYER_LEVEL_TABLE and MAX_PLAYER_LEVEL_TABLE[expansion]) or 80
    end
end

if not GetServerTime then
    -- The 3.3.5a client cannot read the realm clock; local time is the closest available value.
    function GetServerTime()
        return time()
    end
end

if not GetTimePreciseSec then
    function GetTimePreciseSec()
        return debugprofilestop() / 1000
    end
end

if not Ambiguate then
    -- Same-realm names carry no realm suffix on this client, so there is nothing to strip.
    function Ambiguate(fullName)
        return fullName
    end
end

-------------------------------------------------------------------------------------------------
-- Race and class IDs
-------------------------------------------------------------------------------------------------
-- UnitRace and UnitClass return the race/class ID 3rd on later clients only.

local RACE_IDS = {Human = 1, Orc = 2, Dwarf = 3, NightElf = 4, Scourge = 5, Tauren = 6, Gnome = 7, Troll = 8,
                  Goblin = 9, BloodElf = 10, Draenei = 11}
local CLASS_IDS = {WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, DEATHKNIGHT = 6, SHAMAN = 7,
                   MAGE = 8, WARLOCK = 9, MONK = 10, DRUID = 11}

---@return string? raceName, string? raceFile, number? raceID
function QuestieCompat335.UnitRace(unit)
    local raceName, raceFile, raceID = UnitRace(unit)
    return raceName, raceFile, raceID or (raceFile and RACE_IDS[raceFile])
end

---@return string? className, string? classFile, number? classID
function QuestieCompat335.UnitClass(unit)
    local className, classFile, classID = UnitClass(unit)
    return className, classFile, classID or (classFile and CLASS_IDS[classFile])
end

--- UnitClassBase of later clients: the class file name ("PALADIN") and the class ID.
--- On 3.3.5a, UnitClassBase returns the localized class name and the file name instead.
---@return string? classFile, number? classID
function QuestieCompat335.UnitClassBase(unit)
    local _, classFile, classID = QuestieCompat335.UnitClass(unit)
    return classFile, classID
end

-------------------------------------------------------------------------------------------------
-- Achievements
-------------------------------------------------------------------------------------------------

--- True when the player earned the achievement. Later clients report this as GetAchievementInfo's 13th
--- return (wasEarnedByMe); 3.3.5a returns 11 values, and as its achievements are per character the 4th
--- (completed) means the same there.
---@param achievementID number
---@return boolean
function QuestieCompat335.IsAchievementEarnedByMe(achievementID)
    if QuestieCompat335.isLegacyClient then
        return select(4, GetAchievementInfo(achievementID)) and true or false
    end
    return select(13, GetAchievementInfo(achievementID)) and true or false
end

-------------------------------------------------------------------------------------------------
-- Groups
-------------------------------------------------------------------------------------------------

if not IsInRaid then
    function IsInRaid()
        return GetNumRaidMembers() > 0
    end
end

--- IsInGroup with its category. 3.3.5a has no instance groups (LFG groups are ordinary parties), so that
--- category is never true. Questie uses this one: another addon's IsInGroup may ignore the category
--- (CompactRaidFrame's does), which would send Questie's messages to INSTANCE_CHAT, a channel 3.3.5a lacks.
function QuestieCompat335.IsInGroup(category)
    if not QuestieCompat335.isLegacyClient then
        return IsInGroup(category)
    end
    if category == LE_PARTY_CATEGORY_INSTANCE then
        return false
    end
    return GetNumRaidMembers() > 0 or GetNumPartyMembers() > 0
end

if not IsInGroup then
    IsInGroup = QuestieCompat335.IsInGroup
end

if not GetNumGroupMembers then
    function GetNumGroupMembers()
        local raidMembers = GetNumRaidMembers()
        if raidMembers > 0 then
            return raidMembers
        end
        local partyMembers = GetNumPartyMembers()
        if partyMembers > 0 then
            return partyMembers + 1
        end
        return 0
    end
end

if not GetNumSubgroupMembers then
    function GetNumSubgroupMembers()
        return GetNumPartyMembers()
    end
end

if not UnitIsGroupLeader then
    function UnitIsGroupLeader(unit)
        if unit == "player" or UnitIsUnit(unit, "player") then
            return (IsRaidLeader() or IsPartyLeader()) and true or false
        end
        return UnitIsPartyLeader and UnitIsPartyLeader(unit) and true or false
    end
end

-------------------------------------------------------------------------------------------------
-- Widget methods
-------------------------------------------------------------------------------------------------
-- Methods are added to the shared method table of each widget type, and only when missing.
-- Every method here behaves like the real one; rendering hints that this client cannot honour
-- (pixel snapping, texel bias) are accepted and ignored.

local function _SetShown(self, shown)
    if shown then
        self:Show()
    else
        self:Hide()
    end
end

local function _GetSize(self)
    return self:GetWidth(), self:GetHeight()
end

local function _IsForbidden()
    return false
end

local function _IsMouseMotionFocus(self)
    return GetMouseFocus() == self
end

local function _SetResizeBounds(self, minWidth, minHeight, maxWidth, maxHeight)
    if minWidth then
        self:SetMinResize(minWidth, minHeight or minWidth)
    end
    if maxWidth then
        self:SetMaxResize(maxWidth, maxHeight or maxWidth)
    end
end

local function _Ignore()
end

local function _SetEnabled(self, enabled)
    if enabled then
        self:Enable()
    else
        self:Disable()
    end
end

local function _SetColorTexture(self, r, g, b, a)
    self:SetTexture(r, g, b, a or 1)
end

local function _GetUnboundedStringWidth(self)
    return self:GetStringWidth()
end

local function _GetPushedTextOffset()
    return 0, 0
end

local frameMethods = {
    SetShown = _SetShown,
    GetSize = _GetSize,
    IsForbidden = _IsForbidden,
    IsMouseMotionFocus = _IsMouseMotionFocus,
    SetResizeBounds = _SetResizeBounds,
    SetFixedFrameStrata = _Ignore,
    SetFixedFrameLevel = _Ignore,
}

local regionMethods = {
    SetShown = _SetShown,
    GetSize = _GetSize,
    IsForbidden = _IsForbidden,
    SetSnapToPixelGrid = _Ignore,
    SetTexelSnappingBias = _Ignore,
}

local function _AddMethods(object, methods)
    if not object then
        return
    end
    local meta = getmetatable(object)
    local index = meta and meta.__index
    if type(index) ~= "table" then
        return
    end
    for name, func in pairs(methods) do
        if object[name] == nil then
            -- rawset: a plain assignment to a widget type's method table can be dropped silently
            rawset(index, name, func)
        end
    end
end

do
    local probeParent = CreateFrame("Frame")
    probeParent:Hide()

    local frameTypes = {"Frame", "Button", "CheckButton", "EditBox", "ScrollFrame", "Slider", "StatusBar",
                        "Cooldown", "ColorSelect", "GameTooltip", "MessageFrame", "ScrollingMessageFrame",
                        "SimpleHTML", "Model", "PlayerModel"}
    for _, frameType in ipairs(frameTypes) do
        local ok, frame = pcall(CreateFrame, frameType, nil, probeParent)
        if ok and frame then
            _AddMethods(frame, frameMethods)
            if frame.Enable and frame.Disable then
                _AddMethods(frame, {SetEnabled = _SetEnabled})
            end
            if frameType == "Button" or frameType == "CheckButton" then
                _AddMethods(frame, {GetPushedTextOffset = _GetPushedTextOffset})
            end
            frame:Hide()
        end
    end

    local texture = probeParent:CreateTexture()
    _AddMethods(texture, regionMethods)
    _AddMethods(texture, {SetColorTexture = _SetColorTexture})

    local fontString = probeParent:CreateFontString()
    _AddMethods(fontString, regionMethods)
    _AddMethods(fontString, {GetUnboundedStringWidth = _GetUnboundedStringWidth})
end

-------------------------------------------------------------------------------------------------
-- Helpers used by Questie's own 3.3.5a code
-------------------------------------------------------------------------------------------------

--- FontString:GetWrappedWidth(): the width of the widest line once the text is wrapped.
--- This client's GetStringWidth is the width of the text on one line, so the widest wrapped line is
--- that or, when the text wraps, the font string's width.
---@param fontString FontString
---@return number
function QuestieCompat335.GetWrappedWidth(fontString)
    if fontString.GetWrappedWidth then
        return fontString:GetWrappedWidth()
    end
    local stringWidth = fontString:GetStringWidth() or 0
    local width = fontString:GetWidth() or 0
    if width > 0 and width < stringWidth then
        return width
    end
    return stringWidth
end

--- FontString:GetNumLines(): the number of lines the text is wrapped into.
---@param fontString FontString
---@return number
function QuestieCompat335.GetNumLines(fontString)
    if fontString.GetNumLines then
        return fontString:GetNumLines()
    end
    local _, fontSize = fontString:GetFont()
    local height = fontString:GetStringHeight()
    if fontSize and fontSize > 0 and height and height > 0 then
        local lineHeight = fontSize + (fontString:GetSpacing() or 0)
        return math.max(1, floor(height / lineHeight + 0.5))
    end
    return 1
end

--- Calls a widget method only when this client has it (atlas, mask, keyboard propagation, ...).
---@return any
function QuestieCompat335.Call(object, methodName, ...)
    local method = object and object[methodName]
    if method then
        return method(object, ...)
    end
end

--- Sound names for the numeric sound kit IDs used by newer code; this client's PlaySound takes names.
QuestieCompat335.Sounds = {
    [799] = "gsTitleOptionExit",            -- SOUNDKIT.GS_TITLE_OPTION_EXIT
    [841] = "igCharacterInfoTab",           -- SOUNDKIT.IG_CHARACTER_INFO_TAB
    [852] = "igMainMenuOption",             -- SOUNDKIT.IG_MAINMENU_OPTION
    [856] = "igMainMenuOptionCheckBoxOn",   -- SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
    [857] = "igMainMenuOptionCheckBoxOff",  -- SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF
    [882] = "igPlayerInviteDecline",        -- SOUNDKIT.IG_PLAYER_INVITE_DECLINE
    [1115] = "uChatScrollButton",           -- SOUNDKIT.U_CHAT_SCROLL_BUTTON
}

--- PlaySound for numeric sound kit IDs or names.
function QuestieCompat335.PlaySound(sound, ...)
    if type(sound) == "number" and QuestieCompat335.isLegacyClient then
        sound = QuestieCompat335.Sounds[sound]
    end
    if sound then
        PlaySound(sound, ...)
    end
end

--- Region code used where newer clients call GetCurrentRegion(); this client cannot tell.
function QuestieCompat335.GetCurrentRegion()
    if GetCurrentRegion then
        return GetCurrentRegion()
    end
    return 1
end

--- Splits a unit GUID into its kind and entry ID, for both GUID formats:
---   3.3.5a:  "0xF13000462D000A1B"  -> "Creature", 17965   (high 16 bits = type, next 24 bits = entry)
---   newer:   "Creature-0-4170-0-41-17965-000005A1B2" -> "Creature", 17965
--- Kinds: "Creature", "Vehicle", "GameObject", "Pet", "Player" (id nil), or nil for anything else.
---@param guid string?
---@return string? kind
---@return number? id
function QuestieCompat335.GetGuidInfo(guid)
    if type(guid) ~= "string" or guid == "" then
        return nil, nil
    end
    local prefix = guid:sub(1, 2)
    if prefix == "0x" or prefix == "0X" then
        local high = guid:sub(3, 5):upper()
        local kind
        if high == "F13" then
            kind = "Creature"
        elseif high == "F15" then
            kind = "Vehicle"
        elseif high == "F11" then
            kind = "GameObject"
        elseif high == "F14" then
            kind = "Pet"
        elseif high == "000" then
            return "Player", nil
        else
            return nil, nil
        end
        return kind, tonumber(guid:sub(7, 12), 16)
    end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind == "Player" then
        return kind, nil
    end
    return kind, tonumber(id)
end

--- NPC (or object) ID from a GUID of either format.
---@param guid string?
---@return number? npcId
function QuestieCompat335.GetNpcIdFromGuid(guid)
    local kind, id = QuestieCompat335.GetGuidInfo(guid)
    if kind == "Creature" or kind == "Vehicle" or kind == "GameObject" then
        return id
    end
    return nil
end

--- True when the GUID belongs to a creature (or vehicle) on either GUID format.
function QuestieCompat335.IsCreatureGuid(guid)
    local kind = QuestieCompat335.GetGuidInfo(guid)
    return kind == "Creature" or kind == "Vehicle"
end
