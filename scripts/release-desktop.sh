#!/usr/bin/env bash
# Build, Developer ID sign, notarize, and publish the Mac Catalyst desktop DMG.
#
# Version source of truth: desktop/version.env
#   VERSION  -> Modizer-Desktop-VERSION.dmg and GitHub tag vVERSION-desktop
#   BUILD    -> CFBundleVersion; incremented automatically on each compile
#
# Secrets (gitignored): desktop/secrets.env
#   Created interactively on first run. chmod 600. Never commit this file.
#
# Same VERSION as an existing GitHub release (or dist DMG) exits immediately
# unless you pass --force or bump the version.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION_FILE="$ROOT/desktop/version.env"
NOTES_FILE="$ROOT/desktop/RELEASE_NOTES.md"
SECRETS_FILE="$ROOT/desktop/secrets.env"
ENTITLEMENTS="$ROOT/modizer/modizer-mac-developer-id.entitlements"
PROJECT="$ROOT/modizer.xcodeproj"
SCHEME="modizer mac local"
DERIVED="$ROOT/build/DerivedData"
DIST_DIR="$ROOT/dist"
VOL_NAME="Modizer Desktop"
GITHUB_REPO_DEFAULT="NexusEast/modizer_desktop"

FORCE=0
BUMP=""
SKIP_NOTARIZE=0
SKIP_GITHUB=0
KEEP_BUILD=0

usage() {
  cat <<'EOF'
Usage: scripts/release-desktop.sh [options]

  --bump patch|minor|major  Increment VERSION in desktop/version.env, then release
  --force                   Rebuild/replace this VERSION even if it already exists
  --keep-build              Do not increment BUILD
  --skip-notarize           Sign the DMG but do not submit to Apple
  --skip-github             Do not create/upload the GitHub release
  --notes PATH              Release notes markdown (default: desktop/RELEASE_NOTES.md)
  -h, --help                Show this help

First run writes desktop/secrets.env (Apple ID, team ID, app-specific password).
Edit desktop/version.env to set the next marketing version, or use --bump.
Edit desktop/RELEASE_NOTES.md before publishing (English only).
EOF
}

die() { echo "error: $*" >&2; exit 1; }
log() { echo "==> $*"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    --keep-build) KEEP_BUILD=1; shift ;;
    --skip-notarize) SKIP_NOTARIZE=1; shift ;;
    --skip-github) SKIP_GITHUB=1; shift ;;
    --bump)
      BUMP="${2:-}"
      [[ "$BUMP" == "patch" || "$BUMP" == "minor" || "$BUMP" == "major" ]] \
        || die "--bump requires patch, minor, or major"
      shift 2
      ;;
    --notes)
      NOTES_FILE="${2:-}"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

[[ -f "$VERSION_FILE" ]] || die "missing $VERSION_FILE"
# shellcheck disable=SC1090
source "$VERSION_FILE"
[[ -n "${VERSION:-}" ]] || die "VERSION is empty in $VERSION_FILE"
[[ -n "${BUILD:-}" ]] || die "BUILD is empty in $VERSION_FILE"

bump_semver() {
  local kind="$1" ver="$2" major minor patch
  IFS=. read -r major minor patch <<< "$ver"
  : "${minor:=0}"
  : "${patch:=0}"
  case "$kind" in
    major) major=$((major + 1)); minor=0; patch=0 ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    patch) patch=$((patch + 1)) ;;
  esac
  echo "${major}.${minor}.${patch}"
}

write_version_file() {
  cat > "$VERSION_FILE" <<EOF
# Marketing version: DMG name Modizer-Desktop-VERSION.dmg
# GitHub tag: vVERSION-desktop
VERSION=$VERSION

# CFBundleVersion. The release script increments this on each compile.
BUILD=$BUILD
EOF
}

sync_xcode_versions() {
  local pbx="$PROJECT/project.pbxproj"
  perl -pi -e "s/MARKETING_VERSION = 4\\.[0-9.]+;/MARKETING_VERSION = ${VERSION};/g" "$pbx"
  # Leave the window plugin at CURRENT_PROJECT_VERSION = 1
  perl -pi -e "s/CURRENT_PROJECT_VERSION = (?!1;)(\\d+);/CURRENT_PROJECT_VERSION = ${BUILD};/g" "$pbx"
}

