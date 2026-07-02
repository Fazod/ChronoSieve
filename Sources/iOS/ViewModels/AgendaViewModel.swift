import EventKit
import Foundation

@MainActor
final class AgendaViewModel: ObservableObject {
    @Published private(set) var allEvents: [CalendarEvent] = []
    @Published private(set) var filteredEvents: [CalendarEvent] = []
    @Published private(set) var activeRules: [FilterRule] = []
    @Published private(set) var availableCalendars: [CalendarSource] = []
    @Published private(set) var enabledCalendarIDs: Set<String> = []
    @Published private(set) var loadedInterval: DateInterval?
    @Published var permissionDenied = false

    private let calendarService: CalendarServiceProtocol
    private let watchSyncService: WatchSyncService
    private var filterEngine = RegexFilterEngine()

    private let initialLookAheadDays = 45
    private let incrementalLookAheadDays = 30
    private let prefetchThresholdDays = 7
    private let periodicRefreshInterval: TimeInterval = 15 * 60
    private let selectedCalendarIDsKey = "selectedCalendarIDs"

    private var lookAheadDays = 45
    private var lastFetchedInterval: DateInterval?
    private var lastRefreshAt: Date?
    private var hasPendingStoreChange = false
    private var hasLoadedCalendarSelection = false
    private var isExtendingLookAhead = false
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

    func ensureDateLoaded(_ date: Date) async {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: Date())
        let targetDay = calendar.startOfDay(for: date)
        let dayDistance = calendar.dateComponents([.day], from: today, to: targetDay).day ?? 0
        let requiredLookAheadDays = max(initialLookAheadDays, dayDistance + prefetchThresholdDays + 1)

        guard requiredLookAheadDays > lookAheadDays else {
            return
        }

        await extendLookAhead(toAtLeast: requiredLookAheadDays)
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

        await extendLookAhead(toAtLeast: lookAheadDays + incrementalLookAheadDays)
    }

    private func extendLookAhead(toAtLeast minimumDays: Int) async {
        guard !isExtendingLookAhead else {
            return
        }

        guard minimumDays > lookAheadDays else {
            return
        }

        isExtendingLookAhead = true
        lookAheadDays = minimumDays
        await refresh(force: true)
        isExtendingLookAhead = false
    }

    private func makeFetchInterval(referenceDate: Date) -> DateInterval {
        let calendar = Calendar.autoupdatingCurrent
        let start = calendar.startOfDay(for: referenceDate)
        let end = calendar.date(byAdding: .day, value: lookAheadDays, to: start)
            ?? start.addingTimeInterval(TimeInterval(lookAheadDays * 86_400))
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
        filteredEvents = filterEngine.apply(rules: activeRules, to: allEvents)
        watchSyncService.push(events: filteredEvents)
    }
}
