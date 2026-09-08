local _, NS = ...

local ModernSettings = LibStub("LibModernSettings-1.0")
local LootSidecar = {}
local Sidecar = {}

NS.LootSidecar = LootSidecar

local PANEL_WIDTH = 340
local PANEL_GAP = 6
local HEADER_HEIGHT = 48
local ITEM_ROW_HEIGHT = 38
local ITEM_CHECKBOX_SIZE = 34
local ITEM_CONTROL_GAP = 8
local ITEM_ICON_SIZE = 30
local ITEM_TEXT_GAP = 8
local PANEL_INSET = 8
local BOTTOM_PADDING = 8
local ITEM_ROW_STRIPE_ALPHA = 0.06
local RETRY_BUTTON_WIDTH = 65
local STATUS_RETRY_GAP = 8
local BACKGROUND_COLOR = { r = 0.015, g = 0.018, b = 0.022, a = 0.95 }
local BORDER_COLOR = { r = 0.38, g = 0.41, b = 0.45, a = 0.9 }
local UNKNOWN_ITEM_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local sidecars = {}
local defaultSidecar

local function resetItemRow(itemRow)
    ModernSettings:HideOwnedTooltip(itemRow.checkbox)
    ModernSettings:HideOwnedTooltip(itemRow.linkButton)
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

local function hideUnusedItemRows(sidecar, firstUnusedIndex)
    local itemRows = sidecar.panel.itemRows

    for index = firstUnusedIndex, #itemRows do
        resetItemRow(itemRows[index])
    end
end

