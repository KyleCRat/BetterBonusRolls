local _, NS = ...

local Catalog = {
    ready = false,
    raids = {},
    raidByInstance = {},
    worldBosses = {},
    worldBossByEncounter = {},
    dungeons = {},
    dungeonByMap = {},
    dungeonByInstance = {},
    specs = {},
    specByID = {},
}

NS.Catalog = Catalog

local DUNGEON_RANK = NS.DungeonDifficultyRank
local MYTHIC_PLUS_KEY_LEVEL = NS.MythicPlusKeyLevel
local CLIENT_DIFFICULTY = DifficultyUtil and DifficultyUtil.ID or {}

Catalog.Difficulty = {
    DUNGEON_NORMAL = CLIENT_DIFFICULTY.DungeonNormal or 1,
    DUNGEON_HEROIC = CLIENT_DIFFICULTY.DungeonHeroic or 2,
    MYTHIC_PLUS = CLIENT_DIFFICULTY.DungeonChallenge or 8,
    NORMAL = CLIENT_DIFFICULTY.PrimaryRaidNormal or 14,
    HEROIC = CLIENT_DIFFICULTY.PrimaryRaidHeroic or 15,
    MYTHIC = CLIENT_DIFFICULTY.PrimaryRaidMythic or 16,
    RAID_FINDER = CLIENT_DIFFICULTY.PrimaryRaidLFR or 17,
    DUNGEON_MYTHIC = CLIENT_DIFFICULTY.DungeonMythic or 23,
    WORLD_BOSS = 172,
    DELVE = 208,
    STORY = CLIENT_DIFFICULTY.RaidStory or 220,
    FLEX_MYTHIC = CLIENT_DIFFICULTY.RaidMythicFlexible or 233,
    WORLD = CLIENT_DIFFICULTY.RaidWorld or 250,
}

-- Keep the historical ranks for stored progress and unexpected base-difficulty
-- offers. Only ranks 4 through 12 (+2 through +10) are selectable now.
local DUNGEON_THRESHOLD_LABELS = {
    [DUNGEON_RANK.NORMAL] = "Normal",
    [DUNGEON_RANK.HEROIC] = "Heroic",
    [DUNGEON_RANK.MYTHIC_0] = "Mythic",
}

for level = MYTHIC_PLUS_KEY_LEVEL.MINIMUM,
    MYTHIC_PLUS_KEY_LEVEL.MAXIMUM_TRACKED
do
    local rank = DUNGEON_RANK.MYTHIC_PLUS_2
        + (level - MYTHIC_PLUS_KEY_LEVEL.MINIMUM)
    DUNGEON_THRESHOLD_LABELS[rank] = "+" .. level
end

local DIFFICULTY_LABELS = {
    [14] = "Normal",
    [15] = "Heroic",
    [16] = "Mythic",
    [17] = "Raid Finder",
    [220] = "Story",
    [250] = "World",
}

local DIFFICULTY_ORDER = {
    { id = 250, label = "World" },
    { id = 17, label = "Raid Finder" },
    { id = 14, label = "Normal" },
    { id = 15, label = "Heroic" },
    { id = 16, label = "Mythic" },
    { id = 220, label = "Story" },
}

local RAID_DIFFICULTY_DISPLAY_ORDER = {
    Catalog.Difficulty.MYTHIC,
    Catalog.Difficulty.HEROIC,
    Catalog.Difficulty.NORMAL,
    Catalog.Difficulty.RAID_FINDER,
    Catalog.Difficulty.STORY,
    Catalog.Difficulty.WORLD,
}

local CATALOG_DATA_FIELDS = {
    "raids",
    "raidByInstance",
    "worldBosses",
    "worldBossByEncounter",
    "dungeons",
    "dungeonByMap",
    "dungeonByInstance",
    "specs",
    "specByID",
}

local CATALOG_RETRY_DELAYS = { 0.25, 0.5, 1, 2 }
local readyCallbacks = {}
local retryTimer
local retryStep = 1

