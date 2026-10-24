import Foundation

struct SettingsSearchEntry: Identifiable, Hashable, Sendable {
    let tab: SettingsTab
    /// Where picking this result lands; nil for the pane itself, which is its own result.
    let target: SettingsTarget?
    let title: String
    let keywords: [String]

    /// Taking the pane from the target is what makes a row filed under the wrong pane unwritable.
    private init(_ target: SettingsTarget, _ title: String, _ keywords: [String]) {
        self.tab = target.tab
        self.target = target
        self.title = title
        self.keywords = keywords
    }

    /// One setting, which its pane marks with a matching `SettingsRowTitle`.
    init(_ anchor: SettingsAnchor, _ title: LocalizedStringResource, keywords: [String] = []) {
        let localized = title.resolved()
        self.init(.row(anchor, localized), localized, keywords + [title.key])
    }

    /// A whole group, for a result no single row answers — a list, or a section's master switch.
    init(group anchor: SettingsAnchor, _ title: LocalizedStringResource, keywords: [String] = []) {
        self.init(.section(anchor), title.resolved(), keywords + [title.key])
    }

    init(pane: SettingsTab, keywords: [String] = []) {
        self.tab = pane
        self.target = nil
        self.title = pane.title
        self.keywords = keywords
    }

    var anchor: SettingsAnchor? { target?.anchor }

    var id: String { "\(tab.title)/\(anchor?.title ?? "")/\(title)" }

    var breadcrumb: String {
        guard let anchor, anchor.title != tab.title else { return tab.title }
        return "\(tab.title) › \(anchor.title)"
    }
}

/// What Settings offers to search. Hand-written: a `Form` can't be asked what rows it holds, so a
/// new row is searchable only once it is listed here.
enum SettingsSearchCatalog {
    struct Query: Sendable {
        let terms: [FuzzyMatch.Query]

        init(_ raw: String) {
            terms = raw.split(whereSeparator: \Character.isWhitespace).map {
                FuzzyMatch.Query(String($0))
            }
        }

        var isEmpty: Bool { terms.isEmpty }
    }

