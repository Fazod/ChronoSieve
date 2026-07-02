import EventKit
import EventKitUI
import SwiftUI
import UIKit

// MARK: - Event Detail Sheet

struct EventDetailView: View {
    let event: CalendarEvent

    @EnvironmentObject private var viewModel: AgendaViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var showAllNotes = false
    @State private var showingCalendarPicker = false
    @State private var showingRSVPEditor = false
    @State private var showingRSVPPicker = false
    @State private var rsvpStatusOverride: RSVPStatus? = nil
    @State private var rsvpEditStore: EKEventStore?
    @State private var rsvpEditEvent: EKEvent?

    // Optimistic local state — updates immediately when user picks a new calendar
    @State private var localCalendarTitle: String
    @State private var localCalendarColorHex: String

    init(event: CalendarEvent) {
        self.event = event
        _localCalendarTitle    = State(initialValue: event.calendarTitle)
        _localCalendarColorHex = State(initialValue: event.calendarColorHex)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {

                    // Title + date/time/recurrence (no card)
                    titleSection
                        .padding(.bottom, 24)

                    // Notes / meeting link
                    if hasNotesContent {
                        sectionCard { notesCardContent }
                            .padding(.bottom, 16)
                    }

                    // Attendees
                    if !event.attendees.isEmpty {
                        sectionCard { attendeesCardContent }
                            .padding(.bottom, 16)
                    }

                    // Calendar / location info
                    sectionCard { calendarInfoContent }

                    Spacer().frame(height: 44)
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showingCalendarPicker) {
                EventCalendarPickerView(
                    calendars: viewModel.availableCalendars,
                    currentCalendarID: event.calendarID,
                    onSelect: { selected in
                        // Optimistic update
                        localCalendarTitle    = selected.title
                        localCalendarColorHex = selected.colorHex
                        Task { await viewModel.moveEvent(event, toCalendarID: selected.id) }
                    }
                )
            }
            .navigationDestination(isPresented: $showingRSVPPicker) {
                EventRSVPPickerView(
                    currentStatus: displayedRSVPStatus,
                    onSelect: { rsvpStatusOverride = $0 }
                )
            }
            .sheet(isPresented: $showingRSVPEditor) {
                if let store = rsvpEditStore, let ekEvent = rsvpEditEvent {
                    EKEventEditRepresentable(eventStore: store, event: ekEvent) {
                        showingRSVPEditor = false
                    }
                    .ignoresSafeArea()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.left")
                                .font(.body.weight(.semibold))
                            Text(navDateLabel)
                                .font(.body.weight(.medium))
                        }
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: – Title Section

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Calendar color stripe + title
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: event.calendarColorHex))
                    .frame(width: 4)
                    .padding(.top, 4)