local function ensureEncounterJournal()
    if EJ_GetNumTiers and EJ_GetInstanceByIndex then
        return true
    end

    C_AddOns.LoadAddOn("Blizzard_EncounterJournal")

    if not EJ_GetNumTiers or not EJ_GetInstanceByIndex then
        error("BetterBonusRolls could not load Blizzard_EncounterJournal.", 2)
    end

    return true
end

local function hasSelectedInstanceDifficulty(difficultyID)
    if C_EncounterJournal and C_EncounterJournal.InstanceHasDifficultyID then
        local result = C_EncounterJournal.InstanceHasDifficultyID(
            difficultyID
        )
        if result ~= nil and not NS:IsSecret(result) then
            return result == true
        end
    end

    local result = EJ_IsValidInstanceDifficulty(difficultyID)
    return not NS:IsSecret(result) and result == true
end

local function collectDifficulties()
    local difficulties = {}
    local hasWorld = hasSelectedInstanceDifficulty(
        Catalog.Difficulty.WORLD
    )
    local hasFlexibleMythic = hasSelectedInstanceDifficulty(
        Catalog.Difficulty.FLEX_MYTHIC
    )

    for index = 1, #DIFFICULTY_ORDER do
        local definition = DIFFICULTY_ORDER[index]
        local include = hasSelectedInstanceDifficulty(definition.id)

        if definition.id == Catalog.Difficulty.RAID_FINDER and hasWorld then
            include = false
        elseif definition.id == Catalog.Difficulty.MYTHIC
            and hasFlexibleMythic
        then
            include = true
        end

        if include then
            difficulties[#difficulties + 1] = {
                id = definition.id,
                label = definition.label,
                journalDifficultyID = definition.id
                    == Catalog.Difficulty.MYTHIC
                    and hasFlexibleMythic
                    and Catalog.Difficulty.FLEX_MYTHIC
                    or definition.id,
            }
        end
    end

    return difficulties
end

