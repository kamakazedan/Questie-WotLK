-- Questie for World of Warcraft 3.3.5a: quest log events this client does not fire.
--
-- Questie follows the quest log through QUEST_ACCEPTED(questLogIndex, questID), QUEST_TURNED_IN(questID)
-- and QUEST_REMOVED(questID). The 3.3.5a client fires QUEST_ACCEPTED with the log index only and has
-- neither of the other two. They are worked out here and handed to QuestEventHandler:
--
--   * turn-in:  GetQuestReward() is called for the quest on the reward panel; it counts as turned in
--               once it has left the quest log.
--   * abandon:  SetAbandonQuest()/AbandonQuest(); removed once it has left the quest log.
--   * anything else that leaves the log is reported as removed, which Questie then treats as
--     abandoned unless the quest is flagged completed.
--   * the game's "<quest> completed." message (ERR_QUEST_COMPLETE_S) counts as a turn-in too, for turn-ins
--     that did not go through the hooked GetQuestReward: an addon calling the copy it kept before Questie
--     loaded, for example. If the quest already left the log and was reported as removed, it is reported
--     as turned in, which stops it from being taken as abandoned.
--
-- Quests under a collapsed quest log header are listed after the shown entries (see Compat335Api.lua), so a
-- walk to the first absent title sees them all. As a safeguard, a quest only counts as gone when the number
-- of quests in the log (GetNumQuestLogEntries, which counts every quest) went down as well.

local QuestieCompat335 = QuestieCompat335
if not (QuestieCompat335 and QuestieCompat335.isLegacyClient) then
    return
end

local pairs, ipairs, next, select, GetTime = pairs, ipairs, next, select, GetTime

---@type QuestEventHandler
local QuestEventHandler = QuestieLoader:ImportModule("QuestEventHandler")

local MAX_QUEST_LOG_INDEX = 75
local PENDING_TIMEOUT = 15 -- seconds a turn-in or abandon may take to reach the quest log
local COMPLETED_MESSAGE_WINDOW = 10 -- seconds the "<quest> completed." message may come after the quest left the log

local started = false
local knownQuests = {}      -- [questID] = true: quests seen in the log
local knownTitles = {}      -- [questID] = title, for those and for the ones in recentlyRemoved
local recentlyRemoved = {}  -- [questID] = time it left the log, reported as removed
local lastNumQuests         -- quests in the log (hidden ones included) at the last scan
local pendingTurnIns = {}   -- [questID] = {time, xp, money}
local pendingAbandons = {}  -- [questID] = time
local rewardQuestID         -- quest of the open reward panel
local abandonQuestID        -- quest marked with SetAbandonQuest

local frame = CreateFrame("Frame")

-- "%s completed." as a pattern that captures the quest's title
local completedPattern = "^" .. string.gsub(ERR_QUEST_COMPLETE_S or "%s completed.", "[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"):gsub("%%%%s", "(.+)") .. "$"

--- Quests the quest log lists (those under collapsed headers included): [questID] = index, how many, and
--- [questID] = title.
local function _ShownQuests()
    local shown, count, titles = {}, 0, {}
    for index = 1, MAX_QUEST_LOG_INDEX do
        local title, _, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(index)
        if not title then
            break
        end
        if (not isHeader) and questID and questID > 0 then
            shown[questID] = index
            titles[questID] = title
            count = count + 1
        end
    end
    return shown, count, titles
end

--- Calls func(questID[, xp, money]); an error goes to the error handler from where it happened (see Compat335.lua).
local function _Dispatch(func, questID, xp, money)
    xpcall(function()
        func(questID, xp, money)
    end, geterrorhandler())
end

local function _TurnedIn(questID, info)
    knownQuests[questID] = nil
    knownTitles[questID] = nil
    recentlyRemoved[questID] = nil
    QuestieCompat335.MarkQuestCompleted(questID)
    _Dispatch(QuestEventHandler.QuestTurnedIn, questID, info and info.xp or 0, info and info.money or 0)
    _Dispatch(QuestEventHandler.QuestRemoved, questID)
