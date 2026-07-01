# ChronoSieve — Project Plan

## App Name
**ChronoSieve**

## Vision
ChronoSieve is an iOS + watchOS calendar app that reads native iOS account calendars via EventKit and lets users hide/show events using regex-based rules, with a polished Fantastical-inspired UX.

---

## Constraints
- No paid Apple Developer account available.
- Development target: personal use on own devices via Xcode + free Apple ID.
- No App Store / TestFlight distribution in v1.

---

## v1 Scope

### Core Features
1. EventKit integration with native iOS account calendars.
2. Regex rule engine for filtering events.
3. Fantastical-inspired agenda UI in SwiftUI.
4. watchOS companion app showing filtered agenda.

### Out of Scope (v1)
- Public distribution.
- Team collaboration features.
- Advanced NLP event creation.

---

## Architecture
- **UI:** SwiftUI (iOS + watchOS)
- **Calendar API:** EventKit (`EKEventStore`)
- **Persistence:** SwiftData (fallback: UserDefaults)
- **Sync to watch:** WatchConnectivity
- **Modules:**
  - `CalendarService` (EventKit read/auth/updates)
  - `FilterEngine` (regex compile/apply/validate)
  - `EventRepository` (cache + timeline windows)
  - `WatchSyncService` (phone→watch snapshot sync)

---

## Phased Execution Plan

## Phase 0 — Project Setup (1–2 days)
- [x] Create Xcode project scaffold with iOS app + watchOS app + shared code folders.
- [x] Add calendar permissions text in Info.plist (`NSCalendarsFullAccessUsageDescription`).
- [x] Define models: `CalendarEvent`, `FilterRule`.
- [x] Resolve local Xcode platform mismatch and run both targets on simulator/devices.

**Deliverable:** App targets run on simulator/devices.

## Phase 1 — EventKit Integration (3–4 days)
- [x] Implement authorization flow for EventKit.
- [x] Fetch events by date window (today/week/month).
- [x] Observe `EKEventStoreChanged` for live updates.
- [x] Map `EKEvent` into app domain model.

**Deliverable:** Agenda list populated from native calendars.

## Phase 2 — Regex Filter Engine (4–6 days)
- [x] Rule schema: enabled, include/exclude, target fields, case sensitivity, pattern.
- [x] Compile/cached regex for performance.
- [x] Validation UI for invalid regex.
- [x] Preview impact (e.g., hidden event count).

**Deliverable:** Event filtering works in real time.

## Phase 3 — iOS UI (Fantastical-inspired) (1–2 weeks)
- [x] Build agenda timeline with day grouping and all-day sections.
- [x] Preserve calendar color identity.
- [x] Add filter management screens and quick toggles.
- [x] Add hidden-events debug view.

**Deliverable:** Premium-feel daily driver UI.

## Phase 4 — watchOS Companion (1 week)
- [x] Build Today and Next 7 Days watch views.
- [x] Sync filtered data from iPhone using WatchConnectivity.
- [x] Cache latest snapshot on watch for offline display.

**Deliverable:** watchOS app mirrors filtered agenda.

## Phase 5 — Stabilization & Testing (4–6 days)
- [x] Handle recurrence/timezone/DST edge cases.
- [x] Optimize refresh and date-window fetches.
- [x] Unit tests for filter semantics + UI tests for rule CRUD. (rudimentary UI coverage)

**Deliverable:** Stable personal-use build.

---

## Done Criteria (MVP)
- [x] App requests calendar permission and reads account calendars.
- [x] User can create regex hide/show rules.
- [x] Agenda updates instantly with filtered data.
- [x] watchOS companion displays matching filtered agenda.
- [ ] Works on personal iPhone + Apple Watch via Xcode run.

---

## Suggested Timeline
- Week 1: Setup + EventKit
- Week 2: Regex engine + rule UX
- Week 3: iOS UI polish
- Week 4: watchOS + hardening
