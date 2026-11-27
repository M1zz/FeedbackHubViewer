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

# 이 리포는 workspace/개발중/FeedbackHubViewer 에 있고, 앱 리포는 workspace/Auto/ 에 있다.
# 두 칸 올라간 workspace 를 기준으로 적는다.
WORKSPACE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

# ⚠️ 예전에는 경로가 "$WORKSPACE/ClipKeyboard/..." 와 "$WORKSPACE/../Auto/두번알림/..." 이었다.
#    둘 다 없는 경로라 스크립트는 늘 "없음 … 건너뜀"만 찍고 지나갔고, --check 가 드리프트를
#    한 번도 못 잡았다. 스펙이 앱 코드와 어긋난 채 몇 달을 갔던 것이 그 탓이다.
# ⚠️ 2026-09 에 앱 리포가 workspace/code/<영문 이름> 으로 옮겨져 위 Auto/ 경로가 또 죽었다.
# ⚠️ 2026-11 지금 앱 리포는 workspace/Auto/<한글 이름> 에 있다(DeployBar 가 배포하는 곳). code/ 경로는 다시 죽어 있었다.
SPECS=(
  "$WORKSPACE/Auto/클립키보드|docs/engineering/usage-spec.json|clipkeyboard.usage-spec.json"
  "$WORKSPACE/Auto/두번알림|docs/usage-spec.json|rereminder.usage-spec.json"
  "$WORKSPACE/Auto/StickyPresenter|docs/usage-spec.json|com.leeo.stickypresenter.usage-spec.json"
  "$WORKSPACE/Auto/tetratint|docs/usage-spec.json|com.leeo.tetratint.usage-spec.json"
  "$WORKSPACE/Auto/골드위크|docs/usage-spec.json|com.ysoup.leavewise.usage-spec.json"
  "$WORKSPACE/Auto/그사이에|docs/usage-spec.json|com.leeo.geusaie.usage-spec.json"
  "$WORKSPACE/Auto/낫마템포|docs/usage-spec.json|com.leeo.handsfreemetronome.usage-spec.json"
  "$WORKSPACE/Auto/달빛 오락실|docs/usage-spec.json|com.example.moonlitorder.usage-spec.json"
  "$WORKSPACE/Auto/달빛|docs/usage-spec.json|com.leeo.lullabyrecipe.usage-spec.json"
  "$WORKSPACE/Auto/돈꼬마트|docs/usage-spec.json|com.leeo.dontgomart.usage-spec.json"
  "$WORKSPACE/Auto/디자인실습|docs/usage-spec.json|com.leeo.higgym.usage-spec.json"
  "$WORKSPACE/Auto/마이파이|docs/usage-spec.json|com.leeo.wifisnap.usage-spec.json"
  "$WORKSPACE/Auto/말문|docs/usage-spec.json|com.devkoan.indonesiansmalltalk.usage-spec.json"
  "$WORKSPACE/Auto/무지개 공방|docs/usage-spec.json|com.devkoan.scheduledensityapp.usage-spec.json"
  "$WORKSPACE/Auto/밑줄|docs/usage-spec.json|com.leeo.bookmarkshot.usage-spec.json"
  "$WORKSPACE/Auto/벅뚜벅뚜|docs/usage-spec.json|com.leeo.footprintdiary.usage-spec.json"
  "$WORKSPACE/Auto/보태줘|docs/usage-spec.json|com.leeo.moa.usage-spec.json"
  "$WORKSPACE/Auto/불타는내인생|docs/usage-spec.json|com.burningparchment.app.usage-spec.json"
  "$WORKSPACE/Auto/세끼|docs/usage-spec.json|com.ysoup.routinecamera.usage-spec.json"
  "$WORKSPACE/Auto/셔터링크|docs/usage-spec.json|com.devkoan.shutterlink.usage-spec.json"
  "$WORKSPACE/Auto/쑥쑥용돈|docs/usage-spec.json|com.family.familybank.usage-spec.json"
  "$WORKSPACE/Auto/아이일정|docs/usage-spec.json|com.devkoan.calendarsnap.usage-spec.json"
  "$WORKSPACE/Auto/여울|docs/usage-spec.json|com.leeo.yeoul.usage-spec.json"
  "$WORKSPACE/Auto/욕망의 무지개|docs/usage-spec.json|com.example.scheduledensityapp.usage-spec.json"
  "$WORKSPACE/Auto/우리집 가정법원|docs/usage-spec.json|com.family.familycourt.usage-spec.json"
  "$WORKSPACE/Auto/이어생각|docs/usage-spec.json|com.leeo.thinkflow.usage-spec.json"
  "$WORKSPACE/Auto/인생맛집|docs/usage-spec.json|com.ysoup.restaurantmap.usage-spec.json"
  "$WORKSPACE/Auto/장표스냅|docs/usage-spec.json|com.leeo.slidesnap.usage-spec.json"
  "$WORKSPACE/Auto/질문노트|docs/usage-spec.json|com.lectureq.lectureq.usage-spec.json"
  "$WORKSPACE/Auto/초견|docs/usage-spec.json|com.devkoan.staffsinger.usage-spec.json"
  "$WORKSPACE/Auto/쿨타임|docs/usage-spec.json|com.ysoup.cooltime.usage-spec.json"
  "$WORKSPACE/Auto/퇴사각|docs/usage-spec.json|com.devkoan.firetracker.usage-spec.json"
  "$WORKSPACE/Auto/팔랑북|docs/usage-spec.json|com.leeo.rotoscopeipad.usage-spec.json"
  "$WORKSPACE/Auto/펀칭|docs/usage-spec.json|com.devkoan.stampcamera.usage-spec.json"
  "$WORKSPACE/Auto/하늘색|docs/usage-spec.json|com.leeo.skydex.usage-spec.json"
  "$WORKSPACE/Auto/한국길찾기|docs/usage-spec.json|com.kora.leeo.usage-spec.json"
  "$WORKSPACE/Auto/한땀|docs/usage-spec.json|com.leeo.pixelme.usage-spec.json"
  "$WORKSPACE/Auto/햇빛바라기|docs/usage-spec.json|com.leeo.sunflower.usage-spec.json"
  "$WORKSPACE/Auto/모찌모|docs/usage-spec.json|com.leeo.reboundjournal.usage-spec.json"
  "$WORKSPACE/Auto/탭클립키보드|docs/usage-spec.json|com.ysoup.tokenmemo-tap.usage-spec.json"
  "$WORKSPACE/개발중/조주기능사실기|docs/usage-spec.json|com.leeo.bartenderpractice.usage-spec.json"
)

# 유입 경로 지도. 형식은 SPECS 와 같다. 허브의 "유입" 탭이 이것으로 어디가 새는지 판정한다.
# 뷰어 쪽 이름은 반드시 `.acquisition.json` 으로 끝나야 한다(통계 스펙과 가르는 표시).
ACQUISITION=(
  "$WORKSPACE/Auto/클립키보드|docs/engineering/acquisition.json|clipkeyboard.acquisition.json"
)

DEST="FeedbackHubViewer/Specs"
