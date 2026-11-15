---@class WorldMapButton
---@field Initialize function
local WorldMapButton = QuestieLoader:CreateModule("WorldMapButton")

---@type l10n
local l10n = QuestieLoader:ImportModule("l10n")
---@type QuestieLib
local QuestieLib = QuestieLoader:ImportModule("QuestieLib")
---@type QuestieQuest
local QuestieQuest = QuestieLoader:ImportModule("QuestieQuest")
---@type QuestieMenu
local QuestieMenu = QuestieLoader:ImportModule("QuestieMenu")
---@type QuestieOptionsEngine
local QuestieOptionsEngine = QuestieLoader:ImportModule("QuestieOptionsEngine")

-- 3.3.5a: the button is built here and placed in the top right corner of the map. The library that
-- places it on later clients (Krowi_WorldMapButtons) needs their world map frame.

---@type AceConfigDialog-3.0
local AceConfigDialog = LibStub("AceConfigDialog-3.0")

local mapButton

local ICON = "Interface\\AddOns\\Questie\\Icons\\questie.tga"

-- above Questie's map icons (HereBeDragons-Pins puts them at WORLDMAP_POI_FRAMELEVEL + 5 and up)
local function _FrameLevel()
    return (WORLDMAP_POI_FRAMELEVEL or 100) + 30
end

--- The top right corner of the map in view. A zoom addon (BetterMaps-WotLK, Magnify-WotLK, Leatrix Maps) puts the
--- map into WorldMapScrollFrame and zooms the map itself, which would carry the button off with the zoom: the button
--- goes on the scroll frame then, and stays in the corner of the window's map.
---@param button Button
local function _Place(button)
    local parent = _G.WorldMapScrollFrame or _G.WorldMapButton -- the map frame; "WorldMapButton" is this module in here
    if button:GetParent() ~= parent then
        button:SetParent(parent)
    end
    button:ClearAllPoints()
    button:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -4, -4)
    button:SetFrameLevel(_FrameLevel())
end

---@return Button
local function _CreateButton()
    local button = CreateFrame("Button", "QuestieWorldMapButton", _G.WorldMapButton)
    button:SetWidth(32)
    button:SetHeight(32)
    _Place(button)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetWidth(25)
    background:SetHeight(25)
    background:SetPoint("TOPLEFT", 2, -4)
    button.Background = background

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ICON)
    icon:SetWidth(22)
    icon:SetHeight(22)
    icon:SetPoint("TOPLEFT", 6, -5)
    button.Icon = icon

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetWidth(54)
    border:SetHeight(54)
    border:SetPoint("TOPLEFT")
    button.Border = border

    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")

    for scriptName, handler in pairs(QuestieWorldMapButtonMixin) do
        if scriptName == "OnMouseDown" or scriptName == "OnMouseUp" or scriptName == "OnEnter" or scriptName == "OnHide" then
            button:SetScript(scriptName, handler)
        end
    end
    button:SetScript("OnLeave", GameTooltip_Hide)
    -- WorldMapFrame_ResetFrameLevels (map size changes) moves the map's frames; stay on top of them.
    if type(WorldMapFrame_ResetFrameLevels) == "function" then
        hooksecurefunc("WorldMapFrame_ResetFrameLevels", function()
            button:SetFrameLevel(_FrameLevel())
        end)
    end
    -- a zoom addon's scroll frame made after the button
    WorldMapFrame:HookScript("OnShow", function()
        if _G.WorldMapScrollFrame and button:GetParent() ~= _G.WorldMapScrollFrame then
            _Place(button)
        end
    end)
    return button
end

function WorldMapButton.Initialize()
    mapButton = _CreateButton()

    Questie.WorldMap = {
        Button = mapButton
    }

    WorldMapButton.Toggle(Questie.db.profile.mapShowHideEnabled)
end

---@param shouldShow boolean
function WorldMapButton.Toggle(shouldShow)
    if shouldShow then
        mapButton:Show()
    else
        mapButton:Hide()
    end
end

---@param self Frame
---@return nil
local function UpdateTooltip(self)
    local tooltip = GameTooltip
    tooltip:SetOwner(self, "ANCHOR_NONE");
    tooltip:ClearLines()
    tooltip:SetPoint("TOPRIGHT", self, "BOTTOMRIGHT", 0, 0);
    tooltip:AddDoubleLine(Questie:Colorize("Questie", 'gold'), Questie:Colorize(QuestieLib:GetAddonVersionString(), 'gray'))
    tooltip:AddLine(" ")
    local toggleLabel = Questie.db.profile.enabled and l10n('Hide Questie') or l10n('Show Questie')
    tooltip:AddDoubleLine(Questie:Colorize(l10n('Left Click'), 'lightBlue'), Questie:Colorize(toggleLabel, 'white'))
    tooltip:AddDoubleLine(Questie:Colorize(l10n('Right Click'), 'lightBlue'), Questie:Colorize(l10n('Toggle Menu'), 'white'))
    tooltip:Show()
end

QuestieWorldMapButtonMixin = {
    OnLoad = function() end,
    OnHide = function() end,
    OnMouseDown = function(_, button)
        if button == "LeftButton" then
            Questie.db.profile.enabled = (not Questie.db.profile.enabled)
            QuestieQuest:ToggleNotes(Questie.db.profile.enabled)
            if GameTooltip:IsShown() and GameTooltip:GetOwner() == mapButton then
                UpdateTooltip(mapButton)
            end
            -- Refresh options UI if open to reflect new state
            QuestieOptionsEngine:RefreshStates()
        elseif button == "RightButton" then
            if QuestieMenu.IsOpen() then
                QuestieMenu:Hide()
            else
                QuestieMenu:Show()
            end
        end
    end,
    OnMouseUp = function() end,
    OnEnter = function(self)
        UpdateTooltip(self)
    end,
    OnLeave = function() end,
    OnClick = function() end, -- Only fires on left click
    Refresh = function() end,
}
