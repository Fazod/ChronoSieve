# ChronoSieve

ChronoSieve is an iOS + watchOS calendar app prototype that reads native iOS calendars via EventKit and filters events with regex rules.

## Current status
- ✅ Planning document created (`PROJECT_PLAN.md`)
- ✅ Project scaffolded (iOS + watchOS sources)
- ✅ Regex filtering engine implemented
- ✅ EventKit read integration implemented (iOS)
- ✅ Filter rule CRUD UI implemented (add/edit/delete/toggle)
- ✅ Filter rules persisted with SwiftData
- ✅ Basic watch sync plumbing via WatchConnectivity
- ✅ watchOS range views for Today + Next 7 Days
- ✅ Agenda UI polish with richer day headers and denser event rows
- ✅ Calendar-mode day view (graphical date picker + selected-day events)
- ✅ Hidden-events debug sheet in iOS agenda
- ✅ Calendar on/off picker (per-calendar toggles)
- ✅ Unit tests for regex filter engine
- ✅ Rudimentary UI tests for rule manager flow (currently excluded from the default scheme)
- ✅ Recurrence/timezone/DST hardening in calendar fetch pipeline
- ✅ Debounced and optimized refresh/date-window fetching
- ✅ Built-in mock calendar data for simulator + UI testing
- ✅ iOS + watchOS simulator builds passing

## Generate the Xcode project

```bash
cd /Users/fdenk/ChronoSieve
xcodegen generate
```

This creates `ChronoSieve.xcodeproj`.

## Open in Xcode

```bash
open ChronoSieve.xcodeproj
```

## Build notes
- Use your free Apple ID for signing.
- The app automatically uses built-in mock calendar data on simulators and during UI tests.
- Pass the `REAL_CALENDAR` launch argument if you want to force real EventKit access instead.
- The default `ChronoSieve` scheme currently runs unit tests only; UI tests are kept out of the default loop for faster iteration.
- You can run on your personal iPhone/Apple Watch.
- Distribution (App Store/TestFlight) requires paid Apple Developer Program.

## Build an AltStore IPA

To build an unsigned `.ipa` for AltStore Classic:

```bash
./scripts/make-altstore-ipa.sh
```

If AltStore has trouble installing the full app bundle, build a phone-only IPA without the embedded watch companion:

```bash
./scripts/make-altstore-ipa-phone-only.sh
```

Output:

```text
build/AltStore/ChronoSieve-<version>-<build>.ipa
build/AltStore/ChronoSieve-<version>-<build>-phone-only.ipa
```

See `Docs/ALTSTORE_IPA.md` for details.

## Next implementation steps
1. Expand UI tests from rudimentary to full CRUD edge cases
2. Run and verify on personal iPhone + Apple Watch (`Docs/ON_DEVICE_RUN.md`)
3. Refine watch UX and complication support
4. Add recurrence-focused regression tests
5. Add optional complication/widget surfacing
