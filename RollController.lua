local _, NS = ...

local Controller = {}
NS.RollController = Controller

local runtimeEnabled = false
local installed = false
local frame
local rollButton
local passButton
local switchPanel
local switchButton
local nativeRollOnClick
local nativePassOnClick
local rollButtonOnClick
local passButtonOnClick
local armedToken
local currentOffer
local generation = 0
local bonusRollActivated = true
local timedOutSpellID
local unsafeHidden = false
local confirmationReference = {}
local challengeState = {}

local LOOT_SPEC_PANEL_WIDTH = 64
local LOOT_SPEC_PANEL_HEIGHT = 76
local LOOT_SPEC_BUTTON_SIZE = 34
local LOOT_SPEC_ICON_SIZE = 22
local UNKNOWN_SPEC_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local delveState = {}

local SNAPSHOT_KEYS = {
    "generation",
    "kind",
    "spellID",
    "endTime",
    "instanceID",
    "encounterID",
    "difficultyID",
    "dungeonMapID",
    "challengeMapID",
    "challengeLevel",
    "completionRank",
    "minimumDifficulty",
    "delveTier",
    "minimumDelveTier",
    "desiredSpecID",
    "desiredLootSpecID",
    "currentSpecID",
    "configured",
    "allowed",
    "reason",
    "sourceName",
}

local function isPublicNumber(value)
    return not NS:IsSecret(value) and type(value) == "number"
end

local function sameValue(left, right)
    if NS:IsSecret(left) or NS:IsSecret(right) then
        return false
    end
    return left == right
end

local function snapshotsMatch(left, right)
    if not left or not right then
        return false
    end

    for index = 1, #SNAPSHOT_KEYS do
        local key = SNAPSHOT_KEYS[index]
        if not sameValue(left[key], right[key]) then
            return false
        end
    end

    return true
end

local function rawOffersMatch(left, right)
    return left
        and right
        and sameValue(left.spellID, right.spellID)
        and sameValue(left.endTime, right.endTime)
        and sameValue(left.instanceID, right.instanceID)
        and sameValue(left.encounterID, right.encounterID)
        and sameValue(left.difficultyID, right.difficultyID)
end

local function captureRawOffer()
    if not frame then
        return nil
    end
    local state = frame.state
    if NS:IsSecret(state)
        or state ~= "prompt"
        or not NS:IsPublicPositiveInteger(frame.spellID)
        or not NS:IsPublicPositiveInteger(frame.difficultyID)
        or not isPublicNumber(frame.endTime)
    then
        return nil
    end
    if NS:IsSecret(frame.instanceID) or NS:IsSecret(frame.encounterID) then
        return nil
    end
    if frame.instanceID ~= nil
        and frame.instanceID ~= 0
        and not NS:IsPublicPositiveInteger(frame.instanceID)
    then
        return nil
    end
    if frame.encounterID ~= nil
        and frame.encounterID ~= 0
        and not NS:IsPublicPositiveInteger(frame.encounterID)
    then
        return nil
    end

    return {
        spellID = frame.spellID,
        endTime = frame.endTime,
        instanceID = frame.instanceID,
        encounterID = frame.encounterID,
        difficultyID = frame.difficultyID,
    }
end

local function isRawOfferActive(raw)
    if not raw or not frame then
        return false
    end
    local state = frame.state
    if NS:IsSecret(state) or state ~= "prompt" then
        return false
    end
    if not rawOffersMatch(raw, captureRawOffer()) then
        return false
    end
    if currentOffer and currentOffer.raw == raw and currentOffer.expired then
        return false
    end

    local now = time()
    if NS:IsSecret(now) or not isPublicNumber(now) then
        return false
    end

    return now < raw.endTime
end

local function getCurrentClassSpec(specID)
    if not NS:IsPublicPositiveInteger(specID) then
        return nil
    end
    return NS.Catalog.specByID[specID]
end

local function resolveLootSpecSelection(selection)
    if selection == 0 then
        local activeSpecID = NS.Catalog:GetActiveSpecID()
        local activeSpec = getCurrentClassSpec(activeSpecID)
        if activeSpec then
            return activeSpec.id, 0
        end
        return nil, nil
    end

    local spec = getCurrentClassSpec(selection)
    if spec then
        return spec.id, spec.id
    end

    return nil, nil
end

local function getActiveDelveTier()
    if not C_DelvesUI or not C_DelvesUI.GetActiveDelveTier then
        return nil
    end

    local ok, tierInfo = pcall(C_DelvesUI.GetActiveDelveTier)
    if not ok or NS:IsSecret(tierInfo) or type(tierInfo) ~= "table" then
        return nil
    end

    if NS:IsPublicPositiveInteger(tierInfo.tier) then
        return tierInfo.tier
    end

    return nil
end

local function rememberActiveDelveTier()
    local tier = getActiveDelveTier()
    if tier then
        delveState.activeTier = tier
    end
end

