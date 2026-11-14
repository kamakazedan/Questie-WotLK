---@class QuestieNameplate
local QuestieNameplate = QuestieLoader:CreateModule("QuestieNameplate")
local _QuestieNameplate = {}
-------------------------
--Import modules.
-------------------------
---@type QuestieTooltips
local QuestieTooltips = QuestieLoader:ImportModule("QuestieTooltips")
---@type QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB")

local activeGUIDs = {}
local npFrames = {}
local npUnusedFrames = {}
local npFramesCount = 0

local activeTargetFrame


---@param token string
function QuestieNameplate:NameplateCreated(token)
    Questie.Debug(Questie.DEBUG_SPAM, "[QuestieNameplate:NameplateCreated]")
    -- if nameplates are disabled, don't create new nameplates.
    if (not Questie.db.profile.nameplateEnabled) or (Questie.IsForever and IsInInstance()) then
        return
    end

    -- to avoid memory issues
    if npFramesCount >= 300 then
        return
    end

    local unitGUID = UnitGUID(token)
    local unitName, _ = UnitName(token)

    if (not unitGUID) or (not unitName) then
        return
    end

    local unitType = QuestieCompat335.GetGuidInfo(unitGUID) -- 3.3.5a: hex GUIDs
    if unitType ~= "Creature" and unitType ~= "Vehicle" then
        -- We only draw name plates on NPCs/creatures and Vehicles (oddness with Chillmaw being a Vehicle?!?!) and skip players, pets, etc
        return
    end

    local icon = QuestieNameplate.GetIcon(unitGUID)

    if icon then
        activeGUIDs[unitGUID] = token

        local f = _QuestieNameplate.GetFrame(unitGUID)
        f.Icon:SetTexture(icon)
        f.lastIcon = icon -- this is used to prevent updating the texture when it's already what it needs to be
        f:Show()
    end
end

---@param token string
function QuestieNameplate:NameplateDestroyed(token)
    Questie.Debug(Questie.DEBUG_SPAM, "[QuestieNameplate:NameplateDestroyed]")

    -- The removed unit's GUID may be missing or restricted. Clean up the identity we recorded at creation.
    for guid, activeToken in pairs(activeGUIDs) do
        if activeToken == token then
            activeGUIDs[guid] = nil
            _QuestieNameplate.RemoveFrame(guid)
        end
    end
end

function QuestieNameplate:UpdateNameplate()
    Questie.Debug(Questie.DEBUG_SPAM, "[QuestieNameplate:UpdateNameplate]")
    _QuestieNameplate.LegacyRequestRefresh() -- 3.3.5a nameplates (see the end of this file)

    for guid, token in pairs(activeGUIDs) do
        local unitName, _ = UnitName(token)
        if unitName then
            local icon = QuestieNameplate.GetIcon(guid)

            if icon then
                local frame = _QuestieNameplate.GetFrame(guid)
                -- check if the texture needs to be changed
                if frame.lastIcon ~= icon then
                    frame.lastIcon = icon
                    frame.Icon:SetTexture(icon)
                end
            else
                -- tooltip removed but we still have the frame active, remove it
                activeGUIDs[guid] = nil
                _QuestieNameplate.RemoveFrame(guid)
            end
        end
    end
end

---@param xPos number
---@param yPos number
---@param scale number
function QuestieNameplate.SetIconPosition(xPos, yPos, scale)
    QuestieNameplate.SetIconXPosition(xPos)
    QuestieNameplate.SetIconYPosition(yPos)
    QuestieNameplate.SetIconScale(scale)

    QuestieNameplate:RedrawIcons()
end

---@param xPos number
function QuestieNameplate.SetIconXPosition(xPos)
    if (type(xPos) ~= "number") then
        return
    end

    Questie.db.profile.nameplateX = xPos
end

---@param yPos number
function QuestieNameplate.SetIconYPosition(yPos)
    if (type(yPos) ~= "number") then
        return
    end

    Questie.db.profile.nameplateY = yPos
end

---@param scale number
function QuestieNameplate.SetIconScale(scale)
    if (type(scale) ~= "number") then
        return
    end

    Questie.db.profile.nameplateScale = scale
end

function QuestieNameplate:RedrawIcons()
    for _, frame in pairs(npFrames) do
        local iconScale = Questie.db.profile.nameplateScale

        frame:SetPoint("LEFT", Questie.db.profile.nameplateX, Questie.db.profile.nameplateY)
        frame:SetWidth(16 * iconScale)
        frame:SetHeight(16 * iconScale)
    end
end

