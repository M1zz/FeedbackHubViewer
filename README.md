# FeedbackHub Viewer (macOS · iOS · iPadOS)

`iCloud.com.Ysoup.FeedbackHub` 컨테이너의 **Public 데이터베이스**에 쌓인 사용자 피드백을
한눈에 볼 수 있는 SwiftUI 앱입니다. 하나의 타겟이 macOS와 iPhone/iPad에서 모두 돌아갑니다.
목록·상세 보기, 검색·필터·정렬, 프로젝트 개요, 통계 대시보드, 수동/자동 새로고침을 지원합니다.

- **Mac / iPad**: 사이드바(요약·필터) + 목록 + 상세의 3열 레이아웃
- **iPhone**: 개요 / 통계 / 목록 3개 탭, 사이드바는 "필터" 시트, 상세는 화면 전환.
  개요 탭에는 요약 스트립과 최근 피드백 미리보기가 함께 표시됩니다.

> ⚠️ 이 zip에는 **완성된 `.app` 실행 파일이 아니라 Xcode 프로젝트 소스**가 들어 있습니다.
> CloudKit 접근에는 본인의 Apple 개발자 계정 서명이 반드시 필요하기 때문에,
> 여러분이 Xcode에서 직접 빌드해야 정상 동작합니다. (아래 절차 참고)

---

## 1. 필요 환경

- macOS 14 (Sonoma) 이상 / iOS·iPadOS 17 이상
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
6. 실행 대상(destination)에서 **My Mac** 또는 **iPhone/iPad(시뮬레이터·실기기)** 를 고르고 `⌘R`로 실행합니다.
   기기에 iCloud 로그인이 되어 있어야 합니다(Security Role은 로그인한 계정 기준으로 판정됩니다).

## 2-1. Production 데이터 읽기

CloudKit은 어느 환경을 읽을지 **빌드에 박히는 entitlement**
(`com.apple.developer.icloud-container-environment`)로 정합니다. 런타임 토글은 불가능하므로,
**스킴을 골라서** 환경을 바꿉니다. Xcode 스킴 선택기에서 고르고 `⌘R`만 하면 됩니다.

| 스킴 | 빌드 구성 | 읽는 환경 | 번들 ID |
| --- | --- | --- | --- |
| `FeedbackHubViewer` | Debug | Development | `com.Ysoup.FeedbackHubViewer` |
| `FeedbackHubViewer (Production)` | Debug-Production | Production | `com.Ysoup.FeedbackHubViewer.prod` |
| (Archive/Release) | Release | Production | `com.Ysoup.FeedbackHubViewer` |

번들 ID가 달라서 **두 앱을 한 기기에 동시에 설치**해 놓고 오가며 볼 수 있고,
앱 아이콘도 다릅니다(Development=파랑, Production=초록).
현재 보고 있는 환경은 화면의 `DEV`/`PROD` 배지와 툴바 "내 계정 ID" 메뉴에서 확인할 수 있습니다.

> **Production에서 데이터가 보이려면 Console 작업이 선행되어야 합니다.**
> [CloudKit Console](https://icloud.developer.apple.com/dashboard/)에서 스키마와
> Security Role(admin 역할에 내 userRecordName 등록 + 피드백 레코드 타입 read 권한)을
> **Deploy to Production** 해야 합니다. 배포 전에는 `permissionFailure`가 납니다.
> 등록에 쓸 내 userRecordName은 권한 오류 메시지와 툴바 "내 계정 ID" 메뉴에 표시됩니다.

## 3. 주요 기능

- **목록 + 상세**: Mac/iPad는 오른쪽 열, iPhone은 화면 전환으로 전체 내용과 모든 필드를 봅니다.
  (iPhone 상세 화면에는 텍스트 전체를 복사·공유할 수 있는 공유 버튼이 있습니다.)
- **검색**: 상단 검색창에서 본문·버전·기기·이메일·기타 모든 필드를 대상으로 키워드 검색.
- **필터**: 사이드바(iPhone은 왼쪽 위 필터 버튼 → 시트)에서 프로젝트, 앱 버전, 최소 별점으로 필터링.
- **정렬**: 최신순 / 오래된순 / 별점 높은순 / 별점 낮은순.
- **프로젝트 개요**: 프로젝트별 카드(건수·평균 별점·최근 7일·마지막 수신). iPhone에서는 요약 스트립과
  최근 피드백 5건 미리보기가 함께 나옵니다.
- **통계 대시보드**: 헤드라인 타일, 최근 30일 추이, 별점·유형·프로젝트·버전별 분포(Swift Charts).
- **새로고침**: 툴바의 새로고침 버튼(macOS `⌘R`), iPhone에서는 당겨서 새로고침, "자동 갱신" 토글(1분 주기).

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
   `FeedbackHubViewer` 스킴은 Development, `FeedbackHubViewer (Production)` 스킴은 Production을 봅니다(위 2-1 참고).
5. **권한**: LeeoKit은 World에서 read를 빼고 저장하므로, CloudKit Console → Security Roles의 admin 역할에
   내 iCloud **userRecordName**을 등록하고 피드백 레코드 타입에 read를 줘야 합니다.
   권한 오류가 나면 앱이 등록에 쓸 userRecordName을 오류 메시지와 "내 계정 ID" 메뉴에 표시합니다.

## 6. 프로젝트 구성

```
FeedbackHubViewer/
├─ FeedbackHubViewer.xcodeproj
└─ FeedbackHubViewer/
   ├─ FeedbackHubViewerApp.swift   # 앱 진입점 (플랫폼별 Scene 설정)
   ├─ Feedback.swift               # 레코드 → 모델 매핑(스키마 유연)
   ├─ CloudKitService.swift        # Public DB 조회(CKContainer) + 환경(CloudKitEnvironment)
   ├─ EnvironmentControls.swift    # 현재 환경 DEV/PROD 배지
   ├─ Assets.xcassets              # 앱 아이콘 (AppIcon / AppIconProduction)
   ├─ FeedbackStore.swift          # 상태/필터/정렬/통계/자동갱신
   ├─ ContentView.swift            # 레이아웃 선택 + 3열(SplitRootView) + 툴바
   ├─ PhoneRootView.swift          # iPhone 탭 레이아웃 + 공용 툴바/필터 시트
   ├─ PlatformSupport.swift        # macOS/iOS 차이 흡수(붙여넣기·리스트 스타일·날짜 포맷)
   ├─ SidebarView.swift            # 요약 + 프로젝트 선택 + 필터
   ├─ ProjectOverviewView.swift    # 프로젝트 카드 그리드(+iPhone 요약·최근 피드백)
   ├─ StatisticsView.swift         # 통계 대시보드
   ├─ FeedbackListView.swift       # 목록
   ├─ FeedbackDetailView.swift     # 상세
   ├─ FeedbackHubViewer.entitlements                # macOS · Development
   ├─ FeedbackHubViewer-Production.entitlements     # macOS · Production
   ├─ FeedbackHubViewer-iOS.entitlements            # iOS · Development
   └─ FeedbackHubViewer-iOS-Production.entitlements # iOS · Production
```
