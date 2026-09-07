local _, NS = ...

local ModernSettings = LibStub("LibModernSettings-1.0")
local LootSettings = {
    trackedRows = {},
}

NS.LootSettings = LootSettings

local SETTINGS_ICON_ATLAS = "GM-icon-settings"
local DETAILS_INSET = 8
local DETAILS_HEADER_HEIGHT = 30
local DETAILS_BACKGROUND_COLOR = { r = 0.015, g = 0.018, b = 0.022, a = 0.82 }
local DETAILS_BORDER_COLOR = { r = 0.38, g = 0.41, b = 0.45, a = 0.7 }
local ITEM_ROW_HEIGHT = 38
local ITEM_CHECKBOX_SIZE = 34
local ITEM_CONTROL_GAP = 8
local ITEM_ICON_SIZE = 30
local ITEM_ICON_INSET = 0
local ITEM_TEXT_GAP = 8
local ITEM_LINK_LEFT_INSET = ITEM_CHECKBOX_SIZE + ITEM_CONTROL_GAP
local DETAILS_SUMMARY_LEFT_INSET = DETAILS_INSET
    + ITEM_LINK_LEFT_INSET
    + ITEM_ICON_INSET
    + ITEM_ICON_SIZE
    + ITEM_TEXT_GAP
local DETAILS_BOTTOM_PADDING = 8
local DETAILS_BOTTOM_MARGIN = 8
local ITEM_ROW_STRIPE_ALPHA = 0.06
local RETRY_BUTTON_WIDTH = 65
local STATUS_RETRY_GAP = 8
local UNKNOWN_ITEM_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local function hideTooltip()
    GameTooltip:Hide()
end

local function clearOwnedTooltip(button)
    if GameTooltip.GetOwner and GameTooltip:GetOwner() == button then
        GameTooltip:Hide()
    end
end