local function getCompletionChallenge()
    if not C_ChallengeMode or not C_ChallengeMode.GetChallengeCompletionInfo then
        return nil, nil
    end

    local ok, info = pcall(C_ChallengeMode.GetChallengeCompletionInfo)
    if not ok or NS:IsSecret(info) or type(info) ~= "table" then
        return nil, nil
    end

    local mapID = info.mapChallengeModeID
    local level = info.level
    if NS:IsPublicPositiveInteger(mapID)
        and NS:IsPublicPositiveInteger(level)
    then
        return mapID, level
    end

    return nil, nil
end

local function getActiveChallenge()
    if not C_ChallengeMode then
        return nil, nil
    end

    local mapID
    local level
    if C_ChallengeMode.GetActiveChallengeMapID then
        local ok, value = pcall(C_ChallengeMode.GetActiveChallengeMapID)
        if ok and NS:IsPublicPositiveInteger(value) then
            mapID = value
        end
    end
    if C_ChallengeMode.GetActiveKeystoneInfo then
        local ok, value = pcall(C_ChallengeMode.GetActiveKeystoneInfo)
        if ok and NS:IsPublicPositiveInteger(value) then
            level = value
        end
    end

    return mapID, level
end

local function getChallengeForOffer()
    local mapID, level = getActiveChallenge()
    mapID = mapID or challengeState.activeMapID
    level = level or challengeState.activeLevel
    if NS:IsPublicPositiveInteger(mapID)
        and NS:IsPublicPositiveInteger(level)
    then
        challengeState.activeMapID = mapID
        challengeState.activeLevel = level
        challengeState.lastMapID = mapID
        challengeState.lastLevel = level
        return mapID, level
    end

    mapID, level = getCompletionChallenge()
    if mapID and level then
        challengeState.lastMapID = mapID
        challengeState.lastLevel = level
        return mapID, level
    end

    mapID = challengeState.lastMapID
    level = challengeState.lastLevel

    if not NS:IsPublicPositiveInteger(mapID) then
        mapID = nil
    end
    if not NS:IsPublicPositiveInteger(level) then
        level = nil
    end

    return mapID, level
end

local function getDungeonRule(mapID)
    if not NS:IsPublicPositiveInteger(mapID) then
        return nil
    end

    local specSelection = NS.DB:Get(
        "dungeonRules",
        mapID,
        "specializationID"
    )
    local desiredSpecID, desiredLootSpecID = resolveLootSpecSelection(
        specSelection
    )
    local minimumDifficulty = NS.DB:Get(
        "dungeonRules",
        mapID,
        "minimumDifficulty"
    )
    local limits = NS.RuleLimits.dungeonMinimumDifficulty

    if not desiredSpecID
        or not NS:IsPublicPositiveInteger(minimumDifficulty)
        or minimumDifficulty < limits.minimum
        or minimumDifficulty > limits.maximum
    then
        return nil
    end

    return {
        desiredSpecID = desiredSpecID,
        desiredLootSpecID = desiredLootSpecID,
        minimumDifficulty = minimumDifficulty,
    }
end

local function sameDungeonRule(left, right)
    return left
        and right
        and left.desiredSpecID == right.desiredSpecID
        and left.desiredLootSpecID == right.desiredLootSpecID
        and left.minimumDifficulty == right.minimumDifficulty
end

local function findStandardDungeon(raw)
    local matches = NS:IsPublicPositiveInteger(raw.instanceID)
        and NS.Catalog.dungeonByInstance[raw.instanceID] or nil
    if not matches or #matches == 0 then
        return nil, nil, false
    end
    if #matches == 1 then
        return matches[1], getDungeonRule(matches[1].id), false
    end

    local selectedDungeon
    local selectedRule
    for index = 1, #matches do
        local dungeon = matches[index]
        local rule = getDungeonRule(dungeon.id)
        if rule then
            if selectedRule and not sameDungeonRule(selectedRule, rule) then
                return nil, nil, true
            end
            selectedDungeon = selectedDungeon or dungeon
            selectedRule = selectedRule or rule
        end
    end

    return selectedDungeon or matches[1], selectedRule, false
end

