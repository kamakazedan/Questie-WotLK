-- Correction constants. Source origins and extraction history: PROVENANCE.md.

local _, LibQuestieDB = ...
LibQuestieDB = LibQuestieDB or QuestieDB_Namespace335 -- 3.3.5a
local constants = LibQuestieDB.Enum

constants.itemClasses = {
  QUEST = 12,

  -- Forever [add item classes here]
}

constants.dropCorrectionKeys = {
  PSERVER = -2,
  WOWHEAD = -1,

  -- Forever [add drop-correction source keys here]
}
