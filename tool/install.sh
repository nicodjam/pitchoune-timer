#!/usr/bin/env bash
# Installs the last build (tool/build.sh) on the tablet, as an update: the
# app keeps its data.
#
#   tool/install.sh           # on the tablet remembered by tool/connect.sh
#
# Typical: tool/build.sh && tool/install.sh
set -euo pipefail
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/env.sh" --quiet
cd "$ROOT"

apk=build/app/outputs/flutter-apk/app-release.apk
[[ -f $apk ]] || die "$apk not found: run tool/build.sh first"
if [[ -n "$(find lib android pubspec.yaml -newer "$apk" -type f 2>/dev/null | head -1)" ]]; then
  warn "The code changed since this build: run tool/build.sh to install the latest version"
  confirm "Install this older build anyway?" n || exit 1
fi

pick_device
model=$(adb shell getprop ro.product.model 2>/dev/null | tr -d '\r')
echo "== Installing on $ANDROID_SERIAL ($model)"
if out=$(adb install -r "$apk" 2>&1); then
  ok "Installed"
  exit 0
fi
echo "$out"
case $out in
  *UPDATE_INCOMPATIBLE*)
    err "The installed app is signed with another key (debug vs release)."
    hint "Uninstall it (every account): adb uninstall fr.pitchoune.timer, then run again."
    hint "Its settings are lost: set each account up again (family code, Setup screen)." ;;
  *VERSION_DOWNGRADE*)
    err "The installed version is newer than this build."
    hint "Pull the latest code and rebuild, or uninstall first." ;;
  *INSUFFICIENT_STORAGE*)
    err "Not enough space on the tablet." ;;
  *)
    err "Installation failed (see the message above)." ;;
esac
exit 1
