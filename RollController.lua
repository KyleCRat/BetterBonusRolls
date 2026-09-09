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
local resultCandidate
local generation = 0
local bonusRollActivated = true
local timedOutSpellID
local unsafeHidden = false
local confirmationReference = {}
local challengeRun
local challengeRetryTimer
local challengeRetryGeneration = 0

local LOOT_SPEC_PANEL_WIDTH = 64
local LOOT_SPEC_PANEL_HEIGHT = 76
local LOOT_SPEC_BUTTON_SIZE = 34
local LOOT_SPEC_ICON_SIZE = 22
local PERSISTED_OFFER_EXPIRY_GRACE = 5
local CHALLENGE_RUN_MAX_AGE = 60 * 60
local CHALLENGE_RETRY_DELAYS = { 0.1, 0.25, 0.5, 1, 2 }
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

local function getPublicTimestamp()
    local now = time()
    if not isPublicNumber(now) or now <= 0 then
        return nil
    end
    return now
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

local function copySnapshot(snapshot)
    local copy = {}

    for index = 1, #SNAPSHOT_KEYS do
        local key = SNAPSHOT_KEYS[index]

        copy[key] = snapshot[key]
    end

    return copy
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

local function persistedOffersMatch(left, right)
    return left
        and right
        and sameValue(left.spellID, right.spellID)
        and sameValue(left.instanceID, right.instanceID)
        and sameValue(left.encounterID, right.encounterID)
        and sameValue(left.difficultyID, right.difficultyID)
end

local function copyRawOffer(raw)
    return {
        spellID = raw.spellID,
        endTime = raw.endTime,
        instanceID = raw.instanceID,
        encounterID = raw.encounterID,
        difficultyID = raw.difficultyID,
    }
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

    local now = getPublicTimestamp()
    if not now then
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
            return {
                desiredSpecID = activeSpec.id,
                desiredLootSpecID = 0,
            }
        end

        return nil
    end

    local spec = getCurrentClassSpec(selection)
    if spec then
        return {
            desiredSpecID = spec.id,
            desiredLootSpecID = spec.id,
        }
    end

    return nil
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
    local info = C_ChallengeMode.GetChallengeCompletionInfo()
    if NS:IsSecret(info) or type(info) ~= "table" then
        return nil
    end

    local mapID = info.mapChallengeModeID
    local level = info.level
    if NS:IsPublicPositiveInteger(mapID)
        and NS:IsPublicPositiveInteger(level)
    then
        return {
            mapID = mapID,
            level = level,
        }
    end

    return nil
end

local function getActiveChallenge()
    local mapID = C_ChallengeMode.GetActiveChallengeMapID()
    local level = C_ChallengeMode.GetActiveKeystoneInfo()

    if not NS:IsPublicPositiveInteger(mapID) then
        mapID = nil
    end
    if not NS:IsPublicPositiveInteger(level) then
        level = nil
    end

    if not mapID and not level then
        return nil
    end

    return {
        mapID = mapID,
        level = level,
    }
end

local function isPublicOptionalPositiveInteger(value)
    return value == nil or NS:IsPublicPositiveInteger(value)
end

local function isPublicOptionalNonNegativeInteger(value)
    return value == nil
        or (not NS:IsSecret(value)
            and type(value) == "number"
            and value >= 0
            and value % 1 == 0)
end

local function isChallengeRunValid(run)
    if NS:IsSecret(run)
        or type(run) ~= "table"
        or not NS:IsPublicPositiveInteger(run.mapID)
        or not isPublicOptionalPositiveInteger(run.level)
        or not NS:IsPublicPositiveInteger(run.startedAt)
        or not isPublicOptionalPositiveInteger(run.completedAt)
        or not isPublicOptionalPositiveInteger(run.gameMapID)
        or not isPublicOptionalPositiveInteger(run.journalInstanceID)
    then
        return false
    end

    if not run.level and (run.completedAt or run.offer) then
        return false
    end

    local offer = run.offer
    if offer == nil then
        return true
    end

    return not NS:IsSecret(offer)
        and type(offer) == "table"
        and NS:IsPublicPositiveInteger(offer.spellID)
        and isPublicNumber(offer.endTime)
        and offer.endTime > 0
        and isPublicOptionalNonNegativeInteger(offer.instanceID)
        and isPublicOptionalNonNegativeInteger(offer.encounterID)
        and NS:IsPublicPositiveInteger(offer.difficultyID)
