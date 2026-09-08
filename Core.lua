local addonName, NS = ...

NS.addonName = addonName
NS.displayName = "BetterBonusRolls"
NS.version = "12.1.0-1"

local CURRENT_SCHEMA = 5

-- Persisted BBR ranks, not Blizzard difficulty IDs or literal key levels.
-- Keep these values stable so existing rules and obtained-item history match.
local DUNGEON_RANK = {
    NORMAL = 1,
    HEROIC = 2,
    MYTHIC_0 = 3,
    MYTHIC_PLUS_2 = 4,
    MYTHIC_PLUS_10 = 12,
}
NS.DungeonDifficultyRank = DUNGEON_RANK

local MYTHIC_PLUS_KEY_LEVEL = {
    MINIMUM = 2,
    MAXIMUM_TRACKED = 10,
}
NS.MythicPlusKeyLevel = MYTHIC_PLUS_KEY_LEVEL

NS.RuleDefaults = {
    dungeonMinimumDifficulty = DUNGEON_RANK.MYTHIC_PLUS_10,
    delveMinimumTier = 1,
}

NS.RuleLimits = {
    dungeonMinimumDifficulty = {
        minimum = DUNGEON_RANK.MYTHIC_PLUS_2,
        maximum = DUNGEON_RANK.MYTHIC_PLUS_10,
    },
    delveMinimumTier = { minimum = 1, maximum = 11 },
}

local DEFAULTS = {
    schema = CURRENT_SCHEMA,
    enabled = false,
    minimap = {
        hide = false,
        minimapPos = 225,
    },
    raidRules = {},
    dungeonRules = {},
    contentRules = {},
    obtainedItems = {
        raid = {},
        dungeon = {},
        worldBoss = {},
    },
}

local initializers = {}
local eventCallbacks = {}
local initialized = false
local PRINT_PREFIX_COLOR_CODE = "|cff66e5ff"

local function reportError(err)
    local handler = geterrorhandler and geterrorhandler()
    if handler then
        handler(err)
    end
end

local function dispatchCallbacks(callbacks, ...)
    if not callbacks then
        return
    end

    local snapshot = {}
    for index = 1, #callbacks do
        snapshot[index] = callbacks[index]
    end

    for index = 1, #snapshot do
        local ok, err = pcall(snapshot[index], ...)
        if not ok then
            reportError(err)
        end
    end
end

function NS:Print(message)
    local text = PRINT_PREFIX_COLOR_CODE .. self.displayName .. ":|r "
        .. tostring(message)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(text)
    else
        print(text)
    end
end

function NS:IsSecret(value)
    if not issecretvalue then
        return false
    end

    local ok, secret = pcall(issecretvalue, value)
    return ok and secret == true
end

function NS:IsPublicPositiveInteger(value)
    return not self:IsSecret(value)
        and type(value) == "number"
        and value > 0
        and value % 1 == 0
end

