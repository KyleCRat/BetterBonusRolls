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

local function assertNotContains(text, unexpected, message)
    if text and text:find(unexpected, 1, true) then
        fail((message or "text unexpectedly matched")
            .. ": did not expect to find " .. unexpected
            .. " in " .. tostring(text))
    end
end

local function copyValue(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, child in pairs(value) do
        copy[copyValue(key)] = copyValue(child)
    end
    return copy
end

local function makeRegion()
    local region = {}

    function region:SetAllPoints()
    end

    function region:SetAtlas(atlas)
        self.atlas = atlas
    end

    function region:SetBlendMode(blendMode)
        self.blendMode = blendMode
    end

    function region:SetPoint()
    end

    function region:SetJustifyH(justification)
        self.justification = justification
    end

    function region:SetSize()
    end

    function region:SetTexCoord()
    end

    function region:SetText(text)
        self.text = text
    end

    function region:SetTexture(texture)
        self.texture = texture
    end

    return region
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

    function button:CreateFontString()
        local region = makeRegion()
        self.fontString = region
        return region
    end

    function button:CreateTexture()
        return makeRegion()
    end

    function button:SetHighlightTexture(texture)
        self.highlightTexture = texture
    end

    function button:SetNormalTexture(texture)
        self.normalTexture = texture
    end

    function button:SetPushedTexture(texture)
        self.pushedTexture = texture
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
        activeChallengeMapID = options.activeChallengeMapID,
        completionChallengeMapID = options.completionChallengeMapID,
        challengeLevel = options.challengeLevel or 10,
        challengeRun = copyValue(options.challengeRun),
        messages = {},
        events = {},
        initializers = {},
        popupShown = false,
        recordedItems = {},
    }
    if options.raidRule == nil and not options.unconfigured then
        harness.raidRule = 1
    end
    if harness.activeChallengeMapID == nil then
        harness.activeChallengeMapID = harness.challengeMapID
    end
    if harness.completionChallengeMapID == nil then
        harness.completionChallengeMapID = harness.challengeMapID
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
        endTime = options.endTime or 1100,
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
    CreateFrame = function(frameType, _, parent, template)
        if frameType == "Frame" then
            assertEqual(parent, prompt, "switch panel parent")
            assertEqual(
                template,
                "TooltipBackdropTemplate",
                "switch panel template"
            )
            harness.switchPanel = makeButton()
            return harness.switchPanel
        end

        assertEqual(frameType, "Button", "switch button frame type")
        assertEqual(parent, harness.switchPanel, "switch button parent")
        assertEqual(template, nil, "switch button template")
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
                mapChallengeModeID = harness.completionChallengeMapID,
                level = harness.challengeLevel,
            }
        end,
        GetActiveChallengeMapID = function()
            return harness.activeChallengeMapID
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
                [1] = { id = 1, name = "Restoration", icon = 136052 },
                [2] = { id = 2, name = "Elemental", icon = 136048 },
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
                    gameMapID = 900,
                    journalInstanceID = 100,
                },
            },
            dungeonByInstance = {
                [100] = {
                    {
                        id = 300,
                        name = "Test Dungeon",
                        gameMapID = 900,
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

    function NS.Catalog:IsDungeonThresholdAvailable(dungeon, rank)
        return type(dungeon) == "table"
            and type(rank) == "number"
            and rank % 1 == 0
            and rank >= 1
            and rank <= 12
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

    NS.LootTracker = {}
    function NS.LootTracker:RecordBonusRollItem(snapshot, itemLink, specID)
        harness.recordedItems[#harness.recordedItems + 1] = {
            snapshot = copyValue(snapshot),
            itemLink = itemLink,
            specID = specID,
        }
        return 12345
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
        elseif first == "challengeRun" then
            return harness.challengeRun
        end
        return nil
    end
    function NS.DB:GetCopy(first)
        return copyValue(self:Get(first))
    end
    function NS.DB:Set(first, value)
        if first == "enabled" then
            harness.databaseEnabled = value
        elseif first == "challengeRun" then
            harness.challengeRun = copyValue(value)
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
    local harness = buildHarness({
        completionChallengeMapID = 0,
        difficultyID = 8,
        dungeonRule = {
            specializationID = 1,
            minimumDifficulty = 12,
        },
    })
    clickRoll(harness)
    local staleCallback = harness.popup.callback
    harness.events.SPELL_CONFIRMATION_TIMEOUT(
        "SPELL_CONFIRMATION_TIMEOUT",
        harness.frame.spellID,
        Enum.ConfirmationPromptUIType.BonusRoll
    )
    staleCallback()

    assertEqual(harness.nativeRolls, 0, "timeout invalidates token")
    assertEqual(harness.challengeRun, nil, "timeout clears persisted run")
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

test("started roll suppresses expiration and records its result", function()
    local harness = buildHarness()

    clickRoll(harness)
    acceptPopup(harness)
    harness.events.SPELL_CONFIRMATION_TIMEOUT(
        "SPELL_CONFIRMATION_TIMEOUT",
        harness.frame.spellID,
        Enum.ConfirmationPromptUIType.BonusRoll
    )

    assertEqual(harness.nativeRolls, 1, "native Roll remains one shot")
    assertEqual(#harness.messages, 0, "submitted roll does not report expiration")

    harness.events.BONUS_ROLL_STARTED("BONUS_ROLL_STARTED")

    harness.events.BONUS_ROLL_RESULT(
        "BONUS_ROLL_RESULT",
        "item",
        "|cff0070dd|Hitem:12345::::::::|h[Test Item]|h|r",
        1,
        2,
        2,
        true,
        nil,
        false,
        false
    )

    assertEqual(#harness.recordedItems, 1, "item result is recorded")
    assertEqual(
        harness.recordedItems[1].specID,
        2,
        "result uses the actual loot specialization"
    )
    assertEqual(
        harness.recordedItems[1].snapshot.encounterID,
        200,
        "result retains the validated encounter"
    )
    assertContains(
        harness.messages[1],
        "Bonus roll used on Normal Ula'tek with Elemental loot specialization",
        "result message identifies source and actual spec"
    )
    assertNotContains(
        harness.messages[1],
        "expired",
        "successful result is not described as expired"
    )

    harness.events.BONUS_ROLL_RESULT(
        "BONUS_ROLL_RESULT",
        "item",
        "|cff0070dd|Hitem:12346::::::::|h[Secondary Item]|h|r",
        1,
        2,
        2,
        true,
        nil,
        true,
        false
    )
    assertEqual(#harness.recordedItems, 2, "secondary item can be recorded")
    assertEqual(#harness.messages, 1, "secondary result adds no message")
end)

test("unassociated result cannot record an item", function()
    local harness = buildHarness()

    harness.events.BONUS_ROLL_STARTED("BONUS_ROLL_STARTED")
    harness.events.BONUS_ROLL_RESULT(
        "BONUS_ROLL_RESULT",
        "item",
        "|cff0070dd|Hitem:12345::::::::|h[Test Item]|h|r",
        1,
        1,
        2,
        true,
        nil,
        false,
        false
    )

    assertEqual(#harness.recordedItems, 0, "unassociated result is ignored")
    assertEqual(harness.nativeRolls, 0, "result event never invokes Roll")
    assertEqual(harness.nativePasses, 0, "result event never invokes Pass")
end)

test("failed roll cannot mark an item or become an expiration", function()
    local harness = buildHarness()

    clickRoll(harness)
    acceptPopup(harness)
    harness.events.BONUS_ROLL_STARTED("BONUS_ROLL_STARTED")
    harness.events.BONUS_ROLL_FAILED("BONUS_ROLL_FAILED")
    harness.events.BONUS_ROLL_RESULT(
        "BONUS_ROLL_RESULT",
        "item",
        "|cff0070dd|Hitem:12345::::::::|h[Test Item]|h|r",
        1,
        1,
        2,
        true,
        nil,
        false,
        false
    )
    harness.events.SPELL_CONFIRMATION_TIMEOUT(
        "SPELL_CONFIRMATION_TIMEOUT",
        harness.frame.spellID,
        Enum.ConfirmationPromptUIType.BonusRoll
    )

    assertEqual(#harness.recordedItems, 0, "failed roll records no item")
    assertEqual(#harness.messages, 0, "failed roll is not called expired")
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

test("wrong-spec sidecar changes only loot specialization", function()
    local harness = buildHarness({ currentSpecID = 2, raidRule = 1 })
    assertEqual(harness.switchPanel.shown, true, "loot-spec sidecar is visible")
    assertEqual(
        harness.switchButton.specIcon.texture,
        136052,
        "configured loot-spec icon"
    )

    harness.switchButton:GetScript("OnClick")(harness.switchButton)
    assertEqual(harness.lootSpecChanges, 1, "switch changes loot spec")
    assertEqual(harness.nativeRolls, 0, "switch never rolls")
    assertEqual(harness.nativePasses, 0, "switch never passes")
    assertEqual(harness.switchPanel.shown, false, "correct-spec sidecar is hidden")
end)

test("Current Spec rules use Blizzard's default loot-spec selection", function()
    local harness = buildHarness({
        activeSpecID = 1,
        currentSpecID = 2,
        raidRule = 0,
    })

    assertEqual(harness.switchPanel.shown, true, "current-spec sidecar is visible")
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

test("challenge start replaces and persists one atomic run", function()
    local harness = buildHarness({
        challengeRun = {
            mapID = 999,
            level = 4,
            recordedAt = 900,
            offer = {
                spellID = 499,
                endTime = 1050,
                instanceID = 999,
                encounterID = 0,
                difficultyID = 8,
            },
        },
    })

    harness.activeChallengeMapID = 300
    harness.challengeLevel = 10
    harness.events.CHALLENGE_MODE_START("CHALLENGE_MODE_START", 300)

    assertEqual(harness.challengeRun.mapID, 300, "start stores challenge map")
    assertEqual(harness.challengeRun.level, 10, "start stores key level")
    assertEqual(harness.challengeRun.gameMapID, 900, "start stores game map")
    assertEqual(
        harness.challengeRun.journalInstanceID,
        100,
        "start stores journal instance"
    )
    assertEqual(harness.challengeRun.offer, nil, "new start removes old offer")
    assertEqual(harness.nativeRolls, 0, "challenge start never rolls")

    harness.activeChallengeMapID = 301
    harness.events.CHALLENGE_MODE_START("CHALLENGE_MODE_START", 300)
    assertEqual(harness.challengeRun, nil, "conflicting start maps fail closed")
end)

test("Mythic+ offer survives reload using its persisted run", function()
    local first = buildHarness({
        completionChallengeMapID = 0,
        challengeLevel = 10,
        difficultyID = 8,
        dungeonRule = {
            specializationID = 1,
            minimumDifficulty = 12,
        },
    })

    assertEqual(first.frame.shown, true, "initial +10 offer is shown")
    assertEqual(first.challengeRun.mapID, 300, "run map persisted")
    assertEqual(first.challengeRun.level, 10, "run level persisted")
    assertEqual(
        first.challengeRun.offer.spellID,
        first.frame.spellID,
        "run is bound to the active offer"
    )

    local reloaded = buildHarness({
        activeChallengeMapID = 0,
        completionChallengeMapID = 0,
        challengeLevel = 10,
        difficultyID = 8,
        endTime = 1103,
        challengeRun = first.challengeRun,
        dungeonRule = {
            specializationID = 1,
            minimumDifficulty = 12,
        },
    })

    assertEqual(reloaded.frame.shown, true, "reloaded +10 offer remains shown")
    assertContains(
        reloaded.NS.RollController:GetStatusText(),
        "+10 Test Dungeon is shown",
        "persisted run restores map and level"
    )
    assertEqual(
        reloaded.challengeRun.offer.endTime,
        reloaded.frame.endTime,
        "reload refreshes the reconstructed expiration"
    )
    assertEqual(reloaded.nativeRolls, 0, "reload never rolls automatically")

    clickRoll(reloaded)
    assertEqual(reloaded.nativeRolls, 0, "reload still requires confirmation")
    acceptPopup(reloaded)
    assertEqual(reloaded.nativeRolls, 1, "confirmed reload can invoke native Roll")

    reloaded.events.BONUS_ROLL_STARTED("BONUS_ROLL_STARTED")
    assertEqual(reloaded.challengeRun, nil, "used offer clears persisted run")
end)

test("Mythic+ resolver never combines partial challenge data", function()
    local harness = buildHarness({
        activeChallengeMapID = 0,
        completionChallengeMapID = 0,
        challengeLevel = 10,
        difficultyID = 8,
        dungeonRule = {
            specializationID = 1,
            minimumDifficulty = 12,
        },
    })

    assertEqual(harness.frame.shown, false, "unverified key level hides offer")
    assertContains(
        harness.messages[#harness.messages],
        "completed key level could not be verified",
        "partial data fails closed"
    )
    assertEqual(harness.nativeRolls, 0, "partial data never rolls")
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
