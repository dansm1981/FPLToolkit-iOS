#!/bin/zsh
# Screens for a design review, from the real app against the live API with one team:
# every main screen top to bottom, a screenshot per screenful (ReviewCaptureTests), plus the
# audit's screens, dialogs and states (ScreenAuditTests).
#
#   scripts/review-screens.sh <Team ID> [<out dir>]
#
# Writes <out dir>/r10-today~01.png …, 01-welcome.png … (default Review/screens, git-ignored: it
# shows a real team). Runs on the shared iPhone 17 simulator: take its lock first (see README).
set -euo pipefail
cd "$(dirname "$0")/.."

TEAM=${1:?"usage: $0 <Team ID> [<out dir>]"}
OUT=${2:-Review/screens}
DEVICE="iPhone 17"

UDID=$(xcrun simctl list devices available | grep -E "^ +$DEVICE \(" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
[[ -n "$UDID" ]] || { echo "No '$DEVICE' simulator installed" >&2; exit 1; }

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl ui "$UDID" appearance dark
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 \
  --cellularMode active --cellularBars 4 --wifiMode active --wifiBars 3 --dataNetwork wifi

RESULT="$(mktemp -d)/review.xcresult"
# Audit failures don't matter here: the screenshots are captured either way.
TEST_RUNNER_reviewCapture=1 TEST_RUNNER_reviewTeam="$TEAM" TEST_RUNNER_auditTeam="$TEAM" \
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
        m = re.match(r"(r\d+b?-[a-z0-9-]+~\d\d|\d\d[a-z]?-[a-z0-9-]+)_", name)
        if m and name.endswith(".png"):
            shutil.copy(f"{out}/raw/{a['exportedFileName']}", f"{out}/{m.group(1)}.png")
PY
rm -rf "$OUT/raw"
xcrun simctl status_bar "$UDID" clear
echo "$(ls -1 "$OUT" | wc -l | tr -d ' ') screenshots in $OUT"
