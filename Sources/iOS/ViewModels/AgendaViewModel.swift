import EventKit
import Foundation

struct CalendarDayMarker: Identifiable, Hashable {
    enum Style: Hashable {
        case filled
        case outlined
    }

    let id: String
    let colorHex: String
    let style: Style

    init(event: CalendarEvent) {
        id = event.id
        colorHex = event.calendarColorHex

        switch event.rsvpStatus {
        case .tentative, .notResponded:
            style = .outlined
        case .unknown, .accepted, .declined:
            style = .filled
        }
    }
}

@MainActor
final class AgendaViewModel: ObservableObject {
    @Published private(set) var allEvents: [CalendarEvent] = []
    @Published private(set) var filteredEvents: [CalendarEvent] = []
    @Published private(set) var activeRules: [FilterRule] = []
    @Published private(set) var availableCalendars: [CalendarSource] = []
    @Published private(set) var enabledCalendarIDs: Set<String> = []
    @Published private(set) var loadedInterval: DateInterval?
    @Published var permissionDenied = false

    private var filteredEventsByDay: [Date: [CalendarEvent]] = [:]
    private var filteredMarkersByDay: [Date: [CalendarDayMarker]] = [:]

    private let calendarService: CalendarServiceProtocol
    private let watchSyncService: WatchSyncService
    private var filterEngine = RegexFilterEngine()

    private let minimumInitialLookBehindDays = 7
    private let initialLookAheadDays = 45
    private let incrementalLookBehindDays = 30
    private let incrementalLookAheadDays = 30
    private let prefetchThresholdDays = 7
    private let periodicRefreshInterval: TimeInterval = 15 * 60
    private let selectedCalendarIDsKey = "selectedCalendarIDs"

    private var lookBehindDays = AgendaViewModel.defaultInitialLookBehindDays(referenceDate: Date())
    private var lookAheadDays = 45
    private var lastFetchedInterval: DateInterval?
    private var lastRefreshAt: Date?
    private var hasPendingStoreChange = false
    private var hasLoadedCalendarSelection = false
    private var isExtendingVisibleRange = false
    private var changeRefreshTask: Task<Void, Never>?

    init(
        calendarService: CalendarServiceProtocol? = nil,
        watchSyncService: WatchSyncService? = nil
    ) {
        self.calendarService = calendarService ?? CalendarService()
        self.watchSyncService = watchSyncService ?? .shared

        self.calendarService.setChangeHandler { [weak self] in
            self?.scheduleDebouncedStoreRefresh()
        }
    }

    deinit {
        changeRefreshTask?.cancel()
    }

    func onAppear() {
        Task {
            await refresh()
        }
    }

    func updateRules(_ rules: [FilterRule]) {
        activeRules = rules
        applyFilters()
    }

    func moveEvent(_ event: CalendarEvent, toCalendarID calendarID: String) async {
        do {
            try await calendarService.moveEvent(event.id, toCalendarID: calendarID)
            await refresh(force: true)
        } catch {
            // Event store will fire a change notification on its own if something
            // else caused a refresh; silently ignore move errors for now.
        }
    }

    func rsvpEdit(for event: CalendarEvent) -> (EKEventStore, EKEvent)? {
        calendarService.prepareRSVPEdit(for: event.id)
    }

    func updateEnabledCalendars(_ ids: Set<String>) {
        enabledCalendarIDs = ids.intersection(Set(availableCalendars.map(\.id)))
        persistSelectedCalendarIDs()

        Task { [weak self] in
            await self?.refresh(force: true)
        }
    }

    func refresh(force: Bool = false) async {
        let granted = await calendarService.requestAccess()
        guard granted else {
            permissionDenied = true
            allEvents = []
            filteredEvents = []
            availableCalendars = []
            enabledCalendarIDs = []
            loadedInterval = nil
            return
        }

        permissionDenied = false

        await reloadCalendarsIfNeeded()

        let now = Date()
        let interval = makeFetchInterval(referenceDate: now)

        guard shouldFetchEvents(in: interval, force: force, now: now) else {
            applyFilters()
            return
        }

        allEvents = await calendarService.fetchEvents(in: interval, calendarIDs: enabledCalendarIDs)
        loadedInterval = interval
        lastFetchedInterval = interval
        lastRefreshAt = now
        hasPendingStoreChange = false
        applyFilters()
    }