local function resolveDungeonOffer(raw)
    local isMythicPlus = raw.difficultyID
        == NS.Catalog.Difficulty.MYTHIC_PLUS
    local mapID
    local level
    local dungeon
    local rule
    local ambiguous = false

    if isMythicPlus then
        mapID, level = getChallengeForOffer()
        dungeon = mapID and NS.Catalog.dungeonByMap[mapID]

        if dungeon
            and NS:IsPublicPositiveInteger(raw.instanceID)
            and NS:IsPublicPositiveInteger(dungeon.journalInstanceID)
            and raw.instanceID ~= dungeon.journalInstanceID
        then
            dungeon = nil
        end

        rule = dungeon and getDungeonRule(mapID) or nil
    else
        dungeon, rule, ambiguous = findStandardDungeon(raw)
        mapID = dungeon and dungeon.id or nil
    end

    local difficultyName
    if isMythicPlus then
        difficultyName = level and "+" .. level or "Mythic+"
    else
        difficultyName = NS.Catalog:GetDifficultyName(raw.difficultyID)
    end
    local sourceName = difficultyName .. " "
        .. (dungeon and dungeon.name or "current-season dungeon")

    local completionRank = NS.Catalog:GetDungeonCompletionRank(
        raw.difficultyID,
        level
    )
    local base = {
        kind = "dungeon",
        sourceName = sourceName,
        dungeonMapID = mapID,
        challengeMapID = isMythicPlus and mapID or nil,
        challengeLevel = level,
        completionRank = completionRank,
    }

    if ambiguous then
        base.configured = false
        base.allowed = false
        base.reason = "multiple seasonal dungeon rows share this instance with different rules"
        return base
    end
    if not dungeon then
        base.configured = false
        base.allowed = false
        base.reason = "the dungeon could not be matched to the current season"
        return base
    end
    if not rule then
        base.configured = false
        base.allowed = false
        base.reason = "no bonus-roll rule is enabled for this dungeon"
        return base
    end

    base.configured = true
    base.desiredSpecID = rule.desiredSpecID
    base.desiredLootSpecID = rule.desiredLootSpecID
    base.minimumDifficulty = rule.minimumDifficulty

    if not completionRank then
        base.allowed = false
        base.reason = isMythicPlus
            and "the completed key level could not be verified"
            or "the dungeon difficulty could not be verified"
        return base
    end

    if completionRank < rule.minimumDifficulty then
        local actual = NS.Catalog:GetDungeonThresholdLabel(completionRank)
        local minimum = NS.Catalog:GetDungeonThresholdLabel(
            rule.minimumDifficulty
        )
        base.allowed = false
        base.reason = "the " .. actual .. " completion is below your "
            .. minimum .. " minimum"
        return base
    end

    base.allowed = true
    return base
end

local function getContentRule(ruleKey, hasTier)
    local specSelection = NS.DB:Get(
        "contentRules",
        ruleKey,
        "specializationID"
    )
    local desiredSpecID, desiredLootSpecID = resolveLootSpecSelection(
        specSelection
    )
    if not desiredSpecID then
        return nil
    end

    local rule = {
        desiredSpecID = desiredSpecID,
        desiredLootSpecID = desiredLootSpecID,
    }
    if hasTier then
        local minimumTier = NS.DB:Get(
            "contentRules",
            ruleKey,
            "minimumTier"
        )
        local limits = NS.RuleLimits.delveMinimumTier
        if not NS:IsPublicPositiveInteger(minimumTier)
            or minimumTier < limits.minimum
            or minimumTier > limits.maximum
        then
            return nil
        end
        rule.minimumTier = minimumTier
    end

    return rule
end

local function resolveDelveOffer()
    local tier = currentOffer and currentOffer.delveTier or nil
    local rule = getContentRule("delves", true)
    local sourceName = tier and "Tier " .. tier .. " Bountiful Delve"
        or "Bountiful Delve"
    local result = {
        kind = "delve",
        sourceName = sourceName,
        delveTier = tier,
    }

    if not rule then
        result.configured = false
        result.allowed = false
        result.reason = "the Delves bonus-roll rule is disabled"
        return result
    end

    result.configured = true
    result.desiredSpecID = rule.desiredSpecID
    result.desiredLootSpecID = rule.desiredLootSpecID
    result.minimumDelveTier = rule.minimumTier

    if not NS:IsPublicPositiveInteger(tier) then
        result.allowed = false
        result.reason = "the completed Delve tier could not be verified"
        return result
    end
    if tier < rule.minimumTier then
        result.allowed = false
        result.reason = "Tier " .. tier .. " is below your Tier "
            .. rule.minimumTier .. " minimum"
        return result
    end

    result.allowed = true
    return result
end

local function resolveWorldOffer(raw)
    local boss = raw.encounterID
        and NS.Catalog.worldBossByEncounter[raw.encounterID]

    if boss then
        local result = {
            kind = "worldBoss",
            sourceName = boss.name,
        }

        if NS:IsPublicPositiveInteger(raw.instanceID)
            and raw.instanceID ~= boss.instanceID
        then
            result.configured = false
            result.allowed = false
            result.reason = "the world-boss encounter did not match its current-season instance"
            return result
        end

        local specSelection = NS.DB:Get(
            "contentRules",
            "worldBosses",
            boss.id,
            "specializationID"
        )
        local desiredSpecID, desiredLootSpecID = resolveLootSpecSelection(
            specSelection
        )
        if not desiredSpecID then
            result.configured = false
            result.allowed = false
            result.reason = "the " .. boss.name .. " bonus-roll rule is disabled"
            return result
        end

        result.configured = true
        result.allowed = true
        result.desiredSpecID = desiredSpecID
        result.desiredLootSpecID = desiredLootSpecID
        return result
    end

    if NS:IsPublicPositiveInteger(raw.encounterID) then
        return {
            kind = "worldBoss",
            configured = false,
            allowed = false,
            reason = "the world-boss encounter is not in the current-season catalog",
            sourceName = "Unknown World Boss",
        }
    end

    local rule = getContentRule("world", false)
    if not rule then
        return {
            kind = "prey",
            configured = false,
            allowed = false,
            reason = "the Nightmare Prey bonus-roll rule is disabled",
            sourceName = "Nightmare Prey",
        }
    end

    return {
        kind = "prey",
        configured = true,
        allowed = true,
        desiredSpecID = rule.desiredSpecID,
        desiredLootSpecID = rule.desiredLootSpecID,
        sourceName = "Nightmare Prey",
    }
