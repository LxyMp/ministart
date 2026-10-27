import SwiftUI

struct QuicklinksSettingsView: View {
    @Environment(QuicklinkStore.self) private var store
    @Environment(QuicklinkCoordinator.self) private var coordinator
    @Environment(AppSettings.self) private var settings
    @State private var query = ""
    @State private var isAddingGroup = false
    @State private var newGroupName = ""
    /// Which inline field should take focus (and select all), consumed by the onFocusChange.
    @FocusState private var focusedGroupField: GroupField?

    enum GroupField: Hashable {
        case create
        case rename(String)
    }
    @State private var renamingGroup: String?
    @State private var renamedGroupName = ""
    /// Empty groups exist only while a link names them, so a fresh create is held here until
    /// its first member lands (or the window closes and it quietly goes away).
    /// In-place group sorting: the sheet approach fought the Form's own layout, so the
    /// library itself becomes the sorting surface until confirmed.
    @State private var isSortingGroups = false
    @State private var droppedIDs: Set<UUID> = []
    @State private var linkFrames: [UUID: CGRect] = [:]
    @State private var dropTargetGroup: String?? = nil
    /// Collapsed groups this session; a fresh group starts expanded.
    @State private var collapsedGroups: Set<String> = []
    /// The Default group (a nil label) collapses under this sentinel key.
    private let defaultGroupKey = "ministart.default-group"
    /// The key window's field editor, when a group field owns it — for select-all on focus.
    private var focusedGroupTextField: NSTextView? {
        let responder = NSApp.keyWindow?.firstResponder
        return responder as? NSTextView
    }

    /// Marks a drag as a quicklink move, so foreign payloads can't reshape groups.
    private let groupDragToken = "ministart.quicklink.move"

    /// Moves a named group one slot up or down. The order starts from the groups that
    /// actually exist (the order table may never have seen them), so the buttons work on
    /// groups created by link moves or imports without a prior explicit add.
    private func moveGroup(_ name: String, offset: Int) {
        var order = store.groups()
        guard let index = order.firstIndex(
            where: { $0.caseInsensitiveCompare(name) == .orderedSame })
        else { return }
        let target = index + offset
        guard (0..<order.count).contains(target) else { return }
        order.swapAt(index, target)
        store.setGroupOrder(order)
    }

