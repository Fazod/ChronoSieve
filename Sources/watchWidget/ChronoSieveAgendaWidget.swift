import AppIntents
import RelevanceKit
import SwiftUI
import WidgetKit

@available(watchOS 26.0, *)
struct DailyAgendaWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Upcoming Event"
    static var description = IntentDescription("Automatically surfaces your visible ChronoSieve events in the Smart Stack.")

    static var parameterSummary: some ParameterSummary {
        Summary("Upcoming Event")
    }

    @Parameter(title: "Event Identifier")
    var eventID: String?

    init() {
        eventID = nil
    }

    init(eventID: String) {
        self.eventID = eventID
    }
}

@available(watchOS 26.0, *)
struct DailyAgendaWidgetEntry: RelevanceEntry {
    let generatedAt: Date?
    let event: AgendaSnapshotEvent?
    let eventIndex: Int
    let totalEvents: Int
}

@available(watchOS 26.0, *)
struct DailyAgendaRelevanceProvider: RelevanceEntriesProvider {
    typealias Entry = DailyAgendaWidgetEntry
    typealias Configuration = DailyAgendaWidgetIntent

    func placeholder(context: Context) -> DailyAgendaWidgetEntry {
        let events = AgendaSnapshotPlanner.todayEvents(from: mockSnapshot())
        return makeEntry(for: events.first?.id, snapshotGeneratedAt: Date(), events: events)
    }

    func entry(configuration: DailyAgendaWidgetIntent, context: Context) async throws -> DailyAgendaWidgetEntry {
        let snapshot = AgendaSnapshotStore.load(preferSharedStore: true) ?? mockSnapshotIfNeeded()
        let events = AgendaSnapshotPlanner.todayEvents(from: snapshot)
        return makeEntry(for: configuration.eventID, snapshotGeneratedAt: snapshot?.generatedAt, events: events)
    }

    func relevance() async -> WidgetRelevance<DailyAgendaWidgetIntent> {
        let snapshot = AgendaSnapshotStore.load(preferSharedStore: true) ?? mockSnapshotIfNeeded()
        let events = AgendaSnapshotPlanner.todayEvents(from: snapshot)

        let attributes = events.map { event in
            WidgetRelevanceAttribute(
                configuration: DailyAgendaWidgetIntent(eventID: event.id),
                context: RelevantContext.date(range: relevanceRange(for: event), kind: .scheduled)
            )
        }

        return WidgetRelevance(attributes)
    }

    private func makeEntry(
        for eventID: String?,
        snapshotGeneratedAt: Date?,
        events: [AgendaSnapshotEvent]
    ) -> DailyAgendaWidgetEntry {
        let selectedIndex = events.firstIndex(where: { $0.id == eventID }) ?? 0
        let selectedEvent = events.indices.contains(selectedIndex) ? events[selectedIndex] : nil

        return DailyAgendaWidgetEntry(
            generatedAt: snapshotGeneratedAt,
            event: selectedEvent,
            eventIndex: selectedEvent == nil ? 0 : selectedIndex + 1,
            totalEvents: events.count
        )
    }

    private func relevanceRange(for event: AgendaSnapshotEvent) -> ClosedRange<Date> {
        if event.isAllDay {
            return event.startDate...event.endDate
        }

        let start = event.startDate.addingTimeInterval(-30 * 60)
        let end = max(event.endDate, event.startDate)
        return start...end
    }

    private func mockSnapshot() -> AgendaSnapshot {
        AgendaSnapshot(
            generatedAt: Date(),
            events: MockCalendarFixtures.events().map(AgendaSnapshotEvent.init(event:))
        )
    }

    private func mockSnapshotIfNeeded() -> AgendaSnapshot? {
        guard RuntimeEnvironment.usesMockCalendarData else {
            return nil
        }

        return mockSnapshot()
    }
}

@available(watchOS 26.0, *)
struct DailyAgendaRelevanceWidget: Widget {
    var body: some WidgetConfiguration {
        RelevanceConfiguration(kind: ChronoSieveWidgetKind.dailyAgenda, provider: DailyAgendaRelevanceProvider()) { entry in
            DailyAgendaWidgetView(entry: entry)
        }
        .configurationDisplayName("Upcoming Event")
        .description("Creates Smart Stack cards for each visible event in your day.")
        .supportedFamilies([.accessoryRectangular])
    }
}

@available(watchOS 26.0, *)
private struct DailyAgendaWidgetView: View {
    let entry: DailyAgendaWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            if let event = entry.event {
                DailyAgendaEventCard(event: event)
            } else {
                Text("No visible events today")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.clear, for: .widget)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Today")
                .font(.system(size: 12, weight: .semibold))

            if entry.totalEvents > 0 {
                Text("\(entry.eventIndex)/\(entry.totalEvents)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer(minLength: 0)

            if let generatedAt = entry.generatedAt {
                Text(generatedAt, style: .time)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

@available(watchOS 26.0, *)
private struct DailyAgendaEventCard: View {
    let event: AgendaSnapshotEvent

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Circle()
                .fill(Color(hex: event.calendarColorHex))
                .frame(width: 6, height: 6)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(2)
                    .strikethrough(event.isCancelled, color: .primary)

                Text(timeText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .monospacedDigit()

                if let location = event.location, !location.isEmpty {
                    Text(location)
                        .font(.system(size: 9.5, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var timeText: String {
        if event.isAllDay {
            return "All-day"
        }

        let start = event.startDate.formatted(date: .omitted, time: .shortened)
        let end = event.endDate.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }
}

private extension Color {
    init(hex: String?) {
        guard let hex, !hex.isEmpty else {
            self = .gray
            return
        }

        let sanitized = hex.replacingOccurrences(of: "#", with: "")
        guard sanitized.count == 6, let value = Int(sanitized, radix: 16) else {
            self = .gray
            return
        }

        self = Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

@available(watchOS 26.0, *)
@main
struct ChronoSieveWatchWidgets: WidgetBundle {
    var body: some Widget {
        DailyAgendaRelevanceWidget()
    }
}
