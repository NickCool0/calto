#!/bin/bash
# Checks a built calto.app for the settings whose absence makes macOS silently misbehave:
# menu-bar-only mode, calendar usage description, sandbox + calendar entitlements, signature.
set -euo pipefail

APP="${1:?usage: verify-bundle.sh path/to/calto.app}"
PLIST="$APP/Contents/Info.plist"
BINARY="$APP/Contents/MacOS/calto"
failures=0

fail() { echo "error: $*" >&2; failures=$((failures + 1)); }
ok() { echo "ok: $*"; }

plist_value() { /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null || true; }

[[ -d "$APP" ]] || { echo "error: $APP not found" >&2; exit 1; }

[[ "$(plist_value "$PLIST" LSUIElement)" == "true" ]] \
    && ok "LSUIElement = true (no Dock icon)" || fail "LSUIElement must be true"

[[ -n "$(plist_value "$PLIST" NSCalendarsFullAccessUsageDescription)" ]] \
    && ok "NSCalendarsFullAccessUsageDescription present" || fail "NSCalendarsFullAccessUsageDescription missing"

codesign --verify --strict --verbose=2 "$APP" && ok "signature valid" || fail "codesign --verify failed"

signature_info="$(codesign -dv "$APP" 2>&1)"
grep -q 'flags=.*runtime' <<<"$signature_info" && ok "hardened runtime" || fail "hardened runtime not enabled"

entitlements="$(mktemp)"
trap 'rm -f "$entitlements"' EXIT
codesign -d --entitlements - --xml "$APP" >"$entitlements" 2>/dev/null
for key in com.apple.security.app-sandbox com.apple.security.personal-information.calendars; do
    [[ "$(plist_value "$entitlements" "$key")" == "true" ]] && ok "entitlement $key" || fail "entitlement $key missing"
done

[[ "$(lipo -archs "$BINARY")" == *arm64* ]] && ok "arm64 binary" || fail "binary is not arm64"

for file in Localizable.strings InfoPlist.strings; do
    [[ -f "$APP/Contents/Resources/ru.lproj/$file" ]] && ok "ru.lproj/$file" || fail "ru.lproj/$file missing"
done

if ((failures > 0)); then
    echo "$failures check(s) failed" >&2
    exit 1
fi
echo "bundle verified"
