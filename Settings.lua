local _, NS = ...

local ModernSettings = LibStub("LibModernSettings-1.0")
local SettingsUI = {
    ruleControls = {},
}

NS.SettingsUI = SettingsUI

local DISABLED_RULE_TOOLTIP = "Enable this bonus-roll rule first."
local DISABLED_SPEC_VALUE = -1
local DISABLED_SPEC_CHOICE = {
    value = DISABLED_SPEC_VALUE,
    label = "Bonus roll disabled",
}
local RAID_GROUP_HEADER_HEIGHT = 26
local RAID_GROUP_GAP = 8
local RAID_DIFFICULTY_ICON_SIZE = 20
local RAID_DIFFICULTY_ICON_ATLAS = {
    [NS.Catalog.Difficulty.MYTHIC] = "GM-icon-difficulty-mythic",
    [NS.Catalog.Difficulty.HEROIC] = "GM-icon-difficulty-heroic",
    [NS.Catalog.Difficulty.NORMAL] = "GM-icon-difficulty-normal-hover",
    [NS.Catalog.Difficulty.RAID_FINDER] = "RaidFrame-Icon-LFR",
    [NS.Catalog.Difficulty.STORY] = "questlog-storylineicon",
    [NS.Catalog.Difficulty.WORLD] = "RaidFrame-Icon-LFR",
}
local DELVE_TIER_CHOICES = {}
for tier = NS.RuleLimits.delveMinimumTier.minimum,
    NS.RuleLimits.delveMinimumTier.maximum
do
    DELVE_TIER_CHOICES[#DELVE_TIER_CHOICES + 1] = {
        value = tier,
        label = "Tier " .. tier,
    }
end

local function measurementFrame()
    if SettingsPanel and SettingsPanel.GetSettingsCanvas then
        return SettingsPanel:GetSettingsCanvas()
    end
    return nil
end

local function isValidSpecSelection(specID)
    return specID == 0 or NS.Catalog.specByID[specID] ~= nil
end

local function setTextEnabled(fontString, enabled)
    local color = enabled and HIGHLIGHT_FONT_COLOR or GRAY_FONT_COLOR
    fontString:SetTextColor(color.r, color.g, color.b)
end

local function getSpecChoicesForRow(tracked)
    local choices = NS.Catalog:GetSpecChoices()
    if not tracked.isEnabled() then
        return { DISABLED_SPEC_CHOICE }
    end

    return choices
end

local function refreshTrackedRow(tracked)
    local enabled = tracked.isEnabled()

    tracked.enableControl:SetValue(enabled)
    for index = 1, #tracked.texts do
        setTextEnabled(tracked.texts[index], enabled)
    end

    local specID = tracked.getSpec()
    tracked.specControl:SetValue(enabled and specID or DISABLED_SPEC_VALUE)
    tracked.specControl:SetControlEnabled(
        enabled,
        DISABLED_RULE_TOOLTIP
    )

    if tracked.thresholdControl then
        tracked.thresholdControl:SetValue(
            enabled and tracked.getThreshold() or tracked.defaultThreshold
        )
        tracked.thresholdControl:SetControlEnabled(
            enabled,
            DISABLED_RULE_TOOLTIP
        )
    end
end

