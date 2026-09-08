local _, NS = ...

local Tracker = {}
NS.LootTracker = Tracker

local UNKNOWN_ITEM_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local RETRY_DELAYS = { 0.25, 0.5, 1, 2 }
local ITEM_LOAD_FINAL_SETTLE_DELAY = 1
local ITEM_COLLECTION_STATUS = {
    COMPLETE = "complete",
    ITEM_PENDING = "itemPending",
    JOURNAL_PENDING = "journalPending",
}
local poolCache = {}
local pendingItems = {}
local failedItems = {}
local journalQueue = {}
local jobsByQueryKey = {}
local dirtyJobs = {}
local changedCallbacks = {}
local jobRefreshTimer
local itemRetryTimer
local itemRetryDueAt
local activeJournalJob
local journalRetryTimer
local journalPumpTimer

local function reportError(message)
    if NS:IsSecret(message) then
        message = "BetterBonusRolls encountered a restricted loot-tracking error."
    end

    local handler = geterrorhandler and geterrorhandler()
    if handler then
        handler(message)
    end
end

local function isPublicString(value)
    return not NS:IsSecret(value) and type(value) == "string"
end

local function getPlayerClassID()
    local _, _, classID = UnitClass("player")
    if NS:IsPublicPositiveInteger(classID) then
        return classID
    end

    return nil
end

local function resolveConcreteSpecID(selection)
    if NS:IsSecret(selection) then
        return nil
    end
    if selection == 0 then
        return NS.Catalog:GetActiveSpecID()
    end
    if NS:IsPublicPositiveInteger(selection)
        and NS.Catalog.specByID[selection]
    then
        return selection
    end

    return nil
end

local function notifyChanged(changeType, key)
    for index = 1, #changedCallbacks do
        local ok, message = pcall(
            changedCallbacks[index],
            changeType,
            key
        )
        if not ok then
            reportError(message)
        end
    end
end

local function makeRaidKeys(instanceID, encounterID, difficultyID, specID,
    journalDifficultyID, classID)
    local trackingKey = table.concat({
        "raid",
        instanceID,
        encounterID,
        difficultyID,
        specID,
    }, ":")
    local queryKey = table.concat({
        trackingKey,
        journalDifficultyID,
        classID,
    }, ":")

    return {
        trackingKey = trackingKey,
        queryKey = queryKey,
    }
end

local function makeDungeonKeys(mapID, difficultyRank, specID, instanceID,
    journalDifficultyID, classID)
    local trackingKey = table.concat({
        "dungeon",
        mapID,
        difficultyRank,
        specID,
    }, ":")
    local queryKey = table.concat({
        "dungeon",
        mapID,
        instanceID,
        journalDifficultyID,
        specID,
        classID,
    }, ":")

    return {
        trackingKey = trackingKey,
        queryKey = queryKey,
    }
end

local function makeWorldBossKeys(encounterID, specID, instanceID,
    journalDifficultyID, classID)
    local trackingKey = table.concat({
        "worldBoss",
        encounterID,
        specID,
    }, ":")
    local queryKey = table.concat({
        trackingKey,
        instanceID,
        journalDifficultyID,
        classID,
    }, ":")

    return {
        trackingKey = trackingKey,
        queryKey = queryKey,
    }
end

function Tracker:CreateRaidRequest(instance, encounter, difficulty, selection)
    if NS:IsSecret(instance)
        or NS:IsSecret(encounter)
        or NS:IsSecret(difficulty)
        or type(instance) ~= "table"
        or type(encounter) ~= "table"
        or type(difficulty) ~= "table"
    then
        return nil
    end

    local instanceID = instance.id
    local encounterID = encounter.id
    local difficultyID = difficulty.id
    local journalDifficultyID = difficulty.journalDifficultyID
    local specID = resolveConcreteSpecID(selection)
    local classID = getPlayerClassID()

    if not NS:IsPublicPositiveInteger(instanceID)
        or not NS:IsPublicPositiveInteger(encounterID)
        or not NS:IsPublicPositiveInteger(difficultyID)
        or not NS:IsPublicPositiveInteger(journalDifficultyID)
        or not NS:IsPublicPositiveInteger(specID)
        or not NS:IsPublicPositiveInteger(classID)
    then
        return nil
    end

    local keys = makeRaidKeys(
        instanceID,
        encounterID,
        difficultyID,
        specID,
        journalDifficultyID,
        classID
    )

    local difficultyName = isPublicString(difficulty.label)
        and difficulty.label
        or NS.Catalog:GetDifficultyName(difficultyID)
    local encounterName = isPublicString(encounter.name)
        and encounter.name
        or "Encounter " .. encounterID

    return {
        kind = "raid",
        instanceID = instanceID,
        encounterID = encounterID,
        difficultyID = difficultyID,
        journalDifficultyID = journalDifficultyID,
        specID = specID,
        classID = classID,
        difficultyName = difficultyName,
        contentName = encounterName,
        sourceName = difficultyName .. " " .. encounterName,
        trackingKey = keys.trackingKey,
        queryKey = keys.queryKey,
    }
