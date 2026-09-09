local _, NS = ...

local Reconciliation = {}
NS.LootReconciliation = Reconciliation

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

function Reconciliation:Cancel()
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
        return nil
    end

    local lines = data.lines
    local heading = plainText(PUNCH_LIST_ITEM_CACHE_TOOLTIP)
    if NS:IsSecret(lines) or type(lines) ~= "table" or not heading then
        return nil
    end

    local foundHeading = false
    local names = {}
    local seen = {}

    for index = 1, #lines do
        local line = lines[index]
        if NS:IsSecret(line) or type(line) ~= "table" then
            return nil
        end

        local text = plainText(line.leftText)
        if not text then
            return nil
        end

        if text == heading then
            foundHeading = true
        elseif foundHeading and text ~= "" then
            local name = text:match("^%-%s+(.+)$")
            if not name or seen[name] then
                return nil
            end
            seen[name] = true
            names[#names + 1] = name
        end
    end

    -- A missing/empty list is not evidence that every item was obtained.
    if not foundHeading or #names == 0 then
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
        pendingObservation = nil
        return
    end

    local pool = NS.LootTracker:GetPool(request)
    if pool.status ~= "ready" then
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
            return
        end
        itemIDByName[name] = item.itemID
    end

    local remainingItemIDs = {}
    for index = 1, #observation.remainingNames do
        local itemID = itemIDByName[observation.remainingNames[index]]
        if not itemID then
            -- Never infer obtained items from a different or incomplete pool.
            return
        end
        remainingItemIDs[itemID] = true
    end

    pendingObservation = nil
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
        return
    end

    -- Match Blizzard's reward-icon tooltip. Its API has no spec argument;
    -- observed tooltips retain the offer's initial spec after a spec change.
    -- Every read and delayed pool callback must keep that original owner.
    local data = C_TooltipInfo.GetItemByID(
        observation.displayItemID,
        nil,
        observation.itemContext,
        observation.treasureContextLevel
    )
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
        readTimer = C_Timer.NewTimer(delay, tryReadTooltip)
    end
end

function Reconciliation:ObserveOffer(
    snapshot, tooltipSource, tooltipSpecID, isCurrent
)
    if not snapshot then
        self:Cancel()
        return
    end

    if activeObservation
        and activeObservation.generation ~= snapshot.generation
    then
        self:Cancel()
    end

    if not NS:IsPublicPositiveInteger(tooltipSpecID) then
        self:Cancel()
        return
    end

    local request = NS.LootTracker:CreateOfferRequest(
        snapshot,
        tooltipSpecID
    )
    if not request then
        self:Cancel()
        return
    end

    local displayItemID = tooltipSource.displayItemID
    local itemContext = tooltipSource.itemContext
    local treasureContextLevel = tooltipSource.treasureContextLevel
    if not NS:IsPublicPositiveInteger(displayItemID)
        or NS:IsSecret(itemContext)
        or NS:IsSecret(treasureContextLevel)
    then
        return
    end
    if itemContext ~= nil
        and (type(itemContext) ~= "number"
            or itemContext < 0 or itemContext % 1 ~= 0)
    then
        return
    end
    if treasureContextLevel ~= nil
        and (type(treasureContextLevel) ~= "number"
            or treasureContextLevel < 0 or treasureContextLevel % 1 ~= 0)
    then
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
        return
    end

    if activeObservation
        and activeObservation.request.trackingKey == request.trackingKey
        and activeObservation.displayItemID == displayItemID
        and activeObservation.itemContext == itemContext
        and activeObservation.treasureContextLevel == treasureContextLevel
    then
        return
    end

    self:Cancel()
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
