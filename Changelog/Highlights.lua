local _, NS = ...

NS.ChangelogHighlights = {
    Unreleased = {
        {
            title = "Your enabled raid difficulties open first",
            body = "Raid and Lair settings open every difficulty with an enabled boss. With none enabled, only the top difficulty opens. You can still expand or collapse groups while viewing the page.",
            emphasis = "requested",
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
            body = "Browse highlights and full notes on the Changelog settings page, or use /changelog to see updates from all supported addons. Automatic update notices and read status are saved separately for each BBR character.",
        },
    },
}
