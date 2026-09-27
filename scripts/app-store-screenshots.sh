#!/bin/zsh
# App Store screenshots from the real app (6.9" iPhone, 1320 x 2868), dark mode, clean status bar.
#
#   scripts/app-store-screenshots.sh <Team ID> [<Team ID whose Today has something to review>]
#
# Runs the FPLToolkitUITests screens against the live API with that team and writes
# AppStore/screenshots/01-welcome.png … 08-notifications.png (git-ignored: they show a real team).
set -euo pipefail
cd "$(dirname "$0")/.."

TEAM=${1:?"usage: $0 <Team ID> [<attention Team ID>]"}
ATTENTION=${2:-$TEAM}
DEVICE="iPhone 17 Pro Max"
OUT="AppStore/screenshots"

UDID=$(xcrun simctl list devices available | grep -E "^ +$DEVICE \(" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
[[ -n "$UDID" ]] || { echo "No '$DEVICE' simulator installed" >&2; exit 1; }

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl ui "$UDID" appearance dark
xcrun simctl ui "$UDID" content_size large
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 \
  --cellularMode active --cellularBars 4 --wifiMode active --wifiBars 3 --dataNetwork wifi

RESULT="$(mktemp -d)/screens.xcresult"
# The accessibility audit may report issues; the screenshots are captured either way.
TEST_RUNNER_auditTeam="$TEAM" TEST_RUNNER_auditAttentionTeam="$ATTENTION" \
  xcodebuild test -project FPLToolkit.xcodeproj -scheme FPLToolkitUITests \
  -destination "id=$UDID" -parallel-testing-enabled NO -resultBundlePath "$RESULT" -quiet || true

rm -rf "$OUT" && mkdir -p "$OUT/raw"
xcrun xcresulttool export attachments --path "$RESULT" --output-path "$OUT/raw" >/dev/null
python3 - "$OUT" <<'PY'
import json, re, shutil, sys
out = sys.argv[1]
for test in json.load(open(f"{out}/raw/manifest.json")):
    for a in test.get("attachments", []):
        name = a.get("suggestedHumanReadableName", "")
        m = re.match(r"(\d\d-[a-z-]+)_", name)
        if m and name.endswith(".png"):
            shutil.copy(f"{out}/raw/{a['exportedFileName']}", f"{out}/{m.group(1)}.png")
PY
rm -rf "$OUT/raw"
xcrun simctl status_bar "$UDID" clear
ls -1 "$OUT"