    static func results(for raw: String, limit: Int = 50) -> [SettingsSearchEntry] {
        let query = Query(raw)
        guard !query.isEmpty else { return [] }
        // Catalog order is the tie-break, so results don't reshuffle between equal-scoring rows.
        return
            entries
            .enumerated()
            .compactMap { item -> (entry: SettingsSearchEntry, score: Int, rank: Int)? in
                guard let score = score(query, item.element) else { return nil }
                return (item.element, score, item.offset)
            }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.rank < $1.rank }
            .prefix(limit)
            .map(\.entry)
    }

    /// Every term must land somewhere; a term matched in the title outranks one found off it.
    private static func score(_ query: Query, _ entry: SettingsSearchEntry) -> Int? {
        var titleScore = 0
        var titleMatches = 0
        for term in query.terms {
            if let match = FuzzyMatch.match(term, candidate: entry.title) {
                titleMatches += 1
                titleScore += match.score
                continue
            }
            guard
                entry.keywords.contains(where: { FuzzyMatch.match(term, candidate: $0) != nil })
                    || FuzzyMatch.match(term, candidate: entry.breadcrumb) != nil
            else { return nil }
        }

        let band: Int
        if titleMatches == query.terms.count {
            band = 2_000_000
        } else if titleMatches > 0 {
            band = 1_000_000
        } else {
            band = 0
        }
        // A pane outranks its own rows, so a bare "clipboard" lands on the pane rather than a row.
        return band + titleScore + (entry.anchor == nil ? 500_000 : 0)
    }

    // MARK: - The index
    // Pane order, then section order within a pane, so this reads as a table of contents.

    static let entries: [SettingsSearchEntry] =
        general + applications + systemSettings + commands + quicklinks
        + appleShortcuts + fallbacks + clipboard + snippets + fileSearch
        + notes + emoji + extensions + permissions
        + backup + about

    private static let general: [SettingsSearchEntry] = [
        .init(pane: .general, keywords: ["preferences", "settings"]),
        .init(
            .generalGlobalShortcuts, "Show Launcher",
            keywords: ["hotkey", "shortcut", "summon", "palette"]),
        .init(
            .generalGeneral, "Language",
            keywords: ["localization", "translation", "locale", "region"]),
        .init(
            .generalGeneral, "Launch at login",
            keywords: ["startup", "login item", "start", "boot"]),
        .init(
            .generalGeneral, "Show in menu bar",
            keywords: ["menubar", "status item", "icon", "hide"]),
        .init(
            .generalGeneral, "Pop to Root Search",
            keywords: ["reset", "timeout", "back"]),
        .init(
            .generalGeneral, "Escape Key Behavior",
            keywords: ["escape", "esc", "back", "close", "navigate"]),
        .init(
            .generalAppearance, "Appearance",
            keywords: ["dark", "light", "mode", "theme"]),
        .init(
            .generalAppearance, "Show animations",
            keywords: ["motion", "transitions", "reduce motion", "effects", "instant"]),
        .init(
            .generalAppearance, "Interface size",
            keywords: ["text size", "font size", "scale", "zoom", "bigger", "larger", "legible"]),
        .init(
            .generalAppearance, "Window mode",
            keywords: ["compact", "expanded", "slim", "search bar", "small"]),
        .init(
            .generalAppearance, "Show favorites in compact mode",
            keywords: ["pinned", "apps", "compact"]),
        .init(
            .generalAppearance, "Follow the cursor across displays",
            keywords: ["monitor", "screen", "pointer", "multi display"]),
        .init(
            .generalAppearance, "Drag to move the launcher",
            keywords: ["move", "position", "window"]),
        .init(
            .generalSearch, "Show suggestions",
            keywords: ["frequent", "recent", "recommended", "empty", "root search"]),
        .init(
            .generalSearch, "Search sensitivity",
            keywords: ["fuzzy", "strict", "loose", "matching", "typo", "root search"]),
        .init(
            .generalSearch, "Learned ranking",
            keywords: ["reset", "history", "order", "privacy"])
    ]

    private static let applications: [SettingsSearchEntry] = [
        .init(pane: .applications, keywords: ["apps", "index", "launcher"]),
        .init(
            .applicationsApplications, "Enable Applications",
            keywords: ["hide apps", "visibility"]),
        .init(
            group: .applicationsSearchScopes, "Search Scopes",
            keywords: ["folders", "indexed", "locations", "add folder"]),
        .init(
            group: .applicationsApplications, "Aliases and shortcuts",
            keywords: ["alias", "hotkey", "per app", "hide"])
    ]

    private static let systemSettings: [SettingsSearchEntry] = [
        .init(
            pane: .systemSettings,
            keywords: ["panes", "preferences", "macos"]),
        .init(
            .systemSettingsSystemSettings, "Enable System Settings",
            keywords: ["hide panes", "visibility"])
    ]

    private static let commands: [SettingsSearchEntry] = [
        .init(
            pane: .commands,
            keywords: ["custom", "script", "shell", "terminal"]),
        .init(
            .commandsCommands, "Enable Commands",
            keywords: ["hide", "visibility"]),
        .init(
            .commandsCustomCommands, "Enable custom commands",
            keywords: ["script", "shell"]),
        .init(
            .commandsCustomCommands, "Add Custom Command",
            keywords: ["new", "script", "shell", "shortcut"])
    ]

    private static let quicklinks: [SettingsSearchEntry] = [
        .init(pane: .quicklinks, keywords: ["url", "bookmark", "link"]),
        .init(
            .quicklinksQuicklinks, "Enable quicklinks",
            keywords: ["url", "bookmark"]),
        .init(
            .quicklinksQuicklinks, "Add Quicklink",
            keywords: ["new", "url", "bookmark", "alias"]),
        .init(
            group: .quicklinksCommands, "Quicklink commands",
            keywords: ["shortcut", "launcher", "search", "import", "export"]),
        .init(
            .quicklinksBehaviour, "Pass selected text as argument",
            keywords: ["selection", "hotkey", "shortcut", "argument"]),
        .init(
            .quicklinksBehaviour, "Confirm before deleting",
            keywords: ["ask", "delete", "prompt"]),
        .init(
            .quicklinksImportExport, "Import quicklinks",
            keywords: ["json", "restore"]),
        .init(
            .quicklinksImportExport, "Export quicklinks",
            keywords: ["json", "backup"])
    ]

    private static let appleShortcuts: [SettingsSearchEntry] = [
        .init(pane: .appleShortcuts, keywords: ["shortcuts app", "automation", "workflow"]),
        .init(
            .appleShortcutsAppleShortcuts, "Enable Apple Shortcuts",
            keywords: ["shortcuts app", "automation", "workflow"]),
        .init(
            group: .appleShortcutsShortcuts, "Aliases and shortcuts",
            keywords: ["alias", "hotkey", "hide"])
    ]

    private static let fallbacks: [SettingsSearchEntry] = [
        .init(
            pane: .fallbacks,
            keywords: ["no results", "empty", "search web", "order"])
    ]

    private static let fileSearch: [SettingsSearchEntry] = [
        .init(
            pane: .fileSearch,
            keywords: ["files", "folders", "find", "disk"]),
        .init(
            .fileSearchFileSearch, "Enable File Search",
            keywords: ["index", "disk", "show in launcher", "root search"]),
        .init(
            group: .fileSearchFullDiskAccess, "Full Disk Access",
            keywords: ["permission", "privacy", "grant", "fda"]),
        .init(
            group: .fileSearchIndex, "File index",
            keywords: ["rebuild", "refresh", "reindex", "indexed files"]),
        .init(
            group: .fileSearchCommands, "File search commands",
            keywords: ["shortcut", "launcher"]),
        .init(
            group: .fileSearchSearchScopes, "Search Scopes",
            keywords: ["folders", "locations", "home", "whole disk", "add folder"]),
        .init(
            group: .fileSearchIgnorePatterns, "Ignore Patterns",
            keywords: ["exclude", "glob", "node_modules", "skip", "ignore folder"])
    ]

    private static let notes: [SettingsSearchEntry] = [
        .init(pane: .notes, keywords: ["markdown", "scratchpad", "floating"]),
        .init(
            .notesNotes, "Enable Notes",
            keywords: ["markdown", "scratchpad"]),
        .init(
            .notesOptions, "Render Markdown",
            keywords: ["markdown", "formatting", "preview", "raw", "source"]),
        .init(
            .notesOptions, "Show Formatting Bar",
            keywords: ["toolbar", "format bar", "buttons", "bold", "heading", "markdown"]),
        .init(
            .notesOptions, "Notes Folder",
            keywords: ["location", "path", "dotfiles", "files", "markdown"]),
        .init(
            group: .notesCommands, "Notes commands",
            keywords: ["shortcut", "new note", "search notes"])
    ]

    private static let snippets: [SettingsSearchEntry] = [
        .init(
            pane: .snippets,
            keywords: ["expansion", "keyword", "text replacement", "template"]),
        .init(
            .snippetsSnippets, "Enable snippets",
            keywords: ["expansion", "keystrokes", "accessibility"]),
        .init(
            group: .snippetsCommands, "Snippet commands",
            keywords: ["shortcut", "hotkey", "launcher", "browser"]),
        .init(
            .snippetsLibrary, "New Snippet",
            keywords: ["add", "keyword", "expansion"]),
        .init(
            .snippetsLibrary, "Snippets Folder",
            keywords: ["reveal", "finder", "markdown", "files", "location", "path", "dotfiles"])
    ]

    private static let clipboard: [SettingsSearchEntry] = [
        .init(
            pane: .clipboard,
            keywords: ["paste", "history", "copy", "pasteboard"]),
        .init(
            .clipboardClipboard, "Enable Clipboard History",
            keywords: ["disable", "turn off", "monitor", "record", "privacy"]),
        .init(
            group: .clipboardCommands, "Clipboard commands",
            keywords: ["shortcut", "hotkey", "launcher", "paste", "browser"]),
        .init(
            .clipboardHistory, "Keep history for",
            keywords: ["retention", "delete", "privacy", "expire"]),
        .init(
            .clipboardHistory, "Default action",
            keywords: ["enter", "return", "paste", "copy", "primary"]),
        .init(
            group: .clipboardDisabledApplications, "Excluded Applications",
            keywords: ["exclude", "password manager", "ignore", "privacy"]),
        .init(
            .clipboardDisabledApplications, "Clear history",
            keywords: ["delete", "erase", "wipe"])
    ]

    private static let emoji: [SettingsSearchEntry] = [
        .init(
            pane: .emoji,
            keywords: ["picker", "character", "unicode", "smiley"]),
        .init(
            group: .emojiCommands, "Emoji commands",
            keywords: ["shortcut", "hotkey", "launcher", "picker"]),
        .init(
            .emojiAppearance, "Emoji Skin Tone",
            keywords: ["colour", "color", "fitzpatrick", "default"]),
        .init(
            .emojiAppearance, "Column Count",
            keywords: ["columns", "density", "zoom", "six", "eight", "ten"])
    ]

    private static let extensions: [SettingsSearchEntry] = [
        .init(
            pane: .extensions,
            keywords: ["raycast", "plugins", "store", "javascript"]),
        .init(
            .extensionsExtensions, "Enable extensions",
            keywords: ["raycast", "third party", "javascript"]),
        .init(
            .extensionsInstall, "Search extensions",
            keywords: ["store", "browse", "install"]),
        .init(
            .extensionsInstall, "Install from GitHub",
            keywords: ["source", "build", "repository", "package manager", "pnpm", "npm", "yarn", "bun"]),
        .init(
            .extensionsInstall, "Import from Raycast",
            keywords: ["migrate", "existing"]),
        .init(
            .extensionsInstall, "Add from folder",
            keywords: ["local", "develop", "sideload"]),
        .init(
            group: .extensionsInstalled, "Installed extensions",
            keywords: [
                "library", "uninstall", "update", "preferences", "appearance", "alias", "shortcut"
            ]),
        .init(
            group: .extensionsCompatibility, "Compatibility",
            keywords: ["supported", "unsupported", "raycast api"]),
        .init(
            .extensionsStorage, "Leftover files",
            keywords: ["clean up", "disk", "reclaim", "cache"])
    ]

    private static let permissions: [SettingsSearchEntry] = [
        .init(
            pane: .permissions,
            keywords: ["privacy", "tcc", "access", "grant"]),
        .init(
            .permissionsAccessibility, "Accessibility",
            keywords: ["paste", "keystrokes", "privacy", "grant"]),
        .init(
            .permissionsFullDiskAccess, "Full Disk Access",
            keywords: ["files", "folders", "uninstall", "leftovers", "privacy", "grant", "fda"]),
    ]

    private static let backup: [SettingsSearchEntry] = [
        .init(
            pane: .backup,
            keywords: ["export", "import", "restore", "migrate"]),
        .init(
            .backupExport, "Export Backup",
            keywords: ["save", "tinycast file", "archive"]),
        .init(
            .backupImport, "Backup File",
            keywords: ["restore", "choose", "tinycast file"]),
        .init(
            .backupSettingsFile, "Sync settings file",
            keywords: ["settings.json", "config", "json", "dotfiles", ".config", "edit"])
    ]

    private static let about: [SettingsSearchEntry] = [
        .init(
            pane: .about,
            keywords: ["version", "licence", "license", "credits"]),
    ]
}
