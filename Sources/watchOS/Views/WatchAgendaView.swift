import SwiftUI

struct WatchAgendaView: View {
    @ObservedObject var viewModel: WatchAgendaViewModel

    @State private var selectedRange: WatchRange = .today

    var body: some View {
        List {
            Picker("Range", selection: $selectedRange) {
                Text("Today").tag(WatchRange.today)
                Text("Next 7d").tag(WatchRange.next7Days)
            }
            .pickerStyle(.navigationLink)

            if let generatedAt = viewModel.generatedAt {
                Text("Synced \(generatedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if selectedRange == .today {
                todaySection
            } else {
                nextSevenDaysSection
            }
        }
        .navigationTitle("ChronoSieve")
        .task {
            viewModel.onAppear()
        }
    }

    @ViewBuilder
    private var todaySection: some View {
        let events = viewModel.events(for: .today)

        if events.isEmpty {
            Text("No events today")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ForEach(events) { event in
                WatchEventRow(event: event)
            }
        }
    }

    @ViewBuilder
    private var nextSevenDaysSection: some View {
        let groups = viewModel.groupedEvents(for: .next7Days)

        if groups.isEmpty {
            Text("No events in next 7 days")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ForEach(groups) { group in
                Section(dayTitle(group.day)) {
                    ForEach(group.events) { event in
                        WatchEventRow(event: event)
                    }
                }
            }
        }
    }

    private func dayTitle(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) {
            return "Today"
        }

        if Calendar.current.isDateInTomorrow(day) {
            return "Tomorrow"
        }

        return day.formatted(date: .abbreviated, time: .omitted)
    }
}

private struct WatchEventRow: View {
    let event: AgendaSnapshotEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(event.title)
                .font(.headline)
                .lineLimit(2)

            Text(timeText)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(event.calendarTitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var timeText: String {
        if event.isAllDay {
            return "All-day"
        }

        let start = event.startDate.formatted(date: .omitted, time: .shortened)
        let end = event.endDate.formatted(date: .omitted, time: .shortened)
        return "\(start)–\(end)"
    }
}
