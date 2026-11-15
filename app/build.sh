#!/usr/bin/env bash
# Builds Tars into build/Tars.app, signed with the Apple Development identity (a stable signature
# keeps Keychain "Always Allow" answers across rebuilds). --install puts it in
# /Applications and relaunches it. --release ignores config.local.env and signs with Developer ID
# (hardened runtime + secure timestamp) for notarization: see ../Kit/tools/release-app.sh.
set -euo pipefail
cd "$(dirname "$0")"

# Optional, gitignored: BUNDLE_ID and SIGN_IDENTITY, see config.example.env.
BUNDLE_ID=app.newitools.Tars
SIGN_IDENTITY=""
RELEASE=0; [[ "${1:-}" == "--release" ]] && RELEASE=1
# A public release never reads the local file: no personal settings in the shipped app.
[ "$RELEASE" = 0 ] && [ -f config.local.env ] && source ./config.local.env

echo "==> Building (release)…"
swift build -c release

APP="build/Tars.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Tars "$APP/Contents/MacOS/Tars"
cp Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/training-manifest.json Resources/requirements.lock "$APP/Contents/Resources/"
cp -R Resources/third-party "$APP/Contents/Resources/third-party"
cp ../NOTICE ../LICENSE "$APP/Contents/Resources/"

# The training code ships inside the app, so no checkout is needed.
echo "==> Bundling the training code"
T="$APP/Contents/Resources/training"
mkdir -p "$T/catalogs"
rsync -a --exclude __pycache__ --exclude '*.pyc' ../pipeline ../tars "$T/"
cp ../catalogs/example.json "$T/catalogs/"

# uv (MIT OR Apache-2.0, astral-sh/uv) sets up Python and the packages on first use. Pinned and checked.
UV_VERSION=$(plutil -extract uv.version raw Resources/training-manifest.json)
UV_SHA=$(plutil -extract uv.sha256 raw Resources/training-manifest.json)
UV_TGZ=".build/uv-$UV_VERSION.tar.gz"
if ! echo "$UV_SHA  $UV_TGZ" | shasum -a 256 -c --status 2>/dev/null; then
  echo "==> Downloading uv $UV_VERSION"
  curl -fsSL -o "$UV_TGZ" "https://github.com/astral-sh/uv/releases/download/$UV_VERSION/uv-aarch64-apple-darwin.tar.gz"
  echo "$UV_SHA  $UV_TGZ" | shasum -a 256 -c --status || { echo "uv checksum mismatch" >&2; exit 1; }
fi
mkdir -p "$APP/Contents/Helpers"
tar xzf "$UV_TGZ" -C "$APP/Contents/Helpers" --strip-components 1 uv-aarch64-apple-darwin/uv   # drawn once with Kit's tools/icon-tile.swift (4f6bd8, point.3.filled.connected.trianglepath.dotted)
echo -n "APPL????" > "$APP/Contents/PkgInfo"

IDENTITY=${SIGN_IDENTITY:-}
if [ "$RELEASE" = 1 ]; then
  [ -n "$IDENTITY" ] || IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/')
  [ -n "$IDENTITY" ] || { echo "No Developer ID Application identity in the keychain" >&2; exit 1; }
  echo "==> Signing for release with $IDENTITY"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP/Contents/Helpers/uv"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
  codesign --verify --strict --verbose=2 "$APP"
  echo "Built $APP (release)"; exit 0
fi
[ -n "$IDENTITY" ] || IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | head -1 | sed -E 's/.*"(.*)"/\1/')
if [ -n "$IDENTITY" ]; then
  echo "==> Signing with $IDENTITY"
  codesign --force --options runtime --sign "$IDENTITY" "$APP/Contents/Helpers/uv"
  codesign --force --options runtime --sign "$IDENTITY" "$APP"
else
  echo "==> No Apple Development identity; ad-hoc signing (permissions must be re-granted after each build)"
  codesign --force --sign - "$APP/Contents/Helpers/uv"
  codesign --force --sign - "$APP"
fi

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Tars 2>/dev/null || true
  while pgrep -x Tars >/dev/null; do sleep 0.2; done
  rm -rf /Applications/Tars.app
  cp -R "$APP" /Applications/Tars.app
  open /Applications/Tars.app
  echo "Installed and launched /Applications/Tars.app"
else
  echo "Built $APP"
fi
