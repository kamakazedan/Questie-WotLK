-- Questie for World of Warcraft 3.3.5a: Questie's own versions of newer API namespaces.
--
-- Questie calls C_Map, C_QuestLog and C_Calendar, which this client does not have. Creating them as
-- globals could mislead other addons that test for them, so they live in QuestieCompat335 and the
-- Questie files that need them start with e.g. `local C_Map = QuestieCompat335.C_Map`.
--
-- This file also keeps the list of completed quests. The 3.3.5a client only reports it when asked
-- (QueryQuestsCompleted -> QUEST_QUERY_COMPLETE -> GetQuestsCompleted), so it is requested at login
-- and the turn-ins seen afterwards are added to it.

local QuestieCompat335 = QuestieCompat335
local type, tonumber, pairs, next = type, tonumber, pairs, next
local gmatch = string.gmatch

-- Entries (headers included) to scan; Questie scans the same range.
local MAX_QUEST_LOG_INDEX = 75

-- Questie's modules are created after this file loads, so they are looked up when first needed.
local function _Module(name)
    return QuestieLoader:ImportModule(name)
end

-------------------------------------------------------------------------------------------------
-- Quest log
-------------------------------------------------------------------------------------------------
-- On this client the quests under a collapsed header leave their place in the log: GetQuestLogTitle lists
-- them after the shown entries (index > GetNumQuestLogEntries()), without their header. So a walk up to the
-- first absent title sees every quest, and those indexes work with the other quest log functions.

local indexCache = {}       -- [questID] = quest log index
local indexCacheTime = -1
local indexCacheValid = false

local function _InvalidateIndexCache()
    indexCacheValid = false
end
QuestieCompat335.InvalidateQuestLogCache = _InvalidateIndexCache

local function _BuildIndexCache()
    local now = GetTime()
    if indexCacheValid and indexCacheTime == now then
        return indexCache
    end
    for questID in pairs(indexCache) do
        indexCache[questID] = nil
    end
    for index = 1, MAX_QUEST_LOG_INDEX do
        local title, _, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(index)
        if not title then
            break
        end
        if (not isHeader) and questID and questID > 0 and not indexCache[questID] then
            indexCache[questID] = index
        end
    end
    indexCacheTime = now
    indexCacheValid = true
    return indexCache
end

-- Anything that can reorder the quest log invalidates the cache, even within one frame.
for _, functionName in pairs({"ExpandQuestHeader", "CollapseQuestHeader", "AbandonQuest", "SortQuests"}) do
    if type(_G[functionName]) == "function" then
        hooksecurefunc(functionName, _InvalidateIndexCache)
    end
end
do
    -- registered before Questie's own handlers, so they see a fresh log
    local invalidateFrame = CreateFrame("Frame")
    invalidateFrame:RegisterEvent("QUEST_LOG_UPDATE")
    invalidateFrame:RegisterEvent("QUEST_ACCEPTED")
    invalidateFrame:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
    invalidateFrame:RegisterEvent("QUEST_WATCH_UPDATE")
    invalidateFrame:SetScript("OnEvent", _InvalidateIndexCache)
end

--- The quest ID of a quest log entry, or nil for headers and empty entries.
---@param questLogIndex number
---@return number? questID
function QuestieCompat335.GetQuestIdAtLogIndex(questLogIndex)
    if type(questLogIndex) ~= "number" or questLogIndex <= 0 then
        return nil
    end
    local title, _, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(questLogIndex)
    if title and (not isHeader) and questID and questID > 0 then
        return questID
    end
    return nil
end

--- The quest log index of a quest, or 0 when the quest log does not show it.
---@param questID number
---@return number questLogIndex
function QuestieCompat335.GetQuestLogIndexByID(questID)
    questID = tonumber(questID)
    if not questID then
        return 0
    end
    return _BuildIndexCache()[questID] or 0
end

--- Number of quests in the log, including those hidden under collapsed headers.
---@return number numQuests
function QuestieCompat335.GetNumQuests()
    local _, numQuests = GetNumQuestLogEntries()
    return numQuests or 0
end

