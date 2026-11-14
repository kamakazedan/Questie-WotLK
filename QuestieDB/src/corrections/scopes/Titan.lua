-- Titan hints follow the same Wrath-plus-season boundary as their providers.
local _, LibQuestieDB = ...
LibQuestieDB = LibQuestieDB or QuestieDB_Namespace335 -- 3.3.5a
LibQuestieDB.CorrectionCompat.SelectObjectiveFirstScope(
  LibQuestieDB.CorrectionRegister.IsTitanReforgedActive(LibQuestieDB.flavor))