end

function Tracker:CreateDungeonRequest(dungeon, minimumDifficulty, selection)
    if NS:IsSecret(dungeon) or type(dungeon) ~= "table" then
        return nil
    end

    local mapID = dungeon.id
    local instanceID = dungeon.journalInstanceID
    local specID = resolveConcreteSpecID(selection)
    local classID = getPlayerClassID()
    local threshold = NS.Catalog:GetDungeonThreshold(
        dungeon,
        minimumDifficulty
    )
    local journalDifficultyID = threshold
        and threshold.journalDifficultyID or nil

    if not NS:IsPublicPositiveInteger(mapID)
        or not NS:IsPublicPositiveInteger(instanceID)
        or not NS:IsPublicPositiveInteger(specID)
        or not NS:IsPublicPositiveInteger(classID)
        or not NS:IsPublicPositiveInteger(journalDifficultyID)
    then
        return nil
    end

    local keys = makeDungeonKeys(
        mapID,
        minimumDifficulty,
        specID,
        instanceID,
        journalDifficultyID,
        classID
    )

    local sourceName = isPublicString(dungeon.name)
        and dungeon.name or "Dungeon " .. mapID
    local difficultyName = isPublicString(threshold.label)
        and threshold.label
        or NS.Catalog:GetDungeonThresholdLabel(minimumDifficulty)

    return {
        kind = "dungeon",
        mapID = mapID,
        difficultyRank = minimumDifficulty,
        instanceID = instanceID,
        journalDifficultyID = journalDifficultyID,
        specID = specID,
        classID = classID,
        difficultyName = difficultyName,
        contentName = sourceName,
        sourceName = difficultyName .. " " .. sourceName,
        trackingKey = keys.trackingKey,
        queryKey = keys.queryKey,
    }
end

function Tracker:CreateWorldBossRequest(boss, selection)
    if NS:IsSecret(boss) or type(boss) ~= "table" then
        return nil
    end

    local encounterID = boss.id
    local instanceID = boss.instanceID
    local journalDifficultyID = boss.journalDifficultyID
    local specID = resolveConcreteSpecID(selection)
    local classID = getPlayerClassID()

    if not NS:IsPublicPositiveInteger(encounterID)
        or not NS:IsPublicPositiveInteger(instanceID)
        or not NS:IsPublicPositiveInteger(journalDifficultyID)
        or not NS:IsPublicPositiveInteger(specID)
        or not NS:IsPublicPositiveInteger(classID)
    then
        return nil
    end

    local keys = makeWorldBossKeys(
        encounterID,
        specID,
        instanceID,
        journalDifficultyID,
        classID
    )

    local sourceName = isPublicString(boss.name)
        and boss.name or "World Boss " .. encounterID
    local difficultyID = NS:IsPublicPositiveInteger(boss.difficultyID)
        and boss.difficultyID or journalDifficultyID
    local difficultyName = NS.Catalog:GetDifficultyName(difficultyID)

    return {
        kind = "worldBoss",
        instanceID = instanceID,
        encounterID = encounterID,
        journalDifficultyID = journalDifficultyID,
        specID = specID,
        classID = classID,
        difficultyName = difficultyName,
        contentName = sourceName,
        sourceName = difficultyName .. " " .. sourceName,
        trackingKey = keys.trackingKey,
        queryKey = keys.queryKey,
    }
end

local function addEnabledLootRequest(requests, request, selection)
    if not request then
        return
    end

    requests[#requests + 1] = {
        request = request,
        configuredLootSpecID = selection,
    }
end

function Tracker:CollectEnabledLootRequests()
    local requests = {}

    for instanceIndex = 1, #NS.Catalog.raids do
        local instance = NS.Catalog.raids[instanceIndex]
        local difficulties = NS.Catalog:GetRaidDifficultiesHardestFirst(
            instance
        )

        for difficultyIndex = 1, #difficulties do
            local difficulty = difficulties[difficultyIndex]

            for encounterIndex = 1, #instance.encounters do
                local encounter = instance.encounters[encounterIndex]
                local selection = NS.DB:Get(
                    "raidRules",
                    instance.id,
                    encounter.id,
                    difficulty.id
                )

                addEnabledLootRequest(
                    requests,
                    self:CreateRaidRequest(
                        instance,
                        encounter,
                        difficulty,
                        selection
                    ),
                    selection
                )
            end
        end
    end

    for dungeonIndex = 1, #NS.Catalog.dungeons do
        local dungeon = NS.Catalog.dungeons[dungeonIndex]
        local selection = NS.DB:Get(
            "dungeonRules",
            dungeon.id,
            "specializationID"
        )
        local minimumDifficulty = NS.DB:Get(
            "dungeonRules",
            dungeon.id,
            "minimumDifficulty"
        )

        addEnabledLootRequest(
            requests,
            self:CreateDungeonRequest(
                dungeon,
                minimumDifficulty,
                selection
            ),
            selection
        )
    end

    for bossIndex = 1, #NS.Catalog.worldBosses do
        local boss = NS.Catalog.worldBosses[bossIndex]
        local selection = NS.DB:Get(
            "contentRules",
            "worldBosses",
            boss.id,
            "specializationID"
        )

        addEnabledLootRequest(
            requests,
            self:CreateWorldBossRequest(boss, selection),
            selection
        )
    end

    return requests