function QuestieNameplate:HideCurrentFrames()
    for guid, _ in pairs(activeGUIDs) do
        activeGUIDs[guid] = nil
        _QuestieNameplate.RemoveFrame(guid)
    end
    _QuestieNameplate.LegacyHideAll() -- 3.3.5a nameplates (see the end of this file)
end

---@param guid string
---@return string | nil
function QuestieNameplate.GetIcon(guid)
    if (not guid) then
        return nil
    end

    local _, npcId = QuestieCompat335.GetGuidInfo(guid) -- 3.3.5a: hex GUIDs
    if (not npcId) then
        return nil
    end

    return _QuestieNameplate.GetValidIcon(QuestieTooltips.lookupByKey["m_" .. npcId])
end

function QuestieNameplate:DrawTargetFrame()
    Questie.Debug(Questie.DEBUG_SPAM, "[QuestieNameplate:DrawTargetFrame]")

    if (not Questie.db.profile.nameplateTargetFrameEnabled) or (Questie.IsForever and IsInInstance()) then
        return
    end

    -- always remove the previous frame if it exists
    if activeTargetFrame ~= nil then
        activeTargetFrame.Icon:SetTexture(nil)
        activeTargetFrame:Hide()
    end

    local unitGUID = UnitGUID("target")
    local unitName = UnitName("target")

    if (not unitName) or (not unitGUID) then
        -- We need the GUID and name, this should not happen
        return
    end

    local unitType = QuestieCompat335.GetGuidInfo(unitGUID) -- 3.3.5a: hex GUIDs
    if unitType ~= "Creature" and unitType ~= "Vehicle" then
        -- We only draw name plates on NPCs/creatures and Vehicles (oddness with Chillmaw being a Vehicle?!?!) and skip players, pets, etc
        return
    end

    local icon = QuestieNameplate.GetIcon(unitGUID)
    if (not icon) then
        return
    end

    if not activeTargetFrame then
        activeTargetFrame = _QuestieNameplate.GetTargetFrameIconFrame()
    end

    activeTargetFrame.Icon:SetTexture(icon)
    activeTargetFrame:Show()
end

function QuestieNameplate:HideCurrentTargetFrame()
    if (not activeTargetFrame) then
        return
    end

    activeTargetFrame.Icon:SetTexture(nil)
    activeTargetFrame:Hide()
    activeTargetFrame = nil
end

function QuestieNameplate:RedrawFrameIcon()
    if (not Questie.db.profile.nameplateTargetFrameEnabled) or (not activeTargetFrame) then
        return
    end

    local iconScale = Questie.db.profile.nameplateTargetFrameScale
    activeTargetFrame:SetWidth(16 * iconScale)
    activeTargetFrame:SetHeight(16 * iconScale)
    activeTargetFrame:SetPoint("RIGHT", Questie.db.profile.nameplateTargetFrameX, Questie.db.profile.nameplateTargetFrameY)
end

---@param guid string
function _QuestieNameplate.GetFrame(guid)
    if npFrames[guid] then
        return npFrames[guid]
    end

    local parent = C_NamePlate and C_NamePlate.GetNamePlateForUnit(activeGUIDs[guid]) -- no nameplate units on 3.3.5a

    local frame = tremove(npUnusedFrames)

    if (not frame) then
        frame = CreateFrame("Frame")
        npFramesCount = npFramesCount + 1
    end

    local iconScale = Questie.db.profile.nameplateScale

    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(10)
    frame:SetWidth(16 * iconScale)
    frame:SetHeight(16 * iconScale)
    frame:EnableMouse(false)
    frame:SetParent(parent)
    frame:SetPoint("LEFT", Questie.db.profile.nameplateX, Questie.db.profile.nameplateY)

    frame.Icon = frame:CreateTexture(nil, "ARTWORK")
    frame.Icon:ClearAllPoints()
    frame.Icon:SetAllPoints(frame)

    npFrames[guid] = frame

    return frame
end

