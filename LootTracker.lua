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
local queuedJournalQueries = {}
local dirtyPoolKeys = {}
local changedCallbacks = {}
local poolRefreshTimer
local itemRetryTimer
local itemRetryDueAt
local activeJournalQuery
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

local function flushPoolRefreshes()
    local keys = dirtyPoolKeys

    dirtyPoolKeys = {}
    poolRefreshTimer = nil

    for queryKey in pairs(keys) do
        poolCache[queryKey] = nil
        notifyChanged("pool", queryKey)
    end
end

local function queuePoolRefresh(queryKey)
    if not isPublicString(queryKey) then
        return
    end

    dirtyPoolKeys[queryKey] = true
    if not poolRefreshTimer then
        poolRefreshTimer = C_Timer.NewTimer(0, flushPoolRefreshes)
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
    local encounterIDs = {}

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
        encounterIDs = encounterIDs,
        specID = specID,
        classID = classID,
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
    if EJ_SelectInstance
        and EJ_SetDifficulty
        and EJ_SetLootFilter
        and EJ_GetInstanceInfo
        and EJ_GetDifficulty
        and EJ_GetLootFilter
        and EJ_GetNumLoot
        and EJ_GetEncounterInfoByIndex
        and EncounterJournal
        and EJ_ContentTab_SelectAppropriateInstanceTab
        and EncounterJournal_DisplayInstance
        and EncounterJournal_DisplayEncounter
        and EncounterJournal_OnFilterChanged
        and C_EncounterJournal
        and C_EncounterJournal.GetBaseDifficultyID
        and C_EncounterJournal.GetLootInfoByIndex
        and C_EncounterJournal.ResetSlotFilter
    then
        return true
    end

    if C_AddOns and C_AddOns.LoadAddOn then
        C_AddOns.LoadAddOn("Blizzard_EncounterJournal")
    end

    return EJ_SelectInstance ~= nil
        and EJ_SetDifficulty ~= nil
        and EJ_SetLootFilter ~= nil
        and EJ_GetInstanceInfo ~= nil
        and EJ_GetDifficulty ~= nil
        and EJ_GetLootFilter ~= nil
        and EJ_GetNumLoot ~= nil
        and EJ_GetEncounterInfoByIndex ~= nil
        and EncounterJournal ~= nil
        and EJ_ContentTab_SelectAppropriateInstanceTab ~= nil
        and EncounterJournal_DisplayInstance ~= nil
        and EncounterJournal_DisplayEncounter ~= nil
        and EncounterJournal_OnFilterChanged ~= nil
        and C_EncounterJournal ~= nil
        and C_EncounterJournal.GetBaseDifficultyID ~= nil
        and C_EncounterJournal.GetLootInfoByIndex ~= nil
        and C_EncounterJournal.ResetSlotFilter ~= nil
end

local function getPublicTime()
    local now = GetTime()

    if NS:IsSecret(now) or type(now) ~= "number" then
        return 0
    end

    return now
end

local processPendingItems

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

    for queryKey in pairs(pending.waiters) do
        queuePoolRefresh(queryKey)
    end

    if not next(pendingItems) then
        cancelItemRetryTimer()
    end
end

local function requestPendingItem(itemID)
    C_Item.RequestLoadItemDataByID(itemID)
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
                requestPendingItem(itemID)
            else
                completePendingItem(itemID, false)
            end
        end
    end

    scheduleItemRetryTimer()
end

local function addPendingItem(itemID, queryKey)
    if failedItems[itemID]
        or not isPublicString(queryKey)
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
        pending.waiters[queryKey] = true

        -- Install the pending entry before requesting because the result
        -- event can fire synchronously.
        requestPendingItem(itemID)
        if pendingItems[itemID] then
            scheduleItemRetryTimer()
        end
    else
        pending.waiters[queryKey] = true
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

