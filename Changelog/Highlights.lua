local _, NS = ...

NS.ChangelogHighlights = {
    ["12.1.5-8"] = {
        {
            title = "Hidden-offer reminders repeat less often",
            body = "Reminders print immediately, then after about 10 and 20 seconds while the offer stays active and hidden. Each roll gets only one pair of repeats. Using /bbr show cancels pending repeats; hiding that roll again prints only the immediate message.",
        },
    },
    ["12.1.5-7"] = {
        {
            title = "Hidden-offer reminders are easier to see",
            body = "Reminders print immediately and again after 5 and 10 seconds while the offer stays active and hidden. The /bbr show command is highlighted in yellow; showing the offer stops the remaining reminders.",
        },
        {
            title = "Your enabled raid difficulties open first",
            body = "Raid and Lair settings open every difficulty with an enabled boss. With none enabled, only the top difficulty opens. You can still expand or collapse groups while viewing the page.",
            controls = {
                {
                    type = "button",
                    dismissBatch = true,
                    options = {
                        text = "Open bonus-roll settings",
                        onClick = function()
                            if not NS:OpenSettings() then
                                NS:Print("Settings are not available yet.")
                            end
                        end,
                    },
                },
            },
        },
        {
            title = "Read update notes in game",
            body = "Browse highlights and full notes on the Changelog settings page, or use /changelog to see updates from all supported addons. Notification preferences and read status are shared across your account, so each release only needs to be acknowledged once across your characters.",
        },
    },
}