end

function Tracker:CreateOfferRequest(snapshot, specID)
    if NS:IsSecret(snapshot)
        or type(snapshot) ~= "table"
        or NS:IsSecret(specID)
    then
        return nil
    end

    if specID == nil then
        specID = snapshot.desiredSpecID
    end
    if not NS:IsPublicPositiveInteger(specID) then
        return nil
    end

    local kind = snapshot.kind
    if NS:IsSecret(kind) or type(kind) ~= "string" then
        return nil
    end

    if kind == "raid" then
        if not NS:IsPublicPositiveInteger(snapshot.difficultyID) then
            return nil
        end

        local instance = NS:IsPublicPositiveInteger(snapshot.instanceID)
            and NS.Catalog.raidByInstance[snapshot.instanceID] or nil
        local encounter = instance
            and NS:IsPublicPositiveInteger(snapshot.encounterID)
            and instance.encounterByID[snapshot.encounterID] or nil
        local difficultyID = NS.Catalog:CanonicalDifficultyID(
            snapshot.difficultyID
        )
        local difficulty = instance
            and instance.difficultyByID[difficultyID] or nil

        return self:CreateRaidRequest(
            instance,
            encounter,
            difficulty,
            specID
        )
    elseif kind == "dungeon" then
        local dungeon = NS:IsPublicPositiveInteger(snapshot.dungeonMapID)
            and NS.Catalog.dungeonByMap[snapshot.dungeonMapID] or nil

        return self:CreateDungeonRequest(
            dungeon,
            snapshot.completionRank,
            specID
        )
    elseif kind == "worldBoss" then
        local boss = NS:IsPublicPositiveInteger(snapshot.encounterID)
            and NS.Catalog.worldBossByEncounter[snapshot.encounterID] or nil

        return self:CreateWorldBossRequest(
            boss,
            specID
        )
    end

    return nil
end

local function ensureEncounterJournal()
    -- The second return distinguishes fully loaded from still loading.
    local _, loaded = C_AddOns.IsAddOnLoaded("Blizzard_EncounterJournal")
    if not loaded then
        loaded = C_AddOns.LoadAddOn("Blizzard_EncounterJournal")
    end

    return loaded == true
end

local function getPublicTime()
    local now = GetTime()

    if NS:IsSecret(now) or type(now) ~= "number" then
        return 0
    end

    return now
end

local processPendingItems
local queueJobRefresh

local function cancelItemRetryTimer()
    local timer = itemRetryTimer

    itemRetryTimer = nil
    itemRetryDueAt = nil
    if timer and type(timer.Cancel) == "function" then
        timer:Cancel()
    end
end

local function scheduleItemRetryTimer()
    local earliest

    for _, pending in pairs(pendingItems) do
        local dueAt = pending.nextRetryAt

        if type(dueAt) == "number"
            and (not earliest or dueAt < earliest)
        then
            earliest = dueAt
        end
    end

    if not earliest then
        cancelItemRetryTimer()
        return
    end
    if itemRetryTimer
        and itemRetryDueAt
        and itemRetryDueAt <= earliest
    then
        return
    end

    cancelItemRetryTimer()
    itemRetryDueAt = earliest
    itemRetryTimer = C_Timer.NewTimer(
        math.max(0, earliest - getPublicTime()),
        function()
            itemRetryTimer = nil
            itemRetryDueAt = nil
            processPendingItems()
        end
    )
end

local function completePendingItem(itemID, success)
    local pending = pendingItems[itemID]

    if not pending then
        return
    end

    pendingItems[itemID] = nil
    if success == true then
        failedItems[itemID] = nil
    else
        failedItems[itemID] = true
    end

    for job in pairs(pending.waiters) do
        queueJobRefresh(job)
    end

    if not next(pendingItems) then
        cancelItemRetryTimer()
    end
end

