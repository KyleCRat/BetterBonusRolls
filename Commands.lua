local _, NS = ...

local function trim(text)
    return (text or ""):match("^%s*(.-)%s*$")
end

local function openSettings()
    if not NS:OpenSettings() then
        NS:Print("Settings are not available yet.")
    end
end

local function enableAddon()
    if NS:SetEnabled(true) then
        NS:Print("Enabled for this character.")
    end
end

local function disableAddon()
    if NS:SetEnabled(false) then
        NS:Print("Disabled. Blizzard's native bonus-roll behavior is restored.")
    end
end

local commands = {
    {
        triggers = { "settings", "s", "config", "c" },
        usage = "settings (s, config, c)",
        description = "open settings",
        root = true,
        func = openSettings,
    },
    {
        triggers = { "show", "sh" },
        usage = "show (sh)",
        description = "restore a hidden offer while it is active",
        func = function()
            NS.RollController:ShowCurrent()
        end,
    },
    {
        triggers = { "hide", "h" },
        usage = "hide (h)",
        description = "hide the offer without declining it",
        func = function()
            NS.RollController:HideCurrentByCommand()
        end,
    },
    {
        triggers = { "enable", "e" },
        usage = "enable (e)",
        description = "enable filtering and confirmations",
        func = enableAddon,
    },
    {
        triggers = { "disable", "d" },
        usage = "disable (d)",
        description = "restore untouched Blizzard behavior",
        func = disableAddon,
    },
    {
        triggers = { "status", "st" },
        usage = "status (st)",
        description = "show addon and active-offer status",
        func = function()
            NS:Print(NS.RollController:GetStatusText() .. ".")
        end,
    },
    {
        triggers = { "preview", "p" },
        usage = "preview (p)",
        description = "toggle the developer sidecar preview",
        available = function()
            return NS.Preview:IsEnabled()
        end,
        func = function()
            NS.Preview:Toggle()
        end,
    },
}

local function isAvailable(command)
    return not command.available or command.available()
end

local function matches(command, input)
    for index = 1, #command.triggers do
        if input == command.triggers[index] then
            return true
        end
    end

    return false
end

local function printHelp()
    NS:Print("Commands:")
    for index = 1, #commands do
        local command = commands[index]
        if isAvailable(command) then
            local prefix = command.root and "  /bbr or /bbr " or "  /bbr "
            NS:Print(prefix .. command.usage .. " - " .. command.description)
        end
    end
end

commands[#commands + 1] = {
    triggers = { "help", "?" },
    usage = "help (?)",
    description = "show these commands",
    func = printHelp,
}

local function handleCommand(message)
    local input = trim(message):lower()

    if input == "" then
        openSettings()
        return
    end

    for index = 1, #commands do
        local command = commands[index]
        if isAvailable(command) and matches(command, input) then
            command.func()
            return
        end
    end

    NS:Print("Unknown command: " .. input)
    printHelp()
end

SLASH_BETTERBONUSROLLS1 = "/bbr"
SLASH_BETTERBONUSROLLS2 = "/betterbonusrolls"
SlashCmdList.BETTERBONUSROLLS = handleCommand
