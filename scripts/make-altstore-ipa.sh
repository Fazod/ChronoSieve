#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/ChronoSieve.xcodeproj"
PROJECT_SPEC="$ROOT_DIR/project.yml"
SCHEME="ChronoSieve"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_PATH="$ROOT_DIR/build/AltStoreDerivedData"
OUTPUT_DIR="$ROOT_DIR/build/AltStore"
PAYLOAD_DIR="$OUTPUT_DIR/Payload"
APP_NAME="ChronoSieve"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/${CONFIGURATION}-iphoneos/${APP_NAME}.app"
INFO_PLIST="$ROOT_DIR/Resources/iOS/Info.plist"
PLIST_BUDDY="/usr/libexec/PlistBuddy"
PHONE_ONLY="${ALTSTORE_PHONE_ONLY:-0}"
WATCH_APP_PATH="${PAYLOAD_DIR}/${APP_NAME}.app/Watch/ChronoSieveWatch.app"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phone-only)
      PHONE_ONLY=1
      shift
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      echo "usage: $0 [--phone-only]" >&2
      exit 1
      ;;
  esac
done

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen is required but not installed" >&2
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "error: xcodebuild is required but not installed" >&2
  exit 1
fi

if ! command -v ditto >/dev/null 2>&1; then
  echo "error: ditto is required but not available" >&2
  exit 1
fi

if ! command -v zip >/dev/null 2>&1; then
  echo "error: zip is required but not available" >&2
  exit 1
fi

VERSION="$($PLIST_BUDDY -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
BUILD_NUMBER="$($PLIST_BUDDY -c 'Print :CFBundleVersion' "$INFO_PLIST")"
IPA_SUFFIX=""
if [[ "$PHONE_ONLY" == "1" ]]; then
  IPA_SUFFIX="-phone-only"
fi
IPA_PATH="$OUTPUT_DIR/${APP_NAME}-${VERSION}-${BUILD_NUMBER}${IPA_SUFFIX}.ipa"

cd "$ROOT_DIR"

echo "==> Regenerating Xcode project"
xcodegen generate >/dev/null

echo "==> Building ${SCHEME} (${CONFIGURATION}) for generic iPhone"
rm -rf "$DERIVED_DATA_PATH" "$PAYLOAD_DIR" "$IPA_PATH"

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build \
  CODE_SIGNING_ALLOWED=NO

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: built app not found at $APP_PATH" >&2
  exit 1
fi

mkdir -p "$PAYLOAD_DIR"
ditto "$APP_PATH" "$PAYLOAD_DIR/${APP_NAME}.app"

if [[ -d "$WATCH_APP_PATH" ]]; then
  echo "==> Embedded watch companion detected"
  if [[ "$PHONE_ONLY" == "1" ]]; then
    echo "==> Removing embedded watch companion for phone-only AltStore build"
    rm -rf "$PAYLOAD_DIR/${APP_NAME}.app/Watch"
  fi
else
  echo "warning: embedded watch companion was not found in the packaged app" >&2
fi

(
  cd "$OUTPUT_DIR"
  zip -qry "$(basename "$IPA_PATH")" Payload
)

rm -rf "$PAYLOAD_DIR"

echo

echo "Created unsigned AltStore IPA:"
echo "  $IPA_PATH"
echo
if [[ "$PHONE_ONLY" == "1" ]]; then
  echo "Build mode:"
  echo "  Phone-only (embedded watch companion removed before packaging)"
  echo
fi

echo "Next steps:"
echo "  1. AirDrop or copy the IPA to your iPhone"
echo "  2. Open it with AltStore"
echo "  3. Let AltStore/AltServer re-sign it with your Apple ID"
