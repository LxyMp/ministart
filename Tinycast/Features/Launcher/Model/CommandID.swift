import Foundation

enum CommandID: String, CaseIterable, Sendable {
    case calculatorHistory = "command:calculator-history"
    case clipboardHistory = "command:clipboard-history"
    case pasteSequentially = "command:paste-sequentially"
    case searchEmoji = "command:search-emoji"
    case searchFiles = "command:search-files"
    case searchMenuItems = "command:search-menu-items"
    case switchWindows = "command:switch-windows"
    case switchWindowsBackwards = "command:switch-windows-backwards"
    case openCamera = "command:open-camera"
    case openInBrowser = "command:open-in-browser"
    case runShellCommand = "command:run-shell-command"
    case createCustomCommand = "command:create-custom-command"
    case searchCustomCommands = "command:search-custom-commands"
    case define = "command:define"
    case showNotes = "command:show-notes"
    case createNote = "command:create-note"
    case searchNotes = "command:search-notes"
    case createWindowLayout = "command:create-window-layout"
    case captureWindowLayout = "command:capture-window-layout"
    case switchRoom = "command:switch-room"
    case createRoom = "command:create-room"
    case createQuicklink = "command:create-quicklink"
    case searchQuicklinks = "command:search-quicklinks"
    case importQuicklinks = "command:import-quicklinks"
    case exportQuicklinks = "command:export-quicklinks"
    case searchSnippets = "command:search-snippets"
    case createSnippet = "command:create-snippet"
    case exportSettings = "command:export-settings"
    case importSettings = "command:import-settings"
    case checkForUpdates = "command:check-for-updates"
    case settings = "command:settings"
    case about = "command:about"
    case support = "command:support"
    case quit = "command:quit"

    var name: String { nameResource.resolved() }

    var englishName: String { nameResource.key }

    private var nameResource: LocalizedStringResource {
        switch self {
        case .calculatorHistory: return "Calculator History"
        case .clipboardHistory: return "Clipboard History"
        case .pasteSequentially: return "Paste Sequentially"
        case .searchEmoji: return "Search Emoji & Symbols"
        case .searchFiles: return "Search Files"
        case .searchMenuItems: return "Search Menu Bar Items"
        case .switchWindows: return "Switch Windows"
        case .switchWindowsBackwards: return "Switch Windows Backwards"
        case .openCamera: return "Open Camera"
        case .openInBrowser: return "Open in Browser"
        case .runShellCommand: return "Run Shell Command"
        case .createCustomCommand: return "Create Custom Command"
        case .searchCustomCommands: return "Search Custom Commands"
        case .define: return "Define Word"
        case .showNotes: return "Show Notes"
        case .createNote: return "Create Note"
        case .searchNotes: return "Search Notes"
        case .createWindowLayout: return "Create Window Layout"
        case .captureWindowLayout: return "Create Layout from Current Windows"
        case .switchRoom: return "Switch Room"
        case .createRoom: return "Create Room"
        case .createQuicklink: return "Create Quicklink"
        case .searchQuicklinks: return "Search Quicklinks"
        case .importQuicklinks: return "Import Quicklinks"
        case .exportQuicklinks: return "Export Quicklinks"
        case .searchSnippets: return "Search Snippets"
        case .createSnippet: return "Create Snippet"
        case .exportSettings: return "Export Backup"
        case .importSettings: return "Import Backup"
        case .checkForUpdates: return "Check for Updates"
        case .settings: return "Ministart Settings"
        case .about: return "About Ministart"
        case .support: return "Support Ministart"
        case .quit: return "Quit Ministart"
        }
    }

    var sfSymbol: String {
        switch self {
        case .calculatorHistory: return "plus.forwardslash.minus"
        case .clipboardHistory: return "doc.on.clipboard"
        case .pasteSequentially: return "list.bullet.clipboard"
        case .searchEmoji: return "face.smiling"
        case .searchFiles: return "doc.text.magnifyingglass"
        case .searchMenuItems: return "menubar.rectangle"
        case .switchWindows, .switchWindowsBackwards: return "macwindow.on.rectangle"
        case .openCamera: return "camera"
        case .openInBrowser: return "globe"
        case .runShellCommand: return "terminal"
        case .createCustomCommand: return "terminal"
        case .searchCustomCommands: return "terminal"
        case .define: return "book.closed"
        case .showNotes: return "text.page"
        case .createNote: return "note.text.badge.plus"
        case .searchNotes: return "text.magnifyingglass"
        case .createWindowLayout: return "plus.rectangle.on.rectangle"
        case .captureWindowLayout: return "macwindow.badge.plus"
        case .switchRoom: return "door.left.hand.open"
        case .createRoom: return "rectangle.stack.badge.plus"
        case .createQuicklink: return "link.badge.plus"
        case .searchQuicklinks: return Quicklink.sfSymbol
        case .importQuicklinks: return "square.and.arrow.down"
        case .exportQuicklinks: return "square.and.arrow.up"
        case .searchSnippets: return "curlybraces"
        case .createSnippet: return "plus.rectangle.on.rectangle"
        case .exportSettings: return "square.and.arrow.up"
        case .importSettings: return "square.and.arrow.down"
        case .checkForUpdates: return "arrow.down.circle"
        case .settings: return "gearshape"
        case .about: return "info.circle"
        case .support: return "heart"
        case .quit: return "power"
        }
    }

    /// Suggested, highest first, until the user's own habits fill the section.
    var suggestionPriority: Int? {
        switch self {
        case .clipboardHistory: 80
        case .searchFiles: 70
        case .searchEmoji: 50
        case .createQuicklink, .createSnippet: 30
        default: nil
        }
    }

    /// Query-driven: the typed text is their input, so they are built where offered, never listed.
    var isQueryDriven: Bool {
        self == .openInBrowser || self == .runShellCommand
    }

    /// A chord carries no query, and none should be able to terminate the app outright.
    var hotKeyAction: HotKeyAction? {
        isQueryDriven || self == .quit ? nil : .command(self)
    }
}
