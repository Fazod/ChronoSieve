import SwiftUI

struct WatchAgendaView: View {
    @ObservedObject var viewModel: WatchAgendaViewModel
    @State private var showMenu = false
    @State private var stickyDay = Calendar.current.startOfDay(for: Date())

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(agendaSections) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                dayHeader(section.day)
                                    .padding(.horizontal, 12)
                                    .background(headerTracker(for: section))

                                if section.events.isEmpty {
                                    emptyState(section.isToday ? "No events today" : "No events")
                                } else {
                                    ForEach(section.events) { event in
                                        WatchEventCard(event: event)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .padding(.top, -10)
                    .padding(.bottom, 54)
                }
                .coordinateSpace(name: "agendaScroll")
                .scrollIndicators(.hidden)
                .onPreferenceChange(DayHeaderPreferenceKey.self, perform: updateStickyDay)

                VStack(spacing: 0) {
                    topFadeOverlay
                    Spacer()
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .ignoresSafeArea()
                .offset(y: -28)
                .allowsHitTesting(false)

                VStack {
                    HStack {
                        Spacer()
                        stickyDayView
                    }
                    .padding(.top, 54)
                    .padding(.trailing, 15)

                    Spacer()
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .offset(y: -72)
                .allowsHitTesting(false)

                VStack {
                    Spacer()

                    HStack {
                        Spacer()
                        floatingMenuButton
                    }
                    .padding(.trailing, 2)
                    .padding(.bottom, -4)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .task {
            viewModel.onAppear()
            stickyDay = Calendar.current.startOfDay(for: Date())
        }
    }

    private var agendaSections: [AgendaSection] {
        let todayStart = Calendar.current.startOfDay(for: Date())

        let today = AgendaSection(
            day: todayStart,
            events: viewModel.events(for: .today),
            isToday: true
        )

        let upcoming = viewModel.groupedEvents(for: .next7Days)
            .filter { Calendar.current.startOfDay(for: $0.day) != todayStart }
            .map {
                AgendaSection(day: $0.day, events: $0.events, isToday: false)
            }

        return [today] + upcoming
    }

    private func headerTracker(for section: AgendaSection) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: DayHeaderPreferenceKey.self,
                value: [
                    DayHeaderPosition(
                        id: section.id,
                        day: section.day,
                        minY: proxy.frame(in: .named("agendaScroll")).minY
                    )
                ]
            )
        }
    }

    private func dayHeader(_ date: Date) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(dayName(date))
                .foregroundStyle(.red)
            Text(" " + monthDay(date))
                .foregroundStyle(.white)
        }
        .font(.system(size: 16, weight: .semibold))
    }

    private var topFadeOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask(
                    LinearGradient(
                        colors: [.black, .black.opacity(0.75), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 58)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.75),
                    Color.black.opacity(0.50),
                    Color.black.opacity(0.25),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 58)
        }
    }

    private var floatingMenuButton: some View {
        Button(action: { showMenu.toggle() }) {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.blue.opacity(0.5), lineWidth: 1.25)
                }
        }
        .buttonStyle(.plain)
    }

    private func emptyState(_ title: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "calendar")
                .font(.headline)
                .foregroundStyle(.gray)
            Text(title)
                .font(.caption)
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var stickyDayView: some View {
        Group {
            if Calendar.current.isDateInToday(stickyDay) {
                Text("Today")
                    .foregroundStyle(.blue)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(dayName(stickyDay))
                        .foregroundStyle(.red)
                    Text(" " + monthDay(stickyDay))
                        .foregroundStyle(.white)
                }
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .lineLimit(1)
    }

    private func updateStickyDay(_ positions: [DayHeaderPosition]) {
        let threshold: CGFloat = 8
        let sorted = positions.sorted { $0.minY < $1.minY }

        if let current = sorted.last(where: { $0.minY <= threshold }) ?? sorted.first {
            stickyDay = current.day
        }
    }

    private func dayName(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return formatter.string(from: date)
    }

    private func monthDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

private struct AgendaSection: Identifiable {
    let day: Date
    let events: [AgendaSnapshotEvent]
    let isToday: Bool

    var id: Date { day }
}

private struct DayHeaderPosition: Equatable {
    let id: Date
    let day: Date
    let minY: CGFloat
}

private struct DayHeaderPreferenceKey: PreferenceKey {
    static var defaultValue: [DayHeaderPosition] = []

    static func reduce(value: inout [DayHeaderPosition], nextValue: () -> [DayHeaderPosition]) {
        value.append(contentsOf: nextValue())
    }
}

private struct WatchEventCard: View {
    let event: AgendaSnapshotEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(timeText)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .monospacedDigit()

                if isRemoteMeeting {
                    Image(systemName: "video.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            Text(event.title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.84))
                .lineLimit(2)

            Text(subtitle)
                .font(.system(size: 10.5, weight: .regular))
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(cardBackground)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        }
    }

    private var cardBackground: some ShapeStyle {
        LinearGradient(
            colors: [
                Color(red: 0.03, green: 0.24, blue: 0.45),
                Color(red: 0.04, green: 0.20, blue: 0.38)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var subtitle: String {
        if let location = event.location, !location.isEmpty {
            return location
        }
        return event.calendarTitle
    }

    private var isRemoteMeeting: Bool {
        guard let location = event.location?.lowercased() else { return false }
        return location.contains("teams") || location.contains("zoom") || location.contains("meet")
    }

    private var timeText: String {
        let now = Date()

        if event.isAllDay {
            return "All-day"
        }

        if event.startDate <= now && now < event.endDate {
            return "ends at " + event.endDate.formatted(date: .omitted, time: .shortened)
        }

        let start = event.startDate.formatted(date: .omitted, time: .shortened)
        let end = event.endDate.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }
}