prompt_tty() {
  local prompt="$1"
  local silent="${2:-0}"
  local value=""
  if [[ "$silent" == "1" ]]; then
    read -r -s -p "$prompt" value </dev/tty
    echo >/dev/tty
  else
    read -r -p "$prompt" value </dev/tty
  fi
  printf '%s' "$value"
}

load_secrets() {
  if [[ -f "$SECRETS_FILE" ]]; then
    if git -C "$ROOT" ls-files --error-unmatch desktop/secrets.env >/dev/null 2>&1; then
      die "desktop/secrets.env is tracked by git. Remove it from the index before releasing."
    fi
    chmod 600 "$SECRETS_FILE"
    # shellcheck disable=SC1090
    source "$SECRETS_FILE"
  fi

  GITHUB_REPO="${GITHUB_REPO:-$GITHUB_REPO_DEFAULT}"

  local ident
  ident="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | head -1 || true)"
  SIGNING_IDENTITY="${SIGNING_IDENTITY:-$ident}"
  [[ -n "$SIGNING_IDENTITY" ]] || die "no Developer ID Application identity in the login keychain"

  if [[ -z "${TEAM_ID:-}" && "$SIGNING_IDENTITY" =~ \(([A-Z0-9]+)\)$ ]]; then
    TEAM_ID="${BASH_REMATCH[1]}"
  fi

  local need_notary=1
  [[ "${SKIP_NOTARIZE:-0}" -eq 1 ]] && need_notary=0

  # Prefer a saved notarytool keychain profile over prompting for secrets.env.
  if [[ "$need_notary" -eq 1 && -z "${NOTARY_PASSWORD:-}" ]]; then
    local candidate
    for candidate in "${NOTARY_KEYCHAIN_PROFILE:-}" modizer-notary AC_PASSWORD; do
      [[ -n "$candidate" ]] || continue
      if xcrun notarytool history --keychain-profile "$candidate" >/dev/null 2>&1; then
        NOTARY_KEYCHAIN_PROFILE="$candidate"
        log "Using notary keychain profile $NOTARY_KEYCHAIN_PROFILE"
        break
      fi
    done
  fi

  local have_notary=0
  [[ -n "${NOTARY_PASSWORD:-}" || -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]] && have_notary=1

  if [[ -z "${TEAM_ID:-}" || ( "$need_notary" -eq 1 && "$have_notary" -eq 0 && -z "${APPLE_ID:-}" ) ]]; then
    echo "No usable desktop/secrets.env yet. Enter values once; they are saved locally."
    echo "Use an app-specific password from appleid.apple.com, not the Apple ID password."
    echo
    [[ -n "${APPLE_ID:-}" ]] || APPLE_ID="$(prompt_tty "Apple ID email: ")"
    if [[ -z "${TEAM_ID:-}" ]]; then
      TEAM_ID="$(prompt_tty "Team ID: ")"
    fi
    if [[ "$need_notary" -eq 1 && "$have_notary" -eq 0 ]]; then
      NOTARY_PASSWORD="$(prompt_tty "App-specific password (hidden): " 1)"
    fi
    [[ -n "$APPLE_ID" && -n "$TEAM_ID" ]] || die "Apple ID and Team ID are required"
    if [[ "$need_notary" -eq 1 && -z "${NOTARY_PASSWORD:-}" && -z "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
      die "app-specific password is required unless --skip-notarize"
    fi

    umask 077
    cat > "$SECRETS_FILE" <<EOF
APPLE_ID=${APPLE_ID}
TEAM_ID=${TEAM_ID}
NOTARY_PASSWORD=${NOTARY_PASSWORD:-}
GITHUB_REPO=${GITHUB_REPO}
NOTARY_KEYCHAIN_PROFILE=${NOTARY_KEYCHAIN_PROFILE:-}
EOF
    chmod 600 "$SECRETS_FILE"
    log "Wrote $SECRETS_FILE (gitignored)"
  fi
}

github_release_exists() {
  gh release view "$1" --repo "$GITHUB_REPO" >/dev/null 2>&1
}

dmg_is_stapled() {
  xcrun stapler validate "$1" >/dev/null 2>&1
}

find_built_app() {
  local app="$DERIVED/Build/Products/Release-maccatalyst/modizer.app"
  [[ -d "$app" ]] || die "built app not found: $app"
  printf '%s' "$app"
}

build_app() {
  log "Building Release $VERSION ($BUILD) for Mac Catalyst arm64"
  rm -rf "$DERIVED/Build/Products/Release-maccatalyst/modizer.app"
  xcodebuild -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'platform=macOS,variant=Mac Catalyst,arch=arm64' \
    -derivedDataPath "$DERIVED" \
    ONLY_ACTIVE_ARCH=YES \
    CODE_SIGN_IDENTITY='-' \
    CODE_SIGNING_REQUIRED=NO \
    AD_HOC_CODE_SIGNING_ALLOWED=YES \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM= \
    CODE_SIGN_ENTITLEMENTS=modizer/modizer-mac-local.entitlements \
    ENABLE_APP_SANDBOX=NO \
    ENABLE_HARDENED_RUNTIME=NO \
    'ENABLE_HARDENED_RUNTIME[sdk=macosx*]'=NO
}

sign_app() {
  local app="$1"
  [[ -f "$ENTITLEMENTS" ]] || die "missing $ENTITLEMENTS"
  log "Signing app with $SIGNING_IDENTITY"
  codesign --force --deep --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$app"
  codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" \
    --sign "$SIGNING_IDENTITY" "$app"
  codesign --verify --deep --strict "$app"
  local short ver
  short="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
  ver="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")"
  [[ "$short" == "$VERSION" ]] || die "CFBundleShortVersionString is $short, expected $VERSION"
  [[ "$ver" == "$BUILD" ]] || die "CFBundleVersion is $ver, expected $BUILD"
}

make_dmg() {
  local app="$1"
  local dmg_out="$2"
  local stage="$ROOT/build/dmg-stage"
  local dmg_rw="$ROOT/build/Modizer-Desktop-${VERSION}-rw.dmg"
  local mount="/Volumes/${VOL_NAME}"

  log "Packaging $dmg_out"
  rm -rf "$stage"
  mkdir -p "$stage" "$DIST_DIR"
  ditto "$app" "$stage/Modizer.app"
  ln -s /Applications "$stage/Applications"
  cat > "$stage/Read Me.txt" <<EOF
Modizer Desktop ${VERSION}
Apple Silicon (arm64) Mac Catalyst build.
Signed with Developer ID Application.

Install: drag Modizer to Applications.

Official iOS Modizer: https://github.com/yoyofr/modizer
This desktop fork: https://github.com/NexusEast/modizer_desktop
EOF

  if [[ -d "$mount" ]]; then
    hdiutil detach "$mount" -quiet || hdiutil detach "$mount" -force || true
  fi
  if [[ -d "/Volumes/${VOL_NAME} 1" ]]; then
    hdiutil detach "/Volumes/${VOL_NAME} 1" -quiet || hdiutil detach "/Volumes/${VOL_NAME} 1" -force || true
  fi

  rm -f "$dmg_rw" "$dmg_out"
  hdiutil create -srcfolder "$stage" -volname "$VOL_NAME" -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" -format UDRW -ov "$dmg_rw" >/dev/null

  local mount_out device
  mount_out="$(hdiutil attach -readwrite -noverify -noautoopen "$dmg_rw")"
  device="$(echo "$mount_out" | awk '/Apple_HFS/ {print $1; found=1} END {if (!found) print ""}')"
  [[ -n "$device" ]] || device="$(echo "$mount_out" | awk 'NR==1 {print $1}')"

  osascript <<APPLESCRIPT >/dev/null || true
tell application "Finder"
  tell disk "${VOL_NAME}"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 760, 480}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 128
    delay 0.5
    set position of item "Modizer.app" of container window to {140, 180}
    set position of item "Applications" of container window to {420, 180}
    set position of item "Read Me.txt" of container window to {280, 320}
    close
    open
    update without registering applications
    delay 1
  end tell
end tell
APPLESCRIPT

  sync
  hdiutil detach "$device" -quiet || hdiutil detach "$mount" -force
  hdiutil convert "$dmg_rw" -format UDZO -imagekey zlib-level=9 -o "$dmg_out"
  rm -f "$dmg_rw"
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$dmg_out"
}

