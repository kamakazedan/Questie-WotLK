-- HereBeDragons-Pins-2.0 for World of Warcraft 3.3.5a (Questie)
--
-- Questie's copy is a Questie module ("HBDPins"). The minimap part is upstream's logic. The world map
-- part of upstream is a data provider for the MapCanvas of later clients; the 3.3.5a world map has no
-- such canvas, so pins are drawn on an overlay frame on WorldMapButton instead. The provider/map objects
-- keep the small part of the canvas interface that Questie itself calls (GetMap, GetMapID,
-- EnumeratePinsByTemplate, RefreshAllData, OnMapChanged, ...).
--
-- Questie modification of HereBeDragons by Nevcairiel (https://github.com/Nevcairiel/HereBeDragons),
-- licensed under the same terms as the original.

---@class HBDPins
local pins = QuestieLoader:CreateModule("HBDPins")

---@type HBD
local HBD = QuestieLoader:ImportModule("HBD")

local MAP_TYPE = HBD.MapType

pins.updateFrame          = CreateFrame("Frame")

-- storage for minimap pins
pins.minimapPins          = {}
pins.activeMinimapPins    = {}
pins.minimapPinRegistry   = {}

-- and worldmap pins
pins.worldmapPins         = {}
pins.worldmapPinRegistry  = {}
pins.worldmapIconPins     = {} -- Questie modification: icon -> acquired pin

local WORLDMAP_PIN_TEMPLATE = "HereBeDragonsPins-Questie-WorldMapPin"
pins.worldmapPinTemplate  = WORLDMAP_PIN_TEMPLATE

-- store a reference to the active minimap object
pins.Minimap = Minimap

-- Data Constants
local WORLD_MAP_ID = HBD.WORLD_MAP_ID

-- upvalue lua api
local cos, sin, max = math.cos, math.sin, math.max
local type, pairs, next, tremove, tinsert = type, pairs, next, table.remove, table.insert

-- upvalue wow api
local GetPlayerFacing = GetPlayerFacing

-- upvalue data tables
local minimapPins         = pins.minimapPins
local activeMinimapPins   = pins.activeMinimapPins
local minimapPinRegistry  = pins.minimapPinRegistry

local worldmapPins        = pins.worldmapPins
local worldmapPinRegistry = pins.worldmapPinRegistry
local worldmapIconPins    = pins.worldmapIconPins

local minimap_size = {
    indoor = {
        [0] = 300, -- scale
        [1] = 240, -- 1.25
        [2] = 180, -- 5/3
        [3] = 120, -- 2.5
        [4] = 80,  -- 3.75
        [5] = 50,  -- 6
    },
    outdoor = {
        [0] = 466 + 2/3, -- scale
        [1] = 400,       -- 7/6
        [2] = 333 + 1/3, -- 1.4
        [3] = 266 + 2/6, -- 1.75
        [4] = 200,       -- 7/3
        [5] = 133 + 1/3, -- 3.5
    },
}

local minimap_shapes = {
    -- { upper-left, lower-left, upper-right, lower-right }
    ["SQUARE"]                = { false, false, false, false },
    ["CORNER-TOPLEFT"]        = { true,  false, false, false },
    ["CORNER-TOPRIGHT"]       = { false, false, true,  false },
    ["CORNER-BOTTOMLEFT"]     = { false, true,  false, false },
    ["CORNER-BOTTOMRIGHT"]    = { false, false, false, true },
    ["SIDE-LEFT"]             = { true,  true,  false, false },
    ["SIDE-RIGHT"]            = { false, false, true,  true },
    ["SIDE-TOP"]              = { true,  false, true,  false },
    ["SIDE-BOTTOM"]           = { false, true,  false, true },
    ["TRICORNER-TOPLEFT"]     = { true,  true,  true,  false },
    ["TRICORNER-TOPRIGHT"]    = { true,  false, true,  true },
    ["TRICORNER-BOTTOMLEFT"]  = { true,  true,  false, true },
    ["TRICORNER-BOTTOMRIGHT"] = { false, true,  true,  true },
}

local tableCache = setmetatable({}, {__mode='k'})

local function newCachedTable()
    local t = next(tableCache)
    if t then
        tableCache[t] = nil
    else
        t = {}
    end
    return t
end

local function recycle(t)
    tableCache[t] = true
end

-------------------------------------------------------------------------------------------
-- Minimap pin position logic

-- minimap rotation
local rotateMinimap = GetCVar("rotateMinimap") == "1"

-- is the minimap indoors or outdoors
local indoors = GetCVar("minimapZoom")+0 == pins.Minimap:GetZoom() and "outdoor" or "indoor"

local minimapPinCount, queueFullUpdate = 0, false
local minimapScale, minimapShape, mapRadius, minimapWidth, minimapHeight, mapSin, mapCos
local lastZoom, lastFacing, lastXY, lastYY

local function drawMinimapPin(pin, data)
    local xDist, yDist = lastXY - data.x, lastYY - data.y

    -- handle rotation
    if rotateMinimap then
        local dx, dy = xDist, yDist
        xDist = dx*mapCos - dy*mapSin
        yDist = dx*mapSin + dy*mapCos
    end

    -- adapt delta position to the map radius
    local diffX = xDist / mapRadius
    local diffY = yDist / mapRadius

    -- different minimap shapes
    local isRound = true
    if minimapShape and not (xDist == 0 or yDist == 0) then
        isRound = (xDist < 0) and 1 or 3
        if yDist < 0 then
            isRound = minimapShape[isRound]
        else
            isRound = minimapShape[isRound + 1]
        end
    end

    -- calculate distance from the center of the map
    local dist
    if isRound then
        dist = (diffX*diffX + diffY*diffY) / 0.9^2
    else
        dist = max(diffX*diffX, diffY*diffY) / 0.9^2
    end

    -- if distance > 1, then adapt node position to slide on the border
    if dist > 1 and data.floatOnEdge then
        dist = dist^0.5
        diffX = diffX/dist
        diffY = diffY/dist
    end

    -- Questie Modification.
    -- icons will now only float on edge if they have an opacity which is not 0 or if no texture exist.
    data.distanceFromMinimapCenter = dist
    if dist <= 1 or (data.floatOnEdge and ((pin.texture and pin.texture.a and pin.texture.a ~= 0) or pin.texture == nil)) then
        pin:Show()
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", pins.Minimap, "CENTER", diffX * minimapWidth, -diffY * minimapHeight)
        data.onEdge = (dist > 1)
    else
        pin:Hide()
        data.onEdge = nil
        pin.keep = nil
    end
end

local function UpdateMinimapPins(force)
    -- get the current player position
    local x, y, instanceID = HBD:GetPlayerWorldPosition()

    -- get data from the API for calculations
    local zoom = pins.Minimap:GetZoom()
    local diffZoom = zoom ~= lastZoom

    -- for rotating minimap support
    local facing
    if rotateMinimap then
        facing = GetPlayerFacing()
    else
        facing = lastFacing
    end

    -- check for all values to be available (instances do not report coordinates)
    if not x or not y or (rotateMinimap and not facing) then
        minimapPinCount = 0
        for pin in pairs(activeMinimapPins) do
            pin:Hide()
            activeMinimapPins[pin] = nil
        end
        return
    end

    local newScale = pins.Minimap:GetScale()
    if minimapScale ~= newScale then
        minimapScale = newScale
        force = true
    end

    if x ~= lastXY or y ~= lastYY or diffZoom or facing ~= lastFacing or force then
        -- minimap information
        minimapShape = GetMinimapShape and minimap_shapes[GetMinimapShape() or "ROUND"]
        minimapWidth = pins.Minimap:GetWidth() / 2
        minimapHeight = pins.Minimap:GetHeight() / 2
        mapRadius = minimap_size[indoors][zoom] / 2

        -- update upvalues for icon placement
        lastZoom = zoom
        lastFacing = facing
        lastXY, lastYY = x, y

        if rotateMinimap then
            mapSin = sin(facing)
            mapCos = cos(facing)
        end

        for pin, data in pairs(minimapPins) do
            if data.instanceID == instanceID and math.abs(x-data.x) + math.abs(y-data.y) < 500 then -- questie specific fix
                activeMinimapPins[pin] = data
                data.keep = true
                -- draw the pin (this may reset data.keep if outside of the map)
                drawMinimapPin(pin, data)
            end
        end

        minimapPinCount = 0
        for pin, data in pairs(activeMinimapPins) do
            if not data.keep then
                pin:Hide()
                activeMinimapPins[pin] = nil
            else
                minimapPinCount = minimapPinCount + 1
                data.keep = nil
            end
        end
    end
end

local function UpdateMinimapIconPosition()

    -- get the current map  zoom
    local zoom = pins.Minimap:GetZoom()
    local diffZoom = zoom ~= lastZoom
    -- if the map zoom changed, run a full update sweep
    if diffZoom then
        UpdateMinimapPins()
        return
    end

    -- we have no active minimap pins, just return early
    if minimapPinCount == 0 then return end

    local x, y = HBD:GetPlayerWorldPosition()

    -- for rotating minimap support
    local facing
    if rotateMinimap then
        facing = GetPlayerFacing()
    else
        facing = lastFacing
    end

    -- check for all values to be available
    if not x or not y or (rotateMinimap and not facing) then
        UpdateMinimapPins()
        return
    end

    local refresh
    local newScale = pins.Minimap:GetScale()
    if minimapScale ~= newScale then
        minimapScale = newScale
        refresh = true
    end

    if x ~= lastXY or y ~= lastYY or facing ~= lastFacing or refresh then
        -- update radius of the map
        mapRadius = minimap_size[indoors][zoom] / 2
        -- update upvalues for icon placement
        lastXY, lastYY = x, y
        lastFacing = facing

        if rotateMinimap then
            mapSin = sin(facing)
            mapCos = cos(facing)
        end

        -- iterate all nodes and check if they are still in range of our minimap display
        for pin, data in pairs(activeMinimapPins) do
            -- update the position of the node
            drawMinimapPin(pin, data)
        end
    end
end

local function UpdateMinimapZoom()
    local zoom = pins.Minimap:GetZoom()
    if GetCVar("minimapZoom") == GetCVar("minimapInsideZoom") then
        pins.Minimap:SetZoom(zoom < 2 and zoom + 1 or zoom - 1)
    end
    indoors = GetCVar("minimapZoom")+0 == pins.Minimap:GetZoom() and "outdoor" or "indoor"
    pins.Minimap:SetZoom(zoom)
end

-------------------------------------------------------------------------------------------
-- World map

-- Pins are placed on this frame, which covers the map part of the world map and follows its size.
local canvas = CreateFrame("Frame", "QuestieHBDWorldMapCanvas", WorldMapButton)
canvas:SetAllPoints(WorldMapButton)
pins.worldmapCanvas = canvas

local function SetCanvasFrameLevel()
    canvas:SetFrameLevel((WORLDMAP_POI_FRAMELEVEL or 100) + 5)
end
SetCanvasFrameLevel()

local activePins = {} -- pin frame -> true
local freePins = {}

pins.worldmapProviderPin = {}
local worldmapProviderPin = pins.worldmapProviderPin

pins.worldmapProvider = {forceUpdate = false} -- forceUpdate: Put into worldmapProvider to allow addons to force update from outside of HBD.
local worldmapProvider = pins.worldmapProvider

--- Stand-in for the map canvas of later clients
local map = {}
pins.worldmapMap = map

local currentMapID

function map:GetMapID()
    return currentMapID
end

function map:GetCanvas()
    return canvas
end

function map:EnumeratePinsByTemplate()
    return next, activePins
end

function map:AcquirePin(_, icon, x, y, frameLevelType)
    local pin = tremove(freePins)
    if not pin then
        pin = CreateFrame("Frame", nil, canvas)
        pin:SetWidth(1)
        pin:SetHeight(1)
        pin:EnableMouse(false)
    end
    for key, value in pairs(worldmapProviderPin) do
        pin[key] = value
    end
    activePins[pin] = true
    pin.pinTemplate = WORLDMAP_PIN_TEMPLATE
    pin.owningMap = map
    pin:OnAcquired(icon, x, y, frameLevelType)
    return pin
end

function map:RemovePin(pin)
    if not activePins[pin] then
        return
    end
    activePins[pin] = nil
    pin:Hide()
    pin:ClearAllPoints()
    pin:OnReleased()
    pin.pinTemplate = nil
    pin.owningMap = nil
    tinsert(freePins, pin)
end

function map:RemoveAllPinsByTemplate()
    for pin in pairs(activePins) do
        self:RemovePin(pin)
    end
end

-- provider base API
function worldmapProvider:GetMap()
    return map
end

function worldmapProvider:RemoveAllData()
    map:RemoveAllPinsByTemplate(WORLDMAP_PIN_TEMPLATE)
end

-- Questie modification: look up the pin directly instead of scanning all pins, which made bulk removal O(n^2)
function worldmapProvider:RemovePinByIcon(icon)
    local pin = worldmapIconPins[icon]
    if pin and pin.icon == icon then
        map:RemovePin(pin)
    end
end

function worldmapProvider:RemovePinsByRef(ref)
    for pin in map:EnumeratePinsByTemplate(WORLDMAP_PIN_TEMPLATE) do
        if pin.icon and worldmapPinRegistry[ref][pin.icon] then
            map:RemovePin(pin)
        end
    end
end

-- Questie modification
local lastUiMapId = -1;
function worldmapProvider:RefreshAllData()
    local mapId = map:GetMapID()
    if(lastUiMapId ~= mapId or worldmapProvider.forceUpdate) then
        self:RemoveAllData()
        if WorldMapFrame:IsShown() then
            for icon, data in pairs(worldmapPins) do
                self:HandlePin(icon, data)
            end
        end
        lastUiMapId = mapId;
        worldmapProvider.forceUpdate = false;
    end
end

--- Called when the shown map changes; Questie's HBDHooks wraps this to rescale icons afterwards.
function worldmapProvider:OnMapChanged()
    self:RefreshAllData()
end

function worldmapProvider:HandlePin(icon, data)
    -- Questie modification: an icon owns at most one pin, so re-adding must not leave the old one behind
    self:RemovePinByIcon(icon)

    if not WorldMapFrame:IsShown() then return end

    local uiMapID = map:GetMapID()

    -- check for a valid map
    if not uiMapID or not HBD.mapData[uiMapID] then return end

    -- Questie modification
    if (Questie.db.profile.hideIconsOnContinents == true) and (HBD.mapData[uiMapID].mapType == MAP_TYPE.Continent or uiMapID == WORLD_MAP_ID) or (uiMapID ~= data.uiMapID and data.worldMapShowFlag == HBD_PINS_WORLDMAP_SHOW_CURRENT) then
        icon:Hide();
        return;
    elseif(uiMapID == data.uiMapID and data.worldMapShowFlag == HBD_PINS_WORLDMAP_SHOW_CURRENT) then
        icon:Show();
    end

    local x, y
    if uiMapID == WORLD_MAP_ID then
        -- The Azeroth world map has no coordinates on this client. Questie's own world map icons (UiMapID 947)
        -- already carry world map coordinates.
        if icon.UiMapID == WORLD_MAP_ID and icon.x and icon.y then
            x, y = icon.x / 100, icon.y / 100
        else
            return
        end
    else
        if uiMapID ~= data.uiMapID then
            local mapType = HBD.mapData[uiMapID].mapType
            if not data.uiMapID then
                if mapType == MAP_TYPE.Continent and data.worldMapShowFlag >= HBD_PINS_WORLDMAP_SHOW_CONTINENT then
                    -- pass
                elseif mapType ~= MAP_TYPE.Zone and mapType ~= MAP_TYPE.Dungeon and mapType ~= MAP_TYPE.Micro then
                    -- fail
                    return
                end
            else
                local show = true -- Questie fix to show icons in neighbour areas
                local parentMapID = HBD.mapData[data.uiMapID] and HBD.mapData[data.uiMapID].parent
                while parentMapID and HBD.mapData[parentMapID] do
                    if parentMapID == uiMapID then
                        local parentMapType = HBD.mapData[parentMapID].mapType
                        -- show on any parent zones if they are normal zones
                        if data.worldMapShowFlag >= HBD_PINS_WORLDMAP_SHOW_PARENT and
                            (parentMapType == MAP_TYPE.Zone or parentMapType == MAP_TYPE.Dungeon or parentMapType == MAP_TYPE.Micro) then
                            show = true
                        -- show on the continent
                        elseif data.worldMapShowFlag >= HBD_PINS_WORLDMAP_SHOW_CONTINENT and
                            parentMapType == MAP_TYPE.Continent then
                            show = true
                        elseif data.worldMapShowFlag == HBD_PINS_WORLDMAP_SHOW_CURRENT then
                            -- Questie modification
                            show = false
                        end
                        break
                    else
                        parentMapID = HBD.mapData[parentMapID].parent
                    end
                end

                if not show then return end
            end
        end

        if uiMapID == data.uiMapID and data.zoneX then
            -- on its own map the pin keeps the coordinates it was added with
            x, y = data.zoneX, data.zoneY
        else
            -- translate coordinates
            x, y = HBD:GetZoneCoordinatesFromWorldInstance(data.x, data.y, data.instanceID, uiMapID)
        end
    end
    if x and y then
        map:AcquirePin(WORLDMAP_PIN_TEMPLATE, icon, x, y, data.frameLevelType)
    end
end

--  map pin base API
function worldmapProviderPin:OnAcquired(icon, x, y)
    self:SetFrameLevel(canvas:GetFrameLevel() + 1)
    self:ClearAllPoints()
    self:SetPoint("CENTER", canvas, "TOPLEFT", x * WorldMapButton:GetWidth(), -y * WorldMapButton:GetHeight())
    self:Show()

    self.icon = icon
    worldmapIconPins[icon] = self -- Questie modification
    icon:SetParent(self)
    -- re-parenting resets the frame level; keep Questie's draw order (QuestieMap.utils.SetDrawOrder)
    icon:SetFrameLevel(self:GetFrameLevel() + 1 + (icon.questieDrawOrder or 0))
    icon:ClearAllPoints()
    icon:SetPoint("CENTER", self, "CENTER")
    icon:Show()
end

function worldmapProviderPin:OnReleased()
    if self.icon then
        if worldmapIconPins[self.icon] == self then -- Questie modification
            worldmapIconPins[self.icon] = nil
        end
        self.icon:Hide()
        self.icon:SetParent(UIParent)
        self.icon:ClearAllPoints()
        self.icon = nil
    end
end

--- Works out which map the world map shows and redraws the pins when it changed.
local function UpdateWorldMap(force)
    if not WorldMapFrame:IsShown() then
        return
    end
    local mapID = HBD:GetCurrentMapUiMapID()
    if mapID ~= currentMapID or force then
        currentMapID = mapID
        worldmapProvider:OnMapChanged()
    end
end
pins.UpdateWorldMap = UpdateWorldMap

WorldMapFrame:HookScript("OnShow", function()
    SetCanvasFrameLevel()
    worldmapProvider.forceUpdate = true
    UpdateWorldMap(true)
end)
WorldMapFrame:HookScript("OnHide", function()
    worldmapProvider:RemoveAllData()
    currentMapID = nil
    lastUiMapId = -1
end)

-- The map changes size (full screen, quest list, windowed); icons are rescaled for the new size.
local function OnWorldMapResized()
    SetCanvasFrameLevel()
    worldmapProvider.forceUpdate = true
    UpdateWorldMap(true)
end
for _, functionName in ipairs({"WorldMap_ToggleSizeUp", "WorldMap_ToggleSizeDown", "WorldMapFrame_SetFullMapView", "WorldMapFrame_SetQuestMapView"}) do
    if type(_G[functionName]) == "function" then
        hooksecurefunc(functionName, OnWorldMapResized)
    end
end
if type(WorldMapFrame_ResetFrameLevels) == "function" then
    hooksecurefunc("WorldMapFrame_ResetFrameLevels", SetCanvasFrameLevel)
end

-- map event handling
local function UpdateMinimap()
    UpdateMinimapZoom()
    UpdateMinimapPins()
end

local last_update = 0
local function OnUpdateHandler(frame, elapsed)
    last_update = last_update + elapsed

    -- skip updates while the minimap is hidden
    if pins.Minimap and not pins.Minimap:IsVisible() then return end

    -- check for a full update every second, so pins coming in range get properly rendered
    if last_update > 1 or queueFullUpdate then
        UpdateMinimapPins(queueFullUpdate)
        last_update = 0
        queueFullUpdate = false
    else
        UpdateMinimapIconPosition()
    end
end
pins.updateFrame:SetScript("OnUpdate", OnUpdateHandler)

local function OnEventHandler(frame, event, ...)
    if event == "CVAR_UPDATE" then
        local cvar, value = ...
        if cvar == "rotateMinimap" or cvar == "ROTATE_MINIMAP" then
            rotateMinimap = (value == "1")
            queueFullUpdate = true
        end
    elseif event == "MINIMAP_UPDATE_ZOOM" then
        UpdateMinimap()
    elseif event == "PLAYER_LOGIN" then
        -- recheck cvars after login
        rotateMinimap = GetCVar("rotateMinimap") == "1"
    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdateMinimap()
        UpdateWorldMap(true)
    elseif event == "WORLD_MAP_UPDATE" then
        UpdateWorldMap()
    end
end

pins.updateFrame:SetScript("OnEvent", OnEventHandler)
pins.updateFrame:UnregisterAllEvents()
pins.updateFrame:RegisterEvent("CVAR_UPDATE")
pins.updateFrame:RegisterEvent("MINIMAP_UPDATE_ZOOM")
pins.updateFrame:RegisterEvent("PLAYER_LOGIN")
pins.updateFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
pins.updateFrame:RegisterEvent("WORLD_MAP_UPDATE")

HBD.RegisterCallback(pins, "PlayerZoneChanged", UpdateMinimap)


--- Add a icon to the minimap (x/y world coordinate version)
function pins:AddMinimapIconWorld(ref, icon, instanceID, x, y, floatOnEdge)
    if not ref then
        error("HBDPins: AddMinimapIconWorld: 'ref' must not be nil", 2)
    end
    if type(icon) ~= "table" or not icon.SetPoint then
        error("HBDPins: AddMinimapIconWorld: 'icon' must be a frame", 2)
    end
    if type(instanceID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
        error("HBDPins: AddMinimapIconWorld: 'instanceID', 'x' and 'y' must be numbers", 2)
    end

    if not minimapPinRegistry[ref] then
        minimapPinRegistry[ref] = {}
    end

    minimapPinRegistry[ref][icon] = true

    local t = minimapPins[icon] or newCachedTable()
    t.instanceID = instanceID
    t.x = x
    t.y = y
    t.floatOnEdge = floatOnEdge
    t.uiMapID = nil
    t.showInParentZone = nil

    minimapPins[icon] = t
    queueFullUpdate = true

    icon:SetParent(pins.Minimap)
end

--- Add a icon to the minimap (UiMapID zone coordinate version)
function pins:AddMinimapIconMap(ref, icon, uiMapID, x, y, showInParentZone, floatOnEdge)
    if not ref then
        error("HBDPins: AddMinimapIconMap: 'ref' must not be nil", 2)
    end
    if type(icon) ~= "table" or not icon.SetPoint then
        error("HBDPins: AddMinimapIconMap: 'icon' must be a frame", 2)
    end
    if type(uiMapID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
        error("HBDPins: AddMinimapIconMap: 'uiMapID', 'x' and 'y' must be numbers", 2)
    end

    -- convert to world coordinates and use our known adding function
    local xCoord, yCoord, instanceID = HBD:GetWorldCoordinatesFromZone(x, y, uiMapID)
    if not xCoord then return end

    self:AddMinimapIconWorld(ref, icon, instanceID, xCoord, yCoord, floatOnEdge)

    -- store extra information
    minimapPins[icon].uiMapID = uiMapID
    minimapPins[icon].showInParentZone = showInParentZone
end

--- Check if a floating minimap icon is on the edge of the map
function pins:IsMinimapIconOnEdge(icon)
    if not icon then return false end
    local data = minimapPins[icon]
    if not data then return nil end

    return data.onEdge
end

--- Remove a minimap icon
function pins:RemoveMinimapIcon(ref, icon)
    if not ref or not icon or not minimapPinRegistry[ref] then return end
    minimapPinRegistry[ref][icon] = nil
    if minimapPins[icon] then
        recycle(minimapPins[icon])
        minimapPins[icon] = nil
        activeMinimapPins[icon] = nil
    end
    icon:Hide()
end

--- Remove all minimap icons belonging to your addon (as tracked by "ref")
function pins:RemoveAllMinimapIcons(ref)
    if not ref or not minimapPinRegistry[ref] then return end
    for icon in pairs(minimapPinRegistry[ref]) do
        recycle(minimapPins[icon])
        minimapPins[icon] = nil
        activeMinimapPins[icon] = nil
        icon:Hide()
    end
    wipe(minimapPinRegistry[ref])
end

--- Set the minimap object to position the pins on.
function pins:SetMinimapObject(minimapObject)
    pins.Minimap = minimapObject or Minimap
    for pin in pairs(minimapPins) do
        pin:SetParent(pins.Minimap)
    end
    UpdateMinimapPins(true)
end

--- Questie addition: the view minimap icons are placed with, so other minimap drawings line up with them.
-- @return radius Yards from the minimap's center to its edge; nil for an unknown zoom level
-- @return rotating true while the minimap turns with the player
function pins:GetMinimapView()
    local size = minimap_size[indoors][pins.Minimap:GetZoom()]
    return size and size / 2, rotateMinimap
end

-- world map constants
-- show worldmap pin only on zone map (Questie modification)
HBD_PINS_WORLDMAP_SHOW_CURRENT   = -1
-- show worldmap pin on its parent zone map (if any)
HBD_PINS_WORLDMAP_SHOW_PARENT    = 1
-- show worldmap pin on the continent map
HBD_PINS_WORLDMAP_SHOW_CONTINENT = 2
-- show worldmap pin on the continent and world map
HBD_PINS_WORLDMAP_SHOW_WORLD     = 3

--- Add a icon to the world map (x/y world coordinate version)
function pins:AddWorldMapIconWorld(ref, icon, instanceID, x, y, showFlag, frameLevel)
    if not ref then
        error("HBDPins: AddWorldMapIconWorld: 'ref' must not be nil", 2)
    end
    if type(icon) ~= "table" or not icon.SetPoint then
        error("HBDPins: AddWorldMapIconWorld: 'icon' must be a frame", 2)
    end
    if type(instanceID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
        error("HBDPins: AddWorldMapIconWorld: 'instanceID', 'x' and 'y' must be numbers", 2)
    end
    if showFlag ~= nil and type(showFlag) ~= "number" then
        error("HBDPins: AddWorldMapIconWorld: 'showFlag' must be a number (or nil)", 2)
    end

    if not worldmapPinRegistry[ref] then
        worldmapPinRegistry[ref] = {}
    end

    worldmapPinRegistry[ref][icon] = true

    local t = worldmapPins[icon] or newCachedTable()
    t.instanceID = instanceID
    t.x = x
    t.y = y
    t.uiMapID = nil
    t.zoneX = nil
    t.zoneY = nil
    t.worldMapShowFlag = showFlag or 0
    t.frameLevelType = frameLevel

    worldmapPins[icon] = t

    worldmapProvider:HandlePin(icon, t)
end

--- Add a icon to the world map (uiMapID zone coordinate version)
function pins:AddWorldMapIconMap(ref, icon, uiMapID, x, y, showFlag, frameLevel)
    if not ref then
        error("HBDPins: AddWorldMapIconMap: 'ref' must not be nil", 2)
    end
    if type(icon) ~= "table" or not icon.SetPoint then
        error("HBDPins: AddWorldMapIconMap: 'icon' must be a frame", 2)
    end
    if type(uiMapID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
        error("HBDPins: AddWorldMapIconMap: 'uiMapID', 'x' and 'y' must be numbers", 2)
    end
    if showFlag ~= nil and type(showFlag) ~= "number" then
        error("HBDPins: AddWorldMapIconMap: 'showFlag' must be a number (or nil)", 2)
    end

    -- convert to world coordinates
    local xCoord, yCoord, instanceID = HBD:GetWorldCoordinatesFromZone(x, y, uiMapID)
    if not xCoord then
        -- Maps without a size on this client (dungeon floors, ...) still show their own pins.
        if not HBD.mapData[uiMapID] then
            return
        end
        xCoord, yCoord, instanceID = x, y, -2 - uiMapID
    end

    if not worldmapPinRegistry[ref] then
        worldmapPinRegistry[ref] = {}
    end

    worldmapPinRegistry[ref][icon] = true

    local t = worldmapPins[icon] or newCachedTable()
    t.instanceID = instanceID
    t.x = xCoord
    t.y = yCoord
    t.uiMapID = uiMapID
    t.zoneX = x
    t.zoneY = y
    t.worldMapShowFlag = showFlag or 0
    t.frameLevelType = frameLevel

    worldmapPins[icon] = t

    worldmapProvider:HandlePin(icon, t)
end

--- Remove a worldmap icon
function pins:RemoveWorldMapIcon(ref, icon)
    if not ref or not icon or not worldmapPinRegistry[ref] then return end
    worldmapPinRegistry[ref][icon] = nil
    if worldmapPins[icon] then
        recycle(worldmapPins[icon])
        worldmapPins[icon] = nil
    end
    worldmapProvider:RemovePinByIcon(icon)

    worldmapProvider.forceUpdate = true -- Questie modification
end

--- Remove all worldmap icons belonging to your addon (as tracked by "ref")
function pins:RemoveAllWorldMapIcons(ref)
    if not ref or not worldmapPinRegistry[ref] then return end
    for icon in pairs(worldmapPinRegistry[ref]) do
        recycle(worldmapPins[icon])
        worldmapPins[icon] = nil
    end
    worldmapProvider:RemovePinsByRef(ref)
    wipe(worldmapPinRegistry[ref])

    worldmapProvider.forceUpdate = true -- Questie modification
end

--- Return the angle and distance from the player to the specified pin
-- @return angle, distance where angle is in radians and distance in yards
function pins:GetVectorToIcon(icon)
    if not icon then return nil, nil end
    local data = minimapPins[icon] or worldmapPins[icon]
    if not data then return nil, nil end

    local x, y, instance = HBD:GetPlayerWorldPosition()
    if not x or not y or instance ~= data.instanceID then return nil end

    return HBD:GetWorldVector(instance, x, y, data.x, data.y)
end