end

local function _Removed(questID)
    knownQuests[questID] = nil
    recentlyRemoved[questID] = GetTime()
    _Dispatch(QuestEventHandler.QuestRemoved, questID)
end

--- The game's "<title> completed." message: that quest was turned in.
---@param title string
local function _CompletedMessage(title)
    local now = GetTime()
    local inLog, gone
    for questID, questTitle in pairs(knownTitles) do
        if questTitle == title then
            if knownQuests[questID] then
                if inLog then
                    return -- two quests of that title: which one is not known
                end
                inLog = questID
            elseif recentlyRemoved[questID] and now - recentlyRemoved[questID] <= COMPLETED_MESSAGE_WINDOW then
                if gone then
                    return
                end
                gone = questID
            end
        end
    end
    if inLog and gone then
        return
    end
    if inLog then
        -- Reported by the scan once it has left the log, like a turn-in seen through GetQuestReward
        if not pendingTurnIns[inLog] then
            pendingTurnIns[inLog] = {time = now, xp = 0, money = 0}
        end
        pendingAbandons[inLog] = nil
    elseif gone then
        -- Already reported as removed: QuestEventHandler waits a moment before it takes that as an abandon
        recentlyRemoved[gone] = nil
        knownTitles[gone] = nil
        QuestieCompat335.MarkQuestCompleted(gone)
        _Dispatch(QuestEventHandler.QuestTurnedIn, gone, 0, 0)
    end
end

local inLoadingScreen = false

