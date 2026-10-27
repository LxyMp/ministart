import Foundation
import SQLite3

// Spelled as the C macro in sqlite3.h, which isn't imported into Swift.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// SQLite library of authored quicklinks, never deleted. See docs/features/quicklinks.md#storage.
@MainActor
@Observable
final class QuicklinkStore {
    /// Display order is `Quicklink.precedes`: pinned first by pin time, then the rest by name.
    private(set) var quicklinks: [Quicklink] = []
    /// False when the database wouldn't open; every mutation then refuses rather than pretends.
    private(set) var isAvailable = false
    /// Bumped on every group-order write, so views deriving order from `groups()` re-render —
    /// the quicklinks array itself is untouched by a reorder.
    var groupOrderRevision = 0
    var onChange: (([Quicklink]) -> Void)?

    private static let schema = """
        CREATE TABLE IF NOT EXISTS quicklinks(
          id TEXT PRIMARY KEY NOT NULL,
          name TEXT NOT NULL,
          link TEXT NOT NULL,
          open_with TEXT,
          icon TEXT,
          in_root_search INTEGER NOT NULL DEFAULT 1,
          pinned_at REAL,
          created_at REAL NOT NULL,
          is_enabled INTEGER NOT NULL DEFAULT 1
        );
        CREATE TABLE IF NOT EXISTS quicklink_groups(
          name TEXT PRIMARY KEY NOT NULL,
          position INTEGER NOT NULL
        );
        """

    private let dbURL: URL
    @ObservationIgnored private var db: OpaquePointer?
    @ObservationIgnored private var upsertStmt: OpaquePointer?
    @ObservationIgnored private var loadStmt: OpaquePointer?
    @ObservationIgnored private var deleteStmt: OpaquePointer?

    /// `directory` defaults per channel; the harness passes a throwaway one.
    init(directory: URL? = nil) {
        let base = directory ?? Self.defaultDirectory
        dbURL = base.appendingPathComponent("quicklinks.sqlite3")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        isAvailable = openDatabase()
        // A failed open leaves the file alone: this is authored data, so report, never delete.
        if !isAvailable { closeDatabase() }
    }