local function trackRuleRow(tracked)
    SettingsUI.ruleControls[#SettingsUI.ruleControls + 1] = tracked
    refreshTrackedRow(tracked)
end

local function addRuleControls(row, tableView, tracked, thresholdChoices)
    tracked.enableControl = row:AddControl("enable", "checkbox", {
        tooltipTitle = "Enable bonus roll",
        tooltip = "Enable this row and choose its required loot specialization.",
        value = tracked.isEnabled(),
        onChanged = function(value)
            tracked.setEnabled(value)
            refreshTrackedRow(tracked)
        end,
    })

    if thresholdChoices then
        tracked.thresholdControl = row:AddControl("minimum", "dropdown", {
            showLabel = false,
            width = tableView:GetColumnWidth("minimum"),
            leftInset = 0,
            rightInset = 0,
            choices = thresholdChoices,
            value = tracked.defaultThreshold,
            onChanged = function(value)
                if tracked.isEnabled() then
                    tracked.setThreshold(value)
                end
                refreshTrackedRow(tracked)
            end,
        })
    end

    tracked.specControl = row:AddControl("spec", "dropdown", {
        showLabel = false,
        width = tableView:GetColumnWidth("spec"),
        leftInset = 0,
        rightInset = 0,
        getChoices = function()
            return getSpecChoicesForRow(tracked)
        end,
        value = DISABLED_SPEC_VALUE,
        onChanged = function(value)
            if tracked.isEnabled() and isValidSpecSelection(value) then
                tracked.setSpec(value)
            end
            refreshTrackedRow(tracked)
        end,
    })

    trackRuleRow(tracked)
end

local function buildGeneralPage(page)
    if page.built then
        SettingsUI:RefreshGeneralControls()
        return
    end
    page.built = true

    local layout = ModernSettings:CreateCanvasLayout(page, {
        measurementFrame = measurementFrame(),
        scrollable = true,
    })
    local root = layout:GetRootFlow()

    layout:AddHeader(
        "BetterBonusRolls",
        "Bonus-roll filtering is disabled by default. When enabled, only configured offers are shown automatically, and every roll requires a second confirmation."
    )

    local enabledControl
    enabledControl = root:AddControl("checkbox", {
        label = "Enable BetterBonusRolls",
        value = NS.DB:Get("enabled"),
        tooltip = "Enable filtering, safe hiding, loot-specialization guidance, and roll confirmation for this character.",
        onChanged = function(value)
            if not NS:SetEnabled(value) then
                enabledControl:SetValue(false)
            end
        end,
    })
    SettingsUI.enabledControl = enabledControl

    root:AddSection("Safety behavior")
    root:AddText({
        text = "Clicking Blizzard's No button hides the active offer without declining it. Use /bbr show while the server offer is still active. Clicking Blizzard's Roll button always opens a confirmation; no slash command can roll or decline.",
        fontObject = GameFontHighlight,
    })

    layout:Finalize()
end

local function buildDungeonPage(page)
    if page.built then
        SettingsUI:RefreshRuleControls()
        return
    end
    page.built = true

    local layout = ModernSettings:CreateCanvasLayout(page, {
        measurementFrame = measurementFrame(),
        scrollable = true,
    })
    local root = layout:GetRootFlow()

    layout:AddHeader(
        "Current Season Dungeons",
        "Enable each dungeon independently, then choose its minimum difficulty and required loot specialization. Minimums run from Normal through +10; keys above +10 use the same Myth 1/6 bonus-roll reward."
    )

    if #NS.Catalog.dungeons == 0 then
        root:AddText({
            text = "No current-season dungeons were returned by the client.",
            fontObject = GameFontHighlight,
        })
        layout:Finalize()
        return
    end

    local tableView = ModernSettings:CreateSettingsTable(
        layout:GetContent(),
        {
            width = root:GetWidth(),
            columns = {
                { key = "enable", width = 46 },
                { key = "dungeon", weight = 1, justifyH = "LEFT" },
                { key = "minimum", width = 130 },
                { key = "gap", width = 8 },
                { key = "spec", width = 230 },
            },
        }
    )
    tableView:AddHeaderText("enable", "Enable")
    tableView:AddHeaderText("dungeon", "Dungeon", { justifyH = "LEFT" })
    tableView:AddHeaderText("minimum", "Minimum")
    tableView:AddHeaderText("spec", "Loot specialization")

    for index = 1, #NS.Catalog.dungeons do
        local dungeon = NS.Catalog.dungeons[index]
        local row = tableView:AddRow()
        local dungeonText = row:AddText(
            "dungeon",
            dungeon.name,
            { justifyH = "LEFT" }
        )
        local tracked = {
            texts = { dungeonText },
            defaultThreshold = NS.RuleDefaults.dungeonMinimumDifficulty,
            isEnabled = function()
                return isValidSpecSelection(NS.DB:Get(
                    "dungeonRules",
                    dungeon.id,
                    "specializationID"
                ))
            end,
            getSpec = function()
                return NS.DB:Get(
                    "dungeonRules",
                    dungeon.id,
                    "specializationID"
                )
            end,
            getThreshold = function()
                return NS.DB:Get(
                    "dungeonRules",
                    dungeon.id,
                    "minimumDifficulty"
                )
            end,
            setEnabled = function(value)
                if value then
                    NS.DB:Set("dungeonRules", dungeon.id, {
                        specializationID = 0,
                        minimumDifficulty = NS.RuleDefaults.dungeonMinimumDifficulty,
                    })
                else
                    NS.DB:ResetPath("dungeonRules", dungeon.id)
                end
                NS:NotifyConfigurationChanged()
                return true
            end,
            setSpec = function(specID)
                NS.DB:Set(
                    "dungeonRules",
                    dungeon.id,
                    "specializationID",
                    specID
                )
                NS:NotifyConfigurationChanged()
            end,
            setThreshold = function(value)
                local limits = NS.RuleLimits.dungeonMinimumDifficulty
                if type(value) ~= "number"
                    or value % 1 ~= 0
                    or value < limits.minimum
                    or value > limits.maximum
                then
                    return
                end
                NS.DB:Set(
                    "dungeonRules",
                    dungeon.id,
                    "minimumDifficulty",
                    value
                )
                NS:NotifyConfigurationChanged()
            end,
        }

        addRuleControls(
            row,
            tableView,
            tracked,
            NS.Catalog:GetDungeonThresholdChoices()
        )
    end

    root:AddFrame(tableView:GetFrame(), { marginBottom = 8 })
    layout:Finalize()
end

local function buildOutdoorContentPage(page)
    if page.built then
        SettingsUI:RefreshRuleControls()
        return
    end
    page.built = true

    local layout = ModernSettings:CreateCanvasLayout(page, {
        measurementFrame = measurementFrame(),
        scrollable = true,
    })
    local root = layout:GetRootFlow()

    layout:AddHeader(
        "Outdoor Content",
        "Enable each outdoor bonus-roll offer you want to see, then choose its required loot specialization. Bountiful Delves also use a minimum tier."
    )

    local tableView = ModernSettings:CreateSettingsTable(
        layout:GetContent(),
        {
            width = root:GetWidth(),
            columns = {
                { key = "enable", width = 46 },
                { key = "content", weight = 1, justifyH = "LEFT" },
                { key = "minimum", width = 130 },
                { key = "gap", width = 8 },
                { key = "spec", width = 230 },
            },
        }
    )
    tableView:AddHeaderText("enable", "Enable")
    tableView:AddHeaderText("content", "Content", { justifyH = "LEFT" })
    tableView:AddHeaderText("minimum", "Minimum")
    tableView:AddHeaderText("spec", "Loot specialization")

    do
        local row = tableView:AddRow()
        local contentText = row:AddText(
            "content",
            "Bountiful Delves",
            { justifyH = "LEFT" }
        )
        local tracked = {
            texts = { contentText },
            defaultThreshold = NS.RuleDefaults.delveMinimumTier,
            isEnabled = function()
                return isValidSpecSelection(NS.DB:Get(
                    "contentRules",
                    "delves",
                    "specializationID"
                ))
            end,
            getSpec = function()
                return NS.DB:Get(
                    "contentRules",
                    "delves",
                    "specializationID"
                )
            end,
            getThreshold = function()
                return NS.DB:Get(
                    "contentRules",
                    "delves",
                    "minimumTier"
                )
            end,
            setEnabled = function(value)
                if value then
                    NS.DB:Set("contentRules", "delves", {
                        specializationID = 0,
                        minimumTier = NS.RuleDefaults.delveMinimumTier,
                    })
                else
                    NS.DB:ResetPath("contentRules", "delves")
                end
                NS:NotifyConfigurationChanged()
                return true
            end,
            setSpec = function(specID)
                NS.DB:Set(
                    "contentRules",
                    "delves",
                    "specializationID",
                    specID
                )
                NS:NotifyConfigurationChanged()
            end,
            setThreshold = function(value)
                local limits = NS.RuleLimits.delveMinimumTier
                if type(value) ~= "number"
                    or value % 1 ~= 0
                    or value < limits.minimum
                    or value > limits.maximum
                then
                    return
                end
                NS.DB:Set(
                    "contentRules",
                    "delves",
                    "minimumTier",
                    value
                )
                NS:NotifyConfigurationChanged()
            end,
        }
        addRuleControls(row, tableView, tracked, DELVE_TIER_CHOICES)
    end

    for index = 1, #NS.Catalog.worldBosses do
        local boss = NS.Catalog.worldBosses[index]
        local bossID = boss.id
        local bossName = boss.name
        local row = tableView:AddRow()
        local contentText = row:AddText(
            "content",
            bossName,
            { justifyH = "LEFT" }
        )
        local minimumText = row:AddText("minimum", "Any eligible")
        local tracked = {
            texts = { contentText, minimumText },
            isEnabled = function()
                return isValidSpecSelection(NS.DB:Get(
                    "contentRules",
                    "worldBosses",
                    bossID,
                    "specializationID"
                ))
            end,
            getSpec = function()
                return NS.DB:Get(
                    "contentRules",
                    "worldBosses",
                    bossID,
                    "specializationID"
                )
            end,
            setEnabled = function(value)
                if value then
                    NS.DB:Set(
                        "contentRules",
                        "worldBosses",
                        bossID,
                        { specializationID = 0 }
                    )
                else
                    NS.DB:ResetPath(
                        "contentRules",
                        "worldBosses",
                        bossID
                    )
                end
                NS:NotifyConfigurationChanged()
                return true
            end,
            setSpec = function(specID)
                NS.DB:Set(
                    "contentRules",
                    "worldBosses",
                    bossID,
                    "specializationID",
                    specID
                )
                NS:NotifyConfigurationChanged()
            end,
        }
        addRuleControls(row, tableView, tracked)
    end

    do
        local row = tableView:AddRow()
        local contentText = row:AddText(
            "content",
            "Nightmare Prey",
            { justifyH = "LEFT" }
        )
        local minimumText = row:AddText("minimum", "Any eligible")
        local tracked = {
            texts = { contentText, minimumText },
            isEnabled = function()
                return isValidSpecSelection(NS.DB:Get(
                    "contentRules",
                    "world",
                    "specializationID"
                ))
            end,
            getSpec = function()
                return NS.DB:Get(
                    "contentRules",
                    "world",
                    "specializationID"
                )
            end,
            setEnabled = function(value)
                if value then
                    NS.DB:Set("contentRules", "world", {
                        specializationID = 0,
                    })
                else
                    NS.DB:ResetPath("contentRules", "world")
                end
                NS:NotifyConfigurationChanged()
                return true
            end,
            setSpec = function(specID)
                NS.DB:Set(
                    "contentRules",
                    "world",
                    "specializationID",
                    specID
                )
                NS:NotifyConfigurationChanged()
            end,
        }
        addRuleControls(row, tableView, tracked)
    end

    root:AddFrame(tableView:GetFrame(), { marginBottom = 8 })
    layout:Finalize()
end

local function createRaidDifficultyTable(parent, width, instance, difficulty)
    local tableView = ModernSettings:CreateSettingsTable(
        parent,
        {
            width = width,
            columns = {
                { key = "enable", width = 46 },
                { key = "boss", weight = 1, justifyH = "LEFT" },
                { key = "spec", width = 230 },
            },
        }
    )
    tableView:AddHeaderText("enable", "Enable")
    tableView:AddHeaderText("boss", "Boss", { justifyH = "LEFT" })
    tableView:AddHeaderText("spec", "Loot specialization")

    for encounterIndex = 1, #instance.encounters do
        local encounter = instance.encounters[encounterIndex]
        local row = tableView:AddRow()
        local bossText = row:AddText(
            "boss",
            encounter.name,
            { justifyH = "LEFT" }
        )
        local tracked = {
            texts = { bossText },
            isEnabled = function()
                return isValidSpecSelection(NS.DB:Get(
                    "raidRules",
                    instance.id,
                    encounter.id,
                    difficulty.id
                ))
            end,
            getSpec = function()
                return NS.DB:Get(
                    "raidRules",
                    instance.id,
                    encounter.id,
                    difficulty.id
                )
            end,
            setEnabled = function(value)
                if value then
                    NS.DB:Set(
                        "raidRules",
                        instance.id,
                        encounter.id,
                        difficulty.id,
                        0
                    )
                else
                    NS.DB:ResetPath(
                        "raidRules",
                        instance.id,
                        encounter.id,
                        difficulty.id
                    )
                end
                NS:NotifyConfigurationChanged()
                return true
            end,
            setSpec = function(specID)
                NS.DB:Set(
                    "raidRules",
                    instance.id,
                    encounter.id,
                    difficulty.id,
                    specID
                )
                NS:NotifyConfigurationChanged()
            end,
        }

        addRuleControls(row, tableView, tracked)
    end

    return tableView
end

local function addRaidDifficultyIcon(header, difficultyID)
    local icon = header:CreateTexture(nil, "ARTWORK")

    icon:SetSize(RAID_DIFFICULTY_ICON_SIZE, RAID_DIFFICULTY_ICON_SIZE)
    icon:SetPoint("LEFT", header, "LEFT", 8, 0)
    icon:SetAtlas(RAID_DIFFICULTY_ICON_ATLAS[difficultyID], false)
    icon:SetDesaturated(difficultyID == NS.Catalog.Difficulty.STORY)

    local title = header:GetTitleRegion()
    title:ClearAllPoints()
    title:SetPoint("LEFT", icon, "RIGHT", 4, 1)
    title:SetPoint("RIGHT", header:GetCollapseButton(), "LEFT", -4, 1)

    header.difficultyIcon = icon
end

local function layoutRaidDifficultyGroups(groupsFrame, groups)
    local cursor = 0

    for index = 1, #groups do
        local group = groups[index]
        local header = group.header

        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", groupsFrame, "TOPLEFT", 0, -cursor)
        header:Show()
        cursor = cursor + RAID_GROUP_HEADER_HEIGHT

        local tableFrame = group.tableView:GetFrame()
        if group.collapsed then
            tableFrame:Hide()
        else
            tableFrame:ClearAllPoints()
            tableFrame:SetPoint(
                "TOPLEFT",
                groupsFrame,
                "TOPLEFT",
                0,
                -cursor
            )
            tableFrame:Show()
            cursor = cursor + tableFrame:GetHeight()
        end

        if index < #groups then
            cursor = cursor + RAID_GROUP_GAP
        end
    end

    groupsFrame:SetHeight(math.max(cursor, 1))
end

local function buildRaidPage(page, instance)
    if page.built then
        SettingsUI:RefreshRuleControls()
        return
    end
    page.built = true

    local layout = ModernSettings:CreateCanvasLayout(page, {
        measurementFrame = measurementFrame(),
        scrollable = true,
    })
    local root = layout:GetRootFlow()
    local difficulties = NS.Catalog:GetRaidDifficultiesHardestFirst(instance)

    layout:AddHeader(
        instance.name,
        "Choose which bosses you want to bonus roll. Open a difficulty, enable a boss, and select the loot specialization you want to use."
    )

    local groupsFrame = CreateFrame("Frame", nil, layout:GetContent())
    groupsFrame:SetSize(root:GetWidth(), 1)

    local groups = {}

    for difficultyIndex = 1, #difficulties do
        local difficulty = difficulties[difficultyIndex]
        local group = {
            collapsed = difficultyIndex ~= 1,
        }
        local header = CreateFrame(
            "Button",
            nil,
            groupsFrame,
            "ListHeaderVisualTemplate,ListHeaderCodeTemplate"
        )

        header:SetSize(root:GetWidth(), RAID_GROUP_HEADER_HEIGHT)
        header:RegisterForClicks("LeftButtonUp")
        header:SetTitleColor(false, NORMAL_FONT_COLOR)
        header:SetTitleColor(true, HIGHLIGHT_FONT_COLOR)
        addRaidDifficultyIcon(header, difficulty.id)
        header:SetHeaderText(difficulty.label)
        header:UpdateCollapsedState(group.collapsed)
        group.header = header

        group.tableView = createRaidDifficultyTable(
            groupsFrame,
            root:GetWidth(),
            instance,
            difficulty
        )

        groups[#groups + 1] = group
    end

    layoutRaidDifficultyGroups(groupsFrame, groups)

    local groupsTop = root:GetCursor()
    local collapsedGroupsHeight = (#groups * RAID_GROUP_HEADER_HEIGHT)
        + (math.max(#groups - 1, 0) * RAID_GROUP_GAP)

    root:AddFrame(groupsFrame, {
        height = math.max(collapsedGroupsHeight, 1),
        marginBottom = RAID_GROUP_GAP,
    })

    local function refreshGroupLayout()
        layoutRaidDifficultyGroups(groupsFrame, groups)
        layout:Finalize({
            contentHeight = groupsTop
                + groupsFrame:GetHeight()
                + RAID_GROUP_GAP
                + layout:GetStyleValue("paddingBottom"),
        })
    end

    for index = 1, #groups do
        local group = groups[index]

        group.header:SetClickHandler(function(_header, button)
            if button ~= "LeftButton" then
                return
            end

            group.collapsed = not group.collapsed
            group.header:UpdateCollapsedState(group.collapsed)
            refreshGroupLayout()
        end)
    end

    refreshGroupLayout()
end

function SettingsUI:RefreshGeneralControls()
    if self.enabledControl then
        self.enabledControl:SetValue(NS.DB:Get("enabled"))
    end
end

function SettingsUI:RefreshRuleControls()
    for index = 1, #self.ruleControls do
        refreshTrackedRow(self.ruleControls[index])
    end
end

function SettingsUI:Register()
    if self.category then
        return
    end

    local generalPage = CreateFrame("Frame")
    generalPage.OnRefresh = function()
        SettingsUI:RefreshGeneralControls()
    end

    local category = Settings.RegisterCanvasLayoutCategory(
        generalPage,
        NS.displayName
    )
    buildGeneralPage(generalPage)

    local dungeonPage = CreateFrame("Frame")
    dungeonPage.OnRefresh = function()
        SettingsUI:RefreshRuleControls()
    end
    Settings.RegisterCanvasLayoutSubcategory(
        category,
        dungeonPage,
        "Current Season Dungeons"
    )
    buildDungeonPage(dungeonPage)

    local outdoorContentPage = CreateFrame("Frame")
    outdoorContentPage.OnRefresh = function()
        SettingsUI:RefreshRuleControls()
    end
    Settings.RegisterCanvasLayoutSubcategory(
        category,
        outdoorContentPage,
        "Outdoor Content"
    )
    buildOutdoorContentPage(outdoorContentPage)

    for index = 1, #NS.Catalog.raids do
        local instance = NS.Catalog.raids[index]
        local raidPage = CreateFrame("Frame")
        raidPage.OnRefresh = function()
            SettingsUI:RefreshRuleControls()
        end
        Settings.RegisterCanvasLayoutSubcategory(
            category,
            raidPage,
            instance.name
        )
        buildRaidPage(raidPage, instance)
    end

    Settings.RegisterAddOnCategory(category)
    self.category = category
end

local function handleLootSpecChanged(event, unit)
    if event == "PLAYER_SPECIALIZATION_CHANGED" and unit ~= "player" then
        return
    end
    SettingsUI:RefreshRuleControls()
end

NS:RegisterInitializer(function()
    NS:RegisterEvent("PLAYER_LOGIN", function()
        SettingsUI:Register()
    end)
    NS:RegisterEvent("PLAYER_LOOT_SPEC_UPDATED", handleLootSpecChanged)
    NS:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", handleLootSpecChanged)
end)