--- Compares the quest log with what it held before.
local function _Scan()
    if inLoadingScreen then
        return -- the quest log is not to be trusted until the new world has loaded
    end
    QuestieCompat335.InvalidateQuestLogCache()
    local numQuests = QuestieCompat335.GetNumQuests()
    if numQuests == 0 and lastNumQuests and lastNumQuests > 1 and not (next(pendingTurnIns) or next(pendingAbandons)) then
        return -- an empty answer while the log had quests: not loaded yet
    end
    local shown, shownCount, titles = _ShownQuests()
    local fullyShown = shownCount == numQuests
    local removedCount = lastNumQuests and (lastNumQuests - numQuests) or 0
    local now = GetTime()

    -- turn-ins and abandons whose quest left the log
    if next(pendingTurnIns) or next(pendingAbandons) then
        local candidates = {}
        for questID, info in pairs(pendingTurnIns) do
            candidates[#candidates + 1] = {questID = questID, time = info.time, info = info, turnIn = true}
        end
        for questID, time in pairs(pendingAbandons) do
            candidates[#candidates + 1] = {questID = questID, time = time}
        end
        table.sort(candidates, function(a, b) return a.time < b.time end)

        for _, candidate in ipairs(candidates) do
            local questID = candidate.questID
            if (not shown[questID]) and (fullyShown or removedCount > 0) then
                if removedCount > 0 then
                    removedCount = removedCount - 1
                end
                pendingTurnIns[questID] = nil
                pendingAbandons[questID] = nil
                if candidate.turnIn then
                    _TurnedIn(questID, candidate.info)
                else
                    _Removed(questID)
                end
            elseif now - candidate.time > PENDING_TIMEOUT then
                -- it did not happen (bags full, dialog closed, ...)
                pendingTurnIns[questID] = nil
                pendingAbandons[questID] = nil
            end
        end
    end

    -- other quests that left the log; only knowable while the log shows every quest
    if fullyShown and removedCount > 0 then
        local gone = {}
        for questID in pairs(knownQuests) do
            if not shown[questID] then
                gone[#gone + 1] = questID
            end
        end
        if #gone <= removedCount then
            for _, questID in ipairs(gone) do
                _Removed(questID)
            end
        end
    end

    for questID in pairs(shown) do
        knownQuests[questID] = true
        knownTitles[questID] = titles[questID]
    end
    for questID, time in pairs(recentlyRemoved) do
        if now - time > COMPLETED_MESSAGE_WINDOW then
            recentlyRemoved[questID] = nil
            if not knownQuests[questID] then
                knownTitles[questID] = nil
            end
        end
    end
    lastNumQuests = numQuests
end

--- The quest ID of the quest that QUEST_ACCEPTED announced with its log index, or nil if it cannot be told.
---@param questLogIndex number
---@return number? questID
function QuestieCompat335.GetAcceptedQuestID(questLogIndex)
    QuestieCompat335.InvalidateQuestLogCache()
    local questID = QuestieCompat335.GetQuestIdAtLogIndex(questLogIndex)
    if questID and QuestEventHandler.IsQuestAccepted and QuestEventHandler.IsQuestAccepted(questID) then
        -- That entry is a quest Questie already has, so the index did not lead to the new quest.
        -- It is picked up by the next quest log scan (QuestEventHandler adopts quests found in the log).
        return nil
    end
    if questID then
        knownQuests[questID] = true
        knownTitles[questID] = (GetQuestLogTitle(questLogIndex))
        lastNumQuests = QuestieCompat335.GetNumQuests()
    end
    return questID
end

-------------------------------------------------------------------------------------------------
-- Hooks
-------------------------------------------------------------------------------------------------

frame:SetScript("OnEvent", function(_, event, message)
    if not started then
        return
    end
    if event == "CHAT_MSG_SYSTEM" then
        local title = type(message) == "string" and message:match(completedPattern)
        if title then
            _CompletedMessage(title)
        end
    elseif event == "QUEST_COMPLETE" then
        rewardQuestID = QuestieCompat335.GetQuestID()
    elseif event == "QUEST_FINISHED" then
        -- The quest frame closed; a turn-in reaches the quest log right after this.
        if next(pendingTurnIns) then
            C_Timer.After(0.5, _Scan)
        end
    elseif event == "PLAYER_LEAVING_WORLD" then
        inLoadingScreen = true
    elseif event == "PLAYER_ENTERING_WORLD" then
        inLoadingScreen = false
        C_Timer.After(1, _Scan)
    else -- QUEST_LOG_UPDATE
        _Scan()
    end
end)

hooksecurefunc("GetQuestReward", function()
    if not started then
        return
    end
    local questID = rewardQuestID
    if (not questID) or questID == 0 then
        questID = QuestieCompat335.GetQuestID()
    end
    if questID and questID > 0 then
        pendingTurnIns[questID] = {
            time = GetTime(),
            xp = GetRewardXP and GetRewardXP() or 0,
            money = GetRewardMoney and GetRewardMoney() or 0,
        }
    end
    rewardQuestID = nil
end)

hooksecurefunc("SetAbandonQuest", function()
    abandonQuestID = QuestieCompat335.GetQuestIdAtLogIndex(GetQuestLogSelection())
end)

hooksecurefunc("AbandonQuest", function()
    if not started then
        return
    end
    local questID = abandonQuestID
    local name = GetAbandonQuestName and GetAbandonQuestName()
    if name and name ~= "" then
        -- make sure the marked quest is the one with that name
        local shown = _ShownQuests()
        local matches = questID and shown[questID] and select(1, GetQuestLogTitle(shown[questID])) == name
        if not matches then
            questID = nil
            for id, index in pairs(shown) do
                if GetQuestLogTitle(index) == name then
                    questID = id
                    break
                end
            end
        end
    end
    if questID then
        pendingAbandons[questID] = GetTime()
    end
    abandonQuestID = nil
end)

--- Starts following the quest log. Called once Questie's quest log state is set up.
function QuestieCompat335.StartQuestEvents()
    if started then
        return
    end
    started = true
    local shown, _, titles = _ShownQuests()
    for questID in pairs(shown) do
        knownQuests[questID] = true
        knownTitles[questID] = titles[questID]
    end
    lastNumQuests = QuestieCompat335.GetNumQuests()
    frame:RegisterEvent("QUEST_LOG_UPDATE")
    frame:RegisterEvent("QUEST_COMPLETE")
    frame:RegisterEvent("QUEST_FINISHED")
    frame:RegisterEvent("PLAYER_LEAVING_WORLD")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("CHAT_MSG_SYSTEM")
end
