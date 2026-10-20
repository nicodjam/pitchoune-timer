#!/usr/bin/env bash
# Builds a signed release APK and sends it to the testers (family and friends)
# through Firebase App Distribution. See README, "Releasing".
#
#   tool/release.sh "What changed, for the testers"
#   tool/release.sh "What changed" 1.1.0      # also changes the version name
#
# The build number (after the +, in pubspec.yaml) goes up by one at every
# release: Android only installs an update with a higher number.
set -euo pipefail
cd "$(dirname "$0")/.."

notes="${1:?Usage: tool/release.sh \"release notes\" [version name]}"
new_name="${2:-}"
group="${PITCHOUNE_TESTERS:-family}"   # Firebase App Distribution tester group alias

# 1. Checks: release key, Firebase CLI, clean tree.
if [[ ! -f android/key.properties ]]; then
  echo "android/key.properties is missing: create the release key first (README, Releasing)." >&2
  exit 1
fi
command -v firebase >/dev/null || { echo "Firebase CLI not found (npm install -g firebase-tools)." >&2; exit 1; }
if [[ -n "$(git status --porcelain)" ]]; then
  echo "Uncommitted changes: commit them first, so that the release matches a commit." >&2
  exit 1
fi

# 2. Version: "version: 1.0.0+7" -> 1.0.0 (name) and 7 (build number).
current=$(sed -n 's/^version: *//p' pubspec.yaml)
name="${new_name:-${current%%+*}}"
build=$(( ${current##*+} + 1 ))
sed -i "s/^version: .*/version: ${name}+${build}/" pubspec.yaml
echo "== Version ${name} (build ${build})"

# 3. Build, tests first.
flutter test
flutter build apk --release
apk=build/app/outputs/flutter-apk/app-release.apk

# 4. Firebase app id of this Android app (from google-services.json).
package=$(sed -n 's/^ *applicationId = "\(.*\)"/\1/p' android/app/build.gradle.kts)
app_id=$(python3 - "$package" <<'PY'
import json, sys
clients = json.load(open("android/app/google-services.json"))["client"]
ids = [c["client_info"]["mobilesdk_app_id"] for c in clients
       if c["client_info"]["android_client_info"]["package_name"] == sys.argv[1]]
if not ids:
    sys.exit(f"No app {sys.argv[1]} in google-services.json: run flutterfire configure (README).")
print(ids[0])
PY
)

# 5. Upload and invite the testers.
firebase appdistribution:distribute "$apk" \
  --app "$app_id" \
  --groups "$group" \
  --release-notes "$notes"

# 6. Remember it in git.
git commit -q pubspec.yaml -m "Release ${name}+${build}"
git tag "v${name}+${build}"
echo "== Done: version ${name}+${build} sent to the \"${group}\" group."
echo "   Push the commit and the tag: git push && git push --tags"