--- Questie's (Classic) return order for GetQuestLogTitle:
--- title, level, questTag, isHeader, isCollapsed, isComplete, frequency, questID
--- The 3.3.5a client returns: title, level, questTag, suggestedGroup, isHeader, isCollapsed, isComplete, isDaily, questID
---@param questLogIndex number
function QuestieCompat335.GetQuestLogTitle(questLogIndex)
    local title, level, questTag, _, isHeader, isCollapsed, isComplete, isDaily, questID = GetQuestLogTitle(questLogIndex)
    if not title then
        return nil
    end
    if isHeader then
        questID = 0
    end
    -- frequency: 1 = daily (LE_QUEST_FREQUENCY_DAILY), 0 = not repeatable
    return title, level, questTag, isHeader and true or false, isCollapsed and true or false, isComplete,
        isDaily and 1 or 0, questID or 0
end

-- "Kobold Vermin slain: 3/8" -> 3, 8 (the last counter in the text; some locales put it first)
local function _ParseCounter(text)
    local fulfilled, required
    for a, b in gmatch(text, "(%d+)%s*/%s*(%d+)") do
        fulfilled, required = a, b
    end
    return tonumber(fulfilled), tonumber(required)
end

--- C_QuestLog.GetQuestObjectives for quests that the quest log shows. Other quests have no data on
--- this client and get an empty list.
---@param questID number
---@return table[] objectives
function QuestieCompat335.GetQuestObjectives(questID)
    local objectives = {}
    local questLogIndex = QuestieCompat335.GetQuestLogIndexByID(questID)
    if questLogIndex == 0 then
        return objectives
    end
    local numObjectives = GetNumQuestLeaderBoards(questLogIndex) or 0
    for objectiveIndex = 1, numObjectives do
        local text, objectiveType, finished = GetQuestLogLeaderBoard(objectiveIndex, questLogIndex)
        text = text or ""
        finished = finished and true or false
        local fulfilled, required = _ParseCounter(text)
        if not required then
            -- events, exploration and reputation objectives have no counter
            required = 1
            fulfilled = finished and 1 or 0
        end
        objectives[objectiveIndex] = {
            text = text,
            type = objectiveType,
            finished = finished,
            numFulfilled = fulfilled,
            numRequired = required,
        }
    end
    return objectives
end

--- HaveQuestData: this client has data for the quests in the quest log only.
---@param questID number
---@return boolean
function QuestieCompat335.HaveQuestData(questID)
    return QuestieCompat335.GetQuestLogIndexByID(questID) > 0
end

-------------------------------------------------------------------------------------------------
-- Completed quests
-------------------------------------------------------------------------------------------------

local completedQuests = {}      -- [questID] = true, from the server
local completedThisSession = {} -- [questID] = true, turn-ins seen since login
local completedCallbacks = {}
local queryPending = false
QuestieCompat335.completedQuestsReady = false

local completedFrame = CreateFrame("Frame")

local function _RequestCompletedQuests()
    if QueryQuestsCompleted then
        queryPending = true
        QueryQuestsCompleted()
    end
end

