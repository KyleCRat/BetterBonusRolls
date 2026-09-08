local _, NS = ...

local ModernSettings = LibStub("LibModernSettings-1.0")
local LootTrackerSettings = {
    itemRows = {},
    activeQueryKeys = {},
    activeTrackingKeys = {},
}

NS.LootTrackerSettings = LootTrackerSettings

local LIST_HEADER_HEIGHT = 30
local ITEM_ROW_HEIGHT = 38
local ITEM_CHECKBOX_SIZE = 34
local ITEM_ICON_SIZE = 30
local ITEM_TEXT_GAP = 8
local LIST_INSET = 8
local OBTAINED_COLUMN_WIDTH = 74
local CONTEXT_COLUMN_GAP = 12
local CONTEXT_COLUMNS = {
    { key = "difficulty", label = "Difficulty", width = 65 },
    { key = "boss", label = "Boss", width = 140 },
    { key = "spec", label = "Loot Spec", width = 110 },
}
local ITEM_COLUMN_RIGHT_INSET = LIST_INSET

for _, column in ipairs(CONTEXT_COLUMNS) do
    ITEM_COLUMN_RIGHT_INSET = ITEM_COLUMN_RIGHT_INSET
        + column.width + CONTEXT_COLUMN_GAP
end

local LIST_BOTTOM_MARGIN = 8
local ITEM_ROW_STRIPE_ALPHA = 0.035
local UNKNOWN_ITEM_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local function getItemName(item)
    if not NS:IsSecret(item.name)
        and type(item.name) == "string"
        and item.name ~= ""
    then
        return item.name
    end

    return "Item " .. item.itemID
end

local function getItemLink(item, itemName)
    if not NS:IsSecret(item.link)
        and type(item.link) == "string"
        and item.link ~= ""
    then
        return item.link
    end

    return itemName
end

local function resetItemRow(itemRow)
    NS.ObtainedCheckbox:Reset(itemRow.checkbox)
    ModernSettings:HideOwnedTooltip(itemRow.itemButton)
    itemRow.itemButton.itemLink = nil
    itemRow.itemButton.icon:SetTexture(nil)
    itemRow.itemButton.icon:SetDesaturated(false)
    itemRow.itemButton.linkText:SetText("")
    itemRow.itemButton.linkText:SetAlpha(1)

    for _, text in pairs(itemRow.contextText) do
        text:SetText("")
    end

    itemRow:Hide()
end

local function createContextColumns(parent, fontObject)
    local columns = {}
    local rightInset = LIST_INSET

    -- Use the same right-aligned column boundaries for headings and item rows.
    for index = #CONTEXT_COLUMNS, 1, -1 do
        local column = CONTEXT_COLUMNS[index]
        local text = parent:CreateFontString(nil, "OVERLAY", fontObject)

        text:SetPoint(
            "TOPLEFT",
            parent,
            "TOPRIGHT",
            -(rightInset + column.width),
            0
        )
        text:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -rightInset, 0)
        text:SetJustifyH("LEFT")
        text:SetJustifyV("MIDDLE")
        text:SetWordWrap(false)
        text:SetMaxLines(1)
        columns[column.key] = text
        rightInset = rightInset + column.width + CONTEXT_COLUMN_GAP
    end

    return columns
end

