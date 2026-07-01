import SwiftUI

// MARK: - App View Mode

enum AppViewMode: String {
    case calendar = "calendar"
    case day = "day"
}

// MARK: - Day View Container (page-swipe navigation)

struct DayView: View {
    @ObservedObject var viewModel: AgendaViewModel
    @Binding var selectedDate: Date

    /// Total pages in the pager – ±365 days around today.
    private let totalPages = 731
    /// Index of "today" in the page array.
    private let centerPage = 365

    @State private var currentPage: Int
    /// The date that corresponds to page `centerPage`; always startOfDay(today) at init time.
    @State private var pivotDate: Date

    init(viewModel: AgendaViewModel, selectedDate: Binding<Date>) {
        self.viewModel = viewModel
        self._selectedDate = selectedDate

        let cal = Calendar.current
        let today    = cal.startOfDay(for: Date())
        let selected = cal.startOfDay(for: selectedDate.wrappedValue)
        let diff     = cal.dateComponents([.day], from: today, to: selected).day ?? 0
        let page     = max(0, min(730, 365 + diff))

        self._currentPage = State(initialValue: page)
        self._pivotDate   = State(initialValue: today)
    }

    var body: some View {
        TabView(selection: $currentPage) {
            ForEach(0..<totalPages, id: \.self) { page in
                DayTimelineView(
                    events: eventsFor(date: dateFor(page: page)),
                    date:   dateFor(page: page)
                )
                .tag(page)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onChange(of: currentPage) { _, newPage in
            let newDate = dateFor(page: newPage)
            guard !Calendar.current.isDate(newDate, inSameDayAs: selectedDate) else { return }
            selectedDate = newDate
            Task { await viewModel.ensureDateLoaded(newDate) }
        }
        .onChange(of: selectedDate) { _, newDate in
            let cal  = Calendar.current
            let diff = cal.dateComponents([.day], from: pivotDate,
                                          to: cal.startOfDay(for: newDate)).day ?? 0
            let page = max(0, min(730, centerPage + diff))
            if page != currentPage { currentPage = page }
        }
    }

    // MARK: Helpers

    private func dateFor(page: Int) -> Date {
        let offset = page - centerPage
        return Calendar.current.date(byAdding: .day, value: offset, to: pivotDate) ?? pivotDate
    }

    private func eventsFor(date: Date) -> [CalendarEvent] {
        let cal   = Calendar.current
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        return viewModel.filteredEvents.filter { $0.startDate < end && $0.endDate > start }
    }
}

// MARK: - Day Timeline View  (single-day content)

struct DayTimelineView: View {
    let events: [CalendarEvent]
    let date:   Date

    // Layout constants
    private let hourHeight:      CGFloat = 60
    private let timeColumnWidth: CGFloat = 48
    private let minEventHeight:  CGFloat = 20

    // Derived
    private var allDayEvents: [CalendarEvent] { events.filter(\.isAllDay) }
    private var timedEvents:  [CalendarEvent] { events.filter { !$0.isAllDay } }
    private var isToday: Bool { Calendar.current.isDateInToday(date) }
    private var totalHeight: CGFloat { CGFloat(24) * hourHeight }

    var body: some View {
        VStack(spacing: 0) {
            dayHeader
            if !allDayEvents.isEmpty {
                allDaySectionView
            }
            timelineSection
        }
        .background(Color(.systemBackground))
    }

    // MARK: – Header

    private var dayHeader: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(dayAndMonthString)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.primary)
                Text(yearString)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.red)
            }
            .minimumScaleFactor(0.75)
            .lineLimit(1)

            Text(weekdayString)
                .font(.subheadline.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.4)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.5)
        }
    }

    private var dayAndMonthString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "d. MMMM"
        return fmt.string(from: date)
    }

    private var yearString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy"
        return fmt.string(from: date)
    }

    private var weekdayString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE"
        return fmt.string(from: date).uppercased()
    }

    // MARK: – All-Day Events

    private var allDaySectionView: some View {
        VStack(spacing: 0) {
            ForEach(allDayEvents) { event in
                DayAllDayRow(event: event)
                if event.id != allDayEvents.last?.id {
                    Rectangle()
                        .fill(Color.primary.opacity(0.07))
                        .frame(height: 0.5)
                        .padding(.leading, 16)
                }
            }
        }
        .background(Color(.secondarySystemBackground))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.5)
        }
    }

    // MARK: – Timeline

    private var timelineSection: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                ZStack(alignment: .topLeading) {

                    // 1. Hour grid
                    VStack(spacing: 0) {
                        ForEach(0..<24, id: \.self) { hour in
                            HourSlotView(
                                hour: hour,
                                hourHeight: hourHeight,
                                timeColumnWidth: timeColumnWidth
                            )
                            .id("hour-\(hour)")
                        }
                    }

                    // 2. Event blocks – needs actual width from GeometryReader
                    GeometryReader { geo in
                        let areaWidth = max(1, geo.size.width - timeColumnWidth)
                        ZStack(alignment: .topLeading) {
                            ForEach(layoutEvents(timedEvents, areaWidth: areaWidth)) { layout in
                                DayEventBlock(event: layout.event, blockHeight: layout.height)
                                    .frame(
                                        width:  max(8, layout.width),
                                        height: max(minEventHeight, layout.height)
                                    )
                                    .offset(x: timeColumnWidth + layout.xOffset,
                                            y: layout.yOffset)
                            }
                        }
                    }
                    .frame(height: totalHeight)

                    // 3. Current-time indicator (today only, updates every minute)
                    if isToday {
                        TimelineView(.everyMinute) { ctx in
                            currentTimeIndicator(at: ctx.date)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: totalHeight)
                .padding(.bottom, 100)
            }
            .onAppear {
                let hour = max(0, scrollTargetHour - 1)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    proxy.scrollTo("hour-\(hour)", anchor: .top)
                }
            }
        }
    }

    private var scrollTargetHour: Int {
        isToday ? Calendar.current.component(.hour, from: Date()) : 8
    }

    // MARK: – Current Time Indicator

    private func currentTimeIndicator(at now: Date) -> some View {
        let mins = CGFloat(now.timeIntervalSince(Calendar.current.startOfDay(for: date)) / 60)
        let y    = mins * hourHeight / 60

        return HStack(alignment: .center, spacing: 0) {
            // Current time label replaces the hour number in the time column
            Text(shortTimeLabel(for: now))
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.red)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: timeColumnWidth, alignment: .trailing)
                .padding(.trailing, 5)

            // Dot at the boundary between time column and event area
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)

            // Horizontal rule across the full event area
            Rectangle()
                .fill(Color.red.opacity(0.85))
                .frame(height: 1.5)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .offset(y: y - 4)   // −4 centres the 8 pt circle on the line
    }

    private func shortTimeLabel(for date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .none
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }

    // MARK: – Event Layout

    private struct DayEventLayout: Identifiable {
        let event:   CalendarEvent
        let yOffset: CGFloat
        let height:  CGFloat
        let xOffset: CGFloat
        let width:   CGFloat
        var id: String { event.id }
    }

    private func layoutEvents(_ events: [CalendarEvent],
                              areaWidth: CGFloat) -> [DayEventLayout] {
        guard !events.isEmpty else { return [] }

        // Sort: earlier start first; longer events first when starts are equal
        let sorted = events.sorted { a, b in
            let aS = clampedStart(a), bS = clampedStart(b)
            return aS == bS ? clampedEnd(a) > clampedEnd(b) : aS < bS
        }

        // Greedy column assignment
        var colEndTimes: [Date] = []
        var colFor: [String: Int] = [:]

        for event in sorted {
            let start = clampedStart(event)
            let end   = clampedEnd(event)
            var col   = -1
            for i in 0..<colEndTimes.count where colEndTimes[i] <= start {
                col = i
                colEndTimes[i] = end
                break
            }
            if col == -1 {
                col = colEndTimes.count
                colEndTimes.append(end)
            }
            colFor[event.id] = col
        }

        // Build layout, using the max column in each event's overlap group
        return sorted.compactMap { event in
            guard let col = colFor[event.id] else { return nil }
            let start = clampedStart(event)
            let end   = clampedEnd(event)

            let groupMax = sorted.compactMap { other -> Int? in
                guard let c = colFor[other.id],
                      clampedStart(other) < end,
                      clampedEnd(other)  > start else { return nil }
                return c
            }.max() ?? col

            let numCols = groupMax + 1
            let colW    = areaWidth / CGFloat(numCols)

            return DayEventLayout(
                event:   event,
                yOffset: yOffsetFor(event),
                height:  heightFor(event),
                xOffset: CGFloat(col) * colW,
                width:   colW - 2        // 2 pt gap between columns
            )
        }
    }

    private func clampedStart(_ event: CalendarEvent) -> Date {
        max(Calendar.current.startOfDay(for: date), event.startDate)
    }

    private func clampedEnd(_ event: CalendarEvent) -> Date {
        let s      = Calendar.current.startOfDay(for: date)
        let endDay = Calendar.current.date(byAdding: .day, value: 1, to: s)!
        return min(endDay, event.endDate)
    }

    private func yOffsetFor(_ event: CalendarEvent) -> CGFloat {
        let startOfDay = Calendar.current.startOfDay(for: date)
        let mins = clampedStart(event).timeIntervalSince(startOfDay) / 60
        return CGFloat(mins) * hourHeight / 60
    }

    private func heightFor(_ event: CalendarEvent) -> CGFloat {
        let mins = clampedEnd(event).timeIntervalSince(clampedStart(event)) / 60
        return max(minEventHeight, CGFloat(mins) * hourHeight / 60)
    }
}