local function isExpectedEncounter(request, encounterID)
    if encounterID == nil then
        return true
    end
    if not NS:IsPublicPositiveInteger(encounterID) then
        return false
    end
    if request.kind == "dungeon" then
        return type(request.encounterIDs) == "table"
            and request.encounterIDs[encounterID] == true
    end

    return encounterID == request.encounterID
end

local function collectJournalItem(info, request, items, seen)
    if NS:IsSecret(info) or type(info) ~= "table" then
        return ITEM_COLLECTION_STATUS.JOURNAL_PENDING
    end
    if not isExpectedEncounter(request, info.encounterID) then
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
            if addPendingItem(itemID, request.queryKey) then
                return ITEM_COLLECTION_STATUS.ITEM_PENDING
            end

            return ITEM_COLLECTION_STATUS.COMPLETE
        end

        -- A previous request may have timed out before another Blizzard UI
        -- component warmed this item. Cached data is authoritative.
        failedItems[itemID] = nil
    end

    if not isBonusRollCandidate(itemID, request.specID) then
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

local function refreshDungeonEncounterIDs(request)
    if request.kind ~= "dungeon"
        or type(request.encounterIDs) ~= "table"
    then
        return
    end

    local index = 1
    while true do
        local _, _, encounterID = EJ_GetEncounterInfoByIndex(index)

        if encounterID == nil or NS:IsSecret(encounterID) then
            return
        end
        if NS:IsPublicPositiveInteger(encounterID) then
            request.encounterIDs[encounterID] = true
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

        refreshDungeonEncounterIDs(request)
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

local function readSelectedJournal(request)
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
                request,
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

local startNextJournalQuery
local processActiveJournalQuery
local scheduleJournalPump

scheduleJournalPump = function()
    if activeJournalQuery
        or journalPumpTimer
        or #journalQueue == 0
    then
        return
    end

    journalPumpTimer = C_Timer.NewTimer(0, function()
        journalPumpTimer = nil
        if not activeJournalQuery then
            startNextJournalQuery()
        end
    end)
end

local function scheduleActiveJournalAttempt(owner, delay)
    cancelJournalRetryTimer()
    journalRetryTimer = C_Timer.NewTimer(delay, function()
        journalRetryTimer = nil
        if activeJournalQuery == owner then
            processActiveJournalQuery(owner)
        end
    end)
end

local function finishActiveJournalQuery(owner, result)
    if activeJournalQuery ~= owner then
        return
    end

    activeJournalQuery = nil
    cancelJournalRetryTimer()
    poolCache[owner.request.queryKey] = result
    notifyChanged("pool", owner.request.queryKey)
    scheduleJournalPump()
end

processActiveJournalQuery = function(owner)
    local result = readSelectedJournal(owner.request)

    if result.journalPending ~= true then
        finishActiveJournalQuery(owner, result)
        return
    end

    if owner.retryStep >= #RETRY_DELAYS then
        result = {
            status = "unavailable",
            items = result.items or {},
            message = "Loot information did not finish loading.",
            retryable = true,
            failedItemIDs = result.failedItemIDs,
        }
        finishActiveJournalQuery(owner, result)
        return
    end

    owner.retryStep = owner.retryStep + 1
    scheduleActiveJournalAttempt(
        owner,
        RETRY_DELAYS[owner.retryStep]
    )
end

startNextJournalQuery = function()
    local queued = journalQueue[1]
    if not queued then
        return
    end

    local request = queued.request

    if not ensureEncounterJournal() then
        table.remove(journalQueue, 1)
        queuedJournalQueries[request.queryKey] = nil
        poolCache[request.queryKey] = {
            status = "unavailable",
            items = {},
            message = "The Encounter Journal is unavailable.",
            retryable = true,
        }
        notifyChanged("pool", request.queryKey)
        scheduleJournalPump()
        return
    end

    table.remove(journalQueue, 1)
    queuedJournalQueries[request.queryKey] = nil

    local owner = {
        request = request,
        retryStep = 0,
    }
    activeJournalQuery = owner
    poolCache[request.queryKey] = {
        status = "loading",
        items = {},
        message = "Loading Encounter Journal loot...",
    }

    if not applyJournalRequest(request) then
        finishActiveJournalQuery(owner, {
            status = "unavailable",
            items = {},
            message = "Loot information could not be loaded.",
            retryable = true,
        })
        return
    end

    -- Warm Journal data is commonly available synchronously. Read it now;
    -- RETRY_DELAYS are fallbacks only for data that is still cold.
    processActiveJournalQuery(owner)
    if activeJournalQuery == owner then
        notifyChanged("pool", request.queryKey)
    end