end

local function resolveRaidOffer(raw)
    local difficultyID = NS.Catalog:CanonicalDifficultyID(raw.difficultyID)
    local instance = raw.instanceID
        and NS.Catalog.raidByInstance[raw.instanceID]
    local encounter = instance
        and raw.encounterID
        and instance.encounterByID[raw.encounterID]
    local difficulty = instance
        and instance.difficultyByID[difficultyID]
    local difficultyName = NS.Catalog:GetDifficultyName(difficultyID)
    local encounterName = encounter and encounter.name or "unknown encounter"
    local sourceName = difficultyName .. " " .. encounterName

    if not instance or not encounter or not difficulty then
        return {
            kind = "raid",
            configured = false,
            allowed = false,
            reason = "the encounter and difficulty are not in the current-season catalog",
            sourceName = sourceName,
        }
    end

    local specSelection = NS.DB:Get(
        "raidRules",
        instance.id,
        encounter.id,
        difficultyID
    )
    local desiredSpecID, desiredLootSpecID = resolveLootSpecSelection(
        specSelection
    )
    if not desiredSpecID then
        return {
            kind = "raid",
            configured = false,
            allowed = false,
            reason = "no bonus-roll rule is enabled for this encounter and difficulty",
            sourceName = sourceName,
        }
    end

    return {
        kind = "raid",
        configured = true,
        allowed = true,
        desiredSpecID = desiredSpecID,
        desiredLootSpecID = desiredLootSpecID,
        sourceName = sourceName,
    }
end

local function resolveOffer(raw)
    if not raw then
        return nil
    end

    local result
    if NS.Catalog:IsDungeonDifficulty(raw.difficultyID) then
        result = resolveDungeonOffer(raw)
    elseif raw.difficultyID == NS.Catalog.Difficulty.DELVE then
        result = resolveDelveOffer()
    elseif raw.difficultyID == NS.Catalog.Difficulty.WORLD_BOSS then
        result = resolveWorldOffer(raw)
    else
        result = resolveRaidOffer(raw)
    end

    result.generation = currentOffer and currentOffer.generation or generation
    result.spellID = raw.spellID
    result.endTime = raw.endTime
    result.instanceID = raw.instanceID
    result.encounterID = raw.encounterID
    result.difficultyID = NS.Catalog:CanonicalDifficultyID(
        raw.difficultyID
    )
    result.currentSpecID = NS.Catalog:GetEffectiveLootSpecID()

    return result
end

local function hideConfirmation()
    if StaticPopup_IsCustomGenericConfirmationShown
        and StaticPopup_IsCustomGenericConfirmationShown(
            confirmationReference
        )
    then
        StaticPopup_Hide("GENERIC_CONFIRMATION")
    end
end

local function canEnableRollButton()
    return runtimeEnabled
        and bonusRollActivated
        and currentOffer
        and isRawOfferActive(currentOffer.raw)
end

local function disarm(hidePopup, reenableButton)
    local wasArmed = armedToken ~= nil
    armedToken = nil

    if wasArmed and hidePopup then
        hideConfirmation()
    end

    if reenableButton and rollButton and canEnableRollButton() then
        rollButton:Enable()
    end
end

local function refreshSwitchPanel(resolved)
    if not switchPanel then
        return
    end

    switchPanel:Hide()
    switchButton:Hide()
    switchButton.configuredSpecID = nil
    switchButton.configuredLootSpecID = nil
    switchButton.specIcon:SetTexture(nil)

    if not runtimeEnabled
        or not currentOffer
        or not isRawOfferActive(currentOffer.raw)
        or not frame:IsShown()
    then
        return
    end

    resolved = resolved or resolveOffer(currentOffer.raw)
    if not resolved or not resolved.desiredSpecID then
        return
    end
    if resolved.currentSpecID == resolved.desiredSpecID then
        return
    end

    local spec = getCurrentClassSpec(resolved.desiredSpecID)
    if not spec then
        return
    end

    switchButton.configuredSpecID = spec.id
    switchButton.configuredLootSpecID = resolved.desiredLootSpecID
    local icon = NS:IsPublicPositiveInteger(spec.icon)
        and spec.icon or UNKNOWN_SPEC_ICON
    switchButton.specIcon:SetTexture(icon)
    switchButton:Show()
    switchPanel:Show()
