import Foundation
import SwiftData
import SwiftUI

struct AgendaView: View {
    @ObservedObject var viewModel: AgendaViewModel

    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\FilterRuleRecord.createdAt)]) private var persistedRules: [FilterRuleRecord]

    @State private var showingRuleManager = false
    @State private var showingHiddenEvents = false
    @State private var showingCalendarPicker = false
    @State private var selectedDate = Date()

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        if viewModel.permissionDenied {
                            permissionDeniedView
                        } else {
                            CalendarMonthView(
                                events: viewModel.filteredEvents,
                                selectedDate: $selectedDate
                            )
                            .padding(.top, -10)
                            .padding(.bottom, 8)

                            agendaSection
                        }
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomControlBar
            }
            .sheet(isPresented: $showingRuleManager) {
                FilterRulesView()
            }
            .sheet(isPresented: $showingHiddenEvents) {
                HiddenEventsView(events: hiddenEvents)
            }
            .sheet(isPresented: $showingCalendarPicker) {
                CalendarPickerView(
                    calendars: viewModel.availableCalendars,
                    selectedCalendarIDs: viewModel.enabledCalendarIDs,
                    onSave: { selected in
                        viewModel.updateEnabledCalendars(selected)
                    }
                )
            }
            .task {
                ensureDefaultRulesIfNeeded()
                syncRulesToViewModel()
                viewModel.onAppear()
            }
            .onChange(of: rulesDigest) { _, _ in
                syncRulesToViewModel()
            }
        }
    }

    private var bottomControlBar: some View {
        HStack {
            Spacer()

            Menu {
                Button {
                    Task { await viewModel.refresh(force: true) }
                } label: {
                    Label("Refresh now", systemImage: "arrow.clockwise")
                }

                Divider()

                Button {
                    showingCalendarPicker = true
                } label: {
                    Label("Calendars", systemImage: "calendar")
                }

                Button {
                    showingHiddenEvents = true
                } label: {
                    Label("Hidden Events (\(hiddenEvents.count))", systemImage: "eye.slash")
                }

                Divider()

                if persistedRules.isEmpty {
                    Text("No rules configured")
                } else {
                    Section("Quick Rule Toggles") {
                        ForEach(persistedRules, id: \.id) { rule in
                            Button {
                                toggleRule(rule)
                            } label: {
                                Label(rule.name, systemImage: rule.isEnabled ? "checkmark.circle.fill" : "circle")
                            }
                        }
                    }
                }

                Button {
                    showingRuleManager = true
                } label: {
                    Label("Manage Rules", systemImage: "slider.horizontal.3")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title2)
                    .frame(width: 56, height: 56)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .tint(.primary)
            .accessibilityLabel("Controls")
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var permissionDeniedView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Calendar access denied")
                .font(.title3.weight(.semibold))

            Text("Open Settings → Privacy & Security → Calendars and enable ChronoSieve.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 32)
    }

    private var agendaSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SelectedDayAgendaHeader(date: selectedDate)

            if selectedDayEvents.isEmpty {
                ContentUnavailableView(
                    "No Events",
                    systemImage: "calendar",
                    description: Text("No matching events for this day.")
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                EventGroupView(events: selectedDayEvents, style: .agenda)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 420, alignment: .topLeading)
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 112)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
    }

    private var appBackground: some View {
        Color(.systemBackground)
            .ignoresSafeArea()
    }

    private var selectedDayEvents: [CalendarEvent] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: selectedDate)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return []
        }

        return viewModel.filteredEvents
            .filter { $0.startDate < endOfDay && $0.endDate > startOfDay }
            .sorted(by: { $0.startDate < $1.startDate })
    }

    private var hiddenEvents: [CalendarEvent] {
        let visibleIDs = Set(viewModel.filteredEvents.map(\.id))
        return viewModel.allEvents.filter { !visibleIDs.contains($0.id) }
    }

    private var rulesDigest: String {
        persistedRules
            .map {
                "\($0.id.uuidString)|\($0.name)|\($0.pattern)|\($0.isEnabled)|\($0.modeRawValue)|\($0.isCaseSensitive)|\($0.targetsRawValue)"
            }
            .joined(separator: "\n")
    }

    private func syncRulesToViewModel() {
        let rules = persistedRules
            .sorted(by: { $0.createdAt < $1.createdAt })
            .map(\.asFilterRule)

        viewModel.updateRules(rules)
    }

    private func ensureDefaultRulesIfNeeded() {
        guard persistedRules.isEmpty else { return }
        modelContext.insert(FilterRuleRecord.makeDefaultBirthdayRule())
        saveContext()
    }

    private func toggleRule(_ rule: FilterRuleRecord) {
        rule.isEnabled.toggle()
        saveContext()
    }

    private func saveContext() {
        do {
            try modelContext.save()
        } catch {
            assertionFailure("Failed to save rules: \(error)")
        }
    }
}

