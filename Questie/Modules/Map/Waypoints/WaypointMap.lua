-- luacheck: read globals issecretvalue
---Draws the paths of the shown world map onto its canvas, and finds the path under the cursor.
---@class WaypointMap
local WaypointMap = QuestieLoader:CreateModule("WaypointMap")

---@type QuestieWaypoints
local QuestieWaypoints = QuestieLoader:ImportModule("QuestieWaypoints")
---@type WaypointGeometry
local WaypointGeometry = QuestieLoader:ImportModule("WaypointGeometry")
---@type WaypointRenderer
local WaypointRenderer = QuestieLoader:ImportModule("WaypointRenderer")
---@type WaypointHover
local WaypointHover = QuestieLoader:ImportModule("WaypointHover")
---@type QuestieCompat
local QuestieCompat = QuestieLoader:ImportModule("QuestieCompat")
---@type HBD
local HBD = QuestieLoader:ImportModule("HBD")
---@type HBDPins
local HBDPins = QuestieLoader:ImportModule("HBDPins")

-- Below Questie's icons, which start at 2016 (QuestieMap.utils.SetDrawOrder).
local FRAME_LEVEL = 2015

-- 3.3.5a: the map is drawn on WorldMapButton (no ScrollContainer), zoomed only by a zoom addon. Questie's icons
-- sit on a canvas at WORLDMAP_POI_FRAMELEVEL + 5 (HereBeDragons-Pins), so paths go just below it.
local LEGACY = QuestieCompat335.isLegacyClient
if LEGACY then
    FRAME_LEVEL = (WORLDMAP_POI_FRAMELEVEL or 100) + 4
end

local function _GetMapID()
    if LEGACY then
        return QuestieCompat335.GetWorldMapID()
    end
    return WorldMapFrame:GetMapID()
end

local function _GetCanvas()
    if LEGACY then
        return QuestieCompat335.GetWorldMapCanvas()
    end
    return WorldMapFrame:GetCanvas()
end

local function _GetCanvasScale()
    if LEGACY then
        return QuestieCompat335.GetWorldMapZoom()
    end
    return WorldMapFrame.ScrollContainer:GetCanvasScale()
end

---A route drawn on the current map, in canvas units with y down.
---@class WaypointMapView : WaypointHitTarget
---@field path WaypointPath The copy of the route that shows.
---@field view WaypointView
---@field mapId number The map, and its canvas size, the view was drawn for.
---@field width number
---@field height number
---@field alpha number

---@type WaypointCanvasRenderer?
local renderer
---@type Frame?
local driver
---@type table<string, WaypointMapView> By route.
local views = {}
---@type WaypointMapView[]
local visible = {}
-- Paths, their visibility or their highlight changed since the last draw.
local dirty = true
-- The map and canvas size drawn for. shownScale is the canvas scale line widths are drawn for;
-- currentScale the latest one. shownReach: the reach round a zoom addon's view drawn for (3.3.5a).
local shownMapId, shownWidth, shownHeight, shownScale, currentScale, shownReach
-- Cursor at the last hover check, in canvas units; nil off the canvas.
local cursorX, cursorY

-- Drawing

---Line width and hover reach are in map UI units: both are divided by the canvas scale, so they
---keep their size on screen while zooming.
---@param path WaypointPath
---@param alpha number
---@return WaypointStyle
local function _Style(path, alpha)
    local profile = Questie.db.profile
    return {thickness = profile.waypointWidth / shownScale, color = QuestieWaypoints.Color(path), alpha = alpha,
        frameLevel = FRAME_LEVEL, hoverRadius = profile.waypointDebugHover and WaypointHover.Radius() / shownScale or nil}
end

