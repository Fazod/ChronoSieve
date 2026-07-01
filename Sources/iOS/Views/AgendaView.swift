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
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var stickyCalendarHeight: CGFloat = 0
    @State private var stickyDayHeaderHeight: CGFloat = 0
    @State private var pendingScrollDate: Date?
    @State private var isProgrammaticScroll = false

    private let agendaScrollCoordinateSpace = "agenda-scroll"

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground

                if viewModel.permissionDenied {
                    ScrollView(showsIndicators: false) {
                        permissionDeniedView
                    }
                } else {
                    agendaScrollView
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
        .environmentObject(viewModel)
    }

    private var agendaScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(agendaDayGroups) { group in
                        Section {
                            AgendaDaySectionContent(events: group.events)
                                .padding(.horizontal, 16)
                                .background(sectionOffsetReader(for: group))
                                .onAppear {
                                    guard shouldPrefetchMore(for: group) else { return }
                                    Task {
                                        await viewModel.loadMoreIfNeeded(currentDay: group.day)
                                    }
                                }
                        } header: {
                            AgendaDaySectionHeader(
                                date: group.day,
                                showSeparator: group.id != agendaDayGroups.first?.id
                            )
                            .background {
                                GeometryReader { proxy in
                                    Color.clear
                                        .preference(key: DayHeaderHeightPreferenceKey.self, value: proxy.size.height)
                                }
                            }
                        }
                        .id(group.id)
                    }

                    Color.clear
                        .frame(height: 1)
                        .onAppear {
                            guard let lastDay = agendaDayGroups.last?.day else { return }
                            Task {
                                await viewModel.loadMoreIfNeeded(currentDay: lastDay)
                            }
                        }
                }
                .padding(.bottom, 112)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .coordinateSpace(name: agendaScrollCoordinateSpace)
            .background(Color.black)
            // Only the calendar lives in the top safe-area inset now. The per-day
            // headers pin themselves (LazyVStack pinnedViews) directly below it,
            // so there is exactly one header per day and no duplicate sticky copy.
            .safeAreaInset(edge: .top, spacing: 0) {
                stickyCalendarOverlay
            }
            .onPreferenceChange(DayHeaderHeightPreferenceKey.self) { height in
                stickyDayHeaderHeight = height
            }
            .onPreferenceChange(AgendaDaySectionOffsetPreferenceKey.self) { offsets in
                updateSelectedDateFromScroll(offsets)
            }
            .onChange(of: pendingScrollDate) { _, _ in
                scrollToPendingDate(with: proxy)
            }
            .onChange(of: agendaDayGroupIDs) { _, _ in
                scrollToPendingDate(with: proxy)
            }
        }
    }

    private var stickyCalendarOverlay: some View {
        CalendarMonthView(
            events: viewModel.filteredEvents,
            selectedDate: calendarSelectionBinding
        )
        .padding(.top, -10)
        .padding(.bottom, 8)
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.75)
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .preference(key: ViewHeightPreferenceKey.self, value: proxy.size.height)
            }
        }
        .onPreferenceChange(ViewHeightPreferenceKey.self) { height in
            stickyCalendarHeight = height
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

    private var appBackground: some View {
        Color(.systemBackground)
            .ignoresSafeArea()
    }

    private var calendarSelectionBinding: Binding<Date> {
        Binding(
            get: { selectedDate },
            set: { newValue in
                let normalized = Calendar.current.startOfDay(for: newValue)
                selectedDate = normalized
                pendingScrollDate = normalized

                Task {
                    await viewModel.ensureDateLoaded(normalized)
                }
            }
        )
    }

    private var agendaDayGroupIDs: [String] {
        agendaDayGroups.map(\.id)
    }

    private var agendaDayGroups: [AgendaDayGroup] {
        let calendar = Calendar.current
        let selectedDay = calendar.startOfDay(for: selectedDate)

        guard let loadedInterval = viewModel.loadedInterval else {
            return [
                AgendaDayGroup(day: selectedDay, events: events(for: selectedDay))
            ]
        }

        let startDay = calendar.startOfDay(for: loadedInterval.start)
        let endDay = calendar.startOfDay(for: loadedInterval.end)

        var groups: [AgendaDayGroup] = []
        var cursor = startDay

        while cursor < endDay {
            let dayEvents = events(for: cursor)
            if !dayEvents.isEmpty || calendar.isDate(cursor, inSameDayAs: selectedDay) {
                groups.append(AgendaDayGroup(day: cursor, events: dayEvents))
            }

            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: cursor) else {
                break
            }

            cursor = nextDay
        }

        if groups.isEmpty {
            groups.append(AgendaDayGroup(day: selectedDay, events: []))
        }

        return groups
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

    private func events(for day: Date) -> [CalendarEvent] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: day)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return []
        }

        return viewModel.filteredEvents
            .filter { $0.startDate < endOfDay && $0.endDate > startOfDay }
            .sorted(by: { $0.startDate < $1.startDate })
    }

    private func shouldPrefetchMore(for group: AgendaDayGroup) -> Bool {
        guard let index = agendaDayGroups.firstIndex(where: { $0.id == group.id }) else {
            return false
        }

        return index >= max(agendaDayGroups.count - 3, 0)
    }

    private func sectionOffsetReader(for group: AgendaDayGroup) -> some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: AgendaDaySectionOffsetPreferenceKey.self,
                    value: [
                        AgendaDaySectionOffset(
                            id: group.id,
                            day: group.day,
                            minY: proxy.frame(in: .named(agendaScrollCoordinateSpace)).minY
                        )
                    ]
                )
        }
    }

    private func updateSelectedDateFromScroll(_ offsets: [AgendaDaySectionOffset]) {
        // Ignore geometry churn caused by an in-flight programmatic scroll; the
        // tapped date already drives `selectedDate` in that case.
        guard !isProgrammaticScroll, pendingScrollDate == nil else {
            return
        }

        // Content sits just below its pinned day header, so the active day is
        // the one whose content top has passed under the pin line (roughly the
        // header height) and is closest to it.
        let threshold: CGFloat = (stickyDayHeaderHeight > 0 ? stickyDayHeaderHeight : 40) + 4
        let sortedOffsets = offsets.sorted(by: { $0.minY < $1.minY })

        let activeOffset = sortedOffsets
            .filter { $0.minY <= threshold }
            .max(by: { $0.minY < $1.minY })
            ?? sortedOffsets.first

        guard let activeOffset else {
            return
        }

        let normalized = Calendar.current.startOfDay(for: activeOffset.day)
        guard !Calendar.current.isDate(normalized, inSameDayAs: selectedDate) else {
            return
        }

        selectedDate = normalized
    }

    private func scrollToPendingDate(with proxy: ScrollViewProxy) {
        guard let pendingScrollDate else {
            return
        }

        guard let targetGroup = targetAgendaGroup(for: pendingScrollDate) else {
            return
        }

        // With the header in the top safe-area inset, anchoring to `.top` lands
        // the section right below the header.
        isProgrammaticScroll = true
        withAnimation(.snappy(duration: 0.32, extraBounce: 0)) {
            proxy.scrollTo(targetGroup.id, anchor: .top)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            self.pendingScrollDate = nil
            self.isProgrammaticScroll = false
        }
    }

    private func targetAgendaGroup(for date: Date) -> AgendaDayGroup? {
        let calendar = Calendar.current
        let normalized = calendar.startOfDay(for: date)

        if let exactMatch = agendaDayGroups.first(where: { calendar.isDate($0.day, inSameDayAs: normalized) }) {
            return exactMatch
        }

        if let nextMatch = agendaDayGroups.first(where: { $0.day >= normalized }) {
            return nextMatch
        }

        return agendaDayGroups.last
    }
}

