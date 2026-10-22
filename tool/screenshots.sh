#!/usr/bin/env bash
# Screenshots of the user guide (README.md), in doc/screenshots/.
#
#   tool/screenshots.sh --render     # draws them without any device, with a
#                                    # demo family (test_screenshots/): the
#                                    # pictures of the README
#   tool/screenshots.sh              # takes them on the tablet instead, one by
#                                    # one (it says what to show, Enter = capture)
#   tool/screenshots.sh running      # just one, on the tablet
#   tool/screenshots.sh --list       # the list
#
# On the tablet, the pictures are reduced to 480 px wide. The last three of
# the list exist only on a real device (camera, status bar, the tablet's apps).
set -euo pipefail
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/env.sh" --quiet
cd "$ROOT"

OUT=doc/screenshots
WIDTH=480

# name|what to show on the tablet
SHOTS=(
  "family|A device without family: the first screen (Create / Join a family)"
  "family-qr|Parent mode, home screen: the family button (QR code shown)"
  "setup|The Setup screen (⚙ → Permissions and setup)"
  "home|Parent mode, home screen with the children and their banks"
  "parent-code|The parent code keypad (tap the 🔒 of a child card)"
  "choose|A child's timer screen, before Start (amounts to choose)"
  "running|A countdown running"
  "finished|Time's up screen (+1 / +5 / +10 min, All, Stop)"
  "settings|Settings screen (⚙, parent code), child mode selected"
  "scan|Device only: Join a family → Scan the QR code (camera screen)"
  "status-bar|Device only: notification shade pulled down during a countdown"
  "my-apps|Device only: child mode, during a countdown, the My apps sheet"
)

capture() {   # name
  local tmp="$OUT/.$1.raw.png"
  adb exec-out screencap -p >"$tmp"
  if python3 -c "import PIL" 2>/dev/null; then
    python3 - "$tmp" "$OUT/$1.png" "$WIDTH" <<'PY'
import sys
from PIL import Image
src, dst, width = sys.argv[1], sys.argv[2], int(sys.argv[3])
im = Image.open(src)
im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
im.save(dst, optimize=True)
PY
    rm -f "$tmp"
  else
    mv "$tmp" "$OUT/$1.png"
    warn "pillow not installed (pip install pillow): full-size screenshot kept"
  fi
  ok "$OUT/$1.png"
}

if [[ ${1:-} == --render ]]; then
  command -v flutter >/dev/null || die "flutter not found: run tool/env.sh"
  flutter test --update-goldens test_screenshots/
  ok "Rendered in $OUT/ (demo family)"
  echo "Then: git add $OUT && git commit -m 'User guide screenshots'"
  exit 0
fi

if [[ ${1:-} == --list ]]; then
  for s in "${SHOTS[@]}"; do printf '  %-12s %s\n' "${s%%|*}" "${s#*|}"; done
  exit 0
fi

pick_device
mkdir -p "$OUT"
for s in "${SHOTS[@]}"; do
  name=${s%%|*}; what=${s#*|}
  [[ -n ${1:-} && $1 != "$name" ]] && continue
  echo
  echo "== $name: $what"
  read -r -p "Enter = capture, s = skip, q = quit: " answer || answer=q
  case $answer in
    s|S) continue ;;
    q|Q) break ;;
    *) capture "$name" ;;
  esac
done
echo
echo "Then: git add $OUT && git commit -m 'User guide screenshots'"
