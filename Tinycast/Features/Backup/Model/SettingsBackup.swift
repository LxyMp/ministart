import Foundation

/// A readable configuration snapshot; every field is optional, so an import merges.
struct SettingsBackup: Codable {

    var settings: SettingsData?
    var hotkeys: HotkeyBackup?
    var customCommands: [CustomCommand]?
    var quicklinks: [Quicklink]?
    var favoriteApps: [String]?
    var hiddenLauncherItems: [String]?
    var hiddenLauncherKinds: [String]?
    var launcherAliases: [String: String]?
    var pinnedEmoji: [String]?

    /// Enums store by raw value, so an unknown one is ignored rather than failing.
    struct SettingsData: Codable {
        // Adding a field here means adding it to SettingsBackupCoverage too, or the harness fails.
        // Carried, unlike the consent flags: recording your own copies grants no permission class.
        var clipboardEnabled: Bool?
        var clipboardRetentionDays: Int?
        var clipboardDefaultAction: String?
        var clipboardDisabledApps: [String]?
        var launchAtLogin: Bool?
        var emojiSkinTone: String?
        var emojiGridColumns: Int?
        var showInMenuBar: Bool?
        var automaticallyCheckForUpdates: Bool?
        var popToRootSeconds: Int?
        var escapeKeyBehavior: String?
        var appearance: String?
        var language: String?
        var calcNumberStyle: String?
        var interfaceSize: String?
        var compactMode: Bool?
        var showFavoritesInCompactMode: Bool?
        var searchScopes: [String]?
        var launcherShowsSuggestions: Bool?
        var rootSearchSensitivity: String?
        var openOnCursorScreen: Bool?
        // Safe to carry: it grants no permission class, just repositions the window.
        var paletteDraggable: Bool?
        var animationsEnabled: Bool?
        var fileSearchEnabled: Bool?
        var fileSearchScopes: [String]?
        var fileSearchIgnorePatterns: [String]?
        var fileSearchRemovedDefaultPatterns: [String]?
        var fileSearchShowInLauncher: Bool?
        var notesEnabled: Bool?
        var notesRendersMarkdown: Bool?
        var notesShowsFormattingBar: Bool?
        // `snippetsEnabled` is absent: an import must not enable keystroke listening.
        var customCommandsEnabled: Bool?
        var customCommandsShowInLauncher: Bool?
        var snippetsShowInLauncher: Bool?
        // Carried, unlike `snippetsEnabled`: opening a link grants no permission class of its own.
        var quicklinksEnabled: Bool?
        var quicklinksShowInLauncher: Bool?
        var extensionsShowInLauncher: Bool?
        var quicklinkPassesSelectedText: Bool?
        var quicklinkConfirmsBeforeDelete: Bool?
        // Carried like quicklinks: running a shortcut the user built grants no permission class.
        var appleShortcutsEnabled: Bool?
        // Safe to carry: it silences a prompt rather than granting anything.
        var supportReminders: Bool?
    }

    struct HotkeyBackup: Codable {
        /// Named apart from `commands`: the launcher toggle is the one action with no command row.
        var togglePalette: HotKeyBinding?
        var commands: [String: HotKeyBinding]?
        var apps: [String: HotKeyBinding]?
        var panes: [String: HotKeyBinding]?
        var customCommands: [String: HotKeyBinding]?
        var windowCommands: [String: HotKeyBinding]?
        var quicklinks: [String: HotKeyBinding]?
        var windowLayouts: [String: HotKeyBinding]?
        var windowRooms: [String: HotKeyBinding]?
        var customWindowSizes: [String: HotKeyBinding]?
    }

    struct ApplySummary {
        var settingsFields = 0
        var hotkeys = 0
        var favorites = 0
        var hiddenItems = 0
        var aliases = 0
        var pinnedEmoji = 0
        var customCommands = 0
        var quicklinks = 0
    }
}

// MARK: - Gather / apply (main-actor: reads and writes the live stores)

