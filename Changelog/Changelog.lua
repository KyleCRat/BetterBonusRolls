local addonName, NS = ...

local Changelog = {}
NS.Changelog = Changelog

function Changelog:CreateSettingsPage(measurementFrame)
    return self.controller:CreateSettingsPage({
        measurementFrame = measurementFrame,
    })
end

NS:RegisterInitializer(function()
    local release = CopyTable(NS.ReleaseNotes)
    release.highlights = NS.ChangelogHighlights[release.version] or {}

    Changelog.controller = LibStub("LibChangelog-1.0"):Register(addonName, {
        displayName = NS.displayName,
        release = release,
        -- Changelog preferences and read status are shared across characters.
        -- Registration is independent of bonus-roll filtering being enabled.
        storage = {
            get = function(key)
                return NS.AccountDB:Get("changelog", key)
            end,
            set = function(key, value)
                NS.AccountDB:Set("changelog", key, value)
            end,
        },
    })
end)
