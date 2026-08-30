local testsRun = 0

local function fail(message)
    error(message, 2)
end

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        fail((message or "values differ")
            .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual))
    end
end

local function assertContains(text, expected, message)
    if not text or not text:find(expected, 1, true) then
        fail((message or "text did not match")
            .. ": expected to find " .. expected
            .. " in " .. tostring(text))
    end
end

local function makeButton()
    local button = {
        scripts = {},
        shown = true,
        enabled = true,
    }

    function button:GetScript(name)
        return self.scripts[name]
    end

    function button:SetScript(name, callback)
        self.scripts[name] = callback
    end

    function button:Enable()
        self.enabled = true
    end

    function button:Disable()
        self.enabled = false
    end

    function button:SetEnabled(enabled)
        self.enabled = enabled == true
    end

    function button:SetSize()
    end

    function button:SetPoint()
    end

    function button:SetFrameLevel()
    end

    function button:SetText(text)
        self.text = text
    end

    function button:Show()
        self.shown = true
    end

    function button:Hide()
        self.shown = false
    end

    function button:IsShown()
        return self.shown
    end

    return button
end

local function buildHarness(options)
    options = options or {}
    local harness = {
        now = 1000,
        nativeRolls = 0,
        nativePasses = 0,
        lootSpecChanges = 0,
        currentSpecID = options.currentSpecID or 1,
        activeSpecID = options.activeSpecID or 1,
        lastLootSpecSelection = nil,
        raidRule = options.raidRule,
        dungeonRule = options.dungeonRule,
        delveRule = options.delveRule,
        worldBossRule = options.worldBossRule,
        worldRule = options.worldRule,
        delveTier = options.delveTier,
        challengeMapID = options.challengeMapID or 300,
        challengeLevel = options.challengeLevel or 10,
        messages = {},
        events = {},
        initializers = {},
        popupShown = false,
    }
    if options.raidRule == nil and not options.unconfigured then
        harness.raidRule = 1
    end

    local roll = makeButton()
    local pass = makeButton()
    local prompt = {
        RollButton = roll,
        PassButton = pass,
    }
    function prompt:GetFrameLevel()
        return 10
    end

    local bonusFrame = {
        state = "prompt",
        spellID = 500,
        endTime = 1100,
        instanceID = options.instanceID == nil and 100 or options.instanceID,
        encounterID = options.encounterID == nil and 200
            or options.encounterID,
        difficultyID = options.difficultyID or 14,
        PromptFrame = prompt,
        shown = true,
        hooks = {},
    }
    function bonusFrame:IsShown()
        return self.shown
    end
    function bonusFrame:HookScript(name, callback)
        self.hooks[name] = callback
    end

    roll:SetScript("OnClick", function(self)
        harness.nativeRolls = harness.nativeRolls + 1
        self:Disable()
    end)
    pass:SetScript("OnClick", function()
        harness.nativePasses = harness.nativePasses + 1
    end)

    BonusRollFrame = bonusFrame
    GroupLootContainer = {}
    BonusRollFrame_StartBonusRoll = function()
    end
    GroupLootContainer_AddFrame = function(_, target)
        target.shown = true
    end
    GroupLootContainer_RemoveFrame = function(_, target)
        target.shown = false
        if target.hooks.OnHide then
            target.hooks.OnHide(target)
        end
    end
    hooksecurefunc = function(_, callback)
        harness.startHook = callback
    end
    CreateFrame = function(frameType, _, _, template)
        assertEqual(frameType, "Button", "switch frame type")
        assertEqual(template, "UIPanelButtonTemplate", "switch template")
        harness.switchButton = makeButton()
        return harness.switchButton
    end
    C_AddOns = {
        LoadAddOn = function()
            return true
        end,
    }
    C_ChallengeMode = {
        GetChallengeCompletionInfo = function()
            return {
                mapChallengeModeID = harness.challengeMapID,
                level = harness.challengeLevel,
            }
        end,
        GetActiveChallengeMapID = function()
            return harness.challengeMapID
        end,
        GetActiveKeystoneInfo = function()
            return harness.challengeLevel, {}
        end,
    }
    C_DelvesUI = {
        GetActiveDelveTier = function()
            return { tier = harness.delveTier }
        end,
    }
    Enum = {
        ConfirmationPromptUIType = {
            BonusRoll = 3,
        },
    }
    GameTooltip = {
        SetOwner = function()
        end,
        SetText = function()
        end,
        AddLine = function()
        end,
        Show = function()
        end,
    }
    GameTooltip_Hide = function()
    end
    StaticPopup_ShowCustomGenericConfirmation = function(data)
        harness.popup = data
        harness.popupShown = true
    end
    StaticPopup_IsCustomGenericConfirmationShown = function(referenceKey)
        return harness.popupShown
            and harness.popup
            and harness.popup.referenceKey == referenceKey
    end
    StaticPopup_Hide = function()
        harness.popupShown = false
    end
    SetLootSpecialization = function(specID)
        harness.lootSpecChanges = harness.lootSpecChanges + 1
        harness.lastLootSpecSelection = specID
        harness.currentSpecID = specID == 0 and harness.activeSpecID or specID
    end
    time = function()
        return harness.now
    end

    local NS = {
        Catalog = {
            Difficulty = {
                DUNGEON_NORMAL = 1,
                DUNGEON_HEROIC = 2,
                MYTHIC_PLUS = 8,
                FLEX_MYTHIC = 233,
                MYTHIC = 16,
                DUNGEON_MYTHIC = 23,
                WORLD_BOSS = 172,
                DELVE = 208,
            },
            specByID = {
                [1] = { id = 1, name = "Restoration" },
                [2] = { id = 2, name = "Elemental" },
            },
            raidByInstance = {
                [100] = {
                    id = 100,
                    name = "Test Raid",
                    encounterByID = {
                        [200] = { id = 200, name = "Ula'tek" },
                    },
                    difficultyByID = {
                        [14] = { id = 14, label = "Normal" },
                        [16] = { id = 16, label = "Mythic" },
                    },
                },
            },
            worldBossByEncounter = {
                [200] = {
                    id = 200,
                    name = "Ula'tek",
                    instanceID = 100,
                },
            },
            dungeonByMap = {
                [300] = {
                    id = 300,
                    name = "Test Dungeon",
                    journalInstanceID = 100,
                },
            },
            dungeonByInstance = {
                [100] = {
                    {
                        id = 300,
                        name = "Test Dungeon",
                        journalInstanceID = 100,
                    },
                },
            },
        },
        RuleLimits = {
            dungeonMinimumDifficulty = { minimum = 1, maximum = 12 },
            delveMinimumTier = { minimum = 1, maximum = 11 },
        },
    }

    function NS:IsSecret()
        return false
    end

    function NS:IsPublicPositiveInteger(value)
        return type(value) == "number"
            and value > 0
            and value % 1 == 0
    end

    function NS:Print(message)
        harness.messages[#harness.messages + 1] = message
    end

    function NS:RegisterInitializer(callback)
        harness.initializers[#harness.initializers + 1] = callback
    end

    function NS:RegisterEvent(event, callback)
        harness.events[event] = callback
    end

    function NS.Catalog:CanonicalDifficultyID(difficultyID)
        return difficultyID == 233 and 16 or difficultyID
    end

    function NS.Catalog:GetDifficultyName(difficultyID)
        local labels = {
            [1] = "Normal",
            [2] = "Heroic",
            [14] = "Normal",
            [16] = "Mythic",
            [23] = "Mythic",
        }
        return labels[self:CanonicalDifficultyID(difficultyID)] or "Unknown"
    end

    function NS.Catalog:IsDungeonDifficulty(difficultyID)
        return difficultyID == 1
            or difficultyID == 2
            or difficultyID == 8
            or difficultyID == 23
    end

    function NS.Catalog:GetDungeonCompletionRank(difficultyID, level)
        if difficultyID == 1 then
            return 1
        elseif difficultyID == 2 then
            return 2
        elseif difficultyID == 23 then
            return 3
        elseif difficultyID == 8 and type(level) == "number" and level >= 2 then
            return math.min(level, 10) + 2
        end
    end

    function NS.Catalog:GetDungeonThresholdLabel(rank)
        local labels = {
            [1] = "Normal",
            [2] = "Heroic",
            [3] = "Mythic",
        }
        return labels[rank] or "+" .. tostring(rank - 2)
    end

    function NS.Catalog:GetEffectiveLootSpecID()
        return harness.currentSpecID
    end

    function NS.Catalog:GetActiveSpecID()
        return harness.activeSpecID
    end

    function NS.Catalog:GetSpecName(specID)
        local spec = self.specByID[specID]
        return spec and spec.name or "Unknown"
    end

    NS.DB = {}
    function NS.DB:Get(first, second, third, fourth)
        if first == "raidRules" then
            return harness.raidRule
        elseif first == "dungeonRules" then
            return harness.dungeonRule and harness.dungeonRule[third]
        elseif first == "contentRules" and second == "delves" then
            return harness.delveRule and harness.delveRule[third]
        elseif first == "contentRules" and second == "worldBosses" then
            return harness.worldBossRule and harness.worldBossRule[fourth]
        elseif first == "contentRules" and second == "world" then
            return harness.worldRule and harness.worldRule[third]
        elseif first == "enabled" then
            return harness.databaseEnabled
        end
        return nil
    end
    function NS.DB:Set(first, value)
        if first == "enabled" then
            harness.databaseEnabled = value
        end
    end

    local chunk = assert(loadfile("RollController.lua"))
    chunk("BetterBonusRolls", NS)
    for index = 1, #harness.initializers do
        harness.initializers[index]()
    end

    harness.NS = NS
    harness.frame = bonusFrame
    harness.rollButton = roll
    harness.passButton = pass
    if options.cachedDelveTier then
        harness.delveTier = options.cachedDelveTier
        harness.events.ACTIVE_DELVE_DATA_UPDATE(
            "ACTIVE_DELVE_DATA_UPDATE"
        )
        harness.delveTier = nil
    end
    assertEqual(NS.RollController:SetEnabled(true), true, "controller enabled")
    return harness
end

local function clickRoll(harness)
    local callback = harness.rollButton:GetScript("OnClick")
    callback(harness.rollButton, "LeftButton", false)
end

local function acceptPopup(harness)
    harness.popupShown = false
    harness.popup.callback()
end

local function cancelPopup(harness)
    harness.popupShown = false
    harness.popup.cancelCallback()
end

local function test(name, callback)
    callback()
    testsRun = testsRun + 1
    io.write("ok - ", name, "\n")
end

test("native roll requires click and confirmation", function()
    local harness = buildHarness()
    assertEqual(harness.nativeRolls, 0, "nothing rolls on enable")

    clickRoll(harness)
    assertEqual(harness.nativeRolls, 0, "first click only arms")
    assertEqual(harness.rollButton.enabled, false, "roll disabled while armed")
    assertEqual(harness.popup.acceptText, "Use Bonus Roll", "correct-spec text")

    local callback = harness.popup.callback
    acceptPopup(harness)
    assertEqual(harness.nativeRolls, 1, "confirmation invokes native once")
    callback()
    assertEqual(harness.nativeRolls, 1, "authorization is one shot")
end)

test("cancel disarms and requires a fresh click", function()
    local harness = buildHarness()
    clickRoll(harness)
    local staleCallback = harness.popup.callback
    cancelPopup(harness)

    assertEqual(harness.nativeRolls, 0, "cancel does not roll")
    assertEqual(harness.rollButton.enabled, true, "cancel re-enables Roll")
    staleCallback()
    assertEqual(harness.nativeRolls, 0, "stale accept does nothing")

    clickRoll(harness)
    acceptPopup(harness)
    assertEqual(harness.nativeRolls, 1, "fresh click can be confirmed")
end)

test("snapshot mismatch fails closed", function()
    local harness = buildHarness()
    clickRoll(harness)
    harness.currentSpecID = 2
    acceptPopup(harness)

    assertEqual(harness.nativeRolls, 0, "changed spec blocks native Roll")
    assertEqual(harness.rollButton.enabled, true, "mismatch re-enables Roll")
    assertContains(
        harness.messages[#harness.messages],
        "state changed",
        "mismatch explains fresh click"
    )
end)

test("loot-spec event disarms pending confirmation", function()
    local harness = buildHarness()
    clickRoll(harness)
    local staleCallback = harness.popup.callback
    harness.events.PLAYER_LOOT_SPEC_UPDATED("PLAYER_LOOT_SPEC_UPDATED")
    staleCallback()

    assertEqual(harness.nativeRolls, 0, "spec event invalidates token")
    assertEqual(harness.rollButton.enabled, true, "spec event re-enables Roll")
end)

test("rule changes disarm pending confirmation", function()
    local harness = buildHarness()
    clickRoll(harness)
    local staleCallback = harness.popup.callback

    harness.NS.RollController:OnConfigurationChanged()
    staleCallback()

    assertEqual(harness.nativeRolls, 0, "rule change invalidates token")
    assertEqual(harness.rollButton.enabled, true, "rule change re-enables Roll")
end)

test("Blizzard deactivation disarms and blocks Roll", function()
    local harness = buildHarness()
    clickRoll(harness)
    local staleCallback = harness.popup.callback

    harness.events.BONUS_ROLL_DEACTIVATE("BONUS_ROLL_DEACTIVATE")
    staleCallback()
    assertEqual(harness.nativeRolls, 0, "deactivation invalidates token")

    local callback = harness.rollButton:GetScript("OnClick")
    callback(harness.rollButton, "LeftButton", false)
    assertEqual(harness.nativeRolls, 0, "deactivated Roll cannot arm")

    harness.events.BONUS_ROLL_ACTIVATE("BONUS_ROLL_ACTIVATE")
    assertEqual(harness.rollButton.enabled, true, "activation restores Roll")
end)

test("new offer disarms pending confirmation", function()
    local harness = buildHarness()
    clickRoll(harness)
    local staleCallback = harness.popup.callback

    harness.frame.spellID = 501
    harness.frame.endTime = 1200
    harness.NS.RollController:OnOfferStarted()
    staleCallback()

    assertEqual(harness.nativeRolls, 0, "new offer invalidates old token")
end)

test("No hides without invoking native Pass", function()
    local harness = buildHarness()
    local callback = harness.passButton:GetScript("OnClick")
    callback(harness.passButton, "LeftButton", false)

    assertEqual(harness.nativePasses, 0, "native Pass is unreachable")
    assertEqual(harness.frame.shown, false, "offer is hidden")
    assertContains(
        harness.messages[#harness.messages],
        "Use /bbr show",
        "hide message includes recovery"
    )
end)

test("timeout disarms and prevents restoration", function()
    local harness = buildHarness()
    clickRoll(harness)
    local staleCallback = harness.popup.callback
    harness.events.SPELL_CONFIRMATION_TIMEOUT(
        "SPELL_CONFIRMATION_TIMEOUT",
        harness.frame.spellID,
        Enum.ConfirmationPromptUIType.BonusRoll
    )
    staleCallback()

    assertEqual(harness.nativeRolls, 0, "timeout invalidates token")
    assertEqual(
        harness.NS.RollController:ShowCurrent(),
        false,
        "expired offer cannot be restored"
    )
    assertContains(
        harness.messages[#harness.messages - 1],
        "expired without being used",
        "timeout is explicit"
    )
end)

test("disable disarms and restores native scripts", function()
    local harness = buildHarness()
    clickRoll(harness)
    local staleCallback = harness.popup.callback
    harness.NS.RollController:SetEnabled(false)
    staleCallback()

    assertEqual(harness.nativeRolls, 0, "disable invalidates token")
    harness.rollButton:GetScript("OnClick")(harness.rollButton)
    assertEqual(harness.nativeRolls, 1, "disabled mode restores native Roll")
end)

test("wrong-spec switch changes only loot specialization", function()
    local harness = buildHarness({ currentSpecID = 2, raidRule = 1 })
    assertEqual(harness.switchButton.shown, true, "switch button is visible")
    assertEqual(harness.switchButton.text, "Switch to Restoration", "switch label")

    harness.switchButton:GetScript("OnClick")(harness.switchButton)
    assertEqual(harness.lootSpecChanges, 1, "switch changes loot spec")
    assertEqual(harness.nativeRolls, 0, "switch never rolls")
    assertEqual(harness.nativePasses, 0, "switch never passes")
end)

test("Current Spec rules use Blizzard's default loot-spec selection", function()
    local harness = buildHarness({
        activeSpecID = 1,
        currentSpecID = 2,
        raidRule = 0,
    })

    assertEqual(harness.switchButton.shown, true, "current-spec switch is visible")
    harness.switchButton:GetScript("OnClick")(harness.switchButton)

    assertEqual(harness.lastLootSpecSelection, 0, "switch selects Current Spec")
    assertEqual(harness.currentSpecID, 1, "Current Spec resolves to active spec")
    assertEqual(harness.nativeRolls, 0, "current-spec switch never rolls")
    assertEqual(harness.nativePasses, 0, "current-spec switch never passes")
end)

test("wrong-spec confirmation requires Roll Anyway", function()
    local harness = buildHarness({ currentSpecID = 2, raidRule = 1 })
    clickRoll(harness)

    assertEqual(harness.popup.acceptText, "Roll Anyway", "wrong-spec accept text")
    assertContains(
        harness.popup.text,
        "Changing loot specialization now will change",
        "wrong-spec warning explains timing"
    )
    acceptPopup(harness)
    assertEqual(harness.nativeRolls, 1, "explicit Roll Anyway can roll")
end)

test("unconfigured offer hides but can be manually confirmed", function()
    local harness = buildHarness({ unconfigured = true })
    assertEqual(harness.frame.shown, false, "unconfigured offer auto-hides")
    assertEqual(harness.nativePasses, 0, "auto-hide never passes")

    assertEqual(harness.NS.RollController:ShowCurrent(), true, "manual restore works")
    clickRoll(harness)
    assertEqual(harness.popup.acceptText, "Roll Anyway", "violation is explicit")
    acceptPopup(harness)
    assertEqual(harness.nativeRolls, 1, "manual restore still needs two clicks")
end)

io.write("\n", testsRun, " critical bonus-roll tests passed\n")

