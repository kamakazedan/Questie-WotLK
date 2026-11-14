---@class Sounds
local Sounds = QuestieLoader:CreateModule("Sounds")

local LSM30 = LibStub("LibSharedMedia-3.0")

local soundTable
local shouldPlayObjectiveProgress = false
local shouldPlayObjectiveComplete = false

function Sounds.PlayObjectiveProgress()
    if (not Questie.db.profile.soundOnObjectiveProgress) then
        return
    end

    if (not shouldPlayObjectiveProgress) then
        shouldPlayObjectiveProgress = true
        C_Timer.After(Questie.db.profile.soundDelay, function ()
            if shouldPlayObjectiveProgress then
                PlaySoundFile(Sounds.GetSelectedSoundFile(Questie.db.profile.objectiveProgressSoundChoiceName), Questie.db.profile.soundChannel)
                shouldPlayObjectiveProgress = false
            end
        end)
    end
end

function Sounds.PlayObjectiveComplete()
    if (not Questie.db.profile.soundOnObjectiveComplete) then
        return
    end

    if (not shouldPlayObjectiveComplete) then
        shouldPlayObjectiveComplete = true
        C_Timer.After(Questie.db.profile.soundDelay, function ()
            if shouldPlayObjectiveComplete then
                PlaySoundFile(Sounds.GetSelectedSoundFile(Questie.db.profile.objectiveCompleteSoundChoiceName), Questie.db.profile.soundChannel)
                shouldPlayObjectiveComplete = false
            end
        end)
    end
end

function Sounds.PlayQuestComplete()
    if (not Questie.db.profile.soundOnQuestComplete) then
        return
    end

    shouldPlayObjectiveProgress = false
    shouldPlayObjectiveComplete = false
    PlaySoundFile(Sounds.GetSelectedSoundFile(Questie.db.profile.questCompleteSoundChoiceName), Questie.db.profile.soundChannel)
end

function Sounds.GetSelectedSoundFile(typeSelected)
    local soundFile = soundTable[typeSelected]
    if (not soundFile) then
        soundFile = LSM30:Fetch("sound", typeSelected)
    end
    return soundFile
end

