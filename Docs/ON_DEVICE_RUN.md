# On-Device Run Checklist (iPhone + Apple Watch)

Use this checklist to complete the final MVP criterion: run ChronoSieve end-to-end on your personal devices with a free Apple ID.

## 1) Preconditions
- Xcode installed and updated
- iPhone connected via cable (recommended for first deploy)
- Apple Watch paired to that iPhone
- Same Apple ID signed into Xcode and iPhone

## 2) Xcode signing setup
1. Open `ChronoSieve.xcodeproj`
2. Select target **ChronoSieve** → **Signing & Capabilities**
3. Set Team to your personal Apple ID
4. Ensure bundle ID is unique (if needed)
5. Repeat for target **ChronoSieveWatch**

If Xcode prompts to register device/trust computer, accept all prompts.

## 3) iPhone app run
1. Select scheme **ChronoSieve**
2. Select your physical iPhone as run destination
3. Build & Run
4. On first launch, allow calendar access

Expected:
- Agenda appears
- Filter menu works
- Rule manager opens and saves rules

## 4) Watch app run
1. Keep iPhone unlocked and watch nearby
2. Select scheme **ChronoSieveWatch**
3. Choose watch run destination (paired physical watch)
4. Build & Run

Expected:
- Watch app installs/launches
- Today and Next 7 Days views load

## 5) Sync verification (phone → watch)
1. In iPhone app, create a rule hiding a known event
2. Trigger refresh in iPhone app
3. Open watch app and confirm event is hidden there too
4. Disable/delete the rule and confirm event reappears after refresh

## 6) Edge-case sanity checks
- Recurring event appears across expected days
- All-day event around DST transition day still appears correctly
- Ongoing event crossing midnight appears in date-range windows

## 7) Completion criteria
Mark MVP complete when all are true:
- iPhone app runs on device
- Watch app runs on device
- Calendar read permissions function
- Rule filtering works on phone
- Filtered snapshot sync works on watch
