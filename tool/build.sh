#!/usr/bin/env bash
# Builds the release APK and checks its signature.
#
#   tool/build.sh            # build, must be signed with the release key
#   tool/build.sh --debug    # also accepts the debug key (no android/key.properties)
#   tool/build.sh --check    # only check the signature of the last build
#
# The signature decides whether the APK can update the installed app: Android
# refuses an update signed with another key. The check reads the certificate
# of the APK (apksigner) and compares it with the release key of
# android/key.properties (keytool).
set -euo pipefail
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/env.sh" --quiet
cd "$ROOT"

APK=build/app/outputs/flutter-apk/app-release.apk
allow_debug=0
build=1
case ${1:-} in
  --debug) allow_debug=1 ;;
  --check) build=0 ;;
  "") ;;
  *) die "Unknown option: $1 (see the top of tool/build.sh)" ;;
esac

# Value of a key in android/key.properties.
prop() { sed -n "s/^$1=//p" android/key.properties | tr -d '\r'; }

if [[ $build == 1 ]]; then
  command -v flutter >/dev/null || die "flutter not found: run tool/env.sh to see how to install it."
  if [[ ! -f android/key.properties && $allow_debug == 0 ]]; then
    die "android/key.properties is missing: the APK would be signed with the debug key.
  → create the release key (README, Releasing), or tool/build.sh --debug for a local test"
  fi
  version=$(sed -n 's/^version: *//p' pubspec.yaml)
  echo "== Building ${version}"
  flutter build apk --release
fi
[[ -f $APK ]] || die "$APK not found: run tool/build.sh"

# --- Signature check ----------------------------------------------------------
command -v apksigner >/dev/null ||
  die "apksigner not found (Android SDK Build-Tools): run tool/env.sh to see how to install it."
certs=$(apksigner verify --print-certs "$APK" 2>&1) || die "The APK is not validly signed:
$certs"
subject=$(sed -n 's/^Signer #1 certificate DN: //p' <<<"$certs")
apk_sha=$(sed -n 's/^Signer #1 certificate SHA-256 digest: //p' <<<"$certs" | tr -d ':' | tr 'A-F' 'a-f')
echo "== Signature"
echo "  certificate: $subject"
echo "  SHA-256:     $apk_sha"

if [[ $subject == *"Android Debug"* ]]; then
  if [[ $allow_debug == 1 ]]; then
    warn "Signed with the DEBUG key: fine for a local test, not for the testers"
    exit 0
  fi
  die "Signed with the DEBUG key: android/key.properties was not used (is storeFile an absolute path?)"
fi

if [[ -f android/key.properties ]]; then
  command -v keytool >/dev/null || die "keytool not found (Java): run tool/env.sh"
  store=$(prop storeFile); alias=$(prop keyAlias); pass=$(prop storePassword)
  [[ -f $store ]] || die "storeFile=$store (android/key.properties) does not exist"
  key_sha=$(keytool -J-Duser.language=en -list -v -keystore "$store" -alias "$alias" -storepass "$pass" 2>/dev/null |
    sed -n 's/^[[:space:]]*SHA256: //p' | tr -d ':' | tr 'A-F' 'a-f')
  [[ -n $key_sha ]] || die "Cannot read the key '$alias' in $store (wrong password or alias?)"
  if [[ $key_sha == "$apk_sha" ]]; then
    ok "Signed with the release key ($alias in $(basename "$store"))"
  else
    die "Signed with ANOTHER key than the release key of android/key.properties
  release key SHA-256: $key_sha"
  fi
else
  warn "No android/key.properties: cannot compare with the release key"
fi
ok "$APK ($(du -h "$APK" | cut -f1))"