private struct SelectedDayAgendaHeader: View {
    let date: Date

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(primaryTitle)
                .font(.headline.weight(.bold))
                .textCase(.uppercase)

            Text(shortDate)
                .font(.title3.weight(.regular))
                .foregroundStyle(.white.opacity(0.72))
        }
    }

    private var primaryTitle: String {
        if Calendar.current.isDateInToday(date) {
            return "Today"
        }

        return date.formatted(.dateTime.weekday(.wide)).uppercased()
    }

    private var shortDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yy"
        return formatter.string(from: date)
    }
}

private enum EventGroupStyle: Equatable {
    case card
    case agenda
}

private struct EventGroupView: View {
    let events: [CalendarEvent]
    var style: EventGroupStyle = .card

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                EventRow(event: event, style: style)

                if index < events.count - 1 {
                    Rectangle()
                        .fill(style == .agenda ? .white.opacity(0.10) : .white.opacity(0.22))
                        .frame(height: 0.75)
                        .padding(.leading, style == .agenda ? 26 : 84)
                        .padding(.trailing, style == .agenda ? 0 : 12)
                }
            }
        }
        .background {
            if style == .card {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.clear)
                    .glassEffect(.regular.tint(.white.opacity(0.06)), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(.white.opacity(0.24), lineWidth: 0.8)
                    }
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
    }
}