-- Check https://www.wowhead.com/sounds for all available sounds.
-- !!! Make sure to test new/changed sounds across all expansions !!!
soundTable = {
    ["QuestDefault"]       = "Sound\\Creature\\Peon\\PeonBuildingComplete1.wav", -- 3.3.5a path (was FileDataID 558132)
    ["GameDefault"]        = "Sound\\Interface\\iquestcomplete.wav", -- 3.3.5a path (was FileDataID 567439)
    ["Troll Male"]         = "Sound\\Character\\Troll\\TrollVocalMale\\TrollMaleCongratulations01.wav", -- 3.3.5a path (was FileDataID 543307)
    ["Troll Female"]       = "Sound\\Character\\Troll\\TrollVocalFemale\\TrollFemaleCongratulations01.wav", -- 3.3.5a path (was FileDataID 543273)
    ["Tauren Male"]        = "Sound\\Creature\\Tauren\\TaurenYes3.wav", -- 3.3.5a path (was FileDataID 561484)
    ["Tauren Female"]      = "Sound\\Character\\Tauren\\TaurenVocalFemale\\TaurenFemaleCongratulations01.wav", -- 3.3.5a path (was FileDataID 542997)
    ["Undead Male"]        = "Sound\\Character\\Scourge\\ScourgeVocalMale\\UndeadMaleCongratulations02.wav", -- 3.3.5a path (was FileDataID 542775)
    ["Undead Female"]      = "Sound\\Character\\Scourge\\ScourgeVocalFemale\\UndeadFemaleCongratulations01.wav", -- 3.3.5a path (was FileDataID 542684)
    ["Orc Male"]           = "Sound\\Character\\Orc\\OrcVocalMale\\OrcMaleCongratulations02.wav", -- 3.3.5a path (was FileDataID 541401)
    ["Orc Female"]         = "Sound\\Character\\Orc\\OrcVocalFemale\\OrcFemaleCongratulations01.wav", -- 3.3.5a path (was FileDataID 541317)
    ["Night Elf Male"]     = "Sound\\Character\\NightElf\\NightElfVocalMale\\NightElfMaleCongratulations01.wav", -- 3.3.5a path (was FileDataID 541085)
    ["Night Elf Female"]   = "Sound\\Character\\NightElf\\NightElfVocalFemale\\NightElfFemaleCongratulations02.wav", -- 3.3.5a path (was FileDataID 541031)
    ["Human Male"]         = "Sound\\Character\\Human\\HumanVocalMale\\HumanMaleCongratulations01.wav", -- 3.3.5a path (was FileDataID 540703)
    ["Human Female"]       = "Sound\\Character\\Human\\HumanVocalFemale\\HumanFemaleCongratulations01.wav", -- 3.3.5a path (was FileDataID 540654)
    ["Gnome Male"]         = "Sound\\Character\\Gnome\\GnomeVocalMale\\GnomeMaleCongratulations03.wav", -- 3.3.5a path (was FileDataID 540512)
    ["Gnome Female"]       = "Sound\\Character\\Gnome\\GnomeVocalFemale\\GnomeFemaleCongratulations01.wav", -- 3.3.5a path (was FileDataID 540432)
    ["Dwarf Male"]         = "Sound\\Character\\Dwarf\\DwarfVocalMale\\DwarfMaleCongratulations04.wav", -- 3.3.5a path (was FileDataID 540042)
    ["Dwarf Female"]       = "Sound\\Character\\Dwarf\\DwarfVocalFemale\\DwarfFemaleCongratulations01.wav", -- 3.3.5a path (was FileDataID 539981)
    ["Draenei Male"]       = "Sound\\Character\\Draenei\\DraeneiMaleCongratulations02.wav", -- 3.3.5a path (was FileDataID 539661)
    ["Draenei Female"]     = "Sound\\Character\\Draenei\\DraeneiFemaleCongratulations03.wav", -- 3.3.5a path (was FileDataID 539676)
    ["Blood Elf Male"]     = "Sound\\Character\\BloodElf\\BloodElfMaleCongratulations02.wav", -- 3.3.5a path (was FileDataID 539400)
    ["Blood Elf Female"]   = "Sound\\Character\\BloodElf\\BloodElfFemaleCongratulations03.wav", -- 3.3.5a path (was FileDataID 539175)
    ["Goblin Male"]        = "Sound\\Character\\PCGoblinMale\\VO_PCGoblinMale_Congratulations01.wav", -- 3.3.5a path (was FileDataID 542005)
    ["Goblin Female"]      = "Sound\\Character\\PCGoblinFEMale\\VO_PCGoblinFemale_Congratulations01.wav", -- 3.3.5a path (was FileDataID 541735)
    ["Worgen Male"]        = "Sound\\Character\\PCWorgenMale\\VO_PCWorgenMale_Cheer01.wav", -- 3.3.5a path (was FileDataID 542207)
    ["Worgen Female"]      = "Sound\\Character\\PCWorgenFemale\\VO_PCWorgenFemale_Cheer03.wav", -- 3.3.5a path (was FileDataID 542104)
    ["Gilnean Male"]       = "Sound\\Character\\PCGilneanMale\\VO_PCGilneanMale_Cheer02.wav", -- 3.3.5a path (was FileDataID 541630)
    ["Gilnean Female"]     = "Sound\\Character\\PCGilneanFemale\\VO_PCGilneanFemale_Cheer01.wav", -- 3.3.5a path (was FileDataID 541446)
    ["Pandaren Male"]      = "Sound\\Character\\PCPandarenMale\\VO_PCPandarenMale_Congratulations01.wav", -- 3.3.5a path (was FileDataID 630068)
    ["Pandaren Female"]    = "Sound\\Character\\PCPandarenFemale\\VO_PCPandarenFemale_Congratulations01.wav", -- 3.3.5a path (was FileDataID 636417)
    ["Zug Zug"]            = "Sound\\Creature\\OrcMaleShadyNPC\\OrcMaleShadyNPCGreeting05.wav", -- 3.3.5a path (was FileDataID 557827)
    ["ObjectiveDefault"]   = "Sound\\Interface\\iquestupdate.wav", -- 3.3.5a path (was FileDataID 567516)
    ["Map Ping"]           = "Sound\\Interface\\MapPing.wav", -- 3.3.5a path (was FileDataID 567416)
    ["Window Close"]       = "Sound\\Interface\\AuctionWindowClose.wav", -- 3.3.5a path (was FileDataID 567499)
    ["Window Open"]        = "Sound\\Interface\\AuctionWindowOpen.wav", -- 3.3.5a path (was FileDataID 567482)
    ["Boat Docked"]        = "Sound\\Doodad\\BoatDockedWarning.wav", -- 3.3.5a path (was FileDataID 566652)
    ["Bell Toll Alliance"] = "Sound\\Doodad\\BellTollAlliance.wav", -- 3.3.5a path (was FileDataID 566564)
    ["Bell Toll Horde"]    = "Sound\\Doodad\\BellTollHorde.wav", -- 3.3.5a path (was FileDataID 565853)
    ["Explosion"]          = "Sound\\Doodad\\Hellfire_Raid_FX_Explosion05.wav", -- 3.3.5a path (was FileDataID 566982)
    ["Shing!"]             = "Sound\\Doodad\\PortcullisActive_Closed.wav", -- 3.3.5a path (was FileDataID 566240)
    ["Wham!"]              = "Sound\\Doodad\\PVP_Lordaeron_Door_Open.wav", -- 3.3.5a path (was FileDataID 566946)
    ["Simon Chime"]        = "Sound\\Doodad\\SimonGame_LargeBlueTree.wav", -- 3.3.5a path (was FileDataID 566076)
    ["War Drums"]          = "Sound\\Event Sounds\\Event_wardrum_ogre.wav", -- 3.3.5a path (was FileDataID 567275)
    ["Humm"]               = "Sound\\Spells\\SimonGame_Visual_GameStart.wav", -- 3.3.5a path (was FileDataID 569518)
    ["Short Circuit"]      = "Sound\\Spells\\SimonGame_Visual_BadPress.wav", -- 3.3.5a path (was FileDataID 568975)
    ["ObjectiveProgress"]  = "Sound\\Interface\\AuctionWindowOpen.wav", -- 3.3.5a path (was FileDataID 567482)
}