    var body: some View {
        @Bindable var settings = settings
        return Form {
            FeatureSwitchSection(
                anchor: .quicklinksQuicklinks,
                enableTitle: "Enable quicklinks",
                enableSubtitle: "Open saved links and searches from the launcher.",
                isEnabled: $settings.quicklinksEnabled,
                showsInLauncher: $settings.quicklinksShowInLauncher,
                showsIcon: true,
                showsHeader: false)

            Group {
                if !store.isAvailable { storageNotice }
                FeatureCommandsSection(owner: .quicklinks, anchor: .quicklinksCommands)
                library
                behaviour
                transfer
            }
            .settingsEnabled(settings.quicklinksEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.quicklinks)
    }

    // MARK: - Sections

    private var storageNotice: some View {
        Section {
            Label(
                "Changes can't be saved: the database couldn't be opened. Its file is untouched.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var library: some View {
        Section {
            HStack {
                if !store.quicklinks.isEmpty {
                    SettingsFilterField(prompt: "Search quicklinks…", query: $query)
                }
                Spacer(minLength: Theme.Spacing.lg)
                Button {
                    coordinator.editQuicklink(nil)
                } label: {
                    SettingsRowTitle(.quicklinksQuicklinks, "Add Link")
                }
                Button {
                    isAddingGroup = true
                    newGroupName = ""
                } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "folder.badge.plus")
                        SettingsRowTitle(.quicklinksGroups, "Add Group")
                    }
                }
                .disabled(isAddingGroup || isSortingGroups)
                if isSortingGroups {
                    Button(role: .destructive) {
                        finishGroupSorting()
                    } label: {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "checkmark")
                            SettingsRowTitle(.quicklinksGroups, "Confirm Order")
                        }
                    }
                    .keyboardShortcut(.cancelAction)
                } else {
                    Button {
                        isSortingGroups = true
                        collapsedGroups.formUnion(sections.map { $0.name ?? defaultGroupKey })
                    } label: {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "arrow.up.arrow.down")
                            SettingsRowTitle(.quicklinksGroups, "Sort Groups")
                        }
                    }
                    .disabled(store.groups().isEmpty)
                }
            }
            .settingsAnchor(.quicklinksGroups)
            if isAddingGroup {
                newGroupRow
                    .focused($focusedGroupField, equals: .create)
            }

            if sections.isEmpty {
                Text(store.quicklinks.isEmpty ? "No quicklinks yet." : "No quicklink matches “\(query)”.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sections, id: \.name) { section in
                    if isSortingGroups {
                        groupHeader(section, allowsMove: section.name != nil)
                    } else {
                        groupHeader(section)
                    }
                    if !isSortingGroups {
                        ForEach(
                            collapsedGroups.contains(section.name ?? defaultGroupKey) ? [] : section.links
                        ) { quicklink in
                        QuicklinkSettingsRow(
                            quicklink: quicklink,
                            isEnabled: Binding(
                                get: { quicklink.isEnabled },
                                set: {
                                    coordinator.setQuicklinkEnabled($0, id: quicklink.id)
                                }),
                            groups: store.groups(),
                            onMoveToGroup: { group in
                                store.moveLinks(ids: [quicklink.id], toGroup: group)
                            },
                            onEdit: { coordinator.editQuicklink(quicklink) },
                            onDelete: {
                                Task { await coordinator.deleteQuicklink(id: quicklink.id, alwaysConfirm: true) }
                            })
                        .padding(.leading, Theme.Spacing.lg)
                        .onDrag {
                            droppedIDs = [quicklink.id]
                            return NSItemProvider(object: quicklink.id.uuidString as NSString)
                        }
                        .dropDestination(for: String.self) { payload, location in
                            return dropOnLink(payload: payload, location: location, onto: quicklink)
                        } isTargeted: { _ in true }
                        .onGeometryChange(for: CGRect.self) {
                            $0.frame(in: .global)
                        } action: {
                            linkFrames[quicklink.id] = $0
                        }
                        }
                    }
                }
            }
        } header: {
            SettingsSectionHeader(.quicklinksQuicklinks)
        }
    }

    private var behaviour: some View {
        @Bindable var settings = settings
        return Section {
            Toggle(isOn: $settings.quicklinkPassesSelectedText) {
                SettingsRowTitle(.quicklinksBehaviour, "Pass selected text as argument")
                Text("Fills the first argument when a shortcut opens the quicklink.")
            }
            Toggle(isOn: $settings.quicklinkConfirmsBeforeDelete) {
                SettingsRowTitle(.quicklinksBehaviour, "Confirm before deleting")
                Text("From the launcher's Actions menu.")
            }
        } header: {
            SettingsSectionHeader(.quicklinksBehaviour)
        }
    }

    private var transfer: some View {
        Section {
            LabeledContent {
                Button("Import…") { Task { await coordinator.importQuicklinks() } }
            } label: {
                SettingsRowTitle(.quicklinksImportExport, "Import quicklinks")
                Text("From a JSON file; duplicates are skipped.")
            }
            LabeledContent {
                Button("Export…") { Task { await coordinator.exportQuicklinks() } }
                    .disabled(store.quicklinks.isEmpty)
            } label: {
                SettingsRowTitle(.quicklinksImportExport, "Export quicklinks")
                Text("To a JSON file.")
            }
        } header: {
            SettingsSectionHeader(.quicklinksImportExport)
        }
    }

    /// Dropping a drag on a link places it **after** that link — always, within or across
    /// groups. Dropping on a group header places it at that group's end.
    private func dropOnLink(
        payload: [String], location: CGPoint, onto target: Quicklink
    ) -> Bool {
        guard let draggedID = payload.first.flatMap(UUID.init(uuidString:)),
            draggedID != target.id
        else { return false }
        let ids: Set<UUID> = [draggedID]
        let anchor = target.id
        let targetGroup = target.group
        droppedIDs = []
        // The drag ghost hangs until this handler returns, so the return must be the FIRST
        // thing after the local move — the SQLite write and AppIndex fan out afterwards.
        Task { @MainActor in
            store.moveLinks(ids: ids, toGroup: targetGroup, afterID: anchor)
        }
        return true
    }

    /// The store already publishes display order, so filtering keeps pins at the top.
    private var results: [Quicklink] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return store.quicklinks }
        return store.quicklinks.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.link.localizedCaseInsensitiveContains(trimmed)
        }
    }

    /// Default (nil) leads, then the groups in the user's saved order; within a group the
    /// store's display order stands. A link whose group was pruned lands in a trailing section.
    private var sections: [(name: String?, links: [Quicklink])] {
        _ = store.groupOrderRevision  // a reorder touches nothing else observable
        let grouped = Dictionary(grouping: results) { $0.group }
        var output = [(name: String?, links: [Quicklink])]()
        if let links = grouped[nil], !links.isEmpty { output.append((nil, links)) }
        // A link whose group no longer exists in the order table lands in a sorted tail section.
        let orphans = grouped.keys.compactMap { $0 }.filter { group in
            !store.groups().contains(where: { $0.caseInsensitiveCompare(group) == .orderedSame })
        }
        var seen = Set<String>()
        for group in store.groups() + orphans.sorted()
        where seen.insert(group.lowercased()).inserted {
            output.append((group, grouped[group] ?? []))
        }
        return output
    }

    /// The create-group row: a folder glyph and a plain field, reading as a group being named.
    @ViewBuilder
    private var newGroupRow: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            TextField("Group name", text: $newGroupName)
                .textFieldStyle(.plain)
                .onSubmit { commitNewGroup() }
                .onExitCommand { isAddingGroup = false; newGroupName = "" }
        }
        .padding(.vertical, Theme.Spacing.xs)
        .task {
            focusedGroupField = .create
            DispatchQueue.main.async {
                if let editor = focusedGroupTextField {
                    editor.selectAll(nil)
                }
            }
        }
    }

    @ViewBuilder
    private func groupHeader(
        _ section: (name: String?, links: [Quicklink]), allowsMove: Bool = false
    ) -> some View {
        let isDefault = section.name == nil
        let isRenaming = !isDefault && renamingGroup == section.name
        let isCollapsed = collapsedGroups.contains(section.name ?? defaultGroupKey)
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "chevron.right")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isCollapsed ? 0 : 90))
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            if isRenaming {
                TextField("Group name", text: $renamedGroupName)
                    .textFieldStyle(.plain)
                    .focused($focusedGroupField, equals: .rename(section.name ?? ""))
                    .onSubmit { renameGroup(section.name ?? "", to: renamedGroupName) }
                    .onExitCommand { renamingGroup = nil; renamedGroupName = "" }
                    .task {
                        focusedGroupField = .rename(section.name ?? "")
                        DispatchQueue.main.async {
                            if let editor = focusedGroupTextField {
                                editor.selectAll(nil)
                            }
                        }
                    }
            } else {
                Text(isDefault ? String(localized: "Default") : section.name ?? "")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if allowsMove {
                Button {
                    moveGroup(section.name ?? "", offset: -1)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(GroupMoveButtonStyle())
                .help(Text("Move group up"))
                .disabled(store.groups().first == section.name)
                Button {
                    moveGroup(section.name ?? "", offset: 1)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(GroupMoveButtonStyle())
                .help(Text("Move group down"))
                .disabled(store.groups().last == section.name)
            }
            if !isDefault && !isRenaming && !isSortingGroups {
                Button {
                    renamingGroup = section.name
                    renamedGroupName = section.name ?? ""
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                .help(Text("Rename group"))
                Button {
                    Task {
                        if let name = section.name,
                            await coordinator.confirmGroupRemoval(name: name, count: section.links.count)
                        {
                            removeGroup(name)
                        }
                    }
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help(Text("Delete group"))
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
        .contentShape(.rect)
        .modifier(GroupHeaderGestures(
            section: section, isEnabled: !isRenaming && !isSortingGroups,
            isDefault: isDefault, defaultGroupKey: defaultGroupKey,
            collapsedGroups: $collapsedGroups, droppedIDs: $droppedIDs,
            groupDragToken: groupDragToken, store: store,
            dropTargetGroup: $dropTargetGroup))
    }

    /// Leaves sorting mode: everything re-expands and the chevrons return.
    private func finishGroupSorting() {
        isSortingGroups = false
        collapsedGroups.removeAll()
    }

    private func commitNewGroup() {
        focusedGroupField = nil
        let name = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            let taken = Set(store.groups().map {
                $0.folding(options: [.caseInsensitive], locale: .current)
            })
            var candidate = name
            var suffix = 2
            while taken.contains(candidate.lowercased()) {
                candidate = "\(name) \(suffix)"
                suffix += 1
            }
            store.addGroup(candidate)
        }
        isAddingGroup = false
        newGroupName = ""
    }

    private func renameGroup(_ group: String, to proposed: String) {
        focusedGroupField = nil
        let trimmed = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        renamingGroup = nil
        renamedGroupName = ""
        guard !trimmed.isEmpty else { return }
        store.renameGroup(group, to: trimmed)
    }

    private func removeGroup(_ group: String) {
        store.deleteGroup(group)
    }
}

private struct QuicklinkSettingsRow: View {
    let quicklink: Quicklink
    @Binding var isEnabled: Bool
    let groups: [String]
    let onMoveToGroup: (String?) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var pickingGroup = false

    var body: some View {
        SettingsRow(title: quicklink.name, subtitle: quicklink.link) {
            SymbolImage(
                name: quicklink.symbol,
                size: Theme.Size.settingsRowIcon - Theme.Spacing.xs
            )
            .frame(width: SettingsListMetrics.iconSize, height: SettingsListMetrics.iconSize)
        } trailing: {
            if quicklink.isPinned {
                Image(systemName: "pin.fill")
                    .foregroundStyle(.secondary)
                    .help(Text("Pinned to the top"))
            }
            if !quicklink.showsInRootSearch {
                Image(systemName: "eye.slash")
                    .foregroundStyle(.secondary)
                    .help(Text("Hidden from root search"))
            }

            // An alias only reaches the ranker through the root-search slice, so it dims with it.
            AliasField(key: quicklink.entryID, name: quicklink.name)
                .settingsEnabled(quicklink.isEnabled && quicklink.showsInRootSearch)

            // A disabled quicklink's shortcut fires into the funnel's refusal, so it dims too.
            ShortcutRecorder(action: .quicklink(id: quicklink.id))
                .settingsEnabled(quicklink.isEnabled)

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .help(Text("Edit Quicklink"))
            .accessibilityLabel("Edit \(quicklink.name)")

            Button {
                pickingGroup = true
            } label: {
                Image(systemName: "folder.badge.gearshape")
            }
            .buttonStyle(.plain)
            .help(Text("Move to group"))
            .accessibilityLabel("Move \(quicklink.name) to a group")
            .popover(isPresented: $pickingGroup, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        onMoveToGroup(nil)
                        pickingGroup = false
                    } label: {
                        Label("Default", systemImage: quicklink.group == nil ? "checkmark" : "folder")
                    }
                    .buttonStyle(.plain)
                    .padding(Theme.Spacing.md)
                    ForEach(groups, id: \.self) { group in
                        Button {
                            onMoveToGroup(group)
                            pickingGroup = false
                        } label: {
                            Label(
                                group,
                                systemImage: quicklink.group == group ? "checkmark" : "folder")
                        }
                        .buttonStyle(.plain)
                        .padding(Theme.Spacing.md)
                    }
                }
                .frame(width: 220)
            }

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help(Text("Delete Quicklink"))
            .accessibilityLabel("Delete \(quicklink.name)")

            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .help(Text("Enabled"))
                .accessibilityLabel("Enable \(quicklink.name)")
        }
    }
}


/// The header's tap-to-collapse and link-drop target, **skipped entirely in sorting mode** —
/// a registered drop destination answers every drop before the sorting one higher up can,
/// which is what made group reordering inert.
private struct GroupHeaderGestures: ViewModifier {
    let section: (name: String?, links: [Quicklink])
    let isEnabled: Bool
    let isDefault: Bool
    let defaultGroupKey: String
    @Binding var collapsedGroups: Set<String>
    @Binding var droppedIDs: Set<UUID>
    let groupDragToken: String
    let store: QuicklinkStore
    @Binding var dropTargetGroup: String??

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .onTapGesture {
                    let key = section.name ?? defaultGroupKey
                    if collapsedGroups.contains(key) {
                        collapsedGroups.remove(key)
                    } else {
                        collapsedGroups.insert(key)
                    }
                }
                .dropDestination(for: String.self) { payload, _ in
                    // The drag registered the id in `droppedIDs`; the payload is the id itself,
                    // so a session whose state raced still resolves.
                    let delivered = payload.first ?? ""
                    guard delivered == groupDragToken || droppedIDs.count == 1 else {
                        return false
                    }
                    if droppedIDs.isEmpty, let id = UUID(uuidString: delivered) {
                        droppedIDs = [id]
                    }
                    guard !droppedIDs.isEmpty else { return false }
                    let ids = droppedIDs
                    let target = isDefault ? nil : section.name
                    droppedIDs = []
                    // Same contract: return first, persist second. The ghost follows the return.
                    Task { @MainActor in
                        store.moveLinks(ids: ids, toGroup: target)
                    }
                    return true
                } isTargeted: { targeted in
                    dropTargetGroup = targeted ? section.name : nil
                }
        } else {
            content
        }
    }
}


/// A move button with a visible press **and** hover state: trackpad taps never hold
/// `isPressed` long enough to read, so hovering already lights the pill up. Disabled is
/// unmistakable — the glyph drops to a quarter opacity no hover or press can lift.
struct GroupMoveButtonStyle: ButtonStyle {
    @State private var hovered = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground(configuration: configuration))
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(fill(configuration: configuration))
            )
            .opacity(isEnabled ? 1 : 0.25)
            // One animation keyed on both states: separate `.animation(value:)` modifiers
            // race when a trackpad tap flips hover and press on the same frame. Disabled
            // changes opacity with no animation by design — a hard cut reads as "off".
            .animation(
                .easeOut(duration: 0.12),
                value: hovered == configuration.isPressed)
            .onHover { hovered = $0 }
    }

    private func foreground(configuration: Configuration) -> Color {
        guard isEnabled else { return .secondary }
        return configuration.isPressed ? Color.accentColor : Color.secondary
    }

    private func fill(configuration: Configuration) -> Color {
        guard isEnabled else { return .clear }
        if configuration.isPressed { return Color.accentColor.opacity(0.15) }
        return hovered ? Color.primary.opacity(0.08) : Color.clear
    }
}