function _QuestieNameplate.GetTargetFrameIconFrame()
    local frame = CreateFrame("Frame")

    local iconScale = Questie.db.profile.nameplateTargetFrameScale
    local strata = "MEDIUM"

    local targetFrame = TargetFrame -- Default Blizzard target frame
    if ElvUF_Target then
        targetFrame = ElvUF_Target
        strata = "LOW"
    elseif PitBull4_Frames_Target then
        targetFrame = PitBull4_Frames_Target
    elseif AzeriteUnitFrameTarget then
        targetFrame = AzeriteUnitFrameTarget
        strata = "LOW"
    elseif GwTargetUnitFrame then
        targetFrame = GwTargetUnitFrame
        strata = "LOW"
    elseif InvenUnitFrames_Target then
        targetFrame = InvenUnitFrames_Target
        strata = "LOW"
    elseif SUFUnittarget then
        targetFrame = SUFUnittarget
        frame:SetFrameLevel(SUFUnittarget:GetFrameLevel() + 1)
    elseif XPerl_Target then
        targetFrame = XPerl_Target
    elseif EllesmereUIUnitFrames_Target then
        targetFrame = EllesmereUIUnitFrames_Target
        strata = "MEDIUM"
    end

    frame:SetParent(targetFrame)
    frame:SetFrameStrata(strata)
    frame:SetFrameLevel(11)
    frame:SetWidth(16 * iconScale)
    frame:SetHeight(16 * iconScale)
    frame:EnableMouse(false)

    frame:SetPoint("RIGHT", Questie.db.profile.nameplateTargetFrameX, Questie.db.profile.nameplateTargetFrameY)

    frame.Icon = frame:CreateTexture(nil, "ARTWORK")
    frame.Icon:ClearAllPoints()
    frame.Icon:SetAllPoints(frame)

    return frame
end

---@param guid string
function _QuestieNameplate.RemoveFrame(guid)
    if (not npFrames[guid]) then
        return
    end

    table.insert(npUnusedFrames, npFrames[guid])
    npFrames[guid].Icon:SetTexture(nil) -- fix for overlapping icons
    npFrames[guid]:Hide()
    npFrames[guid] = nil
end

---@param tooltips table<string, table>
function _QuestieNameplate.GetValidIcon(tooltips) -- helper function to get the first valid (incomplete) icon from the specified tooltip, or nil if there is none
    if (not tooltips) then
        return
    end

    for _, tooltip in pairs(tooltips) do
        if tooltip.objective and tooltip.objective.Update then
            tooltip.objective:Update() -- get latest qlog data if its outdated
            if (not tooltip.objective.Completed) and tooltip.objective.Icon then
                -- If the tooltip icon is Questie.ICON_TYPE_OBJECT we use Questie.ICON_TYPE_LOOT because NPCs should never show
                -- a cogwheel icon (for pfquest only).
                local iconType = tooltip.objective.Icon
                if iconType == Questie.ICON_TYPE_LOOT then
                    return Questie.db.profile.iconTheme == 'pfquest' and Questie.icons["loot"] or Questie.db.profile.ICON_LOOT or Questie.icons["loot"]
                elseif iconType == Questie.ICON_TYPE_OBJECT then
                    return Questie.db.profile.iconTheme == 'pfquest' and Questie.icons["loot"] or Questie.db.profile.ICON_LOOT or Questie.icons["loot"]
                elseif iconType == Questie.ICON_TYPE_SLAY then
                    return Questie.db.profile.iconTheme == 'pfquest' and Questie.icons["slay"] or Questie.db.profile.ICON_SLAY or Questie.icons["slay"]
                elseif iconType == Questie.ICON_TYPE_EVENT then
                    return Questie.db.profile.iconTheme == 'pfquest' and Questie.icons["event"] or Questie.db.profile.ICON_EVENT or Questie.icons["event"]
                elseif iconType == Questie.ICON_TYPE_TALK then
                    return Questie.db.profile.iconTheme == 'pfquest' and Questie.icons["talk"] or Questie.db.profile.ICON_TALK or Questie.icons["talk"]
                elseif iconType == Questie.ICON_TYPE_INTERACT then
                    return Questie.db.profile.iconTheme == 'pfquest' and Questie.icons["interact"] or Questie.db.profile.ICON_INTERACT or Questie.icons["interact"]
                elseif iconType == Questie.ICON_TYPE_MOUNT_UP then
                    return Questie.db.profile.iconTheme == 'pfquest' and Questie.icons["mount_up"] or Questie.db.profile.MOUNT_UP or Questie.icons["mount_up"]
                elseif iconType == Questie.ICON_TYPE_PET_BATTLE then
                    return Questie.db.profile.iconTheme == 'pfquest' and Questie.icons["petbattle"] or Questie.db.profile.ICON_TYPE_PET_BATTLE or Questie.icons["petbattle"]
                --? icon types below here are never reached or just not used on nameplates ?
                elseif iconType == Questie.ICON_TYPE_AVAILABLE or iconType == Questie.ICON_TYPE_AVAILABLE_GRAY then
                    return Questie.icons["available"]
                elseif iconType == Questie.ICON_TYPE_REPEATABLE then
                    return Questie.icons["repeatable"]
                elseif iconType == Questie.ICON_TYPE_COMPLETE then
                    return Questie.icons["complete"]
                end
            end
        end
    end