function NS:RegisterInitializer(callback)
    assert(type(callback) == "function", "initializer must be a function")
    initializers[#initializers + 1] = callback
end

function NS:RegisterEvent(event, callback)
    assert(type(event) == "string", "event must be a string")
    assert(type(callback) == "function", "event callback must be a function")

    local callbacks = eventCallbacks[event]
    if not callbacks then
        callbacks = {}
        eventCallbacks[event] = callbacks
        self.eventFrame:RegisterEvent(event)
    end

    callbacks[#callbacks + 1] = callback
end

function NS:GetLoadedConflict()
    if not C_AddOns or not C_AddOns.IsAddOnLoaded then
        return nil
    end

    if C_AddOns.IsAddOnLoaded("BonusRollConfirm") then
        return "BonusRollConfirm"
    end
    if C_AddOns.IsAddOnLoaded("BonusRollGate") then
        return "BonusRollGate"
    end

    return nil
end

function NS:SetEnabled(enabled)
    enabled = enabled == true

    if enabled then
        local conflict = self:GetLoadedConflict()
        if conflict then
            self:Print(conflict .. " is loaded. Disable it and reload before enabling BetterBonusRolls.")
            return false
        end
    end

    self.DB:Set("enabled", enabled)
    if self.RollController then
        local applied = self.RollController:SetEnabled(enabled)
        if enabled and applied == false then
            self.DB:Set("enabled", false)
            if self.SettingsUI then
                self.SettingsUI:RefreshGeneralControls()
            end
            return false
        end
    end
    if self.SettingsUI then
        self.SettingsUI:RefreshGeneralControls()
    end

    return true
end

function NS:NotifyConfigurationChanged()
    if self.RollController then
        self.RollController:OnConfigurationChanged()
    end
end

function NS:OpenSettings(categoryID)
    if self.SettingsUI and self.SettingsUI.category then
        if InCombatLockdown and InCombatLockdown() then
            self:Print("Settings cannot be opened in combat.")
            return true
        end
        Settings.OpenToCategory(
            categoryID or self.SettingsUI.category:GetID()
        )
        return true
    end

    return false
end

local function isPositiveInteger(value)
    return not NS:IsSecret(value)
        and type(value) == "number"
        and value > 0
        and value % 1 == 0
end

local function isLootSpecSelection(value)
    return value == 0 or isPositiveInteger(value)
end

local function isIntegerInRange(value, limits)
    return type(value) == "number"
        and value % 1 == 0
        and value >= limits.minimum
        and value <= limits.maximum
end

local function isOptionalPositiveInteger(value)
    return value == nil or isPositiveInteger(value)
end

local function isOptionalNonNegativeInteger(value)
    return value == nil
        or (type(value) == "number" and value >= 0 and value % 1 == 0)
end

local function normalizeChallengeRun(data)
    local run = data.challengeRun
    if run == nil then
        return
    end
    if type(run) ~= "table" then
        data.challengeRun = nil
        return
    end

    if not isPositiveInteger(run.startedAt)
        and isPositiveInteger(run.recordedAt)
    then
        run.startedAt = run.recordedAt
    end
    run.recordedAt = nil

    if not isPositiveInteger(run.mapID)
        or not isOptionalPositiveInteger(run.level)
        or not isPositiveInteger(run.startedAt)
        or not isOptionalPositiveInteger(run.completedAt)
        or not isOptionalPositiveInteger(run.gameMapID)
        or not isOptionalPositiveInteger(run.journalInstanceID)
    then
        data.challengeRun = nil
        return
    end

    if not run.level then
        run.completedAt = nil
        run.offer = nil
        return
    end

    local offer = run.offer
    if offer == nil then
        return
    end
    if type(offer) ~= "table"
        or not isPositiveInteger(offer.spellID)
        or type(offer.endTime) ~= "number"
        or offer.endTime <= 0
        or not isOptionalNonNegativeInteger(offer.instanceID)
        or not isOptionalNonNegativeInteger(offer.encounterID)
        or not isPositiveInteger(offer.difficultyID)
    then
        run.offer = nil
    end
end

local function migrateDungeonObtainedDifficulties(data, legacyMinimum)
    local obtainedItems = data.obtainedItems
    local oldDungeons = type(obtainedItems) == "table"
        and obtainedItems.dungeon or nil
    if type(oldDungeons) ~= "table" then
        return
    end

    local migrated = {}
    for mapID, specifications in pairs(oldDungeons) do
        if isPositiveInteger(mapID) and type(specifications) == "table" then
            local rule = type(data.dungeonRules) == "table"
                and data.dungeonRules[mapID] or nil
            local difficulty = type(rule) == "table"
                and rule.minimumDifficulty or nil
            if isPositiveInteger(rule) then
                difficulty = legacyMinimum
            end

            -- Preserve ranks 1-3 in old obtained-item history even though
            -- Normal, Heroic, and Mythic 0 are no longer selectable.
            if not isPositiveInteger(difficulty)
                or difficulty > NS.RuleLimits.dungeonMinimumDifficulty.maximum
            then
                difficulty = NS.RuleDefaults.dungeonMinimumDifficulty
            end

            migrated[mapID] = {
                [difficulty] = specifications,
            }
        end
    end

    obtainedItems.dungeon = migrated
end

local function getLegacyDungeonMinimum(data)
    local mythicPlus = data.mythicPlus
    if type(mythicPlus) == "table"
        and mythicPlus.enforceMinimumLevel == false
    then
        return DUNGEON_RANK.NORMAL
    end

    local level = type(mythicPlus) == "table"
        and mythicPlus.minimumLevel or nil
    if type(level) ~= "number" or level % 1 ~= 0 then
        level = MYTHIC_PLUS_KEY_LEVEL.MAXIMUM_TRACKED
    end
    level = math.max(
        MYTHIC_PLUS_KEY_LEVEL.MINIMUM,
        math.min(MYTHIC_PLUS_KEY_LEVEL.MAXIMUM_TRACKED, level)
    )

    return DUNGEON_RANK.MYTHIC_PLUS_2
        + (level - MYTHIC_PLUS_KEY_LEVEL.MINIMUM)
end

local function normalizeDungeonRules(data, legacyMinimum)
    if type(data.dungeonRules) ~= "table" then
        data.dungeonRules = {}
        return
    end

    for mapID, rule in pairs(data.dungeonRules) do
        if isPositiveInteger(rule) then
            data.dungeonRules[mapID] = {
                specializationID = rule,
                minimumDifficulty = math.max(
                    legacyMinimum,
                    NS.RuleLimits.dungeonMinimumDifficulty.minimum
                ),
            }
        elseif type(rule) == "table" then
            if not isLootSpecSelection(rule.specializationID) then
                data.dungeonRules[mapID] = nil
            else
                if isPositiveInteger(rule.minimumDifficulty)
                    and rule.minimumDifficulty
                        < NS.RuleLimits.dungeonMinimumDifficulty.minimum
                then
                    -- Former base-difficulty minimums already allowed every
                    -- key. Keep that behavior by choosing the lowest M+ key.
                    rule.minimumDifficulty =
                        NS.RuleLimits.dungeonMinimumDifficulty.minimum
                elseif not isIntegerInRange(
                    rule.minimumDifficulty,
                    NS.RuleLimits.dungeonMinimumDifficulty
                ) then
                    rule.minimumDifficulty = NS.RuleDefaults.dungeonMinimumDifficulty
                end
            end
        else
            data.dungeonRules[mapID] = nil
        end
    end
end

local function normalizeContentRule(rule, hasTier)
    if isPositiveInteger(rule) then
        rule = { specializationID = rule }
    elseif type(rule) ~= "table" then
        return nil
    end

    if not isLootSpecSelection(rule.specializationID) then
        return nil
    end

    if hasTier and not isIntegerInRange(
        rule.minimumTier,
        NS.RuleLimits.delveMinimumTier
    ) then
        rule.minimumTier = NS.RuleDefaults.delveMinimumTier
    end

    return rule
end

local function normalizeWorldBossRules(contentRules)
    local rules = contentRules.worldBosses
    if type(rules) ~= "table" then
        contentRules.worldBosses = {}
        return
    end

    for encounterID, rule in pairs(rules) do
        if not isPositiveInteger(encounterID) then
            rules[encounterID] = nil
        else
            rules[encounterID] = normalizeContentRule(rule, false)
        end
    end
end

local function normalizeMinimapSettings(data)
    if data.minimap == nil then
        return
    end
    if type(data.minimap) ~= "table" then
        data.minimap = nil
        return
    end

    if data.minimap.hide ~= nil
        and type(data.minimap.hide) ~= "boolean"
    then
        data.minimap.hide = nil
    end

    local minimapPos = data.minimap.minimapPos
    if minimapPos ~= nil
        and (type(minimapPos) ~= "number"
            or minimapPos ~= minimapPos
            or minimapPos < 0
            or minimapPos >= 360)
    then
        data.minimap.minimapPos = nil
    end
end

local function normalizeObtainedBranch(branch, depth)
    if NS:IsSecret(branch) or type(branch) ~= "table" then
        return {}
    end

    for key, value in pairs(branch) do
        if not isPositiveInteger(key) then
            branch[key] = nil
        elseif depth == 1 then
            if NS:IsSecret(value) or value ~= true then
                branch[key] = nil
            end
        else
            local normalized = normalizeObtainedBranch(value, depth - 1)

            if next(normalized) == nil then
                branch[key] = nil
            else
                branch[key] = normalized
            end
        end
    end

    return branch
end

local function normalizeObtainedItems(data)
    local obtainedItems = data.obtainedItems
    if NS:IsSecret(obtainedItems) or type(obtainedItems) ~= "table" then
        obtainedItems = {}
        data.obtainedItems = obtainedItems
    end

    obtainedItems.raid = normalizeObtainedBranch(
        obtainedItems.raid,
        5
    )
    obtainedItems.dungeon = normalizeObtainedBranch(
        obtainedItems.dungeon,
        4
    )
    obtainedItems.worldBoss = normalizeObtainedBranch(
        obtainedItems.worldBoss,
        3
    )
end

local function normalizeDatabase(data)
    if type(data.schema) ~= "number"
        or data.schema % 1 ~= 0
        or data.schema < 1
    then
        data.schema = 1
    end

    local legacyMinimum = getLegacyDungeonMinimum(data)

    if data.schema < 4 then
        -- Assign old combined history before moving base-difficulty rules to
        -- +2, so that history cannot be mistaken for Mythic+ obtained items.
        migrateDungeonObtainedDifficulties(data, legacyMinimum)
    end

    normalizeDungeonRules(data, legacyMinimum)

    data.schema = CURRENT_SCHEMA

    -- This global Mythic+ setting became a per-dungeon threshold in schema 2.
    data.mythicPlus = nil

    if data.enabled ~= nil and type(data.enabled) ~= "boolean" then
        data.enabled = nil
    end
    normalizeMinimapSettings(data)
    if type(data.raidRules) ~= "table" then
        data.raidRules = {}
    end
    if type(data.contentRules) ~= "table" then
        data.contentRules = {}
    end

    data.contentRules.delves = normalizeContentRule(
        data.contentRules.delves,
        true
    )
    data.contentRules.world = normalizeContentRule(
        data.contentRules.world,
        false
    )
    normalizeWorldBossRules(data.contentRules)
    normalizeChallengeRun(data)
    normalizeObtainedItems(data)
end

local function initializeDatabase()
    local data = _G.BetterBonusRollsDB
    if type(data) ~= "table" then
        data = {}
        _G.BetterBonusRollsDB = data
    end

    normalizeDatabase(data)

    NS.DB = LibStub("LibSimpleDB-2.0"):New(data, DEFAULTS)
end

local function initializeAddon()
    if initialized then
        return
    end
    initialized = true

    initializeDatabase()
    dispatchCallbacks(initializers)

    if NS.DB:Get("enabled") then
        local conflict = NS:GetLoadedConflict()
        if conflict then
            NS.DB:Set("enabled", false)
            NS:Print(conflict .. " is loaded, so BetterBonusRolls was left disabled. Disable it and reload first.")
        else
            NS.Catalog:WhenReady(function()
                if not NS.DB:Get("enabled") then
                    return
                end

                local applied = NS.RollController:SetEnabled(true)
                if applied == false then
                    NS.DB:Set("enabled", false)
                    if NS.SettingsUI then
                        NS.SettingsUI:RefreshGeneralControls()
                    end
                end
            end)
        end
    end
end

NS.eventFrame = CreateFrame("Frame")
NS.eventFrame:RegisterEvent("ADDON_LOADED")
NS.eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" and ... == addonName then
        initializeAddon()
    end

    dispatchCallbacks(eventCallbacks[event], event, ...)
end)