notarize_dmg() {
  local dmg="$1"
  if dmg_is_stapled "$dmg"; then
    log "Already notarized and stapled: $dmg"
    return 0
  fi
  log "Submitting DMG to Apple notary service"
  if [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
    xcrun notarytool submit "$dmg" \
      --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" \
      --wait
  else
    xcrun notarytool submit "$dmg" \
      --apple-id "$APPLE_ID" \
      --password "$NOTARY_PASSWORD" \
      --team-id "$TEAM_ID" \
      --wait
  fi
  xcrun stapler staple "$dmg"
  xcrun stapler validate "$dmg"
}

publish_github() {
  local dmg="$1"
  local tag="v${VERSION}-desktop"
  local title="Modizer Desktop ${VERSION}"
  [[ -f "$NOTES_FILE" ]] || die "missing release notes: $NOTES_FILE"

  if github_release_exists "$tag"; then
    log "Updating GitHub release $tag"
    gh release upload "$tag" "$dmg" --repo "$GITHUB_REPO" --clobber
    gh release edit "$tag" --repo "$GITHUB_REPO" --title "$title" --notes-file "$NOTES_FILE"
  else
    log "Creating GitHub release $tag"
    gh release create "$tag" \
      --repo "$GITHUB_REPO" \
      --target master \
      --title "$title" \
      --notes-file "$NOTES_FILE" \
      "$dmg"
  fi
  gh release view "$tag" --repo "$GITHUB_REPO" --json url --jq .url
}

# --- version gate ---
if [[ -n "$BUMP" ]]; then
  VERSION="$(bump_semver "$BUMP" "$VERSION")"
  log "Bumped marketing version to $VERSION"
fi

DMG_NAME="Modizer-Desktop-${VERSION}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
TAG="v${VERSION}-desktop"
GITHUB_REPO="${GITHUB_REPO:-$GITHUB_REPO_DEFAULT}"

if [[ "$SKIP_GITHUB" -eq 0 ]]; then
  command -v gh >/dev/null || die "gh is not installed"
  if [[ "$FORCE" -eq 0 ]] && github_release_exists "$TAG"; then
    echo "Version $VERSION already published as $TAG ($DMG_NAME)."
    echo "Bump desktop/version.env, or run with --bump patch / --force."
    exit 0
  fi
fi

if [[ "$FORCE" -eq 0 && -f "$DMG_PATH" && "$SKIP_GITHUB" -ne 0 ]]; then
  echo "Version $VERSION already built: $DMG_PATH"
  echo "Pass --force to rebuild, or bump the version."
  exit 0
fi

NEED_COMPILE=1
if [[ "$FORCE" -eq 0 && -f "$DMG_PATH" ]]; then
  log "Reusing existing $DMG_PATH"
  NEED_COMPILE=0
fi

load_secrets
[[ -d "$DIST_DIR" ]] || mkdir -p "$DIST_DIR"

if [[ "$NEED_COMPILE" -eq 1 ]]; then
  if [[ "$KEEP_BUILD" -eq 0 ]]; then
    BUILD=$((BUILD + 1))
    log "BUILD is now $BUILD"
  fi
  write_version_file
  sync_xcode_versions
  build_app
  APP="$(find_built_app)"
  sign_app "$APP"
  make_dmg "$APP" "$DMG_PATH"
fi

[[ -f "$DMG_PATH" ]] || die "missing $DMG_PATH"

if [[ "$SKIP_NOTARIZE" -eq 0 ]]; then
  notarize_dmg "$DMG_PATH"
else
  log "Skipping notarization"
fi

cp -f "$DMG_PATH" "$HOME/Desktop/$DMG_NAME"
log "Copied $HOME/Desktop/$DMG_NAME"

if [[ "$SKIP_GITHUB" -eq 0 ]]; then
  publish_github "$DMG_PATH"
else
  log "Skipping GitHub release"
fi

log "Done: $DMG_NAME (VERSION=$VERSION BUILD=$BUILD)"
