local _, NS = ...

local Catalog = {
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

local CLIENT_DIFFICULTY = DifficultyUtil and DifficultyUtil.ID or {}

Catalog.Difficulty = {
    DUNGEON_NORMAL = CLIENT_DIFFICULTY.DungeonNormal or 1,
    DUNGEON_HEROIC = CLIENT_DIFFICULTY.DungeonHeroic or 2,
    MYTHIC_PLUS = CLIENT_DIFFICULTY.DungeonChallenge or 8,
    DUNGEON_TIMEWALKING = CLIENT_DIFFICULTY.DungeonTimewalker or 24,
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

local DUNGEON_BASE_THRESHOLD_DEFINITIONS = {
    {
        value = 1,
        label = "Normal",
        journalDifficultyID = Catalog.Difficulty.DUNGEON_NORMAL,
    },
    {
        value = 2,
        label = "Heroic",
        journalDifficultyID = Catalog.Difficulty.DUNGEON_HEROIC,
    },
    {
        value = 3,
        label = "Mythic (M0)",
        journalDifficultyID = Catalog.Difficulty.DUNGEON_MYTHIC,
    },
}

local DUNGEON_THRESHOLD_LABELS = {
    [1] = "Normal",
    [2] = "Heroic",
    [3] = "Mythic",
}

for level = 2, 10 do
    DUNGEON_THRESHOLD_LABELS[level + 2] = "+" .. level
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

local function pack(...)
    return { n = select("#", ...), ... }
end

local function safeCall(func, ...)
    if type(func) ~= "function" then
        return nil
    end

    local results = pack(pcall(func, ...))
    if not results[1] then
        return nil
    end

    return unpack(results, 2, results.n)
end

local function ensureEncounterJournal()
    if EJ_GetNumTiers and EJ_GetInstanceByIndex then
        return true
    end

    if C_AddOns and C_AddOns.LoadAddOn then
        safeCall(C_AddOns.LoadAddOn, "Blizzard_EncounterJournal")
    end

    return EJ_GetNumTiers ~= nil and EJ_GetInstanceByIndex ~= nil
end

local function hasSelectedInstanceDifficulty(difficultyID)
    if C_EncounterJournal and C_EncounterJournal.InstanceHasDifficultyID then
        local result = safeCall(
            C_EncounterJournal.InstanceHasDifficultyID,
            difficultyID
        )
        if result ~= nil and not NS:IsSecret(result) then
            return result == true
        end
    end

    local result = safeCall(EJ_IsValidInstanceDifficulty, difficultyID)
    return not NS:IsSecret(result) and result == true
end

local function isSelectedInstanceDifficultyValid(difficultyID)
    local result = safeCall(EJ_IsValidInstanceDifficulty, difficultyID)
    if result ~= nil and not NS:IsSecret(result) then
        return result == true
    end

    return hasSelectedInstanceDifficulty(difficultyID)
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

local function collectDungeonThresholds(includeBaseDifficulties)
    local choices = {}
    local byValue = {}

    if includeBaseDifficulties then
        local timewalkingBaseDifficultyID
        if isSelectedInstanceDifficultyValid(
                Catalog.Difficulty.DUNGEON_TIMEWALKING
            )
            and hasSelectedInstanceDifficulty(
                Catalog.Difficulty.DUNGEON_TIMEWALKING
            )
        then
            timewalkingBaseDifficultyID = safeCall(
                C_EncounterJournal.GetBaseDifficultyID,
                Catalog.Difficulty.DUNGEON_TIMEWALKING
            )
            if NS:IsSecret(timewalkingBaseDifficultyID)
                or not NS:IsPublicPositiveInteger(
                    timewalkingBaseDifficultyID
                )
            then
                timewalkingBaseDifficultyID = nil
            end
        end

        for index = 1, #DUNGEON_BASE_THRESHOLD_DEFINITIONS do
            local definition = DUNGEON_BASE_THRESHOLD_DEFINITIONS[index]

            if definition.journalDifficultyID
                ~= timewalkingBaseDifficultyID
                and isSelectedInstanceDifficultyValid(
                    definition.journalDifficultyID
                )
            then
                local choice = {
                    value = definition.value,
                    label = definition.label,
                    journalDifficultyID = definition.journalDifficultyID,
                }
                choices[#choices + 1] = choice
                byValue[choice.value] = choice
            end
        end
    end

    -- Every entry came from the active Challenge Mode map table, so +2
    -- through +10 are valid completion thresholds. Blizzard exposes their
    -- shared item pool through the base Mythic Journal difficulty.
    for level = 2, 10 do
        local value = level + 2
        local choice = {
            value = value,
            label = DUNGEON_THRESHOLD_LABELS[value],
            journalDifficultyID = Catalog.Difficulty.DUNGEON_MYTHIC,
        }
        choices[#choices + 1] = choice
        byValue[value] = choice
    end

    return choices, byValue
end

local function collectEncounters(instanceID)
    local encounters = {}
    local encounterByID = {}
    local index = 1

    while true do
        local name, _, encounterID = safeCall(
            EJ_GetEncounterInfoByIndex,
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

    return encounters, encounterByID
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

local function collectWorldBosses(instanceID, instanceName, difficulties)
    local encounters = collectEncounters(instanceID)
    local difficulty = difficulties[1]

    for index = 1, #encounters do
        local encounter = encounters[index]
        if not Catalog.worldBossByEncounter[encounter.id] then
            local boss = {
                id = encounter.id,
                name = encounter.name,
                order = #Catalog.worldBosses + 1,
                instanceID = instanceID,
                instanceName = instanceName,
                difficultyID = difficulty and difficulty.id or nil,
                journalDifficultyID = difficulty
                    and difficulty.journalDifficultyID or nil,
            }
            Catalog.worldBosses[#Catalog.worldBosses + 1] = boss
            Catalog.worldBossByEncounter[boss.id] = boss
        end
    end
end

local function collectRaidLikeInstances(isRaidList, seen, tierName)
    local index = 1

    while true do
        local instanceID, name, ignored3, ignored4, ignored5, ignored6,
            ignored7, dungeonAreaMapID = safeCall(
            EJ_GetInstanceByIndex,
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
            safeCall(EJ_SelectInstance, instanceID)
            local instanceName = getPublicInstanceName(name, instanceID)
            local difficulties = collectDifficulties()

            if isRaidList
                and isWorldBossInstance(name, dungeonAreaMapID, tierName)
                and not seen[instanceID]
            then
                collectWorldBosses(
                    instanceID,
                    instanceName,
                    difficulties
                )
                seen[instanceID] = true
            else
                if #difficulties > 0 and not seen[instanceID] then
                    local encounters, encounterByID = collectEncounters(instanceID)
                    if #encounters > 0 then
                        local difficultyByID = {}
                        for difficultyIndex = 1, #difficulties do
                            local difficulty = difficulties[difficultyIndex]
                            difficultyByID[difficulty.id] = difficulty
                        end

                        local instance = {
                            id = instanceID,
                            name = instanceName,
                            order = #Catalog.raids + 1,
                            encounters = encounters,
                            encounterByID = encounterByID,
                            difficulties = difficulties,
                            difficultyByID = difficultyByID,
                            journalRaidList = isRaidList,
                        }

                        Catalog.raids[#Catalog.raids + 1] = instance
                        Catalog.raidByInstance[instanceID] = instance
                        seen[instanceID] = true
                    end
                end
            end
        end

        index = index + 1
    end
end

local function restoreJournalSelection(tier, instanceID, difficultyID)
    if NS:IsPublicPositiveInteger(tier) then
        safeCall(EJ_SelectTier, tier)
    end
    if NS:IsPublicPositiveInteger(instanceID) then
        safeCall(EJ_SelectInstance, instanceID)
    end
    if NS:IsPublicPositiveInteger(difficultyID) then
        safeCall(EJ_SetDifficulty, difficultyID)
    end
end

function Catalog:BuildRaids()
    self.raids = {}
    self.raidByInstance = {}
    self.worldBosses = {}
    self.worldBossByEncounter = {}

    if not ensureEncounterJournal() then
        return
    end

    local tierCount = safeCall(EJ_GetNumTiers) or 0
    if NS:IsSecret(tierCount) or type(tierCount) ~= "number" or tierCount < 1 then
        return
    end

    local savedTier = safeCall(EJ_GetCurrentTier)
    local savedInstance = safeCall(EJ_GetCurrentInstance)
    local savedDifficulty = safeCall(EJ_GetDifficulty)

    local selected = pcall(EJ_SelectTier, tierCount)
    if not selected then
        restoreJournalSelection(savedTier, savedInstance, savedDifficulty)
        return
    end

    local seen = {}
    local tierName = safeCall(EJ_GetTierInfo, tierCount)
    collectRaidLikeInstances(true, seen, tierName)
    collectRaidLikeInstances(false, seen, nil)
    restoreJournalSelection(savedTier, savedInstance, savedDifficulty)
end

function Catalog:BuildDungeons()
    self.dungeons = {}
    self.dungeonByMap = {}
    self.dungeonByInstance = {}

    if not C_ChallengeMode or not C_ChallengeMode.GetMapTable then
        return
    end

    local mapTable = safeCall(C_ChallengeMode.GetMapTable)
    if NS:IsSecret(mapTable) or type(mapTable) ~= "table" then
        return
    end

    local journalOrder = {}
    local journalAvailable = ensureEncounterJournal()
    local savedTier
    local savedInstance
    local savedDifficulty

    if journalAvailable then
        local tierCount = safeCall(EJ_GetNumTiers) or 0
        savedTier = safeCall(EJ_GetCurrentTier)
        savedInstance = safeCall(EJ_GetCurrentInstance)
        savedDifficulty = safeCall(EJ_GetDifficulty)

        if not NS:IsSecret(tierCount)
            and type(tierCount) == "number"
            and tierCount > 0
        then
            safeCall(EJ_SelectTier, tierCount)
            local journalIndex = 1
            while true do
                local instanceID = safeCall(
                    EJ_GetInstanceByIndex,
                    journalIndex,
                    false
                )
                if NS:IsSecret(instanceID) then
                    break
                end
                if not instanceID then
                    break
                end
                if NS:IsPublicPositiveInteger(instanceID) then
                    journalOrder[instanceID] = journalIndex
                end
                journalIndex = journalIndex + 1
            end
        end
    end

    for index = 1, #mapTable do
        local challengeMapID = mapTable[index]
        if NS:IsPublicPositiveInteger(challengeMapID) then
            local name, _, _, _, _, gameMapID = safeCall(
                C_ChallengeMode.GetMapUIInfo,
                challengeMapID
            )

            if not NS:IsSecret(name) and type(name) == "string" then
                if not NS:IsPublicPositiveInteger(gameMapID) then
                    gameMapID = nil
                end
                local journalInstanceID
                if C_EncounterJournal
                    and C_EncounterJournal.GetInstanceForGameMap
                    and NS:IsPublicPositiveInteger(gameMapID)
                then
                    journalInstanceID = safeCall(
                        C_EncounterJournal.GetInstanceForGameMap,
                        gameMapID
                    )
                end
                if not NS:IsPublicPositiveInteger(journalInstanceID) then
                    journalInstanceID = nil
                end

                local dungeon = {
                    id = challengeMapID,
                    name = name,
                    order = #self.dungeons + 1,
                    gameMapID = gameMapID,
                    journalInstanceID = journalInstanceID,
                    challengeOrder = index,
                }
                self.dungeons[#self.dungeons + 1] = dungeon
                self.dungeonByMap[challengeMapID] = dungeon
            end
        end
    end

    table.sort(self.dungeons, function(left, right)
        local leftOrder = journalOrder[left.journalInstanceID] or 100000
        local rightOrder = journalOrder[right.journalInstanceID] or 100000
        if leftOrder ~= rightOrder then
            return leftOrder < rightOrder
        end
        return left.challengeOrder < right.challengeOrder
    end)

    for index = 1, #self.dungeons do
        local dungeon = self.dungeons[index]
        dungeon.order = index
        local hasJournalInstance = NS:IsPublicPositiveInteger(
            dungeon.journalInstanceID
        )
        local selected = journalAvailable
            and hasJournalInstance
            and pcall(EJ_SelectInstance, dungeon.journalInstanceID)

        if hasJournalInstance then
            dungeon.encounters, dungeon.encounterByID = collectEncounters(
                dungeon.journalInstanceID
            )
        else
            dungeon.encounters = {}
            dungeon.encounterByID = {}
        end

        dungeon.thresholdChoices, dungeon.thresholdByValue =
            collectDungeonThresholds(selected == true)
        dungeon.defaultMinimumDifficulty =
            dungeon.thresholdByValue[
                NS.RuleDefaults.dungeonMinimumDifficulty
            ]
            and NS.RuleDefaults.dungeonMinimumDifficulty
            or dungeon.thresholdChoices[#dungeon.thresholdChoices].value

        if dungeon.journalInstanceID then
            local matches = self.dungeonByInstance[dungeon.journalInstanceID]
            if not matches then
                matches = {}
                self.dungeonByInstance[dungeon.journalInstanceID] = matches
            end
            matches[#matches + 1] = dungeon
        end
    end

    if journalAvailable then
        restoreJournalSelection(savedTier, savedInstance, savedDifficulty)
    end
end

function Catalog:BuildSpecs()
    self.specs = {}
    self.specByID = {}

    local count = safeCall(GetNumSpecializations) or 0
    if NS:IsSecret(count) or type(count) ~= "number" then
        return
    end

    for index = 1, count do
        local specID, name, _, icon = safeCall(GetSpecializationInfo, index)
        if NS:IsPublicPositiveInteger(specID)
            and not NS:IsSecret(name)
            and type(name) == "string"
        then
            local spec = {
                id = specID,
                name = name,
                icon = icon,
                order = #self.specs + 1,
            }
            self.specs[#self.specs + 1] = spec
            self.specByID[specID] = spec
        end
    end
end

function Catalog:Build()
    self:BuildSpecs()
    self:BuildRaids()
    self:BuildDungeons()
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

    local clientLabel = safeCall(GetDifficultyInfo, difficultyID)
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
        return 1
    elseif difficultyID == self.Difficulty.DUNGEON_HEROIC then
        return 2
    elseif difficultyID == self.Difficulty.DUNGEON_MYTHIC then
        return 3
    elseif difficultyID == self.Difficulty.MYTHIC_PLUS
        and NS:IsPublicPositiveInteger(challengeLevel)
        and challengeLevel >= 2
    then
        return math.min(challengeLevel, 10) + 2
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
    local activeIndex = safeCall(GetSpecialization)
    if not NS:IsPublicPositiveInteger(activeIndex) then
        return nil
    end

    local specID = safeCall(GetSpecializationInfo, activeIndex)
    if NS:IsPublicPositiveInteger(specID) then
        return specID
    end

    return nil
end

function Catalog:GetEffectiveLootSpecID()
    local lootSpecID = safeCall(GetLootSpecialization)
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
        local _, name = safeCall(GetSpecializationInfoByID, specID)
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
        Catalog:Build()
    end)
end)
