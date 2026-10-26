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
        -- BBR intentionally keeps all settings and read status per character.
        -- Registration is independent of bonus-roll filtering being enabled.
        storage = {
            get = function(key)
                return NS.DB:Get("changelog", key)
            end,
            set = function(key, value)
                NS.DB:Set("changelog", key, value)
            end,
        },
    })
end)
