import Foundation

/// What `SettingsBackup.SettingsData` carries, written out so a new setting has to be considered.
enum SettingsBackupCoverage {
    static let mirrored: [String: AppSettingsKey] = [
        "clipboardEnabled": .clipboardEnabled,
        "clipboardRetentionDays": .clipboardRetention,
        "clipboardDefaultAction": .clipboardDefaultAction,
        "clipboardDisabledApps": .clipboardDisabledApps,
        "hyperKey": .hyperKey,
        "hyperKeyIncludesShift": .hyperKeyIncludesShift,
        "hyperKeyQuickPress": .hyperKeyQuickPress,
        "hyperKeySecureInputCompatibility": .hyperKeySecureInputCompatibility,
        "showInMenuBar": .showInMenuBar,
        "automaticallyCheckForUpdates": .automaticallyCheckForUpdates,
        "emojiSkinTone": .emojiSkinTone,
        "emojiGridColumns": .emojiGridColumns,
        "popToRootSeconds": .popToRootTimeout,
        "escapeKeyBehavior": .escapeKeyBehavior,
        "appearance": .appearance,
        "language": .language,
        "calcNumberStyle": .calcNumberStyle,
        "interfaceSize": .interfaceSize,
        "compactMode": .compactMode,
        "showFavoritesInCompactMode": .showFavoritesInCompactMode,
        "searchScopes": .searchScopes,
        "launcherShowsSuggestions": .launcherShowsSuggestions,
        "rootSearchSensitivity": .rootSearchSensitivity,
        "openOnCursorScreen": .openOnCursorScreen,
        "paletteDraggable": .paletteDraggable,
        "animationsEnabled": .animationsEnabled,
        "fileSearchEnabled": .fileSearchEnabled,
        "fileSearchScopes": .fileSearchScopes,
        "fileSearchIgnorePatterns": .fileSearchIgnorePatterns,
        "fileSearchRemovedDefaultPatterns": .fileSearchRemovedDefaultPatterns,
        "fileSearchShowInLauncher": .fileSearchShowInLauncher,
        "notesEnabled": .notesEnabled,
        "notesRendersMarkdown": .notesRendersMarkdown,
        "notesShowsFormattingBar": .notesShowsFormattingBar,
        "customCommandsEnabled": .customCommandsEnabled,
        "customCommandsShowInLauncher": .customCommandsShowInLauncher,
        "snippetsShowInLauncher": .snippetsShowInLauncher,
        "navigationEnabled": .navigationEnabled,
        "menuSearchDisabledApps": .menuSearchDisabledApps,
        "menuSearchShowsAppleMenu": .menuSearchShowsAppleMenu,
        "windowManagementEnabled": .windowManagementEnabled,
        "windowManagementShowInLauncher": .windowManagementShowInLauncher,
        "windowGap": .windowGap,
        "windowCycle": .windowCycle,
        "windowLayoutsShowInLauncher": .windowLayoutsShowInLauncher,
        "windowRoomsShowInLauncher": .windowRoomsShowInLauncher,
        "quicklinksEnabled": .quicklinksEnabled,
        "quicklinksShowInLauncher": .quicklinksShowInLauncher,
        "quicklinkOpensNewWindow": .quicklinkOpensNewWindow,
        "quicklinkPassesSelectedText": .quicklinkPassesSelectedText,
        "quicklinkConfirmsBeforeDelete": .quicklinkConfirmsBeforeDelete,
        "appleShortcutsEnabled": .appleShortcutsEnabled,
        "extensionsShowInLauncher": .extensionsShowInLauncher,
        "supportReminders": .supportReminders
    ]

    /// The `SettingsData` fields no `AppSettings` key stands behind, and what they read instead.
    static let externallySourced: [String: String] = [
        "launchAtLogin": "Read from LaunchAtLogin, which owns the login item, not UserDefaults."
    ]

    /// Keys kept out of a backup on purpose, each with the reason it has to stay out.
    static let deliberatelyExcluded: [String: String] = [
        AppSettingsKey.clipboardTextSearchEnabled.rawValue:
            "Background OCR is an opt-in processing choice on this Mac; a backup must not enable it.",
        AppSettingsKey.snippetsEnabled.rawValue:
            "Doubles as keyword-expansion consent; an import must not enable keystroke listening.",
        AppSettingsKey.extensionPackageManager.rawValue:
            "Names a tool on this Mac; the machine a backup lands on may not have it.",
        AppSettingsKey.extensionCustomSearchPaths.rawValue:
            "Machine-local toolchain paths; the Mac a backup lands on may not have them, or may have "
            + "something else there.",
        AppSettingsKey.extensionsEnabled.rawValue:
            "Doubles as consent to run third-party JavaScript; an import must not switch it on.",
        AppSettingsKey.palettePosition.rawValue:
            "Machine-local geometry: every entry names a display this Mac has, and no other one.",
        AppSettingsKey.paletteExpandedCenterDisplays.rawValue:
            "Machine-local geometry: every entry names a display this Mac has, and no other one.",
        AppSettingsKey.autoSwitchInputSource.rawValue:
            "Names a keyboard input source installed on this Mac; another Mac may not have it.",
        AppSettingsKey.snippetsFolder.rawValue:
            "Names a folder on this Mac; the one a backup lands on may not have it.",
        AppSettingsKey.notesFolder.rawValue:
            "Names a folder on this Mac; the one a backup lands on may not have it.",
        AppSettingsKey.settingsFileEnabled.rawValue:
            "Lets a file on this Mac change its settings; an import must not hand that to another."
    ]
}