processPendingItems = function()
    local itemIDs = {}
    local now = getPublicTime()

    for itemID in pairs(pendingItems) do
        itemIDs[#itemIDs + 1] = itemID
    end

    for index = 1, #itemIDs do
        local itemID = itemIDs[index]
        local pending = pendingItems[itemID]

        if pending and pending.nextRetryAt <= now + 0.01 then
            local cached = C_Item
                and C_Item.IsItemDataCachedByID
                and C_Item.IsItemDataCachedByID(itemID)

            if not NS:IsSecret(cached) and cached == true then
                completePendingItem(itemID, true)
            elseif pending.retryStep <= #RETRY_DELAYS then
                pending.retryStep = pending.retryStep + 1
                if pending.retryStep <= #RETRY_DELAYS then
                    pending.nextRetryAt = now
                        + RETRY_DELAYS[pending.retryStep]
                else
                    pending.nextRetryAt = now
                        + ITEM_LOAD_FINAL_SETTLE_DELAY
                end
                C_Item.RequestLoadItemDataByID(itemID)
            else
                completePendingItem(itemID, false)
            end
        end
    end

    scheduleItemRetryTimer()
end

local function addPendingItem(itemID, job)
    if failedItems[itemID]
        or not C_Item
        or type(C_Item.RequestLoadItemDataByID) ~= "function"
    then
        if NS:IsPublicPositiveInteger(itemID)
            and (not C_Item
                or type(C_Item.RequestLoadItemDataByID) ~= "function")
        then
            failedItems[itemID] = true
        end
        return false
    end

    local pending = pendingItems[itemID]
    if not pending then
        local now = getPublicTime()

        pending = {
            retryStep = 1,
            nextRetryAt = now + RETRY_DELAYS[1],
            waiters = {},
        }
        pendingItems[itemID] = pending
        pending.waiters[job] = true

        -- Install the pending entry before requesting because the result
        -- event can fire synchronously.
        C_Item.RequestLoadItemDataByID(itemID)
        if pendingItems[itemID] then
            scheduleItemRetryTimer()
        end
    else
        pending.waiters[job] = true
        scheduleItemRetryTimer()
    end

    return true
end

local function getItemIcon(itemID, journalIcon)
    if not NS:IsSecret(journalIcon)
        and (type(journalIcon) == "number"
            or type(journalIcon) == "string")
    then
        return journalIcon
    end

    local icon = C_Item.GetItemIconByID(itemID)
    if not NS:IsSecret(icon)
        and (type(icon) == "number" or type(icon) == "string")
    then
        return icon
    end

    return UNKNOWN_ITEM_ICON
end

local function getItemName(itemID, journalName)
    if isPublicString(journalName) and journalName ~= "" then
        return journalName
    end

    local itemName = C_Item.GetItemInfo(itemID)
    if isPublicString(itemName) and itemName ~= "" then
        return itemName
    end

    return "Item " .. itemID
end

local function hasExplicitSpecialization(itemID, specID)
    local specs = C_Item.GetItemSpecInfo(itemID)
    if NS:IsSecret(specs) or type(specs) ~= "table" then
        return false
    end

    for _, candidateSpecID in pairs(specs) do
        if NS:IsSecret(candidateSpecID) then
            return false
        end
        if NS:IsPublicPositiveInteger(candidateSpecID)
            and candidateSpecID == specID
        then
            return true
        end
    end

    return false
end

local function isBonusRollCandidate(itemID, specID)
    local equippable = C_Item.IsEquippableItem(itemID)
    local cosmetic = C_Item.IsCosmeticItem(itemID)
    local decor = C_Item.IsDecorItem(itemID)
    local curio = C_Item.IsCurioItem(itemID)

    if NS:IsSecret(equippable)
        or NS:IsSecret(cosmetic)
        or NS:IsSecret(decor)
        or NS:IsSecret(curio)
    then
        return false
    end
    if cosmetic == true or decor == true or curio == true then
        return false
    end
    if equippable == true then
        return true
    end

    return hasExplicitSpecialization(itemID, specID)
end

local function isExpectedEncounter(job, encounterID)
    if NS:IsSecret(encounterID) then
        return false
    end
    if encounterID == nil then
        return true
    end
    if not NS:IsPublicPositiveInteger(encounterID) then
        return false
    end
    local request = job.request
    if request.kind == "dungeon" then
        return job.encounterIDs[encounterID] == true
    end

    return encounterID == request.encounterID
end

local function collectJournalItem(info, job, items, seen)
    if NS:IsSecret(info) or type(info) ~= "table" then
        return ITEM_COLLECTION_STATUS.JOURNAL_PENDING
    end
    if not isExpectedEncounter(job, info.encounterID) then
        return ITEM_COLLECTION_STATUS.JOURNAL_PENDING
    end

    local itemID = info.itemID
    if not NS:IsPublicPositiveInteger(itemID) then
        return ITEM_COLLECTION_STATUS.JOURNAL_PENDING
    end
    if seen[itemID] then
        return ITEM_COLLECTION_STATUS.COMPLETE
    end
    seen[itemID] = true

    if C_Item and C_Item.IsItemDataCachedByID then
        local cached = C_Item.IsItemDataCachedByID(itemID)

        if NS:IsSecret(cached) then
            return ITEM_COLLECTION_STATUS.JOURNAL_PENDING
        end
        if cached ~= true then
            if addPendingItem(itemID, job) then
                return ITEM_COLLECTION_STATUS.ITEM_PENDING
            end

            return ITEM_COLLECTION_STATUS.COMPLETE
        end

        -- A previous request may have timed out before another Blizzard UI
        -- component warmed this item. Cached data is authoritative.
        failedItems[itemID] = nil
    end

    if not isBonusRollCandidate(itemID, job.request.specID) then
        return ITEM_COLLECTION_STATUS.COMPLETE
    end

    local link = info.link
    if NS:IsSecret(link) then
        return ITEM_COLLECTION_STATUS.JOURNAL_PENDING
    end
    if type(link) ~= "string" or link == "" then
        return ITEM_COLLECTION_STATUS.JOURNAL_PENDING
    end

    items[#items + 1] = {
        itemID = itemID,
        name = getItemName(itemID, info.name),
        link = link,
        icon = getItemIcon(itemID, info.icon),
    }

    return ITEM_COLLECTION_STATUS.COMPLETE
end

local function refreshDungeonEncounterIDs(job)
    if job.request.kind ~= "dungeon" then
        return
    end

    wipe(job.encounterIDs)
    local index = 1
    while true do
        local _, _, encounterID = EJ_GetEncounterInfoByIndex(index)

        if NS:IsSecret(encounterID) or encounterID == nil then
            return
        end
        if NS:IsPublicPositiveInteger(encounterID) then
            job.encounterIDs[encounterID] = true
        end

        index = index + 1
    end
end

local function applyJournalRequest(request)
    local ok, message = pcall(function()
        -- Follow Blizzard's own visible Journal navigation order. Updating
        -- EncounterJournal.instanceID before changing difficulty ensures its
        -- synchronous difficulty refresh cannot reselect the previous page.
        EJ_ContentTab_SelectAppropriateInstanceTab(request.instanceID)
        EncounterJournal_DisplayInstance(request.instanceID)
        EJ_SetDifficulty(request.journalDifficultyID)

        if request.encounterID then
            -- Encounter selection belongs after difficulty selection. This is
            -- also the ordering used by Blizzard and BonusRollPreview.
            EncounterJournal_DisplayEncounter(request.encounterID)
        end

        C_EncounterJournal.ResetSlotFilter()
        EJ_SetLootFilter(request.classID, request.specID)
        EncounterJournal_OnFilterChanged(EncounterJournal)
    end)

    if not ok then
        reportError(message)
    end

    return ok
end

local function readSelectedJournal(job)
    local request = job.request
    local items = {}
    local seen = {}
    local itemPending = false
    local journalPending = false
    local failed = false
    local failedItemIDs = {}

    local ok, message = pcall(function()
        local selectedInstanceID = EncounterJournal.instanceID
        local selectedEncounterID = EncounterJournal.encounterID
        if NS:IsSecret(selectedInstanceID)
            or NS:IsSecret(selectedEncounterID)
            or selectedInstanceID ~= request.instanceID
            or selectedEncounterID ~= request.encounterID
        then
            journalPending = true
            return
        end

        local difficultyID = EJ_GetDifficulty()
        if NS:IsSecret(difficultyID)
            or not NS:IsPublicPositiveInteger(difficultyID)
        then
            journalPending = true
            return
        end

        -- Lair override difficulties select their base Journal pools:
        -- flexible Mythic maps to Mythic, while World maps to Raid Finder.
        local selectedBaseDifficultyID =
            C_EncounterJournal.GetBaseDifficultyID(difficultyID)
        local requestedBaseDifficultyID =
            C_EncounterJournal.GetBaseDifficultyID(
                request.journalDifficultyID
            )
        if NS:IsSecret(selectedBaseDifficultyID)
            or NS:IsSecret(requestedBaseDifficultyID)
            or not NS:IsPublicPositiveInteger(selectedBaseDifficultyID)
            or not NS:IsPublicPositiveInteger(requestedBaseDifficultyID)
            or selectedBaseDifficultyID ~= requestedBaseDifficultyID
        then
            journalPending = true
            return
        end

        local filterClassID, filterSpecID = EJ_GetLootFilter()
        if NS:IsSecret(filterClassID)
            or NS:IsSecret(filterSpecID)
            or filterClassID ~= request.classID
            or filterSpecID ~= request.specID
        then
            journalPending = true
            return
        end

        -- Encounter data can arrive after navigation. Refresh it only after
        -- verifying that the selected Journal state still belongs to this job.
        refreshDungeonEncounterIDs(job)

        local count = EJ_GetNumLoot()
        if NS:IsSecret(count)
            or type(count) ~= "number"
            or count < 0
            or count % 1 ~= 0
        then
            error("Encounter Journal returned an invalid loot count")
        end
        if count == 0 then
            journalPending = true
        end

        for index = 1, count do
            local info = C_EncounterJournal.GetLootInfoByIndex(index)
            local collectionStatus = collectJournalItem(
                info,
                job,
                items,
                seen
            )

            if collectionStatus == ITEM_COLLECTION_STATUS.ITEM_PENDING then
                itemPending = true
            elseif collectionStatus
                == ITEM_COLLECTION_STATUS.JOURNAL_PENDING
            then
                journalPending = true
            end
            if not NS:IsSecret(info)
                and type(info) == "table"
                and NS:IsPublicPositiveInteger(info.itemID)
                and failedItems[info.itemID]
            then
                failed = true
                failedItemIDs[info.itemID] = true
            end
        end
    end)

    if not ok then
        reportError(message)
        return {
            status = "unavailable",
            items = {},
            message = "Loot information could not be loaded.",
            retryable = true,
        }
    end
    if itemPending or journalPending then
        return {
            status = "loading",
            items = items,
            message = journalPending
                and "Loading Encounter Journal loot..."
                or "Loading item information...",
            journalPending = journalPending,
            failedItemIDs = failedItemIDs,
        }
    end
    if failed then
        return {
            status = "unavailable",
            items = items,
            message = "Some item information could not be loaded.",
            retryable = true,
            failedItemIDs = failedItemIDs,
        }
    end
    if #items == 0 then
        return {
            status = "loading",
            items = {},
            message = "Loading Encounter Journal loot...",
            journalPending = true,
        }
    end

    -- Consumers can rely on ready pools containing validated items.
    return {
        status = "ready",
        items = items,
    }
end

local function isPoolRequest(request)
    if NS:IsSecret(request)
        or type(request) ~= "table"
        or not isPublicString(request.queryKey)
    then
        return false
    end

    return true
end

local function cancelJournalRetryTimer()
    local timer = journalRetryTimer

    journalRetryTimer = nil
    if timer and type(timer.Cancel) == "function" then
        timer:Cancel()
    end
end

local startNextJournalJob
local processActiveJournalJob

local function scheduleJournalPump()
    if activeJournalJob
        or journalPumpTimer
        or #journalQueue == 0
    then
        return
    end

    journalPumpTimer = C_Timer.NewTimer(0, function()
        journalPumpTimer = nil
        if not activeJournalJob then
            startNextJournalJob()
        end
    end)
end

local function scheduleActiveJournalAttempt(job, delay)
    cancelJournalRetryTimer()
    journalRetryTimer = C_Timer.NewTimer(delay, function()
        journalRetryTimer = nil
        if activeJournalJob == job then
            processActiveJournalJob(job)
        end
    end)
end

local function releaseJob(job)
    jobsByQueryKey[job.request.queryKey] = nil
    dirtyJobs[job] = nil

    -- A terminal result no longer owns item retries. Other jobs waiting on
    -- the same item keep their subscriptions and existing retry deadlines.
    for itemID, pending in pairs(pendingItems) do
        pending.waiters[job] = nil
        if not next(pending.waiters) then
            pendingItems[itemID] = nil
        end
    end
    scheduleItemRetryTimer()
end

local function finishActiveJournalJob(job, result)
    if activeJournalJob ~= job then
        return
    end

    activeJournalJob = nil
    cancelJournalRetryTimer()

    if result.status == "loading" then
        -- Item-data waits do not hold the Journal. The same job resumes when
        -- an item completes, without clearing its cache or asking UI to retry.
        job.phase = "items"
    else
        releaseJob(job)
    end

    poolCache[job.request.queryKey] = result
    notifyChanged("pool", job.request.queryKey)
    scheduleJournalPump()
end

processActiveJournalJob = function(job)
    local result = readSelectedJournal(job)

    if result.journalPending ~= true then
        finishActiveJournalJob(job, result)
        return
    end

    -- Item events may allow an early read, but an incomplete early read must
    -- not consume another retry or move an already scheduled deadline.
    if journalRetryTimer then
        return
    end

    if job.retryStep >= #RETRY_DELAYS then
        result = {
            status = "unavailable",
            items = result.items or {},
            message = "Loot information did not finish loading.",
            retryable = true,
            failedItemIDs = result.failedItemIDs,
        }
        finishActiveJournalJob(job, result)
        return
    end

    job.retryStep = job.retryStep + 1
    scheduleActiveJournalAttempt(
        job,
        RETRY_DELAYS[job.retryStep]
    )
end

startNextJournalJob = function()
    local job = table.remove(journalQueue, 1)
    if not job then
        return
    end

    local request = job.request
    activeJournalJob = job
    job.phase = "journal"

    if not ensureEncounterJournal() then
        finishActiveJournalJob(job, {
            status = "unavailable",
            items = {},
            message = "The Encounter Journal is unavailable.",
            retryable = true,
        })
        return
    end

    poolCache[request.queryKey] = {
        status = "loading",
        items = {},
        message = "Loading Encounter Journal loot...",
    }

    if not applyJournalRequest(request) then
        finishActiveJournalJob(job, {
            status = "unavailable",
            items = {},
            message = "Loot information could not be loaded.",
            retryable = true,
        })
        return
    end

    -- Warm Journal data is commonly available synchronously. Read it now;
    -- RETRY_DELAYS are fallbacks only for data that is still cold.
    processActiveJournalJob(job)
    if activeJournalJob == job then
        notifyChanged("pool", request.queryKey)
    end
end

local function enqueueJournalJob(request)
    if jobsByQueryKey[request.queryKey] then
        return
    end

    -- The request describes the lookup and is never mutated by the loader.
    -- Only the job owns discovered encounters, retries, and lifecycle state.
    local job = {
        request = CopyTable(request),
        encounterIDs = {},
        retryStep = 0,
        phase = "queued",
    }
    jobsByQueryKey[request.queryKey] = job
    journalQueue[#journalQueue + 1] = job
    scheduleJournalPump()
end

local function flushJobRefreshes()
    local jobs = dirtyJobs

    dirtyJobs = {}
    jobRefreshTimer = nil

    for job in pairs(jobs) do
        if jobsByQueryKey[job.request.queryKey] == job then
            if activeJournalJob == job then
                processActiveJournalJob(job)
            elseif job.phase == "items" then
                job.phase = "queued"
                journalQueue[#journalQueue + 1] = job
                scheduleJournalPump()
            end
        end
    end
end

queueJobRefresh = function(job)
    if jobsByQueryKey[job.request.queryKey] ~= job then
        return
    end

    -- ITEM_DATA_LOAD_RESULT can fire inside RequestLoadItemDataByID. Resume
    -- after that read has unwound, and coalesce items belonging to one job.
    dirtyJobs[job] = true
    if not jobRefreshTimer then
        jobRefreshTimer = C_Timer.NewTimer(0, flushJobRefreshes)
    end
end

function Tracker:GetPool(request)
    if not isPoolRequest(request) then
        return {
            status = "unavailable",
            items = {},
            message = "Loot information is unavailable for this row.",
        }
    end

    local cached = poolCache[request.queryKey]
    if cached then
        return cached
    end

    local waiting = activeJournalJob ~= nil
        or journalPumpTimer ~= nil
        or #journalQueue > 0
    local result = {
        status = waiting and "loading" or "pending",
        items = {},
        message = waiting and "Waiting for Encounter Journal..." or nil,
    }
    poolCache[request.queryKey] = result
    enqueueJournalJob(request)

    return result
end

function Tracker:RetryPool(request)
    if not isPoolRequest(request) then
        return false
    end

    local queryKey = request.queryKey
    if jobsByQueryKey[queryKey] then
        -- Repeated redraws or Retry clicks join work already in progress.
        return true
    end

    local cached = poolCache[queryKey]
    local failedItemIDs = cached and cached.failedItemIDs

    if type(failedItemIDs) == "table" then
        for itemID in pairs(failedItemIDs) do
            if NS:IsPublicPositiveInteger(itemID) then
                failedItems[itemID] = nil
            end
        end
    end

    poolCache[queryKey] = nil
    self:GetPool(request)

    return true
end

local function isTrackableRequest(request)
    if NS:IsSecret(request)
        or type(request) ~= "table"
        or not NS:IsPublicPositiveInteger(request.specID)
    then
        return false
    end

    local kind = request.kind
    if NS:IsSecret(kind) or type(kind) ~= "string" then
        return false
    end

    if kind == "raid" then
        return NS:IsPublicPositiveInteger(request.instanceID)
            and NS:IsPublicPositiveInteger(request.encounterID)
            and NS:IsPublicPositiveInteger(request.difficultyID)
    elseif kind == "dungeon" then
        return NS:IsPublicPositiveInteger(request.mapID)
            and NS:IsPublicPositiveInteger(request.difficultyRank)
    elseif kind == "worldBoss" then
        return NS:IsPublicPositiveInteger(request.encounterID)
    end

    return false
end

local function getObtainedRecord(request, itemID)
    if not isTrackableRequest(request)
        or not NS:IsPublicPositiveInteger(itemID)
    then
        return nil
    end

    if request.kind == "raid" then
        return NS.DB:Get(
            "obtainedItems",
            "raid",
            request.instanceID,
            request.encounterID,
            request.difficultyID,
            request.specID,
            itemID
        )
    elseif request.kind == "dungeon" then
        return NS.DB:Get(
            "obtainedItems",
            "dungeon",
            request.mapID,
            request.difficultyRank,
            request.specID,
            itemID
        )
    end

    return NS.DB:Get(
        "obtainedItems",
        "worldBoss",
        request.encounterID,
        request.specID,
        itemID
    )
end

function Tracker:IsObtained(request, itemID)
    local record = getObtainedRecord(request, itemID)
    return record ~= nil and record.obtained == true
end

function Tracker:IsConfirmedObtained(request, itemID)
    local record = getObtainedRecord(request, itemID)
    return record ~= nil and record.confirmedObtained == true
end

local function storeObtained(request, itemID, obtained, confirmedObtained)
    local previous = getObtainedRecord(request, itemID)
    local wasObtained = previous ~= nil and previous.obtained == true
    local wasConfirmed = previous ~= nil and previous.confirmedObtained == true

    if wasObtained == obtained and wasConfirmed == confirmedObtained then
        return false
    end

    local record
    if obtained or confirmedObtained then
        record = {
            obtained = obtained,
            confirmedObtained = confirmedObtained,
        }
    end

    -- LibSimpleDB:Set(path, nil) removes the entry when neither flag is set.
    if request.kind == "raid" then
        NS.DB:Set(
            "obtainedItems",
            "raid",
            request.instanceID,
            request.encounterID,
            request.difficultyID,
            request.specID,
            itemID,
            record
        )
    elseif request.kind == "dungeon" then
        NS.DB:Set(
            "obtainedItems",
            "dungeon",
            request.mapID,
            request.difficultyRank,
            request.specID,
            itemID,
            record
        )
    else
        NS.DB:Set(
            "obtainedItems",
            "worldBoss",
            request.encounterID,
            request.specID,
            itemID,
            record
        )
    end

    return true
end

function Tracker:SetObtained(request, itemID, obtained)
    if NS:IsSecret(obtained)
        or not isTrackableRequest(request)
        or not NS:IsPublicPositiveInteger(itemID)
    then
        return false
    end

    -- Manual changes affect the checklist, not the evidence behind it.
    if storeObtained(
        request,
        itemID,
        obtained == true,
        self:IsConfirmedObtained(request, itemID)
    ) then
        notifyChanged("obtained", request.trackingKey)
    end

    return true
end

function Tracker:ConfirmObtained(request, itemID)
    if not isTrackableRequest(request)
        or not NS:IsPublicPositiveInteger(itemID)
    then
        return false
    end

    if storeObtained(request, itemID, true, true) then
        notifyChanged("obtained", request.trackingKey)
    end

    return true
end

-- The caller has matched a complete native remaining-items list to this
-- Journal pool. Publish one change after updating the entire checklist.
function Tracker:ReconcileRemainingItems(request, items, remainingItemIDs)
    local changed = false

    for index = 1, #items do
        local itemID = items[index].itemID
        local obtained = remainingItemIDs[itemID] ~= true

        -- Fresh native evidence wins over either kind of manual change.
        if storeObtained(request, itemID, obtained, obtained) then
            changed = true
        end
    end

    if changed then
        notifyChanged("obtained", request.trackingKey)
    end
end

local function createResultRequest(snapshot, specID)
    if NS:IsSecret(snapshot)
        or type(snapshot) ~= "table"
        or not NS:IsPublicPositiveInteger(specID)
    then
        return nil
    end

    local kind = snapshot.kind
    if NS:IsSecret(kind) or type(kind) ~= "string" then
        return nil
    end

    if kind == "raid"
        and NS:IsPublicPositiveInteger(snapshot.instanceID)
        and NS:IsPublicPositiveInteger(snapshot.encounterID)
        and NS:IsPublicPositiveInteger(snapshot.difficultyID)
    then
        local trackingKey = table.concat({
            "raid",
            snapshot.instanceID,
            snapshot.encounterID,
            snapshot.difficultyID,
            specID,
        }, ":")

        return {
            kind = "raid",
            instanceID = snapshot.instanceID,
            encounterID = snapshot.encounterID,
            difficultyID = snapshot.difficultyID,
            specID = specID,
            trackingKey = trackingKey,
        }
    elseif kind == "dungeon"
        and NS:IsPublicPositiveInteger(snapshot.dungeonMapID)
        and NS:IsPublicPositiveInteger(snapshot.completionRank)
    then
        local trackingKey = table.concat({
            "dungeon",
            snapshot.dungeonMapID,
            snapshot.completionRank,
            specID,
        }, ":")

        return {
            kind = "dungeon",
            mapID = snapshot.dungeonMapID,
            difficultyRank = snapshot.completionRank,
            specID = specID,
            trackingKey = trackingKey,
        }
    elseif kind == "worldBoss"
        and NS:IsPublicPositiveInteger(snapshot.encounterID)
    then
        local trackingKey = table.concat({
            "worldBoss",
            snapshot.encounterID,
            specID,
        }, ":")

        return {
            kind = "worldBoss",
            encounterID = snapshot.encounterID,
            specID = specID,
            trackingKey = trackingKey,
        }
    end

    return nil
end

function Tracker:RecordBonusRollItem(snapshot, itemLink, specID)
    if not isPublicString(itemLink)
        or itemLink == ""
        or not NS:IsPublicPositiveInteger(specID)
        or not C_Item
        or not C_Item.GetItemIDForItemInfo
    then
        return nil
    end

    local itemID = C_Item.GetItemIDForItemInfo(itemLink)
    if not NS:IsPublicPositiveInteger(itemID) then
        return nil
    end

    local request = createResultRequest(snapshot, specID)
    if not request then
        return nil
    end

    local item = Item:CreateFromItemID(itemID)
    item:ContinueOnItemLoad(function()
        if isBonusRollCandidate(itemID, specID) then
            Tracker:ConfirmObtained(request, itemID)
        end
    end)

    return itemID
end

function Tracker:RegisterChangedCallback(callback)
    assert(type(callback) == "function", "loot callback must be a function")
    changedCallbacks[#changedCallbacks + 1] = callback
end

local function handleItemInfoReceived(_, itemID, success)
    if not NS:IsPublicPositiveInteger(itemID)
        or NS:IsSecret(success)
        or type(success) ~= "boolean"
    then
        return
    end

    if not pendingItems[itemID] then
        return
    end

    if success == true then
        completePendingItem(itemID, true)
    end
end

NS:RegisterInitializer(function()
    NS:RegisterEvent("ITEM_DATA_LOAD_RESULT", handleItemInfoReceived)
    NS:RegisterEvent("GET_ITEM_INFO_RECEIVED", handleItemInfoReceived)
end)