end

-------------------------------------------------------------------------------------------------
-- 3.3.5a nameplates
-------------------------------------------------------------------------------------------------
-- The 3.3.5a client has no nameplate units: there is no UnitGUID("nameplate1") and no
-- NAME_PLATE_UNIT_ADDED/REMOVED. Its nameplates are unnamed children of WorldFrame, found here by
-- scanning, and all they tell about their unit is its name. A nameplate gets an icon when its name
-- is the name of an NPC that is an open quest objective, so another NPC with the same name gets the
-- icon too.

local LEGACY_UPDATE_INTERVAL = 0.2   -- seconds between checks for new nameplates and changed names
local LEGACY_OBJECTIVE_CHECK = 1     -- seconds between checks for added or removed objective NPCs
local LEGACY_NAMEPLATE_BORDER = "interface\\tooltips\\nameplate-border"

local legacyScanner
local legacyChecked = {}            -- [WorldFrame child] = true once looked at
local legacyPlates = {}             -- [nameplate] = its name FontString
local legacyPlateNames = {}         -- [nameplate] = name the icon was chosen for (false: no name)
local legacyNumChildren = -1
local legacyNpcNames = {}           -- [npcId] = name, false when the database has none
local legacyNpcIdsByName = {}       -- [name] = {npcId, ...} for NPCs that are quest objectives
local legacyObjectiveCount, legacyObjectiveSum
local legacyRefreshPending = false
local legacySinceUpdate = 0
local legacySinceObjectiveCheck = LEGACY_OBJECTIVE_CHECK

---@param frame Frame
---@return boolean
local function _IsLegacyNameplate(frame)
    if frame:GetName() then
        return false
    end
    -- the second region of a nameplate is its border
    local _, border = frame:GetRegions()
    if border and border:GetObjectType() == "Texture" then
        local texture = border:GetTexture()
        if type(texture) == "string" and texture:lower() == LEGACY_NAMEPLATE_BORDER then
            return true
        end
    end
    -- Nameplate addons can change that texture. A nameplate also has 11 regions and a health bar
    -- and a cast bar as its children.
    local healthBar, castBar = frame:GetChildren()
    return frame:GetNumRegions() >= 8
        and healthBar ~= nil and healthBar:GetObjectType() == "StatusBar"
        and castBar ~= nil and castBar:GetObjectType() == "StatusBar"
end

---@param plate Frame
---@return FontString?
local function _FindNameRegion(plate)
    local regions = {plate:GetRegions()}
    for i = 1, #regions do
        if regions[i]:GetObjectType() == "FontString" then
            return regions[i] -- the name comes before the level
        end
    end
    return nil
end

---@param npcId number
---@return string|false
local function _GetNpcName(npcId)
    local name = legacyNpcNames[npcId]
    if name == nil then
        name = QuestieDB.QueryNPCSingle(npcId, "name") or false
        legacyNpcNames[npcId] = name
    end
    return name
end

