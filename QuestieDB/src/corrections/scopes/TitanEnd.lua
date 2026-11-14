-- Close the seasonal hint gate before the following providers load.
local _, LibQuestieDB = ...
LibQuestieDB = LibQuestieDB or QuestieDB_Namespace335 -- 3.3.5a
LibQuestieDB.CorrectionCompat.SelectObjectiveFirstScope(true)
