#!/bin/zsh
# Usage:  ./build.sh           build build/MiniPlayer.app
#         ./build.sh install   also copy it to /Applications and launch it
#         ./build.sh dist      signed (and, if credentials are stored, notarized) build/MiniPlayer.zip
#                              for other Macs. Notarization credentials, once:
#                              xcrun notarytool store-credentials MiniPlayer --apple-id <id> --team-id <team>
set -euo pipefail
cd "$(dirname "$0")"
MODE="${1:-}"

swift build -c release

APP="build/MiniPlayer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/MiniPlayer" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

# Bundle librespot (it only links system frameworks)
LIBRESPOT="$(command -v librespot || true)"
if [[ -n "$LIBRESPOT" ]]; then
  cp "$(readlink -f "$LIBRESPOT")" "$APP/Contents/MacOS/librespot"
  chmod u+w "$APP/Contents/MacOS/librespot"
  echo "✓ bundled $("$LIBRESPOT" --version 2>/dev/null | cut -d' ' -f1-2)"
else
  echo "⚠︎ librespot not found, built-in playback disabled (brew install librespot)"
fi

# Sign with a stable identity if available, so macOS doesn't ask for Keychain
# access again after every rebuild. Falls back to ad-hoc signing.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | grep -m1 -oE '"(Developer ID Application|Apple Development)[^"]*"' | tr -d '"' || true)}"
TIMESTAMP="--timestamp=none"
[[ "$MODE" == "dist" ]] && TIMESTAMP="--timestamp"
sign() {
  if [[ -n "$IDENTITY" ]]; then
    if out=$(codesign --force --options runtime $TIMESTAMP --sign "$IDENTITY" "$1" 2>&1); then
      return 0
    fi
    echo "⚠︎ signing with certificate failed, using ad-hoc: ${out##*$'\n'}"
  fi
  codesign --force --sign - "$1" >/dev/null
}
[[ -f "$APP/Contents/MacOS/librespot" ]] && sign "$APP/Contents/MacOS/librespot"
sign "$APP"
SIGNED_BY=$(codesign -dvv "$APP" 2>&1 | awk -F= '/^Authority=/{print $2; exit}' || true)
echo "✓ $APP (${SIGNED_BY:-ad-hoc signed})"

if [[ "$MODE" == "install" ]]; then
  pkill -x MiniPlayer 2>/dev/null || true
  for _ in {1..25}; do pgrep -x MiniPlayer >/dev/null || break; sleep 0.2; done
  rm -rf /Applications/MiniPlayer.app
  cp -R "$APP" /Applications/
  open /Applications/MiniPlayer.app
  echo "✓ installed to /Applications and launched"
fi

if [[ "$MODE" == "dist" ]]; then
  [[ "$IDENTITY" == Developer\ ID* ]] || { echo "✗ dist needs a Developer ID Application certificate"; exit 1; }
  codesign --verify --deep --strict "$APP"
  ZIP="build/MiniPlayer.zip"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  PROFILE="${NOTARY_PROFILE:-MiniPlayer}"
  if xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    echo "… notarizing (usually 1–5 minutes)"
    xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
    xcrun stapler staple "$APP"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    spctl --assess --type execute --verbose "$APP"
    echo "✓ $ZIP (signed and notarized)"
  else
    echo "✓ $ZIP (signed, NOT notarized: no notarytool profile \"$PROFILE\")"
  fi
fi