private struct AgendaDayGroup: Identifiable, Equatable {
    let day: Date
    let events: [CalendarEvent]

    var id: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: day)
    }
}

private struct AgendaDaySectionOffset: Equatable {
    let id: String
    let day: Date
    let minY: CGFloat
}

private struct AgendaDaySectionOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: [AgendaDaySectionOffset] = []

    static func reduce(value: inout [AgendaDaySectionOffset], nextValue: () -> [AgendaDaySectionOffset]) {
        value.append(contentsOf: nextValue())
    }
}

private struct ViewHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct DayHeaderHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct AgendaDaySectionHeader: View {
    let date: Date
    let showSeparator: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showSeparator {
                Rectangle()
                    .fill(.white.opacity(0.14))
                    .frame(height: 0.75)
            }

            SelectedDayAgendaHeader(date: date)
                .padding(.horizontal, 16)
                .padding(.top, showSeparator ? 6 : 8)
                .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
    }
}

private struct AgendaDaySectionContent: View {
    let events: [CalendarEvent]

    var body: some View {
        Group {
            if events.isEmpty {
                ContentUnavailableView(
                    "No Events",
                    systemImage: "calendar",
                    description: Text("No matching events for this day.")
                )
                .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                EventGroupView(events: events, style: .agenda)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 6)
        .padding(.bottom, 18)
        .environment(\.colorScheme, .dark)
    }
}

private struct SelectedDayAgendaHeader: View {
    let date: Date

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(primaryTitle)
                .font(.subheadline.weight(.bold))
                .textCase(.uppercase)
                .tracking(0.2)

