#!/bin/bash
# 앱별 통계 스펙(usage-spec.json)을 각 앱 리포에서 뷰어로 가져온다.
#
# 원본은 지표를 만드는 곳, 즉 앱 리포에 있다(<앱>/docs/usage-spec.json).
# 지표를 추가하는 커밋에서 라벨도 같이 쓰게 되고, 뷰어는 그 사본만 번들에 넣는다.
#
#   ./scripts/sync-stats-specs.sh              # 기본 위치(형제 디렉터리)에서 가져오기
#   ./scripts/sync-stats-specs.sh --check      # 다른지만 확인 (CI/커밋 전)
#
# 새 앱을 추가하려면 아래 SPECS 에 "<리포 경로>|<저장할 이름>" 한 줄만 더한다.

set -euo pipefail

cd "$(dirname "$0")/.."
# 이 리포는 workspace/code/FeedbackHubViewer 에 있고, 앱 리포는 workspace/Auto/ 에 있다.
# 그래서 두 칸 올라가야 workspace 다 (한 칸은 code/ 까지밖에 못 간다).
WORKSPACE="$(cd ../.. && pwd)"
DEST="FeedbackHubViewer/Specs"

# 두 앱 모두 code/ 가 아니라 workspace/Auto/ 아래에 있고, 디렉터리 이름은 한글이다.
# ⚠️ 예전에는 여기가 "$WORKSPACE/ClipKeyboard/..." 와 "$WORKSPACE/../Auto/두번알림/..." 이었다.
#    둘 다 없는 경로라 스크립트는 늘 "없음 … 건너뜀"만 찍고 지나갔고, --check 가 드리프트를
#    한 번도 못 잡았다. 스펙이 앱 코드와 어긋난 채 몇 달을 갔던 것이 그 탓이다.
SPECS=(
  "$WORKSPACE/Auto/클립키보드/docs/engineering/usage-spec.json|clipkeyboard.usage-spec.json"
  "$WORKSPACE/Auto/두번알림/docs/usage-spec.json|rereminder.usage-spec.json"
)

check_only=false
[[ "${1:-}" == "--check" ]] && check_only=true

mkdir -p "$DEST"
status=0

for entry in "${SPECS[@]}"; do
  src="${entry%%|*}"
  name="${entry##*|}"
  dst="$DEST/$name"

  if [[ ! -f "$src" ]]; then
    echo "⚠️  없음: $src (건너뜀 — 앱 리포를 옆에 두고 다시 실행하세요)"
    status=1
    continue
  fi

  # 형식이 깨진 JSON을 번들에 넣으면 뷰어는 그 앱만 조용히 일반 화면으로 떨어진다.
  if ! python3 -m json.tool "$src" >/dev/null 2>&1; then
    echo "❌  JSON 오류: $src"
    status=1
    continue
  fi

  if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then
    echo "✓   같음: $name"
    continue
  fi

  if $check_only; then
    echo "✗   다름: $name  (./scripts/sync-stats-specs.sh 로 갱신하세요)"
    status=1
  else
    cp "$src" "$dst"
    echo "→   가져옴: $name"
  fi
done

exit $status
