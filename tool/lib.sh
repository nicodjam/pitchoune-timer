# shellcheck shell=bash
# Shared helpers for the tool/*.sh scripts. Sourced, not run.

# Colors only on a terminal.
if [[ -t 1 ]]; then
  C_OK=$'\e[32m'; C_ERR=$'\e[31m'; C_WARN=$'\e[33m'; C_DIM=$'\e[2m'; C_END=$'\e[0m'
else
  C_OK=; C_ERR=; C_WARN=; C_DIM=; C_END=
fi
ok()   { echo "${C_OK}✓${C_END} $*"; }
err()  { echo "${C_ERR}✗${C_END} $*" >&2; }
warn() { echo "${C_WARN}!${C_END} $*"; }
hint() { echo "  ${C_DIM}→ $*${C_END}"; }
die()  { err "$*"; exit 1; }

# Asks a yes/no question; default answer in $2 (y or n).
confirm() {
  local prompt="$1" def="${2:-n}" answer
  local choices="[y/N]"; [[ $def == y ]] && choices="[Y/n]"
  read -r -p "$prompt $choices " answer || answer=""
  answer="${answer:-$def}"
  [[ $answer =~ ^[YyOo] ]]
}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE_FILE="$ROOT/.device"   # last device chosen by tool/connect.sh (not in git)

# Picks the device to use and exports ANDROID_SERIAL (read by adb):
# $ANDROID_SERIAL if set, else the one saved by tool/connect.sh, else the only
# one connected. A wireless device often shows twice (ip:port and its mDNS
# name): the ip:port form is preferred.
pick_device() {
  command -v adb >/dev/null || die "adb not found: run tool/env.sh to see how to install it"
  local devices
  devices=$(adb devices | awk 'NR > 1 && $2 == "device" {print $1}')
  if [[ -n ${ANDROID_SERIAL:-} ]] && grep -qx "$ANDROID_SERIAL" <<<"$devices"; then
    return
  fi
  if [[ -f $DEVICE_FILE ]] && grep -qx "$(cat "$DEVICE_FILE")" <<<"$devices"; then
    export ANDROID_SERIAL; ANDROID_SERIAL=$(cat "$DEVICE_FILE")
    return
  fi
  local ip_devices
  ip_devices=$(grep -E '^[0-9.]+:[0-9]+$' <<<"$devices" || true)
  [[ -n $ip_devices ]] && devices=$ip_devices
  local count
  count=$(grep -c . <<<"$devices" || true)
  if [[ $count -eq 0 ]]; then
    die "No device connected: tool/connect.sh <ip:port> (wireless debugging) or plug it in USB"
  elif [[ $count -eq 1 ]]; then
    export ANDROID_SERIAL="$devices"
  else
    echo "Several devices:"
    select d in $devices; do [[ -n $d ]] && break; done
    export ANDROID_SERIAL="$d"
  fi
}
