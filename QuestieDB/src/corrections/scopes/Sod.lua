-- Vanilla ships SoD providers, but ordinary Era must not receive their load-time hints.
local _, LibQuestieDB = ...
LibQuestieDB = LibQuestieDB or QuestieDB_Namespace335 -- 3.3.5a
LibQuestieDB.CorrectionCompat.SelectObjectiveFirstScope(
  LibQuestieDB.flavor.expansion == "Classic" and LibQuestieDB.CorrectionRegister.IsSodActive())
