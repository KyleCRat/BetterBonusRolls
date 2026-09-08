local _, NS = ...

local ModernSettings = LibStub("LibModernSettings-1.0")
local ObtainedCheckbox = {}
NS.ObtainedCheckbox = ObtainedCheckbox

local UNCHECK_POPUP = "BETTERBONUSROLLS_UNCHECK_OBTAINED"
local pendingUncheck

local function cancelPendingUncheck(checkbox)
    local pending = pendingUncheck
    if pending and (not checkbox or pending.checkbox == checkbox) then
        pendingUncheck = nil
        StaticPopup_Hide(UNCHECK_POPUP, pending)
    end
end

local function getItemName(item)
    if not NS:IsSecret(item.name)
        and type(item.name) == "string"
        and item.name ~= ""
    then
        return item.name
    end

    return "Item " .. item.itemID
end

local function getConfirmationText(request, itemName)
    return "BetterBonusRolls has confirmed that you obtained "
        .. itemName .. " from " .. request.sourceName .. " for "
        .. NS.Catalog:GetSpecName(request.specID) .. " loot specialization."
end

local function refreshCheckbox(checkbox)
    local binding = checkbox.bbrObtainedBinding
    if not binding then
        checkbox:SetValue(false)
        return false
    end

    local request = binding.request
    local obtained = NS.LootTracker:IsObtained(request, binding.itemID)
    local confirmed = NS.LootTracker:IsConfirmedObtained(request, binding.itemID)
    local action = obtained and "not obtained" or "obtained"
    local text = "Mark " .. binding.itemName .. " from "
        .. request.sourceName .. " " .. action .. " for "
        .. NS.Catalog:GetSpecName(request.specID) .. " loot specialization."

    if confirmed then
        local confirmation = getConfirmationText(request, binding.itemName)
        if not obtained then
            confirmation = confirmation
                .. "\n\nYou manually marked this item not obtained."
        end

        text = confirmation .. "\n\n" .. text
    end

    if not obtained or not confirmed then
        cancelPendingUncheck(checkbox)
    end

    ModernSettings:SetTooltip(checkbox, {
        title = confirmed and "Confirmed Obtained" or "Obtained",
        text = text,
    })
    checkbox:SetValue(obtained)
    ModernSettings:RefreshTooltip(checkbox)
    return obtained
end

local function dismissUncheck(_, data)
    if pendingUncheck == data then
        pendingUncheck = nil
    end
end

-- This checklist dialog deliberately does not share the roll confirmation's
-- dialog type or callbacks. It can only change the original item's checklist.
StaticPopupDialogs[UNCHECK_POPUP] = {
    text = "%s",
    button1 = "Mark Not Obtained",
    button2 = "Cancel",
    OnAccept = function(_, data)
        if pendingUncheck ~= data then
            return
        end

        pendingUncheck = nil
        local checkbox = data.checkbox
        if checkbox.bbrObtainedBinding ~= data.binding
            or not checkbox:IsVisible()
        then
            return
        end

        NS.LootTracker:SetObtained(data.request, data.itemID, false)
        refreshCheckbox(checkbox)
    end,
    OnCancel = dismissUncheck,
    OnHide = dismissUncheck,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    wide = true,
}

local function onCheckboxChanged(checkbox, value)
    local binding = checkbox.bbrObtainedBinding
    if not binding then
        checkbox:SetValue(false)
        return
    end

    cancelPendingUncheck()
    local obtained = NS.LootTracker:IsObtained(binding.request, binding.itemID)
    if value == obtained then
        refreshCheckbox(checkbox)
        return
    end

    if not value
        and NS.LootTracker:IsConfirmedObtained(binding.request, binding.itemID)
    then
        -- The native checkbox has already toggled visually. Restore it without
        -- writing anything while the user decides whether to override it.
        refreshCheckbox(checkbox)
        local pending = {
            checkbox = checkbox,
            binding = binding,
            request = CopyTable(binding.request),
            itemID = binding.itemID,
        }
        pendingUncheck = pending

        local dialog = StaticPopup_Show(
            UNCHECK_POPUP,
            getConfirmationText(pending.request, binding.itemName)
                .. "\n\nMark this item as not obtained anyway?",
            nil,
            pending
        )

        if not dialog or not dialog:IsShown() then
            dismissUncheck(nil, pending)
            NS:Print("Unable to show the confirmation. The item remains marked obtained.")
        end

        return
    end

    NS.LootTracker:SetObtained(binding.request, binding.itemID, value)
    refreshCheckbox(checkbox)
end

function ObtainedCheckbox:Create(parent)
    local checkbox = ModernSettings:CreateCheckbox(parent, { value = false })

    checkbox:SetOnChanged(function(value)
        onCheckboxChanged(checkbox, value)
    end)
    checkbox:HookScript("OnHide", function()
        cancelPendingUncheck(checkbox)
        ModernSettings:HideOwnedTooltip(checkbox)
    end)

    return checkbox
end

function ObtainedCheckbox:Update(checkbox, request, item)
    local binding = checkbox.bbrObtainedBinding
    if not binding
        or binding.request.trackingKey ~= request.trackingKey
        or binding.itemID ~= item.itemID
    then
        cancelPendingUncheck(checkbox)
        binding = { itemID = item.itemID }
        checkbox.bbrObtainedBinding = binding
    end

    binding.request = request
    binding.itemName = getItemName(item)
    return refreshCheckbox(checkbox)
end

function ObtainedCheckbox:Reset(checkbox)
    cancelPendingUncheck(checkbox)
    ModernSettings:HideOwnedTooltip(checkbox)
    checkbox.bbrObtainedBinding = nil
    checkbox:SetValue(false)
end
