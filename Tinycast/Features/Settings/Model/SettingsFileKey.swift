import Foundation

/// Every key settings.json holds, in the order the file lists them; the raw value is its path.
enum SettingsFileKey: String, CaseIterable, Sendable {
    // Spelled out, so renaming a case can never rename a key in someone's file.
    case launcherShortcut = "general.launcherShortcut"
    case showInMenuBar = "general.showInMenuBar"
    case popToRootTimeout = "general.popToRootSeconds"
    case escapeKeyBehavior = "general.escapeKeyBehavior"
    case supportReminders = "general.supportReminders"
    case language = "general.language"
    case appearance = "appearance.theme"
    case animationsEnabled = "appearance.animations"
    case interfaceSize = "appearance.interfaceSize"
    case compactMode = "appearance.compactMode"
    case showFavoritesInCompactMode = "appearance.showFavoritesInCompactMode"
    case openOnCursorScreen = "appearance.followCursorAcrossDisplays"
    case paletteDraggable = "appearance.dragToReposition"
    case launcherShowsSuggestions = "search.showsSuggestions"
    case rootSearchSensitivity = "search.sensitivity"
    case applicationsEnabled = "applications.enabled"
    case searchScopes = "applications.searchScopes"
    case applications = "applications.apps"
    case systemSettingsEnabled = "systemSettings.enabled"
    case systemSettings = "systemSettings.panes"
    case builtInCommandsEnabled = "commands.builtInEnabled"
    case builtInCommands = "commands.builtIn"
    case customCommandsEnabled = "commands.enabled"
    case customCommandsShowInLauncher = "commands.showInLauncher"
    case quicklinksEnabled = "quicklinks.enabled"
    case quicklinksShowInLauncher = "quicklinks.showInLauncher"
    case quicklinkPassesSelectedText = "quicklinks.passesSelectedText"
    case quicklinkConfirmsBeforeDelete = "quicklinks.confirmsBeforeDelete"
    case quicklinkCommands = "quicklinks.commands"
    case appleShortcutsEnabled = "appleShortcuts.enabled"
    case fileSearchEnabled = "fileSearch.enabled"
    case fileSearchScopes = "fileSearch.scopes"
    case fileSearchIgnorePatterns = "fileSearch.ignorePatterns"
    case fileSearchRemovedDefaultPatterns = "fileSearch.removedDefaultPatterns"
    case fileSearchShowInLauncher = "fileSearch.showInLauncher"
    case fileSearchCommands = "fileSearch.commands"
    case notesEnabled = "notes.enabled"
    case notesRendersMarkdown = "notes.rendersMarkdown"
    case notesShowsFormattingBar = "notes.showsFormattingBar"
    case notesFolder = "notes.folder"
    case notesCommands = "notes.commands"
    case snippetsShowInLauncher = "snippets.showInLauncher"
    case snippetsFolder = "snippets.folder"
    case snippetsCommands = "snippets.commands"
    case clipboardEnabled = "clipboard.enabled"
    case clipboardRetention = "clipboard.retentionDays"
    case clipboardDefaultAction = "clipboard.defaultAction"
    case clipboardDisabledApps = "clipboard.disabledApps"
    case clipboardCommands = "clipboard.commands"
    case emojiSkinTone = "emoji.skinTone"
    case emojiGridColumns = "emoji.gridColumns"
    case emojiCommands = "emoji.commands"
    case extensionsShowInLauncher = "extensions.showInLauncher"

    var section: String { String(rawValue.prefix { $0 != "." }) }

    var name: String { String(rawValue.drop { $0 != "." }.dropFirst()) }

    /// Every section, in file order.
    static let sections: [String] = allCases.reduce(into: []) { sections, key in
        if sections.last != key.section { sections.append(key.section) }
    }
}
