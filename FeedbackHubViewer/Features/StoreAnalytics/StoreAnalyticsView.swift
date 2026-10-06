//
//  StoreAnalyticsView.swift
//  FeedbackHubViewer
//
//  스토어 분석 탭. App Store Connect 분석 리포트에서 Apple 만 아는 것을 한 앱씩 보인다.
//
//  읽는 차례:
//   1. 분석 — 몰린 기간과 평상시를 갈라 읽은 판정(`StoreInsights`), 그리고 창 전체의 숫자
//   2. 사용(세션) · 설치와 삭제 · 다운로드 구성 · 스토어 행동 · 구매 · 웹 미리보기 ·
//      설치 성능 · 크래시 · 설치 경로 · 구독
//   3. 리포트 전부 훑기 — 위에 없는 리포트(위젯 · 단축어 …)에 데이터가 있으면 거기서 본다
//
//  노출 → 다운로드 퍼널과 링크 출처는 유입 · 키워드 탭에 이미 있어서 여기서 다시 그리지 않는다.
//

import SwiftUI

struct StoreAnalyticsView: View {
    @EnvironmentObject private var connect: AppStoreConnectStore
    /// nil == 전체 프로젝트.
    let project: String?

    @State private var isRequesting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !connect.isConfigured {
                    Card(title: "App Store Connect 연결 필요", systemImage: "key") {
                        AnalyticsNote("App Store Connect 키를 넣으면 Apple 이 모은 세션 · 삭제 · 다운로드 · 구매 · 설치 성능 · 크래시 리포트가 앱마다 나옵니다.")
                        OpenSettingsButton(title: "설정 열기").font(.body)
                    }
                } else if let project {
                    content(project)
                } else {
                    AnalyticsCoverageCard()
                }
            }
            .padding()
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .task(id: project) {
            if let project { await connect.loadStoreAnalytics(bundleID: project) }
        }
    }

    @ViewBuilder
    private func content(_ project: String) -> some View {
        switch connect.storeAnalytics[project] {
        case nil, .loading?:
            Card(title: "분석 리포트", systemImage: "chart.xyaxis.line") {
                ProgressView("리포트 열두 종을 받는 중… 처음 한 번은 1~2분 걸립니다").font(.body)
            }
        case .failed(let message)?:
            Card(title: "분석 리포트를 못 받았습니다", systemImage: "exclamationmark.triangle") {
                Text(message).font(.body).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button("다시 받기") { Task { await connect.loadStoreAnalytics(bundleID: project, force: true) } }
            }
        case .loaded(.noRequest)?:
            Card(title: "분석 리포트 요청이 없습니다", systemImage: "tray") {
                AnalyticsNote("이 앱은 아직 App Store 분석 리포트를 요청하지 않았습니다. 요청하면 지난 기록과 함께 1~2일 뒤부터 채워지고, 그다음부터 하루치씩 쌓여요. 요청은 한 번이면 되고, 스토어에 보이는 것은 아무것도 바뀌지 않습니다.")
                Button(isRequesting ? "요청 중…" : "리포트 요청 만들기") {
                    isRequesting = true
                    Task {
                        await connect.requestAnalytics(bundleID: project)
                        await connect.loadStoreAnalytics(bundleID: project, force: true)
                        isRequesting = false
                    }
                }
                .disabled(isRequesting)
            }
        case .loaded(.ready(let analytics))?:
            if analytics.isEmpty {
                Card(title: "아직 쌓인 리포트가 없습니다", systemImage: "hourglass") {
                    AnalyticsNote("App Store Connect 웹의 분석 탭에는 Apple 이 모아 둔 지난 기록이 다 있지만, 분석 API 는 리포트 요청을 만든 날부터만 쌓습니다. 이 앱은 요청은 있는데 최근 \(analytics.days)일에 만들어진 파일이 없어요.")
                    SnapshotRequestView(project: project)
                }
            } else {
                if analytics.coveredDays.count < analytics.days - 5, connect.analyticsSnapshots[project] == false {
                    Card(title: "기록이 \(analytics.coveredDays.count)일 치뿐입니다", systemImage: "clock.arrow.circlepath") {
                        AnalyticsNote("분석 API 는 요청을 만든 날(\(analytics.coveredDays.first.map(StoreInsights.Period.short) ?? "—"))부터만 쌓습니다. 지난 기록을 한 번 받으면 최근 \(analytics.days)일이 채워져 판정이 정확해집니다.")
                        SnapshotRequestView(project: project)
                    }
                }
                cards(analytics)
            }
            AnalyticsExplorerCard(project: project)
        }
    }

    @ViewBuilder
    private func cards(_ analytics: StoreAnalytics) -> some View {
        if let insights = analytics.insights { StoreInsightsCard(insights: insights) }
        AnalyticsSummaryCard(analytics: analytics)
        if let sessions = analytics.sessions { SessionsCard(sessions: sessions, days: analytics.days) }
        if let installs = analytics.installs { InstallsCard(installs: installs) }
        if let downloads = analytics.downloads { DownloadsCard(downloads: downloads) }
        if let engagement = analytics.engagement { EngagementCard(engagement: engagement) }
        if let purchases = analytics.purchases { PurchasesCard(purchases: purchases) }
        if let web = analytics.webPreview { WebPreviewCard(web: web) }
        if let performance = analytics.installPerformance { InstallPerformanceCard(performance: performance) }
        if let crashes = analytics.crashes { AnalyticsCrashesCard(crashes: crashes) }
        if let platform = analytics.platformInstalls { PlatformInstallsCard(platform: platform) }
        if let events = analytics.subscriptionEvents {
            Card(title: "구독 이벤트", systemImage: "arrow.triangle.2.circlepath") { AnalyticsDigestView(digest: events) }
        }
        if let states = analytics.subscriptionStates {
            Card(title: "구독 상태", systemImage: "person.2.badge.gearshape") { AnalyticsDigestView(digest: states) }
        }
        AnalyticsNote("숫자는 Apple 의 App Store Connect 분석 리포트입니다. 하루 이틀 늦게 나오고, 너무 작은 칸은 프라이버시 기준 때문에 통째로 빠집니다. 세션 · 삭제 · 크래시는 기기 설정에서 \"앱 개발자와 공유\" 를 켠 사람만 세서 실제보다 작습니다 — 비율로 읽으세요.")
    }
}

