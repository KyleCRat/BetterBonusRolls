local _, NS = ...

local Migrations = {}
NS.Migrations = Migrations

local DUNGEON_RANK = NS.DungeonDifficultyRank
local MYTHIC_PLUS_KEY_LEVEL = NS.MythicPlusKeyLevel

-- Historical conversions must keep their original meanings. Use the stable
-- rank constants here, not today's configurable rule limits or defaults.
local function getLegacyDungeonMinimum(data)
    local mythicPlus = data.mythicPlus
    if NS:IsSecret(mythicPlus) or type(mythicPlus) ~= "table" then
        return DUNGEON_RANK.MYTHIC_PLUS_10
    end

    if not NS:IsSecret(mythicPlus.enforceMinimumLevel)
        and mythicPlus.enforceMinimumLevel == false
    then
        return DUNGEON_RANK.NORMAL
    end

    local level = mythicPlus.minimumLevel
    if NS:IsSecret(level) or type(level) ~= "number" or level % 1 ~= 0 then
        return DUNGEON_RANK.MYTHIC_PLUS_10
    end

    local rank = DUNGEON_RANK.MYTHIC_PLUS_2
        + (level - MYTHIC_PLUS_KEY_LEVEL.MINIMUM)
    return math.max(
        DUNGEON_RANK.MYTHIC_PLUS_2,
        math.min(DUNGEON_RANK.MYTHIC_PLUS_10, rank)
    )
end

local function migrateContentRule(rule)
    if NS:IsPublicPositiveInteger(rule) then
        return { specializationID = rule }
    end

    return rule
end

local function migrateTo2(data)
    -- Scalar loot specs became rule records with per-source minimums.
    local legacyMinimum = getLegacyDungeonMinimum(data)
    local dungeonRules = data.dungeonRules
    if not NS:IsSecret(dungeonRules) and type(dungeonRules) == "table" then
        for mapID, rule in pairs(dungeonRules) do
            if NS:IsPublicPositiveInteger(mapID)
                and NS:IsPublicPositiveInteger(rule)
            then
                dungeonRules[mapID] = {
                    specializationID = rule,
                    minimumDifficulty = legacyMinimum,
                }
            end
        end
    end

    local contentRules = data.contentRules
    if not NS:IsSecret(contentRules) and type(contentRules) == "table" then
        contentRules.delves = migrateContentRule(contentRules.delves)
        contentRules.world = migrateContentRule(contentRules.world)

        local worldBosses = contentRules.worldBosses
        if not NS:IsSecret(worldBosses) and type(worldBosses) == "table" then
            for encounterID, rule in pairs(worldBosses) do
                if NS:IsPublicPositiveInteger(encounterID) then
                    worldBosses[encounterID] = migrateContentRule(rule)
                end
            end
        end
    end

    data.mythicPlus = nil
end

local function migrateTo3(data)
    -- Schema 3 added obtained-item history without changing existing values.
    -- Current-format validation fills its empty source branches afterward.
    if NS:IsSecret(data.obtainedItems) or type(data.obtainedItems) ~= "table" then
        data.obtainedItems = {}
    end
end

local function migrateTo4(data)
    local run = data.challengeRun
    if not NS:IsSecret(run) and type(run) == "table" then
        if not NS:IsPublicPositiveInteger(run.startedAt)
            and NS:IsPublicPositiveInteger(run.recordedAt)
        then
            run.startedAt = run.recordedAt
        end

        run.recordedAt = nil
    end

    local obtainedItems = data.obtainedItems
    if NS:IsSecret(obtainedItems) or type(obtainedItems) ~= "table" then
        return
    end

    local oldDungeons = obtainedItems.dungeon
    if NS:IsSecret(oldDungeons) or type(oldDungeons) ~= "table" then
        return
    end

    local dungeonRules = data.dungeonRules
    if NS:IsSecret(dungeonRules) or type(dungeonRules) ~= "table" then
        dungeonRules = {}
    end

    -- map/spec/item becomes map/difficulty/spec/item. Preserve the original
    -- difficulty, including Normal/Heroic/Mythic 0, before schema 5 changes
    -- minimums to +2. Build the replacement before assigning it to the save.
    local migrated = {}
    for mapID, specifications in pairs(oldDungeons) do
        if NS:IsPublicPositiveInteger(mapID)
            and not NS:IsSecret(specifications)
            and type(specifications) == "table"
        then
            local difficulty = DUNGEON_RANK.MYTHIC_PLUS_10
            local rule = dungeonRules[mapID]
            if not NS:IsSecret(rule) and type(rule) == "table"
                and NS:IsPublicPositiveInteger(rule.minimumDifficulty)
                and rule.minimumDifficulty <= DUNGEON_RANK.MYTHIC_PLUS_10
            then
                difficulty = rule.minimumDifficulty
            end

            migrated[mapID] = {
                [difficulty] = specifications,
            }
        end
    end

    obtainedItems.dungeon = migrated
end

local function migrateTo5(data)
    local dungeonRules = data.dungeonRules
    if NS:IsSecret(dungeonRules) or type(dungeonRules) ~= "table" then
        return
    end

    for _, rule in pairs(dungeonRules) do
        if not NS:IsSecret(rule) and type(rule) == "table"
            and NS:IsPublicPositiveInteger(rule.minimumDifficulty)
            and rule.minimumDifficulty <= DUNGEON_RANK.MYTHIC_0
        then
            -- These minimums already allowed every key. Keep that behavior
            -- without moving any obtained history to a different pool.
            rule.minimumDifficulty = DUNGEON_RANK.MYTHIC_PLUS_2
        end
    end
end

local function migrateObtainedRecords(branch, depth)
    if NS:IsSecret(branch) or type(branch) ~= "table" then
        return
    end

    for key, value in pairs(branch) do
        if NS:IsPublicPositiveInteger(key) and not NS:IsSecret(value) then
            if depth == 1 then
                if value == true then
                    -- Older saves did not distinguish manual checkmarks from
                    -- automatic evidence. Preserve progress without claiming
                    -- that its source can be reconstructed.
                    branch[key] = {
                        obtained = true,
                        confirmedObtained = false,
                    }
                end
            else
                migrateObtainedRecords(value, depth - 1)
            end
        end
    end
end

local function migrateTo6(data)
    local obtainedItems = data.obtainedItems
    if NS:IsSecret(obtainedItems) or type(obtainedItems) ~= "table" then
        return
    end

    migrateObtainedRecords(obtainedItems.raid, 5)
    migrateObtainedRecords(obtainedItems.dungeon, 4)
    migrateObtainedRecords(obtainedItems.worldBoss, 3)
end

local migrations = {
    [2] = migrateTo2,
    [3] = migrateTo3,
    [4] = migrateTo4,
    [5] = migrateTo5,
    [6] = migrateTo6,
}

function Migrations.Apply(data, currentSchema)
    local schema = data.schema
    if not NS:IsPublicPositiveInteger(schema) then
        schema = 1
    end

    -- Refuse downgrades before changing saved data or applying defaults.
    if schema > currentSchema then
        error(("BetterBonusRolls saved data uses schema %d; this version supports %d. "
            .. "Update the addon; saved data has not been changed."):format(
            schema,
            currentSchema
        ))
    end

    -- Numeric iteration is deliberate: pairs() would not preserve order.
    -- Only stamp a version after its complete migration returns successfully.
    for version = schema + 1, currentSchema do
        migrations[version](data)
        data.schema = version
    end
end
