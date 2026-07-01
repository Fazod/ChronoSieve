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
    @State private var displayMode: AgendaDisplayMode = .calendar
    @State private var selectedDate = Date()

    var body: some View {
        NavigationStack {
            List {
                if viewModel.permissionDenied {
                    Section {
                        Text("Calendar access denied. Open Settings → Privacy & Security → Calendars and enable ChronoSieve.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else if displayMode == .agenda {
                    ForEach(groupedDays, id: \.day) { group in
                        Section {
                            if !group.allDay.isEmpty {
                                Text("All-day")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                EventGroupView(events: group.allDay)
                            }

                            if !group.timed.isEmpty {
                                EventGroupView(events: group.timed)
                            }
                        } header: {
                            DaySectionHeader(day: group.day, totalCount: group.allDay.count + group.timed.count)
                        }
                    }
                } else {
                    Section {
                        DatePicker(
                            "Selected day",
                            selection: $selectedDate,
                            displayedComponents: [.date]
                        )
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                    }

                    Section(calendarSectionTitle) {
                        if selectedDayEvents.isEmpty {
                            ContentUnavailableView(
                                "No Events",
                                systemImage: "calendar",
                                description: Text("No matching events for this day.")
                            )
                        } else {
                            EventGroupView(events: selectedDayEvents)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(appBackground)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                modePickerBar
            }
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

    private var groupedDays: [DayGroup] {
        let grouped = Dictionary(grouping: viewModel.filteredEvents) {
            Calendar.current.startOfDay(for: $0.startDate)
        }

        return grouped
            .keys
            .sorted()
            .map { day in
                let events = grouped[day, default: []].sorted(by: { $0.startDate < $1.startDate })
                let allDay = events.filter(\.isAllDay)
                let timed = events.filter { !$0.isAllDay }
                return DayGroup(day: day, allDay: allDay, timed: timed)
            }
    }

    private var modePickerBar: some View {
        GeometryReader { proxy in
            let segmentWidth = (proxy.size.width - 12) / 2
            let selectedOffset = displayMode == .calendar ? 0 : segmentWidth

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.clear)
                    .glassEffect(.regular.tint(.white.opacity(0.08)).interactive(), in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(.white.opacity(0.35), lineWidth: 1)
                    }

                Capsule()
                    .fill(.clear)
                    .glassEffect(.regular.tint(.white.opacity(0.20)).interactive(), in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(.white.opacity(0.38), lineWidth: 0.8)
                    }
                    .shadow(color: .white.opacity(0.22), radius: 1.2, y: -0.5)
                    .frame(width: segmentWidth, height: 56)
                    .padding(6)
                    .offset(x: selectedOffset)
                    .animation(.spring(response: 0.32, dampingFraction: 0.84), value: displayMode)

                HStack(spacing: 0) {
                    segmentedModeButton(.calendar, systemImage: "calendar")
                    segmentedModeButton(.agenda, systemImage: "list.bullet")
                }
                .padding(6)
            }
        }
        .frame(height: 68)
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
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

    private func segmentedModeButton(_ mode: AgendaDisplayMode, systemImage: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                displayMode = mode
            }
        } label: {
            Label(mode.title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
        }
        .buttonStyle(.plain)
        .foregroundStyle(mode == displayMode ? .primary : .secondary)
        .contentShape(Capsule())
        .accessibilityLabel(mode.title)
    }

    private var appBackground: some View {
        LinearGradient(
            colors: [
                Color.blue.opacity(0.14),
                Color.purple.opacity(0.10),
                Color(.systemBackground)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var calendarSectionTitle: String {
        selectedDate.formatted(date: .complete, time: .omitted)
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

private enum AgendaDisplayMode: String, CaseIterable, Identifiable {
    case agenda
    case calendar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .agenda: return "Agenda"
        case .calendar: return "Calendar"
        }
    }
}

private struct DayGroup {
    let day: Date
    let allDay: [CalendarEvent]
    let timed: [CalendarEvent]
}

private struct DaySectionHeader: View {
    let day: Date
    let totalCount: Int

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(primaryTitle)
                    .font(.headline)
                Text(day.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(totalCount)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .glassEffect(.regular.tint(.white.opacity(0.12)), in: Capsule())
        }
    }

    private var primaryTitle: String {
        if Calendar.current.isDateInToday(day) {
            return "Today"
        }

        if Calendar.current.isDateInTomorrow(day) {
            return "Tomorrow"
        }

        return day.formatted(.dateTime.weekday(.wide))
    }
}

private struct EventGroupView: View {
    let events: [CalendarEvent]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                EventRow(event: event)

                if index < events.count - 1 {
                    Rectangle()
                        .fill(.white.opacity(0.22))
                        .frame(height: 0.75)
                        .padding(.leading, 84)
                        .padding(.trailing, 12)
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.clear)
                .glassEffect(.regular.tint(.white.opacity(0.06)), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.white.opacity(0.24), lineWidth: 0.8)
                }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
    }
}

private struct EventRow: View {
    let event: CalendarEvent

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded ? 7 : 0) {
            Button {
                withAnimation(.snappy) {
                    isExpanded.toggle()
                }
            } label: {
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
            .buttonStyle(.plain)

            if isExpanded {
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
                .padding(.leading, 68)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
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
