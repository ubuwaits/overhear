#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
APP_NAME="Overhear"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
BUILD_MODE="release"
ACTION="run"

for argument in "$@"; do
    case "$argument" in
        --debug) BUILD_MODE="debug" ;;
        --verify) ACTION="verify" ;;
        --logs) ACTION="logs" ;;
        --telemetry) ACTION="logs" ;;
        *)
            print -u2 "Unknown argument: $argument"
            exit 2
            ;;
    esac
done

if [[ "$ACTION" == "logs" ]]; then
    /usr/bin/log stream --style compact --predicate 'subsystem == "com.chadwin.overhear"'
    exit 0
fi

cd "$ROOT_DIR"
swift test
swift build -c "$BUILD_MODE" --product "$APP_NAME"

EXECUTABLE_PATH="$(swift build -c "$BUILD_MODE" --show-bin-path)/$APP_NAME"

/bin/rm -rf "$APP_BUNDLE"
/bin/mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
/bin/cp "$EXECUTABLE_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
/bin/cp "$ROOT_DIR/Config/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
/usr/bin/codesign --force --deep --sign - \
    --entitlements "$ROOT_DIR/Config/Overhear.entitlements" \
    "$APP_BUNDLE"

if [[ "$ACTION" == "verify" ]]; then
    /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
    /usr/bin/plutil -lint "$APP_BUNDLE/Contents/Info.plist"
    print "$APP_BUNDLE"
    exit 0
fi

/usr/bin/pkill -x "$APP_NAME" 2>/dev/null || true
/usr/bin/open -n "$APP_BUNDLE"
