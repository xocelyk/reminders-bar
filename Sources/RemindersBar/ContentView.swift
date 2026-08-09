import AppKit
import EventKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: RemindersStore
    @State private var query = ""
    @State private var backlogExpanded = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            switch store.access {
            case .granted:
                reminderList
            case .denied:
                deniedView
            case .undetermined:
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            }
            Divider()
            footer
        }
        .frame(width: 340)
        .onReceive(
            NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
        ) { _ in
            searchFocused = true
            Task { await store.refresh() }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
            TextField("Search or add a reminder", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit(addFromQuery)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var reminderList: some View {
        let groups = store.grouped(filter: query)
        let backlog = store.backlogItems(filter: query)
        // While searching, matches in Backlog should be visible immediately.
        let expanded = backlogExpanded || !query.trimmingCharacters(in: .whitespaces).isEmpty
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if groups.isEmpty && backlog.isEmpty {
                    emptyState
                }
                ForEach(groups, id: \.0) { group, items in
                    sectionHeader(group.title)
                    ForEach(items, id: \.calendarItemIdentifier) { reminder in
                        row(reminder)
                    }
                }
                if !backlog.isEmpty {
                    backlogSection(backlog, expanded: expanded)
                }
                Color.clear.frame(height: 8)
            }
        }
        // MenuBarExtra windows size to the content's ideal height, and a
        // ScrollView has none — give it an explicit height estimated from
        // the rows (measuring via preferences updates too late to resize
        // the already-opened panel).
        .frame(
            height: Self.estimatedHeight(
                for: groups, backlog: backlog, backlogExpanded: expanded))
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }

    private func row(_ reminder: EKReminder) -> some View {
        let list = reminder.calendar?.title
        func mover(_ name: String, _ icon: String) -> ReminderRow.MoveAction {
            ReminderRow.MoveAction(label: "Move to \(name)", icon: icon) {
                withAnimation(.easeOut(duration: 0.15)) {
                    store.move(reminder, toListNamed: name)
                }
            }
        }
        let todo = mover("Todo", "arrow.up.circle")
        let backlog = mover("Backlog", "archivebox")
        let cycles = mover("Cycles", "arrow.triangle.2.circlepath")
        let moves: [ReminderRow.MoveAction] =
            list == "Backlog" ? [todo, cycles] : list == "Cycles" ? [todo, backlog] : [backlog, cycles]
        return ReminderRow(
            reminder: reminder,
            moves: moves,
            onRename: { newTitle in
                store.rename(reminder, to: newTitle)
            },
            onDelete: {
                withAnimation(.easeOut(duration: 0.15)) {
                    store.delete(reminder)
                }
            },
            onComplete: {
                withAnimation(.easeOut(duration: 0.15)) {
                    store.complete(reminder)
                }
            }
        )
    }

    private func backlogSection(_ backlog: [EKReminder], expanded: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                backlogExpanded.toggle()
            } label: {
                HStack(spacing: 4) {
                    Text("BACKLOG")
                        .font(.system(size: 10, weight: .semibold))
                    Text("\(backlog.count)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                ForEach(backlog, id: \.calendarItemIdentifier) { reminder in
                    row(reminder)
                }
            }
        }
    }

    private static func estimatedHeight(
        for groups: [(DueGroup, [EKReminder])], backlog: [EKReminder], backlogExpanded: Bool
    ) -> CGFloat {
        guard !groups.isEmpty || !backlog.isEmpty else { return 110 }
        var height: CGFloat = 8
        func add(_ items: [EKReminder]) {
            for reminder in items {
                height += 40
                if (reminder.title ?? "").count > 44 { height += 15 }
                if let notes = reminder.notes,
                    !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    height += 15
                }
            }
        }
        for (_, items) in groups {
            height += 28
            add(items)
        }
        if !backlog.isEmpty {
            height += 28
            if backlogExpanded { add(backlog) }
        }
        return min(height, 420)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            if query.isEmpty {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.teal)
                Text("All clear")
                    .foregroundStyle(.secondary)
            } else {
                Text("No matches — press ⏎ to add:")
                    .foregroundStyle(.secondary)
                Text("“\(query)”")
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
        }
        .font(.system(size: 12))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var deniedView: some View {
        VStack(spacing: 10) {
            Text("Reminders access is off.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button("Open Privacy Settings") {
                if let url = URL(
                    string:
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"
                ) {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var footer: some View {
        HStack {
            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("⏎ add reminder")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.teal)
            }
            Spacer()
            Menu {
                Button("Open Reminders.app") {
                    NSWorkspace.shared.open(URL(string: "x-apple-reminderkit://")!)
                }
                Toggle(
                    "Launch at Login",
                    isOn: Binding(
                        get: { store.launchAtLogin },
                        set: { store.launchAtLogin = $0 }
                    ))
                Divider()
                Button("Quit") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func addFromQuery() {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        store.add(from: text)
        query = ""
    }
}

struct ReminderRow: View {
    struct MoveAction {
        let label: String
        let icon: String
        let run: () -> Void
    }

    let reminder: EKReminder
    let moves: [MoveAction]
    let onRename: (String) -> Void
    let onDelete: () -> Void
    let onComplete: () -> Void

    @State private var hovering = false
    @State private var checked = false
    @State private var renaming = false
    @State private var draftTitle = ""
    @FocusState private var renameFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: check) {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(checked ? Theme.teal : Color.secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 1) {
                if renaming {
                    TextField("", text: $draftTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .focused($renameFocused)
                        .onSubmit {
                            onRename(draftTitle)
                            renaming = false
                        }
                        .onExitCommand { renaming = false }
                } else {
                    Text(reminder.title ?? "Untitled")
                        .font(.system(size: 12))
                        .strikethrough(checked, color: .secondary)
                        .foregroundStyle(checked ? Color.secondary : Color.primary)
                        .lineLimit(2)
                        .onTapGesture(count: 2) { beginRename() }
                }
                if let notes = notePreview {
                    Text(notes)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if reminder.dueLabel != nil || isCycle {
                    HStack(spacing: 3) {
                        if isCycle {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                        }
                        if let due = reminder.dueLabel {
                            Text(due)
                                .foregroundStyle(
                                    reminder.dueGroup == .overdue
                                        ? Theme.vermillion : Color.secondary)
                        }
                    }
                    .font(.system(size: 10))
                }
            }
            Spacer(minLength: 0)
            if hovering && !checked {
                HStack(spacing: 8) {
                    if let primary = moves.first {
                        Button(action: primary.run) {
                            Image(systemName: primary.icon)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(primary.label)
                    }
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.vermillion.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .help("Delete")
                }
                .padding(.top, 1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(hovering ? Color.primary.opacity(0.05) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            ForEach(moves.indices, id: \.self) { i in
                Button(moves[i].label, systemImage: moves[i].icon, action: moves[i].run)
            }
            Button("Rename", systemImage: "pencil") { beginRename() }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }

    private func beginRename() {
        draftTitle = reminder.title ?? ""
        renaming = true
        renameFocused = true
    }

    private var isCycle: Bool {
        reminder.hasRecurrenceRules || reminder.calendar?.title == "Cycles"
    }

    private var notePreview: String? {
        guard let notes = reminder.notes?
            .components(separatedBy: .newlines).first?
            .trimmingCharacters(in: .whitespaces),
            !notes.isEmpty
        else { return nil }
        return notes
    }

    private func check() {
        guard !checked else { return }
        checked = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            onComplete()
        }
    }
}