---3.3.5a: whether a path of another zone draws on the shown zone's map, past its edges. A zoom addon's view can take in
---the land round a zone's map (BetterMaps-WotLK's free camera), and Questie's icons of the zones round it show there,
---within reach of the view (HereBeDragons-Pins): their paths do as well, those of zones on the same continent that
---come within that reach.
---@param path WaypointPath
---@return boolean
local function _ShowsPastEdges(path)
    local reach = LEGACY and HBDPins.GetWorldMapReach() or nil
    local shown, own = HBD.mapData[shownMapId], HBD.mapData[path.uiMapId]
    if not (reach and shown and own and shown.mapType == HBD.MapType.Zone and own.mapType == HBD.MapType.Zone) then
        return false
    end
    local bounds = path.worldBounds
    local x1, y1 = HBD:GetZoneCoordinatesFromWorldInstance(bounds[1], bounds[2], path.instanceId, shownMapId, true)
    local x2, y2 = HBD:GetZoneCoordinatesFromWorldInstance(bounds[3], bounds[4], path.instanceId, shownMapId, true)
    if not (x1 and x2) then return false end
    return math.max(x1, x2) >= reach[1] and math.min(x1, x2) <= reach[3]
        and math.max(y1, y2) >= reach[2] and math.min(y1, y2) <= reach[4]
end

---A path's points on the shown map, in canvas units: on its own map from its percentages, past the edges of
---another zone's map from its world yards.
---@param path WaypointPath
---@return table[]
local function _CanvasPoints(path)
    local canvasPoints = {}
    if path.uiMapId == shownMapId then
        for i, point in ipairs(path.points) do
            canvasPoints[i] = {x = point.x * shownWidth / 100, y = point.y * shownHeight / 100}
        end
    else
        for i, point in ipairs(path.world) do
            local x, y = HBD:GetZoneCoordinatesFromWorldInstance(point.x, point.y, path.instanceId, shownMapId, true)
            canvasPoints[i] = {x = x * shownWidth, y = y * shownHeight}
        end
    end
    return canvasPoints
end

---Paths draw on their own map, and on 3.3.5a past the edges of a zone's map round theirs where a zoom addon
---shows that land. Several icons can own the same patrol, such as an NPC who starts three quests: each copy
---would draw the route again, darker where they stack. A route draws once, as its highlighted copy, or else
---its most visible one.
---@return table<string, {path: WaypointPath, alpha: number, rank: number}> By route.
local function _ShownRoutes()
    local routes = {}
    if not (shownWidth > 0 and shownHeight > 0) then return routes end
    for path in pairs(QuestieWaypoints.paths) do
        local alpha = (path.uiMapId == shownMapId or _ShowsPastEdges(path)) and QuestieWaypoints.WorldMapAlpha(path)
        if alpha then
            -- The highlighted copy first, then the most visible one: alpha is at most 1.
            local rank = alpha + (QuestieWaypoints.IsHighlighted(path) and 2 or 0)
            local best = routes[path.route]
            if not best or rank > best.rank then
                routes[path.route] = {path = path, alpha = alpha, rank = rank}
            end
        end
    end
    return routes
end

