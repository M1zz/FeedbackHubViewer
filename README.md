# FeedbackHub Viewer (macOS)

`iCloud.com.Ysoup.FeedbackHub` 컨테이너의 **Public 데이터베이스**에 쌓인 사용자 피드백을
한눈에 볼 수 있는 SwiftUI 맥앱입니다. 목록·상세 보기, 검색·필터·정렬, 통계 요약,
수동/자동 새로고침을 지원합니다.

> ⚠️ 이 zip에는 **완성된 `.app` 실행 파일이 아니라 Xcode 프로젝트 소스**가 들어 있습니다.
> CloudKit 접근에는 본인의 Apple 개발자 계정 서명이 반드시 필요하기 때문에,
> 여러분이 Xcode에서 직접 빌드해야 정상 동작합니다. (아래 절차 참고)

---

## 1. 필요 환경

- macOS 14 (Sonoma) 이상
- Xcode 16 이상
- `com.Ysoup.FeedbackHub` 앱이 속한 **Apple Developer 팀 계정** (CloudKit 컨테이너 접근 권한이 있어야 함)

## 2. 빌드 & 실행 절차

1. 압축을 풀고 `FeedbackHubViewer/FeedbackHubViewer.xcodeproj`를 Xcode로 엽니다.
2. 프로젝트 네비게이터에서 **FeedbackHubViewer 타겟 → Signing & Capabilities** 탭으로 이동합니다.
3. **Team**을 여러분의 개발자 팀(FeedbackHub 컨테이너에 접근 권한이 있는 팀)으로 선택합니다.
4. **iCloud** Capability에 `iCloud.com.Ysoup.FeedbackHub` 컨테이너가 체크되어 있는지 확인합니다.
   (이미 entitlements에 지정돼 있지만, 팀을 바꾸면 Xcode가 목록을 다시 불러옵니다.)
5. 필요하다면 **Bundle Identifier**(`com.Ysoup.FeedbackHubViewer`)를 여러분 것에 맞게 바꿔도 됩니다.
   단, iCloud 컨테이너 ID(`iCloud.com.Ysoup.FeedbackHub`)는 **그대로 두어야** 같은 데이터를 봅니다.
6. `⌘R`로 실행합니다. 처음 실행 시 Mac에 로그인된 iCloud 계정이 있으면 좋습니다.

## 3. 주요 기능

- **목록 + 상세**: 가운데 목록에서 항목을 고르면 오른쪽에 전체 내용과 모든 필드가 표시됩니다.
- **검색**: 상단 검색창에서 본문·버전·기기·이메일·기타 모든 필드를 대상으로 키워드 검색.
- **필터**: 왼쪽 사이드바에서 앱 버전, 최소 별점으로 필터링.
- **정렬**: 최신순 / 오래된순 / 별점 높은순 / 별점 낮은순.
- **통계 요약**: 전체 건수, 평균 별점, 최근 7일 건수, 별점 분포, 버전별 건수.
- **새로고침**: 툴바의 새로고침 버튼(`⌘R`) 또는 "자동 갱신" 토글(1분 주기).

## 4. 데이터 구조에 대한 참고 (중요)

정확한 CloudKit 스키마를 알려주지 않으셨기 때문에, 앱은 **일반적인 구조로 추정**해서 동작합니다.

- **레코드 타입**: `Feedback`, `Feedbacks`, `FeedbackItem`, `UserFeedback`, `Review` 등
  흔한 이름을 차례로 시도해 데이터가 나오는 첫 타입을 사용합니다.
  실제 타입 이름이 다르면 **`CloudKitService.swift`의 `candidateRecordTypes` 배열 맨 앞에
  실제 이름을 추가**하고 다시 빌드하세요.
- **필드 매핑**: 아래 이름들을 자동으로 인식합니다(대소문자 무시).
  - 본문: `text`, `message`, `content`, `body`, `feedback`, `comment`, `description` …
  - 별점: `rating`, `stars`, `score`, `rate`
  - 앱 버전: `appVersion`, `version`, `buildVersion` …
  - 기기: `deviceModel`, `device`, `model` …
  - OS: `systemVersion`, `osVersion`, `os` …
  - 이메일: `email`, `contactEmail`, `contact` …
  인식하지 못한 필드도 상세 화면의 **"모든 필드"** 표에 그대로 표시되므로 데이터는 절대 누락되지 않습니다.

## 5. 데이터가 안 보일 때 체크리스트

CloudKit Public DB는 필드가 **Queryable**로 표시돼 있어야 조회되고, 정렬하려면 **Sortable**이어야 합니다.
비어 있게 나온다면 [CloudKit Console](https://icloud.developer.apple.com/dashboard/)에서 다음을 확인하세요.

1. 컨테이너 `iCloud.com.Ysoup.FeedbackHub` → **Schema → Record Types**에서 피드백 레코드 타입의 실제 이름 확인
   (다르면 `candidateRecordTypes`에 추가).
2. 조회에 쓰는 시스템 인덱스 `recordName`(및 필요한 필드)이 **Queryable**로 설정돼 있는지 확인.
3. 정렬용으로 `createdTimestamp`가 **Sortable**인지 확인. (아니어도 앱은 자동으로 정렬 없이 다시 조회합니다.)
4. **Environment**: 개발 중에는 Development, 배포된 데이터는 Production에 있습니다.
   Xcode에서 디버그 실행하면 기본적으로 Development 환경을 봅니다. 필요하면 스킴 설정에서 조정하세요.

## 6. 프로젝트 구성

```
FeedbackHubViewer/
├─ FeedbackHubViewer.xcodeproj
└─ FeedbackHubViewer/
   ├─ FeedbackHubViewerApp.swift   # 앱 진입점
   ├─ Feedback.swift               # 레코드 → 모델 매핑(스키마 유연)
   ├─ CloudKitService.swift        # Public DB 조회 로직
   ├─ FeedbackStore.swift          # 상태/필터/정렬/통계/자동갱신
   ├─ ContentView.swift            # 3열 레이아웃
   ├─ SidebarView.swift            # 통계 + 필터
   ├─ FeedbackListView.swift       # 목록
   ├─ FeedbackDetailView.swift     # 상세
   └─ FeedbackHubViewer.entitlements
```
