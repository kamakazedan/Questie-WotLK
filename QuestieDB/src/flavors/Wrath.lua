local _, LibQuestieDB = ...
LibQuestieDB = LibQuestieDB or QuestieDB_Namespace335 -- 3.3.5a
assert(not LibQuestieDB.flavor, "QuestieDB: multiple Source flavors selected")
LibQuestieDB.flavor = assert(LibQuestieDB.config.flavorByName.Wrath)
