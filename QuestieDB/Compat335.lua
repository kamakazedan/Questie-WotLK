-- QuestieDB for World of Warcraft 3.3.5a
--
-- Every file of this addon shares one table through the addon namespace (`local _, LibQuestieDB = ...`).
-- This keeps a global copy of it, so the files still share one table should a client pass no namespace.
local _, namespace = ...
QuestieDB_Namespace335 = namespace or QuestieDB_Namespace335 or {}
