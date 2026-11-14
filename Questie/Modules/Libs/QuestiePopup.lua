local _, addon = ...
addon = addon or QuestieCompat335 -- 3.3.5a: shared table if the client passes no namespace
local Dialog = addon.Dialog

-- Expose this addon's private dialog implementation through QuestieLoader.
-- Only frame positioning is shared with other addons via LibPopupStack-1.0.
---@class QuestiePopup
---@field Dialogs table<string, DialogDefinition>
---@field Show fun(key: string, textArg1: string|number?, textArg2: string|number?, data: any): DialogFrame?
---@field FindVisible fun(key: string): DialogFrame?
---@field Hide fun(key: string)
local Popup = QuestieLoader:CreateModule("QuestiePopup")

Popup.Dialogs = Dialog.Dialogs
Popup.Show = Dialog.Show
Popup.FindVisible = Dialog.FindVisible
Popup.Hide = Dialog.Hide

-- A function, because Questie.IsForever is set after this file loads
Dialog.UseGamePadClose = function() return Questie.IsForever end