--- Asks the server for the completed quests. callback() runs once the list has arrived (at once if it already has).
---@param callback function?
function QuestieCompat335.RequestCompletedQuests(callback)
    if callback then
        if QuestieCompat335.completedQuestsReady then
            callback()
        else
            completedCallbacks[#completedCallbacks + 1] = callback
        end
    end
    if not queryPending then
        _RequestCompletedQuests()
    end
end

completedFrame:RegisterEvent("PLAYER_LOGIN")
completedFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
completedFrame:RegisterEvent("QUEST_QUERY_COMPLETE")
completedFrame:SetScript("OnEvent", function(self, event)
    if event == "QUEST_QUERY_COMPLETE" then
        queryPending = false
        local fresh = GetQuestsCompleted and GetQuestsCompleted({}) or {}
        for questID in pairs(completedThisSession) do
            fresh[questID] = true
        end
        completedQuests = fresh
        QuestieCompat335.completedQuestsReady = true
        local callbacks = completedCallbacks
        completedCallbacks = {}
        for _, callback in ipairs(callbacks) do
            -- The handler runs where the error happened, so the error frame can read its locals (see Compat335.lua).
            xpcall(callback, geterrorhandler())
        end
    elseif not QuestieCompat335.completedQuestsReady and not queryPending then
        _RequestCompletedQuests()
    end
end)

--- Questie saw this quest being turned in.
---@param questID number
function QuestieCompat335.MarkQuestCompleted(questID)
    if questID then
        completedQuests[questID] = true
        completedThisSession[questID] = true
    end
end

---@param questID number
---@return boolean
function QuestieCompat335.IsQuestFlaggedCompleted(questID)
    return completedQuests[questID] == true
end

--- A new table of the completed quests: [questID] = true. Copies into `target` when given.
---@param target table?
---@return table<number, boolean>
function QuestieCompat335.GetQuestsCompleted(target)
    local result = target or {}
    for questID in pairs(completedQuests) do
        result[questID] = true
    end
    return result
end

-------------------------------------------------------------------------------------------------
-- Quest frame
-------------------------------------------------------------------------------------------------

--- GetQuestID for the quest shown by the quest frame (offer, progress or reward), or 0.
--- This client does not tell; the quest is identified by its title, the quest log and the NPC.
---@return number questID
function QuestieCompat335.GetQuestID()
    local title = GetTitleText and GetTitleText()
    if type(title) ~= "string" or title == "" then
        return 0
    end
    local isOffer = QuestFrameDetailPanel and QuestFrameDetailPanel:IsVisible()
    if not isOffer then
        -- progress or reward: the quest is (normally) in the log
        for index = 1, MAX_QUEST_LOG_INDEX do
            local logTitle, _, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(index)
            if not logTitle then
                break
            end
            if (not isHeader) and logTitle == title and questID and questID > 0 then
                return questID
            end
        end
    end
    local QuestieDB = _Module("QuestieDB")
    local giverGuid = UnitGUID("questnpc") or UnitGUID("npc")
    if giverGuid and QuestieDB.GetQuestIDFromName then
        local questID = QuestieDB.GetQuestIDFromName(title, giverGuid, isOffer and true or false)
        if questID and questID > 0 then
            return questID
        end
        if not isOffer then
            questID = QuestieDB.GetQuestIDFromName(title, giverGuid, true)
            if questID and questID > 0 then
                return questID
            end
        end
    end
    return 0
end

-------------------------------------------------------------------------------------------------
-- Items
-------------------------------------------------------------------------------------------------
-- GetItemInfo does not ask the server for items the client has not seen; a tooltip does.

local scanTooltip

--- Asks the server for an item the client has not cached yet.
---@param itemID number
function QuestieCompat335.RequestItem(itemID)
    if not itemID or GetItemInfo(itemID) then
        return
    end
    if not scanTooltip then
        scanTooltip = CreateFrame("GameTooltip", "QuestieCompat335ScanTooltip", nil, "GameTooltipTemplate")
    end
    scanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanTooltip:SetHyperlink("item:" .. itemID .. ":0:0:0:0:0:0:0")
    scanTooltip:Hide()
end

---@param itemID number
---@return boolean
function QuestieCompat335.IsItemDataCachedByID(itemID)
    return GetItemInfo(itemID) ~= nil
end

--- Shows an item on a tooltip (GameTooltip:SetItemByID).
function QuestieCompat335.SetTooltipItemByID(tooltip, itemID)
    if tooltip.SetItemByID then
        return tooltip:SetItemByID(itemID)
    end
    return tooltip:SetHyperlink("item:" .. itemID .. ":0:0:0:0:0:0:0")
end

--- Shows a spell on a tooltip (GameTooltip:SetSpellByID).
function QuestieCompat335.SetTooltipSpellByID(tooltip, spellID)
    if tooltip.SetSpellByID then
        return tooltip:SetSpellByID(spellID)
    end
    return tooltip:SetHyperlink("spell:" .. spellID)
end

-- The parts of the Item mixin (Item:CreateFromItemID) Questie uses.
local ItemMethods = {}
local ItemMeta = {__index = ItemMethods}

function ItemMethods:GetItemID()
    return self.itemID
end

function ItemMethods:GetItemName()
    return (GetItemInfo(self.itemID))
end

function ItemMethods:IsItemDataCached()
    return GetItemInfo(self.itemID) ~= nil
end

--- Calls callback once the item's data is loaded (gives up after 30 seconds). Returns a cancel function.
function ItemMethods:ContinueWithCancelOnItemLoad(callback)
    local cancelled = false
    local function cancel()
        cancelled = true
    end
    if GetItemInfo(self.itemID) then
        callback()
        return cancel
    end
    QuestieCompat335.RequestItem(self.itemID)
    local itemID = self.itemID
    local tries = 0
    local ticker
    ticker = C_Timer.NewTicker(0.2, function()
        tries = tries + 1
        if cancelled then
            ticker:Cancel()
        elseif GetItemInfo(itemID) then
            ticker:Cancel()
            callback()
        elseif tries >= 150 then
            ticker:Cancel()
        elseif tries % 25 == 0 then
            QuestieCompat335.RequestItem(itemID)
        end
    end)
    return cancel
end

function ItemMethods:ContinueOnItemLoad(callback)
    self:ContinueWithCancelOnItemLoad(callback)
end

QuestieCompat335.Item = {
    CreateFromItemID = function(_, itemID)
        return setmetatable({itemID = itemID}, ItemMeta)
    end,
}

-------------------------------------------------------------------------------------------------
-- Dates
-------------------------------------------------------------------------------------------------

--- C_DateAndTime.GetCurrentCalendarTime: the realm's date and time.
---@return table calendarTime {monthDay, month, year, weekday, hour, minute}
function QuestieCompat335.GetCurrentCalendarTime()
    local weekday, month, day, year
    if CalendarGetDate then
        weekday, month, day, year = CalendarGetDate()
    end
    if not (month and day and year) then
        local now = date("*t")
        weekday, month, day, year = now.wday, now.month, now.day, now.year
    end
    local hour, minute = GetGameTime()
    return {
        monthDay = day,
        month = month,
        year = year,
        weekday = weekday,
        hour = hour or 0,
        minute = minute or 0,
    }
end

-------------------------------------------------------------------------------------------------
-- C_QuestLog
-------------------------------------------------------------------------------------------------

QuestieCompat335.C_QuestLog = {
    GetQuestObjectives = QuestieCompat335.GetQuestObjectives,
    IsQuestFlaggedCompleted = QuestieCompat335.IsQuestFlaggedCompleted,
    IsOnQuest = function(questID)
        if QuestieCompat335.GetQuestLogIndexByID(questID) > 0 then
            return true
        end
        -- quests under a collapsed header are still known to Questie's quest log cache
        local QuestLogCache = _Module("QuestLogCache")
        return QuestLogCache.TryGetQuest ~= nil and QuestLogCache.TryGetQuest(questID) ~= nil
    end,
    GetMaxNumQuestsCanAccept = function()
        return MAX_QUESTLOG_QUESTS or 25
    end,
}

-------------------------------------------------------------------------------------------------
-- C_Map (on top of Questie's 3.3.5a HereBeDragons)
-------------------------------------------------------------------------------------------------

local C_Map = {}
QuestieCompat335.C_Map = C_Map

-- The Vector2D of later clients, as far as Questie reads it (x and y).
local VectorMethods = {}
local VectorMeta = {__index = VectorMethods}
function VectorMethods:GetXY()
    return self.x, self.y
end
local function _CreateVector2D(x, y)
    return setmetatable({x = x, y = y}, VectorMeta)
end

-- Continent names until the client's own (localized) names are read
local CONTINENT_NAMES = {[1414] = "Kalimdor", [1415] = "Eastern Kingdoms", [1945] = "Outland", [113] = "Northrend"}

local areaNameCache = {}

--- Localized name of an AreaTable ID, from Questie's zone list and translations.
---@param areaID number
---@return string? name
function C_Map.GetAreaInfo(areaID)
    if not areaID then
        return nil
    end
    local cached = areaNameCache[areaID]
    if cached ~= nil then
        return cached or nil
    end
    local l10n = _Module("l10n")
    local lookup = l10n.zoneLookup
    if type(lookup) ~= "table" then
        return nil
    end
    local name
    for _, zones in pairs(lookup) do
        if type(zones) == "table" and zones[areaID] then
            name = zones[areaID]
            break
        end
    end
    if name and l10n.translations then
        local ok, translated = pcall(l10n, name)
        if ok and type(translated) == "string" then
            name = translated
        end
    end
    areaNameCache[areaID] = name or false
    return name
end

---@param uiMapID number
---@return table? mapInfo {mapID, name, mapType, parentMapID, flags}
function C_Map.GetMapInfo(uiMapID)
    local HBD = _Module("HBD")
    local data = uiMapID and HBD.mapData and HBD.mapData[uiMapID]
    if not data then
        return nil
    end
    local name
    if HBD.zoneIndexesScanned then
        name = data.name
    elseif data.areaId then
        name = C_Map.GetAreaInfo(data.areaId)
    elseif CONTINENT_NAMES[uiMapID] then
        local l10n = _Module("l10n")
        local ok, translated = pcall(l10n, CONTINENT_NAMES[uiMapID])
        name = ok and translated or CONTINENT_NAMES[uiMapID]
    end
    return {
        mapID = uiMapID,
        name = name or data.name or "",
        mapType = data.mapType,
        parentMapID = data.parent or 0,
        flags = 0,
    }
end

--- Only the player's map is known on this client.
---@param unit string
---@return number? uiMapID
function C_Map.GetBestMapForUnit(unit)
    if unit == "player" or (unit and UnitIsUnit(unit, "player")) then
        local uiMapID = _Module("HBD"):GetPlayerZone()
        return uiMapID
    end
    return nil
end

---@param uiMapID number
---@param unit string
---@return table? position {x, y} (0-1) on uiMapID
function C_Map.GetPlayerMapPosition(uiMapID, unit)
    if not (unit == "player" or (unit and UnitIsUnit(unit, "player"))) then
        return nil
    end
    local HBD = _Module("HBD")
    local x, y, playerMapID = HBD:GetPlayerZonePosition(true)
    if not x then
        return nil
    end
    if uiMapID and uiMapID ~= playerMapID then
        x, y = HBD:TranslateZoneCoordinates(x, y, playerMapID, uiMapID, true)
        if not x then
            return nil
        end
    end
    return _CreateVector2D(x, y)
end

---@param uiMapID number
---@param mapPosition table {x, y}
---@return number? instanceID
---@return table? worldPosition {x, y}
function C_Map.GetWorldPosFromMapPos(uiMapID, mapPosition)
    if not mapPosition then
        return nil, nil
    end
    local x, y, instance = _Module("HBD"):GetWorldCoordinatesFromZone(mapPosition.x, mapPosition.y, uiMapID)
    if not x then
        return nil, nil
    end
    return instance, _CreateVector2D(x, y)
end

--- Not available on this client.
function C_Map.GetMapChildrenInfo()
    return {}
end

-------------------------------------------------------------------------------------------------
-- World map frame
-------------------------------------------------------------------------------------------------
-- The 3.3.5a world map is WorldMapFrame with the map drawn on WorldMapButton; it has none of the
-- later map frame's methods (GetMapID, GetCanvas, ScrollContainer, ...).

--- The uiMapID the world map shows (WorldMapFrame:GetMapID()).
---@return number? uiMapID
function QuestieCompat335.GetWorldMapID()
    return _Module("HBD"):GetCurrentMapUiMapID()
end

--- The frame the map is drawn on (WorldMapFrame:GetCanvas()).
---@return Frame
function QuestieCompat335.GetWorldMapCanvas()
    return WorldMapButton
end

--- How many times bigger a zoom addon draws the map than the map would show without it: 1 without one.
--- Zoom addons for this client (BetterMaps-WotLK, Magnify-WotLK, Leatrix Maps) put the map into a
--- scroll frame, WorldMapScrollFrame, and scale the map inside it (WorldMapFrame.ScrollContainer:GetCanvasScale()).
---@return number
function QuestieCompat335.GetWorldMapZoom()
    local scroll = _G.WorldMapScrollFrame
    local canvas = WorldMapButton
    if not (scroll and canvas and scroll.GetEffectiveScale) then
        return 1
    end
    local parent = canvas:GetParent()
    while parent and parent ~= scroll do
        parent = parent:GetParent()
    end
    if not parent then
        return 1
    end
    local zoom = canvas:GetEffectiveScale() / scroll:GetEffectiveScale()
    if zoom > 0 and zoom < math.huge then
        return zoom
    end
    return 1
end

--- The part of the map in view in a zoom addon's scroll frame: 0-1 across and down the map, and past that where the
--- view goes past the map's edges (BetterMaps-WotLK's free camera shows the land round a zone's map). Nil without a
--- zoom addon, where the whole map shows and nothing past it.
---@return number? left
---@return number? top
---@return number? right
---@return number? bottom
function QuestieCompat335.GetWorldMapView()
    local scroll = _G.WorldMapScrollFrame
    local canvas = WorldMapButton
    if not (scroll and canvas and scroll.GetEffectiveScale) then
        return nil
    end
    local parent = canvas:GetParent()
    while parent and parent ~= scroll do
        parent = parent:GetParent()
    end
    if not parent then
        return nil
    end
    local canvasScale, scrollScale = canvas:GetEffectiveScale(), scroll:GetEffectiveScale()
    local canvasLeft, canvasTop, width, height = canvas:GetLeft(), canvas:GetTop(), canvas:GetWidth(), canvas:GetHeight()
    local left, top, right, bottom = scroll:GetLeft(), scroll:GetTop(), scroll:GetRight(), scroll:GetBottom()
    if not (canvasLeft and canvasTop and width and height and left and top and right and bottom)
            or not (canvasScale > 0 and scrollScale > 0 and width > 0 and height > 0) then
        return nil
    end
    width, height = width * canvasScale, height * canvasScale
    canvasLeft, canvasTop = canvasLeft * canvasScale, canvasTop * canvasScale
    return (left * scrollScale - canvasLeft) / width, (canvasTop - top * scrollScale) / height,
        (right * scrollScale - canvasLeft) / width, (canvasTop - bottom * scrollScale) / height
end

--- Whether the map Questie draws on is in view. BetterMaps-WotLK draws dungeon maps of its own over the game's map
--- and makes the game's map invisible meanwhile, with all that is drawn on it.
---@return boolean
function QuestieCompat335.IsWorldMapCanvasShown()
    return WorldMapButton:GetAlpha() > 0
end

--- A click handed on to the map by something drawn on it, as a click on the map itself: through the map's own
--- mouse-up script, which zoom addons replace (BetterMaps-WotLK leaves its dungeon maps on a right click).
---@param mouseButton string
function QuestieCompat335.ClickWorldMap(mouseButton)
    local onMouseUp = WorldMapButton:GetScript("OnMouseUp")
    if onMouseUp then
        onMouseUp(WorldMapButton, mouseButton)
    elseif WorldMapButton_OnClick then
        WorldMapButton_OnClick(WorldMapButton, mouseButton)
    end
end

--- BetterMaps-WotLK moves a zoomed map with a drag. A press on one of Questie's map icons is handed to it, so a drag
--- that starts on an icon still moves the map; a press that does not move the map stays a click on the icon.
---@param mouseButton string
---@return boolean handed The press went to the map
function QuestieCompat335.WorldMapIconMouseDown(mouseButton)
    local api = _G.BetterMapsWotLK
    if type(api) == "table" and type(api.IconMouseDown) == "function" then
        api.IconMouseDown(mouseButton)
        return true
    end
    return false
end

--- The end of a press handed to the map by WorldMapIconMouseDown.
---@return boolean dragged The press moved the map, so it is no click on the icon
function QuestieCompat335.WorldMapIconMouseUp()
    local api = _G.BetterMapsWotLK
    if type(api) == "table" and type(api.IconMouseUp) == "function" then
        return api.IconMouseUp() and true or false
    end
    return false
end

--- Cursor position on the map, 0-1 (WorldMapFrame.ScrollContainer:GetNormalizedCursorPosition()).
---@return number x
---@return number y
function QuestieCompat335.GetWorldMapCursorPosition()
    local canvas = WorldMapButton
    local x, y = GetCursorPosition()
    local scale = canvas:GetEffectiveScale()
    x, y = x / scale, y / scale
    local left, top = canvas:GetLeft(), canvas:GetTop()
    local width, height = canvas:GetWidth(), canvas:GetHeight()
    if not (left and top) or width == 0 or height == 0 then
        return 0, 0
    end
    return (x - left) / width, (top - y) / height
end

-------------------------------------------------------------------------------------------------
-- C_Calendar
-------------------------------------------------------------------------------------------------

local C_Calendar = {}
QuestieCompat335.C_Calendar = C_Calendar

function C_Calendar.OpenCalendar()
    if OpenCalendar then
        OpenCalendar()
    end
end

--- Moves the calendar's month, relative to the shown month.
---@param offset number
function C_Calendar.SetMonth(offset)
    if CalendarSetMonth then
        CalendarSetMonth(offset or 0)
    end
end

---@param offset number? months from the shown month
---@return table {month, year, numDays, firstWeekday}
function C_Calendar.GetMonthInfo(offset)
    local month, year, numDays, firstWeekday = CalendarGetMonth(offset or 0)
    return {month = month, year = year, numDays = numDays, firstWeekday = firstWeekday}
end

---@return number
function C_Calendar.GetNumDayEvents(offset, monthDay)
    return CalendarGetNumDayEvents and CalendarGetNumDayEvents(offset, monthDay) or 0
end

---@return table? {name, description, texture}
function C_Calendar.GetHolidayInfo(offset, monthDay, index)
    if not CalendarGetHolidayInfo then
        return nil
    end
    local name, description, texture = CalendarGetHolidayInfo(offset, monthDay, index)
    if not name then
        return nil
    end
    return {name = name, description = description, texture = texture}
end

-------------------------------------------------------------------------------------------------
-- Enum values Questie compares with
-------------------------------------------------------------------------------------------------

QuestieCompat335.Enum = {
    UIMapType = {Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5, Orphan = 6},
    ItemQuality = {Poor = 0, Common = 1, Standard = 1, Uncommon = 2, Good = 2, Rare = 3, Superior = 3,
                   Epic = 4, Legendary = 5, Artifact = 6, Heirloom = 7},
    ItemClass = {Consumable = 0, Container = 1, Weapon = 2, Gem = 3, Armor = 4, Reagent = 5, Projectile = 6,
                 Tradegoods = 7, Recipe = 9, Quiver = 11, Questitem = 12, Key = 13, Miscellaneous = 15, Glyph = 16},
}

-------------------------------------------------------------------------------------------------
-- Faction IDs
-------------------------------------------------------------------------------------------------
-- GetFactionInfo(index) on this client returns no faction ID (later clients return it 14th), and
-- Questie identifies factions by ID. The reputation factions of 3.3.5a, by their English names:

local FACTION_IDS = {
    -- Alliance
    ["Stormwind"] = 72, ["Ironforge"] = 47, ["Darnassus"] = 69, ["Gnomeregan Exiles"] = 54, ["Exodar"] = 930,
    ["Alliance"] = 469, ["Alliance Vanguard"] = 1037, ["Valiance Expedition"] = 1050, ["Explorers' League"] = 1068,
    ["The Frostborn"] = 1126, ["The Silver Covenant"] = 1094, ["Wintersaber Trainers"] = 589,
    ["Silverwing Sentinels"] = 890, ["Stormpike Guard"] = 730, ["The League of Arathor"] = 509,
    ["Honor Hold"] = 946, ["Kurenai"] = 978, ["Alliance Forces"] = 891,
    -- Horde
    ["Orgrimmar"] = 76, ["Thunder Bluff"] = 81, ["Undercity"] = 68, ["Darkspear Trolls"] = 530,
    ["Silvermoon City"] = 911, ["Horde"] = 67, ["Horde Expedition"] = 1052, ["Warsong Offensive"] = 1085,
    ["The Hand of Vengeance"] = 1067, ["The Taunka"] = 1064, ["The Sunreavers"] = 1124,
    ["Warsong Outriders"] = 889, ["Frostwolf Clan"] = 729, ["The Defilers"] = 510, ["Thrallmar"] = 947,
    ["The Mag'har"] = 941, ["Tranquillien"] = 922, ["Horde Forces"] = 892,
    -- Classic
    ["Argent Dawn"] = 529, ["Bloodsail Buccaneers"] = 87, ["Booty Bay"] = 21, ["Brood of Nozdormu"] = 910,
    ["Cenarion Circle"] = 609, ["Darkmoon Faire"] = 909, ["Everlook"] = 577, ["Gadgetzan"] = 369,
    ["Gelkis Clan Centaur"] = 92, ["Hydraxian Waterlords"] = 749, ["Magram Clan Centaur"] = 93,
    ["Ratchet"] = 470, ["Ravenholdt"] = 349, ["Shen'dralar"] = 809, ["Syndicate"] = 70,
    ["Thorium Brotherhood"] = 59, ["Timbermaw Hold"] = 576, ["Zandalar Tribe"] = 270,
    ["Wildhammer Clan"] = 471, ["Steamwheedle Cartel"] = 169,
    -- The Burning Crusade
    ["Ashtongue Deathsworn"] = 1012, ["Cenarion Expedition"] = 942, ["Keepers of Time"] = 989,
    ["Lower City"] = 1011, ["Netherwing"] = 1015, ["Ogri'la"] = 1038, ["Sha'tari Skyguard"] = 1031,
    ["Shattered Sun Offensive"] = 1077, ["Sporeggar"] = 970, ["The Aldor"] = 932, ["The Consortium"] = 933,
    ["The Scale of the Sands"] = 990, ["The Scryers"] = 934, ["The Sha'tar"] = 935, ["The Violet Eye"] = 967,
    ["Shattrath City"] = 936,
    -- Wrath of the Lich King
    ["Argent Crusade"] = 1106, ["Kirin Tor"] = 1090, ["Knights of the Ebon Blade"] = 1098,
    ["The Kalu'ak"] = 1073, ["The Wyrmrest Accord"] = 1091, ["The Sons of Hodir"] = 1119,
    ["Frenzyheart Tribe"] = 1104, ["The Oracles"] = 1105, ["The Ashen Verdict"] = 1156,
    ["Sholazar Basin"] = 1117, ["Wrath of the Lich King"] = 1097,
}

local factionNameById
local factionIdByLocalName

--- Faction ID for a (localized) faction name, or nil.
---@param name string
---@return number? factionID
function QuestieCompat335.GetFactionIdByName(name)
    if not name then
        return nil
    end
    if not factionIdByLocalName then
        factionIdByLocalName = {}
        -- Where the client can name faction IDs, learn the localized names too.
        if GetFactionInfoByID then
            for _, factionID in pairs(FACTION_IDS) do
                local localName = GetFactionInfoByID(factionID)
                if localName then
                    factionIdByLocalName[localName] = factionID
                end
            end
        end
    end
    return factionIdByLocalName[name] or FACTION_IDS[name]
end

--- English name of a faction ID, or nil.
---@param factionID number
---@return string? name
function QuestieCompat335.GetFactionNameById(factionID)
    if not factionNameById then
        factionNameById = {}
        for name, id in pairs(FACTION_IDS) do
            factionNameById[id] = name
        end
    end
    return factionNameById[factionID]
end

--- GetFactionInfo(index) with the faction ID added as 14th return, like later clients.
---@param index number
function QuestieCompat335.GetFactionInfo(index)
    local name, description, standingID, barMin, barMax, barValue, atWarWith, canToggleAtWar, isHeader,
        isCollapsed, hasRep, isWatched, isChild = GetFactionInfo(index)
    if not name then
        return nil
    end
    return name, description, standingID, barMin, barMax, barValue, atWarWith, canToggleAtWar, isHeader,
        isCollapsed, hasRep, isWatched, isChild, QuestieCompat335.GetFactionIdByName(name), false, false
end

--- GetFactionInfoByID: the client's own when it has one, else read from the reputation list.
---@param factionID number
function QuestieCompat335.GetFactionInfoByID(factionID)
    if GetFactionInfoByID then
        return GetFactionInfoByID(factionID)
    end
    for index = 1, GetNumFactions() do
        local name, description, standingID, barMin, barMax, barValue, atWarWith, canToggleAtWar, isHeader,
            isCollapsed, hasRep, isWatched, isChild, id = QuestieCompat335.GetFactionInfo(index)
        if id == factionID then
            return name, description, standingID, barMin, barMax, barValue, atWarWith, canToggleAtWar, isHeader,
                isCollapsed, hasRep, isWatched, isChild, id, false, false
        end
    end
    -- not discovered yet: only the name is known
    local englishName = QuestieCompat335.GetFactionNameById(factionID)
    if englishName then
        return englishName, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, factionID, false, false
    end
    return nil
end