@MainActor
extension SettingsBackup {
    static func gather(from core: AppCore) -> SettingsBackup {
        let s = core.settings
        var backup = SettingsBackup()
        backup.settings = SettingsData(
            clipboardEnabled: s.clipboardEnabled,
            clipboardRetentionDays: s.clipboardRetention.rawValue,
            clipboardDefaultAction: s.clipboardDefaultAction.rawValue,
            clipboardDisabledApps: s.clipboardDisabledApps,
            launchAtLogin: s.launchAtLogin,
            emojiSkinTone: s.emojiSkinTone.rawValue,
            emojiGridColumns: s.emojiGridColumns.rawValue,
            showInMenuBar: s.showInMenuBar,
            automaticallyCheckForUpdates: s.automaticallyCheckForUpdates,
            popToRootSeconds: s.popToRootTimeout.rawValue,
            escapeKeyBehavior: s.escapeKeyBehavior.rawValue,
            appearance: s.appearance.rawValue,
            language: s.language.rawValue,
            calcNumberStyle: s.calcNumberStyle.rawValue,
            interfaceSize: s.interfaceSize.rawValue,
            compactMode: s.compactMode,
            showFavoritesInCompactMode: s.showFavoritesInCompactMode,
            searchScopes: s.searchScopes,
            launcherShowsSuggestions: s.launcherShowsSuggestions,
            rootSearchSensitivity: s.rootSearchSensitivity.rawValue,
            openOnCursorScreen: s.openOnCursorScreen,
            paletteDraggable: s.paletteDraggable,
            animationsEnabled: s.animationsEnabled,
            fileSearchEnabled: s.fileSearchEnabled,
            fileSearchScopes: s.fileSearchScopes,
            fileSearchIgnorePatterns: s.fileSearchIgnorePatterns,
            fileSearchRemovedDefaultPatterns: s.fileSearchRemovedDefaultPatterns,
            fileSearchShowInLauncher: s.fileSearchShowInLauncher,
            notesEnabled: s.notesEnabled,
            notesRendersMarkdown: s.notesRendersMarkdown,
            notesShowsFormattingBar: s.notesShowsFormattingBar,
            customCommandsEnabled: s.customCommandsEnabled,
            customCommandsShowInLauncher: s.customCommandsShowInLauncher,
            snippetsShowInLauncher: s.snippetsShowInLauncher,
            quicklinksEnabled: s.quicklinksEnabled,
            quicklinksShowInLauncher: s.quicklinksShowInLauncher,
            extensionsShowInLauncher: s.extensionsShowInLauncher,
            quicklinkPassesSelectedText: s.quicklinkPassesSelectedText,
            quicklinkConfirmsBeforeDelete: s.quicklinkConfirmsBeforeDelete,
            appleShortcutsEnabled: s.appleShortcutsEnabled,
            supportReminders: s.supportRemindersEnabled)

        let hk = core.hotKeys
        var hotkeys = HotkeyBackup()
        hotkeys.togglePalette = hk.binding(for: .togglePalette)
        hotkeys.commands = Dictionary(
            uniqueKeysWithValues: CommandID.allCases.compactMap { id in
                id.hotKeyAction.flatMap(hk.binding(for:)).map { (id.rawValue, $0) }
            })
        hotkeys.apps = Dictionary(
            uniqueKeysWithValues: hk.boundBundleIDs.compactMap { id in
                hk.binding(for: .app(bundleID: id)).map { (id, $0) }
            })
        hotkeys.panes = Dictionary(
            uniqueKeysWithValues: hk.boundPaneBundleIDs.compactMap { id in
                hk.binding(for: .settingsPane(bundleID: id)).map { (id, $0) }
            })
        hotkeys.customCommands = Dictionary(
            uniqueKeysWithValues: hk.boundCustomCommandIDs.compactMap { id in
                hk.binding(for: .customCommand(id: id)).map { (id.uuidString.lowercased(), $0) }
            })
        hotkeys.quicklinks = Dictionary(
            uniqueKeysWithValues: hk.boundQuicklinkIDs.compactMap { id in
                hk.binding(for: .quicklink(id: id)).map { (id.uuidString.lowercased(), $0) }
            })
        backup.hotkeys = hotkeys

        backup.customCommands = core.customCommands.commands
        backup.quicklinks = core.quicklinks.quicklinks
        backup.favoriteApps = core.favorites.keys
        backup.hiddenLauncherItems = Array(core.visibility.hiddenItemKeys)
        backup.hiddenLauncherKinds = Array(core.visibility.disabledKinds)
        backup.launcherAliases = core.aliases.aliases
        backup.pinnedEmoji = core.pinnedEmoji.glyphs
        return backup
    }

