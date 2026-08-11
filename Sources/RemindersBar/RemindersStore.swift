import EventKit
import ServiceManagement
import SwiftUI
// Case order is display order: dated-soon first, then undated, then far-out.
enum DueGroup: Int, CaseIterable, Identifiable {
    case overdue, today, tomorrow, thisWeek, noDate, later

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .overdue: return "OVERDUE"
        case .today: return "TODAY"
        case .tomorrow: return "TOMORROW"
        case .thisWeek: return "THIS WEEK"
        case .noDate: return "NO DATE"
        case .later: return "LATER"
        }
    }
}

@MainActor
final class RemindersStore: ObservableObject {
    enum Access { case undetermined, granted, denied }

    @Published var access: Access = .undetermined
    @Published var reminders: [EKReminder] = []

    let store = EKEventStore()

    init() {
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            Task { await self?.refresh() }
        }
        Task { await requestAccess() }
    }

    func requestAccess() async {
        do {
            let granted = try await store.requestFullAccessToReminders()
            access = granted ? .granted : .denied
        } catch {
            access = .denied
        }
        if access == .granted { await refresh() }
    }

    func refresh() async {
        guard access == .granted else { return }
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: nil)
        let fetched: [EKReminder] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { result in
                continuation.resume(returning: result ?? [])
            }
        }
        reminders = fetched.sorted { a, b in
            switch (a.dueDate, b.dueDate) {
            case let (da?, db?): return da < db
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil):
                return a.title ?? "" < b.title ?? ""
            }
        }
    }

    private func matches(_ reminder: EKReminder, query: String) -> Bool {
        query.isEmpty
            || (reminder.title ?? "").lowercased().contains(query)
            || (reminder.notes ?? "").lowercased().contains(query)
    }

    /// Date-grouped view of everything except the Backlog list.
    func grouped(filter: String) -> [(DueGroup, [EKReminder])] {
        let query = filter.trimmingCharacters(in: .whitespaces).lowercased()
        let visible = reminders.filter {
            $0.calendar?.title != "Backlog" && matches($0, query: query)
        }
        var buckets: [DueGroup: [EKReminder]] = [:]
        for reminder in visible {
            buckets[reminder.dueGroup, default: []].append(reminder)
        }
        return DueGroup.allCases.compactMap { group in
            guard let items = buckets[group], !items.isEmpty else { return nil }
            return (group, items)
        }
    }

    /// The Backlog list, shown as its own collapsible section.
    func backlogItems(filter: String) -> [EKReminder] {
        let query = filter.trimmingCharacters(in: .whitespaces).lowercased()
        return reminders.filter {
            $0.calendar?.title == "Backlog" && matches($0, query: query)
        }
    }

    func calendarNamed(_ name: String, createIfNeeded: Bool = false) -> EKCalendar? {
        if let existing = store.calendars(for: .reminder).first(where: { $0.title == name }) {
            return existing
        }
        guard createIfNeeded,
            let source = store.defaultCalendarForNewReminders()?.source
                ?? store.calendars(for: .reminder).first?.source
        else { return nil }
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = name
        calendar.source = source
        try? store.saveCalendar(calendar, commit: true)
        return calendar
    }

    func move(_ reminder: EKReminder, toListNamed name: String) {
        guard let target = calendarNamed(name, createIfNeeded: true) else { return }
        reminder.calendar = target
        if name == "Backlog" {
            // Backlog means "not scheduled" — drop the date and any alarms.
            reminder.dueDateComponents = nil
            reminder.alarms?.forEach(reminder.removeAlarm)
        }
        try? store.save(reminder, commit: true)
        Task { await refresh() }
    }

    func rename(_ reminder: EKReminder, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != reminder.title else { return }
        reminder.title = trimmed
        try? store.save(reminder, commit: true)
        objectWillChange.send()
    }

    func delete(_ reminder: EKReminder) {
        try? store.remove(reminder, commit: true)
        reminders.removeAll { $0.calendarItemIdentifier == reminder.calendarItemIdentifier }
    }

    func complete(_ reminder: EKReminder) {
        reminder.isCompleted = true
        try? store.save(reminder, commit: true)
        reminders.removeAll { $0.calendarItemIdentifier == reminder.calendarItemIdentifier }
    }

    /// "gym every monday", "refill meds every 30 days", "review budget monthly"
    private static func detectRecurrence(in text: String)
        -> (rule: EKRecurrenceRule, range: Range<String.Index>, weekday: EKWeekday?)?
    {
        let weekdays: [(String, EKWeekday)] = [
            ("sunday", .sunday), ("monday", .monday), ("tuesday", .tuesday),
            ("wednesday", .wednesday), ("thursday", .thursday), ("friday", .friday),
            ("saturday", .saturday),
        ]
        for (name, day) in weekdays {
            if let range = text.range(
                of: #"\bevery\s+"# + name + #"\b"#,
                options: [.regularExpression, .caseInsensitive])
            {
                let rule = EKRecurrenceRule(
                    recurrenceWith: .weekly, interval: 1,
                    daysOfTheWeek: [EKRecurrenceDayOfWeek(day)], daysOfTheMonth: nil,
                    monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil,
                    setPositions: nil, end: nil)
                return (rule, range, day)
            }
        }
        if let range = text.range(
            of: #"\bevery\s+(\d+\s+)?(day|week|month|year)s?\b"#,
            options: [.regularExpression, .caseInsensitive])
        {
            let phrase = text[range].lowercased()
            let interval = Int(phrase.split(separator: " ").dropFirst().first ?? "") ?? 1
            let freq: EKRecurrenceFrequency =
                phrase.contains("day")
                ? .daily : phrase.contains("week") ? .weekly : phrase.contains("month") ? .monthly : .yearly
            return (EKRecurrenceRule(recurrenceWith: freq, interval: max(interval, 1), end: nil), range, nil)
        }
        let words: [(String, EKRecurrenceFrequency)] = [
            ("daily", .daily), ("weekly", .weekly), ("monthly", .monthly),
            ("yearly", .yearly), ("annually", .yearly),
        ]
        for (word, freq) in words {
            if let range = text.range(
                of: #"\b"# + word + #"\b"#, options: [.regularExpression, .caseInsensitive])
            {
                return (EKRecurrenceRule(recurrenceWith: freq, interval: 1, end: nil), range, nil)
            }
        }
        return nil
    }

    /// Creates a reminder from free text, pulling out a natural-language date
    /// ("pay rent friday 3pm") via NSDataDetector and recurrence phrases
    /// ("every monday") for Cycles.
    func add(from text: String) {
        var trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        var recurrence: (rule: EKRecurrenceRule, weekday: EKWeekday?)?
        if let match = Self.detectRecurrence(in: trimmed) {
            recurrence = (match.rule, match.weekday)
            trimmed.removeSubrange(match.range)
            trimmed = trimmed
                .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { trimmed = text.trimmingCharacters(in: .whitespaces) }
        }

        let reminder = EKReminder(eventStore: store)

        var title = trimmed
        if let match = Self.dateDetector?.firstMatch(
            in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
            let date = match.date, date > Date(),
            let range = Range(match.range, in: trimmed)
        {
            title.removeSubrange(range)
            title = title
                .replacingOccurrences(
                    of: #"\s+(at|on|by)\s*$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty { title = trimmed }

            // NSDataDetector defaults date-only matches to noon.
            let calendar = Calendar.current
            let comps = calendar.dateComponents([.hour, .minute, .second], from: date)
            let looksDateOnly = comps.hour == 12 && comps.minute == 0 && comps.second == 0
                && !trimmed.lowercased().contains("12")

            if looksDateOnly {
                reminder.dueDateComponents = calendar.dateComponents(
                    [.year, .month, .day], from: date)
            } else {
                reminder.dueDateComponents = calendar.dateComponents(
                    [.year, .month, .day, .hour, .minute], from: date)
                reminder.addAlarm(EKAlarm(absoluteDate: date))
            }
        }

        reminder.title = title

        if let (rule, weekday) = recurrence {
            reminder.addRecurrenceRule(rule)
            if reminder.dueDateComponents == nil {
                // Anchor the cycle: next matching weekday, or today.
                let start: Date
                if let weekday,
                    let next = Calendar.current.nextDate(
                        after: Date(), matching: DateComponents(weekday: weekday.rawValue),
                        matchingPolicy: .nextTime)
                {
                    start = next
                } else {
                    start = Date()
                }
                reminder.dueDateComponents = Calendar.current.dateComponents(
                    [.year, .month, .day], from: start)
            }
        }

        // Recurring reminders live in Cycles; everything else defaults to Todo.
        // Backlog is only ever entered by an explicit move.
        let listName = recurrence != nil ? "Cycles" : "Todo"
        reminder.calendar =
            calendarNamed(listName, createIfNeeded: true)
            ?? store.defaultCalendarForNewReminders()
        try? store.save(reminder, commit: true)
        Task { await refresh() }
    }

    private static let dateDetector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.date.rawValue)

    // MARK: - Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {}
            objectWillChange.send()
        }
    }
}