                Text(event.title)
                    .font(.title.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(fullDateString)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if !event.isAllDay {
                    Text(timeRangeString)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let recurrence = event.recurrenceDescription {
                    Text(recurrence)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
            .padding(.leading, 14)
        }
    }

    // MARK: – Notes Card

    private var notesCardContent: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Meeting join button
            if let meetingURL = primaryMeetingURL {
                Button {
                    openURL(meetingURL)
                } label: {
                    HStack {
                        Label(meetingServiceName(for: meetingURL), systemImage: meetingIcon(for: meetingURL))
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.right.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.blue)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.plain)

                if trimmedNotes != nil || !nonMeetingLinks.isEmpty {
                    Divider().padding(.leading, 16)
                }
            }

            // Notes text
            if let notes = trimmedNotes, !notes.isEmpty {
                Text(notes)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(showAllNotes ? nil : 5)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                let isLong = notes.count > 220 || notes.components(separatedBy: "\n").count > 5
                if isLong {
                    Divider().padding(.leading, 16)

                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            showAllNotes.toggle()
                        }
                    } label: {
                        HStack {
                            Text(showAllNotes ? "Show Less" : "Show All Notes")
                                .font(.footnote.weight(.medium))
                            Spacer()
                            Image(systemName: showAllNotes ? "chevron.up" : "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Extra (non-meeting) links
            ForEach(Array(nonMeetingLinks.enumerated()), id: \.element.absoluteString) { index, url in
                if index > 0 || primaryMeetingURL != nil || trimmedNotes != nil {
                    Divider().padding(.leading, 16)
                }
                Button {
                    openURL(url)
                } label: {
                    HStack {
                        Label(url.host ?? url.absoluteString, systemImage: "link")
                            .font(.footnote)
                            .lineLimit(1)
                            .foregroundStyle(.blue)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: – Attendees Card

    private var attendeesCardContent: some View {
        VStack(spacing: 0) {
            rsvpResponseRow

            Divider().padding(.leading, 16)

            ForEach(Array(event.attendees.enumerated()), id: \.element.id) { index, attendee in
                AttendeeRow(attendee: attendee)

                if index < event.attendees.count - 1 {
                    // indent separator to align with text, after the avatar
                    Divider().padding(.leading, 16 + 44 + 12)
                }
            }
        }
    }

    // MARK: – RSVP Row

    private var rsvpResponseRow: some View {
        Button {
            openRSVPEditor()
        } label: {
            HStack {
                Text("Your Response")
                    .font(.body)
                    .foregroundStyle(.primary)
                Spacer()
                HStack(spacing: 6) {
                    rsvpStatusIcon(for: displayedRSVPStatus)
                        .font(.body)
                    Text(rsvpStatusLabel(for: displayedRSVPStatus))
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func rsvpStatusIcon(for status: RSVPStatus) -> some View {
        switch status {
        case .accepted:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .declined:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .tentative:
            Image(systemName: "questionmark.circle.fill").foregroundStyle(.orange)
        case .notResponded, .unknown:
            Image(systemName: "clock.circle").foregroundStyle(Color(.systemGray3))
        }
    }

    private func rsvpStatusLabel(for status: RSVPStatus) -> String {
        switch status {
        case .accepted:     return "Accepted"
        case .declined:     return "Declined"
        case .tentative:    return "Maybe"
        case .notResponded: return "Not Responded"
        case .unknown:      return "Unknown"
        }
    }

    private var displayedRSVPStatus: RSVPStatus {
        rsvpStatusOverride ?? event.rsvpStatus
    }

    private func openRSVPEditor() {
        if let (store, ekEvent) = viewModel.rsvpEdit(for: event) {
            // Real EventKit event — open system edit view (sends response to server)
            rsvpEditStore = store
            rsvpEditEvent = ekEvent
            showingRSVPEditor = true
        } else {
            // Mock / unsupported calendar — fall back to local picker
            showingRSVPPicker = true
        }
    }

    // MARK: – Calendar Info Card

    private var calendarInfoContent: some View {
        VStack(spacing: 0) {
            Button {
                showingCalendarPicker = true
            } label: {
                HStack {
                    Text("Calendar")
                        .font(.body)
                        .foregroundStyle(.primary)
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(hex: localCalendarColorHex))
                            .frame(width: 10, height: 10)
                        Text(localCalendarTitle)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 4)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)

            if let location = event.location, !location.isEmpty {
                Divider().padding(.leading, 16)

                HStack(alignment: .top) {
                    Text("Location")
                        .font(.body)
                    Spacer()
                    Text(location)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
    }

    // MARK: – Card Container

    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: – Computed helpers

    private var navDateLabel: String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEMMMd")
        return formatter.string(from: event.startDate)
    }

    private var fullDateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter.string(from: event.startDate)
    }

    private var timeRangeString: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .none
        fmt.timeStyle = .short
        return "from \(fmt.string(from: event.startDate)) to \(fmt.string(from: event.endDate))"
    }

    private var trimmedNotes: String? {
        let t = event.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (t?.isEmpty == true) ? nil : t
    }

    private var hasNotesContent: Bool {
        primaryMeetingURL != nil || trimmedNotes != nil || !nonMeetingLinks.isEmpty
    }

    private var allDetectedURLs: [URL] {
        let sources = [event.location, event.notes]
            .compactMap { $0 }
            .joined(separator: "\n")
        guard !sources.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return [] }

        let range = NSRange(sources.startIndex..<sources.endIndex, in: sources)
        var seen = Set<String>()
        return detector
            .matches(in: sources, options: [], range: range)
            .compactMap(\.url)
            .filter { seen.insert($0.absoluteString).inserted }
    }

    private let meetingDomains = [
        "teams.microsoft.com", "zoom.us", "meet.google.com",
        "webex.com", "whereby.com", "gotomeet.me", "webex.com",
        "chime.aws", "bluejeans.com"
    ]

    private func isMeetingURL(_ url: URL) -> Bool {
        guard let host = url.host else { return false }
        return meetingDomains.contains { host.hasSuffix($0) }
    }

    private var primaryMeetingURL: URL? {
        allDetectedURLs.first { isMeetingURL($0) }
    }

    private var nonMeetingLinks: [URL] {
        allDetectedURLs.filter { !isMeetingURL($0) }
    }

    private func meetingServiceName(for url: URL) -> String {
        guard let host = url.host else { return "Join Meeting" }
        if host.hasSuffix("teams.microsoft.com") { return "Microsoft Teams Meeting" }
        if host.hasSuffix("zoom.us")             { return "Zoom Meeting" }
        if host.hasSuffix("meet.google.com")     { return "Google Meet" }
        if host.hasSuffix("webex.com")           { return "Webex Meeting" }
        if host.hasSuffix("whereby.com")         { return "Whereby Meeting" }
        if host.hasSuffix("chime.aws")           { return "Amazon Chime" }
        if host.hasSuffix("bluejeans.com")       { return "BlueJeans Meeting" }
        return "Join Meeting"
    }

    private func meetingIcon(for url: URL) -> String {
        guard let host = url.host else { return "video" }
        if host.hasSuffix("teams.microsoft.com") { return "video.fill" }
        if host.hasSuffix("zoom.us")             { return "video.fill" }
        if host.hasSuffix("meet.google.com")     { return "video.fill" }
        return "video.fill"
    }
}

// MARK: - Attendee Row

private struct AttendeeRow: View {
    let attendee: Attendee
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 12) {
            AttendeeAvatar(attendee: attendee)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(attendee.name)
                    .font(.body)
                    .lineLimit(1)

                Group {
                    if attendee.isOrganizer {
                        Text("Organizer")
                    } else if attendee.isOptional {
                        Text("Optional")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            // Contact actions
            if let email = attendee.email {
                Button {
                    if let url = URL(string: "mailto:\(email)") {
                        openURL(url)
                    }
                } label: {
                    Image(systemName: "envelope")
                        .font(.body)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Attendee Avatar

private struct AttendeeAvatar: View {
    let attendee: Attendee

    @EnvironmentObject private var contactsService: ContactsService
    @State private var contactPhoto: UIImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(avatarColor)

            if let photo = contactPhoto {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
            } else {
                Text(attendee.initials)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }

            rsvpBadge
                .offset(x: 3, y: 3)
        }
        .task(id: attendee.id) {
            contactPhoto = await contactsService.photo(for: attendee)
        }
    }

    // Deterministic color from name hash
    private var avatarColor: Color {
        let palette: [(Double, Double, Double)] = [
            (0.55, 0.60, 0.65),  // slate
            (0.20, 0.54, 0.88),  // blue
            (0.12, 0.70, 0.52),  // teal
            (0.86, 0.44, 0.20),  // orange
            (0.62, 0.32, 0.78),  // purple
            (0.82, 0.26, 0.28),  // red
            (0.16, 0.66, 0.36),  // green
            (0.88, 0.65, 0.08),  // amber
        ]
        var hash = 5381
        for scalar in attendee.name.unicodeScalars {
            hash = ((hash << 5) &+ hash) &+ Int(scalar.value)
        }
        let (r, g, b) = palette[abs(hash) % palette.count]
        return Color(red: r, green: g, blue: b)
    }

    @ViewBuilder
    private var rsvpBadge: some View {
        switch attendee.rsvpStatus {
        case .accepted:
            rsvpCircle(color: .green, icon: "checkmark")
        case .declined:
            rsvpCircle(color: .red, icon: "xmark")
        case .tentative:
            rsvpCircle(color: .orange, icon: "questionmark")
        case .notResponded, .unknown:
            rsvpCircle(color: Color(.systemGray3), icon: "questionmark")
        }
    }

    private func rsvpCircle(color: Color, icon: String) -> some View {
        ZStack {
            Circle()
                .fill(Color(.systemBackground))
                .frame(width: 18, height: 18)
            Circle()
                .fill(color)
                .frame(width: 15, height: 15)
            Image(systemName: icon)
                .font(.system(size: 7.5, weight: .black))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - RSVP Picker (push destination inside EventDetailView's NavigationStack)

private struct EventRSVPPickerView: View {
    let currentStatus: RSVPStatus
    let onSelect: (RSVPStatus) -> Void

    @Environment(\.dismiss) private var dismiss

    private let options: [(status: RSVPStatus, label: String, icon: String, color: Color)] = [
        (.accepted,  "Accept",  "checkmark.circle.fill",   .green),
        (.tentative, "Maybe",   "questionmark.circle.fill", .orange),
        (.declined,  "Decline", "xmark.circle.fill",        .red),
    ]

    var body: some View {
        List {
            ForEach(options, id: \.status) { option in
                Button {
                    onSelect(option.status)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: option.icon)
                            .foregroundStyle(option.color)
                            .font(.body)

                        Text(option.label)
                            .foregroundStyle(.primary)

                        Spacer()

                        if currentStatus == option.status {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                                .fontWeight(.semibold)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Your Response")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Calendar Picker (push destination inside EventDetailView's NavigationStack)

private struct EventCalendarPickerView: View {
    let calendars: [CalendarSource]
    let currentCalendarID: String
    let onSelect: (CalendarSource) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(calendars) { calendar in
            Button {
                onSelect(calendar)
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color(hex: calendar.colorHex))
                        .frame(width: 12, height: 12)

                    Text(calendar.title)
                        .foregroundStyle(.primary)

                    Spacer()

                    if calendar.id == currentCalendarID {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.blue)
                            .fontWeight(.semibold)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Color helper (local)

private extension Color {
    init(hex: String) {
        let sanitized = hex.replacingOccurrences(of: "#", with: "")
        guard sanitized.count == 6, let value = Int(sanitized, radix: 16) else {
            self = .gray; return
        }
        self = Color(
            red:   Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8)  & 0xFF) / 255.0,
            blue:  Double(value         & 0xFF) / 255.0
        )
    }
}

// MARK: - Preview

#Preview {
    EventDetailView(event: MockCalendarFixtures.events().first(where: { $0.id == "mock-standup" })!)
        .environmentObject(AgendaViewModel(calendarService: MockCalendarService()))
        .environmentObject(ContactsService())
}
