#!/usr/bin/env bash
# Connects a tablet in wireless debugging, and remembers it for the other
# scripts (tool/install.sh, tool/logs.sh).
#
#   tool/connect.sh 10.83.57.41:44667          # connect (port shown in Wireless debugging)
#   tool/connect.sh --pair 10.83.57.41:37123   # first time: pair with the 6-digit code
#   tool/connect.sh                            # list, and choose among the connected devices
#
# On the tablet: Settings → Developer options → Wireless debugging. The port
# changes at every restart of the tablet.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/env.sh" --quiet

if [[ ${1:-} == --pair ]]; then
  [[ -n ${2:-} ]] || die "Usage: tool/connect.sh --pair <ip:pairing port>"
  echo "Pairing code: Wireless debugging → Pair device with pairing code"
  adb pair "$2"
  echo "Now: tool/connect.sh <ip:port> (the port shown at the top of Wireless debugging)"
  exit 0
fi

if [[ -n ${1:-} ]]; then
  out=$(adb connect "$1")
  echo "$out"
  [[ $out == *connected* ]] || {
    hint "Is Wireless debugging on, and the port the current one? First time: tool/connect.sh --pair <ip:pairing port>"
    exit 1
  }
  export ANDROID_SERIAL="$1"
else
  unset ANDROID_SERIAL
  rm -f "$DEVICE_FILE"
  pick_device
fi
echo "$ANDROID_SERIAL" >"$DEVICE_FILE"
model=$(adb shell getprop ro.product.model 2>/dev/null | tr -d '\r')
android=$(adb shell getprop ro.build.version.release 2>/dev/null | tr -d '\r')
ok "Device: $ANDROID_SERIAL ($model, Android $android), remembered for tool/install.sh and tool/logs.sh"