// MARK: - 지난 기록

/// 지난 기록(ONE_TIME_SNAPSHOT)을 한 번 받는 단추. 이미 요청했으면 기다리라고만 한다.
struct SnapshotRequestView: View {
    @EnvironmentObject private var connect: AppStoreConnectStore
    let project: String

    @State private var isRequesting = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if connect.analyticsSnapshots[project] == true {
                AnalyticsNote("지난 기록을 이미 요청했습니다. Apple 이 만들기까지 1~2일 걸리고, 그다음 열면 채워집니다.")
            } else {
                Button(isRequesting ? "요청 중…" : "지난 기록 받기") {
                    isRequesting = true
                    Task {
                        message = await connect.requestAnalyticsSnapshot(bundleID: project)
                        isRequesting = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRequesting)
                AnalyticsNote("Apple 에 지난 기록을 한 번 만들어 달라고 요청합니다. 스토어에 보이는 것은 아무것도 바뀌지 않습니다.")
            }
            if let message {
                Text(message).font(.body).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - 한눈에

struct AnalyticsSummaryCard: View {
    let analytics: StoreAnalytics

    var body: some View {
        Card(title: "숫자 (최근 \(analytics.days)일 합계)", systemImage: "number") {
            FigureRow {
                if let devices = analytics.sessions?.dailyDevices {
                    Figure("하루 사용 기기", AnalyticsFormat.decimal(devices), note: "공유 동의한 기기")
                }
                if let duration = analytics.sessions?.averageDuration {
                    Figure("세션 길이", AnalyticsFormat.seconds(duration), note: "평균")
                }
                if let installs = analytics.installs {
                    Figure("새 설치 · 삭제", "\(AnalyticsFormat.count(installs.newInstalls)) · \(AnalyticsFormat.count(installs.deletions))")
                }
                if let downloads = analytics.downloads {
                    Figure("첫 다운로드", AnalyticsFormat.count(downloads.firstTime),
                           note: "다시 받기 \(AnalyticsFormat.count(downloads.redownloads))")
                }
                if let purchases = analytics.purchases {
                    Figure("구매 수익", AnalyticsFormat.usd(purchases.proceeds),
                           note: "구매 \(AnalyticsFormat.count(purchases.purchases))건")
                }
                if let rate = analytics.installPerformance?.successRate {
                    Figure("설치 성공", AnalyticsFormat.percent(rate))
                }
                if let rate = analytics.optIn?.rate {
                    Figure("분석 공유 동의", AnalyticsFormat.percent(rate), note: "받은 사람 중")
                }
            }
        }
    }
}

// MARK: - 사용

struct SessionsCard: View {
    let sessions: StoreAnalytics.Sessions
    let days: Int

    var body: some View {
        Card(title: "앱 사용 — 세션", systemImage: "hand.tap") {
            FigureRow {
                Figure("세션", AnalyticsFormat.count(sessions.sessions), note: "\(sessions.activeDays)일")
                if let devices = sessions.dailyDevices { Figure("하루 사용 기기", AnalyticsFormat.decimal(devices), note: "평균") }
                if let perDevice = sessions.sessionsPerDevice { Figure("기기당 세션", AnalyticsFormat.decimal(perDevice), note: "쓰는 날") }
                if let duration = sessions.averageDuration { Figure("세션 길이", AnalyticsFormat.seconds(duration), note: "평균") }
                Figure("쓴 시간", AnalyticsFormat.seconds(sessions.duration), note: "합")
            }
            AnalyticsDayChart(points: sessions.daily,
                              first: ChartSeries("sessions", "세션", .blue),
                              second: ChartSeries("devices", "사용 기기", .green))
            ShareGrid {
                ShareList(title: "받은 지 얼마나 된 사람이 쓰나", shares: sessions.byAge, tint: .purple)
                ShareList(title: "버전별", shares: sessions.byVersion)
                ShareList(title: "나라별", shares: sessions.byTerritory, tint: .teal)
                ShareList(title: "어디서 받은 사람", shares: sessions.bySource, tint: .orange)
                ShareList(title: "기기", shares: sessions.byDevice, tint: .gray)
            }
            AnalyticsNote("\"받은 지\" 는 그 기기가 앱을 받은 날부터 세션 날까지입니다. \"오래전 · 모름\" 은 리포트 창보다 먼저 받은 사람 — 남아서 쓰는 사람이에요.")
        }
    }
}

// MARK: - 설치 · 삭제

struct InstallsCard: View {
    let installs: StoreAnalytics.Installs

    var body: some View {
        Card(title: "설치와 삭제", systemImage: "trash") {
            FigureRow {
                Figure("새 설치", AnalyticsFormat.count(installs.newInstalls), note: "첫 + 다시 받기")
                Figure("삭제", AnalyticsFormat.count(installs.deletions), tint: installs.deletions > 0 ? .red : .primary)
                if let early = installs.earlyDeletionShare { Figure("일주일 안에 지움", AnalyticsFormat.percent(early), note: "삭제 중") }
            }
            AnalyticsDayChart(points: installs.daily,
                              first: ChartSeries("installs", "새 설치", .green),
                              second: ChartSeries("deletions", "삭제", .red))
            ShareGrid {
                ShareList(title: "받고 얼마 만에 지웠나", shares: installs.deletionAge, tint: .red)
                ShareList(title: "지운 버전", shares: installs.deletionsByVersion, tint: .red)
                ShareList(title: "지운 나라", shares: installs.deletionsByTerritory, tint: .red)
                ShareList(title: "지운 사람은 어디서 받았나", shares: installs.deletionsBySource, tint: .red)
                ShareList(title: "설치 종류", shares: installs.installsByType, tint: .green)
            }
            AnalyticsNote("받은 날에 지운 사람이 많으면 첫 화면 · 권한 요청에서 막힌 겁니다. 특정 버전에 몰리면 그 버전을 보세요.")
        }
    }
}

// MARK: - 다운로드

struct DownloadsCard: View {
    let downloads: StoreAnalytics.Downloads

    var body: some View {
        Card(title: "다운로드 구성", systemImage: "arrow.down.circle") {
            FigureRow {
                Figure("첫 다운로드", AnalyticsFormat.count(downloads.firstTime))
                Figure("다시 받기", AnalyticsFormat.count(downloads.redownloads))
            }
            AnalyticsDayChart(points: downloads.daily,
                              first: ChartSeries("first", "첫 다운로드", .blue),
                              second: ChartSeries("again", "다시 받기", .orange))
            ShareGrid {
                ShareList(title: "종류", shares: downloads.byType)
                ShareList(title: "업데이트가 간 버전", shares: downloads.updatesByVersion, tint: .indigo)
                ShareList(title: "첫 다운로드 — 나라", shares: downloads.firstByTerritory, tint: .teal)
                ShareList(title: "첫 다운로드 — 어느 화면에서", shares: downloads.firstByPage, tint: .orange)
                ShareList(title: "첫 다운로드 — 기기", shares: downloads.firstByDevice, tint: .gray)
                ShareList(title: "OS 버전", shares: downloads.byPlatform, tint: .gray)
            }
            AnalyticsNote("\"페이지 없이\" 는 검색 결과 · 목록에서 제품 페이지를 열지 않고 바로 받은 것입니다. 업데이트 버전 몫이 새 버전이 얼마나 퍼졌는지예요.")
        }
    }
}

// MARK: - 스토어 행동

struct EngagementCard: View {
    let engagement: StoreAnalytics.Engagement

    var body: some View {
        Card(title: "스토어에서 한 일", systemImage: "hand.point.up.left") {
            FigureRow {
                Figure("노출", AnalyticsFormat.count(engagement.count("Impression")), note: "고유 기기")
                Figure("페이지 조회", AnalyticsFormat.count(engagement.count("Page view")), note: "고유 기기")
                Figure("탭", AnalyticsFormat.count(engagement.count("Tap")), note: "고유 기기")
            }
            ShareGrid {
                ShareList(title: "무엇을 눌렀나", shares: engagement.taps, tint: .orange)
                ShareList(title: "어느 페이지를 봤나", shares: engagement.pageViews, tint: .purple)
                ShareList(title: "노출 — 어디서", shares: engagement.impressionsBySource)
                ShareList(title: "노출 — 나라", shares: engagement.impressionsByTerritory, tint: .teal)
                ShareList(title: "노출 — 기기", shares: engagement.impressionsByDevice, tint: .gray)
            }
            AnalyticsNote("탭의 \"업데이트 · 열기\" 는 이미 가진 사람, \"받기 · 다시 받기\" 는 새로 받으려는 사람입니다. \"공유\" 는 스토어 페이지를 남에게 보낸 것이에요.")
        }
    }
}

// MARK: - 구매

struct PurchasesCard: View {
    let purchases: StoreAnalytics.Purchases

    var body: some View {
        Card(title: "구매", systemImage: "cart") {
            FigureRow {
                Figure("구매", AnalyticsFormat.count(purchases.purchases), note: "건")
                Figure("돈을 낸 사람", AnalyticsFormat.count(purchases.payingUsers))
                Figure("판매액", AnalyticsFormat.usd(purchases.sales), note: "USD")
                Figure("수익", AnalyticsFormat.usd(purchases.proceeds), note: "수수료 뺀 USD", tint: .green)
            }
            AnalyticsDayChart(points: purchases.daily,
                              first: ChartSeries("purchases", "구매", .blue),
                              second: ChartSeries("proceeds", "수익 USD", .green),
                              format: AnalyticsFormat.decimal)
            ShareGrid {
                ShareList(title: "상품 — 건수", shares: purchases.byProduct)
                ShareList(title: "상품 — 수익", shares: purchases.proceedsByProduct, tint: .green, format: AnalyticsFormat.usd)
                ShareList(title: "받고 얼마 만에 샀나", shares: purchases.purchaseAge, tint: .purple)
                ShareList(title: "나라 — 건수", shares: purchases.byTerritory, tint: .teal)
                ShareList(title: "나라 — 수익", shares: purchases.proceedsByTerritory, tint: .green, format: AnalyticsFormat.usd)
                ShareList(title: "결제 수단", shares: purchases.byPaymentMethod, tint: .gray)
                ShareList(title: "종류", shares: purchases.byType, tint: .gray)
                ShareList(title: "기기", shares: purchases.byDevice, tint: .gray)
            }
            AnalyticsNote("구매 건수에는 0원 구매(무료로 푼 상품 · 오퍼 코드 · 가족 공유)도 들어갑니다. 돈은 \"돈을 낸 사람\" 과 수익으로 보세요. 정산 금액은 판매 리포트(앱 내 구입 탭)가 맞습니다.")
        }
    }
}

// MARK: - 웹 미리보기

struct WebPreviewCard: View {
    let web: StoreAnalytics.WebPreview

    var body: some View {
        Card(title: "웹 미리보기 (apps.apple.com)", systemImage: "safari") {
            FigureRow {
                Figure("웹 페이지 조회", AnalyticsFormat.count(web.pageViews))
                Figure("웹에서 누름", AnalyticsFormat.count(web.taps.reduce(0) { $0 + $1.value }))
            }
            ShareGrid {
                ShareList(title: "무엇을 눌렀나", shares: web.taps, tint: .orange)
                ShareList(title: "브라우저", shares: web.byBrowser, tint: .gray)
                ShareList(title: "나라", shares: web.byTerritory, tint: .teal)
                ShareList(title: "기기", shares: web.byDevice, tint: .gray)
            }
            AnalyticsNote("앱 링크를 브라우저(주로 컴퓨터)에서 연 사람입니다. 여기서 바로 받을 수는 없어서, 많으면 링크를 건 곳에 QR · 휴대폰용 안내를 붙이는 게 좋아요.")
        }
    }
}

// MARK: - 설치 성능

struct InstallPerformanceCard: View {
    let performance: StoreAnalytics.InstallPerformance

    var body: some View {
        Card(title: "설치 성능", systemImage: "speedometer") {
            FigureRow {
                Figure("설치 시도", AnalyticsFormat.count(performance.attempts))
                Figure("실패", AnalyticsFormat.count(performance.failures), tint: performance.failures > 0 ? .orange : .primary)
                if let rate = performance.successRate { Figure("성공률", AnalyticsFormat.percent(rate)) }
                if let duration = performance.medianDuration { Figure("설치 시간", AnalyticsFormat.milliseconds(duration), note: "중앙값") }
            }
            ShareGrid {
                ShareList(title: "패키지별 설치 시간 (중앙값)", shares: performance.durationByPackage, tint: .indigo,
                          format: AnalyticsFormat.milliseconds, showsShare: false)
                ShareList(title: "실패한 OS", shares: performance.failuresByPlatform, tint: .orange)
                ShareList(title: "어디서 받은 설치", shares: performance.bySource, tint: .gray)
            }
        }
    }
}

// MARK: - 크래시

struct AnalyticsCrashesCard: View {
    let crashes: StoreAnalytics.Crashes

    var body: some View {
        Card(title: "크래시 (Apple 집계, 달마다)", systemImage: "bolt.trianglebadge.exclamationmark") {
            FigureRow {
                Figure("크래시", AnalyticsFormat.count(crashes.crashes), tint: crashes.crashes > 0 ? .red : .primary)
                Figure("겪은 기기", AnalyticsFormat.count(crashes.devices))
                if let month = crashes.months.last { Figure("달", String(month.prefix(7))) }
            }
            ShareGrid {
                ShareList(title: "버전", shares: crashes.byVersion, tint: .red)
                ShareList(title: "OS", shares: crashes.byPlatform, tint: .red)
                ShareList(title: "기기", shares: crashes.byDevice, tint: .gray)
            }
            AnalyticsNote("앱이 직접 보낸 진단(진단 탭)과 달리 Apple 이 기기에서 모은 수입니다. 공유에 동의한 기기만 세요.")
        }
    }
}

// MARK: - 설치 경로

struct PlatformInstallsCard: View {
    let platform: StoreAnalytics.PlatformInstalls

    var body: some View {
        Card(title: "설치 경로", systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
            FigureRow {
                Figure("설치", AnalyticsFormat.count(platform.installs))
            }
            ShareGrid {
                ShareList(title: "어디서 설치했나", shares: platform.byChannel)
                ShareList(title: "설치 종류", shares: platform.byType, tint: .green)
                ShareList(title: "OS", shares: platform.byPlatform, tint: .gray)
            }
            AnalyticsNote("App Store 밖(EU 의 다른 마켓 · 웹 배포)에서 설치하면 여기에 따로 잡힙니다.")
        }
    }
}