    @discardableResult
    func apply(to core: AppCore) -> ApplySummary {
        var summary = ApplySummary()
        if let s = settings { summary.settingsFields = applySettings(s, to: core) }
        if let customCommands {
            summary.customCommands = core.customCommandCoordinator.replaceCustomCommands(customCommands)
        }
        // Before the hotkeys, so a restored binding has its quicklink to attach to.
        if let quicklinks {
            summary.quicklinks = core.quicklinkCoordinator.replaceQuicklinks(quicklinks)
        }
        if let hotkeys { summary.hotkeys = applyHotkeys(hotkeys, to: core) }
        if let favoriteApps {
            core.favorites.replace(keys: favoriteApps)
            summary.favorites = favoriteApps.count
        }
        if hiddenLauncherItems != nil || hiddenLauncherKinds != nil {
            let items = hiddenLauncherItems ?? Array(core.visibility.hiddenItemKeys)
            let kinds = hiddenLauncherKinds ?? Array(core.visibility.disabledKinds)
            core.visibility.replace(hiddenItems: items, disabledKinds: kinds)
            summary.hiddenItems = items.count
        }
        if let launcherAliases {
            core.aliases.replace(launcherAliases)
            // Counted after the store, which drops blanks the file may carry.
            summary.aliases = core.aliases.aliases.count
        }
        if let pinnedEmoji {
            core.pinnedEmoji.replace(pinnedEmoji)
            summary.pinnedEmoji = core.pinnedEmoji.glyphs.count
        }
        return summary
    }

    private func applySettings(_ s: SettingsData, to core: AppCore) -> Int {
        let settings = core.settings
        var count = 0
        if let flag = s.clipboardEnabled {
            settings.clipboardEnabled = flag
            count += 1
        }
        if let days = s.clipboardRetentionDays, let retention = ClipboardRetention(rawValue: days) {
            settings.clipboardRetention = retention
            count += 1
        }
        if let apps = s.clipboardDisabledApps {
            settings.clipboardDisabledApps = apps
            count += 1
        }
        if let raw = s.clipboardDefaultAction, let action = ClipboardDefaultAction(rawValue: raw) {
            settings.clipboardDefaultAction = action
            count += 1
        }
        if let launch = s.launchAtLogin {
            settings.launchAtLogin = launch
            count += 1
        }
        if let raw = s.emojiSkinTone, let tone = EmojiSkinTone(rawValue: raw) {
            settings.emojiSkinTone = tone
            count += 1
        }
        if let raw = s.emojiGridColumns, let columns = EmojiGridColumns(rawValue: raw) {
            settings.emojiGridColumns = columns
            count += 1
        }
        if let show = s.showInMenuBar {
            settings.showInMenuBar = show
            count += 1
        }
        if let automaticallyCheck = s.automaticallyCheckForUpdates {
            settings.automaticallyCheckForUpdates = automaticallyCheck
            count += 1
        }
        if let secs = s.popToRootSeconds, let timeout = PopToRootTimeout(rawValue: secs) {
            settings.popToRootTimeout = timeout
            count += 1
        }
        if let raw = s.escapeKeyBehavior, let behavior = EscapeKeyBehavior(rawValue: raw) {
            settings.escapeKeyBehavior = behavior
            count += 1
        }
        if let raw = s.interfaceSize, let size = InterfaceSize(rawValue: raw) {
            settings.interfaceSize = size
            count += 1
        }
        if let raw = s.appearance, let appearance = AppAppearance(rawValue: raw) {
            settings.appearance = appearance
            count += 1
        }
        if let raw = s.language, let language = AppLanguage(rawValue: raw) {
            settings.language = language
            count += 1
        }
        if let raw = s.calcNumberStyle, let style = CalcNumberStyle(rawValue: raw) {
            settings.calcNumberStyle = style
            count += 1
        }
        if let flag = s.compactMode {
            settings.compactMode = flag
            count += 1
        }
        if let flag = s.showFavoritesInCompactMode {
            settings.showFavoritesInCompactMode = flag
            count += 1
        }
        if let scopes = s.searchScopes {
            settings.searchScopes = SearchScopes.normalize(scopes)
            count += 1
        }
        if let flag = s.launcherShowsSuggestions {
            settings.launcherShowsSuggestions = flag
            count += 1
        }
        if let raw = s.rootSearchSensitivity, let sensitivity = SearchSensitivity(rawValue: raw) {
            settings.rootSearchSensitivity = sensitivity
            count += 1
        }
        if let flag = s.openOnCursorScreen {
            settings.openOnCursorScreen = flag
            count += 1
        }
        if let flag = s.paletteDraggable {
            settings.paletteDraggable = flag
            count += 1
        }
        if let flag = s.animationsEnabled {
            settings.animationsEnabled = flag
            count += 1
        }
        // Writing through AppSettings is enough; AppCore's sinks re-project the rest.
        if let flag = s.fileSearchEnabled {
            settings.fileSearchEnabled = flag
            count += 1
        }
        if let scopes = s.fileSearchScopes {
            settings.fileSearchScopes = scopes
            count += 1
        }
        if let patterns = s.fileSearchIgnorePatterns {
            settings.fileSearchIgnorePatterns = patterns
            count += 1
        }
        if let patterns = s.fileSearchRemovedDefaultPatterns {
            settings.fileSearchRemovedDefaultPatterns = patterns
            count += 1
        }
        if let flag = s.fileSearchShowInLauncher {
            settings.fileSearchShowInLauncher = flag
            count += 1
        }
        if let flag = s.notesEnabled {
            settings.notesEnabled = flag
            count += 1
        }
        if let flag = s.notesRendersMarkdown {
            settings.notesRendersMarkdown = flag
            count += 1
        }
        if let flag = s.notesShowsFormattingBar {
            settings.notesShowsFormattingBar = flag
            count += 1
        }
        if let flag = s.customCommandsEnabled {
            settings.customCommandsEnabled = flag
            count += 1
        }
        if let flag = s.customCommandsShowInLauncher {
            settings.customCommandsShowInLauncher = flag
            count += 1
        }
        if let flag = s.snippetsShowInLauncher {
            settings.snippetsShowInLauncher = flag
            count += 1
        }
        if let flag = s.quicklinksEnabled {
            settings.quicklinksEnabled = flag
            count += 1
        }
        if let flag = s.extensionsShowInLauncher {
            settings.extensionsShowInLauncher = flag
            count += 1
        }
        if let flag = s.quicklinksShowInLauncher {
            settings.quicklinksShowInLauncher = flag
            count += 1
        }
        if let flag = s.appleShortcutsEnabled {
            settings.appleShortcutsEnabled = flag
            count += 1
        }
        if let flag = s.quicklinkPassesSelectedText {
            settings.quicklinkPassesSelectedText = flag
            count += 1
        }
        if let flag = s.quicklinkConfirmsBeforeDelete {
            settings.quicklinkConfirmsBeforeDelete = flag
            count += 1
        }
        if let flag = s.supportReminders {
            settings.supportRemindersEnabled = flag
            count += 1
        }
        return count
    }