end

local function hideCurrentOffer(reason, resolved)
    if not currentOffer or not isRawOfferActive(currentOffer.raw) then
        return false
    end

    disarm(true, false)
    refreshSwitchPanel(nil)

    resolved = resolved or resolveOffer(currentOffer.raw)
    local sourceName = resolved and resolved.sourceName or "unknown source"
    currentOffer.hidden = true

    if frame:IsShown() then
        GroupLootContainer_RemoveFrame(GroupLootContainer, frame)
    end

    NS:Print(
        "Bonus roll hidden for " .. sourceName .. ": " .. reason
        .. ". Use /bbr show to view it again while the offer is active."
    )
    return true
end

local function ensureScriptsOwned()
    return installed
        and rollButton:GetScript("OnClick") == rollButtonOnClick
        and passButton:GetScript("OnClick") == passButtonOnClick
end

local function buildConfirmationText(snapshot)
    local currentName = NS.Catalog:GetSpecName(snapshot.currentSpecID)

    if snapshot.configured
        and snapshot.allowed
        and snapshot.currentSpecID == snapshot.desiredSpecID
    then
        return "Use a bonus roll on " .. snapshot.sourceName .. " in "
            .. currentName .. " loot specialization?", "Use Bonus Roll", false
    end

    local lines = {}
    if not snapshot.allowed then
        lines[#lines + 1] = "This offer does not match your configured rules: "
            .. snapshot.reason .. "."
    end
    if snapshot.desiredSpecID
        and snapshot.currentSpecID ~= snapshot.desiredSpecID
    then
        lines[#lines + 1] = "Configured loot specialization: "
            .. NS.Catalog:GetSpecName(snapshot.desiredSpecID)
        lines[#lines + 1] = "Current loot specialization: "
            .. currentName
        lines[#lines + 1] = "Changing loot specialization now will change which specialization this roll uses."
    else
        lines[#lines + 1] = "Current loot specialization: " .. currentName
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "Are you sure you wish to use a bonus roll on "
        .. snapshot.sourceName .. " anyway?"

    return table.concat(lines, "\n"), "Roll Anyway", true
end

local function currentSnapshot()
    if not currentOffer or not isRawOfferActive(currentOffer.raw) then
        return nil
    end
    return resolveOffer(currentOffer.raw)
end

local function confirmArmedToken(token)
    if armedToken ~= token then
        return
    end

    local snapshot = currentSnapshot()
    if not runtimeEnabled
        or not ensureScriptsOwned()
        or not snapshotsMatch(token.snapshot, snapshot)
    then
        disarm(false, true)
        NS:Print("The bonus-roll state changed. Click Blizzard's Roll button again to review a fresh confirmation.")
        return
    end

    local callback = nativeRollOnClick
    local button = rollButton
    local mouseButton = token.mouseButton
    local down = token.down

    armedToken = nil
    if not callback or not button then
        return
    end

    callback(button, mouseButton, down)
end

local function cancelArmedToken(token)
    if armedToken == token then
        disarm(false, true)
    end
end

local function handleRollButtonClick(self, mouseButton, down)
    if self ~= rollButton
        or not runtimeEnabled
        or not bonusRollActivated
        or armedToken
        or not ensureScriptsOwned()
    then
        return
    end

    local snapshot = currentSnapshot()
    if not snapshot then
        return
    end

    local token = {
        snapshot = snapshot,
        mouseButton = mouseButton,
        down = down,
    }
    armedToken = token
    rollButton:Disable()

    local text, acceptText, showAlert = buildConfirmationText(snapshot)
    if not StaticPopup_ShowCustomGenericConfirmation then
        disarm(false, true)
        NS:Print("Unable to open the bonus-roll confirmation; no roll was used.")
        return
    end

    StaticPopup_ShowCustomGenericConfirmation({
        text = text,
        callback = function()
            confirmArmedToken(token)
        end,
        cancelCallback = function()
            cancelArmedToken(token)
        end,
        acceptText = acceptText,
        cancelText = "Cancel",
        showAlert = showAlert,
        referenceKey = confirmationReference,
    })

    if StaticPopup_IsCustomGenericConfirmationShown
        and not StaticPopup_IsCustomGenericConfirmationShown(
            confirmationReference
        )
    then
        disarm(false, true)
        NS:Print("Unable to open the bonus-roll confirmation; no roll was used.")
    end
end

local function handlePassButtonClick(self)
    if self ~= passButton or not runtimeEnabled then
        return
    end

    local resolved = currentSnapshot()
    hideCurrentOffer("you clicked No", resolved)
end

rollButtonOnClick = function(self, mouseButton, down)
    handleRollButtonClick(self, mouseButton, down)
end

passButtonOnClick = function(self)
    handlePassButtonClick(self)
end

local function handleSwitchButtonClick(self)
    if self ~= switchButton or not runtimeEnabled then
        return
    end

    disarm(true, true)
    local snapshot = currentSnapshot()
    local desiredSpecID = snapshot and snapshot.desiredSpecID
    local desiredLootSpecID = snapshot and snapshot.desiredLootSpecID
    local spec = getCurrentClassSpec(desiredSpecID)
    if not spec
        or self.configuredSpecID ~= desiredSpecID
        or self.configuredLootSpecID ~= desiredLootSpecID
        or snapshot.currentSpecID == desiredSpecID
    then
        refreshSwitchPanel(snapshot)
        return
    end

    SetLootSpecialization(desiredLootSpecID)
    refreshSwitchPanel(currentSnapshot())
end

local function createButtonStateTexture(button, layer, atlas)
    local texture = button:CreateTexture(nil, layer)
    texture:SetAllPoints(button)
    texture:SetAtlas(atlas, false)
    return texture
end

local function createSwitchPanel()
    switchPanel = CreateFrame(
        "Frame",
        nil,
        frame.PromptFrame,
        "TooltipBackdropTemplate"
    )
    switchPanel:SetSize(LOOT_SPEC_PANEL_WIDTH, LOOT_SPEC_PANEL_HEIGHT)
    switchPanel:SetPoint("LEFT", frame, "RIGHT", 6, 0)
    switchPanel:SetFrameLevel(frame.PromptFrame:GetFrameLevel() + 10)

    local title = switchPanel:CreateFontString(
        nil,
        "OVERLAY",
        "GameFontNormalSmall"
    )
    title:SetPoint("TOP", switchPanel, "TOP", 0, -8)
    title:SetText("Loot Spec")
    switchPanel.title = title

    switchButton = CreateFrame(
        "Button",
        nil,
        switchPanel
    )
    switchButton:SetSize(LOOT_SPEC_BUTTON_SIZE, LOOT_SPEC_BUTTON_SIZE)
    switchButton:SetPoint("BOTTOM", switchPanel, "BOTTOM", 0, 7)

    local normalTexture = createButtonStateTexture(
        switchButton,
        "BACKGROUND",
        "common-button-tertiary-square-normal"
    )
    switchButton:SetNormalTexture(normalTexture)

    local pushedTexture = createButtonStateTexture(
        switchButton,
        "BACKGROUND",
        "common-button-tertiary-square-pressed"
    )
    switchButton:SetPushedTexture(pushedTexture)

    local highlightTexture = createButtonStateTexture(
        switchButton,
        "HIGHLIGHT",
        "common-button-tertiary-square-normal"
    )
    highlightTexture:SetBlendMode("ADD")
    switchButton:SetHighlightTexture(highlightTexture)

    local specIcon = switchButton:CreateTexture(nil, "ARTWORK")
    specIcon:SetSize(LOOT_SPEC_ICON_SIZE, LOOT_SPEC_ICON_SIZE)
    specIcon:SetPoint("CENTER")
    specIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    switchButton.specIcon = specIcon

    switchButton:SetScript("OnClick", handleSwitchButtonClick)
    switchButton:SetScript("OnEnter", function(self)
        local specID = self.configuredSpecID
        if not specID then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Change Loot Specialization to "
            .. NS.Catalog:GetSpecName(specID) .. ".")
        GameTooltip:AddLine(
            "This button only changes your loot specialization. It does not use the bonus roll.",
            1,
            1,
            1,
            true
        )
        GameTooltip:Show()
    end)
    switchButton:SetScript("OnLeave", GameTooltip_Hide)
    switchButton:Hide()
    switchPanel:Hide()
end

local function install()
    if installed then
        return true
    end

    if not BonusRollFrame and C_AddOns and C_AddOns.LoadAddOn then
        pcall(C_AddOns.LoadAddOn, "Blizzard_UIPanels_Game")
    end

    frame = BonusRollFrame
    if not frame
        or not frame.PromptFrame
        or not frame.PromptFrame.RollButton
        or not frame.PromptFrame.PassButton
        or not GroupLootContainer_AddFrame
        or not GroupLootContainer_RemoveFrame
        or not BonusRollFrame_StartBonusRoll
    then
        return false
    end

    rollButton = frame.PromptFrame.RollButton
    passButton = frame.PromptFrame.PassButton
    nativeRollOnClick = rollButton:GetScript("OnClick")
    nativePassOnClick = passButton:GetScript("OnClick")
    if type(nativeRollOnClick) ~= "function"
        or type(nativePassOnClick) ~= "function"
    then
        return false
    end

    createSwitchPanel()
    frame:HookScript("OnHide", function()
        if runtimeEnabled then
            disarm(true, false)
            refreshSwitchPanel(nil)
        end
    end)
    hooksecurefunc("BonusRollFrame_StartBonusRoll", function()
        Controller:OnOfferStarted()
    end)

    installed = true
    return true
end

local function enableScripts()
    if not install() then
        return false
    end

    local currentRollScript = rollButton:GetScript("OnClick")
    local currentPassScript = passButton:GetScript("OnClick")
    if currentRollScript ~= nativeRollOnClick
        and currentRollScript ~= rollButtonOnClick
    then
        return false
    end
    if currentPassScript ~= nativePassOnClick
        and currentPassScript ~= passButtonOnClick
    then
        return false
    end

    rollButton:SetScript("OnClick", rollButtonOnClick)
    passButton:SetScript("OnClick", passButtonOnClick)
    return true
end

local function restoreScripts()
    if not installed then
        return
    end
    if rollButton:GetScript("OnClick") == rollButtonOnClick then
        rollButton:SetScript("OnClick", nativeRollOnClick)
    end
    if passButton:GetScript("OnClick") == passButtonOnClick then
        passButton:SetScript("OnClick", nativePassOnClick)
    end
end

function Controller:OnOfferStarted()
    if not install() then
        return
    end

    local raw = captureRawOffer()
    if not raw then
        if runtimeEnabled and frame and frame:IsShown() then
            unsafeHidden = true
            GroupLootContainer_RemoveFrame(GroupLootContainer, frame)
            NS:Print("Bonus roll hidden because its state could not be safely inspected. Disable BetterBonusRolls to restore Blizzard's native prompt while the offer is active.")
        end
        return
    end

    if not currentOffer or not rawOffersMatch(currentOffer.raw, raw) then
        disarm(true, false)
        generation = generation + 1
        local delveTier
        if raw.difficultyID == NS.Catalog.Difficulty.DELVE then
            delveTier = getActiveDelveTier() or delveState.activeTier
        end
        delveState.activeTier = nil
        currentOffer = {
            generation = generation,
            raw = raw,
            hidden = false,
            expired = false,
            delveTier = delveTier,
        }
        unsafeHidden = false
        timedOutSpellID = nil
    else
        currentOffer.raw = raw
        if raw.difficultyID == NS.Catalog.Difficulty.DELVE
            and not currentOffer.delveTier
        then
            currentOffer.delveTier = getActiveDelveTier()
                or delveState.activeTier
            delveState.activeTier = nil
        end
    end

    bonusRollActivated = true

    if not runtimeEnabled then
        return
    end
    if not ensureScriptsOwned() then
        hideCurrentOffer("another addon changed the bonus-roll buttons")
        NS:Print("BetterBonusRolls disabled itself because another addon changed the bonus-roll buttons.")
        NS:SetEnabled(false)
        return
    end

    local resolved = resolveOffer(raw)
    if not resolved or not resolved.allowed then
        hideCurrentOffer(
            resolved and resolved.reason
                or "the offer could not be safely evaluated",
            resolved
        )
        return
    end

    currentOffer.hidden = false
    refreshSwitchPanel(resolved)
end

function Controller:SetEnabled(enabled)
    enabled = enabled == true
    if enabled == runtimeEnabled then
        return true
    end

    if enabled then
        if not enableScripts() then
            NS:Print("The Blizzard bonus-roll buttons could not be safely controlled. BetterBonusRolls remains disabled.")
            return false
        end

        runtimeEnabled = true
        self:OnOfferStarted()
        return runtimeEnabled
    end

    local shouldRestore = unsafeHidden
        or (currentOffer
            and currentOffer.hidden
            and isRawOfferActive(currentOffer.raw))

    runtimeEnabled = false
    disarm(true, false)
    refreshSwitchPanel(nil)
    restoreScripts()

    if shouldRestore and frame and not frame:IsShown() then
        GroupLootContainer_AddFrame(GroupLootContainer, frame)
        if not bonusRollActivated then
            rollButton:Disable()
        end
        unsafeHidden = false
        if currentOffer then
            currentOffer.hidden = false
        end
    end

    return true
end

function Controller:OnConfigurationChanged()
    disarm(true, true)
    if not runtimeEnabled
        or not currentOffer
        or not isRawOfferActive(currentOffer.raw)
    then
        return
    end

    local resolved = resolveOffer(currentOffer.raw)
    if frame:IsShown() and (not resolved or not resolved.allowed) then
        hideCurrentOffer(
            resolved and resolved.reason
                or "the offer could not be safely evaluated",
            resolved
        )
    else
        refreshSwitchPanel(resolved)
    end
end

function Controller:ShowCurrent()
    if unsafeHidden then
        NS:Print("This offer could not be safely inspected. Disable BetterBonusRolls to restore Blizzard's native prompt.")
        return false
    end
    if not currentOffer or not isRawOfferActive(currentOffer.raw) then
        NS:Print("No active bonus roll can be shown.")
        return false
    end
    if frame:IsShown() then
        NS:Print("The bonus roll is already showing.")
        return true
    end

    currentOffer.hidden = false
    GroupLootContainer_AddFrame(GroupLootContainer, frame)
    if not bonusRollActivated then
        rollButton:Disable()
    end
    refreshSwitchPanel(resolveOffer(currentOffer.raw))
    return true
end

function Controller:HideCurrentByCommand()
    if not currentOffer
        or not isRawOfferActive(currentOffer.raw)
        or not frame:IsShown()
    then
        NS:Print("There is no active bonus roll on screen to hide.")
        return false
    end

    return hideCurrentOffer("you used /bbr hide")
end

function Controller:IsEnabled()
    return runtimeEnabled
end

function Controller:GetStatusText()
    local mode = runtimeEnabled and "enabled" or "disabled"
    if unsafeHidden then
        return mode .. "; an uninspectable bonus-roll offer is hidden"
    end
    if not currentOffer or not isRawOfferActive(currentOffer.raw) then
        return mode .. "; no active bonus-roll offer"
    end

    local resolved = resolveOffer(currentOffer.raw)
    local sourceName = resolved and resolved.sourceName or "unknown source"
    local visibility = frame:IsShown() and "shown" or "hidden"
    return mode .. "; " .. sourceName .. " is " .. visibility
end

local function handleLootSpecUpdate(event, unit)
    if event == "PLAYER_SPECIALIZATION_CHANGED" and unit ~= "player" then
        return
    end

    disarm(true, true)
    refreshSwitchPanel(currentSnapshot())
end

local function handleTimeout(_, spellID, confirmationType)
    local bonusRollType = Enum
        and Enum.ConfirmationPromptUIType
        and Enum.ConfirmationPromptUIType.BonusRoll
    if NS:IsSecret(confirmationType)
        or NS:IsSecret(spellID)
        or confirmationType ~= bonusRollType
        or not currentOffer
        or not sameValue(spellID, currentOffer.raw.spellID)
    then
        return
    end

    if timedOutSpellID == spellID then
        return
    end
    timedOutSpellID = spellID
    currentOffer.expired = true

    if not runtimeEnabled then
        return
    end

    disarm(true, false)
    refreshSwitchPanel(nil)
    currentOffer.hidden = false
    NS:Print("Bonus roll expired without being used and can no longer be restored.")
end

local function handleBonusRollStarted()
    disarm(true, false)
    refreshSwitchPanel(nil)
    if currentOffer then
        currentOffer.hidden = false
    end
end

local function handleBonusRollActivation(event)
    bonusRollActivated = event == "BONUS_ROLL_ACTIVATE"
    if bonusRollActivated and not armedToken and canEnableRollButton() then
        rollButton:Enable()
    elseif not bonusRollActivated then
        disarm(true, false)
    end
end

local function handleChallengeStart(_, mapID)
    challengeState.activeMapID = NS:IsPublicPositiveInteger(mapID)
        and mapID or nil
    local _, level = getActiveChallenge()
    challengeState.activeLevel = level
    challengeState.lastMapID = challengeState.activeMapID
    challengeState.lastLevel = level
end

local function handleChallengeCompleted()
    local mapID, level = getCompletionChallenge()
    if mapID and level then
        challengeState.lastMapID = mapID
        challengeState.lastLevel = level
    end
end

local function handleChallengeRewards(_, mapID)
    if NS:IsPublicPositiveInteger(mapID) then
        challengeState.lastMapID = mapID
    end
    handleChallengeCompleted()
end

local function handleChallengeReset()
    challengeState.activeMapID = nil
    challengeState.activeLevel = nil
end

local function handleAddonLoaded(_, loadedAddon)
    if loadedAddon == "BonusRollConfirm" or loadedAddon == "BonusRollGate" then
        if runtimeEnabled then
            NS:Print(loadedAddon .. " loaded, so BetterBonusRolls has been disabled. Disable it and reload before re-enabling.")
            NS:SetEnabled(false)
        end
        return
    end

    if loadedAddon == "Blizzard_UIPanels_Game" then
        install()
    end
end

NS:RegisterInitializer(function()
    install()
    NS:RegisterEvent("PLAYER_LOGIN", function()
        install()
        rememberActiveDelveTier()
    end)
    NS:RegisterEvent("ADDON_LOADED", handleAddonLoaded)
    NS:RegisterEvent("PLAYER_LOOT_SPEC_UPDATED", handleLootSpecUpdate)
    NS:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", handleLootSpecUpdate)
    NS:RegisterEvent("SPELL_CONFIRMATION_TIMEOUT", handleTimeout)
    NS:RegisterEvent("BONUS_ROLL_STARTED", handleBonusRollStarted)
    NS:RegisterEvent("BONUS_ROLL_DEACTIVATE", handleBonusRollActivation)
    NS:RegisterEvent("BONUS_ROLL_ACTIVATE", handleBonusRollActivation)
    NS:RegisterEvent("CHALLENGE_MODE_START", handleChallengeStart)
    NS:RegisterEvent("CHALLENGE_MODE_COMPLETED", handleChallengeCompleted)
    NS:RegisterEvent("CHALLENGE_MODE_COMPLETED_REWARDS", handleChallengeRewards)
    NS:RegisterEvent("CHALLENGE_MODE_RESET", handleChallengeReset)
    NS:RegisterEvent("ACTIVE_DELVE_DATA_UPDATE", rememberActiveDelveTier)
end)
