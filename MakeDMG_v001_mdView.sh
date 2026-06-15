#!/usr/bin/env bash
# Full build pipeline: xcodebuild archive → export app → create DMG
set -euo pipefail

# ── 1. CONFIGURATION ──────────────────────────────────────────────────────────
# Only update this path. Everything else is derived automatically.
PROJECT="/Users/josh/Dev/Apps/mdview/mdview/mdview.xcodeproj"

# ── 2. AUTO-DERIVED VARIABLES ─────────────────────────────────────────────────
PROJNAME=$(basename "$PROJECT" .xcodeproj)
# APPNAME is read from the archive after building (a target's PRODUCT_NAME may
# differ from the project name), not assumed to be "<project>.app".
PROJECT_DIR=$(dirname "$PROJECT")
LOG="${PROJECT_DIR}/build_log.txt"

# Pick the scheme. Prefer one matching the project name ("StatDB") — the scheme
# list also includes package schemes (e.g. MarkdownUI) that sort first and would
# otherwise be archived instead of the app, producing an empty Products/.
ALL_SCHEMES=$(xcodebuild -project "$PROJECT" -list | awk '/Schemes:/{flag=1; next} /^ *$/{flag=0} flag {print $1}')
SCHEME=$(echo "$ALL_SCHEMES" | grep -Fx "$PROJNAME" || true)
SCHEME="${SCHEME:-$(echo "$ALL_SCHEMES" | head -n1)}"
# Fallback just in case xcodebuild list fails to parse
SCHEME="${SCHEME:-$PROJNAME}"

# Accept version as first argument; fall back to value in project file
if [[ -n "${1:-}" ]]; then
    VERSION="$1"
else
    VERSION=$(grep -m1 'MARKETING_VERSION' "$PROJECT/project.pbxproj" | tr -d ' ;' | cut -d= -f2)
fi

ARCHIVE="/tmp/${PROJNAME}-${VERSION}.xcarchive"
TIMESTAMP=$(date "+%Y-%m-%d %H-%M-%S")
EXPORT_DIR="$HOME/Desktop/${PROJNAME} ${TIMESTAMP}"
OUT="$HOME/Desktop/${PROJNAME}-${VERSION}.dmg"
# APPNAME / APP / ICON are derived after the archive (see section 4).

# ── 3. ARCHIVE ────────────────────────────────────────────────────────────────
echo "==> Archiving ${SCHEME} ${VERSION}..."
rm -rf "$ARCHIVE"

xcodebuild \
  -verbose \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "platform=macOS,arch=arm64" \
  archive \
  -archivePath "$ARCHIVE" \
  2>&1 | tee "$LOG" | grep -E "^(error:|warning:.*error|.*[Aa]rchive [Ss]ucceeded|.*[Aa]rchive [Ff]ailed|.*[Bb]uild [Ff]ailed)" || true

if ! grep -qi "Archive succeeded" "$LOG"; then
    echo ""
    echo "ERROR: Archive failed — check $LOG for details"
    exit 1
fi
echo "==> Archive succeeded"

# ── 4. EXPORT APP ─────────────────────────────────────────────────────────────
echo "==> Exporting app to Desktop..."

# Find the actual .app the archive produced (its name == the target's PRODUCT_NAME,
# which is not necessarily the project name).
ARCHIVED_APP=$(find "$ARCHIVE/Products/Applications" -maxdepth 1 -name '*.app' | head -n1)
if [[ -z "$ARCHIVED_APP" ]]; then
    echo "ERROR: no .app found in $ARCHIVE/Products/Applications — check $LOG"
    exit 1
fi
APPNAME=$(basename "$ARCHIVED_APP")
APP="$EXPORT_DIR/$APPNAME"
ICON="$APP/Contents/Resources/AppIcon.icns"

mkdir -p "$EXPORT_DIR"
cp -R "$ARCHIVED_APP" "$EXPORT_DIR/"
echo "    $APP"

# Validate app path
if [ ! -d "$APP" ]; then
    echo "ERROR: App not found at: $APP"
    exit 1
fi

# ── 5. CREATE DMG ─────────────────────────────────────────────────────────────
echo "==> Building DMG..."
echo "    App:  $APP"
echo "    Out:  $OUT"

# Remove stale output DMG
rm -f "$OUT"

# Detach any leftover project temp disk images from failed previous runs
# Uses -v to pass the PROJNAME into awk, and tolower() for a case-insensitive match
hdiutil info 2>/dev/null | awk -v vol="$PROJNAME" '
  tolower($0) ~ ("image-path.*" tolower(vol)) { found=1; next }
  found && /^\/dev\/disk[0-9]/ { print $1; found=0 }
' | while IFS= read -r dev; do
    echo "    Detaching stale mount: $dev"
    hdiutil detach "$dev" -force 2>/dev/null || true
done

# Only pass --volicon if the app actually contains an icon.
VOLICON_ARGS=()
if [[ -f "$ICON" ]]; then
    VOLICON_ARGS=(--volicon "$ICON")
else
    echo "    (no AppIcon.icns found — using default volume icon)"
fi

create-dmg \
  --hdiutil-verbose \
  --volname "$PROJNAME" \
  ${VOLICON_ARGS[@]+"${VOLICON_ARGS[@]}"} \
  --window-pos 200 120 \
  --window-size 560 340 \
  --icon-size 128 \
  --icon "$APPNAME" 140 170 \
  --hide-extension "$APPNAME" \
  --app-drop-link 420 170 \
  "$OUT" \
  "$APP" 2>&1 | tee -a "$LOG" | grep -v -E "^(DI|CB|2[0-9]{3}-|diskimages|copy-helper)"

echo ""
echo "Done: $OUT"