// MARK: - Hour Slot

private struct HourSlotView: View {
    let hour:            Int
    let hourHeight:      CGFloat
    let timeColumnWidth: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(label)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(hour == 12 ? Color.red : Color.secondary)
                .frame(width: timeColumnWidth, alignment: .trailing)
                .padding(.trailing, 7)
                .offset(y: -7)   // position label just above the grid line
            Rectangle()
                .fill(Color.primary.opacity(hour == 0 ? 0 : 0.08))
                .frame(height: 0.5)
                .frame(maxWidth: .infinity)
        }
        .frame(height: hourHeight, alignment: .top)
    }

    private var label: String {
        switch hour {
        case 0:  return ""       // midnight – no label, timeline scrolls past it
        case 12: return "noon"
        default: return "\(hour)"
        }
    }
}

// MARK: - All-Day Event Row

private struct DayAllDayRow: View {
    let event: CalendarEvent

    @State private var showingDetail = false

    var body: some View {
        Button { showingDetail = true } label: {
            HStack(spacing: 10) {
                // Birthday gets a gift icon; everything else a color dot
                if event.calendarTitle.localizedCaseInsensitiveContains("birthday") {
                    Image(systemName: "gift.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(hex: event.calendarColorHex))
                } else {
                    Circle()
                        .fill(Color(hex: event.calendarColorHex))
                        .frame(width: 8, height: 8)
                }
                Text(event.title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingDetail) {
            EventDetailView(event: event)
        }
    }
}

// MARK: - Event Block (timeline tile)

private struct DayEventBlock: View {
    let event:       CalendarEvent
    let blockHeight: CGFloat

    @State private var showingDetail = false

    private var isPast:          Bool { event.endDate < Date() }
    private var isStruckThrough: Bool { event.isCancelled }

    var body: some View {
        Button { showingDetail = true } label: {
            HStack(spacing: 0) {
                // Colored left border
                RoundedRectangle(cornerRadius: 2)
                    .fill(calendarColor)
                    .frame(width: 3)

                // Text content
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(blockHeight > 40 ? 2 : 1)
                        .fixedSize(horizontal: false, vertical: true)
                        .strikethrough(isStruckThrough, color: .primary)

                    if blockHeight > 46, !event.isAllDay {
                        Text(startTimeText)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, 5)
                .padding(.vertical, 4)
                .padding(.trailing, 4)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(calendarColor.opacity(isPast ? 0.08 : 0.15))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(calendarColor.opacity(0.25), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .opacity(isPast ? 0.46 : 1.0)
        .sheet(isPresented: $showingDetail) {
            EventDetailView(event: event)
        }
    }

    private var calendarColor: Color { Color(hex: event.calendarColorHex) }

    private var startTimeText: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .none
        fmt.timeStyle = .short
        return fmt.string(from: event.startDate)
    }
}

// MARK: - Color Helper

private extension Color {
    init(hex: String) {
        let s = hex.replacingOccurrences(of: "#", with: "")
        guard s.count == 6, let v = Int(s, radix: 16) else { self = .gray; return }
        self = Color(
            red:   Double((v >> 16) & 0xFF) / 255,
            green: Double((v >>  8) & 0xFF) / 255,
            blue:  Double( v        & 0xFF) / 255
        )
    }
}