--- Rebuilds legacyNpcIdsByName when the NPCs with objective tooltips changed.
---@return boolean changed
local function _CheckObjectiveNpcs()
    local count, sum = 0, 0
    for key in pairs(QuestieTooltips.lookupByKey) do
        if type(key) == "string" and key:byte(1) == 109 and key:byte(2) == 95 then -- "m_<npcId>"
            local npcId = tonumber(key:sub(3))
            if npcId then
                count = count + 1
                sum = sum + npcId
            end
        end
    end
    if count == legacyObjectiveCount and sum == legacyObjectiveSum then
        return false
    end
    legacyObjectiveCount, legacyObjectiveSum = count, sum

    legacyNpcIdsByName = {}
    for key in pairs(QuestieTooltips.lookupByKey) do
        if type(key) == "string" and key:byte(1) == 109 and key:byte(2) == 95 then
            local npcId = tonumber(key:sub(3))
            local name = npcId and _GetNpcName(npcId)
            if name then
                local npcIds = legacyNpcIdsByName[name]
                if not npcIds then
                    npcIds = {}
                    legacyNpcIdsByName[name] = npcIds
                end
                npcIds[#npcIds + 1] = npcId
            end
        end
    end
    return true
end

---@param name string
---@return string? icon
local function _GetIconForName(name)
    local npcIds = legacyNpcIdsByName[name]
    if not npcIds then
        return nil
    end
    for i = 1, #npcIds do
        local icon = _QuestieNameplate.GetValidIcon(QuestieTooltips.lookupByKey["m_" .. npcIds[i]])
        if icon then
            return icon
        end
    end
    return nil
end

---@param plate Frame
---@return Frame?
local function _GetLegacyFrame(plate)
    local frame = npFrames[plate]
    if frame then
        return frame
    end

    frame = tremove(npUnusedFrames)
    if not frame then
        if npFramesCount >= 300 then
            return nil -- to avoid memory issues
        end
        frame = CreateFrame("Frame")
        npFramesCount = npFramesCount + 1
        frame.Icon = frame:CreateTexture(nil, "ARTWORK")
        frame.Icon:SetAllPoints(frame)
    end

    local iconScale = Questie.db.profile.nameplateScale
    frame:SetParent(plate)
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(10)
    frame:SetWidth(16 * iconScale)
    frame:SetHeight(16 * iconScale)
    frame:EnableMouse(false)
    frame:ClearAllPoints()
    frame:SetPoint("LEFT", plate, "LEFT", Questie.db.profile.nameplateX, Questie.db.profile.nameplateY)
    frame.lastIcon = nil

    npFrames[plate] = frame
    return frame
end

---@param plate Frame
local function _UpdateLegacyPlate(plate)
    local nameRegion = legacyPlates[plate]
    local name = nameRegion and nameRegion:GetText()
    legacyPlateNames[plate] = name or false

    local icon = name and plate:IsShown() and Questie.db.profile.nameplateEnabled and _GetIconForName(name)
    local frame = icon and _GetLegacyFrame(plate)
    if frame then
        if frame.lastIcon ~= icon then
            frame.lastIcon = icon
            frame.Icon:SetTexture(icon)
        end
        frame:Show()
    else
        _QuestieNameplate.RemoveFrame(plate)
    end
end

local function _OnPlateShow(plate)
    if Questie.db.profile.nameplateEnabled then
        _UpdateLegacyPlate(plate)
    end
end

local function _OnPlateHide(plate)
    legacyPlateNames[plate] = nil
    _QuestieNameplate.RemoveFrame(plate)
end

local function _ScanWorldFrame()
    local numChildren = WorldFrame:GetNumChildren()
    if numChildren == legacyNumChildren then
        return
    end
    legacyNumChildren = numChildren

    local children = {WorldFrame:GetChildren()}
    for i = 1, #children do
        local frame = children[i]
        if not legacyChecked[frame] then
            legacyChecked[frame] = true
            if _IsLegacyNameplate(frame) then
                local nameRegion = _FindNameRegion(frame)
                if nameRegion then
                    legacyPlates[frame] = nameRegion
                    frame:HookScript("OnShow", _OnPlateShow)
                    frame:HookScript("OnHide", _OnPlateHide)
                    if frame:IsShown() then
                        _UpdateLegacyPlate(frame)
                    end
                end
            end
        end
    end
end

local function _OnLegacyUpdate(_, elapsed)
    legacySinceUpdate = legacySinceUpdate + elapsed
    if legacySinceUpdate < LEGACY_UPDATE_INTERVAL then
        return
    end
    legacySinceObjectiveCheck = legacySinceObjectiveCheck + legacySinceUpdate
    legacySinceUpdate = 0

    if not Questie.db.profile.nameplateEnabled then
        return
    end

    if legacySinceObjectiveCheck >= LEGACY_OBJECTIVE_CHECK then
        legacySinceObjectiveCheck = 0
        if _CheckObjectiveNpcs() then
            legacyRefreshPending = true
        end
    end

    _ScanWorldFrame()

    local refreshAll = legacyRefreshPending
    legacyRefreshPending = false
    for plate, nameRegion in pairs(legacyPlates) do
        if plate:IsShown() and (refreshAll or legacyPlateNames[plate] ~= (nameRegion:GetText() or false)) then
            -- shown for another unit, or its quest objectives changed
            _UpdateLegacyPlate(plate)
        end
    end
end

--- Starts looking for nameplates (3.3.5a only).
function QuestieNameplate.StartLegacyScanner()
    if legacyScanner then
        return
    end
    legacyScanner = CreateFrame("Frame")
    legacyScanner:SetScript("OnUpdate", _OnLegacyUpdate)
end

--- Quest objectives changed: the next update chooses the icons again.
function _QuestieNameplate.LegacyRequestRefresh()
    if legacyScanner then
        legacyRefreshPending = true
        legacySinceObjectiveCheck = LEGACY_OBJECTIVE_CHECK
    end
end

function _QuestieNameplate.LegacyHideAll()
    for plate in pairs(legacyPlateNames) do
        legacyPlateNames[plate] = nil
        _QuestieNameplate.RemoveFrame(plate)
    end
end
