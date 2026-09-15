local addonName, NS = ...

local Development = {}
NS.Development = Development

local enabled = false
local CAPTURE_DELAYS = { 0.25, 0.5, 1, 2 }
local captureTimer
local activeCapture
local hoverTimer
local tooltipSource
local hoveredDataInstanceID
local offerGeneration
-- Diagnostic context only, never used to identify or reconcile an offer.
local observedPreyQuestID
local recentPreyQuestID
-- Only the latest text from each read source, for comparison; not a log buffer.
local lastTooltipText = {}

function Development:IsEnabled()
    return enabled
end

local function scalarText(value)
    if NS:IsSecret(value) then
        return "<secret>"
    end

    local valueType = type(value)
    if valueType == "string" then
        local text = value:gsub("|c%x%x%x%x%x%x%x%x", "")
            :gsub("|cn[%w_]+:", ""):gsub("|r", "")
            :gsub("[\r\n]", " "):gsub("|", "||")
        return text
    elseif valueType == "number" or valueType == "boolean"
        or valueType == "nil"
    then
        return tostring(value)
    end

    return "<" .. valueType .. ">"
end

function Development:Log(event, ...)
    if not enabled then
        return
    end

    local prefix = "[Dev " .. date("%H:%M:%S") .. " offer="
        .. scalarText(offerGeneration) .. "] " .. event
    local fields = {}
    local count = select("#", ...)
    for index = 1, count, 2 do
        fields[#fields + 1] = scalarText(select(index, ...)) .. "="
            .. scalarText(select(index + 1, ...))
        if #fields == 4 or index + 1 >= count then
            NS:Print(prefix .. " | " .. table.concat(fields, " | "))
            wipe(fields)
        end
    end

    if count == 0 then
        NS:Print(prefix)
    end
end

local function readOfferContext()
    local context = NS.RollController:GetDevelopmentContext()
    local generation = context and context.generation
    if generation ~= offerGeneration then
        offerGeneration = generation
        wipe(lastTooltipText)
        hoveredDataInstanceID = nil
    end
    return context
end

local function specText(specID)
    if not NS:IsPublicPositiveInteger(specID) then
        return scalarText(specID)
    end
    return NS.Catalog:GetSpecName(specID) .. " (" .. specID .. ")"
end

function Development:LogSpecs(reason)
    if not enabled then
        return
    end

    local context = readOfferContext()
    local selection = GetLootSpecialization()
    local activeSpecID = NS.Catalog:GetActiveSpecID()
    local effectiveSpecID
    if not NS:IsSecret(selection) and selection == 0 then
        effectiveSpecID = activeSpecID
    elseif NS:IsPublicPositiveInteger(selection) then
        effectiveSpecID = selection
    end

    self:Log(reason, "lootSelection", selection,
        "effectiveSpec", specText(effectiveSpecID),
        "activeSpec", specText(activeSpecID),
        "tooltipOwner", context and specText(context.tooltipSpecID) or "unknown",
        "ownerCaptured", context and context.tooltipSpecCaptured or false)
end

local function logPreyQuest(questID, reason)
    if not NS:IsPublicPositiveInteger(questID) then
        return
    end

    Development:Log("prey quest", "reason", reason, "questID", questID,
        "title", C_QuestLog.GetTitleForQuestID(questID),
        "complete", C_QuestLog.IsComplete(questID))
    local tag = C_QuestLog.GetQuestTagInfo(questID)
    if not NS:IsSecret(tag) and type(tag) == "table" then
        Development:Log("prey quest tag", "questID", questID,
            "tagID", tag.tagID, "tagName", tag.tagName,
            "worldQuestType", tag.worldQuestType)
    else
        Development:Log("prey quest tag", "questID", questID, "tag", tag)
    end
end

local function observePreyQuest()
    if not enabled then
        return nil
    end

    local questID = C_QuestLog.GetActivePreyQuest()
    if NS:IsSecret(questID) then
        return questID
    end
    if questID == 0 then
        questID = nil
    end
    if questID ~= nil and not NS:IsPublicPositiveInteger(questID) then
        Development:Log("prey quest unavailable", "activeQuestID", questID)
        return nil
    end

    if questID ~= observedPreyQuestID then
        Development:Log("active prey quest changed", "previousQuestID", observedPreyQuestID,
            "activeQuestID", questID)
        observedPreyQuestID = questID
        if questID then
            recentPreyQuestID = questID
            logPreyQuest(questID, "active quest changed")
        end
    end
    return questID
end

function Development:LogPreyContext(reason)
    if not enabled then
        return
    end

    local questID = observePreyQuest()
    self:Log("prey context", "reason", reason, "activeQuestID", questID,
        "recentQuestID", recentPreyQuestID,
        "configuredLootSpec", NS.DB:Get("contentRules", "world", "specializationID"))
    self:Log("location", "zone", GetZoneText(), "subZone", GetSubZoneText(),
        "uiMapID", C_Map.GetBestMapForUnit("player"))
    logPreyQuest(questID, reason)
end

function Development:LogPendingPrompts(reason)
    if not enabled then
        return
    end

    local prompts = GetSpellConfirmationPromptsInfo()
    if NS:IsSecret(prompts) or type(prompts) ~= "table" then
        self:Log("pending prompts unavailable", "reason", reason, "data", prompts)
        return
    end

    self:Log("pending prompts", "reason", reason, "count", #prompts)
    for index = 1, #prompts do
        local prompt = prompts[index]
        if NS:IsSecret(prompt) or type(prompt) ~= "table" then
            self:Log("pending prompt unavailable", "index", index, "data", prompt)
        elseif NS:IsSecret(prompt.confirmType) then
            self:Log("pending prompt unavailable", "index", index, "type", prompt.confirmType)
        elseif prompt.confirmType == Enum.ConfirmationPromptUIType.BonusRoll then
            self:Log("pending bonus prompt", "index", index, "spellID", prompt.spellID,
                "type", prompt.confirmType, "duration", prompt.duration,
                "difficultyID", prompt.difficultyID, "displayItemID", prompt.displayItemID,
                "itemContext", prompt.itemContext, "treasureContextLevel", prompt.treasureContextLevel,
                "currencyID", prompt.currencyID, "currencyCost", prompt.currencyCost)
            if NS:IsPublicPositiveInteger(prompt.spellID) then
                local instanceID, encounterID = GetJournalInfoForSpellConfirmation(prompt.spellID)
                self:Log("pending prompt journal", "index", index, "spellID", prompt.spellID,
                    "journalInstanceID", instanceID, "encounterID", encounterID)
            end
        end
    end
end

function Development:LogOffer(reason)
    if not enabled then
        return
    end

    local context = readOfferContext()
    if not context then
        self:Log(reason, "context", "no inspectable offer")
        return
    end

    local raw = context.raw
    self:Log(reason, "spellID", raw.spellID,
        "journalInstanceID", raw.instanceID, "encounterID", raw.encounterID,
        "difficultyID", raw.difficultyID, "endTime", raw.endTime,
        "active", context.active, "hidden", context.hidden,
        "rollState", context.rollState, "filteringEnabled", context.enabled)

    local instanceName, instanceType, difficultyID, _, _, _, _, gameMapID = GetInstanceInfo()
    self:Log("instance", "name", instanceName, "type", instanceType,
        "difficultyID", difficultyID, "gameMapID", gameMapID)
    self:LogSpecs("specializations")
    self:LogPreyContext(reason)
    self:LogPendingPrompts(reason)
end

function Development:LogSnapshot(snapshot)
    if not enabled or not snapshot then
        return
    end

    readOfferContext()
    self:Log("offer evaluated", "source", snapshot.sourceName,
        "kind", snapshot.kind, "configuredSelection", snapshot.desiredLootSpecID,
        "configuredSpec", specText(snapshot.desiredSpecID),
        "allowed", snapshot.allowed, "reason", snapshot.reason,
        "dungeonMapID", snapshot.dungeonMapID,
        "challengeMapID", snapshot.challengeMapID,
        "keyLevel", snapshot.challengeLevel, "difficultyRank", snapshot.completionRank)
end

function Development:LogTooltip(source, data)
    if not enabled then
        return
    end

    readOfferContext()
    if NS:IsSecret(data) or type(data) ~= "table" then
        self:Log("tooltip " .. source, "data", data)
        return
    end

    local lines = data.lines
    if NS:IsSecret(lines) or type(lines) ~= "table" then
        self:Log("tooltip " .. source, "dataInstanceID", data.dataInstanceID,
            "lines", lines)
        return
    end

    local text = {}
    for index = 1, #lines do
        local line = lines[index]
        if NS:IsSecret(line) or type(line) ~= "table" then
            text[index] = scalarText(line)
        else
            text[index] = "type=" .. scalarText(line.type)
                .. " left=" .. scalarText(line.leftText)
                .. " right=" .. scalarText(line.rightText)
        end
    end

    local contents = table.concat(text, "\n")
    local unchanged = contents == lastTooltipText[source]
    self:Log("tooltip " .. source, "dataInstanceID", data.dataInstanceID,
        "lines", #text, "contents", unchanged and "unchanged" or "changed")
    if unchanged then
        return
    end

    lastTooltipText[source] = contents
    for index = 1, #text do
        -- Already sanitized: avoid escaping item-link pipes a second time.
        NS:Print("[Dev " .. date("%H:%M:%S") .. " offer="
            .. scalarText(offerGeneration) .. "] " .. source
            .. " line " .. index .. " | " .. text[index])
    end
end

function Development:CancelCaptures()
    if captureTimer then
        captureTimer:Cancel()
        captureTimer = nil
    end
    if hoverTimer then
        hoverTimer:Cancel()
        hoverTimer = nil
    end
    activeCapture = nil
    hoveredDataInstanceID = nil
end

local function isOptionalContext(value)
    if NS:IsSecret(value) then
        return false
    end
    return value == nil or (type(value) == "number"
        and value >= 0 and value % 1 == 0)
end

local function captureTooltip(capture)
    if not enabled or activeCapture ~= capture then
        return
    end
    captureTimer = nil

    local context = readOfferContext()
    if not context or not context.active
        or (capture.generation and capture.generation ~= context.generation)
    then
        Development:Log("diagnostic capture stopped", "reason", "offer ended or replaced")
        activeCapture = nil
        return
    end

    capture.generation = context.generation
    if capture.attempt == 0 then
        Development:LogOffer(capture.reason)
    else
        Development:LogSpecs("diagnostic specializations")
    end

    local source = tooltipSource
    local displayItemID = source and source.displayItemID
    local itemContext = source and source.itemContext
    local treasureContextLevel = source and source.treasureContextLevel
    Development:Log("diagnostic read", "attempt", capture.attempt,
        "displayItemID", displayItemID, "itemContext", itemContext,
        "treasureContextLevel", treasureContextLevel)

    if NS:IsPublicPositiveInteger(displayItemID)
        and isOptionalContext(itemContext) and isOptionalContext(treasureContextLevel)
    then
        if treasureContextLevel == 0 then
            treasureContextLevel = nil
        end
        -- Diagnostic only: never send this data to LootReconciliation/Tracker.
        local data = C_TooltipInfo.GetItemByID(
            displayItemID, nil, itemContext, treasureContextLevel
        )
        Development:LogTooltip("diagnostic API", data)
    else
        Development:Log("diagnostic read skipped", "reason", "missing or restricted tooltip context")
    end

    capture.attempt = capture.attempt + 1
    local delay = CAPTURE_DELAYS[capture.attempt]
    if delay then
        captureTimer = C_Timer.NewTimer(delay, function()
            captureTooltip(capture)
        end)
    else
        Development:LogPreyContext("last tooltip attempt")
        activeCapture = nil
    end
end

function Development:StartCapture(reason)
    if not enabled then
        return
    end

    self:CancelCaptures()
    local capture = { reason = reason, attempt = 0 }
    activeCapture = capture
    captureTimer = C_Timer.NewTimer(0, function()
        captureTooltip(capture)
    end)
end

local function logHoveredTooltip()
    hoverTimer = nil
    if not enabled or not tooltipSource then
        return
    end

    local owner = GameTooltip:GetOwner()
    local context = readOfferContext()
    if NS:IsSecret(owner) or owner ~= tooltipSource
        or not context or not context.active
    then
        return
    end

    Development:LogSpecs("native reward tooltip hovered")
    local data = GameTooltip:GetPrimaryTooltipData()
    hoveredDataInstanceID = nil
    if not NS:IsSecret(data) and type(data) == "table"
        and NS:IsPublicPositiveInteger(data.dataInstanceID)
    then
        hoveredDataInstanceID = data.dataInstanceID
    end
    Development:LogTooltip("native hover", data)
end

function Development:AttachTooltip(source)
    tooltipSource = source
    source:HookScript("OnEnter", logHoveredTooltip)
end

local function logVersions()
    local version, build, _, interface = GetBuildInfo()
    Development:Log("versions", "addon", C_AddOns.GetAddOnMetadata(addonName, "Version"),
        "client", version, "build", build, "interface", interface)
end

function Development:SetEnabled(value)
    enabled = value == true
    NS.DB:Set("developmentMode", enabled)
    self:CancelCaptures()
    wipe(lastTooltipText)
    observedPreyQuestID = nil
    recentPreyQuestID = nil
    if enabled then
        NS:Print("Development mode enabled for this character. Chat diagnostics and /bbr preview are available. Use /bbr dev off to disable.")
        logVersions()
        self:LogPreyContext("development enabled")
        self:StartCapture("development enabled")
    else
        NS.Preview:Hide()
        NS:Print("Development mode disabled for this character.")
    end
end

local function handleSpecUpdate(event, unit)
    if not enabled then
        return
    end
    if event == "PLAYER_SPECIALIZATION_CHANGED"
        and (NS:IsSecret(unit) or unit ~= "player")
    then
        return
    end

    Development:LogSpecs(event)
    Development:StartCapture(event)
end

local function handleResult(_, resultType, itemLink, quantity, specID,
    _sex, _personalLootToast, currencyID, isSecondaryResult)
    if not enabled then
        return
    end

    Development:CancelCaptures()
    Development:LogOffer("BONUS_ROLL_RESULT context")
    Development:Log("BONUS_ROLL_RESULT", "type", resultType, "itemLink", itemLink,
        "quantity", quantity, "reportedSpec", specID, "currencyID", currencyID,
        "secondary", isSecondaryResult)
end

local function handlePreyQuestEnd(event, questID)
    if not enabled or not NS:IsPublicPositiveInteger(questID)
        or (questID ~= observedPreyQuestID and questID ~= recentPreyQuestID)
    then
        return
    end

    logPreyQuest(questID, event)
    Development:LogPreyContext(event)
    Development:LogPendingPrompts(event)
end

local function handleWorldChange(event, isInitialLogin, isReloadingUI)
    if not enabled then
        return
    end

    Development:Log(event, "initialLogin", isInitialLogin, "reloadingUI", isReloadingUI)
    Development:LogOffer(event)
    if event == "PLAYER_LEAVING_WORLD" then
        Development:CancelCaptures()
    else
        -- Re-read after Blizzard has had a frame to restore the native offer.
        Development:StartCapture(event)
    end
end

NS:RegisterInitializer(function()
    enabled = NS.DB:Get("developmentMode") == true
    NS:RegisterEvent("PLAYER_LOGIN", function()
        if enabled then
            NS:Print("Development mode is enabled for this character; diagnostics go to chat. Use /bbr dev off to disable.")
            logVersions()
            Development:LogPreyContext("PLAYER_LOGIN")
        end
    end)
    NS:RegisterEvent("QUEST_LOG_UPDATE", observePreyQuest)
    NS:RegisterEvent("QUEST_TURNED_IN", handlePreyQuestEnd)
    NS:RegisterEvent("QUEST_REMOVED", handlePreyQuestEnd)
    NS:RegisterEvent("PLAYER_LEAVING_WORLD", handleWorldChange)
    NS:RegisterEvent("PLAYER_ENTERING_WORLD", handleWorldChange)
    NS:RegisterEvent("SPELL_CONFIRMATION_PROMPT", function(_, _spellID, confirmationType)
        if not enabled or NS:IsSecret(confirmationType)
            or confirmationType ~= Enum.ConfirmationPromptUIType.BonusRoll
        then
            return
        end
        Development:LogPreyContext("SPELL_CONFIRMATION_PROMPT")
        Development:LogPendingPrompts("SPELL_CONFIRMATION_PROMPT")
    end)
    NS:RegisterEvent("PLAYER_LOOT_SPEC_UPDATED", handleSpecUpdate)
    NS:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", handleSpecUpdate)
    NS:RegisterEvent("BONUS_ROLL_RESULT", handleResult)
    NS:RegisterEvent("BONUS_ROLL_STARTED", function()
        if enabled then
            Development:CancelCaptures()
            Development:LogOffer("BONUS_ROLL_STARTED")
        end
    end)
    NS:RegisterEvent("BONUS_ROLL_FAILED", function()
        if enabled then
            Development:CancelCaptures()
            Development:LogOffer("BONUS_ROLL_FAILED")
        end
    end)
    NS:RegisterEvent("SPELL_CONFIRMATION_TIMEOUT", function(_, spellID, confirmationType)
        if not enabled or NS:IsSecret(confirmationType)
            or confirmationType ~= Enum.ConfirmationPromptUIType.BonusRoll
        then
            return
        end
        local context = readOfferContext()
        if context and not NS:IsSecret(spellID)
            and spellID == context.raw.spellID
        then
            Development:CancelCaptures()
        end
        Development:Log("SPELL_CONFIRMATION_TIMEOUT", "spellID", spellID)
    end)
    NS:RegisterEvent("TOOLTIP_DATA_UPDATE", function(_, dataInstanceID)
        if not enabled or not hoveredDataInstanceID
            or NS:IsSecret(dataInstanceID) or dataInstanceID ~= hoveredDataInstanceID
        then
            return
        end
        if not hoverTimer then
            hoverTimer = C_Timer.NewTimer(0, logHoveredTooltip)
        end
    end)
end)
