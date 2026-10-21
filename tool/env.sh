# shellcheck shell=bash
# Development environment of Pitchoune Timer: finds the tools, puts them in
# the PATH, checks that nothing is missing and says how to install it.
#
#   source tool/env.sh           # exports for this terminal + check (bash or zsh)
#   tool/env.sh                  # check only
#   tool/env.sh --print          # export lines to paste into ~/.bashrc
#   source tool/env.sh --quiet   # exports only (used by the other scripts)
#
# Tools: git, Flutter (with Dart), Java (keytool), Android SDK (adb,
# apksigner), Node.js + Firebase CLI, FlutterFire CLI, Python 3.

# Sourced from zsh (or another shell): bash does the work, this shell only
# imports the exports. (zsh reads a script command by command, so it never
# reaches the bash-only code below the "return".)
if [ -z "${BASH_VERSION:-}" ]; then
  if [ -n "${ZSH_VERSION:-}" ]; then
    # zsh: folder of the file being sourced.
    # shellcheck disable=SC2296,SC2298
    _pt_dir="${${(%):-%x}:A:h}"
  else
    _pt_dir="$PWD/tool"   # other shells: run it from the project root
  fi
  if [ "${1:-}" != "--quiet" ]; then bash "$_pt_dir/env.sh" "$@"; fi
  eval "$(bash "$_pt_dir/env.sh" --print)"
  unset _pt_dir
  return 0 2>/dev/null || exit 0
fi

_pt_sourced=0; [[ ${BASH_SOURCE[0]} != "$0" ]] && _pt_sourced=1
_pt_print=0; [[ ${1:-} == --print ]] && _pt_print=1
_pt_quiet=0; [[ ${1:-} == --quiet ]] && _pt_quiet=1
# shellcheck source=tool/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# (Both end with "return 0": the calling scripts run with "set -e".)
_pt_orig_path="$PATH"
_pt_first_dir() { for d in "$@"; do [[ -d $d ]] && { echo "$d"; return 0; }; done; return 0; }
_pt_add_path() { [[ -d $1 && ":$PATH:" != *":$1:"* ]] && PATH="$1:$PATH"; return 0; }

# --- Locate -------------------------------------------------------------------

# Flutter: already in the PATH, or a usual install folder.
if ! command -v flutter >/dev/null; then
  _pt_flutter=$(_pt_first_dir "$HOME/flutter/bin" "$HOME/development/flutter/bin" \
    "$HOME/dev/flutter/bin" /opt/flutter/bin /usr/local/flutter/bin)
  [[ -n $_pt_flutter ]] && _pt_add_path "$_pt_flutter"
fi
_pt_add_path "$HOME/.pub-cache/bin"   # flutterfire