    private func reloadCalendarsIfNeeded() async {
        let previousCalendarIDs = Set(availableCalendars.map(\.id))
        let calendars = await calendarService.fetchCalendars()
        availableCalendars = calendars

        let currentCalendarIDs = Set(calendars.map(\.id))
        guard !currentCalendarIDs.isEmpty else {
            enabledCalendarIDs = []
            persistSelectedCalendarIDs()
            return
        }

        if !hasLoadedCalendarSelection {
            if let persisted = persistedSelectedCalendarIDs() {
                let intersected = persisted.intersection(currentCalendarIDs)
                enabledCalendarIDs = intersected.isEmpty ? currentCalendarIDs : intersected
            } else {
                enabledCalendarIDs = currentCalendarIDs
            }
            hasLoadedCalendarSelection = true
            persistSelectedCalendarIDs()
            return
        }

        let newCalendarIDs = currentCalendarIDs.subtracting(previousCalendarIDs)
        enabledCalendarIDs = enabledCalendarIDs
            .intersection(currentCalendarIDs)
            .union(newCalendarIDs)

        if enabledCalendarIDs.isEmpty {
            enabledCalendarIDs = currentCalendarIDs
        }

        persistSelectedCalendarIDs()
    }

    private func scheduleDebouncedStoreRefresh() {
        hasPendingStoreChange = true

        changeRefreshTask?.cancel()
        changeRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 750_000_000)
            guard !Task.isCancelled else { return }
            await self?.refresh(force: true)
        }
    }

    private func shouldFetchEvents(in interval: DateInterval, force: Bool, now: Date) -> Bool {
        if force || hasPendingStoreChange {
            return true
        }

        guard let lastFetchedInterval else {
            return true
        }

        if !intervalsMatch(lhs: lastFetchedInterval, rhs: interval) {
            return true
        }

        guard let lastRefreshAt else {
            return true
        }

        return now.timeIntervalSince(lastRefreshAt) >= periodicRefreshInterval
    }

    private func intervalsMatch(lhs: DateInterval, rhs: DateInterval) -> Bool {
        abs(lhs.start.timeIntervalSince(rhs.start)) < 1
            && abs(lhs.end.timeIntervalSince(rhs.end)) < 1
    }

    func events(on day: Date) -> [CalendarEvent] {
        let normalizedDay = Calendar.autoupdatingCurrent.startOfDay(for: day)
        return filteredEventsByDay[normalizedDay] ?? []
    }

    func dayMarkers(on day: Date) -> [CalendarDayMarker] {
        let normalizedDay = Calendar.autoupdatingCurrent.startOfDay(for: day)
        return filteredMarkersByDay[normalizedDay] ?? []
    }

    func ensureDateLoaded(_ date: Date) async {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: Date())
        let targetDay = calendar.startOfDay(for: date)
        let dayDistance = calendar.dateComponents([.day], from: today, to: targetDay).day ?? 0

        let requiredLookBehindDays = max(
            minimumInitialLookBehindDays,
            max(0, -dayDistance) + prefetchThresholdDays
        )
        let requiredLookAheadDays = max(
            initialLookAheadDays,
            max(0, dayDistance) + prefetchThresholdDays + 1
        )

        await extendVisibleRange(
            toAtLeastLookBehind: requiredLookBehindDays,
            lookAhead: requiredLookAheadDays
        )
    }

    func loadMoreIfNeeded(currentDay: Date) async {
        guard let loadedInterval else {
            return
        }

        let calendar = Calendar.autoupdatingCurrent
        let thresholdDate = calendar.date(byAdding: .day, value: -prefetchThresholdDays, to: loadedInterval.end)
            ?? loadedInterval.end

        guard calendar.startOfDay(for: currentDay) >= calendar.startOfDay(for: thresholdDate) else {
            return
        }

        await extendVisibleRange(
            toAtLeastLookBehind: lookBehindDays,
            lookAhead: lookAheadDays + incrementalLookAheadDays
        )
    }

    func loadPreviousIfNeeded(currentDay: Date) async {
        guard let loadedInterval else {
            return
        }

        let calendar = Calendar.autoupdatingCurrent
        let thresholdDate = calendar.date(byAdding: .day, value: prefetchThresholdDays, to: loadedInterval.start)
            ?? loadedInterval.start

        guard calendar.startOfDay(for: currentDay) <= calendar.startOfDay(for: thresholdDate) else {
            return
        }

        await extendVisibleRange(
            toAtLeastLookBehind: lookBehindDays + incrementalLookBehindDays,
            lookAhead: lookAheadDays
        )
    }

    private func extendVisibleRange(toAtLeastLookBehind minimumLookBehindDays: Int, lookAhead minimumLookAheadDays: Int) async {
        guard !isExtendingVisibleRange else {
            return
        }

        let needsMoreHistory = minimumLookBehindDays > lookBehindDays
        let needsMoreFuture = minimumLookAheadDays > lookAheadDays

        guard needsMoreHistory || needsMoreFuture else {
            return
        }

        isExtendingVisibleRange = true
        lookBehindDays = max(lookBehindDays, minimumLookBehindDays)
        lookAheadDays = max(lookAheadDays, minimumLookAheadDays)
        await refresh(force: true)
        isExtendingVisibleRange = false
    }

    private func makeFetchInterval(referenceDate: Date) -> DateInterval {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: referenceDate)
        let start = calendar.date(byAdding: .day, value: -lookBehindDays, to: today)
            ?? today.addingTimeInterval(TimeInterval(-lookBehindDays * 86_400))
        let end = calendar.date(byAdding: .day, value: lookAheadDays, to: today)
            ?? today.addingTimeInterval(TimeInterval(lookAheadDays * 86_400))
        return DateInterval(start: start, end: end)
    }

    private func persistedSelectedCalendarIDs() -> Set<String>? {
        guard let ids = UserDefaults.standard.array(forKey: selectedCalendarIDsKey) as? [String] else {
            return nil
        }
        return Set(ids)
    }

    private func persistSelectedCalendarIDs() {
        UserDefaults.standard.set(Array(enabledCalendarIDs).sorted(), forKey: selectedCalendarIDsKey)
    }

    private func applyFilters() {
        let filtered = filterEngine.apply(rules: activeRules, to: allEvents)
        let groupedEvents = buildDayIndex(for: filtered)

        filteredEvents = filtered
        filteredEventsByDay = groupedEvents
        filteredMarkersByDay = buildDayMarkers(from: groupedEvents)
        watchSyncService.push(events: filtered)
    }

    private func buildDayIndex(for events: [CalendarEvent]) -> [Date: [CalendarEvent]] {
        let calendar = Calendar.autoupdatingCurrent
        var grouped: [Date: [CalendarEvent]] = [:]

        for event in events {
            let startDay = calendar.startOfDay(for: event.startDate)
            let inclusiveEndDate = max(event.startDate, event.endDate.addingTimeInterval(-1))
            let endDay = calendar.startOfDay(for: inclusiveEndDate)

            var cursor = startDay
            while cursor <= endDay {
                grouped[cursor, default: []].append(event)
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: cursor) else {
                    break
                }
                cursor = nextDay
            }
        }

        for day in grouped.keys {
            grouped[day]?.sort(by: { $0.startDate < $1.startDate })
        }

        return grouped
    }

    private func buildDayMarkers(from groupedEvents: [Date: [CalendarEvent]]) -> [Date: [CalendarDayMarker]] {
        groupedEvents.mapValues { events in
            Array(events.prefix(4)).map(CalendarDayMarker.init(event:))
        }
    }

    private static func defaultInitialLookBehindDays(referenceDate: Date) -> Int {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: referenceDate)
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
        let daysSinceStartOfMonth = calendar.dateComponents([.day], from: startOfMonth, to: today).day ?? 0
        return max(7, daysSinceStartOfMonth)
    }
}