local function createItemRow(panel, index)
    local itemRow = CreateFrame("Frame", nil, panel)

    itemRow:SetFrameLevel(panel:GetFrameLevel() + 1)
    itemRow:SetHeight(ITEM_ROW_HEIGHT)
    itemRow:SetPoint(
        "TOPLEFT",
        panel,
        "TOPLEFT",
        DETAILS_INSET,
        -(DETAILS_HEADER_HEIGHT + ((index - 1) * ITEM_ROW_HEIGHT))
    )
    itemRow:SetPoint(
        "TOPRIGHT",
        panel,
        "TOPRIGHT",
        -DETAILS_INSET,
        -(DETAILS_HEADER_HEIGHT + ((index - 1) * ITEM_ROW_HEIGHT))
    )

    if index % 2 == 0 then
        local stripe = itemRow:CreateTexture(nil, "BACKGROUND")

        stripe:SetPoint(
            "TOPLEFT",
            itemRow,
            "TOPLEFT",
            -(DETAILS_INSET - 1),
            0
        )
        stripe:SetPoint(
            "BOTTOMRIGHT",
            itemRow,
            "BOTTOMRIGHT",
            DETAILS_INSET - 1,
            0
        )
        stripe:SetColorTexture(1, 1, 1, ITEM_ROW_STRIPE_ALPHA)
    end

    local checkbox = ModernSettings:CreateCheckbox(itemRow, {
        value = false,
        tooltipTitle = "Obtained",
        tooltip = "Mark this item as obtained for this source, difficulty, and loot specialization.",
        onChanged = function(value)
            if itemRow.request and itemRow.itemID then
                NS.LootTracker:SetObtained(
                    itemRow.request,
                    itemRow.itemID,
                    value
                )
            end
        end,
    })

    checkbox:SetPoint("LEFT", itemRow, "LEFT", 0, 0)
    itemRow.checkbox = checkbox

    local linkButton = CreateFrame("Button", nil, itemRow)

    linkButton:SetPoint(
        "TOPLEFT",
        itemRow,
        "TOPLEFT",
        ITEM_LINK_LEFT_INSET,
        0
    )
    linkButton:SetPoint("BOTTOMRIGHT", itemRow, "BOTTOMRIGHT", 0, 0)

    local icon = linkButton:CreateTexture(nil, "ARTWORK")

    icon:SetSize(ITEM_ICON_SIZE, ITEM_ICON_SIZE)
    icon:SetPoint("LEFT", linkButton, "LEFT", ITEM_ICON_INSET, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    linkButton.icon = icon

    local linkText = linkButton:CreateFontString(
        nil,
        "OVERLAY",
        "GameFontHighlight"
    )

    linkText:SetPoint("LEFT", icon, "RIGHT", ITEM_TEXT_GAP, 0)
    linkText:SetPoint("RIGHT", linkButton, "RIGHT", -4, 0)
    linkText:SetJustifyH("LEFT")
    linkText:SetJustifyV("MIDDLE")
    linkText:SetWordWrap(false)
    linkText:SetMaxLines(1)
    linkButton.linkText = linkText

    linkButton:SetScript("OnEnter", function(self)
        local link = self.itemLink
        if NS:IsSecret(link) or type(link) ~= "string" or link == "" then
            return
        end

        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(link)
        GameTooltip:Show()
    end)
    linkButton:SetScript("OnLeave", hideTooltip)
    linkButton:SetScript("OnClick", function(self)
        local link = self.itemLink
        if NS:IsSecret(link) or type(link) ~= "string" or link == "" then
            return
        end
        if HandleModifiedItemClick then
            HandleModifiedItemClick(link)
        end
    end)
    itemRow.linkButton = linkButton

    return itemRow
end

local function acquireItemRow(panel, index)
    local itemRow = panel.itemRows[index]
    if not itemRow then
        itemRow = createItemRow(panel, index)
        panel.itemRows[index] = itemRow
    end

    return itemRow
end

local function resetItemRow(itemRow)
    clearOwnedTooltip(itemRow.linkButton)
    itemRow.request = nil
    itemRow.itemID = nil
    itemRow.linkButton.itemLink = nil
    itemRow.linkButton.icon:SetTexture(nil)
    itemRow.linkButton.icon:SetDesaturated(false)
    itemRow.linkButton.linkText:SetText("")
    itemRow.linkButton.linkText:SetAlpha(1)
    itemRow.checkbox:SetValue(false)
    itemRow:Hide()
end

local function hideUnusedItemRows(panel, firstUnusedIndex)
    for index = firstUnusedIndex, #panel.itemRows do
        resetItemRow(panel.itemRows[index])
    end
end

local function setPanelHeight(tracked, contentRows)
    local detailsHeight = DETAILS_HEADER_HEIGHT
        + (math.max(contentRows, 1) * ITEM_ROW_HEIGHT)
        + DETAILS_BOTTOM_PADDING

    tracked.lootPanel:SetHeight(detailsHeight)
    tracked.row:SetHeight(
        tracked.lootBaseHeight
        + detailsHeight
        + DETAILS_BOTTOM_MARGIN
    )
end

local function renderStatus(tracked, message, retryable, preserveHeight)
    local panel = tracked.lootPanel
    local statusText = panel.statusText

    hideUnusedItemRows(panel, 1)
    statusText:ClearAllPoints()
    statusText:SetPoint(
        "TOPLEFT",
        panel,
        "TOPLEFT",
        DETAILS_INSET + 4,
        -DETAILS_HEADER_HEIGHT
    )
    statusText:SetPoint(
        "TOPRIGHT",
        panel,
        "TOPRIGHT",
        retryable
            and -(DETAILS_INSET + RETRY_BUTTON_WIDTH + STATUS_RETRY_GAP)
            or -DETAILS_INSET,
        -DETAILS_HEADER_HEIGHT
    )
    statusText:SetText(message)
    statusText:Show()
    if retryable then
        panel.retryButton:Show()
    else
        panel.retryButton:Hide()
    end
    setPanelHeight(
        tracked,
        preserveHeight and tracked.lootContentRows or 1
    )
end

local function renderItems(tracked, request, items)
    local panel = tracked.lootPanel
    local remaining = 0

    panel.statusText:Hide()
    panel.retryButton:Hide()

    for index = 1, #items do
        local item = items[index]
        local itemRow = acquireItemRow(panel, index)
        local obtained = NS.LootTracker:IsObtained(
            request,
            item.itemID
        )

        clearOwnedTooltip(itemRow.linkButton)

        if not obtained then
            remaining = remaining + 1
        end

        itemRow.request = request
        itemRow.itemID = item.itemID
        itemRow.linkButton.itemLink = item.link
        itemRow.linkButton.icon:SetTexture(
            item.icon or UNKNOWN_ITEM_ICON
        )
        itemRow.linkButton.icon:SetDesaturated(obtained)
        itemRow.linkButton.linkText:SetText(item.link)
        itemRow.linkButton.linkText:SetAlpha(obtained and 0.55 or 1)
        itemRow.checkbox:SetValue(obtained)
        itemRow:Show()
    end

    hideUnusedItemRows(panel, #items + 1)
    panel.summaryText:SetText(
        NS.Catalog:GetSpecName(request.specID)
        .. " loot specialization - "
        .. remaining .. " remaining / " .. #items .. " total"
    )

    if #items == 0 then
        renderStatus(
            tracked,
            "No bonus-rollable items were found for this combination.",
            true
        )
        return
    end

    tracked.lootContentRows = #items
    setPanelHeight(tracked, tracked.lootContentRows)
end

local function renderTrackedRow(tracked)
    if not tracked.lootExpanded then
        return
    end

    local request = tracked.getLootRequest()
    tracked.lootQueryKey = request and request.queryKey or nil
    tracked.lootTrackingKey = request and request.trackingKey or nil

    if not request then
        tracked.lootPanel.summaryText:SetText("Loot items")
        renderStatus(
            tracked,
            "Loot information is unavailable for this combination."
        )
        return
    end

    local pool = NS.LootTracker:GetPool(request)

    -- The first Journal read runs on the next tick. Keep the current panel
    -- untouched unless that immediate attempt confirms data is still loading.
    if pool.status == "pending" then
        return
    end

    tracked.lootPanel.summaryText:SetText(
        NS.Catalog:GetSpecName(request.specID)
        .. " loot specialization"
    )
    if pool.status ~= "ready" then
        renderStatus(
            tracked,
            pool.message or "Loot information is unavailable.",
            pool.retryable == true,
            pool.status == "loading"
        )
        return
    end

    renderItems(tracked, request, pool.items)
end

local function setExpanded(tracked, expanded)
    expanded = expanded == true and tracked.isEnabled()
    if tracked.lootExpanded == expanded then
        if expanded then
            renderTrackedRow(tracked)
        end
        return
    end

    tracked.lootExpanded = expanded
    if expanded then
        tracked.lootPanel:Show()
        renderTrackedRow(tracked)
    else
        tracked.lootQueryKey = nil
        tracked.lootTrackingKey = nil
        for index = 1, #tracked.lootPanel.itemRows do
            clearOwnedTooltip(
                tracked.lootPanel.itemRows[index].linkButton
            )
        end
        tracked.lootPanel:Hide()
        tracked.row:SetHeight(tracked.lootBaseHeight)
    end
end

function LootSettings:Attach(row, tableView, tracked)
    assert(type(tracked.getLootRequest) == "function")

    tracked.row = row
    tracked.lootBaseHeight = row:GetHeight()
    tracked.lootExpanded = false
    tracked.lootContentRows = 1

    tracked.itemsControl = row:AddControl("items", "button", {
        variant = "square",
        iconAtlas = SETTINGS_ICON_ATLAS,
        iconSize = 34,
        tooltipTitle = "Bonus-rollable items",
        tooltip = "Show the bonus-rollable items available for this loot specialization.",
        onClick = function()
            setExpanded(tracked, not tracked.lootExpanded)
        end,
    }, {
        point = "LEFT",
        relativePoint = "LEFT",
    })

    local rowFrame = row:GetFrame()
    local panel = CreateFrame("Frame", nil, rowFrame)

    panel:SetPoint(
        "TOPLEFT",
        rowFrame,
        "TOPLEFT",
        DETAILS_INSET,
        -tracked.lootBaseHeight
    )
    panel:SetPoint(
        "TOPRIGHT",
        rowFrame,
        "TOPRIGHT",
        -DETAILS_INSET,
        -tracked.lootBaseHeight
    )
    panel:SetHeight(1)

    panel.background = NS.PixelPerfect.CreateSurface(
        panel,
        DETAILS_BACKGROUND_COLOR,
        DETAILS_BORDER_COLOR,
        1
    )

    local summaryText = panel:CreateFontString(
        nil,
        "OVERLAY",
        "GameFontHighlightSmall"
    )

    summaryText:SetPoint(
        "TOPLEFT",
        panel,
        "TOPLEFT",
        DETAILS_SUMMARY_LEFT_INSET,
        -8
    )
    summaryText:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -DETAILS_INSET, -8)
    summaryText:SetJustifyH("LEFT")
    summaryText:SetWordWrap(false)
    summaryText:SetMaxLines(1)
    panel.summaryText = summaryText

    local obtainedHeader = panel:CreateFontString(
        nil,
        "OVERLAY",
        "GameFontNormalSmall"
    )

    obtainedHeader:SetPoint(
        "TOP",
        panel,
        "TOPLEFT",
        DETAILS_INSET + (ITEM_CHECKBOX_SIZE / 2),
        -8
    )
    obtainedHeader:SetText("Obtained")

    local statusText = panel:CreateFontString(
        nil,
        "OVERLAY",
        "GameFontDisableSmall"
    )

    statusText:SetPoint(
        "TOPLEFT",
        panel,
        "TOPLEFT",
        DETAILS_INSET + 4,
        -DETAILS_HEADER_HEIGHT
    )
    statusText:SetPoint(
        "TOPRIGHT",
        panel,
        "TOPRIGHT",
        -DETAILS_INSET,
        -DETAILS_HEADER_HEIGHT
    )
    statusText:SetHeight(ITEM_ROW_HEIGHT)
    statusText:SetJustifyH("LEFT")
    statusText:SetJustifyV("MIDDLE")
    statusText:SetWordWrap(true)
    panel.statusText = statusText

    local retryButton = ModernSettings:CreateButton(panel, {
        variant = "small",
        text = "Retry",
        width = RETRY_BUTTON_WIDTH,
        tooltipTitle = "Retry loot information",
        tooltip = "Request this loot list from the Encounter Journal again.",
        onClick = function()
            local request = tracked.getLootRequest()

            if NS.LootTracker:RetryPool(request) then
                renderTrackedRow(tracked)
            end
        end,
    })

    retryButton:SetPoint(
        "RIGHT",
        panel,
        "TOPRIGHT",
        -DETAILS_INSET,
        -(DETAILS_HEADER_HEIGHT + (ITEM_ROW_HEIGHT / 2))
    )
    retryButton:Hide()
    panel.retryButton = retryButton
    panel.itemRows = {}

    panel:Hide()
    tracked.lootPanel = panel
    self.trackedRows[#self.trackedRows + 1] = tracked
end

function LootSettings:Refresh(tracked)
    if not tracked.itemsControl then
        return
    end

    local enabled = tracked.isEnabled()

    tracked.itemsControl:SetControlEnabled(
        enabled,
        "Enable this bonus-roll rule first."
    )
    if not enabled then
        setExpanded(tracked, false)
    elseif tracked.lootExpanded then
        renderTrackedRow(tracked)
    end
end

NS.LootTracker:RegisterChangedCallback(function(changeType, key)
    for index = 1, #LootSettings.trackedRows do
        local tracked = LootSettings.trackedRows[index]

        if tracked.lootExpanded
            and ((changeType == "pool" and tracked.lootQueryKey == key)
                or (changeType == "obtained"
                    and tracked.lootTrackingKey == key))
        then
            renderTrackedRow(tracked)
        end
    end
end)
