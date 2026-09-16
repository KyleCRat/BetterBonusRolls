local _, NS = ...

local Reconciliation = {}
NS.LootReconciliation = Reconciliation

-- Keep the implementation for future investigation, but do not infer history
-- from cache tooltips: they can show already-obtained items or partial lists.
-- Re-enable only after their personal remaining-loot semantics are verified.
local TOOLTIP_RECONCILIATION_ENABLED = false
local RETRY_DELAYS = { 0.25, 0.5, 1, 2 }
local activeObservation
local pendingObservation
local readTimer

local function cancelRead()
    if readTimer then
        readTimer:Cancel()
        readTimer = nil
    end
end

function Reconciliation:Cancel(reason)
    if activeObservation then
        NS.Development:Log("reconciliation cancelled",
            "trackingKey", activeObservation.request.trackingKey,
            "reason", reason or "offer context cleared")
    end
    cancelRead()
    activeObservation = nil
    pendingObservation = nil
end

local function plainText(value)
    if NS:IsSecret(value) or type(value) ~= "string" then
        return nil
    end

    value = value:gsub("|c%x%x%x%x%x%x%x%x", "")
        :gsub("|cn[%w_]+:", ""):gsub("|r", "")
    return value:match("^%s*(.-)%s*$")
end

local function readRemainingNames(data)
    if NS:IsSecret(data) or type(data) ~= "table" then
        NS.Development:Log("remaining list unavailable", "reason", "missing or restricted tooltip data")
        return nil
    end

    local lines = data.lines
    local heading = plainText(PUNCH_LIST_ITEM_CACHE_TOOLTIP)
    if NS:IsSecret(lines) or type(lines) ~= "table" or not heading then
        NS.Development:Log("remaining list unavailable", "reason", "missing lines or localized heading")
        return nil
    end

    local foundHeading = false
    local names = {}
    local seen = {}

    for index = 1, #lines do
        local line = lines[index]
        if NS:IsSecret(line) or type(line) ~= "table" then
            NS.Development:Log("remaining list unavailable", "reason", "missing or restricted line", "line", index)
            return nil
        end

        local text = plainText(line.leftText)
        if not text then
            NS.Development:Log("remaining list unavailable", "reason", "missing or restricted line text", "line", index)
            return nil
        end

        if text == heading then
            foundHeading = true
        elseif foundHeading and text ~= "" then
            local name = text:match("^%-%s+(.+)$")
            if not name or seen[name] then
                NS.Development:Log("remaining list rejected", "reason", "unexpected or duplicate entry",
                    "line", index, "text", text)
                return nil
            end
            seen[name] = true
            names[#names + 1] = name
        end
    end

    -- A missing/empty list is not evidence that every item was obtained.
    if not foundHeading or #names == 0 then
        NS.Development:Log("remaining list unavailable", "headingFound", foundHeading,
            "entries", #names, "reason", "empty list is not evidence of all items obtained")
        return nil
    end

    return names
end

local function matchesTooltipContext(observation)
    local source = observation.tooltipSource
    local displayItemID = source.displayItemID
    local itemContext = source.itemContext
    local treasureContextLevel = source.treasureContextLevel
    if NS:IsSecret(displayItemID) or NS:IsSecret(itemContext)
        or NS:IsSecret(treasureContextLevel)
    then
        return false
    end
    if treasureContextLevel == 0 then
        treasureContextLevel = nil
    end

    return displayItemID == observation.displayItemID
        and itemContext == observation.itemContext
        and treasureContextLevel == observation.treasureContextLevel
end

local function reconcileCapturedItems(observation)
    if pendingObservation ~= observation then
        return
    end

    local request = observation.request
    if not observation.isCurrent() or not matchesTooltipContext(observation) then
        NS.Development:Log("reconciliation skipped", "trackingKey", request.trackingKey,
            "reason", "offer ended or tooltip context changed")
        pendingObservation = nil
        return
    end

    local pool = NS.LootTracker:GetPool(request)
    if pool.status ~= "ready" then
        NS.Development:Log("reconciliation waiting", "trackingKey", request.trackingKey,
            "poolStatus", pool.status, "message", pool.message)
        return
    end

    local itemIDByName = {}
    for index = 1, #pool.items do
        local item = pool.items[index]
        -- UI rows may use a fallback label. Only a real cached item name can
        -- establish that an item is absent from the native remaining list.
        local itemName = C_Item.GetItemInfo(item.itemID)
        local name = plainText(itemName)
        if not name or name == "" or itemIDByName[name] then
            NS.Development:Log("reconciliation skipped", "trackingKey", request.trackingKey,
                "reason", "uncached, restricted, or duplicate item name", "itemID", item.itemID)
            return
        end
        itemIDByName[name] = item.itemID
    end

    local remainingItemIDs = {}
    for index = 1, #observation.remainingNames do
        local itemID = itemIDByName[observation.remainingNames[index]]
        if not itemID then
            -- Never infer obtained items from a different or incomplete pool.
            NS.Development:Log("reconciliation skipped", "trackingKey", request.trackingKey,
                "reason", "tooltip item not found in Journal pool",
                "name", observation.remainingNames[index])
            return
        end
        remainingItemIDs[itemID] = true
    end

    pendingObservation = nil
    NS.Development:Log("reconciliation matched", "trackingKey", request.trackingKey,
        "specID", request.specID, "poolItems", #pool.items,
        "remainingItems", #observation.remainingNames)
    NS.LootTracker:ReconcileRemainingItems(
        request,
        pool.items,
        remainingItemIDs
    )
end

local function canReadTooltip(observation)
    return activeObservation == observation
        and observation.isCurrent()
        and matchesTooltipContext(observation)
end

local function tryReadTooltip()
    readTimer = nil
    local observation = activeObservation
    if not observation or not canReadTooltip(observation) then
        if observation then
            NS.Development:Log("reconciliation read skipped", "reason", "offer or tooltip context changed")
        end
        return
    end

    -- Match Blizzard's reward-icon tooltip. Its API has no spec argument;
    -- spec changes alone retain the observed initial list, but zoning can
    -- regenerate it. Keep the initial owner until the controller invalidates
    -- it and cancels both reads and pending pool work on a world transition.
    NS.Development:Log("reconciliation read", "trackingKey", observation.request.trackingKey,
        "tooltipSpecID", observation.request.specID, "attempt", observation.attempt,
        "displayItemID", observation.displayItemID, "itemContext", observation.itemContext,
        "treasureContextLevel", observation.treasureContextLevel)
    local data = C_TooltipInfo.GetItemByID(
        observation.displayItemID,
        nil,
        observation.itemContext,
        observation.treasureContextLevel
    )
    NS.Development:LogTooltip("reconciliation", data)
    if not canReadTooltip(observation) then
        return
    end

    if not NS:IsSecret(data) and type(data) == "table" then
        local dataInstanceID = data.dataInstanceID
        if NS:IsPublicPositiveInteger(dataInstanceID) then
            observation.dataInstanceID = dataInstanceID
        end
    end

    local names = readRemainingNames(data)
    if names then
        observation.remainingNames = names
        pendingObservation = observation
        reconcileCapturedItems(observation)
        return
    end

    observation.attempt = observation.attempt + 1
    local delay = RETRY_DELAYS[observation.attempt]
    if delay and not readTimer then
        NS.Development:Log("reconciliation retry", "delay", delay,
            "attempt", observation.attempt)
        readTimer = C_Timer.NewTimer(delay, tryReadTooltip)
    elseif not delay then
        NS.Development:Log("reconciliation retries exhausted",
            "trackingKey", observation.request.trackingKey)
    end
end

function Reconciliation:ObserveOffer(
    snapshot, tooltipSource, tooltipSpecID, isCurrent
)
    if not TOOLTIP_RECONCILIATION_ENABLED then
        self:Cancel("tooltip reconciliation disabled")
        NS.Development:Log("reconciliation skipped", "reason", "tooltip reconciliation disabled")
        return
    end

    if not snapshot then
        self:Cancel("no current offer snapshot")
        return
    end

    if activeObservation
        and activeObservation.generation ~= snapshot.generation
    then
        self:Cancel("new offer generation")
    end

    if not NS:IsPublicPositiveInteger(tooltipSpecID) then
        NS.Development:Log("reconciliation skipped", "reason", "original tooltip specialization unknown")
        self:Cancel("original tooltip specialization unknown")
        return
    end

    local request = NS.LootTracker:CreateOfferRequest(
        snapshot,
        tooltipSpecID
    )
    if not request then
        NS.Development:Log("reconciliation skipped", "reason", "no trackable pool for source and spec",
            "tooltipSpecID", tooltipSpecID, "kind", snapshot.kind)
        self:Cancel("no trackable pool")
        return
    end

    local displayItemID = tooltipSource.displayItemID
    local itemContext = tooltipSource.itemContext
    local treasureContextLevel = tooltipSource.treasureContextLevel
    if not NS:IsPublicPositiveInteger(displayItemID)
        or NS:IsSecret(itemContext)
        or NS:IsSecret(treasureContextLevel)
    then
        NS.Development:Log("reconciliation skipped", "reason", "missing or restricted tooltip context",
            "displayItemID", displayItemID, "itemContext", itemContext,
            "treasureContextLevel", treasureContextLevel)
        return
    end
    if itemContext ~= nil
        and (type(itemContext) ~= "number"
            or itemContext < 0 or itemContext % 1 ~= 0)
    then
        NS.Development:Log("reconciliation skipped", "reason", "invalid item context", "value", itemContext)
        return
    end
    if treasureContextLevel ~= nil
        and (type(treasureContextLevel) ~= "number"
            or treasureContextLevel < 0 or treasureContextLevel % 1 ~= 0)
    then
        NS.Development:Log("reconciliation skipped", "reason", "invalid treasure context", "value", treasureContextLevel)
        return
    end
    if treasureContextLevel == 0 then
        treasureContextLevel = nil
    end

    if snapshot.kind == "dungeon"
        and snapshot.difficultyID == NS.Catalog.Difficulty.MYTHIC_PLUS
        and (not treasureContextLevel
            or NS.Catalog:GetDungeonCompletionRank(
                snapshot.difficultyID,
                treasureContextLevel
            ) ~= request.difficultyRank)
    then
        NS.Development:Log("reconciliation skipped", "reason", "key level does not match tracking difficulty",
            "treasureContextLevel", treasureContextLevel, "difficultyRank", request.difficultyRank)
        return
    end

    if activeObservation
        and activeObservation.request.trackingKey == request.trackingKey
        and activeObservation.displayItemID == displayItemID
        and activeObservation.itemContext == itemContext
        and activeObservation.treasureContextLevel == treasureContextLevel
    then
        NS.Development:Log("reconciliation observation reused", "trackingKey", request.trackingKey,
            "tooltipSpecID", tooltipSpecID, "currentSpecID", snapshot.currentSpecID)
        return
    end

    self:Cancel("observation replaced")
    activeObservation = {
        generation = snapshot.generation,
        request = request,
        tooltipSource = tooltipSource,
        displayItemID = displayItemID,
        itemContext = itemContext,
        treasureContextLevel = treasureContextLevel,
        isCurrent = isCurrent,
        attempt = 0,
    }

    -- Let Blizzard finish populating the tooltip. Later spec changes reuse
    -- this observation; they cannot retag its names or pending Journal lookup.
    readTimer = C_Timer.NewTimer(0, tryReadTooltip)
end

NS.LootTracker:RegisterChangedCallback(function(changeType, queryKey)
    if changeType ~= "pool" then
        return
    end

    local observation = pendingObservation
    if observation and observation.request.queryKey == queryKey then
        reconcileCapturedItems(observation)
    end
end)

NS:RegisterInitializer(function()
    NS:RegisterEvent("TOOLTIP_DATA_UPDATE", function(_, dataInstanceID)
        local observation = activeObservation
        if not observation or not canReadTooltip(observation)
            or NS:IsSecret(dataInstanceID)
        then
            return
        end
        if dataInstanceID ~= nil
            and dataInstanceID ~= observation.dataInstanceID
        then
            return
        end

        -- Blizzard tooltips also re-read on the next update when their sparse
        -- data finishes loading. Pull a delayed retry forward and coalesce
        -- simultaneous updates into one read on the next frame.
        cancelRead()
        readTimer = C_Timer.NewTimer(0, tryReadTooltip)
    end)
end)