private struct EventRow: View {
    let event: CalendarEvent
    let style: EventGroupStyle

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded ? 10 : 0) {
            Button {
                withAnimation(.snappy) {
                    isExpanded.toggle()
                }
            } label: {
                if style == .agenda {
                    agendaRow
                } else {
                    cardRow
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                expandedContent
                    .padding(.leading, style == .agenda ? 23 : 68)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, style == .agenda ? 0 : 12)
        .padding(.vertical, style == .agenda ? 12 : 6)
    }

    private var cardRow: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .trailing, spacing: 1) {
                if event.isAllDay {
                    Label("All-day", systemImage: "sun.max")
                        .font(.caption2)
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)

                    Text("All-day")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text(event.startDate.formatted(date: .omitted, time: .shortened))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Text(event.endDate.formatted(date: .omitted, time: .shortened))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 54, alignment: .trailing)

            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: event.calendarColorHex))
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.headline)
                    .lineLimit(isExpanded ? nil : 2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 8) {
                    Label(event.calendarTitle, systemImage: "calendar")
                        .lineLimit(1)

                    if let location = event.location, !location.isEmpty {
                        Label(location, systemImage: "mappin.and.ellipse")
                            .lineLimit(isExpanded ? 2 : 1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .contentShape(Rectangle())
    }

    private var agendaRow: some View {
        HStack(alignment: .top, spacing: 12) {
            EventStatusDot(event: event, size: 11)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
                Text(timeRangeText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.70))

                Text(event.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(isExpanded ? nil : 2)
                    .multilineTextAlignment(.leading)
                    .opacity(isTentativeLike ? 0.92 : 1)

                HStack(spacing: 8) {
                    Label(event.calendarTitle, systemImage: "calendar")
                        .lineLimit(1)

                    if let location = event.location, !location.isEmpty {
                        Label(location, systemImage: "mappin.and.ellipse")
                            .lineLimit(isExpanded ? 2 : 1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.56))
            }

            Spacer(minLength: 0)

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.28))
                .padding(.top, 5)
        }
        .contentShape(Rectangle())
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let location = event.location, !location.isEmpty {
                Label(location, systemImage: "mappin.and.ellipse")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let notes = trimmedNotes, !notes.isEmpty {
                Text(notes)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !detectedLinks.isEmpty {
                ForEach(detectedLinks, id: \.absoluteString) { url in
                    Link(destination: url) {
                        Label(url.absoluteString, systemImage: "link")
                            .font(.footnote)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private var timeRangeText: String {
        if event.isAllDay {
            return "All-day"
        }

        return "\(event.startDate.formatted(date: .omitted, time: .shortened)) – \(event.endDate.formatted(date: .omitted, time: .shortened))"
    }

    private var isTentativeLike: Bool {
        event.rsvpStatus == .tentative || event.rsvpStatus == .notResponded
    }

    private var trimmedNotes: String? {
        event.notes?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var detectedLinks: [URL] {
        let sourceText = [event.location, event.notes]
            .compactMap { $0 }
            .joined(separator: "\n")

        guard !sourceText.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else {
            return []
        }

        let range = NSRange(sourceText.startIndex..<sourceText.endIndex, in: sourceText)
        let urls = detector.matches(in: sourceText, options: [], range: range).compactMap(\.url)

        var seen = Set<String>()
        return urls.filter { seen.insert($0.absoluteString).inserted }
    }
}

private struct EventStatusDot: View {
    let event: CalendarEvent
    let size: CGFloat
    var onDarkBackground = false

    var body: some View {
        let color = Color(hex: event.calendarColorHex)

        Group {
            if event.rsvpStatus == .tentative || event.rsvpStatus == .notResponded {
                ZStack {
                    if onDarkBackground {
                        Circle()
                            .fill(Color.black)
                    }

                    Circle()
                        .stroke(color, lineWidth: max(1.2, size * 0.18))
                }
            } else {
                Circle()
                    .fill(color)
            }
        }
        .frame(width: size, height: size)
    }
}

private struct HiddenEventsView: View {
    let events: [CalendarEvent]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if events.isEmpty {
                    ContentUnavailableView(
                        "No Hidden Events",
                        systemImage: "eye",
                        description: Text("Your current rules are not hiding any events.")
                    )
                } else {
                    ForEach(groupedDays, id: \.day) { group in
                        Section(group.day.formatted(date: .abbreviated, time: .omitted)) {
                            EventGroupView(events: group.events)
                        }
                    }
                }
            }
            .navigationTitle("Hidden Events")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var groupedDays: [(day: Date, events: [CalendarEvent])] {
        let grouped = Dictionary(grouping: events) {
            Calendar.current.startOfDay(for: $0.startDate)
        }

        return grouped
            .keys
            .sorted()
            .map { day in
                let events = grouped[day, default: []].sorted(by: { $0.startDate < $1.startDate })
                return (day: day, events: events)
            }
    }
}

private struct CalendarPickerView: View {
    let calendars: [CalendarSource]
    let onSave: (Set<String>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs: Set<String>

    init(calendars: [CalendarSource], selectedCalendarIDs: Set<String>, onSave: @escaping (Set<String>) -> Void) {
        self.calendars = calendars
        self.onSave = onSave
        _selectedIDs = State(initialValue: selectedCalendarIDs)
    }

    var body: some View {
        NavigationStack {
            List {
                if calendars.isEmpty {
                    ContentUnavailableView(
                        "No Calendars",
                        systemImage: "calendar",
                        description: Text("No event calendars are currently available.")
                    )
                } else {
                    ForEach(calendars) { calendar in
                        Button {
                            toggle(calendar.id)
                        } label: {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(Color(hex: calendar.colorHex))
                                    .frame(width: 10, height: 10)

                                Text(calendar.title)
                                    .foregroundStyle(.primary)

                                Spacer()

                                Image(systemName: selectedIDs.contains(calendar.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedIDs.contains(calendar.id) ? Color.accentColor : Color.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Calendars")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarLeading) {
                    Button("All") {
                        selectedIDs = Set(calendars.map(\.id))
                    }
                    .disabled(calendars.isEmpty)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave(selectedIDs)
                        dismiss()
                    }
                }
            }
        }
    }

    private func toggle(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }
}

private extension Color {
    init(hex: String) {
        let sanitized = hex.replacingOccurrences(of: "#", with: "")
        guard sanitized.count == 6, let value = Int(sanitized, radix: 16) else {
            self = .gray
            return
        }

        self = Color(
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0
        )
    }
}

// MARK: - Calendar Month View

struct CalendarMonthView: View {
    let events: [CalendarEvent]
    @Binding var selectedDate: Date

    private let weekdaySymbols = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]

    var body: some View {
        VStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(monthName)
                        .font(.title.weight(.bold))
                        .foregroundStyle(.primary)

                    Text(yearString)
                        .font(.title.weight(.regular))
                        .foregroundStyle(.red)
                }
                .minimumScaleFactor(0.8)

                HStack(spacing: 0) {
                    ForEach(weekdaySymbols, id: \.self) { day in
                        Text(day)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 15)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 2)

            VStack(spacing: 2) {
                ForEach(Array(calendarWeeks.enumerated()), id: \.offset) { _, week in
                    CalendarWeekRow(
                        week: week,
                        selectedDate: selectedDate,
                        eventsForDay: dayEvents,
                        onSelect: { selectedDate = $0 }
                    )
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 2)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var monthName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        return formatter.string(from: selectedDate)
    }

    private var yearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter.string(from: selectedDate)
    }

    private var calendarWeeks: [[CalendarDay]] {
        calendarDays.chunked(into: 7)
    }

    private var calendarDays: [CalendarDay] {
        let calendar = Calendar.current
        let monthRange = calendar.range(of: .day, in: .month, for: selectedDate)!
        let numDays = monthRange.count

        let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate))!
        let firstWeekday = calendar.component(.weekday, from: firstDay)
        let adjustedFirstWeekday = (firstWeekday - 2 + 7) % 7

        var days: [CalendarDay] = []

        if adjustedFirstWeekday > 0 {
            let previousMonth = calendar.date(byAdding: .month, value: -1, to: selectedDate)!
            let prevMonthDays = calendar.range(of: .day, in: .month, for: previousMonth)!.count
            let startDay = prevMonthDays - adjustedFirstWeekday + 1

            for i in startDay...prevMonthDays {
                let date = calendar.date(from: calendar.dateComponents([.year, .month], from: previousMonth))!
                let day = calendar.date(byAdding: .day, value: i - 1, to: date)!
                days.append(CalendarDay(date: day, isCurrentMonth: false))
            }
        }

        for i in 1...numDays {
            let day = calendar.date(byAdding: .day, value: i - 1, to: firstDay)!
            days.append(CalendarDay(date: day, isCurrentMonth: true))
        }

        let remainingDays = 42 - days.count
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: selectedDate)!
        let nextMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: nextMonth))!

        for i in 1...remainingDays {
            let day = calendar.date(byAdding: .day, value: i - 1, to: nextMonthStart)!
            days.append(CalendarDay(date: day, isCurrentMonth: false))
        }

        return days
    }

    private func dayEvents(for date: Date) -> [CalendarEvent] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return []
        }

        return events
            .filter { $0.startDate < endOfDay && $0.endDate > startOfDay }
            .sorted(by: { $0.startDate < $1.startDate })
    }
}