            Text(shortDate)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.72))
        }
        .lineLimit(1)
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

    @State private var showingDetail = false

    var body: some View {
        Button {
            showingDetail = true
        } label: {
            if style == .agenda {
                agendaRow
            } else {
                cardRow
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, style == .agenda ? 0 : 12)
        .padding(.vertical, style == .agenda ? 12 : 6)
        .sheet(isPresented: $showingDetail) {
            EventDetailView(event: event)
        }
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
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 8) {
                    Label(event.calendarTitle, systemImage: "calendar")
                        .lineLimit(1)

                    if let location = event.location, !location.isEmpty {
                        Label(location, systemImage: "mappin.and.ellipse")
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
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
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .opacity(isTentativeLike ? 0.92 : 1)

                HStack(spacing: 8) {
                    Label(event.calendarTitle, systemImage: "calendar")
                        .lineLimit(1)

                    if let location = event.location, !location.isEmpty {
                        Label(location, systemImage: "mappin.and.ellipse")
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.56))
            }

            Spacer(minLength: 0)

            // Attendee count badge when there are attendees
            if !event.attendees.isEmpty {
                HStack(spacing: -8) {
                    ForEach(Array(event.attendees.prefix(3)), id: \.id) { attendee in
                        MiniAttendeeAvatar(attendee: attendee)
                    }
                }
                .padding(.top, 3)
            }
        }
        .contentShape(Rectangle())
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
}

// Tiny stacked avatar shown on the agenda row when an event has attendees
private struct MiniAttendeeAvatar: View {
    let attendee: Attendee
    private let size: CGFloat = 20

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black)
                .frame(width: size + 2, height: size + 2)

            Circle()
                .fill(avatarColor)
                .frame(width: size, height: size)

            Text(attendee.initials)
                .font(.system(size: 7, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private var avatarColor: Color {
        let palette: [(Double, Double, Double)] = [
            (0.55, 0.60, 0.65), (0.20, 0.54, 0.88), (0.12, 0.70, 0.52),
            (0.86, 0.44, 0.20), (0.62, 0.32, 0.78), (0.82, 0.26, 0.28),
            (0.16, 0.66, 0.36), (0.88, 0.65, 0.08),
        ]
        var hash = 5381
        for scalar in attendee.name.unicodeScalars {
            hash = ((hash << 5) &+ hash) &+ Int(scalar.value)
        }
        let (r, g, b) = palette[abs(hash) % palette.count]
        return Color(red: r, green: g, blue: b)
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