---Draws every route that shows on the current map and releases the others' views.
local function _Refresh()
    dirty = false
    local routes = _ShownRoutes()
    local list = {}
    for route, shown in pairs(routes) do
        local path, alpha = shown.path, shown.alpha
        local entry = views[route]
        if not entry or entry.mapId ~= shownMapId or entry.width ~= shownWidth or entry.height ~= shownHeight then
            local canvasPoints = _CanvasPoints(path)
            local view = renderer:Draw(entry and entry.view, {canvasPoints}, _Style(path, alpha))
            entry = {view = view, mapId = shownMapId, width = shownWidth, height = shownHeight,
                points = canvasPoints, bounds = WaypointGeometry.Bounds(canvasPoints)}
            views[route] = entry
        else
            renderer:Restyle(entry.view, _Style(path, alpha))
        end
        entry.path, entry.alpha = path, alpha
        entry.view:Show()
        list[#list + 1] = entry
    end
    for route, entry in pairs(views) do
        if not routes[route] then
            renderer:Release(entry.view)
            views[route] = nil
        end
    end
    visible = list
end

-- Hover

---Cursor in canvas units; nil off the canvas or while restricted. Blizzard clamps the
---normalized position to the canvas edges, so the canvas itself must be under the cursor.
---@return number?, number?
local function _ReadCursor()
    if not _GetCanvas():IsMouseOver() then return nil, nil end
    local x, y
    if LEGACY then
        x, y = QuestieCompat335.GetWorldMapCursorPosition()
    else
        x, y = WorldMapFrame.ScrollContainer:GetNormalizedCursorPosition()
    end
    if issecretvalue and (issecretvalue(x) or issecretvalue(y)) then return nil, nil end
    if type(x) ~= "number" or type(y) ~= "number" or x ~= x or y ~= y then return nil, nil end
    return x * shownWidth, y * shownHeight
end

-- Paths take no mouse input. They count as hovered only over the bare map, so Questie's icons,
-- Blizzard's pins and other UI on top win.
local function _IsCursorOnMap()
    if LEGACY then
        -- not while BetterMaps-WotLK shows a dungeon map of its own over it
        return QuestieCompat.GetMouseFocus() == WorldMapButton and QuestieCompat335.IsWorldMapCanvasShown()
    end
    return QuestieCompat.GetMouseFocus() == WorldMapFrame.ScrollContainer
end

---Rechecks the hovered path; only when the cursor moved over the canvas, unless forced.
---@param force boolean?
local function _UpdateHover(force)
    local x, y = _ReadCursor()
    if not force and x == cursorX and y == cursorY then return end
    cursorX, cursorY = x, y
    local nearest
    if x and visible[1] and _IsCursorOnMap() then
        nearest = WaypointGeometry.Nearest(visible, x, y, WaypointHover.Radius() / currentScale)
    end
    local path = nearest and nearest.path
    WaypointHover.Set("map", path, path and path.owner)
end

-- Driver
-- One frame on the canvas runs while the map is open. It redraws after changes, map switches and
-- canvas resizes, keeps line widths constant on screen while zooming, and follows the cursor.

-- Smooth zooming eases the canvas scale over many frames. Lines scale with the canvas meanwhile
-- and are redrawn once it settles, or sooner when their width drifts this far from the target.
local ZOOM_REDRAW_DRIFT = 0.25

local function _Update()
    local mapId = _GetMapID()
    local canvas = _GetCanvas()
    local width, height = canvas:GetWidth(), canvas:GetHeight()
    local scale = _GetCanvasScale()
    local settled = scale == currentScale
    currentScale = scale
    local reach = LEGACY and HBDPins.GetWorldMapReach() or nil
    local changed = false
    if dirty or mapId ~= shownMapId or width ~= shownWidth or height ~= shownHeight or reach ~= shownReach then
        -- Paths changed, or the map or canvas did, or the reach of the view past the map's edges: draw again.
        shownMapId, shownWidth, shownHeight, shownScale, shownReach = mapId, width, height, scale, reach
        _Refresh()
        changed = true
    elseif scale ~= shownScale and (settled or math.abs(scale / shownScale - 1) > ZOOM_REDRAW_DRIFT) then
        -- A zoom settled or drifted far: restyle to the width on screen.
        shownScale = scale
        for _, entry in ipairs(visible) do
            renderer:Restyle(entry.view, _Style(entry.path, entry.alpha))
        end
        changed = true
    end
    -- Redrawing or zooming moves the paths under a still cursor.
    _UpdateHover(changed or not settled)
end

local function _CreateDriver()
    local canvas = _GetCanvas()
    renderer = WaypointRenderer.New(canvas)
    driver = CreateFrame("Frame", nil, canvas)
    driver:SetScript("OnUpdate", _Update)
    -- Closing the map ends any hover. Views stay drawn for reopening the same map.
    driver:SetScript("OnHide", function()
        WaypointHover.Set("map", nil)
        cursorX, cursorY = nil, nil
    end)
end

---Redraws on the next frame the map is open, after paths, their visibility or their highlight
---changed. Routes keep their drawn lines when only their style changes.
function WaypointMap.Invalidate()
    if not driver then _CreateDriver() end
    dirty = true
end
