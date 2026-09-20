#!/bin/bash
# 앱별 통계 스펙이 어디에 있는지 — **이 목록의 원본은 여기 하나뿐이다.**
#
# `sync-stats-specs.sh`(사본 가져오기)와 `check-spec-drift.sh`(스펙↔앱 대조)가
# 둘 다 이 파일을 읽는다. 목록을 양쪽에 따로 두면 그 둘이 어긋나고, 그건 이
# 스크립트들이 잡으려는 바로 그 종류의 버그다.
#
# 새 앱을 더하려면 아래 SPECS 에 한 줄만 넣는다:
#
#     "<앱 리포 경로>|<리포 안에서 스펙 위치>|<뷰어 번들에 저장할 이름>"
#
# 앱 리포 경로가 따로 필요한 까닭: 드리프트 검사는 스펙만 보는 게 아니라 **그 앱의
# Swift 코드**를 읽어서 "스펙이 가리키는 지표를 아직 보내고 있는가"를 묻는다.

# 이 리포는 workspace/code/FeedbackHubViewer 에 있고, 앱 리포는 workspace/Auto/ 에 있다.
# 그래서 두 칸 올라가야 workspace 다 (한 칸은 code/ 까지밖에 못 간다).
WORKSPACE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

# ⚠️ 예전에는 경로가 "$WORKSPACE/ClipKeyboard/..." 와 "$WORKSPACE/../Auto/두번알림/..." 이었다.
#    둘 다 없는 경로라 스크립트는 늘 "없음 … 건너뜀"만 찍고 지나갔고, --check 가 드리프트를
#    한 번도 못 잡았다. 스펙이 앱 코드와 어긋난 채 몇 달을 갔던 것이 그 탓이다.
SPECS=(
  "$WORKSPACE/Auto/클립키보드|docs/engineering/usage-spec.json|clipkeyboard.usage-spec.json"
  "$WORKSPACE/Auto/두번알림|docs/usage-spec.json|rereminder.usage-spec.json"
)

DEST="FeedbackHubViewer/Specs"