end

local function persistChallengeRun(run)
    challengeRun = run
    NS.DB:Set("challengeRun", run)
end

local function cancelChallengeRetry()
    local timer = challengeRetryTimer

    challengeRetryTimer = nil
    if timer then
        timer:Cancel()
    end
end

local function beginChallengeRetrySeries()
    cancelChallengeRetry()
    challengeRetryGeneration = challengeRetryGeneration + 1
    return challengeRetryGeneration
end

local function isChallengeTimestampFresh(timestamp)
    if not NS:IsPublicPositiveInteger(timestamp) then
        return false
    end

    local now = getPublicTimestamp()
    return now and now <= timestamp + CHALLENGE_RUN_MAX_AGE
end

local function expireStaleUnboundChallengeRun()
    if not challengeRun or challengeRun.offer then
        return
    end

    local timestamp = challengeRun.completedAt or challengeRun.startedAt
    if not isChallengeTimestampFresh(timestamp) then
        persistChallengeRun(nil)
    end
end

local function restoreChallengeRun()
    local restored = NS.DB:GetCopy("challengeRun")
    if not isChallengeRunValid(restored) then
        persistChallengeRun(nil)
        return
    end

    local now = getPublicTimestamp()
    if restored.offer
        and now
        and now > restored.offer.endTime
            + PERSISTED_OFFER_EXPIRY_GRACE
    then
        persistChallengeRun(nil)
        return
    end

    challengeRun = restored
    expireStaleUnboundChallengeRun()
end

local function buildChallengeRun(mapID, level, startedAt)
    if not NS:IsPublicPositiveInteger(mapID)
        or not isPublicOptionalPositiveInteger(level)
        or not NS:IsPublicPositiveInteger(startedAt)
    then
        return nil
    end

    local dungeon = NS.Catalog.dungeonByMap[mapID]
    return {
        mapID = mapID,
        level = level,
        startedAt = startedAt,
        gameMapID = dungeon and dungeon.gameMapID or nil,
        journalInstanceID = dungeon and dungeon.journalInstanceID or nil,
    }
end

local function buildActiveChallengeRun(active, preserveExisting)
    if not active
        or not NS:IsPublicPositiveInteger(active.mapID)
        or not NS:IsPublicPositiveInteger(active.level)
    then
        return nil
    end

    local startedAt = getPublicTimestamp()
    local previous = challengeRun
    local sameRun = preserveExisting
        and isChallengeRunValid(previous)
        and previous.mapID == active.mapID
        and (not previous.level or previous.level == active.level)
    if sameRun then
        startedAt = previous.startedAt
    end

    local run = buildChallengeRun(active.mapID, active.level, startedAt)
    if not run then
        return nil
    end

    if sameRun and previous.level == active.level then
        run.completedAt = previous.completedAt
        if previous.offer then
            run.offer = copyRawOffer(previous.offer)
        end
    end

    return run
end

local function reconcileActiveChallenge()
    local run = buildActiveChallengeRun(getActiveChallenge(), true)
    if run then
        persistChallengeRun(run)
    end
end

local function challengeRunMatchesSource(run, raw)
    if not isChallengeRunValid(run)
        or not NS:IsPublicPositiveInteger(run.level)
    then
        return false
    end

    local dungeon = NS.Catalog.dungeonByMap[run.mapID]
    if not dungeon
        or not NS:IsPublicPositiveInteger(raw.instanceID)
        or not NS:IsPublicPositiveInteger(dungeon.journalInstanceID)
        or raw.instanceID ~= dungeon.journalInstanceID
    then
        return false
    end
    if run.journalInstanceID
        and run.journalInstanceID ~= dungeon.journalInstanceID
    then
        return false
    end
    if run.gameMapID
        and dungeon.gameMapID
        and run.gameMapID ~= dungeon.gameMapID
    then
        return false
    end
    if run.offer and not persistedOffersMatch(run.offer, raw) then
        return false
    end

    return true