    /// Under Application Support, the same per-channel root snippets use.
    private static var defaultDirectory: URL {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.ministart.app"
        return FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)
    }

    // Isolated so teardown may touch the main-actor pointers; the release is already on main.
    isolated deinit {
        closeDatabase()
    }

    func load() {
        guard let stmt = loadStmt else { return }
        var loaded: [Quicklink] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let row = Self.row(stmt) { loaded.append(row) }
        }
        sqlite3_reset(stmt)
        quicklinks = loaded.sorted(by: Self.displayOrder)
    }

    /// A disabled quicklink is offered nowhere, so every surface lists this, not `quicklinks`.
    var enabled: [Quicklink] { quicklinks.filter(\.isEnabled) }

    func quicklink(id: UUID) -> Quicklink? {
        quicklinks.first { $0.id == id }
    }

    func quicklink(entryID: String) -> Quicklink? {
        Quicklink.id(fromEntryID: entryID).flatMap(quicklink)
    }

    // Takes a whole draft, so adding an option doesn't churn every call site.
    @discardableResult
    func add(_ draft: Quicklink) throws(QuicklinkError) -> Quicklink {
        var value = try validated(draft)
        // A new link lands at the end of its group: after everything sharing that label.
        if let group = value.group {
            value.position = ((quicklinks.filter { $0.group == group }.compactMap(\.position).max())
                ?? -1) + 1
        }
        try write(value)
        return value
    }

    func update(_ draft: Quicklink) throws(QuicklinkError) {
        guard quicklinks.contains(where: { $0.id == draft.id }) else { return }
        try write(validated(draft))
    }

    func remove(id: UUID) throws(QuicklinkError) {
        guard let stmt = deleteStmt else { throw .storageUnavailable }
        sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
        let status = sqlite3_step(stmt)
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
        guard status == SQLITE_DONE else { throw .storageUnavailable }
        commit(quicklinks.filter { $0.id != id })
    }

    func togglePinned(id: UUID) throws(QuicklinkError) {
        guard var value = quicklink(id: id) else { return }
        value.pinnedAt = value.isPinned ? nil : Date()
        try write(value)
    }

    func setEnabled(_ enabled: Bool, id: UUID) throws(QuicklinkError) {
        guard var value = quicklink(id: id), value.isEnabled != enabled else { return }
        value.isEnabled = enabled
        try write(value)
    }

    func setShowsInRootSearch(_ shows: Bool, id: UUID) throws(QuicklinkError) {
        guard var value = quicklink(id: id), value.showsInRootSearch != shows else { return }
        value.showsInRootSearch = shows
        try write(value)
    }

    /// "Duplicate": a new identity, so references stay with the original, plus a distinct name.
    @discardableResult
    func duplicate(id: UUID) throws(QuicklinkError) -> Quicklink {
        guard let source = quicklink(id: id) else { throw .storageUnavailable }
        return try add(
            Quicklink(
                name: Self.uniqueName(basedOn: source.name, taken: quicklinks.map(\.name)),
                link: source.link, openWithBundleID: source.openWithBundleID,
                iconSymbol: source.iconSymbol, isEnabled: source.isEnabled,
                showsInRootSearch: source.showsInRootSearch, group: source.group))
    }

    // MARK: - Groups

    /// Group names as the links spell them, in the user's saved order.
    /// A group is a first-class row here, so an empty one still exists.
    func groups() -> [String] {
        var names = groupOrder()
        for group in Set(quicklinks.compactMap(\.group)).sorted()
        where !names.contains(where: { $0.caseInsensitiveCompare(group) == .orderedSame }) {
            names.append(group)
        }
        return names
    }

    /// The saved group order; names the links no longer use stay until pruned by a rewrite.
    func groupOrder() -> [String] {
        guard let stmt = prepare("SELECT name FROM quicklink_groups ORDER BY position") else {
            return []
        }
        defer { sqlite3_finalize(stmt) }
        var names: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let name = Self.columnString(stmt, 0) { names.append(name) }
        }
        return names
    }

    /// Rewrites the whole order in one transaction; names missing from the links are dropped,
    /// links whose group is missing from the list gain their group at the end.
    func setGroupOrder(_ names: [String]) {
        guard isAvailable,
            sqlite3_exec(db, "DELETE FROM quicklink_groups", nil, nil, nil) == SQLITE_OK
        else { return }
        var stmt: OpaquePointer?
        guard
            sqlite3_prepare_v2(
                db, "INSERT INTO quicklink_groups(name, position) VALUES(?,?)", -1, &stmt, nil)
                == SQLITE_OK
        else { return }
        defer { sqlite3_finalize(stmt) }
        for (index, name) in names.enumerated() {
            sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 2, Int32(index))
            sqlite3_step(stmt)
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
        }
        groupOrderRevision += 1
    }

    /// Registers a group name at the end of the order, so a fresh create lands last.
    func addGroup(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
            !groups().contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame })
        else { return }
        setGroupOrder(groupOrder() + [trimmed])
    }

    /// Deletes a group: its links return to Default and the order row goes with it.
    /// Without the order-table cleanup the group survives its own deletion — the links
    /// move but the row still names it, and `groups()` reads the row back.
    func deleteGroup(_ name: String) {
        moveLinks(
            ids: Set(quicklinks.filter {
                $0.group?.caseInsensitiveCompare(name) == .orderedSame
            }.map(\.id)), toGroup: nil)
        setGroupOrder(groupOrder().filter {
            $0.caseInsensitiveCompare(name) != .orderedSame
        })
    }

    /// Moves links into a group (nil = Default). No anchor appends to the group's end;
    /// `beforeID`/`afterID` insert the drag right at that neighbour, keeping relative order.
    func moveLinks(
        ids: Set<UUID>, toGroup group: String?, beforeID: UUID? = nil, afterID: UUID? = nil
    ) {
        let target = group?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        if let target, !groups().contains(where: { $0.caseInsensitiveCompare(target) == .orderedSame }) {
            addGroup(target)
        }

        var members = quicklinks.filter { $0.group == target }
        // Same-group drags carry the stored row too — the move is a reorder, not a no-op.
        var moving: [Quicklink] = []
        for id in ids {
            guard let stored = quicklink(id: id) else { continue }
            if let updated = try? validated(stored.withGroup(target)) {
                moving.append(updated)
            }
        }
        // Same-group drags reorder; cross-group drops insert at the anchor neighbour.
        let anchor = beforeID ?? afterID
        if let anchor {
            members.removeAll { link in moving.contains(where: { $0.id == link.id }) }
            if let index = members.firstIndex(where: { $0.id == anchor }) {
                members.insert(contentsOf: moving, at: beforeID != nil ? index : index + 1)
            } else {
                members.append(contentsOf: moving)
            }
        } else {
            members.removeAll { link in moving.contains(where: { $0.id == link.id }) }
            members.append(contentsOf: moving)
        }

        // Renumber the whole group, write each row, and commit one hand-built array.
        var updated = quicklinks
        for (index, value) in members.enumerated() {
            var positioned = value
            positioned.position = index
            if let at = updated.firstIndex(where: { $0.id == value.id }) {
                updated[at] = positioned
            }
            if let stmt = upsertStmt {
                sqlite3_bind_text(stmt, 1, positioned.id.uuidString, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, positioned.name, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 3, positioned.link, -1, SQLITE_TRANSIENT)
                bind(stmt, 4, positioned.openWithBundleID)
                bind(stmt, 5, positioned.iconSymbol)
                sqlite3_bind_int(stmt, 6, positioned.isEnabled ? 1 : 0)
                sqlite3_bind_int(stmt, 7, positioned.showsInRootSearch ? 1 : 0)
                if let pinnedAt = positioned.pinnedAt {
                    sqlite3_bind_double(stmt, 8, pinnedAt.timeIntervalSince1970)
                } else {
                    sqlite3_bind_null(stmt, 8)
                }
                sqlite3_bind_double(stmt, 9, positioned.createdAt.timeIntervalSince1970)
                bind(stmt, 10, positioned.group)
                if let position = positioned.position {
                    sqlite3_bind_int(stmt, 11, Int32(position))
                } else {
                    sqlite3_bind_null(stmt, 11)
                }
                sqlite3_step(stmt)
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
            }
        }
        commit(updated.sorted(by: Self.displayOrder))
    }

    /// Renames every member at once. A colliding name gets a numeric suffix, never a merge:
    /// a rename that silently folded two groups together would read as links vanishing.
    func renameGroup(_ from: String, to proposed: String) {
        let taken = Set(groups().map { $0.folding(options: [.caseInsensitive], locale: .current) })
        let base = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return }
        var target = base
        var suffix = 2
        while taken.contains(target.folding(options: [.caseInsensitive], locale: .current)) {
            target = "\(base) \(suffix)"
            suffix += 1
        }
        for stored in quicklinks where stored.group?.caseInsensitiveCompare(from) == .orderedSame {
            try? update(stored.withGroup(target))
        }
        // The order row follows the rename, keeping the group's place in the sorting sheet.
        setGroupOrder(groupOrder().map {
            $0.caseInsensitiveCompare(from) == .orderedSame ? target : $0
        })
    }

    @discardableResult
    func append(_ incoming: [Quicklink]) -> [Quicklink] {
        var added: [Quicklink] = []
        for candidate in incoming {
            if let stored = try? add(candidate) { added.append(stored) }
        }
        return added
    }

    @discardableResult
    func replace(with incoming: [Quicklink]) -> Int {
        guard isAvailable, sqlite3_exec(db, "DELETE FROM quicklinks", nil, nil, nil) == SQLITE_OK
        else { return 0 }
        commit([])
        return append(Self.sanitized(incoming)).count
    }

    private func write(_ value: Quicklink) throws(QuicklinkError) {
        guard let stmt = upsertStmt else { throw .storageUnavailable }
        sqlite3_bind_text(stmt, 1, value.id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, value.name, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, value.link, -1, SQLITE_TRANSIENT)
        bind(stmt, 4, value.openWithBundleID)
        bind(stmt, 5, value.iconSymbol)
        sqlite3_bind_int(stmt, 6, value.isEnabled ? 1 : 0)
        sqlite3_bind_int(stmt, 7, value.showsInRootSearch ? 1 : 0)
        if let pinnedAt = value.pinnedAt {
            sqlite3_bind_double(stmt, 8, pinnedAt.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(stmt, 8)
        }
        sqlite3_bind_double(stmt, 9, value.createdAt.timeIntervalSince1970)
        bind(stmt, 10, value.group)
        if let position = value.position {
            sqlite3_bind_int(stmt, 11, Int32(position))
        } else {
            sqlite3_bind_null(stmt, 11)
        }
        let status = sqlite3_step(stmt)
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
        guard status == SQLITE_DONE else { throw .storageUnavailable }

        var updated = quicklinks.filter { $0.id != value.id }
        updated.append(value)
        commit(updated.sorted(by: Self.displayOrder))
    }

    private func bind(_ stmt: OpaquePointer, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func commit(_ updated: [Quicklink]) {
        guard updated != quicklinks else { return }
        quicklinks = updated
        onChange?(updated)
    }

    private func validated(_ draft: Quicklink) throws(QuicklinkError) -> Quicklink {
        guard isAvailable else { throw .storageUnavailable }
        var value = draft
        value.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.link = draft.link.trimmingCharacters(in: .whitespacesAndNewlines)
        value.iconSymbol =
            draft.iconSymbol?.trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        value.openWithBundleID =
            draft.openWithBundleID?
            .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        value.group = draft.group?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        guard !value.name.isEmpty else { throw .emptyName }
        guard !value.link.isEmpty else { throw .emptyLink }
        guard !value.name.contains("\0"), !value.link.contains("\0") else {
            throw .invalidCharacter
        }
        // A templated link is only knowable once filled, so it is reported at open time.
        guard
            QuicklinkDestination.containsPlaceholder(value.link)
                || QuicklinkDestination.detect(value.link) != nil
        else { throw .unresolvableLink }
        guard
            !quicklinks.contains(where: {
                $0.id != value.id
                    && $0.name.compare(value.name, options: .caseInsensitive) == .orderedSame
            })
        else { throw .duplicateName }
        return value
    }

    /// Pins first; then, within the same group, the manual position; then the legacy
    /// name order for rows a drag has not numbered yet.
    private static func displayOrder(_ left: Quicklink, _ right: Quicklink) -> Bool {
        switch (left.pinnedAt, right.pinnedAt) {
        case (let l?, let r?) where l != r: return l < r
        case (.some, .none): return true
        case (.none, .some): return false
        default: break
        }
        if let l = left.position, let r = right.position, l != r { return l < r }
        return Quicklink.precedes(left, right)
    }

    private static func uniqueName(basedOn name: String, taken: [String]) -> String {
        let folded = Set(taken.map { $0.folding(options: [.caseInsensitive], locale: .current) })
        var candidate = name + " Copy"
        var suffix = 2
        while folded.contains(candidate.folding(options: [.caseInsensitive], locale: .current)) {
            candidate = "\(name) Copy \(suffix)"
            suffix += 1
        }
        return candidate
    }

    private static func sanitized(_ values: [Quicklink]) -> [Quicklink] {
        var ids = Set<UUID>()
        // Copy-and-clean rather than rebuild, so a new option can never be dropped on import.
        return values.filter { ids.insert($0.id).inserted }
    }

    // MARK: - SQLite

    private func openDatabase() -> Bool {
        guard
            sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
                == SQLITE_OK,
            sqlite3_exec(db, "PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;", nil, nil, nil)
                == SQLITE_OK,
            sqlite3_exec(db, Self.schema, nil, nil, nil) == SQLITE_OK
        else { return false }
        // `IF NOT EXISTS` leaves an older table as it was, so its new column is added by hand.
        sqlite3_exec(
            db, "ALTER TABLE quicklinks ADD COLUMN is_enabled INTEGER NOT NULL DEFAULT 1", nil, nil,
            nil)
        sqlite3_exec(db, "ALTER TABLE quicklinks ADD COLUMN group_name TEXT", nil, nil, nil)
        sqlite3_exec(db, "ALTER TABLE quicklinks ADD COLUMN position INTEGER", nil, nil, nil)
        // After the schema, so a column added later can be indexed the same way.
        sqlite3_exec(
            db,
            "CREATE INDEX IF NOT EXISTS quicklinks_pinned_at ON quicklinks(pinned_at) WHERE pinned_at IS NOT NULL",
            nil, nil, nil)
        upsertStmt = prepare(
            """
            INSERT INTO quicklinks(id, name, link, open_with, icon, is_enabled, in_root_search, pinned_at, created_at, group_name, position)
            VALUES(?,?,?,?,?,?,?,?,?,?,?)
            ON CONFLICT(id) DO UPDATE SET
              name = excluded.name, link = excluded.link, open_with = excluded.open_with,
              icon = excluded.icon, is_enabled = excluded.is_enabled,
              in_root_search = excluded.in_root_search, pinned_at = excluded.pinned_at,
              group_name = excluded.group_name, position = excluded.position
            """
        )
        // Both statements name columns in struct order, which `is_enabled` was appended after.
        loadStmt = prepare(
            """
            SELECT id, name, link, open_with, icon, is_enabled, in_root_search, pinned_at, created_at, group_name, position
            FROM quicklinks
            """
        )
        deleteStmt = prepare("DELETE FROM quicklinks WHERE id = ?")
        return upsertStmt != nil && loadStmt != nil && deleteStmt != nil
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        return stmt
    }

    private func closeDatabase() {
        [upsertStmt, loadStmt, deleteStmt].forEach { sqlite3_finalize($0) }
        upsertStmt = nil
        loadStmt = nil
        deleteStmt = nil
        sqlite3_close_v2(db)
        db = nil
    }

    private static func row(_ stmt: OpaquePointer?) -> Quicklink? {
        guard let idString = columnString(stmt, 0), let id = UUID(uuidString: idString),
            let name = columnString(stmt, 1), let link = columnString(stmt, 2)
        else { return nil }
        return Quicklink(
            id: id, name: name, link: link, openWithBundleID: columnString(stmt, 3),
            iconSymbol: columnString(stmt, 4),
            isEnabled: sqlite3_column_int(stmt, 5) != 0,
            showsInRootSearch: sqlite3_column_int(stmt, 6) != 0,
            pinnedAt: columnDate(stmt, 7),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 8)),
            group: columnString(stmt, 9),
            position: sqlite3_column_type(stmt, 10) == SQLITE_NULL
                ? nil : Int(sqlite3_column_int(stmt, 10)))
    }

    private static func columnDate(_ stmt: OpaquePointer?, _ index: Int32) -> Date? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        return Date(timeIntervalSince1970: sqlite3_column_double(stmt, index))
    }

    private static func columnString(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let ptr = sqlite3_column_text(stmt, index) else { return nil }
        let count = Int(sqlite3_column_bytes(stmt, index))
        return String(decoding: UnsafeBufferPointer(start: ptr, count: count), as: UTF8.self)
    }
}

extension String {
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
