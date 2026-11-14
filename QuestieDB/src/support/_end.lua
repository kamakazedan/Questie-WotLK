-- src/support/_end.lua
--
-- Closes the support-data block and hands `QuestieLoader` back.

local _, LibQuestieDB = ...
LibQuestieDB = LibQuestieDB or QuestieDB_Namespace335 -- 3.3.5a
LibQuestieDB.Support.Remove()
