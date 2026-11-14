-- HereBeDragons-2.0 for World of Warcraft 3.3.5a (Questie)
--
-- Questie's copy of HereBeDragons is a Questie module ("HBD"). Upstream HereBeDragons is built on the
-- map API of later clients (C_Map, uiMapIDs, UnitPosition). The 3.3.5a client has none of that, so this
-- file provides the same functions Questie uses on top of the 3.3.5a world map API:
--
--   * maps are still identified by Questie's (Wrath Classic) uiMapIDs;
--   * map sizes come from QuestieCompat335.ZoneData (Compat335/ZoneData335.lua), in yards;
--   * "world" coordinates are yards relative to each continent map (x grows westwards, y northwards,
--     the same orientation HereBeDragons uses), which is all that distances and the minimap need;
--   * the player's position is read with GetPlayerMapPosition on his current zone map.
--
-- Questie modification of HereBeDragons by Nevcairiel (https://github.com/Nevcairiel/HereBeDragons),
-- licensed under the same terms as the original.

---@class HBD
local HereBeDragons = QuestieLoader:CreateModule("HBD")

local CBH = LibStub("CallbackHandler-1.0")

HereBeDragons.eventFrame       = CreateFrame("Frame")

HereBeDragons.mapData          = {} -- [uiMapID] = { width, height, left, top, instance=, name=, mapType=, parent=, mapFile= }
HereBeDragons.worldMapData     = {} -- the Azeroth world map has no coordinates on this client
HereBeDragons.transforms       = {}
HereBeDragons.instanceZones    = {}
HereBeDragons.callbacks        = CBH:New(HereBeDragons, nil, nil, false)

-- The map types of later clients (Enum.UIMapType), which this client does not have.
local MAP_TYPE = {Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5, Orphan = 6}
HereBeDragons.MapType = MAP_TYPE

-- Data Constants
local COSMIC_MAP_ID = 946
local WORLD_MAP_ID = 947
HereBeDragons.COSMIC_MAP_ID = COSMIC_MAP_ID
HereBeDragons.WORLD_MAP_ID = WORLD_MAP_ID

-- Lua upvalues
local PI2 = math.pi * 2
local atan2 = math.atan2
local pairs, unpack, type = pairs, unpack, type

-- WoW API upvalues
local GetTime = GetTime
local GetPlayerMapPosition, GetMapInfo = GetPlayerMapPosition, GetMapInfo
local GetCurrentMapContinent, GetCurrentMapZone, GetCurrentMapDungeonLevel = GetCurrentMapContinent, GetCurrentMapZone, GetCurrentMapDungeonLevel

local mapData          = HereBeDragons.mapData
local worldMapData     = HereBeDragons.worldMapData

-- mapFile (GetMapInfo) -> uiMapID
local mapFileToUiMapId = {}
HereBeDragons.mapFileToUiMapId = mapFileToUiMapId
-- continent index (GetCurrentMapContinent) -> uiMapID
local continentIndexToUiMapId = {}
HereBeDragons.continentIndexToUiMapId = continentIndexToUiMapId
-- uiMapID -> { continentIndex, zoneIndex } for SetMapZoom; filled by ScanZoneIndexes
local zoneIndexByUiMapId = {}
HereBeDragons.zoneIndexByUiMapId = zoneIndexByUiMapId
-- mapFile -> { [dungeonLevel] = uiMapID }
local mapFileLevels = {}

-------------------------------------------------------------------------------------------------
-- Map data
-------------------------------------------------------------------------------------------------

local function BuildMapData()
    local zoneData = QuestieCompat335.ZoneData

    for index, continent in pairs(zoneData.continents) do
        mapData[continent.uiMapId] = {
            continent.width, continent.height, 0, 0,
            instance = continent.instance,
            name = continent.mapFile,
            mapType = MAP_TYPE.Continent,
            parent = WORLD_MAP_ID,
            mapFile = continent.mapFile,
            continentIndex = index,
        }
        mapFileToUiMapId[continent.mapFile] = continent.uiMapId
        continentIndexToUiMapId[index] = continent.uiMapId
    end

    for mapFile, zone in pairs(zoneData.zones) do
        local continentIndex, uiMapId, areaId, width, height, xOffset, yOffset = unpack(zone)
        local continent = zoneData.continents[continentIndex]
        local extra = zoneData.extraContinents[continentIndex]
        mapData[uiMapId] = {
            width, height, -xOffset, -yOffset,
            instance = continent and continent.instance or (extra and extra.instance) or -1,
            name = mapFile,
            mapType = MAP_TYPE.Zone,
            parent = continent and continent.uiMapId or nil,
            mapFile = mapFile,
            areaId = areaId,
            continentIndex = continentIndex,
        }
        mapFileToUiMapId[mapFile] = uiMapId
    end

    for mapFile, levels in pairs(zoneData.levels) do
        local baseId = mapFileToUiMapId[mapFile]
        local base = baseId and mapData[baseId]
        if base then
            mapFileLevels[mapFile] = levels
            for _, uiMapId in pairs(levels) do
                if not mapData[uiMapId] then
                    mapData[uiMapId] = {
                        base[1], base[2], base[3], base[4],
                        instance = base.instance,
                        name = mapFile,
                        mapType = MAP_TYPE.Dungeon,
                        parent = baseId,
                        mapFile = mapFile,
                        continentIndex = base.continentIndex,
                    }
                end
            end
        end
    end

    mapData[WORLD_MAP_ID] = {0, 0, 0, 0, instance = -1, name = WORLD_MAP or "Azeroth", mapType = MAP_TYPE.World, parent = COSMIC_MAP_ID}
    mapData[COSMIC_MAP_ID] = {0, 0, 0, 0, instance = -1, name = "Cosmic", mapType = MAP_TYPE.Cosmic}
end
BuildMapData()

--- The uiMapID of the map the client's world map is currently set to, or nil for maps without data.
---@return number|nil uiMapID
function HereBeDragons:GetCurrentMapUiMapID()
    local mapFile = GetMapInfo()
    if not mapFile then
        local continent = GetCurrentMapContinent()
        if continent == -1 then
            return COSMIC_MAP_ID
        end
        return WORLD_MAP_ID
    end
    local levels = mapFileLevels[mapFile]
    if levels then
        local level = GetCurrentMapDungeonLevel()
        if level and levels[level] then
            return levels[level]
        end
    end
    return mapFileToUiMapId[mapFile]
end

--- Learns the localized zone names and the SetMapZoom indexes of all zone maps.
--- Changes the client's map, so only call it while the world map is closed.
function HereBeDragons:ScanZoneIndexes()
    if WorldMapFrame and WorldMapFrame:IsShown() then
        return false
    end
    local continentNames = {GetMapContinents()}
    for continentIndex = 1, #continentNames do
        local uiMapId = continentIndexToUiMapId[continentIndex]
        if uiMapId and mapData[uiMapId] then
            mapData[uiMapId].name = continentNames[continentIndex]
            zoneIndexByUiMapId[uiMapId] = {continentIndex, 0}
        end
        local zoneNames = {GetMapZones(continentIndex)}
        for zoneIndex = 1, #zoneNames do
            SetMapZoom(continentIndex, zoneIndex)
            local mapFile = GetMapInfo()
            local zoneUiMapId = mapFile and mapFileToUiMapId[mapFile]
            if zoneUiMapId and mapData[zoneUiMapId] then
                mapData[zoneUiMapId].name = zoneNames[zoneIndex]
                zoneIndexByUiMapId[zoneUiMapId] = {continentIndex, zoneIndex}
            end
        end
    end
    SetMapToCurrentZone()
    HereBeDragons.zoneIndexesScanned = true
    return true
end

--- Sets the client's world map to a uiMapID, when that map is known. Returns true on success.
---@param uiMapID number
---@return boolean
function HereBeDragons:SetMapToUiMapID(uiMapID)
    if uiMapID == WORLD_MAP_ID then
        SetMapZoom(0)
        return true
    end
    local indexes = zoneIndexByUiMapId[uiMapID]
    local data = mapData[uiMapID]
    if (not indexes) and data and data.mapType == MAP_TYPE.Dungeon and data.parent then
        indexes = zoneIndexByUiMapId[data.parent]
    end
    if not indexes then
        return false
    end
    if indexes[2] == 0 then
        SetMapZoom(indexes[1])
    else
        SetMapZoom(indexes[1], indexes[2])
    end
    return true
end

-------------------------------------------------------------------------------------------------
-- Player position
-------------------------------------------------------------------------------------------------

local currentPlayerUIMapID, currentPlayerUIMapType
local playerZoneX, playerZoneY -- position on currentPlayerUIMapID, 0-1
local positionTime = -1

-- SetMapToCurrentZone is not called every frame: only after zone changes, when something else moved
-- the (hidden) map, and once a second for changes no event reports (such as dungeon levels).
local MAP_RESET_INTERVAL = 1
local mapDirty = true
local lastMapReset = -MAP_RESET_INTERVAL
local lastResetMapFile, lastResetLevel

local function MarkMapDirty()
    mapDirty = true
end
HereBeDragons.MarkMapDirty = MarkMapDirty

--- Reads the player's zone and position from the client's map.
--- While the world map is open the user's view is left alone and the position is only read when the
--- shown map is the player's own map.
local function ReadPlayerPosition()
    local now = GetTime()
    if now == positionTime then
        return
    end
    positionTime = now

    local mapShown = WorldMapFrame and WorldMapFrame:IsShown()
    if not mapShown then
        if mapDirty or now - lastMapReset >= MAP_RESET_INTERVAL
                or GetMapInfo() ~= lastResetMapFile or GetCurrentMapDungeonLevel() ~= lastResetLevel then
            SetMapToCurrentZone()
            mapDirty = false
            lastMapReset = now
            lastResetMapFile = GetMapInfo()
            lastResetLevel = GetCurrentMapDungeonLevel()
        end
    end

    local x, y = GetPlayerMapPosition("player")
    if (not x) or (x == 0 and y == 0) then
        if not mapShown then
            -- Instances and other maps without coordinates
            local uiMapID = HereBeDragons:GetCurrentMapUiMapID()
            if uiMapID ~= currentPlayerUIMapID then
                currentPlayerUIMapID = uiMapID
                currentPlayerUIMapType = uiMapID and mapData[uiMapID] and mapData[uiMapID].mapType or nil
            end
            playerZoneX, playerZoneY = nil, nil
        end
        return
    end

    local uiMapID = HereBeDragons:GetCurrentMapUiMapID()
    if mapShown then
        -- Only take positions from zone maps; the player is on this map since the position is not 0,0.
        local data = uiMapID and mapData[uiMapID]
        if not (data and (data.mapType == MAP_TYPE.Zone or data.mapType == MAP_TYPE.Dungeon)) then
            return
        end
    end

    currentPlayerUIMapID = uiMapID
    currentPlayerUIMapType = uiMapID and mapData[uiMapID] and mapData[uiMapID].mapType or nil
    playerZoneX, playerZoneY = x, y
end
HereBeDragons.ReadPlayerPosition = ReadPlayerPosition

local function UpdateCurrentPosition()
    local previousMapID = currentPlayerUIMapID
    positionTime = -1
    ReadPlayerPosition()
    if currentPlayerUIMapID ~= previousMapID then
        HereBeDragons.callbacks:Fire("PlayerZoneChanged", currentPlayerUIMapID, currentPlayerUIMapType)
    end
end
HereBeDragons.UpdateCurrentPosition = UpdateCurrentPosition

local function OnEvent(frame, event, ...)
    MarkMapDirty()
    if event == "PLAYER_ENTERING_WORLD" and not HereBeDragons.zoneIndexesScanned then
        HereBeDragons:ScanZoneIndexes()
    end
    UpdateCurrentPosition()
end

HereBeDragons.eventFrame:SetScript("OnEvent", OnEvent)
HereBeDragons.eventFrame:UnregisterAllEvents()
HereBeDragons.eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
HereBeDragons.eventFrame:RegisterEvent("ZONE_CHANGED")
HereBeDragons.eventFrame:RegisterEvent("ZONE_CHANGED_INDOORS")
HereBeDragons.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

-- The zone events do not cover every map change (e.g. dungeon levels), so check once a second.
do
    local elapsedTotal = 0
    HereBeDragons.eventFrame:SetScript("OnUpdate", function(_, elapsed)
        elapsedTotal = elapsedTotal + elapsed
        if elapsedTotal >= 1 then
            elapsedTotal = 0
            UpdateCurrentPosition()
        end
    end)
end

-------------------------------------------------------------------------------------------------
-- Public API (same as upstream HereBeDragons-2.0)
-------------------------------------------------------------------------------------------------

--- Return the localized name of the map, or nil
-- @param uiMapID uiMapID of the map
function HereBeDragons:GetLocalizedMap(uiMapID)
    return mapData[uiMapID] and mapData[uiMapID].name or nil
end

--- Get the size of the zone
-- @param uiMapID uiMapID of the zone
-- @return width, height of the zone, in yards
function HereBeDragons:GetZoneSize(uiMapID)
    local data = mapData[uiMapID]
    if not data then return 0, 0 end

    return data[1], data[2]
end

--- Get a list of all map IDs
-- @return array-style table with all known/valid map IDs
function HereBeDragons:GetAllMapIDs()
    local t = {}
    for id in pairs(mapData) do
        table.insert(t, id)
    end
    return t
end

--- Convert local/point coordinates to world coordinates in yards
-- @param x X position in 0-1 point coordinates
-- @param y Y position in 0-1 point coordinates
-- @param zone uiMapID of the zone
function HereBeDragons:GetWorldCoordinatesFromZone(x, y, zone)
    local data = mapData[zone]
    if not data or data[1] == 0 or data[2] == 0 then return nil, nil, nil end
    if not x or not y then return nil, nil, nil end

    local width, height, left, top = data[1], data[2], data[3], data[4]
    x, y = left - width * x, top - height * y

    return x, y, data.instance
end

--- Not available on this client: there are no world map coordinates.
function HereBeDragons:GetWorldCoordinatesFromAzerothWorldMap()
    return nil, nil, nil
end

--- Convert world coordinates to local/point zone coordinates
-- @deprecated Use GetZoneCoordinatesFromWorldInstance instead
function HereBeDragons:GetZoneCoordinatesFromWorld(x, y, zone, allowOutOfBounds)
    local data = mapData[zone]
    if not data or data[1] == 0 or data[2] == 0 then return nil, nil end
    if not x or not y then return nil, nil end

    return HereBeDragons:GetZoneCoordinatesFromWorldInstance(x, y, data.instance, zone, allowOutOfBounds)
end

--- Convert world coordinates to local/point zone coordinates
-- @param x Global X position
-- @param y Global Y position
-- @param instance World instance of the X/Y coordinates
-- @param zone uiMapID of the target zone
-- @param allowOutOfBounds Allow coordinates to go beyond the current map (ie. outside of the 0-1 range), otherwise nil will be returned
function HereBeDragons:GetZoneCoordinatesFromWorldInstance(x, y, instance, zone, allowOutOfBounds)
    local data = mapData[zone]
    if not data or data[1] == 0 or data[2] == 0 then return nil, nil end
    if not x or not y then return nil, nil end
    if data.instance ~= instance then return nil, nil end

    local width, height, left, top = data[1], data[2], data[3], data[4]
    x, y = (left - x) / width, (top - y) / height

    -- verify the coordinates fall into the zone
    if not allowOutOfBounds and (x < 0 or x > 1 or y < 0 or y > 1) then return nil, nil end

    return x, y
end

--- Not available on this client: there are no world map coordinates.
function HereBeDragons:GetAzerothWorldMapCoordinatesFromWorld()
    return nil, nil
end

--- Translate zone coordinates from one zone to another
-- @param x X position in 0-1 point coordinates, relative to the origin zone
-- @param y Y position in 0-1 point coordinates, relative to the origin zone
-- @param oZone Origin Zone, uiMapID
-- @param dZone Destination Zone, uiMapID
-- @param allowOutOfBounds Allow coordinates to go beyond the current map (ie. outside of the 0-1 range), otherwise nil will be returned
function HereBeDragons:TranslateZoneCoordinates(x, y, oZone, dZone, allowOutOfBounds)
    if oZone == dZone then return x, y end

    local xCoord, yCoord, instance = HereBeDragons:GetWorldCoordinatesFromZone(x, y, oZone)
    if not xCoord then return nil, nil end

    return HereBeDragons:GetZoneCoordinatesFromWorldInstance(xCoord, yCoord, instance, dZone, allowOutOfBounds)
end

--- Return the distance from an origin position to a destination position in the same instance/continent.
-- @return distance, deltaX, deltaY
function HereBeDragons:GetWorldDistance(instanceID, oX, oY, dX, dY)
    if not oX or not oY or not dX or not dY then return nil, nil, nil end
    local deltaX, deltaY = dX - oX, dY - oY
    return (deltaX * deltaX + deltaY * deltaY)^0.5, deltaX, deltaY
end

--- Return the distance between two points on the same continent
-- @return distance, deltaX, deltaY in yards
function HereBeDragons:GetZoneDistance(oZone, oX, oY, dZone, dX, dY)
    local oInstance, dInstance
    oX, oY, oInstance = HereBeDragons:GetWorldCoordinatesFromZone(oX, oY, oZone)
    if not oX then return nil, nil, nil end

    dX, dY, dInstance = HereBeDragons:GetWorldCoordinatesFromZone(dX, dY, dZone)
    if not dX then return nil, nil, nil end

    if oInstance ~= dInstance then return nil, nil, nil end

    return HereBeDragons:GetWorldDistance(oInstance, oX, oY, dX, dY)
end

--- Return the angle and distance from an origin position to a destination position in the same instance/continent.
-- @return angle, distance where angle is in radians and distance in yards
function HereBeDragons:GetWorldVector(instanceID, oX, oY, dX, dY)
    local distance, deltaX, deltaY = HereBeDragons:GetWorldDistance(instanceID, oX, oY, dX, dY)
    if not distance then return nil, nil end

    -- calculate the angle from deltaY and deltaX
    local angle = atan2(-deltaX, deltaY)

    -- normalize the angle
    if angle > 0 then
        angle = PI2 - angle
    else
        angle = -angle
    end

    return angle, distance
end

--- Get the current world position of the specified unit. Only the player is supported on this client.
-- @return x, y, instanceID
function HereBeDragons:GetUnitWorldPosition(unitId)
    if unitId == "player" or (UnitIsUnit and UnitIsUnit(unitId, "player")) then
        return HereBeDragons:GetPlayerWorldPosition()
    end
    return nil, nil, nil
end

--- Get the current world position of the player
-- @return x, y, instanceID
-- Questie calls this one as a plain function (HBD.GetPlayerWorldPosition()), so it must not use self.
function HereBeDragons:GetPlayerWorldPosition()
    ReadPlayerPosition()
    if not (currentPlayerUIMapID and playerZoneX) then
        local data = currentPlayerUIMapID and mapData[currentPlayerUIMapID]
        return nil, nil, data and data.instance or nil
    end
    return HereBeDragons:GetWorldCoordinatesFromZone(playerZoneX, playerZoneY, currentPlayerUIMapID)
end

--- Get the current zone and level of the player
-- @return uiMapID, mapType
function HereBeDragons:GetPlayerZone()
    ReadPlayerPosition()
    return currentPlayerUIMapID, currentPlayerUIMapType
end

--- Get the current position of the player on a zone level
-- @param allowOutOfBounds Allow coordinates to go beyond the current map (ie. outside of the 0-1 range), otherwise nil will be returned
-- @return x, y, uiMapID, mapType
function HereBeDragons:GetPlayerZonePosition(allowOutOfBounds)
    ReadPlayerPosition()
    if not (currentPlayerUIMapID and playerZoneX) then return nil, nil, nil, nil end
    if not allowOutOfBounds and (playerZoneX < 0 or playerZoneX > 1 or playerZoneY < 0 or playerZoneY > 1) then
        return nil, nil, nil, nil
    end
    return playerZoneX, playerZoneY, currentPlayerUIMapID, currentPlayerUIMapType
end

if IsLoggedIn() then
    UpdateCurrentPosition()
end