    private func applyHotkeys(_ hotkeys: HotkeyBackup, to core: AppCore) -> Int {
        let hk = core.hotKeys
        var count = 0
        // Skip an already-claimed binding: the second registration would silently fail.
        func apply(_ binding: HotKeyBinding, _ action: HotKeyAction) {
            guard hk.conflictOwner(of: binding, excluding: action) == nil else { return }
            hk.setBinding(binding, for: action)
            count += 1
        }
        if let b = hotkeys.togglePalette { apply(b, .togglePalette) }
        for (rawID, b) in hotkeys.commands ?? [:] {
            guard let action = CommandID(rawValue: rawID)?.hotKeyAction else { continue }
            apply(b, action)
        }
        for (id, b) in hotkeys.apps ?? [:] { apply(b, .app(bundleID: id)) }
        for (id, b) in hotkeys.panes ?? [:] { apply(b, .settingsPane(bundleID: id)) }
        for (rawID, b) in hotkeys.customCommands ?? [:] {
            guard let id = UUID(uuidString: rawID), core.customCommands.command(id: id) != nil else {
                continue
            }
            apply(b, .customCommand(id: id))
        }
        for (rawID, b) in hotkeys.quicklinks ?? [:] {
            guard let id = UUID(uuidString: rawID), core.quicklinks.quicklink(id: id) != nil else {
                continue
            }
            apply(b, .quicklink(id: id))
        }
        return count
    }
}

// MARK: - Serialization

extension SettingsBackup {
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    init(json: Data) throws {
        self = try JSONDecoder().decode(SettingsBackup.self, from: json)
    }
}
