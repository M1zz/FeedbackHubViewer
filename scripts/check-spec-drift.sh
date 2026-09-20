#!/bin/bash
# 스펙이 가리키는 지표·이벤트를 앱이 **아직 보내고 있는지** 대조한다.
#
#   ./scripts/check-spec-drift.sh
#
# `sync-stats-specs.sh --check` 는 사본이 낡았는지만 본다. 두 파일이 똑같이 틀린
# 경우 — 스펙이 앱에 더 이상 없는 지표를 가리키는 경우 — 는 이쪽이 잡는다.
# 실제로 그 일이 났다: 두번알림이 알림 한도를 없애며 `trial.prealerts` 를 안 보내게
# 됐는데 스펙은 그 키로 "막힌 사람"을 셌고, 없는 키는 0 으로 읽히니 그 칸은 몇 달
# 동안 늘 0 이었다. 0 은 "없다"처럼 보여서 아무도 못 알아챘다.
#
# 앱 목록은 `scripts/spec-sources.sh` 에 있다.
# 판단 근거와 **못 잡는 것**은 `scripts/lib/spec_drift.py` 머리말에 적어 두었다.

set -euo pipefail

cd "$(dirname "$0")/.."
source "scripts/spec-sources.sh"

status=0
for entry in "${SPECS[@]}"; do
  IFS='|' read -r repo rel name <<< "$entry"
  if [[ ! -f "$repo/$rel" ]]; then
    echo "⚠️  없음: $repo/$rel (건너뜀 — 앱 리포를 옆에 두고 다시 실행하세요)"
    status=1
    continue
  fi
  python3 scripts/lib/check_one_spec.py "$repo" "$rel" "$name" || status=1
done

if [[ $status -ne 0 ]]; then
  echo
  echo "스펙이 앱과 어긋났습니다. 원본은 앱 리포의 스펙 파일이고, 고친 뒤"
  echo "./scripts/sync-stats-specs.sh 로 뷰어에 다시 가져오세요."
fi
exit $status