end

local function enqueueJournalQuery(request)
    if activeJournalQuery
        and activeJournalQuery.request.queryKey == request.queryKey
    then
        activeJournalQuery.request = request
        return
    end

    local queued = queuedJournalQueries[request.queryKey]
    if queued then
        queued.request = request
        return
    end

    queued = { request = request }
    queuedJournalQueries[request.queryKey] = queued
    journalQueue[#journalQueue + 1] = queued
    scheduleJournalPump()
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

    local waiting = activeJournalQuery ~= nil
        or journalPumpTimer ~= nil
        or #journalQueue > 0
    local result = {
        status = waiting and "loading" or "pending",
        items = {},
        message = waiting and "Waiting for Encounter Journal..." or nil,
    }
    poolCache[request.queryKey] = result
    enqueueJournalQuery(request)

    return result
end

function Tracker:RetryPool(request)
    if not isPoolRequest(request) then
        return false
    end

    local queryKey = request.queryKey
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
    dirtyPoolKeys[queryKey] = nil

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

function Tracker:IsObtained(request, itemID)
    if not isTrackableRequest(request)
        or not NS:IsPublicPositiveInteger(itemID)
    then
        return false
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
        ) == true
    elseif request.kind == "dungeon" then
        return NS.DB:Get(
            "obtainedItems",
            "dungeon",
            request.mapID,
            request.difficultyRank,
            request.specID,
            itemID
        ) == true
    end

    return NS.DB:Get(
        "obtainedItems",
        "worldBoss",
        request.encounterID,
        request.specID,
        itemID
    ) == true
end

local function storeObtained(request, itemID, newValue)
    local method = newValue and "Set" or "ResetPath"
    if request.kind == "raid" then
        if newValue then
            NS.DB[method](
                NS.DB,
                "obtainedItems",
                "raid",
                request.instanceID,
                request.encounterID,
                request.difficultyID,
                request.specID,
                itemID,
                true
            )
        else
            NS.DB[method](
                NS.DB,
                "obtainedItems",
                "raid",
                request.instanceID,
                request.encounterID,
                request.difficultyID,
                request.specID,
                itemID
            )
        end
    elseif request.kind == "dungeon" then
        if newValue then
            NS.DB[method](
                NS.DB,
                "obtainedItems",
                "dungeon",
                request.mapID,
                request.difficultyRank,
                request.specID,
                itemID,
                true
            )
        else
            NS.DB[method](
                NS.DB,
                "obtainedItems",
                "dungeon",
                request.mapID,
                request.difficultyRank,
                request.specID,
                itemID
            )
        end
    elseif newValue then
        NS.DB[method](
            NS.DB,
            "obtainedItems",
            "worldBoss",
            request.encounterID,
            request.specID,
            itemID,
            true
        )
    else
        NS.DB[method](
            NS.DB,
            "obtainedItems",
            "worldBoss",
            request.encounterID,
            request.specID,
            itemID
        )
    end
end

function Tracker:SetObtained(request, itemID, obtained)
    if NS:IsSecret(obtained)
        or not isTrackableRequest(request)
        or not NS:IsPublicPositiveInteger(itemID)
    then
        return false
    end

    local newValue = obtained == true
    if self:IsObtained(request, itemID) ~= newValue then
        storeObtained(request, itemID, newValue)
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

        if self:IsObtained(request, itemID) ~= obtained then
            storeObtained(request, itemID, obtained)
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
            Tracker:SetObtained(request, itemID, true)
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
