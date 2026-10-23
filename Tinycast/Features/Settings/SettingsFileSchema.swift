import Foundation

/// Where each settings.json key lives; exhaustive, so a new key fails to build until it is bound.
@MainActor
enum SettingsFileSchema {
    static func bindings(
        settings: AppSettings, shortcuts: HotKeySettingsFile, launcher: LauncherSettingsFile
    ) -> [SettingsFileBinding] {
        SettingsFileKey.allCases.map { key in
            binding(for: key, settings: settings, shortcuts: shortcuts, launcher: launcher)
        }
    }

    private static func binding(
        for key: SettingsFileKey, settings: AppSettings, shortcuts: HotKeySettingsFile,
        launcher: LauncherSettingsFile
    ) -> SettingsFileBinding {
        func bind<Root: AnyObject, Value: SettingsFileValue>(
            _ root: Root, _ path: ReferenceWritableKeyPath<Root, Value>,
            accept: @escaping (Value) -> Value? = { $0 }
        ) -> SettingsFileBinding {
            SettingsFileBinding(key, root, path, accept: accept)
        }

        switch key {
        case .launcherShortcut:
            return shortcuts.binding(
                for: key, action: .togglePalette, name: String(localized: "App Launcher"))
        case .showInMenuBar: return bind(settings, \.showInMenuBar)
        case .automaticallyCheckForUpdates: return bind(settings, \.automaticallyCheckForUpdates)
        case .popToRootTimeout: return bind(settings, \.popToRootTimeout)
        case .escapeKeyBehavior: return bind(settings, \.escapeKeyBehavior)
        case .supportReminders: return bind(settings, \.supportRemindersEnabled)
        case .language: return bind(settings, \.language)
        case .appearance: return bind(settings, \.appearance)
        case .animationsEnabled: return bind(settings, \.animationsEnabled)
        case .interfaceSize: return bind(settings, \.interfaceSize)
        case .compactMode: return bind(settings, \.compactMode)
        case .showFavoritesInCompactMode: return bind(settings, \.showFavoritesInCompactMode)
        case .openOnCursorScreen: return bind(settings, \.openOnCursorScreen)
        case .paletteDraggable: return bind(settings, \.paletteDraggable)
        case .calcNumberStyle: return bind(settings, \.calcNumberStyle)
        case .launcherShowsSuggestions: return bind(settings, \.launcherShowsSuggestions)
        case .rootSearchSensitivity: return bind(settings, \.rootSearchSensitivity)
        case .applicationsEnabled: return launcher.kindBinding(for: key, kind: .application)
        case .searchScopes: return bind(settings, \.searchScopes) { SearchScopes.normalize($0) }
        case .applications: return launcher.appsBinding(for: key)
        case .systemSettingsEnabled: return launcher.kindBinding(for: key, kind: .systemSettings)
        case .systemSettings: return launcher.panesBinding(for: key)
        case .builtInCommandsEnabled: return launcher.kindBinding(for: key, kind: .command)
        case .builtInCommands: return launcher.commandsBinding(for: key, owner: nil)
        case .customCommandsEnabled: return bind(settings, \.customCommandsEnabled)
        case .customCommandsShowInLauncher: return bind(settings, \.customCommandsShowInLauncher)
        case .quicklinksEnabled: return bind(settings, \.quicklinksEnabled)
        case .quicklinksShowInLauncher: return bind(settings, \.quicklinksShowInLauncher)
        case .quicklinkPassesSelectedText: return bind(settings, \.quicklinkPassesSelectedText)
        case .quicklinkConfirmsBeforeDelete: return bind(settings, \.quicklinkConfirmsBeforeDelete)
        case .quicklinkCommands: return launcher.commandsBinding(for: key, owner: .quicklinks)
        case .appleShortcutsEnabled: return bind(settings, \.appleShortcutsEnabled)
        case .fileSearchEnabled: return bind(settings, \.fileSearchEnabled)
        case .fileSearchScopes: return bind(settings, \.fileSearchScopes)
        case .fileSearchIgnorePatterns: return bind(settings, \.fileSearchIgnorePatterns)
        case .fileSearchRemovedDefaultPatterns:
            return bind(settings, \.fileSearchRemovedDefaultPatterns)
        case .fileSearchShowInLauncher: return bind(settings, \.fileSearchShowInLauncher)
        case .fileSearchCommands: return launcher.commandsBinding(for: key, owner: .fileSearch)
        case .notesEnabled: return bind(settings, \.notesEnabled)
        case .notesRendersMarkdown: return bind(settings, \.notesRendersMarkdown)
        case .notesShowsFormattingBar: return bind(settings, \.notesShowsFormattingBar)
        case .notesFolder: return bind(settings, \.notesFolder, accept: folder)
        case .notesCommands: return launcher.commandsBinding(for: key, owner: .notes)
        case .snippetsShowInLauncher: return bind(settings, \.snippetsShowInLauncher)
        case .snippetsFolder: return bind(settings, \.snippetsFolder, accept: folder)
        case .snippetsCommands: return launcher.commandsBinding(for: key, owner: .snippets)
        case .clipboardEnabled: return bind(settings, \.clipboardEnabled)
        case .clipboardRetention: return bind(settings, \.clipboardRetention)
        case .clipboardDefaultAction: return bind(settings, \.clipboardDefaultAction)
        case .clipboardDisabledApps: return bind(settings, \.clipboardDisabledApps)
        case .clipboardCommands: return launcher.commandsBinding(for: key, owner: .clipboard)
        case .emojiSkinTone: return bind(settings, \.emojiSkinTone)
        case .emojiGridColumns: return bind(settings, \.emojiGridColumns)
        case .emojiCommands: return launcher.commandsBinding(for: key, owner: .emoji)
        case .extensionsShowInLauncher: return bind(settings, \.extensionsShowInLauncher)
        }
    }

    /// A folder is absolute or under `~/`; null puts it back in Application Support.
    private static func folder(_ path: String?) -> String?? {
        guard let path else { return .some(nil) }
        return AppPaths.isFolderPath(path) ? path : nil
    }
}

extension PopToRootTimeout: SettingsFileRawValue {}
extension EscapeKeyBehavior: SettingsFileRawValue {}
extension AppAppearance: SettingsFileRawValue {}
extension AppLanguage: SettingsFileRawValue {}
extension InterfaceSize: SettingsFileRawValue {}
extension CalcNumberStyle: SettingsFileRawValue {}
extension SearchSensitivity: SettingsFileRawValue {}
extension ClipboardDefaultAction: SettingsFileRawValue {}
extension EmojiSkinTone: SettingsFileRawValue {}
extension EmojiGridColumns: SettingsFileRawValue {}

extension ClipboardRetention: SettingsFileToken {
    var settingsToken: SettingsFileJSON {
        switch self {
        case .day: 1
        case .week: 7
        case .month: 30
        case .threeMonths: 90
        case .sixMonths: 180
        case .year: 365
        case .forever: "forever"
        }
    }
}