local function buildDungeonThresholds()
    local choices = {}
    local byValue = {}

    -- All current-season dungeon rules are Mythic+. Use the Mythic Journal
    -- item catalog for every key, while retaining separate progress per rank.
    for value = DUNGEON_RANK.MYTHIC_PLUS_2, DUNGEON_RANK.MYTHIC_PLUS_10 do
        local choice = {
            value = value,
            label = DUNGEON_THRESHOLD_LABELS[value],
            journalDifficultyID = Catalog.Difficulty.DUNGEON_MYTHIC,
        }
        choices[#choices + 1] = choice
        byValue[value] = choice
    end

    return {
        choices = choices,
        byValue = byValue,
    }
end

local function collectEncounters(instanceID)
    local encounters = {}
    local encounterByID = {}
    local index = 1

    while true do
        local name, _, encounterID = EJ_GetEncounterInfoByIndex(
            index,
            instanceID
        )
        if NS:IsSecret(encounterID) then
            break
        end
        if not encounterID then
            break
        end

        if not NS:IsSecret(name)
            and type(name) == "string"
            and NS:IsPublicPositiveInteger(encounterID)
            and not encounterByID[encounterID]
        then
            local encounter = {
                id = encounterID,
                name = name,
                order = #encounters + 1,
            }
            encounters[#encounters + 1] = encounter
            encounterByID[encounterID] = encounter
        end

        index = index + 1
    end

    return {
        encounters = encounters,
        encounterByID = encounterByID,
    }
end

local function getPublicInstanceName(name, instanceID)
    if not NS:IsSecret(name) and type(name) == "string" then
        return name
    end

    return "Instance " .. instanceID
end

local function isWorldBossInstance(instanceName, dungeonAreaMapID, tierName)
    if not NS:IsSecret(dungeonAreaMapID) and dungeonAreaMapID == 0 then
        return true
    end

    return not NS:IsSecret(instanceName)
        and not NS:IsSecret(tierName)
        and type(instanceName) == "string"
        and type(tierName) == "string"
        and instanceName == tierName
end

local function collectWorldBosses(
    target,
    instanceID,
    instanceName,
    difficulties
)
    local encounterCollection = collectEncounters(instanceID)
    local encounters = encounterCollection.encounters
    local difficulty = difficulties[1]

    for index = 1, #encounters do
        local encounter = encounters[index]
        if not target.worldBossByEncounter[encounter.id] then
            local boss = {
                id = encounter.id,
                name = encounter.name,
                order = #target.worldBosses + 1,
                instanceID = instanceID,
                instanceName = instanceName,
                difficultyID = difficulty and difficulty.id or nil,
                journalDifficultyID = difficulty
                    and difficulty.journalDifficultyID or nil,
            }
            target.worldBosses[#target.worldBosses + 1] = boss
            target.worldBossByEncounter[boss.id] = boss
        end
    end
end

local function collectRaidLikeInstances(target, isRaidList, seen, tierName)
    local index = 1

    while true do
        local instanceID, name, ignored3, ignored4, ignored5, ignored6,
            ignored7, dungeonAreaMapID = EJ_GetInstanceByIndex(
            index,
            isRaidList
        )
        if NS:IsSecret(instanceID) then
            break
        end
        if not instanceID then
            break
        end

        if NS:IsPublicPositiveInteger(instanceID) then
            EJ_SelectInstance(instanceID)
            local instanceName = getPublicInstanceName(name, instanceID)
            local difficulties = collectDifficulties()

            if isRaidList
                and isWorldBossInstance(name, dungeonAreaMapID, tierName)
                and not seen[instanceID]
            then
                collectWorldBosses(
                    target,
                    instanceID,
                    instanceName,
                    difficulties
                )
                seen[instanceID] = true
            else
                if #difficulties > 0 and not seen[instanceID] then
                    local encounterCollection = collectEncounters(instanceID)
                    local encounters = encounterCollection.encounters
                    if #encounters > 0 then
                        local difficultyByID = {}
                        for difficultyIndex = 1, #difficulties do
                            local difficulty = difficulties[difficultyIndex]
                            difficultyByID[difficulty.id] = difficulty
                        end

                        local instance = {
                            id = instanceID,
                            name = instanceName,
                            order = #target.raids + 1,
                            encounters = encounters,
                            encounterByID = encounterCollection.encounterByID,
                            difficulties = difficulties,
                            difficultyByID = difficultyByID,
                            journalRaidList = isRaidList,
                        }

                        target.raids[#target.raids + 1] = instance
                        target.raidByInstance[instanceID] = instance
                        seen[instanceID] = true
                    end
                end
            end
        end

        index = index + 1
    end
end

local function buildRaids(target)
    if not ensureEncounterJournal() then
        return false
    end

    local tierCount = EJ_GetNumTiers() or 0
    if NS:IsSecret(tierCount) or type(tierCount) ~= "number" or tierCount < 1 then
        return false
    end

    EJ_SelectTier(tierCount)

    local seen = {}
    local tierName = EJ_GetTierInfo(tierCount)
    collectRaidLikeInstances(target, true, seen, tierName)
    collectRaidLikeInstances(target, false, seen, nil)

    return #target.raids > 0 or #target.worldBosses > 0
end

local function buildDungeons(target)
    if not C_ChallengeMode or not C_ChallengeMode.GetMapTable then
        error("BetterBonusRolls requires C_ChallengeMode.GetMapTable.", 2)
    end

    local mapTable = C_ChallengeMode.GetMapTable()
    if NS:IsSecret(mapTable)
        or type(mapTable) ~= "table"
        or #mapTable == 0
    then
        return false
    end

    local journalOrder = {}
    local journalAvailable = ensureEncounterJournal()

    if not journalAvailable then
        return false
    end

    local tierCount = EJ_GetNumTiers() or 0
    if NS:IsSecret(tierCount)
        or type(tierCount) ~= "number"
        or tierCount < 1
    then
        return false
    end

    EJ_SelectTier(tierCount)
    local journalIndex = 1
    while true do
        local instanceID = EJ_GetInstanceByIndex(journalIndex, false)
        if NS:IsSecret(instanceID) then
            return false
        end
        if not instanceID then
            break
        end
        if NS:IsPublicPositiveInteger(instanceID) then
            journalOrder[instanceID] = journalIndex
        end
        journalIndex = journalIndex + 1
    end

    for index = 1, #mapTable do
        local challengeMapID = mapTable[index]
        if not NS:IsPublicPositiveInteger(challengeMapID) then
            return false
        end

        local name, _, _, _, _, gameMapID =
            C_ChallengeMode.GetMapUIInfo(challengeMapID)

        if NS:IsSecret(name)
            or type(name) ~= "string"
            or not NS:IsPublicPositiveInteger(gameMapID)
        then
            return false
        end

        local journalInstanceID =
            C_EncounterJournal.GetInstanceForGameMap(gameMapID)
        if not NS:IsPublicPositiveInteger(journalInstanceID) then
            return false
        end

        local dungeon = {
            id = challengeMapID,
            name = name,
            order = #target.dungeons + 1,
            gameMapID = gameMapID,
            journalInstanceID = journalInstanceID,
            challengeOrder = index,
        }
        target.dungeons[#target.dungeons + 1] = dungeon
        target.dungeonByMap[challengeMapID] = dungeon
    end

    table.sort(target.dungeons, function(left, right)
        local leftOrder = journalOrder[left.journalInstanceID] or 100000
        local rightOrder = journalOrder[right.journalInstanceID] or 100000
        if leftOrder ~= rightOrder then
            return leftOrder < rightOrder
        end
        return left.challengeOrder < right.challengeOrder
    end)

    for index = 1, #target.dungeons do
        local dungeon = target.dungeons[index]
        dungeon.order = index
        local hasJournalInstance = NS:IsPublicPositiveInteger(
            dungeon.journalInstanceID
        )
        if hasJournalInstance then
            EJ_SelectInstance(dungeon.journalInstanceID)
            local encounterCollection = collectEncounters(
                dungeon.journalInstanceID
            )
            dungeon.encounters = encounterCollection.encounters
            dungeon.encounterByID = encounterCollection.encounterByID
        else
            dungeon.encounters = {}
            dungeon.encounterByID = {}
        end

        local thresholds = buildDungeonThresholds()
        dungeon.thresholdChoices = thresholds.choices
        dungeon.thresholdByValue = thresholds.byValue
        dungeon.defaultMinimumDifficulty =
            NS.RuleDefaults.dungeonMinimumDifficulty

        if dungeon.journalInstanceID then
            local matches = target.dungeonByInstance[
                dungeon.journalInstanceID
            ]
            if not matches then
                matches = {}
                target.dungeonByInstance[
                    dungeon.journalInstanceID
                ] = matches
            end
            matches[#matches + 1] = dungeon
        end
    end

    return #target.dungeons == #mapTable
end

local function buildSpecs(target)
    local count = GetNumSpecializations() or 0
    if NS:IsSecret(count) or type(count) ~= "number" or count < 1 then
        return false
    end

    for index = 1, count do
        local specID, name, _, icon = GetSpecializationInfo(index)
        if NS:IsPublicPositiveInteger(specID)
            and not NS:IsSecret(name)
            and type(name) == "string"
        then
            local spec = {
                id = specID,
                name = name,
                icon = icon,
                order = #target.specs + 1,
            }
            target.specs[#target.specs + 1] = spec
            target.specByID[specID] = spec
        end
    end

    return #target.specs == count
end

local function createCatalogData()
    return {
        raids = {},
        raidByInstance = {},
        worldBosses = {},
        worldBossByEncounter = {},
        dungeons = {},
        dungeonByMap = {},
        dungeonByInstance = {},
        specs = {},
        specByID = {},
    }
end

local function runReadyCallback(callback)
    local ok, err = pcall(callback)
    if not ok then
        geterrorhandler()(err)
    end
end

local function notifyReadyCallbacks()
    local callbacks = readyCallbacks
    readyCallbacks = {}

    for index = 1, #callbacks do
        runReadyCallback(callbacks[index])
    end
end

function Catalog:IsReady()
    return self.ready == true
end

function Catalog:WhenReady(callback)
    assert(type(callback) == "function", "catalog callback must be a function")

    if self:IsReady() then
        runReadyCallback(callback)
        return
    end

    readyCallbacks[#readyCallbacks + 1] = callback
end

function Catalog:Build()
    if self:IsReady() then
        return true
    end

    local candidate = createCatalogData()
    if not buildSpecs(candidate)
        or not buildRaids(candidate)
        or not buildDungeons(candidate)
    then
        return false
    end

    for index = 1, #CATALOG_DATA_FIELDS do
        local field = CATALOG_DATA_FIELDS[index]
        self[field] = candidate[field]
    end

    self.ready = true
    if retryTimer then
        retryTimer:Cancel()
        retryTimer = nil
    end
    retryStep = 1
    notifyReadyCallbacks()
    return true
end

function Catalog:EnsureReady()
    if self:Build() then
        return true
    end
    if retryTimer then
        return false
    end

    local delay = CATALOG_RETRY_DELAYS[retryStep]
    if retryStep < #CATALOG_RETRY_DELAYS then
        retryStep = retryStep + 1
    end

    retryTimer = C_Timer.NewTimer(delay, function()
        retryTimer = nil
        Catalog:EnsureReady()
    end)
    return false
end

function Catalog:CanonicalDifficultyID(difficultyID)
    if difficultyID == self.Difficulty.FLEX_MYTHIC then
        return self.Difficulty.MYTHIC
    end
    return difficultyID
end

function Catalog:GetDifficultyName(difficultyID)
    difficultyID = self:CanonicalDifficultyID(difficultyID)
    local label = DIFFICULTY_LABELS[difficultyID]
    if label then
        return label
    end

    local clientLabel = GetDifficultyInfo(difficultyID)
    if not NS:IsSecret(clientLabel) and type(clientLabel) == "string" then
        return clientLabel
    end

    return "Difficulty " .. tostring(difficultyID)
end

function Catalog:GetRaidDifficultiesHardestFirst(instance)
    local ordered = {}
    if type(instance) ~= "table"
        or type(instance.difficultyByID) ~= "table"
    then
        return ordered
    end

    for index = 1, #RAID_DIFFICULTY_DISPLAY_ORDER do
        local difficultyID = RAID_DIFFICULTY_DISPLAY_ORDER[index]
        local difficulty = instance.difficultyByID[difficultyID]

        if difficulty then
            ordered[#ordered + 1] = difficulty
        end
    end

    return ordered
end

function Catalog:GetDungeonThresholdChoices(dungeon)
    if NS:IsSecret(dungeon)
        or type(dungeon) ~= "table"
        or type(dungeon.thresholdChoices) ~= "table"
    then
        return {}
    end

    return dungeon.thresholdChoices
end

function Catalog:GetDungeonThreshold(dungeon, rank)
    if NS:IsSecret(dungeon)
        or type(dungeon) ~= "table"
        or type(dungeon.thresholdByValue) ~= "table"
        or not NS:IsPublicPositiveInteger(rank)
    then
        return nil
    end

    return dungeon.thresholdByValue[rank]
end

function Catalog:IsDungeonThresholdAvailable(dungeon, rank)
    return self:GetDungeonThreshold(dungeon, rank) ~= nil
end

function Catalog:GetDungeonDefaultThreshold(dungeon)
    if NS:IsSecret(dungeon)
        or type(dungeon) ~= "table"
        or not NS:IsPublicPositiveInteger(
            dungeon.defaultMinimumDifficulty
        )
    then
        return NS.RuleDefaults.dungeonMinimumDifficulty
    end

    return dungeon.defaultMinimumDifficulty
end

function Catalog:NormalizeDungeonThreshold(dungeon, rank)
    local choices = self:GetDungeonThresholdChoices(dungeon)
    if #choices == 0 then
        return nil
    end
    if not NS:IsPublicPositiveInteger(rank) then
        return self:GetDungeonDefaultThreshold(dungeon)
    end

    for index = 1, #choices do
        if choices[index].value >= rank then
            return choices[index].value
        end
    end

    return choices[#choices].value
end

function Catalog:GetDungeonThresholdLabel(rank)
    return DUNGEON_THRESHOLD_LABELS[rank] or "Unknown"
end

function Catalog:GetDungeonCompletionRank(difficultyID, challengeLevel)
    if difficultyID == self.Difficulty.DUNGEON_NORMAL then
        return DUNGEON_RANK.NORMAL
    elseif difficultyID == self.Difficulty.DUNGEON_HEROIC then
        return DUNGEON_RANK.HEROIC
    elseif difficultyID == self.Difficulty.DUNGEON_MYTHIC then
        return DUNGEON_RANK.MYTHIC_0
    elseif difficultyID == self.Difficulty.MYTHIC_PLUS
        and NS:IsPublicPositiveInteger(challengeLevel)
        and challengeLevel >= MYTHIC_PLUS_KEY_LEVEL.MINIMUM
    then
        local level = math.min(
            challengeLevel,
            MYTHIC_PLUS_KEY_LEVEL.MAXIMUM_TRACKED
        )
        return DUNGEON_RANK.MYTHIC_PLUS_2
            + (level - MYTHIC_PLUS_KEY_LEVEL.MINIMUM)
    end

    return nil
end

function Catalog:IsDungeonDifficulty(difficultyID)
    return difficultyID == self.Difficulty.DUNGEON_NORMAL
        or difficultyID == self.Difficulty.DUNGEON_HEROIC
        or difficultyID == self.Difficulty.DUNGEON_MYTHIC
        or difficultyID == self.Difficulty.MYTHIC_PLUS
end

function Catalog:GetActiveSpecID()
    local activeIndex = GetSpecialization()
    if not NS:IsPublicPositiveInteger(activeIndex) then
        return nil
    end

    local specID = GetSpecializationInfo(activeIndex)
    if NS:IsPublicPositiveInteger(specID) then
        return specID
    end

    return nil
end

function Catalog:GetEffectiveLootSpecID()
    local lootSpecID = GetLootSpecialization()
    if NS:IsPublicPositiveInteger(lootSpecID) then
        return lootSpecID
    end

    return self:GetActiveSpecID()
end

function Catalog:GetSpecName(specID)
    local spec = self.specByID[specID]
    if spec then
        return spec.name
    end

    if NS:IsPublicPositiveInteger(specID) then
        local _, name = GetSpecializationInfoByID(specID)
        if not NS:IsSecret(name) and type(name) == "string" then
            return name
        end
    end

    return "Unknown"
end

function Catalog:GetSpecChoices()
    local choices = {}
    local currentSpecID = self:GetActiveSpecID()
    local currentSpec = currentSpecID and self.specByID[currentSpecID]
    local currentLabel = currentSpec and "Current Spec ("
        .. currentSpec.name .. ")" or "Current Spec"

    choices[#choices + 1] = {
        value = 0,
        label = currentLabel,
    }

    for index = 1, #self.specs do
        local spec = self.specs[index]
        choices[#choices + 1] = {
            value = spec.id,
            label = spec.name,
        }
    end

    return choices
end

NS:RegisterInitializer(function()
    NS:RegisterEvent("PLAYER_LOGIN", function()
        Catalog:EnsureReady()
    end)
end)
