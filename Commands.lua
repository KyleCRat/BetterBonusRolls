local _, NS = ...

local function trim(text)
    return (text or ""):match("^%s*(.-)%s*$")
end

local function printHelp()
    NS:Print("Commands:")
    NS:Print("  /bbr or /bbr config - open settings")
    NS:Print("  /bbr show - restore a hidden offer while it is active")
    NS:Print("  /bbr hide - hide the offer without declining it")
    NS:Print("  /bbr enable - enable filtering and confirmations")
    NS:Print("  /bbr disable - restore untouched Blizzard behavior")
    NS:Print("  /bbr status - show addon and active-offer status")
    NS:Print("  /bbr help - show these commands")
end

local function handleCommand(message)
    local command = trim(message):lower()

    if command == "" or command == "config" then
        if not NS:OpenSettings() then
            NS:Print("Settings are not available yet.")
        end
    elseif command == "show" then
        NS.RollController:ShowCurrent()
    elseif command == "hide" then
        NS.RollController:HideCurrentByCommand()
    elseif command == "enable" then
        if NS:SetEnabled(true) then
            NS:Print("Enabled for this character.")
        end
    elseif command == "disable" then
        if NS:SetEnabled(false) then
            NS:Print("Disabled. Blizzard's native bonus-roll behavior is restored.")
        end
    elseif command == "status" then
        NS:Print(NS.RollController:GetStatusText() .. ".")
    elseif command == "help" then
        printHelp()
    else
        NS:Print("Unknown command: " .. command)
        printHelp()
    end
end

SLASH_BETTERBONUSROLLS1 = "/bbr"
SLASH_BETTERBONUSROLLS2 = "/betterbonusrolls"
SlashCmdList.BETTERBONUSROLLS = handleCommand