private struct CalendarWeekRow: View {
    let week: [CalendarDay]
    let selectedDate: Date
    let eventsForDay: (Date) -> [CalendarEvent]
    let onSelect: (Date) -> Void

    @ScaledMetric(relativeTo: .footnote) private var rowHighlightHeight = 41

    var body: some View {
        HStack(spacing: 0) {
            ForEach(week, id: \.id) { day in
                CalendarDayCell(
                    day: day,
                    isSelected: Calendar.current.isDate(day.date, inSameDayAs: selectedDate),
                    isCurrentMonth: day.isCurrentMonth,
                    isToday: Calendar.current.isDateInToday(day.date),
                    events: eventsForDay(day.date),
                    onTap: { onSelect(day.date) }
                )
            }
        }
        .frame(minHeight: 48)
        .background(alignment: .center) {
            if containsSelectedDate {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemFill))
                    .frame(height: rowHighlightHeight)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: selectedDate)
    }

    private var containsSelectedDate: Bool {
        week.contains { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
    }
}

struct CalendarDayCell: View {
    let day: CalendarDay
    let isSelected: Bool
    let isCurrentMonth: Bool
    let isToday: Bool
    let events: [CalendarEvent]
    let onTap: () -> Void

    @ScaledMetric(relativeTo: .footnote) private var numberDiameter = 31
    @ScaledMetric(relativeTo: .footnote) private var selectedBubbleSize = 46
    @ScaledMetric(relativeTo: .caption2) private var dotSize = 4

    var body: some View {
        Group {
            if isSelected {
                VStack(spacing: 2) {
                    Text("\(Calendar.current.component(.day, from: day.date))")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color(.systemBackground))

                    HStack(spacing: 3) {
                        ForEach(Array(events.prefix(4)), id: \.id) { event in
                            EventStatusDot(event: event, size: dotSize, onDarkBackground: true)
                        }
                    }
                    .frame(height: dotSize)
                    .opacity(events.isEmpty ? 0 : 1)
                    .offset(y: 2)
                }
                .frame(width: selectedBubbleSize, height: selectedBubbleSize)
                .background {
                    Circle()
                        .fill(.primary)
                }
            } else if isToday {
                VStack(spacing: 2) {
                    Text("\(Calendar.current.component(.day, from: day.date))")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    HStack(spacing: 3) {
                        ForEach(Array(events.prefix(4)), id: \.id) { event in
                            EventStatusDot(event: event, size: dotSize)
                        }
                    }
                    .frame(height: dotSize)
                    .opacity(events.isEmpty ? 0 : 1)
                    .offset(y: 2)
                }
                .frame(width: selectedBubbleSize, height: selectedBubbleSize)
                .background {
                    Circle()
                        .stroke(.secondary.opacity(0.28), lineWidth: 1)
                }
            } else {
                VStack(spacing: 1) {
                    Text("\(Calendar.current.component(.day, from: day.date))")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(dayNumberColor)
                        .frame(width: numberDiameter, height: numberDiameter)

                    HStack(spacing: 3) {
                        ForEach(Array(events.prefix(4)), id: \.id) { event in
                            EventStatusDot(event: event, size: dotSize)
                        }
                    }
                    .frame(height: dotSize)
                    .opacity(events.isEmpty ? 0 : 1)
                    .offset(y: -3)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private var dayNumberColor: Color {
        if isCurrentMonth {
            return .primary
        }

        return .secondary.opacity(0.55)
    }
}

struct CalendarDay: Identifiable {
    let date: Date
    let isCurrentMonth: Bool

    var id: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