local function createItemRow(tracker, index)
    local itemRow = CreateFrame("Frame", nil, tracker.listFrame)

    itemRow:SetHeight(ITEM_ROW_HEIGHT)
    itemRow:SetPoint(
        "TOPLEFT",
        tracker.listFrame,
        "TOPLEFT",
        0,
        -(LIST_HEADER_HEIGHT + ((index - 1) * ITEM_ROW_HEIGHT))
    )
    itemRow:SetPoint(
        "TOPRIGHT",
        tracker.listFrame,
        "TOPRIGHT",
        0,
        -(LIST_HEADER_HEIGHT + ((index - 1) * ITEM_ROW_HEIGHT))
    )

    if index % 2 == 0 then
        local stripe = itemRow:CreateTexture(nil, "BACKGROUND")

        stripe:SetAllPoints(itemRow)
        stripe:SetColorTexture(1, 1, 1, ITEM_ROW_STRIPE_ALPHA)
    end

    local checkbox = NS.ObtainedCheckbox:Create(itemRow)

    checkbox:SetPoint(
        "LEFT",
        itemRow,
        "LEFT",
        LIST_INSET
            + ((OBTAINED_COLUMN_WIDTH - ITEM_CHECKBOX_SIZE) / 2),
        0
    )
    itemRow.checkbox = checkbox

    local itemButton = CreateFrame("Button", nil, itemRow)

    itemButton:SetPoint(
        "TOPLEFT",
        itemRow,
        "TOPLEFT",
        LIST_INSET + OBTAINED_COLUMN_WIDTH,
        0
    )
    itemButton:SetPoint(
        "BOTTOMRIGHT",
        itemRow,
        "BOTTOMRIGHT",
        -ITEM_COLUMN_RIGHT_INSET,
        0
    )

    local icon = itemButton:CreateTexture(nil, "ARTWORK")

    icon:SetSize(ITEM_ICON_SIZE, ITEM_ICON_SIZE)
    icon:SetPoint("LEFT", itemButton, "LEFT", 0, 0)
    itemButton.icon = icon

    local linkText = itemButton:CreateFontString(
        nil,
        "OVERLAY",
        "GameFontHighlight"
    )

    linkText:SetPoint("LEFT", icon, "RIGHT", ITEM_TEXT_GAP, 0)
    linkText:SetPoint("RIGHT", itemButton, "RIGHT", -4, 0)
    linkText:SetJustifyH("LEFT")
    linkText:SetJustifyV("MIDDLE")
    linkText:SetWordWrap(false)
    linkText:SetMaxLines(1)
    itemButton.linkText = linkText

    itemButton:SetScript("OnEnter", function(self)
        local link = self.itemLink
        if NS:IsSecret(link) or type(link) ~= "string" or link == "" then
            return
        end

        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(link)
        GameTooltip:Show()
    end)
    itemButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    itemButton:SetScript("OnClick", function(self)
        local link = self.itemLink
        if NS:IsSecret(link) or type(link) ~= "string" or link == "" then
            return
        end

        if HandleModifiedItemClick then
            HandleModifiedItemClick(link)
        end
    end)
    itemRow.itemButton = itemButton

    itemRow.contextText = createContextColumns(
        itemRow,
        "GameFontHighlight"
    )

    return itemRow
end

local function acquireItemRow(tracker, index)
    local itemRow = tracker.itemRows[index]

    if not itemRow then
        itemRow = createItemRow(tracker, index)
        tracker.itemRows[index] = itemRow
    end

    return itemRow
end

local function hideUnusedItemRows(tracker, firstUnusedIndex)
    for index = firstUnusedIndex, #tracker.itemRows do
        resetItemRow(tracker.itemRows[index])
    end
end