# Android SDK.
export ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$(_pt_first_dir "$HOME/Android/Sdk" "$HOME/Android/sdk" /opt/android-sdk)}}"
if [[ -n $ANDROID_HOME ]]; then
  _pt_add_path "$ANDROID_HOME/platform-tools"
  _pt_add_path "$ANDROID_HOME/cmdline-tools/latest/bin"
  _pt_bt=$(ls -d "$ANDROID_HOME"/build-tools/*/ 2>/dev/null | sort -V | tail -1)
  [[ -n $_pt_bt ]] && _pt_add_path "${_pt_bt%/}"
fi

# Java: JAVA_HOME, else the one shipped with Android Studio.
if [[ -z ${JAVA_HOME:-} ]]; then
  _pt_java=$(_pt_first_dir "$HOME/android-studio/jbr" /opt/android-studio/jbr \
    /snap/android-studio/current/jbr /usr/local/android-studio/jbr)
  [[ -n $_pt_java ]] && export JAVA_HOME="$_pt_java"
fi
[[ -n ${JAVA_HOME:-} ]] && _pt_add_path "$JAVA_HOME/bin"

# Global npm packages installed without sudo.
_pt_add_path "$HOME/.npm-global/bin"
export PATH

if [[ $_pt_print == 1 ]]; then
  echo "# Pitchoune Timer development tools (from tool/env.sh --print)"
  [[ -n $ANDROID_HOME ]] && echo "export ANDROID_HOME=\"$ANDROID_HOME\""
  [[ -n ${JAVA_HOME:-} ]] && echo "export JAVA_HOME=\"$JAVA_HOME\""
  _pt_added=""
  IFS=: read -ra _pt_dirs <<<"$PATH"
  for d in "${_pt_dirs[@]}"; do
    [[ ":$_pt_orig_path:" != *":$d:"* ]] && _pt_added="$_pt_added$d:"
  done
  [[ -n $_pt_added ]] && echo "export PATH=\"$_pt_added\$PATH\""
  [[ $_pt_sourced == 1 ]] && return 0 || exit 0
fi

if [[ $_pt_quiet == 1 ]]; then
  unset -f _pt_first_dir _pt_add_path
  return 0 2>/dev/null || exit 0
fi

# --- Check --------------------------------------------------------------------

_pt_missing=0
_pt_check() {   # name, command, version command, install hint...
  local name=$1 cmd=$2 version=$3; shift 3
  if command -v "$cmd" >/dev/null; then
    ok "$name: $(eval "$version" 2>/dev/null | head -1)"
  else
    err "$name not found"
    for h in "$@"; do hint "$h"; done
    _pt_missing=$((_pt_missing + 1))
  fi
}

echo "== Pitchoune Timer tools"
_pt_check git git "git --version" "sudo apt install git"
_pt_check Flutter flutter "flutter --version --machine 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d[\"frameworkVersion\"], \"(\" + d[\"channel\"] + \"), Dart\", d[\"dartSdkVersion\"])' || flutter --version | head -1" \
  "sudo snap install flutter --classic   (or unpack the SDK in ~/flutter)" \
  "https://docs.flutter.dev/get-started/install/linux/android"
_pt_check "Java (keytool)" keytool "java -version 2>&1 | grep -v '^Picked up' | head -1" \
  "Android Studio ships one in ~/android-studio/jbr (found automatically)" \
  "or: sudo apt install openjdk-17-jdk-headless"
_pt_check "Android SDK: adb" adb "adb --version | head -1" \
  "Android Studio → SDK Manager → SDK Tools → Android SDK Platform-Tools" \
  "or: sudo apt install android-sdk-platform-tools"
_pt_check "Android SDK: apksigner" apksigner "echo \"$_pt_bt\" | sed 's|.*/build-tools/||; s|/$||; s|^|build-tools |'" \
  "Android Studio → SDK Manager → SDK Tools → Android SDK Build-Tools"
_pt_check "Python 3" python3 "python3 --version" "sudo apt install python3"
_pt_check Node.js node "node --version" "sudo apt install nodejs npm   (or https://nodejs.org)"
_pt_check "Firebase CLI" firebase "firebase --version" \
  "npm install -g firebase-tools   (then: firebase login)"
_pt_check "FlutterFire CLI" flutterfire "flutterfire --version" \
  "dart pub global activate flutterfire_cli"

echo "== Project"
if [[ -n $ANDROID_HOME ]]; then ok "ANDROID_HOME=$ANDROID_HOME"
else err "Android SDK not found"; hint "install Android Studio, or set ANDROID_HOME"; _pt_missing=$((_pt_missing + 1)); fi
if [[ -f $ROOT/android/key.properties ]]; then ok "release key: android/key.properties"
else warn "no android/key.properties: release builds use the debug key (README, Releasing)"; fi
if command -v firebase >/dev/null; then
  if firebase login:list 2>/dev/null | grep -q "@"; then ok "Firebase: $(firebase login:list 2>/dev/null | grep -o '[^ ]*@[^ ]*' | head -1)"
  else warn "Firebase CLI not signed in"; hint "firebase login"; fi
fi

if [[ $_pt_missing -gt 0 ]]; then
  err "$_pt_missing tool(s) missing"
else
  ok "everything is there"
fi
[[ $_pt_sourced == 0 ]] && echo "${C_DIM}(tip: 'source tool/env.sh' also sets the PATH of this terminal)${C_END}"
unset -f _pt_first_dir _pt_add_path _pt_check
[[ $_pt_sourced == 1 ]] && return 0 || exit $(( _pt_missing > 0 ))
