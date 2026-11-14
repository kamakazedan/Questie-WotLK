-- LibUIDropDownMenuQuestie-4.0 for World of Warcraft 3.3.5a
--
-- Questie's copy of LibUIDropDownMenu needs the newer client's menu system. On 3.3.5a this file
-- keeps the same library name and the functions Questie calls, and hands the work to the client's
-- own UIDropDownMenu / EasyMenu, which support the menu fields Questie builds its menus from.

local MAJOR_VERSION = "LibUIDropDownMenuQuestie-4.0"
local MINOR_VERSION = 90000 + 335

local LibStub = _G.LibStub
if not LibStub then error(MAJOR_VERSION .. " requires LibStub.") end
local lib = LibStub:NewLibrary(MAJOR_VERSION, MINOR_VERSION)
if not lib then return end

local ipairs, type = ipairs, type

--- Menu entries the 3.3.5a menu cannot draw are turned into something it can.
local function _Prepare(menuList)
    if type(menuList) ~= "table" then
        return menuList
    end
    for _, info in ipairs(menuList) do
        if info.isSeparator then
            -- No separator lines on this client: an empty, inert row keeps the spacing.
            info.text = " "
            info.notCheckable = true
            info.notClickable = true
            info.disabled = true
            info.func = nil
            info.icon = nil
            info.iconOnly = nil
            info.iconInfo = nil
        end
        if info.menuList then
            _Prepare(info.menuList)
        end
    end
    return menuList
end

function lib:Create_UIDropDownMenu(name, parent)
    if name and _G[name] then
        return _G[name]
    end
    -- The template names its parts after the frame, so the frame needs a name.
    name = name or ("QuestieDropDownMenu" .. tostring(GetTime()):gsub("%.", ""))
    return CreateFrame("Frame", name, parent or UIParent, "UIDropDownMenuTemplate")
end

function lib:EasyMenu(menuList, menuFrame, anchor, x, y, displayMode, autoHideDelay)
    EasyMenu(_Prepare(menuList), menuFrame, anchor, x, y, displayMode, autoHideDelay)
end

function lib:EasyMenu_Initialize(frame, level, menuList)
    EasyMenu_Initialize(frame, level, _Prepare(menuList))
end

function lib:UIDropDownMenu_Initialize(frame, initFunction, displayMode, level, menuList)
    return UIDropDownMenu_Initialize(frame, initFunction, displayMode, level, menuList)
end

function lib:UIDropDownMenu_CreateInfo()
    return UIDropDownMenu_CreateInfo()
end

function lib:UIDropDownMenu_AddButton(info, level)
    return UIDropDownMenu_AddButton(info, level)
end

function lib:UIDropDownMenu_AddSeparator(level)
    local info = UIDropDownMenu_CreateInfo()
    info.text = " "
    info.notCheckable = true
    info.notClickable = true
    info.disabled = true
    return UIDropDownMenu_AddButton(info, level)
end

function lib:ToggleDropDownMenu(level, value, dropDownFrame, anchorName, xOffset, yOffset, menuList, button, autoHideDelay)
    return ToggleDropDownMenu(level, value, dropDownFrame, anchorName, xOffset, yOffset, _Prepare(menuList), button, autoHideDelay)
end

function lib:CloseDropDownMenus(level)
    return CloseDropDownMenus(level)
end

function lib:HideDropDownMenu(level)
    return HideDropDownMenu(level)
end

function lib:UIDropDownMenu_SetWidth(frame, width, padding)
    return UIDropDownMenu_SetWidth(frame, width, padding)
end

function lib:UIDropDownMenu_SetText(frame, text)
    return UIDropDownMenu_SetText(frame, text)
end

function lib:UIDropDownMenu_GetText(frame)
    return UIDropDownMenu_GetText(frame)
end

function lib:UIDropDownMenu_SetSelectedValue(frame, value, useValue)
    return UIDropDownMenu_SetSelectedValue(frame, value, useValue)
end

function lib:UIDropDownMenu_GetSelectedValue(frame)
    return UIDropDownMenu_GetSelectedValue(frame)
end

function lib:UIDropDownMenu_Refresh(frame, useValue, dropdownLevel)
    return UIDropDownMenu_Refresh(frame, useValue, dropdownLevel)
end

function lib:UIDropDownMenu_JustifyText(frame, justification)
    return UIDropDownMenu_JustifyText(frame, justification)
end

--- The menu that is currently open, if any. The client keeps UIDROPDOWNMENU_OPEN_MENU after a menu
--- closes, so the first menu list must also be visible.
function lib:getOpen()
    if DropDownList1 and DropDownList1:IsShown() then
        return UIDROPDOWNMENU_OPEN_MENU
    end
    return nil
end