extension EKReminder {
    var dueDate: Date? { dueDateComponents?.date }

    var hasDueTime: Bool {
        guard let comps = dueDateComponents else { return false }
        return comps.hour != nil
    }

    var dueGroup: DueGroup {
        guard let due = dueDate else { return .noDate }
        let calendar = Calendar.current
        if calendar.isDateInToday(due) {
            // A timed reminder earlier today is overdue; date-only is just "today".
            if hasDueTime && due < Date() { return .overdue }
            return .today
        }
        if due < Date() { return .overdue }
        if calendar.isDateInTomorrow(due) { return .tomorrow }
        if let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: due)
        ).day, days <= 7 {
            return .thisWeek
        }
        return .later
    }

    var dueLabel: String? {
        guard let due = dueDate else { return nil }
        let calendar = Calendar.current
        let day: String
        if calendar.isDateInToday(due) {
            day = "Today"
        } else if calendar.isDateInTomorrow(due) {
            day = "Tomorrow"
        } else if calendar.isDateInYesterday(due) {
            day = "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat =
                calendar.isDate(due, equalTo: Date(), toGranularity: .year)
                ? "EEE, d MMM" : "EEE, d MMM yyyy"
            day = formatter.string(from: due)
        }
        guard hasDueTime else { return day }
        let time = DateFormatter()
        time.timeStyle = .short
        time.dateStyle = .none
        return "\(day) \(time.string(from: due))"
    }
}
