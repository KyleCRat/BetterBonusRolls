local _, NS = ...

-- Developer-only visual test mode. Keep this false in release builds.
local ENABLE_DEV_PREVIEW = false

local Preview = {}
NS.Preview = Preview

local frame
local panel
local button

local FRAME_WIDTH = 286
local FRAME_HEIGHT = 76
local ADDON_ICON = "Interface\\AddOns\\BetterBonusRolls\\ICON.tga"
local UNKNOWN_SPEC_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local function isPlayerInCombat()
    return InCombatLockdown and InCombatLockdown()
end

local function getCurrentClassSpec(specID)
    if not NS:IsPublicPositiveInteger(specID) then
        return nil
    end

    return NS.Catalog.specByID[specID]
end

local function hidePanel(clearTarget)
    if not panel then
        return
    end

    panel:Hide()
    button:Hide()
    button.specIcon:SetTexture(nil)
    button.specIcon:Hide()
    if clearTarget then
        button.configuredSpecID = nil
        button.configuredLootSpecID = nil
    end
end

local function closePreview()
    if not frame then
        return
    end

    frame:Hide()
    hidePanel(true)
    NS:Print("Bonus-roll preview hidden.")
end

local function getSpecIcon(spec)
    local _, _, _, icon = GetSpecializationInfoForSpecID(spec.id)
    if NS:IsPublicPositiveInteger(icon) then
        return icon
    end
    if NS:IsPublicPositiveInteger(spec.icon) then
        return spec.icon
    end

    return UNKNOWN_SPEC_ICON
end

local function refreshPanel()
    if not frame or not frame:IsShown() then
        return
    end

    local desiredSpecID = button.configuredSpecID
    local desiredLootSpecID = button.configuredLootSpecID
    local spec = getCurrentClassSpec(desiredSpecID)
    if not spec
        or desiredLootSpecID ~= desiredSpecID
        or NS.Catalog:GetEffectiveLootSpecID() == desiredSpecID
    then
        hidePanel(false)
        return
    end

    button.specIcon:SetTexture(getSpecIcon(spec))
    button.specIcon:Show()
    button:Show()
    panel:Show()
end

local function handleButtonClick(self)
    if self ~= button or not frame or not frame:IsShown() then
        return
    end

    if isPlayerInCombat() then
        NS:Print("The loot-specialization preview cannot be used in combat.")
        return
    end

    local desiredSpecID = self.configuredSpecID
    local desiredLootSpecID = self.configuredLootSpecID
    local spec = getCurrentClassSpec(desiredSpecID)
    if not spec
        or desiredLootSpecID ~= desiredSpecID
        or not NS:IsPublicPositiveInteger(desiredLootSpecID)
    then
        return
    end

    SetLootSpecialization(desiredLootSpecID)
    refreshPanel()
    NS:Print("Loot specialization change requested for " .. spec.name
        .. ". The preview did not use a bonus roll.")
end

local function createPreviewFrame()
    frame = CreateFrame("Frame", nil, UIParent, "TooltipBackdropTemplate")
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    frame:SetPoint("CENTER", UIParent, "CENTER", -35, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetDontSavePosition(true)
    frame:SetUserPlaced(false)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if not isPlayerInCombat() then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(46, 46)
    icon:SetPoint("LEFT", frame, "LEFT", 10, 0)
    icon:SetTexture(ADDON_ICON)

    local title = frame:CreateFontString(
        nil,
        "OVERLAY",
        "GameFontNormalLarge"
    )
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 66, -16)
    title:SetText("Bonus Loot Preview")

    local description = frame:CreateFontString(
        nil,
        "OVERLAY",
        "GameFontHighlightSmall"
    )
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    description:SetText("Fake offer - no Roll or Pass action exists.")

    local closeButton = CreateFrame(
        "Button",
        nil,
        frame,
        "UIPanelCloseButton"
    )
    closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, 2)
    closeButton:SetFrameLevel(frame:GetFrameLevel() + 20)
    closeButton:SetScript("OnClick", closePreview)

    panel, button = NS.RollController:CreateLootSpecPanel(
        frame,
        frame,
        handleButtonClick
    )
    frame:Hide()
end

local function handleLootSpecUpdate(event, unit)
    if event == "PLAYER_SPECIALIZATION_CHANGED" and unit ~= "player" then
        return
    end

    refreshPanel()
end

function Preview:IsEnabled()
    return ENABLE_DEV_PREVIEW
end

function Preview:Toggle()
    if not ENABLE_DEV_PREVIEW then
        return false
    end

    if frame and frame:IsShown() then
        closePreview()
        return true
    end

    if isPlayerInCombat() then
        NS:Print("The bonus-roll preview cannot be opened in combat.")
        return false
    end

    local currentSpecID = NS.Catalog:GetEffectiveLootSpecID()
    local candidates = {}
    for index = 1, #NS.Catalog.specs do
        local spec = NS.Catalog.specs[index]
        if spec.id ~= currentSpecID then
            candidates[#candidates + 1] = spec
        end
    end

    if #candidates == 0 then
        NS:Print("No alternate loot specialization is available for the preview.")
        return false
    end

    local previewSpec = candidates[math.random(#candidates)]
    if not frame then
        createPreviewFrame()
    end

    button.configuredSpecID = previewSpec.id
    button.configuredLootSpecID = previewSpec.id
    frame:Show()
    refreshPanel()
    NS:Print("Bonus-roll preview shown for " .. previewSpec.name
        .. ". This fake view cannot use or decline a bonus roll.")
    return true
end

NS:RegisterInitializer(function()
    if not ENABLE_DEV_PREVIEW then
        return
    end

    NS:RegisterEvent("PLAYER_LOOT_SPEC_UPDATED", handleLootSpecUpdate)
    NS:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", handleLootSpecUpdate)
end)