local function createItemRow(sidecar, index)
    local panel = sidecar.panel
    local itemRow = CreateFrame("Frame", nil, panel)

    itemRow:SetFrameLevel(panel:GetFrameLevel() + 1)
    itemRow:SetHeight(ITEM_ROW_HEIGHT)
    itemRow:SetPoint(
        "TOPLEFT",
        panel,
        "TOPLEFT",
        PANEL_INSET,
        -(HEADER_HEIGHT + ((index - 1) * ITEM_ROW_HEIGHT))
    )
    itemRow:SetPoint(
        "TOPRIGHT",
        panel,
        "TOPRIGHT",
        -PANEL_INSET,
        -(HEADER_HEIGHT + ((index - 1) * ITEM_ROW_HEIGHT))
    )

    if index % 2 == 0 then
        local stripe = itemRow:CreateTexture(nil, "BACKGROUND")

        stripe:SetPoint(
            "TOPLEFT",
            itemRow,
            "TOPLEFT",
            -(PANEL_INSET - 1),
            0
        )
        stripe:SetPoint(
            "BOTTOMRIGHT",
            itemRow,
            "BOTTOMRIGHT",
            PANEL_INSET - 1,
            0
        )
        stripe:SetColorTexture(1, 1, 1, ITEM_ROW_STRIPE_ALPHA)
    end

    local checkbox = ModernSettings:CreateCheckbox(itemRow, {
        value = false,
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
        ITEM_CHECKBOX_SIZE + ITEM_CONTROL_GAP,
        0
    )
    linkButton:SetPoint("BOTTOMRIGHT", itemRow, "BOTTOMRIGHT", 0, 0)

    local icon = linkButton:CreateTexture(nil, "ARTWORK")

    icon:SetSize(ITEM_ICON_SIZE, ITEM_ICON_SIZE)
    icon:SetPoint("LEFT", linkButton, "LEFT", 0, 0)
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
    linkButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
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

local function acquireItemRow(sidecar, index)
    local itemRows = sidecar.panel.itemRows
    local itemRow = itemRows[index]

    if not itemRow then
        itemRow = createItemRow(sidecar, index)
        itemRows[index] = itemRow
    end

    return itemRow
end

local function setPanelHeight(sidecar, contentRows)
    sidecar.panel:SetHeight(
        HEADER_HEIGHT
        + (math.max(contentRows, 1) * ITEM_ROW_HEIGHT)
        + BOTTOM_PADDING
    )
end

local function renderStatus(sidecar, message, retryable)
    local panel = sidecar.panel

    hideUnusedItemRows(sidecar, 1)
    panel.statusText:ClearAllPoints()
    panel.statusText:SetPoint(
        "TOPLEFT",
        panel,
        "TOPLEFT",
        PANEL_INSET + 4,
        -HEADER_HEIGHT
    )
    panel.statusText:SetPoint(
        "TOPRIGHT",
        panel,
        "TOPRIGHT",
        retryable
            and -(PANEL_INSET + RETRY_BUTTON_WIDTH + STATUS_RETRY_GAP)
            or -PANEL_INSET,
        -HEADER_HEIGHT
    )
    panel.statusText:SetText(message)
    panel.statusText:Show()
    panel.retryButton:SetShown(retryable == true)
    setPanelHeight(sidecar, 1)
end

local function renderItems(sidecar, items)
    local panel = sidecar.panel
    local request = sidecar.activeRequest
    local specName = NS.Catalog:GetSpecName(request.specID)
    local remaining = 0

    panel.statusText:Hide()
    panel.retryButton:Hide()

    for index = 1, #items do
        local item = items[index]
        local itemRow = acquireItemRow(sidecar, index)
        local obtained = NS.LootTracker:IsObtained(
            request,
            item.itemID
        )
        local itemName = not NS:IsSecret(item.name)
            and type(item.name) == "string"
            and item.name ~= ""
            and item.name
            or "Item " .. item.itemID
        local obtainedAction = obtained and "not obtained" or "obtained"

        ModernSettings:HideOwnedTooltip(itemRow.linkButton)
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
        ModernSettings:SetTooltip(itemRow.checkbox, {
            title = "Obtained",
            text = "Mark " .. itemName .. " from "
                .. request.sourceName .. " " .. obtainedAction .. " for "
                .. specName .. " loot specialization.",
        })
        itemRow.checkbox:SetValue(obtained)
        ModernSettings:RefreshTooltip(itemRow.checkbox)
        itemRow:Show()
    end

    hideUnusedItemRows(sidecar, #items + 1)
    panel.summaryText:SetText(
        specName .. " - " .. remaining
        .. " remaining / " .. #items .. " total"
    )
    setPanelHeight(sidecar, #items)
end

local function render(sidecar)
    local panel = sidecar.panel
    local request = sidecar.activeRequest

    if not panel:IsShown() or not request then
        return
    end

    local pool = NS.LootTracker:GetPool(request)

    if pool.status == "pending" then
        return
    end

    panel.summaryText:SetText(
        NS.Catalog:GetSpecName(request.specID)
        .. " loot specialization"
    )
    if pool.status ~= "ready" then
        renderStatus(
            sidecar,
            pool.message or "Loot information is unavailable.",
            pool.retryable == true
        )
        return
    end

    if #pool.items == 0 then
        renderStatus(
            sidecar,
            "No bonus-rollable items were found for this combination.",
            true
        )
        return
    end

    renderItems(sidecar, pool.items)
end

function Sidecar:ShowRequest(request, anchor)
    if NS:IsSecret(request)
        or type(request) ~= "table"
        or NS:IsSecret(request.queryKey)
        or type(request.queryKey) ~= "string"
        or NS:IsSecret(request.trackingKey)
        or type(request.trackingKey) ~= "string"
        or not NS:IsPublicPositiveInteger(request.specID)
        or NS:IsSecret(request.sourceName)
        or type(request.sourceName) ~= "string"
        or request.sourceName == ""
        or not anchor
    then
        self:Hide()
        return false
    end

    local requestChanged = request.queryKey ~= self.activeQueryKey
        or request.trackingKey ~= self.activeTrackingKey

    self.activeRequest = request
    self.activeQueryKey = request.queryKey
    self.activeTrackingKey = request.trackingKey

    local panel = self.panel

    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", anchor, "TOPRIGHT", PANEL_GAP, 0)
    panel.title:SetText("Bonus Roll Items for " .. request.sourceName)

    if requestChanged then
        hideUnusedItemRows(self, 1)
        panel.statusText:Hide()
        panel.retryButton:Hide()
        panel.summaryText:SetText(
            NS.Catalog:GetSpecName(request.specID)
            .. " loot specialization"
        )
        setPanelHeight(self, 1)
    end

    panel:Show()
    render(self)
    return true
end

function Sidecar:ShowOffer(snapshot, anchor)
    return self:ShowRequest(
        NS.LootTracker:CreateOfferRequest(snapshot),
        anchor
    )
end

function Sidecar:Hide()
    self.activeRequest = nil
    self.activeQueryKey = nil
    self.activeTrackingKey = nil

    local panel = self.panel

    hideUnusedItemRows(self, 1)
    panel.statusText:Hide()
    panel.retryButton:Hide()
    panel.title:SetText("")
    panel.summaryText:SetText("")
    panel:Hide()
end

function LootSidecar:Create(parent)
    local sidecar = setmetatable({}, { __index = Sidecar })
    local panel = CreateFrame("Frame", nil, parent)

    sidecar.panel = panel
    panel:SetWidth(PANEL_WIDTH)
    panel:SetFrameLevel(parent:GetFrameLevel() + 20)
    panel:EnableMouse(true)
    panel.background = NS.PixelPerfect.CreateSurface(
        panel,
        BACKGROUND_COLOR,
        BORDER_COLOR,
        1
    )

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")

    title:SetPoint("TOPLEFT", panel, "TOPLEFT", PANEL_INSET, -8)
    title:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PANEL_INSET, -8)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    title:SetMaxLines(1)
    title:SetText("")
    panel.title = title

    local summaryText = panel:CreateFontString(
        nil,
        "OVERLAY",
        "GameFontHighlightSmall"
    )

    summaryText:SetPoint("TOPLEFT", panel, "TOPLEFT", PANEL_INSET, -27)
    summaryText:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PANEL_INSET, -27)
    summaryText:SetJustifyH("LEFT")
    summaryText:SetWordWrap(false)
    summaryText:SetMaxLines(1)
    panel.summaryText = summaryText

    local statusText = panel:CreateFontString(
        nil,
        "OVERLAY",
        "GameFontDisableSmall"
    )

    statusText:SetHeight(ITEM_ROW_HEIGHT)
    statusText:SetJustifyH("LEFT")
    statusText:SetJustifyV("MIDDLE")
    statusText:SetWordWrap(true)
    statusText:Hide()
    panel.statusText = statusText

    local retryButton = ModernSettings:CreateButton(panel, {
        variant = "small",
        text = "Retry",
        width = RETRY_BUTTON_WIDTH,
        tooltipTitle = "Retry loot information",
        tooltip = "Request this loot list from the Encounter Journal again.",
        onClick = function()
            local request = sidecar.activeRequest

            if request and NS.LootTracker:RetryPool(request) then
                render(sidecar)
            end
        end,
    })

    retryButton:SetPoint(
        "RIGHT",
        panel,
        "TOPRIGHT",
        -PANEL_INSET,
        -(HEADER_HEIGHT + (ITEM_ROW_HEIGHT / 2))
    )
    retryButton:Hide()
    panel.retryButton = retryButton
    panel.itemRows = {}

    setPanelHeight(sidecar, 1)
    panel:Hide()

    sidecars[#sidecars + 1] = sidecar
    return sidecar
end

function LootSidecar:Attach(parent)
    if not defaultSidecar then
        defaultSidecar = self:Create(parent)
    end
end

function LootSidecar:Refresh(snapshot, anchor)
    if not defaultSidecar then
        return false
    end

    return defaultSidecar:ShowOffer(snapshot, anchor)
end

function LootSidecar:Hide()
    if defaultSidecar then
        defaultSidecar:Hide()
    end
end

NS.LootTracker:RegisterChangedCallback(function(changeType, key)
    for index = 1, #sidecars do
        local sidecar = sidecars[index]
        local panel = sidecar.panel

        if panel:IsShown()
            and sidecar.activeRequest
            and ((changeType == "pool" and key == sidecar.activeQueryKey)
                or (changeType == "obtained"
                    and key == sidecar.activeTrackingKey))
        then
            render(sidecar)
        end
    end
end)