local function createListHeader(tracker)
    local header = CreateFrame("Frame", nil, tracker.listFrame)

    header:SetHeight(LIST_HEADER_HEIGHT)
    header:SetPoint("TOPLEFT", tracker.listFrame, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", tracker.listFrame, "TOPRIGHT", 0, 0)

    local obtainedText = header:CreateFontString(
        nil,
        "OVERLAY",
        "GameFontNormalSmall"
    )

    obtainedText:SetPoint("TOPLEFT", header, "TOPLEFT", LIST_INSET, 0)
    obtainedText:SetSize(OBTAINED_COLUMN_WIDTH, LIST_HEADER_HEIGHT)
    obtainedText:SetJustifyH("CENTER")
    obtainedText:SetJustifyV("MIDDLE")
    obtainedText:SetText("Obtained")

    local itemText = header:CreateFontString(
        nil,
        "OVERLAY",
        "GameFontNormalSmall"
    )

    itemText:SetPoint(
        "TOPLEFT",
        header,
        "TOPLEFT",
        LIST_INSET
            + OBTAINED_COLUMN_WIDTH
            + ITEM_ICON_SIZE
            + ITEM_TEXT_GAP,
        0
    )
    itemText:SetPoint(
        "BOTTOMRIGHT",
        header,
        "BOTTOMRIGHT",
        -ITEM_COLUMN_RIGHT_INSET,
        0
    )
    itemText:SetJustifyH("LEFT")
    itemText:SetJustifyV("MIDDLE")
    itemText:SetText("Item")

    local contextText = createContextColumns(
        header,
        "GameFontNormalSmall"
    )

    for _, column in ipairs(CONTEXT_COLUMNS) do
        contextText[column.key]:SetText(column.label)
    end
end

local function getStatusText(requestCount, loadingCount, unavailableCount)
    if requestCount == 0 then
        return "No enabled bosses or dungeons have loot to track."
    end

    local messages = {}

    if loadingCount > 0 then
        messages[#messages + 1] = loadingCount == 1
            and "1 enabled loot list is still loading."
            or loadingCount .. " enabled loot lists are still loading."
    end
    if unavailableCount > 0 then
        messages[#messages + 1] = unavailableCount == 1
            and "1 enabled loot list is unavailable; use its source page to retry."
            or unavailableCount
                .. " enabled loot lists are unavailable; use their source pages to retry."
    end
    return #messages > 0 and table.concat(messages, " ") or nil
end

local function renderItemRow(tracker, index, entry)
    local itemRow = acquireItemRow(tracker, index)
    local request = entry.request
    local item = entry.item
    local obtained = NS.ObtainedCheckbox:Update(itemRow.checkbox, request, item)
    local itemName = getItemName(item)
    local itemLink = getItemLink(item, itemName)
    local specName = NS.Catalog:GetSpecName(request.specID)
    ModernSettings:HideOwnedTooltip(itemRow.itemButton)
    itemRow.itemButton.itemLink = item.link
    itemRow.itemButton.icon:SetTexture(
        not NS:IsSecret(item.icon) and item.icon or UNKNOWN_ITEM_ICON
    )
    itemRow.itemButton.icon:SetDesaturated(obtained)
    itemRow.itemButton.linkText:SetText(itemLink)
    itemRow.itemButton.linkText:SetAlpha(obtained and 0.55 or 1)
    itemRow.contextText.difficulty:SetText(request.difficultyName)
    itemRow.contextText.boss:SetText(request.contentName)
    itemRow.contextText.spec:SetText(specName)

    local textColor = obtained and GRAY_FONT_COLOR or HIGHLIGHT_FONT_COLOR

    for _, text in pairs(itemRow.contextText) do
        text:SetTextColor(textColor.r, textColor.g, textColor.b)
    end

    itemRow:Show()

    return obtained
end

local function updateListHeight(tracker, itemCount, hasStatus)
    local contentRows = itemCount + (hasStatus and 1 or 0)

    tracker.listFrame:SetHeight(
        LIST_HEADER_HEIGHT
        + (math.max(contentRows, 1) * ITEM_ROW_HEIGHT)
    )
    tracker.layout:Finalize({
        contentHeight = tracker.listTop
            + tracker.listFrame:GetHeight()
            + LIST_BOTTOM_MARGIN
            + tracker.layout:GetStyleValue("paddingBottom"),
    })
end

function LootTrackerSettings:Refresh()
    if not self.page then
        return
    end

    local enabled = NS.LootTracker:CollectEnabledLootRequests()
    local entries = {}
    local loadingCount = 0
    local unavailableCount = 0

    self.activeQueryKeys = {}
    self.activeTrackingKeys = {}

    for index = 1, #enabled do
        local request = enabled[index].request
        local pool = NS.LootTracker:GetPool(request)

        self.activeQueryKeys[request.queryKey] = true
        self.activeTrackingKeys[request.trackingKey] = true

        if pool.status == "ready" then
            for itemIndex = 1, #pool.items do
                entries[#entries + 1] = {
                    request = request,
                    item = pool.items[itemIndex],
                }
            end
        elseif pool.status == "pending" or pool.status == "loading" then
            loadingCount = loadingCount + 1
        else
            unavailableCount = unavailableCount + 1
        end
    end

    local remaining = 0

    for index = 1, #entries do
        if not renderItemRow(self, index, entries[index]) then
            remaining = remaining + 1
        end
    end

    hideUnusedItemRows(self, #entries + 1)
    self.summaryText:SetText(
        remaining .. " remaining / " .. #entries .. " total"
    )

    local statusText = getStatusText(
        #enabled,
        loadingCount,
        unavailableCount
    )

    self.statusText:ClearAllPoints()
    self.statusText:SetPoint(
        "TOPLEFT",
        self.listFrame,
        "TOPLEFT",
        LIST_INSET,
        -(LIST_HEADER_HEIGHT + (#entries * ITEM_ROW_HEIGHT))
    )
    self.statusText:SetPoint(
        "TOPRIGHT",
        self.listFrame,
        "TOPRIGHT",
        -LIST_INSET,
        -(LIST_HEADER_HEIGHT + (#entries * ITEM_ROW_HEIGHT))
    )
    self.statusText:SetText(statusText or "")
    self.statusText:SetShown(statusText ~= nil)
    updateListHeight(self, #entries, statusText ~= nil)
end

function LootTrackerSettings:RefreshIfVisible()
    if self.page and self.page:IsShown() then
        self:Refresh()
    end
end

function LootTrackerSettings:Build(page, measurementFrame)
    assert(not self.page, "loot tracker settings page already exists")

    self.page = page
    self.layout = ModernSettings:CreateCanvasLayout(page, {
        measurementFrame = measurementFrame,
        scrollable = true,
    })

    local root = self.layout:GetRootFlow()

    self.titleText, self.summaryText = self.layout:AddHeader(
        "Enabled Bonus Roll Loot Tracker",
        "0 remaining / 0 total",
        { marginBottom = 10 }
    )

    root:AddText({
        text = "Track loot from the bosses and dungeons you've enabled, and mark items as you collect them. Use the other settings pages to change your enabled content or loot specializations.",
        fontObject = GameFontHighlight,
    }, {
        marginBottom = 18,
    })

    self.listFrame = CreateFrame("Frame", nil, self.layout:GetContent())
    self.listFrame:SetSize(
        root:GetWidth(),
        LIST_HEADER_HEIGHT + ITEM_ROW_HEIGHT
    )
    createListHeader(self)

    self.statusText = self.listFrame:CreateFontString(
        nil,
        "OVERLAY",
        "GameFontDisable"
    )
    self.statusText:SetHeight(ITEM_ROW_HEIGHT)
    self.statusText:SetJustifyH("LEFT")
    self.statusText:SetJustifyV("MIDDLE")
    self.statusText:SetWordWrap(true)
    self.statusText:SetMaxLines(2)
    self.statusText:SetText("Loading enabled loot...")

    self.listTop = root:GetCursor()
    root:AddFrame(self.listFrame, {
        height = self.listFrame:GetHeight(),
        marginBottom = LIST_BOTTOM_MARGIN,
    })
    self.layout:Finalize()

    page:SetScript("OnShow", function()
        LootTrackerSettings:Refresh()
    end)
end

NS.LootTracker:RegisterChangedCallback(function(changeType, key)
    if not LootTrackerSettings.page
        or not LootTrackerSettings.page:IsShown()
    then
        return
    end

    if (changeType == "pool"
            and LootTrackerSettings.activeQueryKeys[key])
        or (changeType == "obtained"
            and LootTrackerSettings.activeTrackingKeys[key])
    then
        LootTrackerSettings:Refresh()
    end
end)
