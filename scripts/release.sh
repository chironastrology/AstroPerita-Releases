#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

REPO="chironastrology/AstroPerita-Releases"
DOWNLOADS="${HOME}/Downloads"

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

[[ $# -eq 1 ]] || fail "Usage: ./scripts/release.sh X.Y.Z"

VERSION="$1"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
  fail "Version must look like 1.0.0"

TAG="v${VERSION}"

MAC_DMG="AstroPerita-${VERSION}-macOS.dmg"
MAC_SHA="${MAC_DMG}.sha256"
MAC_LICENSES="AstroPerita-${VERSION}-Open-Source-Lizenzen.txt"

THIRD_PARTY="AstroPerita-${VERSION}-Third-Party-Notices.txt"

WIN_LICENSES="AstroPerita-${VERSION}-Windows-x64-Open-Source-Lizenzen.txt"
WIN_EXE="AstroPerita-${VERSION}-Windows-x64.exe"
WIN_SHA="${WIN_EXE}.sha256"

FILES=(
  "$MAC_DMG"
  "$MAC_SHA"
  "$MAC_LICENSES"
  "$THIRD_PARTY"
  "$WIN_LICENSES"
  "$WIN_EXE"
  "$WIN_SHA"
)

command -v git >/dev/null 2>&1 || fail "git is not installed."
command -v gh >/dev/null 2>&1 || fail "GitHub CLI (gh) is not installed."

gh auth status >/dev/null 2>&1 || \
  fail "GitHub CLI is not logged in. Run: gh auth login"

[[ -d .git ]] || \
  fail "Run this script from the root of the new AstroPerita-Releases repository."

[[ -f README.md ]] || fail "README.md is missing."
[[ -f scripts/release.sh ]] || fail "scripts/release.sh is missing."

ORIGIN="$(git remote get-url origin 2>/dev/null || true)"

[[ "$ORIGIN" == *"chironastrology/AstroPerita-Releases"* ]] || \
  fail "origin does not point to ${REPO}."

for name in "${FILES[@]}"; do
  [[ -f "${DOWNLOADS}/${name}" ]] || \
    fail "Missing in Downloads: ${name}"

  [[ -s "${DOWNLOADS}/${name}" ]] || \
    fail "Empty file in Downloads: ${name}"
done

actual_sha() {
  shasum -a 256 "$1" | awk '{print tolower($1)}'
}

expected_sha() {
  tr -d '\r' < "$1" | awk 'NR==1 {print tolower($1)}'
}

MAC_EXPECTED="$(expected_sha "${DOWNLOADS}/${MAC_SHA}")"
MAC_ACTUAL="$(actual_sha "${DOWNLOADS}/${MAC_DMG}")"

[[ "$MAC_EXPECTED" =~ ^[0-9a-f]{64}$ ]] || \
  fail "Invalid macOS SHA-256 file."

[[ "$MAC_EXPECTED" == "$MAC_ACTUAL" ]] || \
  fail "macOS SHA-256 does not match the DMG."

WIN_EXPECTED="$(expected_sha "${DOWNLOADS}/${WIN_SHA}")"
WIN_ACTUAL="$(actual_sha "${DOWNLOADS}/${WIN_EXE}")"

[[ "$WIN_EXPECTED" =~ ^[0-9a-f]{64}$ ]] || \
  fail "Invalid Windows SHA-256 file."

[[ "$WIN_EXPECTED" == "$WIN_ACTUAL" ]] || \
  fail "Windows SHA-256 does not match the EXE."

cp "${DOWNLOADS}/${THIRD_PARTY}" THIRD_PARTY_NOTICES.txt

{
  printf '===== macOS =====\n'
  cat "${DOWNLOADS}/${MAC_LICENSES}"
  printf '\n===== Windows x64 =====\n'
  cat "${DOWNLOADS}/${WIN_LICENSES}"
} > OPEN_SOURCE_LICENSES.txt

chmod +x scripts/release.sh

git add -- \
  .gitignore \
  README.md \
  scripts/release.sh \
  THIRD_PARTY_NOTICES.txt \
  OPEN_SOURCE_LICENSES.txt

if ! git diff --cached --quiet; then
  git commit -m "chore(release): publish AstroPerita ${VERSION}"
fi

git branch -M main
git push -u origin main

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  fail "Release ${TAG} already exists. Nothing was overwritten."
fi

REMOTE_TAG="$(
  git ls-remote --tags origin "refs/tags/${TAG}" |
  awk '{print $1}'
)"

if [[ -n "$REMOTE_TAG" ]]; then
  CURRENT="$(git rev-parse HEAD)"

  [[ "$REMOTE_TAG" == "$CURRENT" ]] || \
    fail "Remote tag ${TAG} exists on another commit."
else
  git tag -a "$TAG" -m "AstroPerita ${VERSION}"
  git push origin "$TAG"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

for name in "${FILES[@]}"; do
  cp "${DOWNLOADS}/${name}" "${TMP}/${name}"
done

cp "${DOWNLOADS}/${MAC_DMG}" \
  "${TMP}/AstroPerita-macOS.dmg"

cp "${DOWNLOADS}/${WIN_EXE}" \
  "${TMP}/AstroPerita-Windows-x64.exe"

NOTES="${TMP}/release-notes.md"

if [[ "$VERSION" == "1.0.0" ]]; then
  INTRO="First stable release of AstroPerita Professional."
else
  INTRO="Stable release of AstroPerita Professional."
fi

cat > "$NOTES" <<EOF
${INTRO}

## Downloads

### macOS
- AstroPerita-macOS.dmg

### Windows
- AstroPerita-Windows-x64.exe

## Integrity

Versioned application files include SHA-256 checksum files for integrity verification.

## Open-source and third-party notices

Open-source licenses and third-party notices are included with this release.

Product information, documentation and support:
https://www.chiron-astrology.com/astroperita
EOF

ASSETS=(
  "${TMP}/${MAC_DMG}"
  "${TMP}/${MAC_SHA}"
  "${TMP}/${MAC_LICENSES}"
  "${TMP}/${THIRD_PARTY}"
  "${TMP}/${WIN_LICENSES}"
  "${TMP}/${WIN_EXE}"
  "${TMP}/${WIN_SHA}"
  "${TMP}/AstroPerita-macOS.dmg"
  "${TMP}/AstroPerita-Windows-x64.exe"
)

printf '\nReady to publish %s with exactly 9 assets from ~/Downloads.\n' "$TAG"
printf 'Type exactly "release %s" to continue: ' "$TAG"

read -r CONFIRM

[[ "$CONFIRM" == "release ${TAG}" ]] || fail "Cancelled."

gh release create "$TAG" "${ASSETS[@]}" \
  --repo "$REPO" \
  --verify-tag \
  --latest \
  --title "AstroPerita ${VERSION}" \
  --notes-file "$NOTES"

COUNT="$(
  gh release view "$TAG" \
    --repo "$REPO" \
    --json assets \
    --jq '.assets | length'
)"

[[ "$COUNT" == "9" ]] || \
  fail "Release exists, but asset count is ${COUNT}, expected 9."

printf '\nSUCCESS: %s published with 9 assets.\n' "$TAG"
printf 'macOS:  https://github.com/%s/releases/latest/download/AstroPerita-macOS.dmg\n' "$REPO"
printf 'Windows: https://github.com/%s/releases/latest/download/AstroPerita-Windows-x64.exe\n' "$REPO"