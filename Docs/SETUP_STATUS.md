# Setup Status

## Completed
- Created project folder: `/Users/fdenk/ChronoSieve`
- Added initial plan: `PROJECT_PLAN.md`
- Installed `xcodegen`
- Added scaffolded source structure for:
  - iOS app target
  - watchOS app target
  - shared filtering/models/sync code
- Generated Xcode project: `ChronoSieve.xcodeproj`

## Local machine issue detected
`xcodebuild` reports a CoreSimulator/platform mismatch:
- CoreSimulator installed: `1051.50.0`
- Xcode expects: `1051.55.0`
- Also reports missing iOS platform runtime (`iOS 26.5`)

## Fix
In Xcode:
1. Open **Xcode → Settings → Components**
2. Install/update the missing iOS/watchOS platform runtimes
3. Update macOS/Xcode if prompted
4. Re-run build

## Completed after runtime fix
- ✅ Implemented filter rule CRUD UI (add/edit/delete/enable/disable)
- ✅ Added SwiftData persistence for regex rules
- ✅ Hooked persisted rules into agenda filtering in real time
- ✅ Added default seed rule (disabled): "Hide birthdays"
- ✅ Added live EventKit refresh via `EKEventStoreChanged`
- ✅ Added day grouping/all-day split and hidden-events summary in agenda UI
- ✅ Added watch range switcher with Today + Next 7 Days views
- ✅ Polished iOS day headers and event row hierarchy for a denser agenda feel
- ✅ Added hidden-events debug sheet in iOS
- ✅ Added calendar-mode day view in iOS
- ✅ Added per-calendar on/off selection in iOS
- ✅ Added and ran regex filter unit tests (5 passing)
- ✅ Added rudimentary UI tests for rule manager + regex validation (currently excluded from default test runs)
- ✅ Added built-in mock calendar data for simulator + UI testing
- ✅ Hardened calendar mapping for recurrence/timezone/DST edge cases
- ✅ Optimized refresh/date-window behavior (debounced store refresh + smarter fetch cadence)
- ✅ Verified builds:
  - iOS simulator build succeeds
  - watchOS simulator build succeeds

## Next task
Run end-to-end on personal iPhone + Apple Watch while keeping UI coverage paused from the default test loop until the app matures further.
