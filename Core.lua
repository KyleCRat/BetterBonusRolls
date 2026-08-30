local addonName, NS = ...

NS.addonName = addonName
NS.displayName = "BetterBonusRolls"
NS.version = "12.1.0-1"

local CURRENT_SCHEMA = 2

NS.RuleDefaults = {
    dungeonMinimumDifficulty = 12,
    delveMinimumTier = 1,
}

NS.RuleLimits = {
    dungeonMinimumDifficulty = { minimum = 1, maximum = 12 },
    delveMinimumTier = { minimum = 1, maximum = 11 },
}

local DEFAULTS = {
    schema = CURRENT_SCHEMA,
    enabled = false,
    raidRules = {},
    dungeonRules = {},
    contentRules = {},
}

local initializers = {}
local eventCallbacks = {}
local initialized = false

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
    local text = self.displayName .. ": " .. tostring(message)
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

function NS:OpenSettings()
    if self.SettingsUI and self.SettingsUI.category then
        if InCombatLockdown and InCombatLockdown() then
            self:Print("Settings cannot be opened in combat.")
            return true
        end
        Settings.OpenToCategory(self.SettingsUI.category:GetID())
        return true
    end

    return false
end

local function isPositiveInteger(value)
    return type(value) == "number"
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

local function getLegacyDungeonMinimum(data)
    local mythicPlus = data.mythicPlus
    if type(mythicPlus) == "table"
        and mythicPlus.enforceMinimumLevel == false
    then
        return NS.RuleLimits.dungeonMinimumDifficulty.minimum
    end

    local level = type(mythicPlus) == "table"
        and mythicPlus.minimumLevel or nil
    if type(level) ~= "number" or level % 1 ~= 0 then
        level = 10
    end
    level = math.max(2, math.min(10, level))

    -- Normal, Heroic, Mythic, then +2 through +10.
    return level + 2
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
                minimumDifficulty = legacyMinimum,
            }
        elseif type(rule) == "table" then
            if not isLootSpecSelection(rule.specializationID) then
                data.dungeonRules[mapID] = nil
            else
                if not isIntegerInRange(
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

local function normalizeDatabase(data)
    if type(data.schema) ~= "number"
        or data.schema % 1 ~= 0
        or data.schema < 1
    then
        data.schema = 1
    end

    local legacyMinimum = getLegacyDungeonMinimum(data)
    normalizeDungeonRules(data, legacyMinimum)

    if data.schema < CURRENT_SCHEMA then
        data.schema = CURRENT_SCHEMA
    end

    -- This global Mythic+ setting became a per-dungeon threshold in schema 2.
    data.mythicPlus = nil

    if data.enabled ~= nil and type(data.enabled) ~= "boolean" then
        data.enabled = nil
    end
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
            NS:RegisterEvent("PLAYER_LOGIN", function()
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
