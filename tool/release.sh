#!/usr/bin/env bash
# Builds a signed release APK, sends it to the testers (family and friends)
# through Firebase App Distribution, then records it in git. See README,
# "Releasing".
#
#   tool/release.sh "What changed, for the testers"
#   tool/release.sh "What changed" 1.1.0      # also changes the version name
#
# The build number (after the +, in pubspec.yaml) goes up by one at every
# release: Android only installs an update with a higher number.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/env.sh" --quiet
cd "$ROOT"

notes="${1:?Usage: tool/release.sh \"release notes\" [version name]}"
new_name="${2:-}"
group="${PITCHOUNE_TESTERS:-family}"   # Firebase App Distribution tester group alias

# 1. Checks: release key, tools, clean tree, branch.
[[ -f android/key.properties ]] ||
  die "android/key.properties is missing: create the release key first (README, Releasing)."
for tool in flutter firebase python3; do
  command -v "$tool" >/dev/null || die "$tool not found: run tool/env.sh to see how to install it."
done
[[ -z "$(git status --porcelain)" ]] ||
  die "Uncommitted changes: commit them first, so that the release matches a commit."
branch=$(git rev-parse --abbrev-ref HEAD)
if [[ $branch != main ]]; then
  warn "You are on '$branch', not 'main'."
  confirm "Release from '$branch' anyway?" n || exit 1
fi

# 2. Version: "version: 1.0.0+7" -> 1.0.0 (name) and 7 (build number).
current=$(sed -n 's/^version: *//p' pubspec.yaml)
name="${new_name:-${current%%+*}}"
build=$(( ${current##*+} + 1 ))
version="${name}+${build}"
sed -i "s/^version: .*/version: ${version}/" pubspec.yaml
echo "== Version ${version}"

# Until the upload, a failure puts pubspec.yaml back as it was.
uploaded=0
trap '[[ $uploaded == 0 ]] && git checkout -q pubspec.yaml && warn "Stopped: pubspec.yaml restored"' EXIT

# 3. Tests, then the build, checked to be signed with the release key.
flutter test
"$ROOT/tool/build.sh"
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
uploaded=1
ok "Version ${version} sent to the \"${group}\" group"

# 6. Record it in git. The commit and the tag are always made locally: the
#    testers now have this build number, the next release must go above it.
git commit -q pubspec.yaml -m "Release ${version}" -m "$notes"
git tag -a "v${version}" -m "Pitchoune Timer ${version}" -m "$notes"
ok "Committed and tagged v${version}"
if confirm "Push '$branch' and the tag v${version} to GitHub?" y; then
  git push origin "$branch"
  git push origin "v${version}"
  ok "Pushed"
else
  warn "Not pushed. Later: git push origin $branch && git push origin v${version}"
fi
