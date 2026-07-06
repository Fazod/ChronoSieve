# Build an AltStore IPA

ChronoSieve can be packaged as an **unsigned** `.ipa` for AltStore Classic.
AltStore/AltServer will re-sign it with your Apple ID during installation.

## Commands

From the repo root:

### Standard IPA (includes embedded watch companion)

```bash
./scripts/make-altstore-ipa.sh
```

### Phone-only IPA for AltStore troubleshooting

```bash
./scripts/make-altstore-ipa-phone-only.sh
```

You can also use the main script directly:

```bash
./scripts/make-altstore-ipa.sh --phone-only
```

## Output

The scripts write the IPA here:

```text
build/AltStore/ChronoSieve-<version>-<build>.ipa
build/AltStore/ChronoSieve-<version>-<build>-phone-only.ipa
```

Examples:

```text
build/AltStore/ChronoSieve-1.0-1.ipa
build/AltStore/ChronoSieve-1.0-1-phone-only.ipa
```

## What the script does

1. Regenerates `ChronoSieve.xcodeproj` with `xcodegen`
2. Builds the iPhone app for `generic/platform=iOS`
3. Includes the embedded watch companion app inside the iPhone app bundle
4. Optionally removes the `Watch/` bundle for a phone-only AltStore IPA
5. Packages the resulting app as a standard `Payload/*.app` IPA
6. Leaves signing to AltStore/AltServer

## Install with AltStore

1. AirDrop the IPA to your iPhone or place it in Files
2. Open AltStore
3. Choose the IPA from the share sheet or Files picker
4. Let AltStore/AltServer sign and install it

## Notes

- This is for **AltStore Classic**, not AltStore PAL.
- Because ChronoSieve now includes a watch companion app + watch extension, it may consume multiple AltStore/App IDs when signed with a free Apple ID.
- If AltStore crashes or fails midway through install, try the `-phone-only` IPA first to rule out watch-bundle signing issues.
- Auto-refresh still requires AltServer running on your Mac.
