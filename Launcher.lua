local _, NS = ...

local DataBroker = LibStub("LibDataBroker-1.1")
local DBIcon = LibStub("LibDBIcon-1.0")

local Launcher = {}
NS.Launcher = Launcher

local LAUNCHER_NAME = "BetterBonusRolls"
local ICON_PATH = "Interface\\AddOns\\BetterBonusRolls\\ICON.tga"

local minimapState = setmetatable({}, {
    __index = function(_, key)
        return NS.DB:Get("minimap", key)
    end,
    __newindex = function(_, key, value)
        NS.DB:Set("minimap", key, value)
    end,
})

local broker = DataBroker:NewDataObject(LAUNCHER_NAME, {
    type = "launcher",
    label = NS.displayName,
    text = NS.displayName,
    icon = ICON_PATH,
    OnClick = function()
        NS:OpenSettings()
    end,
    OnTooltipShow = function(tooltip)
        tooltip:AddLine(NS.displayName)
        tooltip:AddLine("Click to open settings.", 1, 1, 1)
    end,
})

function Launcher:IsMinimapShown()
    return not NS.DB:Get("minimap", "hide")
end

function Launcher:SetMinimapShown(shown)
    shown = shown == true
    NS.DB:Set("minimap", "hide", not shown)

    if shown then
        DBIcon:Show(LAUNCHER_NAME)
    else
        DBIcon:Hide(LAUNCHER_NAME)
    end

    NS.SettingsUI:RefreshGeneralControls()
end

NS:RegisterInitializer(function()
    DBIcon:Register(LAUNCHER_NAME, broker, minimapState)
end)

function BetterBonusRolls_OnAddonCompartmentClick()
    NS:OpenSettings()
end