end

local function bindChallengeRunToOffer(run, raw)
    if run.offer and rawOffersMatch(run.offer, raw) then
        return run
    end

    local bound = buildChallengeRun(
        run.mapID,
        run.level,
        run.startedAt
    )
    if not bound then
        return nil
    end
    bound.completedAt = run.completedAt
    bound.offer = copyRawOffer(raw)
    persistChallengeRun(bound)
    return bound
end

local function clearChallengeRunForOffer(raw)
    if challengeRun
        and challengeRun.offer
        and persistedOffersMatch(challengeRun.offer, raw)
    then
        persistChallengeRun(nil)
    end
end

local function getChallengeForOffer(raw)
    if challengeRun
        and challengeRun.offer
        and challengeRunMatchesSource(challengeRun, raw)
    then
        return bindChallengeRunToOffer(challengeRun, raw)
    end

    local activeChallenge = getActiveChallenge()
    local mapID = activeChallenge and activeChallenge.mapID
    local level = activeChallenge and activeChallenge.level
    if NS:IsPublicPositiveInteger(mapID)
        and NS:IsPublicPositiveInteger(level)
    then
        local activeRun = buildActiveChallengeRun(activeChallenge, false)
        persistChallengeRun(activeRun)
        if activeRun and challengeRunMatchesSource(activeRun, raw) then
            return bindChallengeRunToOffer(activeRun, raw)
        end

        return nil
    end

    expireStaleUnboundChallengeRun()
    if challengeRun
        and isChallengeTimestampFresh(challengeRun.completedAt)
        and challengeRunMatchesSource(challengeRun, raw)
    then
        local bound = bindChallengeRunToOffer(challengeRun, raw)
        if bound then
            return bound
        end
    end

    return nil
end

local function getDungeonRule(mapID)
    if not NS:IsPublicPositiveInteger(mapID) then
        return nil
    end

    local dungeon = NS.Catalog.dungeonByMap[mapID]
    if not dungeon then
        return nil
    end

    local specSelection = NS.DB:Get(
        "dungeonRules",
        mapID,
        "specializationID"
    )
    local resolvedSpec = resolveLootSpecSelection(
        specSelection
    )
    local minimumDifficulty = NS.DB:Get(
        "dungeonRules",
        mapID,
        "minimumDifficulty"
    )
    local limits = NS.RuleLimits.dungeonMinimumDifficulty

    if not resolvedSpec
        or not NS:IsPublicPositiveInteger(minimumDifficulty)
        or minimumDifficulty < limits.minimum
        or minimumDifficulty > limits.maximum
        or not NS.Catalog:IsDungeonThresholdAvailable(
            dungeon,
            minimumDifficulty
        )
    then
        return nil
    end

    return {
        desiredSpecID = resolvedSpec.desiredSpecID,
        desiredLootSpecID = resolvedSpec.desiredLootSpecID,
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
        return {
            ambiguous = false,
        }
    end
    if #matches == 1 then
        return {
            dungeon = matches[1],
            rule = getDungeonRule(matches[1].id),
            ambiguous = false,
        }
    end

    local selectedDungeon
    local selectedRule
    for index = 1, #matches do
        local dungeon = matches[index]
        local rule = getDungeonRule(dungeon.id)
        if rule then
            if selectedRule and not sameDungeonRule(selectedRule, rule) then
                return {
                    ambiguous = true,
                }
            end
            selectedDungeon = selectedDungeon or dungeon
            selectedRule = selectedRule or rule
        end
    end

    return {
        dungeon = selectedDungeon or matches[1],
        rule = selectedRule,
        ambiguous = false,
    }
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
        local challenge = getChallengeForOffer(raw)

        mapID = challenge and challenge.mapID
        level = challenge and challenge.level
        dungeon = mapID and NS.Catalog.dungeonByMap[mapID]

        if dungeon
            and NS:IsPublicPositiveInteger(raw.instanceID)
            and NS:IsPublicPositiveInteger(dungeon.journalInstanceID)
            and raw.instanceID ~= dungeon.journalInstanceID
        then
            dungeon = nil
        end

        if dungeon then
            rule = getDungeonRule(mapID)
        else
            -- The active map can clear before the bonus-roll offer resolves.
            -- The offer's journal instance is safe only when it identifies
            -- exactly one current-season dungeon row.
            local matches = NS:IsPublicPositiveInteger(raw.instanceID)
                and NS.Catalog.dungeonByInstance[raw.instanceID] or nil
            if matches and #matches == 1 then
                dungeon = matches[1]
                mapID = dungeon.id
                rule = getDungeonRule(mapID)
            elseif matches and #matches > 1 then
                mapID = nil
                ambiguous = true
            else
                mapID = nil
            end
        end
    else
        local match = findStandardDungeon(raw)

        dungeon = match.dungeon
        rule = match.rule
        ambiguous = match.ambiguous
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
        base.reason = "multiple seasonal dungeon rows share this instance, so the exact dungeon could not be verified"
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
    local resolvedSpec = resolveLootSpecSelection(
        specSelection
    )
    if not resolvedSpec then
        return nil
    end

    local rule = {
        desiredSpecID = resolvedSpec.desiredSpecID,
        desiredLootSpecID = resolvedSpec.desiredLootSpecID,
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
        local resolvedSpec = resolveLootSpecSelection(
            specSelection
        )
        if not resolvedSpec then
            result.configured = false
            result.allowed = false
            result.reason = "the " .. boss.name .. " bonus-roll rule is disabled"
            return result
        end

        result.configured = true
        result.allowed = true
        result.desiredSpecID = resolvedSpec.desiredSpecID
        result.desiredLootSpecID = resolvedSpec.desiredLootSpecID
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
    local resolvedSpec = resolveLootSpecSelection(
        specSelection
    )
    if not resolvedSpec then
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
        desiredSpecID = resolvedSpec.desiredSpecID,
        desiredLootSpecID = resolvedSpec.desiredLootSpecID,
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
    NS.LootSidecar:Hide()

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

    local lootAnchor = frame
    if resolved.currentSpecID ~= resolved.desiredSpecID then
        local spec = getCurrentClassSpec(resolved.desiredSpecID)
        if spec then
            switchButton.configuredSpecID = spec.id
            switchButton.configuredLootSpecID = resolved.desiredLootSpecID
            local icon = NS:IsPublicPositiveInteger(spec.icon)
                and spec.icon or UNKNOWN_SPEC_ICON
            switchButton.specIcon:SetTexture(icon)
            switchButton:Show()
            switchPanel:Show()
            lootAnchor = switchPanel
        end
    end

    NS.LootSidecar:Refresh(resolved, lootAnchor)
end

local function hideCurrentOffer(reason, resolved, allowChallengeRecovery)
    if not currentOffer or not isRawOfferActive(currentOffer.raw) then
        return false
    end

    disarm(true, false)
    refreshSwitchPanel(nil)

    resolved = resolved or resolveOffer(currentOffer.raw)
    local sourceName = resolved and resolved.sourceName or "unknown source"
    currentOffer.hidden = true
    -- Only automatic filtering may reopen an offer after its key data arrives.
    -- No and /bbr hide omit this opt-in and clear any pending recovery.
    currentOffer.hiddenForMissingChallenge = allowChallengeRecovery == true
        and resolved ~= nil
        and resolved.kind == "dungeon"
        and currentOffer.raw.difficultyID == NS.Catalog.Difficulty.MYTHIC_PLUS
        and resolved.challengeLevel == nil

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
        return {
            text = "Use a bonus roll on " .. snapshot.sourceName .. " in "
                .. currentName .. " loot specialization?",
            acceptText = "Use Bonus Roll",
            showAlert = false,
        }
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

    return {
        text = table.concat(lines, "\n"),
        acceptText = "Roll Anyway",
        showAlert = true,
    }
end

local function currentSnapshot()
    if not currentOffer or not isRawOfferActive(currentOffer.raw) then
        return nil
    end
    return resolveOffer(currentOffer.raw)
end

local function observeCurrentLoot(snapshot)
    if not runtimeEnabled or not snapshot
        or not currentOffer or currentOffer.rollState
    then
        NS.LootReconciliation:Cancel()
        return
    end

    local offer = currentOffer
    NS.LootReconciliation:ObserveOffer(
        snapshot,
        frame.PromptFrame.EncounterJournalLinkButton,
        offer.tooltipSpecID,
        function()
            return runtimeEnabled
                and currentOffer == offer
                and not offer.rollState
                and isRawOfferActive(offer.raw)
        end
    )
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

    resultCandidate = {
        snapshot = copySnapshot(snapshot),
        started = false,
        primaryResultSeen = false,
    }
    currentOffer.rollState = "submitted"
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

    local confirmation = buildConfirmationText(snapshot)
    if not StaticPopup_ShowCustomGenericConfirmation then
        disarm(false, true)
        NS:Print("Unable to open the bonus-roll confirmation; no roll was used.")
        return
    end

    StaticPopup_ShowCustomGenericConfirmation({
        text = confirmation.text,
        callback = function()
            confirmArmedToken(token)
        end,
        cancelCallback = function()
            cancelArmedToken(token)
        end,
        acceptText = confirmation.acceptText,
        cancelText = "Cancel",
        showAlert = confirmation.showAlert,
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

local function createLootSpecPanel(parent, anchor, clickHandler)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetSize(LOOT_SPEC_PANEL_WIDTH, LOOT_SPEC_PANEL_HEIGHT)
    panel:SetPoint("LEFT", anchor, "RIGHT", 6, 0)
    panel:SetFrameLevel(parent:GetFrameLevel() + 10)
    NS.PixelPerfect.CreateSurface(panel)

    local title = panel:CreateFontString(
        nil,
        "OVERLAY",
        "GameFontNormalSmall"
    )
    title:SetPoint("TOP", panel, "TOP", 0, -8)
    title:SetJustifyH("CENTER")
    title:SetText("Change\nLoot Spec")
    panel.title = title

    local button = CreateFrame(
        "Button",
        nil,
        panel
    )
    button:SetSize(LOOT_SPEC_BUTTON_SIZE, LOOT_SPEC_BUTTON_SIZE)
    button:SetPoint("BOTTOM", panel, "BOTTOM", 0, 7)

    local normalTexture = createButtonStateTexture(
        button,
        "BACKGROUND",
        "common-button-tertiary-square-normal"
    )
    button:SetNormalTexture(normalTexture)

    local pushedTexture = createButtonStateTexture(
        button,
        "BACKGROUND",
        "common-button-tertiary-square-pressed"
    )
    button:SetPushedTexture(pushedTexture)

    local highlightTexture = createButtonStateTexture(
        button,
        "HIGHLIGHT",
        "common-button-tertiary-square-normal"
    )
    highlightTexture:SetBlendMode("ADD")
    button:SetHighlightTexture(highlightTexture)

    local specIcon = button:CreateTexture(nil, "OVERLAY")
    specIcon:SetSize(LOOT_SPEC_ICON_SIZE, LOOT_SPEC_ICON_SIZE)
    specIcon:SetPoint("CENTER")
    specIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.specIcon = specIcon

    button:SetScript("OnClick", clickHandler)
    button:SetScript("OnEnter", function(self)
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
    button:SetScript("OnLeave", GameTooltip_Hide)
    button:Hide()
    panel.button = button
    panel:Hide()

    return panel
end

function Controller:CreateLootSpecPanel(parent, anchor, clickHandler)
    return createLootSpecPanel(parent, anchor, clickHandler)
end

local function createSwitchPanel()
    switchPanel = createLootSpecPanel(
        frame.PromptFrame,
        frame,
        handleSwitchButtonClick
    )
    switchButton = switchPanel.button
    NS.LootSidecar:Attach(frame.PromptFrame)
end

local function install()
    if installed then
        return true
    end

    if not BonusRollFrame then
        C_AddOns.LoadAddOn("Blizzard_UIPanels_Game")
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
        NS.LootReconciliation:Cancel()
        if runtimeEnabled and frame and frame:IsShown() then
            unsafeHidden = true
            GroupLootContainer_RemoveFrame(GroupLootContainer, frame)
            NS:Print("Bonus roll hidden because its state could not be safely inspected. Disable BetterBonusRolls to restore Blizzard's native prompt while the offer is active.")
        end
        return
    end

    if not currentOffer or not rawOffersMatch(currentOffer.raw, raw) then
        NS.LootReconciliation:Cancel()
        disarm(true, false)
        resultCandidate = nil
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
            -- Only a fresh SPELL_CONFIRMATION_PROMPT supplies tooltipSpecID.
            -- A restored offer's original tooltip specialization is unknown.
            tooltipSpecCaptured = false,
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
    observeCurrentLoot(resolved)
    if not resolved or not resolved.allowed then
        hideCurrentOffer(
            resolved and resolved.reason
                or "the offer could not be safely evaluated",
            resolved,
            true
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
    NS.LootReconciliation:Cancel()
    resultCandidate = nil
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
    observeCurrentLoot(resolved)
    if frame:IsShown() and (not resolved or not resolved.allowed) then
        hideCurrentOffer(
            resolved and resolved.reason
                or "the offer could not be safely evaluated",
            resolved,
            true
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
    currentOffer.hiddenForMissingChallenge = false
    if frame:IsShown() then
        NS:Print("The bonus roll is already showing.")
        return true
    end

    currentOffer.hidden = false
    GroupLootContainer_AddFrame(GroupLootContainer, frame)
    if not bonusRollActivated then
        rollButton:Disable()
    end
    local resolved = resolveOffer(currentOffer.raw)
    observeCurrentLoot(resolved)
    refreshSwitchPanel(resolved)
    return true
end

local function restoreOfferAfterChallengeRecovery()
    if not runtimeEnabled
        or not currentOffer
        or not currentOffer.hiddenForMissingChallenge
        or currentOffer.rollState
        or not isRawOfferActive(currentOffer.raw)
        or not ensureScriptsOwned()
    then
        return
    end

    local resolved = resolveOffer(currentOffer.raw)
    if not resolved or not resolved.challengeLevel then
        return
    end

    currentOffer.hiddenForMissingChallenge = false
    if resolved.allowed then
        -- Restore only the prompt; never restore a pending roll confirmation.
        disarm(true, true)
        Controller:ShowCurrent()
    end
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

local function handleSpellConfirmationPrompt(
    _, spellID, confirmationType, _text, duration,
    _currencyID, _currencyCost, difficultyID
)
    if NS:IsSecret(confirmationType)
        or confirmationType ~= Enum.ConfirmationPromptUIType.BonusRoll
        or not NS:IsPublicPositiveInteger(spellID)
        or not NS:IsPublicPositiveInteger(difficultyID)
        or not isPublicNumber(duration) or duration <= 0
    then
        return
    end

    local now = getPublicTimestamp()
    if not now then
        return
    end

    -- Capture before any deferred work or player spec change. Blizzard also
    -- opens recovered prompts on PLAYER_ENTERING_WORLD, without this event.
    local tooltipSpecID = GetLootSpecialization()
    if not NS:IsSecret(tooltipSpecID) and tooltipSpecID == 0 then
        tooltipSpecID = NS.Catalog:GetActiveSpecID()
    end
    if not NS:IsPublicPositiveInteger(tooltipSpecID) then
        tooltipSpecID = nil
    end
    local endTime = now + duration

    -- Let Blizzard populate the frame regardless of event-handler order.
    -- Match the fresh prompt before attaching its immutable tooltip owner.
    C_Timer.After(0, function()
        local offer = currentOffer
        if not offer or offer.tooltipSpecCaptured or offer.rollState
            or not sameValue(offer.raw.spellID, spellID)
            or not sameValue(offer.raw.difficultyID, difficultyID)
            or not sameValue(offer.raw.endTime, endTime)
            or not isRawOfferActive(offer.raw)
        then
            return
        end

        offer.tooltipSpecCaptured = true
        offer.tooltipSpecID = tooltipSpecID
        observeCurrentLoot(currentSnapshot())
    end)
end

local function handleLootSpecUpdate(event, unit)
    if event == "PLAYER_SPECIALIZATION_CHANGED"
        and (NS:IsSecret(unit) or unit ~= "player")
    then
        return
    end

    disarm(true, true)
    local snapshot = currentSnapshot()
    observeCurrentLoot(snapshot)
    refreshSwitchPanel(snapshot)
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
    NS.LootReconciliation:Cancel()
    clearChallengeRunForOffer(currentOffer.raw)
    currentOffer.expired = true

    if currentOffer.rollState then
        disarm(true, false)
        refreshSwitchPanel(nil)
        currentOffer.hidden = false
        return
    end

    if not runtimeEnabled then
        return
    end

    disarm(true, false)
    refreshSwitchPanel(nil)
    currentOffer.hidden = false
    NS:Print("Bonus roll expired without being used and can no longer be restored.")
end

local function handleBonusRollStarted()
    NS.LootReconciliation:Cancel()
    if resultCandidate
        and currentOffer
        and resultCandidate.snapshot.generation == currentOffer.generation
    then
        resultCandidate.started = true
        currentOffer.rollState = "started"
    else
        resultCandidate = nil
    end

    if currentOffer then
        clearChallengeRunForOffer(currentOffer.raw)
    end
    disarm(true, false)
    refreshSwitchPanel(nil)
    if currentOffer then
        currentOffer.hidden = false
    end
end

local function handleBonusRollFailed()
    NS.LootReconciliation:Cancel()
    resultCandidate = nil
    if currentOffer then
        currentOffer.rollState = "failed"
        clearChallengeRunForOffer(currentOffer.raw)
        currentOffer.hidden = false
    end

    disarm(true, false)
    refreshSwitchPanel(nil)
end

local function handleBonusRollResult(_, typeIdentifier, itemLink,
    _quantity, specID, _sex, _personalLootToast, _currencyID,
    isSecondaryResult)
    if not resultCandidate
        or not resultCandidate.started
        or not currentOffer
        or resultCandidate.snapshot.generation ~= currentOffer.generation
    then
        return
    end
    if NS:IsSecret(typeIdentifier)
        or NS:IsSecret(itemLink)
        or NS:IsSecret(specID)
        or NS:IsSecret(isSecondaryResult)
        or type(typeIdentifier) ~= "string"
        or type(isSecondaryResult) ~= "boolean"
    then
        resultCandidate = nil
        currentOffer.rollState = "result"
        return
    end

    local snapshot = resultCandidate.snapshot
    local actualSpecID = specID
    if actualSpecID == 0 then
        actualSpecID = snapshot.currentSpecID
    end

    if typeIdentifier == "item"
        and type(itemLink) == "string"
        and NS:IsPublicPositiveInteger(actualSpecID)
    then
        NS.LootTracker:RecordBonusRollItem(
            snapshot,
            itemLink,
            actualSpecID
        )
    end

    currentOffer.rollState = "result"
    if isSecondaryResult or resultCandidate.primaryResultSeen then
        return
    end

    resultCandidate.primaryResultSeen = true

    local sourceName = not NS:IsSecret(snapshot.sourceName)
        and type(snapshot.sourceName) == "string"
        and snapshot.sourceName or "the selected source"
    local specName = NS:IsPublicPositiveInteger(actualSpecID)
        and NS.Catalog:GetSpecName(actualSpecID) or "Unknown"
    local resultText = "Bonus roll used on " .. sourceName
        .. " with " .. specName .. " loot specialization"

    if typeIdentifier == "item"
        and type(itemLink) == "string"
        and itemLink ~= ""
    then
        resultText = resultText .. ": " .. itemLink
    else
        resultText = resultText .. "."
    end

    NS:Print(resultText)
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
    local eventMapID = NS:IsPublicPositiveInteger(mapID) and mapID or nil
    local startedAt = getPublicTimestamp()
    if not eventMapID or not startedAt then
        return
    end

    local ownerGeneration = beginChallengeRetrySeries()
    persistChallengeRun(buildChallengeRun(eventMapID, nil, startedAt))

    local retryIndex = 1
    local function attemptCapture()
        if challengeRetryGeneration ~= ownerGeneration then
            return
        end

        local active = getActiveChallenge()
        if active
            and active.mapID == eventMapID
            and NS:IsPublicPositiveInteger(active.level)
        then
            persistChallengeRun(buildChallengeRun(
                eventMapID,
                active.level,
                startedAt
            ))
            cancelChallengeRetry()
            return
        end

        local delay = CHALLENGE_RETRY_DELAYS[retryIndex]
        retryIndex = retryIndex + 1
        if delay then
            challengeRetryTimer = C_Timer.NewTimer(delay, function()
                challengeRetryTimer = nil
                attemptCapture()
            end)
        end
    end

    attemptCapture()
end

local function handleChallengeCompleted()
    local completedAt = getPublicTimestamp()
    if not completedAt then
        return
    end

    local ownerGeneration = beginChallengeRetrySeries()
    local retryIndex = 1
    local function attemptCapture()
        if challengeRetryGeneration ~= ownerGeneration then
            return
        end

        local completion = getCompletionChallenge()
        local run
        if completion then
            local startedAt = completedAt
            if isChallengeRunValid(challengeRun)
                and challengeRun.mapID == completion.mapID
            then
                startedAt = challengeRun.startedAt
            end

            run = buildChallengeRun(
                completion.mapID,
                completion.level,
                startedAt
            )
        elseif isChallengeRunValid(challengeRun) and challengeRun.level then
            run = buildChallengeRun(
                challengeRun.mapID,
                challengeRun.level,
                challengeRun.startedAt
            )
        end

        if run then
            run.completedAt = completedAt
            persistChallengeRun(run)
            cancelChallengeRetry()
            restoreOfferAfterChallengeRecovery()
            return
        end

        local delay = CHALLENGE_RETRY_DELAYS[retryIndex]
        retryIndex = retryIndex + 1
        if delay then
            challengeRetryTimer = C_Timer.NewTimer(delay, function()
                challengeRetryTimer = nil
                attemptCapture()
            end)
        end
    end

    attemptCapture()
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
    restoreChallengeRun()
    install()
    NS:RegisterEvent("PLAYER_LOGIN", function()
        reconcileActiveChallenge()
        install()
        rememberActiveDelveTier()
    end)
    NS:RegisterEvent("PLAYER_ENTERING_WORLD", reconcileActiveChallenge)
    NS:RegisterEvent("ADDON_LOADED", handleAddonLoaded)
    NS:RegisterEvent("PLAYER_LOOT_SPEC_UPDATED", handleLootSpecUpdate)
    NS:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", handleLootSpecUpdate)
    NS:RegisterEvent("SPELL_CONFIRMATION_PROMPT", handleSpellConfirmationPrompt)
    NS:RegisterEvent("SPELL_CONFIRMATION_TIMEOUT", handleTimeout)
    NS:RegisterEvent("BONUS_ROLL_STARTED", handleBonusRollStarted)
    NS:RegisterEvent("BONUS_ROLL_FAILED", handleBonusRollFailed)
    NS:RegisterEvent("BONUS_ROLL_RESULT", handleBonusRollResult)
    NS:RegisterEvent("BONUS_ROLL_DEACTIVATE", handleBonusRollActivation)
    NS:RegisterEvent("BONUS_ROLL_ACTIVATE", handleBonusRollActivation)
    NS:RegisterEvent("CHALLENGE_MODE_START", handleChallengeStart)
    NS:RegisterEvent("CHALLENGE_MODE_COMPLETED", handleChallengeCompleted)
    NS:RegisterEvent("ACTIVE_DELVE_DATA_UPDATE", rememberActiveDelveTier)
end)
